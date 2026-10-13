import 'dart:convert';
import 'dart:typed_data';

import '../../core/utils/app_logger.dart';
import '../repositories/media_repository.dart';
import 'encryption_key_manager.dart';
import 'media_encryption_service.dart';
import 'security_service.dart';

/// Outcome of validating / importing a key package.
enum KeyImportOutcome {
  /// Package is valid (and, for [KeyBackupService.importPackage], applied).
  imported,

  /// Not a Privi key package (bad JSON / wrong format tag / bad key length).
  malformed,

  /// This install already holds **different** key material; importing would
  /// silently invalidate every file encrypted on this device.
  saltConflict,

  /// The key cannot unwrap any stored DEK ⇒ it does not belong to this vault.
  keyMismatch,

  /// Secure-storage write failed.
  failed,
}

/// Exports / imports the vault key material ("vault key backup").
///
/// Vault files are encrypted with per-file DEKs that are wrapped by the **KEK**;
/// the KEK is `PBKDF2(pattern|pin, encryption_salt)`.  After a reinstall the
/// secure storage (and therefore the salt) is gone, and
/// `SecurityService.deriveEncryptionKey` would mint a **new** salt ⇒ a different
/// KEK ⇒ every existing file becomes unreadable (ISSUE-029 / ISSUE-036).
///
/// A package therefore carries both halves:
///  * `encryptionSalt` — lets the same pattern/PIN re-derive the same KEK;
///  * `kek` — lets **any** pattern/PIN unlock the vault, once imported
///    ([EncryptionKeyManager.setImportedKey]).
///
/// **The package is as sensitive as the media itself**: it holds the raw KEK in
/// base64 with no password protection, so anyone who has it *and* the vault
/// folder can decrypt everything. Keep it offline or in an encrypted cloud
/// folder, and never hand it to another person.
class KeyBackupService {
  KeyBackupService({
    required EncryptionKeyManager keyManager,
    required SecurityService security,
    required MediaEncryptionService encryption,
    required MediaRepository repository,
  })  : _keyManager = keyManager,
        _security = security,
        _encryption = encryption,
        _repository = repository;

  final EncryptionKeyManager _keyManager;
  final SecurityService _security;
  final MediaEncryptionService _encryption;
  final MediaRepository _repository;

  static const String formatTag = 'privi-key-backup';
  static const int formatVersion = 1;
  static const int _kekBytes = 32;

  /// JSON text of the current key material.
  ///
  /// Throws [StateError] when the vault is locked (no KEK in memory ⇒ nothing to
  /// export); callers show "unlock first" instead of writing an empty package.
  Future<String> buildPackage() async {
    final kek = _keyManager.getKey();
    if (kek == null) {
      throw StateError('vault locked: no KEK in memory');
    }
    final salt = await _security.readEncryptionSalt();
    final package = <String, Object?>{
      'format': formatTag,
      'version': formatVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'encryptionSalt': salt,
      'kek': base64Encode(kek),
      'warning': 'Raw vault key: together with the vault folder it decrypts '
          'every file. Keep it offline or in an encrypted cloud folder.',
    };
    return const JsonEncoder.withIndent('  ').convert(package);
  }

  /// File name to suggest when saving [buildPackage] output.
  static String suggestedFileName(DateTime now) {
    final d = now.toUtc();
    return 'privi-key-${d.year}${_two(d.month)}${_two(d.day)}'
        '-${_two(d.hour)}${_two(d.minute)}.json';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  /// Checks [raw] **without changing anything** — run this before asking the
  /// user to confirm an import.
  Future<KeyImportOutcome> validatePackage(String raw) async {
    final parsed = _parse(raw);
    if (parsed == null) return KeyImportOutcome.malformed;

    final existingSalt = await _security.readEncryptionSalt();
    if (existingSalt != null &&
        existingSalt.isNotEmpty &&
        existingSalt != parsed.salt) {
      // Keep ISSUE-029's rule: never overwrite salt material this install
      // already depends on.
      AppLogger.w('KeyBackupService',
          'import refused: this install already has its own encryption salt');
      return KeyImportOutcome.saltConflict;
    }

    if (!await matchesVault(parsed.kek)) {
      AppLogger.w('KeyBackupService',
          'import refused: the key does not unwrap any stored DEK');
      return KeyImportOutcome.keyMismatch;
    }
    return KeyImportOutcome.imported;
  }

  /// Validates [raw], then adopts its salt and KEK.
  ///
  /// Call [validatePackage] first so the UI only confirms with the user when the
  /// package is actually usable.
  Future<KeyImportOutcome> importPackage(String raw) async {
    final parsed = _parse(raw);
    final outcome = await validatePackage(raw);
    if (outcome != KeyImportOutcome.imported || parsed == null) return outcome;
    try {
      final salt = parsed.salt;
      if (salt != null && salt.isNotEmpty) {
        await _security.adoptEncryptionSaltIfAbsent(salt);
      }
      await _keyManager.setImportedKey(parsed.kek);
    } catch (e, stackTrace) {
      AppLogger.e('KeyBackupService', 'import failed: $e\n$stackTrace');
      return KeyImportOutcome.failed;
    }
    AppLogger.i(
        'KeyBackupService',
        'vault key imported: KEK adopted from the package, salt adopted: '
            '${parsed.salt != null}');
    return KeyImportOutcome.imported;
  }

  /// True when [kek] unwraps at least one stored DEK.
  ///
  /// A vault without encrypted items has nothing to contradict the key, so it
  /// accepts it.
  Future<bool> matchesVault(Uint8List kek) async {
    final items = await _repository.listEncrypted();
    if (items.isEmpty) return true;
    var checked = 0;
    for (final item in items) {
      final dekBase64 = item.encryptedDek;
      if (dekBase64 == null || dekBase64.isEmpty) continue;
      if (checked >= 8) break;
      checked++;
      final dek = await _encryption.decryptDek(
        encryptedDekBase64: dekBase64,
        kek: kek,
      );
      if (dek != null) return true;
    }
    return false;
  }

  /// Parses a package, or null when the text is not one.
  _ParsedKeyPackage? _parse(String raw) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (e) {
      AppLogger.w('KeyBackupService', 'import: not JSON: $e');
      return null;
    }
    if (decoded is! Map) return null;
    if (decoded['format'] != formatTag) return null;
    final version = decoded['version'];
    if (version is! int || version > formatVersion) return null;
    final kekBase64 = decoded['kek'];
    if (kekBase64 is! String || kekBase64.isEmpty) return null;
    Uint8List kek;
    try {
      kek = Uint8List.fromList(base64Decode(kekBase64));
    } catch (_) {
      return null;
    }
    if (kek.length != _kekBytes) return null;
    final salt = decoded['encryptionSalt'];
    return _ParsedKeyPackage(
      kek: kek,
      salt: salt is String && salt.isNotEmpty ? salt : null,
    );
  }
}

class _ParsedKeyPackage {
  const _ParsedKeyPackage({required this.kek, required this.salt});

  final Uint8List kek;
  final String? salt;
}
