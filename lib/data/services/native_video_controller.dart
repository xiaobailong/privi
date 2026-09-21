import 'dart:async';
import 'dart:io';

// `Uint8List`（下面文件事实探针里用到）由这一行提供：flutter/foundation.dart
// 已经 re-export 了 dart:typed_data，所以**不需要**再 import 'dart:typed_data'。
// 实测：加上那一行会让 `dart analyze` 报 `unnecessary_import`；
// 复核探针见 build\_u8_probe2.dart。
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../core/utils/app_logger.dart';

class NativeVideoValue {
  final bool isInitialized;
  final bool isPlaying;
  final bool isCompleted;
  final bool hasError;
  final String? errorDescription;
  final Duration duration;
  final Duration position;
  final Size size;
  final double volume;

  const NativeVideoValue({
    this.isInitialized = false,
    this.isPlaying = false,
    this.isCompleted = false,
    this.hasError = false,
    this.errorDescription,
    this.duration = Duration.zero,
    this.position = Duration.zero,
    this.size = Size.zero,
    this.volume = 1.0,
  });

  double get aspectRatio => size.width > 0 && size.height > 0
      ? size.width / size.height
      : 1.0;

  NativeVideoValue copyWith({
    bool? isInitialized,
    bool? isPlaying,
    bool? isCompleted,
    bool? hasError,
    String? errorDescription,
    bool clearError = false,
    Duration? duration,
    Duration? position,
    Size? size,
    double? volume,
  }) {
    return NativeVideoValue(
      isInitialized: isInitialized ?? this.isInitialized,
      isPlaying: isPlaying ?? this.isPlaying,
      isCompleted: isCompleted ?? this.isCompleted,
      hasError: clearError ? false : (hasError ?? this.hasError),
      errorDescription:
          clearError ? null : (errorDescription ?? this.errorDescription),
      duration: duration ?? this.duration,
      position: position ?? this.position,
      size: size ?? this.size,
      volume: volume ?? this.volume,
    );
  }
}

/// Authoritative snapshot of the native player.
///
/// The native side pushes a one-shot `initialized` event; this is the pull
/// counterpart used as a safety net when that event is missed.
class NativeVideoStatus {
  const NativeVideoStatus({
    required this.isReady,
    required this.isPlaying,
    required this.duration,
    required this.size,
    required this.position,
  });

  final bool isReady;
  final bool isPlaying;
  final Duration duration;
  final Size size;
  final Duration position;
}

class NativeVideoController extends ValueNotifier<NativeVideoValue> {
  static const _channel = MethodChannel('com.privi.app/video_player');

  /// Live controllers keyed by native texture id. The platform channel has a
  /// single process-wide inbound handler, so native events are routed here.
  static final Map<int, NativeVideoController> _registry =
      <int, NativeVideoController>{};

  static bool _handlerInstalled = false;

  /// Installs the shared inbound handler.
  ///
  /// Installed *before* the native player is created and deliberately never
  /// removed: a fast local file can reach STATE_READY while `create` is still
  /// in flight, and uninstalling the handler between clips would drop exactly
  /// the `initialized` event the autoplay chain depends on.
  static void _installHandler() {
    if (_handlerInstalled) return;
    _handlerInstalled = true;
    _channel.setMethodCallHandler(_dispatch);
    AppLogger.d('VideoPlayer', 'Inbound event handler installed');
  }

  static void _register(NativeVideoController controller) {
    _registry[controller.textureId] = controller;
    _installHandler();
    AppLogger.d('VideoPlayer',
        'Registered textureId=${controller.textureId} (live=${_registry.length})');
  }

  static void _unregister(NativeVideoController controller) {
    if (identical(_registry[controller.textureId], controller)) {
      _registry.remove(controller.textureId);
    }
    AppLogger.d('VideoPlayer',
        'Unregistered textureId=${controller.textureId} (live=${_registry.length})');
  }

  /// Routes one native event to the controller that owns it. Payloads carry
  /// the textureId produced by the native side; unknown ids are dropped.
  static Future<dynamic> _dispatch(MethodCall call) async {
    final args = call.arguments;
    int? textureId;
    if (args is Map) {
      final raw = args['textureId'];
      if (raw is int) {
        textureId = raw;
      }
    }
    // Native log lines are written even when their player is already gone: the
    // lines right before a stall are the interesting ones.
    if (call.method == 'log') {
      final text = args is Map ? args['text'] : null;
      final level = args is Map ? args['level'] as String? : null;
      final message = '${text ?? '-'}';
      if (level == 'e') {
        AppLogger.e('VideoPlayer.native', message);
      } else if (level == 'w') {
        AppLogger.w('VideoPlayer.native', message);
      } else if (level == 'd') {
        AppLogger.d('VideoPlayer.native', message);
      } else {
        AppLogger.i('VideoPlayer.native', message);
      }
      return;
    }
    final target = textureId == null ? null : _registry[textureId];
    if (target == null) {
      AppLogger.d('VideoPlayer',
          'Ignoring ${call.method}: no live controller for textureId=$textureId');
      return;
    }
    AppLogger.d('VideoPlayer', 'Event ${call.method} -> textureId=$textureId');
    target._handleCall(call);
  }

  final int textureId;
  final String filePath;

  bool _disposed = false;
  int _durationMs = 0;
  int _width = 0;
  int _height = 0;
  bool _nativePlaying = false;
  bool _positionPollLogged = false;

  /// Leading gap between the native media timeline and the clip's content.
  ///
  /// Media3 reports `currentPosition` on the *media timeline* while `duration`
  /// is the length of the *content*, so a clip whose first sample carries a
  /// large timestamp starts playback at a position far beyond its duration.
  /// A 32-bit 90 kHz PTS wrap is 47,721,859 ms (see
  /// docs/HANDOFF-视频播放诊断日志.md), which is what `202392473501.mp4` does.
  ///
  /// Reported as-is, such a clip looks like it finished instantly: the progress
  /// bar sits at the far right, resuming after a pause jumps back to 0, and the
  /// playlist treats it as completed and skips on. The offset is therefore
  /// measured once - from the first position that lands past the duration - and
  /// subtracted from every position this controller reports.
  int _timelineOffsetMs = 0;

  /// Whether `seekTo` takes media-timeline coordinates (offset included) or
  /// content coordinates. Both are documented as "milliseconds in the current
  /// media item", so the axis is probed once for clips with an offset; see
  /// [_probeSeekAxis]. Clips without an offset are unaffected either way.
  bool _seekNeedsTimelineOffset = true;
  bool _seekAxisProbed = false;

  /// Forward nudge used by [_probeSeekAxis]; small enough to be invisible
  /// during playback.
  static const int _kSeekAxisProbeNudgeMs = 300;

  /// Media-timeline position that maps onto content position 0, or 0 when the
  /// clip has no leading offset.
  int get timelineOffsetMs => _timelineOffsetMs;

  /// Position-stall detection: `isPlaying` can be true while nothing decodes.
  int _lastPolledPositionMs = -1;
  DateTime? _positionStalledSince;
  bool _positionStallLogged = false;

  Timer? _positionTimer;

  VoidCallback? onCompleted;
  VoidCallback? onError;

  NativeVideoController._({
    required this.textureId,
    required this.filePath,
  }) : super(const NativeVideoValue());

  static Future<NativeVideoController> create(
    String filePath, {
    String playerEngine = 'exoPlayer',
  }) async {
    AppLogger.i('VideoPlayer',
        'Creating native player for: $filePath, engine=$playerEngine');
    AppLogger.i(
        'VideoPlayer', 'Source file: ${await describeSourceFile(filePath)}');
    // Install the inbound handler first: STATE_READY can fire before the
    // `create` call returns, and that event carries the initialized metadata.
    _installHandler();
    final stopwatch = Stopwatch()..start();
    try {
      final textureId = await _channel.invokeMethod<int>('create', {
        'filePath': filePath,
        'playerEngine': playerEngine,
      });
      stopwatch.stop();
      if (textureId == null) {
        AppLogger.e('VideoPlayer', 'Failed to create native player: textureId is null');
        throw Exception('Failed to create native video player');
      }
      AppLogger.i('VideoPlayer',
          'Native player created, textureId=$textureId '
          '(create took ${stopwatch.elapsedMilliseconds}ms)');
      final controller = NativeVideoController._(
        textureId: textureId,
        filePath: filePath,
      );
      _register(controller);
      return controller;
    } catch (e, st) {
      stopwatch.stop();
      AppLogger.e(
        'VideoPlayer',
        'Exception creating native player after '
        '${stopwatch.elapsedMilliseconds}ms: $e',
        st,
      );
      rethrow;
    }
  }

  /// One-line description of the clip, written before the native player opens
  /// it.
  ///
  /// A file that plays on one phone and not on another is usually decided by
  /// facts that never reach the log otherwise: the real byte size (a truncated
  /// download, an empty vault entry), the container brand in the first bytes,
  /// and whether the MP4 index (`moov`) sits at the end of the file. All of
  /// them are read here - 8 KB at most - so a failing clip can be identified
  /// from the log alone, without the file itself.
  static Future<String> describeSourceFile(String filePath) async {
    try {
      final file = File(filePath);
      final stat = await file.stat();
      if (stat.type == FileSystemEntityType.notFound) {
        return 'path=$filePath MISSING (file not found)';
      }
      final size = stat.size;
      final head = await _readBytes(file, 0, 64);
      final tailStart = size > 65536 ? size - 8192 : 0;
      final tail = await _readBytes(file, tailStart, 8192);
      return 'path=$filePath size=${size}B '
          'mtime=${stat.modified.toIso8601String()} '
          'head=${_hex(head)} '
          'moovInTail=${_containsAscii(tail, 'moov')} '
          'mdatInTail=${_containsAscii(tail, 'mdat')}';
    } catch (error) {
      return 'path=$filePath probe failed: $error';
    }
  }

  static Future<Uint8List> _readBytes(File file, int start, int length) async {
    final raf = await file.open();
    try {
      await raf.setPosition(start);
      return await raf.read(length);
    } finally {
      await raf.close();
    }
  }

  static String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Whether [bytes] contains [needle] as plain ASCII.
  ///
  /// MP4 box names are plain ASCII, so a substring search is enough to tell
  /// whether the sample table (`moov`) is inside the window that was read.
  static bool _containsAscii(Uint8List bytes, String needle) {
    final pattern = needle.codeUnits;
    for (var i = 0; i + pattern.length <= bytes.length; i++) {
      var matched = true;
      for (var j = 0; j < pattern.length; j++) {
        if (bytes[i + j] != pattern[j]) {
          matched = false;
          break;
        }
      }
      if (matched) return true;
    }
    return false;
  }

  /// Applies the player metadata the UI derives its layout from.
  void _applyInitialized({
    required int durationMs,
    required int width,
    required int height,
    String source = 'event',
  }) {
    _durationMs = durationMs;
    _width = width;
    _height = height;
    AppLogger.i('VideoPlayer',
        'Initialized [$source]: duration=${_durationMs}ms, '
        'size=${_width}x$_height, textureId=$textureId');
    value = value.copyWith(
      isInitialized: true,
      duration: Duration(milliseconds: _durationMs),
      size: Size(_width.toDouble(), _height.toDouble()),
    );
    _startPositionTimer();
  }

  void _handleCall(MethodCall call) {
    if (_disposed) return;
    switch (call.method) {
        case 'initialized':
          final data = call.arguments as Map?;
          _logNativeDiagnostics('initialized', data);
          _applyInitialized(
            durationMs: data?['duration'] as int? ?? 0,
            width: data?['width'] as int? ?? 0,
            height: data?['height'] as int? ?? 0,
          );
          break;
        case 'completed':
          AppLogger.i('VideoPlayer', 'Playback completed, textureId=$textureId');
          _nativePlaying = false;
          _stopPositionTimer();
          value = value.copyWith(
            isPlaying: false,
            isCompleted: true,
            position: value.duration,
          );
          onCompleted?.call();
          break;
        case 'error':
          final data = call.arguments as Map?;
          final msg = data?['message'] as String? ?? 'Unknown playback error';
          AppLogger.e('VideoPlayer',
              'Playback error: $msg, code=${data?['code']}, textureId=$textureId');
          _logNativeDiagnostics('error', data);
          value = value.copyWith(
            hasError: true,
            isPlaying: false,
            errorDescription: msg,
          );
          _stopPositionTimer();
          unawaited(_logDiagnostics('playback-error'));
          onError?.call();
          break;
        case 'playingChanged':
          final data = call.arguments as Map?;
          _nativePlaying = data?['isPlaying'] as bool? ?? false;
          AppLogger.d('VideoPlayer',
              'playingChanged: $_nativePlaying, textureId=$textureId');
          value = value.copyWith(isPlaying: _nativePlaying);
          if (_nativePlaying) {
            _startPositionTimer();
          } else {
            _stopPositionTimer();
          }
          break;
        default:
          AppLogger.d('VideoPlayer',
              'Unknown native event "${call.method}", textureId=$textureId');
          break;
      }
  }

  void _startPositionTimer() {
    _stopPositionTimer();
    _positionTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (_disposed || !_nativePlaying) return;
      _pollPosition();
    });
  }

  void _stopPositionTimer() {
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  Future<void> _pollPosition() async {
    final posMs = await _rawPositionMs();
    if (!_disposed && posMs != null) {
      final contentMs = _contentPositionMs(posMs);
      value = value.copyWith(
        position: Duration(milliseconds: contentMs),
      );
      _trackPositionProgress(contentMs);
    }
  }

  /// Raw media-timeline position, or null when the bridge is unavailable.
  Future<int?> _rawPositionMs() async {
    try {
      return await _channel.invokeMethod<int>('getPosition', {
        'textureId': textureId,
      });
    } catch (error) {
      // Logged once: this runs 4 times per second.
      if (!_positionPollLogged) {
        _positionPollLogged = true;
        AppLogger.w('VideoPlayer',
            'getPosition failed, textureId=$textureId: $error');
      }
      return null;
    }
  }

  /// Content-relative equivalent of the raw media-timeline [rawMs].
  ///
  /// Latches [_timelineOffsetMs] the first time a raw position shows up past
  /// the duration. Until that happens the value passes through unchanged, so a
  /// normal clip is never adjusted and the mapping stays a no-op.
  int _contentPositionMs(int rawMs, {int? durationMs}) {
    if (rawMs <= 0) return 0;
    final duration = durationMs ?? _durationMs;
    if (duration <= 0) return rawMs;
    if (_timelineOffsetMs == 0 && rawMs > duration) {
      _timelineOffsetMs = rawMs;
      AppLogger.w(
        'VideoPlayer.diag',
        'VDIAG[timeline-offset] native position ${rawMs}ms is past duration '
        '${duration}ms: treating ${rawMs}ms as the clip start '
        '(leading edit / 32-bit PTS wrap), textureId=$textureId',
      );
      unawaited(_probeSeekAxis());
    }
    final adjusted = _timelineOffsetMs > 0 ? rawMs - _timelineOffsetMs : rawMs;
    if (adjusted <= 0) return 0;
    return adjusted > duration ? duration : adjusted;
  }

  /// Measures once whether `seekTo` is interpreted on the media timeline (offset
  /// included) or on the content timeline.
  ///
  /// Media3 documents the argument only as milliseconds, and for a clip with a
  /// leading offset the two readings differ by ~13 hours, so getting it wrong
  /// makes every seek jump to the end of the clip. The probe nudges playback
  /// 0.3s forward *on the content axis* - a position the player is already at
  /// under either reading, so the probe is invisible - then reads back which
  /// axis the player actually moved on.
  Future<void> _probeSeekAxis() async {
    if (_seekAxisProbed || _disposed || _timelineOffsetMs <= 0) return;
    _seekAxisProbed = true;
    final offset = _timelineOffsetMs;
    final raw = await _rawPositionMs();
    if (raw == null || _disposed) return;
    final contentNow = raw - offset <= 0 ? 0 : raw - offset;
    final target = contentNow + _kSeekAxisProbeNudgeMs;
    try {
      await _channel.invokeMethod('seekTo', {
        'textureId': textureId,
        'positionMs': target,
      });
    } catch (error) {
      AppLogger.w('VideoPlayer',
          'seek-axis probe seek failed, textureId=$textureId: $error');
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (_disposed) return;
    final back = await _rawPositionMs();
    if (back == null) return;
    final matchesTimeline = (back - offset - target).abs() <= 1000;
    final matchesContent = (back - target).abs() <= 1000;
    if (matchesContent && !matchesTimeline) {
      _seekNeedsTimelineOffset = false;
    }
    AppLogger.i(
      'VideoPlayer.diag',
      'VDIAG[seek-axis] content=${target}ms offset=${offset}ms '
      'readback=${back}ms -> seekTo takes '
      '${_seekNeedsTimelineOffset ? 'timeline' : 'content'} coordinates, '
      'textureId=$textureId',
    );
  }

  /// Flags "isPlaying is true, but the position no longer moves".
  ///
  /// Dart-side twin of the native first-frame watchdog. A clip whose renderer
  /// produces nothing can still report a perfectly healthy player, and without
  /// this line such a session looks like a normal playback in the log.
  void _trackPositionProgress(int posMs) {
    if (posMs != _lastPolledPositionMs) {
      _lastPolledPositionMs = posMs;
      _positionStalledSince = DateTime.now();
      _positionStallLogged = false;
      return;
    }
    if (!_nativePlaying || _positionStallLogged) return;
    final since = _positionStalledSince ??= DateTime.now();
    if (DateTime.now().difference(since) < const Duration(seconds: 3)) return;
    _positionStallLogged = true;
    AppLogger.w(
      'VideoPlayer.diag',
      'VDIAG[dart-position-stall] position stuck at ${posMs}ms while '
      'isPlaying=true, textureId=$textureId',
    );
    unawaited(_logDiagnostics('dart-position-stall'));
  }

  /// Mirrors a native `VDIAG` line that arrived inside an event payload.
  void _logNativeDiagnostics(String source, Map? data) {
    final diag = data?['diag'];
    if (diag is String && diag.isNotEmpty) {
      AppLogger.i('VideoPlayer.diag', '$diag (via $source event)');
    }
  }

  /// Writes one consolidated line with everything the Dart side knows.
  ///
  /// Called exactly when something already looks wrong, so the file has to be
  /// readable by someone who receives only the log and no device.
  Future<void> _logDiagnostics(String reason) async {
    var native = 'getStatus unavailable';
    try {
      final status = await fetchStatus();
      native = status == null
          ? 'getStatus returned null'
          : 'native ready=${status.isReady} playing=${status.isPlaying} '
              'position=${status.position.inMilliseconds}ms '
              'duration=${status.duration.inMilliseconds}ms '
              'size=${status.size.width.toInt()}x${status.size.height.toInt()}';
    } catch (error) {
      native = 'getStatus failed: $error';
    }
    AppLogger.w(
      'VideoPlayer.diag',
      'VDIAG[$reason] textureId=$textureId initialized=${value.isInitialized} '
      'playing=${value.isPlaying} completed=${value.isCompleted} '
      'hasError=${value.hasError} duration=${_durationMs}ms '
      'position=${value.position.inMilliseconds}ms size=${_width}x$_height '
      'timelineOffset=$_timelineOffsetMs ms seekNeedsTimelineOffset='
      '$_seekNeedsTimelineOffset '
      '(${value.errorDescription ?? 'no error text'}) | $native',
    );
  }

  /// Pulls the native player state. Safety net for a missed one-shot
  /// `initialized` event: without it the UI can stay on the spinner while the
  /// native player is already ready and playing.
  Future<NativeVideoStatus?> fetchStatus() async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'getStatus',
        {'textureId': textureId},
      );
      if (raw == null) return null;
      AppLogger.d(
        'VideoPlayer',
        'getStatus: ready=${raw['isReady']} playing=${raw['isPlaying']} '
        'renderedFirstFrame=${raw['renderedFirstFrame']} '
        'videoDecoder=${raw['videoDecoder']}',
      );
      final nativeDiag = raw['diag'];
      if (nativeDiag is String && nativeDiag.isNotEmpty) {
        AppLogger.i('VideoPlayer.diag', '$nativeDiag (via getStatus)');
      }
      final width = (raw['width'] as num?)?.toInt() ?? 0;
      final height = (raw['height'] as num?)?.toInt() ?? 0;
      return NativeVideoStatus(
        isReady: raw['isReady'] == true || raw['isEnded'] == true,
        isPlaying: raw['isPlaying'] == true,
        duration:
            Duration(milliseconds: (raw['duration'] as num?)?.toInt() ?? 0),
        size: Size(width.toDouble(), height.toDouble()),
        position:
            Duration(milliseconds: (raw['position'] as num?)?.toInt() ?? 0),
      );
    } catch (e) {
      AppLogger.w('VideoPlayer', 'getStatus failed, textureId=$textureId: $e');
      return null;
    }
  }

  /// Applies [status] as if the `initialized` event had been delivered.
  /// Returns true when the native player reported a usable state.
  bool applyStatus(NativeVideoStatus status) {
    if (_disposed || !status.isReady) return false;
    _nativePlaying = status.isPlaying;
    if (!value.isInitialized) {
      _applyInitialized(
        durationMs: status.duration.inMilliseconds,
        width: status.size.width.round(),
        height: status.size.height.round(),
        source: 'status-fallback',
      );
    }
    final contentMs = _contentPositionMs(
      status.position.inMilliseconds,
      durationMs: status.duration.inMilliseconds,
    );
    value = value.copyWith(
      position: Duration(milliseconds: contentMs),
      isPlaying: status.isPlaying,
      isCompleted: status.duration > Duration.zero &&
          contentMs >= status.duration.inMilliseconds,
    );
    return true;
  }

  Future<void> play() async {
    AppLogger.d('VideoPlayer', 'play() -> textureId=$textureId');
    await _channel.invokeMethod('play', {'textureId': textureId});
    _nativePlaying = true;
    value = value.copyWith(isPlaying: true, isCompleted: false);
    _startPositionTimer();
  }

  Future<void> pause() async {
    AppLogger.d('VideoPlayer', 'pause() -> textureId=$textureId');
    await _channel.invokeMethod('pause', {'textureId': textureId});
    _nativePlaying = false;
    value = value.copyWith(isPlaying: false);
    _stopPositionTimer();
  }

  Future<void> seekTo(Duration position) async {
    var contentMs = position.inMilliseconds;
    if (contentMs < 0) contentMs = 0;
    final durationMs = _durationMs;
    if (durationMs > 0 && contentMs > durationMs) contentMs = durationMs;
    // Clips with a leading timeline offset may need the offset added back;
    // _probeSeekAxis() decides which axis the native side uses.
    final timelineMs =
        contentMs + (_seekNeedsTimelineOffset ? _timelineOffsetMs : 0);
    AppLogger.d(
        'VideoPlayer',
        'seekTo(content=${contentMs}ms, native=${timelineMs}ms, '
        'timelineOffset=$_timelineOffsetMs ms) -> textureId=$textureId');
    await _channel.invokeMethod('seekTo', {
      'textureId': textureId,
      'positionMs': timelineMs,
    });
    value = value.copyWith(position: Duration(milliseconds: contentMs));
  }

  Future<void> setVolume(double volume) async {
    final vol = volume.clamp(0.0, 1.0);
    AppLogger.d('VideoPlayer', 'setVolume($vol) -> textureId=$textureId');
    await _channel.invokeMethod('setVolume', {
      'textureId': textureId,
      'volume': vol,
    });
    value = value.copyWith(volume: vol);
  }

  Future<void> setPlaybackSpeed(double speed) async {
    AppLogger.d('VideoPlayer', 'setPlaybackSpeed($speed) -> textureId=$textureId');
    await _channel.invokeMethod('setPlaybackSpeed', {
      'textureId': textureId,
      'speed': speed,
    });
  }

  Future<void> setLooping(bool looping) async {
    // Not directly supported by our simple player; ignore for now
  }

  @override
  Future<void> dispose() async {
    AppLogger.i('VideoPlayer', 'Disposing player, textureId=$textureId');
    _disposed = true;
    _stopPositionTimer();
    _unregister(this);
    try {
      await _channel.invokeMethod('dispose', {'textureId': textureId});
    } catch (e) {
      AppLogger.w('VideoPlayer', 'Error during dispose: $e');
    }
    super.dispose();
  }
}