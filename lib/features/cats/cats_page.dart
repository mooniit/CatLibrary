import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../family/family_page.dart';
import 'cats_repository.dart';

class CatsPage extends StatefulWidget {
  const CatsPage({
    super.key,
    required this.ownerId,
    this.call = CatsRepository.call,
  });
  final String ownerId;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  call;
  @override
  State<CatsPage> createState() => _CatsPageState();
}

class _CatsPageState extends State<CatsPage> {
  static const appearances = {'black_short': '黑色短毛猫', 'light_long': '浅色长毛猫'};
  final name = TextEditingController();
  String appearance = 'black_short';
  Map<String, dynamic>? data;
  bool busy = true;
  String? error;
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
    });
    try {
      final result = await widget.call(action, args);
      if (!mounted) return;
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
      });
    } catch (e) {
      const messages = {
        'Join or create a family first': '请先创建或加入小屋。',
        'Cat name required': '请给猫咪起个名字。',
        'Cat name already used': '小屋里已有同名猫咪，请换个名字。',
        'Appearance already adopted': '你已领养过这种外观，请刷新后选择另一种。',
        'Adoption quota reached': '你的两只猫咪名额已用完。',
        'Invalid appearance': '请选择有效的猫咪外观。',
      };
      if (mounted) {
        setState(
          () => error = e is PostgrestException
              ? messages[e.message] ?? '领养未确认成功，请刷新或重试。'
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
            Text(
              '家庭猫咪 ${cats.length}/4',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text('本人剩余领养名额：$remaining', key: const Key('cat-quota')),
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
                    '${appearances[cat['appearance']]}\n登记主人：${cat['is_mine'] == true ? '我' : cat['owner_id']}',
                  ),
                ),
              ),
            const Divider(height: 32),
            if (remaining > 0) ...[
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
            ] else
              const Text('你的两只猫咪名额已用完。'),
            const SizedBox(height: 20),
            const Text('外观画面暂不制作，性格由你后续补充。'),
          ],
        ],
      ),
    );
  }
}
