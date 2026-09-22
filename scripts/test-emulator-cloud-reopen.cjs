// Emulator UI + actual local backend; records UUIDs only, never session tokens.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {run,nodes,tap,pause} = require('./test-android-probe.cjs');
assert(/^emulator-\d+$/.test(process.argv[2] || 'emulator-5554'));
const pkg = 'com.catlibrary.cat_library_demo';
async function probe() {
  await tap('猫窝',true);
  await tap('设置');
  await tap('验证连接与私有样例文件');
  for (let i=0;i<15;i++) {
    const text = nodes().map(n=>n['content-desc']+' '+n.text).join('\n');
    assert(!text.includes('验证失败：'),'Cloud probe reported failure');
    if (text.includes('往返成功')) {
      const id = text.match(/用户编号：([0-9a-f-]{36})/);
      assert(id,'Successful result must include identity');
      run('shell','input','keyevent','KEYCODE_BACK');
      await pause(500);
      return id[1];
    }
    await pause(1000);
  }
  throw new Error('Cloud UI probe timed out');
}
(async()=>{
  const evidence={scope:'Android emulator to local Supabase, process restart identity reuse; NOT iOS or remote cloud',startedAt:new Date().toISOString()};
  evidence.firstId=await probe();
  run('shell','am','force-stop',pkg);
  run('shell','am','start','-W','-n',pkg+'/.MainActivity');
  await pause(2500);
  evidence.reopenedId=await probe();
  assert.equal(evidence.reopenedId,evidence.firstId);
  evidence.result='pass';evidence.finishedAt=new Date().toISOString();
  fs.writeFileSync(path.resolve(__dirname,'../docs/evidence/m0-emulator-cloud-reopen.json'),JSON.stringify(evidence,null,2)+'\n');
  console.log('PASS local cloud roundtrip before and after process restart; identity unchanged');
})().catch(e=>{console.error(e);process.exitCode=1});
