import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/settings/settings_controller.dart';
import '../../core/utils/app_logger.dart';
import '../../data/services/native_video_controller.dart';
import 'video_player_controls.dart';

/// 播放区横向滑动快进/快退（右滑快进、左滑快退）：三个视频界面
/// （`PlayerScreen` / `ViewerScreen` / `GalleryPreviewScreen`）共用这一层。
///
/// 为什么用**原始指针事件**（`Listener`）而不是 `onHorizontalDrag*`：
/// ① `HitTestBehavior.opaque` 让**整个播放区**（含上下黑边、控制条缝隙）都能滑动；
/// ② 原始指针事件只按命中测试派发、不走手势竞技场 ⇒ 不会被上层 `PageView` /
///    `Slider` / 同层 `onTap` 抢走（症状就是"滑了完全没反应"）。
///
/// 一档 = 设置里的「快进/快退步长」，每 [videoSwipeSeekStepPx] 折算一档；
/// 拖动中只显示画面中央提示，**松手才跳一次**。
/// 背景与踩坑见 memory-bank `ISSUE-021` / `ADR-028`（修订）。
class VideoSwipeSeekLayer extends ConsumerStatefulWidget {
  const VideoSwipeSeekLayer({
    super.key,
    required this.controller,
    required this.itemId,
    required this.onSeek,
    required this.child,
  });

  /// 当前视频；未初始化时整段忽略滑动。
  final NativeVideoController? controller;

  /// 当前条目 id（只用于日志）。
  final String? itemId;

  /// 松手跳转：接各界面已有的 `_seekTo`。
  final Future<void> Function(Duration position) onSeek;

  /// 视频画面层（一般是 `NativeVideoViewport`）。
  final Widget child;

  @override
  ConsumerState<VideoSwipeSeekLayer> createState() =>
      _VideoSwipeSeekLayerState();
}

class _VideoSwipeSeekLayerState extends ConsumerState<VideoSwipeSeekLayer> {
  /// 判定"这次到底是横滑还是竖滑"的横向位移阈值（逻辑像素）。
  static const double _slop = 6;

  /// 本次滑动累计的横向位移（逻辑像素，右正左负）。
  double _px = 0;

  /// 累计位移折算出的档数（正 = 快进、负 = 快退，0 = 不显示提示）。
  int _steps = 0;

  /// 正在跟踪的手指（原始指针事件）。
  int? _pointer;

  /// 方向判定用的竖向累计位移（只用来区分"横滑"还是"竖滑"）。
  double _dy = 0;

  /// 本次滑动是否已确认为横向（未确认前不显示提示、不跳转）。
  bool _locked = false;

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
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    _dy += event.delta.dy;
    final px = _px + event.delta.dx;
    if (!_locked) {
      // 方向锁：横向位移还没过阈值时先不判定；竖向明显占优时才只跟踪、不接管
      // （用 < 而非 <=：水平和垂直位移相等时也视为横滑，更宽容）。
      if (px.abs() < _slop) return;
      if (px.abs() < _dy.abs()) return;
      _locked = true;
    }
    final steps = (px / videoSwipeSeekStepPx).round();
    if (px == _px && steps == _steps) return;
    setState(() {
      _px = px;
      _steps = steps;
    });
  }

  void _onPointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    final locked = _locked;
    final px = _px;
    final steps = _steps;
    _release();
    _logGesture(cancel: false, locked: locked, px: px, steps: steps);
    if (!locked) return;
    _commit(steps);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    final locked = _locked;
    final px = _px;
    final steps = _steps;
    _release();
    _logGesture(cancel: true, locked: locked, px: px, steps: steps);
  }

  /// 结束跟踪：清掉累计位移与中央提示（下一次滑动从零开始）。
  void _release() {
    _pointer = null;
    _dy = 0;
    _locked = false;
    if (_px == 0 && _steps == 0) return;
    setState(() {
      _px = 0;
      _steps = 0;
    });
  }

  /// 每次滑动结束写一行（不是每帧；点按/纯竖滑即 `px==0` 不写）：
  /// **日志里没有这一行**说明手势根本没到播放区（命中测试问题）；有这行但
  /// `horizontal=false` / `steps=0` 则是位移/方向判定问题（见 `ISSUE-021`）。
  void _logGesture({
    required bool cancel,
    required bool locked,
    required double px,
    required int steps,
  }) {
    if (px == 0) return;
    final value = widget.controller?.value;
    AppLogger.d(
      'VideoSwipeSeek',
      'Swipe seek gesture end: cancel=$cancel, horizontal=$locked, '
          'steps=$steps, px=${px.toStringAsFixed(1)}, '
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

  /// 横向滑动提示（`_steps == 0` 时为空）。
  Widget _overlay(NativeVideoValue value) {
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