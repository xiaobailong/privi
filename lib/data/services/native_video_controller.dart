import 'dart:async';
import 'dart:math';

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

class NativeVideoController extends ValueNotifier<NativeVideoValue> {
  static const _channel = MethodChannel('com.privi.app/video_player');

  /// Live controllers keyed by native texture id. The platform channel has a
  /// single process-wide inbound handler, so native events are routed here.
  static final Map<int, NativeVideoController> _registry =
      <int, NativeVideoController>{};

  /// Installs the shared inbound handler. It is re-installed whenever a player
  /// is registered, so a late dispose() of an older controller can never leave
  /// the newest controller without an event handler.
  static void _register(NativeVideoController controller) {
    _registry[controller.textureId] = controller;
    _channel.setMethodCallHandler(_dispatch);
    AppLogger.d('VideoPlayer',
        'Event handler installed for textureId=${controller.textureId} (live=${_registry.length})');
  }

  static void _unregister(NativeVideoController controller) {
    if (identical(_registry[controller.textureId], controller)) {
      _registry.remove(controller.textureId);
    }
    if (_registry.isEmpty) {
      _channel.setMethodCallHandler(null);
    } else {
      // Keep the channel alive for the controllers that are still alive.
      _channel.setMethodCallHandler(_dispatch);
    }
    AppLogger.d('VideoPlayer',
        'Event handler released for textureId=${controller.textureId} (live=${_registry.length})');
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
    final target = textureId == null ? null : _registry[textureId];
    if (target == null) {
      AppLogger.d('VideoPlayer',
          'Ignoring ${call.method}: no live controller for textureId=$textureId');
      return;
    }
    target._handleCall(call);
  }

  final int textureId;
  final String filePath;

  bool _disposed = false;
  int _durationMs = 0;
  int _width = 0;
  int _height = 0;
  bool _nativePlaying = false;

  Timer? _positionTimer;

  VoidCallback? onCompleted;
  VoidCallback? onError;

  NativeVideoController._({
    required this.textureId,
    required this.filePath,
  }) : super(const NativeVideoValue());

  static Future<NativeVideoController> create(String filePath) async {
    AppLogger.i('VideoPlayer', 'Creating native player for: $filePath');
    try {
      final textureId = await _channel.invokeMethod<int>('create', {
        'filePath': filePath,
      });
      if (textureId == null) {
        AppLogger.e('VideoPlayer', 'Failed to create native player: textureId is null');
        throw Exception('Failed to create native video player');
      }
      AppLogger.i('VideoPlayer', 'Native player created, textureId=$textureId');
      final controller = NativeVideoController._(
        textureId: textureId,
        filePath: filePath,
      );
      _register(controller);
      return controller;
    } catch (e, st) {
      AppLogger.e('VideoPlayer', 'Exception creating native player: $e', st);
      rethrow;
    }
  }

  void _handleCall(MethodCall call) {
    if (_disposed) return;
    switch (call.method) {
        case 'initialized':
          final data = call.arguments as Map?;
          _durationMs = data?['duration'] as int? ?? 0;
          _width = data?['width'] as int? ?? 0;
          _height = data?['height'] as int? ?? 0;
          AppLogger.i('VideoPlayer',
              'Initialized: duration=${_durationMs}ms, '
              'size=${_width}x$_height, textureId=$textureId');
          value = value.copyWith(
            isInitialized: true,
            duration: Duration(milliseconds: _durationMs),
            size: Size(_width.toDouble(), _height.toDouble()),
          );
          _startPositionTimer();
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
          value = value.copyWith(
            hasError: true,
            isPlaying: false,
            errorDescription: msg,
          );
          _stopPositionTimer();
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
    try {
      final posMs = await _channel.invokeMethod<int>('getPosition', {
        'textureId': textureId,
      });
      if (!_disposed && posMs != null) {
        value = value.copyWith(
          position: Duration(milliseconds: posMs),
        );
      }
    } catch (_) {}
  }

  Future<void> play() async {
    await _channel.invokeMethod('play', {'textureId': textureId});
    _nativePlaying = true;
    value = value.copyWith(isPlaying: true, isCompleted: false);
    _startPositionTimer();
  }

  Future<void> pause() async {
    await _channel.invokeMethod('pause', {'textureId': textureId});
    _nativePlaying = false;
    value = value.copyWith(isPlaying: false);
    _stopPositionTimer();
  }

  Future<void> seekTo(Duration position) async {
    await _channel.invokeMethod('seekTo', {
      'textureId': textureId,
      'positionMs': position.inMilliseconds,
    });
    value = value.copyWith(position: position);
  }

  Future<void> setVolume(double volume) async {
    final vol = volume.clamp(0.0, 1.0);
    await _channel.invokeMethod('setVolume', {
      'textureId': textureId,
      'volume': vol,
    });
    value = value.copyWith(volume: vol);
  }

  Future<void> setPlaybackSpeed(double speed) async {
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