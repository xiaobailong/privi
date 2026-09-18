import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Simple file-based logger for troubleshooting.
///
/// Writes to `Download/Privi/logs/privi_log_YYYY-MM-DD.txt` and automatically
/// deletes log files older than 7 days on startup.
enum LogLevel { debug, info, warn, error }

class _LogEntry {
  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;
  final StackTrace? stackTrace;

  const _LogEntry({
    required this.time,
    required this.level,
    required this.tag,
    required this.message,
    this.stackTrace,
  });

  @override
  String toString() {
    final ts =
        '${time.year}-${_pad2(time.month)}-${_pad2(time.day)} '
        '${_pad2(time.hour)}:${_pad2(time.minute)}:${_pad2(time.second)}.'
        '${time.millisecond.toString().padLeft(3, '0')}';
    final levelName = level.name.toUpperCase().padRight(5);
    var line = '$ts $levelName [$tag] $message';
    if (stackTrace != null) {
      line += '\n${stackTrace.toString()}';
    }
    return line;
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');
}

class AppLogger {
  AppLogger._();

  static final _queue = <_LogEntry>[];
  static bool _flushing = false;
  static String? _logDir;
  static String? _activeDateKey;
  static IOSink? _sink;
  static Timer? _flushTimer;

  /// Must be called once at startup before any other log calls.
  /// [downloadDir] should be `/storage/emulated/0/Download`.
  static Future<void> init(String downloadDir) async {
    _logDir = p.join(downloadDir, 'Privi', 'logs');
    final dir = Directory(_logDir!);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await _cleanOldLogs();
    info('AppLogger', 'Logger initialized, logDir=$_logDir');
  }

  /// Call once at shutdown to flush remaining entries.
  static Future<void> dispose() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _flush();
    await _sink?.close();
    _sink = null;
  }

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${_pad2(now.month)}-${_pad2(now.day)}';
  }

  static String _pad2(int n) => n.toString().padLeft(2, '0');

  static void _ensureStream() {
    final key = _todayKey();
    if (_sink != null && _activeDateKey == key) return;

    _sink?.close();
    _sink = null;

    final filePath = p.join(_logDir!, 'privi_log_$key.txt');
    _activeDateKey = key;
    _sink = File(filePath).openWrite(mode: FileMode.append);
  }

  static Future<void> _flush() async {
    if (_queue.isEmpty) return;
    if (_flushing) return;
    _flushing = true;
    try {
      if (_logDir == null) return;
      _ensureStream();
      final batch = List<_LogEntry>.from(_queue);
      _queue.clear();
      for (final entry in batch) {
        _sink?.writeln(entry.toString());
      }
      await _sink?.flush();
    } finally {
      _flushing = false;
    }
  }

  static void _enqueue(LogLevel level, String tag, String message,
      [StackTrace? stackTrace]) {
    final entry = _LogEntry(
      time: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      stackTrace: stackTrace,
    );

    // Also print to console
    if (level == LogLevel.error) {
      debugPrint(entry.toString());
    } else {
      debugPrint(entry.toString());
    }

    _queue.add(entry);
    if (_queue.length >= 20) {
      unawaited(_flush());
    } else {
      _scheduleFlush();
    }
  }

  static void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(seconds: 5), () {
      _flushTimer = null;
      unawaited(_flush());
    });
  }

  // ---- Auto-cleanup ----

  static Future<void> _cleanOldLogs() async {
    if (_logDir == null) return;
    try {
      final dir = Directory(_logDir!);
      if (!await dir.exists()) return;
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.startsWith('privi_log_') || !name.endsWith('.txt')) continue;
        final dateStr =
            name.substring('privi_log_'.length, name.length - '.txt'.length);
        final parts = dateStr.split('-');
        if (parts.length != 3) continue;
        final y = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        final d = int.tryParse(parts[2]);
        if (y == null || m == null || d == null) continue;
        final fileDate = DateTime(y, m, d);
        if (fileDate.isBefore(cutoff)) {
          await entity.delete();
          debugPrint('AppLogger: deleted old log $name');
        }
      }
    } catch (_) {
      // Best-effort cleanup
    }
  }

  // ---- Public API ----

  static void d(String tag, String message) =>
      _enqueue(LogLevel.debug, tag, message);

  static void i(String tag, String message) =>
      _enqueue(LogLevel.info, tag, message);

  static void w(String tag, String message) =>
      _enqueue(LogLevel.warn, tag, message);

  static void e(String tag, String message,
          [StackTrace? stackTrace]) =>
      _enqueue(LogLevel.error, tag, message, stackTrace);
}