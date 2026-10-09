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
  bool failed = false;
  bool detailsExpanded = true;
  int request = 0;
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
    final current = ++request;
    final owner = widget.ownerId;
    final load = widget.load ?? _load;
    setState(() => loading = true);
    try {
      final value = await load().timeout(const Duration(seconds: 8));
      if (!{'none', 'active', 'completed'}.contains(value['status'])) {
        throw StateError('Unknown repair state');
      }
      if (mounted && current == request && owner == widget.ownerId) {
        setState(() {
          state = value;
          failed = false;
        });
      }
    } catch (_) {
      if (mounted && current == request && owner == widget.ownerId) {
        setState(() => failed = true);
      }
    } finally {
      if (mounted && current == request && owner == widget.ownerId) {
        setState(() => loading = false);
      }
    }
  }

  @override
  void didUpdateWidget(RepairPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ownerId != widget.ownerId) {
      ++request;
      state = null;
      failed = false;
      loading = false;
      detailsExpanded = true;
      unawaited(refresh());
    }
  }

  Widget retryButton() => IconButton(
    tooltip: '重新核对修缮状态',
    onPressed: loading ? null : refresh,
    icon: loading
        ? const SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.sync_rounded, size: 20),
  );

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
      if (!failed && !loading) return const SizedBox.shrink();
      return Card(
        key: const Key('repair-sync-status'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
          child: Row(
            children: [
              Icon(
                Icons.home_repair_service_outlined,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(loading ? '正在核对修缮状态' : '修缮状态暂未同步')),
              retryButton(),
            ],
          ),
        ),
      );
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
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  complete
                      ? Icons.check_circle_outline_rounded
                      : Icons.home_repair_service_outlined,
                  color: Theme.of(context).colorScheme.primary,
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    complete ? '小屋修缮完成' : '小屋修缮中',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                retryButton(),
                IconButton(
                  tooltip: detailsExpanded ? '收起修缮详情' : '展开修缮详情',
                  onPressed: () =>
                      setState(() => detailsExpanded = !detailsExpanded),
                  icon: Icon(
                    detailsExpanded
                        ? Icons.expand_more_rounded
                        : Icons.expand_less_rounded,
                    size: 20,
                  ),
                ),
              ],
            ),
            if (failed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '暂未同步，保留上次确认的进度',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (detailsExpanded) ...[
              const SizedBox(height: 8),
              if (!complete) ...[
                Text(
                  '第 ${value['cycle_no']} 轮 · 剩余 $clock',
                  key: const Key('repair-countdown'),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    minHeight: 6,
                    value: (progress / target).clamp(0, 1),
                  ),
                ),
                const SizedBox(height: 8),
                Text('共同计时 ${(progress ~/ 60000).clamp(0, 120)} / 120 分钟'),
                const Text('自习或任务计时均可推进；修缮时间不产生货币。'),
              ] else
                Text('正常养猫已恢复；免缴至 ${value['grace_through']}（北京时间）。'),
            ],
          ],
        ),
      ),
    );
  }
}
