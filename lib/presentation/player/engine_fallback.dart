import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/settings/settings_controller.dart';
import '../../core/utils/app_logger.dart';
import '../../domain/enums.dart';

/// 传给平台通道 `playerEngine` 参数的两个取值
/// （`NativeVideoController.create(..., playerEngine: ...)`）。
const String kExoPlayerEngine = 'exoPlayer';
const String kVlcEngine = 'vlc';

/// 三个视频入口（`PlayerScreen` / `ViewerScreen` / `GalleryPreviewScreen`）
/// 共用的「引擎选择 + 加载看门狗 + 单次引擎回退」。
///
/// WHY THIS FILE EXISTS
/// 每个入口都必须做同样三件事，漏掉任何一件的后果都是"永远转圈 / 永远黑屏"：
///   1. 引擎**必须**经 [engineFor] 取（不要再裸读 `settings.playerEngine`），
///      否则"某个文件在 VLC 下拿不到画面"这条回退永远生效不了；
///   2. 加载后**必须** [armLoadWatchdog]（15s），否则没有自愈时机；
///   3. 超时且在 VLC 下 ⇒ [fallbackToDefaultEngineIfPossible]：把这个 item 记进
///      回退集合、用默认引擎重建一次；再失败就交给调用方显示错误态。
///
/// 为什么第一次超时就直接换引擎、而不是"同引擎再试一次"：
/// VLC 侧没有 ExoPlayer 那样的 frameWatchdog / reattachSurface 自愈（surface 丢了
/// 就一直是黑屏，只能重建整个播放器），而且同一份文件在同一个引擎下重试大概率
/// 还是同样的结果 —— 直接换引擎才可能真的出画面。
///
/// 背景/证据：`docs/HANDOFF-VLC播放黑屏根因.md`、`memory-bank/decisions.md` ADR-011。
mixin VideoEngineFallbackState<T extends ConsumerStatefulWidget>
    on ConsumerState<T> {
  /// 在 VLC 下拿不到画面的 item：本屏会话内改用默认引擎。
  final Set<String> _engineFallbackItemIds = <String>{};

  /// 已经用掉「换引擎重试」额度的 item：每个 item 只换一次，避免来回重建播放器。
  final Set<String> _engineFallbackUsedItemIds = <String>{};

  Timer? _loadWatchdog;

  /// 传给平台通道的 `playerEngine` 参数：`'vlc'` 或 `'exoPlayer'`。
  ///
  /// 用户选了 VLC、但这个视频在 VLC 下已经确认拿不到帧时，本屏会话内对**这一个**
  /// 视频改用默认引擎，而不是反复把用户扔回黑屏。
  String engineFor(String itemId) {
    final configured = ref.read(settingsControllerProvider).playerEngine;
    if (configured != PlayerEngine.vlc) return kExoPlayerEngine;
    if (_engineFallbackItemIds.contains(itemId)) return kExoPlayerEngine;
    return kVlcEngine;
  }

  /// 该 item 是否还有"换引擎重试"的额度。
  bool engineFallbackAvailable(String itemId) =>
      !_engineFallbackUsedItemIds.contains(itemId) &&
      !_engineFallbackItemIds.contains(itemId);

  /// 用掉额度：之后 [engineFor] 对该 item 返回 [kExoPlayerEngine]。
  void useEngineFallback(String itemId) {
    _engineFallbackUsedItemIds.add(itemId);
    _engineFallbackItemIds.add(itemId);
  }

  /// 挂加载看门狗（默认 15s）。重复调用会替换上一个：同一时刻只跟一个加载。
  ///
  /// [onTimeout] 必须自己用请求序号/当前 item 判新旧
  /// （见各屏的 `_videoRequest` / `_loadRequest`），否则旧加载会覆盖新状态。
  void armLoadWatchdog(
    String itemId, {
    required Future<void> Function(String itemId) onTimeout,
    Duration timeout = const Duration(seconds: 15),
  }) {
    cancelLoadWatchdog();
    _loadWatchdog = Timer(timeout, () {
      _loadWatchdog = null;
      if (!mounted) return;
      unawaited(onTimeout(itemId));
    });
  }

  void cancelLoadWatchdog() {
    _loadWatchdog?.cancel();
    _loadWatchdog = null;
  }

  /// 看门狗是否还在等待（诊断日志用：它是"这个加载是否仍在进行"最直接的信号，
  /// `player_screen.dart` 的 spinner 诊断行就打印它）。
  bool get isLoadWatchdogArmed => _loadWatchdog != null;

  /// 看门狗超时后的统一处置：
  /// 当前引擎还是 VLC 且没用过额度 ⇒ 记回退 + 用 [reload] 重建，返回 `true`；
  /// 否则返回 `false`（调用方应进入可见的错误态，而不是继续转圈）。
  ///
  /// [reload] 由调用方提供，负责"销毁旧 controller + 重新走一遍加载"，
  /// 并且必须让旧的请求序号失效（通常重新调用入口自己的 `_syncVideo()` /
  /// `_loadCurrent()` 即可，它们内部会递增序号）。
  Future<bool> fallbackToDefaultEngineIfPossible(
    String itemId, {
    required Future<void> Function() reload,
  }) async {
    if (engineFor(itemId) != kVlcEngine) return false;
    if (!engineFallbackAvailable(itemId)) return false;
    useEngineFallback(itemId);
    AppLogger.w(
      'VideoEngineFallback',
      'VLC produced no frame within 15s, retrying with $kExoPlayerEngine: '
      '$itemId',
    );
    await reload();
    return true;
  }

  @override
  void dispose() {
    cancelLoadWatchdog();
    super.dispose();
  }
}
