import 'dart:typed_data';

import 'package:flutter/services.dart';

import '../../core/utils/app_logger.dart';

/// Bridges to Android's hardware-accelerated AES-256-GCM via
/// [CryptoHandler](android/app/src/main/kotlin/com/privi/app/CryptoHandler.kt).
///
/// Uses `javax.crypto.Cipher` with `AES/GCM/NoPadding`, which delegates to
/// hardware-accelerated implementations (AES-NI / ARMv8 crypto extensions).
///
/// File format: [nonce:12][ciphertext:N][auth_tag:16]
class NativeCryptoService {
  static const _channel = MethodChannel('com.privi.app/crypto');

  /// Encrypt [filePath] in-place using hardware-accelerated AES-256-GCM.
  ///
  /// Returns a map with `ok` (bool), `originalSize` (int), `encryptedSize` (int),
  /// or `error` (String) on failure.
  Future<Map<String, dynamic>> encryptFile({
    required String filePath,
    required Uint8List dek,
    required Uint8List nonce,
  }) async {
    try {
      final result = await _channel.invokeMapMethod('encryptFile', {
        'filePath': filePath,
        'dek': dek,
        'nonce': nonce,
      });
      return result?.cast<String, dynamic>() ?? {};
    } catch (e, stackTrace) {
      AppLogger.e('NativeCryptoService', 'encryptFile: $e\n$stackTrace');
      return {'ok': false, 'error': '$e'};
    }
  }

  /// Decrypt [filePath] and write plaintext to [destPath].
  ///
  /// Returns a map with `ok` (bool), `plaintextSize` (int),
  /// or `error` (String) on failure.
  Future<Map<String, dynamic>> decryptFile({
    required String filePath,
    required String destPath,
    required Uint8List dek,
  }) async {
    try {
      final result = await _channel.invokeMapMethod('decryptFile', {
        'filePath': filePath,
        'destPath': destPath,
        'dek': dek,
      });
      return result?.cast<String, dynamic>() ?? {};
    } catch (e, stackTrace) {
      AppLogger.e('NativeCryptoService', 'decryptFile: $e\n$stackTrace');
      return {'ok': false, 'error': '$e'};
    }
  }

  /// Decrypt [filePath] and return plaintext bytes (max 512 MiB).
  ///
  /// Returns a map with `ok` (bool), `bytes` (Uint8List),
  /// or `error` (String) on failure.
  Future<Map<String, dynamic>> decryptFileToBytes({
    required String filePath,
    required Uint8List dek,
  }) async {
    try {
      final result = await _channel.invokeMapMethod('decryptFileToBytes', {
        'filePath': filePath,
        'dek': dek,
      });
      return result?.cast<String, dynamic>() ?? {};
    } catch (e, stackTrace) {
      AppLogger.e('NativeCryptoService', 'decryptFileToBytes: $e\n$stackTrace');
      return {'ok': false, 'error': '$e'};
    }
  }
}