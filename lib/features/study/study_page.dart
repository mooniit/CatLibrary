import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../core/storage/app_database.dart';
import '../../core/sync/sync_worker.dart';
import '../../core/time/business_day.dart';
import '../identity/identity_repository.dart';
import 'lock_screen_timer.dart';
import 'study_cloud.dart';
import 'study_history_page.dart';
import 'study_repository.dart';
import 'study_session.dart';

enum StudyTimerMode { stopwatch, countdown }

class StudyPage extends StatefulWidget {
  const StudyPage({
    super.key,
    required this.ownerId,
    required this.onWallet,
    this.onFocusChanged,
    this.databaseFactory,
    this.now,
    this.exchange,
  });
  final String ownerId;
  final ValueChanged<IdentityWallet> onWallet;
  final ValueChanged<bool>? onFocusChanged;
  final AppDatabase Function()? databaseFactory;
  final DateTime Function()? now;
  final Future<StudySnapshot> Function(StudySession? session)? exchange;
  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> with WidgetsBindingObserver {
  late final AppDatabase db;
  late final StudyRepository repository;
  late final StudyCloud cloud;
  late final StudySyncWorker worker;
  late final FixedExtentScrollController hoursWheel;
  late final FixedExtentScrollController minutesWheel;
  late final FixedExtentScrollController secondsWheel;
  Timer? timer;
  List<StudySession> records = [];
  List<StudyPreset> presets = [];
  StudySnapshot? snapshot;
  bool loading = true, busy = false, focus = false, paused = false;
  String? error, syncMessage, notice, runId;
  Future<bool>? saving;
  Future<void>? syncing;
  final sent = <String, String>{};
  StudyTimerMode selectedMode = StudyTimerMode.stopwatch;
  StudyTimerMode runningMode = StudyTimerMode.stopwatch;
  Duration? target;
  int hours = 0, minutes = 40, seconds = 0;
  DateTime get now => (widget.now ?? DateTime.now)();
  Duration get selectedDuration =>
      Duration(hours: hours, minutes: minutes, seconds: seconds);
  String get businessDay => now
      .toUtc()
      .add(const Duration(hours: 8))
      .toIso8601String()
      .substring(0, 10);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    hoursWheel = FixedExtentScrollController(initialItem: hours);
    minutesWheel = FixedExtentScrollController(initialItem: minutes);
    secondsWheel = FixedExtentScrollController(initialItem: seconds);
    db = widget.databaseFactory?.call() ?? AppDatabase.shared;
    repository = StudyRepository(
      database: db,
      ownerId: widget.ownerId,
      now: () => now,
    );
    cloud = StudyCloud(
      database: db,
      ownerId: widget.ownerId,
      onSnapshot: applySnapshot,
    );
    worker = StudySyncWorker(
      database: db,
      ownerId: widget.ownerId,
      submit: (session) async {
        await send(session);
      },
    );
    unawaited(load());
    var ticks = 0;
    var previousDay = businessDay;
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || loading) return;
      setState(() {});
      ticks++;
      final currentDay = businessDay;
      if (currentDay != previousDay) {
        previousDay = currentDay;
        if (repository.active != null) unawaited(save());
        unawaited(sync());
      }
      unawaited(checkCompletion());
      if (repository.active != null && ticks % 5 == 0) unawaited(save());
      // Retry queued offline work, including when there is no active timer.
      if (ticks % 15 == 0) unawaited(sync());
    });
  }

  void applySnapshot(StudySnapshot value) {
    if (!mounted) return;
    setState(() => snapshot = value);
    widget.onWallet(value.wallet);
  }

  Future<void> send(StudySession? session) async {
    if (widget.exchange != null) {
      applySnapshot(await widget.exchange!(session));
    } else if (session == null) {
      await cloud.refresh();
    } else {
      await cloud.submit(session);
    }
  }

  Future<void> load() async {
    try {
      final durable = await LockScreenTimer.readCheckpoint();
      final existing = await repository.records();
      final interrupted = existing.any(
        (r) => r.state == StudySessionState.running,
      );
      if (durable != null && existing.any((r) => r.id == durable.id)) {
        await LockScreenTimer.stop();
      }
      await repository.recover(durableNative: durable);
      records = await repository.records();
      presets = await db.presets(widget.ownerId);
      if (interrupted) notice = '上次计时已恢复到最后可靠的位置，请在自习记录中核对。';
      final cached = await db.accountSnapshot(widget.ownerId);
      if (cached != null) snapshot = StudySnapshot.fromJson(cached);
      error = null;
    } catch (_) {
      error = '本地记录暂时无法读取，请重试；不会补算未保存的时间。';
    }
    if (mounted) {
      setState(() => loading = false);
      if (!repository.needsRecovery) unawaited(sync());
    }
  }

  Future<void> sync() =>
      syncing ??= syncRecords().whenComplete(() => syncing = null);
  Future<void> syncRecords() async {
    if (loading || repository.needsRecovery) return;
    try {
      await worker.sync();
      for (final session in await repository.records()) {
        if (session.state == StudySessionState.synced ||
            session.state == StudySessionState.queued) {
          continue;
        }
        final signature = session.recordedUntil.toIso8601String();
        if (sent[session.id] == signature) continue;
        await send(session);
        sent[session.id] = signature;
      }
      await send(null);
      records = await repository.records();
      if (mounted) setState(() => syncMessage = '已与云端核对');
    } catch (_) {
      if (mounted) setState(() => syncMessage = '尚未同步成功，记录已保存在本机，将自动重试。');
    }
  }

  Future<bool> save({bool stop = false, DateTime? at}) async {
    // A stop must wait for the current write, not get discarded by a busy tick.
    final previous = saving;
    if (previous != null) {
      if (!stop) return previous;
      await previous;
    }
    final operation = persist(stop, at);
    saving = operation;
    try {
      return await operation;
    } finally {
      if (identical(saving, operation)) saving = null;
    }
  }

  Future<bool> persist(bool stop, DateTime? at) async {
    try {
      final wasRunning = repository.active != null;
      await repository.checkpoint(stop: stop, at: at);
      records = await repository.records();
      if (wasRunning && repository.active == null) {
        await LockScreenTimer.stop();
      }
      if (mounted) {
        setState(() {});
        if (!stop) unawaited(sync());
      }
      return true;
    } catch (_) {
      await LockScreenTimer.stop();
      if (mounted) {
        setFocus(false);
        setState(() => error = '保存失败，计时已停止。请恢复最后保存的记录。');
      }
      return false;
    }
  }

  Future<void> act(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
      records = await repository.records();
    } catch (_) {
      error = '操作未完成，原记录仍保留，请重试。';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void setFocus(bool value) {
    if (focus == value) return;
    setState(() => focus = value);
    widget.onFocusChanged?.call(value);
  }

  Duration get runElapsed {
    final id = runId;
    if (id == null) return Duration.zero;
    var milliseconds = 0;
    for (final saved in records.where((record) => record.runId == id)) {
      final record = repository.active?.id == saved.id
          ? repository.active!.checkpoint(now)
          : saved;
      milliseconds += record.elapsed.inMilliseconds;
    }
    return Duration(milliseconds: milliseconds);
  }

  Duration get completedRunElapsed => Duration(
    milliseconds: records
        .where(
          (record) =>
              record.runId == runId && record.id != repository.active?.id,
        )
        .fold<int>(0, (sum, record) => sum + record.elapsed.inMilliseconds),
  );

  Future<void> showNativeTimer() async {
    final active = repository.active;
    if (active == null) return;
    final allowed = await LockScreenTimer.requestPermission();
    if (LockScreenTimer.supported && !allowed) {
      notice = '通知未授权，锁屏计时显示不可用；本机仍会保存记录。';
    }
    await LockScreenTimer.show(
      active.startedAt,
      sessionId: active.id,
      ownerId: widget.ownerId,
      displayElapsed: completedRunElapsed,
      countdownRemaining: target == null ? null : target! - completedRunElapsed,
      maximumRemaining: StudySession.maximumDuration - completedRunElapsed,
    );
  }

  Future<void> start() => act(() async {
    if (selectedMode == StudyTimerMode.countdown &&
        selectedDuration == Duration.zero) {
      throw StateError('Choose a countdown duration');
    }
    await repository.start();
    records = await repository.records();
    runId = repository.active!.runId;
    runningMode = selectedMode;
    target = selectedMode == StudyTimerMode.countdown ? selectedDuration : null;
    paused = false;
    notice = null;
    setFocus(true);
    await showNativeTimer();
  });

  Future<void> pause() => act(() async {
    if (!await save(stop: true)) return;
    paused = true;
  });

  Future<void> resume() async {
    if (runElapsed >= StudySession.maximumDuration) {
      await finish(capped: true);
      return;
    }
    await act(() async {
      if (runId == null) return;
      await repository.start(runId: runId);
      records = await repository.records();
      paused = false;
      await showNativeTimer();
    });
  }

  Future<void> checkCompletion() async {
    if (!focus || paused || busy || runId == null || repository.needsRecovery) {
      return;
    }
    final active = repository.active;
    if (active == null) {
      await finish(capped: true);
      return;
    }
    if (runElapsed >= StudySession.maximumDuration) {
      await finish(
        at: active.startedAt.add(
          StudySession.maximumDuration - completedRunElapsed,
        ),
        capped: true,
      );
    } else if (runningMode == StudyTimerMode.countdown &&
        target != null &&
        runElapsed >= target!) {
      await finish(at: active.startedAt.add(target! - completedRunElapsed));
    }
  }

  Future<void> finish({DateTime? at, bool capped = false}) => act(() async {
    if (runId == null) return;
    if (repository.active != null && !await save(stop: true, at: at)) return;
    if (repository.needsRecovery) return;
    final endingRun = runId!;
    for (final record in await repository.records()) {
      if (record.runId == endingRun &&
          record.state == StudySessionState.pendingConfirmation) {
        await repository.confirm(record.id);
      }
    }
    paused = false;
    runId = null;
    target = null;
    if (capped) notice = '已达到单次最长计时，请休息一下吧。';
    setFocus(false);
    unawaited(sync());
  });

  Future<void> askToFinish() async {
    final shouldEnd = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('结束本次自习？'),
        content: const Text('将保存已计入的时长并自动结算。暂停的时间不计入。'),
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
    if (shouldEnd == true && mounted) await finish();
  }

  void choosePreset(StudyPreset preset) {
    final duration = Duration(seconds: preset.seconds);
    setState(() {
      hours = duration.inHours;
      minutes = duration.inMinutes.remainder(60);
      seconds = duration.inSeconds.remainder(60);
    });
    hoursWheel.jumpToItem(hours);
    minutesWheel.jumpToItem(minutes);
    secondsWheel.jumpToItem(seconds);
  }

  Future<void> addPreset() async {
    final choice = await Navigator.of(context)
        .push<({String name, int seconds})>(
          MaterialPageRoute(
            builder: (_) =>
                StudyPresetCreatePage(initialDuration: selectedDuration),
          ),
        );
    if (choice == null || !mounted) return;
    await act(() async {
      await db.addPreset(widget.ownerId, choice.seconds, choice.name);
      presets = await db.presets(widget.ownerId);
    });
  }

  Future<void> openEdit() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            StudyPresetEditPage(database: db, ownerId: widget.ownerId),
      ),
    );
    presets = await db.presets(widget.ownerId);
    if (mounted) setState(() {});
  }

  Future<void> openHistory() async {
    records = await repository.records();
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => StudyHistoryPage(
          records: records,
          onConfirmRecovered: (record) async {
            await repository.confirm(record.id);
            await sync();
            records = await repository.records();
          },
        ),
      ),
    );
    records = await repository.records();
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (loading) return;
    if (repository.active != null) unawaited(save());
    if (state == AppLifecycleState.resumed) {
      unawaited(checkCompletion());
      unawaited(sync());
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    hoursWheel.dispose();
    minutesWheel.dispose();
    secondsWheel.dispose();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(closeDatabase());
    super.dispose();
  }

  Future<void> closeDatabase() async {
    await saving;
    await syncing;
    if (widget.databaseFactory != null) await db.close();
  }

  int dayMilliseconds(String day) {
    final live = repository.active?.checkpoint(now);
    var total = 0;
    for (final saved in records) {
      final record = live?.id == saved.id ? live! : saved;
      total +=
          millisecondsByBusinessDay(
            record.startedAt,
            record.recordedUntil,
          )[day] ??
          0;
    }
    return math.max(
      total,
      (snapshot?.days[day]?['eligible_ms'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return focus ? buildFocus(context) : buildSetup(context);
  }

  Widget buildSetup(BuildContext context) {
    final day = businessDay;
    final issued = (snapshot?.days[day]?['issued'] as num?)?.toInt() ?? 0;
    final scheme = Theme.of(context).colorScheme;
    final minutesToday = dayMilliseconds(day) ~/ 60000;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        children: [
          Row(
            children: [
              const Spacer(),
              PopupMenuButton<String>(
                key: const Key('study-more'),
                tooltip: '更多',
                icon: const Icon(Icons.more_horiz),
                onSelected: (value) {
                  if (value == 'edit') unawaited(openEdit());
                  if (value == 'history') unawaited(openHistory());
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('编辑常用计时器')),
                  PopupMenuItem(value: 'history', child: Text('查看自习记录')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          SegmentedButton<StudyTimerMode>(
            showSelectedIcon: false,
            style: const ButtonStyle(
              fixedSize: WidgetStatePropertyAll(Size(112, 40)),
              visualDensity: VisualDensity.standard,
            ),
            segments: const [
              ButtonSegment(value: StudyTimerMode.stopwatch, label: Text('计时')),
              ButtonSegment(
                value: StudyTimerMode.countdown,
                label: Text('倒计时'),
              ),
            ],
            selected: {selectedMode},
            onSelectionChanged: (selection) =>
                setState(() => selectedMode = selection.first),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: selectedMode == StudyTimerMode.stopwatch
                ? Center(child: startButton(label: '开始'))
                : buildCountdownSetup(context),
          ),
          if (notice != null) Text(notice!, textAlign: TextAlign.center),
          if (error != null)
            Text(
              error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.error),
            ),
          if (repository.needsRecovery)
            TextButton(
              onPressed: busy ? null : () => act(load),
              child: const Text('恢复已保存记录'),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.38),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '今日自习',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const Spacer(),
                    Text(
                      '${math.min(minutesToday, 60)}/60 分钟',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (dayMilliseconds(day) / 3600000).clamp(0, 1),
                    minHeight: 6,
                    backgroundColor: scheme.primary.withValues(alpha: 0.12),
                    semanticsLabel: '今日自习累计进度，60分钟达到奖励上限',
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  snapshot == null
                      ? '今日可得喵喵币核对中'
                      : '今日还可获得 ${math.max(0, 120 - issued)} 喵喵币',
                  key: const Key('study-remaining-coins'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (syncMessage != null && syncMessage != '已与云端核对')
            Text(syncMessage!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  Widget buildCountdownSetup(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wheelHeight = (constraints.maxHeight / 3).clamp(144.0, 252.0);
      return Column(
        children: [
          SizedBox(
            height: wheelHeight,
            child: StudyDurationWheels(
              hoursWheel: hoursWheel,
              minutesWheel: minutesWheel,
              secondsWheel: secondsWheel,
              hours: hours,
              minutes: minutes,
              seconds: seconds,
              onHours: (value) => setState(() => hours = value),
              onMinutes: (value) => setState(() => minutes = value),
              onSeconds: (value) => setState(() => seconds = value),
            ),
          ),
          Row(
            children: [
              Text('常用计时器', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              TextButton(
                onPressed: busy ? null : addPreset,
                child: const Text('添加'),
              ),
            ],
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: presets.isEmpty
                      ? const Center(child: Text('还没有常用计时器'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(0, 4, 0, 76),
                          itemCount: presets.length,
                          itemBuilder: (context, index) {
                            final preset = presets[index];
                            final selected =
                                preset.seconds == selectedDuration.inSeconds;
                            return Card(
                              elevation: 0,
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerLow,
                              margin: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: selected
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.transparent,
                                ),
                              ),
                              child: ListTile(
                                minTileHeight: 64,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                title: Text(
                                  preset.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 18),
                                ),
                                trailing: Text(
                                  formatStudySeconds(preset.seconds),
                                  style: const TextStyle(fontSize: 20),
                                ),
                                onTap: () => choosePreset(preset),
                              ),
                            );
                          },
                        ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: startButton(label: '开始倒计时', iconOnly: true),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget startButton({required String label, bool iconOnly = false}) =>
      Semantics(
        button: true,
        label: label,
        child: SizedBox(
          height: iconOnly ? 60 : 150,
          width: iconOnly ? 60 : 150,
          child: OutlinedButton(
            key: const Key('study-start'),
            onPressed: busy || repository.needsRecovery ? null : start,
            style: OutlinedButton.styleFrom(
              shape: const CircleBorder(),
              padding: iconOnly ? EdgeInsets.zero : null,
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
              backgroundColor: iconOnly
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            child: iconOnly
                ? Icon(
                    Icons.play_arrow,
                    color: Theme.of(context).colorScheme.onPrimary,
                    size: 38,
                  )
                : Text(label, style: Theme.of(context).textTheme.titleLarge),
          ),
        ),
      );

  Widget buildFocus(BuildContext context) {
    final elapsed = runElapsed;
    final countdown = runningMode == StudyTimerMode.countdown;
    final remaining = countdown && target! > elapsed
        ? target! - elapsed
        : Duration.zero;
    final secondsShown = countdown
        ? (remaining.inMilliseconds / 1000).ceil()
        : elapsed.inSeconds;
    final timeText = Text(
      formatStudySeconds(secondsShown),
      key: const Key('study-running-time'),
      style: Theme.of(context).textTheme.displayLarge?.copyWith(
        fontFeatures: [const FontFeature.tabularFigures()],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: countdown
                  ? SizedBox(
                      width: 270,
                      height: 270,
                      child: CustomPaint(
                        painter: _RemainingRing(
                          fraction: target!.inMilliseconds == 0
                              ? 0
                              : (remaining.inMilliseconds /
                                        target!.inMilliseconds)
                                    .clamp(0, 1),
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        child: Center(child: timeText),
                      ),
                    )
                  : timeText,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              timerAction(
                key: const Key('study-pause-resume'),
                icon: paused ? Icons.play_arrow : Icons.pause,
                label: paused ? '继续' : '暂停',
                onPressed: busy
                    ? null
                    : paused
                    ? resume
                    : pause,
              ),
              const SizedBox(width: 42),
              timerAction(
                key: const Key('study-stop'),
                icon: Icons.stop,
                label: '结束',
                onPressed: busy ? null : askToFinish,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget timerAction({
    required Key key,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
  }) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      IconButton.outlined(
        key: key,
        icon: Icon(icon),
        tooltip: label,
        iconSize: 30,
        onPressed: onPressed,
      ),
      const SizedBox(height: 4),
      Text(label),
    ],
  );
}

class StudyDurationWheels extends StatelessWidget {
  const StudyDurationWheels({
    super.key,
    required this.hoursWheel,
    required this.minutesWheel,
    required this.secondsWheel,
    required this.hours,
    required this.minutes,
    required this.seconds,
    required this.onHours,
    required this.onMinutes,
    required this.onSeconds,
  });

  final FixedExtentScrollController hoursWheel;
  final FixedExtentScrollController minutesWheel;
  final FixedExtentScrollController secondsWheel;
  final int hours, minutes, seconds;
  final ValueChanged<int> onHours, onMinutes, onSeconds;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const itemExtent = 80.0;
      final digitSize = (constraints.maxWidth / 7.5).clamp(34.0, 48.0);

      Widget picker({
        required Key key,
        required String label,
        required int count,
        required int selected,
        required FixedExtentScrollController controller,
        required ValueChanged<int> onChange,
      }) => Expanded(
        child: Semantics(
          label: label,
          value: selected.toString().padLeft(2, '0'),
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Color(0xe6000000),
                Colors.black,
                Colors.black,
                Color(0xe6000000),
                Colors.transparent,
              ],
              stops: [0, 0.18, 0.4, 0.6, 0.82, 1],
            ).createShader(bounds),
            child: CupertinoPicker(
              key: key,
              scrollController: controller,
              looping: true,
              itemExtent: itemExtent,
              diameterRatio: 8,
              selectionOverlay: null,
              onSelectedItemChanged: onChange,
              children: List.generate(
                count,
                (index) => Center(
                  child: Text(
                    index.toString().padLeft(2, '0'),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: digitSize,
                      color: index == selected
                          ? Theme.of(context).brightness == Brightness.dark
                                ? const Color(0xfff1f3f7)
                                : Colors.black
                          : Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xffa8afbd)
                          : const Color(0xffb9c0cb),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      return Row(
        children: [
          picker(
            key: const Key('study-hours-wheel'),
            label: '小时',
            count: 6,
            selected: hours,
            controller: hoursWheel,
            onChange: onHours,
          ),
          Text(':', style: TextStyle(fontSize: digitSize * 0.78)),
          picker(
            key: const Key('study-minutes-wheel'),
            label: '分钟',
            count: 60,
            selected: minutes,
            controller: minutesWheel,
            onChange: onMinutes,
          ),
          Text(':', style: TextStyle(fontSize: digitSize * 0.78)),
          picker(
            key: const Key('study-seconds-wheel'),
            label: '秒',
            count: 60,
            selected: seconds,
            controller: secondsWheel,
            onChange: onSeconds,
          ),
        ],
      );
    },
  );
}

class StudyPresetCreatePage extends StatefulWidget {
  const StudyPresetCreatePage({super.key, required this.initialDuration});
  final Duration initialDuration;

  @override
  State<StudyPresetCreatePage> createState() => _StudyPresetCreatePageState();
}

class _StudyPresetCreatePageState extends State<StudyPresetCreatePage> {
  late int hours = widget.initialDuration.inHours;
  late int minutes = widget.initialDuration.inMinutes.remainder(60);
  late int seconds = widget.initialDuration.inSeconds.remainder(60);
  late final hoursWheel = FixedExtentScrollController(initialItem: hours);
  late final minutesWheel = FixedExtentScrollController(initialItem: minutes);
  late final secondsWheel = FixedExtentScrollController(initialItem: seconds);
  String name = '';

  @override
  void dispose() {
    hoursWheel.dispose();
    minutesWheel.dispose();
    secondsWheel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('添加常用计时器')),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SizedBox(
              height: (constraints.maxHeight / 3).clamp(144.0, 252.0),
              child: StudyDurationWheels(
                hoursWheel: hoursWheel,
                minutesWheel: minutesWheel,
                secondsWheel: secondsWheel,
                hours: hours,
                minutes: minutes,
                seconds: seconds,
                onHours: (value) => setState(() => hours = value),
                onMinutes: (value) => setState(() => minutes = value),
                onSeconds: (value) => setState(() => seconds = value),
              ),
            ),
            const SizedBox(height: 32),
            TextField(
              maxLength: 24,
              onChanged: (value) => setState(() => name = value.trim()),
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '例如：阅读',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed:
                  name.isEmpty || (hours == 0 && minutes == 0 && seconds == 0)
                  ? null
                  : () => Navigator.pop(context, (
                      name: name,
                      seconds: hours * 3600 + minutes * 60 + seconds,
                    )),
              child: const Text('保存常用计时器'),
            ),
          ],
        ),
      ),
    ),
  );
}

String formatStudySeconds(int value) {
  final seconds = value.clamp(0, 21600);
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainder = seconds % 60;
  return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${remainder.toString().padLeft(2, '0')}';
}

class _RemainingRing extends CustomPainter {
  const _RemainingRing({required this.fraction, required this.color});
  final double fraction;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final circle = (Offset.zero & size).deflate(8);
    final background = Paint()
      ..color = color.withValues(alpha: 0.14)
      ..strokeWidth = 9
      ..style = PaintingStyle.stroke;
    final foreground = Paint()
      ..color = color
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawArc(circle, 0, math.pi * 2, false, background);
    canvas.drawArc(
      circle,
      -math.pi / 2,
      math.pi * 2 * fraction,
      false,
      foreground,
    );
  }

  @override
  bool shouldRepaint(_RemainingRing old) =>
      fraction != old.fraction || color != old.color;
}
