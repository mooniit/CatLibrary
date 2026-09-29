// Authorized one-off M2 test on the connected Ace3. Uses its local Supabase test identity.
const {spawnSync}=require('node:child_process');
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const serial='119bad33',pkg='com.catlibrary.cat_library_demo';
const root=path.resolve(__dirname,'..'),adb=path.join(root,'.tooling/android-sdk/platform-tools/adb.exe');
const {DatabaseSync}=require('node:sqlite');
const evidence={at:new Date().toISOString(),device:'OnePlus Ace 3 PJE110 / Android 16; authorized USB debug',scope:'Connected Android phone; M2 native journal, short lock, force-stop recovery and local Supabase only; not iOS, real midnight or six-hour proof',checks:[]};
function run(...args){const r=spawnSync(adb,['-s',serial,...args],{encoding:'utf8',timeout:30000});if(r.error||r.status!==0)throw Error(args.join(' ')+': '+(r.error||r.stderr||r.stdout));return r.stdout.trim();}
function nodes(){run('shell','uiautomator','dump','/sdcard/m2-window.xml');const x=run('shell','cat','/sdcard/m2-window.xml');return [...x.matchAll(/<node\b[^>]*>/g)].map(m=>{const a={};for(const z of m[0].matchAll(/([\w-]+)="([^"]*)"/g))a[z[1]]=z[2].replace(/&#(\d+);/g,(_,n)=>String.fromCodePoint(+n)).replace(/&amp;/g,'&');return a;});}
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
async function tap(label,tab=false){for(let k=0;k<5;k++){const n=nodes().find(x=>x.clickable==='true'&&(tab?x['content-desc'].startsWith(label+'\nTab'):(x['content-desc']===label||x.text===label)));if(n){const b=n.bounds.match(/\d+/g).map(Number);run('shell','input','tap',String((b[0]+b[2])/2),String((b[1]+b[3])/2));await sleep(1000);return;}run('shell','input','swipe','540','1850','540','850','350');}throw Error('Missing UI button '+label);}
function journal(){const x=run('shell','run-as',pkg,'cat','shared_prefs/study_checkpoint.xml');const id=x.match(/<string name="id">([^<]+)<\/string>/)?.[1];const owner=x.match(/<string name="ownerId">([^<]+)<\/string>/)?.[1];const start=Number(x.match(/<long name="startedAt" value="(\d+)"\s*\/>/)?.[1]);const recorded=Number(x.match(/<long name="recordedUntil" value="(\d+)"\s*\/>/)?.[1]);assert(id&&owner&&recorded>=start);return{id,owner,start,recorded};}
function dbSnapshot(){run('shell','am','force-stop',pkg);const dest=path.join(root,'.tooling/m2-phone.sqlite');const entries=run('shell','run-as',pkg,'ls','app_flutter').split(/\s+/);for(const suffix of ['','-wal','-shm']){const name='cat_library.sqlite'+suffix;if(entries.includes(name)){const r=spawnSync(adb,['-s',serial,'exec-out','run-as',pkg,'cat','app_flutter/'+name]);assert.equal(r.status,0);fs.writeFileSync(dest+suffix,r.stdout);}else if(fs.existsSync(dest+suffix))fs.unlinkSync(dest+suffix);}const d=new DatabaseSync(dest);try{return d.prepare('select id,owner_id,started_ms,recorded_ms,state from study_sessions order by started_ms').all();}finally{d.close();}}
function pass(name,detail={}){evidence.checks.push({name,result:'PASS',...detail});fs.writeFileSync(path.join(root,'docs/evidence/m2-study-phone.json'),JSON.stringify(evidence,null,2)+'\n');console.log('PASS '+name);}
(async()=>{
 assert.equal(run('shell','getprop','ro.product.model'),'PJE110');assert.equal(run('shell','getprop','ro.build.version.release'),'16');
 run('reverse','tcp:54321','tcp:54321');run('shell','am','start','-W','-n',pkg+'/.MainActivity');await sleep(12000);
 await tap('自习',true);
 assert(!nodes().some(n=>n['content-desc']==='结束计时'),'An existing active timer must remain untouched');
 const before=nodes().map(n=>n['content-desc']||n.text).join('\n');
 const issued=Number(before.match(/今日已入账 (\d+)/)?.[1]);assert(Number.isFinite(issued));
 const user=before.match(/用户编号：([0-9a-f-]+)/)?.[1];
 await tap('开始自习');await sleep(7000);
 const first=journal();run('shell','input','keyevent','KEYCODE_SLEEP');await sleep(30000);
 const locked=journal();assert(locked.recorded>first.recorded+20000);
 console.log('Ace3 native lock-screen checkpoint advanced while locked.');
 await sleep(30000);const latest=journal();assert.equal(latest.id,first.id);assert.equal(latest.owner,first.owner);
 const saved=dbSnapshot().find(r=>r.id===latest.id);assert(saved);
 const expected=Math.max(saved.recorded_ms,latest.recorded);
 const duration=expected-saved.started_ms;assert(duration>=60000&&duration<180000);
 pass('Ace3 native lock-screen journal and SQLite survive force-stop',{elapsedMs:duration,lockCheckpointAdvanceMs:locked.recorded-first.recorded,user});
 run('reverse','--remove','tcp:54321');await sleep(8000);
 run('shell','input','keyevent','KEYCODE_WAKEUP');run('shell','wm','dismiss-keyguard');
 run('shell','am','start','-W','-n',pkg+'/.MainActivity');await sleep(12000);await tap('自习',true);
 assert(nodes().some(n=>(n['content-desc']||n.text||'').includes('待确认')));
 assert(!nodes().some(n=>n['content-desc']==='结束计时'));
 await tap('确认完成');await sleep(1000);assert(nodes().some(n=>(n['content-desc']||n.text||'').includes('已确认，待入账')));
 const queued=dbSnapshot().find(r=>r.id===latest.id);assert.equal(queued.recorded_ms,expected);assert.equal(queued.state,'queued');
 pass('Ace3 cold recovery offers manual confirmation and stores offline queue',{recordedMs:queued.recorded_ms});
 run('shell','am','start','-W','-n',pkg+'/.MainActivity');await sleep(12000);await tap('自习',true);
 run('reverse','tcp:54321','tcp:54321');await sleep(16000);
 await tap('核对入账');await sleep(2000);
 assert(nodes().some(n=>(n['content-desc']||n.text||'').includes('已同步')));
 const end=nodes().map(n=>n['content-desc']||n.text).join('\n');const credited=Number(end.match(/今日已入账 (\d+)/)?.[1]);assert(credited>issued);
 const synced=dbSnapshot().find(r=>r.id===latest.id);assert.equal(synced.state,'synced');
 pass('Ace3 reconnects queued session and refreshes actual cloud reward',{balanceBefore:before.match(/喵喵币 (\d+)/)?.[1],issuedBefore:issued,issuedAfter:credited});
 run('reverse','tcp:54321','tcp:54321');run('shell','input','keyevent','KEYCODE_WAKEUP');run('shell','wm','dismiss-keyguard');
 fs.writeFileSync(path.join(root,'docs/evidence/m2-study-phone.json'),JSON.stringify(evidence,null,2)+'\n');
 console.log('PASS Ace3 M2 native and offline flow');
})().catch(e=>{console.error(e);process.exitCode=1;try{run('reverse','tcp:54321','tcp:54321');run('shell','input','keyevent','KEYCODE_WAKEUP');run('shell','wm','dismiss-keyguard')}catch{}});
