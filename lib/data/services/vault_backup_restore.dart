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
  })  : manifests = const _VaultBackupManifestCodec(),
        preflight = _VaultBackupRestorePreflight(
          db: db,
          albums: albums,
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

  /// Adopts the KEK salt carried by a backup (only when this install has none).
  final SecurityService? security;

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
      final manifest = await manifests.read(sourceDirectory);
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

  /// Adopts the KEK salt carried by the backup **when this install has none**.
  ///
  /// Restored encrypted media is only readable if PBKDF2(pattern, salt)
  /// reproduces the same KEK, so the salt must follow the backup.  An existing
  /// salt is never overwritten — that would invalidate every file already
  /// encrypted on this device (ISSUE-029).
  Future<void> _adoptEncryptionSalt(_BackupManifest manifest) async {
    final salt = manifest.encryptionSalt;
    if (salt == null || salt.isEmpty) return;
    final adopted = await security?.adoptEncryptionSaltIfAbsent(salt) ?? false;
    if (adopted) {
      AppLogger.i('VaultBackupRestore',
          'adopted KEK salt from backup — restored encrypted media opens with '
          'the password used at export time');
    } else {
      AppLogger.w('VaultBackupRestore',
          'kept the existing KEK salt; encrypted items coming from another '
          'vault need that vault\'s original password');
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
