import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../application/platform/vault_workflow.dart';
import '../../core/utils/app_logger.dart';
import '../../domain/models/media_item.dart';
import '../repositories/album_repository.dart';
import '../repositories/media_repository.dart';
import 'import/asset_gateway.dart';
import 'import/file_system_gateway.dart';
import 'import/hide_preparer.dart';
import 'import/import_models.dart';
import 'import/media_recorder.dart';
import 'import/thumbnail_generator.dart';
import 'import/vault_reveal_runner.dart';
import 'import/vault_transfer_runner.dart';
import 'media_encryption_service.dart';
import 'encryption_key_manager.dart';
import 'media_rename_service.dart';
import 'media_store_service.dart';
import 'media_thumbnail_service.dart';
import 'playback_display_service.dart';
import 'vault_storage_service.dart';

export 'import/import_models.dart';

/// Hide via native atomic rename (prefer) / batch IPC.
///
/// Cancel is cooperative: checked between prep steps and **between native
/// chunks**. A single in-flight native chunk cannot be aborted mid-call, so
/// chunk size stays small enough that Cancel still feels responsive.
/// Wake-lock holder id used while imported files are being encrypted.
const String _encryptScreenHolder = 'import.encryptFiles';

class ImportService implements VaultWorkflow {
  ImportService({
    required VaultStorageService storage,
    required MediaRepository mediaRepository,
    required AlbumRepository albumRepository,
    MediaRenameService? renamer,
    MediaStoreService? mediaStore,
    FileSystemGateway? fileSystem,
    AssetGateway? assetGateway,
    MediaThumbnailCache? thumbnailCache,
    HidePreparer? preparer,
    VaultTransferRunner? transferRunner,
    VaultRevealRunner? revealRunner,
    MediaRecorder? recorder,
    ThumbnailGenerator? thumbnailGenerator,
    MediaEncryptionService? encryptionService,
    EncryptionKeyManager? encryptionKeyManager,
    Uuid? uuid,
  })  : _renamer = renamer ?? MediaRenameService(),
        _mediaStore = mediaStore ?? MediaStoreService() {
    _fileSystem = fileSystem ?? const IoFileSystemGateway();
    _assetGateway = assetGateway ?? const PhotoManagerAssetGateway();
    _mediaRepository = mediaRepository;
    _encryptionService = encryptionService;
    _encryptionKeyManager = encryptionKeyManager;
    _preparer = preparer ??
        HidePreparer(
          storage: storage,
          mediaRepository: mediaRepository,
          albumRepository: albumRepository,
          mediaStore: _mediaStore,
          fileSystem: _fileSystem,
          assetGateway: _assetGateway,
          // Lets the preparer encrypt the file name on import (ADR-042).
          encryptionKeyManager: encryptionKeyManager,
          uuid: uuid,
        );
    _transferRunner = transferRunner ??
        VaultTransferRunner(
          renamer: _renamer,
          fileSystem: _fileSystem,
        );
    _revealRunner = revealRunner ??
        VaultRevealRunner(
          mediaRepository: mediaRepository,
          renamer: _renamer,
          mediaStore: _mediaStore,
          assetGateway: _assetGateway,
          fileSystem: _fileSystem,
          encryptionService: encryptionService,
          encryptionKeyManager: encryptionKeyManager,
        );
    _recorder = recorder ?? MediaRecorder(mediaRepository: mediaRepository);
    _thumbnailGenerator = thumbnailGenerator ??
        ThumbnailGenerator(
          storage: storage,
          mediaRepository: mediaRepository,
          renamer: _renamer,
          thumbnailCache: thumbnailCache ??
              MediaThumbnailService(assetGateway: _assetGateway),
          fileSystem: _fileSystem,
          // Encrypted media is decrypted before poster extraction (ISSUE-029).
          encryptionService: _encryptionService,
          encryptionKeyManager: _encryptionKeyManager,
        );
  }

  final MediaRenameService _renamer;
  final MediaStoreService _mediaStore;
  late final FileSystemGateway _fileSystem;
  late final AssetGateway _assetGateway;
  late final HidePreparer _preparer;
  late final VaultTransferRunner _transferRunner;
  late final VaultRevealRunner _revealRunner;
  late final MediaRecorder _recorder;
  late final ThumbnailGenerator _thumbnailGenerator;
  MediaEncryptionService? _encryptionService;
  EncryptionKeyManager? _encryptionKeyManager;
  late final MediaRepository _mediaRepository;

  /// Native items processed per MethodChannel call.
  ///
  /// Small enough that Cancel is noticed within ~one chunk of renames, and a
  /// single bad video cannot stall the whole batch for minutes.
  static const int nativeBatchChunk = VaultRevealRunner.nativeBatchChunk;

  @override
  Future<int> repairOutdatedVideoThumbnails() =>
      _thumbnailGenerator.repairOutdatedVideos();

  /// Generates and persists [item]'s poster on demand, returning its path.
  /// Used by the Invisible grid to fill videos hidden before generation ran.
  @override
  Future<String?> ensureThumbnail(MediaItem item) =>
      _thumbnailGenerator.generateOne(
        ThumbnailJob(
          id: item.id,
          privatePath: item.privatePath,
          isVideo: item.isVideo,
        ),
      );

  @override
  Future<ImportProgress> importAll(
    List<ImportSource> sources, {
    void Function(ImportProgress progress)? onProgress,
    String? targetUserAlbumId,
    String? defaultSourceFolderName,
    ImportSession? session,
  }) async {
    final activeSession = session ?? ImportSession();
    AppLogger.i('ImportService',
        'Starting import: ${sources.length} sources, targetAlbum=$targetUserAlbumId');
    _preparer.beginBatch();
    var imported = 0;
    var skipped = 0;
    var failed = 0;
    var completed = 0;
    String? lastError;
    ImportErrorCode? lastErrorCode;
    String? currentName;
    final total = sources.length;

    bool cancelledNow() => activeSession.isCancelled;

    var currentPhase = ImportPhase.resolving;

    void emit({bool cancelled = false}) {
      onProgress?.call(
        ImportProgress(
          done: completed,
          total: total,
          phase: cancelled || cancelledNow()
              ? ImportPhase.cancelled
              : currentPhase,
          currentName: currentName,
          imported: imported,
          skipped: skipped,
          failed: failed,
          cancelled: cancelled || cancelledNow(),
        ),
      );
    }

    ImportProgress cancelledProgress() => ImportProgress(
          done: completed,
          total: total,
          phase: ImportPhase.cancelled,
          cancelled: true,
          imported: imported,
          skipped: skipped,
          failed: failed,
          lastError: lastError,
          errorCode: lastErrorCode,
        );

    if (cancelledNow()) {
      emit(cancelled: true);
      return cancelledProgress();
    }

    if (total == 0) {
      const empty = ImportProgress(
        done: 0,
        total: 0,
        phase: ImportPhase.done,
      );
      onProgress?.call(empty);
      return empty;
    }

    // Pre-resolve mirror albums serially so concurrent hides never race-create
    // the same user album.
    if (targetUserAlbumId == null) {
      final folders = <String>{};
      for (final src in sources) {
        final folder = (src.sourceFolderName ??
                defaultSourceFolderName ??
                HidePreparer.folderNameFromPath(src.path))
            .trim();
        if (folder.isNotEmpty) folders.add(folder);
      }
      for (final folder in folders) {
        if (cancelledNow()) {
          emit(cancelled: true);
          return cancelledProgress();
        }
        await _preparer.preResolveAlbum(folder);
      }
    }

    emit();

    // ── Phase 1: prepare dest paths (cancelable per item) ───────────
    final prepared = <PreparedHide>[];
    for (var i = 0; i < sources.length; i++) {
      if (cancelledNow()) {
        // Remaining unprepared sources count as not-done (user cancelled).
        emit(cancelled: true);
        return cancelledProgress();
      }
      final src = sources[i];
      final name = src.name ?? p.basename(src.path);
      currentName = name;
      emit();

      try {
        final job = await _preparer.prepare(
          src,
          targetUserAlbumId: targetUserAlbumId,
          defaultSourceFolderName: defaultSourceFolderName,
        );
        if (job == null) {
          skipped++;
          completed++;
          emit();
          continue;
        }
        prepared.add(job);
      } catch (e, st) {
        AppLogger.w('ImportService', 'prepare hide failed: $e\n$st');
        failed++;
        lastError = e.toString();
        completed++;
        emit();
      }
    }

    if (cancelledNow()) {
      emit(cancelled: true);
      return cancelledProgress();
    }

    // ── Phase 2: native transfers + durable per-chunk recording ─────
    currentPhase = ImportPhase.hiding;
    emit();
    final thumbJobs = <ThumbnailJob>[];
    var encryptionSkipped = 0;
    await _transferRunner.run(
      prepared,
      session: activeSession,
      beforeChunk: _thumbnailGenerator.attachCachedPosters,
      collectOutcomes: false,
      onChunk: (outcomes) async {
        for (final outcome in outcomes) {
          final job = outcome.job;
          currentName = job.originalName;
          completed++;
          if (!outcome.ok) {
            failed++;
            lastError = outcome.rawError;
            lastErrorCode = outcome.errorCode;
            emit(cancelled: cancelledNow());
            continue;
          }

          imported++;
          emit(cancelled: cancelledNow());
        }

        final recorded = await _recorder.record(outcomes);
        final recordedIds = {
          for (final record in recorded) record.item.id,
        };
        final recordingFailures = outcomes.where(
          (outcome) => outcome.ok && !recordedIds.contains(outcome.job.id),
        );
        final recordingFailureCount = recordingFailures.length;
        if (recordingFailureCount > 0) {
          imported -= recordingFailureCount;
          failed += recordingFailureCount;
          lastError = 'database_record_failed';
          lastErrorCode = ImportErrorCode.transferFailed;
          emit();
        }

        // Keep the screen on while this chunk is encrypted: the device locking
        // mid-pass can kill the app between "file encrypted" and "DEK stored"
        // (PIT-044 / ISSUE-030).
        final display = PlaybackDisplayService.instance;
        await display.holdScreenOn(_encryptScreenHolder);
        try {
          encryptionSkipped += await _encryptRecordedFiles(recorded);
        } finally {
          await display.releaseScreenOn(_encryptScreenHolder);
        }

        for (final record in recorded) {
          final job = record.outcome.job;
          final deferredThumbnailJob = ThumbnailJob(
            id: job.id,
            privatePath: record.item.privatePath,
            isVideo: job.isVideo,
            assetId: job.source.assetId,
          );
          final sourceThumbnailBytes = job.thumbnailBytes;
          if (sourceThumbnailBytes?.isNotEmpty ?? false) {
            final capturedThumbnailJob = ThumbnailJob(
              id: job.id,
              privatePath: record.item.privatePath,
              isVideo: job.isVideo,
              assetId: job.source.assetId,
              sourceThumbnailBytes: sourceThumbnailBytes,
            );
            try {
              await _thumbnailGenerator
                  .generateOne(capturedThumbnailJob)
                  .timeout(
                    const Duration(seconds: 3),
                  );
              continue;
            } catch (error, stackTrace) {
              AppLogger.e(
                'ImportService',
                'captured thumb ${job.id}: $error\n$stackTrace',
              );
            }
          }
          // Never retain captured bytes beyond this native chunk. A failed
          // synchronous write retries from the remaining media sources.
          thumbJobs.add(deferredThumbnailJob);
        }
      },
    );

    if (cancelledNow()) {
      emit(cancelled: true);
      return cancelledProgress();
    }

    // Note: we intentionally do NOT clear photo_manager's file cache here.
    // PhotoManager.clearFileCache() wipes Glide's entire thumbnail disk cache,
    // forcing every Visible video poster to re-decode on the next browse. Hidden
    // assets are already excluded from Visible by id/path, so stale thumbnails
    // for them are never shown.

    // ── Phase 3: deferred thumbs (non-blocking for UI completion) ───
    // Fire-and-forget after progress reports Done so the sheet can dismiss.
    // Cancel mid-thumb is best-effort only.
    if (thumbJobs.isNotEmpty && !activeSession.isCancelled) {
      unawaited(
        _thumbnailGenerator.generateDeferred(thumbJobs, activeSession),
      );
    }

    // Items that were hidden but could not be encrypted (vault key not loaded).
    // They stay plaintext inside the vault until the user runs
    // "Encrypt existing files" (ISSUE-029).
    if (encryptionSkipped > 0) {
      lastError = 'encryption_skipped_vault_locked';
      lastErrorCode = ImportErrorCode.encryptionSkippedVaultLocked;
      AppLogger.w('ImportService',
          'encryption skipped for $encryptionSkipped item(s): KEK not loaded');
    }

    final done = ImportProgress(
      done: total,
      total: total,
      phase: ImportPhase.done,
      imported: imported,
      skipped: skipped,
      failed: failed,
      lastError: lastError,
      errorCode: lastErrorCode,
    );
    AppLogger.i('ImportService',
        'Import completed: imported=$imported, skipped=$skipped, failed=$failed');
    onProgress?.call(done);
    return done;
  }

  /// Encrypts freshly hidden files.  Returns how many items could **not** be
  /// encrypted because the vault key (KEK) was not loaded — those stay
  /// plaintext in the vault, so the caller must surface that to the user.
  Future<int> _encryptRecordedFiles(List<RecordedHide> recorded) async {
    if (recorded.isEmpty) return 0;
    final encryptionService = _encryptionService;
    final keyManager = _encryptionKeyManager;
    if (encryptionService == null || keyManager == null) return recorded.length;

    final kek = keyManager.getKey();
    if (kek == null) {
      AppLogger.w(
        'ImportService',
        'vault key (KEK) not loaded — ${recorded.length} imported item(s) '
            'stay unencrypted until "Encrypt existing files" is run',
      );
      return recorded.length;
    }

    for (final record in recorded) {
      try {
        // PIT-044: generate DEK → encrypt with KEK → save to DB → encrypt file.
        // Saving the DEK before file encryption eliminates the crash window
        // where the file is encrypted on disk but the DEK is permanently lost.
        // If native encryption fails, the saved DEK is rolled back.
        final dek = encryptionService.generateDek();
        final nonce = encryptionService.generateNonce();
        final encryptedDekBase64 =
            await encryptionService.encryptDek(dek: dek, kek: kek);

        await _mediaRepository.updateEncryptedDek(
          record.item.id,
          encryptedDekBase64,
        );

        await encryptionService.encryptFileWithDek(
          filePath: record.item.privatePath,
          dek: dek,
          nonce: Uint8List.fromList(nonce),
        );
      } catch (e, stack) {
        AppLogger.e(
          'ImportService',
          '_encryptRecordedFiles failed for ${record.item.id}: $e\n$stack',
        );
        // Roll the DEK back **only** while the file is still plaintext.
        // `encryptFileWithDek` can finish the native in-place swap and still
        // fail on the way back (channel restart / process death); clearing the
        // saved DEK then would orphan an already-encrypted file forever.
        final stillPlain =
            !encryptionService.looksEncrypted(File(record.item.privatePath));
        if (stillPlain) {
          await _mediaRepository.updateEncryptedDek(record.item.id, null);
        } else {
          // NOTE: `looksEncrypted` is a **plaintext whitelist**, so a media
          // format it does not know (BMP / TIFF / …) lands here with `stillPlain`
          // false while the file was never touched.  Logging the header is what
          // makes that distinguishable later (`ISSUE-043`).
          final artifact = File(record.item.privatePath);
          AppLogger.w(
            'ImportService',
            'Kept saved DEK for ${record.item.id}: the file looks encrypted '
                'even though the encrypt call failed '
                '(bytes=${MediaEncryptionService.lengthOrMinusOne(artifact)}, '
                'header=${MediaEncryptionService.headerHex(artifact)})',
          );
        }
      }
    }
    return 0;
  }

  /// Unhide one item through the injected reveal pipeline.
  @override
  Future<bool> reveal(
    MediaItem item, {
    bool clearGalleryCache = true,
    ImportSession? session,
  }) {
    return _revealRunner.reveal(
      item,
      clearGalleryCache: clearGalleryCache,
      session: session ?? ImportSession(),
    );
  }

  /// Batch unhide with chunk-level durability and cooperative cancellation.
  @override
  Future<ImportProgress> revealAll(
    List<MediaItem> items, {
    void Function(ImportProgress progress)? onProgress,
    ImportSession? session,
  }) {
    return _revealRunner.run(
      items,
      session: session ?? ImportSession(),
      onProgress: onProgress,
    );
  }
}
