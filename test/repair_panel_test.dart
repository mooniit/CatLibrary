import 'dart:async';

import 'package:cat_library_demo/features/repair/repair_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('failed first read shows an actionable retry, then clears', (
    tester,
  ) async {
    var offline = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepairPanel(
            ownerId: 'A',
            load: () async {
              if (offline) throw StateError('offline');
              return {'status': 'none'};
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('修缮状态暂未同步'), findsOneWidget);
    offline = false;
    await tester.tap(find.byTooltip('重新核对修缮状态'));
    await tester.pump();
    await tester.pump();
    expect(find.text('修缮状态暂未同步'), findsNothing);
    expect(find.byKey(const Key('repair-panel')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('owner change clears old progress and rejects a late old read', (
    tester,
  ) async {
    final oldRead = Completer<Map<String, dynamic>>();
    Widget panel(String owner, Future<Map<String, dynamic>> Function() load) =>
        MaterialApp(
          home: Scaffold(
            body: RepairPanel(ownerId: owner, load: load),
          ),
        );
    await tester.pumpWidget(panel('A', () => oldRead.future));
    await tester.pump();
    await tester.pumpWidget(panel('B', () async => {'status': 'none'}));
    await tester.pump();
    oldRead.complete({
      'status': 'active',
      'cycle_no': 8,
      'ends_at': DateTime.now()
          .add(const Duration(hours: 72))
          .toIso8601String(),
      'progress_ms': 3600000,
      'target_ms': 7200000,
    });
    await tester.pump();
    await tester.pump();
    expect(find.text('小屋修缮中'), findsNothing);
    expect(find.byKey(const Key('repair-panel')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed reread retains confirmed progress with stale notice', (
    tester,
  ) async {
    var offline = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepairPanel(
            ownerId: 'A',
            load: () async {
              if (offline) throw StateError('offline');
              return {
                'status': 'active',
                'cycle_no': 2,
                'ends_at': DateTime.now()
                    .add(const Duration(hours: 72))
                    .toIso8601String(),
                'progress_ms': 3600000,
                'target_ms': 7200000,
              };
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    offline = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();
    expect(find.text('共同计时 60 / 120 分钟'), findsOneWidget);
    expect(find.text('暂未同步，保留上次确认的进度'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('unknown service state is not presented as completed repair', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepairPanel(
            ownerId: 'A',
            load: () async => {'status': 'unexpected'},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('小屋修缮完成'), findsNothing);
    expect(find.text('修缮状态暂未同步'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('expired grace does not leave a permanent repair banner', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepairPanel(
            ownerId: 'A',
            load: () async => {'status': 'none', 'grace_through': '2020-01-01'},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('repair-panel')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('completed repair shows shared grace day', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepairPanel(
            ownerId: 'A',
            load: () async => {
              'status': 'completed',
              'grace_through': '2026-09-28',
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('小屋修缮完成'), findsOneWidget);
    expect(find.textContaining('免缴至 2026-09-28'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('shared repair progress and remaining time are visible', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepairPanel(
            ownerId: 'A',
            load: () async => {
              'status': 'active',
              'cycle_no': 2,
              'ends_at': DateTime.now()
                  .add(const Duration(hours: 72))
                  .toIso8601String(),
              'progress_ms': 3600000,
              'target_ms': 7200000,
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('小屋修缮中'), findsOneWidget);
    expect(find.text('共同计时 60 / 120 分钟'), findsOneWidget);
    expect(find.textContaining('第 2 轮 · 剩余'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
