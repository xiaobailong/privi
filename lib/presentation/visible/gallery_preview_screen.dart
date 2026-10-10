import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../application/providers.dart';
import '../../application/settings/settings_controller.dart';
import '../../core/l10n.dart';
import '../../core/utils/app_logger.dart';
import '../../data/services/gallery_service.dart';
import '../../data/services/native_video_controller.dart';
import '../../data/services/video_resume_service.dart';
import '../common/keep_vault_unlocked.dart';
import '../common/zoomable_media_image.dart';
import '../player/engine_fallback.dart';
import '../player/video_player_controls.dart';
import '../player/video_player_surface.dart';
import '../player/video_swipe_seek.dart';

typedef GalleryAssetFileResolver = Future<File?> Function(GalleryAsset asset);

Future<File?> resolveGalleryAssetFile(GalleryAsset asset) async {
  final entity = await AssetEntity.fromId(asset.id);
  return entity?.file;
}

/// Fullscreen preview for a Visible-tab gallery asset (tap to open).
class GalleryPreviewScreen extends ConsumerStatefulWidget {
  const GalleryPreviewScreen({
    super.key,
    required this.items,
    required this.initialIndex,
    this.resolveFile = resolveGalleryAssetFile,
    this.initialForcedEngine,
  }) : assert(items.length > 0);

  final List<GalleryAsset> items;
  final int initialIndex;
  final GalleryAssetFileResolver resolveFile;

  /// 长按菜单选了「内部播放（VLC 引擎）」时传进来的引擎（`'vlc'`）。
  ///
  /// 只作用于 [initialIndex] 这一条（见
  /// [VideoEngineFallbackState.forceEngineForItem]）：滑到别的视频仍按设置走。
  final String? initialForcedEngine;

  @override
  ConsumerState<GalleryPreviewScreen> createState() =>
      _GalleryPreviewScreenState();
}

class _GalleryPreviewScreenState extends ConsumerState<GalleryPreviewScreen>
    with VideoEngineFallbackState<GalleryPreviewScreen> {
  late final PageController _page;
  NativeVideoController? _video;
  File? _file;
  String? _error;
  String? _completedForId;
  bool _loading = true;
  bool _chrome = true;
  bool _imageZoomed = false;
  late int _index;
  int _loadRequest = 0;

  /// 「播完后重播」要落到的起点（毫秒）。一次性：`_loadCurrentBody` 读走即清空
  /// （见 [ISSUE-022] / `memory-bank/issues-solved.md`）。
  int? _pendingStartMs;

  /// 已经因为"起播竞态"自动重建过的 item（同一界面内只救一次，见 `ISSUE-023`）。
  final Set<String> _spuriousRecoveredIds = <String>{};

  bool _programmaticPopAllowed = false;
  bool _muted = false;
  bool _looping = false;
  double _playbackSpeed = 1;
  VideoFitMode _fitMode = VideoFitMode.fit;
  bool? _lastImmersive;
  String? _orientationLockedItemId;
  bool _orientationOverridden = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.items.length - 1);
    _page = PageController(initialPage: _index);
    // 长按菜单指定的引擎：只钉住用户选中的这一条，别的 asset 仍按设置走。
    final forcedEngine = widget.initialForcedEngine;
    if (forcedEngine != null) {
      forceEngineForItem(_current.id, forcedEngine);
    }
    _playbackSpeed = ref.read(settingsControllerProvider).playerPlaybackSpeed;
    unawaited(VideoSystemUi.apply(false));
    _loadCurrent();
  }

  GalleryAsset get _current => widget.items[_index];
  bool get _hasPrevious => _index > 0;
  bool get _hasNext => _index < widget.items.length - 1;

  Future<void> _loadCurrent() {
    final request = ++_loadRequest;
    return _loadCurrentBody(request);
  }

  Future<void> _loadCurrentBody(int request) async {
    if (!mounted || request != _loadRequest) return;
    await _stopVideo();
    if (!mounted || request != _loadRequest) return;
    setState(() {
      _loading = true;
      _error = null;
      _file = null;
    });
    try {
      final item = _current;
      final file = await widget.resolveFile(item);
      if (!mounted || request != _loadRequest) return;
      if (file == null || !await file.exists()) {
        setState(() {
          _error = 'Could not open file';
          _loading = false;
        });
        return;
      }
      if (item.isVideo) {
        // 引擎必须经 engineFor() 取：VLC 下拿不到帧的 asset 会在这里被换成默认引擎。
        final engine = engineFor(item.id);
        final c = await NativeVideoController.create(
          file.path,
          playerEngine: engine,
        );
        if (!mounted || request != _loadRequest) {
          await c.dispose();
          return;
        }
        await c.setLooping(_looping);
        await c.setVolume(_muted ? 0 : 1);
        await c.setPlaybackSpeed(_playbackSpeed);

        final pendingStartMs = _pendingStartMs;
        _pendingStartMs = null;
        final savedMs = pendingStartMs ??
            VideoResumeService.getPositionMs(
              ref.read(sharedPreferencesProvider),
              item.id,
            );
        if (savedMs != null && savedMs > 0) {
          AppLogger.i(
            'GalleryPreviewScreen',
            'Restoring resume position: item=${item.id}, saved=${savedMs}ms',
          );
          await c.seekTo(Duration(milliseconds: savedMs));
        } else {
          await c.seekTo(Duration.zero);
        }
        await c.play();
        if (!mounted || request != _loadRequest) {
          await c.dispose();
          return;
        }
        c.onCompleted = () {
          if (!mounted) return;
          _onNativeVideoEnded(item.id);
        };
        // 起播竞态（原始 input 刚起来就报结束）另走一条路：重建播放器继续播，
        // 而不是把进度条丢在结尾（见 `ISSUE-023`）。
        c.onSpuriousCompletion = () => _onSpuriousCompletion(item, c);
        setState(() {
          _video = c;
          _file = file;
          _loading = false;
          _completedForId = null;
        });
        // 兜底：15s 还没 ready 就「换引擎 → 错误态」，否则这里会永远 _loading=true
        //（历史问题：无看门狗、无引擎回退）。
        armLoadWatchdog(
          item.id,
          onTimeout: (id) => _retryVideoLoad(item, request),
        );
      } else {
        if (!mounted || request != _loadRequest) return;
        _clearOrientationLock();
        setState(() {
          _file = file;
          _loading = false;
        });
      }
    } catch (e) {
      if (!mounted || request != _loadRequest) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// 15s 看门狗超时后的处置：先试「换回默认引擎重建一次」，再失败就落到已有的
  /// `_error` 状态（原来是静默卡死：`_loading` 永远为 true）。
  ///
  /// 请求序号校验必须带上：重试是异步的，中途用户可能已经滑到别的 asset。
  Future<void> _retryVideoLoad(GalleryAsset item, int request) async {
    if (!mounted) return;
    if (request != _loadRequest || _current.id != item.id) return;
    final video = _video;
    if (video != null && (video.value.isInitialized || video.value.hasError)) {
      return;
    }

    final retried = await fallbackToDefaultEngineIfPossible(
      item.id,
      reload: () async {
        if (!mounted) return;
        await _stopVideo();
        if (!mounted) return;
        await _loadCurrent();
      },
    );
    if (retried) return;

    AppLogger.e(
      'GalleryPreviewScreen',
      'Video did not start within 15s, giving up '
      '(engine=${engineFor(item.id)}): ${item.id}',
    );
    await _stopVideo();
    if (!mounted) return;
    setState(() {
      _error = 'Video failed to start: ${item.title}';
      _loading = false;
    });
  }

  Future<void> _showItem(int index) async {
    if (index < 0 || index >= widget.items.length || index == _index) return;
    if (!mounted) return;
    if (!_page.hasClients) {
      setState(() => _index = index);
      await _loadCurrent();
      return;
    }
    try {
      await _page.animateToPage(
        index,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {
      if (!mounted || !_page.hasClients) return;
      _page.jumpToPage(index);
    }
  }

  Future<void> _onPageChanged(int index) async {
    if (index == _index) return;
    setState(() {
      _index = index;
      _imageZoomed = false;
    });
    await _loadCurrent();
  }

  /// 单击打开的视频播完后**停在最后一帧，不自动切下一个**（`ADR-032`）。
  ///
  /// 想继续看由用户自己操作：「下一个」按钮 / 左右滑 / 拖进度条重播。
  /// 播放列表页（`PlayerScreen`，从「播放」入口进的那个）仍然连播，不受这里影响。
  void _onNativeVideoEnded(String itemId) {
    if (!mounted) return;
    AppLogger.i(
      'GalleryPreviewScreen',
      'Video ended, staying on this item (no auto-advance): $itemId',
    );
    _completedForId = itemId;
    // 停在最后一帧时把控制条显示出来，否则用户只看到一张静止画面、无从下手
    // （`AutoHideVideoControls` 的定时器之后会再把它收起来）。
    if (!_chrome) setState(() => _chrome = true);
  }

  /// 原生侧**刚起播**就报"播完"（起播竞态，见 `ISSUE-023`）：这不是真的播完。
  ///
  /// 直接重建播放器并从已知位置（`video.value.position`，也就是续播目标/0）
  /// 继续，否则用户看到的就是"进度条停在结尾、视频也不播"。
  ///
  /// 同一个 item 只自动救一次：真是坏文件（起播即结束）时第二次起按"播完"处理，
  /// 避免无限重建。
  void _onSpuriousCompletion(GalleryAsset item, NativeVideoController video) {
    if (!mounted || _current.id != item.id) return;
    final pos = video.value.position;
    if (!_spuriousRecoveredIds.add(item.id)) {
      AppLogger.w(
        'GalleryPreviewScreen',
        'Spurious end repeated for ${item.id}: accepting it as finished',
      );
      video.giveUpOnStartupGlitch();
      _onNativeVideoEnded(item.id);
      return;
    }
    AppLogger.w(
      'GalleryPreviewScreen',
      'Spurious end right after start (${pos.inMilliseconds}ms): recreating '
      'the player and continuing from there, item=${item.id}',
    );
    unawaited(_replayFromPosition(pos));
  }

  Future<void> _stopVideo() async {
    final c = _video;
    _video = null;
    _completedForId = null;
    if (c != null) {
      final pos = c.value.position.inMilliseconds;
      final dur = c.value.duration.inMilliseconds;
      final id = _current.id;
      if (pos > 0 && dur > 0) {
        await VideoResumeService.savePositionMs(
          ref.read(sharedPreferencesProvider),
          id,
          pos,
          dur,
        );
        AppLogger.d(
          'GalleryPreviewScreen',
          'Saved resume position (stop): item=$id, pos=${pos}ms, dur=${dur}ms',
        );
      }
      await c.dispose();
    }
  }

  @override
  void dispose() {
    _loadRequest++;
    final c = _video;
    _video = null;
    _completedForId = null;
    if (c != null) {
      final pos = c.value.position.inMilliseconds;
      final dur = c.value.duration.inMilliseconds;
      final id = _current.id;
      if (pos > 0 && dur > 0) {
        VideoResumeService.savePositionMs(
          ref.read(sharedPreferencesProvider),
          id,
          pos,
          dur,
        );
        AppLogger.d(
          'GalleryPreviewScreen',
          'Saved resume position (dispose): item=$id, pos=${pos}ms, dur=${dur}ms',
        );
      }
      c.dispose();
    }
    unawaited(VideoSystemUi.restore());
    _page.dispose();
    super.dispose();
  }

  bool _isLandscape(BuildContext context) =>
      MediaQuery.orientationOf(context) == Orientation.landscape;

  void _syncSystemUi(bool immersive) {
    if (_lastImmersive == immersive) return;
    _lastImmersive = immersive;
    unawaited(VideoSystemUi.apply(immersive));
  }

  Future<void> _toggleOrientation(BuildContext context) async {
    _orientationOverridden = true;
    await VideoSystemUi.toggle(_isLandscape(context));
  }

  void _maybeLockOrientationToVideo() {
    final video = _video;
    final itemId = _current.id;
    if (video == null || !video.value.isInitialized) return;
    if (_orientationLockedItemId == itemId) return;
    _orientationLockedItemId = itemId;
    _orientationOverridden = false;
    unawaited(VideoSystemUi.lockToVideoSize(video.value.size));
  }

  void _clearOrientationLock() {
    if (_orientationLockedItemId == null && !_orientationOverridden) return;
    _orientationLockedItemId = null;
    _orientationOverridden = false;
    unawaited(VideoSystemUi.unlockOrientations());
  }

  Future<void> _chooseFit() async {
    final selected = await showVideoFitModeSheet(context, current: _fitMode);
    if (selected != null && mounted) setState(() => _fitMode = selected);
  }

  void _setPlaybackSpeed(double speed) {
    setState(() => _playbackSpeed = speed);
    unawaited(
      ref
          .read(settingsControllerProvider.notifier)
          .setPlayerPlaybackSpeed(speed),
    );
    final video = _video;
    if (video != null) unawaited(video.setPlaybackSpeed(speed));
  }

  void _setMuted(bool muted) {
    setState(() => _muted = muted);
    final video = _video;
    if (video != null) unawaited(video.setVolume(muted ? 0 : 1));
  }

  void _setLooping(bool looping) {
    setState(() => _looping = looping);
    final video = _video;
    if (video != null) unawaited(video.setLooping(looping));
  }

  void _togglePlayPause() {
    final video = _video;
    if (video == null) return;
    if (video.value.isPlaying) {
      unawaited(video.pause());
      return;
    }
    unawaited(_playFromCurrentPosition(video));
  }

  Future<void> _playFromCurrentPosition(NativeVideoController video) async {
    final value = video.value;
    if (video.mediaEnded ||
        value.isCompleted ||
        (value.duration > Duration.zero && value.position >= value.duration)) {
      // 已经播到结尾：必须**重建**原生播放器，seek/play 都唤不醒一个结束了的
      // input（`ISSUE-022`）。位置还在结尾之前时（用户先把进度条拖回来再按
      // 播放）就从那儿继续，否则从头重播。
      final from = value.duration > Duration.zero &&
              value.position < value.duration
          ? value.position
          : Duration.zero;
      await _replayFromPosition(from);
      return;
    }
    await video.play();
    await video.setPlaybackSpeed(_playbackSpeed);
  }

  /// 重建原生播放器并从 [position] 起播 —— 「播完后重播」唯一可行的路径。
  ///
  /// 不重建的话，原生播放器会停在最后一帧：libVLC 结束的 input 上 `seekTo` +
  /// `play()` 不产生 `Playing` 事件（日志里 `play: textureId=2` 之后什么都没有、
  /// `getStatus` 一直 `isPlaying=false`），这一点已由真机日志确认（`ISSUE-022`）。
  Future<void> _replayFromPosition(Duration position) async {
    AppLogger.i(
      'GalleryPreviewScreen',
      'Replaying finished video from ${position.inMilliseconds}ms '
      '(recreating native player): ${_current.id}',
    );
    _completedForId = _current.id;
    // 起点显式传给重建后的加载流程（不能只靠进度条上的位置：那是**旧**播放器
    // 的状态，重建后归零）。
    _pendingStartMs = position.inMilliseconds;
    await _loadCurrent();
  }

  Future<void> _seekTo(Duration position) async {
    final video = _video;
    if (video == null) return;
    // 播完之后拖进度条 / 滑动快进：原生 input 已经结束，直接 seek 不会起播，
    // 用户看到的就是「拖回开头 → 不播、进度条还弹回结尾」。
    // 这里改成重建播放器并从目标位置起播（见 `ISSUE-022`）。
    if (video.mediaEnded && position < video.value.duration) {
      await _replayFromPosition(position);
      return;
    }
    await video.seekTo(position);
  }

  Future<void> _openSettings() async {
    final settings = ref.read(settingsControllerProvider);
    await showVideoSettingsSheet(
      context,
      seekSeconds: settings.playerSeekSeconds,
      onSeekSecondsChanged: (seconds) => unawaited(
        ref
            .read(settingsControllerProvider.notifier)
            .setPlayerSeekSeconds(seconds),
      ),
      playbackSpeed: _playbackSpeed,
      onPlaybackSpeedChanged: _setPlaybackSpeed,
      muted: _muted,
      onMutedChanged: _setMuted,
      looping: _looping,
      onLoopingChanged: _setLooping,
    );
  }

  void _toggleChrome() => setState(() => _chrome = !_chrome);

  void _hideChrome() {
    if (_chrome) setState(() => _chrome = false);
  }

  void _exit() {
    final video = _video;
    if (video != null) unawaited(video.pause());
    setState(() => _programmaticPopAllowed = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final landscape = _isLandscape(context);
    final immersive = landscape && _current.isVideo;
    _syncSystemUi(immersive);
    if (_current.isVideo && _video != null && _video!.value.isInitialized) {
      _maybeLockOrientationToVideo();
    }
    return KeepVaultUnlocked(
      child: PopScope(
        canPop: _current.isVideo || !_chrome || _programmaticPopAllowed,
        onPopInvokedWithResult: (didPop, _) async {
          if (!didPop) {
            if (mounted && _chrome) setState(() => _chrome = false);
            return;
          }
          await _stopVideo();
        },
        child: AutoHideVideoControls(
          enabled: _current.isVideo,
          visible: _chrome,
          onHide: _hideChrome,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  key: const Key('folder-media-page-view'),
                  controller: _page,
                  itemCount: widget.items.length,
                  physics: _current.isVideo || _imageZoomed
                      ? const NeverScrollableScrollPhysics()
                      : const PageScrollPhysics(),
                  onPageChanged: (index) => unawaited(_onPageChanged(index)),
                  itemBuilder: (context, index) =>
                      _pageContent(index == _index),
                ),
                if (_chrome) _topBar(),
                if (_chrome &&
                    _current.isVideo &&
                    _video != null &&
                    _video!.value.isInitialized)
                  _videoBottomBar(landscape)
                else if (_chrome && !_current.isVideo)
                  _imageBottomBar(landscape),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pageContent(bool active) {
    if (!active) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }
    final video = _video;
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      );
    }
    if (_error != null) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleChrome,
        child: Center(
          child: Text(_error!, style: const TextStyle(color: Colors.white70)),
        ),
      );
    }
    if (_current.isVideo && video != null && video.value.isInitialized) {
      return GestureDetector(
        onTap: _toggleChrome,
        // 播放区横向滑动：右滑快进 / 左滑快退（与播放列表页、查看器共用同一实现）。
        child: VideoSwipeSeekLayer(
          controller: video,
          itemId: _current.id,
          onSeek: _seekTo,
          child: NativeVideoViewport(controller: video, fitMode: _fitMode),
        ),
      );
    }
    if (_file != null && !_current.isVideo) {
      return ZoomableMediaImage(
        file: _file!,
        onTap: _toggleChrome,
        onZoomChanged: (zoomed) {
          if (_imageZoomed == zoomed) return;
          setState(() => _imageZoomed = zoomed);
        },
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleChrome,
      child: const SizedBox.expand(),
    );
  }

  Widget _topBar() {
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: Material(
          color: Colors.black54,
          child: SizedBox(
            height: kToolbarHeight,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: _exit,
                ),
                Expanded(
                  child: Text(
                    _current.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                Text(
                  '${_index + 1}/${widget.items.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(width: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _videoBottomBar(bool landscape) {
    final video = _video!;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ValueListenableBuilder<NativeVideoValue>(
        valueListenable: video,
        builder: (context, value, _) => NativeVideoBottomControls(
          value: value,
          landscape: landscape,
          fitMode: _fitMode,
          hasPrevious: _hasPrevious,
          hasNext: _hasNext,
          onPrevious: () => unawaited(_showItem(_index - 1)),
          onSeek: _seekTo,
          onPlayPause: _togglePlayPause,
          onNext: () => unawaited(_showItem(_index + 1)),
          onToggleOrientation: () => unawaited(_toggleOrientation(context)),
          onChooseFit: () => unawaited(_chooseFit()),
          onOpenSettings: () => unawaited(_openSettings()),
        ),
      ),
    );
  }

  Widget _imageBottomBar(bool landscape) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Material(
          color: Colors.black54,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  tooltip: context.l10n.previousMedia,
                  color: Colors.white,
                  onPressed: _hasPrevious
                      ? () => unawaited(_showItem(_index - 1))
                      : null,
                  icon: const Icon(Icons.skip_previous),
                ),
                IconButton(
                  tooltip: landscape
                      ? context.l10n.portrait
                      : context.l10n.landscape,
                  color: Colors.white,
                  onPressed: () => unawaited(_toggleOrientation(context)),
                  icon: Icon(
                    landscape
                        ? Icons.stay_current_portrait
                        : Icons.stay_current_landscape,
                  ),
                ),
                IconButton(
                  tooltip: context.l10n.nextMedia,
                  color: Colors.white,
                  onPressed:
                      _hasNext ? () => unawaited(_showItem(_index + 1)) : null,
                  icon: const Icon(Icons.skip_next),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}