import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/backup/vault_backup_controller.dart';
import '../../application/lock/biometric_ui.dart';
import '../../application/lock/lock_controller.dart';
import '../../application/providers.dart';
import '../../application/settings/settings_controller.dart';
import '../../core/constants.dart';
import '../../core/l10n.dart';
import '../../data/services/maintenance_service.dart';
import '../../data/services/playback_display_service.dart';
import '../../data/services/media_encryption_service.dart';
import '../../data/services/encryption_key_manager.dart';
import '../../data/services/vault_backup_service.dart';
import '../../data/repositories/media_repository.dart';
import '../../domain/enums.dart';
import '../../domain/models/media_item.dart';
import '../lock/pattern_lock.dart';
import 'vault_backup_progress_dialog.dart';
import '../../core/utils/app_logger.dart';

/// Full settings — security, display, playback, storage export/import.
/// Guards the "Encrypt existing files" flow (ISSUE-030): the progress dialog is
/// rebuilt after every item, and registering `run()` from the builder without a
/// guard started a **new** concurrent loop per rebuild — dozens of loops then
/// encrypted the same file at once, sharing one `.enc_tmp`, which produced
/// 0-byte media and files that vanished entirely.
bool _batchEncryptInFlight = false;

/// Wake-lock holder id used while "Encrypt existing files" runs.
const String _encryptScreenHolder = 'settings.batchEncrypt';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsControllerProvider);
    final lock = ref.watch(lockControllerProvider);
    final privacyShield = ref.watch(privacyShieldProvider);
    final externalPlaybackSupported =
        ref.watch(externalPlayerGatewayProvider).supported;
    final appBuildInfo = ref.watch(appBuildInfoProvider);
    final backupBusy = ref.watch(
      vaultBackupControllerProvider.select((state) => state.busy),
    );
    final version = appBuildInfo.version;
    final notifier = ref.read(settingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settings), centerTitle: true),
      body: ListView(
        children: [
          _SectionHeader(context.l10n.sectionSecurity),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: Text(context.l10n.lockNow),
            onTap: () {
              ref.read(lockControllerProvider.notifier).lock();
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
          ListTile(
            leading: const Icon(Icons.gesture),
            title: Text(context.l10n.changePattern),
            subtitle: Text(context.l10n.rootUnlockCredential),
            onTap: () => _changePattern(context, ref),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.fingerprint),
            title: Text(context.l10n.biometricUnlock),
            subtitle: Text(
              lock.biometricAvailable
                  ? context.l10n.biometricAvailable
                  : context.l10n.biometricUnavailable,
            ),
            value: lock.biometricEnabled && lock.biometricAvailable,
            onChanged: !lock.biometricAvailable
                ? null
                : (v) async {
                    try {
                      final ok = await ref.setBiometricEnabledUi(context, v);
                      if (!ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              v
                                  ? context.l10n.biometricCancelled
                                  : context.l10n.biometricUpdateFailed,
                            ),
                          ),
                        );
                      }
                    } catch (e, stackTrace) {
                      AppLogger.e('SettingsScreen',
                          'biometric setting update: $e\n$stackTrace');
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(context.l10n.biometricUpdateFailed),
                          ),
                        );
                      }
                    }
                  },
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: Text(context.l10n.autoLock),
            subtitle: Text(_autoLockLabel(context, s.autoLockSeconds)),
            onTap: () async {
              final v = await _pick<int>(
                context,
                title: context.l10n.autoLock,
                options: {
                  context.l10n.autoLockImmediately: 0,
                  context.l10n.autoLockSeconds(30): 30,
                  context.l10n.autoLockMinutes(1): 60,
                  context.l10n.autoLockMinutesPlural(5): 300,
                },
                current: s.autoLockSeconds,
              );
              if (v != null) await notifier.setAutoLockSeconds(v);
            },
          ),
          SwitchListTile(
            secondary: Icon(
              privacyShield.capabilities.screenshotsBlocked
                  ? Icons.screenshot_monitor_outlined
                  : Icons.privacy_tip_outlined,
            ),
            title: Text(
              privacyShield.capabilities.screenshotsBlocked
                  ? context.l10n.blockScreenshots
                  : context.l10n.protectAppPreview,
            ),
            subtitle: privacyShield.capabilities.screenshotsBlocked
                ? null
                : Text(context.l10n.protectAppPreviewSubtitle),
            value: s.flagSecure,
            onChanged: (v) async {
              try {
                await ref.read(privacyShieldProvider).apply(v);
                await notifier.setFlagSecure(v);
              } catch (e, stackTrace) {
                AppLogger.e('SettingsScreen',
                    'privacy shield setting: $e\n$stackTrace');
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        privacyShield.capabilities.screenshotsBlocked
                            ? context.l10n.screenshotSettingFailed
                            : context.l10n.privacySettingFailed,
                      ),
                    ),
                  );
                }
              }
            },
          ),
          _SectionHeader(context.l10n.sectionDisplay),
          ListTile(
            leading: const Icon(Icons.grid_view),
            title: Text(context.l10n.mediaGridColumns),
            subtitle: Text('${s.gridColumns}'),
            onTap: () async {
              final v = await _pick<int>(
                context,
                title: context.l10n.mediaGridColumns,
                options: const {'2': 2, '3': 3, '4': 4, '5': 5},
                current: s.gridColumns,
              );
              if (v != null) await notifier.setGridColumns(v);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_album_outlined),
            title: Text(context.l10n.albumColumns),
            subtitle: Text('${s.albumColumns}'),
            onTap: () async {
              final v = await _pick<int>(
                context,
                title: context.l10n.albumColumns,
                options: const {'3': 3, '4': 4},
                current: s.albumColumns,
              );
              if (v != null) await notifier.setAlbumColumns(v);
            },
          ),
          _SectionHeader(context.l10n.sectionPlayback),
          if (externalPlaybackSupported)
            SwitchListTile(
              secondary: const Icon(Icons.open_in_new),
              title: Text(context.l10n.preferExternalPlayer),
              subtitle: Text(context.l10n.preferExternalPlayer),
              value: s.playerExternal,
              onChanged: notifier.setPlayerExternal,
            )
          else
            ListTile(
              leading: const Icon(Icons.play_circle_outline),
              title: Text(context.l10n.inAppPlayback),
              subtitle: Text(context.l10n.externalPlaybackUnsupported),
            ),
          ListTile(
            leading: const Icon(Icons.videocam_outlined),
            title: Text(context.l10n.playerEngine),
            subtitle: Text(_playerEngineLabel(context, s.playerEngine)),
            onTap: () async {
              final v = await _pick<PlayerEngine>(
                context,
                title: context.l10n.playerEngine,
                options: {
                  context.l10n.playerEngineExoPlayer: PlayerEngine.exoPlayer,
                  context.l10n.playerEngineVlc: PlayerEngine.vlc,
                },
                current: s.playerEngine,
              );
              if (v != null) await notifier.setPlayerEngine(v);
            },
          ),
          ListTile(
            leading: const Icon(Icons.slideshow_outlined),
            title: Text(context.l10n.slideshowDelay),
            subtitle: Text('${s.slideshowSeconds}s'),
            onTap: () async {
              final v = await _pick<int>(
                context,
                title: context.l10n.slideshowDelay,
                options: {
                  context.l10n.secondCount(1): 1,
                  context.l10n.secondsCount(3): 3,
                  context.l10n.secondsCount(5): 5,
                  context.l10n.secondsCount(10): 10,
                },
                current: s.slideshowSeconds,
              );
              if (v != null) await notifier.setSlideshowSeconds(v);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.shuffle),
            title: Text(context.l10n.shuffleByDefault),
            value: s.shuffleDefault,
            onChanged: notifier.setShuffleDefault,
          ),
          ListTile(
            key: const ValueKey('settings-shuffle-play-count'),
            leading: const Icon(Icons.history_outlined),
            title: Text(context.l10n.shufflePlayCount),
            subtitle: Text(
              _shufflePlayCountLabel(context, s.shufflePlayCountMode),
            ),
            onTap: () async {
              final v = await _pick<ShufflePlayCountMode>(
                context,
                title: context.l10n.shufflePlayCount,
                options: {
                  context.l10n.shufflePlayCountOff: ShufflePlayCountMode.off,
                  context.l10n.shufflePlayCountSoften:
                      ShufflePlayCountMode.soften,
                  context.l10n.shufflePlayCountSkip: ShufflePlayCountMode.skip,
                },
                current: s.shufflePlayCountMode,
              );
              if (v != null) await notifier.setShufflePlayCountMode(v);
            },
          ),
          if (s.shufflePlayCountMode == ShufflePlayCountMode.skip)
            ListTile(
              key: const ValueKey('settings-shuffle-skip-threshold'),
              leading: const Icon(Icons.filter_alt_off_outlined),
              title: Text(context.l10n.shuffleSkipThreshold),
              subtitle: Text(
                context.l10n.shuffleSkipAtLeast(s.shuffleSkipThreshold),
              ),
              onTap: () async {
                final v = await _pick<int>(
                  context,
                  title: context.l10n.shuffleSkipThreshold,
                  options: {
                    for (final plays in shuffleSkipThresholdOptions)
                      context.l10n.shuffleSkipAtLeast(plays): plays,
                  },
                  current: s.shuffleSkipThreshold,
                );
                if (v != null) await notifier.setShuffleSkipThreshold(v);
              },
            ),
          ListTile(
            key: const ValueKey('settings-clear-play-history'),
            leading: const Icon(Icons.restart_alt),
            title: Text(context.l10n.clearPlayHistory),
            subtitle: Text(context.l10n.clearPlayHistorySubtitle),
            onTap: () => _clearPlayHistory(context, ref),
          ),
          _SectionHeader(context.l10n.sectionStorage),
          Consumer(
            builder: (context, ref, _) {
              final sizeAsync = ref.watch(vaultSizeBytesProvider);
              final subtitle = sizeAsync.when(
                data: (b) => _formatBytes(b),
                loading: () => context.l10n.calculating,
                error: (_, __) => '—',
              );
              return ListTile(
                leading: const Icon(Icons.sd_storage_outlined),
                title: Text(context.l10n.vaultSize),
                subtitle: Text(subtitle),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.enhanced_encryption_outlined),
            title: Text(context.l10n.encryptExistingFiles),
            subtitle: Text(context.l10n.encryptExistingFilesSubtitle),
            onTap: () => _batchEncrypt(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.find_in_page_outlined),
            title: Text(context.l10n.scanOrphans),
            subtitle: Text(context.l10n.scanOrphansSubtitle),
            onTap: () => _scanOrphans(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.event_available_outlined),
            title: Text(context.l10n.repairCaptureDates),
            subtitle: Text(context.l10n.repairCaptureDatesSubtitle),
            onTap: () => _repairCaptureDates(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.restore_page_outlined),
            title: Text(context.l10n.recoverVault),
            subtitle: Text(context.l10n.recoverVaultSubtitle),
            onTap: () => _recoverVault(context, ref, alsoUnhide: false),
          ),
          ListTile(
            leading: const Icon(Icons.unarchive_outlined),
            title: Text(context.l10n.recoverAndUnhide),
            subtitle: Text(context.l10n.recoverAndUnhideSubtitle),
            onTap: () => _recoverVault(context, ref, alsoUnhide: true),
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: Text(context.l10n.recycleRetention),
            subtitle: Text(context.l10n.retentionDays(s.recycleRetentionDays)),
            onTap: () async {
              final v = await _pick<int>(
                context,
                title: context.l10n.retention,
                options: {
                  context.l10n.retention1Day: 1,
                  context.l10n.retentionDays(7): 7,
                  context.l10n.retentionDays(30): 30,
                },
                current: s.recycleRetentionDays,
              );
              if (v != null) await notifier.setRecycleRetentionDays(v);
            },
          ),
          ListTile(
            key: const ValueKey('settings-export-vault'),
            leading: const Icon(Icons.upload_file_outlined),
            title: Text(context.l10n.exportVault),
            subtitle: Text(context.l10n.exportVaultSubtitle),
            onTap: backupBusy
                ? null
                : () => _startBackup(
                      context,
                      ref,
                      VaultBackupOperation.export,
                    ),
          ),
          ListTile(
            key: const ValueKey('settings-restore-vault'),
            leading: const Icon(Icons.download_outlined),
            title: Text(context.l10n.importVault),
            subtitle: Text(context.l10n.importVaultSubtitle),
            onTap: backupBusy
                ? null
                : () => _startBackup(
                      context,
                      ref,
                      VaultBackupOperation.restore,
                    ),
          ),
          _SectionHeader(context.l10n.sectionDiagnostics),
          SwitchListTile(
            key: const ValueKey('settings-diagnostic-logs'),
            secondary: const Icon(Icons.receipt_long_outlined),
            title: Text(context.l10n.diagnosticLog),
            subtitle: Text(
              s.logEnabled
                  ? context.l10n.diagnosticLogEnabled
                  : context.l10n.diagnosticLogDisabled,
            ),
            value: s.logEnabled,
            onChanged: notifier.setLogEnabled,
          ),
          _SectionHeader(context.l10n.sectionAbout),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(context.l10n.language),
            subtitle: Text(_localeLabel(context, s.localeCode)),
            onTap: () async {
              final v = await _pick<String>(
                context,
                title: context.l10n.language,
                options: {
                  context.l10n.languageSystem: '',
                  context.l10n.languageEnglish: 'en',
                  context.l10n.languageZhCn: 'zh_CN',
                  context.l10n.languageZhHk: 'zh_HK',
                },
                current: s.localeCode,
              );
              if (v != null) await notifier.setLocaleCode(v);
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text(AppInfo.name),
            subtitle: Text(
              'v$version · ${AppInfo.licenseShort}',
            ),
            onTap: () => _showAbout(context, ref, version),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(context.l10n.author),
            subtitle: const Text(AppInfo.author),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _openAuthorUrl(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: Text(context.l10n.license),
            subtitle: const Text(AppInfo.licenseShort),
            onTap: () => _showLicense(context),
          ),
        ],
      ),
    );
  }

  Future<void> _openAuthorUrl(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(externalUrlLauncherProvider).open(
            Uri.parse(AppInfo.authorUrl),
          );
    } catch (e) {
      AppLogger.w('SettingsScreen', 'open author url: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.couldNotOpenBrowser)),
        );
      }
    }
  }

  /// Wipes the per-item play counter that random playback weights its order
  /// by, so every media item starts from an equal chance again.
  Future<void> _clearPlayHistory(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.clearPlayHistory),
        content: Text(context.l10n.clearPlayHistorySubtitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.clear),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final cleared = await ref.read(mediaRepositoryProvider).resetPlayCounts();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.playHistoryCleared(cleared))),
      );
    } catch (e, stackTrace) {
      AppLogger.e('SettingsScreen', 'clear play history: $e\n$stackTrace');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.errorWithDetails('$e'))),
      );
    }
  }

  Future<void> _batchEncrypt(BuildContext context, WidgetRef ref) async {
    // One flow at a time: two concurrent loops encrypt the same file twice,
    // which produced 0-byte media and vanished files (ISSUE-030).
    if (_batchEncryptInFlight) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.encryptingTitle)),
        );
      }
      return;
    }
    _batchEncryptInFlight = true;

    final encryptionService = ref.read(mediaEncryptionServiceProvider);
    final keyManager = ref.read(encryptionKeyManagerProvider);
    final repo = ref.read(mediaRepositoryProvider);

    try {
      final kek = keyManager.getKey();
      if (kek == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.vaultLockedPleaseUnlock)),
          );
        }
        return;
      }

      final unencrypted = await repo.listUnencrypted();
      if (unencrypted.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.allFilesAlreadyEncrypted)),
          );
        }
        return;
      }

      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.l10n.encryptExistingFiles),
          content:
              Text(context.l10n.encryptConfirmationBody(unencrypted.length)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.l10n.encryptAction),
            ),
          ],
        ),
      );
      if (ok != true || !context.mounted) return;

      await _showEncryptProgress(
          context, ref, encryptionService, keyManager, repo, unencrypted);
    } finally {
      _batchEncryptInFlight = false;
      // Safety net: `run()` releases it too, but the dialog can be dismissed
      // from outside (system back) while the loop sits between two items.
      await PlaybackDisplayService.instance
          .releaseScreenOn(_encryptScreenHolder);
    }
  }

  Future<void> _showEncryptProgress(
    BuildContext context,
    WidgetRef ref,
    MediaEncryptionService encryptionService,
    EncryptionKeyManager keyManager,
    MediaRepository repo,
    List<MediaItem> items,
  ) {
    int completed = 0;
    int failed = 0;
    int missing = 0;
    int undecryptable = 0;
    bool cancelled = false;
    // `run()` must start exactly once: the builder re-runs on every
    // setDialogState(), so registering the callback without a guard spawned a
    // new concurrent loop per rebuild (ISSUE-030).
    var started = false;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            Future<void> run() async {
              // Keep the screen on for the whole pass: the device locking would
              // background (and may kill) the app mid-encryption.
              await PlaybackDisplayService.instance
                  .holdScreenOn(_encryptScreenHolder);
              for (final item in items) {
                if (cancelled) break;
                final kekNow = keyManager.getKey();
                if (kekNow == null) {
                  cancelled = true;
                  break;
                }
                try {
                  final file = File(item.privatePath);
                  if (!file.existsSync()) {
                    // Row without a file: maintenance drops it on next launch.
                    missing++;
                  } else if (encryptionService.looksEncrypted(file)) {
                    // Already ciphertext while the DB has no DEK for it: it can
                    // neither be encrypted again (that would corrupt it) nor
                    // decrypted.  Counted separately so the user learns which
                    // files are broken (ISSUE-030).
                    undecryptable++;
                    AppLogger.w(
                      'SettingsScreen',
                      'batch encrypt skipped ${item.id}: already ciphertext '
                      'without a stored DEK',
                    );
                  } else {
                    // PIT-044 order: generate the DEK → persist it → then
                    // encrypt the file.  Encrypting first leaves a crash window
                    // in which the media is ciphertext while its DEK never
                    // reached the DB (unrecoverable).
                    final dek = encryptionService.generateDek();
                    final nonce = encryptionService.generateNonce();
                    final encryptedDek = await encryptionService.encryptDek(
                      dek: dek,
                      kek: kekNow,
                    );
                    await repo.updateEncryptedDek(item.id, encryptedDek);
                    try {
                      await encryptionService.encryptFileWithDek(
                        filePath: item.privatePath,
                        dek: dek,
                        nonce: Uint8List.fromList(nonce),
                      );
                    } catch (e) {
                      // Keep the DEK when the file did get encrypted — the
                      // native swap can succeed even if its reply is lost.
                      if (!encryptionService.looksEncrypted(file)) {
                        await repo.updateEncryptedDek(item.id, null);
                      }
                      rethrow;
                    }
                  }
                } catch (e, stackTrace) {
                  AppLogger.e('SettingsScreen',
                      'batch encrypt ${item.id}: $e\n$stackTrace');
                  failed++;
                }
                completed++;
                // The dialog may already be gone (system back): calling
                // setState on a disposed State throws.
                if (ctx.mounted) setDialogState(() {});
              }
              if (ctx.mounted) Navigator.pop(ctx);
              await PlaybackDisplayService.instance
                  .releaseScreenOn(_encryptScreenHolder);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text([
                      failed > 0
                          ? context.l10n.encryptResultPartial(completed, failed)
                          : context.l10n.encryptResultSuccess(completed),
                      if (missing > 0)
                        context.l10n.encryptMissingFiles(missing),
                      if (undecryptable > 0)
                        context.l10n.encryptSkippedNoKey(undecryptable),
                    ].join('\n')),
                  ),
                );
              }
            }

            // Start exactly once — the builder re-runs on every rebuild and
            // used to spawn one extra concurrent loop each time (ISSUE-030).
            if (!started) {
              started = true;
              WidgetsBinding.instance.addPostFrameCallback((_) => run());
            }

            final progress = items.isEmpty
                ? 0.0
                : completed / items.length;
            final kekNow = keyManager.getKey();
            final lockedOut = kekNow == null && completed < items.length;
            String status;
            if (lockedOut) {
              status = context.l10n.vaultLockedOperationStopped;
            } else if (completed >= items.length) {
              status = context.l10n.done;
            } else {
              status = context.l10n
                  .encryptingProgress(completed + 1, items.length);
            }

            return AlertDialog(
              title: Text(context.l10n.encryptingTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 16),
                  Text(status),
                  if (failed > 0)
                    Text(
                      context.l10n.encryptFailedCount(failed),
                      style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error),
                    ),
                  if (undecryptable > 0)
                    Text(
                      context.l10n.encryptSkippedNoKey(undecryptable),
                      style: TextStyle(
                          color: Theme.of(ctx).colorScheme.error),
                    ),
                ],
              ),
              actions: lockedOut
                  ? [
                      FilledButton(
                        onPressed: () {
                          cancelled = true;
                          Navigator.pop(ctx);
                        },
                        child: Text(context.l10n.close),
                      ),
                    ]
                  : [
                      TextButton(
                        onPressed: () {
                          cancelled = true;
                          Navigator.pop(ctx);
                        },
                        child: Text(context.l10n.cancel),
                      ),
                    ],
            );
          },
        );
      },
    );
  }

  void _showAbout(
    BuildContext context,
    WidgetRef ref,
    String version,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.asset(
                'assets/branding/app_icon_192.png',
                width: 40,
                height: 40,
                errorBuilder: (_, __, ___) => const Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text(AppInfo.name)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                AppInfo.tagline,
                style: Theme.of(ctx).textTheme.titleSmall,
              ),
              const SizedBox(height: 12),
              const Text(AppInfo.about),
              const SizedBox(height: 16),
              Text(
                context.l10n.versionLabel(version),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                context.l10n.authorLabel(AppInfo.author),
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              InkWell(
                onTap: () {
                  Navigator.pop(ctx);
                  _openAuthorUrl(context, ref);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    AppInfo.authorUrl,
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                AppInfo.licenseShort,
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.close),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showLicense(context);
            },
            child: Text(context.l10n.license),
          ),
        ],
      ),
    );
  }

  void _showLicense(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.license),
        content: const SingleChildScrollView(
          child: Text(AppInfo.licenseBody),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.close),
          ),
        ],
      ),
    );
  }

  Future<void> _changePattern(BuildContext context, WidgetRef ref) async {
    final lock = ref.read(lockControllerProvider);
    final String? current;
    if (lock.usesPattern) {
      current = await _promptPattern(
        context,
        title: context.l10n.currentPattern,
        subtitle: context.l10n.drawCurrentPattern,
      );
    } else {
      current = await _promptPin(
        context,
        title: context.l10n.currentPin,
        subtitle: context.l10n.enterPinThenPattern,
      );
    }
    if (current == null || !context.mounted) return;
    final next = await _promptPattern(
      context,
      title: context.l10n.newPattern,
      subtitle: context.l10n.connectAtLeast4Dots,
    );
    if (next == null || !context.mounted) return;
    final confirm = await _promptPattern(
      context,
      title: context.l10n.confirmNewPattern,
      subtitle: context.l10n.drawSamePatternAgain,
    );
    if (confirm == null || !context.mounted) return;
    if (next != confirm) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.newPatternsDidNotMatch)),
      );
      return;
    }
    try {
      if (lock.usesPattern) {
        await ref.read(lockControllerProvider.notifier).changePattern(
              currentPattern: current,
              newPattern: next,
            );
      } else {
        await ref.read(lockControllerProvider.notifier).migratePinToPattern(
              currentPin: current,
              newPattern: next,
            );
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.patternUpdated)),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.e('SettingsScreen', 'change pattern: $e\n$stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              lock.usesPattern
                  ? context.l10n.wrongPattern
                  : context.l10n.wrongPin,
            ),
          ),
        );
      }
    }
  }

  Future<String?> _promptPattern(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(subtitle, style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 16),
              PatternLock(
                size: 240,
                onCompleted: (p) => Navigator.pop(ctx, p),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.l10n.cancel),
            ),
          ],
        );
      },
    );
  }

  Future<String?> _promptPin(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(subtitle, style: Theme.of(ctx).textTheme.bodySmall),
            TextField(
              controller: ctrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'PIN'),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.continueAction),
          ),
        ],
      ),
    );
    if (ok != true) return null;
    return ctrl.text;
  }

  Future<void> _scanOrphans(BuildContext context, WidgetRef ref) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.scanningOrphans)),
    );
    try {
      final result = await ref
          .read(maintenanceServiceProvider)
          .recoverVaultFiles(alsoUnhide: false);
      ref.invalidate(vaultSizeBytesProvider);
      ref.invalidate(albumsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_recoverySummary(context, result))),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.e('SettingsScreen', 'orphan scan: $e\n$stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.scanFailedShort)),
        );
      }
    }
  }

  Future<void> _repairCaptureDates(BuildContext context, WidgetRef ref) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.repairingCaptureDates)),
    );
    try {
      final result =
          await ref.read(maintenanceServiceProvider).repairCaptureDates();
      ref.invalidate(albumsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_captureDateSummary(context, result))),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.e('SettingsScreen', 'capture date repair: $e\n$stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.scanFailedShort)),
        );
      }
    }
  }

  /// Reinstall recovery: re-index files still under `.privateheart_vault`.
  ///
  /// [alsoUnhide] restores them to the public Gallery after indexing.
  Future<void> _recoverVault(
    BuildContext context,
    WidgetRef ref, {
    required bool alsoUnhide,
  }) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          alsoUnhide
              ? context.l10n.recoverAndUnhide
              : context.l10n.recoverVault,
        ),
        content: Text(
          alsoUnhide
              ? context.l10n.recoverAndUnhideBody
              : context.l10n.recoverVaultBody,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.continueAction),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.recoveringVault)),
    );
    try {
      final result = await ref
          .read(maintenanceServiceProvider)
          .recoverVaultFiles(alsoUnhide: alsoUnhide);
      ref.invalidate(vaultSizeBytesProvider);
      ref.invalidate(albumsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_recoverySummary(context, result))),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.e('SettingsScreen', 'vault recovery: $e\n$stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.scanFailedShort)),
        );
      }
    }
  }

  static String _recoverySummary(
    BuildContext context,
    VaultRecoveryResult result,
  ) {
    return switch (result.status) {
      VaultRecoveryStatus.noFiles => context.l10n.noOrphanVaultFiles,
      VaultRecoveryStatus.reindexed => context.l10n.recoveryResult(
          result.reindexed,
          result.skipped,
          result.failed,
        ),
      VaultRecoveryStatus.restoredToGallery =>
        context.l10n.galleryRecoveryResult(
          result.reindexed,
          result.skipped,
          result.failed,
        ),
    };
  }

  static String _captureDateSummary(
    BuildContext context,
    CaptureDateRepairResult result,
  ) {
    if (!result.hadMedia) return context.l10n.noVaultMediaToRepair;
    return context.l10n.captureDateRepairResult(
      result.fixed,
      result.skipped,
      result.failed,
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }

  Future<void> _startBackup(
    BuildContext context,
    WidgetRef ref,
    VaultBackupOperation operation,
  ) async {
    final controller = ref.read(vaultBackupControllerProvider.notifier);
    final restoring = operation == VaultBackupOperation.restore;
    final pickerTitle = restoring
        ? context.l10n.backupRestorePickerTitle
        : context.l10n.backupExportPickerTitle;
    final bool started;
    try {
      final selectDirectory = ref.read(vaultBackupDirectoryPickerProvider);
      started = await controller.selectDirectoryAndStart(
        operation: operation,
        selectDirectory: () => selectDirectory(pickerTitle),
      );
    } catch (error, stackTrace) {
      AppLogger.e(
        'SettingsScreen',
        'vault backup directory selection failed: $error\n$stackTrace',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.backupFolderSelectionFailed)),
      );
      return;
    }
    if (!started || !context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Consumer(
        builder: (context, dialogRef, _) {
          final state = dialogRef.watch(vaultBackupControllerProvider);
          final notifier =
              dialogRef.read(vaultBackupControllerProvider.notifier);
          return VaultBackupProgressDialog(
            state: state,
            text: _backupDialogText(context, restoring: restoring),
            onCancel: notifier.cancel,
            onRetry: notifier.retry,
            onClose: () => Navigator.pop(dialogContext),
          );
        },
      ),
    );
    if (!ref.read(vaultBackupControllerProvider).busy) controller.dismiss();
  }

  VaultBackupDialogText _backupDialogText(
    BuildContext context, {
    required bool restoring,
  }) {
    final l10n = context.l10n;
    return VaultBackupDialogText(
      operationTitle: restoring
          ? l10n.backupRestoreProgressTitle
          : l10n.backupExportProgressTitle,
      completedTitle: restoring
          ? l10n.backupRestoreCompleteTitle
          : l10n.backupExportCompleteTitle,
      cancelledTitle: l10n.backupCancelledTitle,
      cancelledBody: l10n.backupCancelledBody,
      errorTitle: restoring
          ? l10n.backupRestoreErrorTitle
          : l10n.backupExportErrorTitle,
      cancel: l10n.cancel,
      cancelling: l10n.backupCancelling,
      close: l10n.close,
      retry: l10n.retry,
      checksumVerified: l10n.backupChecksumVerified,
      checkedWithoutChecksum: l10n.backupCheckedWithoutChecksum,
      progressLabel: l10n.backupProgressLabel,
      stageLabel: (stage) => switch (stage) {
        VaultBackupStage.preparing => l10n.backupStagePreparing,
        VaultBackupStage.checkingSource => l10n.backupStageCheckingSource,
        VaultBackupStage.copying => l10n.backupStageCopying,
        VaultBackupStage.writingManifest => l10n.backupStageWritingManifest,
        VaultBackupStage.checkingBackup => l10n.backupStageCheckingBackup,
        VaultBackupStage.restoring => l10n.backupStageRestoring,
        VaultBackupStage.completed => l10n.backupStageComplete,
      },
      itemCount: l10n.backupItemCount,
      totalSize: _formatBytes,
      progressCount: l10n.backupProgressCount,
      errorMessage: (error) => _backupErrorMessage(
        context,
        error,
        restoring: restoring,
      ),
    );
  }

  String _backupErrorMessage(
    BuildContext context,
    Object error, {
    required bool restoring,
  }) {
    final l10n = context.l10n;
    if (error is! VaultBackupException) {
      return restoring
          ? l10n.backupRestoreFailedGeneric
          : l10n.backupExportFailedGeneric;
    }
    final item = error.fileName ?? l10n.backupUnknownItem;
    return switch (error.code) {
      VaultBackupErrorCode.manifestMissing => l10n.backupManifestMissing,
      VaultBackupErrorCode.malformedManifest => error.fileName == null
          ? l10n.backupManifestMalformed
          : l10n.backupManifestMalformedItem(item),
      VaultBackupErrorCode.unsupportedManifestVersion =>
        l10n.backupVersionUnsupported,
      VaultBackupErrorCode.sourceMissing => l10n.backupSourceMissing(item),
      VaultBackupErrorCode.sourceUnreadable =>
        l10n.backupSourceUnreadable(item),
      VaultBackupErrorCode.sourceEmpty => l10n.backupSourceEmpty(item),
      VaultBackupErrorCode.sourceChanged => l10n.backupSourceChanged(item),
      VaultBackupErrorCode.payloadMissing => l10n.backupPayloadMissing(item),
      VaultBackupErrorCode.payloadUnreadable =>
        l10n.backupPayloadUnreadable(item),
      VaultBackupErrorCode.payloadEmpty => l10n.backupPayloadEmpty(item),
      VaultBackupErrorCode.payloadLengthMismatch =>
        l10n.backupPayloadLengthMismatch(item),
      VaultBackupErrorCode.payloadDigestMismatch =>
        l10n.backupPayloadDigestMismatch(item),
      VaultBackupErrorCode.unsafePath => l10n.backupUnsafePath(item),
      VaultBackupErrorCode.destinationConflict =>
        l10n.backupDestinationConflict(item),
      VaultBackupErrorCode.destinationWriteFailed ||
      VaultBackupErrorCode.databaseWriteFailed =>
        restoring
            ? l10n.backupRestoreWriteFailed
            : l10n.backupExportWriteFailed,
    };
  }

  String _localeLabel(BuildContext context, String code) {
    final l10n = context.l10n;
    return switch (code) {
      'en' => l10n.languageEnglish,
      'zh_CN' => l10n.languageZhCn,
      'zh_HK' => l10n.languageZhHk,
      _ => l10n.languageSystem,
    };
  }

  String _shufflePlayCountLabel(
    BuildContext context,
    ShufflePlayCountMode mode,
  ) {
    final l10n = context.l10n;
    return switch (mode) {
      ShufflePlayCountMode.off => l10n.shufflePlayCountOff,
      ShufflePlayCountMode.soften => l10n.shufflePlayCountSoften,
      ShufflePlayCountMode.skip => l10n.shufflePlayCountSkip,
    };
  }

  String _autoLockLabel(BuildContext context, int s) {
    final l10n = context.l10n;
    if (s <= 0) return l10n.autoLockImmediately;
    if (s < 60) return l10n.autoLockSeconds(s);
    final m = s ~/ 60;
    return m == 1 ? l10n.autoLockMinutes(m) : l10n.autoLockMinutesPlural(m);
  }

  String _playerEngineLabel(BuildContext context, PlayerEngine engine) {
    final l10n = context.l10n;
    return switch (engine) {
      PlayerEngine.exoPlayer => l10n.playerEngineExoPlayer,
      PlayerEngine.vlc => l10n.playerEngineVlc,
    };
  }

  Future<T?> _pick<T>(
    BuildContext context, {
    required String title,
    required Map<String, T> options,
    required T current,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final e in options.entries)
              ListTile(
                title: Text(e.key),
                trailing: e.value == current
                    ? Icon(
                        Icons.check,
                        color: Theme.of(ctx).colorScheme.primary,
                      )
                    : null,
                onTap: () => Navigator.pop(ctx, e.value),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}