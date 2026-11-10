part of 'vault_backup_service.dart';

/// One standalone SQLite database holding the whole data-only vault backup.
///
/// `ADR-049` had replaced the old key package with a JSON manifest; `ADR-053`
/// puts the structured container back: every media row, album, group,
/// membership, KEK of the key ring and every app setting lives in a table, so
/// the file can be inspected (and later merged) with any SQLite tool and can
/// grow new columns without rewriting the whole document.
///
/// The file is deliberately self-contained: `journal_mode = DELETE` keeps it a
/// single `.db` without `-wal` / `-shm` siblings, exactly like the legacy key
/// package (`KeyBackupService`).  It carries **plaintext KEKs**, so the export
/// warning in the UI must stay.
final class _VaultBackupDatabaseCodec {
  const _VaultBackupDatabaseCodec();

  /// Written to `meta.format`; distinguishes this file from a key package
  /// (`privi-key-backup`), which uses the same `.db` extension.
  static const String formatTag = 'privi-vault-data';

  /// Container schema version, independent of
  /// [VaultBackupService.manifestVersion] (the semantic layout of the rows).
  static const int formatVersion = 1;

  static const String fileExtension = '.db';

  /// `privi-vault-YYYYMMDD-HHMMSS.db` — the export date is readable from the
  /// file name, same convention as the legacy key package.
  static const String fileNamePrefix = 'privi-vault-';

  static const String _schemaSql = '''
CREATE TABLE meta (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT
);
CREATE TABLE media (
  id TEXT PRIMARY KEY NOT NULL,
  position INTEGER NOT NULL,
  file_name TEXT NOT NULL,
  thumbnail_name TEXT,
  sha256 TEXT,
  byte_length INTEGER,
  original_path TEXT,
  source_platform TEXT,
  source_library_id TEXT,
  source_removal_pending INTEGER NOT NULL DEFAULT 0,
  content_digest TEXT,
  original_name TEXT,
  mime_type TEXT,
  is_video INTEGER,
  width INTEGER,
  height INTEGER,
  duration_ms INTEGER,
  rating INTEGER,
  date_added TEXT,
  date_taken TEXT,
  size_bytes INTEGER,
  deleted_at TEXT,
  encrypted_dek TEXT,
  encryption_key_id TEXT,
  private_path TEXT,
  thumbnail_path TEXT,
  play_count INTEGER,
  last_played_at TEXT
);
CREATE TABLE albums (
  id TEXT PRIMARY KEY NOT NULL,
  position INTEGER NOT NULL,
  name TEXT,
  is_system INTEGER NOT NULL DEFAULT 1,
  cover_media_id TEXT,
  created_at TEXT,
  system_kind TEXT,
  pinned_at TEXT,
  rating INTEGER,
  sort_index INTEGER,
  group_id TEXT
);
CREATE TABLE album_groups (
  id TEXT PRIMARY KEY NOT NULL,
  position INTEGER NOT NULL,
  name TEXT,
  created_at TEXT,
  sort_index INTEGER
);
CREATE TABLE memberships (
  album_id TEXT NOT NULL,
  media_id TEXT NOT NULL,
  added_at TEXT,
  position INTEGER NOT NULL,
  PRIMARY KEY (album_id, media_id)
);
CREATE TABLE encryption_keys (
  id TEXT PRIMARY KEY NOT NULL,
  position INTEGER NOT NULL,
  kek TEXT NOT NULL,
  fingerprint TEXT NOT NULL,
  created_at TEXT,
  label TEXT,
  salt TEXT,
  is_default INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE app_settings (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT
);
''';

  String suggestedFileName(DateTime now) {
    final utc = now.toUtc();
    String two(int value) => value.toString().padLeft(2, '0');
    return '$fileNamePrefix${utc.year}${two(utc.month)}${two(utc.day)}'
        '-${two(utc.hour)}${two(utc.minute)}${two(utc.second)}$fileExtension';
  }

  /// True when [file] is a vault data container (and not a legacy key package,
  /// which shares the `.db` extension).
  Future<bool> hasFormat(File file) async {
    sqlite.Database? db;
    try {
      db = sqlite.sqlite3.open(file.path, mode: sqlite.OpenMode.readOnly);
      final rows = db.select(
        'SELECT value FROM meta WHERE key = ? LIMIT 1',
        ['format'],
      );
      return rows.isNotEmpty && rows.first['value'] == formatTag;
    } catch (_) {
      return false;
    } finally {
      db?.dispose();
    }
  }

  Future<void> write(File file, _BackupManifest manifest) async {
    sqlite.Database? db;
    try {
      db = sqlite.sqlite3.open(file.path);
      // Keep the backup a single self-contained file (no -wal / -shm
      // siblings) so copying one file is enough to migrate.
      db.execute('PRAGMA journal_mode = DELETE');
      db.execute('PRAGMA user_version = $formatVersion');
      db.execute(_schemaSql);
      db.execute('BEGIN');
      try {
        _writeMeta(db, manifest);
        _writeMedia(db, manifest.media);
        _writeAlbums(db, manifest.albums);
        _writeGroups(db, manifest.groups);
        _writeMemberships(db, manifest.memberships);
        _writeKeys(db, manifest.encryptionKeys);
        _writeSettings(db, manifest.appSettings);
        db.execute('COMMIT');
      } catch (_) {
        try {
          db.execute('ROLLBACK');
        } catch (_) {
          // The transaction may already be gone; the file is deleted below.
        }
        rethrow;
      }
    } catch (error) {
      db?.dispose();
      db = null;
      // Never leave a half-written database behind: a truncated SQLite file
      // is still openable and would look like a successful backup.
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (deleteError) {
          AppLogger.w(
            'VaultBackupExport',
            'could not delete partial data file ${file.path}: $deleteError',
          );
        }
      }
      throw VaultBackupException(
        VaultBackupErrorCode.destinationWriteFailed,
        fileName: p.basename(file.path),
        stage: VaultBackupStage.writingManifest,
        cause: error,
      );
    } finally {
      db?.dispose();
    }
    if (!await file.exists() || await file.length() == 0) {
      throw VaultBackupException(
        VaultBackupErrorCode.destinationWriteFailed,
        fileName: p.basename(file.path),
        stage: VaultBackupStage.writingManifest,
      );
    }
  }

  Future<_BackupManifest> read(File file) async {
    sqlite.Database? db;
    try {
      db = sqlite.sqlite3.open(file.path, mode: sqlite.OpenMode.readOnly);
      final meta = <String, String?>{};
      for (final row in db.select('SELECT key, value FROM meta')) {
        meta[row['key'] as String] = row['value'] as String?;
      }
      final name = p.basename(file.path);
      if (meta['format'] != formatTag) {
        throw VaultBackupException(
          VaultBackupErrorCode.malformedManifest,
          fileName: name,
          stage: VaultBackupStage.checkingBackup,
        );
      }
      final containerVersion = int.tryParse(meta['version'] ?? '') ?? 0;
      if (containerVersion <= 0) {
        throw VaultBackupException(
          VaultBackupErrorCode.malformedManifest,
          fileName: name,
          stage: VaultBackupStage.checkingBackup,
        );
      }
      if (containerVersion > formatVersion) {
        throw VaultBackupException(
          VaultBackupErrorCode.unsupportedManifestVersion,
          fileName: name,
          stage: VaultBackupStage.checkingBackup,
        );
      }
      final version = int.tryParse(meta['manifestVersion'] ?? '') ??
          VaultBackupService.manifestVersion;
      if (version < 1 || version > VaultBackupService.manifestVersion) {
        throw VaultBackupException(
          VaultBackupErrorCode.unsupportedManifestVersion,
          fileName: name,
          stage: VaultBackupStage.checkingBackup,
        );
      }
      return _BackupManifest(
        version: version,
        exportedAt: _date(meta['exportedAt']),
        verifiedAt: _date(meta['verifiedAt']),
        declaredItemCount: _int(meta['itemCount']),
        declaredTotalBytes: _int(meta['totalBytes']),
        media: List.unmodifiable(
          db.select('SELECT * FROM media ORDER BY position').map(
                _mediaFromRow,
              ),
        ),
        albums: List.unmodifiable(
          db.select('SELECT * FROM albums ORDER BY position').map(
                _albumFromRow,
              ),
        ),
        groups: List.unmodifiable(
          db.select('SELECT * FROM album_groups ORDER BY position').map(
                _groupFromRow,
              ),
        ),
        memberships: List.unmodifiable(
          db.select('SELECT * FROM memberships ORDER BY position').map(
                _membershipFromRow,
              ),
        ),
        encryptionSalt: _text(meta['encryptionSalt']),
        encryptionKeys: List.unmodifiable(
          db.select('SELECT * FROM encryption_keys ORDER BY position').map(
                _keyFromRow,
              ),
        ),
        appSettings: _settings(db),
        defaultKeyId: _text(meta['defaultKeyId']),
        includesMedia: meta['includesMedia'] == '1',
      );
    } on VaultBackupException {
      rethrow;
    } catch (error) {
      throw VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        fileName: p.basename(file.path),
        stage: VaultBackupStage.checkingBackup,
        cause: error,
      );
    } finally {
      db?.dispose();
    }
  }

  void _writeMeta(sqlite.Database db, _BackupManifest manifest) {
    final insert = db.prepare('INSERT INTO meta (key, value) VALUES (?, ?)');
    try {
      void put(String key, Object? value) {
        if (value == null) return;
        insert.execute([key, '$value']);
      }

      put('format', formatTag);
      put('version', formatVersion);
      put('manifestVersion', manifest.version);
      put('exportedAt', manifest.exportedAt?.toIso8601String());
      put('verifiedAt', manifest.verifiedAt?.toIso8601String());
      put('itemCount', manifest.declaredItemCount ?? manifest.media.length);
      put('totalBytes', manifest.declaredTotalBytes ?? 0);
      put('includesMedia', manifest.includesMedia ? 1 : 0);
      put('mediaCount', manifest.media.length);
      put('albumCount', manifest.albums.length);
      put('groupCount', manifest.groups.length);
      put('membershipCount', manifest.memberships.length);
      put('encryptionKeyCount', manifest.encryptionKeys.length);
      put('appSettingCount', manifest.appSettings.length);
      put('encryptionSalt', manifest.encryptionSalt);
      put('defaultKeyId', manifest.defaultKeyId);
      put(
        'warning',
        'Plaintext vault keys: anyone who has this file and the vault folder '
            'can decrypt every media file. Keep it offline or in an encrypted '
            'cloud folder.',
      );
    } finally {
      insert.dispose();
    }
  }

  void _writeMedia(sqlite.Database db, List<_ManifestMedia> media) {
    final insert = db.prepare(
      'INSERT INTO media (id, position, file_name, thumbnail_name, sha256, '
      'byte_length, original_path, source_platform, source_library_id, '
      'source_removal_pending, content_digest, original_name, mime_type, '
      'is_video, width, height, duration_ms, rating, date_added, date_taken, '
      'size_bytes, deleted_at, encrypted_dek, encryption_key_id, private_path, '
      'thumbnail_path, play_count, last_played_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '
      '?, ?, ?, ?, ?, ?, ?, ?)',
    );
    try {
      for (var index = 0; index < media.length; index++) {
        final item = media[index];
        insert.execute([
          item.id,
          index,
          item.fileName,
          item.thumbnailName,
          item.sha256,
          item.byteLength,
          item.originalPath,
          item.source?.platform,
          item.source?.libraryId,
          item.sourceRemovalPending ? 1 : 0,
          item.contentDigest,
          item.originalName,
          item.mimeType,
          _flag(item.isVideo),
          item.width,
          item.height,
          item.durationMs,
          item.rating,
          item.dateAdded?.toIso8601String(),
          item.dateTaken?.toIso8601String(),
          item.sizeBytes,
          item.deletedAt?.toIso8601String(),
          item.encryptedDek,
          item.encryptionKeyId,
          item.privatePath,
          item.thumbnailPath,
          item.playCount,
          item.lastPlayedAt?.toIso8601String(),
        ]);
      }
    } finally {
      insert.dispose();
    }
  }

  void _writeAlbums(sqlite.Database db, List<_ManifestAlbum> albums) {
    final insert = db.prepare(
      'INSERT INTO albums (id, position, name, is_system, cover_media_id, '
      'created_at, system_kind, pinned_at, rating, sort_index, group_id) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    );
    try {
      for (var index = 0; index < albums.length; index++) {
        final album = albums[index];
        insert.execute([
          album.id,
          index,
          album.name,
          album.isSystem ? 1 : 0,
          album.coverMediaId,
          album.createdAt?.toIso8601String(),
          album.systemKind,
          album.pinnedAt?.toIso8601String(),
          album.rating,
          album.sortIndex,
          album.groupId,
        ]);
      }
    } finally {
      insert.dispose();
    }
  }

  void _writeGroups(sqlite.Database db, List<_ManifestGroup> groups) {
    final insert = db.prepare(
      'INSERT INTO album_groups (id, position, name, created_at, sort_index) '
      'VALUES (?, ?, ?, ?, ?)',
    );
    try {
      for (var index = 0; index < groups.length; index++) {
        final group = groups[index];
        insert.execute([
          group.id,
          index,
          group.name,
          group.createdAt?.toIso8601String(),
          group.sortIndex,
        ]);
      }
    } finally {
      insert.dispose();
    }
  }

  void _writeMemberships(
    sqlite.Database db,
    List<_ManifestMembership> memberships,
  ) {
    final insert = db.prepare(
      'INSERT INTO memberships (album_id, media_id, added_at, position) '
      'VALUES (?, ?, ?, ?)',
    );
    try {
      for (var index = 0; index < memberships.length; index++) {
        final membership = memberships[index];
        insert.execute([
          membership.albumId,
          membership.mediaId,
          membership.addedAt?.toIso8601String(),
          index,
        ]);
      }
    } finally {
      insert.dispose();
    }
  }

  void _writeKeys(sqlite.Database db, List<_ManifestKey> keys) {
    final insert = db.prepare(
      'INSERT INTO encryption_keys (id, position, kek, fingerprint, created_at, '
      'label, salt, is_default) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    );
    try {
      for (var index = 0; index < keys.length; index++) {
        final key = keys[index];
        insert.execute([
          key.id,
          index,
          key.kekBase64,
          key.fingerprint,
          key.createdAt?.toIso8601String(),
          key.label,
          key.salt,
          key.isDefault ? 1 : 0,
        ]);
      }
    } finally {
      insert.dispose();
    }
  }

  void _writeSettings(sqlite.Database db, Map<String, Object?> settings) {
    if (settings.isEmpty) return;
    final insert = db.prepare(
      'INSERT INTO app_settings (key, value) VALUES (?, ?)',
    );
    try {
      settings.forEach((key, value) {
        insert.execute([key, jsonEncode(value)]);
      });
    } finally {
      insert.dispose();
    }
  }

  static Map<String, Object?> _settings(sqlite.Database db) {
    final settings = <String, Object?>{};
    for (final row in db.select('SELECT key, value FROM app_settings')) {
      final key = _text(row['key']);
      final raw = _text(row['value']);
      if (key == null || raw == null) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          settings[key] = List<String>.from(decoded.whereType<String>());
        } else if (decoded is bool ||
            decoded is int ||
            decoded is double ||
            decoded is String) {
          settings[key] = decoded;
        }
      } catch (error) {
        // A hand-edited row must not abort the whole restore.
        AppLogger.w('VaultBackupRestore', 'ignoring setting $key: $error');
      }
    }
    return settings;
  }

  static _ManifestMedia _mediaFromRow(sqlite.Row row) {
    final platform = _text(row['source_platform']);
    final libraryId = _text(row['source_library_id']);
    return _ManifestMedia(
      id: _text(row['id']),
      fileName: _text(row['file_name']) ?? '',
      thumbnailName: _text(row['thumbnail_name']),
      sha256: _text(row['sha256']),
      byteLength: _int(row['byte_length']),
      originalPath: _text(row['original_path']),
      source: platform == null || libraryId == null
          ? null
          : _ManifestSource(platform: platform, libraryId: libraryId),
      sourceRemovalPending: _bool(row['source_removal_pending']) ?? false,
      contentDigest: _text(row['content_digest']),
      originalName: _text(row['original_name']),
      mimeType: _text(row['mime_type']),
      isVideo: _bool(row['is_video']),
      width: _int(row['width']),
      height: _int(row['height']),
      durationMs: _int(row['duration_ms']),
      rating: _int(row['rating']),
      dateAdded: _date(row['date_added']),
      dateTaken: _date(row['date_taken']),
      sizeBytes: _int(row['size_bytes']),
      deletedAt: _date(row['deleted_at']),
      encryptedDek: _text(row['encrypted_dek']),
      encryptionKeyId: _text(row['encryption_key_id']),
      privatePath: _text(row['private_path']),
      thumbnailPath: _text(row['thumbnail_path']),
      playCount: _int(row['play_count']),
      lastPlayedAt: _date(row['last_played_at']),
    );
  }

  static _ManifestAlbum _albumFromRow(sqlite.Row row) => _ManifestAlbum(
        id: _text(row['id']),
        name: _text(row['name']),
        isSystem: _bool(row['is_system']) ?? true,
        coverMediaId: _text(row['cover_media_id']),
        createdAt: _date(row['created_at']),
        systemKind: _text(row['system_kind']),
        pinnedAt: _date(row['pinned_at']),
        rating: _int(row['rating']),
        sortIndex: _int(row['sort_index']),
        groupId: _text(row['group_id']),
      );

  static _ManifestGroup _groupFromRow(sqlite.Row row) => _ManifestGroup(
        id: _text(row['id']),
        name: _text(row['name']),
        createdAt: _date(row['created_at']),
        sortIndex: _int(row['sort_index']),
      );

  static _ManifestMembership _membershipFromRow(sqlite.Row row) =>
      _ManifestMembership(
        albumId: _text(row['album_id']),
        mediaId: _text(row['media_id']),
        addedAt: _date(row['added_at']),
      );

  static _ManifestKey _keyFromRow(sqlite.Row row) => _ManifestKey(
        id: _text(row['id']) ?? '',
        kekBase64: _text(row['kek']) ?? '',
        fingerprint: _text(row['fingerprint']) ?? '',
        createdAt: _date(row['created_at']),
        label: _text(row['label']),
        salt: _text(row['salt']),
        isDefault: _bool(row['is_default']) ?? false,
      );

  static String? _text(Object? value) {
    if (value == null) return null;
    if (value is String) return value.isEmpty ? null : value;
    return value.toString();
  }

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static bool? _bool(Object? value) {
    final parsed = _int(value);
    return parsed == null ? null : parsed != 0;
  }

  static DateTime? _date(Object? value) {
    final text = _text(value);
    if (text == null) return null;
    return DateTime.tryParse(text);
  }

  static int? _flag(bool? value) => value == null ? null : (value ? 1 : 0);
}
