import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/enums.dart';
import '../providers.dart';

/// User-chosen type (photos-only / videos-only) per private album.
///
/// Stored outside the Drift schema on purpose: the type is a UI preference, so
/// no database migration is needed and albums created before typing simply stay
/// untyped and keep showing images + videos together.
class AlbumKindPreferences {
  AlbumKindPreferences(Map<String, AlbumKind> kinds)
      : kinds = Map.unmodifiable(kinds);

  factory AlbumKindPreferences.defaults() =>
      AlbumKindPreferences(const <String, AlbumKind>{});

  final Map<String, AlbumKind> kinds;

  /// Null = untyped album (system albums, legacy user albums).
  AlbumKind? kindOf(String albumId) => kinds[albumId];

  AlbumKindPreferences withKind(String albumId, AlbumKind kind) =>
      AlbumKindPreferences({...kinds, albumId: kind});

  AlbumKindPreferences withoutAlbum(String albumId) =>
      AlbumKindPreferences({...kinds}..remove(albumId));
}

class AlbumKindPreferencesController extends Notifier<AlbumKindPreferences> {
  static const storageKey = 'album_kind_preferences_v1';
  Future<void> _pendingWrite = Future.value();

  @override
  AlbumKindPreferences build() {
    final preferences = ref.watch(sharedPreferencesProvider);
    final raw = preferences.getString(storageKey);
    return raw == null ? AlbumKindPreferences.defaults() : _decode(raw);
  }

  /// Records the type of a freshly created (or renamed-by-type) album.
  Future<void> setKind(String albumId, AlbumKind kind) =>
      _commit(state.withKind(albumId, kind));

  /// Drops the stored type once the album is gone.
  Future<void> forget(String albumId) => _commit(state.withoutAlbum(albumId));

  Future<void> _commit(AlbumKindPreferences next) {
    state = next;
    final preferences = ref.read(sharedPreferencesProvider);
    final encoded = _encode(next);
    _pendingWrite = _pendingWrite.then((_) async {
      if (!await preferences.setString(storageKey, encoded)) {
        throw StateError('Could not persist album kind preferences');
      }
    });
    return _pendingWrite;
  }

  static String _encode(AlbumKindPreferences value) => jsonEncode({
        for (final entry in value.kinds.entries) entry.key: entry.value.name,
      });

  static AlbumKindPreferences _decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid album kind preferences');
    }
    final kinds = <String, AlbumKind>{};
    for (final entry in decoded.entries) {
      final value = entry.value;
      if (value is! String) {
        throw const FormatException('Album kinds must be strings');
      }
      try {
        kinds[entry.key] = AlbumKind.values.byName(value);
      } on StateError {
        throw FormatException('Unknown album kind: $value');
      }
    }
    return AlbumKindPreferences(kinds);
  }
}

final albumKindPreferencesProvider = NotifierProvider<
    AlbumKindPreferencesController, AlbumKindPreferences>(
  AlbumKindPreferencesController.new,
);
