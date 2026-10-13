import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../core/utils/app_logger.dart';
import '../../domain/models/media_item.dart';
import '../repositories/media_repository.dart';
import 'encryption_key_manager.dart';
import 'media_encryption_service.dart';

/// Per-item result of one "decrypt this file" attempt.
enum DecryptItemOutcome {
  /// Plaintext is on disk and `encrypted_dek` was cleared.
  decrypted,

  /// The row has no stored DEK — nothing to do.
  alreadyPlaintext,

  /// No file on disk for this row.
  missing,

  /// The KEK was gone when this item was claimed (vault locked mid-pass).
  keyUnavailable,

  /// Decryption or the swap failed; the ciphertext was kept/restored.
  failed,
}

/// Live counters of one content-decryption pass.
class DecryptionStats {
  int decrypted = 0;
  int alreadyPlaintext = 0;
  int missing = 0;
  int failed = 0;

  /// Set when a queue found the KEK gone (vault locked mid-pass).
  bool keyLost = false;

  int get handled => decrypted + alreadyPlaintext + missing + failed;

  int unhandledOf(int total) => total - handled;
}

/// Turns ciphertext back into plaintext, in place (the reverse of
/// `BatchEncryptionService`).
///
/// **Order matters** (`ISSUE-039`): the file is decrypted and swapped first, and
/// `encrypted_dek` is cleared only after the plaintext is on disk.  The reverse
/// order has a crash window in which the media is ciphertext with no stored DEK,
/// which nothing can repair.  This order can only degrade into "plaintext with a
/// stale DEK" — repairable by `EncryptionRecordRepairService` and harmless for
/// browsing/playback.
class BatchDecryptionService {
  BatchDecryptionService({
    required MediaEncryptionService encryption,
    required EncryptionKeyManager keyManager,
    required MediaRepository repository,
  })  : _encryption = encryption,
        _keyManager = keyManager,
        _repository = repository;

  final MediaEncryptionService _encryption;
  final EncryptionKeyManager _keyManager;
  final MediaRepository _repository;

  /// Queue-count bounds — same reasoning as `BatchEncryptionService`: the work is
  /// mostly native/IO waiting, so two queues per core keep the crypto pool fed
  /// while peak memory stays ~2 MiB per in-flight file (`ISSUE-032`).
  static const int minQueues = 6;
  static const int maxQueues = 16;

  static int defaultQueueCount({int? itemCount}) {
    var queues = Platform.numberOfProcessors * 2;
    if (queues < minQueues) queues = minQueues;
    if (queues > maxQueues) queues = maxQueues;
    if (itemCount != null && itemCount < queues) queues = itemCount;
    return queues < 1 ? 1 : queues;
  }

  /// Items that still hold ciphertext (have a stored DEK).
  static List<MediaItem> pendingItems(List<MediaItem> encryptedItems) =>
      encryptedItems
          .where((item) =>
              item.encryptedDek != null && item.encryptedDek!.isNotEmpty)
          .toList(growable: false);

  /// Decrypts [items] over [queues] parallel queues.
  ///
  /// Returns the same [DecryptionStats] instance that [onProgress] receives;
  /// [isCancelled] is polled between items (an in-flight decrypt + swap is never
  /// interrupted — it would leave the row and the disk disagreeing).
  Future<DecryptionStats> run({
    required List<MediaItem> items,
    int? queues,
    bool Function()? isCancelled,
    void Function(DecryptionStats stats)? onProgress,
  }) async {
    final stats = DecryptionStats();
    if (items.isEmpty) return stats;

    final cancelled = isCancelled ?? _neverCancelled;
    final workerCount = (queues ?? defaultQueueCount(itemCount: items.length))
        .clamp(1, items.length);
    var cursor = 0;

    Future<void> queue() async {
      while (!cancelled() && !stats.keyLost) {
        final index = cursor++;
        if (index >= items.length) return;

        final item = items[index];
        final kek = _keyManager.getKey();
        if (kek == null) {
          stats.keyLost = true;
          return;
        }

        try {
          final outcome = await decryptOne(item, kek);
          if (outcome == DecryptItemOutcome.decrypted) {
            stats.decrypted++;
          } else if (outcome == DecryptItemOutcome.alreadyPlaintext) {
            stats.alreadyPlaintext++;
          } else if (outcome == DecryptItemOutcome.missing) {
            stats.missing++;
          } else {
            stats.failed++;
          }
        } catch (error, stackTrace) {
          stats.failed++;
          AppLogger.e('BatchDecryptionService',
              'decrypt ${item.id}: $error\n$stackTrace');
        }
        onProgress?.call(stats);
      }
    }

    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => queue()),
    );

    AppLogger.i(
      'BatchDecryptionService',
      'decrypt pass done: ${stats.decrypted} decrypted, '
          '${stats.alreadyPlaintext} already plaintext, ${stats.missing} missing, '
          '${stats.failed} failed, queues=$workerCount, keyLost=${stats.keyLost}',
    );
    return stats;
  }

  /// Decrypts one item in place (see the class docs for the ordering rule).
  Future<DecryptItemOutcome> decryptOne(MediaItem item, Uint8List kek) async {
    final dekBase64 = item.encryptedDek;
    if (dekBase64 == null || dekBase64.isEmpty) {
      return DecryptItemOutcome.alreadyPlaintext;
    }
    final file = File(item.privatePath);
    if (!file.existsSync()) return DecryptItemOutcome.missing;

    final dek = await _encryption.decryptDek(
      encryptedDekBase64: dekBase64,
      kek: kek,
    );
    if (dek == null) {
      AppLogger.e('BatchDecryptionService',
          'DEK decryption failed for ${item.id} (wrong KEK or corrupted DEK)');
      return DecryptItemOutcome.failed;
    }

    // The plaintext goes into the media's **own directory**: the swap below must
    // stay atomic, and a system-temp path may live on another filesystem.  The
    // temp name is derived from the row id, so a crashed run is simply
    // overwritten next time instead of piling up.
    final directory = file.parent.path;
    final tmp = File(p.join(directory, '.dec_tmp-${item.id}'));
    _bestEffortDelete(tmp);
    try {
      await _encryption.decryptFile(
        filePath: item.privatePath,
        destPath: tmp.path,
        dek: dek,
      );
    } catch (error, stackTrace) {
      AppLogger.e(
          'BatchDecryptionService', 'decrypt ${item.id}: $error\n$stackTrace');
      _bestEffortDelete(tmp);
      return DecryptItemOutcome.failed;
    }
    if (!tmp.existsSync() || tmp.lengthSync() == 0) {
      AppLogger.e('BatchDecryptionService',
          'decrypt produced no plaintext for ${item.id}; keeping ciphertext');
      _bestEffortDelete(tmp);
      return DecryptItemOutcome.failed;
    }

    // Atomic swap: ciphertext → `.dec_bak`, plaintext → original path, then drop
    // the backup.  Never delete-then-rename (PIT-034): a crash in between would
    // lose the only copy.
    final backup = File('${item.privatePath}.dec_bak');
    _bestEffortDelete(backup);
    try {
      await file.rename(backup.path);
    } catch (error, stackTrace) {
      AppLogger.e('BatchDecryptionService',
          'backup before swap failed for ${item.id}: $error\n$stackTrace');
      _bestEffortDelete(tmp);
      return DecryptItemOutcome.failed;
    }
    try {
      await tmp.rename(item.privatePath);
    } catch (error, stackTrace) {
      AppLogger.e('BatchDecryptionService',
          'swap failed for ${item.id}: $error\n$stackTrace');
      // Put the ciphertext back; if even that fails, the backup stays on disk.
      await _restoreFile(backup, item.privatePath);
      _bestEffortDelete(tmp);
      return DecryptItemOutcome.failed;
    }
    _bestEffortDelete(backup);

    // Only now is it safe to forget the DEK: the plaintext is on disk.  Failing
    // here leaves "plaintext + stale DEK", which is the *safe* direction
    // (repairable, and re-encryption still works).
    try {
      await _repository.updateEncryptedDek(item.id, null);
    } catch (error, stackTrace) {
      AppLogger.e('BatchDecryptionService',
          'kept stale DEK for ${item.id} (repairable): $error\n$stackTrace');
    }
    return DecryptItemOutcome.decrypted;
  }

  Future<void> _restoreFile(File backup, String originalPath) async {
    try {
      if (backup.existsSync()) await backup.rename(originalPath);
    } catch (error) {
      AppLogger.e(
          'BatchDecryptionService',
          'could not restore $originalPath; ciphertext kept at ${backup.path}: '
              '$error');
    }
  }

  void _bestEffortDelete(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  static bool _neverCancelled() => false;
}
