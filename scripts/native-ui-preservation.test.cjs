const {test} = require('node:test');
const assert = require('node:assert/strict');
const {buildPlan, redactOutput} = require('./run-native-ui.cjs');

const options = {
  serial: 'emulator-5554',
  target: 'integration_test/m7_album_ui_test.dart',
  driver: 'test_driver/m7_album_driver.dart',
  apkPath: 'build/app/outputs/flutter-apk/app-debug.apk',
  vmServiceUrl: 'http://127.0.0.1:45678/test-session-token=/',
};

// Interpret CLI options rather than snapshotting the entire command line.
function option(args, name) {
  const index = args.indexOf(name);
  if (index >= 0) return args[index + 1];
  return args.find(arg => arg.startsWith(name + '='))?.slice(name.length + 1);
}

function command(plan, tool, verb) {
  const matches = plan.commands.filter(item => item.tool === tool && item.args.includes(verb));
  assert.equal(matches.length, 1, `Expected one ${tool} ${verb} command`);
  return matches[0];
}

test('only an explicitly selected Android emulator can receive the native UI test', () => {
  for (const serial of ['emulator-5554', 'emulator-5556']) {
    const plan = buildPlan({...options, serial});
    for (const {tool, args} of plan.commands) {
      if (tool === 'adb') assert.equal(option(args, '-s'), serial);
    }
    assert.equal(option(command(plan, 'flutter', 'drive').args, '-d'), serial);
  }
});

test('physical devices, network devices and missing serials are refused before creating a plan', () => {
  for (const serial of ['R58M123456A', '192.168.1.10:5555', 'android', '', undefined, 'emulator-', 'emulator-5554 extra']) {
    assert.throws(() => buildPlan({...options, serial}), /emulator|模拟器/i);
  }
});

test('the test APK is built for the requested target without using flutter to install it', () => {
  const plan = buildPlan(options);
  const build = command(plan, 'flutter', 'build');
  assert.ok(build.args.includes('apk'));
  assert.ok(build.args.includes('--debug'));
  assert.equal(option(build.args, '--target'), options.target);
  assert.ok(!plan.commands.some(item => item.tool === 'flutter' && item.args.includes('install')));
});

test('isolated defines are passed to the fixture build and attached driver only', () => {
  const definesFile = '.tooling/native-cloud-session-defines-123.json';
  const plan = buildPlan({...options, definesFile});
  for (const verb of ['build', 'drive']) {
    assert.equal(option(command(plan, 'flutter', verb).args, '--dart-define-from-file'), definesFile);
  }
  assert.ok(!buildPlan(options).commands.some(c => c.args.some(a => a.startsWith('--dart-define'))));
});

test('fixture defines must use an isolated project-local tooling path', () => {
  for (const definesFile of ['../private.json', '.tooling/../private.json', 'C:/private.json',
    'lib/private.json', '.tooling/private.txt', '.tooling/file.json extra']) {
    assert.throws(() => buildPlan({...options, definesFile}), /defines/i);
  }
});

test('ADB installs the test APK as a replacement and permits its test manifest', () => {
  const install = command(buildPlan(options), 'adb', 'install');
  assert.ok(install.args.includes('-r'), 'Replacement install must retain existing app data');
  assert.ok(install.args.includes('-t'), 'Integration-test APK must be explicitly allowed');
  assert.equal(install.args.at(-1), options.apkPath);
});

test('the app starts only after replacement installation and before attaching the driver', () => {
  const plan = buildPlan(options);
  const install = command(plan, 'adb', 'install');
  const launch = plan.commands.find(item => item.tool === 'adb' && item.args.includes('am') && item.args.includes('start'));
  assert.ok(launch, 'The installed test application must be launched explicitly');
  assert.equal(option(launch.args, '-n'), 'com.catlibrary.cat_library_demo/.MainActivity');
  assert.ok(plan.commands.indexOf(install) < plan.commands.indexOf(launch));
  assert.ok(plan.commands.indexOf(launch) < plan.commands.indexOf(command(plan, 'flutter', 'drive')));
});

test('Flutter drive attaches to the running app and explicitly bypasses destructive cleanup', () => {
  const drive = command(buildPlan(options), 'flutter', 'drive');
  assert.equal(option(drive.args, '--use-existing-app'), options.vmServiceUrl);
  assert.equal(option(drive.args, '--driver'), options.driver);
  assert.ok(drive.args.includes('--keep-app-running'));
  assert.ok(!drive.args.includes('--no-keep-app-running'));
});

test('the native test plan contains no uninstall, private-data deletion or emulator reset', () => {
  const plan = buildPlan(options);
  for (const {args} of plan.commands) {
    assert.ok(!args.includes('uninstall'), 'Uninstallation destroys the cached account');
    assert.ok(!args.includes('-wipe-data') && !args.includes('--wipe-data'));
    assert.ok(!args.some((arg, index) => arg === 'pm' && args[index + 1] === 'clear'));
    assert.ok(!args.includes('rm'), 'Private files must not be deleted by this runner');
  }
});

test('an absent or invalid VM service address cannot fall back to normal flutter drive', () => {
  for (const vmServiceUrl of [undefined, '', 'not-a-url']) {
    assert.throws(() => buildPlan({...options, vmServiceUrl}));
  }
});

test('command logging removes the VM service address and session token', () => {
  const drive = command(buildPlan(options), 'flutter', 'drive');
  const logged = redactOutput(['flutter', ...drive.args].join(' '));
  assert.ok(!logged.includes(options.vmServiceUrl));
  assert.ok(!logged.includes('test-session-token'));
  assert.ok(logged.includes('drive'));
  assert.ok(logged.includes(options.driver));
});

test('success and failure output remove HTTP and WebSocket VM session addresses', () => {
  for (const url of [
    options.vmServiceUrl,
    'ws://127.0.0.1:45678/test-session-token=/ws',
    'http://localhost:45678/test-session-token=/',
    'http://[::1]:45678/test-session-token=/',
  ]) {
    for (const output of [
      `The Dart VM service is listening on ${url}\nPASS: native UI`,
      `Failed to connect to VM service at ${url}\nDriver exited with status 1`,
    ]) {
      const logged = redactOutput(output);
      assert.ok(!logged.includes(url));
      assert.ok(!logged.includes('test-session-token'));
      assert.ok(logged.includes(output.split('\n')[1]), 'Useful test status must remain visible');
    }
  }
});
