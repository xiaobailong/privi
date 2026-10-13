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

  /// Default backend (legacy installs persisted the KEK here).
  static const FlutterSecureStorage _defaultStorage = FlutterSecureStorage();

  /// Same backend [SecurityService] uses for credentials.
  static const FlutterSecureStorage _espStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  EncryptionKeyManager({FlutterSecureStorage? storage})
      : _storages = storage == null
            ? const [_defaultStorage, _espStorage]
            : [storage];

  final List<FlutterSecureStorage> _storages;

  Uint8List? _kek;
  String? _lockKind;

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
      AppLogger.e('EncryptionKeyManager',
          'KEK could not be persisted to any backend — biometric unlock will '
          'not be able to load it after a lock');
    } else if (persisted < _storages.length) {
      AppLogger.w('EncryptionKeyManager',
          'KEK persisted to $persisted/${_storages.length} backends');
    }
  }

  /// Clear KEK from memory AND persistent storage.
  /// Used for credential reset; do NOT call on normal lock.
  Future<void> clear() async {
    _kek = null;
    _lockKind = null;
    for (var i = 0; i < _storages.length; i++) {
      try {
        await _storages[i].delete(key: _storageKey);
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