import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Window brightness, keep-screen-on and system media volume for the in-player
/// swipe gestures.
abstract class VideoDisplayControls {
  Future<double> getBrightness();
  Future<void> setBrightness(double value);
  Future<void> resetBrightness();
  Future<double> getVolume();
  Future<void> setVolume(double value);

  /// FLAG_KEEP_SCREEN_ON — stops the system from sleeping during playback.
  Future<void> setKeepScreenOn(bool enabled);
}

class PlaybackDisplayService implements VideoDisplayControls {
  PlaybackDisplayService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.privi.app/window');

  static PlaybackDisplayService instance = PlaybackDisplayService();

  final MethodChannel _channel;

  @override
  Future<double> getBrightness() => _readUnit('getBrightness');

  @override
  Future<void> setBrightness(double value) {
    return _writeUnit('setBrightness', value);
  }

  @override
  Future<void> resetBrightness() async {
    try {
      await _channel.invokeMethod<void>('resetBrightness');
    } catch (error, stackTrace) {
      debugPrint('resetBrightness: $error\n$stackTrace');
    }
  }

  @override
  Future<double> getVolume() => _readUnit('getVolume');

  @override
  Future<void> setVolume(double value) => _writeUnit('setVolume', value);

  @override
  Future<void> setKeepScreenOn(bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setKeepScreenOn', {
        'enabled': enabled,
      });
    } catch (error, stackTrace) {
      debugPrint('setKeepScreenOn: $error\n$stackTrace');
    }
  }

  Future<double> _readUnit(String method) async {
    try {
      final value = await _channel.invokeMethod<num>(method);
      return (value?.toDouble() ?? 0.5).clamp(0.0, 1.0);
    } catch (error, stackTrace) {
      debugPrint('$method: $error\n$stackTrace');
      return 0.5;
    }
  }

  Future<void> _writeUnit(String method, double value) async {
    try {
      await _channel.invokeMethod<void>(method, {
        'value': value.clamp(0.0, 1.0),
      });
    } catch (error, stackTrace) {
      debugPrint('$method: $error\n$stackTrace');
    }
  }
}
