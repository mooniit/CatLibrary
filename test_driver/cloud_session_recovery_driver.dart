import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    responseDataCallback: (data) async {
      if (data == null ||
          data['result'] != 'PASS' ||
          data['isolatedFixtureOnly'] != true) {
        throw StateError('Independent session evidence missing');
      }
      final report = {
        'verifiedAt': DateTime.now().toUtc().toIso8601String(),
        for (final field in [
          'result',
          'isolatedFixtureOnly',
          'sameOwnerVerified',
          'lostRefreshReceiptRetried',
          'originalLocalSessionRetained',
          'cloudSessionReopened',
          'realHostedAuthAndBusinessRpc',
          'observedOfflineThenOnline',
          'originalIdentityMigrated',
          'physicalPhoneVerified',
        ])
          field: data[field],
      };
      await File('docs/evidence/m7-cloud-session-native.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
    },
  );
}
