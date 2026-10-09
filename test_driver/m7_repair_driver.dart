import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final screenshots = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(
        r'^m7-repair-(active|offline|complete)-(light|night)$',
      ).hasMatch(name)) {
        throw StateError('Unexpected repair screenshot');
      }
      await File('docs/evidence/$name.png').writeAsBytes(bytes);
      screenshots.add(name);
      return true;
    },
    responseDataCallback: (data) async {
      if (data?['result'] != 'PASS' || screenshots.length != 6) {
        throw StateError('Fresh repair report and six screenshots required');
      }
      final report = Map<String, dynamic>.from(data!)..remove('screenshots');
      report['screenshots'] = screenshots.toList();
      await File('docs/evidence/m7-repair-ui-native.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
    },
  );
}
