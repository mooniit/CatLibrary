import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/storage/app_database.dart';
import '../identity/identity_repository.dart';
import 'wallet_repository.dart';

class ExchangeSheet extends StatefulWidget {
  const ExchangeSheet({
    super.key,
    required this.wallet,
    required this.onWallet,
  });
  final IdentityWallet wallet;
  final ValueChanged<IdentityWallet> onWallet;
  @override
  State<ExchangeSheet> createState() => _ExchangeSheetState();
}

class _ExchangeSheetState extends State<ExchangeSheet> {
  final AppDatabase db = AppDatabase.shared;
  late final WalletRepository repository = WalletRepository(
    db,
    widget.wallet.ownerId,
  );
  (String, String)? pending;
  late IdentityWallet wallet = widget.wallet;
  bool busy = false, loading = true;
  String? message;

  @override
  void initState() {
    super.initState();
    repository.pending().then((value) {
      if (mounted) {
        setState(() {
          pending = value;
          loading = false;
        });
      }
    });
  }

  Future<void> exchange(String currency) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final wallet = await repository.exchange(currency);
      this.wallet = wallet;
      widget.onWallet(wallet);
      if (mounted) setState(() => message = '兑换成功，已将 5 喵喵币计入钱包。');
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(
          () => message =
              error.code == '22023' &&
                  error.message == 'Insufficient special currency'
              ? '余额不足，未兑换。'
              : '兑换尚未核实；请重试同一笔。',
        );
      }
    } catch (_) {
      if (mounted) setState(() => message = '兑换未完成或尚未核实；如显示待核对，请重试同一笔。');
    } finally {
      final value = await repository.pending();
      if (mounted) {
        setState(() {
          pending = value;
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('兑换喵喵币', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('每次兑换 1 枚鹰镑或 1 颗宝石，获得 5 喵喵币。余额为负时先抵扣欠款。'),
          const SizedBox(height: 16),
          if (pending != null)
            Text('有一笔${pending!.$2 == 'eagle' ? '鹰镑' : '宝石'}兑换待核对，请重试。'),
          if (message != null) Text(message!),
          const SizedBox(height: 8),
          FilledButton(
            onPressed:
                busy ||
                    loading ||
                    pending != null && pending!.$2 != 'eagle' ||
                    pending == null && wallet.eaglePounds < 1
                ? null
                : () => exchange('eagle'),
            child: const Text('1 鹰镑 → 5 喵喵币'),
          ),
          FilledButton(
            onPressed:
                busy ||
                    loading ||
                    pending != null && pending!.$2 != 'gem' ||
                    pending == null && wallet.gems < 1
                ? null
                : () => exchange('gem'),
            child: const Text('1 宝石 → 5 喵喵币'),
          ),
        ],
      ),
    ),
  );
}
