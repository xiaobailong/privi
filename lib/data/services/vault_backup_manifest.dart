part of 'vault_backup_service.dart';

final class _VaultBackupManifestCodec {
  const _VaultBackupManifestCodec();

  static const _parser = _VaultBackupManifestParser();
  static const _validator = _VaultBackupManifestValidator();
  static const _database = _VaultBackupDatabaseCodec();

  /// Builds a v6 **data-only** manifest: every database row, the full key ring
  /// and all app settings — no media bytes.
  _BackupManifest fromExport({
    required List<_ExportEntry> entries,
    required List<AlbumRow> albums,
    required List<AlbumGroupRow> groups,
    required List<AlbumMediaRow> memberships,
    required String platformName,
    required DateTime verifiedAt,
    required List<_ManifestKey> encryptionKeys,
    required Map<String, Object?> appSettings,
    String? encryptionSalt,
    String? defaultKeyId,
  }) {
    final media = entries
        .map(
          (entry) => _ManifestMedia(
            id: entry.row.id,
            // Identifier only: v6 has no payload file to point at.
            fileName: entry.fileName,
            thumbnailName: null,
            sha256: null,
            byteLength: null,
            originalPath: entry.row.originalPath,
            source: entry.row.sourcePlatformId == null
                ? null
                : _ManifestSource(
                    platform: platformName,
                    libraryId: entry.row.sourcePlatformId!,
                  ),
            sourceRemovalPending: entry.row.sourceRemovalPending,
            contentDigest: entry.row.contentDigest,
            originalName: entry.row.originalName,
            mimeType: entry.row.mimeType,
            isVideo: entry.row.isVideo,
            width: entry.row.width,
            height: entry.row.height,
            durationMs: entry.row.durationMs,
            rating: entry.row.rating,
            dateAdded: entry.row.dateAdded,
            dateTaken: entry.row.dateTaken,
            sizeBytes: entry.row.sizeBytes,
            deletedAt: entry.row.deletedAt,
            encryptedDek: entry.row.encryptedDek,
            encryptionKeyId: _keyIdForRow(entry.row, defaultKeyId),
            privatePath: entry.row.privatePath,
            thumbnailPath: entry.row.thumbnailPath,
            playCount: entry.row.playCount,
            lastPlayedAt: entry.row.lastPlayedAt,
          ),
        )
        .toList(growable: false);
    final manifest = _BackupManifest(
      version: VaultBackupService.manifestVersion,
      exportedAt: verifiedAt,
      verifiedAt: verifiedAt,
      declaredItemCount: media.length,
      // Media files are intentionally excluded from v6 backups.
      declaredTotalBytes: 0,
      encryptionSalt: encryptionSalt,
      encryptionKeys: List.unmodifiable(encryptionKeys),
      appSettings: Map.unmodifiable(appSettings),
      defaultKeyId: defaultKeyId,
      includesMedia: false,
      media: List.unmodifiable(media),
      albums: List.unmodifiable(
        albums.map(
          (album) => _ManifestAlbum(
            id: album.id,
            name: album.name,
            isSystem: album.isSystem,
            coverMediaId: album.coverMediaId,
            createdAt: album.createdAt,
            systemKind: album.systemKind,
            pinnedAt: album.pinnedAt,
            rating: album.rating,
            sortIndex: album.sortIndex,
            groupId: album.groupId,
          ),
        ),
      ),
      groups: List.unmodifiable(
        groups.map(
          (group) => _ManifestGroup(
            id: group.id,
            name: group.name,
            createdAt: group.createdAt,
            sortIndex: group.sortIndex,
          ),
        ),
      ),
      memberships: List.unmodifiable(
        memberships.map(
          (membership) => _ManifestMembership(
            albumId: membership.albumId,
            mediaId: membership.mediaId,
            addedAt: membership.addedAt,
          ),
        ),
      ),
    );
    validateV5(manifest);
    return manifest;
  }

  /// Reads a backup folder.
  ///
  /// Current exports are one SQLite file (`ADR-053`); a legacy
  /// `privi_manifest.json` (v1..v6) is still accepted so backups made before
  /// the container change keep importing.  When neither is present this throws
  /// [VaultBackupErrorCode.manifestMissing] and the caller falls back to the
  /// legacy key-package import.
  Future<_BackupManifest> read(String sourceDirectory) async {
    final file = await _backupFile(sourceDirectory);
    final isLegacyJson =
        p.basename(file.path) == VaultBackupService.manifestName;
    final manifest =
        isLegacyJson ? await _readLegacyJson(file) : await _database.read(file);
    validateV5(manifest);
    return manifest;
  }

  /// Backup file that would be imported from [sourceDirectory], or null.
  ///
  /// Shared by [read], the export conflict check (one backup per folder) and
  /// the pending-restore marker.
  Future<File?> findBackupFile(String sourceDirectory) async {
    final root = Directory(sourceDirectory);
    if (!await root.exists()) return null;
    final data = await _databaseFile(root);
    if (data != null) return data;
    return _legacyManifest(root);
  }

  /// Writes the whole backup into [file] as one SQLite database.
  Future<void> write(File file, _BackupManifest manifest) =>
      _database.write(file, manifest);

  Future<_BackupManifest> _readLegacyJson(File manifestFile) async {
    dynamic decoded;
    try {
      decoded = jsonDecode(await manifestFile.readAsString());
    } catch (error) {
      throw VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        stage: VaultBackupStage.checkingBackup,
        cause: error,
      );
    }
    if (decoded is! Map) {
      throw const VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    return _parser.parse(Map<String, dynamic>.from(decoded));
  }

  /// Key id to record for one row.
  ///
  /// Rows written before `encryption_key_id` existed (or restored from a
  /// v1..v5 backup) still belong to the key that was default at export time.
  /// Naming it here is what lets another phone open the file with the imported
  /// key: without it the receiving phone's launch-time backfill would stamp its
  /// own default key and the DEK would never unwrap.
  static String? _keyIdForRow(MediaItemRow row, String? defaultKeyId) {
    final dek = row.encryptedDek;
    if (dek == null || dek.isEmpty) return null;
    final keyId = row.encryptionKeyId;
    if (keyId != null && keyId.trim().isNotEmpty) return keyId;
    return defaultKeyId;
  }

  void validateV5Summary(_BackupManifest manifest) {
    _validator.validateSummary(manifest);
  }

  void validateV5(_BackupManifest manifest) => _validator.validate(manifest);

  /// Locates and validates the backup file inside [sourceDirectory].
  ///
  /// The file must be a regular file directly inside the folder (no symlink
  /// escape), otherwise a crafted folder could make the app read arbitrary
  /// storage.
  Future<File> _backupFile(String sourceDirectory) async {
    final root = Directory(sourceDirectory);
    if (!await root.exists()) {
      throw const VaultBackupException(
        VaultBackupErrorCode.manifestMissing,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    final file = await findBackupFile(sourceDirectory);
    if (file == null) {
      throw const VaultBackupException(
        VaultBackupErrorCode.manifestMissing,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    final name = p.basename(file.path);
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw VaultBackupException(
        VaultBackupErrorCode.unsafePath,
        fileName: name,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    if (type != FileSystemEntityType.file) {
      throw VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        fileName: name,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    try {
      final canonicalRoot = await root.resolveSymbolicLinks();
      final canonicalFile = await file.resolveSymbolicLinks();
      if (!p.isWithin(canonicalRoot, canonicalFile)) {
        throw VaultBackupException(
          VaultBackupErrorCode.unsafePath,
          fileName: name,
          stage: VaultBackupStage.checkingBackup,
        );
      }
      return file;
    } on VaultBackupException {
      rethrow;
    } catch (error) {
      throw VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        fileName: name,
        stage: VaultBackupStage.checkingBackup,
        cause: error,
      );
    }
  }

  /// The legacy JSON manifest of [root], or null when the folder has none.
  Future<File?> _legacyManifest(Directory root) async {
    final manifest = File(
      p.join(root.path, VaultBackupService.manifestName),
    );
    final type = await FileSystemEntity.type(
      manifest.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) return null;
    if (type != FileSystemEntityType.file) {
      throw VaultBackupException(
        VaultBackupErrorCode.unsafePath,
        fileName: VaultBackupService.manifestName,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    return manifest;
  }

  /// Newest SQLite data file in [root], or null.
  ///
  /// A folder can also hold a legacy key package, which shares the `.db`
  /// extension: only files carrying the vault data format tag are considered,
  /// so the caller can still fall back to the key-package import.
  Future<File?> _databaseFile(Directory root) async {
    final candidates = <File>[];
    try {
      await for (final entity in root.list(followLinks: false)) {
        if (entity is! File) continue;
        if (p.extension(entity.path).toLowerCase() !=
            VaultBackupService.dataFileExtension) {
          continue;
        }
        candidates.add(entity);
      }
    } catch (error) {
      throw VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        stage: VaultBackupStage.checkingBackup,
        cause: error,
      );
    }
    candidates.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    for (final candidate in candidates) {
      if (await _database.hasFormat(candidate)) return candidate;
    }
    return null;
  }
}
