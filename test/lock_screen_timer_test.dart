import 'package:cat_library_demo/core/storage/probe_database.dart';
import 'package:cat_library_demo/features/study/lock_screen_timer.dart';
import 'package:cat_library_demo/features/study/timer_probe.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final allowed in [true, false]) {
    testWidgets(
      'notification permission $allowed keeps study start and stop usable',
      (tester) async {
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(LockScreenTimer.channel, (call) async {
              calls.add(call);
              return call.method == 'requestPermission' ? allowed : true;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(LockScreenTimer.channel, null);
        });
        final db = ProbeDatabase(NativeDatabase.memory());
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: TimerProbe(databaseFactory: () => db)),
          ),
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        expect(
          calls.any((c) => c.method == 'stop'),
          isTrue,
          reason: 'Cold recovery clears an old timer notification',
        );
        calls.clear();
        await tester.tap(find.text('开始计时'));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        expect(find.text('结束计时'), findsOneWidget);
        expect(calls.where((c) => c.method == 'requestPermission').length, 1);
        expect(calls.where((c) => c.method == 'show').length, allowed ? 1 : 0);
        if (allowed) {
          final shown = calls.singleWhere((c) => c.method == 'show');
          expect((shown.arguments as Map)['startedAt'], isA<int>());
        }
        calls.clear();
        await tester.tap(find.text('结束计时'));
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        expect(calls.any((c) => c.method == 'stop'), isTrue);
        expect(find.text('确认探针记录'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }
}
