import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:cat_library_demo/features/study/lock_screen_timer.dart';
import 'package:drift/native.dart';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/study/study_page.dart';
import 'package:cat_library_demo/features/study/study_history_page.dart';
import 'package:cat_library_demo/features/study/study_cloud.dart';
import 'package:cat_library_demo/features/study/study_session.dart';
import 'package:cat_library_demo/features/identity/identity_repository.dart';

void main() {
  testWidgets(
    'normal endings auto settle the daily remainder and show record coins',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            LockScreenTimer.channel,
            (call) async => call.method == 'readCheckpoint' ? null : false,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(LockScreenTimer.channel, null),
      );
      final db = AppDatabase(NativeDatabase.memory());
      var time = DateTime.utc(2026, 9, 26, 1);
      var issued = 0;
      final confirmed = <String, StudySession>{};
      var balance = 30;
      Future<StudySnapshot> exchange(StudySession? record) async {
        if (record?.state == StudySessionState.queued) {
          confirmed[record!.id] = record;
        }
        final ms = confirmed.values.fold<int>(
          0,
          (sum, r) => sum + r.elapsed.inMilliseconds,
        );
        issued = (ms ~/ 60000 * 2).clamp(0, 120);
        return StudySnapshot(
          IdentityWallet(
            ownerId: 'a',
            miaoCoins: 30 + issued,
            eaglePounds: 0,
            gems: 0,
          ),
          {
            '2026-09-26': {'issued': issued, 'eligible_ms': ms},
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
      Future<void> settle() async {
        for (var i = 0; i < 5; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pumpAndSettle();
        }
      }

      await settle();
      for (final duration in [
        const Duration(minutes: 5, seconds: 30),
        const Duration(minutes: 5, seconds: 40),
      ]) {
        await tester.tap(find.byKey(const Key('study-start')));
        await settle();
        time = time.add(duration);
        await tester.tap(find.byKey(const Key('study-stop')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认结束'));
        await settle();
        final saved = await tester.runAsync(() => db.sessions('a'));
        expect(
          saved!.last.state,
          StudySessionState.synced,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((t) => t.data)
              .join(' | '),
        );
        if (confirmed.length == 1) expect(balance, 40);
        time = time.add(const Duration(seconds: 10));
      }
      expect(balance, 52);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('今日还可获得 98 喵喵币'), findsOneWidget);
      await tester.tap(find.byKey(const Key('study-more')));
      await tester.pumpAndSettle();
      expect(find.text('查看自习记录'), findsNothing);
      expect(find.text('编辑常用计时器'), findsOneWidget);
      final savedRecords = await tester.runAsync(() => db.sessions('a'));
      expect(savedRecords!.length, 2);
      expect(
        savedRecords.every((r) => r.state == StudySessionState.synced),
        isTrue,
      );
      await tester.pumpWidget(const SizedBox());
      await settle();
    },
  );

  testWidgets('history groups by Beijing date and hides short settled runs', (
    tester,
  ) async {
    StudySession session(
      String id,
      DateTime start,
      Duration duration,
      StudySessionState state,
    ) => StudySession(
      id: id,
      runId: id,
      ownerId: 'a',
      startedAt: start,
      recordedUntil: start.add(duration),
      state: state,
    );
    final records = [
      session(
        'short',
        DateTime.utc(2026, 9, 25, 14),
        const Duration(minutes: 5),
        StudySessionState.synced,
      ),
      session(
        'first',
        DateTime.utc(2026, 9, 25, 15),
        const Duration(minutes: 11),
        StudySessionState.synced,
      ),
      session(
        'second',
        DateTime.utc(2026, 9, 26, 1),
        const Duration(minutes: 12),
        StudySessionState.synced,
      ),
      session(
        'recover',
        DateTime.utc(2026, 9, 27, 1),
        const Duration(minutes: 3),
        StudySessionState.pendingConfirmation,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: StudyHistoryPage(
          records: records,
          onConfirmRecovered: (_) async {},
        ),
      ),
    );
    expect(find.text('2026年9月25日'), findsOneWidget);
    expect(find.text('2026年9月26日'), findsOneWidget);
    expect(find.text('2026年9月27日'), findsOneWidget);
    expect(find.text('00:05:00'), findsNothing);
    expect(find.text('00:11:00'), findsOneWidget);
    expect(find.text('00:12:00'), findsOneWidget);
    expect(find.text('00:03:00'), findsOneWidget);
    expect(find.text('核对恢复记录并入账'), findsOneWidget);
  });
}
