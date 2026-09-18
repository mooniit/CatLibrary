// Android probe. Physical devices require an explicit flag; never clears data or changes the clock.
const {spawnSync} = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {DatabaseSync} = require('node:sqlite');
const root = path.resolve(__dirname, '..');
const adb = path.join(root, '.tooling/android-sdk/platform-tools/adb.exe');
const serial = process.argv[2] || 'emulator-5554';
const physical = process.argv.includes('--physical');
if (!physical) assert.match(serial, /^emulator-\d+$/, 'Physical devices require --physical');
else assert(!serial.startsWith('emulator-'), 'Physical evidence requires a real device');
const pkg = 'com.catlibrary.cat_library_demo';
const evidence = {scope:physical ? 'Physical Android; foreground and short background/force-stop only; no lock-screen, currency, midnight or six-hour proof' : 'Android emulator; no currency, real phone, midnight or six-hour proof', startedAt:new Date().toISOString(), device:serial, checks:[]};
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
function run(...args) {
  const r = spawnSync(adb, ['-s', serial, ...args], {encoding:'utf8', timeout:30000});
  if (r.error || r.status !== 0) throw new Error(`${args.join(' ')}: ${r.error || r.stderr || r.stdout}`);
  return r.stdout.trim();
}
function nodes() {
  run('shell', 'uiautomator', 'dump', '/sdcard/m0-window.xml');
  const xml = run('shell', 'cat', '/sdcard/m0-window.xml');
  return [...xml.matchAll(/<node\b[^>]*>/g)].map(m => {
    const attrs = {};
    for (const a of m[0].matchAll(/([\w-]+)="([^"]*)"/g)) attrs[a[1]]=a[2].replace(/&#(\d+);/g, (_, n)=>String.fromCodePoint(+n)).replace(/&amp;/g,'&');
    return attrs;
  });
}
async function tap(label, tab=false) {
  const n = nodes().find(n => n.clickable==='true' && (tab ? n['content-desc'].startsWith(label+'\nTab') : n['content-desc']===label));
  assert(n && n.enabled==='true', `Missing/enabled button: ${label}`);
  const b=n.bounds.match(/\d+/g).map(Number);
  run('shell','input','tap',String(Math.round((b[0]+b[2])/2)),String(Math.round((b[1]+b[3])/2)));
  await pause(700);
}
function shown(text) { assert(nodes().some(n=>n['content-desc'].includes(text)||n.text.includes(text)), `Missing text: ${text}`); }
function elapsed() {
  const value = nodes().map(n=>n['content-desc']).find(s=>/^\d{2}:\d{2}:\d{2}$/.test(s));
  assert(value,'Missing timer display');
  return value.split(':').reduce((v,n)=>v*60+Number(n),0);
}
function pid() { return run('shell','pidof',pkg); }
function checkpoint() {
  const target=path.join(root,physical ? '.tooling/phone-checkpoint.sqlite' : '.tooling/emulator-checkpoint.sqlite');
  const r=spawnSync(adb,['-s',serial,'exec-out','run-as',pkg,'cat','app_flutter/cat_library_m0.sqlite'],{timeout:10000});
  assert.equal(r.status,0,r.stderr?.toString());
  fs.writeFileSync(target,r.stdout);
  const db=new DatabaseSync(target,{readOnly:true});
  try { return JSON.parse(db.prepare('SELECT payload FROM probe_records WHERE id=1').get().payload); }
  finally { db.close(); }
}
function pass(name, detail={}) { evidence.checks.push({name,result:'pass',...detail}); console.log(`PASS ${name}`); }
(async()=>{
  assert.equal(run('shell','getprop','sys.boot_completed'),'1');
  evidence.android=run('shell','getprop','ro.build.version.release');
  evidence.model=run('shell','getprop','ro.product.model');
  evidence.emulator=run('shell','getprop','ro.kernel.qemu')==='1';
  assert.equal(evidence.emulator,!physical,'Device type does not match test scope');
  run('shell','am','start','-W','-n',pkg+'/.MainActivity');
  await tap('猫窝',true); shown('布置猫窝');
  await tap('任务板',true); shown('外语学习');
  await tap('阅读',true); shown('阅读功能筹备中');
  await tap('自习',true); shown('计时技术探针');
  pass('four-page native navigation');
  let current=nodes();
  assert(!current.some(n=>n['content-desc']==='结束计时'), 'Existing active record: leave it untouched and stop this test');
  if(current.some(n=>n['content-desc']==='确认探针记录')) await tap('确认探针记录');
  current=nodes();
  await tap(current.some(n=>n['content-desc']==='开始计时') ? '开始计时':'开始新记录');
  const initialPid=pid();
  if (physical) {
    const first=elapsed(); const foregroundStart=Date.now();
    for(let i=0;i<6;i++) {
      const n=nodes().find(n=>/^\d{2}:\d{2}:\d{2}$/.test(n['content-desc']));
      assert(n,'Timer must remain visible during foreground test');
      const b=n.bounds.match(/\d+/g).map(Number);
      run('shell','input','tap',String(Math.round((b[0]+b[2])/2)),String(Math.round((b[1]+b[3])/2)));
      await pause(20000);
      console.log(`Foreground interval ${i+1}/6`);
    }
    const last=elapsed(); const wallSeconds=(Date.now()-foregroundStart)/1000;
    assert(wallSeconds>=120);
    assert(Math.abs((last-first)-wallSeconds)<5);
    pass('foreground at least two minutes',{before:first,after:last,wallSeconds});
  } else await pause(10000);
  const before=elapsed(); const startWall=Date.now();
  run('shell','input','keyevent','KEYCODE_HOME');
  await pause(12000);
  run('shell','am','start','-W','-n',pkg+'/.MainActivity');
  const after=elapsed(); const wallSeconds=(Date.now()-startWall)/1000;
  assert.equal(pid(),initialPid,'Background process changed');
  assert(Math.abs((after-before)-wallSeconds)<5,`Warm elapsed ${after-before} vs wall ${wallSeconds}`);
  pass('same-process background resume',{before,after,wallSeconds});
  if (!physical) {
  const lockBefore=elapsed(); const lockWall=Date.now();
  run('shell','input','keyevent','KEYCODE_SLEEP');
  await pause(12000);
  run('shell','input','keyevent','KEYCODE_WAKEUP');
  run('shell','wm','dismiss-keyguard');
  const lockAfter=elapsed(); const lockSeconds=(Date.now()-lockWall)/1000;
  assert.equal(pid(),initialPid,'Lock screen process changed');
  assert(Math.abs((lockAfter-lockBefore)-lockSeconds)<5);
  pass('short lock-screen resume',{before:lockBefore,after:lockAfter,wallSeconds:lockSeconds});
  }
  run('shell','am','force-stop',pkg);
  const saved=checkpoint();
  const savedSeconds=Math.floor((Date.parse(saved.checkpoint)-Date.parse(saved.start))/1000);
  await pause(10000);
  run('shell','am','start','-W','-n',pkg+'/.MainActivity');
  await tap('自习',true);
  shown('恢复到最后保存点'); shown('确认探针记录');
  assert.notEqual(pid(),initialPid);
  assert.equal(elapsed(),savedSeconds);
  await pause(7000);
  assert.equal(elapsed(),savedSeconds,'Cold recovery incorrectly kept counting');
  assert.deepEqual(checkpoint(),saved,'Cold recovery changed the durable checkpoint');
  pass('force-stop and cold SQLite recovery',{savedSeconds,durableCheckpoint:saved.checkpoint,oldPid:initialPid,newPid:pid(),stoppedWhileAbsent:true});
  evidence.finishedAt=new Date().toISOString();
})().catch(error=>{evidence.error=error.stack; process.exitCode=1; console.error(error);}).finally(()=>{
  fs.writeFileSync(path.join(root,physical ? 'docs/evidence/m0-oneplus-lifecycle.json' : 'docs/evidence/m0-android-lifecycle.json'),JSON.stringify(evidence,null,2)+'\n');
});
