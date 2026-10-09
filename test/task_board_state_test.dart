import 'dart:async';

import 'package:cat_library_demo/app/app_theme.dart';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/tasks/task_board_page.dart';
import 'package:cat_library_demo/features/tasks/task_repository.dart';
import 'package:cat_library_demo/features/tasks/task_session.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class BoardCloud extends TaskCloud {
  BoardCloud(AppDatabase db)
    : super(database: db, ownerId: 'board-fixture', onWallet: (_) {});

  bool offline = true;
  Completer<void>? wait;
  int refreshes = 0;

  @override
  Future<void> sync(TaskSession session) async {}

  @override
  Future<void> refresh() async {
    refreshes++;
    await wait?.future;
    if (offline) throw StateError('isolated offline');
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
  Future<List<Map<String, dynamic>>> feed() async => [
    {
      'activity': 'language',
      'owner_id': ownerId,
      'started_at': '2026-10-09T10:00:00Z',
      'photo_path': 'fixture-only',
    },
  ];
}

Future<void> flushBoard(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('unknown tasks remain unconfirmed at 320px in $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      final cloud = BoardCloud(db);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness),
          home: Scaffold(
            body: TaskBoardPage(
              ownerId: cloud.ownerId,
              onWallet: (_) {},
              database: db,
              taskCloud: cloud,
            ),
          ),
        ),
      );
      await flushBoard(tester);
      expect(find.text('今日奖励待核对'), findsNWidgets(2));
      expect(find.textContaining('今日 0/12'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('完成记录待核对'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('暂无已确认任务'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await flushBoard(tester);
      await db.close();
    });
  }

  testWidgets('successful sync cannot erase local permission notice', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    final cloud = BoardCloud(db)..offline = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TaskBoardPage(
            ownerId: cloud.ownerId,
            onWallet: (_) {},
            database: db,
            taskCloud: cloud,
          ),
        ),
      ),
    );
    await flushBoard(tester);
    await tester.tap(find.text('开始').first);
    await flushBoard(tester);
    expect(find.textContaining('通知未授权'), findsOneWidget);
    await tester.pump(const Duration(seconds: 15));
    await flushBoard(tester);
    expect(find.textContaining('通知未授权'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await flushBoard(tester);
    await db.close();
  });

  testWidgets(
    'failed retry retains last verified reward and feed; concurrent retry is disabled',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final cloud = BoardCloud(db)..offline = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TaskBoardPage(
              ownerId: cloud.ownerId,
              onWallet: (_) {},
              database: db,
              taskCloud: cloud,
            ),
          ),
        ),
      );
      await flushBoard(tester);
      expect(find.textContaining('今日 3/12'), findsOneWidget);
      cloud.offline = true;
      await tester.pump(const Duration(seconds: 15));
      await flushBoard(tester);
      expect(find.textContaining('上次核对 3/12'), findsOneWidget);
      expect(find.text('完成记录待核对'), findsNothing);
      cloud.offline = false;
      cloud.wait = Completer<void>();
      final before = cloud.refreshes;
      await tester.tap(find.byTooltip('核对任务同步'));
      await flushBoard(tester);
      final button = tester.widget<IconButton>(
        find.byWidgetPredicate(
          (widget) => widget is IconButton && widget.tooltip == '核对任务同步',
        ),
      );
      expect(button.onPressed, isNull);
      await tester.pump(const Duration(seconds: 15));
      await flushBoard(tester);
      expect(cloud.refreshes, before + 1);
      cloud.wait!.complete();
      await flushBoard(tester);
      expect(find.textContaining('今日 3/12'), findsOneWidget);
      expect(find.text('已核对任务'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await flushBoard(tester);
      await db.close();
    },
  );
}
