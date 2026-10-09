import 'package:cat_library_demo/app/app_theme.dart';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/tasks/task_board_page.dart';
import 'package:cat_library_demo/features/tasks/task_repository.dart';
import 'package:cat_library_demo/features/tasks/task_session.dart';
import 'package:cat_library_demo/features/tasks/task_board_visuals.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

class ReadOnlyTaskCloud extends TaskCloud {
  ReadOnlyTaskCloud(AppDatabase db)
    : super(database: db, ownerId: 'visual-board-only', onWallet: (_) {});
  bool offline = true;

  @override
  Future<void> sync(TaskSession session) async =>
      throw StateError('No writes allowed');

  @override
  Future<void> refresh() async {
    if (offline) throw StateError('isolated read failure');
    final day = DateTime.now().toUtc().add(const Duration(hours: 8));
    days = [
      {
        'activity': 'language',
        'day': day.toIso8601String().substring(0, 10),
        'issued': 3,
      },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> feed() async {
    if (offline) throw StateError('isolated offline');
    return [
      {
        'id': 'board-read-only',
        'activity': 'language',
        'owner_id': ownerId,
        'started_at': '2026-10-09T10:00:00Z',
        'recorded_until': '2026-10-09T10:05:00Z',
        'photo_path': 'visual-only',
      },
    ];
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'task board distinguishes unknown and retained data in both themes',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      try {
        await binding.convertFlutterSurfaceToImage();
        for (final brightness in [Brightness.light, Brightness.dark]) {
          final mode = brightness == Brightness.light ? 'light' : 'night';
          final cloud = ReadOnlyTaskCloud(db);
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
          for (
            var i = 0;
            i < 50 && find.text('今日奖励待核对').evaluate().isEmpty;
            i++
          ) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(find.text('今日奖励待核对'), findsNWidgets(2));
          Future<void> capture(String state) async {
            await tester.pump();
            await Future<void>.delayed(const Duration(milliseconds: 400));
            await tester.pump(const Duration(milliseconds: 300));
            await binding.takeScreenshot('m7-task-board-$state-$mode');
          }

          await capture('unknown');
          await tester.tap(find.byTooltip('学习记录'));
          await tester.pump(const Duration(seconds: 1));
          expect(find.text('记录待核对'), findsOneWidget);
          expect(find.text('暂无已确认任务'), findsNothing);
          await capture('unknown-records');
          await tester.pageBack();
          await tester.pump(const Duration(milliseconds: 300));
          cloud.offline = false;
          await tester.tap(find.byTooltip('核对任务同步'));
          for (
            var i = 0;
            i < 50 && find.textContaining('今日 3/12').evaluate().isEmpty;
            i++
          ) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(find.textContaining('今日 3/12'), findsOneWidget);
          expect(
            tester
                .widgetList<TaskActivityCard>(find.byType(TaskActivityCard))
                .first
                .issued,
            3,
          );
          await capture('confirmed');
          cloud.offline = true;
          await tester.tap(find.byTooltip('核对任务同步'));
          for (
            var i = 0;
            i < 50 && find.textContaining('上次核对 3/12').evaluate().isEmpty;
            i++
          ) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(find.textContaining('上次核对 3/12'), findsOneWidget);
          await capture('retained');
          await tester.tap(find.byTooltip('学习记录'));
          await tester.pump(const Duration(seconds: 1));
          expect(find.text('记录待核对'), findsNothing);
          expect(tester.takeException(), isNull);
          expect(await db.taskSessions(cloud.ownerId), isEmpty);
          await tester.pumpWidget(const SizedBox());
          await db.customStatement(
            'DELETE FROM task_feed_cache WHERE owner_id=?',
            [cloud.ownerId],
          );
        }
        binding.reportData!.addAll({
          'result': 'PASS',
          'actualTaskBoardPage': true,
          'themes': ['light', 'night'],
          'unknownDoesNotClaimZeroRewardsOrEmptyFeed': true,
          'retryUsesActualButton': true,
          'failedReadRetainsConfirmedRewardsAndFeed': true,
          'taskQueueUnchanged': true,
          'scope':
              'one emulator; isolated memory SQLite and cloud read stub; no business HTTP',
          'remoteInternetVerified': false,
          'physicalPhoneVerified': false,
        });
      } finally {
        await tester.pumpWidget(const SizedBox());
        await db.close();
      }
    },
  );
}
