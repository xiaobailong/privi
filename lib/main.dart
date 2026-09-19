import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'application/providers.dart';
import 'application/settings/settings_controller.dart';
import 'application/update/app_restart_service.dart';
import 'application/update/external_url_launcher.dart';
import 'core/app_build_info.dart';
import 'core/utils/app_logger.dart';
import 'data/services/android_external_url_launcher.dart';
import 'data/services/platform_app_restart_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The logging switch is applied before the log file is opened: with logging
  // off, the file must stay untouched from the very first line of the session.
  await _applyLogPreference();

  // Initialize file logger to Download/Privi/logs/ (app-private fallback when
  // that folder is not writable). Never blocks startup.
  await _initLogging();
  AppLogger.i('Main', 'Privi starting...');

  // Record uncaught Dart errors in the same log file: a playback bug reported
  // from the phone must not depend on adb logcat being available.
  FlutterError.onError = (details) {
    AppLogger.e(
      'FlutterError',
      '${details.library ?? '-'}: ${details.exceptionAsString()}',
      details.stack,
    );
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    AppLogger.e('UncaughtError', '$error', stack);
    return false;
  };

  final packageInfo = await PackageInfo.fromPlatform();
  AppLogger.i('Main', 'Version: ${packageInfo.version}+${packageInfo.buildNumber}');
  AppLogger.i('Main', 'Logger: ${AppLogger.diagnostics}');
  final AppRestartService appRestartService =
      const PlatformAppRestartService();
  final ExternalUrlLauncher externalUrlLauncher =
      const AndroidExternalUrlLauncher();
  final appBuildInfo = AppBuildInfo(
    version: packageInfo.version,
    buildNumber: packageInfo.buildNumber,
  );
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appBuildInfoProvider.overrideWithValue(appBuildInfo),
      appRestartServiceProvider.overrideWithValue(appRestartService),
      externalUrlLauncherProvider.overrideWithValue(externalUrlLauncher),
    ],
  );
  container.read(databaseProvider);
  await container.read(vaultStorageProvider).ensureVault();
  final settings = container.read(settingsControllerProvider);

  if (settings.flagSecure) {
    try {
      final capabilities =
          await container.read(privacyShieldProvider).apply(true);
      if (!capabilities.appSwitcherProtected) {
        AppLogger.w('Main',
            'privacy shield unavailable: ${capabilities.diagnostic}');
      }
    } catch (error, stackTrace) {
      AppLogger.e('Main', 'privacy shield startup failed: $error\n$stackTrace');
      rethrow;
    }
  }

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(() async {
      try {
        final summary = await container
            .read(maintenanceServiceProvider)
            .runLaunchMaintenance(
              retentionDays: settings.recycleRetentionDays,
            );
        AppLogger.d('Main', 'maintenance: $summary');
      } catch (e, stackTrace) {
        AppLogger.e('Main', 'maintenance failed: $e\n$stackTrace');
      }
    }());
  });

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const PrivateHeartApp(),
    ),
  );
}

/// Reads the persisted logging switch before the log file is opened.
///
/// The provider container does not exist yet at this point, so the raw
/// preference is read here; [SettingsController] owns the same key and
/// re-applies the value whenever the user flips the switch.
Future<void> _applyLogPreference() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    AppLogger.setEnabled(
      prefs.getBool(SettingsController.logEnabledKey) ?? true,
    );
  } catch (error) {
    AppLogger.w('Main', 'log preference unavailable: $error');
  }
}

/// File logging is the only diagnostic channel available on a phone, so its
/// setup must never be able to break startup: a missing permission (common
/// after re-installing an APK) used to be enough to throw out of `main`.
Future<void> _initLogging() async {
  final fallbackDirs = <String>[];
  try {
    final docs = await getApplicationDocumentsDirectory();
    fallbackDirs.add(docs.path);
  } catch (error) {
    AppLogger.w('Main', 'log fallback dir unavailable: $error');
  }
  try {
    await AppLogger.init(
      '/storage/emulated/0/Download',
      fallbackDirs: fallbackDirs,
    );
  } catch (error, stackTrace) {
    AppLogger.e('Main', 'logger init failed: $error\n$stackTrace');
  }
}