const fs=require('node:fs');
const path=require('node:path');
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const root=path.resolve(__dirname,'..');
const config=JSON.parse(fs.readFileSync(path.join(root,'.tooling/local-phone-defines.json'),'utf8').replace(/^\uFEFF/,''));
assert.equal(config.SUPABASE_URL,'http://127.0.0.1:54321');
async function call(route,token,body) {
 const r=await fetch(config.SUPABASE_URL+route,{method:'POST',headers:{apikey:config.SUPABASE_ANON_KEY,'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify(body),signal:AbortSignal.timeout(15000)});
 return {ok:r.ok,status:r.status,value:await r.json()};
}
(async()=>{
 const auth=await call('/auth/v1/signup',null,{});
 const token=auth.value.access_token; assert(token);
 assert((await call('/rest/v1/rpc/bootstrap_identity',token,{})).ok);
 const first={session_id:randomUUID(),start_at:'2026-09-01T00:00:00Z',checkpoint_at:'2026-09-01T00:05:30Z',is_confirmed:true};
 const replies=await Promise.all(Array.from({length:12},()=>call('/rest/v1/rpc/sync_study_session',token,first)));
 for(const r of replies) {assert(r.ok,JSON.stringify(r));assert.equal(r.value.wallet.miao_coins,40);}
 const second={session_id:randomUUID(),start_at:'2026-09-01T01:00:00Z',checkpoint_at:'2026-09-01T01:05:40Z',is_confirmed:true};
 // Drop the first successful reply deliberately, then resend unchanged.
 assert((await call('/rest/v1/rpc/sync_study_session',token,second)).ok);
 const retry=await call('/rest/v1/rpc/sync_study_session',token,second);
 assert.equal(retry.value.wallet.miao_coins,52);
 assert.equal(retry.value.days[0].eligible_ms,670000);
 const overlap={start_at:'2026-09-02T00:00:00Z',checkpoint_at:'2026-09-02T00:10:00Z',is_confirmed:true};
 const race=await Promise.all([1,2].map(()=>call('/rest/v1/rpc/sync_study_session',token,{...overlap,session_id:randomUUID()})));
 assert.equal(race.filter(r=>r.ok).length,1);
 const different=await Promise.all([0,1].map(n=>call('/rest/v1/rpc/sync_study_session',token,{session_id:randomUUID(),start_at:`2026-09-03T0${n}:00:00Z`,checkpoint_at:`2026-09-03T0${n}:05:30Z`,is_confirmed:true})));
 assert(different.every(r=>r.ok));
 const state=await call('/rest/v1/rpc/study_state',token,{});
 assert.equal(state.value.wallet.miao_coins,94);
 const evidence={at:new Date().toISOString(),result:'PASS',scope:'Local Supabase HTTP: 12 same-ID concurrent requests; real committed response discarded then retried; overlapping race admits one; non-overlapping race accumulates remainders',owner_id:auth.value.user.id};
 fs.writeFileSync(path.join(root,'docs/evidence/m2-study-http.json'),JSON.stringify(evidence,null,2)+'\n');
 console.log('PASS: concurrency, lost response, overlap and cumulative remainder');
})().catch(e=>{console.error(e);process.exitCode=1});
