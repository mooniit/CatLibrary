import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../family/family_page.dart';
import '../identity/identity_repository.dart';
import 'cats_repository.dart';

class CatsPage extends StatefulWidget {
  const CatsPage({
    super.key,
    required this.ownerId,
    this.onWallet,
    this.call = CatsRepository.call,
  });
  final String ownerId;
  final ValueChanged<IdentityWallet>? onWallet;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  call;
  @override
  State<CatsPage> createState() => _CatsPageState();
}

class _CatsPageState extends State<CatsPage> {
  static const appearances = {'black_short': '三花猫', 'light_long': '蓝眸长毛猫'};
  final name = TextEditingController();
  String appearance = 'black_short';
  Map<String, dynamic>? data;
  bool busy = true;
  String? error;
  String? notice;
  @override
  void initState() {
    super.initState();
    act('cats_state');
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> act(
    String action, [
    Map<String, dynamic> args = const {},
  ]) async {
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      final result = await widget.call(action, args);
      if (!mounted) return;
      if (result['wallet'] case final Map walletData) {
        final wallet = IdentityWallet.fromJson(
          Map<String, dynamic>.from(walletData),
        );
        if (wallet.ownerId != widget.ownerId) {
          throw StateError('Wallet identity mismatch');
        }
        widget.onWallet?.call(wallet);
      }
      final owned = (result['cats'] as List)
          .where((c) => c['is_mine'] == true)
          .map((c) => c['appearance'])
          .toSet();
      setState(() {
        data = result;
        if (owned.contains(appearance)) {
          appearance = appearances.keys.firstWhere(
            (key) => !owned.contains(key),
            orElse: () => appearance,
          );
        }
        if (action == 'adopt_cat') name.clear();
        if (action == 'feed_cat') {
          notice = result['outcome'] == 'fed'
              ? '已支付 15 喵喵币，今天不用再为这只猫付费。'
              : '这只猫今天已喂食，没有重复扣款。';
        }
      });
    } catch (e) {
      const messages = {
        'Join or create a family first': '请先创建或加入小屋。',
        'Cat name required': '请给猫咪起个名字。',
        'Cat name already used': '小屋里已有同名猫咪，请换个名字。',
        'Appearance already adopted': '你已领养过这种外观，请刷新后选择另一种。',
        'Adoption quota reached': '你的两只猫咪名额已用完。',
        'Invalid appearance': '请选择有效的猫咪外观。',
        'Insufficient miao coins': '喵喵币不足 15，无法主动喂食。',
        'Cat is outside your family': '这只猫不属于当前小屋。',
        'Repair in progress': '小屋修缮中，暂不能领养或喂食。',
      };
      if (mounted) {
        setState(
          () => error = e is PostgrestException && messages[e.message] != null
              ? messages[e.message]
              : action == 'feed_cat'
              ? '喂食结果待确认，请刷新；当天重复请求不会重复扣款。'
              : e is PostgrestException
              ? '领养未确认成功，请刷新或重试。'
              : '连接失败，请重试；尚未确认领养成功。',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = (data?['cats'] as List?) ?? [];
    final owned = cats
        .where((c) => c['is_mine'] == true)
        .map((c) => c['appearance'])
        .toSet();
    final hasFamily = data?['family_id'] != null;
    final repairing = data?['repairing'] == true;
    final remaining = (data?['remaining'] as int?) ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('猫咪管理'),
        actions: [
          IconButton(
            tooltip: '刷新猫咪',
            onPressed: busy ? null : () => act('cats_state'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(error!, key: const Key('cat-error')),
            ),
          if (notice != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(notice!, key: const Key('feeding-notice')),
            ),
          if (data == null && !busy)
            FilledButton(
              onPressed: () => act('cats_state'),
              child: const Text('重试连接'),
            ),
          if (data != null && !hasFamily) ...[
            const Text('先选择你的小屋'),
            const Text('可以创建单人小屋，也可以用邀请码加入对方的小屋。无需先领养猫咪。'),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => FamilyPage(ownerId: widget.ownerId),
                        ),
                      );
                      if (mounted) await act('cats_state');
                    },
              child: const Text('去创建或加入小屋'),
            ),
          ],
          if (hasFamily) ...[
            if (repairing)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.handyman_outlined),
                  title: Text('小屋修缮中'),
                  subtitle: Text('暂不能领养或喂食；计时任务仍可继续推进修缮。'),
                ),
              ),
            Text(
              '家庭猫咪 ${cats.length}/4',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text('本人剩余领养名额：$remaining', key: const Key('cat-quota')),
            if (data?['wallet'] case final Map walletData)
              Text('个人余额：${walletData['miao_coins']} 喵喵币'),
            if (cats.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('小屋还没有猫咪，认识第一位新伙伴吧。'),
              ),
            for (final cat in cats)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.pets_outlined),
                  title: Text(cat['name'] as String),
                  subtitle: Text(
                    '${appearances[cat['appearance']]}\n登记主人：${cat['is_mine'] == true ? '我' : cat['owner_id']}'
                    '\n${cat['fed_today'] == true ? '今日已喂食' : '今日尚未喂食'}',
                  ),
                  trailing: cat['fed_today'] == true
                      ? const Icon(
                          Icons.check_circle_outline,
                          semanticLabel: '今日已喂食',
                        )
                      : FilledButton(
                          onPressed: busy || repairing
                              ? null
                              : () =>
                                    act('feed_cat', {'target_cat': cat['id']}),
                          child: const Text('喂食 15'),
                        ),
                ),
              ),
            const Divider(height: 32),
            if (remaining > 0 && !repairing) ...[
              Text('认识新伙伴', style: Theme.of(context).textTheme.titleLarge),
              const Text('免费领养 · 登记主人为本人'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey(appearance),
                initialValue: appearance,
                items: [
                  for (final entry in appearances.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      enabled: !owned.contains(entry.key),
                      child: Text(
                        '${entry.value}${owned.contains(entry.key) ? '（已领养）' : ''}',
                      ),
                    ),
                ],
                onChanged: busy
                    ? null
                    : (value) => setState(() => appearance = value!),
              ),
              TextField(
                controller: name,
                enabled: !busy,
                decoration: const InputDecoration(labelText: '给猫咪起个名字'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: busy
                    ? null
                    : () {
                        final chosen = name.text.trim();
                        if (chosen.isEmpty) {
                          setState(() => error = '请给猫咪起个名字。');
                          return;
                        }
                        act('adopt_cat', {
                          'appearance_key': appearance,
                          'cat_name': chosen,
                        });
                      },
                child: const Text('免费领养'),
              ),
              const Text('每人最多两只，同一外观只能领养一次；小屋内名字不能重复。'),
            ] else if (remaining == 0)
              const Text('你的两只猫咪名额已用完。'),
            const SizedBox(height: 20),
            const Text('可选三花猫或蓝眸长毛猫；猫咪性格由你后续补充。'),
          ],
        ],
      ),
    );
  }
}
