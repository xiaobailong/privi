import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../data/services/gallery_service.dart';
import '../providers.dart';

export '../../data/services/gallery_service.dart'
    show
        GalleryAsset,
        GalleryFolder,
        VisibleFilterChanged,
        VisibleHidden,
        VisiblePermissionChanged,
        VisibleRevealed;

final galleryServiceProvider = Provider<GalleryService>((ref) {
  final service = GalleryService(
    assetGateway: ref.watch(assetGatewayProvider),
    thumbnailCache: ref.watch(mediaThumbnailCacheProvider),
    library: ref.watch(visibleLibraryProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// A single mutation stream replaces caller-managed epoch bumping.
final galleryChangeProvider = StreamProvider.autoDispose<int>((ref) {
  return ref.watch(galleryServiceProvider).changes;
});

/// Visible-tab folder list (images + videos together).
///
/// Uses MediaStore counts and the [VisibleLibraryState] mutation stream.
final galleryFoldersProvider =
    FutureProvider.autoDispose<List<GalleryFolder>>((ref) async {
  ref.watch(galleryChangeProvider);
  final gallery = ref.watch(galleryServiceProvider);
  final ok = await gallery.hasPermission();
  if (!ok) {
    final state = await gallery.requestPermission();
    if (!(state.isAuth || state.hasAccess)) {
      return const [];
    }
  }
  // Cold-start: subtract vault private paths so counts match after restart.
  // Cached until the Visible state receives a hide/reveal mutation.
  await gallery.ensureVaultHydrated(
    () => ref.read(mediaRepositoryProvider).listActiveOriginalPaths(),
  );
  return gallery.listFolders();
});

/// Assets inside a gallery folder (metadata only; thumbs lazy).
final galleryAssetsProvider = FutureProvider.autoDispose
    .family<List<GalleryAsset>, String>((ref, pathId) async {
  ref.watch(galleryChangeProvider);
  final gallery = ref.watch(galleryServiceProvider);
  await gallery.ensureVaultHydrated(
    () => ref.read(mediaRepositoryProvider).listActiveOriginalPaths(),
  );
  return gallery.listAssets(pathId: pathId);
});

final galleryPermissionProvider =
    FutureProvider.autoDispose<PermissionState>((ref) {
  return ref.watch(galleryServiceProvider).permissionState();
});
