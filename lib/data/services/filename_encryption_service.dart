import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/utils/app_logger.dart';
import '../../domain/models/media_item.dart';
import '../repositories/media_repository.dart';
import 'hide_naming.dart';

/// Per-item result of one "encrypt this file name" attempt.
enum FilenameRenameOutcome {
  /// The file now has a random, extension-less name and the row points at it.
  renamed,

  /// Already a filename-encrypted name — nothing to do (idempotent re-runs).
  alreadyEncrypted,

  /// No file on disk for this row.
  missing,

  /// Row has no stored DEK (still plaintext): never rename a plaintext file.
  plaintext,

  /// Rename or DB update failed; the original name was restored.
  failed,
}

/// Live counters of one filename-encryption pass.
class FilenameRenameStats {
  int renamed = 0;
  int alreadyEncrypted = 0;
  int missing = 0;
  int plaintext = 0;
  int failed = 0;

  int get handled => renamed + alreadyEncrypted + missing + plaintext + failed;
}

/// Live counters of one filename-restore pass (the reverse of
/// [FilenameRenameStats]).
class FilenameRestoreStats {
  int restored = 0;
  int alreadyReadable = 0;
  int missing = 0;
  int failed = 0;

  int get handled => restored + alreadyReadable + missing + failed;
}

/// Per-item result of one "restore this file name" attempt.
enum FilenameRestoreOutcome {
  /// The readable name is back and the row points at it.
  restored,

  /// Not a random name — nothing to do.
  alreadyReadable,

  /// No file on disk for this row.
  missing,

  /// Rename or DB update failed; the random name was kept/restored.
  failed,
}

/// Renames ciphertext media to a random, **extension-less** name (ADR-042).
///
/// Why: the vault keeps `<uuid8>_<original-name>.<ext>`, so programs that scan
/// by extension (or by keyword) still recognise the file as media even though
/// its bytes are encrypted.  The stored original name is untouched — all
/// display/restore paths use `media_items.original_name`.
///
/// Safety rules (mirroring the batch encryptor):
///  * only rows with a stored DEK are renamed (a plaintext file must keep its
///    name so the user can still recognise it);
///  * the rename stays inside the media's own directory (same filesystem ⇒
///    atomic) and is verified (target exists, same byte count) **before** the DB
///    row is repointed;
///  * if the DB update fails, the file is renamed back, so "DB path == file on
///    disk" always holds;
///  * idempotent: an already-encrypted name is skipped, so the pass can be
///    re-run after a crash or a cancel.
class FilenameEncryptionService {
  FilenameEncryptionService({required MediaRepository repository})
      : _repository = repository;

  final MediaRepository _repository;

  /// Queue-count bounds, same reasoning as `BatchEncryptionService` (the work is
  /// a rename + a DB write, so it is cheap but IO-bound).
  static const int minQueues = 4;
  static const int maxQueues = 16;

  /// True when [fileName] already is a random hex name (32 lowercase hex chars).
  ///
  /// Delegates to [HideNaming.isEncryptedFileName] so the import path and this
  /// migration always agree on the format (`ADR-042`).
  static bool isEncryptedName(String fileName) =>
      HideNaming.isEncryptedFileName(fileName);

  /// 32 hex chars (128 random bits), no extension — see
  /// [HideNaming.encryptedFileName].
  static String generateName() => HideNaming.encryptedFileName();

  /// The items of [encryptedItems] whose file name is still readable.
  static List<MediaItem> pendingItems(List<MediaItem> encryptedItems) =>
      encryptedItems
          .where((item) => !isEncryptedName(p.basename(item.privatePath)))
          .toList(growable: false);

  /// Items whose file name is a random (extension-less) one — the ones a
  /// "decrypt file names" pass must restore.
  static List<MediaItem> renamedItems(List<MediaItem> items) => items
      .where((item) => isEncryptedName(p.basename(item.privatePath)))
      .toList(growable: false);

  /// Readable target name for [item]: the stored original name, sanitized to a
  /// legal single path segment.
  static String readableNameFor(MediaItem item) {
    var name = item.originalName.trim();
    if (name.isEmpty) name = 'privi-media';
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001f]'), '_');
    if (name == '.' || name == '..') name = 'privi-media';
    return name;
  }

  static int defaultQueueCount({int? itemCount}) {
    var queues = Platform.numberOfProcessors;
    if (queues < minQueues) queues = minQueues;
    if (queues > maxQueues) queues = maxQueues;
    if (itemCount != null && itemCount < queues) queues = itemCount;
    return queues < 1 ? 1 : queues;
  }

  /// Encrypts the file names of [items] over [queues] parallel workers.
  ///
  /// Returns the same [FilenameRenameStats] instance that [onProgress] receives;
  /// [isCancelled] is polled between items (an in-flight rename is never
  /// interrupted — it would leave the row and the disk disagreeing).
  Future<FilenameRenameStats> run({
    required List<MediaItem> items,
    int? queues,
    bool Function()? isCancelled,
    void Function(FilenameRenameStats stats)? onProgress,
  }) async {
    final stats = FilenameRenameStats();
    if (items.isEmpty) return stats;

    final cancelled = isCancelled ?? _neverCancelled;
    final workerCount = (queues ?? defaultQueueCount(itemCount: items.length))
        .clamp(1, items.length);
    var cursor = 0;

    Future<void> queue() async {
      while (!cancelled()) {
        final index = cursor++;
        if (index >= items.length) return;
        final item = items[index];
        try {
          final outcome = await renameOne(item);
          if (outcome == FilenameRenameOutcome.renamed) {
            stats.renamed++;
          } else if (outcome == FilenameRenameOutcome.alreadyEncrypted) {
            stats.alreadyEncrypted++;
          } else if (outcome == FilenameRenameOutcome.missing) {
            stats.missing++;
          } else if (outcome == FilenameRenameOutcome.plaintext) {
            stats.plaintext++;
          } else {
            stats.failed++;
          }
        } catch (error, stackTrace) {
          stats.failed++;
          AppLogger.e('FilenameEncryptionService',
              'encrypt name ${item.id}: $error\n$stackTrace');
        }
        onProgress?.call(stats);
      }
    }

    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => queue()),
    );

    AppLogger.i(
      'FilenameEncryptionService',
      'filename encryption pass done: ${stats.renamed} renamed, '
          '${stats.alreadyEncrypted} already encrypted, ${stats.missing} missing, '
          '${stats.plaintext} plaintext (skipped), ${stats.failed} failed, '
          'queues=$workerCount',
    );
    return stats;
  }

  /// Renames one ciphertext file and repoints its row (see class docs).
  Future<FilenameRenameOutcome> renameOne(MediaItem item) async {
    final dek = item.encryptedDek;
    if (dek == null || dek.isEmpty) {
      AppLogger.w('FilenameEncryptionService',
          'refusing to rename ${item.id}: no stored DEK (still plaintext)');
      return FilenameRenameOutcome.plaintext;
    }
    final file = File(item.privatePath);
    if (isEncryptedName(p.basename(item.privatePath))) {
      return FilenameRenameOutcome.alreadyEncrypted;
    }
    if (!file.existsSync()) return FilenameRenameOutcome.missing;

    // Same directory as the media (same filesystem ⇒ atomic rename).  Retry a
    // few times in the (vanishingly unlikely) case the random name is taken.
    final directory = file.parent.path;
    File? target;
    for (var attempt = 0; attempt < 5; attempt++) {
      final candidate = File(p.join(directory, generateName()));
      if (!candidate.existsSync()) {
        target = candidate;
        break;
      }
    }
    if (target == null) {
      AppLogger.e('FilenameEncryptionService',
          'no free random name in $directory for ${item.id}');
      return FilenameRenameOutcome.failed;
    }

    final originalLength = file.lengthSync();
    try {
      await file.rename(target.path);
    } catch (error, stackTrace) {
      AppLogger.e('FilenameEncryptionService',
          'rename ${item.privatePath}: $error\n$stackTrace');
      return FilenameRenameOutcome.failed;
    }

    // Verify on disk **before** repointing the row: the new name must exist with
    // exactly the same byte count, otherwise put the original name back.
    if (!target.existsSync() || target.lengthSync() != originalLength) {
      AppLogger.e('FilenameEncryptionService',
          'rename verification failed for ${item.id}; restoring the old name');
      await _restore(target, item.privatePath);
      return FilenameRenameOutcome.failed;
    }

    try {
      await _repository.updatePrivatePath(item.id, target.path);
    } catch (error, stackTrace) {
      AppLogger.e('FilenameEncryptionService',
          'DB update failed for ${item.id}: $error\n$stackTrace');
      // Keep "row path == file on disk" true, otherwise the media looks lost.
      await _restore(target, item.privatePath);
      return FilenameRenameOutcome.failed;
    }
    return FilenameRenameOutcome.renamed;
  }

  /// Puts the file back at [originalPath] after a failed verification/DB write.
  Future<void> _restore(File renamed, String originalPath) async {
    try {
      if (renamed.existsSync()) await renamed.rename(originalPath);
    } catch (error) {
      AppLogger.e('FilenameEncryptionService',
          'could not restore $originalPath after a failed rename: $error');
    }
  }

  /// Reverse pass of [run]: gives the random names back to [items] (ADR-042).
  ///
  /// Only names produced by [run] (32 hex chars, no extension) are restored;
  /// the readable name comes from `media_items.original_name`, so browsing and
  /// restoring to the gallery stay consistent.
  Future<FilenameRestoreStats> restoreNames({
    required List<MediaItem> items,
    int? queues,
    bool Function()? isCancelled,
    void Function(FilenameRestoreStats stats)? onProgress,
  }) async {
    final stats = FilenameRestoreStats();
    if (items.isEmpty) return stats;

    final cancelled = isCancelled ?? _neverCancelled;
    final workerCount = (queues ?? defaultQueueCount(itemCount: items.length))
        .clamp(1, items.length);
    var cursor = 0;

    Future<void> queue() async {
      while (!cancelled()) {
        final index = cursor++;
        if (index >= items.length) return;
        final item = items[index];
        try {
          final outcome = await restoreOne(item);
          if (outcome == FilenameRestoreOutcome.restored) {
            stats.restored++;
          } else if (outcome == FilenameRestoreOutcome.alreadyReadable) {
            stats.alreadyReadable++;
          } else if (outcome == FilenameRestoreOutcome.missing) {
            stats.missing++;
          } else {
            stats.failed++;
          }
        } catch (error, stackTrace) {
          stats.failed++;
          AppLogger.e('FilenameEncryptionService',
              'restore name ${item.id}: $error\n$stackTrace');
        }
        onProgress?.call(stats);
      }
    }

    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => queue()),
    );

    AppLogger.i(
      'FilenameEncryptionService',
      'filename restore pass done: ${stats.restored} restored, '
          '${stats.alreadyReadable} already readable, ${stats.missing} missing, '
          '${stats.failed} failed, queues=$workerCount',
    );
    return stats;
  }

  /// Restores the readable name of one random-named file.
  Future<FilenameRestoreOutcome> restoreOne(MediaItem item) async {
    final file = File(item.privatePath);
    if (!isEncryptedName(p.basename(item.privatePath))) {
      return FilenameRestoreOutcome.alreadyReadable;
    }
    if (!file.existsSync()) return FilenameRestoreOutcome.missing;

    final directory = file.parent.path;
    final target = _freePathIn(
      directory,
      readableNameFor(item),
      item.id.length >= 8 ? item.id.substring(0, 8) : item.id,
    );
    final originalLength = file.lengthSync();
    try {
      await file.rename(target);
    } catch (error, stackTrace) {
      AppLogger.e('FilenameEncryptionService',
          'restore rename ${item.privatePath}: $error\n$stackTrace');
      return FilenameRestoreOutcome.failed;
    }
    // Verify before repointing the row (same rule as `renameOne`).
    final renamed = File(target);
    if (!renamed.existsSync() || renamed.lengthSync() != originalLength) {
      AppLogger.e('FilenameEncryptionService',
          'restore verification failed for ${item.id}; restoring the random name');
      await _restore(renamed, item.privatePath);
      return FilenameRestoreOutcome.failed;
    }
    try {
      await _repository.updatePrivatePath(item.id, target);
    } catch (error, stackTrace) {
      AppLogger.e('FilenameEncryptionService',
          'DB update failed while restoring ${item.id}: $error\n$stackTrace');
      await _restore(renamed, item.privatePath);
      return FilenameRestoreOutcome.failed;
    }
    return FilenameRestoreOutcome.restored;
  }

  /// A free path for [wanted] inside [directory]; never overwrites an existing
  /// file.  Falls back to the vault's historical `<id8>_<name>` form, then to
  /// `-2`, `-3`, …, and finally to a random name.
  String _freePathIn(String directory, String wanted, String idHint) {
    final direct = p.join(directory, wanted);
    if (!File(direct).existsSync()) return direct;
    final prefixed = p.join(directory, '${idHint}_$wanted');
    if (!File(prefixed).existsSync()) return prefixed;
    final base = p.basenameWithoutExtension(wanted);
    final ext = p.extension(wanted);
    for (var i = 2; i <= 99; i++) {
      final candidate = p.join(directory, '$base-$i$ext');
      if (!File(candidate).existsSync()) return candidate;
    }
    return p.join(directory, '${generateName()}$ext');
  }

  static bool _neverCancelled() => false;
}
