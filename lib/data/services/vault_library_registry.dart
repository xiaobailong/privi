import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import 'hide_naming.dart';

/// One user-added insurance-vault directory.
///
/// The built-in `.privateheart_vault` root is deliberately **not** stored here:
/// its path is derived by `VaultStorageService` and can change with the storage
/// volume. Storing it would freeze a stale absolute path.
class VaultLibraryEntry {
  const VaultLibraryEntry({
    required this.id,
    required this.path,
    required this.name,
    required this.addedAt,
  });

  final String id;
  final String path;
  final String name;
  final DateTime addedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'name': name,
        'addedAt': addedAt.toIso8601String(),
      };

  static VaultLibraryEntry? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final path = raw['path'];
    if (id is! String || id.isEmpty || path is! String || path.isEmpty) {
      return null;
    }
    final name = raw['name'];
    final addedAt = DateTime.tryParse(raw['addedAt']?.toString() ?? '');
    return VaultLibraryEntry(
      id: id,
      path: path,
      name: name is String && name.isNotEmpty ? name : p.basename(path),
      addedAt: addedAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

/// Persistent registry of extra vault directories.
///
/// Multiple libraries coexist: every registered root is scanned and every
/// `privatePath` under any of them is a valid library item. One library is the
/// *active* write target for new hides; the built-in one stays available so an
/// older vault and a migrated directory can be used side by side.
///
/// Stored in `SharedPreferences`, which means a v6 archive backup carries the
/// list automatically. Paths from another phone may not exist here; the UI
/// marks those as unavailable instead of dropping them, so re-adding a copied
/// directory on the new device is a one-tap fix.
class VaultLibraryRegistry extends ChangeNotifier {
  VaultLibraryRegistry(this._prefs) {
    // No listeners exist yet (Riverpod attaches them after construction), so
    // the initial load must not notify during the provider's build phase.
    _load(notify: false);
  }

  static const String builtInId = 'builtin';
  static const String librariesKey = 'vault_libraries_v1';
  static const String activeKey = 'vault_active_library_v1';

  final SharedPreferences _prefs;

  List<VaultLibraryEntry> _entries = [];
  String _activeId = builtInId;

  List<VaultLibraryEntry> get userLibraries => List.unmodifiable(_entries);
  String get activeId => _activeId;
  bool get hasUserLibraries => _entries.isNotEmpty;

  /// Absolute paths of the extra roots (existence is checked by consumers).
  List<String> get rootPaths => List.unmodifiable(
        _entries.map((entry) => entry.path),
      );

  String? pathFor(String id) {
    if (id == builtInId) return null;
    for (final entry in _entries) {
      if (entry.id == id) return entry.path;
    }
    return null;
  }

  VaultLibraryEntry? entryFor(String id) {
    for (final entry in _entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  bool ownsPath(String path) {
    final normalized = _normalize(path);
    for (final root in rootPaths) {
      if (_within(root, normalized)) return true;
    }
    return false;
  }

  Future<void> add({
    required String path,
    required String name,
  }) async {
    final entry = VaultLibraryEntry(
      id: _newId(),
      path: _normalize(path),
      name: name.trim().isEmpty ? p.basename(path) : name.trim(),
      addedAt: DateTime.now().toUtc(),
    );
    _entries = [..._entries, entry];
    await _persist();
  }

  Future<void> remove(String id) async {
    if (id == builtInId) return;
    _entries = _entries.where((entry) => entry.id != id).toList();
    if (_activeId == id) _activeId = builtInId;
    await _persist();
  }

  Future<void> rename(String id, String name) async {
    _entries = _entries
        .map(
          (entry) => entry.id == id
              ? VaultLibraryEntry(
                  id: entry.id,
                  path: entry.path,
                  name: name,
                  addedAt: entry.addedAt,
                )
              : entry,
        )
        .toList();
    await _persist();
  }

  Future<void> setActive(String id) async {
    if (id != builtInId && entryFor(id) == null) return;
    _activeId = id;
    await _persist();
  }

  /// Re-reads the preference (used after an archive restore rewrote settings).
  void reload() => _load();

  void _load({bool notify = true}) {
    List<VaultLibraryEntry> parsed = [];
    try {
      final raw = _prefs.getString(librariesKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          parsed = decoded
              .map(VaultLibraryEntry.tryParse)
              .whereType<VaultLibraryEntry>()
              .toList(growable: false);
        }
      }
    } catch (_) {
      parsed = [];
    }
    final seenIds = <String>{};
    final seenPaths = <String>{};
    _entries = [
      for (final entry in parsed)
        if (seenIds.add(entry.id) && seenPaths.add(_normalize(entry.path)))
          entry,
    ];
    final storedActive = _prefs.getString(activeKey);
    _activeId = (storedActive != null &&
            (storedActive == builtInId || entryFor(storedActive) != null))
        ? storedActive
        : builtInId;
    _syncHideNaming();
    if (notify) notifyListeners();
  }

  Future<void> _persist() async {
    await _prefs.setString(
      librariesKey,
      jsonEncode(_entries.map((entry) => entry.toJson()).toList()),
    );
    await _prefs.setString(activeKey, _activeId);
    _syncHideNaming();
    notifyListeners();
  }

  void _syncHideNaming() {
    HideNaming.extraVaultRoots = rootPaths.toSet();
  }

  static String _newId() {
    final random = Random.secure();
    return 'lib_${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}_'
        '${random.nextInt(1 << 32).toRadixString(16)}';
  }

  static String _normalize(String path) =>
      p.normalize(path.trim().replaceAll('\\', '/'));

  static bool _within(String root, String path) {
    final a = _normalize(root);
    if (p.equals(a, path)) return true;
    return p.isWithin(a, path);
  }
}

/// Why a picked directory cannot become a vault library.
enum VaultLibraryPathIssue {
  ok,
  empty,
  missing,
  notDirectory,
  unreadable,
  duplicate,
  nested,
  reserved,
}

class VaultLibraryPathCheck {
  const VaultLibraryPathCheck(this.issue, {this.normalizedPath});

  final VaultLibraryPathIssue issue;
  final String? normalizedPath;

  bool get ok => issue == VaultLibraryPathIssue.ok;
}
