import 'package:cat_library_demo/features/repair/repair_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RepairPanel(
          ownerId: 'A',
          load: () async => {
            'status': 'completed',
            'grace_through': '2026-09-28',
          },
        ),
      ),
    ));
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
