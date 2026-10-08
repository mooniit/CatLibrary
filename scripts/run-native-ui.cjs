// Attach to an explicitly installed emulator fixture. Flutter must never install
// or uninstall the existing application's package on this path.
const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const {createHash} = require('node:crypto');
const pkg = 'com.catlibrary.cat_library_demo';

function validate(options) {
  if (!/^emulator-\d+$/.test(options.serial || '')) throw new Error('Explicit emulator serial required');
  for (const key of ['target', 'driver']) {
    if (!/^(integration_test|test_driver)\/[a-zA-Z0-9_/-]+\.dart$/.test(options[key] || '') || options[key].includes('..')) {
      throw new Error(`Invalid ${key}`);
    }
  }
  if (typeof options.apkPath !== 'string' || !options.apkPath.endsWith('.apk')) throw new Error('APK path required');
}

function redactOutput(value) {
  return String(value).replace(/(?:https?|wss?):\/\/[^\s"'<>]+/g, '[VM address hidden]');
}

function buildPlan(options) {
  validate(options);
  const vm = new URL(options.vmServiceUrl);
  if (!['http:', 'ws:'].includes(vm.protocol) || !['127.0.0.1', 'localhost', '[::1]'].includes(vm.hostname) || vm.username || vm.password) {
    throw new Error('Loopback VM service address required');
  }
  const adb = (...args) => ({tool: 'adb', args: ['-s', options.serial, ...args]});
  return {commands: [
    {tool: 'flutter', args: ['build', 'apk', '--debug', '--no-pub', '--target', options.target]},
    adb('install', '-r', '-t', options.apkPath),
    adb('shell', 'am', 'start', '-n', `${pkg}/.MainActivity`),
    {tool: 'flutter', args: ['drive', '--no-pub', '-d', options.serial, '--target', options.target,
      '--driver', options.driver, '--use-existing-app', options.vmServiceUrl, '--keep-app-running']},
  ]};
}

async function main(argv) {
  const options = {apkPath: 'build/app/outputs/flutter-apk/app-debug.apk'};
  const names = {'--serial': 'serial', '--target': 'target', '--driver': 'driver', '--restore-apk': 'restoreApk'};
  for (let i = 0; i < argv.length; i += 2) {
    if (!names[argv[i]] || !argv[i + 1]) throw new Error('Usage: --serial emulator-N --target integration_test/...dart --driver test_driver/...dart --restore-apk original.apk');
    options[names[argv[i]]] = argv[i + 1];
  }
  validate(options);
  const root = path.resolve(__dirname, '..');
  const within = file => {
    const resolved = path.resolve(root, file);
    if (!resolved.startsWith(root + path.sep)) throw new Error('Paths must stay inside project');
    return resolved;
  };
  const original = within(options.restoreApk || '');
  if (!original.endsWith('.apk') || !fs.existsSync(original) || original === within(options.apkPath)) {
    throw new Error('A separate original APK is required before testing');
  }
  for (const key of ['target', 'driver']) if (!fs.existsSync(within(options[key]))) throw new Error(`Missing ${key}`);
  const env = {...process.env, ANDROID_HOME: path.join(root, '.tooling/android-sdk'),
    GRADLE_USER_HOME: path.join(root, '.tooling/gradle-cache'), PUB_CACHE: path.join(root, '.tooling/pub-cache')};
  const adb = path.join(env.ANDROID_HOME, 'platform-tools/adb.exe');
  const dart = path.join(root, '.tooling/flutter/bin/cache/dart-sdk/bin/dart.exe');
  const flutter = path.join(root, '.tooling/flutter/bin/cache/flutter_tools.snapshot');
  const backup = fs.mkdtempSync(path.join(root, '.tooling/native-ui-backup-'));
  const run = (tool, args, silent = false) => {
    const result = spawnSync(tool === 'adb' ? adb : dart,
      tool === 'adb' ? ['-s', options.serial, ...args] : [flutter, '--no-version-check', ...args],
      {cwd: root, env, maxBuffer: 32 * 1024 * 1024});
    if (!silent) process.stdout.write(redactOutput(Buffer.concat([result.stdout || Buffer.alloc(0), result.stderr || Buffer.alloc(0)]).toString()));
    if (result.status !== 0) throw new Error(`${tool} ${args[0]} failed; no uninstall fallback is permitted`);
    return result.stdout;
  };
  // Refuse absent/non-debuggable packages: do not manufacture a test identity.
  run('adb', ['shell', 'am', 'force-stop', pkg]);
  const listing = run('adb', ['shell', 'run-as', pkg, 'find', 'app_flutter', 'shared_prefs', '-type', 'f'], true).toString().trim().split(/\r?\n/);
  if (!listing.includes('app_flutter/cat_library.sqlite')) throw new Error('Existing SQLite account snapshot required');
  // Flutter's own kernel/snapshot and resource timestamps change with the APK;
  // back up account databases (including quarantined copies) and preferences.
  const files = listing.filter(file => /^app_flutter\/cat_library\.sqlite[a-zA-Z0-9_.-]*$|^shared_prefs\/[a-zA-Z0-9_.-]+$/.test(file)).map(file => {
    const bytes = run('adb', ['exec-out', 'run-as', pkg, 'cat', file], true);
    fs.mkdirSync(path.dirname(path.join(backup, file)), {recursive: true});
    fs.writeFileSync(path.join(backup, file), bytes, {flag: 'wx'});
    return {file, sha256: createHash('sha256').update(bytes).digest('hex')};
  });
  let forwarded;
  let failure;
  try {
    const plan = buildPlan({...options, vmServiceUrl: 'http://127.0.0.1:1/pending/'});
    for (const command of plan.commands.slice(0, 3)) run(command.tool, command.args.slice(command.tool === 'adb' ? 2 : 0));
    let service;
    for (let i = 0; i < 30 && !service; i++) {
      let pid;
      try {
        pid = run('adb', ['shell', 'pidof', pkg], true).toString().trim();
      } catch {
        // am start may return before Android creates the application process.
        await new Promise(resolve => setTimeout(resolve, 500));
        continue;
      }
      if (!/^\d+$/.test(pid)) throw new Error('Unexpected fixture process');
      const log = run('adb', ['logcat', '-d', '--pid', pid, '-v', 'raw', '-s', 'flutter'], true).toString();
      service = log.match(/Dart VM service is listening on (http:\/\/127\.0\.0\.1:\d+\/[^\s]+)/)?.[1];
      if (!service) await new Promise(resolve => setTimeout(resolve, 500));
    }
    if (!service) throw new Error('VM service not found; refusing default Flutter drive');
    const uri = new URL(service);
    forwarded = run('adb', ['forward', 'tcp:0', `tcp:${uri.port}`], true).toString().trim();
    if (!/^\d+$/.test(forwarded)) throw new Error('VM forwarding failed');
    uri.port = forwarded;
    const attach = buildPlan({...options, vmServiceUrl: uri.toString()}).commands.at(-1);
    run(attach.tool, attach.args);
  } catch (error) {
    failure = error;
  } finally {
    run('adb', ['shell', 'am', 'force-stop', pkg]);
    if (forwarded) run('adb', ['forward', '--remove', `tcp:${forwarded}`], true);
    const mismatches = files.filter(item => createHash('sha256').update(run('adb', ['exec-out', 'run-as', pkg, 'cat', item.file], true)).digest('hex') !== item.sha256);
    fs.writeFileSync(path.join(backup, 'verification.json'), JSON.stringify({serial: options.serial,
      originalPrivateFilesUnchanged: mismatches.length === 0, fileCount: files.length,
      fixturePassed: !failure, physicalPhoneTouched: false}, null, 2) + '\n');
    if (mismatches.length) throw new Error('Private data changed. Backup retained; stop for explicit recovery before restoring normal app.');
    // Only ADB replacement install; a failed installation must never remove data.
    run('adb', ['install', '-r', '-t', original]);
    run('adb', ['shell', 'am', 'start', '-n', `${pkg}/.MainActivity`]);
  }
  if (failure) throw failure;
  console.log(`PASS: fixture and ${files.length} existing private files preserved; original APK restored`);
}

module.exports = {buildPlan, redactOutput};
if (require.main === module) main(process.argv.slice(2)).catch(error => {
  console.error(redactOutput(error.message));
  process.exitCode = 1;
});
