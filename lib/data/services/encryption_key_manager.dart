import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/utils/app_logger.dart';

/// Holds the 256-bit KEK (Key Encryption Key) in memory.
///
/// On pattern/pin unlock the KEK is derived from the user secret via PBKDF2
/// and persisted to [FlutterSecureStorage] (backed by Android Keystore on
/// Android).  On biometric unlock the persisted KEK is retrieved from secure
/// storage and loaded into memory.
///
/// On lock the in-memory copy is dropped via [clearMemory] but the persisted
/// copy is kept, so biometric unlock can load it again (PIT-042 / PIT-049).
/// Only [clear] — reserved for credential resets — removes the persisted KEK.
///
/// **Two storage backends, written and read as a pair (ISSUE-031).**
/// [SecurityService] stores credentials with
/// `AndroidOptions(encryptedSharedPreferences: true)`; this class historically
/// used the default backend.  Field reports showed biometric unlock failing
/// with "no persisted KEK found" *seconds after* a successful pattern unlock on
/// the same device — i.e. one backend silently failed to persist or read the
/// value back.  The KEK is therefore written to **both** backends and read from
/// whichever answers first, which is idempotent and fixes either direction of
/// failure.  Do not "simplify" this back to a single instance.
class EncryptionKeyManager {
  static const _storageKey = 'privi_kek_v1';

  /// Records where the persisted KEK came from: `derived` (PBKDF2 of this
  /// install's pattern/PIN) or `imported` (a key package, see
  /// `KeyBackupService`).  An imported KEK must not be replaced by a freshly
  /// derived one — the stored DEKs were wrapped with the imported key
  /// (ISSUE-036).
  static const _sourceKey = 'privi_kek_source_v1';
  static const String sourceDerived = 'derived';
  static const String sourceImported = 'imported';

  /// Default backend (legacy installs persisted the KEK here).
  static const FlutterSecureStorage _defaultStorage = FlutterSecureStorage();

  /// Same backend [SecurityService] uses for credentials.
  static const FlutterSecureStorage _espStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  EncryptionKeyManager({FlutterSecureStorage? storage})
      : _storages =
            storage == null ? const [_defaultStorage, _espStorage] : [storage];

  final List<FlutterSecureStorage> _storages;

  Uint8List? _kek;
  String? _lockKind;

  /// Mirror of [_sourceKey] so unlock paths do not hit secure storage on every
  /// check; `null` until loaded (see [isImportedKey]).
  bool? _importedCache;

  Uint8List? get key => _kek;
  Uint8List? getKey() => _kek;
  String? get lockKind => _lockKind;
  bool get hasKey => _kek != null;

  /// Set KEK in memory and persist it to secure storage (all backends).
  Future<void> setKey(Uint8List kek, {String? lockKind}) async {
    _kek = kek;
    _lockKind = lockKind;
    final encoded = base64Encode(kek);
    var persisted = 0;
    for (var i = 0; i < _storages.length; i++) {
      try {
        await _storages[i].write(key: _storageKey, value: encoded);
        persisted++;
      } catch (e, stack) {
        AppLogger.e('EncryptionKeyManager',
            'Failed to persist KEK (backend $i): $e\n$stack');
      }
    }
    if (persisted == 0) {
      AppLogger.e(
          'EncryptionKeyManager',
          'KEK could not be persisted to any backend — biometric unlock will '
              'not be able to load it after a lock');
    } else if (persisted < _storages.length) {
      AppLogger.w('EncryptionKeyManager',
          'KEK persisted to $persisted/${_storages.length} backends');
    }
  }

  /// True when the persisted KEK came from an imported key package.
  ///
  /// Cached per process.  Unlock paths use this to decide whether the current
  /// pattern/PIN may overwrite the stored KEK (ISSUE-036).
  Future<bool> isImportedKey() async {
    final cached = _importedCache;
    if (cached != null) return cached;
    var imported = false;
    for (var i = 0; i < _storages.length; i++) {
      try {
        final value = await _storages[i].read(key: _sourceKey);
        if (value == sourceImported) {
          imported = true;
          break;
        }
      } catch (e) {
        AppLogger.w('EncryptionKeyManager', 'read KEK source (backend $i): $e');
      }
    }
    _importedCache = imported;
    return imported;
  }

  /// Adopts [kek] from an imported key package: it becomes the vault KEK (memory
  /// + secure storage) and unlock paths stop replacing it with a derived key.
  Future<void> setImportedKey(Uint8List kek) async {
    await setKey(kek);
    _importedCache = true;
    await _writeSource(sourceImported);
  }

  /// Marks the KEK as *derived* again — call **after** a credential change has
  /// rotated every DEK to a freshly derived KEK (`changePattern` / `changePin` /
  /// `migratePinToPattern`), otherwise the next unlock would load the stale
  /// imported key while the DEKs were re-wrapped with the new one.
  Future<void> markDerivedKey() async {
    _importedCache = false;
    await _writeSource(sourceDerived);
  }

  /// Loads the persisted KEK into memory **without** re-persisting it and
  /// without touching the source flag.
  Future<bool> loadPersistedKey() async {
    final persisted = await retrievePersistedKek();
    if (persisted == null) return false;
    _kek = persisted;
    return true;
  }

  Future<void> _writeSource(String source) async {
    for (var i = 0; i < _storages.length; i++) {
      try {
        await _storages[i].write(key: _sourceKey, value: source);
      } catch (e) {
        AppLogger.w(
            'EncryptionKeyManager', 'write KEK source (backend $i): $e');
      }
    }
  }

  /// Clear KEK from memory AND persistent storage.
  /// Used for credential reset; do NOT call on normal lock.
  Future<void> clear() async {
    _kek = null;
    _lockKind = null;
    _importedCache = null;
    for (var i = 0; i < _storages.length; i++) {
      try {
        await _storages[i].delete(key: _storageKey);
        await _storages[i].delete(key: _sourceKey);
      } catch (e, stack) {
        AppLogger.e('EncryptionKeyManager',
            'Failed to delete persisted KEK (backend $i): $e\n$stack');
      }
    }
  }

  /// Clear KEK from memory only — keep the persisted copy so biometric unlock
  /// can retrieve it after lock.
  void clearMemory() {
    _kek = null;
    _lockKind = null;
  }

  /// Retrieve persisted KEK from secure storage.  Returns null if no backend
  /// holds one (logs which backends were tried, see ISSUE-031).
  Future<Uint8List?> retrievePersistedKek() async {
    for (var i = 0; i < _storages.length; i++) {
      try {
        final encoded = await _storages[i].read(key: _storageKey);
        if (encoded == null || encoded.isEmpty) continue;
        return base64Decode(encoded);
      } catch (e, stack) {
        AppLogger.e('EncryptionKeyManager',
            'Failed to retrieve persisted KEK (backend $i): $e\n$stack');
      }
    }
    AppLogger.w('EncryptionKeyManager',
        'no persisted KEK found in any of ${_storages.length} backend(s)');
    return null;
  }
}
