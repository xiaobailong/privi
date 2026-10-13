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
/// Both backends are intentionally left on FlutterSecureStorage's default
/// Android options: switching to `encryptedSharedPreferences: true` here would
/// orphan every KEK persisted by an already-installed build.
class EncryptionKeyManager {
  static const _storageKey = 'privi_kek_v1';
  final FlutterSecureStorage _storage;

  EncryptionKeyManager({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Uint8List? _kek;
  String? _lockKind;

  Uint8List? get key => _kek;
  Uint8List? getKey() => _kek;
  String? get lockKind => _lockKind;
  bool get hasKey => _kek != null;

  /// Set KEK in memory and persist to secure storage.
  Future<void> setKey(Uint8List kek, {String? lockKind}) async {
    _kek = kek;
    _lockKind = lockKind;
    try {
      await _storage.write(key: _storageKey, value: base64Encode(kek));
    } catch (e, stack) {
      AppLogger.e('EncryptionKeyManager', 'Failed to persist KEK: $e\n$stack');
    }
  }

  /// Clear KEK from memory AND persistent storage.
  /// Used for credential reset; do NOT call on normal lock.
  Future<void> clear() async {
    _kek = null;
    _lockKind = null;
    try {
      await _storage.delete(key: _storageKey);
    } catch (e, stack) {
      AppLogger.e(
          'EncryptionKeyManager', 'Failed to delete persisted KEK: $e\n$stack');
    }
  }

  /// Clear KEK from memory only — keep the persisted copy so biometric unlock
  /// can retrieve it after lock.
  void clearMemory() {
    _kek = null;
    _lockKind = null;
  }

  /// Retrieve persisted KEK from secure storage.  Returns null if not found.
  Future<Uint8List?> retrievePersistedKek() async {
    try {
      final encoded = await _storage.read(key: _storageKey);
      if (encoded == null || encoded.isEmpty) return null;
      return base64Decode(encoded);
    } catch (e, stack) {
      AppLogger.e('EncryptionKeyManager', 'Failed to retrieve persisted KEK: $e\n$stack');
      return null;
    }
  }
}