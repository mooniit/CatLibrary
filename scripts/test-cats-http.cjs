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
  async function rpc(u,name,args={}){return request('/rest/v1/rpc/'+name,u.access_token,'POST',args);}
  const [a,b,c]=await Promise.all([user(),user(),user()]);
  await Promise.all([a,b].map(u=>rpc(u,'bootstrap_identity')));
  const home=(await rpc(a,'create_family')).value.family;
  await rpc(b,'request_family_join',{code:home.invite_code});
  const join=(await rpc(a,'family_state')).value.requests[0];
  assert((await rpc(a,'decide_family_join',{request_id:join.id,approve:true})).ok);
  const args={appearance_key:'black_short',cat_name:'共同名字'};
  const race=await Promise.all([a,b].map(u=>rpc(u,'adopt_cat',args)));
  assert.equal(race.filter(r=>r.ok).length,1);
  const winner=race[0].ok?a:b,loser=winner===a?b:a;
  const retries=await Promise.all(Array.from({length:8},()=>rpc(winner,'adopt_cat',args)));
  retries.forEach(r=>{assert(r.ok);assert.equal(r.value.cats.length,1);assert.equal(r.value.cats[0].owner_id,winner.user.id);});
  assert((await rpc(loser,'adopt_cat',{appearance_key:'black_short',cat_name:'另一只黑猫'})).ok);
  assert(!(await rpc(winner,'adopt_cat',{appearance_key:'black_short',cat_name:'不可重复'})).ok);
  const seconds=await Promise.all([a,b].map((u,i)=>rpc(u,'adopt_cat',{appearance_key:'light_long',cat_name:'白猫'+i})));
  seconds.forEach(r=>assert(r.ok));
  const state=(await rpc(a,'cats_state')).value;
  assert.equal(state.cats.length,4);assert.equal(state.remaining,0);
  assert.equal(state.cats.filter(cat=>cat.owner_id===a.user.id).length,2);
  assert.equal(state.cats.filter(cat=>cat.owner_id===b.user.id).length,2);
  for(const u of [a,b]) assert.equal((await rpc(u,'bootstrap_identity')).value.miao_coins,30);
  assert.deepEqual((await rpc(c,'cats_state')).value.cats,[]);
  assert(!(await rpc(c,'adopt_cat',args)).ok);
  const forged=await request('/rest/v1/cats',a.access_token,'POST',{family_id:home.id,owner_id:b.user.id,appearance:'black_short',name:'forged'});
  assert.equal(forged.status,403);
  const evidence={time:new Date().toISOString(),result:'PASS',scope:'Local HTTP: two family members race same name, eight identical retries create one cat, owner inferred from auth, two appearances each/four family cats, balances unchanged, outsider and forged owner denied'};
  fs.writeFileSync(path.join(root,'docs/evidence/m1-cats-http.json'),JSON.stringify(evidence,null,2)+'\n');
  console.log('PASS concurrent naming, retry safety, quotas, free adoption and owner isolation');
})().catch(e=>{console.error(e);process.exitCode=1});
