import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/core/sync/cloud_client.dart';
import 'package:cat_library_demo/core/sync/cloud_connection.dart';
import 'package:cat_library_demo/app/app_theme.dart';
import 'package:cat_library_demo/features/home/home_page.dart';
import 'package:cat_library_demo/features/identity/identity_repository.dart';
import 'package:cat_library_demo/features/room/layout_draft.dart';
import 'package:cat_library_demo/features/shop/shop_repository.dart';

// Reuses the existing isolated hosted family. No signup, purchases or grants.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('home polls naturally, keeps offline layout and reloads on entry', (
    tester,
  ) async {
    const url = String.fromEnvironment('SUPABASE_URL');
    const key = String.fromEnvironment('SUPABASE_ANON_KEY');
    expect(url, 'https://ludwvhsvknjgblfgouor.supabase.co');
    expect(const String.fromEnvironment('ISOLATED_HOSTED_COMMERCE'), 'true');
    SharedPreferences.setMockInitialValues({});
    final gate = _OfflineGate(http.Client());
    final transport = ConnectionHttpClient(gate, CloudClient.connection);
    final a = SupabaseClient(
      url,
      key,
      httpClient: transport,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final b = SupabaseClient(
      url,
      key,
      authOptions: const AuthClientOptions(autoRefreshToken: false),
    );
    final databases = List.generate(
      2,
      (_) => AppDatabase(NativeDatabase.memory()),
    );
    try {
      await a.auth.setSession(const String.fromEnvironment('M7_A_REFRESH'));
      await b.auth.setSession(const String.fromEnvironment('M7_B_REFRESH'));
      expect(a.auth.currentUser!.id != b.auth.currentUser!.id, isTrue);
      ShopRepository repository(SupabaseClient client, AppDatabase db) =>
          ShopRepository(
            db,
            client.auth.currentUser!.id,
            rpc: (method, args) async => Map<String, dynamic>.from(
              await client.rpc(method, params: args) as Map,
            ),
          );
      final repoA = repository(a, databases[0]);
      final repoB = repository(b, databases[1]);
      final before = await repoA.load();
      expect(before.testScope, isFalse);
      expect(before.configured, isTrue);
      expect(before.inventory.length, 2);
      expect(before.layout.items.length, 2);
      expect(before.raw['wallet']['miao_coins'], 0);
      final wallet = IdentityWallet.fromJson(
        Map<String, dynamic>.from(before.raw['wallet']),
      );
      var homeKey = GlobalKey<HomePageState>();
      Future<void> mount() => tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(Brightness.dark),
          home: Scaffold(
            body: HomePage(
              key: homeKey,
              onStudy: () {},
              wallet: wallet,
              shopRepository: repoA,
              loadRoom: repoA.load,
              loadCats: () => repoA.call('cats_state', const {}),
              loadProxyNotices: () async => [
                for (final raw in await a.rpc('proxy_notice_state') as List)
                  Map<String, dynamic>.from(raw as Map),
              ],
              acknowledgeProxyNotice: (day) async {
                await a.rpc('ack_proxy_notice', params: {'target_day': day});
              },
            ),
          ),
        ),
      );
      Future<void> waitUntil(bool Function() ready, {int seconds = 20}) async {
        final clock = Stopwatch()..start();
        while (!ready() && clock.elapsed < Duration(seconds: seconds)) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
        expect(
          ready(),
          isTrue,
          reason: 'Hosted home did not reach expected state',
        );
      }

      await binding.convertFlutterSurfaceToImage();
      await mount();
      await waitUntil(() => !homeKey.currentState!.loadingFurniture);
      await waitUntil(() => homeKey.currentState!.scene.geometryReady);
      expect(homeKey.currentState!.scene.roomState!.version, before.version);
      final scene = homeKey.currentState!.scene;
      final token = furnitureRequestId();
      final acquired = await repoB.editor('acquire', token);
      expect(acquired['status'], 'acquired');
      try {
        final current = await repoB.load();
        final target = current.layout.items.first;
        final available =
            [
              'art-left-back',
              'art-left-front',
              'art-right-back',
              'art-right-front',
            ].firstWhere(
              (slot) => current.layout.items.every((item) => item.slot != slot),
            );
        final next = RoomLayout([
          for (final item in current.layout.items)
            item.instanceId == target.instanceId
                ? item.copy(slot: available)
                : item,
        ]);
        expect(current.rules.validate(next), isEmpty);
        final saved = await repoB.save(
          current.familyId!,
          token,
          LayoutDraft(next, current.version),
        );
        expect(saved['status'], 'saved');
        expect(saved['version'], before.version + 1);
      } finally {
        await repoB.editor('release', token);
      }
      final clock = Stopwatch()..start();
      final notice = find.text('家庭布局已更新，点击刷新查看');
      // No explicit checkRoomUpdate invocation or shortened production interval.
      await waitUntil(() => notice.evaluate().isNotEmpty, seconds: 45);
      final observedPollMilliseconds = clock.elapsedMilliseconds;
      expect(homeKey.currentState!.scene.roomState!.version, before.version);
      await binding.takeScreenshot('m7-home-natural-update');
      await tester.tap(notice);
      await waitUntil(
        () =>
            homeKey.currentState!.scene.roomState!.version ==
            before.version + 1,
      );
      expect(identical(scene, homeKey.currentState!.scene), isTrue);
      final confirmed = homeKey.currentState!.scene.roomState!.layout.toJson();
      gate.offline = true;
      homeKey.currentState!.didChangeAppLifecycleState(
        AppLifecycleState.resumed,
      );
      await waitUntil(() => homeKey.currentState!.furnitureError != null);
      expect(homeKey.currentState!.scene.roomState!.layout.toJson(), confirmed);
      expect(CloudClient.connection.value.phase, CloudPhase.offline);
      await waitUntil(
        () =>
            !homeKey.currentState!.loadingCats &&
            !homeKey.currentState!.loadingFurniture,
      );
      await tester.pump(const Duration(milliseconds: 400));
      await binding.takeScreenshot('m7-home-offline-retained');
      gate.offline = false;
      await tester.tap(find.text('家庭布局暂未同步，点击重试；当前画面保留'));
      await waitUntil(
        () =>
            !homeKey.currentState!.loadingFurniture &&
            homeKey.currentState!.furnitureError == null,
      );
      expect(CloudClient.connection.value.phase, CloudPhase.online);
      expect(homeKey.currentState!.scene.roomState!.layout.toJson(), confirmed);
      // Recreate the actual home widget; no cache assigned directly to its scene.
      await tester.pumpWidget(const SizedBox());
      homeKey = GlobalKey<HomePageState>();
      await mount();
      await waitUntil(() => !homeKey.currentState!.loadingFurniture);
      final geometryReadyWhenDataArrived =
          homeKey.currentState!.scene.geometryReady;
      await waitUntil(() => homeKey.currentState!.scene.geometryReady);
      expect(homeKey.currentState!.scene.roomState!.configured, isTrue);
      expect(
        homeKey.currentState!.scene.roomState!.version,
        before.version + 1,
      );
      expect(homeKey.currentState!.scene.roomState!.layout.toJson(), confirmed);
      expect(find.text('家庭布局已更新，点击刷新查看'), findsNothing);
      await waitUntil(() => !homeKey.currentState!.loadingCats);
      expect(CloudClient.connection.value.phase, CloudPhase.online);
      await tester.pump(const Duration(milliseconds: 400));
      await binding.takeScreenshot('m7-home-reentered');
      final finalState = await repoB.load();
      expect(finalState.raw['lock_user'], isNull);
      expect(
        finalState.inventory.map((item) => item.id),
        before.inventory.map((item) => item.id),
      );
      expect(finalState.raw['wallet']['miao_coins'], 0);
      expect((await repoA.load()).raw['wallet']['miao_coins'], 0);
      binding.reportData!.addAll({
        'result': 'PASS',
        'scope':
            'one emulator; existing independent hosted family; two clients',
        'naturalThirtySecondPoll': true,
        'pollObservedAfterRemoteSaveMs': observedPollMilliseconds,
        'manualRefreshRequired': true,
        'scenePreservedDuringRefresh': true,
        'offlineConfirmedLayoutRetained': true,
        'reconnectedByVisibleRetry': true,
        'newHomeEntryLoadedLatest': true,
        'newHomeGeometryReadyWhenDataArrived': geometryReadyWhenDataArrived,
        'newHomeGeometryReadyBeforeScreenshot': true,
        'versionBefore': before.version,
        'versionAfter': finalState.version,
        'inventoryUnchanged': true,
        'bothWalletsUnchanged': true,
        'newIdentitiesCreated': false,
        'originalIdentityMigrated': false,
        'physicalPhoneVerified': false,
        'networkFailureScope':
            'HTTP adapter rejection; physical network not interrupted',
      });
    } finally {
      await tester.pumpWidget(const SizedBox());
      for (final db in databases) {
        await db.close();
      }
      await a.dispose();
      await b.dispose();
      transport.close();
    }
  });
}

class _OfflineGate extends http.BaseClient {
  _OfflineGate(this.delegate);
  final http.Client delegate;
  bool offline = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (offline) throw const SocketException('isolated member disconnected');
    return delegate.send(request);
  }

  @override
  void close() => delegate.close();
}
