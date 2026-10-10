import 'dart:async';
import 'package:flutter/material.dart';
import 'task_repository.dart';
import 'task_session.dart';
import '../study/study_session.dart';
import '../study/study_cloud.dart';
import '../identity/identity_repository.dart';

String taskDay(DateTime utc) => utc
    .toUtc()
    .add(const Duration(hours: 8))
    .toIso8601String()
    .substring(0, 10);

/// Merge by server session id, then split actual intervals at UTC+8 midnight.
Map<String, Duration> taskHeatmap(
  String ownerId,
  List<TaskSession> local,
  List<Map<String, dynamic>> feed, {
  List<StudySession> studyLocal = const [],
  List<Map<String, dynamic>> studyFeed = const [],
}) {
  final intervals = <String, (DateTime, DateTime)>{};
  for (final row in local) {
    if (row.ownerId == ownerId && row.state == TaskSessionState.synced) {
      intervals[row.id] = (row.startedAt, row.recordedUntil);
    }
  }
  for (final row in feed) {
    if (row['owner_id'] != ownerId || row['id'] is! String) continue;
    final a = DateTime.tryParse(row['started_at'] as String? ?? ''),
        b = DateTime.tryParse(row['recorded_until'] as String? ?? '');
    if (a != null &&
        b != null &&
        !b.isBefore(a) &&
        b.difference(a) <= const Duration(hours: 6)) {
      intervals[row['id'] as String] = (a.toUtc(), b.toUtc());
    }
  }
  final days = <String, Duration>{};
  for (final row in studyLocal) {
    if (row.ownerId == ownerId &&
        [
          StudySessionState.queued,
          StudySessionState.synced,
        ].contains(row.state)) {
      intervals['study/${row.id}'] = (row.startedAt, row.recordedUntil);
    }
  }
  for (final row in studyFeed) {
    if (row['owner_id'] != ownerId || row['confirmed'] != true) continue;
    final a = DateTime.tryParse(row['started_at'] as String? ?? ''),
        b = DateTime.tryParse(row['recorded_until'] as String? ?? '');
    if (a != null &&
        b != null &&
        !b.isBefore(a) &&
        b.difference(a) <= const Duration(hours: 6)) {
      intervals['study/${row['id']}'] = (a.toUtc(), b.toUtc());
    }
  }
  for (final (a, b) in intervals.values) {
    var cursor = a;
    while (cursor.isBefore(b)) {
      final local = cursor.add(const Duration(hours: 8));
      final midnight = DateTime.utc(
        local.year,
        local.month,
        local.day + 1,
      ).subtract(const Duration(hours: 8));
      final end = b.isBefore(midnight) ? b : midnight;
      final day = taskDay(cursor);
      days[day] = (days[day] ?? Duration.zero) + end.difference(cursor);
      cursor = end;
    }
  }
  return days;
}

class TaskHistoryPage extends StatefulWidget {
  const TaskHistoryPage({
    super.key,
    required this.repository,
    required this.cloud,
    required this.onSync,
    this.onWallet,
    this.loadStudyFeed,
    this.studyCloud,
  });
  final TaskRepository repository;
  final TaskCloud cloud;
  final Future<void> Function() onSync;
  final ValueChanged<IdentityWallet>? onWallet;
  final Future<List<Map<String, dynamic>>> Function()? loadStudyFeed;
  final StudyCloud? studyCloud;
  @override
  State<TaskHistoryPage> createState() => _TaskHistoryPageState();
}

class _TaskHistoryPageState extends State<TaskHistoryPage> {
  List<TaskSession> records = [];
  List<Map<String, dynamic>> feed = [];
  List<StudySession> studyRecords = [];
  List<Map<String, dynamic>> studyFeed = [];
  late final studyCloud =
      widget.studyCloud ??
      StudyCloud(
        database: widget.repository.database,
        ownerId: widget.repository.ownerId,
        onSnapshot: (s) => widget.onWallet?.call(s.wallet),
      );
  String selected = taskDay(DateTime.now());
  bool loading = true, busy = false, verified = false;
  String? notice;
  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    try {
      records = await widget.repository.records();
      studyRecords = await widget.repository.database.sessions(
        widget.repository.ownerId,
      );
      studyFeed = await widget.repository.database.cachedStudyFeed(
        widget.repository.ownerId,
      );
      feed = await widget.repository.database.cachedTaskFeed(
        widget.repository.ownerId,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          notice = '本地记录暂时无法读取，请重启后重试。';
        });
      }
      return;
    }
    if (!mounted) return;
    setState(() => loading = false);
    await refresh();
  }

  Future<void> refresh() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.onSync();
      final next = await widget.cloud.feed();
      await widget.repository.database.cacheTaskFeed(
        widget.repository.ownerId,
        next,
      );
      records = await widget.repository.records();
      feed = next;
      for (final row in await widget.repository.database.sessions(
        widget.repository.ownerId,
      )) {
        if (row.state == StudySessionState.queued) {
          await studyCloud.submit(row);
          await widget.repository.database.acknowledge(
            widget.repository.ownerId,
            row.id,
          );
        }
      }
      studyFeed = await (widget.loadStudyFeed?.call() ?? studyCloud.history());
      studyRecords = await widget.repository.database.sessions(
        widget.repository.ownerId,
      );
      verified = true;
      notice = null;
    } catch (_) {
      notice = '显示本机保存的记录，云端更新待核对。';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> confirm(TaskSession row) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认中断前的计时？'),
        content: Text(
          '${row.activity.label} · ${row.elapsed.inMinutes} 分钟。仅保存的时长会参与奖励核对。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('暂不确认'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认记录'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await widget.repository.finishRun(row.runId);
      records = await widget.repository.records();
      if (mounted) setState(() {});
      await refresh();
    } catch (_) {
      if (mounted) setState(() => notice = '确认尚未保存，请重试。');
    }
  }

  Future<void> confirmStudy(StudySession row) async {
    if (busy) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('确认中断前的自习计时？'),
        content: Text('${row.elapsed.inMinutes} 分钟，仅保存的时长参与奖励核对。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('暂不确认'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('确认记录'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await widget.repository.database.confirm(
        widget.repository.ownerId,
        row.id,
        DateTime.now(),
      );
      studyRecords = await widget.repository.database.sessions(
        widget.repository.ownerId,
      );
      if (mounted) setState(() {});
      await refresh();
    } catch (_) {
      if (mounted) setState(() => notice = '确认尚未保存，请重试。');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = taskHeatmap(
      widget.repository.ownerId,
      records,
      feed,
      studyLocal: studyRecords,
      studyFeed: studyFeed,
    );
    final pending = records
        .where(
          (r) =>
              r.state == TaskSessionState.pendingPhoto ||
              r.state == TaskSessionState.ready,
        )
        .toList();
    final confirmedStudy = <String, Map<String, dynamic>>{
      for (final s in studyRecords.where(
        (s) => [
          StudySessionState.queued,
          StudySessionState.synced,
        ].contains(s.state),
      ))
        s.id: {
          'id': s.id,
          'owner_id': s.ownerId,
          'activity': 'study',
          'started_at': s.startedAt.toIso8601String(),
          'recorded_until': s.recordedUntil.toIso8601String(),
        },
      for (final s in studyFeed.where((s) => s['confirmed'] == true))
        s['id'] as String: s,
    };
    final ownFeed = [...feed, ...confirmedStudy.values]
        .where(
          (r) =>
              r['owner_id'] == widget.repository.ownerId &&
              taskDay(DateTime.parse(r['started_at'] as String)) == selected,
        )
        .toList();
    final today = DateTime.now().toUtc().add(const Duration(hours: 8));
    final last = DateTime.utc(today.year, today.month, today.day);
    final first = last.subtract(Duration(days: 90 + last.weekday % 7));
    return Scaffold(
      appBar: AppBar(
        title: const Text('学习记录'),
        actions: [
          IconButton(
            tooltip: '刷新记录',
            onPressed: busy ? null : refresh,
            icon: const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: refresh,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    '留下的时间',
                    style: Theme.of(
                      context,
                    ).textTheme.headlineMedium?.copyWith(letterSpacing: 1),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '近三个月 · 已核对的有效时长',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  for (final row in studyRecords.where(
                    (s) => s.state == StudySessionState.pendingConfirmation,
                  ))
                    ListTile(
                      leading: const Icon(Icons.menu_book_outlined),
                      title: Text('自习 · ${row.elapsed.inMinutes} 分钟'),
                      trailing: IconButton(
                        tooltip: '核对记录',
                        icon: const Icon(Icons.check_rounded),
                        onPressed: busy ? null : () => confirmStudy(row),
                      ),
                    ),
                  LayoutBuilder(
                    builder: (context, box) {
                      const columns = 14;
                      final cell = (box.maxWidth - 13 * 5) / columns;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var week = 0; week < columns; week++)
                            Padding(
                              padding: EdgeInsets.only(
                                right: week == columns - 1 ? 0 : 5,
                              ),
                              child: Column(
                                children: [
                                  for (var day = 0; day < 7; day++)
                                    Builder(
                                      builder: (context) {
                                        final date = first.add(
                                              Duration(days: week * 7 + day),
                                            ),
                                            key = date
                                                .toIso8601String()
                                                .substring(0, 10);
                                        final minutes =
                                            (days[key] ?? Duration.zero)
                                                .inMinutes;
                                        final future = date.isAfter(last);
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 5,
                                          ),
                                          child: Tooltip(
                                            message: '$key · $minutes 分钟',
                                            child: Semantics(
                                              label: '$key，$minutes 分钟',
                                              button: true,
                                              selected: selected == key,
                                              child: InkWell(
                                                onTap: future
                                                    ? null
                                                    : () => setState(
                                                        () => selected = key,
                                                      ),
                                                borderRadius:
                                                    BorderRadius.circular(3),
                                                child: Container(
                                                  width: cell,
                                                  height: cell,
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          3,
                                                        ),
                                                    border: selected == key
                                                        ? Border.all(
                                                            color: scheme
                                                                .onSurface,
                                                            width: 1.3,
                                                          )
                                                        : null,
                                                    color: future
                                                        ? Colors.transparent
                                                        : minutes == 0
                                                        ? scheme
                                                              .surfaceContainer
                                                        : scheme.primary
                                                              .withValues(
                                                                alpha:
                                                                    minutes < 15
                                                                    ? .3
                                                                    : minutes <
                                                                          30
                                                                    ? .5
                                                                    : minutes <
                                                                          60
                                                                    ? .7
                                                                    : 1,
                                                              ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        '少',
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 5),
                      for (final alpha in [.12, .3, .5, .7, 1.0])
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Container(
                            width: 10,
                            height: 10,
                            color: scheme.primary.withValues(alpha: alpha),
                          ),
                        ),
                      Text(
                        '多',
                        style: TextStyle(
                          fontSize: 10,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (notice != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        notice!,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  const SizedBox(height: 28),
                  if (pending.isNotEmpty) ...[
                    Text(
                      '待核对 / 待同步',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    for (final row in pending)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          row.state == TaskSessionState.ready
                              ? Icons.cloud_upload_outlined
                              : Icons.history_rounded,
                          color: scheme.primary,
                        ),
                        title: Text(
                          '${row.activity.label} · ${row.elapsed.inMinutes} 分钟',
                        ),
                        subtitle: Text(
                          row.state == TaskSessionState.ready
                              ? '本机已保存，等待云端回执'
                              : '中断前记录，请自行核对',
                          style: const TextStyle(fontSize: 12),
                        ),
                        trailing: IconButton(
                          tooltip: row.state == TaskSessionState.ready
                              ? '重试同步'
                              : '核对记录',
                          onPressed: busy
                              ? null
                              : row.state == TaskSessionState.ready
                              ? refresh
                              : () => confirm(row),
                          icon: Icon(
                            row.state == TaskSessionState.ready
                                ? Icons.sync_rounded
                                : Icons.check_rounded,
                          ),
                        ),
                      ),
                    const Divider(height: 32),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          selected,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        '${(days[selected] ?? Duration.zero).inMinutes} 分钟',
                        style: TextStyle(color: scheme.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (ownFeed.isEmpty)
                    Text(
                      verified ? '这一天尚无已确认记录' : '记录待核对',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  for (final row in ownFeed)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        row['activity'] == 'language'
                            ? Icons.translate_rounded
                            : row['activity'] == 'study'
                            ? Icons.menu_book_outlined
                            : Icons.directions_run_rounded,
                      ),
                      title: Text(
                        row['activity'] == 'language'
                            ? '外语学习'
                            : row['activity'] == 'study'
                            ? '自习'
                            : '锻炼',
                      ),
                      subtitle: Text(
                        '${DateTime.parse(row['recorded_until'] as String).difference(DateTime.parse(row['started_at'] as String)).inMinutes} 分钟',
                      ),
                      trailing: row['photo_path'] is String
                          ? const Icon(Icons.photo_outlined, size: 18)
                          : null,
                      onTap: row['photo_path'] is! String
                          ? null
                          : () async {
                              try {
                                final bytes = await widget.cloud.photo(
                                  row['photo_path'] as String,
                                );
                                if (!context.mounted) return;
                                await showDialog<void>(
                                  context: context,
                                  builder: (_) => Dialog(
                                    child: InteractiveViewer(
                                      child: Image.memory(bytes),
                                    ),
                                  ),
                                );
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('历史照片暂时无法加载。'),
                                    ),
                                  );
                                }
                              }
                            },
                    ),
                ],
              ),
            ),
    );
  }
}
