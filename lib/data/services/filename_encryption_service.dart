import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import '../../core/utils/app_logger.dart';
import '../../domain/models/media_item.dart';
import '../repositories/media_repository.dart';

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

  static final RegExp _encryptedNamePattern = RegExp(r'^[0-9a-f]{32}$');
  static final Random _random = Random.secure();

  /// Queue-count bounds, same reasoning as [BatchEncryptionService] (the work is
  /// a rename + a DB write, so it is cheap but IO-bound).
  static const int minQueues = 4;
  static const int maxQueues = 16;

  /// True when [fileName] already is a random hex name (32 lowercase hex chars).
  static bool isEncryptedName(String fileName) =>
      _encryptedNamePattern.hasMatch(fileName);

  /// 32 hex chars (128 random bits), no extension.
  static String generateName() {
    final buffer = StringBuffer();
    for (var i = 0; i < 16; i++) {
      buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// The items of [encryptedItems] whose file name is still readable.
  static List<MediaItem> pendingItems(List<MediaItem> encryptedItems) =>
      encryptedItems
          .where((item) => !isEncryptedName(p.basename(item.privatePath)))
          .toList(growable: false);

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

  static bool _neverCancelled() => false;
}
