import 'package:pub_semver/pub_semver.dart';

import 'app_release_source.dart';
import 'app_update_service.dart';

final class AppUpdateCoordinator implements AppUpdateService {
  const AppUpdateCoordinator({
    required Version currentVersion,
    required AppReleaseSource releaseSource,
  })  : _currentVersion = currentVersion,
        _releaseSource = releaseSource;

  final Version _currentVersion;
  final AppReleaseSource _releaseSource;

  @override
  Future<AppUpdateCheck> checkForUpdate() async {
    if (_releaseSource.supported) {
      final release = await _releaseSource.readLatestRelease();
      if (release.version > _currentVersion) {
        return AppUpdateCheck.appReleaseAvailable(
          version: release.version.toString(),
          uri: release.uri,
        );
      }
    }
    return const AppUpdateCheck.upToDate();
  }

  @override
  Future<void> downloadUpdate() async {}
}