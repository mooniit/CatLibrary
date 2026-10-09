import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cat_library_demo/app/app_theme.dart';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/features/home/home_page.dart';
import 'package:cat_library_demo/features/identity/identity_repository.dart';
import 'package:cat_library_demo/features/shop/shop_repository.dart';

// Actual HomePage, isolated memory data. No Auth, HTTP, billing or asset writes.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('home repair states remain readable in light and night', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase(NativeDatabase.memory());
    var offline = false;
    var completed = false;
    final repo = ShopRepository(
      db,
      'visual-repair-owner',
      rpc: (method, args) async {
        if (method != 'repair_state') {
          throw StateError('Fixture refuses other RPCs');
        }
        if (offline) throw StateError('isolated read failure');
        return completed
            ? {
                'status': 'completed',
                'grace_through': DateTime.now()
                    .toUtc()
                    .add(const Duration(hours: 32))
                    .toIso8601String()
                    .substring(0, 10),
              }
            : {
                'status': 'active',
                'cycle_no': 2,
                'ends_at': DateTime.now()
                    .add(const Duration(hours: 48))
                    .toIso8601String(),
                'progress_ms': 3600000,
                'target_ms': 7200000,
              };
      },
    );
    try {
      await binding.convertFlutterSurfaceToImage();
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final mode = brightness == Brightness.light ? 'light' : 'night';
        offline = false;
        completed = false;
        final homeKey = GlobalKey<HomePageState>();
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness),
            debugShowCheckedModeBanner: false,
            builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
              value: appSystemBars(brightness),
              child: child!,
            ),
            home: Scaffold(
              bottomNavigationBar: NavigationBar(
                height: 56,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
                onDestinationSelected: (_) {},
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    label: '猫窝',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.checklist),
                    label: '任务板',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.menu_book_outlined),
                    label: '阅读',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.timer_outlined),
                    label: '自习',
                  ),
                ],
              ),
              body: SafeArea(
                child: HomePage(
                  key: homeKey,
                  wallet: const IdentityWallet(
                    ownerId: 'visual-repair-owner',
                    miaoCoins: -150,
                    eaglePounds: 0,
                    gems: 0,
                  ),
                  onStudy: () {},
                  shopRepository: repo,
                  loadRoom: () async => FurnitureState.fromJson({
                    'configured': true,
                    'family_id': 'visual-repair-family',
                    'products': <dynamic>[],
                    'inventory': <dynamic>[],
                    'version': 0,
                    'layout': {
                      'standard': 'room-standard-v1',
                      'items': <dynamic>[],
                    },
                  }),
                  loadCats: () async => {
                    'family_id': 'visual-repair-family',
                    'repairing': true,
                    'cats': [
                      {
                        'id': 'visual-calico',
                        'name': '橘点',
                        'appearance': 'black_short',
                        'traveling': false,
                      },
                    ],
                  },
                  loadProxyNotices: () async => [],
                  acknowledgeProxyNotice: (_) async {},
                ),
              ),
            ),
          ),
        );
        final wait = Stopwatch()..start();
        while ((!homeKey.currentState!.scene.geometryReady ||
                homeKey.currentState!.loadingFurniture ||
                homeKey.currentState!.loadingCats ||
                find.byType(CircularProgressIndicator).evaluate().isNotEmpty ||
                find.text('小屋修缮中').evaluate().isEmpty) &&
            wait.elapsed < const Duration(seconds: 20)) {
          await tester.pump(const Duration(milliseconds: 100));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(homeKey.currentState!.scene.geometryReady, isTrue);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('共同计时 60 / 120 分钟'), findsOneWidget);
        expect(find.byTooltip('重新核对修缮状态').hitTestable(), findsOneWidget);
        Future<void> capture(String state) async {
          await Future<void>.delayed(const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 300));
          await binding.takeScreenshot('m7-repair-$state-$mode');
        }

        await capture('active');
        offline = true;
        await tester.tap(find.byTooltip('重新核对修缮状态'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('暂未同步，保留上次确认的进度'), findsOneWidget);
        expect(find.text('共同计时 60 / 120 分钟'), findsOneWidget);
        await tester.ensureVisible(find.text('暂未同步，保留上次确认的进度'));
        await tester.pump(const Duration(milliseconds: 300));
        await capture('offline');
        offline = false;
        completed = true;
        await tester.tap(find.byTooltip('重新核对修缮状态'));
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('小屋修缮完成'), findsOneWidget);
        expect(find.text('暂未同步，保留上次确认的进度'), findsNothing);
        await tester.ensureVisible(find.text('小屋修缮完成'));
        await tester.pump(const Duration(milliseconds: 300));
        await capture('complete');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
      binding.reportData!.addAll({
        'result': 'PASS',
        'actualHomePage': true,
        'productionSafeAreaAndNavigationDimensions': true,
        'sceneLoadedBeforeScreenshot': true,
        'themes': ['light', 'night'],
        'states': ['active', 'failed-reread', 'completed'],
        'scope': 'one emulator; memory data; no business HTTP or writes',
        'remoteInternetVerified': false,
        'physicalPhoneVerified': false,
      });
    } finally {
      await tester.pumpWidget(const SizedBox());
      await db.close();
    }
  });
}
