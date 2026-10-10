import 'package:cat_library_demo/features/study/study_cloud.dart';
import 'package:cat_library_demo/features/study/study_session.dart';
import 'package:cat_library_demo/app/app_theme.dart';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/tasks/task_history_page.dart';
import 'package:cat_library_demo/features/tasks/task_timer_page.dart';
import 'package:cat_library_demo/features/tasks/task_repository.dart';
import 'package:cat_library_demo/features/tasks/task_session.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> flush(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  testWidgets(
    'unified history keeps interrupted study queued while offline then synchronizes once',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final start = DateTime.now().toUtc().subtract(
        const Duration(minutes: 12),
      );
      final initial = StudySession(
        id: 'interrupted',
        ownerId: 'a',
        startedAt: start,
        recordedUntil: start,
        state: StudySessionState.running,
      );
      await tester.runAsync(() async {
        await db.start(initial);
        await db.checkpoint(
          initial.checkpoint(start.add(const Duration(minutes: 7)), stop: true),
        );
      });
      final task = TaskRepository(database: db, ownerId: 'a');
      final study = HistoryStudyCloud(db);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.light),
          home: TaskHistoryPage(
            repository: task,
            cloud: HistoryTaskCloud(db),
            studyCloud: study,
            onSync: () async {},
          ),
        ),
      );
      await flush(tester);
      expect(find.text('自习 · 7 分钟'), findsOneWidget);
      await tester.tap(find.byTooltip('核对记录'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('确认记录'));
      await flush(tester);
      final queued = await tester.runAsync(() => db.sessions('a'));
      expect(queued!.single.state, StudySessionState.queued);
      expect(study.attempts, 1);
      expect(find.text('显示本机保存的记录，云端更新待核对。'), findsOneWidget);
      study.offline = false;
      await tester.tap(find.byTooltip('刷新记录'));
      await flush(tester);
      expect(
        (await tester.runAsync(() => db.sessions('a')))!.single.state,
        StudySessionState.synced,
      );
      expect(study.attempts, 2);
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('自习'), findsOneWidget);
      expect(find.text('7 分钟'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
      await tester.runAsync(db.close);
    },
  );
  test(
    'unified heatmap deduplicates paused study intervals and keeps UTC+8 midnight and owner scope',
    () {
      final a = DateTime.utc(2026, 10, 10, 15, 55),
          b = a.add(const Duration(minutes: 10));
      final row = StudySession(
        id: 'same',
        ownerId: 'a',
        runId: 'paused-run',
        startedAt: a,
        recordedUntil: b,
        state: StudySessionState.synced,
      );
      final result = taskHeatmap(
        'a',
        [],
        [],
        studyLocal: [row],
        studyFeed: [
          {
            'id': 'same',
            'owner_id': 'a',
            'started_at': a.toIso8601String(),
            'recorded_until': b.toIso8601String(),
            'confirmed': true,
          },
          {
            'id': 'pending',
            'owner_id': 'a',
            'started_at': a.toIso8601String(),
            'recorded_until': b.toIso8601String(),
            'confirmed': false,
          },
          {
            'id': 'other',
            'owner_id': 'b',
            'started_at': a.toIso8601String(),
            'recorded_until': b.toIso8601String(),
            'confirmed': true,
          },
        ],
      );
      expect(result, {
        '2026-10-10': const Duration(minutes: 5),
        '2026-10-11': const Duration(minutes: 5),
      });
    },
  );

  test(
    'heatmap deduplicates ids, excludes unconfirmed and other members, splits midnight',
    () {
      final start = DateTime.utc(2026, 10, 8, 15, 55),
          end = DateTime.utc(2026, 10, 8, 16, 5);
      TaskSession row(String id, TaskSessionState state) => TaskSession(
        id: id,
        ownerId: 'a',
        activity: TaskActivity.language,
        startedAt: start,
        recordedUntil: end,
        state: state,
      );
      final result = taskHeatmap(
        'a',
        [
          row('same', TaskSessionState.synced),
          row('pending', TaskSessionState.ready),
        ],
        [
          {
            'id': 'same',
            'owner_id': 'a',
            'started_at': start.toIso8601String(),
            'recorded_until': end.toIso8601String(),
          },
          {
            'id': 'other',
            'owner_id': 'b',
            'started_at': start.toIso8601String(),
            'recorded_until': end.toIso8601String(),
          },
        ],
      );
      expect(result, {
        '2026-10-08': const Duration(minutes: 5),
        '2026-10-09': const Duration(minutes: 5),
      });
    },
  );
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('fullscreen pause resume and confirm end in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      var now = DateTime.utc(2026, 10, 9, 1);
      final repo = TaskRepository(database: db, ownerId: 'a', now: () => now);
      await tester.runAsync(() async {
        await repo.recover(null);
        await repo.start(TaskActivity.language);
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        TaskTimerPage(repository: repo, onSync: () async {}),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await flush(tester);
      expect(find.byType(TaskTimerPage), findsOneWidget);
      now = now.add(const Duration(minutes: 6));
      await tester.tap(find.byTooltip('暂停计时'));
      await flush(tester);
      expect(find.text('已暂停'), findsOneWidget);
      expect(find.text('00:06:00'), findsOneWidget);
      now = now.add(const Duration(minutes: 20));
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('00:06:00'), findsOneWidget);
      await tester.tap(find.byTooltip('继续计时'));
      await flush(tester);
      now = now.add(const Duration(minutes: 5));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('00:11:00'), findsOneWidget);
      await tester.tap(find.byTooltip('结束计时'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('继续计时'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(TaskTimerPage), findsOneWidget);
      await tester.tap(find.byTooltip('结束计时'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('确认结束'));
      await flush(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(TaskTimerPage), findsNothing);
      final records = await tester.runAsync(repo.records);
      expect(
        records!.every(
          (r) => r.state == TaskSessionState.ready && r.photoBytes == null,
        ),
        isTrue,
      );
      expect(records.fold<int>(0, (sum, r) => sum + r.elapsed.inMinutes), 11);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await flush(tester);
      await tester.runAsync(db.close);
    });
  }
}

class HistoryTaskCloud extends TaskCloud {
  HistoryTaskCloud(AppDatabase db)
    : super(database: db, ownerId: 'a', onWallet: (_) {});
  @override
  Future<List<Map<String, dynamic>>> feed() async => [];
}

class HistoryStudyCloud extends StudyCloud {
  HistoryStudyCloud(AppDatabase db)
    : super(database: db, ownerId: 'a', onSnapshot: (_) {});
  bool offline = true;
  int attempts = 0;
  @override
  Future<void> submit(StudySession session) async {
    attempts++;
    if (offline) throw StateError('offline');
  }

  @override
  Future<List<Map<String, dynamic>>> history() async => [];
}
