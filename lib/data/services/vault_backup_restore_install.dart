part of 'vault_backup_service.dart';

final class _VaultBackupRestoreInstaller {
  const _VaultBackupRestoreInstaller({
    required this.db,
    required this.media,
    required this.albums,
    required this.storage,
    required this.uuid,
    required this.platformName,
    required this.usePrivateMediaStorage,
    required this.files,
    this.datasets,
  });

  final AppDatabase db;
  final MediaRepository media;
  final AlbumRepository albums;
  final VaultStorageService storage;
  final Uuid uuid;
  final String platformName;
  final bool usePrivateMediaStorage;
  final _VaultBackupFileOps files;

  /// 「保险库数据管理」台账；为 null 时（单元测试/旧调用）只导入记录，不记账。
  final VaultDatasetService? datasets;

  Future<VaultBackupResult> run(
    _BackupManifest manifest,
    List<_RestoreMediaPlan> plans,
    VaultBackupSession session,
    VaultBackupProgressCallback? onProgress, {
    String? datasetId,
  }) async {
    final installed = <_InstalledMedia>[];
    var restoredCount = 0;
    try {
      for (var index = 0; index < plans.length; index++) {
        _checkBackupCancelled(session);
        final plan = plans[index];
        _emitBackupProgress(
          onProgress,
          VaultBackupStage.restoring,
          index,
          plans.length,
          plan.originalName,
        );
        if (manifest.dataOnly) {
          // v6: no payload to copy. A row whose file was found in phone storage
          // points at it directly; a row whose file has not been copied yet is
          // imported too (metadata, DEK and key id are far more valuable than a
          // dropped row) and stays invisible until the user links the directory
          // that holds it in「保险库数据管理」(ADR-054).
          final localPath = plan.localPath;
          if (!plan.skipExisting) {
            installed.add(
              _InstalledMedia(
                plan: plan,
                destination: File(localPath ?? _archivedPathOf(plan)),
                thumbnailPath:
                    localPath == null ? null : await _localThumbnailPath(plan),
                createdFiles: const [],
              ),
            );
            restoredCount++;
          }
        } else if (!plan.skipExisting) {
          final destination = await _restoreDestination(plan);
          final restoredFile = await _installRestoredFile(
            source: plan.source!,
            destination: destination,
            expectedLength: plan.expectedLength,
            expectedDigest: plan.expectedDigest,
            fileName: plan.originalName,
          );
          final thumbnail = await _installOptionalThumbnail(plan);
          installed.add(
            _InstalledMedia(
              plan: plan,
              destination: restoredFile.file,
              thumbnailPath: thumbnail?.file.path,
              createdFiles: List.unmodifiable([
                if (restoredFile.created) restoredFile.file,
                if (thumbnail?.created ?? false) thumbnail!.file,
              ]),
            ),
          );
          restoredCount++;
        }
        _emitBackupProgress(
          onProgress,
          VaultBackupStage.restoring,
          index + 1,
          plans.length,
        );
      }
      _checkBackupCancelled(session);

      await db.transaction(() async {
        final groupIdMap = manifest.version >= 3
            ? await _restoreGroups(manifest.groups)
            : const <String, String>{};
        final albumIdMap = manifest.version >= 2
            ? await _restoreAlbums(
                manifest.albums,
                groupIdMap: groupIdMap,
                restoreOrganizer: manifest.version >= 3,
              )
            : const <String, String>{};
        // Rows that already point at one of these files but carry no backup
        // metadata (orphan scan before the relink) are dropped in the same
        // transaction, so the file ends up with exactly one, decryptable row.
        final staleRows = <String>[
          for (final entry in installed)
            if (entry.plan.staleRowId != null &&
                entry.plan.staleRowId != entry.plan.id)
              entry.plan.staleRowId!,
        ];
        if (staleRows.isNotEmpty) {
          AppLogger.w(
            'VaultBackupRestore',
            'replacing ${staleRows.length} stale row(s) that share a file with '
                'the backup',
          );
          await media.hardDeleteRowsOnly(staleRows);
        }
        await media.insertMany(
          installed
              .map((item) => _mediaEntry(item, manifest.version))
              .toList(growable: false),
        );
        if (manifest.dataOnly && datasetId != null && datasets != null) {
          // Ledger for「保险库数据管理」: which of these rows still wait for
          // their file. `present` is only ever raised (see
          // `VaultDatasetService.recordImportedRows`).
          await datasets!.recordImportedRows(datasetId, [
            for (final entry in installed)
              VaultDatasetMediaRecord(
                mediaId: entry.plan.id,
                archivedPath: _archivedPathOf(entry.plan),
                isVideo: entry.plan.media.isVideo ?? false,
                rating: entry.plan.media.rating ?? 0,
                inRecycle: entry.plan.media.deletedAt != null,
                present: entry.plan.localPath != null,
              ),
          ]);
        }
        if (manifest.version >= 2) {
          await _restoreMemberships(manifest.memberships, albumIdMap);
        } else {
          await _restoreV1Albums(manifest.albums);
        }
        _checkBackupCancelled(session);
      });

      _emitBackupProgress(
        onProgress,
        VaultBackupStage.completed,
        plans.length,
        plans.length,
      );
      return VaultBackupResult(
        itemCount: restoredCount,
        totalBytes: manifest.dataOnly
            ? 0
            : plans.fold(
                0,
                (sum, plan) => sum + plan.expectedLength,
              ),
        checksumsVerified:
            manifest.version >= VaultBackupService.strictManifestVersion,
        status: VaultBackupResultStatus.completed,
      );
    } on _VaultBackupCancelled {
      await _removeInstalledFiles(installed);
      return const VaultBackupResult(
        itemCount: 0,
        totalBytes: 0,
        checksumsVerified: false,
        status: VaultBackupResultStatus.cancelled,
      );
    } catch (error) {
      await _removeInstalledFiles(installed);
      if (error is VaultBackupException) rethrow;
      throw VaultBackupException(
        VaultBackupErrorCode.databaseWriteFailed,
        stage: VaultBackupStage.restoring,
        cause: error,
      );
    }
  }

  Future<String?> _localThumbnailPath(_RestoreMediaPlan plan) async {
    final recorded = plan.media.thumbnailPath;
    if (recorded != null && await File(recorded).exists()) return recorded;
    final candidate = await storage.thumbFileFor(plan.id);
    if (await candidate.exists() && await candidate.length() > 0) {
      return candidate.path;
    }
    return null;
  }

  /// Data-only rows whose file is not on this phone yet have no length; a
  /// missing file must not abort the whole import (`lengthSync` would throw).
  static int _existingLength(File file) {
    try {
      return file.lengthSync();
    } catch (_) {
      return 0;
    }
  }

  /// 导出手机上的私密路径；老数据没有该字段时退回数据文件名。
  ///
  /// 「保险库数据管理」按 **basename** 匹配文件，所以两种取值都能用来重连。
  String _archivedPathOf(_RestoreMediaPlan plan) {
    final recorded = plan.media.privatePath;
    if (recorded != null && recorded.isNotEmpty) return recorded;
    return plan.media.fileName;
  }

  ({MediaItem item, String? userAlbumId}) _mediaEntry(
    _InstalledMedia installed,
    int version,
  ) {
    final plan = installed.plan;
    final item = plan.media;
    final isVideo = item.isVideo ?? false;
    final dataOnly = version >= VaultBackupService.manifestVersion;
    return (
      item: MediaItem(
        id: plan.id,
        privatePath: installed.destination.path,
        originalPath: plan.originalPath,
        originalName: plan.originalName,
        mimeType: item.mimeType ?? (isVideo ? 'video/mp4' : 'image/jpeg'),
        isVideo: isVideo,
        width: item.width,
        height: item.height,
        durationMs: item.durationMs,
        rating: item.rating ?? 0,
        dateAdded: item.dateAdded ?? DateTime.now().toUtc(),
        dateTaken: item.dateTaken,
        sizeBytes: dataOnly
            ? (item.sizeBytes ?? _existingLength(installed.destination))
            : installed.destination.lengthSync(),
        thumbnailPath: installed.thumbnailPath,
        deletedAt: item.deletedAt,
        sourcePlatformId:
            _sourceMatchesTarget(item.source) ? item.source?.libraryId : null,
        sourceRemovalPending: _sourceMatchesTarget(item.source) &&
            version >= 4 &&
            item.sourceRemovalPending,
        contentDigest: version >= 4 ? item.contentDigest : null,
        // Restored encrypted media keeps the DEK **and the key it belongs to**,
        // so an imported key works without touching this install's default key.
        encryptedDek: item.encryptedDek,
        encryptionKeyId: dataOnly ? plan.encryptionKeyId : null,
        playCount: dataOnly ? (item.playCount ?? 0) : 0,
        lastPlayedAt: dataOnly ? item.lastPlayedAt : null,
      ),
      userAlbumId: null,
    );
  }

  bool _sourceMatchesTarget(_ManifestSource? source) =>
      source?.platform.toLowerCase() == platformName;

  Future<File> _restoreDestination(_RestoreMediaPlan plan) async {
    if (usePrivateMediaStorage) {
      return storage.privateMediaFileFor(
        id: plan.id,
        originalName: plan.originalName,
        sourceFolder: plan.sourceFolder,
      );
    }
    return File(
      await storage.hiddenDestPath(
        id: plan.id,
        originalName: plan.originalName,
        sourceFolder: plan.sourceFolder,
      ),
    );
  }

  Future<_InstalledFile> _installRestoredFile({
    required File source,
    required File destination,
    required int expectedLength,
    required String expectedDigest,
    required String fileName,
  }) async {
    if (await destination.exists()) {
      await _verifyExistingDestination(
        destination,
        fileName,
        expectedLength,
        expectedDigest,
      );
      return _InstalledFile(file: destination, created: false);
    }
    final temporary = File('${destination.path}.part-${uuid.v4()}');
    try {
      await files.copyAndVerify(
        source: source,
        target: temporary,
        expectedLength: expectedLength,
        expectedDigest: expectedDigest,
        fileName: fileName,
        mismatchCode: VaultBackupErrorCode.payloadDigestMismatch,
        stage: VaultBackupStage.restoring,
      );
      if (await destination.exists()) {
        await _verifyExistingDestination(
          destination,
          fileName,
          expectedLength,
          expectedDigest,
        );
        await temporary.delete();
        return _InstalledFile(file: destination, created: false);
      }
      await temporary.rename(destination.path);
      return _InstalledFile(file: destination, created: true);
    } catch (error) {
      Object? cleanupError;
      try {
        if (await temporary.exists()) await temporary.delete();
      } catch (caught, stackTrace) {
        AppLogger.e('VaultBackupRestoreInstall',
            'restore temporary cleanup failed: $caught\n$stackTrace');
        cleanupError = caught;
      }
      if (cleanupError != null) {
        throw VaultBackupException(
          VaultBackupErrorCode.destinationWriteFailed,
          fileName: fileName,
          stage: VaultBackupStage.restoring,
          cause: (operation: error, cleanup: cleanupError),
        );
      }
      if (error is VaultBackupException) rethrow;
      throw VaultBackupException(
        VaultBackupErrorCode.destinationWriteFailed,
        fileName: fileName,
        stage: VaultBackupStage.restoring,
        cause: error,
      );
    }
  }

  Future<void> _verifyExistingDestination(
    File destination,
    String fileName,
    int expectedLength,
    String expectedDigest,
  ) async {
    try {
      await files.hashPayload(
        destination,
        fileName,
        expectedLength: expectedLength,
        expectedDigest: expectedDigest,
      );
    } on VaultBackupException catch (error) {
      throw VaultBackupException(
        VaultBackupErrorCode.destinationConflict,
        fileName: fileName,
        stage: VaultBackupStage.restoring,
        cause: error,
      );
    }
  }

  Future<_InstalledFile?> _installOptionalThumbnail(
    _RestoreMediaPlan plan,
  ) async {
    final source = plan.thumbnail;
    if (source == null) return null;
    File? temporary;
    try {
      final destination = await storage.thumbFileFor(plan.id);
      if (await destination.exists()) {
        return await destination.length() > 0
            ? _InstalledFile(file: destination, created: false)
            : null;
      }
      temporary = File('${destination.path}.part-${uuid.v4()}');
      await source.openRead().pipe(temporary.openWrite());
      if (await temporary.length() == 0) {
        await temporary.delete();
        return null;
      }
      if (await destination.exists()) {
        await temporary.delete();
        return await destination.length() > 0
            ? _InstalledFile(file: destination, created: false)
            : null;
      }
      await temporary.rename(destination.path);
      return _InstalledFile(file: destination, created: true);
    } catch (error, stackTrace) {
      AppLogger.e('VaultBackupRestoreInstall',
          'optional restore thumbnail skipped: $error\n$stackTrace');
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
      return null;
    }
  }

  Future<Map<String, String>> _restoreGroups(
    List<_ManifestGroup> groups,
  ) async {
    final restored = <String, String>{};
    final existingGroups = {
      for (final group in await albums.listGroups()) group.id: group,
    };
    for (final group in groups) {
      final id = group.id ?? _missingRestoreField('group id');
      final name = group.name ?? _missingRestoreField('group name');
      final existing = existingGroups[id];
      if (existing != null) {
        restored[id] = existing.id;
        continue;
      }
      await db.insertAlbumGroup(
        AlbumGroupsCompanion.insert(
          id: id,
          name: name,
          createdAt: group.createdAt ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          sortIndex: Value(group.sortIndex),
        ),
      );
      restored[id] = id;
    }
    return Map.unmodifiable(restored);
  }

  Future<Map<String, String>> _restoreAlbums(
    List<_ManifestAlbum> manifestAlbums, {
    required Map<String, String> groupIdMap,
    required bool restoreOrganizer,
  }) async {
    final restored = <String, String>{};
    for (final album in manifestAlbums) {
      if (album.isSystem) continue;
      final id = album.id ?? _missingRestoreField('album id');
      final name = album.name ?? _missingRestoreField('album name');
      final existing = await albums.getById(id);
      if (existing != null) {
        restored[id] = existing.id;
        continue;
      }
      final created = await albums.insertWithId(
        id: id,
        name: name,
        createdAt: album.createdAt ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        pinnedAt: album.pinnedAt,
        coverMediaId: album.coverMediaId,
        rating: restoreOrganizer ? (album.rating ?? 0) : 0,
        sortIndex: restoreOrganizer ? album.sortIndex : null,
        groupId: restoreOrganizer && album.groupId != null
            ? groupIdMap[album.groupId]
            : null,
      );
      restored[id] = created.id;
    }
    return Map.unmodifiable(restored);
  }

  Future<void> _restoreMemberships(
    List<_ManifestMembership> memberships,
    Map<String, String> albumIdMap,
  ) async {
    for (final membership in memberships) {
      final sourceAlbumId =
          membership.albumId ?? _missingRestoreField('album id');
      final mediaId = membership.mediaId ?? _missingRestoreField('media id');
      final albumId = albumIdMap[sourceAlbumId];
      if (albumId == null || await db.getMediaById(mediaId) == null) continue;
      await albums.restoreMembership(
        albumId,
        mediaId,
        membership.addedAt ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    }
  }

  Future<void> _restoreV1Albums(
    List<_ManifestAlbum> manifestAlbums,
  ) async {
    for (final album in manifestAlbums) {
      if (album.isSystem) continue;
      final name = album.name;
      if (name == null || name.trim().isEmpty) continue;
      await albums.getOrCreateUserAlbumByName(name);
    }
  }

  Future<void> _removeInstalledFiles(List<_InstalledMedia> installed) async {
    await files.removeFiles(
      installed.reversed.expand((item) => item.createdFiles.reversed),
    );
  }
}
