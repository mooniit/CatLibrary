// Local service fault only. Never a substitute for Wi-Fi/mobile-cloud testing.
const fs = require('node:fs'), path = require('node:path');
const assert = require('node:assert/strict');
const {spawnSync} = require('node:child_process');
const {createHash} = require('node:crypto');
const {DatabaseSync} = require('node:sqlite');
const p = require('./test-android-probe.cjs');
const serial = process.argv[2] || 'emulator-5554';
assert.match(serial, /^emulator-\d+$/, 'This test is emulator-only');
const prefix = process.argv.includes('--journal') ? 'm7-journal-native' : 'm7-native';
const pkg = 'com.catlibrary.cat_library_demo', stamp = Date.now();
const sha = value => createHash('sha256').update(value).digest('hex');
function snapshot(phase) {
  p.run('shell', 'am', 'force-stop', pkg);
  const names = p.run('shell', 'run-as', pkg, 'ls', 'app_flutter').split(/\s+/);
  const file = `.tooling/m7-reconnect-${stamp}-${phase}.sqlite`;
  for (const suffix of ['', '-wal', '-shm']) {
    const name = 'cat_library.sqlite' + suffix;
    if (!names.includes(name)) continue;
    const result = spawnSync(path.resolve('.tooling/android-sdk/platform-tools/adb.exe'),
      ['-s', serial, 'exec-out', 'run-as', pkg, 'cat', 'app_flutter/' + name]);
    assert.equal(result.status, 0, 'Private cache snapshot failed');
    fs.writeFileSync(file + suffix, result.stdout);
  }
  const db = new DatabaseSync(file, {readOnly: true});
  try {
    const rows = db.prepare('select owner_id,payload from account_cache order by owner_id').all();
    assert.equal(rows.length, 1, 'Refuse ambiguous or empty identity');
    return {owners: rows.map(r => sha(r.owner_id)), wallets: rows.map(r => sha(JSON.stringify(JSON.parse(r.payload).wallet)))};
  } finally { db.close(); }
}
function launch() { p.run('shell', 'am', 'start', '-W', '-n', pkg + '/.MainActivity'); }
function screenshot(name) {
  p.run('shell', 'screencap', '-p', '/sdcard/' + name + '.png');
  p.run('pull', '/sdcard/' + name + '.png', 'docs/evidence/' + name + '.png');
}
(async () => {
  const before = snapshot('before');
  try {
    if (p.run('reverse', '--list').split(/\r?\n/).some(line => /\btcp:54321\s/.test(line))) {
      p.run('reverse', '--remove', 'tcp:54321');
    }
    launch(); await p.pause(12000);
    await p.tap('打开功能菜单'); await p.tap('设置');
    await p.tap('重新连接'); await p.pause(13000);
    p.run('shell', 'input', 'swipe', '150', '520', '150', '220', '350');
    await p.pause(600);
    p.shown('离线保存中'); p.shown('保留上次确认'); screenshot(prefix + '-offline');
    p.run('reverse', 'tcp:54321', 'tcp:54321');
    await p.tap('重新连接'); await p.pause(2000);
    p.shown('已连接'); p.shown('账户与余额已核对'); screenshot(prefix + '-recovered');
  } finally { p.run('reverse', 'tcp:54321', 'tcp:54321'); }
  const after = snapshot('after'); assert.deepEqual(after, before, 'Identity or wallet changed during reconnect');
  launch();
  fs.writeFileSync('docs/evidence/' + prefix + '-reconnect.json', JSON.stringify({
    at: new Date().toISOString(), scope: 'Existing emulator account; local ADB reverse fault/recovery only',
    serial, before, after, identityPreserved: true, walletUnchanged: true,
    remoteInternetVerified: false, phoneVerified: false,
    actions: 'No account recreation, data clearing, purchases, feeding or timer start',
  }, null, 2) + '\n');
  console.log('PASS native offline -> recovered; original identity and cached wallet preserved; local only');
})().catch(e => { console.error(e.message); process.exitCode = 1; });
