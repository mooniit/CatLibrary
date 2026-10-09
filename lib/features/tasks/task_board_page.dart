import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/storage/app_database.dart';
import '../identity/identity_repository.dart';
import '../study/lock_screen_timer.dart';
import 'task_repository.dart';
import 'task_session.dart';
import 'task_board_visuals.dart';
import 'task_timer_page.dart';
import 'task_history_page.dart';
import 'weekly_tasks_panel.dart';

class TaskBoardPage extends StatefulWidget {
  const TaskBoardPage({
    super.key,
    required this.ownerId,
    required this.onWallet,
    this.database,
    this.taskCloud,
  });
  final String ownerId;
  final ValueChanged<IdentityWallet> onWallet;
  final AppDatabase? database;
  final TaskCloud? taskCloud;
  @override
  State<TaskBoardPage> createState() => _TaskBoardPageState();
}

class _TaskBoardPageState extends State<TaskBoardPage>
    with WidgetsBindingObserver {
  late final db = widget.database ?? AppDatabase.shared;
  late final repository = TaskRepository(database: db, ownerId: widget.ownerId);
  late final cloud =
      widget.taskCloud ??
      TaskCloud(
        database: db,
        ownerId: widget.ownerId,
        onWallet: widget.onWallet,
      );
  Timer? timer;
  Future<void>? syncing;
  List<TaskSession> records = [];
  List<Map<String, dynamic>> feed = [];
  bool loading = true,
      busy = false,
      checkingCloud = false,
      rewardsLoaded = false,
      feedLoaded = false;
  String? message, syncMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(load());
    timer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(sync()),
    );
  }

  Future<void> load() async {
    try {
      final native = await LockScreenTimer.readCheckpoint();
      final existing = await repository.records();
      if (native != null && existing.any((r) => r.id == native.id)) {
        await LockScreenTimer.stop();
      }
      await repository.recover(native);
      records = await repository.records();
      feed = await db.cachedTaskFeed(widget.ownerId);
      feedLoaded = feed.isNotEmpty;
    } catch (_) {
      message = '本地记录暂时无法读取，请重启后重试。';
    }
    if (!mounted) return;
    setState(() => loading = false);
    if (!repository.needsRecovery) unawaited(sync());
  }

  Future<void> start(TaskActivity activity) async {
    if (busy || loading || repository.needsRecovery) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await repository.start(activity);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TaskTimerPage(repository: repository, onSync: sync),
        ),
      );
      records = await repository.records();
      unawaited(sync());
    } catch (_) {
      message = '计时未能开始，请检查是否已有计时正在运行。';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> sync() => syncing ??= _sync().whenComplete(() => syncing = null);
  Future<void> _sync() async {
    if (loading || repository.needsRecovery) return;
    if (mounted) setState(() => checkingCloud = true);
    try {
      for (final record in await repository.records()) {
        if (record.state != TaskSessionState.synced) await cloud.sync(record);
      }
      await cloud.refresh();
      if (!mounted) return;
      setState(() => rewardsLoaded = true);
      final next = await cloud.feed();
      await db.cacheTaskFeed(widget.ownerId, next);
      if (!mounted) return;
      feed = next;
      feedLoaded = true;
      records = await repository.records();
      if (mounted) setState(() => syncMessage = null);
    } catch (error) {
      if (kDebugMode) debugPrint('Task sync failed: $error');
      if (mounted) setState(() => syncMessage = '本机记录仍保留，联网后自动重试。');
    } finally {
      if (mounted) setState(() => checkingCloud = false);
    }
  }

  int issued(TaskActivity activity) {
    final day = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 8))
        .toIso8601String()
        .substring(0, 10);
    for (final item in cloud.days) {
      if (item['activity'] == activity.name && item['day'] == day) {
        return item['issued'] as int;
      }
    }
    return 0;
  }

  Future<void> history() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TaskHistoryPage(repository: repository, cloud: cloud, onSync: sync),
      ),
    );
    records = await repository.records();
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final scheme = Theme.of(context).colorScheme;
    final waiting = records
        .where(
          (r) =>
              r.state == TaskSessionState.pendingPhoto ||
              r.state == TaskSessionState.ready,
        )
        .length;
    return RefreshIndicator(
      onRefresh: sync,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'TASK JOURNAL',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 3,
                    color: scheme.primary,
                  ),
                ),
              ),
              IconButton(
                tooltip: '学习记录',
                onPressed: history,
                icon: Badge(
                  isLabelVisible: waiting > 0,
                  label: Text('$waiting'),
                  child: const Icon(Icons.calendar_month_outlined),
                ),
              ),
              IconButton(
                tooltip: '核对任务同步',
                onPressed: checkingCloud ? null : sync,
                icon: checkingCloud
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        syncMessage != null
                            ? Icons.cloud_off_outlined
                            : Icons.sync_rounded,
                        size: 20,
                      ),
              ),
            ],
          ),
          const TaskBoardHeading(),
          if (message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(message!),
            ),
          for (final activity in TaskActivity.values)
            TaskActivityCard(
              activity: activity,
              issued: rewardsLoaded ? issued(activity) : null,
              rewardCaption: !rewardsLoaded
                  ? '今日奖励待核对'
                  : '${syncMessage == null ? '今日' : '上次核对'} ${issued(activity)}/12 ${activity.rewardLabel}',
              onStart: !busy && !repository.needsRecovery
                  ? () => start(activity)
                  : null,
            ),
          const SizedBox(height: 16),
          InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('本周特别任务')),
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: WeeklyTasksPanel(
                      ownerId: widget.ownerId,
                      onWallet: widget.onWallet,
                      database: db,
                    ),
                  ),
                ),
              ),
            ),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Row(
                children: [
                  Icon(Icons.auto_stories_outlined, color: scheme.primary),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text('本周特别任务', style: TextStyle(fontSize: 17)),
                  ),
                  const Icon(Icons.arrow_forward_rounded, size: 20),
                ],
              ),
            ),
          ),
          Divider(color: scheme.outlineVariant),
          Row(
            children: [
              Expanded(
                child: Text(
                  checkingCloud
                      ? '正在核对任务'
                      : syncMessage != null
                      ? '等待同步'
                      : rewardsLoaded && feedLoaded
                      ? '已核对任务'
                      : '等待核对',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                tooltip: '奖励规则',
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(
                    title: Text('常规任务奖励'),
                    content: Text(
                      '每天同类累计满 10 分钟起奖，每满 5 分钟获得 1 枚奖励，各类每日最多 12 枚。暂停不计时；结束确认后自动保存，联网核对后入账。',
                    ),
                  ),
                ),
                icon: Icon(
                  Icons.info_outline_rounded,
                  size: 17,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
