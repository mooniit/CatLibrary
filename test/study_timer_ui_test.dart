import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/identity/identity_repository.dart';
import 'package:cat_library_demo/features/study/lock_screen_timer.dart';
import 'package:cat_library_demo/features/study/study_cloud.dart';
import 'package:cat_library_demo/features/study/study_page.dart';
import 'package:cat_library_demo/features/study/study_session.dart';
import 'package:drift/native.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          LockScreenTimer.channel,
          (call) async => call.method == 'readCheckpoint' ? null : false,
        );
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(LockScreenTimer.channel, null);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }
  }

  testWidgets('pause excludes the gap and ending confirms all run segments', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    var time = DateTime.utc(2026, 9, 26, 1);
    final confirmed = <String, StudySession>{};
    var balance = 30;
    Future<StudySnapshot> exchange(StudySession? session) async {
      if (session?.state == StudySessionState.queued) {
        confirmed[session!.id] = session;
      }
      final total = confirmed.values.fold<int>(
        0,
        (sum, record) => sum + record.elapsed.inMilliseconds,
      );
      final issued = (total ~/ 60000 * 2).clamp(0, 120);
      return StudySnapshot(
        IdentityWallet(
          ownerId: 'a',
          miaoCoins: 30 + issued,
          eaglePounds: 0,
          gems: 0,
        ),
        {
          '2026-09-26': {'issued': issued, 'eligible_ms': total},
        },
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudyPage(
            ownerId: 'a',
            onWallet: (value) => balance = value.miaoCoins,
            databaseFactory: () => db,
            now: () => time,
            exchange: exchange,
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.byKey(const Key('study-start')));
    await settle(tester);
    time = time.add(const Duration(minutes: 5));
    await tester.tap(find.byKey(const Key('study-pause-resume')));
    await settle(tester);
    expect(find.text('00:05:00'), findsOneWidget);
    time = time.add(const Duration(minutes: 10));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('00:05:00'), findsOneWidget);
    await tester.tap(find.byKey(const Key('study-pause-resume')));
    await settle(tester);
    time = time.add(const Duration(minutes: 5));
    await tester.tap(find.byKey(const Key('study-stop')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认结束'));
    await settle(tester);
    final segments = await tester.runAsync(() => db.sessions('a'));
    expect(segments, hasLength(2));
    expect(segments!.map((record) => record.runId).toSet(), hasLength(1));
    expect(
      segments.fold<int>(0, (sum, record) => sum + record.elapsed.inMinutes),
      10,
    );
    expect(
      segments.every((record) => record.state == StudySessionState.synced),
      isTrue,
    );
    expect(balance, 50);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('countdown has a five-hour wheel and auto ends at target', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    var time = DateTime.utc(2026, 9, 26, 1);
    var balance = 30;
    Future<StudySnapshot> exchange(StudySession? session) async {
      final issued = session?.state == StudySessionState.queued
          ? 80
          : (balance - 30);
      return StudySnapshot(
        IdentityWallet(
          ownerId: 'a',
          miaoCoins: 30 + issued,
          eaglePounds: 0,
          gems: 0,
        ),
        {
          '2026-09-26': {
            'issued': issued,
            'eligible_ms': issued == 80 ? 2400000 : 0,
          },
        },
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudyPage(
            ownerId: 'a',
            onWallet: (value) => balance = value.miaoCoins,
            databaseFactory: () => db,
            now: () => time,
            exchange: exchange,
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('倒计时'));
    await tester.pumpAndSettle();
    final toggle = find.byType(SegmentedButton<StudyTimerMode>);
    final toggleWidth = tester.getSize(toggle).width;
    expect(
      tester.widget<SegmentedButton<StudyTimerMode>>(toggle).showSelectedIcon,
      isFalse,
    );
    await tester.tap(find.text('计时'));
    await tester.pumpAndSettle();
    expect(tester.getSize(toggle).width, toggleWidth);
    await tester.tap(find.text('倒计时'));
    await tester.pumpAndSettle();
    expect(find.text('自习'), findsNothing);
    expect(find.text('示例'), findsOneWidget);
    expect(find.text('00:40:00'), findsOneWidget);
    expect(find.text('时'), findsNothing);
    final buttonCenter = tester.getCenter(find.byKey(const Key('study-start')));
    final iconCenter = tester.getCenter(find.byIcon(Icons.play_arrow));
    expect(iconCenter.dx, closeTo(buttonCenter.dx, 0.5));
    expect(iconCenter.dy, closeTo(buttonCenter.dy, 0.5));
    expect(
      tester
          .widget<CupertinoPicker>(find.byKey(const Key('study-hours-wheel')))
          .childDelegate,
      isA<ListWheelChildLoopingListDelegate>(),
    );
    await tester.timedDrag(
      find.byKey(const Key('study-hours-wheel')),
      const Offset(0, 48),
      const Duration(milliseconds: 550),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StudyDurationWheels>(find.byType(StudyDurationWheels))
          .hours,
      5,
    );
    await tester.tap(find.text('示例'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<StudyDurationWheels>(find.byType(StudyDurationWheels))
          .hours,
      0,
    );
    expect(
      tester.getCenter(find.byKey(const Key('study-start'))).dx,
      closeTo(tester.getSize(find.byType(Scaffold)).width / 2, 1),
    );
    await expectLater(db.addPreset('a', 21600, '超过上限'), throwsArgumentError);
    await tester.tap(find.byKey(const Key('study-start')));
    await settle(tester);
    expect(find.text('00:40:00'), findsOneWidget);
    time = time.add(const Duration(minutes: 40, seconds: 3));
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(find.byKey(const Key('study-start')), findsOneWidget);
    expect(balance, 110);
    final saved = await tester.runAsync(() => db.sessions('a'));
    expect(saved!.single.elapsed, const Duration(minutes: 40));
    expect(saved.single.state, StudySessionState.synced);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('pause does not reset the six-hour limit for one run', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    var time = DateTime.utc(2026, 9, 26, 1);
    Future<StudySnapshot> exchange(StudySession? session) async =>
        StudySnapshot(
          IdentityWallet(ownerId: 'a', miaoCoins: 30, eaglePounds: 0, gems: 0),
          const {},
        );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudyPage(
            ownerId: 'a',
            onWallet: (_) {},
            databaseFactory: () => db,
            now: () => time,
            exchange: exchange,
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.byKey(const Key('study-start')));
    await settle(tester);
    time = time.add(const Duration(hours: 5));
    await tester.tap(find.byKey(const Key('study-pause-resume')));
    await settle(tester);
    time = time.add(const Duration(minutes: 10));
    await tester.tap(find.byKey(const Key('study-pause-resume')));
    await settle(tester);
    time = time.add(const Duration(hours: 1, seconds: 5));
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(find.byKey(const Key('study-start')), findsOneWidget);
    final saved = await tester.runAsync(() => db.sessions('a'));
    expect(
      saved!.fold<int>(0, (sum, record) => sum + record.elapsed.inMilliseconds),
      const Duration(hours: 6).inMilliseconds,
    );
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('preset can be named, edited and deleted without reseeding', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    final time = DateTime.utc(2026, 9, 26, 1);
    Future<StudySnapshot> exchange(StudySession? session) async =>
        StudySnapshot(
          IdentityWallet(ownerId: 'a', miaoCoins: 30, eaglePounds: 0, gems: 0),
          const {},
        );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StudyPage(
            ownerId: 'a',
            onWallet: (_) {},
            databaseFactory: () => db,
            now: () => time,
            exchange: exchange,
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('倒计时'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(find.text('添加常用计时器'), findsOneWidget);
    final minutesPicker = tester.widget<CupertinoPicker>(
      find.byKey(const Key('study-minutes-wheel')),
    );
    await tester.drag(
      find.byKey(const Key('study-minutes-wheel')),
      const Offset(0, -58),
    );
    await tester.pumpAndSettle();
    expect(minutesPicker.scrollController!.selectedItem, isNot(40));
    await tester.enterText(find.byType(TextField), '阅读');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存常用计时器'))
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存常用计时器'));
    await settle(tester);
    expect(find.text('添加常用计时器'), findsNothing);
    final savedPresets = (await tester.runAsync(() => db.presets('a')))!;
    expect(
      savedPresets.any((preset) => preset.name == '阅读'),
      isTrue,
      reason: savedPresets
          .map((preset) => '${preset.name}:${preset.seconds}')
          .join(', '),
    );
    final added = savedPresets.singleWhere((preset) => preset.name == '阅读');
    expect(added.seconds, isNot(2400));
    await tester.tap(find.byKey(const Key('study-more')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑常用计时器'));
    await tester.pumpAndSettle();
    expect(find.text('阅读'), findsOneWidget);
    expect(find.text(formatStudySeconds(added.seconds)), findsOneWidget);
    await tester.tap(find.byKey(const Key('delete-preset-2400')));
    await tester.pumpAndSettle();
    expect(find.text('阅读'), findsOneWidget);
    await tester.tap(find.byKey(Key('delete-preset-${added.seconds}')));
    await tester.pumpAndSettle();
    expect(find.text('还没有常用计时器'), findsOneWidget);
    await tester.pageBack();
    await settle(tester);
    expect(find.text('还没有常用计时器'), findsOneWidget);
    expect(await tester.runAsync(() => db.presets('a')), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
