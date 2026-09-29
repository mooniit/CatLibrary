import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'study_session.dart';

/// Android display and native recovery evidence; never awards currency.
class LockScreenTimer {
  static const channel = MethodChannel('cat_library/lock_screen_timer');
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static Future<bool> requestPermission() => _invoke('requestPermission');
  static Future<bool> isActive() => _invoke('isActive');
  static Future<bool> show(
    DateTime start, {
    String? sessionId,
    String? ownerId,
    Duration displayElapsed = Duration.zero,
    Duration? countdownRemaining,
    Duration? maximumRemaining,
    String? title,
  }) => _invoke('show', {
    'startedAt': start.millisecondsSinceEpoch,
    'sessionId': ?sessionId,
    'ownerId': ?ownerId,
    'displayElapsedMs': displayElapsed.inMilliseconds,
    'countdownRemainingMs': ?countdownRemaining?.inMilliseconds,
    'maximumRemainingMs': ?maximumRemaining?.inMilliseconds,
    'title': ?title,
  });
  static Future<void> stop() async {
    await _invoke('stop');
  }

  static Future<StudySession?> readCheckpoint() async {
    if (!supported) return null;
    try {
      final raw = await channel.invokeMapMethod<String, dynamic>(
        'readCheckpoint',
      );
      if (raw == null) return null;
      return StudySession(
        id: raw['id'] as String,
        ownerId: raw['ownerId'] as String,
        startedAt: DateTime.fromMillisecondsSinceEpoch(
          raw['startedAt'] as int,
          isUtc: true,
        ),
        recordedUntil: DateTime.fromMillisecondsSinceEpoch(
          raw['recordedUntil'] as int,
          isUtc: true,
        ),
        state: StudySessionState.running,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    } on ArgumentError {
      return null;
    }
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
