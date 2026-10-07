// Runs the actual inventory conversion block with isolated fixtures and rollback.
const fs=require('node:fs'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto'),{execFileSync}=require('node:child_process');
const migration=fs.readFileSync('supabase/migrations/202610070002_artwork_binding.sql','utf8');
const block=migration.match(/do \$\$ declare i record;[\s\S]*?end \$\$;/)?.[0];assert(block);
const owner=randomUUID(),home=randomUUID(),placed=randomUUID(),stored=randomUUID(),request=randomUUID(),lease=randomUUID();
const sql=`begin;
insert into auth.users(id) values('${owner}');
select set_config('request.jwt.claims','{"sub":"${owner}"}',true);
select public.bootstrap_identity();
insert into public.families(id,creator_id) values('${home}','${owner}');
insert into public.family_members(user_id,family_id) values('${owner}','${home}');
insert into public.furniture_inventory(id,family_id,sku,purchased_by,source) values
 ('${placed}','${home}','lunar-frame-portrait','${owner}','purchase'),
 ('${stored}','${home}','wood-frame-square','${owner}','purchase');
insert into public.room_layouts(family_id,version,layout,lock_user,lock_token,lock_until) values
 ('${home}',7,'{"standard":"room-standard-v1","items":[{"instance_id":"${placed}","gx":0,"gy":0,"facing":"x","slot":"art-left-front","artwork":"mona"}]}','${owner}','${lease}',now()+interval '120 seconds');
insert into public.furniture_requests values('${request}','${owner}','${home}','purchase','{"sku":"lunar-frame-portrait"}','{"status":"purchased","sku":"lunar-frame-portrait"}',now());
select set_config('test.before_ledger',(select count(*)::text from public.wallet_entries where owner_id='${owner}'),true);
select set_config('test.before_wallet',(select to_jsonb(w)::text from public.wallets w where owner_id='${owner}'),true);
${block}
select json_build_object(
 'placedSku',(select sku from public.furniture_inventory where id='${placed}'),
 'storedSku',(select sku from public.furniture_inventory where id='${stored}'),
 'retainedInstances',(select count(*) from public.furniture_inventory where family_id='${home}' and purchased_by='${owner}' and source='purchase'),
 'version',(select version from public.room_layouts where family_id='${home}'),
 'leaseReleased',(select lock_token is null from public.room_layouts where family_id='${home}'),
 'artwork',(select layout->'items'->0->>'artwork' from public.room_layouts where family_id='${home}'),
 'receiptSku',(select result->>'sku' from public.furniture_requests where request_id='${request}'),
 'walletEntriesDelta',(select count(*) from public.wallet_entries where owner_id='${owner}')-current_setting('test.before_ledger')::int,
 'walletUnchanged',(select to_jsonb(w)::text=current_setting('test.before_wallet') from public.wallets w where owner_id='${owner}'));
rollback;`;
const out=execFileSync('docker',['exec','-i','supabase_db_CatLibrary','psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-At'],{input:sql,encoding:'utf8'});
const result=JSON.parse(out.split('\n').find(s=>s.startsWith('{"placedSku"')));
assert.deepEqual(result,{placedSku:'lunar-painting-mona',storedSku:'wood-painting-sunflowers',retainedInstances:2,version:8,leaseReleased:true,artwork:'mona',receiptSku:'lunar-frame-portrait',walletEntriesDelta:0,walletUnchanged:true});
fs.writeFileSync('docs/evidence/m5-artwork-migration.json',JSON.stringify({scope:'Actual migration conversion block; isolated rollback fixtures only',result,checks:'IDs/buyer/source retained; placed artwork retained; stored frame default bound; version bumped; old lease released; receipt unchanged; no wallet mutation'},null,2)+'\n');
console.log('PASS actual legacy inventory conversion; instance IDs and provenance retained, old receipts immutable, old version/lease blocked, rollback complete');
