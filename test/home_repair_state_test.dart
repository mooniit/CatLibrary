import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/home/home_page.dart';
import 'package:cat_library_demo/features/identity/identity_repository.dart';
import 'package:cat_library_demo/features/shop/shop_repository.dart';

void main() {
  testWidgets('timed out repair reply does not later change the room', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    final key = GlobalKey<HomePageState>();
    var response = Future<Map<String, dynamic>>.value({'status': 'none'});
    final repo = ShopRepository(
      db,
      'A',
      rpc: (method, args) async {
        if (method != 'repair_state') {
          throw StateError('fixture refuses other calls');
        }
        return response;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePage(
            key: key,
            onStudy: () {},
            wallet: const IdentityWallet(
              ownerId: 'A',
              miaoCoins: 0,
              eaglePounds: 0,
              gems: 0,
            ),
            shopRepository: repo,
            loadCats: () async => {
              'family_id': 'family',
              'cats': [],
              'repairing': false,
            },
            loadRoom: () async => FurnitureState.fromJson({
              'configured': true,
              'family_id': 'family',
              'products': [],
              'inventory': [],
              'version': 0,
              'layout': {'items': []},
            }),
            loadProxyNotices: () async => [],
            acknowledgeProxyNotice: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(key.currentState!.scene.confirmedRepairing, isFalse);
    final pending = Completer<Map<String, dynamic>>();
    response = pending.future;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    expect(find.text('修缮状态暂未同步'), findsOneWidget);
    pending.complete({'status': 'active'});
    await tester.pump();
    await tester.pump();
    expect(
      key.currentState!.scene.confirmedRepairing,
      isFalse,
      reason: 'reply arrived after the displayed timeout',
    );
    await tester.pumpWidget(const SizedBox());
    await db.close();
  });
  testWidgets(
    'confirmed completion restores the room; late cats and failed repair reads cannot undo it',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final key = GlobalKey<HomePageState>();
      var status = 'active';
      var offline = false;
      var cats = Future<Map<String, dynamic>>.value({
        'family_id': 'family',
        'cats': [],
        'repairing': true,
      });
      final repo = ShopRepository(
        db,
        'A',
        rpc: (method, args) async {
          if (method != 'repair_state') {
            throw StateError('fixture refuses other calls');
          }
          if (offline) throw StateError('offline');
          return {'status': status};
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomePage(
              key: key,
              onStudy: () {},
              wallet: const IdentityWallet(
                ownerId: 'A',
                miaoCoins: 0,
                eaglePounds: 0,
                gems: 0,
              ),
              shopRepository: repo,
              loadCats: () => cats,
              loadRoom: () async => FurnitureState.fromJson({
                'configured': true,
                'family_id': 'family',
                'products': [],
                'inventory': [],
                'version': 0,
                'layout': {'items': []},
              }),
              loadProxyNotices: () async => [],
              acknowledgeProxyNotice: (_) async {},
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(key.currentState!.scene.confirmedRepairing, isTrue);
      final pending = Completer<Map<String, dynamic>>();
      cats = pending.future;
      final refresh = key.currentState!.refreshCats();
      status = 'completed';
      await tester.tap(find.byTooltip('重新核对修缮状态'));
      await tester.pump();
      await tester.pump();
      expect(find.text('小屋修缮完成'), findsOneWidget);
      expect(key.currentState!.scene.confirmedRepairing, isFalse);
      pending.complete({'family_id': 'family', 'cats': [], 'repairing': true});
      await refresh;
      await tester.pump();
      expect(
        key.currentState!.scene.confirmedRepairing,
        isFalse,
        reason: 'old cats reply reinstated damage',
      );
      offline = true;
      await tester.tap(find.byTooltip('重新核对修缮状态'));
      await tester.pump();
      await tester.pump();
      expect(key.currentState!.scene.confirmedRepairing, isFalse);
      expect(find.text('暂未同步，保留上次确认的进度'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await db.close();
    },
  );

  testWidgets(
    'late repair read cannot overwrite a newer normal cats snapshot',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final key = GlobalKey<HomePageState>();
      final oldRepair = Completer<Map<String, dynamic>>();
      final repo = ShopRepository(
        db,
        'A',
        rpc: (method, args) async {
          if (method != 'repair_state') {
            throw StateError('fixture refuses other calls');
          }
          return oldRepair.future;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomePage(
              key: key,
              onStudy: () {},
              wallet: const IdentityWallet(
                ownerId: 'A',
                miaoCoins: 0,
                eaglePounds: 0,
                gems: 0,
              ),
              shopRepository: repo,
              loadCats: () async => {
                'family_id': 'family',
                'cats': [],
                'repairing': false,
              },
              loadRoom: () async => FurnitureState.fromJson({
                'configured': true,
                'family_id': 'family',
                'products': [],
                'inventory': [],
                'version': 0,
                'layout': {'items': []},
              }),
              loadProxyNotices: () async => [],
              acknowledgeProxyNotice: (_) async {},
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await key.currentState!.refreshCats();
      await tester.pump();
      expect(key.currentState!.scene.confirmedRepairing, isFalse);
      oldRepair.complete({'status': 'active'});
      await tester.pump();
      await tester.pump();
      expect(key.currentState!.scene.confirmedRepairing, isFalse);
      await tester.pumpWidget(const SizedBox());
      await db.close();
    },
  );
}
