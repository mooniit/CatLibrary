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
  const session=(await request('/auth/v1/signup',null,'POST',{})).value;
  assert(session.access_token);
  const responses=await Promise.all(Array.from({length:12},()=>request('/rest/v1/rpc/bootstrap_identity',session.access_token,'POST',{})));
  for(const response of responses) {
    assert(response.ok, JSON.stringify({status:response.status,error:response.value}));
    assert.deepEqual(response.value,{owner_id:session.user.id,miao_coins:30,eagle_pounds:0,gems:0});
  }
  const ledger=await request('/rest/v1/wallet_entries?select=kind,miao_delta',session.access_token);
  assert.deepEqual(ledger.value,[{kind:'initial',miao_delta:30}]);
  const mutation=await request('/rest/v1/wallets?owner_id=eq.'+session.user.id,session.access_token,'PATCH',{miao_coins:999});
  assert.equal(mutation.status,403);
  const other=(await request('/auth/v1/signup',null,'POST',{})).value;
  const hidden=await request('/rest/v1/wallets?select=*',other.access_token);
  assert.deepEqual(hidden.value,[]);
  const anonymous=await request('/rest/v1/rpc/bootstrap_identity',null,'POST',{});
  assert(!anonymous.ok);
  const evidence={time:new Date().toISOString(),scope:'local Supabase actual HTTP; 12 concurrent bootstrap requests, one initial ledger entry, direct balance update denied, other-user read isolated, unauthenticated call denied',result:'PASS'};
  fs.writeFileSync(path.join(root,'docs/evidence/m1-identity-http.json'),JSON.stringify(evidence,null,2)+'\n');
  console.log('PASS concurrent bootstrap, one initial grant, write/read authorization');
})().catch(e=>{console.error(e);process.exitCode=1});

