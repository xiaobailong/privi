import 'package:flutter/services.dart';
import '../../core/utils/app_logger.dart';

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

  /// The player's own request (mirrored by the video screens' build()).
  bool _playbackWants = false;

  /// Long-running tasks that must not be interrupted by the device locking:
  /// batch encryption and the encryption pass after an import.  Losing the
  /// foreground mid-encryption can kill the app and leave ciphertext behind
  /// without its DEK (see ISSUE-030 / PIT-044).
  final Set<String> _taskHolders = <String>{};

  /// Last value actually pushed to the platform channel.
  bool? _applied;

  /// True while some long task is holding the screen on.
  bool get keepScreenOnHeldByTask => _taskHolders.isNotEmpty;

  bool get _wantsKeepScreenOn => _playbackWants || _taskHolders.isNotEmpty;

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
      AppLogger.e(
          'PlaybackDisplayService', 'resetBrightness: $error\n$stackTrace');
    }
  }

  @override
  Future<double> getVolume() => _readUnit('getVolume');

  @override
  Future<void> setVolume(double value) => _writeUnit('setVolume', value);

  /// Playback asks for / gives up the wake lock.
  ///
  /// Routed through the arbiter so a player screen shutting down no longer
  /// clears the flag while a long task still needs the screen on.
  @override
  Future<void> setKeepScreenOn(bool enabled) {
    _playbackWants = enabled;
    return _applyKeepScreenOn();
  }

  /// Keeps the screen awake while [holder] runs long work (idempotent).
  Future<void> holdScreenOn(String holder) {
    _taskHolders.add(holder);
    return _applyKeepScreenOn();
  }

  /// Drops [holder]'s hold; the flag follows whatever remains (idempotent).
  Future<void> releaseScreenOn(String holder) {
    _taskHolders.remove(holder);
    return _applyKeepScreenOn();
  }

  Future<void> _applyKeepScreenOn() async {
    final wanted = _wantsKeepScreenOn;
    if (_applied == wanted) return;
    try {
      await _channel.invokeMethod<void>('setKeepScreenOn', {
        'enabled': wanted,
      });
      _applied = wanted;
    } catch (error, stackTrace) {
      // Leave _applied unset so the next request retries.
      _applied = null;
      AppLogger.e(
          'PlaybackDisplayService', 'setKeepScreenOn: $error\n$stackTrace');
    }
  }

  Future<double> _readUnit(String method) async {
    try {
      final value = await _channel.invokeMethod<num>(method);
      return (value?.toDouble() ?? 0.5).clamp(0.0, 1.0);
    } catch (error, stackTrace) {
      AppLogger.e('PlaybackDisplayService', '$method: $error\n$stackTrace');
      return 0.5;
    }
  }

  Future<void> _writeUnit(String method, double value) async {
    try {
      await _channel.invokeMethod<void>(method, {
        'value': value.clamp(0.0, 1.0),
      });
    } catch (error, stackTrace) {
      AppLogger.e('PlaybackDisplayService', '$method: $error\n$stackTrace');
    }
  }
}
