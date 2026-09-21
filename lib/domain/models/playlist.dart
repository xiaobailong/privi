import 'dart:math' as math;

import 'media_item.dart';

/// In-memory playlist for album/Favorites playback.
/// See docs/03-architecture/playback.md.
///
/// Shuffle can be weighted by the per-item play counter: the more often an
/// item was played, the lower its odds, and items past [skipThreshold] are
/// pushed to the end of the random order.
class Playlist {
  Playlist({
    required List<MediaItem> items,
    this.shuffle = false,
    int cursor = 0,
    Map<String, int> playCounts = const <String, int>{},
    this.skipThreshold = 0,
  })  : items = List.unmodifiable(items),
        _playCounts = Map.unmodifiable(playCounts),
        _order = List.generate(items.length, (i) => i),
        cursor = cursor.clamp(0, items.isEmpty ? 0 : items.length - 1) {
    if (shuffle) _reshuffle(keepCurrent: false);
  }

  /// Fresh mutable copy sharing the (unmodifiable) item list.
  ///
  /// Player state snapshots must never alias each other: every published
  /// state owns its own cursor, otherwise a listener diffing two consecutive
  /// states sees no change at all and misses the item switch.
  Playlist copy() => Playlist._(
        items: items,
        order: _order,
        shuffle: shuffle,
        cursor: cursor,
        playCounts: _playCounts,
        skipThreshold: skipThreshold,
      );

  Playlist._({
    required this.items,
    required List<int> order,
    required this.shuffle,
    required this.cursor,
    required Map<String, int> playCounts,
    required this.skipThreshold,
  })  : _order = List.of(order),
        _playCounts = playCounts;

  final List<MediaItem> items;
  final List<int> _order;
  bool shuffle;
  int cursor;

  /// Play counts keyed by media id. Empty means "no history known", which
  /// turns [_reshuffle] back into a plain uniform shuffle.
  final Map<String, int> _playCounts;

  /// Items played at least this often are parked at the end of the random
  /// order. 0 disables the push.
  final int skipThreshold;

  bool get isEmpty => items.isEmpty;
  int get length => items.length;

  MediaItem? get current {
    if (items.isEmpty) return null;
    return items[_order[cursor.clamp(0, _order.length - 1)]];
  }

  int get positionDisplay => items.isEmpty ? 0 : cursor + 1;

  bool get hasNext => cursor < _order.length - 1;
  bool get hasPrev => cursor > 0;

  void toggleShuffle() {
    shuffle = !shuffle;
    if (shuffle) {
      _reshuffle(keepCurrent: true);
    } else {
      // Restore natural order, keep current item under cursor if possible.
      final curId = current?.id;
      _order
        ..clear()
        ..addAll(List.generate(items.length, (i) => i));
      if (curId != null) {
        final idx = items.indexWhere((e) => e.id == curId);
        if (idx >= 0) cursor = idx;
      }
    }
  }

  void next() {
    if (hasNext) cursor++;
  }

  /// Next item without moving the cursor (for video preload).
  MediaItem? peekNext() {
    if (!hasNext) return null;
    return items[_order[cursor + 1]];
  }

  void prev() {
    if (hasPrev) cursor--;
  }

  void jumpToItemId(String id) {
    final itemIndex = items.indexWhere((e) => e.id == id);
    if (itemIndex < 0) return;
    final orderIndex = _order.indexOf(itemIndex);
    if (orderIndex >= 0) cursor = orderIndex;
  }

  void _reshuffle({required bool keepCurrent}) {
    final curId = keepCurrent ? current?.id : null;
    _order
      ..clear()
      ..addAll(_weightedOrder());
    cursor = 0;
    if (curId != null) {
      final itemIndex = items.indexWhere((e) => e.id == curId);
      final orderIndex = _order.indexOf(itemIndex);
      if (orderIndex > 0) {
        _order.removeAt(orderIndex);
        _order.insert(0, itemIndex);
      }
    }
  }

  /// Item indexes in weighted-random order.
  ///
  /// Every eligible item draws `key = -ln(U) / weight`; sorting the keys
  /// ascending samples without replacement with probability proportional to the
  /// weights (Efraimidis–Spirakis). A zero weight gives an infinite key, which
  /// parks the "used up" items at the very end of the random order.
  List<int> _weightedOrder() {
    final random = math.Random();
    if (_playCounts.isEmpty) {
      return List<int>.generate(items.length, (i) => i)..shuffle(random);
    }

    final picked = <int>[];
    final keys = <double>[];
    final skipped = <int>[];
    for (var index = 0; index < items.length; index++) {
      final weight = _weightFor(items[index]);
      if (weight <= 0) {
        skipped.add(index);
        continue;
      }
      picked.add(index);
      keys.add(-math.log(_uniform(random)) / weight);
    }

    if (picked.isEmpty) {
      // Every item reached the skip threshold: fall back to the softened
      // weighting so a long-running playlist never runs dry.
      for (final index in skipped) {
        picked.add(index);
        keys.add(
          -math.log(_uniform(random)) /
              _weightFor(items[index], ignoreSkip: true),
        );
      }
      skipped.clear();
    }

    final ranked = List<int>.generate(picked.length, (i) => i)
      ..sort((a, b) => keys[a].compareTo(keys[b]));
    return [
      for (final rank in ranked) picked[rank],
      ...skipped,
    ];
  }

  /// `U` in `(0, 1]` keeps `ln(U)` finite.
  static double _uniform(math.Random random) => 1 - random.nextDouble();

  /// Play-count weight `1 / (1 + plays)^2`: a never-played item draws nine
  /// times the odds of one that was played twice.
  double _weightFor(MediaItem item, {bool ignoreSkip = false}) {
    final plays = _playCounts[item.id] ?? 0;
    if (plays <= 0) return 1;
    if (!ignoreSkip && skipThreshold > 0 && plays >= skipThreshold) return 0;
    final base = 1 + plays;
    return 1 / (base * base);
  }
}
