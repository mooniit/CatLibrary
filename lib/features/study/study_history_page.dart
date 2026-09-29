import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/storage/app_database.dart';
import '../../core/time/business_day.dart';
import 'study_reward.dart';
import 'study_session.dart';

class StudyPresetEditPage extends StatefulWidget {
  const StudyPresetEditPage({
    super.key,
    required this.database,
    required this.ownerId,
  });
  final AppDatabase database;
  final String ownerId;

  @override
  State<StudyPresetEditPage> createState() => _StudyPresetEditPageState();
}

class _StudyPresetEditPageState extends State<StudyPresetEditPage> {
  List<StudyPreset>? presets;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    final next = await widget.database.presets(widget.ownerId);
    if (mounted) setState(() => presets = next);
  }

  Future<void> remove(StudyPreset preset) async {
    await widget.database.deletePreset(widget.ownerId, preset.seconds);
    await load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('常用计时器')),
    body: presets == null
        ? const Center(child: CircularProgressIndicator())
        : presets!.isEmpty
        ? const Center(child: Text('还没有常用计时器'))
        : ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: presets!.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final preset = presets![index];
              return Card(
                child: ListTile(
                  title: Text(preset.name),
                  subtitle: Text(
                    studyDurationText(Duration(seconds: preset.seconds)),
                  ),
                  trailing: IconButton(
                    key: Key('delete-preset-${preset.seconds}'),
                    tooltip: '删除${preset.name}',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => remove(preset),
                  ),
                ),
              );
            },
          ),
  );
}

class StudyHistoryPage extends StatefulWidget {
  const StudyHistoryPage({
    super.key,
    required this.records,
    required this.onConfirmRecovered,
  });
  final List<StudySession> records;
  final Future<void> Function(StudySession record) onConfirmRecovered;

  @override
  State<StudyHistoryPage> createState() => _StudyHistoryPageState();
}

class _StudyHistoryPageState extends State<StudyHistoryPage> {
  late List<StudySession> records = [...widget.records];
  bool busy = false;

  Future<void> confirm(StudySession record) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.onConfirmRecovered(record);
      final index = records.indexWhere((item) => item.id == record.id);
      if (index >= 0) {
        records[index] = StudySession(
          id: record.id,
          ownerId: record.ownerId,
          runId: record.runId,
          startedAt: record.startedAt,
          recordedUntil: record.recordedUntil,
          state: StudySessionState.queued,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<StudySession>>{};
    for (final record in records) {
      if (record.state == StudySessionState.running) continue;
      groups.putIfAbsent(record.runId, () => []).add(record);
    }
    final runs = groups.values.where((run) {
      final duration = run.fold<Duration>(
        Duration.zero,
        (sum, record) => sum + record.elapsed,
      );
      return duration >= const Duration(minutes: 10) ||
          run.any(
            (record) => record.state == StudySessionState.pendingConfirmation,
          );
    }).toList()..sort((a, b) => b.first.startedAt.compareTo(a.first.startedAt));
    final items = <({String? day, List<StudySession>? run})>[];
    String? lastDay;
    for (final run in runs) {
      final day = run.first.startedAt
          .toUtc()
          .add(const Duration(hours: 8))
          .toIso8601String()
          .substring(0, 10);
      if (day != lastDay) {
        items.add((day: day, run: null));
        lastDay = day;
      }
      items.add((day: null, run: run));
    }
    final awarded = studyCoinsByRun(records);
    return Scaffold(
      appBar: AppBar(title: const Text('自习记录')),
      body: runs.isEmpty
          ? const Center(child: Text('暂无满10分钟的自习记录'))
          : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                if (item.day != null) {
                  final parts = item.day!.split('-');
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                    child: Text(
                      '${parts[0]}年${int.parse(parts[1])}月${int.parse(parts[2])}日',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  );
                }
                final run = item.run!;
                final duration = run.fold<Duration>(
                  Duration.zero,
                  (sum, record) => sum + record.elapsed,
                );
                final startTime = run.first.startedAt
                    .toUtc()
                    .add(const Duration(hours: 8))
                    .toIso8601String()
                    .substring(11, 16);
                final pending = run
                    .where(
                      (record) =>
                          record.state == StudySessionState.pendingConfirmation,
                    )
                    .toList();
                final queued = run.any(
                  (record) => record.state == StudySessionState.queued,
                );
                final status = pending.isNotEmpty
                    ? '待核对'
                    : queued
                    ? '待入账'
                    : '+${awarded[run.first.runId] ?? 0} 喵喵币';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    children: [
                      ListTile(
                        title: Text(studyDurationText(duration)),
                        subtitle: Text('$startTime · 有效计时'),
                        trailing: Text(status),
                      ),
                      if (pending.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 12, bottom: 8),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: busy
                                  ? null
                                  : () async {
                                      for (final record in pending) {
                                        await confirm(record);
                                      }
                                    },
                              child: const Text('核对恢复记录并入账'),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// Attribution is the incremental daily reward after each synced interval.
/// Paused gaps contribute no time or coins.
Map<String, int> studyCoinsByRun(List<StudySession> records) {
  final sorted =
      records
          .where((record) => record.state == StudySessionState.synced)
          .toList()
        ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  final dailyMs = <String, int>{};
  final result = <String, int>{};
  for (final record in sorted) {
    for (final entry in millisecondsByBusinessDay(
      record.startedAt,
      record.recordedUntil,
    ).entries) {
      final before = dailyMs[entry.key] ?? 0;
      final after = before + entry.value;
      dailyMs[entry.key] = after;
      final delta =
          dailyStudyCoins(Duration(milliseconds: after)) -
          dailyStudyCoins(Duration(milliseconds: before));
      result.update(
        record.runId,
        (value) => value + delta,
        ifAbsent: () => delta,
      );
    }
  }
  return result;
}

String studyDurationText(Duration duration) {
  final seconds = duration.inSeconds;
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final rest = seconds % 60;
  return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
}
