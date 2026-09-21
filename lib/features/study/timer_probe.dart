import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/storage/probe_database.dart';
import '../../core/time/study_clock.dart';
import 'lock_screen_timer.dart';

class TimerProbe extends StatefulWidget {
  const TimerProbe({super.key, this.databaseFactory});
  final ProbeDatabase Function()? databaseFactory;
  @override
  State<TimerProbe> createState() => _TimerProbeState();
}

class _TimerProbeState extends State<TimerProbe> with WidgetsBindingObserver {
  ProbeDatabase? db;
  StudyClock? clock;
  Timer? tick;
  bool loading = true, busy = false, confirmed = false;
  String? error;
  String? notificationMessage;
  String status = '等待开始';
  AppLifecycleState? lifecycle;
  DateTime? durableAt;
  Future<void> writes = Future.value();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    load();
    tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (clock?.running != true) return;
      final wasRunning = clock!.running;
      clock!.checkpoint(DateTime.now());
      if (clock!.elapsed.inSeconds % 5 == 0 ||
          (wasRunning && !clock!.running)) {
        persist();
      }
      if (!clock!.running) unawaited(LockScreenTimer.stop());
      if (mounted) setState(() {});
    });
  }

  Future<void> load() async {
    await LockScreenTimer.stop();
    try {
      if (!kIsWeb) {
        db = widget.databaseFactory?.call() ?? ProbeDatabase();
        final raw = await db!.readCheckpoint();
        if (raw != null) {
          clock = StudyClock.restore(raw);
          durableAt = clock!.recordedUntil;
          status = '恢复到最后保存点，请核对记录';
        }
      }
    } catch (_) {
      error = '无法读取本机检查点。为避免覆盖旧记录，计时已禁用。';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> persist() {
    final current = clock;
    if (current == null || db == null) return Future.value();
    final raw = current.toJson(), savedAt = current.recordedUntil;
    final database = db!;
    writes = writes.then((_) async {
      try {
        await database.saveCheckpoint(raw);
        if (mounted) {
          setState(() {
            durableAt = savedAt;
            error = null;
          });
        }
      } catch (_) {
        current.running = false;
        await LockScreenTimer.stop();
        if (mounted) {
          setState(() {
            status = '已停止，等待核对';
            notificationMessage = null;
            error = '检查点写入失败，计时已停止。请重试保存。';
          });
        }
      }
    });
    return writes;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (clock?.running == true) {
      clock!.checkpoint(DateTime.now());
      persist();
      if (!clock!.running) unawaited(LockScreenTimer.stop());
    }
    if (mounted) setState(() => lifecycle = state);
  }

  @override
  void dispose() {
    tick?.cancel();
    unawaited(LockScreenTimer.stop());
    WidgetsBinding.instance.removeObserver(this);
    final database = db;
    writes.whenComplete(() => database?.close());
    super.dispose();
  }

  Future<void> start() async {
    setState(() => busy = true);
    final allowed = await LockScreenTimer.requestPermission();
    if (!mounted) return;
    setState(() {
      busy = true;
      confirmed = false;
      clock = StudyClock(DateTime.now());
      status = '计时中';
    });
    await persist();
    final shown =
        allowed &&
        clock!.running &&
        await LockScreenTimer.show(clock!.startedAt);
    if (mounted) {
      setState(() {
        busy = false;
        notificationMessage = error != null || !LockScreenTimer.supported
            ? null
            : shown
            ? '锁屏计时通知已开启；是否展示由手机通知设置控制。'
            : '锁屏计时通知未开启。可在系统设置中允许通知；应用内计时仍可使用。';
      });
    }
  }

  Future<void> stop() async {
    setState(() {
      busy = true;
      clock!.stop(DateTime.now());
      status = '已结束，等待核对';
      notificationMessage = null;
    });
    await persist();
    await LockScreenTimer.stop();
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = clock?.elapsed ?? Duration.zero;
    final time = [
      elapsed.inHours,
      elapsed.inMinutes % 60,
      elapsed.inSeconds % 60,
    ].map((n) => n.toString().padLeft(2, '0')).join(':');
    final running = clock?.running == true;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('留一段时间给自己', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        const Text('计时技术探针 · 不发放货币'),
        const SizedBox(height: 36),
        Center(
          child: Text(
            time,
            key: const Key('timer-value'),
            style: const TextStyle(
              fontSize: 48,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(height: 28),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (error != null && clock != null)
          TextButton(onPressed: persist, child: const Text('重试保存检查点')),
        if (!loading)
          FilledButton(
            onPressed:
                busy ||
                    error != null ||
                    (!running && clock != null && !confirmed)
                ? null
                : running
                ? stop
                : start,
            child: Text(
              running
                  ? '结束计时'
                  : clock == null
                  ? '开始计时'
                  : '开始新记录',
            ),
          ),
        if (clock != null && !running && !confirmed)
          OutlinedButton(
            onPressed: busy || error != null
                ? null
                : () => setState(() {
                    confirmed = true;
                    status = '已核对本次探针记录（未入账）';
                  }),
            child: const Text('确认探针记录'),
          ),
        const SizedBox(height: 20),
        Text(status),
        if (notificationMessage != null) Text(notificationMessage!),
        if (lifecycle != null) Text('生命周期：${lifecycle!.name}'),
        if (elapsed >= const Duration(hours: 6))
          const Text('已达到单次最长计时，请休息一下吧。'),
        if (clock?.clockReversed == true) const Text('检测到系统时间回退，结果需核查。'),
        const Divider(height: 36),
        const Text('UTC+8 原始分段（尚未结算）'),
        if (clock != null)
          for (final day in clock!.secondsByDay.entries)
            Text('${day.key}  ·  ${day.value} 秒'),
        const SizedBox(height: 20),
        Text(
          kIsWeb
              ? '浏览器预览只保留内存记录，不用于后台或可靠存储验收。'
              : 'SQLite 检查点：${durableAt?.toLocal().toString() ?? '尚无'}',
        ),
        const Text(
          '实验间隔：5 秒（待 Q07 实测审阅）。系统暂停期间不能保证写入。重新启动仅恢复已落盘时间；同进程返回按时间戳续计，上限 6 小时。修改系统时间可能影响本探针。',
        ),
        const SizedBox(height: 16),
        const Text('跨零点自动入账尚未实现。后台执行、异常终止与连续 6 小时需要真机分别验证。'),
      ],
    );
  }
}
