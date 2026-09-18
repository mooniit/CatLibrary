import 'package:cat_library_demo/core/storage/probe_database.dart';
import 'package:cat_library_demo/core/time/study_clock.dart';
import 'package:cat_library_demo/features/study/timer_probe.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('resume after cold load preserves pending recovery explanation', (
    tester,
  ) async {
    final db = ProbeDatabase(NativeDatabase.memory());
    final start = DateTime.utc(2026, 9, 18);
    final saved = StudyClock(start)
      ..checkpoint(start.add(const Duration(seconds: 26)));
    await tester.runAsync(() => db.saveCheckpoint(saved.toJson()));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TimerProbe(databaseFactory: () => db)),
      ),
    );
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pump();
    expect(find.text('恢复到最后保存点，请核对记录'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('恢复到最后保存点，请核对记录'), findsOneWidget);
    expect(find.text('00:00:26'), findsOneWidget);
    expect(find.text('确认探针记录'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
  });
}
