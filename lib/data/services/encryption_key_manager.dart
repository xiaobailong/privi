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
/// On lock / screen-off both in-memory and persisted copies are cleared.
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
  Future<void> clear() async {
    _kek = null;
    _lockKind = null;
    try {
      await _storage.delete(key: _storageKey);
    } catch (e, stack) {
      AppLogger.e('EncryptionKeyManager', 'Failed to delete persisted KEK: $e\n$stack');
    }
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