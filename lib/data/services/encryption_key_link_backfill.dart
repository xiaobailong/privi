import '../repositories/media_repository.dart';
import '../../core/utils/app_logger.dart';
import 'encryption_key_manager.dart';

/// Outcome of the one-time key-link initialization.
enum EncryptionKeyLinkBackfillStatus {
  /// No row has a blank key link — already backfilled on this phone.
  alreadyComplete,

  /// Blank links exist but this phone has no KEK yet (fresh install, vault not
  /// set up). Nothing is written; the next launch / unlock retries.
  noLocalKey,

  /// Blank links were stamped with this phone's default key id.
  filled,
}

class EncryptionKeyLinkBackfillResult {
  const EncryptionKeyLinkBackfillResult({
    required this.status,
    required this.pending,
    required this.filled,
    required this.remaining,
    this.keyId,
  });

  final EncryptionKeyLinkBackfillStatus status;
  final int pending;
  final int filled;
  final int remaining;
  final String? keyId;

  @override
  String toString() => switch (status) {
        EncryptionKeyLinkBackfillStatus.alreadyComplete => 'no blank key links',
        EncryptionKeyLinkBackfillStatus.noLocalKey =>
          '$pending blank key links waiting for a local KEK',
        EncryptionKeyLinkBackfillStatus.filled =>
          'backfilled $filled/$pending rows with ${keyId ?? '-'} '
              '(remaining $remaining)',
      };
}

/// Initializes `media_items.encryption_key_id` for media encrypted **before**
/// the file↔key relation existed.
///
/// Legacy rows were all wrapped with the single KEK of the phone that encrypted
/// them (there was no key ring yet), so the blank links are filled with this
/// phone's default key id. Rows that already name a key — e.g. files restored
/// from a v6 backup and decrypted by an imported key — are never modified.
///
/// Idempotence is derived from the database itself, not from a
/// `SharedPreferences` "already done" flag:
///  * a flag would travel with a v6 backup (which exports all settings) and
///    make a *different* phone skip its own backfill;
///  * a flag could go stale after a key change or an old backup import creates
///    new blank rows.
///
/// Instead, a single cheap COUNT is the whole check: zero blank links means
/// "this phone has already been backfilled", so no write is attempted. A
/// partial run is also safe — the next call only touches the rows still blank.
class EncryptionKeyLinkBackfill {
  const EncryptionKeyLinkBackfill({
    required this.media,
    required this.keyManager,
  });

  final MediaRepository media;
  final EncryptionKeyManager keyManager;

  Future<EncryptionKeyLinkBackfillResult> run() async {
    final pending = await media.countMissingEncryptionKeyId();
    if (pending == 0) {
      return const EncryptionKeyLinkBackfillResult(
        status: EncryptionKeyLinkBackfillStatus.alreadyComplete,
        pending: 0,
        filled: 0,
        remaining: 0,
      );
    }

    final keyId = await keyManager.defaultKeyId();
    if (keyId == null) {
      AppLogger.w(
        'KeyLinkBackfill',
        '$pending encrypted row(s) have no key id, but this phone has no KEK '
            'yet — will retry on the next launch',
      );
      return EncryptionKeyLinkBackfillResult(
        status: EncryptionKeyLinkBackfillStatus.noLocalKey,
        pending: pending,
        filled: 0,
        remaining: pending,
      );
    }

    final filled = await media.backfillEncryptionKeyId(keyId);
    final remaining = await media.countMissingEncryptionKeyId();
    AppLogger.i(
      'KeyLinkBackfill',
      'stamped $filled/$pending legacy row(s) with this phone\'s key $keyId; '
          '$remaining blank link(s) remain',
    );
    return EncryptionKeyLinkBackfillResult(
      status: EncryptionKeyLinkBackfillStatus.filled,
      pending: pending,
      filled: filled,
      remaining: remaining,
      keyId: keyId,
    );
  }
}
