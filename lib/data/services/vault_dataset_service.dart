import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../core/constants.dart';
import '../../core/utils/app_logger.dart';
import '../db/database.dart';
import '../repositories/media_repository.dart';

/// 一次「导入保险库数据」的台账视图（数据来自 `vault_datasets` 表）。
///
/// `total` = 这次导入带进来的媒体记录数；`present` = 已经在本机确认存在的
/// 记录数（`vault_dataset_media.present = 1`）。两者之差就是
/// 「还没找到文件、因此不出现在私密相册里」的数量。
class VaultDatasetSummary {
  const VaultDatasetSummary({
    required this.id,
    required this.name,
    required this.archivePath,
    required this.archiveFile,
    required this.importedAt,
    required this.linkedPaths,
    required this.total,
    required this.present,
  });

  final String id;
  final String name;

  /// 导入时选择的数据目录（数据文件就在这里面）。
  final String archivePath;

  /// 数据文件名（例如 `privi-vault-20261110-101500.db`），老数据可能为空。
  final String? archiveFile;

  final DateTime importedAt;

  /// 用户为这份数据手动关联过的保险库路径（按关联顺序）。
  final List<String> linkedPaths;

  final int total;
  final int present;

  int get missing => total > present ? total - present : 0;

  bool get complete => total > 0 && missing == 0;
}

/// 一次「关联目录 / 重新扫描」的结果。
class VaultDatasetScanResult {
  const VaultDatasetScanResult({
    required this.directory,
    required this.pendingBefore,
    required this.linked,
    required this.presentCount,
  });

  /// 本次扫描的目录（`null` = 汇总多次扫描，见 [merge]）。
  final String? directory;

  /// 扫描前还没找到文件的记录数。
  final int pendingBefore;

  /// 本次新确认存在（台账从 present=0 翻成 1）的记录数。
  final int linked;

  /// 扫描后已经确认存在的记录总数。
  final int presentCount;

  VaultDatasetScanResult merge(VaultDatasetScanResult other) {
    return VaultDatasetScanResult(
      directory: null,
      pendingBefore: pendingBefore + other.pendingBefore,
      linked: linked + other.linked,
      presentCount: other.presentCount,
    );
  }
}

/// 一条导入记录在台账里的形态（写入 `vault_dataset_media` 用）。
class VaultDatasetMediaRecord {
  const VaultDatasetMediaRecord({
    required this.mediaId,
    required this.archivedPath,
    required this.isVideo,
    required this.rating,
    required this.inRecycle,
    required this.present,
  });

  final String mediaId;

  /// 导出手机上的私密路径（即磁盘上那个随机文件名的完整路径）。
  final String archivedPath;

  final bool isVideo;
  final int rating;
  final bool inRecycle;

  /// 导入这一刻是否已经在手机上找到文件。
  final bool present;
}

class _PendingFile {
  const _PendingFile({
    required this.mediaId,
    required this.archivedPath,
    required this.originalName,
    required this.hasDek,
  });

  final String mediaId;
  final String archivedPath;
  final String originalName;

  /// 这条记录带不带 DEK：带 DEK 的记录优先接管文件（见 [VaultDatasetService]）。
  final bool hasDek;
}

/// 某个文件当前被哪条记录占用。
class _FileOwner {
  const _FileOwner({required this.mediaId, required this.hasDek});

  final String mediaId;
  final bool hasDek;
}

/// 「保险库数据管理」的服务层（ADR-054）。
///
/// 导入「保险库数据」只恢复**记录**，媒体文件可能还没拷到这台手机。导入时
/// 没找到文件的记录会写进 `vault_dataset_media`（`present = 0`），因此不会
/// 出现在私密相册里；用户在这里手动关联保险库目录后，按**文件名**扫描该目录，
/// 找到一条就翻一条（`present = 1` 之后不再参与后续扫描）。
class VaultDatasetService {
  VaultDatasetService({
    required AppDatabase db,
    required MediaRepository media,
  })  : _db = db,
        _media = media;

  final AppDatabase _db;
  final MediaRepository _media;

  /// 同一次导入（同一个目录 + 同一个数据文件 + 同一个导出时间）得到同一个 id：
  /// 重复导入只会更新同一条台账，不会长出新条目。
  static String datasetIdFor({
    required String archivePath,
    String? archiveFile,
    DateTime? exportedAt,
  }) {
    final seed = <String>[
      p.normalize(archivePath.replaceAll('\\', '/')),
      archiveFile ?? '',
      exportedAt?.toUtc().toIso8601String() ?? '',
    ].join('|');
    final digest = sha256.convert(utf8.encode(seed)).toString();
    return 'ds_${digest.substring(0, 20)}';
  }

  /// 登记（或更新）一次导入。`linked_paths` 由用户关联目录时维护，这里不覆盖。
  Future<void> recordDataset({
    required String id,
    required String name,
    required String archivePath,
    String? archiveFile,
    DateTime? importedAt,
  }) async {
    await _db.customInsert(
      'INSERT INTO vault_datasets '
      '(id, name, archive_path, archive_file, imported_at, linked_paths) '
      'VALUES (?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(id) DO UPDATE SET '
      'name = excluded.name, '
      'archive_path = excluded.archive_path, '
      'archive_file = excluded.archive_file',
      variables: [
        Variable<String>(id),
        Variable<String>(name),
        Variable<String>(archivePath),
        Variable<String>(archiveFile ?? ''),
        Variable<int>(
          (importedAt ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
        ),
        Variable<String>('[]'),
      ],
    );
  }

  /// 记录一次导入里的媒体记录；`present` 只升不降（重复导入不会把已确认的
  /// 记录重新标成缺失）。
  Future<void> recordImportedRows(
    String datasetId,
    Iterable<VaultDatasetMediaRecord> rows,
  ) async {
    final list = rows.toList(growable: false);
    if (list.isEmpty) return;
    await _db.transaction(() async {
      for (final row in list) {
        await _db.customInsert(
          'INSERT INTO vault_dataset_media '
          '(dataset_id, media_id, archived_path, is_video, rating, in_recycle, '
          'present) VALUES (?, ?, ?, ?, ?, ?, ?) '
          'ON CONFLICT(dataset_id, media_id) DO UPDATE SET '
          'archived_path = excluded.archived_path, '
          'is_video = excluded.is_video, '
          'rating = excluded.rating, '
          'in_recycle = excluded.in_recycle, '
          'present = MAX(present, excluded.present)',
          variables: [
            Variable<String>(datasetId),
            Variable<String>(row.mediaId),
            Variable<String>(row.archivedPath),
            Variable<int>(row.isVideo ? 1 : 0),
            Variable<int>(row.rating),
            Variable<int>(row.inRecycle ? 1 : 0),
            Variable<int>(row.present ? 1 : 0),
          ],
        );
      }
    });
    AppLogger.i(
      'VaultDataset',
      'recorded ${list.length} row(s) for data set $datasetId '
          '(${list.where((row) => row.present).length} already located)',
    );
  }

  /// 所有导入过的保险库数据（新的在前）。
  Future<List<VaultDatasetSummary>> list() async {
    final rows = await _db
        .customSelect(
          'SELECT d.id, d.name, d.archive_path, d.archive_file, d.imported_at, '
          'd.linked_paths, '
          '(SELECT COUNT(*) FROM vault_dataset_media m '
          '  WHERE m.dataset_id = d.id) AS total, '
          '(SELECT COUNT(*) FROM vault_dataset_media m '
          '  WHERE m.dataset_id = d.id AND m.present = 1) AS present '
          'FROM vault_datasets d ORDER BY d.imported_at DESC, d.id',
        )
        .get();
    return [
      for (final row in rows)
        VaultDatasetSummary(
          id: row.read<String>('id'),
          name: row.read<String>('name'),
          archivePath: row.read<String>('archive_path'),
          archiveFile: _nullIfEmpty(row.read<String?>('archive_file')),
          importedAt: DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('imported_at'),
            isUtc: true,
          ).toLocal(),
          linkedPaths: _decodePaths(row.read<String?>('linked_paths')),
          total: row.read<int>('total'),
          present: row.read<int>('present'),
        ),
    ];
  }

  Future<VaultDatasetSummary?> find(String datasetId) async {
    for (final summary in await list()) {
      if (summary.id == datasetId) return summary;
    }
    return null;
  }

  /// 手动关联一个保险库目录，并立刻扫描一次。
  ///
  /// 只处理 `present = 0` 的记录（已经确认存在的记录不再参与判断）：在目录里
  /// 按文件名给它们找文件，找到就改指向并把台账翻成 `present = 1`。之后再关联
  /// 别的目录时，之前找到过的记录不会被重新判断。
  Future<VaultDatasetScanResult> linkDirectory(
    String datasetId,
    String directory,
  ) async {
    final normalized = p.normalize(directory.replaceAll('\\', '/'));
    final pending = await _pendingFiles(datasetId);
    final presentBefore = await _countPresent(datasetId);
    if (pending.isEmpty) {
      await _rememberLinkedPath(datasetId, normalized);
      return VaultDatasetScanResult(
        directory: normalized,
        pendingBefore: 0,
        linked: 0,
        presentCount: presentBefore,
      );
    }

    final dir = Directory(normalized);
    if (!await dir.exists()) {
      AppLogger.w(
        'VaultDataset',
        'link scan skipped, directory missing: $normalized',
      );
      return VaultDatasetScanResult(
        directory: normalized,
        pendingBefore: pending.length,
        linked: 0,
        presentCount: presentBefore,
      );
    }

    // 只索引「可能是待关联记录」的文件名，避免把整个相册目录全量读进内存。
    final wanted = <String>{};
    for (final entry in pending) {
      final archivedName = p.basename(entry.archivedPath);
      if (archivedName.isNotEmpty) wanted.add(archivedName);
      final originalName = p.basename(entry.originalName);
      if (originalName.isNotEmpty) wanted.add(originalName);
    }
    final index = await _indexFiles(dir, wanted);
    final owners = await _fileOwners();
    final staleIds = <String>{};

    var linked = 0;
    for (final entry in pending) {
      final candidates = <String>[
        p.basename(entry.archivedPath),
        p.basename(entry.originalName),
      ];
      String? match;
      for (final name in candidates) {
        final paths = index[name];
        if (paths == null || paths.isEmpty) continue;
        for (final path in paths) {
          if (staleIds.contains(owners[path]?.mediaId)) continue;
          final owner = owners[path];
          if (owner == null) {
            match = path;
            break;
          }
          // 这个文件已经被别的记录占用。孤儿扫描会先给拷进来的密文建一条
          // **没有 DEK** 的记录；带 DEK 的导入记录必须接管它，否则那条带密钥
          // 的记录永远连不上、而可见的那条又解不开（`ISSUE-050` 同型问题）。
          if (!owner.hasDek && entry.hasDek) {
            staleIds.add(owner.mediaId);
            match = path;
            break;
          }
        }
        if (match != null) break;
      }
      if (match == null) continue;
      owners[match] = _FileOwner(mediaId: entry.mediaId, hasDek: entry.hasDek);
      await _db.updateMediaPrivatePath(entry.mediaId, match);
      // 旧手机上的缩略图路径在这台手机上无效，清掉让网格重新生成。
      await _db.updateMediaThumbnail(entry.mediaId, null);
      await _markPresent(datasetId, entry.mediaId);
      linked++;
    }
    if (staleIds.isNotEmpty) {
      await _media.hardDeleteRowsOnly(staleIds.toList(growable: false));
      AppLogger.w(
        'VaultDataset',
        'replaced ${staleIds.length} stale row(s) that shared a file with the '
            'imported data',
      );
    }

    await _rememberLinkedPath(datasetId, normalized);
    final presentAfter = await _countPresent(datasetId);
    AppLogger.i(
      'VaultDataset',
      'linked $linked/${pending.length} row(s) under $normalized '
          '(data set $datasetId, $presentAfter confirmed present)',
    );
    return VaultDatasetScanResult(
      directory: normalized,
      pendingBefore: pending.length,
      linked: linked,
      presentCount: presentAfter,
    );
  }

  /// 重新扫描这份数据关联过的全部目录（仍然缺文件的记录才参与）。
  Future<VaultDatasetScanResult> rescan(String datasetId) async {
    final summary = await find(datasetId);
    if (summary == null) {
      return const VaultDatasetScanResult(
        directory: null,
        pendingBefore: 0,
        linked: 0,
        presentCount: 0,
      );
    }
    var result = VaultDatasetScanResult(
      directory: null,
      pendingBefore: 0,
      linked: 0,
      presentCount: summary.present,
    );
    for (final path in summary.linkedPaths) {
      result = result.merge(await linkDirectory(datasetId, path));
    }
    return result;
  }

  /// 移除一份导入台账：**待关联（缺文件）的记录会被删掉**，已经确认存在的
  /// 媒体记录保留在私密相册里（磁盘文件一律不动）。
  Future<int> deleteDataset(String datasetId) async {
    final pendingIds = await _pendingMediaIds(datasetId);
    if (pendingIds.isNotEmpty) {
      await _media.hardDeleteRowsOnly(pendingIds);
    }
    await _db.customUpdate(
      'DELETE FROM vault_dataset_media WHERE dataset_id = ?',
      variables: [Variable<String>(datasetId)],
    );
    await _db.customUpdate(
      'DELETE FROM vault_datasets WHERE id = ?',
      variables: [Variable<String>(datasetId)],
    );
    AppLogger.i(
      'VaultDataset',
      'removed data set $datasetId (${pendingIds.length} pending row(s) '
          'dropped, confirmed rows kept)',
    );
    return pendingIds.length;
  }

  Future<List<_PendingFile>> _pendingFiles(String datasetId) async {
    final rows = await _db.customSelect(
      "SELECT m.media_id, m.archived_path, i.original_name, "
      "COALESCE(i.encrypted_dek, '') AS encrypted_dek "
      'FROM vault_dataset_media m '
      'JOIN media_items i ON i.id = m.media_id '
      'WHERE m.dataset_id = ? AND m.present = 0',
      variables: [Variable<String>(datasetId)],
    ).get();
    return [
      for (final row in rows)
        _PendingFile(
          mediaId: row.read<String>('media_id'),
          archivedPath: row.read<String>('archived_path'),
          originalName: row.read<String>('original_name'),
          hasDek: row.read<String>('encrypted_dek').isNotEmpty,
        ),
    ];
  }

  /// private_path → 当前占用它的记录（用于避免两条记录指向同一个文件）。
  Future<Map<String, _FileOwner>> _fileOwners() async {
    final rows = await _db
        .customSelect(
          "SELECT id, private_path, COALESCE(encrypted_dek, '') AS encrypted_dek "
          'FROM media_items',
        )
        .get();
    return {
      for (final row in rows)
        p.normalize(row.read<String>('private_path')): _FileOwner(
          mediaId: row.read<String>('id'),
          hasDek: row.read<String>('encrypted_dek').isNotEmpty,
        ),
    };
  }

  Future<List<String>> _pendingMediaIds(String datasetId) async {
    final rows = await _db.customSelect(
      'SELECT media_id FROM vault_dataset_media '
      'WHERE dataset_id = ? AND present = 0',
      variables: [Variable<String>(datasetId)],
    ).get();
    return [for (final row in rows) row.read<String>('media_id')];
  }

  /// 导入失败/取消时把「一条记录都没有、只剩空台账」的数据集删掉，避免列表里出现
  /// 0 项的空条目。已经有记录时不动（部分导入仍然要保留）。
  Future<void> discardIfEmpty(String datasetId) async {
    final row = await _db.customSelect(
      'SELECT COUNT(*) AS c FROM vault_dataset_media WHERE dataset_id = ?',
      variables: [Variable<String>(datasetId)],
    ).getSingle();
    if ((row.read<int>('c')) > 0) return;
    await _db.customUpdate(
      'DELETE FROM vault_datasets WHERE id = ?',
      variables: [Variable<String>(datasetId)],
    );
  }

  Future<int> _countPresent(String datasetId) async {
    final row = await _db.customSelect(
      'SELECT COUNT(*) AS c FROM vault_dataset_media '
      'WHERE dataset_id = ? AND present = 1',
      variables: [Variable<String>(datasetId)],
    ).getSingle();
    return row.read<int>('c');
  }

  Future<void> _markPresent(String datasetId, String mediaId) async {
    await _db.customUpdate(
      'UPDATE vault_dataset_media SET present = 1 '
      'WHERE dataset_id = ? AND media_id = ?',
      variables: [
        Variable<String>(datasetId),
        Variable<String>(mediaId),
      ],
    );
  }

  Future<void> _rememberLinkedPath(String datasetId, String path) async {
    final row = await _db.customSelect(
      'SELECT linked_paths FROM vault_datasets WHERE id = ?',
      variables: [Variable<String>(datasetId)],
    ).getSingleOrNull();
    if (row == null) return;
    final paths = _decodePaths(row.read<String?>('linked_paths'));
    final normalized = p.normalize(path.replaceAll('\\', '/'));
    if (paths.any((existing) => p.equals(existing, normalized))) return;
    paths.add(normalized);
    await _db.customUpdate(
      'UPDATE vault_datasets SET linked_paths = ? WHERE id = ?',
      variables: [
        Variable<String>(jsonEncode(paths)),
        Variable<String>(datasetId),
      ],
    );
  }

  /// basename → 目录下的绝对路径（只收 [wanted] 里的名字）。
  Future<Map<String, List<String>>> _indexFiles(
    Directory root,
    Set<String> wanted,
  ) async {
    final index = <String, List<String>>{};
    if (wanted.isEmpty) return index;
    try {
      await for (final entity
          in root.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final path = entity.path;
        if (_isScratchPath(path)) continue;
        final name = p.basename(path);
        if (!wanted.contains(name)) continue;
        (index[name] ??= <String>[]).add(p.normalize(path));
      }
    } catch (e) {
      AppLogger.w('VaultDataset', 'scan ${root.path} failed: $e');
    }
    for (final paths in index.values) {
      paths.sort();
    }
    return index;
  }

  static bool _isScratchPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    return normalized.contains('/${VaultPaths.stagingDir}/') ||
        normalized.contains('/${VaultPaths.shareStagingDir}/') ||
        normalized.contains('/${VaultPaths.thumbsDir}/');
  }

  static String? _nullIfEmpty(String? value) =>
      value == null || value.trim().isEmpty ? null : value;

  static List<String> _decodePaths(Object? raw) {
    if (raw is! String || raw.isEmpty) return <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>[];
      return [
        for (final entry in decoded)
          if (entry is String && entry.isNotEmpty) entry,
      ];
    } catch (_) {
      return <String>[];
    }
  }
}
