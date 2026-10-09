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
