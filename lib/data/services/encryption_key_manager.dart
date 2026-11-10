import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/utils/app_logger.dart';

/// One KEK held by the vault, identified by the fingerprint of its bytes.
///
/// The id is derived from the key material (never from the install or the
/// credential), so the same key keeps the same id on every device.  Media rows
/// store this id in `encryption_key_id`; a restore can therefore register a
/// foreign key without ever having to renumber the rows (and without clashing
/// with this install's own default key).
class EncryptionKeyRecord {
  const EncryptionKeyRecord({
    required this.id,
    required this.kek,
    required this.fingerprint,
    required this.createdAt,
    this.label,
    this.salt,
    this.isDefault = false,
  });

  final String id;
  final Uint8List kek;
  final String fingerprint;
  final DateTime createdAt;
  final String? label;
  final String? salt;
  final bool isDefault;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'kek': base64Encode(kek),
        'fingerprint': fingerprint,
        'createdAt': createdAt.toUtc().toIso8601String(),
        if (label != null) 'label': label,
        if (salt != null) 'salt': salt,
        'isDefault': isDefault,
      };

  static EncryptionKeyRecord? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final id = json['id'];
    final encoded = json['kek'];
    final fingerprint = json['fingerprint'];
    if (id is! String || id.isEmpty || encoded is! String) return null;
    late final Uint8List kek;
    try {
      kek = Uint8List.fromList(base64Decode(encoded));
    } catch (_) {
      return null;
    }
    if (kek.length != EncryptionKeyManager.kekBytes) return null;
    return EncryptionKeyRecord(
      id: id,
      kek: kek,
      fingerprint: fingerprint is String && fingerprint.isNotEmpty
          ? fingerprint
          : EncryptionKeyManager.fingerprintOf(kek),
      createdAt: DateTime.tryParse('${json['createdAt'] ?? ''}')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      label: json['label'] is String ? json['label'] as String : null,
      salt: json['salt'] is String ? json['salt'] as String : null,
      isDefault: json['isDefault'] == true,
    );
  }
}

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
/// **Key ring.** Besides the current (default) KEK, the vault keeps every key
/// it has ever used, plus keys registered from an imported backup.  Each media
/// row records which key wrapped its DEK (`media_items.encryption_key_id`), so
/// importing a foreign key no longer has to replace this install's default
/// key — the two simply coexist and each file is opened with its own key.
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
  static const _ringStorageKey = 'privi_kek_ring_v1';

  /// Records where the persisted KEK came from: `derived` (PBKDF2 of this
  /// install's pattern/PIN) or `imported` (a legacy key package, see
  /// `KeyBackupService`).  Kept for installs that imported a v1/v2 key
  /// package before the key ring existed (ISSUE-036).
  static const _sourceKey = 'privi_kek_source_v1';
  static const String sourceDerived = 'derived';
  static const String sourceImported = 'imported';

  static const int kekBytes = 32;

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

  /// Lazily loaded additional keys.  Dropped on [clearMemory] so a locked
  /// vault does not keep imported KEKs in memory.
  List<EncryptionKeyRecord>? _ringCache;

  Uint8List? get key => _kek;
  Uint8List? getKey() => _kek;
  String? get lockKind => _lockKind;
  bool get hasKey => _kek != null;

  /// Stable id of a KEK: `k_` + the first 16 hex chars of its SHA-256.
  ///
  /// Because it is a pure function of the key bytes, ids survive a device
  /// change and never collide with a different key.
  static String keyIdFor(Uint8List kek) =>
      'k_${fingerprintOf(kek).substring(0, 16)}';

  static String fingerprintOf(Uint8List kek) => sha256.convert(kek).toString();

  /// Id of the key currently used to encrypt new files.
  String? currentKeyId() {
    final kek = _kek;
    return kek == null ? null : keyIdFor(kek);
  }

  /// This phone's default key id, available **while the vault is locked**.
  ///
  /// Computing an id only hashes key bytes — no credential is needed — so the
  /// launch-time backfill can stamp legacy rows before the user unlocks. Falls
  /// back to the persisted KEK when the in-memory copy was cleared on lock.
  Future<String?> defaultKeyId() async {
    final kek = _kek ?? await retrievePersistedKek();
    return kek == null ? null : keyIdFor(kek);
  }

  /// KEK for the key a media row was encrypted with.
  ///
  /// `null` (legacy rows, encrypted before the key ring existed) means the
  /// current default KEK.  Unknown ids resolve to `null` instead of silently
  /// falling back to a different key — trying the wrong KEK only produces a
  /// confusing "corrupted file" error.  Returns null while the vault is locked.
  Future<Uint8List?> keyForId(String? keyId) async {
    final kek = _kek;
    if (kek == null) return null;
    if (keyId == null || keyId.trim().isEmpty || keyId == keyIdFor(kek)) {
      return kek;
    }
    for (final record in await _loadRing()) {
      if (record.id == keyId) return record.kek;
    }
    return null;
  }

  /// Every key this install can decrypt with: the default key first, then the
  /// historical / imported ones.  Used by the vault backup exporter.
  Future<List<EncryptionKeyRecord>> listKeys() async {
    final records = <EncryptionKeyRecord>[];
    final kek = _kek ?? await retrievePersistedKek();
    if (kek != null) {
      records.add(
        EncryptionKeyRecord(
          id: keyIdFor(kek),
          kek: kek,
          fingerprint: fingerprintOf(kek),
          createdAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          label: '本机密钥',
          isDefault: true,
        ),
      );
    }
    final seen = records.map((record) => record.id).toSet();
    for (final record in await _loadRing()) {
      if (seen.add(record.id)) records.add(record);
    }
    return List.unmodifiable(records);
  }

  /// Registers [kek] as an additional key without touching the default key.
  ///
  /// Returns the (possibly already existing) record, so importing the same
  /// backup twice is a no-op and media rows keep pointing at a valid id.
  Future<EncryptionKeyRecord> registerKey(
    Uint8List kek, {
    String? label,
    String? salt,
    DateTime? createdAt,
  }) async {
    if (kek.length != kekBytes) {
      throw ArgumentError.value(kek.length, 'kek', 'must be 32 bytes');
    }
    final id = keyIdFor(kek);
    final defaultKek = _kek ?? await retrievePersistedKek();
    if (defaultKek != null && keyIdFor(defaultKek) == id) {
      final existing = await listKeys();
      return existing.first;
    }
    final ring = List<EncryptionKeyRecord>.from(await _loadRing());
    for (final record in ring) {
      if (record.id == id) return record;
    }
    final record = EncryptionKeyRecord(
      id: id,
      kek: kek,
      fingerprint: fingerprintOf(kek),
      createdAt: (createdAt ?? DateTime.now()).toUtc(),
      label: label,
      salt: salt,
    );
    ring.add(record);
    await _saveRing(ring);
    _ringCache = List.unmodifiable(ring);
    AppLogger.i(
      'EncryptionKeyManager',
      'registered imported/historical key $id (${ring.length} extra keys)',
    );
    return record;
  }

  /// Set KEK in memory and persist it to secure storage (all backends).
  ///
  /// If the vault was previously running on a *different* KEK (credential
  /// change, or a restore), that key is kept in the ring so files whose DEK
  /// rotation has not finished are still decryptable.
  Future<void> setKey(Uint8List kek, {String? lockKind}) async {
    final previous = _kek ?? await retrievePersistedKek();
    if (previous != null && !_sameBytes(previous, kek)) {
      await _rememberHistoricalKey(previous);
    }
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

  /// True when the persisted KEK came from a legacy imported key package.
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

  /// Legacy v1/v2 key packages replace the whole KEK.  New (v6) backups use
  /// [registerKey] instead and never call this.
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

  Future<List<EncryptionKeyRecord>> _loadRing() async {
    final cached = _ringCache;
    if (cached != null) return cached;
    for (var i = 0; i < _storages.length; i++) {
      try {
        final raw = await _storages[i].read(key: _ringStorageKey);
        if (raw == null || raw.isEmpty) continue;
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final entries = decoded['keys'];
        if (entries is! List) continue;
        final records = <EncryptionKeyRecord>[];
        for (final entry in entries) {
          final record = EncryptionKeyRecord.fromJson(entry);
          if (record != null) records.add(record);
        }
        _ringCache = List.unmodifiable(records);
        return _ringCache!;
      } catch (e) {
        AppLogger.w('EncryptionKeyManager', 'read key ring (backend $i): $e');
      }
    }
    _ringCache = const <EncryptionKeyRecord>[];
    return _ringCache!;
  }

  Future<void> _saveRing(List<EncryptionKeyRecord> records) async {
    final encoded = jsonEncode(<String, dynamic>{
      'version': 1,
      'keys': records.map((record) => record.toJson()).toList(),
    });
    for (var i = 0; i < _storages.length; i++) {
      try {
        await _storages[i].write(key: _ringStorageKey, value: encoded);
      } catch (e) {
        AppLogger.w('EncryptionKeyManager', 'write key ring (backend $i): $e');
      }
    }
  }

  Future<void> _rememberHistoricalKey(Uint8List kek) async {
    final id = keyIdFor(kek);
    final ring = List<EncryptionKeyRecord>.from(await _loadRing());
    if (ring.any((record) => record.id == id)) return;
    ring.add(
      EncryptionKeyRecord(
        id: id,
        kek: kek,
        fingerprint: fingerprintOf(kek),
        createdAt: DateTime.now().toUtc(),
        label: '历史密钥',
      ),
    );
    await _saveRing(ring);
    _ringCache = List.unmodifiable(ring);
  }

  /// Clear KEK from memory AND persistent storage.
  /// Used for credential reset; do NOT call on normal lock.
  Future<void> clear() async {
    _kek = null;
    _lockKind = null;
    _importedCache = null;
    _ringCache = null;
    for (var i = 0; i < _storages.length; i++) {
      try {
        await _storages[i].delete(key: _storageKey);
        await _storages[i].delete(key: _sourceKey);
        await _storages[i].delete(key: _ringStorageKey);
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
    _ringCache = null;
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

  static bool _sameBytes(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
