part of 'vault_backup_service.dart';

abstract interface class VaultBackupOperations {
  Future<VaultBackupResult> exportToDirectory(
    String destinationDirectory, {
    VaultBackupSession? session,
    VaultBackupProgressCallback? onProgress,
  });

  Future<VaultBackupResult> importFromDirectory(
    String sourceDirectory, {
    VaultBackupSession? session,
    VaultBackupProgressCallback? onProgress,
  });

  /// An earlier data-only import still waits for its media files.
  ///
  /// v6 archives never contain media bytes, so importing before copying the
  /// folder used to drop the rows.  The import now remembers its source
  /// directory; this flag tells the UI/maintenance that relinking is possible.
  Future<bool> get hasPendingRestore;

  /// Re-runs the pending import; null when nothing is pending.
  Future<VaultBackupResult?> resumePending({
    VaultBackupSession? session,
    VaultBackupProgressCallback? onProgress,
  });
}

typedef VaultBackupProgressCallback = void Function(
  VaultBackupProgress progress,
);

enum VaultBackupStage {
  preparing,
  checkingSource,
  copying,
  writingManifest,
  checkingBackup,
  restoring,
  completed,
}

enum VaultBackupErrorCode {
  manifestMissing,
  malformedManifest,
  unsupportedManifestVersion,
  sourceMissing,
  sourceUnreadable,
  sourceEmpty,
  sourceChanged,
  payloadMissing,
  payloadUnreadable,
  payloadEmpty,
  payloadLengthMismatch,
  payloadDigestMismatch,
  unsafePath,
  destinationConflict,
  destinationWriteFailed,
  databaseWriteFailed,
}

enum VaultBackupResultStatus { completed, cancelled }

final class VaultBackupProgress {
  const VaultBackupProgress({
    required this.stage,
    required this.completed,
    required this.total,
    this.currentFile,
  });

  final VaultBackupStage stage;
  final int completed;
  final int total;
  final String? currentFile;

  double get fraction {
    if (total <= 0) return stage == VaultBackupStage.completed ? 1 : 0;
    return (completed / total).clamp(0.0, 1.0);
  }
}

final class VaultBackupSession {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

final class VaultBackupResult {
  const VaultBackupResult({
    required this.itemCount,
    this.totalBytes = 0,
    required this.checksumsVerified,
    required this.status,
  });

  final int itemCount;
  final int totalBytes;
  final bool checksumsVerified;
  final VaultBackupResultStatus status;

  bool get cancelled => status == VaultBackupResultStatus.cancelled;
}

final class VaultBackupException implements Exception {
  const VaultBackupException(
    this.code, {
    this.fileName,
    this.stage,
    this.cause,
  });

  final VaultBackupErrorCode code;
  final String? fileName;
  final VaultBackupStage? stage;
  final Object? cause;

  @override
  String toString() {
    final suffix = fileName == null ? '' : ' ($fileName)';
    return 'VaultBackupException.${code.name}$suffix';
  }
}

final class _VaultBackupCancelled implements Exception {}

final class _HashedFile {
  const _HashedFile({required this.length, required this.digest});

  final int length;
  final String digest;
}

final class _ExportSnapshot {
  const _ExportSnapshot({
    required this.media,
    required this.albums,
    required this.groups,
    required this.memberships,
  });

  final List<MediaItemRow> media;
  final List<AlbumRow> albums;
  final List<AlbumGroupRow> groups;
  final List<AlbumMediaRow> memberships;
}

/// v6 exports only the row + a stable identifier; no payload is copied.
final class _ExportEntry {
  const _ExportEntry({
    required this.row,
    required this.fileName,
  });

  final MediaItemRow row;
  final String fileName;
}

final class _BackupManifest {
  const _BackupManifest({
    required this.version,
    required this.exportedAt,
    required this.verifiedAt,
    required this.declaredItemCount,
    required this.declaredTotalBytes,
    required this.media,
    required this.albums,
    required this.groups,
    required this.memberships,
    this.encryptionSalt,
    this.encryptionKeys = const [],
    this.appSettings = const {},
    this.defaultKeyId,
    this.includesMedia = true,
  });

  final int version;
  final DateTime? exportedAt;
  final DateTime? verifiedAt;
  final int? declaredItemCount;
  final int? declaredTotalBytes;
  final List<_ManifestMedia> media;
  final List<_ManifestAlbum> albums;
  final List<_ManifestGroup> groups;
  final List<_ManifestMembership> memberships;

  /// PBKDF2 salt (base64) the exported vault's KEK was derived from.
  ///
  /// Stored so a restore on a fresh install can derive the same KEK from the
  /// same pattern/PIN.  Null for pre-encryption backups and for backups made
  /// before a salt existed (ISSUE-029).  The salt is not a secret.
  final String? encryptionSalt;

  /// v6: every KEK this vault can decrypt with (raw key material, base64).
  /// Registering these on import never replaces the receiving install's own
  /// default key — each media row names the key it needs.
  final List<_ManifestKey> encryptionKeys;

  /// v6: full `SharedPreferences` snapshot (app settings / view preferences).
  final Map<String, Object?> appSettings;

  /// v6: id of the key that was default at export time.
  final String? defaultKeyId;

  /// v6 backups contain **no media bytes**; the files stay in phone storage.
  final bool includesMedia;

  bool get dataOnly => version >= VaultBackupService.manifestVersion;

  int get payloadBytes => media.fold(
        0,
        (sum, item) => sum + (item.byteLength ?? 0),
      );
}

/// One KEK carried by a v6 backup.
final class _ManifestKey {
  const _ManifestKey({
    required this.id,
    required this.kekBase64,
    required this.fingerprint,
    required this.createdAt,
    this.label,
    this.salt,
    this.isDefault = false,
  });

  final String id;
  final String kekBase64;
  final String fingerprint;
  final DateTime? createdAt;
  final String? label;
  final String? salt;
  final bool isDefault;
}

final class _ManifestSource {
  const _ManifestSource({required this.platform, required this.libraryId});

  final String platform;
  final String libraryId;
}

final class _ManifestMedia {
  const _ManifestMedia({
    required this.id,
    required this.fileName,
    required this.thumbnailName,
    required this.sha256,
    required this.byteLength,
    required this.originalPath,
    required this.source,
    required this.sourceRemovalPending,
    required this.contentDigest,
    required this.originalName,
    required this.mimeType,
    required this.isVideo,
    required this.width,
    required this.height,
    required this.durationMs,
    required this.rating,
    required this.dateAdded,
    required this.dateTaken,
    required this.sizeBytes,
    required this.deletedAt,
    this.encryptedDek,
    this.encryptionKeyId,
    this.privatePath,
    this.thumbnailPath,
    this.playCount,
    this.lastPlayedAt,
  });

  final String? id;
  final String fileName;
  final String? thumbnailName;
  final String? sha256;
  final int? byteLength;
  final String? originalPath;
  final _ManifestSource? source;
  final bool sourceRemovalPending;
  final String? contentDigest;
  final String? originalName;
  final String? mimeType;
  final bool? isVideo;
  final int? width;
  final int? height;
  final int? durationMs;
  final int? rating;
  final DateTime? dateAdded;
  final DateTime? dateTaken;
  final int? sizeBytes;
  final DateTime? deletedAt;

  /// Per-file DEK, already encrypted with the vault KEK (never plaintext).
  ///
  /// Without it a restored encrypted file can never be decrypted again: the
  /// backup would carry ciphertext nobody holds the key for (ISSUE-029).
  /// Null for plaintext media and for older backups.
  final String? encryptedDek;

  /// v6: id of the KEK that wrapped [encryptedDek]. Files encrypted with an
  /// imported key keep pointing at it instead of the default key.
  final String? encryptionKeyId;

  /// v6: original on-device path, used to find the media file (which is not
  /// part of a data-only backup) when importing.
  final String? privatePath;
  final String? thumbnailPath;
  final int? playCount;
  final DateTime? lastPlayedAt;
}

final class _ManifestAlbum {
  const _ManifestAlbum({
    required this.id,
    required this.name,
    required this.isSystem,
    required this.coverMediaId,
    required this.createdAt,
    required this.systemKind,
    required this.pinnedAt,
    required this.rating,
    required this.sortIndex,
    required this.groupId,
  });

  final String? id;
  final String? name;
  final bool isSystem;
  final String? coverMediaId;
  final DateTime? createdAt;
  final String? systemKind;
  final DateTime? pinnedAt;
  final int? rating;
  final int? sortIndex;
  final String? groupId;
}

final class _ManifestGroup {
  const _ManifestGroup({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.sortIndex,
  });

  final String? id;
  final String? name;
  final DateTime? createdAt;
  final int? sortIndex;
}

final class _ManifestMembership {
  const _ManifestMembership({
    required this.albumId,
    required this.mediaId,
    required this.addedAt,
  });

  final String? albumId;
  final String? mediaId;
  final DateTime? addedAt;
}

final class _RestoreMediaPlan {
  const _RestoreMediaPlan({
    required this.media,
    required this.id,
    required this.originalName,
    required this.originalPath,
    required this.sourceFolder,
    required this.source,
    required this.thumbnail,
    required this.expectedLength,
    required this.expectedDigest,
    required this.skipExisting,
    this.encryptionKeyId,
    this.staleRowId,
    this.missingLocalFile = false,
    this.localPath,
  });

  final _ManifestMedia media;
  final String id;
  final String originalName;
  final String? originalPath;
  final String sourceFolder;

  /// Payload file inside a v1..v5 backup. Null for v6 data-only backups, which
  /// use the media file already present in phone storage instead.
  final File? source;
  final File? thumbnail;
  final int expectedLength;
  final String expectedDigest;
  final bool skipExisting;

  /// Key that wrapped this row's DEK, resolved for this install.
  ///
  /// Older exports left `encryptionKeyId` blank for rows encrypted with the
  /// exporting phone's default key; [VaultBackupService] then falls back to the
  /// manifest's `defaultKeyId` instead of letting the launch-time backfill stamp
  /// this phone's own key (which would make the DEK unopenable).
  final String? encryptionKeyId;

  /// Row that already points at the same file under a different id.
  ///
  /// An orphan scan run before the relink indexed the file without any DEK
  /// metadata; the restored row replaces it so the file gains its key again.
  final String? staleRowId;

  /// v6: no media file was found in phone storage for this row. The metadata
  /// is kept in the manifest but must not become an empty grid entry.
  final bool missingLocalFile;

  /// v6: absolute path of the media file found in phone storage.
  final String? localPath;
}

final class _InstalledFile {
  const _InstalledFile({required this.file, required this.created});

  final File file;
  final bool created;
}

final class _InstalledMedia {
  const _InstalledMedia({
    required this.plan,
    required this.destination,
    required this.thumbnailPath,
    required this.createdFiles,
  });

  final _RestoreMediaPlan plan;
  final File destination;
  final String? thumbnailPath;
  final List<File> createdFiles;
}
