import 'dart:io';
import 'dart:typed_data';

import '../../core/utils/app_logger.dart';
import '../../domain/models/media_item.dart';
import '../repositories/media_repository.dart';
import 'encryption_key_manager.dart';
import 'media_encryption_service.dart';

/// Per-item result of one "encrypt this file" attempt.
enum BatchEncryptOutcome {
  /// Ciphertext on disk **and** the wrapped DEK is stored in the DB.
  encrypted,

  /// Native encryption / DB write failed while the media is still usable.
  failed,

  /// The row's media file is gone; maintenance prunes the row on next launch.
  missing,

  /// Already ciphertext while the row has no DEK: it can neither be encrypted
  /// again (that would corrupt it) nor decrypted (ISSUE-030).
  alreadyCiphertextWithoutKey,
}

/// Live counters + flags of one batch encryption pass.
///
/// The same instance is handed to the `onProgress` callback on every handled
/// item and returned by [BatchEncryptionService.run].
class BatchEncryptionStats {
  /// Items that reached the goal state (ciphertext + stored DEK).
  int encrypted = 0;

  /// Items that threw (media left usable, DEK rolled back when still plaintext).
  int failed = 0;

  /// Rows whose media file is gone.
  int missing = 0;

  /// Ciphertext without a stored DEK — needs user action, never retried here.
  int skippedNoKey = 0;

  /// Set when a queue found the KEK gone (vault locked mid-pass): every queue
  /// stops, the files it never reached stay plaintext.
  bool keyLost = false;

  /// Items a queue is done with (successful or not).
  int get handled => encrypted + failed + missing + skippedNoKey;

  /// Items the pass never reached (cancelled / locked out).
  int unhandledOf(int total) => total - handled;
}

/// Encrypts many existing files at once, split over several parallel queues.
///
/// Serially, 6 000+ files took minutes: every item costs a header probe, a DEK
/// wrap, a DB write and one native AES-GCM round trip, and each of them waited
/// for the previous item.  [run] therefore starts [defaultQueueCount] workers
/// that all pull from **one shared cursor**, so a queue that lands a big video
/// is not stuck with the rest of the list — its next item is simply "whatever
/// is left".
///
/// The data-safety rules of the serial version are kept on purpose (both come
/// from real data-loss incidents):
///  * `ISSUE-030` — every item is claimed by exactly one queue, so a file is
///    never encrypted twice; the caller still holds its own re-entry guard.
///  * `PIT-051` / `PIT-044` — the DEK is wrapped and **persisted before** the
///    file is touched, and it is rolled back only while the media is verifiably
///    still plaintext.
class BatchEncryptionService {
  BatchEncryptionService({
    required MediaEncryptionService encryption,
    required EncryptionKeyManager keyManager,
    required MediaRepository repository,
  })  : _encryption = encryption,
        _keyManager = keyManager,
        _repository = repository;

  final MediaEncryptionService _encryption;
  final EncryptionKeyManager _keyManager;
  final MediaRepository _repository;

  /// Queue-count bounds.  Below [minQueues] the pass wastes the phone's cores on
  /// MethodChannel / sqflite latency; above [maxQueues] the extra queues only
  /// pile up on the native crypto pool (bounded in `MainActivity.runCrypto`,
  /// which is what really keeps peak memory at ~2 MiB per in-flight file —
  /// `ISSUE-032` / `ADR-038`).
  static const int minQueues = 6;
  static const int maxQueues = 24;

  /// Queues for a pass over [itemCount] items: two per CPU core (the work is
  /// mostly *waiting* — native round trips and DB writes — so oversubscribing
  /// the CPU keeps the crypto pool fed), clamped to [minQueues]…[maxQueues] and
  /// never more than one queue per item.
  static int defaultQueueCount({int? itemCount}) {
    var queues = Platform.numberOfProcessors * 2;
    if (queues < minQueues) queues = minQueues;
    if (queues > maxQueues) queues = maxQueues;
    if (itemCount != null && itemCount < queues) queues = itemCount;
    return queues < 1 ? 1 : queues;
  }

  /// Encrypts [items] with [queues] parallel workers (default:
  /// [defaultQueueCount]).
  ///
  /// [isCancelled] is polled between items — a queue never aborts an in-flight
  /// native call, that would leave a temp file behind.  [onProgress] runs after
  /// every handled item; UI callers should throttle their rebuilds there (one
  /// rebuild per item was pure overhead at 6 000+ items).
  Future<BatchEncryptionStats> run({
    required List<MediaItem> items,
    int? queues,
    bool Function()? isCancelled,
    void Function(BatchEncryptionStats stats)? onProgress,
  }) async {
    final stats = BatchEncryptionStats();
    if (items.isEmpty) return stats;

    final cancelled = isCancelled ?? _neverCancelled;
    final workerCount = (queues ?? defaultQueueCount(itemCount: items.length))
        .clamp(1, items.length);
    // Shared cursor: each queue claims the next unclaimed index.  The pass lives
    // in the single Dart isolate, so `cursor++` needs no lock — and an item that
    // is being encrypted is never handed to a second queue (ISSUE-030).
    var cursor = 0;

    Future<void> queue() async {
      while (!cancelled() && !stats.keyLost) {
        final index = cursor++;
        if (index >= items.length) return;

        final item = items[index];
        final kek = _keyManager.getKey();
        if (kek == null) {
          // Vault locked mid-pass (auto-lock / "lock now"): stop every queue.
          // The claimed item stays unhandled on purpose, so the caller can
          // report "stopped after N of M".
          stats.keyLost = true;
          return;
        }

        try {
          final outcome = await encryptOne(item, kek);
          if (outcome == BatchEncryptOutcome.encrypted) {
            stats.encrypted++;
          } else if (outcome == BatchEncryptOutcome.failed) {
            stats.failed++;
          } else if (outcome == BatchEncryptOutcome.missing) {
            stats.missing++;
          } else {
            stats.skippedNoKey++;
          }
        } catch (error, stackTrace) {
          stats.failed++;
          AppLogger.e(
            'BatchEncryptionService',
            'batch encrypt ${item.id}: $error\n$stackTrace',
          );
        }
        onProgress?.call(stats);
      }
    }

    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => queue()),
    );

    AppLogger.i(
      'BatchEncryptionService',
      'batch encrypt pass done: ${stats.encrypted} encrypted, '
          '${stats.failed} failed, ${stats.missing} missing, '
          '${stats.skippedNoKey} without key, queues=$workerCount, '
          'keyLost=${stats.keyLost}',
    );
    return stats;
  }

  /// Encrypts a single item, honouring the crash-safe ordering of `PIT-051`.
  ///
  /// Exposed so a caller can reuse the one-item path (and its rollback rules)
  /// without the queue machinery.
  Future<BatchEncryptOutcome> encryptOne(MediaItem item, Uint8List kek) async {
    final file = File(item.privatePath);
    if (!file.existsSync()) {
      // Row without a file: maintenance drops it on next launch.
      return BatchEncryptOutcome.missing;
    }
    if (_encryption.looksEncrypted(file)) {
      AppLogger.w(
        'BatchEncryptionService',
        'batch encrypt skipped ${item.id}: already ciphertext without a '
            'stored DEK',
      );
      return BatchEncryptOutcome.alreadyCiphertextWithoutKey;
    }

    // PIT-044 / PIT-051 order: wrap the DEK → persist it → only then encrypt the
    // file.  Encrypting first leaves a crash window in which the media is
    // ciphertext while its DEK never reached the DB (unrecoverable).
    final dek = _encryption.generateDek();
    final nonce = _encryption.generateNonce();
    final encryptedDek = await _encryption.encryptDek(dek: dek, kek: kek);
    await _repository.updateEncryptedDek(item.id, encryptedDek);

    try {
      await _encryption.encryptFileWithDek(
        filePath: item.privatePath,
        dek: dek,
        nonce: Uint8List.fromList(nonce),
      );
      return BatchEncryptOutcome.encrypted;
    } catch (error) {
      // The native in-place swap can succeed even when its reply is lost
      // (Activity rebuilt / channel restart).  The media is ciphertext then, so
      // the saved DEK must stay — clearing it would orphan the file forever.
      if (_encryption.looksEncrypted(file)) {
        AppLogger.w(
          'BatchEncryptionService',
          'kept saved DEK for ${item.id}: the media is already encrypted even '
              'though the encrypt call failed ($error)',
        );
        return BatchEncryptOutcome.encrypted;
      }
      // Verifiably still plaintext → the persisted DEK is a lie, drop it so the
      // row shows up in the next pass again.
      await _repository.updateEncryptedDek(item.id, null);
      rethrow;
    }
  }

  static bool _neverCancelled() => false;
}
