import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Preserves the local session while recovering the same migrated anonymous user.
/// This does not copy accounts, wallets or family assets to the hosted database.
class LegacySessionRecovery {
  static const _cloud = 'https://ludwvhsvknjgblfgouor.supabase.co';
  static const _legacyIssuer = 'http://127.0.0.1:54321/auth/v1';
  static const _legacyKey = 'sb-127-auth-token';
  static const _cloudKey = 'sb-ludwvhsvknjgblfgouor-auth-token';

  static Future<bool> recover({
    required String targetUrl,
    required String publicKey,
    required SharedPreferences preferences,
    required http.Client transport,
    required Future<void> Function(String) restoreSession,
    String? rememberedOwner,
    Iterable<String> cachedOwners = const [],
  }) async {
    // Never forward an existing refresh credential to arbitrary configuration.
    if (targetUrl != _cloud) return false;
    final original = preferences.getString(_legacyKey);
    if (original == null) return false;
    try {
      final local = _session(original, _legacyIssuer);
      final owner = (local['user'] as Map)['id'] as String;
      final cached = cachedOwners.toSet();
      if (rememberedOwner != null && rememberedOwner != owner ||
          cached.isNotEmpty && !cached.contains(owner) ||
          rememberedOwner == null && cached.length > 1) {
        throw const FormatException();
      }
      final request =
          http.Request(
              'POST',
              Uri.parse('$_cloud/auth/v1/token?grant_type=refresh_token'),
            )
            ..followRedirects = false
            ..headers.addAll({
              'apikey': publicKey,
              'Content-Type': 'application/json',
            })
            ..body = jsonEncode({'refresh_token': local['refresh_token']});
      final response = await http.Response.fromStream(
        await transport.send(request).timeout(const Duration(seconds: 12)),
      ).timeout(const Duration(seconds: 12));
      if (response.statusCode != 200) throw const FormatException();
      final restored = _session(response.body, '$_cloud/auth/v1');
      if ((restored['user'] as Map)['id'] != owner) {
        throw const FormatException();
      }
      final receipt = jsonEncode(restored);
      // Persist the successful receipt before entering the SDK. An interrupted
      // restore can reopen this cloud session without losing either identity.
      if (!await preferences.setString(_cloudKey, receipt)) {
        throw StateError('Session receipt could not be saved');
      }
      await restoreSession(receipt);
      return true;
    } catch (_) {
      // Do not include server error bodies, refresh tokens or SDK errors.
      throw StateError('原账户云端会话待恢复，已保留本地记录。请核对账户迁移及网络后重试。');
    }
  }

  static Map<String, dynamic> _session(String value, String issuer) {
    final data = jsonDecode(value) as Map<String, dynamic>;
    final user = data['user'] as Map;
    final refresh = data['refresh_token'];
    final access = data['access_token'] as String;
    final segments = access.split('.');
    if (segments.length != 3 ||
        refresh is! String ||
        refresh.isEmpty ||
        user['is_anonymous'] != true ||
        user['id'] is! String) {
      throw const FormatException();
    }
    final claims =
        jsonDecode(
              utf8.decode(base64Url.decode(base64Url.normalize(segments[1]))),
            )
            as Map;
    // The HTTPS Auth response is trusted; these checks prevent mixing sessions.
    if (claims['iss'] != issuer || claims['sub'] != user['id']) {
      throw const FormatException();
    }
    return data;
  }
}
