import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../core/constants.dart';
import '../../core/l10n.dart';
import '../../core/utils/app_logger.dart';
import '../../data/services/media_crypto_repair_service.dart';
import '../../data/services/playback_display_service.dart';

/// Screen-on holder for this flow — every holder must be released (`ADR-037`).
const String _repairScreenHolder = 'grid.cryptoRepair';

/// One repair at a time: an in-flight decrypt + swap is never interrupted, and
/// two runs must never rewrite the same file concurrently (`ISSUE-030`).
bool _repairInFlight = false;

/// Runs the "加解密修复" action over [paths] (Visible **and** Invisible grids).
///
/// Reports progress in a modal dialog and, afterwards, a summary that names what
/// happened per outcome (`MediaCryptoRepairService`).  Returns null when the run
/// never started (empty selection, or another repair is still running).
Future<CryptoRepairReport?> runCryptoRepair(
  BuildContext context,
  WidgetRef ref, {
  required List<String> paths,
}) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  if (paths.isEmpty) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.repairCryptoNothingSelected)),
    );
    return null;
  }
  if (_repairInFlight) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.repairCryptoRunning)),
    );
    return null;
  }
  _repairInFlight = true;

  final service = ref.read(mediaCryptoRepairServiceProvider);
  var done = 0;
  var total = paths.length;
  var current = '';
  // The pass must start exactly once — `showDialog`'s builder re-runs on every
  // setDialogState(), and starting it there spawned a concurrent loop per
  // rebuild (`ISSUE-030`).
  var started = false;
  CryptoRepairReport? report;

  final result = await showDialog<CryptoRepairReport?>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        Future<void> run() async {
          final display = PlaybackDisplayService.instance;
          // Decrypting a large file takes long enough for a screen lock to
          // background the app mid-swap.
          await display.holdScreenOn(_repairScreenHolder);
          try {
            report = await service.repairPaths(
              paths,
              onProgress: (d, t, name) {
                done = d;
                total = t;
                current = name;
                if (ctx.mounted) setDialogState(() {});
              },
            );
          } catch (error, stackTrace) {
            AppLogger.e(
                'CryptoRepairAction', 'repair failed: $error\n$stackTrace');
          } finally {
            _repairInFlight = false;
            await display.releaseScreenOn(_repairScreenHolder);
          }
          if (ctx.mounted) Navigator.pop(ctx, report);
        }

        if (!started) {
          started = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(run()));
        }

        final index = done >= total ? total : done + 1;
        final status = current.isEmpty || total == 0
            ? l10n.repairCryptoRunning
            : l10n.repairCryptoProgress(index, total, current);
        final value = total == 0 ? null : (done / total).clamp(0.0, 1.0);

        return AlertDialog(
          title: Text(l10n.repairCrypto),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: value),
              const SizedBox(height: AppSpacing.lg),
              Text(status),
            ],
          ),
          // No cancel button: interrupting a decrypt + swap is exactly the
          // crash window `PIT-064` warns about (a file that is neither the
          // ciphertext nor the plaintext).
          actions: const <Widget>[],
        );
      },
    ),
  );

  if (!context.mounted) return result;
  // Paths changed in place (decrypted) → cached album sizes/covers are stale.
  ref.invalidate(albumsProvider);
  ref.invalidate(vaultSizeBytesProvider);
  if (result != null && result.total > 0) {
    await _showRepairSummary(context, result);
  }
  return result;
}

/// One dialog listing what the run did, per outcome.
Future<void> _showRepairSummary(
  BuildContext context,
  CryptoRepairReport report,
) async {
  final l10n = context.l10n;
  final lines = <String>[
    if (report.decrypted > 0) l10n.repairCryptoDecrypted(report.decrypted),
    if (report.recordCleared > 0)
      l10n.repairCryptoRecordCleared(report.recordCleared),
    if (report.keyMismatch > 0)
      l10n.repairCryptoKeyMismatch(report.keyMismatch),
    if (report.noKey > 0) l10n.repairCryptoNoKey(report.noKey),
    if (report.locked > 0) l10n.repairCryptoLocked,
    if (report.missing > 0) l10n.repairCryptoMissing(report.missing),
    if (report.failed > 0) l10n.repairCryptoFailed(report.failed),
    if (report.nothingToDo > 0) l10n.repairCryptoAlreadyPlain,
  ];
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.repairCrypto),
      content: SingleChildScrollView(child: Text(lines.join('\n\n'))),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l10n.done),
        ),
      ],
    ),
  );
}
