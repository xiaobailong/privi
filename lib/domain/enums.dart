// Domain enums. See docs/03-architecture/data-model.md and security.md.

/// Tags for the three always-present system albums.
enum SystemAlbumKind {
  all('all'),
  favorites('favorites'),
  recycle('recycle');

  const SystemAlbumKind(this.storageValue);
  final String storageValue;

  static SystemAlbumKind? fromStorage(String? value) {
    if (value == null) return null;
    for (final k in SystemAlbumKind.values) {
      if (k.storageValue == value) return k;
    }
    return null;
  }
}

/// App lock gate state.
enum LockStatus {
  /// Pattern (or legacy PIN) not yet configured — show setup flow.
  needsSetup,

  /// Vault is locked; require pattern (or biometric if enabled).
  locked,

  /// Vault is unlocked for this session.
  unlocked,
}

/// Sort criteria for Invisible media grids (multi-select, ordered).
enum MediaSort {
  dateAddedDesc,
  dateAddedAsc,
  nameAsc,
  nameDesc,
  ratingDesc,
  ratingAsc,
}

/// Sort criteria for the Invisible home album shelf.
enum AlbumSort {
  createdAtDesc,
  createdAtAsc,
  nameAsc,
  nameDesc,
  ratingDesc,
  ratingAsc,
  custom,
}

enum AlbumViewMode { mosaic, list }

/// Rating filter for Invisible grids (`null` / all = no filter).
enum RatingFilter {
  all,
  unrated,
  hearts1,
  hearts2,
  hearts3,
  favorites,
}

/// Type of a private (user) album: photos-only or videos-only.
///
/// Persisted per album in user preferences, so system albums and albums created
/// before typing stay untyped (`AlbumKindPreferences.kindOf` == null) and keep
/// mixing images and videos.
enum AlbumKind {
  image,
  video;

  /// True when a media item of the given kind fits this album type.
  bool matches({required bool isVideo}) => isVideo == (this == AlbumKind.video);
}

/// How random playback reacts to the per-item play counter.
///
/// The counter is bumped every time an item is played (viewer / player); the
/// shuffle order is weighted by it so the same items stop coming back.
enum ShufflePlayCountMode {
  /// Plain uniform shuffle, play counter ignored.
  off,

  /// Weighted shuffle: the more often an item was played, the lower its odds.
  soften,

  /// Weighted shuffle that pushes used-up items (`playCount` >= threshold) to
  /// the end of the random order, so they effectively stop appearing.
  skip;

  static ShufflePlayCountMode fromStorage(String? value) {
    for (final mode in ShufflePlayCountMode.values) {
      if (mode.name == value) return mode;
    }
    return ShufflePlayCountMode.soften;
  }
}

/// Play counts offered as the "stop appearing" threshold for
/// [ShufflePlayCountMode.skip].
const shuffleSkipThresholdOptions = <int>[3, 5, 10, 20];
