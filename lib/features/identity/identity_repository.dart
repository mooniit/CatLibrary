import '../../core/sync/cloud_client.dart';

class IdentityWallet {
  const IdentityWallet({
    required this.ownerId,
    required this.miaoCoins,
    required this.eaglePounds,
    required this.gems,
  });
  final String ownerId;
  final int miaoCoins, eaglePounds, gems;
  factory IdentityWallet.fromJson(Map<String, dynamic> value) => IdentityWallet(
    ownerId: value['owner_id'] as String,
    miaoCoins: value['miao_coins'] as int,
    eaglePounds: value['eagle_pounds'] as int,
    gems: value['gems'] as int,
  );
}

class IdentityRepository {
  static Future<IdentityWallet> bootstrap() async {
    final client = await CloudClient.connect();
    final value = await client.rpc('bootstrap_identity');
    final wallet = IdentityWallet.fromJson(
      Map<String, dynamic>.from(value as Map),
    );
    if (wallet.ownerId != client.auth.currentUser?.id) {
      throw StateError('Wallet identity mismatch');
    }
    return wallet;
  }
}
