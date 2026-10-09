import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/storage/app_database.dart';
import '../identity/identity_repository.dart';
import 'weekly_tasks.dart';

class WeeklyTasksPanel extends StatefulWidget {
  const WeeklyTasksPanel({
    super.key,
    required this.ownerId,
    required this.onWallet,
    this.database,
  });

  final String ownerId;
  final ValueChanged<IdentityWallet> onWallet;
  final AppDatabase? database;

  @override
  State<WeeklyTasksPanel> createState() => _WeeklyTasksPanelState();
}

class _WeeklyTasksPanelState extends State<WeeklyTasksPanel>
    with WidgetsBindingObserver {
  late final database = widget.database ?? AppDatabase.shared;
  late final repository = WeeklyRepository(database, widget.ownerId);
  late final cloud = WeeklyCloud(database, widget.ownerId, widget.onWallet);
  final picker = ImagePicker();
  Timer? timer;
  Future<void>? syncing;
  List<WeeklyTask> tasks = [];
  List<WeeklyDraft> drafts = [];
  List<Map<String, dynamic>> feed = [];
  bool busy = false;
  String? message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
    timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(sync()),
    );
  }

  Future<void> _load() async {
    try {
      tasks = (await repository.cachedTasks())
          .where((task) => task.isCurrent(DateTime.now()))
          .toList();
      drafts = await repository.drafts();
      if (mounted) setState(() {});
      await sync();
    } catch (error) {
      if (kDebugMode) debugPrint('Weekly load failed: $error');
      if (mounted) setState(() => message = '周任务暂时无法读取，请重试。');
    }
  }

  Future<void> sync() => syncing ??= _sync().whenComplete(() => syncing = null);

  Future<void> _sync() async {
    if (busy) return;
    try {
      final all = {
        for (final task in await repository.cachedTasks()) task.offerId: task,
      };
      for (final draft in await repository.drafts()) {
        if (draft.state == 'ready' && all[draft.offerId] != null) {
          await cloud.submit(all[draft.offerId]!, draft);
        }
      }
      tasks = await cloud.refresh();
      feed = await cloud.familyFeed();
      drafts = await repository.drafts();
      message = null;
    } catch (error) {
      if (kDebugMode) debugPrint('Weekly sync failed: $error');
      tasks = (await repository.cachedTasks())
          .where((task) => task.isCurrent(DateTime.now()))
          .toList();
      drafts = await repository.drafts();
      message = '周任务尚未同步；已确认的内容保存在本机，联网后自动重试。';
    }
    if (mounted) setState(() {});
  }

  Future<void> _act(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
      drafts = await repository.drafts();
    } catch (error) {
      if (kDebugMode) debugPrint('Weekly action failed: $error');
      message = error is ArgumentError
          ? '文字最多 100 字；照片仅支持不超过 5 MB 的 JPEG 或 PNG。'
          : '操作未完成，本机内容仍保留，请重试。';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _editNote(WeeklyTask task, WeeklyDraft? draft) async {
    final controller = TextEditingController(text: draft?.note ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('完成记录'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 100,
          maxLines: 4,
          decoration: const InputDecoration(hintText: '写下本次完成内容'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) await _act(() => repository.saveNote(task, value));
  }

  Future<void> _pickPhoto(WeeklyTask task, int slot) async {
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (file == null) return;
    await _act(
      () async => repository.savePhoto(task, slot, await file.readAsBytes()),
    );
  }

  Future<void> _confirm(WeeklyTask task) async {
    await _act(() => repository.confirm(task, DateTime.now()));
    unawaited(sync());
  }

  Future<void> _showRecord(Map<String, dynamic> item) async {
    final paths = (item['photo_paths'] as List?)?.cast<String>() ?? [];
    try {
      final photos = <Uint8List>[];
      for (final path in paths) {
        photos.add(await cloud.photo(path));
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(item['prompt'] as String),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if ((item['note'] as String?)?.isNotEmpty ?? false)
                    Text(item['note'] as String),
                  for (final photo in photos)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: InteractiveViewer(
                        child: Image.memory(photo, fit: BoxFit.contain),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('记录照片暂时无法读取，请联网后重试。')));
      }
    }
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
    final draftById = {for (final draft in drafts) draft.offerId: draft};
    final pendingOld = drafts
        .where(
          (d) =>
              d.state == 'ready' && !tasks.any((t) => t.offerId == d.offerId),
        )
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '每周特别任务',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton(
              onPressed: sync,
              icon: const Icon(Icons.refresh),
              tooltip: '刷新周任务',
            ),
          ],
        ),
        const Text('每周一 00:00（北京时间）更新两项；每项完成获得 6 宝石和 6 鹰镑。'),
        if (message != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(message!),
          ),
        if (tasks.isEmpty) const ListTile(title: Text('正在获取本周任务')),
        for (final task in tasks) _card(task, draftById[task.offerId]),
        if (pendingOld > 0)
          ListTile(
            title: Text('$pendingOld 项上周已确认任务待同步'),
            trailing: IconButton(
              onPressed: sync,
              icon: const Icon(Icons.sync),
              tooltip: '重试补发',
            ),
          ),
        const SizedBox(height: 12),
        Text('完成记录', style: Theme.of(context).textTheme.titleMedium),
        if (feed.isEmpty) const ListTile(title: Text('暂无已确认记录')),
        for (final item in feed)
          ListTile(
            title: Text(item['prompt'] as String),
            subtitle: Text(
              '${(item['confirmed_at'] as String).substring(0, 10)} · '
              '${item['owner_id'] == widget.ownerId ? '我' : '家庭成员'} · +6 宝石、+6 鹰镑',
            ),
            onTap: () => _showRecord(item),
          ),
      ],
    );
  }

  Widget _card(WeeklyTask task, WeeklyDraft? draft) {
    final done = task.confirmedAt != null || draft?.state == 'synced';
    final ready = draft?.state == 'ready';
    final editable = !busy && !done && !ready && task.isCurrent(DateTime.now());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(task.prompt, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              done
                  ? '已完成 · 奖励已入账'
                  : ready
                  ? '已确认 · 等待同步'
                  : task.evidenceLabel,
            ),
            if (editable) ...[
              const SizedBox(height: 8),
              if (task.evidenceKind == 'text')
                OutlinedButton.icon(
                  onPressed: () => _editNote(task, draft),
                  icon: const Icon(Icons.edit_outlined),
                  label: Text(draft?.note.isNotEmpty == true ? '修改记录' : '填写记录'),
                ),
              for (var slot = 0; slot < task.imageCount; slot++)
                OutlinedButton.icon(
                  onPressed: () => _pickPhoto(task, slot),
                  icon: Icon(
                    draft?.photos[slot] == null
                        ? Icons.add_photo_alternate_outlined
                        : Icons.check_circle_outline,
                  ),
                  label: Text(
                    '照片 ${slot + 1}${draft?.photos[slot] == null ? '' : ' · 已保存'}',
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => _confirm(task),
                  child: const Text('确认完成'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
