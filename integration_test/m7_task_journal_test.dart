import 'package:cat_library_demo/app/app_theme.dart';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/tasks/task_board_page.dart';
import 'package:cat_library_demo/features/tasks/task_repository.dart';
import 'package:cat_library_demo/features/tasks/task_session.dart';
import 'package:cat_library_demo/features/tasks/task_board_visuals.dart';
import 'package:cat_library_demo/features/tasks/task_timer_page.dart';
import 'package:cat_library_demo/features/tasks/weekly_tasks_panel.dart';
import 'package:cat_library_demo/features/study/lock_screen_timer.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

class JournalFixtureCloud extends TaskCloud {
  JournalFixtureCloud(AppDatabase db)
    : super(database: db, ownerId: 'journal-memory-only', onWallet: (_) {});
  bool offline = true;
  @override
  Future<void> sync(TaskSession session) async {
    if (offline) throw StateError('isolated offline');
    if (session.state == TaskSessionState.ready) {
      await database.acknowledgeTask(ownerId, session.id);
    }
  }

  @override
  Future<void> refresh() async {
    if (offline) throw StateError('isolated offline');
    days = [
      {
        'activity': 'language',
        'day': DateTime.now()
            .toUtc()
            .add(const Duration(hours: 8))
            .toIso8601String()
            .substring(0, 10),
        'issued': 3,
      },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> feed() async {
    if (offline) throw StateError('isolated offline');
    final now = DateTime.now().toUtc();
    return [
      for (var day = 0; day < 70; day++)
        if (day % 3 == 0 || day % 7 == 0)
          {
            'id': 'journal-demo-$day',
            'owner_id': ownerId,
            'activity': day.isEven ? 'language' : 'exercise',
            'started_at': now
                .subtract(Duration(days: day, minutes: 30))
                .toIso8601String(),
            'recorded_until': now
                .subtract(Duration(days: day))
                .toIso8601String(),
            'photo_path': null,
          },
    ];
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets(
    'task journal native navigation, pause and history in both themes',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            LockScreenTimer.channel,
            (call) async => call.method == 'readCheckpoint' ? null : true,
          );
      try {
        await binding.convertFlutterSurfaceToImage();
        for (final brightness in [Brightness.light, Brightness.dark]) {
          final mode = brightness == Brightness.light ? 'light' : 'night';
          final cloud = JournalFixtureCloud(db);
          await db.customStatement(
            'DELETE FROM task_feed_cache WHERE owner_id=?',
            [cloud.ownerId],
          );
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(brightness),
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                appBar: AppBar(),
                body: SafeArea(
                  child: TaskBoardPage(
                    key: ValueKey(mode),
                    database: db,
                    taskCloud: cloud,
                    ownerId: cloud.ownerId,
                    onWallet: (_) {},
                  ),
                ),
              ),
            ),
          );
          Future<void> flush() async {
            for (var i = 0; i < 15; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 30));
              await tester.pump(const Duration(milliseconds: 50));
            }
          }

          Future<void> capture(String state) async {
            await flush();
            await binding.takeScreenshot('m7-task-journal-$state-$mode');
          }

          await flush();
          await precacheImage(
            const AssetImage('assets/images/cats/calico-sitting-v1.png'),
            tester.element(find.byType(TaskBoardHeading)),
          );
          expect(find.text('今日奖励待核对'), findsNWidgets(2));
          expect(find.text('任务板'), findsNothing);
          await capture('unknown');
          await tester.tap(find.byTooltip('学习记录'));
          await flush();
          expect(find.text('记录待核对'), findsOneWidget);
          await capture('unknown-history');
          await tester.pageBack();
          await flush();
          cloud.offline = false;
          await tester.tap(find.byTooltip('核对任务同步'));
          await flush();
          expect(find.textContaining('今日 3/12'), findsOneWidget);
          await capture('confirmed');
          cloud.offline = true;
          await tester.tap(find.byTooltip('核对任务同步'));
          await flush();
          expect(find.textContaining('上次核对 3/12'), findsOneWidget);
          await capture('retained');
          await tester.tap(find.byTooltip('开始外语学习'));
          await flush();
          expect(find.byType(TaskTimerPage), findsOneWidget);
          expect(find.text('本周特别任务'), findsNothing);
          await capture('active');
          await tester.tap(find.byTooltip('暂停计时'));
          await flush();
          expect(find.text('已暂停'), findsOneWidget);
          final frozen = tester
              .widget<Text>(find.byKey(const Key('task-focus-time')))
              .data;
          await Future<void>.delayed(const Duration(seconds: 2));
          await tester.pump();
          expect(
            tester.widget<Text>(find.byKey(const Key('task-focus-time'))).data,
            frozen,
          );
          await capture('paused');
          await tester.tap(find.byTooltip('继续计时'));
          await flush();
          expect(find.text('专注中'), findsOneWidget);
          await tester.tap(find.byTooltip('结束计时'));
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.text('确认结束'));
          await flush();
          expect(find.byType(TaskTimerPage), findsNothing);
          final rows = await db.taskSessions(cloud.ownerId);
          expect(rows.length, 2);
          expect(
            rows.every(
              (r) => r.state == TaskSessionState.ready && r.photoBytes == null,
            ),
            isTrue,
          );
          await tester.tap(find.byTooltip('学习记录'));
          await flush();
          await capture('history');
          expect(find.text('本机已保存，等待云端回执'), findsWidgets);
          await tester.pageBack();
          await flush();
          await tester.scrollUntilVisible(
            find.text('本周特别任务'),
            100,
            scrollable: find.byType(Scrollable).first,
          );
          await flush();
          await tester.tap(find.text('本周特别任务').hitTestable());
          await flush();
          expect(find.byType(WeeklyTasksPanel), findsOneWidget);
          await capture('weekly');
          expect(find.text('本周特别任务'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await flush();
          // Only the fixture's memory records; native SQLite/prefs are never opened.
          await db.customStatement(
            'DELETE FROM task_sessions WHERE owner_id=?',
            [cloud.ownerId],
          );
        }
        binding.reportData!.addAll({
          'result': 'PASS',
          'actualTaskBoardPage': true,
          'actualFullscreenTimer': true,
          'pauseFreezesClock': true,
          'resumeAndConfirmEnd': true,
          'photoFreeQueue': true,
          'historyAndWeeklyAreSeparateRoutes': true,
          'retainsUnknownAndOfflineStates': true,
          'nativeTimerChannelIntercepted': true,
          'scope': 'one emulator, memory SQLite, cloud stub; synthetic history',
          'remoteInternetVerified': false,
          'physicalPhoneVerified': false,
        });
      } finally {
        await tester.pumpWidget(const SizedBox());
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(LockScreenTimer.channel, null);
        await db.close();
      }
    },
  );
}
