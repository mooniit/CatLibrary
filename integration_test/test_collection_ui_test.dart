import 'dart:async';
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
import 'package:cat_library_demo/features/room/room_scene.dart';
import 'package:cat_library_demo/features/room/editor_page.dart';
import 'package:cat_library_demo/features/room/furniture_catalog_widgets.dart';
import 'package:cat_library_demo/features/shop/shop_repository.dart';
import 'package:cat_library_demo/features/album/album_page.dart';
import 'package:cat_library_demo/features/travel/travel_repository.dart';

// Existing room/editor and album with memory-only data; no Auth or business HTTP.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('personal warehouse and unlocked album in both themes', (
    tester,
  ) async {
    const run = String.fromEnvironment('TEST_COLLECTION_CAPTURE_RUN');
    expect(RegExp(r'^\d{15,20}$').hasMatch(run), isTrue);
    final stage = File(
      '${Directory.systemTemp.path}/test_collection_native_$run.json',
    );
    final ack = File('${stage.path}.ack');
    Future<void> capture(String name) async {
      await tester.pump(const Duration(milliseconds: 200));
      await tester.runAsync(
        () => stage.writeAsString(jsonEncode({'name': name}), flush: true),
      );
      for (var attempt = 0; attempt < 180; attempt++) {
        await tester.pump(const Duration(milliseconds: 200));
        final done = await tester.runAsync(
          () async => await ack.exists() && await ack.readAsString() == name,
        );
        if (done == true) return;
      }
      fail('Fresh screen receipt timed out');
    }

    final products =
        jsonDecode(
              await rootBundle.loadString('assets/data/souvenir-products.json'),
            )
            as List;
    final db = AppDatabase(NativeDatabase.memory());
    final room = {
      'family_id': 'visual-family',
      'configured': true,
      'version': 7,
      'products': products,
      'inventory': [
        for (final p in products)
          {
            'id': 'mine-${p['sku']}',
            'sku': p['sku'],
            'source': 'test_grant',
            'purchased_by': 'visual-owner',
          },
        {
          'id': 'other-palace',
          'sku': 'souvenir-palace',
          'source': 'test_grant',
          'purchased_by': 'another-owner',
        },
      ],
      'layout': {'standard': 'room-standard-v1', 'items': <dynamic>[]},
      'lease_seconds': 120,
      'renewal_seconds': 30,
    };
    final repo = ShopRepository(
      db,
      'visual-owner',
      rpc: (method, args) async {
        if (method == 'furniture_state') return room;
        if (method == 'room_editor') {
          return {
            ...room,
            'status': args['action'] == 'release' ? 'released' : 'acquired',
            'server_time': DateTime.now().toUtc().toIso8601String(),
            'lock_until': DateTime.now()
                .toUtc()
                .add(const Duration(seconds: 120))
                .toIso8601String(),
          };
        }
        throw StateError('Fixture refuses RPC $method');
      },
    );
    try {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final mode = brightness == Brightness.light ? 'light' : 'night';
        final editor = GlobalKey<EditorPageState>();
        final scene = RoomScene(fitViewport: true);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness),
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: SafeArea(
                child: Stack(
                  children: [
                    Positioned.fill(
                      bottom: 320,
                      child: GameWidget(game: scene),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        height: 320,
                        child: ColoredBox(
                          color: ThemeData(
                            brightness: brightness,
                          ).colorScheme.surface,
                          child: EditorPage(
                            key: editor,
                            repository: repo,
                            scene: scene,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        for (
          var i = 0;
          i < 100 &&
              (editor.currentState?.editable != true || !scene.geometryReady);
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(editor.currentState!.editable, isTrue);
        expect(scene.geometryReady, isTrue);
        await tester.tap(find.byKey(const Key('personal-inventory')));
        await tester.pump(const Duration(milliseconds: 300));
        final grid = tester.widget<FurnitureGrid>(
          find.byKey(const Key('editor-inventory')),
        );
        expect(grid.inventory.length, 6);
        expect(
          grid.inventory.every((i) => i.belongsTo('visual-owner')),
          isTrue,
        );
        final palace = editor.currentState!.state!.products['souvenir-palace']!;
        unawaited(editor.currentState!.selectOwned(palace));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('故宫宫殿').last);
        await tester.pump(const Duration(milliseconds: 300));
        expect(editor.currentState!.draft!.preview!.facing, 'x');
        editor.currentState!.rotatePreview();
        await tester.pump(const Duration(milliseconds: 300));
        expect(editor.currentState!.draft!.preview!.facing, 'y');
        expect(editor.currentState!.draft!.baseVersion, 7);
        expect(editor.currentState!.draft!.layout.items, isEmpty);
        await capture('test-collection-inventory-$mode');
        editor.currentState!.cancelPreview();
        await tester.pump(const Duration(milliseconds: 200));
        await tester.tap(find.byKey(const Key('family-inventory')));
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          tester
              .widget<FurnitureGrid>(find.byKey(const Key('editor-inventory')))
              .inventory
              .length,
          7,
        );
        await tester.pumpWidget(const SizedBox());
        final travel = TravelRepository(
          db,
          'visual-owner',
          rpc: (method, _) async {
            if (method != 'family_album') {
              throw StateError('Fixture refuses album write');
            }
            return {
              'family_id': 'visual-family',
              'photos': [
                for (final appearance in ['black_short', 'light_long'])
                  for (final d in [
                    ('palace', '故宫'),
                    ('louvre', '卢浮宫'),
                    ('fuji', '富士山'),
                    ('pyramid', '金字塔'),
                    ('eiffel', '埃菲尔铁塔'),
                    ('liberty', '自由女神像'),
                  ])
                    {
                      'id': '$appearance-${d.$1}',
                      'appearance': appearance,
                      'destination': d.$1,
                      'destination_label': d.$2,
                      'cat_name': appearance == 'black_short' ? '三花猫' : '蓝眸长毛猫',
                      'source': 'test_grant',
                      'taken_at': '2026-10-10T01:00:00Z',
                      'arranger_label': '测试解锁',
                      'souvenir_label': d.$2,
                    },
              ],
            };
          },
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness),
            debugShowCheckedModeBanner: false,
            home: AlbumPage(key: ValueKey('album-$mode'), repository: travel),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('12 张照片'), findsOneWidget);
        for (var attempt = 0; attempt < 60; attempt++) {
          final painted = tester.widgetList<RawImage>(find.byType(RawImage));
          if (painted.length >= 6 && painted.every((i) => i.image != null)) {
            break;
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          tester
              .widgetList<RawImage>(find.byType(RawImage))
              .where((i) => i.image != null)
              .length,
          greaterThanOrEqualTo(6),
        );
        await capture('test-collection-album-$mode');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
      binding.reportData = {
        'result': 'PASS',
        'themes': 2,
        'personalSouvenirStyles': 6,
        'unlockedPhotos': 12,
        'personalFilterExcludesOtherOwner': true,
        'familyInventoryRetained': true,
        'rotationVerified': true,
        'draftNotAutomaticallySaved': true,
        'businessWrites': 0,
        'physicalPhoneTouched': false,
        'captureHandshakeRun': run,
        'captureMethod':
            'ADB Android screen with fresh per-stage acknowledgment',
      };
    } finally {
      await db.close();
    }
  });
}
