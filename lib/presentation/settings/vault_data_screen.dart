import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../application/providers.dart';
import '../../core/constants.dart';
import '../../core/l10n.dart';
import '../../core/utils/app_logger.dart';
import '../../data/services/vault_dataset_service.dart';
import '../../data/services/vault_library_registry.dart';

/// Settings → 保险库数据管理.
///
/// 每一份「导入的保险库数据」在这里都有一条台账：记录数、已经确认存在的
/// 数量、还缺多少，以及用户手动关联过的保险库路径。
///
/// 导入时**不校验**文件是否存在（`ADR-054`）：找不到文件的记录先不出现在
/// 私密相册里。用户在这里「关联保险库路径」后立刻扫描该目录，按文件名把
/// 还没定位的记录接上；之后再关联别的目录时，已经确认存在的记录不再参与扫描。
class VaultDataScreen extends ConsumerStatefulWidget {
  const VaultDataScreen({super.key});

  @override
  ConsumerState<VaultDataScreen> createState() => _VaultDataScreenState();
}

class _VaultDataScreenState extends ConsumerState<VaultDataScreen> {
  bool _busy = false;
  bool _loading = true;
  List<VaultDatasetSummary> _datasets = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  Future<void> _reload() async {
    try {
      final datasets = await ref.read(vaultDatasetServiceProvider).list();
      if (!mounted) return;
      setState(() {
        _datasets = datasets;
        _loading = false;
      });
    } catch (e, stackTrace) {
      AppLogger.e('VaultDataScreen', 'load: $e\n$stackTrace');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 扫描完成后刷新台账与私密相册。
  ///
  /// 相册列表是 drift 的流，可见性却来自 `vault_dataset_media` 台账 ⇒ 必须
  /// 重新订阅（`invalidate`）才会按新的 `present` 重新过滤。
  Future<void> _refreshAfterScan() async {
    await _reload();
    if (!mounted) return;
    ref.invalidate(vaultSizeBytesProvider);
    ref.invalidate(albumsProvider);
    ref.invalidate(albumMediaProvider);
  }

  Future<void> _linkDirectory(VaultDatasetSummary dataset) async {
    final l10n = context.l10n;
    final picker = ref.read(vaultBackupDirectoryPickerProvider);
    String? picked;
    try {
      picked = await picker(l10n.vaultDataLinkPath);
    } catch (e, stackTrace) {
      AppLogger.e('VaultDataScreen', 'pick directory: $e\n$stackTrace');
      _snack(l10n.vaultLibraryOperationFailed);
      return;
    }
    if (picked == null || !mounted) return;

    setState(() => _busy = true);
    try {
      final storage = ref.read(vaultStorageProvider);
      final check = await storage.validateLibraryPath(picked);
      if (!mounted) return;
      // 「已经登记为保险库」不是错误：这条路径本来就在保险库里，直接扫描
      // （`validateLibraryPath` 的 duplicate 分支不返回 normalizedPath）。
      final String normalized;
      if (check.ok) {
        normalized = check.normalizedPath!;
      } else if (check.issue == VaultLibraryPathIssue.duplicate) {
        normalized = p.normalize(picked.replaceAll('\\', '/'));
      } else {
        _snack(_messageFor(check.issue, l10n));
        return;
      }

      final registry = ref.read(vaultLibraryRegistryProvider);
      if (!registry.ownsPath(normalized)) {
        await registry.add(path: normalized, name: p.basename(normalized));
        // 让 MediaScanner 忽略这个保险库目录（与「保险库管理」添加时一致）。
        await storage.prepareLibraryDirectory(normalized);
      }

      final result = await ref
          .read(vaultDatasetServiceProvider)
          .linkDirectory(dataset.id, normalized);
      if (!mounted) return;
      await _refreshAfterScan();
      if (!mounted) return;
      final updated = _summaryOf(dataset.id);
      _snack(l10n.vaultDataScanDone(result.linked, updated?.missing ?? 0));
    } catch (e, stackTrace) {
      AppLogger.e('VaultDataScreen', 'link directory: $e\n$stackTrace');
      if (mounted) _snack(l10n.vaultLibraryOperationFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rescan(VaultDatasetSummary dataset) async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      final result =
          await ref.read(vaultDatasetServiceProvider).rescan(dataset.id);
      if (!mounted) return;
      await _refreshAfterScan();
      if (!mounted) return;
      final updated = _summaryOf(dataset.id);
      _snack(l10n.vaultDataScanDone(result.linked, updated?.missing ?? 0));
    } catch (e, stackTrace) {
      AppLogger.e('VaultDataScreen', 'rescan: $e\n$stackTrace');
      if (mounted) _snack(l10n.vaultLibraryOperationFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(VaultDatasetSummary dataset) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.vaultDataRemoveTitle),
        content: Text(l10n.vaultDataRemoveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const ValueKey('vault-data-remove-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.vaultDataRemove),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final removed =
          await ref.read(vaultDatasetServiceProvider).deleteDataset(dataset.id);
      if (!mounted) return;
      await _refreshAfterScan();
      if (mounted) _snack(l10n.vaultDataRemoved(removed));
    } catch (e, stackTrace) {
      AppLogger.e('VaultDataScreen', 'remove data set: $e\n$stackTrace');
      if (mounted) _snack(l10n.vaultLibraryOperationFailed);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  VaultDatasetSummary? _summaryOf(String id) {
    for (final dataset in _datasets) {
      if (dataset.id == id) return dataset;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.vaultDataManagement)),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Text(
                  l10n.vaultDataManagementSubtitle,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  l10n.vaultDataScanHint,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                ),
              if (!_loading && _datasets.isEmpty)
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: Text(l10n.vaultDataEmpty),
                  subtitle: Text(l10n.vaultDataEmptyHint),
                ),
              for (final dataset in _datasets) _datasetCard(dataset, l10n),
            ],
          ),
          if (_busy) ...[
            const ModalBarrier(dismissible: false, color: Colors.black26),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }

  Widget _datasetCard(VaultDatasetSummary dataset, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.xs,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _datasetHeader(dataset, l10n, theme),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l10n.vaultDataCounts(
                dataset.total,
                dataset.present,
                dataset.missing,
              ),
              style: theme.textTheme.bodyMedium,
            ),
            Text(
              '${l10n.vaultDataArchiveLocation}: '
              '${dataset.archiveFile ?? dataset.archivePath}',
              style: theme.textTheme.bodySmall,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.xs),
            ..._linkedPathLines(dataset, l10n, theme),
            if (dataset.missing > 0) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.vaultDataMissingHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.tertiary,
                ),
              ),
            ],
            Wrap(
              alignment: WrapAlignment.end,
              spacing: AppSpacing.xs,
              children: [
                TextButton.icon(
                  key: ValueKey('vault-data-link-${dataset.id}'),
                  onPressed:
                      _busy ? null : () => unawaited(_linkDirectory(dataset)),
                  icon: const Icon(Icons.folder_open_outlined),
                  label: Text(l10n.vaultDataLinkPath),
                ),
                if (dataset.linkedPaths.isNotEmpty)
                  TextButton.icon(
                    key: ValueKey('vault-data-rescan-${dataset.id}'),
                    onPressed: _busy ? null : () => unawaited(_rescan(dataset)),
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.vaultDataRescan),
                  ),
                TextButton.icon(
                  key: ValueKey('vault-data-remove-${dataset.id}'),
                  onPressed: _busy ? null : () => unawaited(_remove(dataset)),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l10n.vaultDataRemove),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _datasetHeader(
    VaultDatasetSummary dataset,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          dataset.complete
              ? Icons.verified_outlined
              : Icons.pending_actions_outlined,
          color: dataset.complete
              ? theme.colorScheme.primary
              : theme.colorScheme.tertiary,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(dataset.name, style: theme.textTheme.titleMedium),
              Text(
                l10n.vaultDataImportedAt(_formatDate(dataset.importedAt)),
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _linkedPathLines(
    VaultDatasetSummary dataset,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    if (dataset.linkedPaths.isEmpty) {
      return [
        Text(l10n.vaultDataNoLinkedPath, style: theme.textTheme.bodySmall),
      ];
    }
    return [
      Text(l10n.vaultDataLinkedPaths, style: theme.textTheme.labelSmall),
      for (final path in dataset.linkedPaths)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Row(
            children: [
              Icon(
                Icons.folder_outlined,
                size: 14,
                color: theme.textTheme.bodySmall?.color,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  path,
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
    ];
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
    if (!mounted || message.isEmpty) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
