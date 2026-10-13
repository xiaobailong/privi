// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $MediaItemsTable extends MediaItems
    with TableInfo<$MediaItemsTable, MediaItemRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _privatePathMeta =
      const VerificationMeta('privatePath');
  @override
  late final GeneratedColumn<String> privatePath = GeneratedColumn<String>(
      'private_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _originalPathMeta =
      const VerificationMeta('originalPath');
  @override
  late final GeneratedColumn<String> originalPath = GeneratedColumn<String>(
      'original_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _originalNameMeta =
      const VerificationMeta('originalName');
  @override
  late final GeneratedColumn<String> originalName = GeneratedColumn<String>(
      'original_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _mimeTypeMeta =
      const VerificationMeta('mimeType');
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
      'mime_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isVideoMeta =
      const VerificationMeta('isVideo');
  @override
  late final GeneratedColumn<bool> isVideo = GeneratedColumn<bool>(
      'is_video', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_video" IN (0, 1))'));
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<int> width = GeneratedColumn<int>(
      'width', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _heightMeta = const VerificationMeta('height');
  @override
  late final GeneratedColumn<int> height = GeneratedColumn<int>(
      'height', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _durationMsMeta =
      const VerificationMeta('durationMs');
  @override
  late final GeneratedColumn<int> durationMs = GeneratedColumn<int>(
      'duration_ms', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<int> rating = GeneratedColumn<int>(
      'rating', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _dateAddedMeta =
      const VerificationMeta('dateAdded');
  @override
  late final GeneratedColumn<DateTime> dateAdded = GeneratedColumn<DateTime>(
      'date_added', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _dateTakenMeta =
      const VerificationMeta('dateTaken');
  @override
  late final GeneratedColumn<DateTime> dateTaken = GeneratedColumn<DateTime>(
      'date_taken', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _sizeBytesMeta =
      const VerificationMeta('sizeBytes');
  @override
  late final GeneratedColumn<int> sizeBytes = GeneratedColumn<int>(
      'size_bytes', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _thumbnailPathMeta =
      const VerificationMeta('thumbnailPath');
  @override
  late final GeneratedColumn<String> thumbnailPath = GeneratedColumn<String>(
      'thumbnail_path', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _deletedAtMeta =
      const VerificationMeta('deletedAt');
  @override
  late final GeneratedColumn<DateTime> deletedAt = GeneratedColumn<DateTime>(
      'deleted_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _sourcePlatformIdMeta =
      const VerificationMeta('sourcePlatformId');
  @override
  late final GeneratedColumn<String> sourcePlatformId = GeneratedColumn<String>(
      'source_platform_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _sourceRemovalPendingMeta =
      const VerificationMeta('sourceRemovalPending');
  @override
  late final GeneratedColumn<bool> sourceRemovalPending = GeneratedColumn<bool>(
      'source_removal_pending', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("source_removal_pending" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _contentDigestMeta =
      const VerificationMeta('contentDigest');
  @override
  late final GeneratedColumn<String> contentDigest = GeneratedColumn<String>(
      'content_digest', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _playCountMeta =
      const VerificationMeta('playCount');
  @override
  late final GeneratedColumn<int> playCount = GeneratedColumn<int>(
      'play_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastPlayedAtMeta =
      const VerificationMeta('lastPlayedAt');
  @override
  late final GeneratedColumn<DateTime> lastPlayedAt = GeneratedColumn<DateTime>(
      'last_played_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _encryptedDekMeta =
      const VerificationMeta('encryptedDek');
  @override
  late final GeneratedColumn<String> encryptedDek = GeneratedColumn<String>(
      'encrypted_dek', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        privatePath,
        originalPath,
        originalName,
        mimeType,
        isVideo,
        width,
        height,
        durationMs,
        rating,
        dateAdded,
        dateTaken,
        sizeBytes,
        thumbnailPath,
        deletedAt,
        sourcePlatformId,
        sourceRemovalPending,
        contentDigest,
        playCount,
        lastPlayedAt,
        encryptedDek
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media_items';
  @override
  VerificationContext validateIntegrity(Insertable<MediaItemRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('private_path')) {
      context.handle(
          _privatePathMeta,
          privatePath.isAcceptableOrUnknown(
              data['private_path']!, _privatePathMeta));
    } else if (isInserting) {
      context.missing(_privatePathMeta);
    }
    if (data.containsKey('original_path')) {
      context.handle(
          _originalPathMeta,
          originalPath.isAcceptableOrUnknown(
              data['original_path']!, _originalPathMeta));
    }
    if (data.containsKey('original_name')) {
      context.handle(
          _originalNameMeta,
          originalName.isAcceptableOrUnknown(
              data['original_name']!, _originalNameMeta));
    } else if (isInserting) {
      context.missing(_originalNameMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(_mimeTypeMeta,
          mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta));
    } else if (isInserting) {
      context.missing(_mimeTypeMeta);
    }
    if (data.containsKey('is_video')) {
      context.handle(_isVideoMeta,
          isVideo.isAcceptableOrUnknown(data['is_video']!, _isVideoMeta));
    } else if (isInserting) {
      context.missing(_isVideoMeta);
    }
    if (data.containsKey('width')) {
      context.handle(
          _widthMeta, width.isAcceptableOrUnknown(data['width']!, _widthMeta));
    }
    if (data.containsKey('height')) {
      context.handle(_heightMeta,
          height.isAcceptableOrUnknown(data['height']!, _heightMeta));
    }
    if (data.containsKey('duration_ms')) {
      context.handle(
          _durationMsMeta,
          durationMs.isAcceptableOrUnknown(
              data['duration_ms']!, _durationMsMeta));
    }
    if (data.containsKey('rating')) {
      context.handle(_ratingMeta,
          rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta));
    }
    if (data.containsKey('date_added')) {
      context.handle(_dateAddedMeta,
          dateAdded.isAcceptableOrUnknown(data['date_added']!, _dateAddedMeta));
    } else if (isInserting) {
      context.missing(_dateAddedMeta);
    }
    if (data.containsKey('date_taken')) {
      context.handle(_dateTakenMeta,
          dateTaken.isAcceptableOrUnknown(data['date_taken']!, _dateTakenMeta));
    }
    if (data.containsKey('size_bytes')) {
      context.handle(_sizeBytesMeta,
          sizeBytes.isAcceptableOrUnknown(data['size_bytes']!, _sizeBytesMeta));
    } else if (isInserting) {
      context.missing(_sizeBytesMeta);
    }
    if (data.containsKey('thumbnail_path')) {
      context.handle(
          _thumbnailPathMeta,
          thumbnailPath.isAcceptableOrUnknown(
              data['thumbnail_path']!, _thumbnailPathMeta));
    }
    if (data.containsKey('deleted_at')) {
      context.handle(_deletedAtMeta,
          deletedAt.isAcceptableOrUnknown(data['deleted_at']!, _deletedAtMeta));
    }
    if (data.containsKey('source_platform_id')) {
      context.handle(
          _sourcePlatformIdMeta,
          sourcePlatformId.isAcceptableOrUnknown(
              data['source_platform_id']!, _sourcePlatformIdMeta));
    }
    if (data.containsKey('source_removal_pending')) {
      context.handle(
          _sourceRemovalPendingMeta,
          sourceRemovalPending.isAcceptableOrUnknown(
              data['source_removal_pending']!, _sourceRemovalPendingMeta));
    }
    if (data.containsKey('content_digest')) {
      context.handle(
          _contentDigestMeta,
          contentDigest.isAcceptableOrUnknown(
              data['content_digest']!, _contentDigestMeta));
    }
    if (data.containsKey('play_count')) {
      context.handle(_playCountMeta,
          playCount.isAcceptableOrUnknown(data['play_count']!, _playCountMeta));
    }
    if (data.containsKey('last_played_at')) {
      context.handle(
          _lastPlayedAtMeta,
          lastPlayedAt.isAcceptableOrUnknown(
              data['last_played_at']!, _lastPlayedAtMeta));
    }
    if (data.containsKey('encrypted_dek')) {
      context.handle(
          _encryptedDekMeta,
          encryptedDek.isAcceptableOrUnknown(
              data['encrypted_dek']!, _encryptedDekMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MediaItemRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaItemRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      privatePath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}private_path'])!,
      originalPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}original_path']),
      originalName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}original_name'])!,
      mimeType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}mime_type'])!,
      isVideo: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_video'])!,
      width: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}width']),
      height: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}height']),
      durationMs: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}duration_ms']),
      rating: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}rating'])!,
      dateAdded: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}date_added'])!,
      dateTaken: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}date_taken']),
      sizeBytes: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}size_bytes'])!,
      thumbnailPath: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}thumbnail_path']),
      deletedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}deleted_at']),
      sourcePlatformId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}source_platform_id']),
      sourceRemovalPending: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}source_removal_pending'])!,
      contentDigest: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content_digest']),
      playCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}play_count'])!,
      lastPlayedAt: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_played_at']),
      encryptedDek: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}encrypted_dek']),
    );
  }

  @override
  $MediaItemsTable createAlias(String alias) {
    return $MediaItemsTable(attachedDatabase, alias);
  }
}

class MediaItemRow extends DataClass implements Insertable<MediaItemRow> {
  final String id;
  final String privatePath;

  /// Absolute path before hide (for unhide restore). Null for legacy rows.
  final String? originalPath;
  final String originalName;
  final String mimeType;
  final bool isVideo;
  final int? width;
  final int? height;
  final int? durationMs;
  final int rating;
  final DateTime dateAdded;
  final DateTime? dateTaken;
  final int sizeBytes;
  final String? thumbnailPath;
  final DateTime? deletedAt;

  /// Opaque source identity; iOS stores the PhotoKit localIdentifier here.
  final String? sourcePlatformId;

  /// A verified vault copy whose system-library source still exists.
  final bool sourceRemovalPending;

  /// SHA-256 of the verified private media bytes.
  final String? contentDigest;

  /// How often the item was played. Random playback reads this back and lowers
  /// the odds of replaying items that already had their turn.
  final int playCount;

  /// Last playback time; null when the item was never played.
  final DateTime? lastPlayedAt;

  /// AES-256-GCM encrypted DEK (base64). Null for legacy plaintext rows.
  final String? encryptedDek;
  const MediaItemRow(
      {required this.id,
      required this.privatePath,
      this.originalPath,
      required this.originalName,
      required this.mimeType,
      required this.isVideo,
      this.width,
      this.height,
      this.durationMs,
      required this.rating,
      required this.dateAdded,
      this.dateTaken,
      required this.sizeBytes,
      this.thumbnailPath,
      this.deletedAt,
      this.sourcePlatformId,
      required this.sourceRemovalPending,
      this.contentDigest,
      required this.playCount,
      this.lastPlayedAt,
      this.encryptedDek});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['private_path'] = Variable<String>(privatePath);
    if (!nullToAbsent || originalPath != null) {
      map['original_path'] = Variable<String>(originalPath);
    }
    map['original_name'] = Variable<String>(originalName);
    map['mime_type'] = Variable<String>(mimeType);
    map['is_video'] = Variable<bool>(isVideo);
    if (!nullToAbsent || width != null) {
      map['width'] = Variable<int>(width);
    }
    if (!nullToAbsent || height != null) {
      map['height'] = Variable<int>(height);
    }
    if (!nullToAbsent || durationMs != null) {
      map['duration_ms'] = Variable<int>(durationMs);
    }
    map['rating'] = Variable<int>(rating);
    map['date_added'] = Variable<DateTime>(dateAdded);
    if (!nullToAbsent || dateTaken != null) {
      map['date_taken'] = Variable<DateTime>(dateTaken);
    }
    map['size_bytes'] = Variable<int>(sizeBytes);
    if (!nullToAbsent || thumbnailPath != null) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath);
    }
    if (!nullToAbsent || deletedAt != null) {
      map['deleted_at'] = Variable<DateTime>(deletedAt);
    }
    if (!nullToAbsent || sourcePlatformId != null) {
      map['source_platform_id'] = Variable<String>(sourcePlatformId);
    }
    map['source_removal_pending'] = Variable<bool>(sourceRemovalPending);
    if (!nullToAbsent || contentDigest != null) {
      map['content_digest'] = Variable<String>(contentDigest);
    }
    map['play_count'] = Variable<int>(playCount);
    if (!nullToAbsent || lastPlayedAt != null) {
      map['last_played_at'] = Variable<DateTime>(lastPlayedAt);
    }
    if (!nullToAbsent || encryptedDek != null) {
      map['encrypted_dek'] = Variable<String>(encryptedDek);
    }
    return map;
  }

  MediaItemsCompanion toCompanion(bool nullToAbsent) {
    return MediaItemsCompanion(
      id: Value(id),
      privatePath: Value(privatePath),
      originalPath: originalPath == null && nullToAbsent
          ? const Value.absent()
          : Value(originalPath),
      originalName: Value(originalName),
      mimeType: Value(mimeType),
      isVideo: Value(isVideo),
      width:
          width == null && nullToAbsent ? const Value.absent() : Value(width),
      height:
          height == null && nullToAbsent ? const Value.absent() : Value(height),
      durationMs: durationMs == null && nullToAbsent
          ? const Value.absent()
          : Value(durationMs),
      rating: Value(rating),
      dateAdded: Value(dateAdded),
      dateTaken: dateTaken == null && nullToAbsent
          ? const Value.absent()
          : Value(dateTaken),
      sizeBytes: Value(sizeBytes),
      thumbnailPath: thumbnailPath == null && nullToAbsent
          ? const Value.absent()
          : Value(thumbnailPath),
      deletedAt: deletedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(deletedAt),
      sourcePlatformId: sourcePlatformId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourcePlatformId),
      sourceRemovalPending: Value(sourceRemovalPending),
      contentDigest: contentDigest == null && nullToAbsent
          ? const Value.absent()
          : Value(contentDigest),
      playCount: Value(playCount),
      lastPlayedAt: lastPlayedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPlayedAt),
      encryptedDek: encryptedDek == null && nullToAbsent
          ? const Value.absent()
          : Value(encryptedDek),
    );
  }

  factory MediaItemRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaItemRow(
      id: serializer.fromJson<String>(json['id']),
      privatePath: serializer.fromJson<String>(json['privatePath']),
      originalPath: serializer.fromJson<String?>(json['originalPath']),
      originalName: serializer.fromJson<String>(json['originalName']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      isVideo: serializer.fromJson<bool>(json['isVideo']),
      width: serializer.fromJson<int?>(json['width']),
      height: serializer.fromJson<int?>(json['height']),
      durationMs: serializer.fromJson<int?>(json['durationMs']),
      rating: serializer.fromJson<int>(json['rating']),
      dateAdded: serializer.fromJson<DateTime>(json['dateAdded']),
      dateTaken: serializer.fromJson<DateTime?>(json['dateTaken']),
      sizeBytes: serializer.fromJson<int>(json['sizeBytes']),
      thumbnailPath: serializer.fromJson<String?>(json['thumbnailPath']),
      deletedAt: serializer.fromJson<DateTime?>(json['deletedAt']),
      sourcePlatformId: serializer.fromJson<String?>(json['sourcePlatformId']),
      sourceRemovalPending:
          serializer.fromJson<bool>(json['sourceRemovalPending']),
      contentDigest: serializer.fromJson<String?>(json['contentDigest']),
      playCount: serializer.fromJson<int>(json['playCount']),
      lastPlayedAt: serializer.fromJson<DateTime?>(json['lastPlayedAt']),
      encryptedDek: serializer.fromJson<String?>(json['encryptedDek']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'privatePath': serializer.toJson<String>(privatePath),
      'originalPath': serializer.toJson<String?>(originalPath),
      'originalName': serializer.toJson<String>(originalName),
      'mimeType': serializer.toJson<String>(mimeType),
      'isVideo': serializer.toJson<bool>(isVideo),
      'width': serializer.toJson<int?>(width),
      'height': serializer.toJson<int?>(height),
      'durationMs': serializer.toJson<int?>(durationMs),
      'rating': serializer.toJson<int>(rating),
      'dateAdded': serializer.toJson<DateTime>(dateAdded),
      'dateTaken': serializer.toJson<DateTime?>(dateTaken),
      'sizeBytes': serializer.toJson<int>(sizeBytes),
      'thumbnailPath': serializer.toJson<String?>(thumbnailPath),
      'deletedAt': serializer.toJson<DateTime?>(deletedAt),
      'sourcePlatformId': serializer.toJson<String?>(sourcePlatformId),
      'sourceRemovalPending': serializer.toJson<bool>(sourceRemovalPending),
      'contentDigest': serializer.toJson<String?>(contentDigest),
      'playCount': serializer.toJson<int>(playCount),
      'lastPlayedAt': serializer.toJson<DateTime?>(lastPlayedAt),
      'encryptedDek': serializer.toJson<String?>(encryptedDek),
    };
  }

  MediaItemRow copyWith(
          {String? id,
          String? privatePath,
          Value<String?> originalPath = const Value.absent(),
          String? originalName,
          String? mimeType,
          bool? isVideo,
          Value<int?> width = const Value.absent(),
          Value<int?> height = const Value.absent(),
          Value<int?> durationMs = const Value.absent(),
          int? rating,
          DateTime? dateAdded,
          Value<DateTime?> dateTaken = const Value.absent(),
          int? sizeBytes,
          Value<String?> thumbnailPath = const Value.absent(),
          Value<DateTime?> deletedAt = const Value.absent(),
          Value<String?> sourcePlatformId = const Value.absent(),
          bool? sourceRemovalPending,
          Value<String?> contentDigest = const Value.absent(),
          int? playCount,
          Value<DateTime?> lastPlayedAt = const Value.absent(),
          Value<String?> encryptedDek = const Value.absent()}) =>
      MediaItemRow(
        id: id ?? this.id,
        privatePath: privatePath ?? this.privatePath,
        originalPath:
            originalPath.present ? originalPath.value : this.originalPath,
        originalName: originalName ?? this.originalName,
        mimeType: mimeType ?? this.mimeType,
        isVideo: isVideo ?? this.isVideo,
        width: width.present ? width.value : this.width,
        height: height.present ? height.value : this.height,
        durationMs: durationMs.present ? durationMs.value : this.durationMs,
        rating: rating ?? this.rating,
        dateAdded: dateAdded ?? this.dateAdded,
        dateTaken: dateTaken.present ? dateTaken.value : this.dateTaken,
        sizeBytes: sizeBytes ?? this.sizeBytes,
        thumbnailPath:
            thumbnailPath.present ? thumbnailPath.value : this.thumbnailPath,
        deletedAt: deletedAt.present ? deletedAt.value : this.deletedAt,
        sourcePlatformId: sourcePlatformId.present
            ? sourcePlatformId.value
            : this.sourcePlatformId,
        sourceRemovalPending: sourceRemovalPending ?? this.sourceRemovalPending,
        contentDigest:
            contentDigest.present ? contentDigest.value : this.contentDigest,
        playCount: playCount ?? this.playCount,
        lastPlayedAt:
            lastPlayedAt.present ? lastPlayedAt.value : this.lastPlayedAt,
        encryptedDek:
            encryptedDek.present ? encryptedDek.value : this.encryptedDek,
      );
  MediaItemRow copyWithCompanion(MediaItemsCompanion data) {
    return MediaItemRow(
      id: data.id.present ? data.id.value : this.id,
      privatePath:
          data.privatePath.present ? data.privatePath.value : this.privatePath,
      originalPath: data.originalPath.present
          ? data.originalPath.value
          : this.originalPath,
      originalName: data.originalName.present
          ? data.originalName.value
          : this.originalName,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      isVideo: data.isVideo.present ? data.isVideo.value : this.isVideo,
      width: data.width.present ? data.width.value : this.width,
      height: data.height.present ? data.height.value : this.height,
      durationMs:
          data.durationMs.present ? data.durationMs.value : this.durationMs,
      rating: data.rating.present ? data.rating.value : this.rating,
      dateAdded: data.dateAdded.present ? data.dateAdded.value : this.dateAdded,
      dateTaken: data.dateTaken.present ? data.dateTaken.value : this.dateTaken,
      sizeBytes: data.sizeBytes.present ? data.sizeBytes.value : this.sizeBytes,
      thumbnailPath: data.thumbnailPath.present
          ? data.thumbnailPath.value
          : this.thumbnailPath,
      deletedAt: data.deletedAt.present ? data.deletedAt.value : this.deletedAt,
      sourcePlatformId: data.sourcePlatformId.present
          ? data.sourcePlatformId.value
          : this.sourcePlatformId,
      sourceRemovalPending: data.sourceRemovalPending.present
          ? data.sourceRemovalPending.value
          : this.sourceRemovalPending,
      contentDigest: data.contentDigest.present
          ? data.contentDigest.value
          : this.contentDigest,
      playCount: data.playCount.present ? data.playCount.value : this.playCount,
      lastPlayedAt: data.lastPlayedAt.present
          ? data.lastPlayedAt.value
          : this.lastPlayedAt,
      encryptedDek: data.encryptedDek.present
          ? data.encryptedDek.value
          : this.encryptedDek,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaItemRow(')
          ..write('id: $id, ')
          ..write('privatePath: $privatePath, ')
          ..write('originalPath: $originalPath, ')
          ..write('originalName: $originalName, ')
          ..write('mimeType: $mimeType, ')
          ..write('isVideo: $isVideo, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('durationMs: $durationMs, ')
          ..write('rating: $rating, ')
          ..write('dateAdded: $dateAdded, ')
          ..write('dateTaken: $dateTaken, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('sourcePlatformId: $sourcePlatformId, ')
          ..write('sourceRemovalPending: $sourceRemovalPending, ')
          ..write('contentDigest: $contentDigest, ')
          ..write('playCount: $playCount, ')
          ..write('lastPlayedAt: $lastPlayedAt, ')
          ..write('encryptedDek: $encryptedDek')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        id,
        privatePath,
        originalPath,
        originalName,
        mimeType,
        isVideo,
        width,
        height,
        durationMs,
        rating,
        dateAdded,
        dateTaken,
        sizeBytes,
        thumbnailPath,
        deletedAt,
        sourcePlatformId,
        sourceRemovalPending,
        contentDigest,
        playCount,
        lastPlayedAt,
        encryptedDek
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaItemRow &&
          other.id == this.id &&
          other.privatePath == this.privatePath &&
          other.originalPath == this.originalPath &&
          other.originalName == this.originalName &&
          other.mimeType == this.mimeType &&
          other.isVideo == this.isVideo &&
          other.width == this.width &&
          other.height == this.height &&
          other.durationMs == this.durationMs &&
          other.rating == this.rating &&
          other.dateAdded == this.dateAdded &&
          other.dateTaken == this.dateTaken &&
          other.sizeBytes == this.sizeBytes &&
          other.thumbnailPath == this.thumbnailPath &&
          other.deletedAt == this.deletedAt &&
          other.sourcePlatformId == this.sourcePlatformId &&
          other.sourceRemovalPending == this.sourceRemovalPending &&
          other.contentDigest == this.contentDigest &&
          other.playCount == this.playCount &&
          other.lastPlayedAt == this.lastPlayedAt &&
          other.encryptedDek == this.encryptedDek);
}

class MediaItemsCompanion extends UpdateCompanion<MediaItemRow> {
  final Value<String> id;
  final Value<String> privatePath;
  final Value<String?> originalPath;
  final Value<String> originalName;
  final Value<String> mimeType;
  final Value<bool> isVideo;
  final Value<int?> width;
  final Value<int?> height;
  final Value<int?> durationMs;
  final Value<int> rating;
  final Value<DateTime> dateAdded;
  final Value<DateTime?> dateTaken;
  final Value<int> sizeBytes;
  final Value<String?> thumbnailPath;
  final Value<DateTime?> deletedAt;
  final Value<String?> sourcePlatformId;
  final Value<bool> sourceRemovalPending;
  final Value<String?> contentDigest;
  final Value<int> playCount;
  final Value<DateTime?> lastPlayedAt;
  final Value<String?> encryptedDek;
  final Value<int> rowid;
  const MediaItemsCompanion({
    this.id = const Value.absent(),
    this.privatePath = const Value.absent(),
    this.originalPath = const Value.absent(),
    this.originalName = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.isVideo = const Value.absent(),
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.rating = const Value.absent(),
    this.dateAdded = const Value.absent(),
    this.dateTaken = const Value.absent(),
    this.sizeBytes = const Value.absent(),
    this.thumbnailPath = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.sourcePlatformId = const Value.absent(),
    this.sourceRemovalPending = const Value.absent(),
    this.contentDigest = const Value.absent(),
    this.playCount = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
    this.encryptedDek = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MediaItemsCompanion.insert({
    required String id,
    required String privatePath,
    this.originalPath = const Value.absent(),
    required String originalName,
    required String mimeType,
    required bool isVideo,
    this.width = const Value.absent(),
    this.height = const Value.absent(),
    this.durationMs = const Value.absent(),
    this.rating = const Value.absent(),
    required DateTime dateAdded,
    this.dateTaken = const Value.absent(),
    required int sizeBytes,
    this.thumbnailPath = const Value.absent(),
    this.deletedAt = const Value.absent(),
    this.sourcePlatformId = const Value.absent(),
    this.sourceRemovalPending = const Value.absent(),
    this.contentDigest = const Value.absent(),
    this.playCount = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
    this.encryptedDek = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        privatePath = Value(privatePath),
        originalName = Value(originalName),
        mimeType = Value(mimeType),
        isVideo = Value(isVideo),
        dateAdded = Value(dateAdded),
        sizeBytes = Value(sizeBytes);
  static Insertable<MediaItemRow> custom({
    Expression<String>? id,
    Expression<String>? privatePath,
    Expression<String>? originalPath,
    Expression<String>? originalName,
    Expression<String>? mimeType,
    Expression<bool>? isVideo,
    Expression<int>? width,
    Expression<int>? height,
    Expression<int>? durationMs,
    Expression<int>? rating,
    Expression<DateTime>? dateAdded,
    Expression<DateTime>? dateTaken,
    Expression<int>? sizeBytes,
    Expression<String>? thumbnailPath,
    Expression<DateTime>? deletedAt,
    Expression<String>? sourcePlatformId,
    Expression<bool>? sourceRemovalPending,
    Expression<String>? contentDigest,
    Expression<int>? playCount,
    Expression<DateTime>? lastPlayedAt,
    Expression<String>? encryptedDek,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (privatePath != null) 'private_path': privatePath,
      if (originalPath != null) 'original_path': originalPath,
      if (originalName != null) 'original_name': originalName,
      if (mimeType != null) 'mime_type': mimeType,
      if (isVideo != null) 'is_video': isVideo,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (durationMs != null) 'duration_ms': durationMs,
      if (rating != null) 'rating': rating,
      if (dateAdded != null) 'date_added': dateAdded,
      if (dateTaken != null) 'date_taken': dateTaken,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (thumbnailPath != null) 'thumbnail_path': thumbnailPath,
      if (deletedAt != null) 'deleted_at': deletedAt,
      if (sourcePlatformId != null) 'source_platform_id': sourcePlatformId,
      if (sourceRemovalPending != null)
        'source_removal_pending': sourceRemovalPending,
      if (contentDigest != null) 'content_digest': contentDigest,
      if (playCount != null) 'play_count': playCount,
      if (lastPlayedAt != null) 'last_played_at': lastPlayedAt,
      if (encryptedDek != null) 'encrypted_dek': encryptedDek,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MediaItemsCompanion copyWith(
      {Value<String>? id,
      Value<String>? privatePath,
      Value<String?>? originalPath,
      Value<String>? originalName,
      Value<String>? mimeType,
      Value<bool>? isVideo,
      Value<int?>? width,
      Value<int?>? height,
      Value<int?>? durationMs,
      Value<int>? rating,
      Value<DateTime>? dateAdded,
      Value<DateTime?>? dateTaken,
      Value<int>? sizeBytes,
      Value<String?>? thumbnailPath,
      Value<DateTime?>? deletedAt,
      Value<String?>? sourcePlatformId,
      Value<bool>? sourceRemovalPending,
      Value<String?>? contentDigest,
      Value<int>? playCount,
      Value<DateTime?>? lastPlayedAt,
      Value<String?>? encryptedDek,
      Value<int>? rowid}) {
    return MediaItemsCompanion(
      id: id ?? this.id,
      privatePath: privatePath ?? this.privatePath,
      originalPath: originalPath ?? this.originalPath,
      originalName: originalName ?? this.originalName,
      mimeType: mimeType ?? this.mimeType,
      isVideo: isVideo ?? this.isVideo,
      width: width ?? this.width,
      height: height ?? this.height,
      durationMs: durationMs ?? this.durationMs,
      rating: rating ?? this.rating,
      dateAdded: dateAdded ?? this.dateAdded,
      dateTaken: dateTaken ?? this.dateTaken,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      deletedAt: deletedAt ?? this.deletedAt,
      sourcePlatformId: sourcePlatformId ?? this.sourcePlatformId,
      sourceRemovalPending: sourceRemovalPending ?? this.sourceRemovalPending,
      contentDigest: contentDigest ?? this.contentDigest,
      playCount: playCount ?? this.playCount,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      encryptedDek: encryptedDek ?? this.encryptedDek,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (privatePath.present) {
      map['private_path'] = Variable<String>(privatePath.value);
    }
    if (originalPath.present) {
      map['original_path'] = Variable<String>(originalPath.value);
    }
    if (originalName.present) {
      map['original_name'] = Variable<String>(originalName.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (isVideo.present) {
      map['is_video'] = Variable<bool>(isVideo.value);
    }
    if (width.present) {
      map['width'] = Variable<int>(width.value);
    }
    if (height.present) {
      map['height'] = Variable<int>(height.value);
    }
    if (durationMs.present) {
      map['duration_ms'] = Variable<int>(durationMs.value);
    }
    if (rating.present) {
      map['rating'] = Variable<int>(rating.value);
    }
    if (dateAdded.present) {
      map['date_added'] = Variable<DateTime>(dateAdded.value);
    }
    if (dateTaken.present) {
      map['date_taken'] = Variable<DateTime>(dateTaken.value);
    }
    if (sizeBytes.present) {
      map['size_bytes'] = Variable<int>(sizeBytes.value);
    }
    if (thumbnailPath.present) {
      map['thumbnail_path'] = Variable<String>(thumbnailPath.value);
    }
    if (deletedAt.present) {
      map['deleted_at'] = Variable<DateTime>(deletedAt.value);
    }
    if (sourcePlatformId.present) {
      map['source_platform_id'] = Variable<String>(sourcePlatformId.value);
    }
    if (sourceRemovalPending.present) {
      map['source_removal_pending'] =
          Variable<bool>(sourceRemovalPending.value);
    }
    if (contentDigest.present) {
      map['content_digest'] = Variable<String>(contentDigest.value);
    }
    if (playCount.present) {
      map['play_count'] = Variable<int>(playCount.value);
    }
    if (lastPlayedAt.present) {
      map['last_played_at'] = Variable<DateTime>(lastPlayedAt.value);
    }
    if (encryptedDek.present) {
      map['encrypted_dek'] = Variable<String>(encryptedDek.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaItemsCompanion(')
          ..write('id: $id, ')
          ..write('privatePath: $privatePath, ')
          ..write('originalPath: $originalPath, ')
          ..write('originalName: $originalName, ')
          ..write('mimeType: $mimeType, ')
          ..write('isVideo: $isVideo, ')
          ..write('width: $width, ')
          ..write('height: $height, ')
          ..write('durationMs: $durationMs, ')
          ..write('rating: $rating, ')
          ..write('dateAdded: $dateAdded, ')
          ..write('dateTaken: $dateTaken, ')
          ..write('sizeBytes: $sizeBytes, ')
          ..write('thumbnailPath: $thumbnailPath, ')
          ..write('deletedAt: $deletedAt, ')
          ..write('sourcePlatformId: $sourcePlatformId, ')
          ..write('sourceRemovalPending: $sourceRemovalPending, ')
          ..write('contentDigest: $contentDigest, ')
          ..write('playCount: $playCount, ')
          ..write('lastPlayedAt: $lastPlayedAt, ')
          ..write('encryptedDek: $encryptedDek, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AlbumsTable extends Albums with TableInfo<$AlbumsTable, AlbumRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AlbumsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isSystemMeta =
      const VerificationMeta('isSystem');
  @override
  late final GeneratedColumn<bool> isSystem = GeneratedColumn<bool>(
      'is_system', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_system" IN (0, 1))'));
  static const VerificationMeta _coverMediaIdMeta =
      const VerificationMeta('coverMediaId');
  @override
  late final GeneratedColumn<String> coverMediaId = GeneratedColumn<String>(
      'cover_media_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _systemKindMeta =
      const VerificationMeta('systemKind');
  @override
  late final GeneratedColumn<String> systemKind = GeneratedColumn<String>(
      'system_kind', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _pinnedAtMeta =
      const VerificationMeta('pinnedAt');
  @override
  late final GeneratedColumn<DateTime> pinnedAt = GeneratedColumn<DateTime>(
      'pinned_at', aliasedName, true,
      type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<int> rating = GeneratedColumn<int>(
      'rating', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _sortIndexMeta =
      const VerificationMeta('sortIndex');
  @override
  late final GeneratedColumn<int> sortIndex = GeneratedColumn<int>(
      'sort_index', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _groupIdMeta =
      const VerificationMeta('groupId');
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
      'group_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        name,
        isSystem,
        coverMediaId,
        createdAt,
        systemKind,
        pinnedAt,
        rating,
        sortIndex,
        groupId
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'albums';
  @override
  VerificationContext validateIntegrity(Insertable<AlbumRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('is_system')) {
      context.handle(_isSystemMeta,
          isSystem.isAcceptableOrUnknown(data['is_system']!, _isSystemMeta));
    } else if (isInserting) {
      context.missing(_isSystemMeta);
    }
    if (data.containsKey('cover_media_id')) {
      context.handle(
          _coverMediaIdMeta,
          coverMediaId.isAcceptableOrUnknown(
              data['cover_media_id']!, _coverMediaIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('system_kind')) {
      context.handle(
          _systemKindMeta,
          systemKind.isAcceptableOrUnknown(
              data['system_kind']!, _systemKindMeta));
    }
    if (data.containsKey('pinned_at')) {
      context.handle(_pinnedAtMeta,
          pinnedAt.isAcceptableOrUnknown(data['pinned_at']!, _pinnedAtMeta));
    }
    if (data.containsKey('rating')) {
      context.handle(_ratingMeta,
          rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta));
    }
    if (data.containsKey('sort_index')) {
      context.handle(_sortIndexMeta,
          sortIndex.isAcceptableOrUnknown(data['sort_index']!, _sortIndexMeta));
    }
    if (data.containsKey('group_id')) {
      context.handle(_groupIdMeta,
          groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AlbumRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AlbumRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      isSystem: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_system'])!,
      coverMediaId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}cover_media_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      systemKind: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}system_kind']),
      pinnedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}pinned_at']),
      rating: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}rating'])!,
      sortIndex: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_index']),
      groupId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}group_id']),
    );
  }

  @override
  $AlbumsTable createAlias(String alias) {
    return $AlbumsTable(attachedDatabase, alias);
  }
}

class AlbumRow extends DataClass implements Insertable<AlbumRow> {
  final String id;
  final String name;
  final bool isSystem;
  final String? coverMediaId;
  final DateTime createdAt;
  final String? systemKind;

  /// When set, album is pinned to the top of the Invisible mosaic.
  final DateTime? pinnedAt;

  /// 0-3 hearts for user albums. System albums keep the default value.
  final int rating;

  /// User-defined position within the top level or an album group.
  final int? sortIndex;

  /// Owning group, or null when the album is shown at the top level.
  final String? groupId;
  const AlbumRow(
      {required this.id,
      required this.name,
      required this.isSystem,
      this.coverMediaId,
      required this.createdAt,
      this.systemKind,
      this.pinnedAt,
      required this.rating,
      this.sortIndex,
      this.groupId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['is_system'] = Variable<bool>(isSystem);
    if (!nullToAbsent || coverMediaId != null) {
      map['cover_media_id'] = Variable<String>(coverMediaId);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || systemKind != null) {
      map['system_kind'] = Variable<String>(systemKind);
    }
    if (!nullToAbsent || pinnedAt != null) {
      map['pinned_at'] = Variable<DateTime>(pinnedAt);
    }
    map['rating'] = Variable<int>(rating);
    if (!nullToAbsent || sortIndex != null) {
      map['sort_index'] = Variable<int>(sortIndex);
    }
    if (!nullToAbsent || groupId != null) {
      map['group_id'] = Variable<String>(groupId);
    }
    return map;
  }

  AlbumsCompanion toCompanion(bool nullToAbsent) {
    return AlbumsCompanion(
      id: Value(id),
      name: Value(name),
      isSystem: Value(isSystem),
      coverMediaId: coverMediaId == null && nullToAbsent
          ? const Value.absent()
          : Value(coverMediaId),
      createdAt: Value(createdAt),
      systemKind: systemKind == null && nullToAbsent
          ? const Value.absent()
          : Value(systemKind),
      pinnedAt: pinnedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(pinnedAt),
      rating: Value(rating),
      sortIndex: sortIndex == null && nullToAbsent
          ? const Value.absent()
          : Value(sortIndex),
      groupId: groupId == null && nullToAbsent
          ? const Value.absent()
          : Value(groupId),
    );
  }

  factory AlbumRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AlbumRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      isSystem: serializer.fromJson<bool>(json['isSystem']),
      coverMediaId: serializer.fromJson<String?>(json['coverMediaId']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      systemKind: serializer.fromJson<String?>(json['systemKind']),
      pinnedAt: serializer.fromJson<DateTime?>(json['pinnedAt']),
      rating: serializer.fromJson<int>(json['rating']),
      sortIndex: serializer.fromJson<int?>(json['sortIndex']),
      groupId: serializer.fromJson<String?>(json['groupId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'isSystem': serializer.toJson<bool>(isSystem),
      'coverMediaId': serializer.toJson<String?>(coverMediaId),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'systemKind': serializer.toJson<String?>(systemKind),
      'pinnedAt': serializer.toJson<DateTime?>(pinnedAt),
      'rating': serializer.toJson<int>(rating),
      'sortIndex': serializer.toJson<int?>(sortIndex),
      'groupId': serializer.toJson<String?>(groupId),
    };
  }

  AlbumRow copyWith(
          {String? id,
          String? name,
          bool? isSystem,
          Value<String?> coverMediaId = const Value.absent(),
          DateTime? createdAt,
          Value<String?> systemKind = const Value.absent(),
          Value<DateTime?> pinnedAt = const Value.absent(),
          int? rating,
          Value<int?> sortIndex = const Value.absent(),
          Value<String?> groupId = const Value.absent()}) =>
      AlbumRow(
        id: id ?? this.id,
        name: name ?? this.name,
        isSystem: isSystem ?? this.isSystem,
        coverMediaId:
            coverMediaId.present ? coverMediaId.value : this.coverMediaId,
        createdAt: createdAt ?? this.createdAt,
        systemKind: systemKind.present ? systemKind.value : this.systemKind,
        pinnedAt: pinnedAt.present ? pinnedAt.value : this.pinnedAt,
        rating: rating ?? this.rating,
        sortIndex: sortIndex.present ? sortIndex.value : this.sortIndex,
        groupId: groupId.present ? groupId.value : this.groupId,
      );
  AlbumRow copyWithCompanion(AlbumsCompanion data) {
    return AlbumRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      isSystem: data.isSystem.present ? data.isSystem.value : this.isSystem,
      coverMediaId: data.coverMediaId.present
          ? data.coverMediaId.value
          : this.coverMediaId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      systemKind:
          data.systemKind.present ? data.systemKind.value : this.systemKind,
      pinnedAt: data.pinnedAt.present ? data.pinnedAt.value : this.pinnedAt,
      rating: data.rating.present ? data.rating.value : this.rating,
      sortIndex: data.sortIndex.present ? data.sortIndex.value : this.sortIndex,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AlbumRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('isSystem: $isSystem, ')
          ..write('coverMediaId: $coverMediaId, ')
          ..write('createdAt: $createdAt, ')
          ..write('systemKind: $systemKind, ')
          ..write('pinnedAt: $pinnedAt, ')
          ..write('rating: $rating, ')
          ..write('sortIndex: $sortIndex, ')
          ..write('groupId: $groupId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, isSystem, coverMediaId, createdAt,
      systemKind, pinnedAt, rating, sortIndex, groupId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AlbumRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.isSystem == this.isSystem &&
          other.coverMediaId == this.coverMediaId &&
          other.createdAt == this.createdAt &&
          other.systemKind == this.systemKind &&
          other.pinnedAt == this.pinnedAt &&
          other.rating == this.rating &&
          other.sortIndex == this.sortIndex &&
          other.groupId == this.groupId);
}

class AlbumsCompanion extends UpdateCompanion<AlbumRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<bool> isSystem;
  final Value<String?> coverMediaId;
  final Value<DateTime> createdAt;
  final Value<String?> systemKind;
  final Value<DateTime?> pinnedAt;
  final Value<int> rating;
  final Value<int?> sortIndex;
  final Value<String?> groupId;
  final Value<int> rowid;
  const AlbumsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.isSystem = const Value.absent(),
    this.coverMediaId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.systemKind = const Value.absent(),
    this.pinnedAt = const Value.absent(),
    this.rating = const Value.absent(),
    this.sortIndex = const Value.absent(),
    this.groupId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AlbumsCompanion.insert({
    required String id,
    required String name,
    required bool isSystem,
    this.coverMediaId = const Value.absent(),
    required DateTime createdAt,
    this.systemKind = const Value.absent(),
    this.pinnedAt = const Value.absent(),
    this.rating = const Value.absent(),
    this.sortIndex = const Value.absent(),
    this.groupId = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        isSystem = Value(isSystem),
        createdAt = Value(createdAt);
  static Insertable<AlbumRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<bool>? isSystem,
    Expression<String>? coverMediaId,
    Expression<DateTime>? createdAt,
    Expression<String>? systemKind,
    Expression<DateTime>? pinnedAt,
    Expression<int>? rating,
    Expression<int>? sortIndex,
    Expression<String>? groupId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (isSystem != null) 'is_system': isSystem,
      if (coverMediaId != null) 'cover_media_id': coverMediaId,
      if (createdAt != null) 'created_at': createdAt,
      if (systemKind != null) 'system_kind': systemKind,
      if (pinnedAt != null) 'pinned_at': pinnedAt,
      if (rating != null) 'rating': rating,
      if (sortIndex != null) 'sort_index': sortIndex,
      if (groupId != null) 'group_id': groupId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AlbumsCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<bool>? isSystem,
      Value<String?>? coverMediaId,
      Value<DateTime>? createdAt,
      Value<String?>? systemKind,
      Value<DateTime?>? pinnedAt,
      Value<int>? rating,
      Value<int?>? sortIndex,
      Value<String?>? groupId,
      Value<int>? rowid}) {
    return AlbumsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      isSystem: isSystem ?? this.isSystem,
      coverMediaId: coverMediaId ?? this.coverMediaId,
      createdAt: createdAt ?? this.createdAt,
      systemKind: systemKind ?? this.systemKind,
      pinnedAt: pinnedAt ?? this.pinnedAt,
      rating: rating ?? this.rating,
      sortIndex: sortIndex ?? this.sortIndex,
      groupId: groupId ?? this.groupId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (isSystem.present) {
      map['is_system'] = Variable<bool>(isSystem.value);
    }
    if (coverMediaId.present) {
      map['cover_media_id'] = Variable<String>(coverMediaId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (systemKind.present) {
      map['system_kind'] = Variable<String>(systemKind.value);
    }
    if (pinnedAt.present) {
      map['pinned_at'] = Variable<DateTime>(pinnedAt.value);
    }
    if (rating.present) {
      map['rating'] = Variable<int>(rating.value);
    }
    if (sortIndex.present) {
      map['sort_index'] = Variable<int>(sortIndex.value);
    }
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AlbumsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('isSystem: $isSystem, ')
          ..write('coverMediaId: $coverMediaId, ')
          ..write('createdAt: $createdAt, ')
          ..write('systemKind: $systemKind, ')
          ..write('pinnedAt: $pinnedAt, ')
          ..write('rating: $rating, ')
          ..write('sortIndex: $sortIndex, ')
          ..write('groupId: $groupId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AlbumMediaTable extends AlbumMedia
    with TableInfo<$AlbumMediaTable, AlbumMediaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AlbumMediaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _albumIdMeta =
      const VerificationMeta('albumId');
  @override
  late final GeneratedColumn<String> albumId = GeneratedColumn<String>(
      'album_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES albums (id) ON DELETE CASCADE'));
  static const VerificationMeta _mediaIdMeta =
      const VerificationMeta('mediaId');
  @override
  late final GeneratedColumn<String> mediaId = GeneratedColumn<String>(
      'media_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'REFERENCES media_items (id) ON DELETE CASCADE'));
  static const VerificationMeta _addedAtMeta =
      const VerificationMeta('addedAt');
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
      'added_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [albumId, mediaId, addedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'album_media';
  @override
  VerificationContext validateIntegrity(Insertable<AlbumMediaRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('album_id')) {
      context.handle(_albumIdMeta,
          albumId.isAcceptableOrUnknown(data['album_id']!, _albumIdMeta));
    } else if (isInserting) {
      context.missing(_albumIdMeta);
    }
    if (data.containsKey('media_id')) {
      context.handle(_mediaIdMeta,
          mediaId.isAcceptableOrUnknown(data['media_id']!, _mediaIdMeta));
    } else if (isInserting) {
      context.missing(_mediaIdMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(_addedAtMeta,
          addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta));
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {albumId, mediaId};
  @override
  AlbumMediaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AlbumMediaRow(
      albumId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}album_id'])!,
      mediaId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}media_id'])!,
      addedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}added_at'])!,
    );
  }

  @override
  $AlbumMediaTable createAlias(String alias) {
    return $AlbumMediaTable(attachedDatabase, alias);
  }
}

class AlbumMediaRow extends DataClass implements Insertable<AlbumMediaRow> {
  final String albumId;
  final String mediaId;
  final DateTime addedAt;
  const AlbumMediaRow(
      {required this.albumId, required this.mediaId, required this.addedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['album_id'] = Variable<String>(albumId);
    map['media_id'] = Variable<String>(mediaId);
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  AlbumMediaCompanion toCompanion(bool nullToAbsent) {
    return AlbumMediaCompanion(
      albumId: Value(albumId),
      mediaId: Value(mediaId),
      addedAt: Value(addedAt),
    );
  }

  factory AlbumMediaRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AlbumMediaRow(
      albumId: serializer.fromJson<String>(json['albumId']),
      mediaId: serializer.fromJson<String>(json['mediaId']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'albumId': serializer.toJson<String>(albumId),
      'mediaId': serializer.toJson<String>(mediaId),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  AlbumMediaRow copyWith(
          {String? albumId, String? mediaId, DateTime? addedAt}) =>
      AlbumMediaRow(
        albumId: albumId ?? this.albumId,
        mediaId: mediaId ?? this.mediaId,
        addedAt: addedAt ?? this.addedAt,
      );
  AlbumMediaRow copyWithCompanion(AlbumMediaCompanion data) {
    return AlbumMediaRow(
      albumId: data.albumId.present ? data.albumId.value : this.albumId,
      mediaId: data.mediaId.present ? data.mediaId.value : this.mediaId,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AlbumMediaRow(')
          ..write('albumId: $albumId, ')
          ..write('mediaId: $mediaId, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(albumId, mediaId, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AlbumMediaRow &&
          other.albumId == this.albumId &&
          other.mediaId == this.mediaId &&
          other.addedAt == this.addedAt);
}

class AlbumMediaCompanion extends UpdateCompanion<AlbumMediaRow> {
  final Value<String> albumId;
  final Value<String> mediaId;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const AlbumMediaCompanion({
    this.albumId = const Value.absent(),
    this.mediaId = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AlbumMediaCompanion.insert({
    required String albumId,
    required String mediaId,
    required DateTime addedAt,
    this.rowid = const Value.absent(),
  })  : albumId = Value(albumId),
        mediaId = Value(mediaId),
        addedAt = Value(addedAt);
  static Insertable<AlbumMediaRow> custom({
    Expression<String>? albumId,
    Expression<String>? mediaId,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (albumId != null) 'album_id': albumId,
      if (mediaId != null) 'media_id': mediaId,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AlbumMediaCompanion copyWith(
      {Value<String>? albumId,
      Value<String>? mediaId,
      Value<DateTime>? addedAt,
      Value<int>? rowid}) {
    return AlbumMediaCompanion(
      albumId: albumId ?? this.albumId,
      mediaId: mediaId ?? this.mediaId,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (albumId.present) {
      map['album_id'] = Variable<String>(albumId.value);
    }
    if (mediaId.present) {
      map['media_id'] = Variable<String>(mediaId.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AlbumMediaCompanion(')
          ..write('albumId: $albumId, ')
          ..write('mediaId: $mediaId, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AlbumGroupsTable extends AlbumGroups
    with TableInfo<$AlbumGroupsTable, AlbumGroupRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AlbumGroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  static const VerificationMeta _sortIndexMeta =
      const VerificationMeta('sortIndex');
  @override
  late final GeneratedColumn<int> sortIndex = GeneratedColumn<int>(
      'sort_index', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [id, name, createdAt, sortIndex];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'album_groups';
  @override
  VerificationContext validateIntegrity(Insertable<AlbumGroupRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('sort_index')) {
      context.handle(_sortIndexMeta,
          sortIndex.isAcceptableOrUnknown(data['sort_index']!, _sortIndexMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AlbumGroupRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AlbumGroupRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
      sortIndex: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}sort_index']),
    );
  }

  @override
  $AlbumGroupsTable createAlias(String alias) {
    return $AlbumGroupsTable(attachedDatabase, alias);
  }
}

class AlbumGroupRow extends DataClass implements Insertable<AlbumGroupRow> {
  final String id;
  final String name;
  final DateTime createdAt;
  final int? sortIndex;
  const AlbumGroupRow(
      {required this.id,
      required this.name,
      required this.createdAt,
      this.sortIndex});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || sortIndex != null) {
      map['sort_index'] = Variable<int>(sortIndex);
    }
    return map;
  }

  AlbumGroupsCompanion toCompanion(bool nullToAbsent) {
    return AlbumGroupsCompanion(
      id: Value(id),
      name: Value(name),
      createdAt: Value(createdAt),
      sortIndex: sortIndex == null && nullToAbsent
          ? const Value.absent()
          : Value(sortIndex),
    );
  }

  factory AlbumGroupRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AlbumGroupRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      sortIndex: serializer.fromJson<int?>(json['sortIndex']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'sortIndex': serializer.toJson<int?>(sortIndex),
    };
  }

  AlbumGroupRow copyWith(
          {String? id,
          String? name,
          DateTime? createdAt,
          Value<int?> sortIndex = const Value.absent()}) =>
      AlbumGroupRow(
        id: id ?? this.id,
        name: name ?? this.name,
        createdAt: createdAt ?? this.createdAt,
        sortIndex: sortIndex.present ? sortIndex.value : this.sortIndex,
      );
  AlbumGroupRow copyWithCompanion(AlbumGroupsCompanion data) {
    return AlbumGroupRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      sortIndex: data.sortIndex.present ? data.sortIndex.value : this.sortIndex,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AlbumGroupRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('sortIndex: $sortIndex')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, createdAt, sortIndex);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AlbumGroupRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt &&
          other.sortIndex == this.sortIndex);
}

class AlbumGroupsCompanion extends UpdateCompanion<AlbumGroupRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<DateTime> createdAt;
  final Value<int?> sortIndex;
  final Value<int> rowid;
  const AlbumGroupsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.sortIndex = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AlbumGroupsCompanion.insert({
    required String id,
    required String name,
    required DateTime createdAt,
    this.sortIndex = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        createdAt = Value(createdAt);
  static Insertable<AlbumGroupRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<DateTime>? createdAt,
    Expression<int>? sortIndex,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
      if (sortIndex != null) 'sort_index': sortIndex,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AlbumGroupsCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<DateTime>? createdAt,
      Value<int?>? sortIndex,
      Value<int>? rowid}) {
    return AlbumGroupsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
      sortIndex: sortIndex ?? this.sortIndex,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (sortIndex.present) {
      map['sort_index'] = Variable<int>(sortIndex.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AlbumGroupsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt, ')
          ..write('sortIndex: $sortIndex, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $MediaItemsTable mediaItems = $MediaItemsTable(this);
  late final $AlbumsTable albums = $AlbumsTable(this);
  late final $AlbumMediaTable albumMedia = $AlbumMediaTable(this);
  late final $AlbumGroupsTable albumGroups = $AlbumGroupsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [mediaItems, albums, albumMedia, albumGroups];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules(
        [
          WritePropagation(
            on: TableUpdateQuery.onTableName('albums',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('album_media', kind: UpdateKind.delete),
            ],
          ),
          WritePropagation(
            on: TableUpdateQuery.onTableName('media_items',
                limitUpdateKind: UpdateKind.delete),
            result: [
              TableUpdate('album_media', kind: UpdateKind.delete),
            ],
          ),
        ],
      );
}

typedef $$MediaItemsTableCreateCompanionBuilder = MediaItemsCompanion Function({
  required String id,
  required String privatePath,
  Value<String?> originalPath,
  required String originalName,
  required String mimeType,
  required bool isVideo,
  Value<int?> width,
  Value<int?> height,
  Value<int?> durationMs,
  Value<int> rating,
  required DateTime dateAdded,
  Value<DateTime?> dateTaken,
  required int sizeBytes,
  Value<String?> thumbnailPath,
  Value<DateTime?> deletedAt,
  Value<String?> sourcePlatformId,
  Value<bool> sourceRemovalPending,
  Value<String?> contentDigest,
  Value<int> playCount,
  Value<DateTime?> lastPlayedAt,
  Value<String?> encryptedDek,
  Value<int> rowid,
});
typedef $$MediaItemsTableUpdateCompanionBuilder = MediaItemsCompanion Function({
  Value<String> id,
  Value<String> privatePath,
  Value<String?> originalPath,
  Value<String> originalName,
  Value<String> mimeType,
  Value<bool> isVideo,
  Value<int?> width,
  Value<int?> height,
  Value<int?> durationMs,
  Value<int> rating,
  Value<DateTime> dateAdded,
  Value<DateTime?> dateTaken,
  Value<int> sizeBytes,
  Value<String?> thumbnailPath,
  Value<DateTime?> deletedAt,
  Value<String?> sourcePlatformId,
  Value<bool> sourceRemovalPending,
  Value<String?> contentDigest,
  Value<int> playCount,
  Value<DateTime?> lastPlayedAt,
  Value<String?> encryptedDek,
  Value<int> rowid,
});

final class $$MediaItemsTableReferences
    extends BaseReferences<_$AppDatabase, $MediaItemsTable, MediaItemRow> {
  $$MediaItemsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$AlbumMediaTable, List<AlbumMediaRow>>
      _albumMediaRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
          db.albumMedia,
          aliasName:
              $_aliasNameGenerator(db.mediaItems.id, db.albumMedia.mediaId));

  $$AlbumMediaTableProcessedTableManager get albumMediaRefs {
    final manager = $$AlbumMediaTableTableManager($_db, $_db.albumMedia)
        .filter((f) => f.mediaId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_albumMediaRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$MediaItemsTableFilterComposer
    extends Composer<_$AppDatabase, $MediaItemsTable> {
  $$MediaItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get privatePath => $composableBuilder(
      column: $table.privatePath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get originalPath => $composableBuilder(
      column: $table.originalPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get originalName => $composableBuilder(
      column: $table.originalName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mimeType => $composableBuilder(
      column: $table.mimeType, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isVideo => $composableBuilder(
      column: $table.isVideo, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get width => $composableBuilder(
      column: $table.width, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get height => $composableBuilder(
      column: $table.height, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get rating => $composableBuilder(
      column: $table.rating, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get dateAdded => $composableBuilder(
      column: $table.dateAdded, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get dateTaken => $composableBuilder(
      column: $table.dateTaken, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sizeBytes => $composableBuilder(
      column: $table.sizeBytes, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get thumbnailPath => $composableBuilder(
      column: $table.thumbnailPath, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get sourcePlatformId => $composableBuilder(
      column: $table.sourcePlatformId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get sourceRemovalPending => $composableBuilder(
      column: $table.sourceRemovalPending,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get contentDigest => $composableBuilder(
      column: $table.contentDigest, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get playCount => $composableBuilder(
      column: $table.playCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastPlayedAt => $composableBuilder(
      column: $table.lastPlayedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get encryptedDek => $composableBuilder(
      column: $table.encryptedDek, builder: (column) => ColumnFilters(column));

  Expression<bool> albumMediaRefs(
      Expression<bool> Function($$AlbumMediaTableFilterComposer f) f) {
    final $$AlbumMediaTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.albumMedia,
        getReferencedColumn: (t) => t.mediaId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AlbumMediaTableFilterComposer(
              $db: $db,
              $table: $db.albumMedia,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$MediaItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $MediaItemsTable> {
  $$MediaItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get privatePath => $composableBuilder(
      column: $table.privatePath, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get originalPath => $composableBuilder(
      column: $table.originalPath,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get originalName => $composableBuilder(
      column: $table.originalName,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mimeType => $composableBuilder(
      column: $table.mimeType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isVideo => $composableBuilder(
      column: $table.isVideo, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get width => $composableBuilder(
      column: $table.width, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get height => $composableBuilder(
      column: $table.height, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get rating => $composableBuilder(
      column: $table.rating, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get dateAdded => $composableBuilder(
      column: $table.dateAdded, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get dateTaken => $composableBuilder(
      column: $table.dateTaken, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sizeBytes => $composableBuilder(
      column: $table.sizeBytes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get thumbnailPath => $composableBuilder(
      column: $table.thumbnailPath,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get deletedAt => $composableBuilder(
      column: $table.deletedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get sourcePlatformId => $composableBuilder(
      column: $table.sourcePlatformId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get sourceRemovalPending => $composableBuilder(
      column: $table.sourceRemovalPending,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get contentDigest => $composableBuilder(
      column: $table.contentDigest,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get playCount => $composableBuilder(
      column: $table.playCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastPlayedAt => $composableBuilder(
      column: $table.lastPlayedAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get encryptedDek => $composableBuilder(
      column: $table.encryptedDek,
      builder: (column) => ColumnOrderings(column));
}

class $$MediaItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $MediaItemsTable> {
  $$MediaItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get privatePath => $composableBuilder(
      column: $table.privatePath, builder: (column) => column);

  GeneratedColumn<String> get originalPath => $composableBuilder(
      column: $table.originalPath, builder: (column) => column);

  GeneratedColumn<String> get originalName => $composableBuilder(
      column: $table.originalName, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<bool> get isVideo =>
      $composableBuilder(column: $table.isVideo, builder: (column) => column);

  GeneratedColumn<int> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<int> get height =>
      $composableBuilder(column: $table.height, builder: (column) => column);

  GeneratedColumn<int> get durationMs => $composableBuilder(
      column: $table.durationMs, builder: (column) => column);

  GeneratedColumn<int> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<DateTime> get dateAdded =>
      $composableBuilder(column: $table.dateAdded, builder: (column) => column);

  GeneratedColumn<DateTime> get dateTaken =>
      $composableBuilder(column: $table.dateTaken, builder: (column) => column);

  GeneratedColumn<int> get sizeBytes =>
      $composableBuilder(column: $table.sizeBytes, builder: (column) => column);

  GeneratedColumn<String> get thumbnailPath => $composableBuilder(
      column: $table.thumbnailPath, builder: (column) => column);

  GeneratedColumn<DateTime> get deletedAt =>
      $composableBuilder(column: $table.deletedAt, builder: (column) => column);

  GeneratedColumn<String> get sourcePlatformId => $composableBuilder(
      column: $table.sourcePlatformId, builder: (column) => column);

  GeneratedColumn<bool> get sourceRemovalPending => $composableBuilder(
      column: $table.sourceRemovalPending, builder: (column) => column);

  GeneratedColumn<String> get contentDigest => $composableBuilder(
      column: $table.contentDigest, builder: (column) => column);

  GeneratedColumn<int> get playCount =>
      $composableBuilder(column: $table.playCount, builder: (column) => column);

  GeneratedColumn<DateTime> get lastPlayedAt => $composableBuilder(
      column: $table.lastPlayedAt, builder: (column) => column);

  GeneratedColumn<String> get encryptedDek => $composableBuilder(
      column: $table.encryptedDek, builder: (column) => column);

  Expression<T> albumMediaRefs<T extends Object>(
      Expression<T> Function($$AlbumMediaTableAnnotationComposer a) f) {
    final $$AlbumMediaTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.albumMedia,
        getReferencedColumn: (t) => t.mediaId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AlbumMediaTableAnnotationComposer(
              $db: $db,
              $table: $db.albumMedia,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$MediaItemsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MediaItemsTable,
    MediaItemRow,
    $$MediaItemsTableFilterComposer,
    $$MediaItemsTableOrderingComposer,
    $$MediaItemsTableAnnotationComposer,
    $$MediaItemsTableCreateCompanionBuilder,
    $$MediaItemsTableUpdateCompanionBuilder,
    (MediaItemRow, $$MediaItemsTableReferences),
    MediaItemRow,
    PrefetchHooks Function({bool albumMediaRefs})> {
  $$MediaItemsTableTableManager(_$AppDatabase db, $MediaItemsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> privatePath = const Value.absent(),
            Value<String?> originalPath = const Value.absent(),
            Value<String> originalName = const Value.absent(),
            Value<String> mimeType = const Value.absent(),
            Value<bool> isVideo = const Value.absent(),
            Value<int?> width = const Value.absent(),
            Value<int?> height = const Value.absent(),
            Value<int?> durationMs = const Value.absent(),
            Value<int> rating = const Value.absent(),
            Value<DateTime> dateAdded = const Value.absent(),
            Value<DateTime?> dateTaken = const Value.absent(),
            Value<int> sizeBytes = const Value.absent(),
            Value<String?> thumbnailPath = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<String?> sourcePlatformId = const Value.absent(),
            Value<bool> sourceRemovalPending = const Value.absent(),
            Value<String?> contentDigest = const Value.absent(),
            Value<int> playCount = const Value.absent(),
            Value<DateTime?> lastPlayedAt = const Value.absent(),
            Value<String?> encryptedDek = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MediaItemsCompanion(
            id: id,
            privatePath: privatePath,
            originalPath: originalPath,
            originalName: originalName,
            mimeType: mimeType,
            isVideo: isVideo,
            width: width,
            height: height,
            durationMs: durationMs,
            rating: rating,
            dateAdded: dateAdded,
            dateTaken: dateTaken,
            sizeBytes: sizeBytes,
            thumbnailPath: thumbnailPath,
            deletedAt: deletedAt,
            sourcePlatformId: sourcePlatformId,
            sourceRemovalPending: sourceRemovalPending,
            contentDigest: contentDigest,
            playCount: playCount,
            lastPlayedAt: lastPlayedAt,
            encryptedDek: encryptedDek,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String privatePath,
            Value<String?> originalPath = const Value.absent(),
            required String originalName,
            required String mimeType,
            required bool isVideo,
            Value<int?> width = const Value.absent(),
            Value<int?> height = const Value.absent(),
            Value<int?> durationMs = const Value.absent(),
            Value<int> rating = const Value.absent(),
            required DateTime dateAdded,
            Value<DateTime?> dateTaken = const Value.absent(),
            required int sizeBytes,
            Value<String?> thumbnailPath = const Value.absent(),
            Value<DateTime?> deletedAt = const Value.absent(),
            Value<String?> sourcePlatformId = const Value.absent(),
            Value<bool> sourceRemovalPending = const Value.absent(),
            Value<String?> contentDigest = const Value.absent(),
            Value<int> playCount = const Value.absent(),
            Value<DateTime?> lastPlayedAt = const Value.absent(),
            Value<String?> encryptedDek = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MediaItemsCompanion.insert(
            id: id,
            privatePath: privatePath,
            originalPath: originalPath,
            originalName: originalName,
            mimeType: mimeType,
            isVideo: isVideo,
            width: width,
            height: height,
            durationMs: durationMs,
            rating: rating,
            dateAdded: dateAdded,
            dateTaken: dateTaken,
            sizeBytes: sizeBytes,
            thumbnailPath: thumbnailPath,
            deletedAt: deletedAt,
            sourcePlatformId: sourcePlatformId,
            sourceRemovalPending: sourceRemovalPending,
            contentDigest: contentDigest,
            playCount: playCount,
            lastPlayedAt: lastPlayedAt,
            encryptedDek: encryptedDek,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$MediaItemsTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({albumMediaRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (albumMediaRefs) db.albumMedia],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (albumMediaRefs)
                    await $_getPrefetchedData<MediaItemRow, $MediaItemsTable,
                            AlbumMediaRow>(
                        currentTable: table,
                        referencedTable: $$MediaItemsTableReferences
                            ._albumMediaRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$MediaItemsTableReferences(db, table, p0)
                                .albumMediaRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.mediaId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$MediaItemsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MediaItemsTable,
    MediaItemRow,
    $$MediaItemsTableFilterComposer,
    $$MediaItemsTableOrderingComposer,
    $$MediaItemsTableAnnotationComposer,
    $$MediaItemsTableCreateCompanionBuilder,
    $$MediaItemsTableUpdateCompanionBuilder,
    (MediaItemRow, $$MediaItemsTableReferences),
    MediaItemRow,
    PrefetchHooks Function({bool albumMediaRefs})>;
typedef $$AlbumsTableCreateCompanionBuilder = AlbumsCompanion Function({
  required String id,
  required String name,
  required bool isSystem,
  Value<String?> coverMediaId,
  required DateTime createdAt,
  Value<String?> systemKind,
  Value<DateTime?> pinnedAt,
  Value<int> rating,
  Value<int?> sortIndex,
  Value<String?> groupId,
  Value<int> rowid,
});
typedef $$AlbumsTableUpdateCompanionBuilder = AlbumsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<bool> isSystem,
  Value<String?> coverMediaId,
  Value<DateTime> createdAt,
  Value<String?> systemKind,
  Value<DateTime?> pinnedAt,
  Value<int> rating,
  Value<int?> sortIndex,
  Value<String?> groupId,
  Value<int> rowid,
});

final class $$AlbumsTableReferences
    extends BaseReferences<_$AppDatabase, $AlbumsTable, AlbumRow> {
  $$AlbumsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$AlbumMediaTable, List<AlbumMediaRow>>
      _albumMediaRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
          db.albumMedia,
          aliasName: $_aliasNameGenerator(db.albums.id, db.albumMedia.albumId));

  $$AlbumMediaTableProcessedTableManager get albumMediaRefs {
    final manager = $$AlbumMediaTableTableManager($_db, $_db.albumMedia)
        .filter((f) => f.albumId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_albumMediaRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$AlbumsTableFilterComposer
    extends Composer<_$AppDatabase, $AlbumsTable> {
  $$AlbumsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isSystem => $composableBuilder(
      column: $table.isSystem, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get coverMediaId => $composableBuilder(
      column: $table.coverMediaId, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get systemKind => $composableBuilder(
      column: $table.systemKind, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get pinnedAt => $composableBuilder(
      column: $table.pinnedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get rating => $composableBuilder(
      column: $table.rating, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortIndex => $composableBuilder(
      column: $table.sortIndex, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get groupId => $composableBuilder(
      column: $table.groupId, builder: (column) => ColumnFilters(column));

  Expression<bool> albumMediaRefs(
      Expression<bool> Function($$AlbumMediaTableFilterComposer f) f) {
    final $$AlbumMediaTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.albumMedia,
        getReferencedColumn: (t) => t.albumId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AlbumMediaTableFilterComposer(
              $db: $db,
              $table: $db.albumMedia,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$AlbumsTableOrderingComposer
    extends Composer<_$AppDatabase, $AlbumsTable> {
  $$AlbumsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isSystem => $composableBuilder(
      column: $table.isSystem, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get coverMediaId => $composableBuilder(
      column: $table.coverMediaId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get systemKind => $composableBuilder(
      column: $table.systemKind, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get pinnedAt => $composableBuilder(
      column: $table.pinnedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get rating => $composableBuilder(
      column: $table.rating, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortIndex => $composableBuilder(
      column: $table.sortIndex, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get groupId => $composableBuilder(
      column: $table.groupId, builder: (column) => ColumnOrderings(column));
}

class $$AlbumsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AlbumsTable> {
  $$AlbumsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<bool> get isSystem =>
      $composableBuilder(column: $table.isSystem, builder: (column) => column);

  GeneratedColumn<String> get coverMediaId => $composableBuilder(
      column: $table.coverMediaId, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get systemKind => $composableBuilder(
      column: $table.systemKind, builder: (column) => column);

  GeneratedColumn<DateTime> get pinnedAt =>
      $composableBuilder(column: $table.pinnedAt, builder: (column) => column);

  GeneratedColumn<int> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<int> get sortIndex =>
      $composableBuilder(column: $table.sortIndex, builder: (column) => column);

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  Expression<T> albumMediaRefs<T extends Object>(
      Expression<T> Function($$AlbumMediaTableAnnotationComposer a) f) {
    final $$AlbumMediaTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.albumMedia,
        getReferencedColumn: (t) => t.albumId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AlbumMediaTableAnnotationComposer(
              $db: $db,
              $table: $db.albumMedia,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$AlbumsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AlbumsTable,
    AlbumRow,
    $$AlbumsTableFilterComposer,
    $$AlbumsTableOrderingComposer,
    $$AlbumsTableAnnotationComposer,
    $$AlbumsTableCreateCompanionBuilder,
    $$AlbumsTableUpdateCompanionBuilder,
    (AlbumRow, $$AlbumsTableReferences),
    AlbumRow,
    PrefetchHooks Function({bool albumMediaRefs})> {
  $$AlbumsTableTableManager(_$AppDatabase db, $AlbumsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AlbumsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AlbumsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AlbumsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<bool> isSystem = const Value.absent(),
            Value<String?> coverMediaId = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<String?> systemKind = const Value.absent(),
            Value<DateTime?> pinnedAt = const Value.absent(),
            Value<int> rating = const Value.absent(),
            Value<int?> sortIndex = const Value.absent(),
            Value<String?> groupId = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AlbumsCompanion(
            id: id,
            name: name,
            isSystem: isSystem,
            coverMediaId: coverMediaId,
            createdAt: createdAt,
            systemKind: systemKind,
            pinnedAt: pinnedAt,
            rating: rating,
            sortIndex: sortIndex,
            groupId: groupId,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required bool isSystem,
            Value<String?> coverMediaId = const Value.absent(),
            required DateTime createdAt,
            Value<String?> systemKind = const Value.absent(),
            Value<DateTime?> pinnedAt = const Value.absent(),
            Value<int> rating = const Value.absent(),
            Value<int?> sortIndex = const Value.absent(),
            Value<String?> groupId = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AlbumsCompanion.insert(
            id: id,
            name: name,
            isSystem: isSystem,
            coverMediaId: coverMediaId,
            createdAt: createdAt,
            systemKind: systemKind,
            pinnedAt: pinnedAt,
            rating: rating,
            sortIndex: sortIndex,
            groupId: groupId,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$AlbumsTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({albumMediaRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (albumMediaRefs) db.albumMedia],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (albumMediaRefs)
                    await $_getPrefetchedData<AlbumRow, $AlbumsTable,
                            AlbumMediaRow>(
                        currentTable: table,
                        referencedTable:
                            $$AlbumsTableReferences._albumMediaRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$AlbumsTableReferences(db, table, p0)
                                .albumMediaRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.albumId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$AlbumsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AlbumsTable,
    AlbumRow,
    $$AlbumsTableFilterComposer,
    $$AlbumsTableOrderingComposer,
    $$AlbumsTableAnnotationComposer,
    $$AlbumsTableCreateCompanionBuilder,
    $$AlbumsTableUpdateCompanionBuilder,
    (AlbumRow, $$AlbumsTableReferences),
    AlbumRow,
    PrefetchHooks Function({bool albumMediaRefs})>;
typedef $$AlbumMediaTableCreateCompanionBuilder = AlbumMediaCompanion Function({
  required String albumId,
  required String mediaId,
  required DateTime addedAt,
  Value<int> rowid,
});
typedef $$AlbumMediaTableUpdateCompanionBuilder = AlbumMediaCompanion Function({
  Value<String> albumId,
  Value<String> mediaId,
  Value<DateTime> addedAt,
  Value<int> rowid,
});

final class $$AlbumMediaTableReferences
    extends BaseReferences<_$AppDatabase, $AlbumMediaTable, AlbumMediaRow> {
  $$AlbumMediaTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $AlbumsTable _albumIdTable(_$AppDatabase db) => db.albums
      .createAlias($_aliasNameGenerator(db.albumMedia.albumId, db.albums.id));

  $$AlbumsTableProcessedTableManager get albumId {
    final $_column = $_itemColumn<String>('album_id')!;

    final manager = $$AlbumsTableTableManager($_db, $_db.albums)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_albumIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $MediaItemsTable _mediaIdTable(_$AppDatabase db) =>
      db.mediaItems.createAlias(
          $_aliasNameGenerator(db.albumMedia.mediaId, db.mediaItems.id));

  $$MediaItemsTableProcessedTableManager get mediaId {
    final $_column = $_itemColumn<String>('media_id')!;

    final manager = $$MediaItemsTableTableManager($_db, $_db.mediaItems)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_mediaIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$AlbumMediaTableFilterComposer
    extends Composer<_$AppDatabase, $AlbumMediaTable> {
  $$AlbumMediaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<DateTime> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnFilters(column));

  $$AlbumsTableFilterComposer get albumId {
    final $$AlbumsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.albumId,
        referencedTable: $db.albums,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AlbumsTableFilterComposer(
              $db: $db,
              $table: $db.albums,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$MediaItemsTableFilterComposer get mediaId {
    final $$MediaItemsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.mediaId,
        referencedTable: $db.mediaItems,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MediaItemsTableFilterComposer(
              $db: $db,
              $table: $db.mediaItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$AlbumMediaTableOrderingComposer
    extends Composer<_$AppDatabase, $AlbumMediaTable> {
  $$AlbumMediaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
      column: $table.addedAt, builder: (column) => ColumnOrderings(column));

  $$AlbumsTableOrderingComposer get albumId {
    final $$AlbumsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.albumId,
        referencedTable: $db.albums,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AlbumsTableOrderingComposer(
              $db: $db,
              $table: $db.albums,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$MediaItemsTableOrderingComposer get mediaId {
    final $$MediaItemsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.mediaId,
        referencedTable: $db.mediaItems,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MediaItemsTableOrderingComposer(
              $db: $db,
              $table: $db.mediaItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$AlbumMediaTableAnnotationComposer
    extends Composer<_$AppDatabase, $AlbumMediaTable> {
  $$AlbumMediaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  $$AlbumsTableAnnotationComposer get albumId {
    final $$AlbumsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.albumId,
        referencedTable: $db.albums,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$AlbumsTableAnnotationComposer(
              $db: $db,
              $table: $db.albums,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$MediaItemsTableAnnotationComposer get mediaId {
    final $$MediaItemsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.mediaId,
        referencedTable: $db.mediaItems,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MediaItemsTableAnnotationComposer(
              $db: $db,
              $table: $db.mediaItems,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$AlbumMediaTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AlbumMediaTable,
    AlbumMediaRow,
    $$AlbumMediaTableFilterComposer,
    $$AlbumMediaTableOrderingComposer,
    $$AlbumMediaTableAnnotationComposer,
    $$AlbumMediaTableCreateCompanionBuilder,
    $$AlbumMediaTableUpdateCompanionBuilder,
    (AlbumMediaRow, $$AlbumMediaTableReferences),
    AlbumMediaRow,
    PrefetchHooks Function({bool albumId, bool mediaId})> {
  $$AlbumMediaTableTableManager(_$AppDatabase db, $AlbumMediaTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AlbumMediaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AlbumMediaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AlbumMediaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> albumId = const Value.absent(),
            Value<String> mediaId = const Value.absent(),
            Value<DateTime> addedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AlbumMediaCompanion(
            albumId: albumId,
            mediaId: mediaId,
            addedAt: addedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String albumId,
            required String mediaId,
            required DateTime addedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              AlbumMediaCompanion.insert(
            albumId: albumId,
            mediaId: mediaId,
            addedAt: addedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$AlbumMediaTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({albumId = false, mediaId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (albumId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.albumId,
                    referencedTable:
                        $$AlbumMediaTableReferences._albumIdTable(db),
                    referencedColumn:
                        $$AlbumMediaTableReferences._albumIdTable(db).id,
                  ) as T;
                }
                if (mediaId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.mediaId,
                    referencedTable:
                        $$AlbumMediaTableReferences._mediaIdTable(db),
                    referencedColumn:
                        $$AlbumMediaTableReferences._mediaIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$AlbumMediaTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AlbumMediaTable,
    AlbumMediaRow,
    $$AlbumMediaTableFilterComposer,
    $$AlbumMediaTableOrderingComposer,
    $$AlbumMediaTableAnnotationComposer,
    $$AlbumMediaTableCreateCompanionBuilder,
    $$AlbumMediaTableUpdateCompanionBuilder,
    (AlbumMediaRow, $$AlbumMediaTableReferences),
    AlbumMediaRow,
    PrefetchHooks Function({bool albumId, bool mediaId})>;
typedef $$AlbumGroupsTableCreateCompanionBuilder = AlbumGroupsCompanion
    Function({
  required String id,
  required String name,
  required DateTime createdAt,
  Value<int?> sortIndex,
  Value<int> rowid,
});
typedef $$AlbumGroupsTableUpdateCompanionBuilder = AlbumGroupsCompanion
    Function({
  Value<String> id,
  Value<String> name,
  Value<DateTime> createdAt,
  Value<int?> sortIndex,
  Value<int> rowid,
});

class $$AlbumGroupsTableFilterComposer
    extends Composer<_$AppDatabase, $AlbumGroupsTable> {
  $$AlbumGroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sortIndex => $composableBuilder(
      column: $table.sortIndex, builder: (column) => ColumnFilters(column));
}

class $$AlbumGroupsTableOrderingComposer
    extends Composer<_$AppDatabase, $AlbumGroupsTable> {
  $$AlbumGroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sortIndex => $composableBuilder(
      column: $table.sortIndex, builder: (column) => ColumnOrderings(column));
}

class $$AlbumGroupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AlbumGroupsTable> {
  $$AlbumGroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get sortIndex =>
      $composableBuilder(column: $table.sortIndex, builder: (column) => column);
}

class $$AlbumGroupsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AlbumGroupsTable,
    AlbumGroupRow,
    $$AlbumGroupsTableFilterComposer,
    $$AlbumGroupsTableOrderingComposer,
    $$AlbumGroupsTableAnnotationComposer,
    $$AlbumGroupsTableCreateCompanionBuilder,
    $$AlbumGroupsTableUpdateCompanionBuilder,
    (
      AlbumGroupRow,
      BaseReferences<_$AppDatabase, $AlbumGroupsTable, AlbumGroupRow>
    ),
    AlbumGroupRow,
    PrefetchHooks Function()> {
  $$AlbumGroupsTableTableManager(_$AppDatabase db, $AlbumGroupsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AlbumGroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AlbumGroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AlbumGroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
            Value<int?> sortIndex = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AlbumGroupsCompanion(
            id: id,
            name: name,
            createdAt: createdAt,
            sortIndex: sortIndex,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            required DateTime createdAt,
            Value<int?> sortIndex = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AlbumGroupsCompanion.insert(
            id: id,
            name: name,
            createdAt: createdAt,
            sortIndex: sortIndex,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AlbumGroupsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $AlbumGroupsTable,
    AlbumGroupRow,
    $$AlbumGroupsTableFilterComposer,
    $$AlbumGroupsTableOrderingComposer,
    $$AlbumGroupsTableAnnotationComposer,
    $$AlbumGroupsTableCreateCompanionBuilder,
    $$AlbumGroupsTableUpdateCompanionBuilder,
    (
      AlbumGroupRow,
      BaseReferences<_$AppDatabase, $AlbumGroupsTable, AlbumGroupRow>
    ),
    AlbumGroupRow,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$MediaItemsTableTableManager get mediaItems =>
      $$MediaItemsTableTableManager(_db, _db.mediaItems);
  $$AlbumsTableTableManager get albums =>
      $$AlbumsTableTableManager(_db, _db.albums);
  $$AlbumMediaTableTableManager get albumMedia =>
      $$AlbumMediaTableTableManager(_db, _db.albumMedia);
  $$AlbumGroupsTableTableManager get albumGroups =>
      $$AlbumGroupsTableTableManager(_db, _db.albumGroups);
}
