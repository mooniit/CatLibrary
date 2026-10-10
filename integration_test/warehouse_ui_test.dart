import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:cat_library_demo/app/app_theme.dart';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/home/home_page.dart';
import 'package:cat_library_demo/features/identity/identity_repository.dart';
import 'package:cat_library_demo/features/room/editor_page.dart';
import 'package:cat_library_demo/features/room/furniture_catalog_widgets.dart';
import 'package:cat_library_demo/features/room/layout_draft.dart';
import 'package:cat_library_demo/features/shop/shop_repository.dart';
import 'package:cat_library_demo/features/tasks/task_board_page.dart';
import 'package:cat_library_demo/features/tasks/task_repository.dart';
import 'package:cat_library_demo/features/study/lock_screen_timer.dart';

// Real native Home/album/editor, isolated in memory. No account or business HTTP.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'album returns to the same room and all four fixed photo mounts',
    (tester) async {
      const run = String.fromEnvironment('WAREHOUSE_CAPTURE_RUN');
      expect(RegExp(r'^\d{15,20}$').hasMatch(run), isTrue);
      final stage = File(
        '${Directory.systemTemp.path}/warehouse_native_$run.json',
      );
      final ack = File('${stage.path}.ack');
      Future<void> capture(String name) async {
        await tester.pump(const Duration(milliseconds: 300));
        await tester.runAsync(
          () => stage.writeAsString(jsonEncode({'name': name}), flush: true),
        );
        for (var n = 0; n < 180; n++) {
          await tester.pump(const Duration(milliseconds: 200));
          if (await tester.runAsync(
                () async =>
                    await ack.exists() && await ack.readAsString() == name,
              ) ==
              true) {
            return;
          }
        }
        fail('Fresh Android screenshot missing');
      }

      final catalog =
          jsonDecode(
                await rootBundle.loadString(
                  'assets/data/furniture-products.json',
                ),
              )
              as List;
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final mode = brightness == Brightness.light ? 'light' : 'night';
        final db = AppDatabase(NativeDatabase.memory());
        catalog.addAll(
          jsonDecode(
                await rootBundle.loadString(
                  'assets/data/souvenir-products.json',
                ),
              )
              as List,
        );
        var writes = 0;
        final room = <String, dynamic>{
          'family_id': 'visual-family',
          'configured': true,
          'version': 7,
          'products': catalog,
          'layout': const RoomLayout([
            PlacedItem(
              'old-painting',
              slot: 'art-left-back',
              artwork: 'starry',
            ),
          ]).toJson(),
          'lease_seconds': 120,
          'renewal_seconds': 30,
        };
        Map<String, dynamic> current() => {
          ...room,
          'inventory': [
            {
              'id': 'old-painting',
              'sku': 'painting-starry',
              'source': 'purchase',
              'purchased_by': 'visual-owner',
            },
            {
              'id': 'new-photo',
              'sku': 'photo-black_short-palace',
              'source': 'photo',
              'purchased_by': 'visual-owner',
            },
            for (final id in [
              'palace',
              'louvre',
              'fuji',
              'pyramid',
              'eiffel',
              'liberty',
            ])
              {
                'id': 'souvenir-$id',
                'sku': 'souvenir-$id',
                'source': 'test_grant',
                'purchased_by': 'visual-owner',
              },
          ],
        };
        final repo = ShopRepository(
          db,
          'visual-owner',
          rpc: (method, args) async {
            if (method == 'furniture_state') {
              return current();
            }
            if (method == 'room_editor') {
              return {
                ...current(),
                'status': args['action'] == 'release' ? 'released' : 'acquired',
                'server_time': DateTime.now().toUtc().toIso8601String(),
                'lock_until': DateTime.now()
                    .toUtc()
                    .add(const Duration(seconds: 120))
                    .toIso8601String(),
              };
            }
            if (method == 'family_album') {
              return {
                'family_id': 'visual-family',
                'photos': [
                  {
                    'id': 'visual-photo',
                    'source': 'test_grant',
                    'appearance': 'black_short',
                    'destination': 'palace',
                    'destination_label': '故宫',
                    'cat_name': '三花猫',
                    'taken_at': '2026-10-10T01:00:00Z',
                    'arranger_label': '测试解锁',
                    'souvenir_label': '宫殿',
                  },
                ],
              };
            }
            if (method == 'save_room_layout' ||
                method == 'purchase_furniture') {
              writes++;
            }
            if (method == 'repair_state') return {'status': 'none'};
            throw StateError('No live RPC in fixture: $method');
          },
        );
        final homeKey = GlobalKey<HomePageState>();
        try {
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(brightness),
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                body: HomePage(
                  key: homeKey,
                  onStudy: () {},
                  shopRepository: repo,
                  wallet: const IdentityWallet(
                    ownerId: 'visual-owner',
                    miaoCoins: 2000,
                    eaglePounds: 12,
                    gems: 12,
                  ),
                  loadRoom: () async => FurnitureState.fromJson(current()),
                  loadProxyNotices: () async => [],
                  loadCats: () async => {
                    'family_id': 'visual-family',
                    'cats': <dynamic>[],
                    'repairing': false,
                  },
                ),
              ),
            ),
          );
          for (
            var n = 0;
            n < 100 &&
                (homeKey.currentState?.scene.geometryReady != true ||
                    homeKey.currentState!.loadingFurniture);
            n++
          ) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          final scene = homeKey.currentState!.scene;
          expect(scene.geometryReady, isTrue);
          expect(
            tester
                .widget<GameWidget>(
                  find.byWidgetPredicate((w) => w is GameWidget),
                )
                .game,
            same(scene),
          );
          homeKey.currentState!.openStore();
          await tester.pump(const Duration(seconds: 1));
          await tester.tap(find.byKey(const Key('category-windows')));
          await tester.pump(const Duration(milliseconds: 500));
          await capture('warehouse-shop-$mode');
          await tester.tap(
            find.byKey(const ValueKey('product-painting-starry')),
          );
          await tester.pump(const Duration(milliseconds: 500));
          expect(
            tester.getSize(find.byType(Dialog)).width,
            lessThanOrEqualTo(320),
          );
          await capture('warehouse-detail-$mode');
          await tester.tap(find.byTooltip('关闭详情'));
          await tester.pump(const Duration(milliseconds: 300));
          homeKey.currentState!.closeActiveRoomTools();
          await tester.pump(const Duration(milliseconds: 300));
          await homeKey.currentState!.openArrange();
          await tester.pump(const Duration(milliseconds: 300));
          for (
            var n = 0;
            n < 50 &&
                tester
                        .state<EditorPageState>(find.byType(EditorPage))
                        .editable !=
                    true;
            n++
          ) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          final editor = tester.state<EditorPageState>(find.byType(EditorPage));
          final token = editor.token;
          final before = editor.draft!.layout.toJson();
          final album = homeKey.currentState!.openAlbum();
          for (
            var n = 0;
            n < 100 &&
                find
                    .byKey(const ValueKey('photo-visual-photo'))
                    .evaluate()
                    .isEmpty;
            n++
          ) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.tap(find.byKey(const ValueKey('photo-visual-photo')));
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byKey(const Key('place-album-photo')), findsNothing);
          await tester.tap(find.byType(BackButton).hitTestable().last);
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(find.byType(BackButton).hitTestable().last);
          await tester.pump(const Duration(milliseconds: 300));
          await album;
          expect(
            tester
                .widget<GameWidget>(
                  find.byWidgetPredicate((w) => w is GameWidget),
                )
                .game,
            same(scene),
          );
          expect(
            tester.state<EditorPageState>(find.byType(EditorPage)),
            same(editor),
          );
          expect(editor.token, token);
          await tester.tap(find.byKey(const Key('category-windows')));
          await tester.pump(const Duration(milliseconds: 300));
          await tester.tap(
            find.byKey(const ValueKey('product-photo-black_short-palace')),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(editor.draft!.preview!.slot, 'art-left-front');
          expect(editor.replacing, isNull);
          expect(editor.draft!.layout.toJson(), before);
          editor.cancelPreview();
          await tester.pump(const Duration(milliseconds: 300));
          expect(editor.draft!.layout.toJson(), before);
          await editor.selectOwned(
            editor.state!.products['photo-black_short-palace']!,
          );
          await tester.pump(const Duration(milliseconds: 300));
          final mounts = <String>{};
          for (var n = 0; n < 3; n++) {
            mounts.add(editor.draft!.preview!.slot!);
            editor.rotatePreview();
            await tester.pump(const Duration(milliseconds: 150));
          }
          expect(mounts.length, 3);
          expect(mounts.contains('art-left-back'), isFalse);
          expect(
            find.descendant(
              of: find.byType(FurnitureGrid),
              matching: find.byType(Text),
            ),
            findsNothing,
          );
          await capture('warehouse-room-$mode');
          await tester.tap(find.byTooltip('确认摆放'));
          await tester.pump(const Duration(milliseconds: 300));
          expect(editor.draft!.layout.items.length, 2);
          final photoItem = editor.draft!.layout.items.last;
          editor.tapPlaced(
            scene
                .placedViewportBounds(
                  photoItem,
                  editor.state!.products['photo-black_short-palace']!,
                )
                .center,
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(editor.draft!.preview!.instanceId, 'new-photo');
          editor.cancelPreview();
          await tester.pump(const Duration(milliseconds: 200));
          await editor.selectOwned(editor.state!.products['souvenir-palace']!);
          await tester.pump(const Duration(milliseconds: 300));
          expect(editor.draft!.preview!.instanceId, 'souvenir-palace');
          expect(editor.canConfirm, isTrue);
          editor.rotatePreview();
          await tester.pump(const Duration(milliseconds: 200));
          expect(editor.draft!.preview!.facing, 'y');
          await tester.tap(find.byTooltip('确认摆放'));
          await tester.pump(const Duration(milliseconds: 300));
          expect(editor.draft!.layout.items.length, 3);
          expect(editor.state!.inventory.length, 8);
          expect(writes, 0);
          expect(tester.takeException(), isNull);

          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(brightness),
              debugShowCheckedModeBanner: false,
              home: Scaffold(
                body: TaskBoardPage(
                  ownerId: 'visual-owner',
                  onWallet: (_) {},
                  database: db,
                  taskCloud: VisualTaskCloud(db),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(seconds: 1));
          expect(find.text('01'), findsNothing);
          expect(find.text('02'), findsNothing);
          await capture('warehouse-tasks-$mode');
          await LockScreenTimer.requestPermission();
          expect(
            await LockScreenTimer.show(
              DateTime.now().subtract(const Duration(seconds: 90)),
            ),
            isTrue,
          );
          await tester.pump(const Duration(seconds: 1));
          expect(await LockScreenTimer.isActive(), isTrue);
          await capture('warehouse-timer-$mode');
          await capture('warehouse-lock-$mode');
          await LockScreenTimer.stop();
          await tester.pumpWidget(const SizedBox());
        } finally {
          await db.close();
        }
      }
      binding.reportData = {
        'result': 'PASS',
        'captureHandshakeRun': run,
        'themes': 2,
        'sameHomeScene': true,
        'existingDraftAndLeasePreserved': true,
        'fixedPhotoMounts': 4,
        'skipOccupiedMounts': true,
        'placedItemReactivated': true,
        'souvenirPlacementAndRotation': true,
        'iconOnlyWarehouse': true,
        'minimalTimerNotificationAndLockScreen': true,
        'cancelPreservesDraft': true,
        'inventoryPreserved': true,
        'noAutomaticSaveOrPurchase': true,
        'physicalPhoneTouched': false,
      };
    },
  );
}

class VisualTaskCloud extends TaskCloud {
  VisualTaskCloud(AppDatabase database)
    : super(database: database, ownerId: 'visual-owner', onWallet: (_) {});
  @override
  Future<void> refresh() async {
    days = [];
  }

  @override
  Future<List<Map<String, dynamic>>> feed() async => [];
}
