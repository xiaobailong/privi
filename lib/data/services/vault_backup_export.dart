part of 'vault_backup_service.dart';

/// Writes a v6 **data-only** backup: everything the app stores (media rows
/// including the recycle bin, albums, groups, memberships, the full key ring
/// and every SharedPreferences entry) **except** the media files themselves.
///
/// Media files already live in phone storage and are copied separately; keeping
/// them out of the backup makes an export a single small JSON file.  Restore
/// matches rows back to the files by path / basename (see
/// `_VaultBackupRestorePreflight`).
final class _VaultBackupExporter {
  _VaultBackupExporter({
    required this.db,
    required this.uuid,
    required this.platformName,
    this.security,
    this.keyManager,
    this.preferences,
  });

  final AppDatabase db;
  final Uuid uuid;
  final String platformName;
  final SecurityService? security;
  final EncryptionKeyManager? keyManager;
  final SharedPreferences? preferences;

  final _VaultBackupManifestCodec manifests = const _VaultBackupManifestCodec();

  Future<VaultBackupResult> run(
    String destinationPath, {
    VaultBackupSession? session,
    VaultBackupProgressCallback? onProgress,
  }) async {
    final activeSession = session ?? VaultBackupSession();
    Directory? staging;
    final committed = <File>[];
    var failureStage = VaultBackupStage.preparing;
    try {
      failureStage = VaultBackupStage.preparing;
      final snapshot = await _loadSnapshot();
      final rows = snapshot.media;
      _emitBackupProgress(
        onProgress,
        VaultBackupStage.preparing,
        0,
        rows.length,
      );
      _checkBackupCancelled(activeSession);

      final entries = _entries(rows);
      final encryptionKeys = await _encryptionKeys();
      final appSettings = _appSettings();
      final encryptionSalt = await security?.readEncryptionSalt();
      final defaultKeyId = keyManager?.currentKeyId();
      _emitBackupProgress(
        onProgress,
        VaultBackupStage.preparing,
        rows.length,
        rows.length,
      );
      _checkBackupCancelled(activeSession);

      failureStage = VaultBackupStage.writingManifest;
      final destination = await _prepareDestination(destinationPath);
      staging = Directory(
        p.join(destination.path, '.privi-export-${uuid.v4()}'),
      );
      await staging.create(recursive: true);

      final manifest = manifests.fromExport(
        entries: entries,
        albums: snapshot.albums,
        groups: snapshot.groups,
        memberships: snapshot.memberships,
        platformName: platformName,
        verifiedAt: DateTime.now().toUtc(),
        encryptionSalt: encryptionSalt,
        encryptionKeys: encryptionKeys,
        appSettings: appSettings,
        defaultKeyId: defaultKeyId,
      );
      final stagedManifest = File(
        p.join(staging.path, VaultBackupService.manifestName),
      );
      await manifests.write(stagedManifest, manifest);
      // Round-trip the manifest before committing it: a truncated or invalid
      // snapshot must not look like a successful backup.
      await manifests.read(staging.path);
      await _commitManifest(
        stagedManifest,
        File(p.join(destination.path, VaultBackupService.manifestName)),
        committed,
      );

      failureStage = VaultBackupStage.checkingBackup;
      await _verifyCommitted(
        destination: destination,
        expected: manifest,
        session: activeSession,
        onProgress: onProgress,
      );
      await staging.delete(recursive: true);
      staging = null;

      _emitBackupProgress(
        onProgress,
        VaultBackupStage.completed,
        rows.length,
        rows.length,
      );
      return VaultBackupResult(
        itemCount: entries.length,
        totalBytes: 0,
        checksumsVerified: true,
        status: VaultBackupResultStatus.completed,
      );
    } on _VaultBackupCancelled {
      await _rollback(committed, staging: staging);
      return const VaultBackupResult(
        itemCount: 0,
        totalBytes: 0,
        checksumsVerified: false,
        status: VaultBackupResultStatus.cancelled,
      );
    } on VaultBackupException {
      await _rollback(committed, staging: staging);
      rethrow;
    } catch (error, stackTrace) {
      AppLogger.e(
          'VaultBackupExport', 'vault export failed: $error\n$stackTrace');
      await _rollback(committed, staging: staging);
      throw VaultBackupException(
        VaultBackupErrorCode.destinationWriteFailed,
        stage: failureStage,
        cause: error,
      );
    }
  }

  Future<_ExportSnapshot> _loadSnapshot() {
    return db.transaction(() async {
      final active = await db.listActiveMediaRows();
      final deleted = await db.listRecycleBinRows();
      return _ExportSnapshot(
        media: List.unmodifiable([...active, ...deleted]),
        albums: List.unmodifiable(await db.getAllAlbums()),
        groups: List.unmodifiable(await db.getAllAlbumGroups()),
        memberships: List.unmodifiable(await db.getAllMemberships()),
      );
    });
  }

  List<_ExportEntry> _entries(List<MediaItemRow> rows) {
    final entries = <_ExportEntry>[];
    final names = <String>{};
    for (final row in rows) {
      final id = _validatedBackupId(row.id, 'media id');
      final extension = p.extension(row.privatePath);
      final fileName = extension.isNotEmpty
          ? '$id$extension'
          : '$id${p.extension(row.originalName)}';
      _validateBackupName(fileName);
      if (!names.add(fileName)) {
        throw VaultBackupException(
          VaultBackupErrorCode.destinationConflict,
          fileName: fileName,
          stage: VaultBackupStage.preparing,
        );
      }
      entries.add(_ExportEntry(row: row, fileName: fileName));
    }
    return List.unmodifiable(entries);
  }

  Future<List<_ManifestKey>> _encryptionKeys() async {
    final records = await keyManager?.listKeys() ?? const [];
    final salt = await security?.readEncryptionSalt();
    return List.unmodifiable(
      records.map(
        (record) => _ManifestKey(
          id: record.id,
          kekBase64: base64Encode(record.kek),
          fingerprint: record.fingerprint,
          createdAt: record.createdAt,
          label: record.label,
          salt: record.isDefault ? (record.salt ?? salt) : record.salt,
          isDefault: record.isDefault,
        ),
      ),
    );
  }

  Map<String, Object?> _appSettings() {
    final prefs = preferences;
    if (prefs == null) return const <String, Object?>{};
    final snapshot = <String, Object?>{};
    for (final key in prefs.getKeys()) {
      // Flutter's own internal counters are not app data.
      if (key.startsWith('flutter.')) continue;
      final value = prefs.get(key);
      if (value is bool ||
          value is int ||
          value is double ||
          value is String ||
          value is List<String>) {
        snapshot[key] = value;
      }
    }
    return snapshot;
  }

  Future<Directory> _prepareDestination(String destinationPath) async {
    final destination = Directory(destinationPath);
    final destinationType = await FileSystemEntity.type(
      destination.path,
      followLinks: false,
    );
    if (destinationType == FileSystemEntityType.notFound) {
      await destination.create(recursive: true);
    } else if (destinationType == FileSystemEntityType.link) {
      throw VaultBackupException(
        VaultBackupErrorCode.unsafePath,
        fileName: p.basename(destination.path),
        stage: VaultBackupStage.writingManifest,
      );
    } else if (destinationType != FileSystemEntityType.directory) {
      throw VaultBackupException(
        VaultBackupErrorCode.destinationConflict,
        fileName: p.basename(destination.path),
        stage: VaultBackupStage.writingManifest,
      );
    }
    await _requireMissing(
      p.join(destination.path, VaultBackupService.manifestName),
    );
    return destination;
  }

  Future<void> _requireMissing(String path) async {
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw VaultBackupException(
        VaultBackupErrorCode.destinationConflict,
        fileName: p.basename(path),
        stage: VaultBackupStage.writingManifest,
      );
    }
  }

  Future<void> _commitManifest(
    File staged,
    File target,
    List<File> committed,
  ) async {
    await _requireMissing(target.path);
    await staged.rename(target.path);
    committed.add(target);
  }

  Future<void> _verifyCommitted({
    required Directory destination,
    required _BackupManifest expected,
    required VaultBackupSession session,
    required VaultBackupProgressCallback? onProgress,
  }) async {
    _checkBackupCancelled(session);
    _emitBackupProgress(
      onProgress,
      VaultBackupStage.checkingBackup,
      0,
      expected.media.length,
    );
    try {
      final actual = await manifests.read(destination.path);
      if (actual.version != expected.version ||
          actual.media.length != expected.media.length ||
          actual.encryptionKeys.length != expected.encryptionKeys.length ||
          actual.appSettings.length != expected.appSettings.length ||
          actual.albums.length != expected.albums.length ||
          actual.groups.length != expected.groups.length ||
          actual.memberships.length != expected.memberships.length) {
        throw const VaultBackupException(
          VaultBackupErrorCode.destinationWriteFailed,
          stage: VaultBackupStage.checkingBackup,
        );
      }
    } on _VaultBackupCancelled {
      rethrow;
    } on VaultBackupException catch (error) {
      if (error.code == VaultBackupErrorCode.destinationWriteFailed) rethrow;
      throw VaultBackupException(
        VaultBackupErrorCode.destinationWriteFailed,
        stage: VaultBackupStage.checkingBackup,
        cause: error,
      );
    } catch (error) {
      throw VaultBackupException(
        VaultBackupErrorCode.destinationWriteFailed,
        stage: VaultBackupStage.checkingBackup,
        cause: error,
      );
    }
    _emitBackupProgress(
      onProgress,
      VaultBackupStage.checkingBackup,
      expected.media.length,
      expected.media.length,
    );
  }

  Future<void> _rollback(
    List<File> committed, {
    required Directory? staging,
  }) async {
    Object? firstError;
    for (final file in committed.reversed) {
      try {
        if (await file.exists()) await file.delete();
      } catch (error) {
        firstError ??= error;
      }
    }
    if (staging != null) {
      try {
        if (await staging.exists()) await staging.delete(recursive: true);
      } catch (error) {
        firstError ??= error;
      }
    }
    if (firstError != null) {
      throw VaultBackupException(
        VaultBackupErrorCode.destinationWriteFailed,
        cause: firstError,
      );
    }
  }
}
