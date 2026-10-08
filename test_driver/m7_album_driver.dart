import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^m7-album-[a-z0-9-]+$').hasMatch(name)) {
        throw StateError('Unexpected album evidence filename');
      }
      await File('docs/evidence/$name.png').writeAsBytes(bytes);
      return true;
    },
    responseDataCallback: (data) async {
      if (data == null) throw StateError('Native evidence missing');
      final batch = data['assetBatch'];
      if (batch is! int || batch < 1 || batch > 4) {
        throw StateError('Unexpected travel asset batch');
      }
      final report = {
        for (final field in [
          'nativeVisualTestPassed',
          'assetBatch',
          'fixtureOnly',
          'measurements',
          'allTravelPairsRendered',
          'completeAlbumViews',
          'remoteInternetVerified',
          'physicalPhoneVerified',
        ])
          field: data[field],
      };
      await File(
        'docs/evidence/m7-album-batch$batch-native.json',
      ).writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
    },
  );
}
