import 'dart:convert';

import 'package:cat_library_demo/core/sync/legacy_session_recovery.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const cloud = 'https://ludwvhsvknjgblfgouor.supabase.co';
const oldIssuer = 'http://127.0.0.1:54321/auth/v1';
const owner = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const other = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
const oldKey = 'sb-127-auth-token';
const newKey = 'sb-ludwvhsvknjgblfgouor-auth-token';

String jwt(String issuer, String subject) {
  String part(Map<String, Object> data) =>
      base64Url.encode(utf8.encode(jsonEncode(data))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part({'iss': issuer, 'sub': subject})}.signature';
}

Map<String, dynamic> session({
  String issuer = oldIssuer,
  String user = owner,
  bool anonymous = true,
}) => {
  'access_token': jwt(issuer, user),
  'refresh_token': 'private-refresh-fixture',
  'expires_in': 3600,
  'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
  'token_type': 'bearer',
  'user': {'id': user, 'is_anonymous': anonymous},
};

void main() {
  late SharedPreferences prefs;
  late String original;
  setUp(() async {
    original = jsonEncode(session());
    SharedPreferences.setMockInitialValues({oldKey: original});
    prefs = await SharedPreferences.getInstance();
  });

  Future<bool> recover(
    http.Client transport, {
    String target = cloud,
    String? remembered = owner,
    Iterable<String> cached = const [owner],
    Future<void> Function(String)? restore,
  }) => LegacySessionRecovery.recover(
    targetUrl: target,
    publicKey: 'publishable-test-key',
    preferences: prefs,
    transport: transport,
    rememberedOwner: remembered,
    cachedOwners: cached,
    restoreSession: restore ?? (_) async {},
  );

  test(
    'refreshes the same owner and retains the complete local session',
    () async {
      String? restored;
      final client = MockClient((request) async {
        expect(
          request.url.toString(),
          '$cloud/auth/v1/token?grant_type=refresh_token',
        );
        expect(request.followRedirects, isFalse);
        expect(request.headers['apikey'], 'publishable-test-key');
        expect(request.headers.containsKey('authorization'), isFalse);
        expect(jsonDecode(request.body), {
          'refresh_token': 'private-refresh-fixture',
        });
        return http.Response(
          jsonEncode(session(issuer: '$cloud/auth/v1')),
          200,
        );
      });
      expect(
        await recover(client, restore: (value) async => restored = value),
        isTrue,
      );
      expect(jsonDecode(restored!)['user']['id'], owner);
      expect(prefs.getString(oldKey), original);
      expect(prefs.getString(newKey), restored);
    },
  );

  test(
    'a first installation without a legacy session performs no handoff',
    () async {
      await prefs.remove(oldKey);
      expect(
        await recover(MockClient((_) async => throw StateError('No request'))),
        isFalse,
      );
    },
  );

  test(
    'local endpoints and unrelated hosts never receive a legacy credential',
    () async {
      for (final target in [
        'http://127.0.0.1:54321',
        'http://ludwvhsvknjgblfgouor.supabase.co',
        'https://another.supabase.co',
        '$cloud/other',
        '$cloud@evil.example',
      ]) {
        expect(
          await recover(
            MockClient((_) async => throw StateError('No request')),
            target: target,
          ),
          isFalse,
        );
      }
      expect(prefs.getString(oldKey), original);
    },
  );

  test(
    'the remembered owner and cache must both match the legacy owner',
    () async {
      for (final histories in [
        (other, <String>[owner]),
        (owner, <String>[other]),
        (null, <String>[owner, other]),
      ]) {
        await expectLater(
          recover(
            MockClient((_) async => throw StateError('No request')),
            remembered: histories.$1,
            cached: histories.$2,
          ),
          throwsStateError,
        );
        expect(prefs.getString(newKey), isNull);
      }
    },
  );

  test(
    'a single cached owner can recover without the preferences marker',
    () async {
      expect(
        await recover(
          MockClient(
            (_) async => http.Response(
              jsonEncode(session(issuer: '$cloud/auth/v1')),
              200,
            ),
          ),
          remembered: null,
        ),
        isTrue,
      );
    },
  );

  test(
    'corrupt, nonanonymous and wrong-issuer source sessions cannot refresh',
    () async {
      for (final value in [
        'invalid-json',
        jsonEncode(session(anonymous: false)),
        jsonEncode(session(issuer: 'https://another.supabase.co/auth/v1')),
        jsonEncode({...session(), 'access_token': 'invalid-token'}),
      ]) {
        await prefs.setString(oldKey, value);
        await expectLater(
          recover(MockClient((_) async => throw StateError('No request'))),
          throwsStateError,
        );
        expect(prefs.getString(oldKey), value);
        expect(prefs.getString(newKey), isNull);
      }
    },
  );

  test(
    'missing cloud identity and network failure retain local credentials',
    () async {
      for (final client in [
        MockClient((_) async => http.Response('sensitive-server-error', 400)),
        MockClient((_) async => http.Response('', 302)),
        MockClient((_) async => throw http.ClientException('private detail')),
      ]) {
        await expectLater(recover(client), throwsStateError);
        expect(prefs.getString(oldKey), original);
        expect(prefs.getString(newKey), isNull);
      }
    },
  );

  test(
    'wrong user or token issuer is rejected before SDK persistence',
    () async {
      for (final reply in [
        session(issuer: '$cloud/auth/v1', user: other),
        session(),
        {...session(issuer: '$cloud/auth/v1'), 'refresh_token': ''},
        {
          ...session(issuer: '$cloud/auth/v1'),
          'user': {'id': owner, 'is_anonymous': false},
        },
        {
          ...session(issuer: '$cloud/auth/v1'),
          'access_token': jwt('$cloud/auth/v1', other),
        },
      ]) {
        await expectLater(
          recover(
            MockClient((_) async => http.Response(jsonEncode(reply), 200)),
            restore: (_) async => fail('Must not restore invalid identity'),
          ),
          throwsStateError,
        );
        expect(prefs.getString(newKey), isNull);
        expect(prefs.getString(oldKey), original);
      }
    },
  );

  test(
    'SDK restore failure retains a valid cloud receipt and the local session',
    () async {
      await expectLater(
        recover(
          MockClient(
            (_) async => http.Response(
              jsonEncode(session(issuer: '$cloud/auth/v1')),
              200,
            ),
          ),
          restore: (_) async => throw StateError('SDK restore failed'),
        ),
        throwsStateError,
      );
      expect(jsonDecode(prefs.getString(newKey)!)['user']['id'], owner);
      expect(prefs.getString(oldKey), original);
    },
  );
}
