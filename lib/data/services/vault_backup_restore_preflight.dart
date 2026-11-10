part of 'vault_backup_service.dart';

final class _VaultBackupRestorePreflight {
  const _VaultBackupRestorePreflight({
    required this.db,
    required this.albums,
    required this.storage,
    required this.uuid,
    required this.files,
    required this.manifests,
  });

  final AppDatabase db;
  final AlbumRepository albums;
  final VaultStorageService storage;
  final Uuid uuid;
  final _VaultBackupFileOps files;
  final _VaultBackupManifestCodec manifests;

  Future<List<_RestoreMediaPlan>> run(
    String sourceDirectory,
    _BackupManifest manifest,
    VaultBackupSession session,
    VaultBackupProgressCallback? onProgress,
  ) async {
    final plans = manifest.dataOnly
        ? await _preflightDataOnly(manifest, session, onProgress)
        : await _preflightMedia(
            sourceDirectory,
            manifest,
            session,
            onProgress,
          );
    await _preflightStructure(manifest, plans);
    _checkBackupCancelled(session);
    return plans;
  }

  /// v6: media bytes are not in the backup. Match each row to a file already
  /// present in phone storage; rows without a file are kept in the manifest but
  /// skipped on install (never become empty grid entries).
  Future<List<_RestoreMediaPlan>> _preflightDataOnly(
    _BackupManifest manifest,
    VaultBackupSession session,
    VaultBackupProgressCallback? onProgress,
  ) async {
    final fileIndex = await _localVaultFileIndex();
    final plans = <_RestoreMediaPlan>[];
    final ids = <String>{};
    final referencedNames = <String>{};
    for (var index = 0; index < manifest.media.length; index++) {
      _checkBackupCancelled(session);
      final item = manifest.media[index];
      final fileName = item.fileName;
      _emitBackupProgress(
        onProgress,
        VaultBackupStage.checkingBackup,
        index,
        manifest.media.length,
        item.originalName ?? fileName,
      );
      if (!referencedNames.add(fileName)) {
        throw VaultBackupException(
          VaultBackupErrorCode.malformedManifest,
          fileName: fileName,
          stage: VaultBackupStage.checkingBackup,
        );
      }
      final id = item.id ?? uuid.v4();
      if (!ids.add(id)) {
        throw VaultBackupException(
          VaultBackupErrorCode.malformedManifest,
          fileName: fileName,
          stage: VaultBackupStage.checkingBackup,
        );
      }
      final originalName = item.originalName ?? fileName;
      final originalPath = manifest.version >= 2
          ? _validatedOriginalPath(item.originalPath)
          : null;
      final localPath = await _resolveLocalFile(item, fileIndex);
      final existing = await db.getMediaById(id);
      // A file indexed by the orphan scan (no DEK) under another id would
      // otherwise become a second, permanently unopenable grid entry.
      final staleRowId = existing == null && localPath != null
          ? (await db.findByPrivatePath(localPath))?.id
          : null;
      final dek = item.encryptedDek;
      final hasDek = dek != null && dek.isNotEmpty;
      final encryptionKeyId =
          hasDek ? (item.encryptionKeyId ?? manifest.defaultKeyId) : null;
      plans.add(
        _RestoreMediaPlan(
          media: item,
          id: id,
          originalName: originalName,
          originalPath: originalPath,
          sourceFolder: _restoreSourceFolder(originalPath),
          source: null,
          thumbnail: null,
          expectedLength: item.byteLength ?? item.sizeBytes ?? 0,
          expectedDigest: item.sha256 ?? item.contentDigest ?? '',
          skipExisting: existing != null,
          encryptionKeyId: encryptionKeyId,
          staleRowId: staleRowId,
          missingLocalFile: localPath == null,
          localPath: localPath,
        ),
      );
      _emitBackupProgress(
        onProgress,
        VaultBackupStage.checkingBackup,
        index + 1,
        manifest.media.length,
      );
    }
    return List.unmodifiable(plans);
  }

  /// basename → absolute path for every media file in the vault roots.
  Future<Map<String, String>> _localVaultFileIndex() async {
    final index = <String, String>{};
    for (final root in await storage.mediaRoots()) {
      try {
        await for (final entity
            in root.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final path = entity.path;
          if (_isScratchPath(path)) continue;
          index.putIfAbsent(p.basename(path), () => path);
        }
      } catch (e) {
        AppLogger.w(
            'VaultBackupRestorePreflight', 'scan ${root.path} failed: $e');
      }
    }
    return index;
  }

  Future<String?> _resolveLocalFile(
    _ManifestMedia item,
    Map<String, String> index,
  ) async {
    final privatePath = item.privatePath;
    if (privatePath != null && privatePath.isNotEmpty) {
      if (await File(privatePath).exists()) return privatePath;
      final byBasename = index[p.basename(privatePath)];
      if (byBasename != null) return byBasename;
    }
    final byBackupName = index[item.fileName];
    if (byBackupName != null) return byBackupName;
    final originalPath = item.originalPath;
    if (originalPath != null &&
        originalPath.isNotEmpty &&
        await File(originalPath).exists()) {
      return originalPath;
    }
    final originalName = item.originalName;
    if (originalName != null && originalName.isNotEmpty) {
      final byOriginal = index[p.basename(originalName)];
      if (byOriginal != null) return byOriginal;
    }
    return null;
  }

  static bool _isScratchPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.contains('/${VaultPaths.stagingDir}/') ||
        normalized.contains('/${VaultPaths.shareStagingDir}/') ||
        normalized.contains('/${VaultPaths.thumbsDir}/');
  }

  Future<List<_RestoreMediaPlan>> _preflightMedia(
    String sourceDirectory,
    _BackupManifest manifest,
    VaultBackupSession session,
    VaultBackupProgressCallback? onProgress,
  ) async {
    final mediaDirectory = await _validatedMediaDirectory(sourceDirectory);
    final plans = <_RestoreMediaPlan>[];
    final ids = <String>{};
    final referencedNames = <String>{};
    for (var index = 0; index < manifest.media.length; index++) {
      _checkBackupCancelled(session);
      final item = manifest.media[index];
      final fileName = item.fileName;
      _emitBackupProgress(
        onProgress,
        VaultBackupStage.checkingBackup,
        index,
        manifest.media.length,
        fileName,
      );
      if (!referencedNames.add(fileName)) {
        throw VaultBackupException(
          VaultBackupErrorCode.malformedManifest,
          fileName: fileName,
          stage: VaultBackupStage.checkingBackup,
        );
      }
      final source = await files.backupFile(
        mediaDirectory,
        fileName,
        required: true,
      );
      final id = item.id ?? uuid.v4();
      if (!ids.add(id)) {
        throw VaultBackupException(
          VaultBackupErrorCode.malformedManifest,
          fileName: fileName,
          stage: VaultBackupStage.checkingBackup,
        );
      }
      final originalName = item.originalName ?? fileName;
      final originalPath = manifest.version >= 2
          ? _validatedOriginalPath(item.originalPath)
          : null;
      final actual = await files.hashPayload(
        source,
        fileName,
        expectedLength: item.byteLength,
        expectedDigest: item.sha256,
      );
      File? thumbnail;
      final thumbnailName = item.thumbnailName;
      if (thumbnailName != null) {
        if (!referencedNames.add(thumbnailName)) {
          throw VaultBackupException(
            VaultBackupErrorCode.malformedManifest,
            fileName: thumbnailName,
            stage: VaultBackupStage.checkingBackup,
          );
        }
        thumbnail = await files.backupFile(
          mediaDirectory,
          thumbnailName,
          required: false,
        );
      }
      final expectedLength = item.byteLength ?? actual.length;
      final expectedDigest = item.sha256 ?? actual.digest;
      final existing = await db.getMediaById(id);
      if (existing != null) {
        await _verifyExistingMedia(
          existing,
          originalName,
          expectedLength,
          expectedDigest,
        );
      }
      plans.add(
        _RestoreMediaPlan(
          media: item,
          id: id,
          originalName: originalName,
          originalPath: originalPath,
          sourceFolder: _restoreSourceFolder(originalPath),
          source: source,
          thumbnail: thumbnail,
          expectedLength: expectedLength,
          expectedDigest: expectedDigest,
          skipExisting: existing != null,
        ),
      );
      _emitBackupProgress(
        onProgress,
        VaultBackupStage.checkingBackup,
        index + 1,
        manifest.media.length,
      );
    }
    return List.unmodifiable(plans);
  }

  Future<void> _verifyExistingMedia(
    MediaItemRow existing,
    String fileName,
    int expectedLength,
    String expectedDigest,
  ) async {
    try {
      await files.hashPayload(
        File(existing.privatePath),
        fileName,
        expectedLength: expectedLength,
        expectedDigest: expectedDigest,
      );
    } on VaultBackupException catch (error) {
      throw VaultBackupException(
        VaultBackupErrorCode.destinationConflict,
        fileName: fileName,
        stage: VaultBackupStage.checkingBackup,
        cause: error,
      );
    }
  }

  Future<Directory> _validatedMediaDirectory(String sourceDirectory) async {
    final root = Directory(sourceDirectory);
    final mediaDirectory = Directory(p.join(sourceDirectory, 'media'));
    final type = await FileSystemEntity.type(
      mediaDirectory.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.link) {
      throw const VaultBackupException(
        VaultBackupErrorCode.unsafePath,
        fileName: 'media',
        stage: VaultBackupStage.checkingBackup,
      );
    }
    if (type != FileSystemEntityType.directory) {
      throw const VaultBackupException(
        VaultBackupErrorCode.payloadMissing,
        fileName: 'media',
        stage: VaultBackupStage.checkingBackup,
      );
    }
    try {
      final canonicalRoot = await root.resolveSymbolicLinks();
      final canonicalMedia = await mediaDirectory.resolveSymbolicLinks();
      if (!p.isWithin(canonicalRoot, canonicalMedia)) {
        throw const VaultBackupException(
          VaultBackupErrorCode.unsafePath,
          fileName: 'media',
          stage: VaultBackupStage.checkingBackup,
        );
      }
      return mediaDirectory;
    } on VaultBackupException {
      rethrow;
    } catch (error) {
      throw VaultBackupException(
        VaultBackupErrorCode.payloadUnreadable,
        fileName: 'media',
        stage: VaultBackupStage.checkingBackup,
        cause: error,
      );
    }
  }

  Future<void> _preflightStructure(
    _BackupManifest manifest,
    List<_RestoreMediaPlan> plans,
  ) async {
    manifests.validateV5Summary(manifest);
    final groupIds = <String>{};
    final existingGroups = {
      for (final group in await albums.listGroups()) group.id: group,
    };
    if (manifest.version >= 3) {
      for (final group in manifest.groups) {
        final id = group.id ?? _missingRestoreField('group id');
        final name = group.name ?? _missingRestoreField('group name');
        if (!groupIds.add(id)) {
          throw VaultBackupException(
            VaultBackupErrorCode.malformedManifest,
            fileName: name,
            stage: VaultBackupStage.checkingBackup,
          );
        }
        final existing = existingGroups[id];
        if (existing != null &&
            existing.name.toLowerCase() != name.toLowerCase()) {
          throw VaultBackupException(
            VaultBackupErrorCode.destinationConflict,
            fileName: name,
            stage: VaultBackupStage.checkingBackup,
          );
        }
      }
    }

    final albumIds = <String>{};
    for (final album in manifest.albums) {
      if (album.isSystem) continue;
      final id = album.id ?? _missingRestoreField('album id');
      final name = album.name ?? _missingRestoreField('album name');
      if (!albumIds.add(id)) {
        throw VaultBackupException(
          VaultBackupErrorCode.malformedManifest,
          fileName: name,
          stage: VaultBackupStage.checkingBackup,
        );
      }
      final existing = await albums.getById(id);
      if (existing != null &&
          (existing.isSystem ||
              existing.name.toLowerCase() != name.toLowerCase())) {
        throw VaultBackupException(
          VaultBackupErrorCode.destinationConflict,
          fileName: name,
          stage: VaultBackupStage.checkingBackup,
        );
      }
      if (manifest.version >= 3 &&
          album.groupId != null &&
          !groupIds.contains(album.groupId)) {
        throw VaultBackupException(
          VaultBackupErrorCode.malformedManifest,
          fileName: album.groupId,
          stage: VaultBackupStage.checkingBackup,
        );
      }
    }

    // A v6 backup deliberately skips rows whose media file is not present;
    // structural references are still validated against the full manifest.
    final mediaIds = manifest.dataOnly
        ? {
            for (final item in manifest.media)
              if (item.id != null) item.id!
          }
        : {for (final plan in plans) plan.id};
    if (manifest.version >= VaultBackupService.strictManifestVersion) {
      for (final album in manifest.albums) {
        final coverMediaId = album.coverMediaId;
        if (coverMediaId != null && !mediaIds.contains(coverMediaId)) {
          throw VaultBackupException(
            VaultBackupErrorCode.malformedManifest,
            fileName: coverMediaId,
            stage: VaultBackupStage.checkingBackup,
          );
        }
      }
    }
    final membershipKeys = <String>{};
    for (final membership in manifest.memberships) {
      final albumId = membership.albumId ?? _missingRestoreField('album id');
      final mediaId = membership.mediaId ?? _missingRestoreField('media id');
      if (!membershipKeys.add('$albumId\u0000$mediaId')) {
        throw VaultBackupException(
          VaultBackupErrorCode.malformedManifest,
          fileName: mediaId,
          stage: VaultBackupStage.checkingBackup,
        );
      }
      if (manifest.version >= VaultBackupService.strictManifestVersion &&
          (!albumIds.contains(albumId) || !mediaIds.contains(mediaId))) {
        throw VaultBackupException(
          VaultBackupErrorCode.malformedManifest,
          fileName: mediaId,
          stage: VaultBackupStage.checkingBackup,
        );
      }
      if (manifest.version >= 2 &&
          !albumIds.contains(albumId) &&
          await db.getAlbumById(albumId) == null) {
        continue;
      }
    }
  }
}
