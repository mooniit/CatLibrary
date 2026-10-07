import 'dart:async';
import 'package:flutter/material.dart';
import '../identity/identity_repository.dart';
import 'travel_repository.dart';
import 'return_sheet.dart';

class TravelSheet extends StatefulWidget {
  const TravelSheet({super.key, required this.repository, this.onWallet});
  final TravelRepository repository;
  final ValueChanged<IdentityWallet>? onWallet;
  @override
  State<TravelSheet> createState() => _TravelSheetState();
}

class _TravelSheetState extends State<TravelSheet> with WidgetsBindingObserver {
  Map<String, dynamic>? data;
  bool busy = false, offline = false;
  String? message;
  final elapsed = Stopwatch();
  Timer? timer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !busy) load();
  }

  DateTime get serverNow =>
      DateTime.parse(data!['server_time']).add(elapsed.elapsed);
  String countdown(String end) {
    final d = DateTime.parse(end).difference(serverNow);
    if (d.isNegative || d.inSeconds == 0) return '等待返程核对';
    return '${d.inHours.toString().padLeft(2, '0')}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  Future<void> load() async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final receipt = await widget.repository.reconcile();
      final raw = await widget.repository.load();
      if (!mounted) return;
      final wallet = IdentityWallet.fromJson(
        Map<String, dynamic>.from(raw['wallet']),
      );
      if (wallet.ownerId != widget.repository.ownerId) {
        throw StateError('身份已改变');
      }
      widget.onWallet?.call(wallet);
      setState(() {
        data = raw;
        offline = false;
        elapsed
          ..reset()
          ..start();
        message = receipt == null ? null : travelReceiptMessage(receipt);
      });
    } catch (_) {
      final cache = await widget.repository.cached();
      if (mounted) {
        setState(() {
          data ??= cache;
          offline = true;
          message = '连接未确认，已保留待核对请求。重连后点击刷新。';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> start(Map cat) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('让${cat['name']}去旅行？'),
        content: const Text('支付个人 60 宝石，24 小时后回家。目的地在返程时揭晓。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('出发 · 60 宝石'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    try {
      final receipt = await widget.repository.start(
        data!['family_id'],
        cat['id'],
      );
      if (mounted) setState(() => message = travelReceiptMessage(receipt));
    } catch (_) {
      if (mounted) {
        setState(() {
          offline = true;
          message = '出发结果待核对，请刷新；不会重新创建付款请求。';
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
    if (!offline) {
      final notice = message;
      await load();
      if (mounted) setState(() => message = notice);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = data?['cats'] as List? ?? [];
    return Scaffold(
      appBar: AppBar(
        title: const Text('猫咪旅行'),
        actions: [
          IconButton(
            tooltip: '核对旅行',
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (busy) const LinearProgressIndicator(),
          Row(
            children: [
              const Icon(Icons.diamond_outlined, size: 20),
              const SizedBox(width: 8),
              Text(
                '${data?['wallet']?['gems'] ?? '—'}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const Spacer(),
              const Text('24 小时 · 60 宝石'),
            ],
          ),
          const SizedBox(height: 16),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(message!, key: const Key('travel-message')),
            ),
          if (data?['repairing'] == true)
            const ListTile(
              leading: Icon(Icons.handyman_outlined),
              title: Text('修缮中暂不能出发'),
              subtitle: Text('已有旅行照常计时，返程奖励不会丢失。'),
            ),
          if (data?['family_id'] == null && !busy)
            const Text('请先创建或加入小屋，再领养猫咪。'),
          for (final trip in data?['returns'] as List? ?? [])
            ListTile(
              leading: const Icon(Icons.markunread_mailbox_outlined),
              title: Text('${trip['cat_name']}回来了'),
              subtitle: Text(trip['destination_label']),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showTravelReturn(
                context,
                Map<String, dynamic>.from(trip),
                widget.repository,
                load,
              ),
            ),
          for (final cat in cats)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.pets_outlined, size: 30),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              cat['name'],
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          Text('${cat['visited']}/6'),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (cat['trip_id'] != null)
                        Row(
                          children: [
                            const Icon(Icons.flight_takeoff_outlined, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                offline
                                    ? '旅行中 · 离线记录'
                                    : countdown(cat['ends_at']),
                              ),
                            ),
                            if (!offline &&
                                DateTime.parse(
                                  cat['ends_at'],
                                ).isBefore(serverNow))
                              IconButton(
                                tooltip: '核对返程',
                                onPressed: busy ? null : load,
                                icon: const Icon(Icons.sync),
                              ),
                          ],
                        )
                      else
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            key: ValueKey('travel-${cat['id']}'),
                            onPressed:
                                busy || offline || data?['repairing'] == true
                                ? null
                                : () => start(cat),
                            icon: const Icon(Icons.flight_takeoff, size: 18),
                            label: const Text('出发'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          if (cats.isEmpty && data?['family_id'] != null)
            const Text('小屋还没有猫咪，先去猫咪管理认识一位伙伴。'),
          const SizedBox(height: 20),
          const Text(
            '未访地点优先。每只猫首次到访，带回一张旅行记录和一件纪念品。',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}

String travelReceiptMessage(Map receipt) => receipt['status'] == 'started'
    ? '出发成功，24 小时后回家。'
    : switch (receipt['reason']) {
        'insufficient_gems' => '宝石不足 60，未扣款。',
        'already_traveling' => '这只猫已经在旅行中。',
        'repair_in_progress' => '修缮中暂不能安排新旅行。',
        'family_required' || 'family_changed' => '小屋已改变，请重新进入。',
        'cat_unavailable' => '猫咪不属于当前小屋。',
        _ => '旅行未确认成功，请刷新核对。',
      };
