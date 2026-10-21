import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/backup/vault_backup_controller.dart';
import '../../application/lock/biometric_ui.dart';
import '../../application/lock/lock_controller.dart';
import '../../application/providers.dart';
import '../../application/settings/settings_controller.dart';
import '../../core/constants.dart';
import '../../core/l10n.dart';
import '../../data/repositories/media_repository.dart';
import '../../data/services/batch_decryption_service.dart';
import '../../data/services/batch_encryption_service.dart';
import '../../data/services/filename_encryption_service.dart';
import '../../data/services/key_backup_service.dart';
import '../../data/services/maintenance_service.dart';
import '../../data/services/playback_display_service.dart';
import '../../data/services/vault_backup_service.dart';
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

/// True while "Decrypt all files" runs.
bool _decryptAllInFlight = false;

/// The encrypt and decrypt flows both rewrite media files — never let them
/// overlap (two writers on the same file produced 0-byte media before,
/// ISSUE-030).
bool _encryptionFlowBusy() => _batchEncryptInFlight || _decryptAllInFlight;

/// Wake-lock holder id used while "Encrypt existing files" runs.
const String _encryptScreenHolder = 'settings.batchEncrypt';

/// How often the progress dialog may rebuild during the pass.  One rebuild per
/// item was tolerable in the serial loop but is pure overhead now that dozens
/// of queues finish items in parallel (6 000+ items × setDialogState).
const int _encryptProgressUiIntervalMs = 100;

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
            leading: const Icon(Icons.key_outlined),
            title: Text(context.l10n.exportVaultKey),
            subtitle: Text(context.l10n.exportVaultKeySubtitle),
            onTap: () => _exportVaultKey(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.vpn_key_outlined),
            title: Text(context.l10n.importVaultKey),
            subtitle: Text(context.l10n.importVaultKeySubtitle),
            onTap: () => _importVaultKey(context, ref),
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
            leading: const Icon(Icons.lock_open_outlined),
            title: Text(context.l10n.decryptAllFiles),
            subtitle: Text(context.l10n.decryptAllFilesSubtitle),
            onTap: () => _decryptAll(context, ref),
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
            leading: const Icon(Icons.plumbing_outlined),
            title: Text(context.l10n.repairEncryptionRecords),
            subtitle: Text(context.l10n.repairEncryptionRecordsSubtitle),
            onTap: () => _repairEncryptionRecords(context, ref),
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

  /// Reads a key package the user picks and adopts it as this install's key.
  ///
  /// Validates **before** asking for confirmation (a rejected package must never
  /// look like a successful import) and lets the service refuse a package that
  /// would invalidate files already encrypted here.  v2 packages are SQLite
  /// databases that also carry the filename/DEK map (ADR-047); v1 JSON packages
  /// still import as key-only.
  Future<void> _importVaultKey(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: false,
    );
    final path = picked?.files.single.path;
    if (path == null || !context.mounted) return;

    final service = ref.read(keyBackupServiceProvider);
    KeyPackageSummary? summary;
    var preview = KeyImportOutcome.failed;
    try {
      summary = await service.inspectPackage(path);
      if (summary != null) {
        preview = await service.validatePackage(path);
      }
    } catch (e, stackTrace) {
      AppLogger.e('SettingsScreen', 'inspect vault key: $e\n$stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.vaultKeyImportReadFailed)),
        );
      }
      return;
    }
    if (!context.mounted) return;
    if (summary == null || preview != KeyImportOutcome.imported) {
      final outcome = summary == null ? KeyImportOutcome.malformed : preview;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _keyImportMessage(context, KeyImportResult(outcome: outcome)),
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.importVaultKey),
        content: Text(
          context.l10n.importVaultKeyWarningDetail(
            summary!.fileCount,
            summary.encryptedFileCount,
          ),
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
    if (confirmed != true || !context.mounted) return;

    final result = await service.importPackage(path);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_keyImportMessage(context, result))),
    );
  }

  String _keyImportMessage(BuildContext context, KeyImportResult result) {
    switch (result.outcome) {
      case KeyImportOutcome.imported:
        return context.l10n.vaultKeyImportedDetail(
          result.restored,
          result.updated,
          result.skipped,
        );
      case KeyImportOutcome.malformed:
        return context.l10n.vaultKeyImportMalformed;
      case KeyImportOutcome.unsupportedVersion:
        return context.l10n.vaultKeyImportUnsupportedVersion;
      case KeyImportOutcome.saltConflict:
        return context.l10n.vaultKeyImportSaltConflict;
      case KeyImportOutcome.keyMismatch:
        return context.l10n.vaultKeyImportKeyMismatch;
      case KeyImportOutcome.failed:
        return context.l10n.vaultKeyImportFailed;
    }
  }

  /// Writes the vault key material (KEK + salt) **and** the filename/DEK map to
  /// a SQLite database in the directory the user picks, so a reinstall/device
  /// change can still decrypt old files and show their original names.
  Future<void> _exportVaultKey(BuildContext context, WidgetRef ref) async {
    if (ref.read(encryptionKeyManagerProvider).getKey() == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.vaultKeyExportLocked)),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.exportVaultKey),
        content: Text(context.l10n.exportVaultKeyWarning),
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
    if (confirmed != true || !context.mounted) return;

    final pickDirectory = ref.read(vaultBackupDirectoryPickerProvider);
    final directory = await pickDirectory(context.l10n.exportVaultKey);
    if (directory == null || !context.mounted) return;

    try {
      final saved =
          await ref.read(keyBackupServiceProvider).exportToDirectory(directory);
      AppLogger.i('SettingsScreen', 'vault key exported to $saved');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.vaultKeyExported(saved))),
        );
      }
    } catch (e, stackTrace) {
      AppLogger.e('SettingsScreen', 'export vault key: $e\n$stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.vaultKeyExportFailed)),
        );
      }
    }
  }

  Future<void> _batchEncrypt(BuildContext context, WidgetRef ref) async {
    // One flow at a time: two concurrent loops encrypt the same file twice,
    // which produced 0-byte media and vanished files (ISSUE-030).
    if (_encryptionFlowBusy()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.encryptingTitle)),
        );
      }
      return;
    }
    _batchEncryptInFlight = true;

    // Both passes run over parallel queues (BatchEncryptionService /
    // FilenameEncryptionService): the serial loops were the bottleneck at
    // 6 000+ files.
    final batch = ref.read(batchEncryptionServiceProvider);
    final filenames = ref.read(filenameEncryptionServiceProvider);
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
      // Ciphertext rows whose file name is still readable (ADR-042).
      final renamePending =
          FilenameEncryptionService.pendingItems(await repo.listEncrypted());

      if (unencrypted.isEmpty && renamePending.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.allFilesAlreadyEncrypted)),
          );
        }
        return;
      }

      final choice = await showDialog<_EncryptChoice>(
        context: context,
        builder: (ctx) => _EncryptOptionsDialog(
          plaintextCount: unencrypted.length,
          renameCount: renamePending.length,
        ),
      );
      if (choice == null || !context.mounted) return;
      // Validation: the dialog disables OK when nothing is ticked — this is the
      // belt-and-braces check so a pass never starts with no work to do.
      if (!choice.encryptContent && !choice.renameFilenames) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.encryptOptionsPickOne)),
        );
        return;
      }

      final renameStats = await _showEncryptProgress(
        context: context,
        batch: batch,
        filenames: filenames,
        repo: repo,
        contentItems: unencrypted,
        encryptContent: choice.encryptContent,
        encryptFilenames: choice.renameFilenames,
      );

      // The views cache file paths: refresh them once files were renamed.
      if ((renameStats?.renamed ?? 0) > 0) {
        ref.invalidate(albumsProvider);
        ref.invalidate(vaultSizeBytesProvider);
      }
    } finally {
      _batchEncryptInFlight = false;
      // Safety net: `run()` releases it too, but the dialog can be dismissed
      // from outside (system back) while the loop sits between two items.
      await PlaybackDisplayService.instance
          .releaseScreenOn(_encryptScreenHolder);
    }
  }

  /// Reverse of [_batchEncrypt]: decrypts contents and/or restores file names.
  ///
  /// Both passes run over parallel queues and share the per-item rules of their
  /// services (contents: decrypt → verify swap → clear DEK; names: rename →
  /// verify → repoint the row, rolling back on failure).
  Future<void> _decryptAll(BuildContext context, WidgetRef ref) async {
    if (_encryptionFlowBusy()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.decryptingTitle)),
        );
      }
      return;
    }
    _decryptAllInFlight = true;

    final decryption = ref.read(batchDecryptionServiceProvider);
    final filenames = ref.read(filenameEncryptionServiceProvider);
    final keyManager = ref.read(encryptionKeyManagerProvider);
    final repo = ref.read(mediaRepositoryProvider);

    try {
      if (keyManager.getKey() == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.vaultLockedPleaseUnlock)),
          );
        }
        return;
      }

      final contentItems = BatchDecryptionService.pendingItems(
        await repo.listEncrypted(),
      );
      final renameItems =
          FilenameEncryptionService.renamedItems(await repo.listActive());
      if (contentItems.isEmpty && renameItems.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.decryptNothingToDo)),
          );
        }
        return;
      }

      final choice = await showDialog<_DecryptChoice>(
        context: context,
        builder: (ctx) => _DecryptOptionsDialog(
          ciphertextCount: contentItems.length,
          renameCount: renameItems.length,
        ),
      );
      if (choice == null || !context.mounted) return;
      if (!choice.decryptContent && !choice.restoreFilenames) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.encryptOptionsPickOne)),
        );
        return;
      }

      await _showDecryptProgress(
        context: context,
        decryption: decryption,
        filenames: filenames,
        repo: repo,
        contentItems: contentItems,
        decryptContent: choice.decryptContent,
        restoreFilenames: choice.restoreFilenames,
      );

      // Paths changed (decrypted/renamed files): refresh the cached views.
      ref.invalidate(albumsProvider);
      ref.invalidate(vaultSizeBytesProvider);
    } finally {
      _decryptAllInFlight = false;
      // Safety net, mirroring `_batchEncrypt`.
      await PlaybackDisplayService.instance
          .releaseScreenOn(_encryptScreenHolder);
    }
  }

  /// Runs the selected decryption passes and reports progress in one dialog
  /// (phase 1 = contents, phase 2 = file names; mirrors `_showEncryptProgress`).
  Future<void> _showDecryptProgress({
    required BuildContext context,
    required BatchDecryptionService decryption,
    required FilenameEncryptionService filenames,
    required MediaRepository repo,
    required List<MediaItem> contentItems,
    required bool decryptContent,
    required bool restoreFilenames,
  }) {
    final contentTotal = decryptContent ? contentItems.length : 0;
    var stats = DecryptionStats();
    var restoreStats = FilenameRestoreStats();
    var renameTotal = 0;
    // 0 = content pass, 1 = filename pass (drives the status text/title).
    var phase = 0;
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
              // Keep the screen on: the device locking would background (and may
              // kill) the app mid-decryption.
              await PlaybackDisplayService.instance
                  .holdScreenOn(_encryptScreenHolder);
              var lastUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
              void onTick() {
                final elapsedMs =
                    DateTime.now().difference(lastUiUpdate).inMilliseconds;
                if (elapsedMs < _encryptProgressUiIntervalMs) return;
                lastUiUpdate = DateTime.now();
                if (ctx.mounted) setDialogState(() {});
              }

              if (decryptContent && contentItems.isNotEmpty) {
                stats = await decryption.run(
                  items: contentItems,
                  isCancelled: () => cancelled,
                  onProgress: (live) {
                    stats = live;
                    onTick();
                  },
                );
              }
              if (restoreFilenames && !cancelled) {
                // Re-read: the rows decrypted above are plaintext now, and files
                // that were already plaintext may still carry random names.
                final pending = FilenameEncryptionService.renamedItems(
                  await repo.listActive(),
                );
                renameTotal = pending.length;
                phase = 1;
                if (ctx.mounted) setDialogState(() {});
                restoreStats = await filenames.restoreNames(
                  items: pending,
                  isCancelled: () => cancelled,
                  onProgress: (live) {
                    restoreStats = live;
                    onTick();
                  },
                );
              }

              if (ctx.mounted) Navigator.pop(ctx);
              await PlaybackDisplayService.instance
                  .releaseScreenOn(_encryptScreenHolder);
              if (context.mounted) {
                final lines = <String>[
                  if (decryptContent)
                    stats.failed > 0
                        ? context.l10n
                            .decryptResultPartial(stats.decrypted, stats.failed)
                        : context.l10n
                            .decryptResultSuccess(stats.decrypted),
                  if (restoreFilenames)
                    context.l10n.filenameRestoreResult(restoreStats.restored),
                  if (restoreFilenames && restoreStats.failed > 0)
                    context.l10n
                        .filenameRestoreFailedCount(restoreStats.failed),
                ];
                if (lines.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(lines.join('\n'))),
                  );
                }
              }
            }

            // Start exactly once — the builder re-runs on every rebuild and used
            // to spawn one extra concurrent loop each time (ISSUE-030).
            if (!started) {
              started = true;
              WidgetsBinding.instance.addPostFrameCallback((_) => run());
            }

            final contentHandled = stats.handled;
            final renameHandled = restoreStats.handled;
            final total = contentTotal + renameTotal;
            final handled = contentHandled + renameHandled;
            final progress =
                total == 0 ? 0.0 : (handled / total).clamp(0.0, 1.0);
            // `keyLost` is set by whichever queue found the KEK gone — i.e. the
            // vault was locked while the content pass was running.
            final lockedOut =
                stats.keyLost && stats.unhandledOf(contentTotal) > 0;
            final stageTotal = phase == 1 ? renameTotal : contentTotal;
            final stageHandled = phase == 1 ? renameHandled : contentHandled;
            String status;
            if (lockedOut) {
              status = context.l10n.vaultLockedOperationStopped;
            } else if (stageTotal == 0 || stageHandled >= stageTotal) {
              status = context.l10n.done;
            } else if (phase == 1) {
              status = context.l10n.restoringNamesProgress(
                stageHandled + 1,
                stageTotal,
              );
            } else {
              status = context.l10n.decryptingProgress(
                stageHandled + 1,
                stageTotal,
              );
            }

            return AlertDialog(
              title: Text(
                phase == 1
                    ? context.l10n.decryptOptionFilenames
                    : context.l10n.decryptingTitle,
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 16),
                  Text(status),
                  if (stats.failed > 0)
                    Text(
                      context.l10n.encryptFailedCount(stats.failed),
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                  if (restoreStats.failed > 0)
                    Text(
                      context.l10n
                          .filenameRestoreFailedCount(restoreStats.failed),
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
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

  /// Runs the selected passes and reports progress in one dialog.
  ///
  /// Phase 1 encrypts the contents of [contentItems] over parallel queues;
  /// phase 2 re-reads the encrypted rows and renames every file whose name is
  /// still readable — so the files encrypted in phase 1 are renamed, too
  /// (ADR-042).  Returns the rename stats so the caller can refresh cached
  /// paths.
  Future<FilenameRenameStats?> _showEncryptProgress({
    required BuildContext context,
    required BatchEncryptionService batch,
    required FilenameEncryptionService filenames,
    required MediaRepository repo,
    required List<MediaItem> contentItems,
    required bool encryptContent,
    required bool encryptFilenames,
  }) {
    final contentTotal = encryptContent ? contentItems.length : 0;
    // Live counters, filled by the services through `onProgress` below.
    var stats = BatchEncryptionStats();
    var renameStats = FilenameRenameStats();
    var renameTotal = 0;
    // 0 = content pass, 1 = filename pass (drives the status text/title).
    var phase = 0;
    bool cancelled = false;
    // `run()` must start exactly once: the builder re-runs on every
    // setDialogState(), so registering the callback without a guard spawned a
    // new concurrent loop per rebuild (ISSUE-030).
    var started = false;
    FilenameRenameStats? renameResult;

    return showDialog<FilenameRenameStats?>(
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
              // The dialog may already be gone (system back): calling
              // setState on a disposed State throws.
              var lastUiUpdate = DateTime.fromMillisecondsSinceEpoch(0);
              void onTick() {
                final elapsedMs =
                    DateTime.now().difference(lastUiUpdate).inMilliseconds;
                if (elapsedMs < _encryptProgressUiIntervalMs) return;
                lastUiUpdate = DateTime.now();
                if (ctx.mounted) setDialogState(() {});
              }

              if (encryptContent && contentItems.isNotEmpty) {
                // Phase 1: `run()` returns when every queue drained, the vault
                // got locked, or the user cancelled.  Each item is claimed by
                // exactly one queue, so no file is ever encrypted twice
                // (ISSUE-030).
                stats = await batch.run(
                  items: contentItems,
                  isCancelled: () => cancelled,
                  onProgress: (live) {
                    stats = live;
                    onTick();
                  },
                );
              }
              if (encryptFilenames && !cancelled) {
                // Phase 2: re-read the rows — the files encrypted above are
                // ciphertext now and still carry their old names.
                final pending = FilenameEncryptionService.pendingItems(
                  await repo.listEncrypted(),
                );
                renameTotal = pending.length;
                phase = 1;
                if (ctx.mounted) setDialogState(() {});
                renameResult = await filenames.run(
                  items: pending,
                  isCancelled: () => cancelled,
                  onProgress: (live) {
                    renameStats = live;
                    onTick();
                  },
                );
              }
              if (ctx.mounted) Navigator.pop(ctx, renameResult);
              await PlaybackDisplayService.instance
                  .releaseScreenOn(_encryptScreenHolder);
              if (context.mounted) {
                final lines = <String>[
                  if (encryptContent)
                    stats.failed > 0
                        ? context.l10n
                            .encryptResultPartial(stats.encrypted, stats.failed)
                        : context.l10n
                            .encryptResultSuccess(stats.encrypted),
                  if (encryptContent && stats.missing > 0)
                    context.l10n.encryptMissingFiles(stats.missing),
                  if (encryptContent && stats.skippedNoKey > 0)
                    context.l10n.encryptSkippedNoKey(stats.skippedNoKey),
                  if (encryptFilenames)
                    context.l10n.filenameEncryptResult(renameStats.renamed),
                  if (encryptFilenames && renameStats.failed > 0)
                    context.l10n
                        .filenameEncryptFailedCount(renameStats.failed),
                ];
                if (lines.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(lines.join('\n'))),
                  );
                }
              }
            }

            // Start exactly once — the builder re-runs on every rebuild and
            // used to spawn one extra concurrent loop each time (ISSUE-030).
            if (!started) {
              started = true;
              WidgetsBinding.instance.addPostFrameCallback((_) => run());
            }

            final contentHandled = stats.handled;
            final renameHandled = renameStats.handled;
            final total = contentTotal + renameTotal;
            final handled = contentHandled + renameHandled;
            final progress =
                total == 0 ? 0.0 : (handled / total).clamp(0.0, 1.0);
            // `keyLost` is set by whichever queue found the KEK gone — i.e. the
            // vault was locked while the content pass was running.
            final lockedOut =
                stats.keyLost && stats.unhandledOf(contentTotal) > 0;
            final stageTotal = phase == 1 ? renameTotal : contentTotal;
            final stageHandled = phase == 1 ? renameHandled : contentHandled;
            String status;
            if (lockedOut) {
              status = context.l10n.vaultLockedOperationStopped;
            } else if (stageTotal == 0 || stageHandled >= stageTotal) {
              status = context.l10n.done;
            } else if (phase == 1) {
              status = context.l10n.renamingProgress(
                stageHandled + 1,
                stageTotal,
              );
            } else {
              status = context.l10n.encryptingProgress(
                stageHandled + 1,
                stageTotal,
              );
            }

            return AlertDialog(
              title: Text(
                phase == 1
                    ? context.l10n.encryptOptionFilenames
                    : context.l10n.encryptingTitle,
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 16),
                  Text(status),
                  if (stats.failed > 0)
                    Text(
                      context.l10n.encryptFailedCount(stats.failed),
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                  if (stats.skippedNoKey > 0)
                    Text(
                      context.l10n.encryptSkippedNoKey(stats.skippedNoKey),
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                  if (renameStats.failed > 0)
                    Text(
                      context.l10n
                          .filenameEncryptFailedCount(renameStats.failed),
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
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

  /// Clears rows that claim to be encrypted while their file is plaintext.
  ///
  /// Dry run first (`scan(apply: false)`) so the confirmation dialog can show
  /// how many rows are actually affected — and so an all-clean vault never asks
  /// for a pointless confirmation.
  Future<void> _repairEncryptionRecords(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final service = ref.read(encryptionRecordRepairServiceProvider);
    final repo = ref.read(mediaRepositoryProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.scanningEncryptionRecords)),
    );
    try {
      final preview = await service.scan(items: await repo.listActive());
      if (!context.mounted) return;

      if (preview.staleCleared == 0) {
        final lines = <String>[
          context.l10n.repairEncryptionNothingFound,
          if (preview.orphanCiphertext > 0)
            context.l10n.repairEncryptionOrphans(preview.orphanCiphertext),
        ];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(lines.join('\n'))),
        );
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(context.l10n.repairEncryptionRecords),
          content: Text(
            context.l10n.repairEncryptionRecordsBody(preview.staleCleared),
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
      if (confirmed != true || !context.mounted) return;

      final result =
          await service.scan(items: await repo.listActive(), apply: true);
      // Those rows are "unencrypted" again, so cached views/queues change.
      ref.invalidate(albumsProvider);
      ref.invalidate(vaultSizeBytesProvider);
      if (!context.mounted) return;
      final lines = <String>[
        context.l10n.repairEncryptionResult(result.staleCleared),
        if (result.orphanCiphertext > 0)
          context.l10n.repairEncryptionOrphans(result.orphanCiphertext),
      ];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(lines.join('\n'))),
      );
    } catch (e, stackTrace) {
      AppLogger.e(
          'SettingsScreen', 'repair encryption records: $e\n$stackTrace');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.repairEncryptionFailed)),
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

/// Confirmation dialog for "Encrypt existing files".
///
/// The user picks the content pass, the filename pass, or both (ADR-042):
///  * content pass — encrypts the bytes of rows that are still plaintext;
///  * filename pass — renames ciphertext files to random, extension-less names.
///
/// Defaults are deliberately conservative: an available content pass is ticked,
/// the irreversible rename only when no content work is left (the "already
/// encrypted, I only want the names done" case).  OK stays disabled while
/// nothing is ticked, so a pass can never start with no work (validation).
class _EncryptOptionsDialog extends StatefulWidget {
  const _EncryptOptionsDialog({
    required this.plaintextCount,
    required this.renameCount,
  });

  final int plaintextCount;
  final int renameCount;

  @override
  State<_EncryptOptionsDialog> createState() => _EncryptOptionsDialogState();
}

class _EncryptOptionsDialogState extends State<_EncryptOptionsDialog> {
  late bool _content = widget.plaintextCount > 0;
  late bool _filenames = widget.plaintextCount == 0 && widget.renameCount > 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canPickContent = widget.plaintextCount > 0;
    final canPickFilenames = widget.renameCount > 0;
    final picked =
        (_content && canPickContent) || (_filenames && canPickFilenames);

    return AlertDialog(
      title: Text(l10n.encryptExistingFiles),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              canPickContent
                  ? l10n.encryptConfirmationBody(widget.plaintextCount)
                  : l10n.encryptFilenamesConfirmationBody(widget.renameCount),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _content && canPickContent,
              onChanged: canPickContent
                  ? (value) => setState(() => _content = value ?? false)
                  : null,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: Text(l10n.encryptOptionContent),
              subtitle: Text(
                l10n.encryptOptionContentSubtitle(widget.plaintextCount),
              ),
            ),
            CheckboxListTile(
              value: _filenames && canPickFilenames,
              onChanged: canPickFilenames
                  ? (value) => setState(() => _filenames = value ?? false)
                  : null,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: Text(l10n.encryptOptionFilenames),
              subtitle: Text(
                l10n.encryptOptionFilenamesSubtitle(widget.renameCount),
              ),
            ),
            if (!picked)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.encryptOptionsPickOne,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: picked
              ? () => Navigator.pop(
                    context,
                    _EncryptChoice(
                      encryptContent: _content && canPickContent,
                      renameFilenames: _filenames && canPickFilenames,
                    ),
                  )
              : null,
          child: Text(l10n.encryptAction),
        ),
      ],
    );
  }
}

/// What the user ticked in [_EncryptOptionsDialog].
class _EncryptChoice {
  const _EncryptChoice({
    required this.encryptContent,
    required this.renameFilenames,
  });

  final bool encryptContent;
  final bool renameFilenames;
}


/// Confirmation dialog for "Decrypt all files" — the mirror of
/// [_EncryptOptionsDialog].
///
/// The user picks the content pass (ciphertext → plaintext), the filename pass
/// (random name → original name), or both.  Defaults stay conservative: the
/// content pass is ticked when ciphertext exists, the filename pass only when
/// there is no content work left.  OK is disabled while nothing is ticked, so
/// the flow can never start with no work (validation).
class _DecryptOptionsDialog extends StatefulWidget {
  const _DecryptOptionsDialog({
    required this.ciphertextCount,
    required this.renameCount,
  });

  final int ciphertextCount;
  final int renameCount;

  @override
  State<_DecryptOptionsDialog> createState() => _DecryptOptionsDialogState();
}

class _DecryptOptionsDialogState extends State<_DecryptOptionsDialog> {
  late bool _content = widget.ciphertextCount > 0;
  late bool _filenames =
      widget.ciphertextCount == 0 && widget.renameCount > 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canPickContent = widget.ciphertextCount > 0;
    final canPickFilenames = widget.renameCount > 0;
    final picked =
        (_content && canPickContent) || (_filenames && canPickFilenames);

    return AlertDialog(
      title: Text(l10n.decryptAllFiles),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              canPickContent
                  ? l10n.decryptConfirmationBody
                  : l10n.decryptFilenamesOnlyBody,
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: _content && canPickContent,
              onChanged: canPickContent
                  ? (value) => setState(() => _content = value ?? false)
                  : null,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: Text(l10n.decryptOptionContent),
              subtitle: Text(
                l10n.decryptOptionContentSubtitle(widget.ciphertextCount),
              ),
            ),
            CheckboxListTile(
              value: _filenames && canPickFilenames,
              onChanged: canPickFilenames
                  ? (value) => setState(() => _filenames = value ?? false)
                  : null,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              dense: true,
              title: Text(l10n.decryptOptionFilenames),
              subtitle: Text(
                l10n.decryptOptionFilenamesSubtitle(widget.renameCount),
              ),
            ),
            if (!picked)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.encryptOptionsPickOne,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: picked
              ? () => Navigator.pop(
                    context,
                    _DecryptChoice(
                      decryptContent: _content && canPickContent,
                      restoreFilenames: _filenames && canPickFilenames,
                    ),
                  )
              : null,
          child: Text(l10n.decryptAllFiles),
        ),
      ],
    );
  }
}

/// What the user ticked in [_DecryptOptionsDialog].
class _DecryptChoice {
  const _DecryptChoice({
    required this.decryptContent,
    required this.restoreFilenames,
  });

  final bool decryptContent;
  final bool restoreFilenames;
}

