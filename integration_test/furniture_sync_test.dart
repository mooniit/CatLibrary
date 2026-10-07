import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/game.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/shop/shop_repository.dart';
import 'package:cat_library_demo/features/identity/identity_repository.dart';
import 'package:cat_library_demo/features/home/home_page.dart';
import 'package:cat_library_demo/features/room/layout_draft.dart';
import 'package:cat_library_demo/features/room/room_scene.dart';
import 'package:cat_library_demo/features/room/furniture_catalog_widgets.dart';
import 'package:cat_library_demo/app/app_theme.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'two isolated members purchase, draft, save, notice and manually refresh',
    (tester) async {
      const url = String.fromEnvironment('SUPABASE_URL'),
          key = String.fromEnvironment('SUPABASE_ANON_KEY');
      const sku = String.fromEnvironment('M5_TEST_SKU');
      expect(sku, startsWith('m5-test-chair-'));
      final a = SupabaseClient(url, key), b = SupabaseClient(url, key);
      await a.auth.setSession(const String.fromEnvironment('M5_A_REFRESH'));
      await b.auth.setSession(const String.fromEnvironment('M5_B_REFRESH'));
      final db = AppDatabase(NativeDatabase.memory());
      bool dropSave = false, offline = false;
      final repoA = ShopRepository(
        db,
        a.auth.currentUser!.id,
        rpc: (m, p) async {
          if (offline) throw const SocketException('isolated test offline');
          final value = Map<String, dynamic>.from(
            await a.rpc(m, params: p) as Map,
          );
          if (m == 'save_room_layout' && dropSave) {
            dropSave = false;
            offline = true;
            throw TimeoutException('save committed; receipt dropped');
          }
          return value;
        },
      );
      final repoB = ShopRepository(
        db,
        b.auth.currentUser!.id,
        rpc: (m, p) async =>
            Map<String, dynamic>.from(await b.rpc(m, params: p) as Map),
      );
      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 50; i++) {
          await tester.pump(const Duration(milliseconds: 200));
          if (finder.evaluate().isNotEmpty) return;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        expect(finder, findsWidgets);
      }

      Future<void> tap(Finder finder) async {
        await waitFor(finder);
        await tester.ensureVisible(finder.first);
        await tester.tap(finder.first);
        await tester.pump(const Duration(milliseconds: 500));
      }

      GlobalKey<HomePageState>? shopHost;

      Future<void> showShop(
        ShopRepository repo, {
        Brightness brightness = Brightness.light,
      }) async {
        final s = await repo.load();
        final hostKey = GlobalKey<HomePageState>();
        shopHost = hostKey;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness),
            home: Scaffold(
              body: HomePage(
                key: hostKey,
                onStudy: () {},
                shopRepository: repo,
                loadRoom: repo.load,
                loadCats: () async => {
                  'family_id': s.familyId,
                  'cats': <dynamic>[],
                },
                wallet: IdentityWallet.fromJson(
                  Map<String, dynamic>.from(s.raw['wallet']),
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 1));
        final sameScene = hostKey.currentState!.scene;
        sameScene.pan = const Offset(10, 8);
        sameScene.zoom = 1.1;
        final sameGameState = tester.state(
          find.byWidgetPredicate((w) => w is GameWidget).first,
        );
        final walletRect = tester.getRect(
          find.byKey(const Key('persistent-home-wallet')),
        );
        final menuRect = tester.getRect(
          find.byKey(const Key('persistent-home-menu')),
        );
        await hostKey.currentState!.openStore();
        await tester.pump(const Duration(seconds: 1));
        expect(
          tester.getRect(find.byKey(const Key('persistent-home-wallet'))),
          walletRect,
        );
        expect(
          tester.getRect(find.byKey(const Key('persistent-home-menu'))),
          menuRect,
        );
        expect(
          identical(
            tester
                .widget<GameWidget>(
                  find.byWidgetPredicate((w) => w is GameWidget).first,
                )
                .game,
            sameScene,
          ),
          isTrue,
        );
        expect(
          identical(
            tester.state(find.byWidgetPredicate((w) => w is GameWidget).first),
            sameGameState,
          ),
          isTrue,
          reason:
              'opening shop must move the existing home viewport, not recreate it',
        );
        await waitFor(find.byKey(const Key('shop-goods')));
        for (var i = 0; i < 50 && !sameScene.geometryReady; i++) {
          await tester.pump(const Duration(milliseconds: 200));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(sameScene.geometryReady, isTrue);
        await tester.pump(const Duration(milliseconds: 500));
        expect(sameScene.displayScale, greaterThan(0.1));
        await tap(find.byKey(const Key('category-furniture')));
        final target = find.byKey(ValueKey('product-$sku'));
        for (var i = 0; i < 20 && target.evaluate().isEmpty; i++) {
          await tester.drag(
            find.byKey(const Key('shop-goods')),
            const Offset(0, -400),
          );
          await tester.pump(const Duration(milliseconds: 300));
        }
        await waitFor(target);
      }

      Future<void> shot(String name) async {
        await tester.pump(const Duration(milliseconds: 500));
        await binding.takeScreenshot(
          name.replaceFirst('m5-native-', 'm5-artwork-'),
        );
      }

      Future<void> revealProduct(String targetSku) async {
        final scrollable = find
            .descendant(
              of: find.byKey(const Key('shop-goods')),
              matching: find.byType(Scrollable),
            )
            .first;
        tester.state<ScrollableState>(scrollable).position.jumpTo(0);
        await tester.pump(const Duration(milliseconds: 200));
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('product-$targetSku')),
          160,
          scrollable: find
              .descendant(
                of: find.byKey(const Key('shop-goods')),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.pump(const Duration(milliseconds: 300));
      }

      try {
        await binding.convertFlutterSurfaceToImage();
        await showShop(repoA, brightness: Brightness.dark);
        expect(
          tester
              .widget<Material>(find.byKey(const Key('room-tools-shelf')))
              .color,
          buildAppTheme(
            Brightness.dark,
          ).colorScheme.surface.withValues(alpha: .96),
        );
        await tap(find.byKey(ValueKey('product-$sku')));
        await tap(find.byKey(const Key('product-preview')));
        await waitFor(find.byTooltip('结束预览'));
        await shot('m5-native-night-preview');
        await showShop(repoA);
        await shot('m5-native-basic-shell');
        for (final kind in ['floor', 'wall']) {
          await tap(find.byKey(const Key('category-renovation')));
          await revealProduct('wood-$kind');
          await tap(find.byKey(ValueKey('product-wood-$kind')));
          await tap(find.byKey(const Key('product-preview')));
          await waitFor(find.byTooltip('结束预览'));
          final previewScene = shopHost!.currentState!.scene;
          final instance = previewScene.ghostItem!;
          expect(
            previewScene.roomState!.layout.items
                .where((i) => i.slot == kind)
                .single
                .instanceId,
            instance.instanceId,
          );
          expect(
            previewScene
                .roomState!
                .products[previewScene.roomState!.inventory
                    .firstWhere((i) => i.id == instance.instanceId)
                    .sku]!
                .theme,
            'wood',
          );
          await shot('m5-native-wood-$kind-preview');
          await tap(find.byTooltip('结束预览'));
          expect(previewScene.roomState!.layout.items, isEmpty);
        }
        await tap(find.byKey(const Key('category-windows')));
        for (final target in ['lunar-painting-pearl', 'wood-window']) {
          await revealProduct(target);
          await tap(find.byKey(ValueKey('product-$target')));
          await tap(find.byKey(const Key('product-preview')));
          await waitFor(find.byTooltip('切换挂位'));
          final scene = shopHost!.currentState!.scene;
          final first = scene.ghostItem!.slot;
          final origin = scene.origin;
          expect(find.byType(DropdownButton<String>), findsNothing);
          for (var i = 0; i < (target.contains('painting') ? 4 : 2); i++) {
            await tap(find.byTooltip('切换挂位'));
            expect(
              scene.origin,
              origin,
              reason: 'slot cycling must not reset view',
            );
          }
          expect(scene.ghostItem!.slot, first);
          await shot('m5-native-$target-preview');
          await tap(find.byTooltip('结束预览'));
        }
        await tap(find.byKey(const Key('category-furniture')));
        await revealProduct(sku);
        await tester.drag(
          find.byType(FurnitureCategories),
          const Offset(320, 0),
        );
        await tester.pump(const Duration(milliseconds: 500));
        await tap(find.byKey(const Key('category-all')));
        await shot('m5-native-catalog-four-columns');
        await tap(find.byKey(const Key('category-furniture')));
        await tap(find.byKey(const Key('wallet-card-0')));
        await waitFor(find.byKey(const Key('exchange-quantity')));
        await tester.enterText(find.byKey(const Key('exchange-quantity')), '3');
        await tester.pump();
        expect(find.text('获得 15 喵喵币'), findsOneWidget);
        await shot('m5-native-exchange');
        await tap(find.byKey(const Key('exchange-submit')));
        await waitFor(find.text('兑换成功，15 喵喵币已入账。'));
        expect((await repoA.load()).raw['wallet']['gems'], 9);
        await tap(find.text('关闭'));
        await tap(find.byKey(ValueKey('product-$sku')));
        await shot('m5-native-product-multiple');
        await tap(find.byKey(const Key('product-preview')));
        await waitFor(find.byTooltip('结束预览'));
        await tester.pump(const Duration(seconds: 2));
        final shopRoom = find.byKey(const Key('room-viewport'));
        final shopScene =
            tester
                    .widget<GameWidget>(
                      find
                          .descendant(
                            of: shopRoom,
                            matching: find.byWidgetPredicate(
                              (w) => w is GameWidget,
                            ),
                          )
                          .first,
                    )
                    .game
                as RoomScene;
        final originalLayout = shopScene.roomState!.layout;
        final trial = shopScene.ghostItem!;
        final shelf = find.byKey(const Key('room-tools-shelf'));
        final shelfColor = tester.widget<Material>(shelf).color!;
        expect(
          shelfColor,
          buildAppTheme(
            Brightness.light,
          ).colorScheme.surface.withValues(alpha: .96),
        );
        expect(shelfColor.a, greaterThan(.85));
        expect(shelfColor.a, lessThan(.98));
        expect(
          shopScene.artboard.width * shopScene.displayScale,
          greaterThan(tester.getSize(shopRoom).width * .90),
        );
        expect(
          tester.getTopLeft(shopRoom).dy +
              shopScene.origin.dy +
              shopScene.artboard.height * shopScene.displayScale,
          greaterThan(tester.getTopLeft(shelf).dy),
        );
        expect(find.byTooltip('商品详情'), findsNothing);
        final globalGhost = shopScene.ghostBounds!.shift(
          tester.getTopLeft(shopRoom),
        );
        expect(globalGhost.bottom, lessThan(tester.getTopLeft(shelf).dy - 16));
        expect(
          globalGhost.top,
          greaterThanOrEqualTo(tester.getTopLeft(shopRoom).dy + 79),
        );
        final rotateRect = tester.getRect(find.byTooltip('切换朝向'));
        final cancelRect = tester.getRect(find.byTooltip('结束预览'));
        for (final rect in [rotateRect, cancelRect]) {
          expect(rect.width, closeTo(48, 1e-8));
          expect(rect.height, closeTo(48, 1e-8));
        }
        expect(
          tester.getSize(find.byKey(const ValueKey('preview-glyph-切换朝向'))),
          const Size(22, 22),
        );
        expect(
          tester.getSize(find.byKey(const ValueKey('preview-glyph-结束预览'))),
          const Size(22, 22),
        );
        expect(rotateRect.center.dx, lessThan(globalGhost.center.dx));
        expect(rotateRect.center.dy, greaterThan(globalGhost.center.dy));
        expect(cancelRect.center.dx, greaterThan(globalGhost.center.dx));
        expect(cancelRect.center.dy, lessThan(globalGhost.center.dy));
        final shopStart =
            tester.getTopLeft(shopRoom) +
            shopScene.origin +
            shopScene.projectWorld(
                  (trial.gx + .5) / 8,
                  (trial.gy + .5) / 8,
                  .08,
                ) *
                shopScene.displayScale;
        await tester.tapAt(shopStart);
        await waitFor(find.byTooltip('关闭详情'));
        await shot('m5-native-preview-tapped-detail');
        await tap(find.byTooltip('关闭详情'));
        final shopDrag = await tester.startGesture(shopStart);
        await shopDrag.moveBy(const Offset(25, 10));
        await shopDrag.moveBy(const Offset(15, 0));
        await shopDrag.up();
        await tester.pump(const Duration(milliseconds: 500));
        expect(shopScene.ghostItem!.gx, isNot(trial.gx));
        expect(tester.getRect(find.byTooltip('切换朝向')), isNot(rotateRect));
        expect(identical(shopScene.roomState!.layout, originalLayout), isTrue);
        final facing = shopScene.ghostItem!.facing;
        await tap(find.byTooltip('切换朝向'));
        expect(shopScene.ghostItem!.facing, isNot(facing));
        final viewBeforePan = shopScene.origin;
        await tester.dragFrom(
          tester.getTopLeft(shopRoom) + const Offset(24, 110),
          const Offset(40, -25),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          shopScene.origin,
          isNot(viewBeforePan),
          reason: 'empty room space must pan freely',
        );
        final freeView = shopScene.origin;
        await tap(find.byTooltip('切换朝向'));
        expect(
          shopScene.origin,
          freeView,
          reason: 'rotation must retain user view',
        );
        expect((await repoA.load()).inventory, isEmpty);
        expect((await repoA.load()).layout.items, isEmpty);
        await shot('m5-native-shop-preview');
        await tap(find.byTooltip('结束预览'));
        expect(shopScene.ghostItem, isNull);
        await tap(find.byKey(ValueKey('product-$sku')));
        await tap(find.byKey(ValueKey('buy-$sku')));
        await tap(find.text('确认购买'));
        await waitFor(find.text('购买成功，物件已进入家庭库存'));
        await shot('m5-native-shop');
        final home = (await repoA.load()).familyId!;
        expect((await repoA.load()).inventory.length, 1);
        await showShop(repoB);
        await tap(find.byKey(ValueKey('product-$sku')));
        await tap(find.byKey(ValueKey('buy-$sku')));
        await tap(find.text('确认购买'));
        await waitFor(find.text('购买成功，物件已进入家庭库存'));
        expect((await repoB.load()).inventory.length, 2);
        await revealProduct('wood-chair');
        await tap(find.byKey(const ValueKey('product-wood-chair')));
        expect(find.byKey(const Key('purchase-quantity')), findsNothing);
        await shot('m5-native-product-unique');
        await tap(find.byKey(const ValueKey('buy-wood-chair')));
        await tap(find.text('确认购买'));
        await waitFor(find.text('购买成功，物件已进入家庭库存'));
        expect((await repoB.load()).inventory.length, 3);
        await showShop(repoA);
        await revealProduct('wood-chair');
        await tap(find.byKey(const ValueKey('product-wood-chair')));
        expect(find.text('已拥有 1/1'), findsWidgets);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('buy-wood-chair')),
              )
              .onPressed,
          isNull,
        );
        await shot('m5-native-owned-unique');
        await tap(find.byTooltip('关闭详情'));
        final sameSceneBeforeEdit = tester
            .widget<GameWidget>(
              find.byWidgetPredicate((w) => w is GameWidget).first,
            )
            .game;
        expect(find.text('布置小屋'), findsNothing);
        await tap(find.byTooltip('打开功能菜单'));
        await tap(find.text('布置'));
        await waitFor(find.byKey(const Key('editor-inventory')));
        await waitFor(find.byTooltip('草稿基于版本 0 · 最新家庭版本 0'));
        await waitFor(
          find.byWidgetPredicate(
            (w) =>
                w is IconButton && w.tooltip == '保存到家庭' && w.onPressed != null,
          ),
        );
        expect(
          identical(
            tester
                .widget<GameWidget>(
                  find.byWidgetPredicate((w) => w is GameWidget).first,
                )
                .game,
            sameSceneBeforeEdit,
          ),
          isTrue,
        );
        expect(find.byKey(const ValueKey('product-royal-chair')), findsNothing);
        await shot('m5-native-editor-inventory');
        await tap(find.byKey(ValueKey('product-$sku')));
        await tap(find.textContaining('库存 ·').first);
        await waitFor(find.byTooltip('切换朝向'));
        await tester.pump(const Duration(seconds: 2));
        final roomFinder = find.byKey(const Key('room-viewport'));
        final scene =
            tester
                    .widget<GameWidget>(
                      find
                          .descendant(
                            of: roomFinder,
                            matching: find.byWidgetPredicate(
                              (widget) => widget is GameWidget,
                            ),
                          )
                          .first,
                    )
                    .game
                as RoomScene;
        final start =
            tester.getTopLeft(roomFinder) +
            scene.origin +
            scene.projectWorld(.0625, .0625, .08) * scene.displayScale;
        final gesture = await tester.startGesture(start);
        await gesture.moveBy(const Offset(25, 20));
        await gesture.moveBy(const Offset(10, 0));
        await gesture.up();
        await tester.pump(const Duration(milliseconds: 500));
        await tap(find.byTooltip('切换朝向'));
        await tap(find.byTooltip('确认'));
        expect(
          (await repoA.draft(home))!.layout.items.single.gx,
          greaterThan(0),
          reason: 'touching the chair must move its authoritative anchor',
        );
        expect(
          (await repoA.load()).version,
          0,
          reason: 'single-item confirm must not save the family',
        );
        expect((await repoA.draft(home))!.layout.items.length, 1);
        await shot('m5-native-draft');
        // Releasing only the test lease and rebuilding the page preserves its local draft.
        final busy = await repoB.editor('acquire', furnitureRequestId());
        expect(busy['reason'], 'editor_busy');
        dropSave = true;
        await tap(find.byTooltip('保存到家庭'));
        await waitFor(find.textContaining('保存结果待核对'));
        expect(await repoA.pending(home, 'save'), isNotNull);
        expect((await repoA.draft(home))!.layout.items.length, 1);
        await shot('m5-native-offline');
        offline = false;
        await tap(find.byTooltip('重连核对／获取编辑权'));
        await waitFor(find.byTooltip('草稿基于版本 1 · 最新家庭版本 1'));
        expect(await repoA.pending(home, 'save'), isNull);
        expect((await repoA.load()).version, 1);
        await tap(find.byTooltip('离开并保留草稿'));
        await tester.pump(const Duration(seconds: 1));
        expect(find.byKey(const Key('shop-goods')), findsNothing);
        expect(find.byKey(const Key('editor-inventory')), findsNothing);
        expect(shopHost!.currentState!.scene.pan, const Offset(10, 8));
        expect(shopHost!.currentState!.scene.zoom, 1.1);
        expect(shopHost!.currentState!.scene.fitViewport, isFalse);
        expect(shopHost!.currentState!.scene.draftLayout, isNull);
        expect(
          identical(
            tester
                .widget<GameWidget>(
                  find.byWidgetPredicate((w) => w is GameWidget).first,
                )
                .game,
            sameSceneBeforeEdit,
          ),
          isTrue,
        );
        await shot('m5-native-home-restored');
        await shopHost!.currentState!.openStore();
        await tester.pump(const Duration(seconds: 1));
        await tap(find.byKey(const Key('category-furniture')));
        await revealProduct('wood-chair');
        await tap(find.byKey(const ValueKey('product-wood-chair')));
        await tap(find.byKey(const Key('product-preview')));
        await tester.pump(const Duration(seconds: 1));
        expect(
          shopHost!.currentState!.scene.roomState!.layout.items,
          hasLength(1),
        );
        expect(shopHost!.currentState!.scene.ghostProduct!.sku, 'wood-chair');
        await shot('m5-native-ghost-over-existing');
        await revealProduct('lunar-chair');
        await tap(find.byKey(const ValueKey('product-lunar-chair')));
        await tap(find.byKey(const Key('product-preview')));
        await tester.pump();
        expect(
          shopHost!.currentState!.scene.roomState!.layout.items,
          hasLength(1),
        );
        expect(shopHost!.currentState!.scene.ghostProduct!.sku, 'lunar-chair');
        await tap(find.byTooltip('关闭商店'));
        // Home of B is loaded at v1. Partner then saves v2; the active home
        // must remain at v1 until its update notice is explicitly tapped.
        final homeKey = GlobalKey<HomePageState>();
        final wallet = IdentityWallet.fromJson(
          Map<String, dynamic>.from((await repoB.load()).raw['wallet']),
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(Brightness.light),
            home: Scaffold(
              body: HomePage(
                key: homeKey,
                wallet: wallet,
                onStudy: () {},
                loadRoom: repoB.load,
                loadCats: () async => {'family_id': home, 'cats': <dynamic>[]},
              ),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 2));
        expect(homeKey.currentState!.scene.roomState!.version, 1);
        final token = furnitureRequestId();
        await repoA.editor('acquire', token);
        final latest = await repoA.load();
        await repoA.save(
          home,
          token,
          LayoutDraft(const RoomLayout([]), latest.version),
        );
        await repoA.editor('release', token);
        await homeKey.currentState!.checkRoomUpdate();
        await tester.pump();
        expect(homeKey.currentState!.scene.roomState!.version, 1);
        await shot('m5-native-update-notice');
        await tap(find.text('家庭布局已更新，点击刷新查看'));
        for (
          var i = 0;
          i < 30 && homeKey.currentState!.scene.roomState!.version != 2;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 200));
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        expect(homeKey.currentState!.scene.roomState!.version, 2);
        expect(homeKey.currentState!.scene.roomState!.layout.items, isEmpty);
        await shot('m5-native-refreshed');
      } finally {
        await tester.pumpWidget(const SizedBox());
        await db.close();
        await a.dispose();
        await b.dispose();
      }
    },
  );
}
