// Reuses the installed app. Sampling never changes battery policy, clock or app data.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {run,nodes,tap,elapsed,pid,checkpoint,pause} = require('./test-android-probe.cjs');
const file = path.resolve(__dirname,'../docs/evidence/m0-oneplus-lock-with-notification.json');
const pkg = 'com.catlibrary.cat_library_demo';
assert(process.argv.includes('--physical'));
(async () => {
  if (process.argv.includes('--resume')) {
    const evidence = JSON.parse(fs.readFileSync(file,'utf8'));
    await tap('自习',true);
    assert.equal(pid(), evidence.pid, 'Warm resume needs the original process');
    const displayed = elapsed();
    const saved = checkpoint();
    const deviceNow = Number(run('shell','date','+%s')) * 1000;
    const expected = Math.floor((deviceNow-Date.parse(saved.start))/1000);
    assert(Math.abs(displayed-expected) < 6, `${displayed} vs device ${expected}`);
    await tap('结束计时');
    evidence.resume = {result:'pass',displayed,expectedDeviceSeconds:expected,checkpoint:checkpoint()};
    evidence.finishedAt = new Date().toISOString();
    fs.writeFileSync(file,JSON.stringify(evidence,null,2)+'\n');
    console.log('PASS warm resume after lock; session ended');
    return;
  }
  assert.equal(run('shell','getprop','ro.product.model'),'PJE110');
  assert(/android.permission.POST_NOTIFICATIONS: granted=true/.test(run('shell','dumpsys','package',pkg)), 'Allow notifications before starting this probe');
  await tap('自习',true);
  let current = nodes();
  assert(!current.some(n=>n['content-desc']==='结束计时'),'Existing running record left untouched');
  if(current.some(n=>n['content-desc']==='确认探针记录')) await tap('确认探针记录');
  current = nodes();
  await tap(current.some(n=>n['content-desc']==='开始计时')?'开始计时':'开始新记录');
  const service = run('shell','dumpsys','activity','services',pkg);
  assert(service.includes('StudyTimerService'),'Notification service must be running');
  const evidence = {scope:'OnePlus USB-powered seven-minute lock sampling with foreground notification; no deep-doze, six-hour or midnight proof', startedAt:new Date().toISOString(),device:process.argv[2],pid:pid(),before:checkpoint(),samples:[]};
  const save = () => fs.writeFileSync(file,JSON.stringify(evidence,null,2)+'\n');
  save();
  run('shell','input','keyevent','KEYCODE_SLEEP');
  for(let minute=1;minute<=7;minute++) {
    await pause(60000);
    evidence.samples.push({minute,observedAt:new Date().toISOString(),pid:pid(),checkpoint:checkpoint(),power:run('shell','dumpsys','power').split('\n').filter(s=>/mWakefulness=|mIsPowered=|mStayOn=/.test(s)).map(s=>s.trim())});
    save(); console.log(`Sample ${minute}/7 saved`);
  }
  evidence.sampledAt = new Date().toISOString();
  let prior = Date.parse(evidence.before.checkpoint);
  evidence.everySampleAdvanced = evidence.samples.every(sample => {const next=Date.parse(sample.checkpoint.checkpoint);const advanced=next>prior;prior=next;return advanced;});
  save();
  run('shell','input','keyevent','KEYCODE_WAKEUP');
  console.log('Sampling complete; unlock and resume separately');
})().catch(error=>{console.error(error);process.exitCode=1;});

