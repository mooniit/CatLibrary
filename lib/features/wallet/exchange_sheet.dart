import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/storage/app_database.dart';
import '../identity/identity_repository.dart';
import 'wallet_repository.dart';

class ExchangeSheet extends StatefulWidget {
  const ExchangeSheet({
    super.key,
    required this.wallet,
    required this.onWallet,
    this.repository,
  });
  final IdentityWallet wallet;
  final ValueChanged<IdentityWallet> onWallet;
  final WalletRepository? repository;
  @override
  State<ExchangeSheet> createState() => _ExchangeSheetState();
}

class _ExchangeSheetState extends State<ExchangeSheet> {
  late final repository =
      widget.repository ??
      WalletRepository(AppDatabase.shared, widget.wallet.ownerId);
  final input = TextEditingController(text: '1');
  late IdentityWallet wallet = widget.wallet;
  (String, String, int)? pending;
  String currency = 'gem';
  String? message;
  bool busy = false, loading = true, loadFailed = false;
  int? get quantity => int.tryParse(input.text);
  int get available => currency == 'gem' ? wallet.gems : wallet.eaglePounds;
  @override
  void initState() {
    super.initState();
    repository
        .pending()
        .then((value) {
          if (mounted) {
            setState(() {
              pending = value;
              loading = false;
              if (value != null) {
                currency = value.$2;
                input.text = '${value.$3}';
              }
            });
          }
        })
        .catchError((_) {
          if (mounted) {
            setState(() {
              loading = false;
              loadFailed = true;
              message = '原请求暂未读取，请重新打开弹窗核对。';
            });
          }
        });
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> exchange() async {
    final amount = pending?.$3 ?? quantity;
    if (busy || amount == null || amount < 1 || amount > 429496729) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final updated = await repository.exchange(currency, quantity: amount);
      wallet = updated;
      widget.onWallet(updated);
      if (mounted) setState(() => message = '兑换成功，${amount * 5} 喵喵币已入账。');
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(
          () => message = error.message == 'Insufficient special currency'
              ? '余额不足，未兑换。'
              : '兑换尚未核实，请重试原请求。',
        );
      }
    } catch (_) {
      if (mounted) setState(() => message = '兑换结果待核对，请重试原请求。');
    } finally {
      try {
        final waiting = await repository.pending();
        if (mounted) {
          setState(() {
            pending = waiting;
            busy = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            busy = false;
            loadFailed = true;
            message = '原请求暂未读取，请重新打开弹窗核对。';
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final amount = quantity;
    final valid =
        amount != null &&
        amount > 0 &&
        amount <= 429496729 &&
        amount <= available;
    return PopScope(
      canPop: !busy,
      child: AlertDialog(
        title: const Text('兑换喵喵币'),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'gem', label: Text('宝石')),
                    ButtonSegment(value: 'eagle', label: Text('鹰镑')),
                  ],
                  selected: {currency},
                  onSelectionChanged:
                      busy || loading || loadFailed || pending != null
                      ? null
                      : (v) => setState(() => currency = v.single),
                ),
                const SizedBox(height: 12),
                Text('可用 $available ${currency == 'gem' ? '颗宝石' : '枚鹰镑'}'),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('exchange-quantity'),
                  controller: input,
                  enabled: !busy && !loading && !loadFailed && pending == null,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: '兑换数量',
                    errorText: amount == null || amount < 1
                        ? '请输入正整数'
                        : amount > available && pending == null
                        ? '余额不足'
                        : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Text(
                  '获得 ${(amount ?? 0) * 5} 喵喵币',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text('1 宝石或1鹰镑 = 5喵喵币，欠款优先抵扣。'),
                if (pending != null) const Text('上次兑换结果待核对，金额与币种已锁定。'),
                if (message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(message!),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          FilledButton(
            key: const Key('exchange-submit'),
            onPressed:
                busy || loading || loadFailed || (!valid && pending == null)
                ? null
                : exchange,
            child: Text(
              busy
                  ? '正在核对…'
                  : pending != null
                  ? '核对原兑换'
                  : '确认兑换',
            ),
          ),
        ],
      ),
    );
  }
}
