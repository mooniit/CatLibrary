import 'dart:convert';
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  final screenshots = <String>{};
  final adb =
      '${Directory.current.path}/.tooling/android-sdk/platform-tools/adb.exe';
  const serial = 'emulator-5554';
  const package = 'com.catlibrary.cat_library_demo';
  final captureConfig =
      jsonDecode(
            await File('.tooling/warehouse-capture-config.json').readAsString(),
          )
          as Map;
  final captureRun = captureConfig['WAREHOUSE_CAPTURE_RUN'] as String;
  if (!RegExp(r'^\d{15,20}$').hasMatch(captureRun)) {
    throw StateError('Isolated capture run required');
  }
  var running = true;
  Object? captureError;
  String? runFile;
  Future<ProcessResult> command(List<String> args, {bool bytes = false}) =>
      Process.run(adb, [
        '-s',
        serial,
        ...args,
      ], stdoutEncoding: bytes ? null : utf8);
  var notificationScreens = 0;
  Future<void> waitForNotification(bool locked) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      if (attempt == 0) {
        final dump = await command([
          'shell',
          'dumpsys',
          'notification',
          '--noredact',
        ]);
        await File(
          '.tooling/warehouse-notification-state-private.txt',
        ).writeAsString(dump.stdout.toString());
      }
      await command([
        'shell',
        'uiautomator',
        'dump',
        '/sdcard/warehouse-timer-ui.xml',
      ]);
      final xml = (await command([
        'shell',
        'cat',
        '/sdcard/warehouse-timer-ui.xml',
      ])).stdout.toString();
      if (xml.contains('$package:id/timer_time') &&
          xml.contains('com.android.systemui') &&
          (!locked || xml.contains('keyguard'))) {
        notificationScreens++;
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    throw StateError('Actual timer notification not visible in system UI');
  }

  Future<void> captureStages() async {
    final deadline = DateTime.now().add(const Duration(minutes: 4));
    while (running && DateTime.now().isBefore(deadline)) {
      final listing = await command([
        'shell',
        'run-as',
        package,
        'find',
        'cache',
        'code_cache',
        '-name',
        'warehouse_native_*.json',
      ]);
      if (listing.exitCode == 0) {
        final files =
            (listing.stdout as String)
                .split(RegExp(r'\s+'))
                .where(
                  (name) =>
                      RegExp(
                        r'^(cache|code_cache)/warehouse_native_\d{15,20}\.json$',
                      ).hasMatch(name) &&
                      name.endsWith('warehouse_native_$captureRun.json'),
                )
                .toList()
              ..sort();
        if (files.isNotEmpty) {
          runFile ??= files.last;
          final raw = await command([
            'shell',
            'run-as',
            package,
            'cat',
            runFile!,
          ]);
          if (raw.exitCode == 0) {
            final name = (jsonDecode(raw.stdout as String) as Map)['name'];
            if (name is! String ||
                !RegExp(
                  r'^warehouse-(shop|detail|room|tasks|timer|lock)-(light|night)$',
                ).hasMatch(name)) {
              throw StateError('Unexpected reminder stage');
            }
            if (!screenshots.contains(name)) {
              if (name.startsWith('warehouse-timer-')) {
                await command([
                  'shell',
                  'cmd',
                  'statusbar',
                  'expand-notifications',
                ]);
                await Future<void>.delayed(const Duration(milliseconds: 700));
              } else if (name.startsWith('warehouse-lock-')) {
                await command(['shell', 'cmd', 'statusbar', 'collapse']);
                await command(['shell', 'input', 'keyevent', '223']);
                await Future<void>.delayed(const Duration(milliseconds: 400));
                await command(['shell', 'input', 'keyevent', '224']);
                await Future<void>.delayed(const Duration(milliseconds: 700));
              }
              if (name.startsWith('warehouse-timer-') ||
                  name.startsWith('warehouse-lock-')) {
                await waitForNotification(name.startsWith('warehouse-lock-'));
              }
              final pixels = await command([
                'exec-out',
                'screencap',
                '-p',
              ], bytes: true);
              if (pixels.exitCode != 0) {
                throw StateError('Android screen capture failed');
              }
              await File(
                'docs/evidence/$name.png',
              ).writeAsBytes(pixels.stdout as List<int>);
              final writer = await Process.start(adb, [
                '-s',
                serial,
                'shell',
                '-T',
                'run-as',
                package,
                'tee',
                '$runFile.ack',
              ]);
              final output = writer.stdout.drain<void>();
              final errors = writer.stderr.drain<void>();
              writer.stdin.write(name);
              await writer.stdin.close();
              final exit = await writer.exitCode.timeout(
                const Duration(seconds: 10),
              );
              await Future.wait([output, errors]);
              if (exit != 0) {
                throw StateError('Android screen acknowledgment failed');
              }

              if (name.startsWith('warehouse-timer-')) {
                await command(['shell', 'cmd', 'statusbar', 'collapse']);
              }
              if (name.startsWith('warehouse-lock-')) {
                await command(['shell', 'wm', 'dismiss-keyguard']);
              }
              screenshots.add(name);
            }
          }
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    if (running) throw StateError('Android screenshot stages timed out');
  }

  final capturing = captureStages().catchError((Object error) {
    captureError = error;
  });
  try {
    await integrationDriver(
      responseDataCallback: (data) async {
        if (captureError != null ||
            data?['result'] != 'PASS' ||
            data?['captureHandshakeRun'] != captureRun ||
            screenshots.length != 12 ||
            notificationScreens != 4) {
          throw StateError(
            'Fresh reminder report and twelve Android screenshots required: $captureError',
          );
        }
        final report = Map<String, dynamic>.from(data!)..remove('screenshots');
        report['screenshots'] = screenshots.toList();
        report['systemNotificationScreensVerified'] = notificationScreens;
        await File('docs/evidence/warehouse-native.json').writeAsString(
          '${const JsonEncoder.withIndent('  ').convert(report)}\n',
        );
      },
    );
  } finally {
    running = false;
    await capturing;
  }
}
