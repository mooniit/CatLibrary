import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/identity/identity_repository.dart';
import 'package:cat_library_demo/features/wallet/wallet_repository.dart';
import 'package:cat_library_demo/features/wallet/exchange_sheet.dart';
import 'package:cat_library_demo/features/home/home_controls.dart';

void main() {
  Map<String, dynamic> result() => {
    'wallet': {
      'owner_id': 'a',
      'miao_coins': 35,
      'gems': 5,
      'eagle_pounds': 10,
    },
  };
  test(
    'lost batch receipt retains quantity and request across reopening',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final calls = <Map<String, dynamic>>[];
      final first = WalletRepository(
        db,
        'a',
        rpc: (_, p) async {
          calls.add(p);
          throw TimeoutException('committed, receipt lost');
        },
      );
      await expectLater(
        first.exchange('gem', quantity: 7),
        throwsA(isA<TimeoutException>()),
      );
      final pending = (await first.pending())!;
      expect(pending.$3, 7);
      final reopened = WalletRepository(
        db,
        'a',
        rpc: (_, p) async {
          calls.add(p);
          return result();
        },
      );
      await expectLater(
        reopened.exchange('eagle', quantity: 7),
        throwsStateError,
      );
      await expectLater(
        reopened.exchange('gem', quantity: 1),
        throwsStateError,
      );
      expect(calls, hasLength(1));
      await reopened.exchange('gem', quantity: 7);
      expect(calls[1], calls[0]);
      expect(await reopened.pending(), isNull);
    },
  );
  testWidgets(
    'currency modal calculates typed batch and disables insufficient balance',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      Map<String, dynamic>? sent;
      final repo = WalletRepository(
        db,
        'a',
        rpc: (_, p) async {
          sent = p;
          return result();
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: ExchangeSheet(
            wallet: const IdentityWallet(
              ownerId: 'a',
              miaoCoins: 0,
              gems: 12,
              eaglePounds: 10,
            ),
            repository: repo,
            onWallet: (_) {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('exchange-quantity')), '13');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('exchange-submit')))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.byKey(const Key('exchange-quantity')), '7');
      await tester.pump();
      expect(find.text('获得 35 喵喵币'), findsOneWidget);
      await tester.tap(find.byKey(const Key('exchange-submit')));
      await tester.pumpAndSettle();
      expect(sent!['quantity'], 7);
      expect(sent!['source_currency'], 'gem');
      expect(find.text('兑换成功，35 喵喵币已入账。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('only miao card opens exchange', (tester) async {
    var opens = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeWallet(
            wallet: const IdentityWallet(
              ownerId: 'a',
              miaoCoins: 0,
              gems: 12,
              eaglePounds: 10,
            ),
            onExchange: () => opens++,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('wallet-card-1')));
    await tester.tap(find.byKey(const Key('wallet-card-2')));
    expect(opens, 0);
    await tester.tap(find.byKey(const Key('wallet-card-0')));
    expect(opens, 1);
  });
}
