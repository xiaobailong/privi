import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as cryptography;
import 'package:flutter/foundation.dart';

import '../../core/utils/app_logger.dart';
import 'native_crypto_service.dart';

class EncryptedFileResult {
  const EncryptedFileResult({
    required this.encryptedDekBase64,
    required this.dekNonce,
  });

  final String encryptedDekBase64;
  final List<int> dekNonce;
}

/// AES-256-GCM media encryption service.
///
/// **Two-tier key architecture (Huawei Vault style):**
///   User password → PBKDF2 → KEK  → encrypts DEK (stored in DB)
///   Random DEK   → AES-GCM → encrypts media file
///
/// **File operations** delegate to Android's hardware-accelerated
/// `javax.crypto.Cipher` via [NativeCryptoService] for performance:
///   - 1 GiB decrypt ≈ 0.5–2 s  (vs 13–34 s pure Dart)
///   - 35 GiB encrypt ≈ 18–70 s (vs 7–21 min pure Dart)
///
/// **DEK operations** (encryptDek / decryptDek) stay in pure Dart
/// `cryptography` – they only handle 32-byte keys, no perf concern.
///
/// File format: `[nonce:12][ciphertext:N][auth_tag:16]`
class MediaEncryptionService {
  MediaEncryptionService({NativeCryptoService? nativeCrypto})
      : _native = nativeCrypto ?? NativeCryptoService();

  final NativeCryptoService _native;

  static const int _dekBits = 256;
  static const int _nonceLength = 12;

  cryptography.AesGcm get _algorithm => cryptography.AesGcm.with256bits(
        nonceLength: _nonceLength,
      );

  // ────────────────────── DEK / key helpers ──────────────────────

  Uint8List generateDek() {
    final r = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(_dekBits ~/ 8, (_) => r.nextInt(256)),
    );
  }

  List<int> generateNonce() {
    final r = Random.secure();
    return List<int>.generate(_nonceLength, (_) => r.nextInt(256));
  }

  /// Encrypt the per-file DEK under KEK.
  /// Output: base64([nonce:12][ciphertext][tag:16])
  Future<String> encryptDek({
    required Uint8List dek,
    required Uint8List kek,
  }) async {
    final nonce = generateNonce();
    final secretBox = await _algorithm.encrypt(
      dek,
      secretKey: cryptography.SecretKey(kek),
      nonce: nonce,
    );
    final combined = <int>[...nonce, ...secretBox.cipherText, ...secretBox.mac.bytes];
    return base64Encode(Uint8List.fromList(combined));
  }

  /// Decrypt DEK with KEK. Returns null on failure (wrong password, tampered data).
  Future<Uint8List?> decryptDek({
    required String encryptedDekBase64,
    required Uint8List kek,
  }) async {
    try {
      final combined = base64Decode(encryptedDekBase64);
      if (combined.length < _nonceLength + 16) return null;
      final nonce = combined.sublist(0, _nonceLength);
      final cipherAndTag = combined.sublist(_nonceLength);
      if (cipherAndTag.length < 16) return null;
      final cipherText = cipherAndTag.sublist(0, cipherAndTag.length - 16);
      final mac =
          cryptography.Mac(cipherAndTag.sublist(cipherAndTag.length - 16));

      final secretBox =
          cryptography.SecretBox(cipherText, mac: mac, nonce: nonce);
      final dek = await _algorithm.decrypt(
        secretBox,
        secretKey: cryptography.SecretKey(kek),
      );
      return Uint8List.fromList(dek);
    } catch (e, stack) {
      AppLogger.e(
          'MediaEncryptionService', 'Failed to decrypt DEK: $e\n$stack');
      return null;
    }
  }

  // ────────────────────── File encryption (native) ──────────────────────

  /// Encrypt [filePath] in-place with a fresh DEK, then encrypt DEK under KEK.
  ///
  /// Uses hardware-accelerated native crypto.  Checks [looksEncrypted] first
  /// to prevent double encryption.
  Future<EncryptedFileResult> encryptFile({
    required String filePath,
    required Uint8List kek,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileSystemException('File not found', filePath);
    }
    if (looksEncrypted(file)) {
      throw StateError(
          'File already appears encrypted: $filePath.  Skipping to avoid '
          'double encryption.');
    }

    final dek = generateDek();
    final nonce = generateNonce();

    final result = await _native.encryptFile(
      filePath: filePath,
      dek: dek,
      nonce: Uint8List.fromList(nonce),
    );

    final ok = result['ok'] as bool? ?? false;
    if (!ok) {
      final err = result['error'] as String? ?? 'Unknown native crypto error';
      throw Exception('Native encryption failed: $err');
    }

    final encryptedDekBase64 = await encryptDek(dek: dek, kek: kek);

    AppLogger.d('MediaEncryptionService',
        'Encrypted: $filePath (${result['originalSize']} → ${result['encryptedSize']} bytes)');

    return EncryptedFileResult(
      encryptedDekBase64: encryptedDekBase64,
      dekNonce: nonce,
    );
  }

  // ────────────────────── File decryption (native) ──────────────────────

  /// Decrypt [filePath] to [destPath] using hardware-accelerated native crypto.
  ///
  /// Verifies AES-GCM auth tag.  Throws on failure.
  Future<void> decryptFile({
    required String filePath,
    required String destPath,
    required Uint8List dek,
  }) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileSystemException('File not found', filePath);
    }

    final result = await _native.decryptFile(
      filePath: filePath,
      destPath: destPath,
      dek: dek,
    );

    final ok = result['ok'] as bool? ?? false;
    if (!ok) {
      final err = result['error'] as String? ?? 'Unknown native crypto error';
      throw Exception('Native decryption failed: $err');
    }

    AppLogger.d('MediaEncryptionService',
        'Decrypted: $filePath → $destPath (${result['plaintextSize']} bytes)');
  }

  /// Decrypt [filePath] to a temporary file.
  ///
  /// The caller MUST delete the temp file after use.
  Future<String> decryptToTempFile({
    required String filePath,
    required Uint8List dek,
  }) async {
    final tempDir = Directory.systemTemp;
    final r = Random.secure();
    final randomSuffix =
        r.nextInt(0xFFFFFFFF).toRadixString(16).padLeft(8, '0');
    final tempName =
        'privi_dec_${DateTime.now().millisecondsSinceEpoch}_$randomSuffix';
    final tempPath = '${tempDir.path}/$tempName';

    await decryptFile(
      filePath: filePath,
      destPath: tempPath,
      dek: dek,
    );

    return tempPath;
  }

  /// Full pipeline: decrypt DEK with KEK, then decrypt file to temp file.
  ///
  /// Returns null if DEK decryption fails (wrong key, tampered) or file
  /// decryption fails (auth tag mismatch, corruption).
  Future<String?> decryptToTempFileWithDek({
    required String filePath,
    required String encryptedDekBase64,
    required Uint8List kek,
  }) async {
    final dek = await decryptDek(
      encryptedDekBase64: encryptedDekBase64,
      kek: kek,
    );
    if (dek == null) {
      AppLogger.e('MediaEncryptionService',
          'DEK decryption failed — wrong KEK or corrupted DEK');
      return null;
    }
    try {
      return await decryptToTempFile(filePath: filePath, dek: dek);
    } catch (e, stack) {
      AppLogger.e(
          'MediaEncryptionService', 'File decryption failed: $e\n$stack');
      return null;
    }
  }

  /// Decrypt [filePath] and return plaintext bytes.
  ///
  /// Uses native hardware-accelerated decryption.  For files up to ~512 MiB.
  /// For larger files use [decryptToTempFile].
  Future<Uint8List> decryptFileToBytes({
    required String filePath,
    required Uint8List dek,
  }) async {
    final result = await _native.decryptFileToBytes(
      filePath: filePath,
      dek: dek,
    );

    final ok = result['ok'] as bool? ?? false;
    if (!ok) {
      final err = result['error'] as String? ?? 'Unknown native crypto error';
      throw Exception('Native decryption failed: $err');
    }

    return result['bytes'] as Uint8List;
  }

  // ────────────────────── Detection ──────────────────────

  /// Heuristic: does [file] look already encrypted?
  ///
  /// Checks the file header against known plaintext media signatures
  /// (JPEG, PNG, MP4, WebM, MKV).  If none match, the file is likely
  /// encrypted.  Not 100 % reliable but safe enough to prevent double
  /// encryption.
  bool looksEncrypted(File file) {
    if (!file.existsSync()) return false;
    final length = file.lengthSync();
    if (length < _nonceLength + 16) return false;

    // Only read the first 32 bytes (enough for all known media headers).
    try {
      final raf = file.openSync(mode: FileMode.read);
      try {
        final bytes = Uint8List(32);
        final read = raf.readIntoSync(bytes);
        raf.closeSync();
        if (read < _nonceLength + 16) return false;
        return !_looksLikePlainMedia(bytes);
      } catch (_) {
        try { raf.closeSync(); } catch (_) {}
        return true; // unreadable → treat as encrypted
      }
    } catch (_) {
      return true;
    }
  }

  /// Returns true if [bytes] starts with a known plaintext media signature.
  static bool _looksLikePlainMedia(Uint8List bytes) {
    final header = bytes.sublist(0, 8);
    final commonJpeg =
        Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46]);
    final commonPng =
        Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
    final commonMp4 =
        Uint8List.fromList([0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70]);
    final commonWebm =
        Uint8List.fromList([0x1A, 0x45, 0xDF, 0xA3, 0x93, 0x42, 0x82, 0x88]);
    final commonMkv = Uint8List.fromList([0x1A, 0x45, 0xDF, 0xA3]);

    if (_bytesMatch(header, commonJpeg)) return true;
    if (_bytesMatch(header, commonPng)) return true;
    if (bytes.length >= 12 && _bytesMatch(bytes.sublist(4, 12), commonMp4)) {
      return true;
    }
    if (_bytesMatch(header, commonWebm)) return true;
    if (_bytesMatch(header, commonMkv)) return true;

    return false;
  }

  static bool _bytesMatch(List<int> a, List<int> b) {
    if (a.length < b.length || b.length < 4) return false;
    for (var i = 0; i < b.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}