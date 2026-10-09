import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final screenshots = <String>{};
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(
        r'^m7-task-board-(unknown|unknown-records|confirmed|retained)-(light|night)$',
      ).hasMatch(name)) {
        throw StateError('Unexpected task board screenshot');
      }
      await File('docs/evidence/$name.png').writeAsBytes(bytes);
      screenshots.add(name);
      return true;
    },
    responseDataCallback: (data) async {
      if (data?['result'] != 'PASS' || screenshots.length != 8) {
        throw StateError('Fresh task report and eight screenshots required');
      }
      final report = Map<String, dynamic>.from(data!)..remove('screenshots');
      report['screenshots'] = screenshots.toList();
      await File('docs/evidence/m7-task-board-native.json').writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
    },
  );
}
