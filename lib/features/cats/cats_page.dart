import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../family/family_page.dart';
import '../identity/identity_repository.dart';
import 'cats_repository.dart';
import '../travel/travel_repository.dart';
import '../travel/travel_sheet.dart';
import '../../core/storage/app_database.dart';

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
  String? failedAction;
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
      failedAction = null;
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
          notice = result['outcome'] == 'traveling'
              ? '这只猫旅行中，不需要喂食。'
              : result['outcome'] == 'fed'
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
        setState(() {
          failedAction = action;
          error = e is PostgrestException && messages[e.message] != null
              ? messages[e.message]
              : action == 'feed_cat'
              ? '喂食结果待确认，请刷新；当天重复请求不会重复扣款。'
              : action == 'cats_state'
              ? '猫咪暂时无法同步，请重试；已有记录仍保留。'
              : e is PostgrestException
              ? '领养未确认成功，请刷新或重试。'
              : '连接失败，请重试；尚未确认领养成功。';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null && failedAction != 'adopt_cat')
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
            ListTile(
              leading: const Icon(Icons.flight_takeoff_outlined),
              title: const Text('猫咪旅行'),
              trailing: const Icon(Icons.chevron_right),
              onTap: busy
                  ? null
                  : () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => TravelSheet(
                            repository: TravelRepository(
                              AppDatabase.shared,
                              widget.ownerId,
                              rpc: widget.call,
                            ),
                            onWallet: widget.onWallet,
                          ),
                        ),
                      );
                      if (mounted) await act('cats_state');
                    },
            ),
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
                margin: const EdgeInsets.only(top: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          portrait(cat['appearance'] as String, size: 96),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cat['name'] as String,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${appearances[cat['appearance']]}\n登记主人：${cat['is_mine'] == true ? '我' : '家庭成员'}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant,
                                    height: 1.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              cat['traveling'] == true
                                  ? '旅行中，无需喂食'
                                  : cat['fed_today'] == true
                                  ? '今日已喂食'
                                  : '今日尚未喂食',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                                height: 1.5,
                              ),
                            ),
                          ),
                          if (cat['traveling'] == true)
                            const Icon(
                              Icons.flight_takeoff_outlined,
                              semanticLabel: '旅行中',
                            )
                          else if (cat['fed_today'] == true)
                            const Icon(
                              Icons.check_circle_outline,
                              semanticLabel: '今日已喂食',
                            )
                          else
                            FilledButton(
                              onPressed: busy || repairing
                                  ? null
                                  : () => act('feed_cat', {
                                      'target_cat': cat['id'],
                                    }),
                              child: const Text('喂食 15'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const Divider(height: 32),
            if (remaining > 0 && !repairing) ...[
              Text('认识新伙伴', style: Theme.of(context).textTheme.titleLarge),
              const Text('免费领养 · 登记主人为本人'),
              const SizedBox(height: 16),
              Row(
                children: [
                  for (final entry in appearances.entries)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: entry.key == appearances.keys.first ? 10 : 0,
                        ),
                        child: Material(
                          color: scheme.surfaceContainerLow,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: appearance == entry.key
                                  ? scheme.primary
                                  : scheme.outlineVariant,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: busy || owned.contains(entry.key)
                                ? null
                                : () => setState(() => appearance = entry.key),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 6,
                              ),
                              child: Column(
                                children: [
                                  Opacity(
                                    opacity: owned.contains(entry.key) ? .5 : 1,
                                    child: portrait(entry.key, size: 84),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    entry.value,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelMedium,
                                  ),
                                  const SizedBox(height: 6),
                                  if (owned.contains(entry.key))
                                    Text(
                                      '已领养',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    )
                                  else
                                    Icon(
                                      appearance == entry.key
                                          ? Icons.check_circle
                                          : Icons.radio_button_unchecked,
                                      size: 18,
                                      color: scheme.primary,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: name,
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: '给猫咪起个名字',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: busy
                    ? null
                    : () {
                        final chosen = name.text.trim();
                        if (chosen.isEmpty) {
                          setState(() {
                            failedAction = 'adopt_cat';
                            error = '请给猫咪起个名字。';
                          });
                          return;
                        }
                        act('adopt_cat', {
                          'appearance_key': appearance,
                          'cat_name': chosen,
                        });
                      },
                child: const Text('免费领养'),
              ),
              if (error != null && failedAction == 'adopt_cat')
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    error!,
                    key: const Key('cat-error'),
                    style: TextStyle(color: scheme.error),
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                '每人最多两只，同一外观只能领养一次；小屋内名字不能重复。',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ] else if (remaining == 0)
              const Text('你的两只猫咪名额已用完。'),
          ],
        ],
      ),
    );
  }

  Widget portrait(String appearance, {double size = 64}) => SizedBox.square(
    dimension: size,
    child: Image.asset(
      'assets/images/cats/${appearance == 'light_long' ? 'longhair' : 'calico'}-sitting-v1.png',
      fit: BoxFit.contain,
      cacheWidth: (size * 3).round(),
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => const Icon(Icons.pets_outlined),
    ),
  );
}
