import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/vault_backup_service.dart';
import '../media/album_kind_preferences.dart';
import '../media/album_list_preferences.dart';
import '../media/visible_folder_view_preferences.dart';
import '../providers.dart';
import '../settings/settings_controller.dart';
import '../../core/utils/app_logger.dart';

enum VaultBackupOperation { export, restore }

enum VaultBackupUiStatus {
  idle,
  selectingDirectory,
  running,
  cancelling,
  completed,
  cancelled,
  failed,
}

final class VaultBackupUiState {
  const VaultBackupUiState({
    this.operation,
    this.directory,
    this.status = VaultBackupUiStatus.idle,
    this.progress = const VaultBackupProgress(
      stage: VaultBackupStage.preparing,
      completed: 0,
      total: 0,
    ),
    this.result,
    this.error,
  });

  final VaultBackupOperation? operation;
  final String? directory;
  final VaultBackupUiStatus status;
  final VaultBackupProgress progress;
  final VaultBackupResult? result;
  final Object? error;

  bool get busy => switch (status) {
        VaultBackupUiStatus.selectingDirectory ||
        VaultBackupUiStatus.running ||
        VaultBackupUiStatus.cancelling =>
          true,
        _ => false,
      };

  bool get dialogVisible => switch (status) {
        VaultBackupUiStatus.running ||
        VaultBackupUiStatus.cancelling ||
        VaultBackupUiStatus.completed ||
        VaultBackupUiStatus.cancelled ||
        VaultBackupUiStatus.failed =>
          true,
        _ => false,
      };
}

class VaultBackupController extends Notifier<VaultBackupUiState> {
  VaultBackupSession? _session;

  @override
  VaultBackupUiState build() => const VaultBackupUiState();

  Future<bool> selectDirectoryAndStart({
    required VaultBackupOperation operation,
    required Future<String?> Function() selectDirectory,
  }) async {
    _ensureAvailable();
    state = VaultBackupUiState(
      operation: operation,
      status: VaultBackupUiStatus.selectingDirectory,
    );
    String? directory;
    try {
      directory = await selectDirectory();
    } catch (_) {
      if (ref.mounted) state = const VaultBackupUiState();
      rethrow;
    }
    if (!ref.mounted) return false;
    if (directory == null) {
      state = const VaultBackupUiState();
      return false;
    }
    final selected = directory;
    unawaited(
      _run(
        operation: operation,
        directory: selected,
        execute: (session) => _execute(operation, selected, session),
      ),
    );
    return true;
  }

  Future<void> start({
    required VaultBackupOperation operation,
    required String directory,
  }) {
    _ensureAvailable();
    return _run(
      operation: operation,
      directory: directory,
      execute: (session) => _execute(operation, directory, session),
    );
  }

  /// Relinks a data-only import whose media files were copied after the fact.
  ///
  /// The archive records no media bytes (`ADR-049`), so an import that ran
  /// before the folder was copied has no rows to link. The import remembers its
  /// archive; this re-runs it once the files are visible and returns the result
  /// (null when nothing is pending).
  Future<VaultBackupResult?> resumePendingRestore() async {
    _ensureAvailable();
    final service = ref.read(vaultBackupServiceProvider);
    if (!await service.hasPendingRestore) return null;
    await _run(
      operation: VaultBackupOperation.restore,
      execute: (session) => service.resumePending(
        session: session,
        onProgress: (progress) => _updateProgress(session, progress),
      ),
    );
    return state.result;
  }

  Future<void> retry() async {
    final operation = state.operation;
    final directory = state.directory;
    if (operation == null) {
      throw StateError('No vault backup operation is available to retry.');
    }
    if (directory == null) {
      // A relink has no directory of its own; retry it the same way.
      await resumePendingRestore();
      return;
    }
    await start(operation: operation, directory: directory);
  }

  Future<VaultBackupResult> _execute(
    VaultBackupOperation operation,
    String directory,
    VaultBackupSession session,
  ) {
    final service = ref.read(vaultBackupServiceProvider);
    return switch (operation) {
      VaultBackupOperation.export => service.exportToDirectory(
          directory,
          session: session,
          onProgress: (progress) => _updateProgress(session, progress),
        ),
      VaultBackupOperation.restore => service.importFromDirectory(
          directory,
          session: session,
          onProgress: (progress) => _updateProgress(session, progress),
        ),
    };
  }

  void cancel() {
    final session = _session;
    if (session == null || state.status != VaultBackupUiStatus.running) {
      throw StateError('No running vault backup operation can be cancelled.');
    }
    session.cancel();
    state = VaultBackupUiState(
      operation: state.operation,
      directory: state.directory,
      status: VaultBackupUiStatus.cancelling,
      progress: state.progress,
    );
  }

  void dismiss() {
    if (state.busy) {
      throw StateError('A running vault backup operation cannot be dismissed.');
    }
    state = const VaultBackupUiState();
  }

  Future<void> _run({
    required VaultBackupOperation operation,
    required Future<VaultBackupResult?> Function(VaultBackupSession session)
        execute,
    String? directory,
  }) async {
    final session = VaultBackupSession();
    _session = session;
    state = VaultBackupUiState(
      operation: operation,
      directory: directory,
      status: VaultBackupUiStatus.running,
    );
    try {
      final result = await execute(session);
      if (!ref.mounted || !identical(_session, session)) return;
      final cancelled = result?.cancelled ?? false;
      state = VaultBackupUiState(
        operation: operation,
        directory: directory,
        status: cancelled
            ? VaultBackupUiStatus.cancelled
            : VaultBackupUiStatus.completed,
        progress: state.progress,
        result: result,
      );
      if (!cancelled && operation == VaultBackupOperation.restore) {
        ref.invalidate(vaultSizeBytesProvider);
        ref.invalidate(albumsProvider);
        // v6 backups restore every app setting; drop the cached state so the
        // UI reads the freshly written SharedPreferences values.
        ref.invalidate(settingsControllerProvider);
        ref.invalidate(albumListPreferencesProvider);
        ref.invalidate(albumKindPreferencesProvider);
        ref.invalidate(visibleFolderViewPreferencesProvider);
        // The archive also carries the registered vault libraries. Reload the
        // in-memory registry so scans/writes immediately see the restored list
        // (paths from another phone will be shown as unavailable in Settings).
        ref.read(vaultLibraryRegistryProvider).reload();
      }
    } catch (error, stackTrace) {
      AppLogger.e('VaultBackupController',
          'vault backup controller: $error\n$stackTrace');
      if (!ref.mounted || !identical(_session, session)) return;
      state = VaultBackupUiState(
        operation: operation,
        directory: directory,
        status: VaultBackupUiStatus.failed,
        progress: state.progress,
        error: error,
      );
    } finally {
      if (identical(_session, session)) _session = null;
    }
  }

  void _updateProgress(
    VaultBackupSession session,
    VaultBackupProgress progress,
  ) {
    if (!ref.mounted || !identical(_session, session)) return;
    state = VaultBackupUiState(
      operation: state.operation,
      directory: state.directory,
      status: session.isCancelled
          ? VaultBackupUiStatus.cancelling
          : VaultBackupUiStatus.running,
      progress: progress,
    );
  }

  void _ensureAvailable() {
    if (state.busy) {
      throw StateError('A vault backup operation is already in progress.');
    }
  }
}

final vaultBackupControllerProvider =
    NotifierProvider<VaultBackupController, VaultBackupUiState>(
  VaultBackupController.new,
);
