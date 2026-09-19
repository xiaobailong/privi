import '../enums.dart';

/// Domain album (system or user). See docs/03-architecture/data-model.md.
class Album {
  const Album({
    required this.id,
    required this.name,
    required this.isSystem,
    required this.createdAt,
    this.coverMediaId,
    this.systemKind,
    this.pinnedAt,
    this.rating = 0,
    this.sortIndex,
    this.groupId,
  });

  final String id;
  final String name;
  final bool isSystem;
  final String? coverMediaId;
  final DateTime createdAt;
  final SystemAlbumKind? systemKind;

  /// Non-null when pinned to the top of the Invisible mosaic.
  final DateTime? pinnedAt;
  final int rating;
  final int? sortIndex;
  final String? groupId;

  bool get isPinned => pinnedAt != null;
}

/// Stable IDs for the three system albums (seeded once).
abstract final class SystemAlbumIds {
  static const all = 'sys-all-media';
  static const favorites = 'sys-favorites';
  static const recycle = 'sys-recycle-bin';
}

/// Canonical names of the three system albums (seeded once).
///
/// Plain literals on purpose: the value is persisted in the database and is
/// not resolved through l10n. They match the allMedia, favorites and
/// recycleBin getters of lib/l10n/app_localizations.dart.
abstract final class SystemAlbumNames {
  static const all = '全部媒体';
  static const favorites = '收藏';
  static const recycle = '回收站';
}
