import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/media/rating_controller.dart';
import '../../application/player/external_player_coordinator.dart';
import '../../application/player/player_controller.dart';
import '../../application/settings/settings_controller.dart';
import '../../core/l10n.dart';
import '../../core/utils/app_logger.dart';
import '../../data/services/native_video_controller.dart';
import '../../domain/models/media_item.dart';
import '../common/keep_vault_unlocked.dart';
import 'video_player_controls.dart';
import 'video_player_surface.dart';

typedef VideoFileProbe = Future<bool> Function(String path);

Future<bool> _probeVideoFile(String path) => File(path).exists();

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({
    super.key,
    required this.items,
    this.shuffle,
    this.startItemId,
    this.title = 'Playing',
    this.videoFileProbe = _probeVideoFile,
  });

  final List<MediaItem> items;
  final bool? shuffle;
  final String? startItemId;
  final String title;
  final VideoFileProbe videoFileProbe;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  NativeVideoController? _nVideo;
  String? _nVideoItemId;
  String? _videoError;
  String? _videoErrorItemId;
  String? _completedForId;
  int _videoRequest = 0;
  bool _chrome = true;
  bool _programmaticPopAllowed = false;
  VideoFitMode _fitMode = VideoFitMode.fit;
  double _playbackSpeed = 1;
  bool _muted = false;
  bool? _lastImmersive;
  bool? _lastKeepScreenOn;
  String? _orientationLockedItemId;
  bool _orientationOverridden = false;
  final Map<String, int> _ratingOverrides = {};

  @override
  void initState() {
    super.initState();
    _playbackSpeed = ref.read(settingsControllerProvider).playerPlaybackSpeed;
    unawaited(VideoSystemUi.apply(false));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(playerControllerProvider.notifier).start(
            items: widget.items,
            shuffle: widget.shuffle,
            startItemId: widget.startItemId,
          );
    });
  }

  @override
  void dispose() {
    _disposeNativeVideo();
    unawaited(VideoSystemUi.restore());
    super.dispose();
  }

  bool _isLandscape(BuildContext context) =>
      MediaQuery.orientationOf(context) == Orientation.landscape;

  void _syncSystemUi(bool immersive) {
    if (_lastImmersive == immersive) return;
    _lastImmersive = immersive;
    unawaited(VideoSystemUi.apply(immersive));
  }

  /// Keeps the screen awake while the slideshow runs or a video is on screen,
  /// so playback is not interrupted by the system lock screen.
  void _syncKeepScreenOn(bool keepOn) {
    if (_lastKeepScreenOn == keepOn) return;
    _lastKeepScreenOn = keepOn;
    unawaited(VideoSystemUi.setKeepScreenOn(keepOn));
  }

  Future<void> _toggleOrientation(BuildContext context) async {
    _orientationOverridden = true;
    await VideoSystemUi.toggle(_isLandscape(context));
  }

  void _maybeLockOrientationToVideo() {
    final video = _nVideo;
    final itemId = _nVideoItemId;
    if (video == null || itemId == null || !video.value.isInitialized) return;
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

  int _ratingFor(MediaItem item) => _ratingOverrides[item.id] ?? item.rating;

  void _setRating(MediaItem item, int rating) {
    unawaited(
      ref.read(ratingControllerProvider.notifier).setRating(item.id, rating),
    );
    setState(() => _ratingOverrides[item.id] = rating);
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
    final video = _nVideo;
    if (video != null) unawaited(video.setPlaybackSpeed(speed));
  }

  void _setMuted(bool muted) {
    setState(() => _muted = muted);
    final video = _nVideo;
    if (video != null) unawaited(video.setVolume(muted ? 0 : 1));
  }

  Future<void> _seekTo(Duration position) async {
    final video = _nVideo;
    if (video != null) await video.seekTo(position);
  }

  Future<void> _openSettings(PlayerUiState ui) async {
    final settings = ref.read(settingsControllerProvider);
    final item = ui.current;
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
      shuffle: ui.playlist?.shuffle,
      onShuffleChanged: (value) {
        if (value != ref.read(playerControllerProvider).playlist?.shuffle) {
          ref.read(playerControllerProvider.notifier).toggleShuffle();
        }
      },
      rating: item == null ? null : _ratingFor(item),
      onRatingChanged:
          item == null ? null : (rating) => _setRating(item, rating),
    );
  }

  Future<void> _configureNativeVideo(
    NativeVideoController controller, {
    required bool playing,
  }) async {
    await controller.setLooping(false);
    await controller.setVolume(_muted ? 0 : 1);
    if (playing) {
      await controller.play();
      await controller.setPlaybackSpeed(_playbackSpeed);
    } else {
      await controller.setPlaybackSpeed(_playbackSpeed);
    }
  }

  Future<void> _disposeNativeVideo() async {
    // Invalidate any in-flight load so it cannot publish a stale controller.
    _videoRequest++;
    final c = _nVideo;
    _nVideo = null;
    _nVideoItemId = null;
    _completedForId = null;
    if (c != null) await c.dispose();
  }

  void _clearVideoError() {
    if (_videoError == null && _videoErrorItemId == null) return;
    setState(() {
      _videoError = null;
      _videoErrorItemId = null;
    });
  }

  Future<void> _loadVideo(MediaItem item, bool playing) async {
    final external = ref.read(settingsControllerProvider).playerExternal &&
        ref.read(externalPlayerCoordinatorProvider).supported;
    if (external) {
      AppLogger.d('PlayerScreen', 'External player mode, skipping native load');
      await _disposeNativeVideo();
      return;
    }

    _clearVideoError();

    // Already showing the right video
    if (_nVideoItemId == item.id && _nVideo != null) {
      final currentVideo = _nVideo!;
      try {
        if (playing && !currentVideo.value.isPlaying) {
          if (_completedForId == item.id) {
            _completedForId = null;
            AppLogger.d('PlayerScreen', 'Replaying completed video: ${item.id}');
            await currentVideo.seekTo(Duration.zero);
          }
          AppLogger.d('PlayerScreen', 'Resuming video: ${item.id}');
          await currentVideo.play();
          await currentVideo.setPlaybackSpeed(_playbackSpeed);
        } else if (!playing && currentVideo.value.isPlaying) {
          AppLogger.d('PlayerScreen', 'Pausing video: ${item.id}');
          await currentVideo.pause();
        }
      } catch (error, stackTrace) {
        AppLogger.e('PlayerScreen',
            'Video control failed for ${item.id}: $error', stackTrace);
        debugPrint('video control failed for ${item.id}: $error\n$stackTrace');
        setState(() {
          _videoError = error.toString();
          _videoErrorItemId = item.id;
        });
      }
      return;
    }

    // Need to load a new video
    AppLogger.i(
      'PlayerScreen',
      'Loading new video: ${item.id} -> ${item.privatePath}',
    );
    await _disposeNativeVideo();
    // Load generation: bumped by every dispose, so a superseded load can
    // never publish a controller for a stale item.
    final request = _videoRequest;

    if (!await widget.videoFileProbe(item.privatePath)) {
      if (_isStaleLoad(request, item)) return;
      AppLogger.e('PlayerScreen', 'Video file not found: ${item.privatePath}');
      setState(() {
        _videoError = 'Video file does not exist: ${item.privatePath}';
        _videoErrorItemId = item.id;
      });
      return;
    }

    try {
      final controller = await NativeVideoController.create(item.privatePath);
      if (_isStaleLoad(request, item)) {
        AppLogger.d('PlayerScreen', 'Stale video load, disposing: ${item.id}');
        await controller.dispose();
        return;
      }
      AppLogger.i('PlayerScreen', 'Configuring native video: ${item.id}, playing=$playing');
      await _configureNativeVideo(controller, playing: playing);
      if (_isStaleLoad(request, item)) {
        await controller.dispose();
        return;
      }
      controller.onCompleted = () {
        if (!mounted) return;
        _completedForId = item.id;
        AppLogger.i('PlayerScreen', 'Video completed callback: ${item.id}');
        ref.read(playerControllerProvider.notifier).onItemCompleted();
      };
      controller.onError = () {
        if (!mounted) return;
        AppLogger.e('PlayerScreen',
            'Video error callback: ${item.id}, ${controller.value.errorDescription}');
        setState(() {
          _videoError = controller.value.errorDescription;
          _videoErrorItemId = item.id;
        });
      };
      setState(() {
        _nVideo = controller;
        _nVideoItemId = item.id;
      });
      AppLogger.i('PlayerScreen', 'Video loaded successfully: ${item.id}');
    } catch (error, stackTrace) {
      if (_isStaleLoad(request, item)) return;
      AppLogger.e('PlayerScreen',
          'Video load failed for ${item.id}: $error', stackTrace);
      debugPrint('video load failed for ${item.id}: $error\n$stackTrace');
      setState(() {
        _videoError = error.toString();
        _videoErrorItemId = item.id;
      });
    }
  }

  /// Reconciles the native video engine with the playlist's current item.
  ///
  /// Keyed on the loaded item id instead of on prev/next state diffs: every
  /// item switch ends in either a playing video or a visible error, never in
  /// an endless spinner.
  void _syncNativeVideo(PlayerUiState ui) {
    final item = ui.current;
    if (item == null || !item.isVideo) {
      if (_nVideo != null) unawaited(_disposeNativeVideo());
      return;
    }
    final video = _nVideo;
    if (_nVideoItemId != item.id || video == null) {
      unawaited(_loadVideo(item, ui.playing));
      return;
    }
    if (video.value.isInitialized && video.value.isPlaying != ui.playing) {
      unawaited(_loadVideo(item, ui.playing));
    }
  }

  /// True when [request] was superseded or the playlist moved to another item.
  bool _isStaleLoad(int request, MediaItem item) {
    if (!mounted || request != _videoRequest) return true;
    return ref.read(playerControllerProvider).current?.id != item.id;
  }

  void _toggleChrome() => setState(() => _chrome = !_chrome);

  void _hideChrome() {
    if (_chrome) setState(() => _chrome = false);
  }

  void _exitPlayer() {
    ref.read(playerControllerProvider.notifier).stop();
    if (!mounted) return;
    setState(() {
      _chrome = false;
      _programmaticPopAllowed = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ui = ref.watch(playerControllerProvider);
    final item = ui.current;
    final pl = ui.playlist;
    final landscape = _isLandscape(context);
    final builtInVideo = item?.isVideo == true &&
        _nVideo != null &&
        _nVideoItemId == item?.id &&
        _nVideo!.value.isInitialized;
    final immersive = landscape && builtInVideo;
    _syncSystemUi(immersive);
    _syncKeepScreenOn(item != null && (ui.playing || item.isVideo));
    if (builtInVideo) {
      _maybeLockOrientationToVideo();
    }

    // Keep the video engine in sync with the playlist's current item.
    ref.listen(playerControllerProvider, (_, next) => _syncNativeVideo(next));

    return KeepVaultUnlocked(
      child: PopScope(
        canPop: item?.isVideo == true || !_chrome || _programmaticPopAllowed,
        onPopInvokedWithResult: (didPop, _) async {
          if (!didPop) {
            if (mounted && _chrome) setState(() => _chrome = false);
            return;
          }
          ref.read(playerControllerProvider.notifier).stop();
          await _disposeNativeVideo();
        },
        child: AutoHideVideoControls(
          enabled: item?.isVideo == true,
          visible: _chrome,
          onHide: _hideChrome,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                if (item == null)
                  Center(
                    child: Text(
                      context.l10n.emptyPlaylist,
                      style: const TextStyle(color: Colors.white54),
                    ),
                  )
                else if (item.isVideo)
                  _buildVideo(item, ui)
                else
                  _buildImage(item),
                if (_chrome)
                  _topBar(ui, pl?.positionDisplay ?? 0, pl?.length ?? 0),
                if (_chrome && builtInVideo)
                  _nVideoBottomBar(ui, landscape)
                else if (_chrome)
                  _bottomBar(ui, landscape),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage(MediaItem item) {
    final file = File(item.privatePath);
    if (!file.existsSync()) {
      return const Center(
        child: Icon(Icons.broken_image, color: Colors.white38, size: 64),
      );
    }
    return GestureDetector(
      onTap: _toggleChrome,
      child: InteractiveViewer(
        child: Center(child: Image.file(file, fit: BoxFit.contain)),
      ),
    );
  }

  Widget _buildVideo(MediaItem item, PlayerUiState ui) {
    if (ui.externalHandedOff) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.open_in_new, color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            Text(
              context.l10n.openedExternalPlayer,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () =>
                  ref.read(playerControllerProvider.notifier).next(),
              child: Text(context.l10n.next),
            ),
          ],
        ),
      );
    }
    if (_videoErrorItemId == item.id && _videoError != null) {
      return GestureDetector(
        onTap: _toggleChrome,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.white54,
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.errorWithDetails(_videoError!),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => _loadVideo(item, ui.playing),
                  child: Text(context.l10n.retry),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final c = _nVideo;
    if (c == null || _nVideoItemId != item.id || !c.value.isInitialized) {
      return GestureDetector(
        onTap: _toggleChrome,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white54),
        ),
      );
    }
    return GestureDetector(
      onTap: _toggleChrome,
      child: NativeVideoViewport(controller: c, fitMode: _fitMode),
    );
  }

  Widget _topBar(PlayerUiState ui, int pos, int total) {
    final title = ui.current?.originalName ?? widget.title;
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
                  onPressed: _exitPlayer,
                ),
                Expanded(
                  child: Text(
                    '$title \u00b7 $pos/$total',
                    style: const TextStyle(color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar(PlayerUiState ui, bool landscape) {
    final pl = ui.playlist;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        child: Material(
          color: Colors.black54,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      iconSize: 32,
                      color: Colors.white,
                      tooltip: context.l10n.previousMedia,
                      onPressed: pl?.hasPrev == true
                          ? () =>
                              ref.read(playerControllerProvider.notifier).prev()
                          : null,
                      icon: const Icon(Icons.skip_previous),
                    ),
                    IconButton(
                      iconSize: 44,
                      color: Colors.white,
                      tooltip:
                          ui.playing ? context.l10n.pause : context.l10n.play,
                      onPressed: () => ref
                          .read(playerControllerProvider.notifier)
                          .togglePlayPause(),
                      icon: Icon(
                        ui.playing ? Icons.pause_circle : Icons.play_circle,
                      ),
                    ),
                    IconButton(
                      iconSize: 32,
                      color: Colors.white,
                      tooltip: context.l10n.nextMedia,
                      onPressed: pl?.hasNext == true
                          ? () =>
                              ref.read(playerControllerProvider.notifier).next()
                          : null,
                      icon: const Icon(Icons.skip_next),
                    ),
                    IconButton(
                      iconSize: 28,
                      color: pl?.shuffle == true
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white70,
                      tooltip: context.l10n.shuffle,
                      onPressed: () => ref
                          .read(playerControllerProvider.notifier)
                          .toggleShuffle(),
                      icon: const Icon(Icons.shuffle),
                    ),
                    IconButton(
                      iconSize: 28,
                      color: Colors.white,
                      tooltip: landscape
                          ? context.l10n.portrait
                          : context.l10n.landscape,
                      onPressed: () => unawaited(_toggleOrientation(context)),
                      icon: Icon(
                        landscape
                            ? Icons.stay_current_portrait
                            : Icons.stay_current_landscape,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _nVideoBottomBar(PlayerUiState ui, bool landscape) {
    final video = _nVideo;
    final playlist = ui.playlist;
    if (video == null || !video.value.isInitialized) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.bottomCenter,
      child: ValueListenableBuilder<NativeVideoValue>(
        valueListenable: video,
        builder: (context, value, _) {
          return NativeVideoBottomControls(
            value: value,
            landscape: landscape,
            fitMode: _fitMode,
            hasPrevious: playlist?.hasPrev == true,
            hasNext: playlist?.hasNext == true,
            onPrevious: () =>
                unawaited(ref.read(playerControllerProvider.notifier).prev()),
            onSeek: _seekTo,
            onPlayPause: () =>
                ref.read(playerControllerProvider.notifier).togglePlayPause(),
            onNext: () =>
                unawaited(ref.read(playerControllerProvider.notifier).next()),
            onToggleOrientation: () => unawaited(_toggleOrientation(context)),
            onChooseFit: () => unawaited(_chooseFit()),
            onOpenSettings: () => unawaited(_openSettings(ui)),
          );
        },
      ),
    );
  }
}