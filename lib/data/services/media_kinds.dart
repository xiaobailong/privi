import 'package:path/path.dart' as p;

import 'hide_naming.dart';

/// Single source of truth for "is this file an image or a video?".
///
/// Vault files keep their original name (and therefore their extension) — the
/// legacy `.img.pg` / `.vid.pg` markers are only a fallback — so the container
/// extension is the only signal available for legacy rows that were imported
/// before the sniffing table covered their format.
///
/// A too narrow table is not cosmetic: anything unknown fell back to
/// `image/jpeg`, so a real video (`.ts`, `.wmv`, `.rmvb`, `.flv`, …) was filed
/// as a *photo* and could never be recognised or played as a video.
abstract final class MediaKinds {
  static const String imageMime = 'image/jpeg';

  /// Fallback mime for a video file with an unknown container.
  static const String videoMime = 'video/mp4';

  /// Lower-case extension → mime type for every container the app can hide,
  /// play (ExoPlayer sniffs the container itself) or restore.
  ///
  /// Invariant: a video entry must carry a `video/` mime and an image entry an
  /// `image/` one. The stored mime is not decoration — the whole app derives the
  /// kind from that prefix (`hide_preparer`, `_repairMediaKinds`) and the Android
  /// side keys off it too (`VaultFileHandler.createExternalPlayerIntent` targets
  /// VLC only for `video/`, `ExternalPlayerHandler` reads the duration only for
  /// `video/`, and an `application/*` type does not resolve against the
  /// `video/*` intent filters players declare).
  static const Map<String, String> extensionMime = {
    // Images
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.jpe': 'image/jpeg',
    '.png': 'image/png',
    '.gif': 'image/gif',
    '.bmp': 'image/bmp',
    '.webp': 'image/webp',
    '.heic': 'image/heic',
    '.heif': 'image/heif',
    '.avif': 'image/avif',
    '.dng': 'image/x-adobe-dng',
    // Videos
    '.mp4': 'video/mp4',
    '.m4v': 'video/mp4',
    '.mov': 'video/quicktime',
    '.mkv': 'video/x-matroska',
    '.webm': 'video/webm',
    '.avi': 'video/x-msvideo',
    '.3gp': 'video/3gpp',
    '.3g2': 'video/3gpp2',
    '.3gpp': 'video/3gpp',
    '.ts': 'video/mp2t',
    '.m2ts': 'video/mp2t',
    '.mts': 'video/mp2t',
    '.mpg': 'video/mpeg',
    '.mpeg': 'video/mpeg',
    '.m2v': 'video/mpeg',
    '.vob': 'video/mpeg',
    '.wmv': 'video/x-ms-wmv',
    '.asf': 'video/x-ms-asf',
    '.flv': 'video/x-flv',
    '.f4v': 'video/x-f4v',
    '.ogv': 'video/ogg',
    '.divx': 'video/divx',
    '.dv': 'video/dv',
    // RealMedia is registered as `application/vnd.rn-realmedia*`; keeping that
    // spelling would re-introduce the very bug this table exists to fix, because
    // the prefix-based kind check would file `.rm` / `.rmvb` as photos.
    '.rm': 'video/vnd.rn-realmedia',
    '.rmvb': 'video/vnd.rn-realmedia-vbr',
  };

  /// Lower-case extension of [pathOrName], legacy hide markers stripped.
  static String extensionOf(String pathOrName) =>
      p.extension(HideNaming.toVisiblePath(pathOrName)).toLowerCase();

  /// Mime type for [pathOrName], or null when the extension is unknown.
  static String? mimeFor(String pathOrName) =>
      extensionMime[extensionOf(pathOrName)];

  static bool isKnown(String pathOrName) => mimeFor(pathOrName) != null;

  static bool isVideoName(String pathOrName) =>
      (mimeFor(pathOrName) ?? '').startsWith('video/');

  static bool isImageName(String pathOrName) =>
      (mimeFor(pathOrName) ?? '').startsWith('image/');

  /// Resolves the mime type of a hidden source file.
  ///
  /// A platform provided media mime wins; otherwise the extension decides and
  /// unknown extensions fall back to [imageMime] (previous behaviour).
  static String resolveMime({String? provided, required String pathOrName}) {
    if (provided != null &&
        (provided.startsWith('image/') || provided.startsWith('video/'))) {
      return provided;
    }
    return mimeFor(pathOrName) ?? imageMime;
  }
}
