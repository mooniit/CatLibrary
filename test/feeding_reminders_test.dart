import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:cat_library_demo/features/reminders/feeding_reminders.dart';
import 'package:cat_library_demo/core/notifications/feeding_notifications.dart';

class MemoryReminderStore extends ReminderStore {
  final states = <String, ReminderLocalState>{};
  bool fail = false;
  @override
  Future<ReminderLocalState> load(String owner) async {
    if (fail) throw StateError('disk unavailable');
    return states[owner] ?? ReminderLocalState();
  }

  @override
  Future<void> update(
    String owner, {
    bool? enabled,
    String? delivered,
    String? acknowledged,
  }) async {
    if (fail) throw StateError('disk unavailable');
    final current = states.putIfAbsent(owner, ReminderLocalState.new);
    if (enabled != null) current.enabled = enabled;
    if (delivered != null) {
      current.delivered.add(delivered);
      current.pending.add(delivered);
    }
    if (acknowledged != null) current.pending.remove(acknowledged);
  }
}

class MemoryFeedingNotifications extends FeedingNotifications {
  @override
  bool get supported => true;
  bool allowed = false;
  int shows = 0, updates = 0, cancels = 0;
  @override
  Future<bool> requestPermission() async => allowed;
  @override
  Future<bool> isAllowed() async => allowed;
  @override
  Future<bool> show(String owner, String day, List<String> names) async {
    if (!allowed) return false;
    shows++;
    return true;
  }

  @override
  Future<void> update(String owner, String day, List<String> names) async {
    updates++;
  }

  @override
  Future<void> cancel(String owner) async {
    cancels++;
  }
}

void main() {
  final now = DateTime.utc(2026, 10, 10, 13);
  Map<String, dynamic> ready({
    String owner = 'owner-a',
    List<String> names = const ['橘点', '白云'],
  }) => {
    'status': 'ready',
    'owner_id': owner,
    'family_id': 'home-a',
    'business_day': '2026-10-10',
    'created_at': now.toIso8601String(),
    'cats': [
      for (var i = 0; i < names.length; i++) {'id': 'cat-$i', 'name': names[i]},
    ],
    'in_app_seen': false,
    'notification_seen': false,
  };
  Map<String, dynamic> ack(Map<String, dynamic> params) => {
    'status': 'acknowledged',
    'owner_id': 'owner-a',
    'business_day': params['target_day'],
    'channel': params['target_channel'],
  };
  test(
    'two store instances merge settings and delivery; another owner remains separate',
    () async {
      final bytes = <String, String>{};
      Future<String?> read(String key) async {
        await Future<void>.delayed(Duration.zero);
        return bytes[key];
      }

      Future<void> write(String key, String value) async {
        await Future<void>.delayed(Duration.zero);
        bytes[key] = value;
      }

      final first = PreferencesReminderStore(read: read, write: write);
      final settings = PreferencesReminderStore(read: read, write: write);
      await Future.wait([
        first.update('owner-a', delivered: '2026-10-10/in_app'),
        settings.update('owner-a', enabled: true),
      ]);
      final state = await first.load('owner-a');
      expect(state.enabled, isTrue);
      expect(state.pending, {'2026-10-10/in_app'});
      expect((await first.load('owner-b')).delivered, isEmpty);
    },
  );
  test(
    'corrupt local reminder data is retained, never silently reset',
    () async {
      var writes = 0;
      final store = PreferencesReminderStore(
        read: (_) async => '{broken',
        write: (_, _) async {
          writes++;
        },
      );
      await expectLater(
        store.update('owner-a', enabled: true),
        throwsFormatException,
      );
      expect(writes, 0);
    },
  );
  test(
    'only visible presentation consumes the daily application reminder; restart does not repeat',
    () async {
      final store = MemoryReminderStore();
      final calls = <String>[];
      Future<Map<String, dynamic>> rpc(
        String method,
        Map<String, dynamic> params,
      ) async {
        calls.add(method);
        return method == 'get_feeding_reminder' ? ready() : ack(params);
      }

      final first = FeedingReminderController(
        ownerId: 'owner-a',
        rpc: rpc,
        store: store,
        notifications: MemoryFeedingNotifications(),
        clock: () => now,
      );
      addTearDown(first.dispose);
      await first.refresh();
      expect(first.reminder?.names, ['橘点', '白云']);
      expect((await store.load('owner-a')).delivered, isEmpty);
      await first.present('2026-10-10');
      await first.present('2026-10-10');
      expect(calls.where((m) => m == 'ack_feeding_reminder').length, 1);
      await first.refresh();
      expect(first.reminder, isNotNull);
      final restarted = FeedingReminderController(
        ownerId: 'owner-a',
        rpc: rpc,
        store: store,
        notifications: MemoryFeedingNotifications(),
        clock: () => now,
      );
      addTearDown(restarted.dispose);
      await restarted.refresh();
      expect(restarted.reminder, isNull);
    },
  );
  test(
    'lost acknowledgment retains the original date/channel and does not redisplay',
    () async {
      final store = MemoryReminderStore();
      var lose = true;
      final requests = <Map<String, dynamic>>[];
      final controller = FeedingReminderController(
        ownerId: 'owner-a',
        store: store,
        notifications: MemoryFeedingNotifications(),
        clock: () => now,
        rpc: (method, params) async {
          if (method == 'get_feeding_reminder') return ready();
          requests.add(params);
          if (lose) throw StateError('receipt lost');
          return ack(params);
        },
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await controller.present('2026-10-10');
      expect((await store.load('owner-a')).pending, {'2026-10-10/in_app'});
      lose = false;
      await controller.refresh();
      expect(requests.length, 2);
      expect(requests.first, requests.last);
      expect((await store.load('owner-a')).pending, isEmpty);
    },
  );
  test(
    'permission rejection leaves application reminder and does not acknowledge notification',
    () async {
      final store = MemoryReminderStore();
      await store.update('owner-a', enabled: true);
      final notifications = MemoryFeedingNotifications();
      final controller = FeedingReminderController(
        ownerId: 'owner-a',
        store: store,
        notifications: notifications,
        clock: () => now,
        rpc: (method, params) async =>
            method == 'get_feeding_reminder' ? ready() : ack(params),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await controller.present('2026-10-10');
      expect(controller.reminder, isNotNull);
      expect(notifications.shows, 0);
      expect((await store.load('owner-a')).delivered, {'2026-10-10/in_app'});
      notifications.allowed = true;
      await controller.refresh();
      await controller.refresh();
      expect(notifications.shows, 1);
      expect(
        (await store.load('owner-a')).delivered,
        contains('2026-10-10/notification'),
      );
    },
  );
  test(
    'feeding removes cats, all fed cancels notification, midnight clears stale offline reminder',
    () async {
      var moment = now;
      Map<String, dynamic> response = ready();
      final notifications = MemoryFeedingNotifications()..allowed = true;
      final store = MemoryReminderStore();
      await store.update('owner-a', enabled: true);
      final controller = FeedingReminderController(
        ownerId: 'owner-a',
        store: store,
        notifications: notifications,
        clock: () => moment,
        rpc: (method, params) async =>
            method == 'get_feeding_reminder' ? response : ack(params),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await controller.present('2026-10-10');
      response = ready(names: ['白云']);
      await controller.refresh();
      expect(controller.reminder?.names, ['白云']);
      expect(notifications.updates, 1);
      response = {'status': 'empty', 'business_day': '2026-10-10'};
      await controller.refresh();
      expect(controller.reminder, isNull);
      expect(notifications.cancels, greaterThan(0));
      response = ready();
      moment = DateTime.utc(2026, 10, 10, 16);
      await controller.refresh();
      expect(controller.reminder, isNull);
    },
  );
  test(
    'foreign and malformed receipts are rejected without claiming delivery',
    () async {
      final store = MemoryReminderStore();
      Map<String, dynamic> response = ready(owner: 'owner-b');
      final controller = FeedingReminderController(
        ownerId: 'owner-a',
        store: store,
        clock: () => now,
        rpc: (_, _) async => response,
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      expect(controller.hasError, isTrue);
      expect(controller.reminder, isNull);
      response = ready()..['in_app_seen'] = 'false';
      await controller.refresh();
      expect(controller.hasError, isTrue);
      expect((await store.load('owner-a')).delivered, isEmpty);
    },
  );
  test(
    'foreign acknowledgment cannot remove a pending original request',
    () async {
      final store = MemoryReminderStore();
      final controller = FeedingReminderController(
        ownerId: 'owner-a',
        store: store,
        notifications: MemoryFeedingNotifications(),
        clock: () => now,
        rpc: (method, params) async => method == 'get_feeding_reminder'
            ? ready()
            : (ack(params)..['owner_id'] = 'owner-b'),
      );
      addTearDown(controller.dispose);
      await controller.refresh();
      await controller.present('2026-10-10');
      expect((await store.load('owner-a')).pending, {'2026-10-10/in_app'});
    },
  );
  test(
    'single flight and disposal prevent a late snapshot being delivered',
    () async {
      final result = Completer<Map<String, dynamic>>();
      var calls = 0;
      final store = MemoryReminderStore();
      final controller = FeedingReminderController(
        ownerId: 'owner-a',
        store: store,
        clock: () => now,
        rpc: (_, _) {
          calls++;
          return result.future;
        },
      );
      final first = controller.refresh();
      final second = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      controller.dispose();
      result.complete(ready());
      await Future.wait([first, second]);
      expect((await store.load('owner-a')).delivered, isEmpty);
    },
  );
  test(
    'pause rejects late delivery; resume keeps a fresh request single flight',
    () async {
      final old = Completer<Map<String, dynamic>>();
      final fresh = Completer<Map<String, dynamic>>();
      final store = MemoryReminderStore();
      await store.update('owner-a', enabled: true);
      final notifications = MemoryFeedingNotifications()..allowed = true;
      var gets = 0;
      final controller = FeedingReminderController(
        ownerId: 'owner-a',
        store: store,
        notifications: notifications,
        clock: () => now,
        rpc: (method, params) {
          if (method != 'get_feeding_reminder') {
            return Future.value(ack(params));
          }
          gets++;
          return gets == 1 ? old.future : fresh.future;
        },
      );
      addTearDown(controller.dispose);
      final first = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      controller.pause();
      old.complete(ready());
      await first;
      expect(controller.reminder, isNull);
      expect(notifications.shows, 0);
      controller.resume();
      await Future<void>.delayed(Duration.zero);
      final next = controller.refresh();
      expect(gets, 2);
      fresh.complete(ready());
      await next;
      expect(controller.reminder, isNotNull);
      expect(notifications.shows, 1);
      expect((await store.load('owner-a')).pending, isEmpty);
    },
  );
}
