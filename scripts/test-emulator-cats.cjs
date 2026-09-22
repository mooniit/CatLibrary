const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
const {run,nodes,tap,shown,pause}=require('./test-android-probe.cjs');
assert(/^emulator-\d+$/.test(process.argv[2]||'emulator-5554'));
(async()=>{
  await tap('猫咪管理');await pause(800);
  const text=nodes().map(n=>n['content-desc']||n.text).join('\n');
  const remaining=Number(text.match(/本人剩余领养名额：(\d)/)?.[1]);
  assert(remaining>0,'Do not alter an exhausted test profile');
  const catName='M1Cat'+Date.now().toString().slice(-7);
  let edit=nodes().find(n=>n.class==='android.widget.EditText');
  for(let i=0;i<4&&!edit;i++) {
    run('shell','input','swipe','160','410','160','160','350');
    edit=nodes().find(n=>n.class==='android.widget.EditText');
  }
  assert(edit,'Name field must be visible');
  const b=edit.bounds.match(/\d+/g).map(Number);
  run('shell','input','tap',String((b[0]+b[2])/2),String((b[1]+b[3])/2));
  run('shell','input','text',catName);
  run('shell','input','keyevent','KEYCODE_BACK');
  await tap('免费领养');await pause(1000);
  shown(catName);shown('本人剩余领养名额：'+(remaining-1));
  run('shell','input','keyevent','KEYCODE_BACK');await pause(500);
  await tap('猫咪管理');await pause(1000);
  shown(catName);shown('本人剩余领养名额：'+(remaining-1));shown('登记主人：我');
  const evidence={time:new Date().toISOString(),result:'PASS',catName,remainingBefore:remaining,remainingAfter:remaining-1,scope:'Android emulator using real local Supabase: enter name, adopt via UI, owner/quota displayed, close and reopen page reloads saved cat; NOT phone/iOS or cold process restart'};
  fs.writeFileSync(path.resolve(__dirname,'../docs/evidence/m1-cats-emulator.json'),JSON.stringify(evidence,null,2)+'\n');
  console.log('PASS real UI adoption and server reload with owner and remaining quota');
})().catch(e=>{console.error(e);process.exitCode=1});
