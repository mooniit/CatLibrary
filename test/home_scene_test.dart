import 'package:cat_library_demo/features/home/home_page.dart';
import 'package:cat_library_demo/features/home/home_controls.dart';
import 'package:cat_library_demo/features/identity/identity_repository.dart';
import 'package:cat_library_demo/features/room/room_scene.dart';
import 'package:cat_library_demo/room_layout.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('camera zoom keeps focal ground point and has bounded pan/reset', () {
    final scene = RoomScene()..onGameResize(Vector2(390, 740));
    const focal = Offset(180, 390);
    final before = (focal - scene.origin) / scene.displayScale;
    scene.moveView(1.2, focal, Offset.zero);
    final after = (focal - scene.origin) / scene.displayScale;
    expect((before - after).distance, lessThan(0.001));
    scene.moveView(100, focal, const Offset(90000, 90000));
    expect(scene.zoom, 1.6);
    expect(scene.pan.distance, lessThan(1000));
    scene.resetView();
    expect(scene.zoom, 1);
    expect(scene.pan, Offset.zero);
  });

  testWidgets(
    'three separate balance cards fit four digits without an exchange tap',
    (tester) async {
      const wallet = IdentityWallet(
        ownerId: 'A',
        miaoCoins: 9999,
        eaglePounds: 9999,
        gems: 9999,
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(width: 320, child: HomeWallet(wallet: wallet)),
            ),
          ),
        ),
      );
      expect(find.text('9999'), findsNWidgets(3));
      for (var i = 0; i < 3; i++) {
        expect(
          tester.getSize(find.byKey(Key('wallet-card-$i'))).width,
          greaterThan(90),
        );
      }
      await tester.tap(find.byKey(const Key('wallet-card-0')));
      await tester.pump();
      expect(find.text('兑换喵喵币'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('room drag keeps cards and menu fixed; menu reveals entries', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey<HomePageState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomePage(key: key, onStudy: () {}),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    final home = key.currentState!;
    final cardPosition = tester.getCenter(
      find.byKey(const Key('wallet-card-0')),
    );
    final menuPosition = tester.getCenter(
      find.byKey(const Key('home-menu-toggle')),
    );
    await tester.dragFrom(const Offset(160, 380), const Offset(55, 40));
    await tester.pump(const Duration(milliseconds: 350));
    expect(home.scene.pan.distance, greaterThan(20));
    expect(RoomLayout.defaults['bookshelf'], const GridPoint(0.08, 3.2));
    expect(RoomLayout.defaults['bed'], const GridPoint(8.1, 8.1));
    expect(
      tester.getCenter(find.byKey(const Key('wallet-card-0'))),
      cardPosition,
    );
    expect(
      tester.getCenter(find.byKey(const Key('home-menu-toggle'))),
      menuPosition,
    );
    expect(find.text('布置猫窝'), findsNothing);
    await tester.tap(find.byTooltip('回到初始视角'));
    await tester.pump();
    expect(home.scene.pan, Offset.zero);
    await tester.tap(find.byTooltip('打开功能菜单'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byTooltip('关闭功能菜单'), findsOneWidget);
    final labels = ['猫咪管理', '商店', '相册', '设置'];
    for (var i = 0; i < labels.length; i++) {
      expect(find.text(labels[i]), findsOneWidget);
      if (i > 0) {
        expect(
          tester.getTopLeft(find.text(labels[i])).dy,
          greaterThan(tester.getTopLeft(find.text(labels[i - 1])).dy),
        );
      }
    }
    await tester.tap(find.text('商店'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('连接钱包后可兑换币种。'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'real empty home has no demo cats; refresh failure retains known cats',
    (tester) async {
      final key = GlobalKey<HomePageState>();
      var empty = true;
      var fail = false;
      const wallet = IdentityWallet(
        ownerId: 'A',
        miaoCoins: -15,
        eaglePounds: 18,
        gems: 12,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HomePage(
              key: key,
              onStudy: () {},
              wallet: wallet,
              loadCats: () async {
                if (fail) throw StateError('offline');
                return {
                  'family_id': 'home',
                  'cats': empty
                      ? []
                      : [
                          {'name': '花花', 'appearance': 'black_short'},
                        ],
                };
              },
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(key.currentState!.scene.cats, isEmpty);
      expect(find.text('认识第一只猫咪'), findsOneWidget);
      expect(find.text('喵喵币欠款 15'), findsOneWidget);
      empty = false;
      await key.currentState!.refreshCats();
      await tester.pump();
      expect(key.currentState!.scene.cats.single.name, '花花');
      fail = true;
      await key.currentState!.refreshCats();
      await tester.pump();
      expect(key.currentState!.scene.cats.single.name, '花花');
      expect(find.text('猫咪暂未同步，点击重试'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
