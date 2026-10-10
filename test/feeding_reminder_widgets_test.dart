import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/app/app_theme.dart';
import 'package:cat_library_demo/features/reminders/feeding_reminders.dart';
import 'package:cat_library_demo/features/reminders/reminder_widgets.dart';
import 'feeding_reminders_test.dart'
    show MemoryReminderStore, MemoryFeedingNotifications;

Map<String, dynamic> reminderReceipt() => {
  'status': 'ready',
  'owner_id': 'owner-a',
  'family_id': 'family-a',
  'business_day': '2026-10-10',
  'created_at': '2026-10-10T13:00:00Z',
  'cats': [
    {'id': 'cat-a', 'name': '橘点'},
    {'id': 'cat-b', 'name': '白云'},
  ],
  'in_app_seen': false,
  'notification_seen': false,
};

class DelayedReminderStore extends MemoryReminderStore {
  final first = Completer<ReminderLocalState>();
  @override
  Future<ReminderLocalState> load(String owner) =>
      owner == 'owner-a' ? first.future : super.load(owner);
}

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets(
      'banner visible delivery, navigation and close at 320px $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = MemoryReminderStore();
        var acknowledgments = 0, opens = 0;
        final controller = FeedingReminderController(
          ownerId: 'owner-a',
          store: store,
          clock: () => DateTime.utc(2026, 10, 10, 13),
          notifications: MemoryFeedingNotifications(),
          rpc: (method, params) async {
            if (method == 'get_feeding_reminder') return reminderReceipt();
            acknowledgments++;
            return {
              'status': 'acknowledged',
              'owner_id': 'owner-a',
              'business_day': params['target_day'],
              'channel': params['target_channel'],
            };
          },
        );
        addTearDown(controller.dispose);
        await controller.refresh();
        Widget page(bool visible) => MaterialApp(
          theme: buildAppTheme(brightness),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FeedingReminderBanner(
                  controller: controller,
                  visible: visible,
                  onOpen: () => opens++,
                ),
              ),
            ),
          ),
        );
        await tester.pumpWidget(page(false));
        await tester.pumpAndSettle();
        expect(acknowledgments, 0);
        expect(find.text('晚餐时间'), findsNothing);
        await tester.pumpWidget(page(true));
        await tester.pumpAndSettle();
        expect(acknowledgments, 1);
        expect(find.text('橘点、白云'), findsOneWidget);
        await tester.tap(find.text('晚餐时间'));
        expect(opens, 1);
        await tester.tap(find.byTooltip('收起今日提醒'));
        await tester.pumpAndSettle();
        expect(find.text('晚餐时间'), findsNothing);
        expect(acknowledgments, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'permission denial preserves in-app choice; grant and disable persist',
    (tester) async {
      final store = MemoryReminderStore();
      final notifications = MemoryFeedingNotifications();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeedingReminderSettings(
              ownerId: 'owner-a',
              store: store,
              notifications: notifications,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final toggle = find.byKey(const Key('feeding-notification-switch'));
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('系统通知未开启，应用内提醒仍然保留'), findsOneWidget);
      expect((await store.load('owner-a')).enabled, isFalse);
      notifications.allowed = true;
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect((await store.load('owner-a')).enabled, isTrue);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect((await store.load('owner-a')).enabled, isFalse);
      expect(notifications.cancels, 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('unread settings are disabled, retained and recover by retry', (
    tester,
  ) async {
    final store = MemoryReminderStore()..fail = true;
    final notifications = MemoryFeedingNotifications()..allowed = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedingReminderSettings(
            ownerId: 'owner-a',
            store: store,
            notifications: notifications,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
    expect(store.states, isEmpty);
    store.fail = false;
    await tester.tap(find.text('提醒设置未读取，点击重试'));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
  });
  testWidgets('old member delayed settings cannot replace the new member', (
    tester,
  ) async {
    final store = DelayedReminderStore();
    final notifications = MemoryFeedingNotifications();
    Widget page(String owner) => MaterialApp(
      home: Scaffold(
        body: FeedingReminderSettings(
          ownerId: owner,
          store: store,
          notifications: notifications,
        ),
      ),
    );
    await tester.pumpWidget(page('owner-a'));
    await tester.pumpWidget(page('owner-b'));
    await tester.pumpAndSettle();
    store.first.complete(ReminderLocalState(enabled: true));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    expect(store.states, isEmpty);
  });
}
