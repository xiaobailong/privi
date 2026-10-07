import 'package:flutter/foundation.dart';

/// Immutable package version metadata supplied by the composition root.
///
/// [version] is the plain three-part version from `pubspec.yaml` (e.g. `1.0.59`,
/// no `+build` suffix - see memory-bank ADR-026). The Android `versionCode` is
/// derived from it at build time (`android/app/build.gradle.kts`), so it is not
/// part of the user-facing version string.
@immutable
class AppBuildInfo {
  AppBuildInfo({
    required String version,
  }) : version = _requireValue(version, 'version');

  final String version;

  static String _requireValue(String value, String name) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(value, name, 'must not be empty');
    }
    return normalized;
  }
}