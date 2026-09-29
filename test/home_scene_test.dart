import 'package:cat_library_demo/features/home/home_page.dart';
import 'package:cat_library_demo/features/identity/identity_repository.dart';
import 'package:cat_library_demo/features/room/room_scene.dart';
import 'package:cat_library_demo/room_layout.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('camera zoom keeps focal ground point and has bounded pan/reset', () {
    final scene = RoomScene(RoomLayout())..onGameResize(Vector2(390, 740));
    const focal = Offset(180, 390);
    final before = (focal - scene.origin) / scene.displayScale;
    scene.moveView(1.2, focal, Offset.zero);
    final after = (focal - scene.origin) / scene.displayScale;
    expect((before - after).distance, lessThan(0.001));
    final grid = scene.gridDelta(Offset(50, 33) * scene.displayScale);
    expect(grid.x, closeTo(1, 0.001));
    expect(grid.y, closeTo(0, 0.001));
    scene.moveView(100, focal, const Offset(90000, 90000));
    expect(scene.zoom, 1.6);
    expect(scene.pan.distance, lessThan(1000));
    scene.resetView();
    expect(scene.zoom, 1);
    expect(scene.pan, Offset.zero);
  });

  testWidgets('room drag keeps controls fixed and furniture edits cancel', (
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
    final saved = home.layout.saved;
    final buttonPosition = tester.getCenter(find.byTooltip('设置'));
    final actionsPosition = tester.getCenter(
      find.byKey(const Key('room-actions')),
    );
    await tester.dragFrom(const Offset(160, 380), const Offset(55, 40));
    await tester.pump(const Duration(milliseconds: 350));
    expect(home.scene.pan.distance, greaterThan(20));
    expect(home.layout.saved, saved);
    expect(tester.getCenter(find.byTooltip('设置')), buttonPosition);
    expect(
      tester.getCenter(find.byKey(const Key('room-actions'))),
      actionsPosition,
    );
    expect(find.text('布置猫窝'), findsNothing);
    expect(find.text('相册'), findsNothing);
    await tester.tap(find.byTooltip('回到初始视角'));
    await tester.pump();
    expect(home.scene.pan, Offset.zero);
    await tester.tap(find.byTooltip('布置猫窝'));
    await tester.pump();
    await tester.tap(find.byTooltip('移动 1,0'));
    await tester.pump();
    expect(home.layout.draft, isNot(saved));
    expect(home.layout.saved, saved);
    await tester.tap(find.text('取消'));
    await tester.pump();
    expect(home.layout.draft, saved);
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
