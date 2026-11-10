import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants.dart';
import '../../core/media_thumbnail_spec.dart';
import 'hide_naming.dart';
import 'vault_library_registry.dart';
import '../../core/utils/app_logger.dart';

/// Manages vault directories:
/// - App-private: thumbs/metadata under documents/vault/
/// - Shared hide root: /storage/emulated/0/.privateheart_vault/ (+ .nomedia)
///
/// See docs/03-architecture/storage-and-hiding.md (dense gallery directory hide).
class VaultStorageService {
  VaultStorageService({
    this.initializeSharedRoot = true,
    this.registry,
  });

  /// Whether this instance may touch Android's shared-storage hide root.
  ///
  /// iOS uses the same app-private vault metadata path but must never probe or
  /// create `/storage/emulated/0/.privateheart_vault`.
  final bool initializeSharedRoot;

  /// Extra vault libraries registered by the user. Optional so a caller that
  /// only needs app-private metadata is unaffected.
  final VaultLibraryRegistry? registry;

  Directory? _vault;
  Directory? _thumbs;
  Directory? _hiddenRoot;

  Future<Directory> ensureVault() async {
    if (_vault != null) return _vault!;
    final docs = await getApplicationDocumentsDirectory();
    final vault = Directory(p.join(docs.path, VaultPaths.vaultDir));
    if (!await vault.exists()) {
      await vault.create(recursive: true);
    }
    final nomedia = File(p.join(vault.path, VaultPaths.nomedia));
    if (!await nomedia.exists()) {
      await nomedia.create();
    }
    final thumbs = Directory(p.join(vault.path, VaultPaths.thumbsDir));
    if (!await thumbs.exists()) {
      await thumbs.create(recursive: true);
    }
    _vault = vault;
    _thumbs = thumbs;
    // Android creates the shared root early so the first hide can use a rename.
    // App-private platforms deliberately skip this probe.
    if (initializeSharedRoot) {
      try {
        await ensureHiddenRoot();
      } catch (e) {
        AppLogger.w('VaultStorageService', 'ensureHiddenRoot: $e');
      }
    }
    return vault;
  }

  Future<Directory> get thumbsDir async {
    await ensureVault();
    return _thumbs!;
  }

  Future<Directory> get vaultDir async => ensureVault();

  /// Directories that may hold vault media files (recursive scan targets).
  ///
  /// The app-private metadata root plus **every** library root: the built-in
  /// `.privateheart_vault` and each user-added directory. Key-package and
  /// archive restores use this to re-associate rows with files that survived a
  /// reinstall or a manual copy from another phone.
  Future<List<Directory>> mediaRoots() async {
    final roots = <Directory>[await ensureVault()];
    roots.addAll(await libraryRoots());
    return roots;
  }

  /// All library roots that currently exist on this device.
  ///
  /// A registered path that no longer exists (e.g. it was copied from an
  /// archive made on another phone) is skipped, never created implicitly.
  Future<List<Directory>> libraryRoots() async {
    final roots = <Directory>[];
    if (initializeSharedRoot) {
      try {
        roots.add(await ensureHiddenRoot());
      } catch (e) {
        AppLogger.w('VaultStorageService', 'libraryRoots: ensureHiddenRoot: $e');
      }
    }
    for (final path in registry?.rootPaths ?? const <String>[]) {
      try {
        final dir = Directory(path);
        if (await dir.exists()) roots.add(dir);
      } catch (e) {
        AppLogger.w('VaultStorageService', 'libraryRoots: $path: $e');
      }
    }
    // Keep HideNaming's vault-path tests in sync with the effective roots.
    HideNaming.extraVaultRoots = {
      for (final entry in registry?.userLibraries ?? const <VaultLibraryEntry>[])
        entry.path,
    };
    return roots;
  }

  /// Root that receives newly hidden media. Defaults to the built-in root;
  /// falls back to it if the selected library disappeared from the device.
  Future<Directory> activeLibraryRoot() async {
    if (!initializeSharedRoot) return ensureVault();
    final id = registry?.activeId ?? VaultLibraryRegistry.builtInId;
    final path = registry?.pathFor(id);
    if (path != null) {
      final dir = Directory(path);
      if (await dir.exists()) {
        await _ensureNomedia(dir);
        return dir;
      }
      AppLogger.w('VaultStorageService',
          'active library $id is missing ($path); using built-in root');
    }
    return ensureHiddenRoot();
  }

  /// Validates a user-picked directory before registering it as a library.
  ///
  /// Rejects missing/unreadable paths, volume roots, the app-private metadata
  /// vault, and anything nested in (or containing) an existing library: nested
  /// roots would make every scan index the same file twice.
  Future<VaultLibraryPathCheck> validateLibraryPath(String rawPath) async {
    final trimmed = rawPath.trim();
    if (trimmed.isEmpty) {
      return const VaultLibraryPathCheck(VaultLibraryPathIssue.empty);
    }
    final normalized = _norm(trimmed);
    if (_isVolumeRoot(normalized) || _isPublicMediaRoot(normalized)) {
      return const VaultLibraryPathCheck(VaultLibraryPathIssue.reserved);
    }
    if (await FileSystemEntity.type(normalized, followLinks: false) ==
        FileSystemEntityType.notFound) {
      return const VaultLibraryPathCheck(VaultLibraryPathIssue.missing);
    }
    if (await FileSystemEntity.type(normalized, followLinks: false) !=
        FileSystemEntityType.directory) {
      return const VaultLibraryPathCheck(VaultLibraryPathIssue.notDirectory);
    }
    try {
      await Directory(normalized)
          .list(followLinks: false)
          .first
          .timeout(const Duration(seconds: 3));
    } on StateError {
      // An empty directory is a perfectly valid (new) library.
    } catch (_) {
      return const VaultLibraryPathCheck(VaultLibraryPathIssue.unreadable);
    }

    final existing = <String>[_norm((await ensureVault()).path)];
    if (initializeSharedRoot) {
      try {
        existing.add(_norm((await ensureHiddenRoot()).path));
      } catch (_) {}
    }
    for (final entry in registry?.userLibraries ?? const <VaultLibraryEntry>[]) {
      existing.add(_norm(entry.path));
    }
    for (final root in existing) {
      if (p.equals(root, normalized) || p.equals(root, '$normalized/')) {
        return const VaultLibraryPathCheck(VaultLibraryPathIssue.duplicate);
      }
      if (p.isWithin(root, normalized) || p.isWithin(normalized, root)) {
        return const VaultLibraryPathCheck(VaultLibraryPathIssue.nested);
      }
    }
    return VaultLibraryPathCheck(
      VaultLibraryPathIssue.ok,
      normalizedPath: normalized,
    );
  }

  /// Marks a newly registered directory with `.nomedia` so the system gallery
  /// ignores it. Call this once when a library is added.
  Future<void> prepareLibraryDirectory(String path) =>
      _ensureNomedia(Directory(path));

  /// Writes `.nomedia` so the system gallery ignores this library.
  Future<void> _ensureNomedia(Directory dir) async {
    try {
      if (!await dir.exists()) await dir.create(recursive: true);
      final marker = File(p.join(dir.path, VaultPaths.nomedia));
      if (!await marker.exists()) await marker.create();
    } catch (e) {
      AppLogger.w('VaultStorageService', 'nomedia ${dir.path}: $e');
    }
  }

  static String _norm(String path) =>
      p.normalize(path.trim().replaceAll('\\', '/'));

  static bool _isVolumeRoot(String path) {
    final clean = path.replaceAll(RegExp(r'/+$'), '');
    const reserved = {
      '/',
      '/storage',
      '/storage/emulated',
      '/storage/emulated/0',
      '/sdcard',
      '/mnt/sdcard',
    };
    if (reserved.contains(clean) || clean.isEmpty) return true;
    final segments = p
        .split(clean)
        .where((segment) => segment.isNotEmpty && segment != '/')
        .toList();
    return segments.length < 2;
  }

  /// These are scanned for *legacy marker* files, not vault roots. Registering
  /// one wholesale would import every unrelated photo in the user's gallery as
  /// a vault item. Sub-folders of them are fine.
  static bool _isPublicMediaRoot(String path) {
    const base = '/storage/emulated/0';
    const publicRoots = {
      '$base/DCIM',
      '$base/DCIM/Camera',
      '$base/Pictures',
      '$base/Download',
      '$base/Downloads',
      '$base/Movies',
      '$base/Music',
    };
    return publicRoots.contains(path.replaceAll(RegExp(r'/+$'), ''));
  }

  Future<Directory> get shareStagingDir async {
    final vault = await ensureVault();
    final directory = Directory(p.join(vault.path, VaultPaths.shareStagingDir));
    if (!await directory.exists()) await directory.create(recursive: true);
    return directory;
  }

  /// Shared-storage hide root: `.privateheart_vault` with `.nomedia`.
  Future<Directory> ensureHiddenRoot() async {
    if (!initializeSharedRoot) {
      throw UnsupportedError(
        'Shared-storage vault is disabled for this platform',
      );
    }
    if (_hiddenRoot != null && await _hiddenRoot!.exists()) {
      return _hiddenRoot!;
    }
    // Prefer primary external storage (same volume as DCIM/Download) so move is rename.
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch (_) {}
    // getExternalStorageDirectory on Android is often …/Android/data/<pkg>/files
    // Walk up to the emulated root when possible.
    String rootPath;
    if (base != null) {
      final cur = base.path.replaceAll('\\', '/');
      final idx = cur.indexOf('/Android/data/');
      if (idx > 0) {
        rootPath = cur.substring(0, idx);
      } else if (cur.startsWith('/storage/emulated/0')) {
        rootPath = '/storage/emulated/0';
      } else {
        rootPath = cur;
      }
    } else {
      rootPath = '/storage/emulated/0';
    }
    final hidden = Directory(p.join(rootPath, VaultPaths.hiddenRootName));
    if (!await hidden.exists()) {
      await hidden.create(recursive: true);
    }
    final nomedia = File(p.join(hidden.path, VaultPaths.nomedia));
    if (!await nomedia.exists()) {
      await nomedia.create();
    }
    _hiddenRoot = hidden;
    return hidden;
  }

  /// Destination path for a hide move under the .nomedia vault.
  ///
  /// [encryptFileName] picks a random, extension-less name (`ADR-042`) instead
  /// of `<id8>_<originalName>`.  Callers pass `true` when the file is about to
  /// be encrypted, so the name never leaks the media type or the original
  /// title; the readable name lives in the database
  /// (`media_items.original_name`), which display, playback and restore use.
  ///
  /// Note: this is the Android shared-directory path.  `privateMediaFileFor`
  /// (iOS app-private storage) still uses readable names.
  Future<String> hiddenDestPath({
    required String id,
    required String originalName,
    required String? sourceFolder,
    bool encryptFileName = false,
  }) async {
    // New hides go to the currently selected library, so several vaults can
    // be used in parallel without ever moving the built-in one.
    final root = await activeLibraryRoot();
    final folder = HideNaming.sanitizeFolder(sourceFolder);
    final dir = Directory(p.join(root.path, folder));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    await _ensureNomedia(dir);
    if (encryptFileName) {
      // Retry on the (astronomically unlikely) name clash: renaming onto an
      // existing file would silently replace it.
      for (var attempt = 0; attempt < 5; attempt++) {
        final candidate = p.join(dir.path, HideNaming.encryptedFileName());
        if (!await File(candidate).exists()) return candidate;
      }
      AppLogger.w('VaultStorageService',
          'no free random name in ${dir.path}; falling back to a readable one');
    }
    final safeName = p.basename(originalName).replaceAll(RegExp(r'[\\/]'), '_');
    // Prefix id to avoid collisions when restoring multiple same names.
    final short = id.length >= 8 ? id.substring(0, 8) : id;
    return p.join(dir.path, '${short}_$safeName');
  }

  /// Stream-copy [source] into app-private vault (export/import fallback).
  Future<File> copyIntoVault({
    required File source,
    required String id,
    required String extension,
  }) async {
    final vault = await ensureVault();
    final ext = extension.startsWith('.') ? extension : '.$extension';
    final dest = File(p.join(vault.path, '$id$ext'));
    await source.openRead().pipe(dest.openWrite());
    return dest;
  }

  Future<File> writeBytesIntoVault({
    required List<int> bytes,
    required String id,
    required String extension,
  }) async {
    final vault = await ensureVault();
    final ext = extension.startsWith('.') ? extension : '.$extension';
    final dest = File(p.join(vault.path, '$id$ext'));
    await dest.writeAsBytes(bytes, flush: true);
    return dest;
  }

  /// App-private media destination used by the iOS Photos adapter. Android's
  /// D5 path continues to use [hiddenDestPath] and the shared `.nomedia` root.
  Future<File> privateMediaFileFor({
    required String id,
    required String originalName,
    String? sourceFolder,
  }) async {
    final vault = await ensureVault();
    final folder = HideNaming.sanitizeFolder(sourceFolder);
    final dir = Directory(p.join(vault.path, VaultPaths.mediaDir, folder));
    await dir.create(recursive: true);
    final safeName = p.basename(originalName).replaceAll(RegExp(r'[\\/]'), '_');
    // Keep the complete transaction id in the filename. A short prefix would
    // make unrelated iOS vault items collide once the library grows.
    return File(p.join(dir.path, '${id}_$safeName'));
  }

  /// Durable staging location for provider/PhotoKit materialization. Staging
  /// files are never treated as source identities and are removed after commit.
  Future<File> stagingFileFor({
    required String id,
    required String originalName,
  }) async {
    final vault = await ensureVault();
    final dir = Directory(p.join(vault.path, VaultPaths.stagingDir));
    await dir.create(recursive: true);
    final safeName = p.basename(originalName).replaceAll(RegExp(r'[\\/]'), '_');
    return File(p.join(dir.path, '$id-$safeName.part'));
  }

  String thumbPathFor(String id) {
    final base =
        _thumbs?.path ?? p.join(VaultPaths.vaultDir, VaultPaths.thumbsDir);
    return p.join(base, MediaThumbnailSpec.fileName(id));
  }

  Future<File> thumbFileFor(String id) async {
    final thumbs = await thumbsDir;
    return File(p.join(thumbs.path, MediaThumbnailSpec.fileName(id)));
  }

  Future<void> deleteMediaFiles({
    required String privatePath,
    String? thumbnailPath,
  }) async {
    try {
      final media = File(privatePath);
      if (await media.exists()) await media.delete();
    } catch (_) {}
    if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
      try {
        final thumb = File(thumbnailPath);
        if (await thumb.exists()) await thumb.delete();
      } catch (_) {}
    }
  }

  /// Deletes iOS restore bytes without hiding cleanup failures.
  ///
  /// The thumbnail is removed first so a failure cannot leave a database row
  /// whose verified media bytes have already disappeared.
  Future<void> deleteMediaFilesStrict({
    required String privatePath,
    String? thumbnailPath,
  }) async {
    if (thumbnailPath != null && thumbnailPath.isNotEmpty) {
      await _deleteFileStrict(File(thumbnailPath));
    }
    await _deleteFileStrict(File(privatePath));
  }

  /// Consumes one app-owned share entry and its now-empty digest directory.
  Future<void> deleteShareStagedSource(String sourcePath) async {
    final root = await shareStagingDir;
    final rootPath = p.canonicalize(root.absolute.path);
    final source = File(sourcePath).absolute;
    final normalizedSource = p.canonicalize(source.path);
    if (!p.isWithin(rootPath, normalizedSource)) {
      throw ArgumentError.value(
        sourcePath,
        'sourcePath',
        'Share staging cleanup must stay inside ${root.path}',
      );
    }

    await _deleteFileStrict(source);
    final entry = source.parent;
    if (p.equals(entry.path, root.path)) return;
    if (await entry.exists()) {
      final remaining = await entry.list(followLinks: false).toList();
      for (final entity in remaining) {
        if (entity is File && p.basename(entity.path).startsWith('.source-')) {
          await _deleteFileStrict(entity);
        }
      }
      final unexpected = await entry.list(followLinks: false).toList();
      if (unexpected.isNotEmpty) {
        throw StateError(
          'Share staging entry is not empty after consumption: ${entry.path}',
        );
      }
      await entry.delete();
      if (await entry.exists()) {
        throw FileSystemException(
          'Could not remove consumed share staging entry',
          entry.path,
        );
      }
    }
  }

  static Future<void> _deleteFileStrict(File file) async {
    if (await file.exists()) await file.delete();
    if (await file.exists()) {
      throw FileSystemException('Could not delete file', file.path);
    }
  }
}
