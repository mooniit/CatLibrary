import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/home/home_page.dart';
import 'package:cat_library_demo/features/identity/identity_repository.dart';
import 'package:cat_library_demo/features/repair/repair_panel.dart';
import 'package:cat_library_demo/features/wallet/proxy_payment_notice.dart';
import 'package:cat_library_demo/features/shop/shop_repository.dart';

void main() {
  testWidgets('home repair reads use the same supplied member repository', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await db.close();
    });
    final methods = <String>[];
    final repo = ShopRepository(
      db,
      'A',
      rpc: (method, args) async {
        methods.add(method);
        return {'status': 'none'};
      },
    );
    final wallet = const IdentityWallet(
      ownerId: 'A',
      miaoCoins: 30,
      eaglePounds: 0,
      gems: 0,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePage(
            wallet: wallet,
            onStudy: () {},
            shopRepository: repo,
            loadProxyNotices: () async {
              methods.add('member-notices');
              return [];
            },
            acknowledgeProxyNotice: (day) async =>
                methods.add('member-ack-$day'),
            loadRoom: () async => FurnitureState.fromJson({
              'family_id': 'F',
              'products': <dynamic>[],
              'inventory': <dynamic>[],
              'layout': {'standard': 'room-standard-v1', 'items': <dynamic>[]},
              'version': 0,
            }),
            loadCats: () async => {
              'family_id': 'F',
              'cats': <dynamic>[],
              'repairing': false,
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final panel = tester.widget<RepairPanel>(find.byType(RepairPanel));
    expect(panel.load, isNotNull);
    await tester.runAsync(panel.load!);
    expect(methods, contains('repair_state'));
    final notice = tester.widget<ProxyPaymentNotice>(
      find.byType(ProxyPaymentNotice),
    );
    expect(notice.load, isNotNull);
    expect(notice.acknowledge, isNotNull);
    await tester.runAsync(notice.load!);
    await tester.runAsync(() => notice.acknowledge!('2026-10-09'));
    expect(methods, contains('member-notices'));
    expect(methods, contains('member-ack-2026-10-09'));
  });
}
