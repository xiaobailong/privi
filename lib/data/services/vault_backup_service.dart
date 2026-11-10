import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../domain/models/media_item.dart';
import '../db/database.dart';
import '../repositories/album_repository.dart';
import '../repositories/media_repository.dart';
import 'encryption_key_link_backfill.dart';
import 'encryption_key_manager.dart';
import 'hide_naming.dart';
import 'key_backup_service.dart';
import 'security_service.dart';
import 'vault_storage_service.dart';
import '../../core/utils/app_logger.dart';

part 'vault_backup_export.dart';
part 'vault_backup_manifest.dart';
part 'vault_backup_manifest_organization.dart';
part 'vault_backup_manifest_parser.dart';
part 'vault_backup_manifest_validation.dart';
part 'vault_backup_models.dart';
part 'vault_backup_restore.dart';
part 'vault_backup_restore_install.dart';
part 'vault_backup_restore_preflight.dart';
part 'vault_backup_support.dart';

/// Local export/import durability (D3) - no cloud.
///
/// User-facing name: **保险库数据 / Vault Data** — the data file holds every
/// record, album, key and setting, but never the media bytes themselves (those
/// already live in phone storage and are copied separately).
///
/// Since manifest v6 this is the **single** backup feature: the encryption
/// key ring and every app setting travel with the vault metadata. Media rows
/// also record which key wrapped their DEK, so keys imported from another
/// install can be registered without ever replacing this install's default
/// key.
class VaultBackupService implements VaultBackupOperations {
  VaultBackupService({
    required AppDatabase db,
    required MediaRepository media,
    required AlbumRepository albums,
    required VaultStorageService storage,
    Uuid? uuid,
    SecurityService? security,
    EncryptionKeyManager? keyManager,
    SharedPreferences? preferences,
    KeyBackupService? keyBackup,
    EncryptionKeyLinkBackfill? backfill,
    bool usePrivateMediaStorage = false,
  })  : _db = db,
        _media = media,
        _albums = albums,
        _storage = storage,
        _uuid = uuid ?? const Uuid(),
        _security = security,
        _keyManager = keyManager,
        _preferences = preferences,
        _keyBackup = keyBackup,
        _backfill = backfill,
        _usePrivateMediaStorage = usePrivateMediaStorage;

  static const manifestName = 'privi_manifest.json';

  /// v6: one data-only backup (media bytes excluded) carrying the key ring and
  /// all app settings.  v1..v5 backups that still contain a `media/` folder
  /// remain importable.
  static const manifestVersion = 6;

  /// v5 introduced strict manifests; it stays strict for old backups.
  static const strictManifestVersion = 5;

  final AppDatabase _db;
  final MediaRepository _media;
  final AlbumRepository _albums;
  final VaultStorageService _storage;
  final Uuid _uuid;

  /// Supplies / adopts the KEK salt so backups survive a reinstall (ISSUE-029).
  final SecurityService? _security;

  /// Key ring: exported in full, imported as *additional* keys.
  final EncryptionKeyManager? _keyManager;

  /// All app settings (`SharedPreferences`) are part of the backup.
  final SharedPreferences? _preferences;

  /// Reads legacy v1/v2 `.db` key packages found in a backup directory.
  final KeyBackupService? _keyBackup;

  /// Fills blank key links after restoring an older (v1..v5) backup.
  final EncryptionKeyLinkBackfill? _backfill;

  final bool _usePrivateMediaStorage;

  String get _platformName => 'android';

  @override
  Future<VaultBackupResult> exportToDirectory(
    String destinationDirectory, {
    VaultBackupSession? session,
    VaultBackupProgressCallback? onProgress,
  }) {
    return _VaultBackupExporter(
      db: _db,
      uuid: _uuid,
      platformName: _platformName,
      security: _security,
      keyManager: _keyManager,
      preferences: _preferences,
    ).run(
      destinationDirectory,
      session: session,
      onProgress: onProgress,
    );
  }

  @override
  Future<VaultBackupResult> importFromDirectory(
    String sourceDirectory, {
    VaultBackupSession? session,
    VaultBackupProgressCallback? onProgress,
  }) {
    return _VaultBackupRestorer(
      db: _db,
      media: _media,
      albums: _albums,
      storage: _storage,
      uuid: _uuid,
      platformName: _platformName,
      usePrivateMediaStorage: _usePrivateMediaStorage,
      security: _security,
      keyManager: _keyManager,
      preferences: _preferences,
      keyBackup: _keyBackup,
      backfill: _backfill,
    ).run(
      sourceDirectory,
      session: session,
      onProgress: onProgress,
    );
  }
}
