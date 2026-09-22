import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'family_repository.dart';

class FamilyPage extends StatefulWidget {
  const FamilyPage({
    super.key,
    required this.ownerId,
    this.call = FamilyRepository.call,
  });
  final String ownerId;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)
  call;
  @override
  State<FamilyPage> createState() => _FamilyPageState();
}

class _FamilyPageState extends State<FamilyPage> {
  final code = TextEditingController();
  Map<String, dynamic>? data;
  bool busy = true;
  String? error;
  @override
  void initState() {
    super.initState();
    act('family_state');
  }

  @override
  void dispose() {
    code.dispose();
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
      if (mounted) setState(() => data = result);
    } catch (e) {
      const messages = {
        'Already in a family': '你已经属于一个小屋，暂不支持家庭合并。',
        'Applicant already in a family': '申请者已经加入其他小屋，不能合并家庭。',
        'Invalid invitation code': '邀请码无效，请检查后重试。',
        'Family is full': '小屋已满两人，无法加入。',
        'Only inviter may decide': '只有邀请人可以处理这条申请。',
      };
      if (mounted) {
        setState(
          () => error = e is PostgrestException
              ? messages[e.message] ?? '操作未完成，请刷新状态后重试。'
              : '连接失败，请检查网络后重试。',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final family = data?['family'] as Map?;
    final members = (data?['members'] as List?) ?? [];
    final requests = (data?['requests'] as List?) ?? [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('我们的小屋'),
        actions: [
          IconButton(
            tooltip: '刷新小屋',
            onPressed: busy ? null : () => act('family_state'),
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
              child: Text(error!, key: const Key('family-error')),
            ),
          if (data == null && !busy)
            FilledButton(
              onPressed: () => act('family_state'),
              child: const Text('重试连接'),
            ),
          if (data != null && family == null) ...[
            Text('选择你的小屋', style: Theme.of(context).textTheme.headlineSmall),
            const Text('可以建立自己的小屋，也可以直接申请加入对方的小屋。无需先领养猫咪。'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : () => act('create_family'),
              child: const Text('创建我的小屋'),
            ),
            const Divider(height: 40),
            TextField(
              controller: code,
              enabled: !busy,
              decoration: const InputDecoration(
                labelText: '邀请码',
                hintText: '粘贴对方分享的邀请码',
              ),
              maxLength: 32,
            ),
            FilledButton.tonal(
              onPressed: busy
                  ? null
                  : () {
                      if (code.text.trim().isEmpty) {
                        setState(() => error = '请先填写邀请码。');
                        return;
                      }
                      act('request_family_join', {'code': code.text.trim()});
                    },
              child: const Text('申请加入'),
            ),
            const Text('提交后需要邀请人确认。确认前不会加入。'),
            for (final request in requests)
              ListTile(
                title: Text(
                  request['status'] == 'pending'
                      ? '等待邀请人确认'
                      : request['status'] == 'rejected'
                      ? '申请未通过'
                      : '申请已通过，请刷新',
                ),
              ),
          ],
          if (family != null) ...[
            Text(
              '小屋成员 ${members.length}/2',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            for (final member in members)
              ListTile(
                title: Text(member['is_me'] == true ? '我' : '共同成员'),
                subtitle: SelectableText(member['user_id'] as String),
              ),
            if (family['is_creator'] == true) ...[
              const Divider(height: 32),
              const Text('分享邀请码'),
              SelectableText(family['invite_code'] as String),
              OutlinedButton.icon(
                onPressed: busy
                    ? null
                    : () async {
                        await Clipboard.setData(
                          ClipboardData(text: family['invite_code'] as String),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('邀请码已复制')),
                          );
                        }
                      },
                icon: const Icon(Icons.copy),
                label: const Text('复制邀请码'),
              ),
              const Text('对方输入后，你需要在这里确认申请。小屋最多两人。'),
              const SizedBox(height: 20),
              const Text('待处理申请'),
              if (requests.isEmpty) const Text('暂无申请。对方提交后点击右上角刷新。'),
              for (final request in requests)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('申请加入的用户'),
                        SelectableText(request['applicant_id'] as String),
                        Wrap(
                          spacing: 12,
                          children: [
                            FilledButton(
                              onPressed: busy
                                  ? null
                                  : () => act('decide_family_join', {
                                      'request_id': request['id'],
                                      'approve': true,
                                    }),
                              child: const Text('同意加入'),
                            ),
                            TextButton(
                              onPressed: busy
                                  ? null
                                  : () => act('decide_family_join', {
                                      'request_id': request['id'],
                                      'approve': false,
                                    }),
                              child: const Text('不接受'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 16),
            const Text('首版不提供退出家庭或合并已有家庭。'),
          ],
          const Divider(height: 32),
          const Text('我的用户编号'),
          SelectableText(widget.ownerId),
        ],
      ),
    );
  }
}
