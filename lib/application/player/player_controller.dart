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
    if (items.isEmpty) return;
    final useShuffle =
        shuffle ?? ref.read(settingsControllerProvider).shuffleDefault;
    AppLogger.i('PlayerController',
        'Starting playlist: ${items.length} items, shuffle=$useShuffle');
    final pl = Playlist(items: items, shuffle: useShuffle);
    if (startItemId != null) pl.jumpToItemId(startItemId);
    state = PlayerUiState(playlist: pl, playing: true);
    unawaited(_onItemEntered());
  }

  void stop() {
    _slideTimer?.cancel();
    state = const PlayerUiState();
  }

  void togglePlayPause() {
    final playing = !state.playing;
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
    // Persist preference.
    unawaited(
      ref
          .read(settingsControllerProvider.notifier)
          .setShuffleDefault(toggled.shuffle),
    );
    state = state.copyWith(playlist: toggled);
  }

  Future<void> next() async {
    final pl = state.playlist;
    if (pl == null || !pl.hasNext) {
      AppLogger.i('PlayerController', 'Playlist ended, no more items');
      state = state.copyWith(playing: false);
      return;
    }
    // Advance a copy so the state published earlier keeps its own cursor.
    final advanced = pl.copy()..next();
    final current = advanced.current;
    AppLogger.i('PlayerController',
        'Next item: ${current?.id ?? 'null'} '
        '(${advanced.positionDisplay}/${advanced.length})');
    state = state.copyWith(
      playlist: advanced,
      playing: true,
      externalHandedOff: false,
    );
    await _onItemEntered();
  }

  Future<void> prev() async {
    final pl = state.playlist;
    if (pl == null || !pl.hasPrev) return;
    final rewound = pl.copy()..prev();
    state = state.copyWith(
      playlist: rewound,
      playing: true,
      externalHandedOff: false,
    );
    await _onItemEntered();
  }

  /// Called when built-in video finishes or slideshow timer fires.
  Future<void> onItemCompleted() async {
    if (!state.playing) return;
    AppLogger.i('PlayerController',
        'Item completed, advancing to next');
    await next();
  }

  /// Advances only when the active playlist item was handed to an external
  /// player and that player confirmed a natural completion.
  Future<void> onExternalPlayerReturned(ExternalPlayerReturn result) async {
    if (!state.externalHandedOff) return;
    if (result != ExternalPlayerReturn.completed) return;
    await next();
  }

  Future<void> _onItemEntered() async {
    _slideTimer?.cancel();
    final item = state.current;
    if (item == null || !state.playing) return;

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
        state = state.copyWith(playing: false, externalHandedOff: ok);
        return;
      }
    }

    if (!item.isVideo) {
      // Image slideshow auto-advance.
      final delay = Duration(seconds: settings.slideshowSeconds);
      _slideTimer = Timer(delay, () {
        if (state.playing) unawaited(onItemCompleted());
      });
    }
    // Built-in video: PlayerScreen video widget calls onItemCompleted.
  }
}

final playerControllerProvider =
    NotifierProvider<PlayerController, PlayerUiState>(PlayerController.new);