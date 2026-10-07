// Explicit user-authorized grant to the already verified physical-phone account.
// No public RPC, no credential export, no account creation, no global entitlement.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const {execFileSync} = require('node:child_process');
const {DatabaseSync} = require('node:sqlite');
const config = JSON.parse(fs.readFileSync('.tooling/local-phone-defines.json', 'utf8').replace(/^\uFEFF/, ''));
assert.equal(config.SUPABASE_URL, 'http://127.0.0.1:54321');
const record = JSON.parse(fs.readFileSync('docs/evidence/m6-v2-phone-install.json'));
assert.equal(record.model, 'PJE110');
assert.equal(record.postStartup.ownersPreserved, true);
const db = new DatabaseSync('.tooling/m6-v2-phone-after-start.sqlite', {readOnly: true});
const accounts = db.prepare('select owner_id from account_cache').all();
db.close();
assert.equal(accounts.length, 1, 'Ambiguous identity; refuse grant');
const owner = accounts[0].owner_id;
assert.match(owner, /^[a-f0-9-]{36}$/);
const ownerHash = createHash('sha256').update(owner).digest('hex');
assert.deepEqual(record.before.owners, [ownerHash], 'Must match the preserved phone identity');
const sql = q => execFileSync('docker', ['exec', 'supabase_db_CatLibrary', 'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-Atc', q], {encoding: 'utf8'}).trim();
const state = () => JSON.parse(sql(`select json_build_object(
  'wallet',(select row_to_json(w) from (select miao_coins,eagle_pounds,gems from public.wallets where owner_id='${owner}')w),
  'layout',(select row_to_json(l) from (select r.version,r.layout from public.room_layouts r join public.family_members m using(family_id) where m.user_id='${owner}')l),
  'owned',(select count(*) from public.furniture_inventory i join public.family_members m using(family_id) join public.furniture_products p using(sku) where m.user_id='${owner}' and p.theme='lunar' and p.active and not p.is_test))`));
const before = state();
assert(before.wallet, 'Verified identity absent from server; do not replace it');
sql(`begin;
  do $$ declare home uuid; begin
    select family_id into strict home from public.family_members where user_id='${owner}' for update;
    perform 1 from public.families where id=home for update;
    if (select count(*) from public.furniture_products where theme='lunar' and active and not is_test)<>14 then
      raise exception 'Expected exactly 14 approved lunar products';
    end if;
    insert into public.furniture_inventory(family_id,sku,source,source_id)
      select home,p.sku,'test_grant','79000000-0000-0000-0000-000000000007'
      from public.furniture_products p where p.theme='lunar' and p.active and not p.is_test
      and not exists(select 1 from public.furniture_inventory i where i.family_id=home and i.sku=p.sku);
  end $$;
commit;`);
const after = state();
assert.deepEqual(after.wallet, before.wallet, 'Do not change wallet');
assert.deepEqual(after.layout, before.layout, 'Do not change saved layout or version');
assert.equal(after.owned, 14);
fs.writeFileSync('docs/evidence/m7-lunar-account-grant.json', JSON.stringify({at: new Date().toISOString(),scope: 'Explicitly authorized original PJE110 account, local Supabase; no remote grant claimed',ownerHash,previouslyOwned: before.owned,owned: after.owned,walletUnchanged: true,layoutUnchanged: true,source: 'test_grant',sourceId: '79000000-0000-0000-0000-000000000007',globalInitialGrant: false,deviceRefreshVerified: false}, null, 2) + '\n');
console.log(`PASS original account owns 14 lunar products (${14-before.owned} added); wallet/layout unchanged; no duplicate on retry`);
