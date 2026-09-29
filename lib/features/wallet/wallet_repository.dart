import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/storage/app_database.dart';
import '../../core/sync/cloud_client.dart';
import '../identity/identity_repository.dart';

class WalletRepository {
  WalletRepository(this.database, this.ownerId);
  final AppDatabase database;
  final String ownerId;

  Future<(String, String)?> pending() => database.pendingExchange(ownerId);

  Future<IdentityWallet> exchange(String currency) async {
    if (currency != 'eagle' && currency != 'gem') {
      throw ArgumentError('Unknown currency');
    }
    final pending = await database.pendingExchange(ownerId);
    if (pending != null && pending.$2 != currency) {
      throw StateError('Finish the previous exchange first');
    }
    final requestId = pending?.$1 ?? _newId();
    if (pending == null) {
      await database.queueExchange(ownerId, requestId, currency);
    }
    final client = await CloudClient.connect();
    if (client.auth.currentUser?.id != ownerId) {
      throw StateError('Identity changed');
    }
    late final Map<String, dynamic> result;
    try {
      result = Map<String, dynamic>.from(
        await client
                .rpc(
                  'exchange_special',
                  params: {
                    'request_id': requestId,
                    'source_currency': currency,
                  },
                )
                .timeout(const Duration(seconds: 10))
            as Map,
      );
    } on PostgrestException catch (error) {
      if (error.code == '22023' &&
          error.message == 'Insufficient special currency') {
        await database.acknowledgeExchange(ownerId, requestId);
      }
      rethrow;
    }
    final wallet = IdentityWallet.fromJson(
      Map<String, dynamic>.from(result['wallet'] as Map),
    );
    if (wallet.ownerId != ownerId || client.auth.currentUser?.id != ownerId) {
      throw StateError('Wallet identity mismatch');
    }
    final cached = await database.accountSnapshot(ownerId);
    await database.saveAccountSnapshot(ownerId, {
      'wallet': result['wallet'],
      'days': cached?['days'] ?? [],
    });
    await database.acknowledgeExchange(ownerId, requestId);
    return wallet;
  }

  static String _newId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
