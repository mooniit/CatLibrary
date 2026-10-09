import 'dart:convert';
import 'dart:io';

import 'package:cat_library_demo/core/sync/cloud_connection.dart';
import 'package:cat_library_demo/core/sync/legacy_session_recovery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Private compile-time fixture is only used by this test entry point. No device
// credentials, persistent SQLite, family purchases or settlement calls are used.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'same isolated user recovers a hosted session and a lost receipt',
    (tester) async {
      const url = String.fromEnvironment('SUPABASE_URL');
      const key = String.fromEnvironment('SUPABASE_ANON_KEY');
      const source = String.fromEnvironment('ISOLATED_SOURCE_SESSION');
      const isolated = String.fromEnvironment('ISOLATED_AUTH_FIXTURE');
      expect(isolated == 'true', isTrue);
      expect(url == 'https://ludwvhsvknjgblfgouor.supabase.co', isTrue);
      final oldSession = jsonDecode(source) as Map<String, dynamic>;
      final owner = (oldSession['user'] as Map)['id'] as String;
      const oldKey = 'sb-127-auth-token';
      const newKey = 'sb-ludwvhsvknjgblfgouor-auth-token';
      SharedPreferences.setMockInitialValues({oldKey: source});
      final preferences = await SharedPreferences.getInstance();
      final connection = CloudConnection();
      final raw = http.Client();
      final dropping = _LostRefreshReceiptClient(raw);
      final transport = ConnectionHttpClient(dropping, connection);
      SupabaseClient createClient() => SupabaseClient(
        url,
        key,
        httpClient: transport,
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final first = createClient();
      SupabaseClient? restarted;
      try {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Center(child: Text('独立云端会话恢复验证'))),
          ),
        );
        Future<bool> restore(SupabaseClient client) =>
            LegacySessionRecovery.recover(
              targetUrl: url,
              publicKey: key,
              preferences: preferences,
              transport: transport,
              rememberedOwner: owner,
              cachedOwners: [owner],
              restoreSession: (receipt) async {
                await client.auth.recoverSession(receipt);
              },
            );
        await tester.runAsync(() async {
          await expectLater(restore(first), throwsStateError);
          expect(first.auth.currentUser == null, isTrue);
          expect(preferences.getString(newKey) == null, isTrue);
          expect(preferences.getString(oldKey) == source, isTrue);
          expect(connection.value.phase == CloudPhase.offline, isTrue);
          expect(await restore(first), isTrue);
          expect(first.auth.currentUser?.id == owner, isTrue);
          expect(connection.value.phase == CloudPhase.online, isTrue);
          final user = await first.auth.getUser();
          expect(user.user?.id == owner, isTrue);
          final wallet = await first.rpc('bootstrap_identity') as Map;
          expect(wallet['owner_id'] == owner, isTrue);
          expect(wallet['miao_coins'] == 30, isTrue);
          restarted = createClient();
          await restarted!.auth.recoverSession(preferences.getString(newKey)!);
          expect((await restarted!.auth.getUser()).user?.id == owner, isTrue);
          expect(preferences.getString(oldKey) == source, isTrue);
          binding.reportData = {
            'result': 'PASS',
            'isolatedFixtureOnly': true,
            'sameOwnerVerified': true,
            'lostRefreshReceiptRetried': true,
            'originalLocalSessionRetained': true,
            'cloudSessionReopened': true,
            'realHostedAuthAndBusinessRpc': true,
            'observedOfflineThenOnline': true,
            'originalIdentityMigrated': false,
            'physicalPhoneVerified': false,
          };
        });
      } finally {
        await first.dispose();
        await restarted?.dispose();
        transport.close();
        connection.dispose();
      }
    },
  );
}

class _LostRefreshReceiptClient extends http.BaseClient {
  _LostRefreshReceiptClient(this.delegate);
  final http.Client delegate;
  bool _drop = true;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await delegate.send(request);
    if (_drop &&
        request.url.path == '/auth/v1/token' &&
        response.statusCode == 200) {
      _drop = false;
      await response.stream.drain<void>();
      throw const SocketException('Isolated test dropped the refresh receipt');
    }
    return response;
  }

  @override
  void close() => delegate.close();
}
