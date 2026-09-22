const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
const {run,nodes,pause}=require('./test-android-probe.cjs');
assert(/^emulator-\d+$/.test(process.argv[2]||'emulator-5554'));
const pkg='com.catlibrary.cat_library_demo';
async function wallet() {
  for(let attempt=0;attempt<12;attempt++) {
    const text=nodes().map(n=>n['content-desc']+' '+n.text).join('\n');
    assert(!text.includes('连接失败'),'Automatic bootstrap failed');
    const match=text.match(/喵喵币 (\d+) · 鹰镑 (\d+) · 宝石 (\d+)/);
    if(match) {
      assert(text.includes('个人钱包 · 已连接'));
      return match.slice(1).map(Number);
    }
    await pause(1000);
  }
  throw new Error('No server wallet displayed');
}
(async()=>{
  const before=await wallet();
  assert.deepEqual(before,[30,0,0]);
  run('shell','am','force-stop',pkg);
  run('shell','am','start','-W','-n',pkg+'/.MainActivity');
  await pause(2000);
  const after=await wallet();
  assert.deepEqual(after,before);
  const evidence={time:new Date().toISOString(),scope:'Android emulator, real local Supabase auto-bootstrap and displayed wallet after process restart; no phone/iOS/remote cloud claim',before,after,result:'PASS'};
  fs.writeFileSync(path.resolve(__dirname,'../docs/evidence/m1-emulator-bootstrap.json'),JSON.stringify(evidence,null,2)+'\n');
  console.log('PASS automatic startup, real wallet 30/0/0, unchanged after restart');
})().catch(e=>{console.error(e);process.exitCode=1});
