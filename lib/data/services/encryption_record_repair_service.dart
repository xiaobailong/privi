import 'dart:io';

import '../../core/utils/app_logger.dart';
import '../../domain/models/media_item.dart';
import '../repositories/media_repository.dart';
import 'media_encryption_service.dart';

/// How one row's encryption bookkeeping compares with the file on disk.
enum EncryptionRecordState {
  /// Ciphertext + DEK, or plaintext without a DEK: nothing to repair.
  consistent,

  /// A DEK is stored while the file is plaintext — a stale/failed record.
  staleDek,

  /// Ciphertext without a stored DEK: unrecoverable orphan (reported only).
  orphanCiphertext,

  /// No file on disk for this row (maintenance prunes the row later).
  missingFile,
}

/// Counters of one repair scan.
class EncryptionRecordRepairStats {
  int checked = 0;
  int consistent = 0;
  int staleCleared = 0;
  int orphanCiphertext = 0;
  int missingFile = 0;
  int failed = 0;

  /// Rows that need attention, whether or not the scan applied changes.
  int get issues => staleCleared + orphanCiphertext;

  /// Rows the scan is done with.
  int get handled =>
      consistent + staleCleared + orphanCiphertext + missingFile + failed;
}

/// Repairs rows whose encryption bookkeeping disagrees with the bytes on disk —
/// the "clear failed encryption records" maintenance action (`ISSUE-039`).
///
/// The case worth fixing: a row stores `encrypted_dek` while the media is still
/// **plaintext**.  An early bug could leave that behind, and the decrypt path
/// produces exactly that shape when the process dies after the plaintext swap but
/// before the DEK is cleared.  Such a row makes the app treat a plaintext file as
/// ciphertext (viewer/player try to "decrypt" it and fail), so the record is
/// cleared — which also puts the file back into the "encrypt existing files"
/// queue.
///
/// The opposite case ("ciphertext without a DEK") is **never** modified: the DEK
/// is gone, so the media is unrecoverable and deleting the row would only hide
/// the problem.  It is counted so the UI can report it.
class EncryptionRecordRepairService {
  EncryptionRecordRepairService({
    required MediaEncryptionService encryption,
    required MediaRepository repository,
  })  : _encryption = encryption,
        _repository = repository;

  final MediaEncryptionService _encryption;
  final MediaRepository _repository;

  /// The scan only reads a 32-byte header per row (and occasionally writes one
  /// column), so a handful of queues is plenty.
  static const int queueCount = 8;

  /// Scans [items]; when [apply] is true, stale DEK records are cleared.
  ///
  /// Run it once with `apply: false` to count the issues (the confirmation
  /// dialog shows that number), then again with `apply: true`.
  Future<EncryptionRecordRepairStats> scan({
    required List<MediaItem> items,
    bool apply = false,
    bool Function()? isCancelled,
    void Function(EncryptionRecordRepairStats stats)? onProgress,
  }) async {
    final stats = EncryptionRecordRepairStats();
    if (items.isEmpty) return stats;

    final cancelled = isCancelled ?? _neverCancelled;
    final workerCount = queueCount.clamp(1, items.length);
    var cursor = 0;

    Future<void> queue() async {
      while (!cancelled()) {
        final index = cursor++;
        if (index >= items.length) return;
        final item = items[index];
        stats.checked++;
        try {
          final state = _inspect(item);
          if (state == EncryptionRecordState.staleDek) {
            if (apply) {
              await _repository.updateEncryptedDek(item.id, null);
              AppLogger.w(
                'EncryptionRecordRepairService',
                'cleared stale encryption record for ${item.id} '
                    '(the file is plaintext)',
              );
            }
            stats.staleCleared++;
          } else if (state == EncryptionRecordState.orphanCiphertext) {
            stats.orphanCiphertext++;
            final file = File(item.privatePath);
            AppLogger.w(
              'EncryptionRecordRepairService',
              'orphan ciphertext without DEK for ${item.id} — not repairable '
                  '(bytes=${MediaEncryptionService.lengthOrMinusOne(file)}, '
                  'header=${MediaEncryptionService.headerHex(file)})',
            );
          } else if (state == EncryptionRecordState.missingFile) {
            stats.missingFile++;
          } else {
            stats.consistent++;
          }
        } catch (error, stackTrace) {
          stats.failed++;
          AppLogger.e('EncryptionRecordRepairService',
              'inspect ${item.id}: $error\n$stackTrace');
        }
        onProgress?.call(stats);
      }
    }

    await Future.wait(
      List<Future<void>>.generate(workerCount, (_) => queue()),
    );

    AppLogger.i(
      'EncryptionRecordRepairService',
      'record scan done (apply=$apply): handled=${stats.handled}, '
          'stale=${stats.staleCleared}, orphans=${stats.orphanCiphertext}, '
          'missing=${stats.missingFile}, failed=${stats.failed}',
    );
    return stats;
  }

  /// Reads only the 32-byte header (`looksEncrypted`), so this is cheap.
  EncryptionRecordState _inspect(MediaItem item) {
    final file = File(item.privatePath);
    if (!file.existsSync()) return EncryptionRecordState.missingFile;
    final hasDek = item.encryptedDek != null && item.encryptedDek!.isNotEmpty;
    final isCiphertext = _encryption.looksEncrypted(file);
    if (hasDek == isCiphertext) return EncryptionRecordState.consistent;
    return hasDek
        ? EncryptionRecordState.staleDek
        : EncryptionRecordState.orphanCiphertext;
  }

  static bool _neverCancelled() => false;
}
