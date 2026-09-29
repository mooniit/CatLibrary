import 'package:cat_library_demo/features/wallet/proxy_payment_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('payer acknowledges one combined daily notice after reading it', (
    tester,
  ) async {
    var pending = true;
    var acknowledgments = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProxyPaymentNotice(
            ownerId: 'payer',
            load: () async => pending
                ? [
                    {'day': '2026-09-02', 'paid': 40},
                  ]
                : [],
            acknowledge: (day) async {
              expect(day, '2026-09-02');
              acknowledgments++;
              pending = false;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('家庭代扣提醒'), findsOneWidget);
    expect(find.textContaining('代付 40 喵喵币'), findsOneWidget);
    expect(acknowledgments, 0);
    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(acknowledgments, 1);
    expect(find.text('家庭代扣提醒'), findsNothing);
  });
}
