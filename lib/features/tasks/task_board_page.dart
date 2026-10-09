import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/storage/app_database.dart';
import '../identity/identity_repository.dart';
import '../study/lock_screen_timer.dart';
import 'task_repository.dart';
import 'task_session.dart';
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
  late final AppDatabase db = widget.database ?? AppDatabase.shared;
  late final TaskRepository repository = TaskRepository(
    database: db,
    ownerId: widget.ownerId,
  );
  late final TaskCloud cloud =
      widget.taskCloud ??
      TaskCloud(
        database: db,
        ownerId: widget.ownerId,
        onWallet: widget.onWallet,
      );
  final picker = ImagePicker();
  Timer? timer;
  Future<void>? syncing;
  Future<void>? saving;
  List<TaskSession> records = [];
  List<Map<String, dynamic>> feed = [];
  bool loading = true, busy = false;
  String? message;
  String? syncMessage;
  bool checkingCloud = false, rewardsLoaded = false, feedLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(load());
    var seconds = 0;
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || loading) return;
      setState(() {});
      seconds++;
      final active = repository.active;
      if (active != null &&
          DateTime.now().toUtc().difference(active.startedAt) >=
              const Duration(hours: 6)) {
        unawaited(save(stop: true));
      } else if (active != null && seconds % 5 == 0) {
        unawaited(save());
      }
      if (seconds % 15 == 0) unawaited(sync());
    });
  }

  Future<void> load() async {
    try {
      final native = await LockScreenTimer.readCheckpoint();
      final existing = await repository.records();
      if (native != null && existing.any((record) => record.id == native.id)) {
        await LockScreenTimer.stop();
      }
      await repository.recover(native);
      records = await repository.records();
      final lost = await picker.retrieveLostData();
      if (!lost.isEmpty) {
        message = '上次选择照片时应用被中断，请为对应任务重新选择照片。';
      }
    } catch (_) {
      message = '本地任务记录暂时无法读取，请重启应用后重试。';
    }
    if (!mounted) return;
    setState(() => loading = false);
    if (!repository.needsRecovery) unawaited(sync());
  }

  Future<void> act(Future<void> Function() action) async {
    if (busy || loading) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
      records = await repository.records();
    } catch (error) {
      message = error is ArgumentError
          ? '请选择不超过 5 MB 的 JPEG 或 PNG 照片。'
          : '操作未完成，原记录仍保留，请重试。';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> start(TaskActivity activity) => act(() async {
    await repository.start(activity);
    records = await repository.records();
    final active = repository.active!;
    final allowed = await LockScreenTimer.requestPermission();
    if (LockScreenTimer.supported && !allowed) {
      message = '通知未授权，锁屏计时不显示；本机仍会保存记录。';
    }
    await LockScreenTimer.show(
      active.startedAt,
      sessionId: active.id,
      ownerId: widget.ownerId,
      maximumRemaining: const Duration(hours: 6),
      title: '${activity.label}计时中',
    );
  });

  Future<void> save({bool stop = false}) async {
    if (saving != null) {
      if (!stop) return saving;
      await saving;
    }
    final operation = _save(stop);
    saving = operation;
    try {
      await operation;
    } finally {
      if (identical(saving, operation)) saving = null;
    }
  }

  Future<void> _save(bool stop) async {
    try {
      await repository.checkpoint(stop: stop);
      records = await repository.records();
      if (repository.active == null) await LockScreenTimer.stop();
      if (mounted) setState(() {});
      unawaited(sync());
    } catch (_) {
      await LockScreenTimer.stop();
      if (mounted) setState(() => message = '保存失败，计时已停止；请核对最后保存的记录。');
    }
  }

  Future<void> stop() async {
    final active = repository.active;
    if (active == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('结束任务计时？'),
        content: Text(
          '已计时 ${_duration(active.checkpoint(DateTime.now()).elapsed)}。结束后选择照片并自行确认完成。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('继续计时'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('结束'),
          ),
        ],
      ),
    );
    if (confirmed == true) await save(stop: true);
  }

  Future<void> choosePhoto(TaskSession record) => act(() async {
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null) return;
    await repository.attachPhoto(record.id, await file.readAsBytes());
  });

  Future<void> confirm(TaskSession record) => act(() async {
    await repository.confirm(record.id);
    await sync();
  });

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
      final nextFeed = await cloud.feed();
      if (!mounted) return;
      feed = nextFeed;
      feedLoaded = true;
      records = await repository.records();
      if (mounted) setState(() => syncMessage = null);
    } catch (error) {
      if (kDebugMode) debugPrint('Task sync failed: $error');
      if (mounted) {
        setState(() => syncMessage = '本机记录与照片仍保留，联网后自动重试。');
      }
    } finally {
      if (mounted) setState(() => checkingCloud = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      if (repository.active != null) unawaited(save());
    } else if (state == AppLifecycleState.resumed) {
      unawaited(sync());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    super.dispose();
  }

  static String _duration(Duration value) {
    final seconds = value.inSeconds;
    final h = (seconds ~/ 3600).toString().padLeft(2, '0');
    final m = ((seconds ~/ 60) % 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
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

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final active = repository.active;
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: sync,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Text('常规任务', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            '计时、上传照片，再确认完成',
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: scheme.surfaceContainerLow,
            child: ListTile(
              leading: Icon(
                syncMessage != null
                    ? Icons.cloud_off_outlined
                    : !rewardsLoaded || !feedLoaded
                    ? Icons.sync_rounded
                    : Icons.cloud_done_outlined,
                color: scheme.onSurfaceVariant,
              ),
              title: Text(
                checkingCloud
                    ? '正在核对任务'
                    : syncMessage != null
                    ? '等待同步'
                    : rewardsLoaded && feedLoaded
                    ? '已核对任务'
                    : '等待核对',
              ),
              subtitle: syncMessage == null ? null : Text(syncMessage!),
              trailing: IconButton(
                tooltip: '核对任务同步',
                onPressed: checkingCloud ? null : sync,
                icon: checkingCloud
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
              ),
            ),
          ),
          if (message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(message!),
            ),
          for (final activity in TaskActivity.values)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: active?.activity == activity
                      ? scheme.primary
                      : scheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          activity == TaskActivity.language
                              ? Icons.translate_rounded
                              : Icons.directions_run_rounded,
                          size: 30,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            activity.label,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (active?.activity == activity)
                          Text(
                            _duration(
                              active!.checkpoint(DateTime.now()).elapsed,
                            ),
                            style: Theme.of(context).textTheme.titleMedium,
                          )
                        else
                          FilledButton.tonal(
                            onPressed:
                                active == null &&
                                    !busy &&
                                    !repository.needsRecovery
                                ? () => start(activity)
                                : null,
                            child: const Text('开始'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    LinearProgressIndicator(
                      value: (issued(activity) / 12).clamp(0, 1),
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(3),
                      backgroundColor: scheme.outlineVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      !rewardsLoaded
                          ? '今日奖励待核对'
                          : '${syncMessage == null ? '今日' : '上次核对'} ${issued(activity)}/12 ${activity.rewardLabel}',
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              '当天同类累计满 10 分钟起奖，每满 5 分钟获得 1 枚奖励。',
              style: TextStyle(
                fontSize: 12,
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
          ),
          if (active != null)
            FilledButton.icon(
              onPressed: busy ? null : stop,
              icon: const Icon(Icons.stop_circle_outlined),
              label: const Text('结束计时'),
            ),
          if (records.any(
            (r) =>
                r.state == TaskSessionState.pendingPhoto ||
                r.state == TaskSessionState.ready,
          )) ...[
            const SizedBox(height: 16),
            Text('待完成', style: Theme.of(context).textTheme.titleLarge),
            for (final record in records.reversed.where(
              (r) =>
                  r.state == TaskSessionState.pendingPhoto ||
                  r.state == TaskSessionState.ready,
            ))
              Card(
                child: ListTile(
                  title: Text(
                    '${record.activity.label} · ${_duration(record.elapsed)}',
                  ),
                  subtitle: Text(
                    record.state == TaskSessionState.ready
                        ? '已确认，等待云端照片与奖励核对'
                        : record.photoBytes == null
                        ? '待选择照片并确认'
                        : '照片已保存，待自行确认',
                  ),
                  trailing: record.state == TaskSessionState.ready
                      ? IconButton(
                          onPressed: sync,
                          icon: const Icon(Icons.sync),
                          tooltip: '重试同步',
                        )
                      : Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              onPressed: busy
                                  ? null
                                  : () => choosePhoto(record),
                              icon: const Icon(
                                Icons.add_photo_alternate_outlined,
                              ),
                              tooltip: '选择照片',
                            ),
                            IconButton(
                              onPressed: busy || record.photoBytes == null
                                  ? null
                                  : () => confirm(record),
                              icon: const Icon(Icons.check_circle_outline),
                              tooltip: '确认完成',
                            ),
                          ],
                        ),
                ),
              ),
          ],
          const SizedBox(height: 16),
          Text('完成记录', style: Theme.of(context).textTheme.titleLarge),
          if (feed.isEmpty)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              leading: Icon(
                Icons.photo_library_outlined,
                color: scheme.outline,
              ),
              title: Text(feedLoaded ? '暂无已确认任务' : '完成记录待核对'),
              subtitle: Text(feedLoaded ? '完成后的照片会留在这里' : '联网核对后显示家庭完成记录'),
            ),
          for (final item in feed)
            ListTile(
              title: Text(
                (item['activity'] == 'language'
                        ? TaskActivity.language
                        : TaskActivity.exercise)
                    .label,
              ),
              subtitle: Text(
                '${(item['started_at'] as String).substring(0, 10)} · ${item['owner_id'] == widget.ownerId ? '我' : '家庭成员'}',
              ),
              trailing: const Icon(Icons.photo_outlined),
              onTap: () async {
                try {
                  final bytes = await cloud.photo(item['photo_path'] as String);
                  if (!context.mounted) return;
                  await showDialog<void>(
                    context: context,
                    builder: (_) => Dialog(
                      child: InteractiveViewer(
                        child: Image.memory(bytes, fit: BoxFit.contain),
                      ),
                    ),
                  );
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('照片暂时无法加载，请联网后重试。')),
                    );
                  }
                }
              },
            ),
          const Divider(height: 32),
          WeeklyTasksPanel(
            ownerId: widget.ownerId,
            onWallet: widget.onWallet,
            database: db,
          ),
        ],
      ),
    );
  }
}
