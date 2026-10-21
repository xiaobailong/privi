import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../core/constants.dart';
import '../../core/utils/app_logger.dart';
import '../../domain/models/media_item.dart';
import '../repositories/media_repository.dart';
import 'encryption_key_manager.dart';
import 'media_encryption_service.dart';
import 'security_service.dart';
import 'vault_storage_service.dart';

/// Outcome of validating / importing a key package.
enum KeyImportOutcome {
  /// Package is valid (and, for [KeyBackupService.importPackage], applied).
  imported,

  /// Not a Privi key package (bad JSON / not SQLite / bad key length).
  malformed,

  /// Written by a newer app version whose package format this build cannot
  /// read. Refusing is safer than guessing at a newer layout.
  unsupportedVersion,

  /// This install already holds **different** key material; importing would
  /// silently invalidate every file encrypted on this device.
  saltConflict,

  /// The key cannot unwrap any stored DEK ⇒ it does not belong to this vault.
  keyMismatch,

  /// Secure-storage write failed.
  failed,
}

/// What a key package contains, without changing anything on this device.
///
/// Shown in the import confirmation so the user can tell a key-only legacy
/// package from one that also carries the filename/DEK map.
class KeyPackageSummary {
  const KeyPackageSummary({
    required this.version,
    required this.sqlite,
    required this.createdAt,
    required this.fileCount,
    required this.encryptedFileCount,
    required this.hasEncryptionSalt,
  });

  /// Package format version: `1` = legacy JSON, `2` = SQLite database.
  final int version;

  /// True when the package is a SQLite database (v2+).
  final bool sqlite;

  final DateTime? createdAt;

  /// `media_keys` rows in the package (0 for legacy key-only packages).
  final int fileCount;

  /// Rows that carry an `encrypted_dek` (wrapped by the packaged KEK).
  final int encryptedFileCount;

  final bool hasEncryptionSalt;

  bool get isLegacy => !sqlite;
}

/// Result of [KeyBackupService.importPackage].
class KeyImportResult {
  const KeyImportResult({
    required this.outcome,
    this.restored = 0,
    this.updated = 0,
    this.skipped = 0,
  });

  final KeyImportOutcome outcome;

  /// Rows re-created in this install's database (the vault file was found).
  final int restored;

  /// Existing rows whose DEK / path were re-pointed at the package's values.
  final int updated;

  /// Package entries with no matching local file (or already claimed by
  /// another row). Never turned into empty rows.
  final int skipped;

  int get mapped => restored + updated;
}

/// Exports / imports the vault key material ("vault key backup").
///
/// Vault files are encrypted with per-file DEKs that are wrapped by the **KEK**;
/// the KEK is `PBKDF2(pattern|pin, encryption_salt)`.  After a reinstall the
/// secure storage (and therefore the salt) is gone, and
/// `SecurityService.deriveEncryptionKey` would mint a **new** salt ⇒ a different
/// KEK ⇒ every existing file becomes unreadable (ISSUE-029 / ISSUE-036).
///
/// A package therefore carries both halves:
///  * `encryptionSalt` — lets the same pattern/PIN re-derive the same KEK;
///  * `kek` — lets **any** pattern/PIN unlock the vault, once imported
///    ([EncryptionKeyManager.setImportedKey]).
///
/// Since 2026-10 the package is a **SQLite database** (format version 2,
/// `ADR-047`) instead of a handful of JSON fields: a reinstall also loses the
/// metadata DB, so a key alone leaves the recovered ciphertext files nameless
/// (their names are random, `ADR-042`) and without the `encrypted_dek` needed
/// to decrypt them.  The extra tables fix that:
///
/// ```sql
/// meta        (key, value)                  -- format tag / version / counts
/// key_material(id, encryption_salt, kek, kek_source, created_at)
/// media_keys  (media_id, private_path, original_path, original_name,
///              mime_type, is_video, size_bytes, width, height, duration_ms,
///              date_added, date_taken, encrypted_dek, content_digest)
/// ```
///
/// Import re-creates rows **only for files that actually exist** in this
/// install's vault roots, so a package never produces empty grid entries.
/// Legacy JSON packages (version 1) are still accepted for import.
///
/// **The package is as sensitive as the media itself**: it holds the raw KEK in
/// clear with no password protection, so anyone who has it *and* the vault
/// folder can decrypt everything. Keep it offline or in an encrypted cloud
/// folder, and never hand it to another person.
class KeyBackupService {
  KeyBackupService({
    required EncryptionKeyManager keyManager,
    required SecurityService security,
    required MediaEncryptionService encryption,
    required MediaRepository repository,
    required VaultStorageService storage,
  })  : _keyManager = keyManager,
        _security = security,
        _encryption = encryption,
        _repository = repository,
        _storage = storage;

  final EncryptionKeyManager _keyManager;
  final SecurityService _security;
  final MediaEncryptionService _encryption;
  final MediaRepository _repository;
  final VaultStorageService _storage;

  static const String formatTag = 'privi-key-backup';

  /// `1` = legacy JSON package, `2` = SQLite package.
  static const int formatVersion = 2;

  /// Kept for the v1 JSON reader (and for the tests that pin the KEK size).
  static const int _kekBytes = 32;

  /// SQLite files carry no meaningful extension requirement, but `.db` tells
  /// the user (and any desktop tool) what the file is.
  static const String fileExtension = '.db';

  static const String _schemaSql = '''
CREATE TABLE meta (
  key TEXT PRIMARY KEY NOT NULL,
  value TEXT
);
CREATE TABLE key_material (
  id INTEGER PRIMARY KEY CHECK (id = 1),
  encryption_salt TEXT,
  kek BLOB NOT NULL,
  kek_source TEXT NOT NULL,
  created_at TEXT NOT NULL
);
CREATE TABLE media_keys (
  media_id TEXT PRIMARY KEY NOT NULL,
  private_path TEXT NOT NULL,
  original_path TEXT,
  original_name TEXT NOT NULL,
  mime_type TEXT,
  is_video INTEGER NOT NULL DEFAULT 0,
  size_bytes INTEGER NOT NULL DEFAULT 0,
  width INTEGER,
  height INTEGER,
  duration_ms INTEGER,
  date_added INTEGER,
  date_taken INTEGER,
  encrypted_dek TEXT,
  content_digest TEXT
);
CREATE INDEX idx_media_keys_private_path ON media_keys (private_path);
''';

  /// Writes the vault key **and** the filename/DEK map into [directoryPath] as
  /// a SQLite database, then returns the saved path.
  ///
  /// Throws [StateError] when the vault is locked (no KEK in memory ⇒ nothing to
  /// export); callers show "unlock first" instead of writing an empty package.
  Future<String> exportToDirectory(
    String directoryPath, {
    DateTime? now,
  }) async {
    final kek = _keyManager.getKey();
    if (kek == null) {
      throw StateError('vault locked: no KEK in memory');
    }
    final salt = await _security.readEncryptionSalt();
    final imported = await _keyManager.isImportedKey();
    final items = await _repository.listActive();
    final created = (now ?? DateTime.now()).toUtc();
    final file = File(p.join(directoryPath, suggestedFileName(created)));
    if (await file.exists()) {
      await file.delete();
    }

    final encryptedCount =
        items.where((item) => (item.encryptedDek ?? '').isNotEmpty).length;

    Database? db;
    try {
      db = sqlite3.open(file.path);
      // Keep the package a single self-contained file (no -wal/-shm siblings).
      db.execute('PRAGMA journal_mode = DELETE');
      db.execute('PRAGMA user_version = $formatVersion');
      db.execute(_schemaSql);

      final insertMeta =
          db.prepare('INSERT INTO meta (key, value) VALUES (?, ?)');
      final insertKey = db.prepare(
        'INSERT INTO key_material '
        '(id, encryption_salt, kek, kek_source, created_at) '
        'VALUES (1, ?, ?, ?, ?)',
      );
      final insertMedia = db.prepare(
        'INSERT INTO media_keys (media_id, private_path, original_path, '
        'original_name, mime_type, is_video, size_bytes, width, height, '
        'duration_ms, date_added, date_taken, encrypted_dek, content_digest) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      );
      try {
        db.execute('BEGIN');
        void meta(String key, String value) => insertMeta.execute([key, value]);
        meta('format', formatTag);
        meta('version', '$formatVersion');
        meta('createdAt', created.toIso8601String());
        meta('fileCount', '${items.length}');
        meta('encryptedFileCount', '$encryptedCount');
        meta(
          'warning',
          'Raw vault key plus per-file DEKs and filename mapping: together '
              'with the vault folder it decrypts every file. Keep it offline '
              'or in an encrypted cloud folder.',
        );
        insertKey.execute([
          salt,
          kek,
          imported
              ? EncryptionKeyManager.sourceImported
              : EncryptionKeyManager.sourceDerived,
          created.toIso8601String(),
        ]);
        for (final item in items) {
          insertMedia.execute([
            item.id,
            item.privatePath,
            item.originalPath,
            item.originalName,
            item.mimeType,
            item.isVideo ? 1 : 0,
            item.sizeBytes,
            item.width,
            item.height,
            item.durationMs,
            item.dateAdded.toUtc().millisecondsSinceEpoch,
            item.dateTaken?.toUtc().millisecondsSinceEpoch,
            item.encryptedDek,
            item.contentDigest,
          ]);
        }
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      } finally {
        insertMeta.dispose();
        insertKey.dispose();
        insertMedia.dispose();
      }
    } catch (e) {
      // Never leave a half-written package behind: a truncated SQLite file is
      // still openable, which would look like "the backup worked".
      db?.dispose();
      db = null;
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (deleteError) {
          AppLogger.w('KeyBackupService',
              'could not delete partial package ${file.path}: $deleteError');
        }
      }
      AppLogger.e('KeyBackupService', 'export failed: $e');
      rethrow;
    } finally {
      db?.dispose();
    }

    AppLogger.i(
      'KeyBackupService',
      'vault key package exported: files=${items.length}, '
          'encrypted=$encryptedCount -> ${file.path}',
    );
    return file.path;
  }

  /// File name to suggest when saving [exportToDirectory] output.
  static String suggestedFileName(DateTime now) {
    final d = now.toUtc();
    return 'privi-key-${d.year}${_two(d.month)}${_two(d.day)}'
        '-${_two(d.hour)}${_two(d.minute)}${_two(d.second)}$fileExtension';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  /// Reads [filePath] **without changing anything** — run this before asking
  /// the user to confirm an import.
  ///
  /// Returns null when the file is not a Privi package.
  Future<KeyPackageSummary?> inspectPackage(String filePath) async {
    final package = await _readPackage(filePath);
    return package?.summary;
  }

  /// Checks [filePath] **without changing anything** — run this before asking
  /// the user to confirm an import.
  Future<KeyImportOutcome> validatePackage(String filePath) async {
    final package = await _readPackage(filePath);
    if (package == null) return KeyImportOutcome.malformed;
    return _validate(package);
  }

  /// Validates [filePath], then adopts its salt, KEK and file mapping.
  ///
  /// Call [validatePackage] first so the UI only confirms with the user when the
  /// package is actually usable.
  Future<KeyImportResult> importPackage(String filePath) async {
    final package = await _readPackage(filePath);
    if (package == null) {
      return const KeyImportResult(outcome: KeyImportOutcome.malformed);
    }
    final outcome = await _validate(package);
    if (outcome != KeyImportOutcome.imported) {
      return KeyImportResult(outcome: outcome);
    }
    try {
      final salt = package.salt;
      if (salt != null && salt.isNotEmpty) {
        await _security.adoptEncryptionSaltIfAbsent(salt);
      }
      await _keyManager.setImportedKey(package.kek);
    } catch (e, stackTrace) {
      AppLogger.e('KeyBackupService', 'import failed: $e\n$stackTrace');
      return const KeyImportResult(outcome: KeyImportOutcome.failed);
    }

    var restored = 0;
    var updated = 0;
    var skipped = 0;
    try {
      final counts = await _restoreFileMapping(package.rows);
      restored = counts.restored;
      updated = counts.updated;
      skipped = counts.skipped;
    } catch (e, stackTrace) {
      // The key itself is already adopted at this point: report the partial
      // result instead of pretending the whole import failed.
      AppLogger.e(
        'KeyBackupService',
        'key adopted but file mapping restore failed: $e\n$stackTrace',
      );
      return KeyImportResult(
        outcome: KeyImportOutcome.failed,
        restored: restored,
        updated: updated,
        skipped: skipped,
      );
    }

    AppLogger.i(
      'KeyBackupService',
      'vault key imported: KEK adopted from the package, salt adopted: '
          '${package.salt != null}, mapping restored=$restored '
          'updated=$updated skipped=$skipped',
    );
    return KeyImportResult(
      outcome: KeyImportOutcome.imported,
      restored: restored,
      updated: updated,
      skipped: skipped,
    );
  }

  /// True when [kek] unwraps at least one stored DEK.
  ///
  /// A vault without encrypted items has nothing to contradict the key, so it
  /// accepts it.
  Future<bool> matchesVault(Uint8List kek) async {
    final items = await _repository.listEncrypted();
    if (items.isEmpty) return true;
    var checked = 0;
    for (final item in items) {
      final dekBase64 = item.encryptedDek;
      if (dekBase64 == null || dekBase64.isEmpty) continue;
      if (checked >= 8) break;
      checked++;
      final dek = await _encryption.decryptDek(
        encryptedDekBase64: dekBase64,
        kek: kek,
      );
      if (dek != null) return true;
    }
    return false;
  }

  Future<KeyImportOutcome> _validate(_KeyPackage package) async {
    if (package.unsupportedVersion) {
      AppLogger.w(
        'KeyBackupService',
        'import refused: package version ${package.summary.version} is newer '
            'than this build ($formatVersion)',
      );
      return KeyImportOutcome.unsupportedVersion;
    }

    final existingSalt = await _security.readEncryptionSalt();
    if (existingSalt != null &&
        existingSalt.isNotEmpty &&
        existingSalt != package.salt) {
      // Keep ISSUE-029's rule: never overwrite salt material this install
      // already depends on.
      AppLogger.w('KeyBackupService',
          'import refused: this install already has its own encryption salt');
      return KeyImportOutcome.saltConflict;
    }

    if (!await _matchesPackage(package)) {
      AppLogger.w('KeyBackupService',
          'import refused: the key does not unwrap any stored DEK');
      return KeyImportOutcome.keyMismatch;
    }
    return KeyImportOutcome.imported;
  }

  /// Local rows are authoritative when they exist; otherwise the package's own
  /// DEKs are used, so a corrupted package is still rejected.
  Future<bool> _matchesPackage(_KeyPackage package) async {
    final local = await _repository.listEncrypted();
    if (local.isNotEmpty) {
      var checked = 0;
      for (final item in local) {
        final dekBase64 = item.encryptedDek;
        if (dekBase64 == null || dekBase64.isEmpty) continue;
        if (checked >= 8) break;
        checked++;
        final dek = await _encryption.decryptDek(
          encryptedDekBase64: dekBase64,
          kek: package.kek,
        );
        if (dek != null) return true;
      }
      return false;
    }

    var checked = 0;
    for (final row in package.rows) {
      final dekBase64 = row.encryptedDek;
      if (dekBase64 == null || dekBase64.isEmpty) continue;
      if (checked >= 8) break;
      checked++;
      final dek = await _encryption.decryptDek(
        encryptedDekBase64: dekBase64,
        kek: package.kek,
      );
      if (dek != null) return true;
    }
    // Nothing to check against (key-only / plaintext-only vault).
    return checked == 0;
  }

  /// Re-creates rows for package entries whose file still exists locally.
  ///
  /// Files that are missing are **skipped**, never inserted as empty rows: a
  /// reinstall restores the vault folder, and only the files actually copied
  /// back can be decrypted anyway.
  Future<({int restored, int updated, int skipped})> _restoreFileMapping(
    List<_PackageMediaRow> rows,
  ) async {
    if (rows.isEmpty) return (restored: 0, updated: 0, skipped: 0);
    final index = await _localVaultFileIndex();
    final takenPaths = (await _repository.listActivePrivatePaths()).toSet();
    final pending = <MediaItem>[];
    var updated = 0;
    var skipped = 0;

    for (final row in rows) {
      final path = await _resolveLocalPath(row.privatePath, index);
      if (path == null) {
        skipped++;
        continue;
      }
      final existing = await _repository.findById(row.mediaId);
      if (existing != null) {
        var touched = false;
        final dek = row.encryptedDek;
        // Never overwrite a DEK that is already recorded: the file may have been
        // re-encrypted after this package was written, and its current DEK is
        // the only one that matches the bytes. Only fill a *missing* record, and
        // only when the local file really looks like ciphertext (ISSUE-043) —
        // attaching a DEK to a plaintext file makes it unopenable.
        if ((existing.encryptedDek ?? '').isEmpty &&
            dek != null &&
            dek.isNotEmpty &&
            _encryption.looksEncrypted(File(path))) {
          await _repository.updateEncryptedDek(row.mediaId, dek);
          touched = true;
        }
        if (path != existing.privatePath) {
          await _repository.updatePrivatePath(row.mediaId, path);
          touched = true;
        }
        // Already consistent (same DEK + path): nothing to report.
        if (touched) updated++;
        continue;
      }
      if (takenPaths.contains(path)) {
        // Another row already owns this file (e.g. recovered by the orphan
        // scan before the import). Do not create a duplicate.
        skipped++;
        continue;
      }
      takenPaths.add(path);
      pending.add(
        MediaItem(
          id: row.mediaId,
          privatePath: path,
          originalPath: row.originalPath,
          originalName: row.originalName.isNotEmpty
              ? row.originalName
              : p.basename(row.privatePath),
          mimeType: row.mimeType ?? '',
          isVideo: row.isVideo,
          width: row.width,
          height: row.height,
          durationMs: row.durationMs,
          rating: 0,
          dateAdded: row.dateAdded ?? DateTime.now().toUtc(),
          dateTaken: row.dateTaken,
          sizeBytes:
              row.sizeBytes > 0 ? row.sizeBytes : await _fileLengthOrZero(path),
          encryptedDek: row.encryptedDek,
          contentDigest: row.contentDigest,
        ),
      );
    }

    if (pending.isNotEmpty) {
      await _repository.insertMany([
        for (final item in pending) (item: item, userAlbumId: null),
      ]);
    }
    return (restored: pending.length, updated: updated, skipped: skipped);
  }

  Future<int> _fileLengthOrZero(String path) async {
    try {
      return await File(path).length();
    } catch (_) {
      return 0;
    }
  }

  Future<String?> _resolveLocalPath(
    String privatePath,
    Map<String, String> index,
  ) async {
    if (privatePath.isEmpty) return null;
    if (await File(privatePath).exists()) return privatePath;
    final name = p.basename(privatePath);
    if (name.isEmpty) return null;
    return index[name];
  }

  /// basename → absolute path for every media file in the vault roots.
  ///
  /// One recursive listing instead of a scan per package entry; staging and
  /// thumbnail folders are excluded (their names are temporary by design).
  Future<Map<String, String>> _localVaultFileIndex() async {
    final index = <String, String>{};
    for (final root in await _storage.mediaRoots()) {
      try {
        await for (final entity
            in root.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final path = entity.path;
          if (_isScratchPath(path)) continue;
          index.putIfAbsent(p.basename(path), () => path);
        }
      } catch (e) {
        AppLogger.w('KeyBackupService', 'scan ${root.path} failed: $e');
      }
    }
    return index;
  }

  static bool _isScratchPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.contains('/${VaultPaths.stagingDir}/') ||
        normalized.contains('/${VaultPaths.shareStagingDir}/') ||
        normalized.contains('/${VaultPaths.thumbsDir}/');
  }

  /// Reads a v2 SQLite package or a legacy v1 JSON package, or null.
  Future<_KeyPackage?> _readPackage(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      AppLogger.w('KeyBackupService', 'import: file not found: $filePath');
      return null;
    }
    final header = await _readHeader(file);
    if (String.fromCharCodes(header.take(15)) == 'SQLite format 3') {
      return _readSqlitePackage(file);
    }
    if (header.isNotEmpty && header.first == 0x7b) {
      // '{' — a legacy key-only JSON package (format version 1).
      return _readLegacyJson(file);
    }
    AppLogger.w('KeyBackupService',
        'import: unrecognised file header (${header.length} bytes)');
    return null;
  }

  static Future<List<int>> _readHeader(File file) async {
    RandomAccessFile? handle;
    try {
      handle = await file.open();
      return await handle.read(16);
    } catch (e) {
      AppLogger.w('KeyBackupService', 'import: cannot read header: $e');
      return const [];
    } finally {
      await handle?.close();
    }
  }

  _KeyPackage? _readSqlitePackage(File file) {
    Database? db;
    try {
      db = sqlite3.open(file.path, mode: OpenMode.readOnly);
      final meta = <String, String?>{};
      for (final row in db.select('SELECT key, value FROM meta')) {
        meta[row['key'] as String] = row['value'] as String?;
      }
      if (meta['format'] != formatTag) {
        AppLogger.w('KeyBackupService',
            'import: sqlite package has format=${meta['format']}');
        return null;
      }
      final version = int.tryParse(meta['version'] ?? '') ?? 0;
      if (version <= 0) {
        AppLogger.w('KeyBackupService',
            'import: sqlite package has an invalid version');
        return null;
      }
      final createdAt = DateTime.tryParse(meta['createdAt'] ?? '')?.toUtc();
      final keyRows = db.select(
        'SELECT encryption_salt, kek FROM key_material LIMIT 1',
      );
      if (keyRows.isEmpty) {
        AppLogger.w('KeyBackupService',
            'import: sqlite package has no key_material row');
        return null;
      }
      final salt = keyRows.first['encryption_salt'] as String?;
      final kek = _asBytes(keyRows.first['kek']);
      if (kek == null || kek.length != _kekBytes) {
        AppLogger.w('KeyBackupService',
            'import: sqlite package carries a ${kek?.length ?? 0}-byte key');
        return null;
      }

      final supported = version <= formatVersion;
      final rows = <_PackageMediaRow>[];
      if (supported && _tableExists(db, 'media_keys')) {
        for (final row in db.select('SELECT * FROM media_keys')) {
          rows.add(_PackageMediaRow.fromRow(row));
        }
      }
      return _KeyPackage(
        kek: kek,
        salt: salt,
        rows: rows,
        summary: KeyPackageSummary(
          version: version,
          sqlite: true,
          createdAt: createdAt,
          fileCount: rows.length,
          encryptedFileCount:
              rows.where((row) => (row.encryptedDek ?? '').isNotEmpty).length,
          hasEncryptionSalt: salt != null && salt.isNotEmpty,
        ),
        unsupportedVersion: !supported,
      );
    } on SqliteException catch (e) {
      AppLogger.w('KeyBackupService', 'import: not a valid sqlite package: $e');
      return null;
    } catch (e, stackTrace) {
      AppLogger.e(
          'KeyBackupService', 'import: sqlite read failed: $e\n$stackTrace');
      return null;
    } finally {
      db?.dispose();
    }
  }

  static bool _tableExists(Database db, String table) {
    final rows = db.select(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return rows.isNotEmpty;
  }

  /// Legacy v1 package: `{format, version, createdAt, encryptionSalt, kek}`.
  Future<_KeyPackage?> _readLegacyJson(File file) async {
    Object? decoded;
    try {
      decoded = jsonDecode(await file.readAsString());
    } catch (e) {
      AppLogger.w('KeyBackupService', 'import: not JSON: $e');
      return null;
    }
    if (decoded is! Map) return null;
    if (decoded['format'] != formatTag) return null;
    final version = decoded['version'];
    if (version is! int || version <= 0) return null;
    if (version > formatVersion) {
      return _KeyPackage(
        kek: Uint8List(0),
        salt: null,
        rows: const [],
        summary: KeyPackageSummary(
          version: version,
          sqlite: false,
          createdAt: null,
          fileCount: 0,
          encryptedFileCount: 0,
          hasEncryptionSalt: false,
        ),
        unsupportedVersion: true,
      );
    }
    final kekBase64 = decoded['kek'];
    if (kekBase64 is! String || kekBase64.isEmpty) return null;
    Uint8List kek;
    try {
      kek = Uint8List.fromList(base64Decode(kekBase64));
    } catch (_) {
      return null;
    }
    if (kek.length != _kekBytes) return null;
    final salt = decoded['encryptionSalt'];
    final hasSalt = salt is String && salt.isNotEmpty;
    return _KeyPackage(
      kek: kek,
      salt: hasSalt ? salt : null,
      rows: const [],
      summary: KeyPackageSummary(
        version: version,
        sqlite: false,
        createdAt: DateTime.tryParse('${decoded['createdAt'] ?? ''}')?.toUtc(),
        fileCount: 0,
        encryptedFileCount: 0,
        hasEncryptionSalt: hasSalt,
      ),
      unsupportedVersion: false,
    );
  }

  static Uint8List? _asBytes(Object? value) {
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    return null;
  }
}

class _KeyPackage {
  const _KeyPackage({
    required this.kek,
    required this.salt,
    required this.rows,
    required this.summary,
    required this.unsupportedVersion,
  });

  final Uint8List kek;
  final String? salt;
  final List<_PackageMediaRow> rows;
  final KeyPackageSummary summary;
  final bool unsupportedVersion;
}

/// One row of the package's `media_keys` table.
class _PackageMediaRow {
  const _PackageMediaRow({
    required this.mediaId,
    required this.privatePath,
    required this.originalPath,
    required this.originalName,
    required this.mimeType,
    required this.isVideo,
    required this.sizeBytes,
    required this.width,
    required this.height,
    required this.durationMs,
    required this.dateAdded,
    required this.dateTaken,
    required this.encryptedDek,
    required this.contentDigest,
  });

  factory _PackageMediaRow.fromRow(Row row) {
    return _PackageMediaRow(
      mediaId: _text(row['media_id']) ?? '',
      privatePath: _text(row['private_path']) ?? '',
      originalPath: _text(row['original_path']),
      originalName: _text(row['original_name']) ?? '',
      mimeType: _text(row['mime_type']),
      isVideo: (_int(row['is_video']) ?? 0) != 0,
      sizeBytes: _int(row['size_bytes']) ?? 0,
      width: _int(row['width']),
      height: _int(row['height']),
      durationMs: _int(row['duration_ms']),
      dateAdded: _date(row['date_added']),
      dateTaken: _date(row['date_taken']),
      encryptedDek: _text(row['encrypted_dek']),
      contentDigest: _text(row['content_digest']),
    );
  }

  final String mediaId;
  final String privatePath;
  final String? originalPath;
  final String originalName;
  final String? mimeType;
  final bool isVideo;
  final int sizeBytes;
  final int? width;
  final int? height;
  final int? durationMs;
  final DateTime? dateAdded;
  final DateTime? dateTaken;
  final String? encryptedDek;
  final String? contentDigest;

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

  static DateTime? _date(Object? value) {
    final millis = _int(value);
    if (millis == null || millis <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }
}
