import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (Platform.environment['M6_ART_REVISION'] == 'v2' &&
          !name.startsWith('m6-v2-')) {
        name = name.replaceFirst('m6-', 'm6-v2-');
      }
      await File('docs/evidence/$name.png').writeAsBytes(bytes);
      return true;
    },
  );
}
