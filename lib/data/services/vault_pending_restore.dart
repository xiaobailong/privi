part of 'vault_backup_service.dart';

/// Remembers a data-only import whose media files were not on this phone yet.
///
/// v6 archives carry metadata only (`ADR-049`), so a row can only be restored
/// when its file is already in phone storage.  The natural migration order is
/// however the opposite one — import the data first, copy the media folder
/// afterwards — and those rows used to be dropped for good: the archive is
/// small and users do not copy it again.
///
/// The import therefore records the archive directory here.  Once the copied
/// directory becomes visible (a library was added, or the app started again)
/// the very same data file is imported again and the rows come back with their
/// DEKs, key ids and album memberships.
///
/// Only the **path** is stored: copying the data file into app storage would
/// duplicate the plaintext KEKs it carries, which `ADR-049` / `ADR-053`
/// deliberately keep in the user-chosen export folder only.
final class _PendingRestoreStore {
  const _PendingRestoreStore();

  static const String fileName = 'pending_restore.json';
  static const int formatVersion = 1;

  Future<Directory> _root() async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, VaultPaths.pendingRestoreDir));
  }

  Future<File> _marker() async => File(p.join((await _root()).path, fileName));

  /// Archive directory to re-import, or null when nothing is pending.
  ///
  /// A marker whose archive disappeared is dropped: without the manifest there
  /// is nothing left to link, and a later import records a fresh marker.
  Future<Directory?> sourceDirectory() async {
    try {
      final marker = await _marker();
      if (!await marker.exists()) return null;
      final raw = jsonDecode(await marker.readAsString());
      final directory = raw is Map ? raw['directory'] : null;
      if (directory is! String || directory.isEmpty) {
        await clear();
        return null;
      }
      if (await const _VaultBackupManifestCodec().findBackupFile(directory) ==
          null) {
        AppLogger.w(
          'VaultPendingRestore',
          'archive is gone ($directory) — nothing left to relink',
        );
        await clear();
        return null;
      }
      return Directory(directory);
    } catch (e) {
      AppLogger.w('VaultPendingRestore', 'could not read marker: $e');
      return null;
    }
  }

  Future<bool> get hasPending async => await sourceDirectory() != null;

  /// Records that [missing] of [total] backup rows still wait for their file.
  Future<void> remember(
    String sourceDirectory, {
    required int missing,
    required int total,
  }) async {
    try {
      final root = await _root();
      await root.create(recursive: true);
      await File(p.join(root.path, fileName)).writeAsString(
        jsonEncode(<String, Object?>{
          'version': formatVersion,
          'directory': sourceDirectory,
          'missing': missing,
          'total': total,
          'recordedAt': DateTime.now().toUtc().toIso8601String(),
        }),
        flush: true,
      );
      AppLogger.i(
        'VaultPendingRestore',
        '$missing/$total media row(s) wait for their files; archive=$sourceDirectory',
      );
    } catch (e) {
      AppLogger.w('VaultPendingRestore', 'could not record marker: $e');
    }
  }

  Future<void> clear() async {
    try {
      final marker = await _marker();
      if (await marker.exists()) await marker.delete();
    } catch (e) {
      AppLogger.w('VaultPendingRestore', 'could not clear marker: $e');
    }
  }
}
