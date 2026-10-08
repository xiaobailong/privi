import 'package:shared_preferences/shared_preferences.dart';

class VideoResumeService {
  static const _prefix = 'vr_';
  static const _completionRatio = 0.95;

  static String _key(String itemId) => '$_prefix$itemId';

  static int? getPositionMs(SharedPreferences prefs, String itemId) {
    return prefs.getInt(_key(itemId));
  }

  static Future<void> savePositionMs(
    SharedPreferences prefs,
    String itemId,
    int positionMs,
    int durationMs,
  ) async {
    if (durationMs > 0 && positionMs >= durationMs * _completionRatio) {
      await prefs.remove(_key(itemId));
    } else {
      await prefs.setInt(_key(itemId), positionMs);
    }
  }

  static Future<void> clear(SharedPreferences prefs, String itemId) async {
    await prefs.remove(_key(itemId));
  }
}