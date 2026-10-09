import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final captured = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(
        r'^m7-cloud-native-(shop|update|refreshed)$',
      ).hasMatch(name)) {
        throw StateError('Unexpected native cloud screenshot filename');
      }
      await File('docs/evidence/$name.png').writeAsBytes(bytes);
      captured.add(name);
      return true;
    },
    responseDataCallback: (data) async {
      if (data == null ||
          data['result'] != 'PASS' ||
          data['productionCatalog'] != true) {
        throw StateError('Native hosted commerce evidence missing');
      }
      if (captured.length != 3) {
        throw StateError('All three fresh native screenshots are required');
      }
      final report = Map<String, dynamic>.from(data)..remove('screenshots');
      await File('docs/evidence/m7-cloud-native-commerce.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert({'verifiedAt': DateTime.now().toUtc().toIso8601String(), ...report, 'freshScreenshots': captured.toList()})}\n',
      );
    },
  );
}
