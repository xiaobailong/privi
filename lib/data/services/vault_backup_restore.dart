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
      final result = await installer.run(
        manifest,
        plans,
        activeSession,
        onProgress,
      );
      await _backfillLegacyLinks();
      await _restoreAppSettings(manifest);
      await _adoptEncryptionSalt(manifest);
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

  Future<void> _restoreAppSettings(_BackupManifest manifest) async {
    final prefs = preferences;
    if (prefs == null || manifest.appSettings.isEmpty) return;
    var restored = 0;
    for (final entry in manifest.appSettings.entries) {
      final key = entry.key;
      if (key.startsWith('flutter.')) continue;
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
    AppLogger.i(
        'VaultBackupRestore', 'restored $restored app setting(s) from backup');
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
