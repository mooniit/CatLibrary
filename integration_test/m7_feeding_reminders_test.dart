import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cat_library_demo/app/app_theme.dart';
import 'package:cat_library_demo/core/storage/app_database.dart';
import 'package:cat_library_demo/core/notifications/feeding_notifications.dart';
import 'package:cat_library_demo/features/home/home_page.dart';
import 'package:cat_library_demo/features/identity/identity_repository.dart';
import 'package:cat_library_demo/features/shop/shop_repository.dart';
import 'package:cat_library_demo/features/reminders/feeding_reminders.dart';
import 'package:cat_library_demo/features/reminders/reminder_widgets.dart';
import '../test/feeding_reminders_test.dart'
    show MemoryReminderStore, MemoryFeedingNotifications;

// Real home/settings with memory state: no Auth, HTTP, grants, feeding or billing.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'home reminders and optional notification settings in both themes',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = AppDatabase(NativeDatabase.memory());
      final badPost = await NativeFeedingNotifications.channel
          .invokeMethod<bool>('show', {
            'ownerId': 'invalid-owner',
            'businessDay': 'invalid-day',
            'names': ['橘点'],
          })
          .timeout(const Duration(seconds: 10));
      expect(badPost, isFalse);
      final permissionInitiallyAllowed = await NativeFeedingNotifications
          .channel
          .invokeMethod<bool>('isAllowed')
          .timeout(const Duration(seconds: 10));
      expect(permissionInitiallyAllowed, isA<bool>());
      const captureRun = String.fromEnvironment('M7_FEEDING_CAPTURE_RUN');
      expect(RegExp(r'^\d{15,20}$').hasMatch(captureRun), isTrue);
      final stageFile = File(
        '${Directory.systemTemp.path}/feeding_native_$captureRun.json',
      );
      final ackFile = File('${stageFile.path}.ack');
      Future<void> capture(String name) async {
        await tester.pump(const Duration(milliseconds: 200));
        debugPrint('Reminder native screenshot: $name');
        await tester.runAsync(
          () =>
              stageFile.writeAsString(jsonEncode({'name': name}), flush: true),
        );
        for (var attempt = 0; attempt < 180; attempt++) {
          await tester.pump(const Duration(milliseconds: 200));
          final accepted = await tester.runAsync(
            () async =>
                await ackFile.exists() && await ackFile.readAsString() == name,
          );
          if (accepted == true) {
            return;
          }
        }
        throw StateError(
          'Fresh Android screenshot acknowledgment timed out: $name',
        );
      }

      var totalAcks = 0;
      try {
        for (final brightness in [Brightness.light, Brightness.dark]) {
          final mode = brightness == Brightness.light ? 'light' : 'night';
          final store = MemoryReminderStore();
          final notifications = MemoryFeedingNotifications();
          var acks = 0;
          final controller = FeedingReminderController(
            ownerId: 'reminder-visual-owner',
            store: store,
            notifications: notifications,
            clock: () => DateTime.utc(2026, 10, 10, 13),
            rpc: (method, params) async {
              if (method == 'ack_feeding_reminder') {
                acks++;
                return {
                  'status': 'acknowledged',
                  'owner_id': 'reminder-visual-owner',
                  'business_day': params['target_day'],
                  'channel': params['target_channel'],
                };
              }
              if (method != 'get_feeding_reminder') {
                throw StateError('Unsupported fixture RPC');
              }
              return {
                'status': 'ready',
                'owner_id': 'reminder-visual-owner',
                'family_id': 'reminder-visual-family',
                'business_day': '2026-10-10',
                'created_at': '2026-10-10T13:00:00Z',
                'cats': [
                  {'id': 'cat-a', 'name': '橘点'},
                  {'id': 'cat-b', 'name': '白云'},
                ],
                'in_app_seen': false,
                'notification_seen': false,
              };
            },
          );
          final home = GlobalKey<HomePageState>();
          final repo = ShopRepository(
            db,
            'reminder-visual-owner',
            rpc: (method, params) async {
              if (method != 'repair_state') {
                throw StateError('Fixture refuses other RPCs');
              }
              return {'status': 'none'};
            },
          );
          Widget page(bool visible) => MaterialApp(
            theme: buildAppTheme(brightness),
            debugShowCheckedModeBanner: false,
            builder: (_, child) => AnnotatedRegion<SystemUiOverlayStyle>(
              value: appSystemBars(brightness),
              child: child!,
            ),
            home: Scaffold(
              body: SafeArea(
                child: HomePage(
                  key: home,
                  visible: visible,
                  reminderController: controller,
                  onStudy: () {},
                  onThemeChanged: (_) async {},
                  wallet: const IdentityWallet(
                    ownerId: 'reminder-visual-owner',
                    miaoCoins: 45,
                    eaglePounds: 0,
                    gems: 0,
                  ),
                  shopRepository: repo,
                  loadRoom: () async => FurnitureState.fromJson({
                    'configured': true,
                    'family_id': 'reminder-visual-family',
                    'products': <dynamic>[],
                    'inventory': <dynamic>[],
                    'version': 0,
                    'layout': {
                      'standard': 'room-standard-v1',
                      'items': <dynamic>[],
                    },
                  }),
                  loadCats: () async => {
                    'family_id': 'reminder-visual-family',
                    'repairing': false,
                    'cats': [
                      {
                        'id': 'cat-a',
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
          );
          await tester.pumpWidget(page(false));
          final watch = Stopwatch()..start();
          while ((!home.currentState!.scene.geometryReady ||
                  home.currentState!.loadingFurniture ||
                  home.currentState!.loadingCats ||
                  controller.reminder == null) &&
              watch.elapsed.inSeconds < 20) {
            await tester.pump(const Duration(milliseconds: 100));
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          expect(home.currentState!.scene.geometryReady, isTrue);
          expect(controller.reminder, isNotNull);
          expect(acks, 0);
          await tester.pumpWidget(page(true));
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.text('晚餐时间'), findsOneWidget);
          expect(acks, 1);
          await capture('m7-feeding-home-$mode');
          unawaited(home.currentState!.openSettings());
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.byType(FeedingReminderSettings), findsOneWidget);
          await tester.ensureVisible(
            find.byKey(const Key('feeding-notification-switch')),
          );
          await tester.pump(const Duration(milliseconds: 200));
          await tester.tap(
            find.byKey(const Key('feeding-notification-switch')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.text('系统通知未开启，应用内提醒仍然保留'), findsOneWidget);
          expect((await store.load('reminder-visual-owner')).enabled, isFalse);
          await capture('m7-feeding-settings-$mode');
          await tester.pageBack();
          await tester.pump(const Duration(milliseconds: 500));
          expect(find.text('晚餐时间'), findsOneWidget);
          await tester.tap(find.byTooltip('收起今日提醒'));
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('晚餐时间'), findsNothing);
          expect(acks, 1);
          expect(tester.takeException(), isNull);
          totalAcks += acks;
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
        }
        binding.reportData = {
          'result': 'PASS',
          'themes': 2,
          'inAppAcknowledgments': totalAcks,
          'hiddenHomeDoesNotAcknowledge': true,
          'permissionDenialUsesMemoryFixture': true,
          'nativeInvalidPostRejected': true,
          'nativeChannelRegistrationVerifiedDirectly': true,
          'nativePermissionInitiallyAllowed': permissionInitiallyAllowed,
          'actualSystemNotificationDeliveryTested': false,
          'backgroundScheduleTested': false,
          'captureHandshakeRun': captureRun,
          'captureMethod':
              'ADB Android screen with fresh per-stage acknowledgment',
          'businessWrites': 0,
          'physicalPhoneTouched': false,
        };
      } finally {
        await tester.pumpWidget(const SizedBox());
        await db.close();
        if (await stageFile.exists()) await stageFile.delete();
        if (await ackFile.exists()) await ackFile.delete();
      }
    },
  );
}
