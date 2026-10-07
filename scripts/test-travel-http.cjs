// Local isolated identities only. No device session is read or replaced.
const fs=require('node:fs'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto'),{execFileSync}=require('node:child_process');
const config=JSON.parse(fs.readFileSync('.tooling/local-phone-defines.json','utf8').replace(/^\uFEFF/,''));
assert.equal(config.SUPABASE_URL,'http://127.0.0.1:54321');
const file='.tooling/m6-test-fixture.json',defines='.tooling/m6-integration-defines.json';
const sql=q=>execFileSync('docker',['exec','supabase_db_CatLibrary','psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-Atc',q],{encoding:'utf8'}).trim();
async function api(u,m,p={}){const r=await fetch(config.SUPABASE_URL+'/rest/v1/rpc/'+m,{method:'POST',headers:{apikey:config.SUPABASE_ANON_KEY,Authorization:'Bearer '+u.access,'Content-Type':'application/json'},body:JSON.stringify(p),signal:AbortSignal.timeout(15000)});return {ok:r.ok,value:await r.json()};}
async function rpc(u,m,p={}){const r=await api(u,m,p);assert(r.ok,'RPC '+m+' failed: '+r.value.message);return r.value;}
async function identity(){const r=await fetch(config.SUPABASE_URL+'/auth/v1/signup',{method:'POST',headers:{apikey:config.SUPABASE_ANON_KEY,'Content-Type':'application/json'},body:'{}'});assert(r.ok);const a=await r.json();const u={id:a.user.id,access:a.access_token,refresh:a.refresh_token};await rpc(u,'bootstrap_identity');return u;}
async function prepare(){
  assert(!fs.existsSync(file),'Recorded M6 fixture exists; clean explicitly first');
  const f={scope:'isolated-local-M6',users:[],home:null,cats:[]};fs.writeFileSync(file,JSON.stringify(f));
  for(let i=0;i<3;i++){f.users.push(await identity());fs.writeFileSync(file,JSON.stringify(f));}
  const [a,b,c]=f.users,home=await rpc(a,'create_family');f.home=home.family.id;fs.writeFileSync(file,JSON.stringify(f));
  await rpc(b,'request_family_join',{code:home.family.invite_code});await rpc(a,'decide_family_join',{request_id:(await rpc(a,'family_state')).requests[0].id,approve:true});
  await rpc(c,'create_family');
  await rpc(a,'adopt_cat',{appearance_key:'black_short',cat_name:'远行猫甲'});await rpc(b,'adopt_cat',{appearance_key:'black_short',cat_name:'远行猫乙'});
  f.cats=(await rpc(a,'cats_state')).cats.map(c=>c.id);fs.writeFileSync(file,JSON.stringify(f));
  sql(`update public.wallets set gems=120,miao_coins=100 where owner_id in ('${a.id}','${b.id}')`);
  fs.writeFileSync(defines,JSON.stringify({...config,M6_A_REFRESH:a.refresh,M6_B_REFRESH:b.refresh,M6_CAT_A:f.cats[0],M6_CAT_B:f.cats[1],M6_HOME:f.home,M6_CLOCK_NONCE:randomUUID()}));
  return f;
}
function cleanup(){
  if(!fs.existsSync(file))return;
  const f=JSON.parse(fs.readFileSync(file));assert.equal(f.scope,'isolated-local-M6');
  f.users.forEach(u=>assert.match(u.id,/^[0-9a-f-]{36}$/));if(f.home)assert.match(f.home,/^[0-9a-f-]{36}$/);
  const users=f.users.map(u=>`'${u.id}'`).join(',');if(users){sql(`begin;
    delete from public.travel_return_seen where user_id in (${users}) or trip_id in (select id from public.cat_trips where arranged_by in (${users}));
    delete from public.cat_travel_visits where trip_id in (select id from public.cat_trips where arranged_by in (${users}));
    delete from public.furniture_requests where user_id in (${users});
    delete from public.room_layouts where family_id in (select id from public.families where creator_id in (${users}));
    delete from public.furniture_inventory where family_id in (select id from public.families where creator_id in (${users}));
    delete from public.travel_requests where user_id in (${users});
    delete from public.travel_return_failures where family_id in (select id from public.families where creator_id in (${users}));
    delete from public.cat_trips where arranged_by in (${users});
    delete from public.daily_cat_charges where owner_id in (${users});delete from public.cat_feedings where payer_id in (${users});
    delete from public.cats where owner_id in (${users});
    delete from public.family_settlement_failures where family_id in (select id from public.families where creator_id in (${users}));
    delete from public.family_daily_settlements where family_id in (select id from public.families where creator_id in (${users}));
    delete from public.family_join_requests where applicant_id in (${users}) or family_id in (select id from public.families where creator_id in (${users}));
    delete from public.family_members where user_id in (${users});delete from public.families where creator_id in (${users});
    delete from public.daily_interest_charges where owner_id in (${users});delete from public.study_days where owner_id in (${users});
    delete from public.wallet_entries where owner_id in (${users});delete from public.wallets where owner_id in (${users});delete from auth.users where id in (${users});
    commit;`);}
  fs.unlinkSync(file);if(fs.existsSync(defines))fs.unlinkSync(defines);
}
async function verify(f){
  const [a,b,c]=f.users,p={request_id:randomUUID(),target_cat:f.cats[0],target_family:f.home};
  const same=await Promise.all(Array.from({length:12},()=>rpc(a,'start_cat_travel',p)));
  assert(same.every(r=>r.trip_id===same[0].trip_id));assert.equal((await rpc(a,'travel_state')).wallet.gems,60);
  assert(!(await api(b,'start_cat_travel',p)).ok,'cross-user receipt replay denied');
  assert.equal((await rpc(c,'start_cat_travel',{...p,request_id:randomUUID()})).reason,'family_changed');
  const race=await Promise.all([a,b].map(u=>rpc(u,'start_cat_travel',{request_id:randomUUID(),target_cat:f.cats[1],target_family:f.home})));
  assert.equal(race.filter(r=>r.status==='started').length,1);assert.equal(race.filter(r=>r.reason==='already_traveling').length,1);
  assert.equal((await rpc(a,'travel_state')).wallet.gems+(await rpc(b,'travel_state')).wallet.gems,120);
  sql(`update public.cat_trips set destination='palace',started_at=now()-interval '25 hours',ends_at=now()-interval '1 hour' where family_id='${f.home}'`);
  const returned=await Promise.all(Array.from({length:10},(_,i)=>rpc(i%2?a:b,'travel_state')));
  assert(returned.every(s=>s.cats.every(c=>c.trip_id===null)));
  const albumA=await rpc(a,'family_album'),albumB=await rpc(b,'family_album');
  assert.equal(albumA.photos.length,2);assert.equal(albumB.photos.length,2);assert.equal((await rpc(c,'family_album')).photos.length,0);
  const inventory=(await rpc(a,'furniture_state')).inventory;assert.equal(inventory.length,2);assert.equal(new Set(inventory.map(i=>i.source_cat_id)).size,2);
  assert(inventory.every(i=>i.source==='souvenir'&&i.source_cat_name&&i.source_destination==='故宫'));
  assert(!(await api(a,'return_family_trips',{home:f.home,as_of:'2099-01-01T00:00:00Z'})).ok);
  fs.writeFileSync('docs/evidence/m6-http.json',JSON.stringify({at:new Date().toISOString(),result:'PASS',scope:'Local HTTP isolated identities, test gems, host advances only fixture trip clocks',checks:['12 same-ID starts: one trip and one debit','different members race same cat: one accepted','cross-user replay and outsider denied','10 simultaneous return reads: exactly two rewards','same-appearance cats independent','family album private to members','source cat preserved','client cannot forge return clock']},null,2)+'\n');
  console.log('PASS travel HTTP concurrency, idempotency, returns, shared album and provenance');
}
(async()=>{const mode=process.argv[2]||'verify';if(mode==='cleanup'){cleanup();console.log('Cleaned only recorded M6 fixtures');return;}const f=await prepare();if(mode==='prepare'){console.log('Prepared isolated M6 native fixture; private config ignored');return;}try{await verify(f)}finally{cleanup()}})().catch(e=>{console.error(e.message);process.exitCode=1});
