import 'dart:io';

import 'package:cat_library_demo/core/storage/probe_database.dart';
import 'package:cat_library_demo/core/time/study_clock.dart';
import 'package:cat_library_demo/features/study/timer_probe.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:cat_library_demo/features/study/lock_screen_timer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('aborted SQLite update preserves durable time after reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'catlibrary_abort_',
    );
    final file = File('${directory.path}/probe.sqlite');
    var db = ProbeDatabase(NativeDatabase(file));
    try {
      final start = DateTime.utc(2026, 9, 21, 15, 59);
      final clock = StudyClock(start)
        ..checkpoint(start.add(const Duration(seconds: 30)));
      final durable = clock.toJson();
      await db.saveCheckpoint(durable);
      await db.customStatement('''
        CREATE TRIGGER fail_checkpoint AFTER UPDATE ON probe_records
        BEGIN SELECT RAISE(ABORT, 'injected checkpoint failure'); END
      ''');
      clock.checkpoint(start.add(const Duration(minutes: 2)));
      await expectLater(db.saveCheckpoint(clock.toJson()), throwsException);
      expect(await db.readCheckpoint(), durable);
      await db.close();
      db = ProbeDatabase(NativeDatabase(file));
      final recovered = StudyClock.restore((await db.readCheckpoint())!);
      recovered.checkpoint(start.add(const Duration(hours: 5)));
      expect(recovered.elapsed, const Duration(seconds: 30));
      expect(recovered.running, isFalse);
      expect(recovered.secondsByDay, {'2026-09-21': 30});
      await db.customStatement('DROP TRIGGER fail_checkpoint');
      await db.saveCheckpoint(clock.toJson());
      expect(
        StudyClock.restore((await db.readCheckpoint())!).elapsed,
        const Duration(minutes: 2),
      );
    } finally {
      await db.close();
      for (final entry in directory.listSync()) {
        await entry.delete();
      }
      await directory.delete();
    }
  });

  testWidgets(
    'failed start stops visibly and retry stays pending confirmation',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            LockScreenTimer.channel,
            (_) async => false,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(LockScreenTimer.channel, null),
      );
      final db = ProbeDatabase(NativeDatabase.memory());
      await tester.runAsync(() async {
        await db.readCheckpoint();
        await db.customStatement('''
        CREATE TRIGGER fail_checkpoint BEFORE INSERT ON probe_records
        BEGIN SELECT RAISE(ABORT, 'injected checkpoint failure'); END
      ''');
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TimerProbe(databaseFactory: () => db)),
        ),
      );
      Future<void> settleStorage() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
      }

      await settleStorage();
      await tester.tap(find.text('开始计时'));
      await settleStorage();
      expect(find.text('检查点写入失败，计时已停止。请重试保存。'), findsOneWidget);
      expect(find.text('计时中'), findsNothing);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
      await tester.runAsync(() async {
        expect(await db.readCheckpoint(), isNull);
        await db.customStatement('DROP TRIGGER fail_checkpoint');
      });
      await tester.tap(find.text('重试保存检查点'));
      await settleStorage();
      expect(find.text('计时中'), findsNothing);
      expect(find.text('已停止，等待核对'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNotNull,
      );
      await tester.runAsync(() async {
        expect(
          StudyClock.restore((await db.readCheckpoint())!).running,
          isFalse,
        );
      });
      await tester.pumpWidget(const SizedBox());
      await settleStorage();
    },
  );
}
