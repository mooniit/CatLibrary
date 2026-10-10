import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

abstract class FeedingNotifications {
  bool get supported;
  Future<bool> requestPermission();
  Future<bool> isAllowed();
  Future<bool> show(String owner, String day, List<String> names);
  Future<void> update(String owner, String day, List<String> names);
  Future<void> cancel(String owner);
}

class NativeFeedingNotifications extends FeedingNotifications {
  static const channel = MethodChannel('cat_library/feeding_reminders');
  @override
  bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  Future<bool> _call(String method, [Map<String, Object>? args]) async {
    if (!supported) return false;
    try {
      return await channel.invokeMethod<bool>(method, args) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() => _call('requestPermission');
  @override
  Future<bool> isAllowed() => _call('isAllowed');
  Map<String, Object> _payload(String owner, String day, List<String> names) =>
      {'ownerId': owner, 'businessDay': day, 'names': names};
  @override
  Future<bool> show(String owner, String day, List<String> names) =>
      _call('show', _payload(owner, day, names));
  @override
  Future<void> update(String owner, String day, List<String> names) async {
    await _call('update', _payload(owner, day, names));
  }

  @override
  Future<void> cancel(String owner) async {
    await _call('cancel', {'ownerId': owner});
  }
}
