import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

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

  final int textureId;
  final String filePath;

  bool _disposed = false;
  int _durationMs = 0;
  int _width = 0;
  int _height = 0;
  bool _nativePlaying = false;

  StreamSubscription<dynamic>? _eventSubscription;
  Timer? _positionTimer;

  VoidCallback? onCompleted;
  VoidCallback? onError;

  NativeVideoController._({
    required this.textureId,
    required this.filePath,
  }) : super(const NativeVideoValue());

  static Future<NativeVideoController> create(String filePath) async {
    final textureId = await _channel.invokeMethod<int>('create', {
      'filePath': filePath,
    });
    if (textureId == null) {
      throw Exception('Failed to create native video player');
    }
    final controller = NativeVideoController._(
      textureId: textureId,
      filePath: filePath,
    );
    controller._listenForEvents();
    return controller;
  }

  void _listenForEvents() {
    _eventSubscription = _channel.setMethodCallHandler((call) {
      if (_disposed) return;
      switch (call.method) {
        case 'initialized':
          final data = call.arguments as Map?;
          _durationMs = data?['duration'] as int? ?? 0;
          _width = data?['width'] as int? ?? 0;
          _height = data?['height'] as int? ?? 0;
          value = value.copyWith(
            isInitialized: true,
            duration: Duration(milliseconds: _durationMs),
            size: Size(_width.toDouble(), _height.toDouble()),
          );
          _startPositionTimer();
          break;
        case 'completed':
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
          value = value.copyWith(
            hasError: true,
            isPlaying: false,
            errorDescription:
                data?['message'] as String? ?? 'Unknown playback error',
          );
          _stopPositionTimer();
          onError?.call();
          break;
        case 'playingChanged':
          final data = call.arguments as Map?;
          _nativePlaying = data?['isPlaying'] as bool? ?? false;
          value = value.copyWith(isPlaying: _nativePlaying);
          if (_nativePlaying) {
            _startPositionTimer();
          } else {
            _stopPositionTimer();
          }
          break;
      }
    });
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
    _disposed = true;
    _stopPositionTimer();
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    try {
      await _channel.invokeMethod('dispose', {'textureId': textureId});
    } catch (_) {}
    super.dispose();
  }
}