import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android notification display only; never awards currency or writes study time.
class LockScreenTimer {
  static const channel = MethodChannel('cat_library/lock_screen_timer');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static Future<bool> requestPermission() => _invoke('requestPermission');
  static Future<bool> show(DateTime start) =>
      _invoke('show', {'startedAt': start.millisecondsSinceEpoch});
  static Future<void> stop() async {
    await _invoke('stop');
  }

  static Future<bool> _invoke(
    String method, [
    Map<String, Object>? arguments,
  ]) async {
    if (!supported) return false;
    try {
      return await channel.invokeMethod<bool>(method, arguments) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
