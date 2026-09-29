import '../../core/storage/app_database.dart';
import '../../core/sync/cloud_client.dart';

class IdentityWallet {
  const IdentityWallet({
    required this.ownerId,
    required this.miaoCoins,
    required this.eaglePounds,
    required this.gems,
    this.cached = false,
  });
  final String ownerId;
  final int miaoCoins, eaglePounds, gems;
  final bool cached;
  factory IdentityWallet.fromJson(
    Map<String, dynamic> value, {
    bool cached = false,
  }) => IdentityWallet(
    ownerId: value['owner_id'] as String,
    miaoCoins: value['miao_coins'] as int,
    eaglePounds: value['eagle_pounds'] as int,
    gems: value['gems'] as int,
    cached: cached,
  );
}

class IdentityRepository {
  static Future<IdentityWallet> bootstrap() async {
    final client = await CloudClient.connect();
    final owner = client.auth.currentUser!.id;
    final db = AppDatabase();
    try {
      final cached = await db.accountSnapshot(owner);
      try {
        final value = Map<String, dynamic>.from(
          await client
                  .rpc('bootstrap_identity')
                  .timeout(const Duration(seconds: 8))
              as Map,
        );
        final wallet = IdentityWallet.fromJson(value);
        if (wallet.ownerId != owner || client.auth.currentUser?.id != owner) {
          throw StateError('Wallet identity mismatch');
        }
        await db.saveAccountSnapshot(owner, {
          'wallet': value,
          'days': cached?['days'] ?? [],
        });
        return wallet;
      } catch (_) {
        // Only a previously authenticated identity's actual server snapshot may
        // unlock offline study. Never create an initial balance offline.
        if (cached == null || client.auth.currentUser?.id != owner) rethrow;
        final wallet = IdentityWallet.fromJson(
          Map<String, dynamic>.from(cached['wallet'] as Map),
          cached: true,
        );
        if (wallet.ownerId != owner) rethrow;
        return wallet;
      }
    } finally {
      await db.close();
    }
  }
}
