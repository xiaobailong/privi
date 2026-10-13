import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/services/encryption_key_manager.dart';
import '../../data/services/security_service.dart';
import '../../data/services/media_encryption_service.dart';
import '../../data/repositories/media_repository.dart';
import '../../domain/enums.dart';
import '../providers.dart';
import '../settings/settings_controller.dart';
import '../../core/utils/app_logger.dart';

/// App vault lock UI state (not Flutter's shortcuts [LockState]).
enum VaultLockErrorCode {
  wrongPattern,
  wrongPin,
  noSystemLock,
  systemAuthCancelled,
  lockout,

  /// Biometric identity check passed, but no persisted KEK could be loaded
  /// (e.g. the device was unlocked with biometrics before the encryption
  /// layer existed, so the KEK was never persisted).  The user must unlock
  /// with pattern/pin once; that derives and persists the KEK, after which
  /// biometric unlock works again (PIT-049).
  kekUnavailable,
}

class VaultLockState {
  const VaultLockState({
    required this.status,
    this.errorCode,
    this.lockoutSeconds,
    this.lockKind = SecurityService.kindPattern,
    this.pinLength = 4,
    this.biometricEnabled = false,
    this.biometricAvailable = false,
  });

  final LockStatus status;
  final VaultLockErrorCode? errorCode;
  final int? lockoutSeconds;

  /// [SecurityService.kindPattern] (default) or [SecurityService.kindPin].
  final String lockKind;
  final int pinLength;
  final bool biometricEnabled;
  final bool biometricAvailable;

  bool get usesPattern => lockKind != SecurityService.kindPin;

  VaultLockState copyWith({
    LockStatus? status,
    VaultLockErrorCode? errorCode,
    int? lockoutSeconds,
    String? lockKind,
    int? pinLength,
    bool? biometricEnabled,
    bool? biometricAvailable,
    bool clearError = false,
  }) {
    return VaultLockState(
      status: status ?? this.status,
      errorCode: clearError ? null : (errorCode ?? this.errorCode),
      lockoutSeconds:
          clearError ? null : (lockoutSeconds ?? this.lockoutSeconds),
      lockKind: lockKind ?? this.lockKind,
      pinLength: pinLength ?? this.pinLength,
      biometricEnabled: biometricEnabled ?? this.biometricEnabled,
      biometricAvailable: biometricAvailable ?? this.biometricAvailable,
    );
  }
}

class LockController extends Notifier<VaultLockState> {
  Timer? _autoLockTimer;
  Timer? _lockoutTimer;

  /// Wall-clock moment we left the foreground. Dart [Timer]s are unreliable
  /// while Android suspends the isolate — resume must re-check this stamp.
  DateTime? _backgroundedAt;

  /// Nested counter used by in-app viewer/player routes.
  int _suppressAutoLockDepth = 0;

  /// True only between a native external-media launch and its next resume.
  bool _externalPlayerHandoffExpected = false;

  @override
  VaultLockState build() {
    ref.onDispose(() {
      _autoLockTimer?.cancel();
      _lockoutTimer?.cancel();
      _backgroundedAt = null;
      _suppressAutoLockDepth = 0;
      _externalPlayerHandoffExpected = false;
    });
    Future.microtask(_bootstrap);
    return const VaultLockState(status: LockStatus.locked);
  }

  void _cancelAutoLockTimer() {
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
    _backgroundedAt = null;
  }

  void _cancelLockoutTimer() {
    _lockoutTimer?.cancel();
    _lockoutTimer = null;
  }

  Future<void> _showCredentialFailure(VaultLockErrorCode fallbackCode) async {
    final security = ref.read(securityServiceProvider);
    final remaining = await security.lockoutRemaining();
    if (!ref.mounted) return;
    if (remaining == null) {
      _cancelLockoutTimer();
      state = state.copyWith(errorCode: fallbackCode);
      return;
    }
    _cancelLockoutTimer();
    _setLockoutMessage(remaining);
    _lockoutTimer = Timer(
      const Duration(seconds: 1),
      () => unawaited(_refreshLockoutMessage()),
    );
  }

  Future<void> _refreshLockoutMessage() async {
    final remaining =
        await ref.read(securityServiceProvider).lockoutRemaining();
    if (!ref.mounted) return;
    if (remaining == null) {
      _cancelLockoutTimer();
      state = state.copyWith(clearError: true);
      return;
    }
    _setLockoutMessage(remaining);
    _lockoutTimer = Timer(
      const Duration(seconds: 1),
      () => unawaited(_refreshLockoutMessage()),
    );
  }

  void _setLockoutMessage(Duration remaining) {
    final seconds = (remaining.inMilliseconds + 999) ~/ 1000;
    state = state.copyWith(
      errorCode: VaultLockErrorCode.lockout,
      lockoutSeconds: seconds,
    );
  }

  /// Keep session unlocked (in-app viewer/player). Pair with [releaseAutoLockSuppress].
  void suppressAutoLock() {
    _suppressAutoLockDepth++;
    // Cancel only the in-memory timer. Do not clear [_backgroundedAt] — if the
    // app is already backgrounded, the wall-clock deadline must still apply.
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
  }

  void releaseAutoLockSuppress() {
    if (_suppressAutoLockDepth > 0) {
      _suppressAutoLockDepth--;
    }
  }

  void beginExternalPlayerHandoff() {
    _externalPlayerHandoffExpected = true;
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
  }

  void cancelExternalPlayerHandoff() {
    _externalPlayerHandoffExpected = false;
  }

  Future<void> _bootstrap() async {
    final security = ref.read(securityServiceProvider);
    final bio = ref.read(biometricServiceProvider);
    final has = await security.hasCredential();
    final kind = has ? await security.lockKind() : SecurityService.kindPattern;
    final bioEnabled = await security.isBiometricEnabled();
    final bioHw = await bio.isHardwareAvailable();
    if (!ref.mounted) return;
    state = VaultLockState(
      status: has ? LockStatus.locked : LockStatus.needsSetup,
      lockKind: kind,
      biometricEnabled: bioEnabled,
      biometricAvailable: bioHw,
    );
  }

  /// Persist the first-run pattern.
  ///
  /// When [unlockNow] is false, the credential is stored but [LockStatus]
  /// stays [LockStatus.needsSetup] so the lock UI can finish post-setup
  /// steps (e.g. biometric opt-in) before [enterAppAfterSetup] opens the vault.
  /// Unlocking immediately would dispose [LockScreen] and drop that dialog.
  Future<void> setupPattern(String pattern, {bool unlockNow = true}) async {
    final security = ref.read(securityServiceProvider);
    await security.setPattern(pattern);
    if (!ref.mounted) return;
    if (unlockNow) {
      _cancelAutoLockTimer();
      await _deriveAndStoreEncryptionKey(security, pattern);
      if (!ref.mounted) return;
      state = state.copyWith(
        status: LockStatus.unlocked,
        lockKind: SecurityService.kindPattern,
        clearError: true,
      );
    } else {
      // Credential exists; keep setup UI alive for optional biometric prompt.
      state = state.copyWith(
        lockKind: SecurityService.kindPattern,
        clearError: true,
      );
      // Derive KEK in background so enterAppAfterSetup can load it.
      _deriveAndStoreEncryptionKey(security, pattern);
    }
  }

  /// Open the vault after first-run setup (and optional biometric prompt).
  Future<void> enterAppAfterSetup() async {
    if (!ref.mounted) return;
    if (state.status == LockStatus.unlocked) return;
    _cancelAutoLockTimer();
    state = state.copyWith(
      status: LockStatus.unlocked,
      clearError: true,
    );
    // setupPattern/setupPin already started PBKDF2 in background;
    // it may not have finished writing the persisted KEK yet (PIT-045).
    // Retry a few times with short delays.
    final keyManager = ref.read(encryptionKeyManagerProvider);
    final persisted = await _retrievePersistedKekWithRetry(keyManager);
    if (persisted != null) {
      await keyManager.setKey(persisted);
    }
  }

  /// Retry [EncryptionKeyManager.retrievePersistedKek] up to ~3 s while
  /// PBKDF2 derivation started by setupPattern/setupPin completes.
  Future<Uint8List?> _retrievePersistedKekWithRetry(
    EncryptionKeyManager keyManager,
  ) async {
    for (var i = 0; i < 10; i++) {
      final value = await keyManager.retrievePersistedKek();
      if (value != null) return value;
      if (!ref.mounted) return null;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    AppLogger.w('LockController',
        'enterAppAfterSetup: persisted KEK still null after retries');
    return null;
  }

  /// Legacy PIN setup (still available if needed).
  Future<void> setupPin(String pin, {bool unlockNow = true}) async {
    final security = ref.read(securityServiceProvider);
    await security.setPin(pin);
    if (!ref.mounted) return;
    if (unlockNow) {
      _cancelAutoLockTimer();
      await _deriveAndStoreEncryptionKey(security, pin);
      if (!ref.mounted) return;
      state = state.copyWith(
        status: LockStatus.unlocked,
        lockKind: SecurityService.kindPin,
        pinLength: pin.length,
        clearError: true,
      );
    } else {
      state = state.copyWith(
        lockKind: SecurityService.kindPin,
        pinLength: pin.length,
        clearError: true,
      );
      // Derive KEK in background so enterAppAfterSetup can load it.
      _deriveAndStoreEncryptionKey(security, pin);
    }
  }

  Future<bool> unlockWithPattern(String pattern) async {
    final security = ref.read(securityServiceProvider);
    final ok = await security.verifyPattern(pattern);
    if (!ref.mounted) return false;
    if (ok) {
      _cancelLockoutTimer();
      _cancelAutoLockTimer();
      // PIT-046: derive KEK before marking unlocked so the vault is
      // actually ready when the UI transition completes.
      await _deriveAndStoreEncryptionKey(security, pattern);
      if (!ref.mounted) return true;
      state = state.copyWith(
        status: LockStatus.unlocked,
        clearError: true,
        lockKind: SecurityService.kindPattern,
      );
      return true;
    }
    await _showCredentialFailure(VaultLockErrorCode.wrongPattern);
    return false;
  }

  Future<bool> unlock(String pin) async {
    final security = ref.read(securityServiceProvider);
    final ok = await security.verifyPin(pin);
    if (!ref.mounted) return false;
    if (ok) {
      _cancelLockoutTimer();
      _cancelAutoLockTimer();
      await _deriveAndStoreEncryptionKey(security, pin);
      if (!ref.mounted) return true;
      state = state.copyWith(
        status: LockStatus.unlocked,
        clearError: true,
        pinLength: pin.length,
        lockKind: SecurityService.kindPin,
      );
      return true;
    }
    await _showCredentialFailure(VaultLockErrorCode.wrongPin);
    return false;
  }

  /// Biometric convenience unlock (requires root credential + enabled).
  Future<bool> unlockWithBiometric({
    String reason = '解锁密册',
    String signInTitle = '密册',
    String biometricHint = 'Verify identity',
    String cancelButton = 'Cancel',
  }) async {
    final security = ref.read(securityServiceProvider);
    final bio = ref.read(biometricServiceProvider);
    if (!await security.hasCredential()) return false;
    if (!await security.isBiometricEnabled()) return false;
    // Prefer biometrics; still allow device credential if OEM cancels bio-only.
    final ok = await bio.authenticate(
      reason: reason,
      biometricOnly: false,
      signInTitle: signInTitle,
      biometricHint: biometricHint,
      cancelButton: cancelButton,
    );
    if (!ref.mounted) return false;
    if (ok) {
      _cancelAutoLockTimer();
      // Biometric only proves identity; the KEK was persisted to secure
      // storage during the last pattern/pin unlock.  Retrieve it now.
      // Only transition to unlocked *after* the KEK is in memory so that
      // encryption-dependent features (re-encrypt, import, etc.) never see
      // a half-unlocked vault (PIT-049).
      final keyManager = ref.read(encryptionKeyManagerProvider);
      final persisted = await keyManager.retrievePersistedKek();
      if (persisted != null) {
        await keyManager.setKey(persisted);
        state = state.copyWith(status: LockStatus.unlocked, clearError: true);
        return true;
      }
      AppLogger.e(
          'LockController',
          'Biometric OK but no persisted KEK found — '
              'user must unlock with pattern/pin first to derive the '
              'encryption key before biometric unlock can load it.');
      if (!ref.mounted) return false;
      // Stay locked, but tell the user *why* — a bare `false` made the
      // fingerprint button look broken (no prompt result, no error).
      state = state.copyWith(errorCode: VaultLockErrorCode.kekUnavailable);
      return false;
    }
    return false;
  }

  /// Enable/disable biometric. Cancel is soft-fail (returns false, no throw).
  /// Throws only when hardware truly unavailable.
  Future<bool> setBiometricEnabled(
    bool enabled, {
    String? reason,
    String? signInTitle,
    String? biometricHint,
    String? cancelButton,
  }) async {
    final security = ref.read(securityServiceProvider);
    final bio = ref.read(biometricServiceProvider);
    if (enabled) {
      final hw = await bio.isHardwareAvailable();
      AppLogger.d('LockController', 'setBiometricEnabled hw=$hw');
      if (!hw) {
        throw StateError(
          'Biometrics not available — enroll fingerprint/face in system Settings first',
        );
      }
      // Confirm with a live biometric before enabling.
      // Allow device credential fallback if OEM biometric-only is flaky.
      final ok = await bio.authenticate(
        reason: reason ?? 'Confirm to enable biometric unlock',
        biometricOnly: false,
        signInTitle: signInTitle ?? '密册',
        biometricHint: biometricHint ?? 'Verify identity',
        cancelButton: cancelButton ?? 'Cancel',
      );
      AppLogger.d('LockController', 'setBiometricEnabled auth ok=$ok');
      if (!ok) {
        // User cancelled or failed — not an exceptional state.
        return false;
      }
    }
    await security.setBiometricEnabled(enabled);
    if (!ref.mounted) return false;
    state = state.copyWith(biometricEnabled: enabled);
    return true;
  }

  /// Forgot pattern: verify via Android system auth (biometrics or device PIN/pattern),
  /// then clear the vault credential so the user can set a new pattern.
  /// Returns true if recovery completed (status → needsSetup).
  Future<bool> recoverWithSystemAuth({
    String? reason,
    String? signInTitle,
    String? biometricHint,
    String? cancelButton,
  }) async {
    final security = ref.read(securityServiceProvider);
    final bio = ref.read(biometricServiceProvider);
    if (!await security.hasCredential()) {
      if (!ref.mounted) return false;
      state = state.copyWith(status: LockStatus.needsSetup, clearError: true);
      return true;
    }
    final supported = await bio.canUseDeviceCredential();
    if (!supported) {
      if (!ref.mounted) return false;
      state = state.copyWith(
        errorCode: VaultLockErrorCode.noSystemLock,
      );
      return false;
    }
    final ok = await bio.authenticate(
      reason: reason ?? '确认身份以重置密册图案',
      biometricOnly: false, // allow device PIN / pattern / biometric
      signInTitle: signInTitle ?? '密册',
      biometricHint: biometricHint ?? 'Verify identity',
      cancelButton: cancelButton ?? 'Cancel',
    );
    if (!ok) {
      if (!ref.mounted) return false;
      state = state.copyWith(
        errorCode: VaultLockErrorCode.systemAuthCancelled,
      );
      return false;
    }
    await security.clearCredential();
    // Optional: leave biometric flag; user re-enables after setup if desired.
    if (!ref.mounted) return false;
    _cancelAutoLockTimer();
    state = VaultLockState(
      status: LockStatus.needsSetup,
      lockKind: SecurityService.kindPattern,
      biometricEnabled: state.biometricEnabled,
      biometricAvailable: state.biometricAvailable,
    );
    return true;
  }

  Future<void> changePattern({
    required String currentPattern,
    required String newPattern,
  }) async {
    final security = ref.read(securityServiceProvider);
    final ok = await security.verifyPattern(currentPattern);
    if (!ok) {
      final pinOk = await security.verifyPin(currentPattern);
      if (!pinOk) throw StateError('Current pattern is incorrect');
    }

    final keyManager = ref.read(encryptionKeyManagerProvider);
    final oldKek = keyManager.getKey();
    final repo = ref.read(mediaRepositoryProvider);

    if (oldKek == null) {
      final encryptedCount = (await repo.listEncrypted()).length;
      if (encryptedCount > 0) {
        throw StateError(
            'Cannot change pattern: $encryptedCount encrypted file(s) exist '
            'but the current key is unavailable. '
            'Lock and unlock the vault first to reload the encryption key.');
      }
    }

    // Derive new KEK BEFORE changing credential so we can rotate with both
    // keys available.  If this fails nothing has been changed yet.
    final newKek = await security.deriveEncryptionKey(newPattern);
    if (newKek == null || !ref.mounted) return;

    // Rotate DEKs BEFORE changing credential so a crash during rotation can be
    // recovered by re-running with the still-valid old credential.
    if (oldKek != null) {
      await _rotateAllDeks(oldKek, newKek, 'changePattern');
    }

    await security.setPattern(newPattern);
    if (!ref.mounted) return;

    await keyManager.setKey(newKek);
    // A credential change re-derives the KEK and rotates every DEK to it, so the
    // vault no longer runs on an imported key (ISSUE-036).
    await keyManager.markDerivedKey();
    state = state.copyWith(lockKind: SecurityService.kindPattern);
  }

  /// Verify legacy PIN then replace root credential with [newPattern].
  /// Also rotates all encrypted DEKs to the new KEK.
  Future<void> migratePinToPattern({
    required String currentPin,
    required String newPattern,
  }) async {
    final security = ref.read(securityServiceProvider);
    final ok = await security.verifyPin(currentPin);
    if (!ok) throw StateError('Current PIN is incorrect');

    final keyManager = ref.read(encryptionKeyManagerProvider);
    final oldKek = keyManager.getKey();
    final repo = ref.read(mediaRepositoryProvider);

    if (oldKek == null) {
      final encryptedCount = (await repo.listEncrypted()).length;
      if (encryptedCount > 0) {
        throw StateError(
            'Cannot migrate to pattern: $encryptedCount encrypted file(s) exist '
            'but the current key is unavailable. '
            'Lock and unlock the vault first to reload the encryption key.');
      }
    }

    final newKek = await security.deriveEncryptionKey(newPattern);
    if (newKek == null || !ref.mounted) return;

    if (oldKek != null) {
      await _rotateAllDeks(oldKek, newKek, 'migratePinToPattern');
    }

    await security.setPattern(newPattern);
    if (!ref.mounted) return;

    await keyManager.setKey(newKek);
    // Credential change: DEKs are rotated onto the freshly derived KEK, so drop
    // the imported-key flag (ISSUE-036).
    await keyManager.markDerivedKey();
    state =
        state.copyWith(lockKind: SecurityService.kindPattern, clearError: true);
  }

  Future<void> changePin({
    required String currentPin,
    required String newPin,
  }) async {
    final security = ref.read(securityServiceProvider);
    final ok = await security.verifyPin(currentPin);
    if (!ok) throw StateError('Current PIN is incorrect');

    final keyManager = ref.read(encryptionKeyManagerProvider);
    final oldKek = keyManager.getKey();
    final repo = ref.read(mediaRepositoryProvider);

    if (oldKek == null) {
      final encryptedCount = (await repo.listEncrypted()).length;
      if (encryptedCount > 0) {
        throw StateError(
            'Cannot change PIN: $encryptedCount encrypted file(s) exist '
            'but the current key is unavailable. '
            'Lock and unlock the vault first to reload the encryption key.');
      }
    }

    final newKek = await security.deriveEncryptionKey(newPin);
    if (newKek == null || !ref.mounted) return;

    if (oldKek != null) {
      await _rotateAllDeks(oldKek, newKek, 'changePin');
    }

    await security.setPin(newPin);
    if (!ref.mounted) return;

    await keyManager.setKey(newKek);
    // Credential change: DEKs are rotated onto the freshly derived KEK, so drop
    // the imported-key flag (ISSUE-036).
    await keyManager.markDerivedKey();
    state = state.copyWith(
      pinLength: newPin.length,
      lockKind: SecurityService.kindPin,
    );
  }

  /// Re-encrypt all existing DEKs from [oldKek] to [newKek].
  ///
  /// Idempotent: tries [newKek] first (already-rotated DEKs), then [oldKek]
  /// (still-pending DEKs).  Safe to re-run after an interrupted rotation.
  /// Logs how many succeeded / were lost.
  Future<void> _rotateAllDeks(
      Uint8List oldKek, Uint8List newKek, String caller) async {
    final encryptionService = ref.read(mediaEncryptionServiceProvider);
    final repo = ref.read(mediaRepositoryProvider);
    try {
      final encryptedItems = await repo.listEncrypted();
      int okCount = 0;
      int lostCount = 0;
      for (final item in encryptedItems) {
        if (item.encryptedDek == null || item.encryptedDek!.isEmpty) continue;
        try {
          Uint8List? dek = await encryptionService.decryptDek(
            encryptedDekBase64: item.encryptedDek!,
            kek: newKek,
          );
          dek ??= await encryptionService.decryptDek(
            encryptedDekBase64: item.encryptedDek!,
            kek: oldKek,
          );
          if (dek == null) {
            AppLogger.e(
                'LockController',
                'DEK rotation ($caller): could not decrypt DEK for ${item.id} '
                    'with either old or new KEK — file is orphaned');
            lostCount++;
            continue;
          }
          final newEncryptedDek = await encryptionService.encryptDek(
            dek: dek,
            kek: newKek,
          );
          await repo.updateEncryptedDek(item.id, newEncryptedDek);
          okCount++;
        } catch (_) {
          lostCount++;
        }
      }
      if (lostCount > 0) {
        AppLogger.e('LockController',
            'DEK rotation ($caller): $okCount OK, $lostCount LOST');
      }
    } catch (e, stack) {
      AppLogger.e(
          'LockController', 'DEK rotation failed ($caller): $e\n$stack');
    }
  }

  void lock() {
    _cancelAutoLockTimer();
    _cancelLockoutTimer();
    _externalPlayerHandoffExpected = false;
    _kekGen++;
    // Only clear in-memory KEK; keep persisted copy for biometric unlock.
    ref.read(encryptionKeyManagerProvider).clearMemory();
    state = state.copyWith(status: LockStatus.locked, clearError: true);
  }

  int _kekGen = 0;

  Future<void> _deriveAndStoreEncryptionKey(
    SecurityService security,
    String secret,
  ) async {
    final gen = ++_kekGen;
    final keyManager = ref.read(encryptionKeyManagerProvider);
    // An imported key package wins over this install's pattern/PIN: the stored
    // DEKs were wrapped with the imported KEK, so re-deriving from the current
    // secret would silently make every encrypted file unreadable (ISSUE-036).
    // Changing the pattern/PIN still works — that path rotates all DEKs and then
    // calls `markDerivedKey()`.
    if (await keyManager.isImportedKey()) {
      if (gen != _kekGen) return;
      if (await keyManager.loadPersistedKey()) {
        AppLogger.i('LockController',
            'unlock: using the imported vault key (key package)');
        return;
      }
      AppLogger.w('LockController',
          'imported key flag set but no persisted KEK — deriving from secret');
    }
    final kek = await security.deriveEncryptionKey(secret);
    if (gen != _kekGen) return;
    if (kek != null && ref.mounted) {
      await ref.read(encryptionKeyManagerProvider).setKey(kek);
    } else if (kek == null) {
      // PBKDF2 failed (secure-storage read error): nothing is persisted, so
      // biometric unlock cannot load a KEK later (VaultLockErrorCode.kekUnavailable).
      AppLogger.e(
          'LockController',
          'KEK derivation returned null — encrypted media stays '
              'inaccessible and biometric unlock has no persisted KEK to load.');
    }
  }

  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// Auto-lock when the app leaves the foreground for [autoLockSeconds].
  ///
  /// - Ignores [AppLifecycleState.inactive] (dialogs / transient focus).
  /// - On paused/hidden/detached: stamp wall-clock time and arm a best-effort
  ///   [Timer]. Android often suspends Dart timers in the background, so the
  ///   stamp is the source of truth.
  /// - On resumed: VLC/external picture viewers bypass the lock only when their
  ///   native activity result matches an expected hand-off.
  /// - An expected external-media resume without a result locks immediately.
  /// - Other resumes lock only after hidden/paused. Inactive-only transitions
  ///   are system UI (including biometric prompts), not background hand-offs.
  void onAppLifecycle(
    AppLifecycleState lifecycle, {
    bool externalPlayerReturnedCleanly = false,
  }) {
    final seconds = ref.read(settingsControllerProvider).autoLockSeconds;

    switch (lifecycle) {
      case AppLifecycleState.resumed:
        final leftAt = _backgroundedAt;
        final expectedExternalReturn = _externalPlayerHandoffExpected;
        _autoLockTimer?.cancel();
        _autoLockTimer = null;
        _backgroundedAt = null;
        _externalPlayerHandoffExpected = false;

        if (state.status != LockStatus.unlocked) return;
        if (expectedExternalReturn) {
          if (externalPlayerReturnedCleanly) return;
          lock();
          return;
        }
        if (leftAt != null) lock();
        return;
      case AppLifecycleState.inactive:
        // Ignore: system UI overlays / focus loss without leaving the app.
        return;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        if (state.status != LockStatus.unlocked) return;
        _autoLockTimer?.cancel();
        _autoLockTimer = null;
        _backgroundedAt ??= DateTime.now();
        if (_externalPlayerHandoffExpected) return;
        if (seconds <= 0) {
          _backgroundedAt = null;
          lock();
        } else {
          // Keep first background stamp if we already recorded one (paused
          // often follows hidden); don't reset the deadline on every event.
          final remaining = Duration(seconds: seconds) -
              DateTime.now().difference(_backgroundedAt!);
          if (remaining <= Duration.zero) {
            lock();
          } else {
            // Best-effort: fires if the isolate keeps running (some OEMs).
            _autoLockTimer = Timer(remaining, lock);
          }
        }
    }
  }
}

final lockControllerProvider =
    NotifierProvider<LockController, VaultLockState>(LockController.new);
