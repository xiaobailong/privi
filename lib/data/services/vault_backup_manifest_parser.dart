part of 'vault_backup_service.dart';

final class _VaultBackupManifestParser {
  const _VaultBackupManifestParser();

  static const _organization = _VaultBackupOrganizationParser();

  _BackupManifest parse(Map<String, dynamic> raw) {
    final version =
        raw['version'] == null ? 1 : _manifestInt(raw['version'], 'version');
    if (version < 1 || version > VaultBackupService.manifestVersion) {
      throw const VaultBackupException(
        VaultBackupErrorCode.unsupportedManifestVersion,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    if (version >= VaultBackupService.manifestVersion) {
      return _parseDataOnly(raw, version);
    }
    final strict = version >= VaultBackupService.strictManifestVersion;
    return _BackupManifest(
      version: version,
      exportedAt: _manifestDate(
        raw['exportedAt'],
        'exportedAt',
        strict: strict,
        required: strict,
      ),
      verifiedAt: _manifestDate(
        raw['verifiedAt'],
        'verifiedAt',
        strict: strict,
        required: strict,
      ),
      declaredItemCount: strict
          ? _manifestInt(raw['itemCount'], 'itemCount')
          : _optionalManifestInt(raw['itemCount'], 'itemCount'),
      declaredTotalBytes: strict
          ? _manifestInt(raw['totalBytes'], 'totalBytes')
          : _optionalManifestInt(raw['totalBytes'], 'totalBytes'),
      media: List.unmodifiable(
        _manifestObjects(raw['media'], 'media', required: strict).map(
          (entry) => _parseMedia(entry, version),
        ),
      ),
      albums: List.unmodifiable(
        _manifestObjects(raw['albums'], 'albums', required: strict).map(
          (entry) => _organization.parseAlbum(entry, version),
        ),
      ),
      groups: List.unmodifiable(
        _manifestObjects(
          raw['albumGroups'],
          'albumGroups',
          required: strict,
        ).map(
          (entry) => _organization.parseGroup(entry, version),
        ),
      ),
      memberships: List.unmodifiable(
        _manifestObjects(
          raw['membership'],
          'membership',
          required: strict,
        ).map(
          (entry) => _organization.parseMembership(entry, version),
        ),
      ),
      encryptionSalt:
          _optionalManifestString(raw['encryptionSalt'], 'encryptionSalt'),
    );
  }

  _ManifestMedia _parseMedia(Map<String, dynamic> raw, int version) {
    final strict = version >= VaultBackupService.strictManifestVersion;
    final fileName = _requiredManifestString(raw['file'], 'file');
    _validateBackupName(fileName);
    final id = strict
        ? _validatedBackupId(
            _requiredManifestString(raw['id'], 'media id'),
            'media id',
          )
        : switch (_optionalManifestString(raw['id'], 'media id')) {
            final value? => _validatedBackupId(value, 'media id'),
            null => null,
          };
    final thumbnailName = _optionalManifestString(raw['thumb'], 'thumb');
    if (thumbnailName != null) _validateBackupName(thumbnailName);
    final byteLength = strict
        ? _manifestInt(raw['byteLength'], 'byteLength')
        : _optionalManifestInt(raw['byteLength'], 'byteLength');
    if (byteLength != null && byteLength <= 0) {
      throw VaultBackupException(
        VaultBackupErrorCode.payloadEmpty,
        fileName: fileName,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    final sha256 = strict
        ? _requiredManifestString(raw['sha256'], 'sha256')
        : _optionalManifestString(raw['sha256'], 'sha256');
    if (sha256 != null && !_isSha256Digest(sha256)) {
      throw VaultBackupException(
        VaultBackupErrorCode.payloadDigestMismatch,
        fileName: fileName,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    final originalName = strict
        ? _requiredManifestString(raw['originalName'], 'originalName')
        : _optionalManifestString(raw['originalName'], 'originalName');
    final mimeType = strict
        ? _requiredManifestString(raw['mimeType'], 'mimeType')
        : _optionalManifestString(raw['mimeType'], 'mimeType');
    final isVideo = strict
        ? _optionalManifestBool(raw['isVideo'], 'isVideo') ??
            (throw const VaultBackupException(
              VaultBackupErrorCode.malformedManifest,
              fileName: 'isVideo',
              stage: VaultBackupStage.checkingBackup,
            ))
        : _optionalManifestBool(raw['isVideo'], 'isVideo');
    final rating = strict
        ? _optionalManifestInt(raw['rating'], 'rating') ??
            (throw const VaultBackupException(
              VaultBackupErrorCode.malformedManifest,
              fileName: 'rating',
              stage: VaultBackupStage.checkingBackup,
            ))
        : _optionalManifestInt(raw['rating'], 'rating');
    if (rating != null && (rating < 0 || rating > 3)) {
      throw const VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        fileName: 'rating',
        stage: VaultBackupStage.checkingBackup,
      );
    }
    final sizeBytes = strict
        ? _manifestInt(raw['sizeBytes'], 'sizeBytes')
        : _optionalManifestInt(raw['sizeBytes'], 'sizeBytes');
    if (sizeBytes != null && sizeBytes < 0) {
      throw const VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        fileName: 'sizeBytes',
        stage: VaultBackupStage.checkingBackup,
      );
    }
    if (strict && sizeBytes != byteLength) {
      _throwMalformedManifest('sizeBytes');
    }
    final contentDigest =
        _optionalManifestString(raw['contentDigest'], 'contentDigest');
    if (strict && contentDigest != null && !_isSha256Digest(contentDigest)) {
      throw VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        fileName: originalName,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    if (strict && contentDigest != null && contentDigest != sha256) {
      _throwMalformedManifest(originalName ?? fileName);
    }
    final sourceRemovalPending = _optionalManifestBool(
      raw['sourceRemovalPending'],
      'sourceRemovalPending',
    );
    if (strict && sourceRemovalPending == null) {
      _throwMalformedManifest('sourceRemovalPending');
    }
    return _ManifestMedia(
      id: id,
      fileName: fileName,
      thumbnailName: thumbnailName,
      sha256: sha256,
      byteLength: byteLength,
      originalPath: _optionalManifestString(
        raw['originalPath'],
        'originalPath',
      ),
      source: version >= 4 ? _parseSource(raw['source']) : null,
      sourceRemovalPending:
          version >= 4 ? sourceRemovalPending ?? false : false,
      contentDigest: version >= 4 ? contentDigest : null,
      originalName: originalName,
      mimeType: mimeType,
      isVideo: isVideo,
      width: _nonNegativeInt(raw['width'], 'width'),
      height: _nonNegativeInt(raw['height'], 'height'),
      durationMs: _nonNegativeInt(raw['durationMs'], 'durationMs'),
      rating: rating,
      dateAdded: _manifestDate(
        raw['dateAdded'],
        'dateAdded',
        strict: strict,
        required: strict,
      ),
      dateTaken: _manifestDate(
        raw['dateTaken'],
        'dateTaken',
        strict: strict,
        required: false,
      ),
      sizeBytes: sizeBytes,
      deletedAt: _manifestDate(
        raw['deletedAt'],
        'deletedAt',
        strict: strict,
        required: false,
      ),
      // Optional: absent in backups made before file encryption (ISSUE-029).
      encryptedDek:
          _optionalManifestString(raw['encryptedDek'], 'encryptedDek'),
    );
  }

  /// v6: data-only snapshot. Media entries no longer carry a payload, so the
  /// checksum/length rules of v1..v5 do not apply; keys and settings are new
  /// top-level sections.
  _BackupManifest _parseDataOnly(Map<String, dynamic> raw, int version) {
    final media = _manifestObjects(raw['media'], 'media', required: true)
        .map(_parseV6Media)
        .toList(growable: false);
    return _BackupManifest(
      version: version,
      exportedAt: _manifestDate(
        raw['exportedAt'],
        'exportedAt',
        strict: true,
        required: true,
      ),
      verifiedAt: _manifestDate(
        raw['verifiedAt'],
        'verifiedAt',
        strict: true,
        required: true,
      ),
      declaredItemCount: _manifestInt(raw['itemCount'], 'itemCount'),
      declaredTotalBytes: _manifestInt(raw['totalBytes'], 'totalBytes'),
      media: List.unmodifiable(media),
      albums: List.unmodifiable(
        _manifestObjects(raw['albums'], 'albums', required: true)
            .map((entry) => _organization.parseAlbum(entry, version)),
      ),
      groups: List.unmodifiable(
        _manifestObjects(raw['albumGroups'], 'albumGroups', required: true)
            .map((entry) => _organization.parseGroup(entry, version)),
      ),
      memberships: List.unmodifiable(
        _manifestObjects(raw['membership'], 'membership', required: true)
            .map((entry) => _organization.parseMembership(entry, version)),
      ),
      encryptionSalt:
          _optionalManifestString(raw['encryptionSalt'], 'encryptionSalt'),
      encryptionKeys: _parseV6Keys(raw['encryptionKeys']),
      appSettings: _parseV6Settings(raw['appSettings']),
      defaultKeyId:
          _optionalManifestString(raw['defaultKeyId'], 'defaultKeyId'),
      includesMedia:
          _optionalManifestBool(raw['includesMedia'], 'includesMedia') ?? true,
    );
  }

  _ManifestMedia _parseV6Media(Map<String, dynamic> raw) {
    final fileName = _requiredManifestString(raw['file'], 'file');
    _validateBackupName(fileName);
    final id = _validatedBackupId(
      _requiredManifestString(raw['id'], 'media id'),
      'media id',
    );
    final byteLength = _optionalManifestInt(raw['byteLength'], 'byteLength');
    final sha256 = _optionalManifestString(raw['sha256'], 'sha256');
    final rating = _optionalManifestInt(raw['rating'], 'rating') ?? 0;
    if (rating < 0 || rating > 3) {
      _throwMalformedManifest('rating');
    }
    final contentDigest =
        _optionalManifestString(raw['contentDigest'], 'contentDigest');
    return _ManifestMedia(
      id: id,
      fileName: fileName,
      thumbnailName: _optionalManifestString(raw['thumb'], 'thumb'),
      sha256: sha256,
      byteLength: byteLength,
      originalPath:
          _optionalManifestString(raw['originalPath'], 'originalPath'),
      source: _parseSource(raw['source']),
      sourceRemovalPending: _optionalManifestBool(
              raw['sourceRemovalPending'], 'sourceRemovalPending') ??
          false,
      contentDigest: contentDigest,
      originalName:
          _optionalManifestString(raw['originalName'], 'originalName'),
      mimeType: _optionalManifestString(raw['mimeType'], 'mimeType'),
      isVideo: _optionalManifestBool(raw['isVideo'], 'isVideo') ?? false,
      width: _nonNegativeInt(raw['width'], 'width'),
      height: _nonNegativeInt(raw['height'], 'height'),
      durationMs: _nonNegativeInt(raw['durationMs'], 'durationMs'),
      rating: rating,
      dateAdded: _manifestDate(
        raw['dateAdded'],
        'dateAdded',
        strict: true,
        required: true,
      ),
      dateTaken: _manifestDate(
        raw['dateTaken'],
        'dateTaken',
        strict: true,
        required: false,
      ),
      sizeBytes: _optionalManifestInt(raw['sizeBytes'], 'sizeBytes'),
      deletedAt: _manifestDate(
        raw['deletedAt'],
        'deletedAt',
        strict: true,
        required: false,
      ),
      encryptedDek:
          _optionalManifestString(raw['encryptedDek'], 'encryptedDek'),
      encryptionKeyId:
          _optionalManifestString(raw['encryptionKeyId'], 'encryptionKeyId'),
      privatePath: _optionalManifestString(raw['privatePath'], 'privatePath'),
      thumbnailPath:
          _optionalManifestString(raw['thumbnailPath'], 'thumbnailPath'),
      playCount: _optionalManifestInt(raw['playCount'], 'playCount'),
      lastPlayedAt: _manifestDate(
        raw['lastPlayedAt'],
        'lastPlayedAt',
        strict: true,
        required: false,
      ),
    );
  }

  List<_ManifestKey> _parseV6Keys(Object? value) {
    if (value == null) return const <_ManifestKey>[];
    if (value is! List) _throwMalformedManifest('encryptionKeys');
    final keys = <_ManifestKey>[];
    for (final entry in value) {
      if (entry is! Map) _throwMalformedManifest('encryptionKeys');
      final json = Map<String, dynamic>.from(entry);
      final id = _requiredManifestString(json['id'], 'encryptionKeys.id');
      final kek = _requiredManifestString(json['kek'], 'encryptionKeys.kek');
      try {
        if (base64Decode(kek).length != EncryptionKeyManager.kekBytes) {
          _throwMalformedManifest('encryptionKeys.kek');
        }
      } on FormatException {
        _throwMalformedManifest('encryptionKeys.kek');
      }
      keys.add(
        _ManifestKey(
          id: id,
          kekBase64: kek,
          fingerprint: _optionalManifestString(
                json['fingerprint'],
                'encryptionKeys.fingerprint',
              ) ??
              '',
          createdAt: _manifestDate(
            json['createdAt'],
            'encryptionKeys.createdAt',
            strict: true,
            required: false,
          ),
          label: _optionalManifestString(json['label'], 'encryptionKeys.label'),
          salt: _optionalManifestString(json['salt'], 'encryptionKeys.salt'),
          isDefault: json['isDefault'] == true,
        ),
      );
    }
    return List.unmodifiable(keys);
  }

  Map<String, Object?> _parseV6Settings(Object? value) {
    if (value == null) return const <String, Object?>{};
    if (value is! Map) _throwMalformedManifest('appSettings');
    final map = Map<String, dynamic>.from(value);
    final settings = <String, Object?>{};
    map.forEach((key, entry) {
      if (entry is bool || entry is int || entry is double || entry is String) {
        settings[key] = entry;
      } else if (entry is List && entry.every((item) => item is String)) {
        settings[key] = List<String>.from(entry);
      }
    });
    return settings;
  }

  _ManifestSource? _parseSource(Object? value) {
    if (value == null) return null;
    if (value is! Map) {
      throw const VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        fileName: 'source',
        stage: VaultBackupStage.checkingBackup,
      );
    }
    return _ManifestSource(
      platform: _requiredManifestString(value['platform'], 'source.platform'),
      libraryId:
          _requiredManifestString(value['libraryId'], 'source.libraryId'),
    );
  }

  int? _nonNegativeInt(Object? value, String label) {
    final parsed = _optionalManifestInt(value, label);
    if (parsed != null && parsed < 0) {
      throw VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        fileName: label,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    return parsed;
  }

  List<Map<String, dynamic>> _manifestObjects(
    Object? value,
    String label, {
    required bool required,
  }) {
    if (value == null) {
      if (required) _throwMalformedManifest(label);
      return const [];
    }
    if (value is! List) {
      throw VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        fileName: label,
        stage: VaultBackupStage.checkingBackup,
      );
    }
    try {
      return value.map((entry) {
        if (entry is! Map) {
          throw VaultBackupException(
            VaultBackupErrorCode.malformedManifest,
            fileName: label,
            stage: VaultBackupStage.checkingBackup,
          );
        }
        return Map<String, dynamic>.from(entry);
      }).toList(growable: false);
    } on VaultBackupException {
      rethrow;
    } catch (error) {
      throw VaultBackupException(
        VaultBackupErrorCode.malformedManifest,
        fileName: label,
        stage: VaultBackupStage.checkingBackup,
        cause: error,
      );
    }
  }
}
