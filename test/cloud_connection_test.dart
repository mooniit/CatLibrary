import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cat_library_demo/core/sync/cloud_connection.dart';

void main() {
  test(
    'actual response recovers from offline; cached session is not proof of online',
    () async {
      var fail = true;
      final status = CloudConnection();
      final client = ConnectionHttpClient(
        MockClient((request) async {
          if (fail) throw http.ClientException('unreachable');
          return http.Response('{}', 200);
        }),
        status,
      );
      expect(status.value.phase, CloudPhase.unknown);
      await expectLater(
        client.get(Uri.parse('https://example.test/rest/v1/rpc/state')),
        throwsA(isA<http.ClientException>()),
      );
      expect(status.value.phase, CloudPhase.offline);
      fail = false;
      await client.get(Uri.parse('https://example.test/rest/v1/rpc/state'));
      expect(status.value.phase, CloudPhase.online);
      client.close();
      status.dispose();
    },
  );

  test(
    'server error and expired authentication are distinct from offline',
    () async {
      var code = 503;
      final status = CloudConnection();
      final client = ConnectionHttpClient(
        MockClient((_) async => http.Response('{}', code)),
        status,
      );
      final url = Uri.parse('https://example.test/rest/v1/rpc/state');
      await client.get(url);
      expect(status.value.phase, CloudPhase.serviceUnavailable);
      code = 401;
      await client.get(url);
      expect(status.value.phase, CloudPhase.authenticationRequired);
      code = 403;
      await client.get(url);
      expect(
        status.value.phase,
        CloudPhase.online,
        reason: 'membership refusal is still a reachable service',
      );
      client.close();
      status.dispose();
    },
  );

  test(
    'late old failure cannot replace evidence from newer successful request',
    () async {
      final old = Completer<http.Response>();
      final status = CloudConnection();
      final client = ConnectionHttpClient(
        MockClient(
          (r) async =>
              r.url.path == '/old' ? old.future : http.Response('{}', 200),
        ),
        status,
      );
      final request = client.get(Uri.parse('https://example.test/old'));
      final assertion = expectLater(
        request,
        throwsA(isA<http.ClientException>()),
      );
      await client.get(Uri.parse('https://example.test/new'));
      old.completeError(http.ClientException('late failure'));
      await assertion;
      expect(status.value.phase, CloudPhase.online);
      client.close();
      status.dispose();
    },
  );

  test(
    'request timeout preserves a meaningful offline state and can retry',
    () async {
      var hang = true;
      final status = CloudConnection();
      final client = ConnectionHttpClient(
        MockClient(
          (_) async => hang
              ? Completer<http.Response>().future
              : http.Response('{}', 200),
        ),
        status,
        timeout: const Duration(milliseconds: 20),
      );
      await expectLater(
        client.get(Uri.parse('https://example.test/rest/v1/rpc/state')),
        throwsA(isA<TimeoutException>()),
      );
      expect(status.value.phase, CloudPhase.offline);
      hang = false;
      await client.get(Uri.parse('https://example.test/rest/v1/rpc/state'));
      expect(status.value.phase, CloudPhase.online);
      client.close();
      status.dispose();
    },
  );

  test(
    'endpoint diagnostics distinguish local test address from remote service',
    () {
      expect(CloudConnection.isLocalEndpoint('http://127.0.0.1:54321'), true);
      expect(CloudConnection.isLocalEndpoint('http://localhost:54321'), true);
      expect(
        CloudConnection.isLocalEndpoint('https://project.supabase.co'),
        false,
      );
    },
  );
}
