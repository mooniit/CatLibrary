import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/features/identity/bootstrap_page.dart';
import 'package:cat_library_demo/features/identity/identity_repository.dart';

void main() {
  testWidgets('automatic startup retries failure and renders server wallet', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: BootstrapPage(
          initialize: () async {
            calls++;
            if (calls == 1) throw Exception('offline');
            return const IdentityWallet(
              ownerId: 'user-a',
              miaoCoins: 17,
              eaglePounds: 2,
              gems: 3,
            );
          },
          builder: (wallet) => Text(
            '余额 ${wallet.miaoCoins}/${wallet.eaglePounds}/${wallet.gems}',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('连接失败，请检查网络后重试。'), findsOneWidget);
    expect(find.textContaining('余额'), findsNothing);
    await tester.tap(find.text('重试连接'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('余额 17/2/3'), findsOneWidget);
    await tester.pump();
    expect(calls, 2);
  });
}
