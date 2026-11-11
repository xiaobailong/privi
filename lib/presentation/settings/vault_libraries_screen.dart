import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../application/backup/vault_backup_controller.dart';
import '../../application/providers.dart';
import '../../core/l10n.dart';
import '../../core/utils/app_logger.dart';
import '../../data/services/vault_library_registry.dart';
import 'vault_data_screen.dart';

/// Settings → 保险库管理.
///
/// The built-in root is always present; user-added directories are registered
/// as additional, parallel libraries. One of them is the write target for new
/// hides. This is the migration entry point: copy an old phone's vault folder
/// anywhere on the new phone, add it here, then let the orphan scan rebuild
/// the database rows for the files in it.
class VaultLibrariesScreen extends ConsumerStatefulWidget {
  const VaultLibrariesScreen({super.key});

  @override
  ConsumerState<VaultLibrariesScreen> createState() =>
      _VaultLibrariesScreenState();
}

class _VaultLibrariesScreenState extends ConsumerState<VaultLibrariesScreen> {
  bool _busy = false;
  String? _builtInPath;

  @override
  void initState() {
    super.initState();
    _loadBuiltInPath();
  }

  Future<void> _loadBuiltInPath() async {
    try {
      final root = await ref.read(vaultStorageProvider).ensureHiddenRoot();
      if (mounted) setState(() => _builtInPath = root.path);
    } catch (e) {
      AppLogger.w('VaultLibrariesScreen', 'built-in root unavailable: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final registry = ref.watch(vaultLibraryRegistryProvider);
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.vaultLibraries)),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  l10n.vaultLibrariesSubtitle,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              _builtInTile(registry, l10n),
              if (registry.userLibraries.isEmpty)
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(l10n.vaultLibraryEmpty),
                ),
              for (final entry in registry.userLibraries)
                _userLibraryTile(registry, entry, l10n),
              const Divider(height: 24),
              ListTile(
                key: const ValueKey('vault-library-add'),
                leading: const Icon(Icons.create_new_folder_outlined),
                title: Text(l10n.vaultLibraryAdd),
                subtitle: Text(l10n.vaultLibraryAddHint),
                onTap: _busy ? null : _addLibrary,
              ),
              ListTile(
                key: const ValueKey('vault-library-data'),
                leading: const Icon(Icons.dns_outlined),
                title: Text(l10n.vaultDataManagement),
                subtitle: Text(l10n.vaultDataManagementSubtitle),
                onTap: _busy
                    ? null
                    : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const VaultDataScreen(),
                          ),
                        ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  l10n.vaultLibraryHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  l10n.vaultLibraryMigrationHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          if (_busy) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  Widget _builtInTile(VaultLibraryRegistry registry, AppLocalizations l10n) {
    final active = registry.activeId == VaultLibraryRegistry.builtInId;
    return _card(
      ListTile(
        key: const ValueKey('vault-library-builtin'),
        leading: const Icon(Icons.lock_outline),
        title: Row(
          children: [
            Text(l10n.vaultLibraryBuiltIn),
            if (active) ...[
              const SizedBox(width: 8),
              _currentChip(l10n),
            ],
          ],
        ),
        subtitle: Text(
          '${_builtInPath ?? ''}\n${l10n.vaultLibraryBuiltInSubtitle}',
        ),
        isThreeLine: true,
        trailing: active
            ? null
            : TextButton(
                onPressed: _busy
                    ? null
                    : () => _setActive(VaultLibraryRegistry.builtInId),
                child: Text(l10n.vaultLibrarySetCurrent),
              ),
      ),
    );
  }

  Widget _userLibraryTile(
    VaultLibraryRegistry registry,
    VaultLibraryEntry entry,
    AppLocalizations l10n,
  ) {
    final active = registry.activeId == entry.id;
    final available = Directory(entry.path).existsSync();
    return _card(
      ListTile(
        key: ValueKey('vault-library-${entry.id}'),
        leading: Icon(
          available ? Icons.folder_outlined : Icons.warning_amber_outlined,
          color: available ? null : Theme.of(context).colorScheme.error,
        ),
        title: Row(
          children: [
            Flexible(child: Text(entry.name, overflow: TextOverflow.ellipsis)),
            if (active) ...[
              const SizedBox(width: 8),
              _currentChip(l10n),
            ],
          ],
        ),
        subtitle: Text(
          available
              ? entry.path
              : '${entry.path}\n${l10n.vaultLibraryUnavailable}',
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<String>(
          enabled: !_busy,
          onSelected: (value) {
            if (value == 'active') {
              _setActive(entry.id);
            } else if (value == 'remove') {
              _removeLibrary(entry);
            }
          },
          itemBuilder: (_) => [
            if (!active)
              PopupMenuItem(
                value: 'active',
                child: Text(l10n.vaultLibrarySetCurrent),
              ),
            PopupMenuItem(
              value: 'remove',
              child: Text(l10n.vaultLibraryRemove),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(Widget child) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: child,
      );

  Widget _currentChip(AppLocalizations l10n) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          l10n.vaultLibraryCurrent,
          style: Theme.of(context).textTheme.labelSmall,
        ),
      );

  Future<void> _setActive(String id) async {
    try {
      await ref.read(vaultLibraryRegistryProvider).setActive(id);
      if (mounted) _snack(context.l10n.vaultLibrarySetCurrentDone);
    } catch (e, stackTrace) {
      AppLogger.e('VaultLibrariesScreen', 'setActive: $e\n$stackTrace');
      if (mounted) _snack(context.l10n.vaultLibraryOperationFailed);
    }
  }

  Future<void> _addLibrary() async {
    final l10n = context.l10n;
    final picker = ref.read(vaultBackupDirectoryPickerProvider);
    String? picked;
    try {
      picked = await picker(l10n.vaultLibraryAdd);
    } catch (e, stackTrace) {
      AppLogger.e('VaultLibrariesScreen', 'pick directory: $e\n$stackTrace');
      _snack(l10n.vaultLibraryOperationFailed);
      return;
    }
    if (picked == null || !mounted) return;

    final storage = ref.read(vaultStorageProvider);
    final check = await storage.validateLibraryPath(picked);
    if (!mounted) return;
    if (!check.ok) {
      _snack(_messageFor(check.issue, l10n));
      return;
    }
    final normalized = check.normalizedPath!;

    final nameController = TextEditingController(
      text: p.basename(normalized),
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.vaultLibraryAddConfirmTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(normalized, style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.nameLabel,
                  hintText: l10n.vaultLibraryNameHint,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                l10n.vaultLibraryAddConfirmBody,
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameController.text),
            child: Text(l10n.continueAction),
          ),
        ],
      ),
    );
    nameController.dispose();
    if (name == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final registry = ref.read(vaultLibraryRegistryProvider);
      await registry.add(path: normalized, name: name);
      // Hide the new library from MediaScanner regardless of which one is the
      // current write target.
      await storage.prepareLibraryDirectory(normalized);

      // A data-only import that ran before this folder was copied can now link
      // its rows — with DEKs, key ids and album memberships — instead of
      // rebuilding bare entries that could never be decrypted.
      final backup = ref.read(vaultBackupServiceProvider);
      if (await backup.hasPendingRestore) {
        final result = await ref
            .read(vaultBackupControllerProvider.notifier)
            .resumePendingRestore();
        if (!mounted) return;
        if (await backup.hasPendingRestore) {
          _snack(l10n.vaultLibraryRelinkPending);
        } else {
          _snack(l10n.vaultLibraryRelinkDone(result?.itemCount ?? 0));
        }
        return;
      }

      final scan = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l10n.vaultLibraryScanTitle),
          content: Text(l10n.vaultLibraryScanBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l10n.continueAction),
            ),
          ],
        ),
      );
      if (scan == true) {
        final result =
            await ref.read(maintenanceServiceProvider).scanOrphanHiddenFiles();
        if (mounted) _snack(l10n.vaultLibraryScanDone(result.reindexed));
      } else if (mounted) {
        _snack(l10n.vaultLibraryAdded);
      }
    } catch (e, stackTrace) {
      AppLogger.e('VaultLibrariesScreen', 'add library: $e\n$stackTrace');
      if (mounted) _snack(l10n.vaultLibraryOperationFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeLibrary(VaultLibraryEntry entry) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.vaultLibraryRemoveTitle),
        content: Text(l10n.vaultLibraryRemoveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.vaultLibraryRemove),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final repository = ref.read(mediaRepositoryProvider);
      final items = await repository.listAll();
      final ids = <String>[
        for (final item in items)
          if (_isWithin(entry.path, item.privatePath)) item.id,
      ];
      // Rows only: the files stay on the phone and can be re-indexed by
      // adding this directory again later.
      if (ids.isNotEmpty) await repository.hardDeleteRowsOnly(ids);
      await ref.read(vaultLibraryRegistryProvider).remove(entry.id);
      if (mounted) _snack(l10n.vaultLibraryRemoved(ids.length));
    } catch (e, stackTrace) {
      AppLogger.e('VaultLibrariesScreen', 'remove library: $e\n$stackTrace');
      if (mounted) _snack(l10n.vaultLibraryOperationFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _messageFor(VaultLibraryPathIssue issue, AppLocalizations l10n) {
    return switch (issue) {
      VaultLibraryPathIssue.empty => l10n.vaultLibraryErrEmpty,
      VaultLibraryPathIssue.missing => l10n.vaultLibraryErrMissing,
      VaultLibraryPathIssue.notDirectory => l10n.vaultLibraryErrNotDirectory,
      VaultLibraryPathIssue.unreadable => l10n.vaultLibraryErrUnreadable,
      VaultLibraryPathIssue.duplicate => l10n.vaultLibraryErrDuplicate,
      VaultLibraryPathIssue.nested => l10n.vaultLibraryErrNested,
      VaultLibraryPathIssue.reserved => l10n.vaultLibraryErrReserved,
      VaultLibraryPathIssue.ok => '',
    };
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  static bool _isWithin(String root, String path) {
    final r = p.normalize(root.replaceAll('\\', '/'));
    final t = p.normalize(path.replaceAll('\\', '/'));
    return p.equals(r, t) || p.isWithin(r, t);
  }
}
