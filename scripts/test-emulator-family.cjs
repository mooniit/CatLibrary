// Emulator inviter + separate local HTTP applicant; no second physical-device claim.
const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
const {nodes,tap,shown,pause}=require('./test-android-probe.cjs');
assert(/^emulator-\d+$/.test(process.argv[2]||'emulator-5554'));
const root=path.resolve(__dirname,'..');
const config=JSON.parse(fs.readFileSync(path.join(root,'.tooling/local-phone-defines.json'),'utf8').replace(/^\uFEFF/,''));
assert.equal(config.SUPABASE_URL,'http://127.0.0.1:54321');
async function post(route,token,body={}) {
  const r=await fetch(config.SUPABASE_URL+route,{method:'POST',headers:{apikey:config.SUPABASE_ANON_KEY,'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
  const value=await r.json();assert(r.ok,JSON.stringify(value));return value;
}
(async()=>{
  await tap('家庭与邀请');
  await pause(1000);
  if(nodes().some(n=>n['content-desc']==='创建我的小屋')) await tap('创建我的小屋');
  await pause(1000);
  shown('小屋成员 1/2');
  const code=nodes().map(n=>n['content-desc']||n.text).find(s=>/^[a-f0-9]{32}$/.test(s));
  assert(code,'Invitation must be visible to creator');
  const applicant=await post('/auth/v1/signup',null);
  const pending=await post('/rest/v1/rpc/request_family_join',applicant.access_token,{code});
  assert.equal(pending.family,null);
  await tap('刷新小屋');await pause(800);
  // Scroll this app's list until the exact test applicant is visible.
  const {run}=require('./test-android-probe.cjs');
  for(let i=0;i<5&&!nodes().some(n=>(n['content-desc']||n.text).includes(applicant.user.id));i++) run('shell','input','swipe','160','420','160','150','350');
  shown(applicant.user.id);
  assert.equal(nodes().filter(n=>n['content-desc']==='同意加入').length,1,'Do not approve unrelated requests');
  await tap('同意加入');await pause(800);
  const joined=await post('/rest/v1/rpc/family_state',applicant.access_token);
  assert.equal(joined.members.length,2);
  assert(joined.members.some(m=>m.user_id===applicant.user.id));
  const evidence={time:new Date().toISOString(),result:'PASS',scope:'Emulator UI creator plus independent HTTP applicant on local Supabase; create home, visible code, pending application, UI approval, applicant reads two-member family; NOT two physical devices'};
  fs.writeFileSync(path.join(root,'docs/evidence/m1-family-emulator.json'),JSON.stringify(evidence,null,2)+'\n');
  console.log('PASS actual home creation and invitation approval via emulator UI');
})().catch(e=>{console.error(e);process.exitCode=1});
