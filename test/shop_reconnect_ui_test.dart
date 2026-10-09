import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/identity/identity_repository.dart';
import 'package:cat_library_demo/features/room/room_scene.dart';
import 'package:cat_library_demo/features/shop/shop_page.dart';
import 'package:cat_library_demo/features/shop/shop_repository.dart';

void main() {
  testWidgets(
    'lost purchase receipt stays visible when the following state read is offline',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var offline = false, charged = 0;
      Map<String, dynamic>? receipt;
      final wallet = {
        'owner_id': 'A',
        'miao_coins': 30,
        'eagle_pounds': 0,
        'gems': 0,
      };
      final room = {
        'family_id': 'F',
        'products': <dynamic>[],
        'inventory': <dynamic>[],
        'layout': {'standard': 'room-standard-v1', 'items': <dynamic>[]},
        'version': 0,
        'wallet': wallet,
      };
      final repo = ShopRepository(
        db,
        'A',
        rpc: (method, args) async {
          if (offline) throw TimeoutException('isolated offline');
          if (method == 'furniture_state') return room;
          if (method == 'furniture_request')
            return receipt ?? {'status': 'not_found'};
          charged++;
          receipt = {
            'status': 'purchased',
            'request_id': args['request_id'],
            'family_id': 'F',
          };
          offline = true;
          throw TimeoutException('isolated lost purchase receipt');
        },
      );
      final key = GlobalKey<ShopPageState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShopPage(
              key: key,
              scene: RoomScene(),
              repository: repo,
              wallet: IdentityWallet.fromJson(wallet),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => key.currentState!.perform(
          () => repo.purchase('F', 'wood-painting-mona'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('购买结果待核对'), findsOneWidget);
      expect(find.text('核对原请求'), findsOneWidget);
      expect(await repo.pending('F', 'purchase'), isNotNull);
      offline = false;
      await tester.tap(find.text('核对原请求'));
      await tester.pumpAndSettle();
      expect(find.text('购买成功，物件已进入家庭库存'), findsOneWidget);
      expect(charged, 1);
      expect(await repo.pending('F', 'purchase'), isNull);
      expect(find.text('核对原请求'), findsNothing);
    },
  );

  testWidgets(
    'a failed cached catalog read has a retry and clears its offline message after recovery',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      var offline = true;
      final wallet = {
        'owner_id': 'A',
        'miao_coins': 30,
        'eagle_pounds': 0,
        'gems': 0,
      };
      final room = {
        'family_id': 'F',
        'products': <dynamic>[],
        'inventory': <dynamic>[],
        'layout': {'standard': 'room-standard-v1', 'items': <dynamic>[]},
        'version': 0,
        'wallet': wallet,
      };
      final repo = ShopRepository(
        db,
        'A',
        rpc: (_, _) async {
          if (offline) throw TimeoutException('isolated offline');
          return room;
        },
      );
      final key = GlobalKey<ShopPageState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShopPage(
              key: key,
              scene: RoomScene()..roomState = FurnitureState.fromJson(room),
              repository: repo,
              wallet: IdentityWallet.fromJson(wallet),
            ),
          ),
        ),
      );
      await tester.runAsync(() => key.currentState!.load());
      await tester.pumpAndSettle();
      expect(find.text('重试连接'), findsOneWidget);
      expect(find.textContaining('商店暂未连接'), findsOneWidget);
      offline = false;
      await tester.runAsync(() => key.currentState!.load());
      await tester.pumpAndSettle();
      expect(find.text('重试连接'), findsNothing);
      expect(find.textContaining('商店暂未连接'), findsNothing);
    },
  );
}
