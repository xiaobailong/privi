import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/services/native_video_controller.dart';
import '../../data/services/playback_display_service.dart';

enum VideoFitMode { fit, fill, original, ratio4x3, ratio16x9 }

bool nativeVideoPlaybackEnded(NativeVideoValue value) {
  if (!value.isInitialized) return false;
  final duration = value.duration;
  if (duration <= Duration.zero) return false;
  if (value.isCompleted) return true;
  return value.position >= duration;
}

String formatVideoTime(Duration duration) {
  final totalSeconds = duration.inSeconds.abs();
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

String formatVideoDelta(Duration duration) {
  final sign = duration.isNegative ? '-' : '+';
  return '$sign${formatVideoTime(duration)}';
}

String formatVideoProgress(Duration position, Duration duration) {
  return '${formatVideoTime(position)}/${formatVideoTime(duration)}';
}

List<DeviceOrientation> preferredOrientationsForVideo(Size size) {
  if (size.width > size.height) {
    return const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ];
  }
  return const [DeviceOrientation.portraitUp];
}

abstract final class VideoSystemUi {
  static Future<void> apply(bool immersive) {
    return SystemChrome.setEnabledSystemUIMode(
      immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  /// Keeps the screen awake while media is on screen on this page.
  static Future<void> setKeepScreenOn(bool enabled) {
    return PlaybackDisplayService.instance.setKeepScreenOn(enabled);
  }

  static Future<void> toggle(bool currentlyLandscape) async {
    await SystemChrome.setPreferredOrientations(
      currentlyLandscape
          ? const [DeviceOrientation.portraitUp]
          : const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ],
    );
  }

  static Future<void> lockToVideoSize(Size size) {
    if (size.isEmpty) return Future<void>.value();
    return SystemChrome.setPreferredOrientations(
      preferredOrientationsForVideo(size),
    );
  }

  static Future<void> unlockOrientations() {
    return SystemChrome.setPreferredOrientations(const []);
  }

  static Future<void> restore() async {
    await unlockOrientations();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await PlaybackDisplayService.instance.resetBrightness();
    await PlaybackDisplayService.instance.setKeepScreenOn(false);
  }
}

class NativeVideoViewport extends StatelessWidget {
  const NativeVideoViewport({
    super.key,
    required this.controller,
    required this.fitMode,
  });

  final NativeVideoController controller;
  final VideoFitMode fitMode;

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    final sourceAspect = value.aspectRatio > 0 ? value.aspectRatio : 16 / 9;
    return ClipRect(
      child: switch (fitMode) {
        VideoFitMode.fit => _ratioViewport(sourceAspect),
        VideoFitMode.fill => _fillViewport(sourceAspect),
        VideoFitMode.original => _originalViewport(value.size, sourceAspect),
        VideoFitMode.ratio4x3 => _ratioViewport(4 / 3),
        VideoFitMode.ratio16x9 => _ratioViewport(16 / 9),
      },
    );
  }

  Widget _ratioViewport(double aspectRatio) {
    return Center(
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: Texture(textureId: controller.textureId),
      ),
    );
  }

  Widget _fillViewport(double aspectRatio) {
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: aspectRatio * 1000,
          height: 1000,
          child: Texture(textureId: controller.textureId),
        ),
      ),
    );
  }

  Widget _originalViewport(Size sourceSize, double fallbackAspect) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (sourceSize.isEmpty) return _ratioViewport(fallbackAspect);
        final scale = math.min(
          1.0,
          math.min(
            constraints.maxWidth / sourceSize.width,
            constraints.maxHeight / sourceSize.height,
          ),
        );
        return Center(
          child: SizedBox(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale,
            child: Texture(textureId: controller.textureId),
          ),
        );
      },
    );
  }
}