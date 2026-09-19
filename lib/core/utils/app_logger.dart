import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Simple file-based logger for troubleshooting.
///
/// Writes to `Download/Privi/logs/privi_log_YYYY-MM-DD.txt` and automatically
/// deletes log files older than 7 days on startup.
///
/// The shared Download folder needs "all files access"; when it is not
/// writable (permission reset by a re-install, storage full, folder deleted)
/// the logger falls back to an app-private directory instead of going silent.
///
/// Design rules:
/// * Logging must never throw and never block startup. A broken sink must not
///   take the app down with it.
/// * Entries that could not be written are kept in memory and retried, so a
///   temporary write failure cannot truncate a session's log half way through.
/// * warn/error entries are flushed immediately: a native crash right after an
///   error must not swallow that final line.
/// * A periodic heartbeat proves the process is still alive, which is what
///   tells "the app died" apart from "the logger died".
/// * The user can switch logging off from Settings; a disabled logger is
///   silent in every channel (file, console and in-memory buffer).
enum LogLevel { debug, info, warn, error }

String _pad2(int n) => n.toString().padLeft(2, '0');

/// `YYYY-MM-DD HH:mm:ss.mmm`, used by both log lines and the startup probe.
String _stamp(DateTime time) =>
    '${time.year}-${_pad2(time.month)}-${_pad2(time.day)} '
    '${_pad2(time.hour)}:${_pad2(time.minute)}:${_pad2(time.second)}.'
    '${time.millisecond.toString().padLeft(3, '0')}';

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
    final levelName = level.name.toUpperCase().padRight(5);
    var line = '${_stamp(time)} $levelName [$tag] $message';
    if (stackTrace != null) {
      line += '\n${stackTrace.toString()}';
    }
    return line;
  }
}

class AppLogger {
  AppLogger._();

  static const String _filePrefix = 'privi_log_';

  static final _queue = <_LogEntry>[];
  static bool _flushing = false;
  static List<String> _candidateDirs = const <String>[];
  static int _dirIndex = 0;
  static String? _activeDateKey;
  static IOSink? _sink;
  static Timer? _flushTimer;
  static Timer? _heartbeatTimer;
  static DateTime? _retryAfter;
  static int _writeFailures = 0;
  static int _writtenEntries = 0;
  static int _droppedEntries = 0;
  static String? _sessionId;

  /// Master switch, mirrored by the Settings screen. `false` means "stay
  /// silent": nothing reaches the file, the console or the buffer.
  static bool _enabled = true;

  /// Heartbeat period; kept so the timer can be restarted when logging is
  /// switched back on within the same session.
  static Duration _heartbeatPeriod = const Duration(minutes: 5);

  /// Cap on buffered entries while writes are failing; the oldest lines are
  /// dropped first so the most recent context always survives.
  static const int _pendingMax = 500;

  static String? get _activeDir =>
      _candidateDirs.isEmpty ? null : _candidateDirs[_dirIndex];

  /// Absolute path of the file currently being written, or null when logging
  /// is down.
  static String? get currentLogPath {
    final dir = _activeDir;
    if (dir == null) return null;
    return p.join(dir, '$_filePrefix${_activeDateKey ?? _todayKey()}.txt');
  }

  /// One-line health summary. Cheap enough to log on every app start and on
  /// every heartbeat, so a silent logger becomes visible in the log itself.
  static String get diagnostics => 'file=${currentLogPath ?? 'unavailable'} '
      'enabled=$_enabled '
      'writeFailures=$_writeFailures dropped=$_droppedEntries '
      'written=$_writtenEntries pending=${_queue.length} '
      'session=${_sessionId ?? '-'}';

  /// Must be called once at startup before any other log calls. Never throws.
  ///
  /// [downloadDir] should be `/storage/emulated/0/Download`. [fallbackDirs]
  /// are tried in order when the shared folder cannot be written, e.g. an
  /// app-private directory that always exists.
  static Future<void> init(
    String downloadDir, {
    List<String> fallbackDirs = const <String>[],
    Duration heartbeat = const Duration(minutes: 5),
  }) async {
    _applyConsoleSwitch();
    _sessionId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    _candidateDirs = <String>[
      if (downloadDir.isNotEmpty) p.join(downloadDir, 'Privi', 'logs'),
      for (final dir in fallbackDirs)
        if (dir.isNotEmpty) p.join(dir, 'Privi', 'logs'),
    ];
    _dirIndex = 0;
    _writeFailures = 0;

    var active = false;
    if (_enabled) {
      for (var i = 0; i < _candidateDirs.length; i++) {
        if (await _openDir(i, probe: true)) {
          _dirIndex = i;
          active = true;
          break;
        }
      }
    } else {
      // Logging is switched off: do not even create the folder or an empty
      // file for today. `setEnabled(true)` opens the stream on demand.
      // The console is muted too while the switch is off (see
      // [_applyConsoleSwitch]), so this line is only visible if someone
      // restores Flutter's default printer.
      debugPrint('AppLogger: logging disabled, log file left untouched');
    }

    if (active) {
      await _cleanOldLogs();
      i(
          'AppLogger',
          'log file active: ${currentLogPath ?? '-'} '
              '(session=$_sessionId)');
      if (_candidateDirs.length > 1) {
        d('AppLogger', 'candidate log dirs: ${_candidateDirs.join(' | ')}');
      }
    } else if (_enabled) {
      _retryAfter = DateTime.now().add(const Duration(seconds: 10));
      // Console-only: the failure itself must never be invisible.
      debugPrint('AppLogger: no writable log dir among $_candidateDirs');
    }
    _startHeartbeat(heartbeat);
  }

  /// Call once at shutdown to flush remaining entries.
  static Future<void> dispose() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    await flush();
    try {
      await _sink?.close();
    } catch (error) {
      debugPrint('AppLogger: closing sink failed: $error');
    }
    _sink = null;
  }

  /// Writes everything buffered right now. Safe to call from lifecycle hooks.
  static Future<void> flush() => _flush();

  static void _startHeartbeat(Duration period) {
    _heartbeatPeriod = period;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (period <= Duration.zero || !_enabled) return;
    _heartbeatTimer = Timer.periodic(period, (_) {
      d('Heartbeat', 'alive: $diagnostics');
    });
  }

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${_pad2(now.month)}-${_pad2(now.day)}';
  }

  /// Opens (and verifies) the log file in candidate dir [index]. Returns false
  /// when that directory cannot be written.
  static Future<bool> _openDir(int index, {bool probe = false}) async {
    if (index < 0 || index >= _candidateDirs.length) return false;
    final dir = _candidateDirs[index];
    final filePath = p.join(dir, '$_filePrefix${_todayKey()}.txt');
    IOSink? opened;
    try {
      final directory = Directory(dir);
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
      opened = File(filePath).openWrite(mode: FileMode.append);
      // The probe is the one line written outside the queue, so it has to
      // respect the switch too: "logging off" must leave no trace at all.
      if (probe && _enabled) {
        opened.writeln('${_stamp(DateTime.now())} INFO  [AppLogger] '
            'probe dir=$dir session=$_sessionId');
        await opened.flush();
      }
    } catch (error) {
      debugPrint('AppLogger: cannot use log dir "$dir": $error');
      try {
        await opened?.close();
      } catch (_) {
        // Best effort.
      }
      _sink = null;
      _activeDateKey = null;
      return false;
    }

    final previous = _sink;
    _sink = opened;
    _activeDateKey = _todayKey();
    _retryAfter = null;
    _writeFailures = 0;
    try {
      await previous?.close();
    } catch (error) {
      debugPrint('AppLogger: closing previous sink failed: $error');
    }
    return true;
  }

  /// Makes sure a writable sink for today exists.
  static Future<bool> _ensureStream() async {
    if (_sink != null && _activeDateKey == _todayKey()) return true;

    if (_sink != null) {
      // Date rolled over: reopen in the directory that is already working.
      if (await _openDir(_dirIndex)) return true;
    }

    final retryAfter = _retryAfter;
    if (_sink == null &&
        retryAfter != null &&
        DateTime.now().isBefore(retryAfter)) {
      return false;
    }

    for (var attempt = 0; attempt < _candidateDirs.length; attempt++) {
      final index = (_dirIndex + attempt) % _candidateDirs.length;
      if (await _openDir(index)) {
        final switched = index != _dirIndex;
        _dirIndex = index;
        if (switched) {
          _enqueue(
            LogLevel.warn,
            'AppLogger',
            'log file switched to ${currentLogPath ?? '-'}',
          );
        }
        return true;
      }
    }

    _writeFailures++;
    _retryAfter = DateTime.now().add(_retryDelay());
    return false;
  }

  static Duration _retryDelay() =>
      Duration(seconds: (5 * _writeFailures).clamp(5, 120));

  static Future<void> _flush() async {
    if (_queue.isEmpty) return;
    if (_flushing) return;
    _flushing = true;
    final batch = List<_LogEntry>.from(_queue);
    _queue.clear();
    try {
      if (_candidateDirs.isEmpty) {
        _droppedEntries += batch.length;
        return;
      }
      if (!await _ensureStream()) {
        _requeue(batch);
        return;
      }
      final sink = _sink;
      if (sink == null) {
        _requeue(batch);
        return;
      }
      for (final entry in batch) {
        sink.writeln(entry.toString());
      }
      await sink.flush();
      _writtenEntries += batch.length;
    } catch (error) {
      _writeFailures++;
      // Keep the lines: a transient failure must not eat the diagnostics.
      _requeue(batch);
      try {
        await _sink?.close();
      } catch (_) {
        // Best effort.
      }
      _sink = null;
      _activeDateKey = null;
      _retryAfter = DateTime.now().add(_retryDelay());
      debugPrint('AppLogger: flush failed (${_writeFailures}x): $error');
    } finally {
      _flushing = false;
    }
  }

  /// Puts a failed batch back at the front, dropping the oldest overflow.
  static void _requeue(List<_LogEntry> batch) {
    if (batch.isEmpty) return;
    final room = _pendingMax - _queue.length;
    if (room <= 0) {
      _droppedEntries += batch.length;
      return;
    }
    if (batch.length > room) {
      _droppedEntries += batch.length - room;
      _queue.insertAll(0, batch.sublist(batch.length - room));
      return;
    }
    _queue.insertAll(0, batch);
  }

  static void _enqueue(
    LogLevel level,
    String tag,
    String message, [
    StackTrace? stackTrace,
  ]) {
    // Cheapest possible gate, and the only one needed: every public log call
    // funnels through here, so a disabled logger cannot write or print.
    if (!_enabled) return;

    final entry = _LogEntry(
      time: DateTime.now(),
      level: level,
      tag: tag,
      message: message,
      stackTrace: stackTrace,
    );

    // Also print to console (visible through `flutter run` / adb logcat even
    // when the file itself cannot be written).
    debugPrint(entry.toString());

    if (_queue.length >= _pendingMax) {
      _queue.removeAt(0);
      _droppedEntries++;
    }
    _queue.add(entry);

    // Warnings and errors are the lines a post-mortem needs most, so they hit
    // the disk immediately instead of waiting for the periodic flush.
    if (level == LogLevel.error ||
        level == LogLevel.warn ||
        _queue.length >= 20) {
      unawaited(_flush());
    } else {
      _scheduleFlush();
    }
  }

  static void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(seconds: 2), () {
      _flushTimer = null;
      unawaited(_flush());
    });
  }

  // ---- Auto-cleanup ----

  static Future<void> _cleanOldLogs() async {
    final dirPath = _activeDir;
    if (dirPath == null) return;
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return;
      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (!name.startsWith(_filePrefix) || !name.endsWith('.txt')) continue;
        final dateStr =
            name.substring(_filePrefix.length, name.length - '.txt'.length);
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

  /// Whether logging to file/console is currently on.
  static bool get enabled => _enabled;

  /// Turns logging on or off at runtime (Settings > 诊断).
  ///
  /// Switching off drops the buffered backlog and stops the heartbeat as well,
  /// so that not a single line is written after the switch. The global
  /// [debugPrint] callback is muted as well, which also silences the framework.
  /// Switching on again resumes logging in the same session.
  static void setEnabled(bool value) {
    if (_enabled == value) return;
    _enabled = value;
    if (!value) {
      _queue.clear();
      _flushTimer?.cancel();
      _flushTimer = null;
      _heartbeatTimer?.cancel();
      _heartbeatTimer = null;
      debugPrint('AppLogger: logging disabled by user setting');
      _applyConsoleSwitch();
      return;
    }
    _applyConsoleSwitch();
    debugPrint('AppLogger: logging enabled');
    _enqueue(
      LogLevel.info,
      'AppLogger',
      'logging enabled (session=$_sessionId)',
    );
    _startHeartbeat(_heartbeatPeriod);
  }

  /// Mirrors the switch onto the global [debugPrint] callback.
  ///
  /// Every diagnostic in the app funnels through [d]/[i]/[w]/[e], but the
  /// framework and the plugins keep printing on their own (layout overflows,
  /// image decode errors, ...). The setting promises that nothing at all is
  /// printed, so the console callback is muted here and restored to Flutter's
  /// default throttled printer as soon as logging comes back on.
  static void _applyConsoleSwitch() {
    debugPrint = _enabled ? debugPrintThrottled : _silentDebugPrint;
  }

  /// Sink for [debugPrint] while logging is off: the promise is "not a line".
  static void _silentDebugPrint(String? message, {int? wrapWidth}) {}

  static void d(String tag, String message) =>
      _enqueue(LogLevel.debug, tag, message);

  static void i(String tag, String message) =>
      _enqueue(LogLevel.info, tag, message);

  static void w(String tag, String message) =>
      _enqueue(LogLevel.warn, tag, message);

  static void e(String tag, String message, [StackTrace? stackTrace]) =>
      _enqueue(LogLevel.error, tag, message, stackTrace);
}
