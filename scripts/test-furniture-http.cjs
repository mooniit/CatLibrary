// Local-only independent test identities. Never reads or replaces device sessions.
const fs=require('node:fs'),assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto'),{execFileSync}=require('node:child_process');
const config=JSON.parse(fs.readFileSync('.tooling/local-phone-defines.json','utf8').replace(/^\uFEFF/,''));
assert.equal(config.SUPABASE_URL,'http://127.0.0.1:54321');
const file='.tooling/m5-test-fixture.json',defines='.tooling/m5-integration-defines.json';
const sql=q=>execFileSync('docker',['exec','supabase_db_CatLibrary','psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-Atc',q],{encoding:'utf8'}).trim();
async function api(user,method,params={}) {
 const r=await fetch(config.SUPABASE_URL+'/rest/v1/rpc/'+method,{method:'POST',
  headers:{apikey:config.SUPABASE_ANON_KEY,Authorization:'Bearer '+user.access,'Content-Type':'application/json'},
  body:JSON.stringify(params),signal:AbortSignal.timeout(15000)});
 return {ok:r.ok,value:await r.json()};
}
async function rpc(u,m,p={}){const r=await api(u,m,p);assert(r.ok,'RPC '+m+' failed: '+r.value.message);return r.value}
async function identity(){
 const r=await fetch(config.SUPABASE_URL+'/auth/v1/signup',{method:'POST',headers:{apikey:config.SUPABASE_ANON_KEY,'Content-Type':'application/json'},body:'{}'});
 assert(r.ok,'test identity creation failed');const a=await r.json();
 const user={id:a.user.id,access:a.access_token,refresh:a.refresh_token};
 await rpc(user,'bootstrap_identity');return user;
}
async function prepare(){
 assert(!fs.existsSync(file),'Prior isolated fixture exists; clean it explicitly before preparing a new one');
 const users=[];
 const f={users,home:null,sku:'m5-test-chair-'+randomUUID().slice(0,8),scope:'isolated-local-M5'};
 fs.writeFileSync(file,JSON.stringify(f));
 for(let i=0;i<3;i++){users.push(await identity());fs.writeFileSync(file,JSON.stringify(f));}
 const [a,b,c]=users;
 const family=await rpc(a,'create_family');f.home=family.family.id;fs.writeFileSync(file,JSON.stringify(f));
 await rpc(b,'request_family_join',{code:family.family.invite_code});
 const state=await rpc(a,'family_state');
 await rpc(a,'decide_family_join',{request_id:state.requests[0].id,approve:true});
 await rpc(c,'create_family');
 sql(`begin;
  insert into public.room_test_families values('${f.home}');
  update public.room_policies set lease_seconds=120,renewal_seconds=30 where id='test';
  insert into public.furniture_products(sku,label,theme,kind,placement,geometry,price,currency,purchase_limit,active,is_test)
   select '${f.sku}','隔离测试椅子','lunar',kind,placement,geometry,5,'miao',4,true,true
   from public.furniture_products where sku='lunar-chair';
  update public.wallets set miao_coins=100,gems=12,eagle_pounds=10 where owner_id in ('${a.id}','${b.id}');
  commit;`);
 fs.writeFileSync(defines,JSON.stringify({...config,M5_A_REFRESH:a.refresh,M5_B_REFRESH:b.refresh,M5_TEST_SKU:f.sku}));
 return f;
}
function cleanup(){
 if(!fs.existsSync(file))return;
 const f=JSON.parse(fs.readFileSync(file));assert.equal(f.scope,'isolated-local-M5');
 for(const u of f.users)assert.match(u.id,/^[0-9a-f-]{36}$/);
 assert.match(f.sku,/^m5-test-chair-[0-9a-f]{8}$/);
 const users=f.users.map(u=>"'"+u.id+"'").join(',');
 if(users)sql(`begin;
  delete from public.furniture_requests where user_id in (${users});
  delete from public.furniture_inventory where purchased_by in (${users});
  delete from public.room_layouts where family_id in (select id from public.families where creator_id in (${users}));
  delete from public.room_test_families where family_id in (select id from public.families where creator_id in (${users}));
  delete from public.family_join_requests where applicant_id in (${users}) or family_id in (select id from public.families where creator_id in (${users}));
  delete from public.family_daily_settlements where family_id in (select id from public.families where creator_id in (${users}));
  delete from public.family_members where user_id in (${users});
  delete from public.families where creator_id in (${users});
  delete from public.daily_interest_charges where owner_id in (${users});
  delete from public.study_days where owner_id in (${users});
  delete from public.wallet_entries where owner_id in (${users});
  delete from public.wallets where owner_id in (${users});
  delete from auth.users where id in (${users});
  delete from public.furniture_products where sku='${f.sku}' and is_test;
  commit;`);
 fs.unlinkSync(file);if(fs.existsSync(defines))fs.unlinkSync(defines);
}
async function verify(f){
 const [a,b,c]=f.users;
 const first={request_id:randomUUID(),product_sku:f.sku,target_family:f.home};
 const same=await Promise.all(Array.from({length:12},()=>rpc(a,'purchase_furniture',first)));
 assert(same.every(r=>r.instance_id===same[0].instance_id));
 let s=await rpc(a,'furniture_state');assert.equal(s.wallet.miao_coins,95);assert.equal(s.inventory.length,1);
 assert(!(await api(b,'purchase_furniture',first)).ok,'cross-user replay denied');
 const outsider=await rpc(c,'purchase_furniture',{request_id:randomUUID(),product_sku:f.sku});
 assert.equal(outsider.reason,'product_unavailable','test product absent from production families');
 const wrongFamily=await rpc(c,'purchase_furniture',{request_id:randomUUID(),product_sku:f.sku,target_family:f.home});
 assert.equal(wrongFamily.reason,'family_changed');
 await rpc(a,'purchase_furniture',{request_id:randomUUID(),product_sku:f.sku,target_family:f.home});
 await rpc(b,'purchase_furniture',{request_id:randomUUID(),product_sku:f.sku,target_family:f.home});
 const last=await Promise.all([a,b].map(u=>rpc(u,'purchase_furniture',{request_id:randomUUID(),product_sku:f.sku,target_family:f.home})));
 assert.equal(last.filter(r=>r.status==='purchased').length,1);
 s=await rpc(a,'furniture_state');assert.equal(s.inventory.length,4);
 assert.equal(s.wallet.miao_coins+(await rpc(b,'furniture_state')).wallet.miao_coins,180);
 const token= randomUUID(),other=randomUUID();
 const acquired=await Promise.all([a,b].map((u,i)=>rpc(u,'room_editor',{action:'acquire',editor_token:i?other:token})));
 assert.equal(acquired.filter(r=>r.status==='acquired').length,1);
 const win=acquired[0].status==='acquired'?a:b,lose=win===a?b:a,t=win===a?token:other;
 const placed={standard:'room-standard-v1',items:[{instance_id:s.inventory[0].id,gx:2,gy:2,facing:'x',slot:null,artwork:'starry'}]};
 const save={request_id:randomUUID(),editor_token:t,expected_version:0,proposed:placed};
 await rpc(win,'save_room_layout',save); // Deliberately discard the success receipt.
 const receipt=await rpc(win,'furniture_request',{target_request:save.request_id});assert.equal(receipt.version,1);
 await rpc(win,'room_editor',{action:'release',editor_token:t});
 const nextToken=randomUUID();await rpc(lose,'room_editor',{action:'acquire',editor_token:nextToken});
 await rpc(lose,'save_room_layout',{request_id:randomUUID(),editor_token:nextToken,expected_version:1,proposed:{standard:'room-standard-v1',items:[]}});
 assert.equal((await rpc(win,'save_room_layout',save)).version,1);
 assert.equal((await rpc(win,'furniture_state')).version,2);
 assert.equal((await rpc(win,'furniture_state')).layout.items.length,0);
 sql(`update public.room_layouts set lock_until=clock_timestamp()-interval '1 second' where family_id='${f.home}'`);
 const expired=await rpc(lose,'save_room_layout',{request_id:randomUUID(),editor_token:nextToken,expected_version:2,proposed:placed});
 assert.equal(expired.reason,'lease_expired');
 fs.writeFileSync('docs/evidence/m5-http.json',JSON.stringify({at:new Date().toISOString(),result:'PASS',scope:'Local Supabase HTTP; isolated synthetic users/product/100 test coins',checks:['12 same-ID concurrent purchases issue one instance','two members race at family purchase cap','outsider test scope denied','pending purchase stays bound to its original family','simultaneous lease acquisition admits one','lost save receipt lookup','partner later save preserved','expired lease refused']},null,2)+'\n');
 console.log('PASS local HTTP purchase concurrency, stock cap, lease race, lost receipt and partner save');
}
(async()=>{
 const mode=process.argv[2]||'verify';
 if(mode==='cleanup'){cleanup();console.log('Cleaned only recorded M5 fixture identities and assets');return;}
 const f=await prepare();
 if(mode==='prepare'){console.log('Prepared isolated M5 integration fixture; private config is ignored');return;}
 try{await verify(f)}finally{cleanup()}
})().catch(e=>{console.error(e.message);process.exitCode=1});
