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
import 'engine_fallback.dart';
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

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with VideoEngineFallbackState<PlayerScreen> {
  NativeVideoController? _nVideo;
  String? _nVideoItemId;
  String? _videoError;
  String? _videoErrorItemId;
  String? _completedForId;
  int _videoRequest = 0;
  String? _loadingItemId;
  bool? _nativeInitialized;
  bool _reconcileScheduled = false;
  /// De-duplication keys for the diagnostic lines written from build(): a
  /// per-item state change is readable in the log, a per-frame one is not.
  String? _loggedItemId;
  String? _loggedVideoBranch;
  String? _loggedHealItemId;
  String? _loggedSpinnerKey;
  String? _loggedSurfaceKey;
  final Set<String> _autoRetriedItemIds = <String>{};
  // 引擎回退集合（VLC 下拿不到画面的 item）现在由 VideoEngineFallbackState 持有。
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
    AppLogger.i(
      'PlayerScreen',
      'initState: items=${widget.items.length}, '
      'startItemId=${widget.startItemId ?? '-'}, shuffle=${widget.shuffle}',
    );
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
    _cancelLoadWatchdog();
    AppLogger.i(
      'PlayerScreen',
      'dispose: item=${_nVideoItemId ?? '-'}, '
      'hasController=${_nVideo != null}, request=$_videoRequest',
    );
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
    _cancelLoadWatchdog();
    final c = _nVideo;
    final previousItemId = _nVideoItemId;
    _nVideo = null;
    _nVideoItemId = null;
    _completedForId = null;
    _nativeInitialized = null;
    if (c != null) {
      AppLogger.i(
        'PlayerScreen',
        'Disposing native player: item=${previousItemId ?? '-'}, '
        'textureId=${c.textureId}, request=$_videoRequest',
      );
      c.removeListener(_onNativeVideoValueChanged);
      await c.dispose();
    }
  }

  /// Native events (initialized/error) land on the controller asynchronously.
  ///
  /// [build] decides between the spinner and the video surface by reading
  /// `controller.value.isInitialized`, so the screen has to repaint when that
  /// flag flips. Without this listener the second video of a folder autoplay
  /// keeps spinning forever: the chrome is already hidden by then, so no other
  /// rebuild is scheduled after the native player becomes ready.
  void _onNativeVideoValueChanged() {
    if (!mounted) return;
    final video = _nVideo;
    if (video == null) return;
    final initialized = video.value.isInitialized;
    if (initialized == _nativeInitialized) return;
    _nativeInitialized = initialized;
    // The spinner <-> surface switch in build() keys off this line: when an
    // autoplay stalls, a missing "Native value changed" for item X is the
    // answer, and the state printed here tells us why.
    AppLogger.i(
      'PlayerScreen',
      'Native value changed: item=${_nVideoItemId ?? '-'}, '
      'textureId=${video.textureId}, initialized=$initialized, '
      'playing=${video.value.isPlaying}, error=${video.value.hasError}, '
      'size=${video.value.size.width.toInt()}x'
      '${video.value.size.height.toInt()}',
    );
    setState(() {});
  }

  /// Safety net for a missed `initialized` event: shortly after a load, ask the
  /// native player for its authoritative state and apply it, so a dropped event
  /// can never park the UI on the spinner.
  void _armStatusFallback(
    NativeVideoController controller,
    MediaItem item,
    int request,
  ) {
    Timer(const Duration(milliseconds: 900), () async {
      if (!mounted || !identical(controller, _nVideo)) return;
      if (controller.value.isInitialized || controller.value.hasError) return;
      if (_isStaleLoad(request, item)) return;
      final status = await controller.fetchStatus();
      if (!mounted || !identical(controller, _nVideo)) return;
      if (status == null) {
        AppLogger.w('PlayerScreen',
            'Status fallback for ${item.id}: getStatus returned null '
            '(textureId=${controller.textureId})');
        return;
      }
      if (!status.isReady) {
        AppLogger.w('PlayerScreen',
            'Status fallback for ${item.id}: native player still not ready '
            '(textureId=${controller.textureId}, position=${status.position})');
        return;
      }
      AppLogger.w('PlayerScreen',
          'Recovered video state from native status: ${item.id} '
          '(initialized event was missed)');
      controller.applyStatus(status);
    });
  }

  /// Fails the endless-spinner case: when the native side never reports
  /// initialized for the item we handed it, retry once and then show an error.
  ///
  /// 计时器本体在 [VideoEngineFallbackState]（三处入口共用），这里只保留本屏的
  /// 判定与处置，语义与拆分前一致。
  void _startLoadWatchdog(MediaItem item, int request) {
    armLoadWatchdog(
      item.id,
      onTimeout: (id) async {
        if (_isStaleLoad(request, item)) return;
        if (_videoErrorItemId == item.id) return;
        final video = _nVideo;
        final showing = video != null && _nVideoItemId == item.id;
        if (showing && (video.value.isInitialized || video.value.hasError)) {
          return;
        }
        // A load that never even published a controller (hung create/dispose)
        // must be retried too, otherwise the spinner stays on screen forever.
        AppLogger.w(
          'PlayerScreen',
          'Video did not initialize within 15s '
          '(controller=${showing ? 'published' : 'missing'}): $id',
        );
        unawaited(_retryLoad(item));
      },
    );
  }

  void _cancelLoadWatchdog() => cancelLoadWatchdog();

  /// 传给平台通道的 `playerEngine` 参数（`'vlc'` / `'exoPlayer'`）。
  ///
  /// 规则集中在 [VideoEngineFallbackState.engineFor]：用户选了 VLC、但这个视频在
  /// VLC 下已经确认拿不到帧时（见 [_retryLoad]），本屏会话内对**这一个**视频改用
  /// 默认引擎，而不是反复把用户扔回黑屏。
  String _preferredEngineFor(MediaItem item) => engineFor(item.id);

  /// One automatic retry per item, then a visible error instead of a spinner.
  ///
  /// 引擎回退优先于“再试一次同一个引擎”：VLC 侧没有 ExoPlayer 那样的
  /// frameWatchdog / reattachSurface 自愈（surface 丢了就一直是黑屏，
  /// 只能重建整个播放器），而且同一份文件在同一个引擎下重试大概率还是同样
  /// 的结果。所以第一次超时就直接换回默认引擎重载，把这一次重试额度用掉。
  Future<void> _retryLoad(MediaItem item) async {
    if (!mounted) return;

    // 还没用过那唯一一次自动重试、且当前用的是 VLC ⇒ 换成 ExoPlayer 重载。
    if (!_autoRetriedItemIds.contains(item.id) &&
        _preferredEngineFor(item) == 'vlc') {
      _autoRetriedItemIds.add(item.id);
      useEngineFallback(item.id);
      AppLogger.w(
        'PlayerScreen',
        'VLC engine produced no frame within 15s, retrying with the '
        'exoPlayer engine: ${item.id}',
      );
      await _disposeNativeVideo();
      if (!mounted) return;
      final state = ref.read(playerControllerProvider);
      if (state.current?.id != item.id) return;
      unawaited(_loadVideo(item, state.playing, force: true));
      return;
    }

    if (_autoRetriedItemIds.contains(item.id)) {
      if (_videoErrorItemId != item.id) {
        AppLogger.e('PlayerScreen', 'Video load retry failed: ${item.id}');
        setState(() {
          _videoError = 'Video failed to start: ${item.privatePath}';
          _videoErrorItemId = item.id;
        });
      }
      await _disposeNativeVideo();
      return;
    }
    _autoRetriedItemIds.add(item.id);
    AppLogger.w('PlayerScreen', 'Retrying video load: ${item.id}');
    await _disposeNativeVideo();
    if (!mounted) return;
    final state = ref.read(playerControllerProvider);
    if (state.current?.id != item.id) return;
    // Forced: the previous attempt may still be hanging inside the platform
    // channel, and _disposeNativeVideo() already invalidated it.
    unawaited(_loadVideo(item, state.playing, force: true));
  }

  /// Self-heal hook: re-runs the playlist/native sync after the current frame.
  void _scheduleReconcile() {
    if (_reconcileScheduled) return;
    _reconcileScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reconcileScheduled = false;
      if (!mounted) return;
      final ui = ref.read(playerControllerProvider);
      // Logged once per item: build() schedules this on every frame while the
      // native engine is out of sync, so a raw log here would be a flood.
      if (_loggedHealItemId != ui.current?.id) {
        _loggedHealItemId = ui.current?.id;
        AppLogger.w(
          'PlayerScreen',
          'Self-heal: reconciling native video for ${ui.current?.id ?? '-'} '
          '(loadedItem=${_nVideoItemId ?? '-'}, '
          'hasController=${_nVideo != null}, '
          'initialized=${_nVideo?.value.isInitialized})',
        );
      }
      _syncNativeVideo(ui);
    });
  }

  void _clearVideoError() {
    if (_videoError == null && _videoErrorItemId == null) return;
    setState(() {
      _videoError = null;
      _videoErrorItemId = null;
    });
  }

  Future<void> _loadVideo(
    MediaItem item,
    bool playing, {
    bool force = false,
  }) async {
    if (!force && _loadingItemId == item.id) {
      AppLogger.d('PlayerScreen', 'Video load already in flight: ${item.id}');
      return;
    }
    _loadingItemId = item.id;
    AppLogger.d(
      'PlayerScreen',
      'loadVideo(${item.id}) playing=$playing force=$force, '
      'loadedItem=${_nVideoItemId ?? '-'}, '
      'hasController=${_nVideo != null}',
    );
    try {
      await _loadVideoInner(item, playing);
    } finally {
      if (_loadingItemId == item.id) _loadingItemId = null;
    }
  }

  Future<void> _loadVideoInner(MediaItem item, bool playing) async {
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
      AppLogger.d(
        'PlayerScreen',
        'Reusing loaded video for ${item.id} '
        '(textureId=${currentVideo.textureId}, '
        'initialized=${currentVideo.value.isInitialized}, '
        'playing=${currentVideo.value.isPlaying}, want=$playing)',
      );
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
    _startLoadWatchdog(item, request);

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
      // 注意不要再直接读 settings.playerEngine：走 [_preferredEngineFor]，
      // 它会在 VLC 已经确认画不出帧时回退到默认引擎。
      final engine = _preferredEngineFor(item);
      final controller = await NativeVideoController.create(
        item.privatePath,
        playerEngine: engine,
      );
      if (_isStaleLoad(request, item)) {
        AppLogger.d('PlayerScreen', 'Stale video load, disposing: ${item.id}');
        await controller.dispose();
        return;
      }
      AppLogger.i('PlayerScreen',
          'Configuring native video: ${item.id}, engine=$engine, playing=$playing');
      await _configureNativeVideo(controller, playing: playing);
      if (_isStaleLoad(request, item)) {
        await controller.dispose();
        return;
      }
      controller.onCompleted = () {
        if (!mounted) return;
        _completedForId = item.id;
        final ui = ref.read(playerControllerProvider);
        final pl = ui.playlist;
        AppLogger.i(
          'PlayerScreen',
          'Video completed callback: ${item.id} '
          '(${pl?.positionDisplay ?? 0}/${pl?.length ?? 0}), '
          'playing=${ui.playing}, '
          'next=${pl?.peekNext()?.id ?? 'none'}',
        );
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
      // The spinner/video switch in build() reads controller.value, so the
      // screen must repaint once the native player reports it is ready.
      controller.addListener(_onNativeVideoValueChanged);
      _nativeInitialized = controller.value.isInitialized;
      setState(() {
        _nVideo = controller;
        _nVideoItemId = item.id;
      });
      // A fresh controller is a fresh start: let the self-heal log speak again
      // if this item later loses its video surface.
      _loggedHealItemId = null;
      _armStatusFallback(controller, item, request);
      AppLogger.i(
        'PlayerScreen',
        'Video loaded successfully: ${item.id}, '
        'textureId=${controller.textureId}, '
        'initialized=${controller.value.isInitialized} (request=$request)',
      );
    } catch (error, stackTrace) {
      if (_isStaleLoad(request, item)) return;
      AppLogger.e('PlayerScreen',
          'Video load failed for ${item.id}: $error', stackTrace);
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
      if (_nVideo != null) {
        AppLogger.d('PlayerScreen',
            'sync: current=${item?.id ?? '-'} is not a video, releasing engine');
        unawaited(_disposeNativeVideo());
      }
      return;
    }
    final video = _nVideo;
    if (_nVideoItemId != item.id || video == null) {
      AppLogger.i(
        'PlayerScreen',
        'sync: loading ${item.id} (loaded=${_nVideoItemId ?? '-'}, '
        'hasController=${video != null}, playing=${ui.playing})',
      );
      unawaited(_loadVideo(item, ui.playing));
      return;
    }
    if (video.value.isInitialized && video.value.isPlaying != ui.playing) {
      AppLogger.i(
        'PlayerScreen',
        'sync: correcting play state of ${item.id} '
        '(native=${video.value.isPlaying}, wanted=${ui.playing})',
      );
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
    // The single line that answers "did autoplay move on?" when reading a log.
    if (item?.id != _loggedItemId) {
      _loggedItemId = item?.id;
      AppLogger.i(
        'PlayerScreen',
        'Showing ${item?.id ?? '-'} '
        '(${item?.isVideo == true ? 'video' : 'image'}) '
        '(${pl?.positionDisplay ?? 0}/${pl?.length ?? 0}), '
        'playing=${ui.playing}',
      );
    }
    final landscape = _isLandscape(context);
    final builtInVideo = item?.isVideo == true &&
        _nVideo != null &&
        _nVideoItemId == item?.id &&
        _nVideo!.value.isInitialized;
    final immersive = landscape && builtInVideo;
    // One line per (item, playing, branch) transition: enough to see which
    // branch every clip of an autoplay run settled on, without a log flood.
    final branchKey = 'item=${item?.id ?? '-'}|playing=${ui.playing}|'
        'surface=$builtInVideo|error=${_videoErrorItemId ?? '-'}|'
        'loaded=${_nVideoItemId ?? '-'}|init=${_nVideo?.value.isInitialized}|'
        'nativePlaying=${_nVideo?.value.isPlaying}';
    if (branchKey != _loggedVideoBranch) {
      _loggedVideoBranch = branchKey;
      AppLogger.d(
        'PlayerScreen',
        'build: $branchKey, chrome=$_chrome, '
        'externalHandedOff=${ui.externalHandedOff}, '
        'playlist=${pl?.positionDisplay ?? 0}/${pl?.length ?? 0}',
      );
    }
    _syncSystemUi(immersive);
    _syncKeepScreenOn(item != null && (ui.playing || item.isVideo));
    if (builtInVideo) {
      _maybeLockOrientationToVideo();
    }

    // Keep the video engine in sync with the playlist's current item.
    ref.listen(playerControllerProvider, (_, next) => _syncNativeVideo(next));

    // Self-heal: a video is on screen but the native engine has nothing
    // loaded for it (or is stuck on an older texture). Scheduling a
    // reconciliation pass keeps the player off an endless spinner.
    if (item != null &&
        item.isVideo &&
        _videoErrorItemId != item.id &&
        (_nVideo == null || _nVideoItemId != item.id)) {
      _scheduleReconcile();
    }

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
      AppLogger.d('PlayerScreen',
          'Video view: external hand-off placeholder for ${item.id}');
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
      AppLogger.d('PlayerScreen',
          'Video view: error panel for ${item.id}: $_videoError');
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
      // Logged once per distinct spinner state: an endless spinner plus this
      // line is the exact failure signature reported from the phone.
      final spinnerKey = '${item.id}|loaded=${_nVideoItemId ?? '-'}|'
          'texture=${c?.textureId ?? '-'}|init=${c?.value.isInitialized}|'
          'error=${c?.value.hasError}';
      if (spinnerKey != _loggedSpinnerKey) {
        _loggedSpinnerKey = spinnerKey;
        AppLogger.w(
          'PlayerScreen',
          'Video view: spinner for ${item.id} '
          '(hasController=${c != null}, loadedItem=${_nVideoItemId ?? '-'}, '
          'initialized=${c?.value.isInitialized}, '
          'nativeError=${c?.value.hasError}, '
          'loadingItem=${_loadingItemId ?? '-'}, '
          'watchdog=$isLoadWatchdogArmed)',
        );
      }
      return GestureDetector(
        onTap: _toggleChrome,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white54),
        ),
      );
    }
    final surfaceKey = '${item.id}|${c.textureId}';
    if (surfaceKey != _loggedSurfaceKey) {
      _loggedSurfaceKey = surfaceKey;
      AppLogger.i(
        'PlayerScreen',
        'Video surface visible: ${item.id}, textureId=${c.textureId}, '
        'size=${c.value.size.width.toInt()}x'
        '${c.value.size.height.toInt()}, playing=${c.value.isPlaying}',
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