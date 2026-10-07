import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/travel/travel_repository.dart';
import 'package:cat_library_demo/features/travel/travel_sheet.dart';
import 'package:cat_library_demo/features/album/album_page.dart';
import 'package:cat_library_demo/features/home/home_page.dart';
import 'package:cat_library_demo/features/shop/shop_repository.dart';
import 'package:cat_library_demo/features/identity/identity_repository.dart';
import 'package:cat_library_demo/features/room/layout_draft.dart';
import 'package:cat_library_demo/app/app_theme.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'two members travel, lost receipt, return, album, provenance and room save',
    (tester) async {
      const url = String.fromEnvironment('SUPABASE_URL'),
          key = String.fromEnvironment('SUPABASE_ANON_KEY'),
          home = String.fromEnvironment('M6_HOME'),
          catA = String.fromEnvironment('M6_CAT_A'),
          catB = String.fromEnvironment('M6_CAT_B');
      expect(home, isNotEmpty);
      final a = SupabaseClient(url, key), b = SupabaseClient(url, key);
      await a.auth.setSession(const String.fromEnvironment('M6_A_REFRESH'));
      await b.auth.setSession(const String.fromEnvironment('M6_B_REFRESH'));
      final db = AppDatabase(NativeDatabase.memory());
      bool dropStart = true, offline = false;
      Future<Map<String, dynamic>> callA(
        String method,
        Map<String, dynamic> p,
      ) async {
        if (offline) throw const SocketException('isolated offline');
        final value = Map<String, dynamic>.from(
          await a.rpc(method, params: p) as Map,
        );
        if (method == 'start_cat_travel' && dropStart) {
          dropStart = false;
          offline = true;
          throw TimeoutException('receipt dropped after commit');
        }
        return value;
      }

      Future<Map<String, dynamic>> callB(
        String method,
        Map<String, dynamic> p,
      ) async =>
          Map<String, dynamic>.from(await b.rpc(method, params: p) as Map);
      final travelA = TravelRepository(db, a.auth.currentUser!.id, rpc: callA),
          travelB = TravelRepository(db, b.auth.currentUser!.id, rpc: callB);
      final roomA = ShopRepository(db, a.auth.currentUser!.id, rpc: callA),
          roomB = ShopRepository(db, b.auth.currentUser!.id, rpc: callB);
      Future<void> waitFor(Finder f) async {
        for (var i = 0; i < 60; i++) {
          await tester.pump(const Duration(milliseconds: 150));
          if (f.evaluate().isNotEmpty) return;
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
        expect(f, findsWidgets);
      }

      Future<void> tap(Finder f) async {
        await waitFor(f);
        await tester.ensureVisible(f.first);
        await tester.tap(f.first);
        await tester.pump(const Duration(milliseconds: 500));
      }

      bool surfaceConverted = false;
      Future<void> shot(String name) async {
        if (!surfaceConverted) {
          await binding.convertFlutterSurfaceToImage();
          surfaceConverted = true;
        }
        await tester.pump();
        await binding.takeScreenshot(name);
      }

      Future<void> advanceFixture(String cat) async {
        final http = HttpClient();
        try {
          final req = await http.postUrl(
            Uri.parse('http://127.0.0.1:54329/m6/return'),
          );
          req.headers.contentType = ContentType.json;
          req.write(
            jsonEncode({
              'cat': cat,
              'nonce': const String.fromEnvironment('M6_CLOCK_NONCE'),
            }),
          );
          final result = await req.close();
          expect(result.statusCode, 200);
          await result.drain<void>();
        } finally {
          http.close(force: true);
        }
      }

      Future<void> showTravel(TravelRepository repo) async {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            theme: buildAppTheme(Brightness.light),
            home: TravelSheet(repository: repo),
          ),
        );
        await waitFor(find.text('远行猫甲'));
        await tester.pump(const Duration(seconds: 1));
      }

      Future<void> showAlbum(
        TravelRepository repo,
        Brightness brightness,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            theme: buildAppTheme(brightness),
            home: AlbumPage(repository: repo),
          ),
        );
        await waitFor(find.text('故宫'));
        await tester.pump(const Duration(seconds: 1));
      }

      try {
        await showTravel(travelA);
        await shot('m6-native-travel');
        await tap(find.byKey(const ValueKey('travel-$catA')));
        await tap(find.text('出发 · 60 宝石'));
        await waitFor(find.textContaining('出发结果待核对'));
        expect(await travelA.pending(), isNotNull);
        await shot('m6-native-start-pending');
        offline = false;
        await showTravel(
          TravelRepository(db, a.auth.currentUser!.id, rpc: callA),
        );
        expect(await travelA.pending(), isNull);
        expect((await travelA.load())['wallet']['gems'], 60);
        await shot('m6-native-cat-a-started');
        await advanceFixture(catA);
        await tap(find.byTooltip('核对旅行'));
        await waitFor(find.text('远行猫甲回来了'));
        await tap(find.text('远行猫甲回来了'));
        await shot('m6-native-return');
        await tap(find.text('收好回忆'));
        await showAlbum(travelB, Brightness.light);
        expect(find.text('1 条旅行回忆'), findsOneWidget);
        await shot('m6-native-album-partner');
        await tap(find.text('故宫'));
        await waitFor(find.text('安排人：另一位成员'));
        await shot('m6-native-photo-detail');
        await showTravel(travelB);
        await tap(find.byKey(const ValueKey('travel-$catB')));
        await tap(find.text('出发 · 60 宝石'));
        await waitFor(find.text('出发成功，24 小时后回家。'));
        await shot('m6-native-cat-b-started');
        await advanceFixture(catB);
        await tap(find.byTooltip('核对旅行'));
        await waitFor(find.text('远行猫乙回来了'));
        await showAlbum(travelA, Brightness.dark);
        expect(find.text('2 条旅行回忆'), findsOneWidget);
        await shot('m6-native-album-night');
        final state = await roomA.load();
        expect(state.inventory, hasLength(2));
        expect(state.inventory.map((i) => i.sourceCatName).toSet(), {
          '远行猫甲',
          '远行猫乙',
        });
        final host = GlobalKey<HomePageState>();
        await tester.pumpWidget(
          MaterialApp(
            key: UniqueKey(),
            theme: buildAppTheme(Brightness.light),
            home: Scaffold(
              body: HomePage(
                key: host,
                onStudy: () {},
                wallet: IdentityWallet.fromJson(
                  Map<String, dynamic>.from(state.raw['wallet']),
                ),
                shopRepository: roomA,
                loadRoom: roomA.load,
                loadCats: () => callA('cats_state', {}),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(seconds: 2));
        await host.currentState!.scene.loaded;
        await tester.pump(const Duration(milliseconds: 200));
        await host.currentState!.openArrange();
        await waitFor(find.byKey(const Key('editor-inventory')));
        await tap(find.byKey(const ValueKey('product-souvenir-palace')));
        await waitFor(find.textContaining('远行猫甲 · 故宫'));
        await shot('m6-native-souvenir-sources');
        await tap(find.textContaining('远行猫甲 · 故宫'));
        await waitFor(find.byTooltip('确认'));
        expect(host.currentState!.scene.geometryReady, true);
        expect(host.currentState!.scene.ghostBounds, isNotNull);
        await shot('m6-native-souvenir-preview');
        await tap(find.byTooltip('切换朝向'));
        await tap(find.byTooltip('确认'));
        expect((await roomA.load()).layout.items, isEmpty);
        expect((await roomA.draft(home))!.layout.items, hasLength(1));
        expect(
          (await roomB.editor('acquire', furnitureRequestId()))['reason'],
          'editor_busy',
        );
        // Partner's album and travel reads remain available during the lease.
        expect((await travelB.load(album: true))['photos'], hasLength(2));
        await tap(find.byTooltip('保存到家庭'));
        await waitFor(find.textContaining('保存成功 · 家庭版本 1'));
        await shot('m6-native-souvenir-saved');
        final partner = await roomB.load();
        expect(partner.version, 1);
        expect(partner.layout.items, hasLength(1));
        expect(partner.layout.items.single.facing, 'y');
        expect(partner.inventory, hasLength(2));
        await tap(find.byTooltip('离开并保留草稿'));
        await tester.pump(const Duration(seconds: 1));
        final token = furnitureRequestId();
        await roomB.editor('acquire', token);
        await roomB.save(home, token, LayoutDraft(const RoomLayout([]), 1));
        await roomB.editor('release', token);
        await host.currentState!.checkRoomUpdate();
        await waitFor(find.text('家庭布局已更新，点击刷新查看'));
        await shot('m6-native-partner-layout-notice');
        await tap(find.text('家庭布局已更新，点击刷新查看'));
        expect(host.currentState!.scene.roomState!.version, 2);
        expect(host.currentState!.scene.roomState!.layout.items, isEmpty);
        expect((await roomA.load()).inventory, hasLength(2));
        await shot('m6-native-stowed-inventory-retained');
      } finally {
        await tester.pumpWidget(const SizedBox());
        await db.close();
        await a.dispose();
        await b.dispose();
      }
    },
  );
}
