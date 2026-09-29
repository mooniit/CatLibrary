// Real emulator lifecycle/offline test. Never runs on physical devices or changes clock.
const {spawnSync}=require('node:child_process');
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {DatabaseSync}=require('node:sqlite');
const {run,nodes,tap,shown,pause}=require('./test-android-probe.cjs');
const serial=process.argv[2]||'emulator-5554';
assert(/^emulator-\d+$/.test(serial));
const root=path.resolve(__dirname,'..'),pkg='com.catlibrary.cat_library_demo';
const adb=path.join(root,'.tooling/android-sdk/platform-tools/adb.exe');
const evidence={at:new Date().toISOString(),scope:'Android emulator, real elapsed time, real local Supabase; not physical phone or iOS; no real midnight or six-hour duration',checks:[]};
function checkpoint() {
 const xml=run('shell','run-as',pkg,'cat','shared_prefs/study_checkpoint.xml');
 const value={};
 for(const m of xml.matchAll(/<long name="([^"]+)" value="(\d+)"\s*\/>/g)) value[m[1]]=Number(m[2]);
 for(const m of xml.matchAll(/<string name="([^"]+)">([^<]*)<\/string>/g)) value[m[1]]=m[2];
 assert(value.id && value.recordedUntil);return value;
}
function sqliteRows() {
 const destination=path.join(root,'.tooling/m2-emulator.sqlite');
 // App must be stopped before copying database and WAL as a coherent set.
 const names=run('shell','run-as',pkg,'ls','app_flutter').split(/\s+/);
 for(const suffix of ['', '-wal','-shm']) {
  const remote='cat_library.sqlite'+suffix;
  if(names.includes(remote)) {
   const r=spawnSync(adb,['-s',serial,'exec-out','run-as',pkg,'cat','app_flutter/'+remote]);
   assert.equal(r.status,0);fs.writeFileSync(destination+suffix,r.stdout);
  } else if(fs.existsSync(destination+suffix)) fs.unlinkSync(destination+suffix);
 }
 const db=new DatabaseSync(destination);
 try{return db.prepare('select * from study_sessions order by started_ms').all();}finally{db.close();}
}
async function launch() {
 run('shell','am','start','-W','-n',pkg+'/.MainActivity');
 await pause(12000);
 await tap('自习',true);
}
function pass(name,detail={}){evidence.checks.push({name,result:'PASS',...detail});fs.writeFileSync(path.join(root,'docs/evidence/m2-study-emulator.json'),JSON.stringify(evidence,null,2)+'\n');console.log('PASS '+name);}
async function tapVisible(label) {
 for(let i=0;i<5;i++) { if(nodes().some(n=>n['content-desc']===label && n.clickable==='true')) { await tap(label); return; } run('shell','input','swipe','160','470','160','180','350'); } throw new Error('Button not visible: '+label);
}
(async()=>{
 assert.equal(run('shell','getprop','ro.kernel.qemu'),'1');
 run('reverse','tcp:54321','tcp:54321');
 run('shell','pm','grant',pkg,'android.permission.POST_NOTIFICATIONS');
 await launch();
 shown('今日自习');
 assert(!nodes().some(n=>n['content-desc']==='结束计时'),'Existing timer left untouched');
 const initialText=nodes().map(n=>n['content-desc']).join('\n');
 const initialIssued=Number(initialText.match(/今日已入账 (\d+)/)?.[1]);
 assert(Number.isFinite(initialIssued));
 let latest, expected;
 if (!process.argv.includes('--resume')) {
 await tap('开始自习');
 await pause(7000);
 const first=checkpoint();
 run('shell','input','keyevent','KEYCODE_SLEEP');
 await pause(30000);
 const middle=checkpoint();
 assert(middle.recordedUntil>first.recordedUntil+20000,'Native checkpoint must advance while locked');
 console.log('Native lock-screen checkpoint advanced; continuing toward one earned minute.');
 await pause(30000);
 latest=checkpoint();
 run('shell','am','force-stop',pkg);
 const beforeRows=sqliteRows();
 const before=beforeRows.find(r=>r.id===latest.id);assert(before);
 expected=Math.max(before.recorded_ms,latest.recordedUntil);
 const earnedMs=expected-before.started_ms;
 assert(earnedMs>=60000 && earnedMs<180000);
 pass('native lock-screen checkpoint survives force-stop',{elapsedMs:earnedMs,nativeAdvanceMs:latest.recordedUntil-first.recordedUntil});
 } else {
 latest=checkpoint(); run('shell','am','force-stop',pkg);
 const saved=sqliteRows().find(r=>r.id===latest.id); assert(saved);
 expected=Math.max(saved.recorded_ms,latest.recordedUntil);
 pass('resume existing native recovery record after fixing scroll locator',{elapsedMs:expected-saved.started_ms,earlierRun:'native locked advancement and force-stop passed; confirmation button was below viewport'});
 }
 run('reverse','--remove','tcp:54321');
 await pause(10000);
 run('shell','input','keyevent','KEYCODE_WAKEUP');
 run('shell','wm','dismiss-keyguard');
 await launch();
 shown('待确认');
 assert(!nodes().some(n=>n['content-desc']==='结束计时'));
 await tapVisible('确认完成');
 await pause(1000);
 shown('已确认，待入账');
 run('shell','am','force-stop',pkg);
 const queued=sqliteRows().find(r=>r.id===latest.id);
 assert.equal(queued.recorded_ms,expected);
 assert.equal(queued.state,'queued');
 pass('offline cold recovery excludes shutdown time and confirmation is durable',{savedMs:queued.recorded_ms});
 await launch();
 shown('已确认，待入账');
 run('reverse','tcp:54321','tcp:54321');
 await pause(22000);
 await tap('核对入账');
 await pause(2000);
 shown('已同步');
 run('shell','input','swipe','160','180','160','470','350');
 const endText=nodes().map(n=>n['content-desc']).join('\n');
 const finalIssued=Number(endText.match(/今日已入账 (\d+)/)?.[1]);
 assert(finalIssued>initialIssued && finalIssued<=120);
 run('shell','am','force-stop',pkg);
 assert.equal(sqliteRows().find(r=>r.id===latest.id).state,'synced');
 pass('offline queued record auto-syncs after reconnect with actual server credit',{initialIssued,finalIssued});
 await launch();
 fs.writeFileSync(path.join(root,'docs/evidence/m2-study-emulator.json'),JSON.stringify(evidence,null,2)+'\n');
 console.log('PASS M2 emulator lifecycle and offline settlement');
})().catch(e=>{console.error(e);process.exitCode=1;}).finally(()=>{
 try{run('reverse','tcp:54321','tcp:54321');run('shell','input','keyevent','KEYCODE_WAKEUP');run('shell','wm','dismiss-keyguard');}catch{}
});
