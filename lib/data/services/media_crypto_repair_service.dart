import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../core/utils/app_logger.dart';
import '../../domain/models/media_item.dart';
import '../repositories/media_repository.dart';
import 'encryption_key_manager.dart';
import 'media_encryption_service.dart';

/// What one repair attempt did to one file.
enum CryptoRepairOutcome {
  /// Ciphertext → plaintext on disk; the owning row's DEK was cleared.
  decrypted,

  /// The file is plaintext while a row still stored a DEK: record cleared.
  recordCleared,

  /// Ciphertext, but none of the stored DEKs decrypt it — kept as-is.
  ///
  /// This is the log's `Authentication failed` shape: the bytes were encrypted
  /// with a key that is no longer in the database (`ISSUE-043`).
  keyMismatch,

  /// Ciphertext and no DEK for it anywhere: unrecoverable, kept as-is.
  noKey,

  /// Plaintext without any stored DEK: nothing to fix.
  nothingToDo,

  /// No file on disk for this path.
  missing,

  /// Vault locked (KEK not in memory) while the file is ciphertext.
  locked,

  /// IO or unexpected failure — the file was left untouched.
  failed,
}

/// Result of one [MediaCryptoRepairService.repairPaths] item.
class CryptoRepairResult {
  const CryptoRepairResult({
    required this.path,
    required this.outcome,
    this.source,
    this.detail,
  });

  final String path;
  final CryptoRepairOutcome outcome;

  /// Which DEK worked: `owner` (the row that points at this file) or
  /// `same-name` / `same-size` for a cross-row match.
  final String? source;

  /// Extra diagnostic text for the log.
  final String? detail;
}

/// Aggregated results of one repair run.
class CryptoRepairReport {
  const CryptoRepairReport(this.results);

  final List<CryptoRepairResult> results;

  int get total => results.length;

  int countOf(CryptoRepairOutcome outcome) =>
      results.where((r) => r.outcome == outcome).length;

  int get decrypted => countOf(CryptoRepairOutcome.decrypted);
  int get recordCleared => countOf(CryptoRepairOutcome.recordCleared);
  int get keyMismatch => countOf(CryptoRepairOutcome.keyMismatch);
  int get noKey => countOf(CryptoRepairOutcome.noKey);
  int get nothingToDo => countOf(CryptoRepairOutcome.nothingToDo);
  int get missing => countOf(CryptoRepairOutcome.missing);
  int get locked => countOf(CryptoRepairOutcome.locked);
  int get failed => countOf(CryptoRepairOutcome.failed);

  /// Paths that are plaintext on disk now (either decrypted here or already
  /// plaintext) — the caller uses this to refresh platform indexes.
  Iterable<String> get plaintextPaths => results
      .where((r) =>
          r.outcome == CryptoRepairOutcome.decrypted ||
          r.outcome == CryptoRepairOutcome.recordCleared ||
          r.outcome == CryptoRepairOutcome.nothingToDo)
      .map((r) => r.path);
}

/// Per-selection "加解密修复": make the bytes on disk and the encryption record
/// agree again.
///
/// Why this exists — a `Bad state: File already appears encrypted` during a hide
/// stores a **fresh DEK that never encrypted anything** (the file was skipped,
/// not encrypted).  Every later decrypt then fails the AES-GCM tag check, which
/// blocks 取消隐藏 **by design** (`ISSUE-029`④: never move ciphertext to the
/// gallery) while the row and its DEK stay behind (`ISSUE-041`).  The same shape
/// appears when a whitelist miss left a plaintext file recorded as ciphertext
/// (`ISSUE-043`).
///
/// Repair order (per file, cheap checks first):
///  1. plaintext sniff ([MediaEncryptionService.looksLikePlaintextMedia]) →
///     when a DEK is recorded the **record** is the problem: clear it, nothing
///     on disk is touched.
///  2. otherwise try the DEKs that could belong to this file — the owner row
///     first, then rows with the same original name / same byte size (bounded).
///     A success is swapped in atomically, and only then is the DEK cleared.
///  3. nothing works → report the concrete reason and leave the file alone.
///
/// Crash safety mirrors `BatchDecryptionService` (`ISSUE-039`, `PIT-064`): the
/// plaintext is written to `<dir>/.enc_tmp-repair-<hash>`, the ciphertext moves
/// to `<path>.enc_bak`, the plaintext is renamed into place and the backup is
/// deleted last.  Those are exactly the names
/// `MaintenanceService._repairEncryptionArtifacts` heals on the next launch
/// (`ISSUE-030`), so an interrupted run inside the vault is recoverable.
class MediaCryptoRepairService {
  MediaCryptoRepairService({
    required MediaEncryptionService encryption,
    required EncryptionKeyManager keyManager,
    required MediaRepository repository,
  })  : _encryption = encryption,
        _keyManager = keyManager,
        _repository = repository;

  final MediaEncryptionService _encryption;
  final EncryptionKeyManager _keyManager;
  final MediaRepository _repository;

  /// Upper bound on cross-row DEK attempts.  Each attempt decrypts the whole
  /// file before the tag check fails, so this stays small on purpose.
  static const int maxExtraCandidates = 6;

  /// Files above this size only get their own row's DEK tried — an 8-candidate
  /// sweep over a multi-GiB video would look like a hang.
  static const int maxCrossCheckBytes = 512 << 20; // 512 MiB

  /// Repairs [paths] one after another (never in parallel: several items may
  /// share a directory, and two writes to one file would corrupt it — see
  /// `ISSUE-030`).
  Future<CryptoRepairReport> repairPaths(
    List<String> paths, {
    void Function(int done, int total, String current)? onProgress,
  }) async {
    final results = <CryptoRepairResult>[];
    if (paths.isEmpty) return CryptoRepairReport(results);

    final kek = _keyManager.getKey();
    // One snapshot for the whole run: rows are only ever *cleared* here, so a
    // stale snapshot can at worst retry a DEK that was just removed.
    final items = await _repository.listActive();

    var index = 0;
    for (final path in paths) {
      onProgress?.call(index, paths.length, p.basename(path));
      CryptoRepairResult result;
      try {
        result = await _repairOne(path: path, items: items, kek: kek);
      } catch (error, stackTrace) {
        AppLogger.e('MediaCryptoRepairService',
            'repair $path failed: $error\n$stackTrace');
        result = CryptoRepairResult(
          path: path,
          outcome: CryptoRepairOutcome.failed,
          detail: '$error',
        );
      }
      results.add(result);
      index++;
      onProgress?.call(index, paths.length, p.basename(path));
    }

    final report = CryptoRepairReport(results);
    AppLogger.i(
      'MediaCryptoRepairService',
      'repair done: total=${report.total}, decrypted=${report.decrypted}, '
          'recordsCleared=${report.recordCleared}, '
          'keyMismatch=${report.keyMismatch}, noKey=${report.noKey}, '
          'nothingToDo=${report.nothingToDo}, missing=${report.missing}, '
          'locked=${report.locked}, failed=${report.failed}',
    );
    return report;
  }

  Future<CryptoRepairResult> _repairOne({
    required String path,
    required List<MediaItem> items,
    required Uint8List? kek,
  }) async {
    final file = File(path);
    if (!file.existsSync()) {
      AppLogger.w(
          'MediaCryptoRepairService', 'repair $path: file no longer exists');
      return CryptoRepairResult(
          path: path, outcome: CryptoRepairOutcome.missing);
    }

    final bytes = MediaEncryptionService.lengthOrMinusOne(file);
    final header = MediaEncryptionService.headerHex(file);
    // Rows that own this exact file (hidden row: privatePath; a row an unhide
    // left behind: originalPath).
    final owners = items
        .where((item) => item.privatePath == path || item.originalPath == path)
        .toList(growable: false);
    final plaintext = _encryption.looksLikePlaintextMedia(file);

    AppLogger.i(
      'MediaCryptoRepairService',
      'repair $path: bytes=$bytes header=$header plaintext=$plaintext '
          'owners=${owners.length} '
          'ownerDeks=${owners.where(_hasDek).length} locked=${kek == null}',
    );

    if (kek != null) {
      final candidates = _candidates(
        path: path,
        bytes: bytes,
        owners: owners,
        items: items,
        plaintext: plaintext,
      );
      for (final candidate in candidates) {
        final dek = await _encryption.decryptDek(
          encryptedDekBase64: candidate.dekBase64,
          kek: kek,
        );
        if (dek == null) {
          AppLogger.w('MediaCryptoRepairService',
              'repair $path: candidate ${candidate.source} DEK unusable');
          continue;
        }
        if (await _decryptInPlace(file: file, dek: dek, path: path)) {
          await _clearDeks(owners, reason: 'decrypted ${p.basename(path)}');
          AppLogger.w(
            'MediaCryptoRepairService',
            'repair $path: decrypted with ${candidate.source} DEK',
          );
          return CryptoRepairResult(
            path: path,
            outcome: CryptoRepairOutcome.decrypted,
            source: candidate.source,
          );
        }
      }
    }

    if (plaintext) {
      final withDek = owners.where(_hasDek).toList(growable: false);
      if (withDek.isNotEmpty) {
        await _clearDeks(withDek, reason: 'file was plaintext all along');
        AppLogger.w(
          'MediaCryptoRepairService',
          'repair $path: cleared ${withDek.length} stale record(s); the file '
              'is plaintext',
        );
        return CryptoRepairResult(
            path: path, outcome: CryptoRepairOutcome.recordCleared);
      }
      return CryptoRepairResult(
          path: path, outcome: CryptoRepairOutcome.nothingToDo);
    }

    final hasOwnerDek = owners.any(_hasDek);
    if (kek == null && hasOwnerDek) {
      AppLogger.w('MediaCryptoRepairService',
          'repair $path: vault locked, cannot try the stored DEK');
      return CryptoRepairResult(
        path: path,
        outcome: CryptoRepairOutcome.locked,
        detail: 'kek not loaded',
      );
    }
    if (!hasOwnerDek) {
      AppLogger.w('MediaCryptoRepairService',
          'repair $path: ciphertext without any DEK (unrecoverable)');
      return CryptoRepairResult(path: path, outcome: CryptoRepairOutcome.noKey);
    }
    AppLogger.w(
      'MediaCryptoRepairService',
      'repair $path: no stored DEK decrypts this ciphertext '
          '(bytes=$bytes, header=$header)',
    );
    return CryptoRepairResult(
      path: path,
      outcome: CryptoRepairOutcome.keyMismatch,
      detail: 'bytes=$bytes, header=$header',
    );
  }

  /// DEK candidates for the file at [path], most likely first, de-duplicated.
  List<_DekCandidate> _candidates({
    required String path,
    required int bytes,
    required List<MediaItem> owners,
    required List<MediaItem> items,
    required bool plaintext,
  }) {
    final out = <_DekCandidate>[];
    void add(MediaItem item, String source) {
      final dek = item.encryptedDek;
      if (dek == null || dek.isEmpty) return;
      if (out.any((c) => c.dekBase64 == dek)) return;
      out.add(_DekCandidate(dekBase64: dek, source: source));
    }

    for (final owner in owners) {
      add(owner, 'owner');
    }
    // Plaintext needs no decrypt attempt, and a file that already has a usable
    // candidate list stops here.  Big files only get their own row's DEK: a
    // multi-candidate sweep would read the whole file once per candidate.
    if (plaintext ||
        out.isNotEmpty ||
        bytes < 0 ||
        bytes > maxCrossCheckBytes) {
      return out;
    }
    // Cross-row rescue: the same media hidden twice leaves a row whose DEK no
    // longer matches — the second hide generated a fresh DEK and skipped the
    // encryption (`Bad state: File already appears encrypted`).  The older row
    // may still hold the key that actually fits these bytes.
    final name = p.basename(path);
    var extra = 0;
    for (final item in items) {
      if (extra >= maxExtraCandidates) break;
      final dek = item.encryptedDek;
      if (dek == null || dek.isEmpty) continue;
      if (out.any((c) => c.dekBase64 == dek)) continue;
      if (item.originalName == name) {
        add(item, 'same-name');
        extra++;
      } else if (item.sizeBytes == bytes) {
        add(item, 'same-size');
        extra++;
      }
    }
    return out;
  }

  /// Decrypts [file] into a same-directory temp file and swaps it in atomically.
  ///
  /// Returns false when the DEK does not match (or the swap failed); the
  /// ciphertext is restored in that case.
  Future<bool> _decryptInPlace({
    required File file,
    required Uint8List dek,
    required String path,
  }) async {
    final directory = file.parent.path;
    final tmp = File(p.join(directory, _tmpName(path)));
    _bestEffortDelete(tmp);
    try {
      await _encryption.decryptFile(
        filePath: path,
        destPath: tmp.path,
        dek: dek,
      );
    } catch (error) {
      AppLogger.w('MediaCryptoRepairService',
          'repair candidate rejected for $path: $error');
      _bestEffortDelete(tmp);
      return false;
    }
    if (!tmp.existsSync() || tmp.lengthSync() == 0) {
      AppLogger.w('MediaCryptoRepairService',
          'repair candidate produced no plaintext for $path');
      _bestEffortDelete(tmp);
      return false;
    }

    // Ciphertext → `.enc_bak`, plaintext → original path, backup deleted last.
    // Never delete-then-rename (`PIT-034`); `.enc_bak` is the name the startup
    // self-heal restores from (`ISSUE-030`).
    final backup = File('$path.enc_bak');
    _bestEffortDelete(backup);
    try {
      await file.rename(backup.path);
    } catch (error) {
      AppLogger.e('MediaCryptoRepairService',
          'repair $path: backup before swap failed: $error');
      _bestEffortDelete(tmp);
      return false;
    }
    try {
      await tmp.rename(path);
    } catch (error) {
      AppLogger.e(
          'MediaCryptoRepairService', 'repair $path: swap failed: $error');
      await _restore(backup, path);
      _bestEffortDelete(tmp);
      return false;
    }
    _bestEffortDelete(backup);
    return true;
  }

  Future<void> _clearDeks(
    List<MediaItem> items, {
    required String reason,
  }) async {
    for (final item in items) {
      if (!_hasDek(item)) continue;
      try {
        await _repository.updateEncryptedDek(item.id, null);
        AppLogger.w('MediaCryptoRepairService',
            'cleared encryption record for ${item.id} ($reason)');
      } catch (error, stackTrace) {
        AppLogger.e('MediaCryptoRepairService',
            'could not clear DEK for ${item.id}: $error\n$stackTrace');
      }
    }
  }

  static bool _hasDek(MediaItem item) =>
      item.encryptedDek != null && item.encryptedDek!.isNotEmpty;

  /// Stable short name for the temp file — a temp name must never be built by
  /// appending to the media name (255-byte limit, `PIT-061` / `ISSUE-034`).
  static String _tmpName(String path) {
    var hash = 0x811c9dc5;
    for (final unit in path.codeUnits) {
      hash = (hash ^ unit) & 0xffffffff;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return '.enc_tmp-repair-${hash.toRadixString(16)}';
  }

  Future<void> _restore(File backup, String originalPath) async {
    try {
      if (backup.existsSync()) await backup.rename(originalPath);
    } catch (error) {
      AppLogger.e(
          'MediaCryptoRepairService',
          'could not restore $originalPath; ciphertext kept at '
              '${backup.path}: $error');
    }
  }

  void _bestEffortDelete(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }
}

class _DekCandidate {
  const _DekCandidate({required this.dekBase64, required this.source});

  final String dekBase64;
  final String source;
}
