part of 'vault_backup_service.dart';

final class _VaultBackupRestorer {
  _VaultBackupRestorer({
    required AppDatabase db,
    required MediaRepository media,
    required AlbumRepository albums,
    required VaultStorageService storage,
    required Uuid uuid,
    required String platformName,
    required bool usePrivateMediaStorage,
    this.security,
    this.keyManager,
    this.preferences,
    this.keyBackup,
    this.backfill,
    this.pending,
  })  : manifests = const _VaultBackupManifestCodec(),
        preflight = _VaultBackupRestorePreflight(
          db: db,
          albums: albums,
          storage: storage,
          uuid: uuid,
          files: const _VaultBackupFileOps(),
          manifests: const _VaultBackupManifestCodec(),
        ),
        installer = _VaultBackupRestoreInstaller(
          db: db,
          media: media,
          albums: albums,
          storage: storage,
          uuid: uuid,
          platformName: platformName,
          usePrivateMediaStorage: usePrivateMediaStorage,
          files: const _VaultBackupFileOps(),
        );

  final _VaultBackupManifestCodec manifests;
  final _VaultBackupRestorePreflight preflight;
  final _VaultBackupRestoreInstaller installer;

  final SecurityService? security;

  /// Registers the backup's keys as *additional* keys (never replacing this
  /// install's default), then restores settings.
  final EncryptionKeyManager? keyManager;
  final SharedPreferences? preferences;

  /// Legacy v1/v2 `.db` key packages can still be imported from a directory.
  final KeyBackupService? keyBackup;

  /// Old (v1..v5) backups have no key links; stamp them with this phone's key.
  final EncryptionKeyLinkBackfill? backfill;

  /// Remembers rows whose media file is not on this phone yet.
  final _PendingRestoreStore? pending;

  Future<VaultBackupResult> run(
    String sourceDirectory, {
    VaultBackupSession? session,
    VaultBackupProgressCallback? onProgress,
  }) async {
    final activeSession = session ?? VaultBackupSession();
    try {
      _emitBackupProgress(
        onProgress,
        VaultBackupStage.preparing,
        0,
        0,
      );
      late final _BackupManifest manifest;
      try {
        manifest = await manifests.read(sourceDirectory);
      } on VaultBackupException catch (error) {
        if (error.code != VaultBackupErrorCode.manifestMissing) rethrow;
        final legacy = await _importLegacyKeyPackage(sourceDirectory);
        await _backfillLegacyLinks();
        return legacy;
      }
      await _registerEncryptionKeys(manifest);
      final plans = await preflight.run(
        sourceDirectory,
        manifest,
        activeSession,
        onProgress,
      );
      final missingFiles =
          await _syncPendingRestore(manifest, plans, sourceDirectory);
      final result = await installer.run(
        manifest,
        plans,
        activeSession,
        onProgress,
      );
      await _backfillLegacyLinks();
      await _restoreAppSettings(manifest);
      await _adoptEncryptionSalt(manifest);
      // Every row has a file now: the relink marker has done its job.  A
      // partial import keeps it so the next launch can pick up the rest.
      if (manifest.dataOnly && missingFiles == 0) {
        await pending?.clear();
      }
      return result;
    } on _VaultBackupCancelled {
      return const VaultBackupResult(
        itemCount: 0,
        totalBytes: 0,
        checksumsVerified: false,
        status: VaultBackupResultStatus.cancelled,
      );
    } on VaultBackupException {
      rethrow;
    } catch (error, stackTrace) {
      AppLogger.e(
          'VaultBackupRestore', 'vault restore failed: $error\n$stackTrace');
      throw VaultBackupException(
        VaultBackupErrorCode.databaseWriteFailed,
        stage: VaultBackupStage.checkingBackup,
        cause: error,
      );
    }
  }

  /// A v1..v5 backup carries no `encryption_key_id`, so the rows just restored
  /// would otherwise rely on the legacy "null means default key" fallback.
  /// Stamp them with this phone's key right away. Never fatal: the fallback
  /// still works and the next launch retries.
  Future<void> _backfillLegacyLinks() async {
    final service = backfill;
    if (service == null) return;
    try {
      final result = await service.run();
      AppLogger.i('VaultBackupRestore', 'key-link backfill: $result');
    } catch (e) {
      AppLogger.w('VaultBackupRestore', 'key-link backfill skipped: $e');
    }
  }

  /// Keys from the backup are registered by their fingerprint id.  A row that
  /// was encrypted with a foreign key keeps that id, so the two keys coexist:
  /// this is what removes the old "本机已有自己的密钥" import refusal.
  Future<void> _registerEncryptionKeys(_BackupManifest manifest) async {
    final manager = keyManager;
    if (manager == null || manifest.encryptionKeys.isEmpty) return;
    var registered = 0;
    for (final key in manifest.encryptionKeys) {
      try {
        final kek = Uint8List.fromList(base64Decode(key.kekBase64));
        await manager.registerKey(
          kek,
          label: key.label ?? '导入密钥',
          salt: key.salt,
          createdAt: key.createdAt,
        );
        registered++;
      } catch (e) {
        AppLogger.w('VaultBackupRestore',
            'could not register key ${key.id} from backup: $e');
      }
    }
    AppLogger.i(
      'VaultBackupRestore',
      'registered $registered/${manifest.encryptionKeys.length} encryption '
          'key(s) from backup; default key unchanged',
    );
  }

  /// Records (or clears) the "media files not copied yet" marker.
  ///
  /// A v6 import that cannot see its media files yet must not lose the
  /// metadata: the marker lets the very same manifest be imported again once
  /// the folder has been copied — which is exactly the order a phone migration
  /// follows when the user copies the directory afterwards.
  ///
  /// Returns how many rows are still without a file.  The marker is removed by
  /// [run] only after the whole restore succeeded, so a failed run can retry.
  Future<int> _syncPendingRestore(
    _BackupManifest manifest,
    List<_RestoreMediaPlan> plans,
    String sourceDirectory,
  ) async {
    final store = pending;
    if (store == null || !manifest.dataOnly) return 0;
    final missing = plans.where((plan) => plan.missingLocalFile).length;
    if (missing == 0) return 0;
    await store.remember(
      sourceDirectory,
      missing: missing,
      total: plans.length,
    );
    return missing;
  }

  Future<void> _restoreAppSettings(_BackupManifest manifest) async {
    final prefs = preferences;
    if (prefs == null || manifest.appSettings.isEmpty) return;
    var restored = 0;
    for (final entry in manifest.appSettings.entries) {
      final key = entry.key;
      // Engine counters plus keys that describe this phone's own absolute
      // paths — the vault libraries are merged separately (see below).
      if (key.startsWith('flutter.') || _isDeviceScopedSetting(key)) continue;
      final value = entry.value;
      try {
        switch (value) {
          case final bool v:
            await prefs.setBool(key, v);
          case final int v:
            await prefs.setInt(key, v);
          case final double v:
            await prefs.setDouble(key, v);
          case final String v:
            await prefs.setString(key, v);
          case final List<String> v:
            await prefs.setStringList(key, v);
          default:
            continue;
        }
        restored++;
      } catch (e) {
        AppLogger.w('VaultBackupRestore', 'could not restore setting $key: $e');
      }
    }
    await _mergeVaultLibraries(manifest.appSettings);
    AppLogger.i(
        'VaultBackupRestore', 'restored $restored app setting(s) from backup');
  }

  /// Settings that hold **this device's** absolute paths and must not be
  /// overwritten by another phone's snapshot.
  static bool _isDeviceScopedSetting(String key) =>
      key == VaultLibraryRegistry.librariesKey ||
      key == VaultLibraryRegistry.activeKey;

  /// Merges the backup's vault libraries into the ones this phone already has.
  ///
  /// `ADR-051` tells users to add the copied directory **before** importing the
  /// data, so restoring the key verbatim would wipe that entry (and every other
  /// library added since). Paths are merged by normalized path and the active
  /// library is left alone, so this phone keeps writing where the user told it
  /// to. Entries whose directory is missing here stay in the list — the
  /// settings screen marks them as unavailable instead of dropping them.
  Future<void> _mergeVaultLibraries(Map<String, Object?> settings) async {
    final prefs = preferences;
    if (prefs == null) return;
    final incomingRaw = settings[VaultLibraryRegistry.librariesKey];
    if (incomingRaw is! String || incomingRaw.isEmpty) return;
    final incoming = _decodeLibraryList(incomingRaw);
    if (incoming.isEmpty) return;
    final local = _decodeLibraryList(
      prefs.getString(VaultLibraryRegistry.librariesKey) ?? '',
    );
    final seenPaths = <String>{};
    final seenIds = <String>{};
    for (final entry in local) {
      final path = _libraryPathOf(entry);
      if (path != null) seenPaths.add(path);
      final id = _libraryIdOf(entry);
      if (id != null) seenIds.add(id);
    }
    final merged = <Object?>[...local];
    var added = 0;
    for (final entry in incoming) {
      final path = _libraryPathOf(entry);
      final id = _libraryIdOf(entry);
      if (path == null || id == null) continue;
      if (!seenIds.add(id) || !seenPaths.add(path)) continue;
      merged.add(entry);
      added++;
    }
    if (added == 0) return;
    await prefs.setString(
      VaultLibraryRegistry.librariesKey,
      jsonEncode(merged),
    );
    AppLogger.i(
      'VaultBackupRestore',
      'merged $added vault library path(s) from the backup; this phone keeps '
          'its active library',
    );
  }

  static List<Object?> _decodeLibraryList(String raw) {
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? List<Object?>.from(decoded) : const [];
    } catch (_) {
      return const [];
    }
  }

  static String? _libraryPathOf(Object? entry) {
    if (entry is! Map) return null;
    final path = entry['path'];
    if (path is! String || path.trim().isEmpty) return null;
    return p.normalize(path.trim().replaceAll('\\', '/'));
  }

  static String? _libraryIdOf(Object? entry) {
    if (entry is! Map) return null;
    final id = entry['id'];
    return id is String && id.isNotEmpty ? id : null;
  }

  Future<VaultBackupResult> _importLegacyKeyPackage(
    String sourceDirectory,
  ) async {
    final service = keyBackup;
    if (service == null) {
      throw const VaultBackupException(
        VaultBackupErrorCode.manifestMissing,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    final packages = await Directory(sourceDirectory)
        .list(followLinks: false)
        .where(
          (entity) =>
              entity is File &&
              p.extension(entity.path).toLowerCase() ==
                  KeyBackupService.fileExtension,
        )
        .toList();
    if (packages.isEmpty) {
      throw const VaultBackupException(
        VaultBackupErrorCode.manifestMissing,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    final result = await service.importPackage(packages.first.path);
    if (result.outcome != KeyImportOutcome.imported) {
      throw VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        fileName: p.basename(packages.first.path),
        stage: VaultBackupStage.checkingBackup,
        cause: result.outcome.name,
      );
    }
    AppLogger.i('VaultBackupRestore',
        'legacy key package imported: mapped=${result.mapped}');
    return VaultBackupResult(
      itemCount: result.mapped,
      totalBytes: 0,
      checksumsVerified: false,
      status: VaultBackupResultStatus.completed,
    );
  }

  /// Adopts the KEK salt carried by the backup **when this install has none**.
  ///
  /// An existing salt is never overwritten.  This is no longer required for
  /// decryption (v6 backups carry the raw KEKs), but it keeps the credential
  /// derivation stable on a fresh install (ISSUE-029).
  Future<void> _adoptEncryptionSalt(_BackupManifest manifest) async {
    final salt = manifest.encryptionSalt;
    if (salt == null || salt.isEmpty) return;
    final adopted = await security?.adoptEncryptionSaltIfAbsent(salt) ?? false;
    if (adopted) {
      AppLogger.i(
          'VaultBackupRestore',
          'adopted KEK salt from backup — restored encrypted media opens with '
              'the password used at export time');
    }
  }
}

String _restoreSourceFolder(String? originalPath) {
  if (originalPath == null || originalPath.trim().isEmpty) return 'Imported';
  return HideNaming.sanitizeFolder(p.basename(p.dirname(originalPath)));
}

Never _missingRestoreField(String field) {
  throw VaultBackupException(
    VaultBackupErrorCode.malformedManifest,
    fileName: field,
    stage: VaultBackupStage.checkingBackup,
  );
}
