enum AppUpdateStatus {
  upToDate,
  appReleaseAvailable,
  unavailable,
}

final class AppUpdateCheck {
  const AppUpdateCheck._({
    required this.status,
    this.releaseVersion,
    this.releaseUri,
  });

  const AppUpdateCheck.upToDate() : this._(status: AppUpdateStatus.upToDate);

  const AppUpdateCheck.unavailable()
      : this._(status: AppUpdateStatus.unavailable);

  const AppUpdateCheck.appReleaseAvailable({
    required String version,
    required Uri uri,
  }) : this._(
          status: AppUpdateStatus.appReleaseAvailable,
          releaseVersion: version,
          releaseUri: uri,
        );

  final AppUpdateStatus status;
  final String? releaseVersion;
  final Uri? releaseUri;
}