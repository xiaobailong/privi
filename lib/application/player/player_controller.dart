import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/app_logger.dart';
import '../../domain/models/media_item.dart';
import '../../domain/models/playlist.dart';
import '../settings/settings_controller.dart';
import 'external_player_coordinator.dart';
import 'external_player_gateway.dart';

class PlayerUiState {
  const PlayerUiState({
    this.playlist,
    this.playing = false,
    this.externalHandedOff = false,
  });

  final Playlist? playlist;
  final bool playing;
  final bool externalHandedOff;

  MediaItem? get current => playlist?.current;

  PlayerUiState copyWith({
    Playlist? playlist,
    bool? playing,
    bool? externalHandedOff,
  }) {
    return PlayerUiState(
      playlist: playlist ?? this.playlist,
      playing: playing ?? this.playing,
      externalHandedOff: externalHandedOff ?? this.externalHandedOff,
    );
  }
}

class PlayerController extends Notifier<PlayerUiState> {
  Timer? _slideTimer;

  @override
  PlayerUiState build() {
    ref.onDispose(() => _slideTimer?.cancel());
    return const PlayerUiState();
  }

  void start({
    required List<MediaItem> items,
    bool? shuffle,
    String? startItemId,
  }) {
    if (items.isEmpty) {
      AppLogger.w('PlayerController', 'start() ignored: empty item list');
      return;
    }
    final useShuffle =
        shuffle ?? ref.read(settingsControllerProvider).shuffleDefault;
    AppLogger.i('PlayerController',
        'Starting playlist: ${items.length} items, shuffle=$useShuffle');
    // The queue order is what a failed autoplay transition is compared against.
    AppLogger.i('PlayerController', 'Queue: ${_describeQueue(items)}');
    final pl = Playlist(items: items, shuffle: useShuffle);
    if (startItemId != null) pl.jumpToItemId(startItemId);
    AppLogger.i('PlayerController',
        'Playlist started at ${pl.current?.id} '
        '(${pl.positionDisplay}/${pl.length})');
    state = PlayerUiState(playlist: pl, playing: true);
    unawaited(_onItemEntered());
  }

  /// Compact `id(video) -> id(image) -> ...` rendering, capped so a 5000 item
  /// folder cannot flood the log file.
  static String _describeQueue(List<MediaItem> items) {
    const maxEntries = 30;
    final parts = <String>[
      for (final item in items.take(maxEntries))
        '${item.id}${item.isVideo ? '(v)' : '(i)'}',
    ];
    if (items.length > maxEntries) {
      parts.add('...+${items.length - maxEntries} more');
    }
    return parts.join(' -> ');
  }

  void stop() {
    _slideTimer?.cancel();
    final pl = state.playlist;
    AppLogger.i('PlayerController',
        'Stopping playlist at ${pl?.current?.id ?? '-'} '
        '(${pl?.positionDisplay ?? 0}/${pl?.length ?? 0})');
    state = const PlayerUiState();
  }

  void togglePlayPause() {
    final playing = !state.playing;
    AppLogger.i(
      'PlayerController',
      'togglePlayPause -> playing=$playing, item=${state.current?.id ?? '-'}',
    );
    state = state.copyWith(playing: playing);
    if (playing) {
      unawaited(_onItemEntered());
    } else {
      _slideTimer?.cancel();
    }
  }

  void toggleShuffle() {
    final pl = state.playlist;
    if (pl == null) return;
    // Publish a copy: the playlist held by the previous state stays intact.
    final toggled = pl.copy()..toggleShuffle();
    AppLogger.i('PlayerController',
        'Shuffle -> ${toggled.shuffle}, now at ${toggled.current?.id ?? '-'} '
        '(${toggled.positionDisplay}/${toggled.length})');
    // Persist preference.
    unawaited(
      ref
          .read(settingsControllerProvider.notifier)
          .setShuffleDefault(toggled.shuffle),
    );
    state = state.copyWith(playlist: toggled);
  }

  Future<void> next({String reason = 'user'}) async {
    final pl = state.playlist;
    if (pl == null) {
      AppLogger.w('PlayerController', 'next($reason) ignored: no playlist');
      return;
    }
    if (!pl.hasNext) {
      AppLogger.i('PlayerController',
          'next($reason): playlist ended at ${pl.positionDisplay}/${pl.length}, '
          'stopping autoplay');
      state = state.copyWith(playing: false);
      return;
    }
    AppLogger.i(
      'PlayerController',
      'next($reason) from ${pl.current?.id ?? '-'} '
      '(${pl.positionDisplay}/${pl.length})',
    );
    // Advance a copy so the state published earlier keeps its own cursor.
    final advanced = pl.copy()..next();
    final current = advanced.current;
    AppLogger.i(
      'PlayerController',
      'Now playing ${current?.id ?? 'null'} '
      '(${advanced.positionDisplay}/${advanced.length}), '
      'isVideo=${current?.isVideo}, path=${current?.privatePath}',
    );
    state = state.copyWith(
      playlist: advanced,
      playing: true,
      externalHandedOff: false,
    );
    await _onItemEntered();
  }

  Future<void> prev() async {
    final pl = state.playlist;
    if (pl == null || !pl.hasPrev) {
      AppLogger.d('PlayerController',
          'prev() ignored: playlist=${pl?.positionDisplay ?? 0}/${pl?.length ?? 0}');
      return;
    }
    final rewound = pl.copy()..prev();
    AppLogger.i('PlayerController',
        'prev -> ${rewound.current?.id ?? '-'} '
        '(${rewound.positionDisplay}/${rewound.length})');
    state = state.copyWith(
      playlist: rewound,
      playing: true,
      externalHandedOff: false,
    );
    await _onItemEntered();
  }

  /// Called when built-in video finishes or slideshow timer fires.
  Future<void> onItemCompleted() async {
    final item = state.current;
    final pl = state.playlist;
    if (!state.playing) {
      // This silent early return is why a broken autoplay chain used to look
      // like "nothing happened" in the log.
      AppLogger.w('PlayerController',
          'Autoplay stopped: ${item?.id ?? '-'} completed while '
          'playing=false (${pl?.positionDisplay ?? 0}/${pl?.length ?? 0})');
      return;
    }
    AppLogger.i('PlayerController',
        'Item completed: ${item?.id ?? '-'} (isVideo=${item?.isVideo}) '
        '(${pl?.positionDisplay ?? 0}/${pl?.length ?? 0}), advancing');
    await next(reason: 'item-completed');
  }

  /// Advances only when the active playlist item was handed to an external
  /// player and that player confirmed a natural completion.
  Future<void> onExternalPlayerReturned(ExternalPlayerReturn result) async {
    if (!state.externalHandedOff) {
      AppLogger.d('PlayerController',
          'External return $result ignored: no hand-off in flight');
      return;
    }
    if (result != ExternalPlayerReturn.completed) {
      AppLogger.d('PlayerController',
          'External return $result ignored (not a natural completion)');
      return;
    }
    AppLogger.i('PlayerController', 'External player completed, advancing');
    await next(reason: 'external-completed');
  }

  Future<void> _onItemEntered() async {
    _slideTimer?.cancel();
    final item = state.current;
    if (item == null) {
      AppLogger.d('PlayerController', '_onItemEntered: no current item');
      return;
    }
    if (!state.playing) {
      AppLogger.d('PlayerController',
          '_onItemEntered: ${item.id} skipped, playlist is paused');
      return;
    }

    final settings = ref.read(settingsControllerProvider);
    AppLogger.d('PlayerController',
        'Item entered: ${item.id}, isVideo=${item.isVideo}, external=${settings.playerExternal}');

    if (item.isVideo && settings.playerExternal) {
      final external = ref.read(externalPlayerCoordinatorProvider);
      if (external.supported) {
        AppLogger.i('PlayerController', 'Handing off to external player');
        final ok = await external.open(
          filePath: item.privatePath,
          mimeType: item.mimeType,
        );
        AppLogger.i('PlayerController', 'External hand-off opened=$ok');
        state = state.copyWith(playing: false, externalHandedOff: ok);
        return;
      }
      AppLogger.d('PlayerController',
          'External player requested but unsupported, using built-in player');
    }

    if (!item.isVideo) {
      // Image slideshow auto-advance.
      final delay = Duration(seconds: settings.slideshowSeconds);
      AppLogger.i('PlayerController',
          'Slideshow: ${item.id} advances in ${delay.inSeconds}s');
      _slideTimer = Timer(delay, () {
        AppLogger.d('PlayerController', 'Slideshow timer fired: ${item.id}');
        if (state.playing) {
          unawaited(onItemCompleted());
        } else {
          AppLogger.d('PlayerController',
              'Slideshow timer ignored: playlist paused on ${item.id}');
        }
      });
    } else {
      // Built-in video: PlayerScreen video widget calls onItemCompleted.
      AppLogger.d('PlayerController',
          'Waiting for the built-in player to finish ${item.id}');
    }
  }
}

final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerUiState>(PlayerController.new);