import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/sync/cloud_client.dart';

class RepairPanel extends StatefulWidget {
  const RepairPanel({super.key, required this.ownerId, this.load});

  final String ownerId;
  final Future<Map<String, dynamic>> Function()? load;

  @override
  State<RepairPanel> createState() => _RepairPanelState();
}

class _RepairPanelState extends State<RepairPanel> with WidgetsBindingObserver {
  Timer? timer;
  Map<String, dynamic>? state;
  DateTime now = DateTime.now();
  bool loading = false;
  int ticks = 0;

  Future<Map<String, dynamic>> _load() async {
    final client = await CloudClient.connect();
    if (client.auth.currentUser?.id != widget.ownerId) {
      throw StateError('Identity changed');
    }
    return Map<String, dynamic>.from(
      await client.rpc('repair_state').timeout(const Duration(seconds: 8))
          as Map,
    );
  }

  Future<void> refresh() async {
    if (loading || !mounted) return;
    loading = true;
    try {
      final value = await (widget.load ?? _load)();
      if (mounted) setState(() => state = value);
    } catch (_) {
      // Keep the last confirmed state until the next online read.
    } finally {
      loading = false;
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(refresh()));
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => now = DateTime.now());
      if (++ticks % 60 == 0) unawaited(refresh());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState status) {
    if (status == AppLifecycleState.resumed) unawaited(refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = state;
    final beijingDay = now
        .toUtc()
        .add(const Duration(hours: 8))
        .toIso8601String()
        .substring(0, 10);
    if (value == null ||
        (value['status'] == 'none' &&
            (value['grace_through'] == null ||
                value['grace_through'].toString().compareTo(beijingDay) < 0))) {
      return const SizedBox.shrink();
    }
    final complete = value['status'] != 'active';
    final progress = (value['progress_ms'] as num?)?.toInt() ?? 0;
    final target = (value['target_ms'] as num?)?.toInt() ?? 7200000;
    final end = DateTime.tryParse(value['ends_at']?.toString() ?? '');
    final remaining = end?.difference(now) ?? Duration.zero;
    final seconds = remaining.inSeconds.clamp(0, 259200);
    final clock =
        '${(seconds ~/ 3600).toString().padLeft(2, '0')}'
        ':${((seconds ~/ 60) % 60).toString().padLeft(2, '0')}'
        ':${(seconds % 60).toString().padLeft(2, '0')}';
    return Card(
      key: const Key('repair-panel'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              complete ? '小屋修缮完成' : '小屋修缮中',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            if (!complete) ...[
              Text(
                '第 ${value['cycle_no']} 轮 · 剩余 $clock',
                key: const Key('repair-countdown'),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: (progress / target).clamp(0, 1)),
              Text('共同计时 ${(progress ~/ 60000).clamp(0, 120)} / 120 分钟'),
              const Text('自习或任务计时均可推进；修缮时间不产生货币。'),
            ] else
              Text('正常养猫已恢复；免缴至 ${value['grace_through']}（北京时间）。'),
          ],
        ),
      ),
    );
  }
}
