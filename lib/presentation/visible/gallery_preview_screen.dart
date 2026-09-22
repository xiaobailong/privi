import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../application/settings/settings_controller.dart';
import '../../core/l10n.dart';
import '../../core/utils/app_logger.dart';
import '../../data/services/gallery_service.dart';
import '../../data/services/native_video_controller.dart';
import '../common/keep_vault_unlocked.dart';
import '../common/zoomable_media_image.dart';
import '../player/engine_fallback.dart';
import '../player/video_player_controls.dart';
import '../player/video_player_surface.dart';

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
  }) : assert(items.length > 0);

  final List<GalleryAsset> items;
  final int initialIndex;
  final GalleryAssetFileResolver resolveFile;

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
  DateTime? _ignoreAutoAdvanceUntil;
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
        await c.play();
        if (!mounted || request != _loadRequest) {
          await c.dispose();
          return;
        }
        c.onCompleted = () {
          if (!mounted) return;
          _onNativeVideoEnded(item.id);
        };
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

  void _markUserSeek() {
    _ignoreAutoAdvanceUntil = DateTime.now().add(
      const Duration(milliseconds: 800),
    );
  }

  void _onNativeVideoEnded(String itemId) {
    if (!mounted) return;
    if (_looping) return;
    final now = DateTime.now();
    if (_ignoreAutoAdvanceUntil != null &&
        !now.isAfter(_ignoreAutoAdvanceUntil!)) return;
    _completedForId = itemId;
    final nextIndex = _index + 1;
    if (nextIndex >= widget.items.length) return;
    unawaited(_showItem(nextIndex));
  }

  Future<void> _stopVideo() async {
    final c = _video;
    _video = null;
    _completedForId = null;
    if (c != null) await c.dispose();
  }

  @override
  void dispose() {
    _loadRequest++;
    final c = _video;
    _video = null;
    _completedForId = null;
    if (c != null) {
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
    if (value.isCompleted ||
        (value.duration > Duration.zero && value.position >= value.duration)) {
      await video.seekTo(Duration.zero);
    }
    await video.play();
    await video.setPlaybackSpeed(_playbackSpeed);
  }

  Future<void> _seekTo(Duration position) async {
    final video = _video;
    if (video == null) return;
    _markUserSeek();
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
        child: NativeVideoViewport(controller: video, fitMode: _fitMode),
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