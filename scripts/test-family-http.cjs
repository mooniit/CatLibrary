// Real local HTTP concurrency and RLS checks. No administrative key is used.
const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const config=JSON.parse(fs.readFileSync(path.join(root,'.tooling/local-phone-defines.json'),'utf8').replace(/^\uFEFF/,''));
const base=config.SUPABASE_URL;
assert.equal(base,'http://127.0.0.1:54321');
async function request(route,token,method='GET',body) {
  const response=await fetch(base+route,{method,headers:{apikey:config.SUPABASE_ANON_KEY,...(token?{Authorization:'Bearer '+token}:{}),'Content-Type':'application/json'},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
  const text=await response.text();
  return {status:response.status,ok:response.ok,value:text?JSON.parse(text):null};
}
(async()=>{
  async function user(){const r=await request('/auth/v1/signup',null,'POST',{});assert(r.ok);return r.value;}
  async function rpc(session,name,args={}) {return request('/rest/v1/rpc/'+name,session.access_token,'POST',args);}
  const [a,b,c]=await Promise.all([user(),user(),user()]);
  const home=await rpc(a,'create_family');assert(home.ok);
  const code=home.value.family.invite_code;
  const applications=await Promise.all([b,c].map(u=>rpc(u,'request_family_join',{code})));
  applications.forEach(r=>{assert(r.ok);assert.equal(r.value.family,null);});
  const pending=(await rpc(a,'family_state')).value.requests;
  assert.equal(pending.length,2);
  const selfApproval=await rpc(b,'decide_family_join',{request_id:pending.find(r=>r.applicant_id===b.user.id).id,approve:true});
  assert.equal(selfApproval.status,403);
  const approvals=await Promise.all(pending.map(r=>rpc(a,'decide_family_join',{request_id:r.id,approve:true})));
  assert.equal(approvals.filter(r=>r.ok).length,1);
  const state=(await rpc(a,'family_state')).value;
  assert.equal(state.members.length,2);
  assert.equal(state.requests.length,1);
  const winner=state.members.find(m=>!m.is_me).user_id===b.user.id?b:c;
  const loser=winner===b?c:b;
  const winnerHome=(await rpc(winner,'family_state')).value;
  assert.equal(winnerHome.family.id,home.value.family.id);
  assert.equal(winnerHome.family.invite_code,null);
  assert.equal(winnerHome.requests.length,0);
  assert(!(await rpc(winner,'request_family_join',{code})).ok);
  assert((await rpc(a,'decide_family_join',{request_id:state.requests[0].id,approve:false})).ok);
  assert.equal((await rpc(loser,'family_state')).value.requests[0].status,'rejected');
  assert((await rpc(loser,'create_family')).ok);
  assert(!(await rpc(loser,'request_family_join',{code})).ok);
  const direct=await request('/rest/v1/family_members',b.access_token,'POST',{user_id:b.user.id,family_id:home.value.family.id});
  assert.equal(direct.status,403);
  const evidence={time:new Date().toISOString(),result:'PASS',scope:'Local HTTP with three anonymous users; create/apply/approve/reject, two simultaneous approvals admit only one, no self-approval or direct membership writes, no existing-family merge, creator-only invite and request visibility'};
  fs.writeFileSync(path.join(root,'docs/evidence/m1-family-http.json'),JSON.stringify(evidence,null,2)+'\n');
  console.log('PASS family workflow, concurrent capacity and authorization');
})().catch(e=>{console.error(e);process.exitCode=1});
