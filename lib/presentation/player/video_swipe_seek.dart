import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/settings/settings_controller.dart';
import '../../core/utils/app_logger.dart';
import '../../data/services/native_video_controller.dart';
import 'video_player_controls.dart';

/// 播放区手势层：横向滑动快进/快退 + 竖向滑动调音量，三个视频界面
/// （`PlayerScreen` / `ViewerScreen` / `GalleryPreviewScreen`）共用。
///
/// 为什么用**原始指针事件**（`Listener`）而不是 `onHorizontalDrag*`：
/// ① `HitTestBehavior.opaque` 让**整个播放区**（含上下黑边、控制条缝隙）都能滑动；
/// ② 原始指针事件只按命中测试派发、不走手势竞技场 ⇒ 不会被上层 `PageView` /
///    `Slider` / 同层 `onTap` 抢走（症状就是"滑了完全没反应"）。
///
/// 横向：一档 = 设置里的「快进/快退步长」，每 [videoSwipeSeekStepPx] 折算一档；
/// 拖动中只显示画面中央提示，**松手才跳一次**。
/// 竖向：上滑增大音量、下滑减小音量，直接改**播放器自身音量**
/// （`NativeVideoController.setVolume`，与静音开关同一个口径），
/// 整屏高度约对应 [_volumeFullScreenFraction] 的音量行程。
///
/// 背景与踩坑见 memory-bank `ISSUE-021` / `ADR-028`（修订）与新条目
/// `ADR-054`（音量手势并入同一层）。
class VideoSwipeSeekLayer extends ConsumerStatefulWidget {
  const VideoSwipeSeekLayer({
    super.key,
    required this.controller,
    required this.itemId,
    required this.onSeek,
    required this.child,
    this.onVolumeChanged,
  });

  /// 当前视频；未初始化时整段忽略滑动。
  final NativeVideoController? controller;

  /// 当前条目 id（只用于日志）。
  final String? itemId;

  /// 松手跳转：接各界面已有的 `_seekTo`。
  final Future<void> Function(Duration position) onSeek;

  /// 手势把播放器音量改成 [volume]（0~1）之后回调，用于让界面的静音开关
  /// 保持同一口径（音量降到 0 ⇒ 显示为静音）。
  final ValueChanged<double>? onVolumeChanged;

  /// 视频画面层（一般是 `NativeVideoViewport`）。
  final Widget child;

  @override
  ConsumerState<VideoSwipeSeekLayer> createState() =>
      _VideoSwipeSeekLayerState();
}

class _VideoSwipeSeekLayerState extends ConsumerState<VideoSwipeSeekLayer> {
  /// 判定"这次到底是横滑还是竖滑"的横向位移阈值（逻辑像素）。
  static const double _slop = 2;

  /// 竖向滑动（调音量）的起步阈值：太小会误伤轻点/横滑。
  static const double _verticalSlop = 8;

  /// 竖向滑动走完整屏高度的多少比例 = 音量 0 → 1。
  static const double _volumeFullScreenFraction = 0.45;

  /// 音量行程的下限（逻辑像素），小窗口也能滑得动。
  static const double _volumeMinRangePx = 160;

  /// 本次滑动累计的横向位移（逻辑像素，右正左负）。
  double _px = 0;

  /// 累计位移折算出的档数（正 = 快进、负 = 快退，0 = 不显示提示）。
  int _steps = 0;

  /// 正在跟踪的手指（原始指针事件）。
  int? _pointer;

  /// 方向判定用的竖向累计位移（正 = 下滑、负 = 上滑）。
  double _dy = 0;

  /// 本次滑动是否已确认为横向（未确认前不显示提示、不跳转）。
  bool _locked = false;

  /// 本次滑动是否已确认为竖向（调音量）。
  bool _vertical = false;

  /// 竖向滑动开始时的播放器音量（0~1）。
  double _volumeStart = 1;

  /// 当前手势设定的音量（0~1），用于中央提示。
  double _volume = 1;

  /// 一整段音量行程对应的像素数（锁定竖向时按屏幕高度算一次）。
  double _volumeRangePx = _volumeMinRangePx;

  /// 上一次真正下发给原生播放器的音量（百分比取整），避免每帧都过通道。
  int _volumeSentPercent = -1;

  int get _stepSeconds =>
      ref.read(settingsControllerProvider).playerSeekSeconds;

  bool get _ready {
    final value = widget.controller?.value;
    return value != null && value.isInitialized;
  }

  /// [steps] 档跳转后的目标位置，按视频长度裁剪到 `0 ~ duration`。
  Duration _target(NativeVideoValue value, int steps) {
    final durationMs = value.duration.inMilliseconds;
    final rawMs = value.position.inMilliseconds +
        steps * _stepSeconds * Duration.millisecondsPerSecond;
    if (durationMs <= 0) {
      // 长度还没探到时给一个未裁剪的目标用于提示；真正跳转会被 `_commit` 跳过
      // （否则会跳到错误位置）。
      return Duration(milliseconds: rawMs < 0 ? 0 : rawMs);
    }
    return Duration(milliseconds: rawMs.clamp(0, durationMs));
  }

  void _onPointerDown(PointerDownEvent event) {
    // 只跟第一根手指：第二根手指落下时忽略。
    if (_pointer != null || !_ready) return;
    _pointer = event.pointer;
    _dy = 0;
    _locked = false;
    _vertical = false;
    _volumeSentPercent = -1;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _dy += event.delta.dy;
    final px = _px + event.delta.dx;
    if (!_locked && !_vertical) {
      final ax = px.abs();
      final ay = _dy.abs();
      if (ax < _slop && ay < _verticalSlop) return;
      if (ax >= _slop && ax * 5 >= ay) {
        // 横向占优（竖向需达横向 5 倍才让位，日常横滑即使略有倾斜也能触发）。
        _locked = true;
      } else if (ay >= _verticalSlop && ay > ax * 2) {
        _startVertical();
      } else {
        return;
      }
    }
    if (_vertical) {
      _applyVertical(_dy);
      return;
    }
    final steps = (px / videoSwipeSeekStepPx).round();
    if (px == _px && steps == _steps) return;
    setState(() {
      _px = px;
      _steps = steps;
    });
  }

  /// 锁定本次滑动为"调音量"：记录起点音量与整段行程像素数。
  void _startVertical() {
    final start = (widget.controller?.value.volume ?? 1).clamp(0.0, 1.0);
    final range = MediaQuery.sizeOf(context).height * _volumeFullScreenFraction;
    _vertical = true;
    _volumeStart = start;
    _volume = start;
    _volumeRangePx = range < _volumeMinRangePx ? _volumeMinRangePx : range;
    _volumeSentPercent = (start * 100).round();
    setState(() {});
  }

  /// 竖向累计位移 → 音量（上滑 = 负 dy = 变大）。
  void _applyVertical(double dy) {
    final volume = (_volumeStart - dy / _volumeRangePx).clamp(0.0, 1.0);
    final percent = (volume * 100).round();
    if (percent == _volumeSentPercent) return;
    _volumeSentPercent = percent;
    _volume = volume;
    unawaited(widget.controller?.setVolume(volume) ?? Future<void>.value());
    widget.onVolumeChanged?.call(volume);
    setState(() {});
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    final locked = _locked;
    final vertical = _vertical;
    final px = _px;
    final steps = _steps;
    final volume = _volume;
    _release();
    _logGesture(
      cancel: false,
      locked: locked,
      vertical: vertical,
      px: px,
      steps: steps,
      volume: volume,
    );
    if (!locked) return;
    _commit(steps);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    final locked = _locked;
    final vertical = _vertical;
    final px = _px;
    final steps = _steps;
    final volume = _volume;
    _release();
    _logGesture(
      cancel: true,
      locked: locked,
      vertical: vertical,
      px: px,
      steps: steps,
      volume: volume,
    );
  }

  /// 结束跟踪：清掉累计位移/音量提示（下一次滑动从零开始）。
  void _release() {
    _pointer = null;
    _dy = 0;
    _locked = false;
    final hadOverlay = _vertical || _px != 0 || _steps != 0;
    _vertical = false;
    _volumeSentPercent = -1;
    if (!hadOverlay) return;
    setState(() {
      _px = 0;
      _steps = 0;
    });
  }

  /// 每次滑动结束写一行（不是每帧；点按即 `px==0 && !vertical` 不写）：
  /// **日志里没有这一行**说明手势根本没到播放区（命中测试问题）；有这行但
  /// `horizontal=false` / `steps=0` 则是位移/方向判定问题（见 `ISSUE-021`）。
  void _logGesture({
    required bool cancel,
    required bool locked,
    required bool vertical,
    required double px,
    required int steps,
    required double volume,
  }) {
    if (px == 0 && !vertical) return;
    final value = widget.controller?.value;
    AppLogger.d(
      'VideoSwipeSeek',
      'Swipe gesture end: cancel=$cancel, horizontal=$locked, '
          'vertical=$vertical, steps=$steps, px=${px.toStringAsFixed(1)}, '
          'volume=${(volume * 100).round()}%, '
          'item=${widget.itemId ?? '-'}, '
          'initialized=${value?.isInitialized}, '
          'duration=${value?.duration.inMilliseconds ?? -1}ms',
    );
  }

  /// 松手：按滑出的档数跳一次（0 档 / 引擎就绪前 / 长度未知都不跳）。
  void _commit(int steps) {
    final value = widget.controller?.value;
    if (steps == 0 || value == null || !value.isInitialized) return;
    if (value.duration <= Duration.zero) {
      AppLogger.w(
        'VideoSwipeSeek',
        'Swipe seek skipped: duration unknown for ${widget.itemId ?? '-'}',
      );
      return;
    }
    final target = _target(value, steps);
    AppLogger.i(
      'VideoSwipeSeek',
      'Swipe seek: item=${widget.itemId ?? '-'}, steps=$steps '
          '(${_stepSeconds}s each), '
          'from=${value.position.inMilliseconds}ms '
          'to=${target.inMilliseconds}ms',
    );
    unawaited(widget.onSeek(target));
  }

  /// 滑动提示：调音量时显示音量条，横滑时显示快进/快退提示（都没有则为空）。
  Widget _overlay(NativeVideoValue value) {
    if (_vertical) return VideoVolumeIndicator(volume: _volume);
    final steps = _steps;
    if (steps == 0) return const SizedBox.shrink();
    final target = _target(value, steps);
    return VideoSwipeSeekIndicator(
      delta: target - value.position,
      position: target,
      duration: value.duration,
    );
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.controller?.value;
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          IgnorePointer(
            child: Center(
              child: value == null ? const SizedBox.shrink() : _overlay(value),
            ),
          ),
        ],
      ),
    );
  }
}
