import 'dart:async';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cat_library_demo/app/app_theme.dart';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/core/sync/cloud_client.dart';
import 'package:cat_library_demo/core/sync/cloud_connection.dart';
import 'package:cat_library_demo/features/home/home_page.dart';
import 'package:cat_library_demo/features/identity/identity_repository.dart';
import 'package:cat_library_demo/features/room/editor_page.dart';
import 'package:cat_library_demo/features/shop/shop_page.dart';
import 'package:cat_library_demo/features/shop/shop_repository.dart';

// Two independent hosted users and SQLite stores on one emulator. The device's
// normal preferences/database are never used, and no test prices/funds are added.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'hosted members buy, draft, reconcile lost receipts and manually refresh',
    (tester) async {
      const url = String.fromEnvironment('SUPABASE_URL'),
          key = String.fromEnvironment('SUPABASE_ANON_KEY');
      expect(
        const String.fromEnvironment('ISOLATED_HOSTED_COMMERCE') == 'true',
        isTrue,
      );
      expect(url == 'https://ludwvhsvknjgblfgouor.supabase.co', isTrue);
      SharedPreferences.setMockInitialValues({});
      final transport = ConnectionHttpClient(
        http.Client(),
        CloudClient.connection,
      );
      final clients = List.generate(
        2,
        (_) => SupabaseClient(
          url,
          key,
          httpClient: transport,
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );
      final databases = List.generate(
        2,
        (_) => AppDatabase(NativeDatabase.memory()),
      );
      final homes = List.generate(2, (_) => GlobalKey<HomePageState>());
      final calls = [<String>[], <String>[]];
      var offlineA = false, dropPurchase = true, dropSave = true;
      try {
        await clients[0].auth.setSession(
          const String.fromEnvironment('M7_A_REFRESH'),
        );
        await clients[1].auth.setSession(
          const String.fromEnvironment('M7_B_REFRESH'),
        );
        expect(
          clients[0].auth.currentUser!.id != clients[1].auth.currentUser!.id,
          isTrue,
        );
        final repositories = List.generate(
          2,
          (index) => ShopRepository(
            databases[index],
            clients[index].auth.currentUser!.id,
            rpc: (method, args) async {
              if (index == 0 && offlineA) {
                throw const SocketException('isolated member offline');
              }
              calls[index].add(method);
              final reply = Map<String, dynamic>.from(
                await clients[index].rpc(method, params: args) as Map,
              );
              if (index == 0 &&
                  ((method == 'purchase_furniture' && dropPurchase) ||
                      (method == 'save_room_layout' && dropSave))) {
                if (method == 'purchase_furniture') {
                  dropPurchase = false;
                } else {
                  dropSave = false;
                }
                offlineA = true;
                throw TimeoutException('isolated server-success receipt loss');
              }
              return reply;
            },
          ),
        );
        final initial = [
          await repositories[0].load(),
          await repositories[1].load(),
        ];
        final family = initial.first.familyId!;
        for (final state in initial) {
          expect(
            state.familyId == family && state.version == 0 && !state.testScope,
            isTrue,
          );
          expect(
            state.inventory.isEmpty && state.raw['wallet']['miao_coins'] == 30,
            isTrue,
          );
        }
        var member = 0;
        final wallets = [
          for (final state in initial)
            IdentityWallet.fromJson(
              Map<String, dynamic>.from(state.raw['wallet']),
            ),
        ];
        late void Function(int) switchMember;
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              switchMember = (next) => setState(() => member = next);
              return MaterialApp(
                theme: buildAppTheme(
                  member == 0 ? Brightness.light : Brightness.dark,
                ),
                home: Scaffold(
                  body: IndexedStack(
                    index: member,
                    children: [
                      for (var i = 0; i < 2; i++)
                        HomePage(
                          key: homes[i],
                          onStudy: () {},
                          wallet: wallets[i],
                          onWallet: (value) => wallets[i] = value,
                          shopRepository: repositories[i],
                          loadProxyNotices: () async => [
                            for (final raw
                                in await clients[i].rpc('proxy_notice_state')
                                    as List)
                              Map<String, dynamic>.from(raw as Map),
                          ],
                          acknowledgeProxyNotice: (day) async {
                            await clients[i].rpc(
                              'ack_proxy_notice',
                              params: {'target_day': day},
                            );
                          },
                          loadRoom: repositories[i].load,
                          loadCats: () =>
                              repositories[i].call('cats_state', const {}),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
        Future<void> waitUntil(bool Function() ready) async {
          for (var i = 0; i < 100; i++) {
            await tester.pump(const Duration(milliseconds: 150));
            if (ready()) return;
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          expect(
            ready(),
            isTrue,
            reason: 'Native cloud UI did not reach the expected state',
          );
        }

        Future<void> waitFor(Finder finder) =>
            waitUntil(() => finder.evaluate().isNotEmpty);
        Future<void> tap(Finder finder) async {
          await waitFor(finder);
          await tester.ensureVisible(finder.first);
          await tester.tap(finder.first);
          await tester.pump(const Duration(milliseconds: 350));
        }

        Future<void> chooseMember(int next) async {
          switchMember(next);
          await tester.pump(const Duration(milliseconds: 500));
          await waitUntil(
            () => homes[next].currentState!.scene.roomState != null,
          );
        }

        Future<void> menu(int item) async {
          await tap(find.byTooltip('打开功能菜单'));
          await tap(find.byKey(Key('home-menu-item-$item')));
        }

        Future<void> shop() async {
          await menu(1);
          await waitFor(find.byKey(const Key('shop-goods')));
          await waitUntil(
            () => !tester.state<ShopPageState>(find.byType(ShopPage)).busy,
          );
        }

        Future<void> product(String sku, {String category = 'windows'}) async {
          await waitUntil(
            () => !tester.state<ShopPageState>(find.byType(ShopPage)).busy,
          );
          await tap(find.byKey(Key('category-$category')));
          final scroll = find
              .descendant(
                of: find.byKey(const Key('shop-goods')),
                matching: find.byType(Scrollable),
              )
              .first;
          tester.state<ScrollableState>(scroll).position.jumpTo(0);
          await tester.pump();
          await tester.scrollUntilVisible(
            find.byKey(ValueKey('product-$sku')),
            150,
            scrollable: scroll,
          );
          await tap(find.byKey(ValueKey('product-$sku')));
        }

        Future<void> buy(String sku) async {
          await product(sku);
          expect(find.byKey(const Key('purchase-quantity')), findsNothing);
          await tap(find.byKey(ValueKey('buy-$sku')));
          await tap(find.text('确认购买'));
        }

        Future<void> closeShop() async {
          await waitUntil(
            () => !tester.state<ShopPageState>(find.byType(ShopPage)).busy,
          );
          await tap(find.byTooltip('关闭商店'));
          await waitUntil(() => find.byType(ShopPage).evaluate().isEmpty);
        }

        Future<void> shot(String name) async {
          await tester.pump(const Duration(milliseconds: 400));
          await binding.takeScreenshot(name);
        }

        await binding.convertFlutterSurfaceToImage();
        await chooseMember(0);
        final scene = homes[0].currentState!.scene;
        final gameState = tester.state(
          find.byWidgetPredicate((w) => w is GameWidget).first,
        );
        await shop();
        expect(identical(homes[0].currentState!.scene, scene), isTrue);
        expect(
          identical(
            tester.state(find.byWidgetPredicate((w) => w is GameWidget).first),
            gameState,
          ),
          isTrue,
        );
        await product('wood-chair', category: 'furniture');
        await tap(find.byKey(const Key('product-preview')));
        await waitUntil(() => scene.geometryReady && scene.ghostItem != null);
        final viewport = find.byKey(const Key('room-viewport'));
        final originalItem = scene.ghostItem!;
        final start =
            tester.getTopLeft(viewport) +
            scene.origin +
            scene.projectWorld(
                  (originalItem.gx + .5) / 8,
                  (originalItem.gy + .5) / 8,
                  .08,
                ) *
                scene.displayScale;
        final drag = await tester.startGesture(start);
        await drag.moveBy(const Offset(25, 10));
        await drag.moveBy(const Offset(15, 0));
        await drag.up();
        await tester.pump(const Duration(milliseconds: 350));
        expect(
          scene.ghostItem!.gx != originalItem.gx ||
              scene.ghostItem!.gy != originalItem.gy,
          isTrue,
        );
        final beforePan = scene.origin;
        await tester.dragFrom(
          tester.getTopLeft(viewport) + const Offset(24, 110),
          const Offset(40, -25),
        );
        await tester.pump(const Duration(milliseconds: 350));
        expect(scene.origin != beforePan, isTrue);
        final freeView = scene.origin, facing = scene.ghostItem!.facing;
        await tap(find.byTooltip('切换朝向'));
        expect(
          scene.ghostItem!.facing != facing && scene.origin == freeView,
          isTrue,
        );
        expect((await repositories[0].load()).inventory.isEmpty, isTrue);
        await tap(find.byTooltip('结束预览'));
        // This product costs 40; an ordinary 30-coin wallet cannot buy it.
        dropPurchase = false;
        await product('wood-chair', category: 'furniture');
        await tap(find.byKey(const ValueKey('buy-wood-chair')));
        await tap(find.text('确认购买'));
        await waitFor(find.text('余额不足，未扣款'));
        expect(
          (await repositories[0].load()).raw['wallet']['miao_coins'] == 30,
          isTrue,
        );
        dropPurchase = true;
        await buy('wood-painting-mona');
        await waitFor(find.text('核对原请求'));
        expect(
          await repositories[0].pending(family, 'purchase') != null,
          isTrue,
        );
        expect(find.text('购买成功，物件已进入家庭库存'), findsNothing);
        offlineA = false;
        await tap(find.text('核对原请求'));
        await waitFor(find.text('购买成功，物件已进入家庭库存'));
        expect(
          await repositories[0].pending(family, 'purchase') == null,
          isTrue,
        );
        expect(
          calls[0].where((m) => m == 'purchase_furniture').length,
          2,
        ); // rejected chair + one painting
        await product('wood-painting-mona');
        expect(find.text('已拥有 1/1'), findsWidgets);
        expect(
          tester
                  .widget<FilledButton>(
                    find.byKey(const ValueKey('buy-wood-painting-mona')),
                  )
                  .onPressed ==
              null,
          isTrue,
        );
        await tap(find.byTooltip('关闭详情'));
        await shot('m7-cloud-native-shop');
        await closeShop();
        await chooseMember(1);
        await shop();
        await buy('wood-painting-pearl');
        await waitFor(find.text('购买成功，物件已进入家庭库存'));
        final owned = await repositories[1].load();
        expect(
          owned.inventory.length == 2 && owned.raw['wallet']['miao_coins'] == 0,
          isTrue,
        );
        expect(
          owned.inventory
              .where((i) => i.purchasedBy == clients[0].auth.currentUser!.id)
              .length,
          1,
        );
        expect(
          owned.inventory
              .where((i) => i.purchasedBy == clients[1].auth.currentUser!.id)
              .length,
          1,
        );
        await closeShop();
        Future<void> arrange(String sku) async {
          await menu(2);
          await waitFor(find.byKey(const Key('editor-inventory')));
          await waitUntil(
            () => !tester.state<EditorPageState>(find.byType(EditorPage)).busy,
          );
          final editor = tester.state<EditorPageState>(find.byType(EditorPage));
          expect(editor.editable, isTrue, reason: editor.message);
          expect(
            find.byKey(const ValueKey('product-wood-chair')),
            findsNothing,
          );
          await tap(find.byKey(ValueKey('product-$sku')));
          await waitFor(find.byTooltip('切换挂位'));
        }

        await chooseMember(0);
        await arrange('wood-painting-mona');
        expect(identical(homes[0].currentState!.scene, scene), isTrue);
        await tap(find.byTooltip('切换挂位'));
        await tap(find.byTooltip('确认'));
        final draft = await repositories[0].draft(family);
        expect(draft!.layout.items.single.artwork, 'mona');
        expect(draft.layout.items.single.slot, 'art-left-front');
        expect((await repositories[0].load()).layout.items.isEmpty, isTrue);
        final denied = await repositories[1].editor(
          'acquire',
          furnitureRequestId(),
        );
        expect(denied['reason'], 'editor_busy');
        await tap(find.byTooltip('保存到家庭'));
        await waitFor(find.textContaining('保存结果待核对'));
        expect(await repositories[0].pending(family, 'save') != null, isTrue);
        expect((await repositories[0].draft(family))!.layout.items.length, 1);
        expect((await repositories[1].load()).version, 1);
        offlineA = false;
        await tap(find.byTooltip('重连核对／获取编辑权'));
        await waitFor(find.byTooltip('草稿基于版本 1 · 最新家庭版本 1'));
        expect(await repositories[0].pending(family, 'save') == null, isTrue);
        Future<void> leaveEditor() async {
          await waitUntil(
            () => !tester.state<EditorPageState>(find.byType(EditorPage)).busy,
          );
          await tap(find.byTooltip('离开并保留草稿'));
          await waitUntil(() => find.byType(EditorPage).evaluate().isEmpty);
          expect(
            (await repositories[member].load()).raw['lock_user'] == null,
            isTrue,
            reason: 'Normal exit must finish releasing the hosted lease',
          );
        }

        await leaveEditor();
        await chooseMember(1);
        await homes[1].currentState!.checkRoomUpdate();
        await tester.pump();
        expect(homes[1].currentState!.scene.roomState!.version, 0);
        await shot('m7-cloud-native-update');
        await tap(find.text('家庭布局已更新，点击刷新查看'));
        await waitUntil(
          () => homes[1].currentState!.scene.roomState!.version == 1,
        );
        expect(
          homes[1].currentState!.scene.roomState!.layout.items.single.artwork,
          'mona',
        );
        await arrange('wood-painting-pearl');
        await tap(find.byTooltip('确认'));
        await tap(find.byTooltip('保存到家庭'));
        await waitFor(find.text('保存成功 · 家庭版本 2'));
        await leaveEditor();
        await shot('m7-cloud-native-refreshed');
        await chooseMember(0);
        await homes[0].currentState!.checkRoomUpdate();
        await tester.pump();
        expect(homes[0].currentState!.scene.roomState!.version, 1);
        await tap(find.text('家庭布局已更新，点击刷新查看'));
        await waitUntil(
          () => homes[0].currentState!.scene.roomState!.version == 2,
        );
        final receipt = await repositories[0].pending(family, 'save_receipt');
        final old = await repositories[0].call('furniture_request', {
          'target_request': receipt!['request_id'],
        });
        expect(
          old['version'] == 1 &&
              homes[0].currentState!.scene.roomState!.version == 2,
          isTrue,
        );
        await menu(2);
        await waitFor(find.byTooltip('草稿基于版本 1 · 最新家庭版本 2'));
        expect(
          tester.state<EditorPageState>(find.byType(EditorPage)).editable,
          isFalse,
        );
        expect((await repositories[0].draft(family))!.layout.items.length, 1);
        await leaveEditor();
        binding.reportData!.addAll({
          'result': 'PASS',
          'scope':
              'one emulator, two independent hosted clients and in-memory SQLite stores',
          'productionCatalog': true,
          'extraFundsOrAssetsGranted': false,
          'previewDragAndFreePan': true,
          'insufficientBalanceDenied': true,
          'purchaseReceiptRetriedWithoutSecondPurchase': true,
          'bothMemberWallets': [0, 0],
          'householdInventoryCount': 2,
          'ownedLimitDisabled': true,
          'existingHomeScenePreserved': true,
          'ownedOnlyEditor': true,
          'fixedArtworkSlotAndFrame': true,
          'draftBeforeManualSave': true,
          'editorConflictDenied': true,
          'lostSaveReceiptReconciled': true,
          'bothMembersNotifiedAndManuallyRefreshed': true,
          'finalLayoutVersion': 2,
          'oldReceiptCannotReplaceNewLayout': true,
          'staleDraftRetainedAndPaused': true,
          'originalIdentityMigrated': false,
          'physicalPhoneVerified': false,
        });
      } finally {
        await tester.pumpWidget(const SizedBox());
        for (final db in databases) {
          await db.close();
        }
        for (final client in clients) {
          await client.dispose();
        }
        transport.close();
      }
    },
  );
}
