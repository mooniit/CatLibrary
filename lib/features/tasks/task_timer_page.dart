import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../study/lock_screen_timer.dart';
import 'task_repository.dart';
import 'task_session.dart';

class TaskTimerPage extends StatefulWidget {
  const TaskTimerPage({
    super.key,
    required this.repository,
    required this.onSync,
  });
  final TaskRepository repository;
  final Future<void> Function() onSync;
  @override
  State<TaskTimerPage> createState() => _TaskTimerPageState();
}

class _TaskTimerPageState extends State<TaskTimerPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late final initial = widget.repository.active!;
  late final runId = initial.runId;
  late final activity = initial.activity;
  late final runStart = initial.runStartedAt;
  late final AnimationController breathing = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 4),
  );
  Timer? timer;
  List<TaskSession> records = [];
  bool paused = false, busy = false, finished = false, asking = false;
  String? notice;
  Future<void>? saving;
  TaskRepository get repo => widget.repository;
  Duration get elapsed {
    var ms = records
        .where((r) => r.runId == runId && r.id != repo.active?.id)
        .fold<int>(0, (sum, r) => sum + r.elapsed.inMilliseconds);
    ms += repo.active?.checkpoint(repo.now()).elapsed.inMilliseconds ?? 0;
    return Duration(milliseconds: ms);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(initialize());
    var ticks = 0;
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || finished) return;
      setState(() {});
      ticks++;
      if (!busy &&
          !repo.now().toUtc().isBefore(
            runStart.add(const Duration(hours: 6)),
          )) {
        unawaited(finish(capped: true));
      } else if (!paused && ticks % 5 == 0) {
        unawaited(checkpoint());
      }
    });
  }

  Future<void> initialize() async {
    records = await repo.records();
    await showNative();
    if (mounted) setState(() {});
  }

  Future<void> showNative() async {
    final active = repo.active;
    if (active == null) return;
    final allowed = await LockScreenTimer.requestPermission();
    if (!mounted || finished || paused || repo.active?.id != active.id) return;
    if (LockScreenTimer.supported && !allowed) {
      notice = '通知未授权，锁屏计时不显示；本机仍会保存记录。';
    }
    final completed = records
        .where((r) => r.runId == runId && r.id != active.id)
        .fold<Duration>(Duration.zero, (sum, r) => sum + r.elapsed);
    await LockScreenTimer.show(
      active.startedAt,
      sessionId: active.id,
      ownerId: repo.ownerId,
      displayElapsed: completed,
      maximumRemaining: runStart
          .add(const Duration(hours: 6))
          .difference(active.startedAt),
      title: '${activity.label}计时中',
    );
  }

  Future<void> checkpoint({bool stop = false}) async {
    if (saving != null) {
      await saving;
      if (!stop) return;
    }
    final operation = _checkpoint(stop);
    saving = operation;
    try {
      await operation;
    } finally {
      if (identical(saving, operation)) saving = null;
    }
  }

  Future<void> _checkpoint(bool stop) async {
    final before = repo.active?.id;
    try {
      await repo.checkpoint(stop: stop);
      records = await repo.records();
      if (repo.active == null) {
        await LockScreenTimer.stop();
      } else if (repo.active!.id != before) {
        await showNative();
      }
      unawaited(widget.onSync());
    } catch (_) {
      paused = true;
      await LockScreenTimer.stop();
      try {
        await repo.recover(null);
        records = await repo.records();
        notice = '保存失败，计时已停止；最后保存的时长等待核对。';
      } catch (_) {
        notice = '本地保存暂不可用，请重启后核对最后保存的记录。';
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> togglePause() async {
    if (busy || repo.needsRecovery) return;
    setState(() => busy = true);
    try {
      if (paused) {
        if (!repo.now().toUtc().isBefore(
          runStart.add(const Duration(hours: 6)),
        )) {
          busy = false;
          await finish(capped: true);
          return;
        }
        await repo.start(activity, runId: runId);
        records = await repo.records();
        paused = false;
        await showNative();
      } else {
        await checkpoint(stop: true);
        if (!repo.needsRecovery) paused = true;
      }
    } catch (_) {
      notice = '操作未完成，已保存的计时仍保留。';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> askFinish() async {
    if (busy || asking || finished) return;
    asking = true;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('结束本次计时？'),
        content: const Text('保存有效时长并核对奖励，暂停的时间不计入。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续计时'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认结束'),
          ),
        ],
      ),
    );
    asking = false;
    if (yes == true && mounted) await finish();
  }

  Future<void> finish({bool capped = false}) async {
    if (busy || finished || asking) return;
    setState(() => busy = true);
    try {
      await saving;
      if (!repo.needsRecovery) await repo.finishRun(runId);
      await LockScreenTimer.stop();
      if (!mounted) return;
      setState(() => finished = true);
      if (capped || repo.needsRecovery) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              capped ? '已达到本次六小时上限，记录已保存。' : '计时已停止，请在学习记录中核对保存的时长。',
            ),
          ),
        );
      }
      unawaited(widget.onSync());
      Navigator.of(context).pop();
    } catch (_) {
      notice = '保存尚未完成，记录仍保留，请重试。';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive) &&
        !paused &&
        !finished) {
      unawaited(checkpoint());
    }
    if (state == AppLifecycleState.resumed) unawaited(widget.onSync());
  }

  @override
  void dispose() {
    timer?.cancel();
    breathing.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final animate =
        !MediaQuery.disableAnimationsOf(context) && !paused && !finished;
    if (animate && !breathing.isAnimating) breathing.repeat();
    if (!animate && breathing.isAnimating) breathing.stop();
    final value = elapsed;
    final time =
        '${value.inHours.toString().padLeft(2, '0')}:${value.inMinutes.remainder(60).toString().padLeft(2, '0')}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';
    return PopScope(
      canPop: finished,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(askFinish());
      },
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Icon(
                  activity == TaskActivity.language
                      ? Icons.translate_rounded
                      : Icons.directions_run_rounded,
                  color: scheme.primary,
                  size: 24,
                ),
                const SizedBox(height: 12),
                Text(
                  activity.label,
                  style: TextStyle(
                    fontSize: 16,
                    color: scheme.onSurfaceVariant,
                    letterSpacing: 2,
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final ring = (box.maxHeight * .48).clamp(90.0, 220.0);
                      return Center(
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedBuilder(
                                animation: breathing,
                                builder: (_, child) => CustomPaint(
                                  painter: _OrbitPainter(
                                    scheme.primary,
                                    paused ? 0 : breathing.value,
                                  ),
                                  child: child,
                                ),
                                child: SizedBox(
                                  width: ring,
                                  height: ring,
                                  child: Center(
                                    child: Image.asset(
                                      'assets/images/cats/calico-sitting-v1.png',
                                      width: ring * .48,
                                      height: ring * .67,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 20),
                              FittedBox(
                                child: Text(
                                  time,
                                  key: const Key('task-focus-time'),
                                  style: TextStyle(
                                    fontSize: 52,
                                    fontWeight: FontWeight.w300,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                    letterSpacing: 2,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                paused ? '已暂停' : '专注中',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              if (notice != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 14),
                                  child: Text(
                                    notice!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.outlined(
                      tooltip: paused ? '继续计时' : '暂停计时',
                      onPressed: busy || repo.needsRecovery
                          ? null
                          : togglePause,
                      style: IconButton.styleFrom(
                        minimumSize: const Size.square(58),
                      ),
                      icon: Icon(
                        paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      ),
                    ),
                    const SizedBox(width: 32),
                    IconButton.filled(
                      tooltip: '结束计时',
                      onPressed: busy ? null : askFinish,
                      style: IconButton.styleFrom(
                        minimumSize: const Size.square(58),
                      ),
                      icon: const Icon(Icons.stop_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter(this.color, this.phase);
  final Color color;
  final double phase;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2),
        radius = size.width / 2 - 3;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: .18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    canvas.drawCircle(
      center,
      radius - 13,
      Paint()
        ..color = color.withValues(alpha: .07)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    final angle = phase * 2 * math.pi - math.pi / 2;
    canvas.drawCircle(
      center + Offset(math.cos(angle) * radius, math.sin(angle) * radius),
      4,
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_OrbitPainter old) =>
      old.color != color || old.phase != phase;
}
