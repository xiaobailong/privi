import 'package:photo_manager/photo_manager.dart';

import '../../data/services/import/import_models.dart';

/// Platform read seam for the system media library.
///
/// The returned asset IDs are opaque platform identities. A path returned in
/// [resolveForHide] is transient materialization input and must not be stored
/// as the identity of a Photos asset.
final class VisibleLibraryCapabilities {
  const VisibleLibraryCapabilities({
    required this.includesAllCollection,
    required this.showsLimitedAccessNotice,
  });

  /// Whether the platform exposes a useful virtual All/Recents collection.
  final bool includesAllCollection;

  /// Whether a limited authorization state has a user-visible meaning here.
  final bool showsLimitedAccessNotice;
}

abstract interface class VisibleLibrary {
  VisibleLibraryCapabilities get capabilities;

  Future<PermissionState> requestPermission();

  Future<PermissionState> permissionState();

  Future<void> openSettings();

  /// Every image/video collection the platform exposes (images + videos).
  Future<List<AssetPathEntity>> paths();

  Future<int> assetCount(AssetPathEntity path);

  /// Reads one raw page from a platform collection. The caller owns any
  /// platform-specific type filtering and logical pagination.
  Future<List<AssetEntity>> assetPage(
    AssetPathEntity path, {
    required int page,
    required int size,
  });

  Future<ImportSource?> resolveForHide(
    String assetId, {
    String? sourceFolderName,
  });
}
