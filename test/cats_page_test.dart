import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/features/cats/cats_page.dart';

void main() {
  testWidgets('adoption displays server cat, owner and remaining quota', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CatsPage(
          ownerId: 'A',
          call: (action, args) async {
            if (action == 'adopt_cat') {
              expect(args, {'appearance_key': 'black_short', 'cat_name': '煤球'});
            }
            return {
              'family_id': 'home',
              'remaining': action == 'adopt_cat' ? 1 : 2,
              'cats': action == 'adopt_cat'
                  ? [
                      {
                        'id': 'cat',
                        'name': '煤球',
                        'appearance': 'black_short',
                        'owner_id': 'A',
                        'is_mine': true,
                      },
                    ]
                  : [],
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '煤球');
    await tester.ensureVisible(find.text('免费领养'));
    await tester.tap(find.text('免费领养'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 700));
    await tester.pumpAndSettle();
    expect(find.text('煤球'), findsOneWidget);
    expect(find.text('本人剩余领养名额：1'), findsOneWidget);
    expect(find.textContaining('登记主人：我'), findsOneWidget);
  });
  testWidgets('failed adoption retains input and does not invent a cat', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CatsPage(
          ownerId: 'A',
          call: (action, args) async {
            if (action == 'adopt_cat') throw Exception('offline');
            return {'family_id': 'home', 'remaining': 2, 'cats': []};
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '煤球');
    await tester.ensureVisible(find.text('免费领养'));
    await tester.tap(find.text('免费领养'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '煤球',
    );
    expect(find.text('家庭猫咪 0/4'), findsOneWidget);
    expect(find.text('连接失败，请重试；尚未确认领养成功。'), findsOneWidget);
  });
  testWidgets('no family offers join path without adopting', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CatsPage(
          ownerId: 'A',
          call: (action, args) async => {
            'family_id': null,
            'remaining': 2,
            'cats': [],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('去创建或加入小屋'), findsOneWidget);
    expect(find.text('免费领养'), findsNothing);
  });

  testWidgets(
    'feeding updates the cat and personal wallet only after server reply',
    (tester) async {
      var fed = false;
      var balance = 30;
      final walletUpdates = <int>[];
      await tester.pumpWidget(
        MaterialApp(
          home: CatsPage(
            ownerId: 'A',
            onWallet: (wallet) => walletUpdates.add(wallet.miaoCoins),
            call: (action, args) async {
              if (action == 'feed_cat') {
                expect(args, {'target_cat': 'cat'});
                fed = true;
                balance -= 15;
              }
              return {
                'family_id': 'home',
                'remaining': 1,
                'wallet': {
                  'owner_id': 'A',
                  'miao_coins': balance,
                  'eagle_pounds': 0,
                  'gems': 0,
                },
                'cats': [
                  {
                    'id': 'cat',
                    'name': '煤球',
                    'appearance': 'black_short',
                    'owner_id': 'A',
                    'is_mine': true,
                    'fed_today': fed,
                  },
                ],
                if (action == 'feed_cat') 'outcome': 'fed',
              };
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('个人余额：30 喵喵币'), findsOneWidget);
      await tester.tap(find.text('喂食 15'));
      await tester.pumpAndSettle();
      expect(find.text('个人余额：15 喵喵币'), findsOneWidget);
      expect(find.textContaining('今日已喂食'), findsWidgets);
      expect(find.text('喂食 15'), findsNothing);
      expect(walletUpdates.last, 15);
    },
  );
  testWidgets('repair state disables feeding and adoption', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CatsPage(
          ownerId: 'A',
          call: (action, args) async {
            expect(action, 'cats_state');
            return {
              'family_id': 'home',
              'repairing': true,
              'remaining': 1,
              'cats': [
                {
                  'id': 'cat',
                  'name': '煤球',
                  'appearance': 'black_short',
                  'owner_id': 'A',
                  'is_mine': true,
                  'fed_today': false,
                },
              ],
            };
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('小屋修缮中'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '喂食 15'))
          .onPressed,
      isNull,
    );
    expect(find.text('免费领养'), findsNothing);
  });
}
