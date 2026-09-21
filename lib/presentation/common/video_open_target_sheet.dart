import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/l10n.dart';
import 'vault_sheet.dart';

/// What a long-press on a video item should do.
enum VideoOpenTarget {
  /// Hand the file over to the system chooser / external player app.
  external,

  /// Play it in the built-in player, regardless of the "prefer external
  /// player" setting.
  internal,

  /// The behaviour long-press had before this chooser existed: start selecting.
  selection,
}

/// Long-press chooser for video items: external player, in-app playback, or
/// selection.
///
/// Returns null when the sheet is dismissed without a choice, so callers can
/// leave the grid untouched in that case.
Future<VideoOpenTarget?> showVideoOpenTargetSheet(
  BuildContext context, {
  required bool externalSupported,
}) {
  return showVaultSheet<VideoOpenTarget>(
    context,
    builder: (sheetContext) {
      final l10n = sheetContext.l10n;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.xs,
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  l10n.openWith,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
            ),
            ListTile(
              key: const ValueKey('video-open-external'),
              enabled: externalSupported,
              leading: const Icon(Icons.open_in_new),
              title: Text(l10n.openExternal),
              subtitle: externalSupported
                  ? null
                  : Text(l10n.externalPlaybackUnsupported),
              onTap: externalSupported
                  ? () =>
                      Navigator.of(sheetContext).pop(VideoOpenTarget.external)
                  : null,
            ),
            ListTile(
              key: const ValueKey('video-open-internal'),
              leading: const Icon(Icons.smart_display_outlined),
              title: Text(l10n.inAppPlayback),
              onTap: () =>
                  Navigator.of(sheetContext).pop(VideoOpenTarget.internal),
            ),
            ListTile(
              key: const ValueKey('video-open-selection'),
              leading: const Icon(Icons.check_circle_outline),
              title: Text(l10n.select),
              onTap: () =>
                  Navigator.of(sheetContext).pop(VideoOpenTarget.selection),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      );
    },
  );
}
