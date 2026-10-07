import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/l10n.dart';
import '../../domain/enums.dart';
import 'vault_sheet.dart';

/// 长按菜单里「内部播放（默认引擎）」写死的引擎。
///
/// **不看设置**：设置里也可能是 libVLC，跟着设置走会让两条内部入口变成同一个
/// 引擎、名字却不同（用户实测的重复问题）。
const PlayerEngine kSheetDefaultEngine = PlayerEngine.exoPlayer;

/// What a long-press on a video item should do.
enum VideoOpenTarget {
  /// Hand the file over to the system chooser / external player app.
  external,

  /// Play it in the built-in player with [kSheetDefaultEngine] (ExoPlayer),
  /// regardless of both the "playback engine" and "prefer external player"
  /// settings.
  internalDefaultEngine,

  /// Play it in the built-in player with libVLC for this one item, whatever
  /// the settings say (the default engine cannot decode everything).
  internalVlcEngine,
}

/// 引擎在「打开方式」里的显示名，与设置页的 `播放引擎` 文案保持一致。
String videoEngineLabel(BuildContext context, PlayerEngine engine) {
  final l10n = context.l10n;
  return switch (engine) {
    PlayerEngine.exoPlayer => l10n.playerEngineExoPlayer,
    PlayerEngine.vlc => l10n.playerEngineVlc,
  };
}

/// Long-press chooser for video items: external player, in-app playback with
/// ExoPlayer or with libVLC, or selection.
///
/// The two in-app entries use **fixed** engines ([kSheetDefaultEngine] /
/// [PlayerEngine.vlc]) and deliberately ignore the "playback engine" setting:
/// when that setting is libVLC, following it would render both entries
/// identical while still being labelled differently.
///
/// Returns null when the sheet is dismissed without a choice, so callers can
/// leave the grid untouched in that case.
///
/// Selection is deliberately absent: every grid reaches it from the row's
/// swipe actions (the「操作」button) or from the ⋮ menu, so a long-press on a
/// video is purely about playback.
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
              key: const ValueKey('video-open-internal-default'),
              leading: const Icon(Icons.smart_display_outlined),
              title: Text(l10n.inAppPlaybackDefaultEngine),
              subtitle: Text(videoEngineLabel(sheetContext, kSheetDefaultEngine)),
              onTap: () => Navigator.of(sheetContext)
                  .pop(VideoOpenTarget.internalDefaultEngine),
            ),
            ListTile(
              key: const ValueKey('video-open-internal-vlc'),
              leading: const Icon(Icons.movie_filter_outlined),
              title: Text(l10n.inAppPlaybackVlcEngine),
              onTap: () => Navigator.of(sheetContext)
                  .pop(VideoOpenTarget.internalVlcEngine),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      );
    },
  );
}
