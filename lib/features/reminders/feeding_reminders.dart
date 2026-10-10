import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/sync/cloud_client.dart';
import '../../core/notifications/feeding_notifications.dart';

typedef ReminderRpc =
    Future<Map<String, dynamic>> Function(String, Map<String, dynamic>);
String beijingDay(DateTime value) => value
    .toUtc()
    .add(const Duration(hours: 8))
    .toIso8601String()
    .substring(0, 10);

bool _validDay(Object? value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    return false;
  }
  final parsed = DateTime.tryParse(value);
  return parsed != null && parsed.toIso8601String().substring(0, 10) == value;
}

class FeedingReminder {
  FeedingReminder.fromJson(Map<String, dynamic> raw, String owner)
    : day = raw['business_day'] as String,
      names = [
        for (final cat in raw['cats'] as List) (cat as Map)['name'] as String,
      ],
      inAppSeen = raw['in_app_seen'] as bool,
      notificationSeen = raw['notification_seen'] as bool {
    final cats = raw['cats'] as List;
    final created = DateTime.tryParse(raw['created_at']?.toString() ?? '');
    if (raw['owner_id'] != owner ||
        raw['family_id'] is! String ||
        (raw['family_id'] as String).isEmpty ||
        !_validDay(day) ||
        created == null ||
        beijingDay(created) != day ||
        created.toUtc().add(const Duration(hours: 8)).hour < 21 ||
        cats.isEmpty ||
        cats.length > 2 ||
        names.any((name) => name.trim().isEmpty) ||
        cats.any(
          (cat) => cat['id'] is! String || (cat['id'] as String).isEmpty,
        ) ||
        cats.map((cat) => cat['id']).toSet().length != cats.length) {
      throw StateError('Invalid feeding reminder');
    }
  }
  final String day;
  final List<String> names;
  final bool inAppSeen, notificationSeen;
}

class ReminderLocalState {
  ReminderLocalState({
    this.enabled = false,
    Set<String>? delivered,
    Set<String>? pending,
  }) : delivered = delivered ?? {},
       pending = pending ?? {};
  bool enabled;
  final Set<String> delivered, pending;
}

abstract class ReminderStore {
  Future<ReminderLocalState> load(String owner);
  Future<void> update(
    String owner, {
    bool? enabled,
    String? delivered,
    String? acknowledged,
  });
}

/// Merge changes under one owner lock: toggling settings cannot erase an acknowledgment.
class PreferencesReminderStore extends ReminderStore {
  PreferencesReminderStore({
    Future<String?> Function(String)? read,
    Future<void> Function(String, String)? write,
  }) : _read = read,
       _write = write;
  static final _writes = <String, Future<void>>{};
  final Future<String?> Function(String)? _read;
  final Future<void> Function(String, String)? _write;
  late final _preferences = SharedPreferencesAsync();
  String _key(String owner) => 'feeding_reminders_$owner';
  @override
  Future<ReminderLocalState> load(String owner) async {
    final text =
        await (_read?.call(_key(owner)) ?? _preferences.getString(_key(owner)));
    if (text == null) return ReminderLocalState();
    final raw = jsonDecode(text) as Map;
    final delivered = Set<String>.from(raw['delivered'] as List);
    final pending = Set<String>.from(raw['pending'] as List);
    bool valid(String key) {
      final parts = key.split('/');
      return parts.length == 2 &&
          _validDay(parts[0]) &&
          {'in_app', 'notification'}.contains(parts[1]);
    }

    if (raw['enabled'] is! bool ||
        !delivered.every(valid) ||
        !pending.every(valid) ||
        !delivered.containsAll(pending)) {
      throw StateError('Reminder settings require recovery');
    }
    return ReminderLocalState(
      enabled: raw['enabled'] as bool,
      delivered: delivered,
      pending: pending,
    );
  }

  @override
  Future<void> update(
    String owner, {
    bool? enabled,
    String? delivered,
    String? acknowledged,
  }) {
    final previous = _writes[owner] ?? Future<void>.value();
    final next = previous.catchError((Object _) {}).then((_) async {
      final state = await load(owner);
      if (enabled != null) state.enabled = enabled;
      if (delivered != null) {
        state.delivered.add(delivered);
        state.pending.add(delivered);
      }
      if (acknowledged != null) state.pending.remove(acknowledged);
      final text = jsonEncode({
        'enabled': state.enabled,
        'delivered': state.delivered.toList(),
        'pending': state.pending.toList(),
      });
      if (_write != null) {
        await _write(_key(owner), text);
      } else {
        await _preferences.setString(_key(owner), text);
      }
    });
    _writes[owner] = next;
    return next.whenComplete(() {
      if (identical(_writes[owner], next)) _writes.remove(owner);
    });
  }
}

class FeedingReminderController extends ChangeNotifier {
  FeedingReminderController({
    required this.ownerId,
    ReminderRpc? rpc,
    ReminderStore? store,
    FeedingNotifications? notifications,
    DateTime Function()? clock,
  }) : _rpc = rpc,
       store = store ?? PreferencesReminderStore(),
       notifications = notifications ?? NativeFeedingNotifications(),
       clock = clock ?? DateTime.now;
  final String ownerId;
  final ReminderRpc? _rpc;
  final ReminderStore store;
  final FeedingNotifications notifications;
  final DateTime Function() clock;
  FeedingReminder? reminder;
  bool hasError = false;
  bool _disposed = false;
  bool _paused = false;
  int _generation = 0;
  String? _shownDay, _dismissedDay, _notificationContent;
  Future<void>? _refreshing;
  Future<bool>? _presenting;
  Timer? _poll;

  void resume() {
    if (_disposed) return;
    _paused = false;
    _poll ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => unawaited(refresh()),
    );
    unawaited(refresh());
  }

  void pause() {
    _paused = true;
    _generation++;
    _refreshing = null;
    _poll?.cancel();
    _poll = null;
  }

  @override
  void dispose() {
    _disposed = true;
    pause();
    super.dispose();
  }

  Future<Map<String, dynamic>> _call(
    String method,
    Map<String, dynamic> params,
  ) async {
    if (_rpc != null) return _rpc(method, params);
    final client = await CloudClient.connect();
    if (client.auth.currentUser?.id != ownerId) {
      throw StateError('Reminder identity changed');
    }
    final raw = Map<String, dynamic>.from(
      await client
              .rpc(method, params: params)
              .timeout(const Duration(seconds: 8))
          as Map,
    );
    if (client.auth.currentUser?.id != ownerId) {
      throw StateError('Reminder identity changed');
    }
    return raw;
  }

  Future<void> _ack(String key) async {
    if (_disposed) return;
    try {
      final parts = key.split('/');
      final result = await _call('ack_feeding_reminder', {
        'target_day': parts[0],
        'target_channel': parts[1],
      });
      if (_disposed) return;
      if (result['owner_id'] != ownerId ||
          result['business_day'] != parts[0] ||
          result['channel'] != parts[1] ||
          !{'acknowledged', 'not_found'}.contains(result['status'])) {
        throw StateError('Invalid acknowledgment');
      }
      await store.update(ownerId, acknowledged: key);
    } catch (_) {
      /* Keep the exact date/channel until a formal response arrives. */
    }
  }

  Future<void> refresh() {
    if (_disposed || _paused) return Future<void>.value();
    if (_refreshing != null) return _refreshing!;
    final request = _refresh();
    _refreshing = request;
    return request.whenComplete(() {
      if (identical(_refreshing, request)) _refreshing = null;
    });
  }

  Future<void> _refresh() async {
    final generation = _generation;
    bool current() => !_disposed && !_paused && generation == _generation;
    var expired = false;
    if (reminder?.day != null && reminder!.day != beijingDay(clock())) {
      reminder = null;
      expired = true;
      notifyListeners();
    }
    try {
      if (expired) await notifications.cancel(ownerId);
      final local = await store.load(ownerId);
      if (!current()) return;
      for (final key in local.pending.toList()) {
        await _ack(key);
      }
      if (!current()) return;
      final raw = await _call('get_feeding_reminder', const {});
      if (!current()) return;
      if (!_validDay(raw['business_day']) ||
          !{'ready', 'empty', 'before_time'}.contains(raw['status'])) {
        throw StateError('Unknown reminder response');
      }
      hasError = false;
      final latest = raw['status'] == 'ready'
          ? FeedingReminder.fromJson(raw, ownerId)
          : null;
      if (latest == null || latest.day != beijingDay(clock())) {
        reminder = null;
        _notificationContent = null;
        await notifications.cancel(ownerId);
      } else {
        final seen =
            latest.inAppSeen ||
            local.delivered.contains('${latest.day}/in_app');
        reminder =
            _dismissedDay == latest.day || (seen && _shownDay != latest.day)
            ? null
            : latest;
        if (!local.enabled) {
          await notifications.cancel(ownerId);
        } else if (notifications.supported &&
            await notifications.isAllowed() &&
            current()) {
          final key = '${latest.day}/notification';
          final content = '${latest.day}/${latest.names.join('、')}';
          if (latest.notificationSeen || local.delivered.contains(key)) {
            if (_notificationContent != content) {
              await notifications.update(ownerId, latest.day, latest.names);
            }
          } else if (await notifications.show(
                ownerId,
                latest.day,
                latest.names,
              ) &&
              !_disposed) {
            await store.update(ownerId, delivered: key);
            await _ack(key);
          }
          _notificationContent = content;
        }
      }
    } catch (_) {
      if (current()) hasError = true;
    }
    if (current()) notifyListeners();
  }

  /// Called after the visible banner paints, never merely because HomePage is mounted.
  Future<bool> present(String day) {
    if (_disposed ||
        _paused ||
        hasError ||
        reminder?.day != day ||
        beijingDay(clock()) != day) {
      return Future<bool>.value(false);
    }
    if (_shownDay == day) return Future<bool>.value(true);
    return _presenting ??= _present(day).whenComplete(() => _presenting = null);
  }

  Future<bool> _present(String day) async {
    try {
      final key = '$day/in_app';
      await store.update(ownerId, delivered: key);
      if (_disposed || _paused) return false;
      _shownDay = day;
      await _ack(key);
      return true;
    } catch (_) {
      if (!_disposed) {
        hasError = true;
        notifyListeners();
      }
      return false;
    }
  }

  Future<void> dismiss(String day) async {
    if (!await present(day) || _disposed || reminder?.day != day) return;
    _dismissedDay = day;
    reminder = null;
    notifyListeners();
  }
}
