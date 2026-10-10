// Independent hosted test identities; never reads or modifies a device session.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const {spawnSync} = require('node:child_process');
const {readConfig, validateConfig} = require('./cloud-config.cjs');
const root = path.resolve(__dirname, '..');
const config = readConfig(path.join(root, '.tooling/cloud-phone-defines.json'));
const endpoint = validateConfig(config, {remoteOnly: true});
assert.equal(new URL(config.SUPABASE_URL).hostname, 'ludwvhsvknjgblfgouor.supabase.co');
const fixtureFile = path.join(root, '.tooling', `cloud-workflow-fixture-${Date.now()}.json`);
const reportFile = path.join(root, 'docs/evidence', process.argv.includes('--warehouse') ? 'warehouse-cloud-workflow.json' : 'photo-wall-cloud-workflow.json');
const report = {startedAt: new Date().toISOString(), environment: 'hosted Supabase HTTPS',
  scope: 'three independent test identities, public client key; no original device account',
  projectRef: 'ludwvhsvknjgblfgouor', checks: [], originalIdentityMigrated: false,
  mobileInternetVerified: false};
function record(name) { report.checks.push(name); console.log('PASS ' + name); }
async function request(route, user, method = 'GET', body) {
  const response = await fetch(endpoint.origin + route, {method, redirect: 'error',
    headers: {apikey: config.SUPABASE_ANON_KEY,
      ...(user ? {Authorization: 'Bearer ' + user.access_token} : {}), 'Content-Type': 'application/json'},
    ...(body === undefined ? {} : {body: JSON.stringify(body)}), signal: AbortSignal.timeout(20000)});
  const text = await response.text();
  return {ok: response.ok, status: response.status, value: text ? JSON.parse(text) : null};
}
const call = (u, name, args = {}) => request('/rest/v1/rpc/' + name, u, 'POST', args);
async function rpc(u, name, args = {}) {
  const result = await call(u, name, args);
  assert(result.ok, 'RPC ' + name + ' HTTP ' + result.status);
  return result.value;
}
async function run() {
  assert(!fs.existsSync(fixtureFile), 'Existing isolated fixture must be reviewed before another run');
  const fixture = {scope: 'isolated-hosted-workflow', projectRef: report.projectRef, users: []};
  const persist = () => fs.writeFileSync(fixtureFile, JSON.stringify(fixture, null, 2));
  persist();
  fs.writeFileSync(path.join(root, '.tooling/cloud-workflow-latest.json'), JSON.stringify({fixtureFile}));
  for (let i = 0; i < 3; i++) {
    const response = await request('/auth/v1/signup', null, 'POST', {});
    assert(response.ok && response.value.access_token, 'Independent signup failed');
    fixture.users.push(response.value); persist();
  }
  const [a, b, c] = fixture.users;
  assert.equal(new Set(fixture.users.map(u => u.user.id)).size, 3);
  record('three distinct anonymous identities');
  const repeated = await Promise.all(Array.from({length: 12}, () => rpc(a, 'bootstrap_identity')));
  assert(repeated.every(w => w.owner_id === a.user.id && w.miao_coins === 30));
  await rpc(b, 'bootstrap_identity'); await rpc(c, 'bootstrap_identity');
  const initialLedger = await request('/rest/v1/wallet_entries?select=kind,miao_delta', a);
  assert.deepEqual(initialLedger.value, [{kind: 'initial', miao_delta: 30}]);
  record('12 concurrent bootstrap retries grant initial wallet once');
  const family = await rpc(a, 'create_family');
  fixture.familyId = family.family.id; persist();
  await rpc(b, 'request_family_join', {code: family.family.invite_code});
  const applications = (await rpc(a, 'family_state')).requests;
  assert.equal((await call(b, 'decide_family_join', {request_id: applications[0].id, approve: true})).status, 403);
  await rpc(a, 'decide_family_join', {request_id: applications[0].id, approve: true});
  await rpc(c, 'create_family');
  assert.equal((await rpc(b, 'family_state')).family.id, fixture.familyId);
  record('creator approval joins second member; self approval denied');
  let state = await rpc(a, 'furniture_state');
  assert.equal(state.inventory.length, 0);
  assert.equal(state.test_scope, false);
  assert.equal(state.lease_seconds, 120); assert.equal(state.renewal_seconds, 30);
  assert.equal(state.products.filter(p => p.active && !p.is_test).length, 32);
  record('production catalog and empty initial inventory');
  const insufficient = await rpc(a, 'purchase_furniture', {request_id: randomUUID(), product_sku: 'wood-chair', target_family: fixture.familyId});
  assert.equal(insufficient.reason, 'insufficient_balance');
  const unchanged = await rpc(a, 'furniture_state');
  assert.equal(unchanged.wallet.miao_coins, 30); assert.equal(unchanged.inventory.length, 0);
  record('insufficient balance leaves wallet and inventory unchanged');
  const buy = {request_id: randomUUID(), product_sku: 'painting-mona', target_family: fixture.familyId};
  const receipts = await Promise.all(Array.from({length: 12}, () => rpc(a, 'purchase_furniture', buy)));
  assert(receipts.every(r => r.status === 'purchased' && r.instance_id === receipts[0].instance_id));
  state = await rpc(a, 'furniture_state');
  assert.equal(state.wallet.miao_coins, 0); assert.equal(state.inventory.length, 1);
  assert.equal(state.inventory[0].purchased_by, a.user.id);
  assert.equal((await rpc(a, 'furniture_request', {target_request: buy.request_id})).instance_id, receipts[0].instance_id);
  record('12 purchase retries debit once, deliver once, recover receipt and retain purchaser');
  assert.equal((await call(b, 'purchase_furniture', buy)).status, 403);
  assert.equal((await call(a, 'purchase_furniture', {...buy, quantity: 2})).status, 400);
  assert.equal((await rpc(b, 'purchase_furniture', {...buy, request_id: randomUUID()})).reason, 'purchase_limit');
  assert.equal((await rpc(b, 'furniture_state')).wallet.miao_coins, 30);
  record('cross user replay, changed payload and household 1/1 repurchase denied');
  const outsideBuy = await rpc(c, 'purchase_furniture', {...buy, request_id: randomUUID()});
  assert.equal(outsideBuy.reason, 'family_changed');
  assert.equal((await request('/rest/v1/wallets?owner_id=eq.' + a.user.id, a, 'PATCH', {miao_coins: 999})).status, 403);
  assert.equal((await request('/rest/v1/furniture_inventory?select=*', c)).status, 403);
  assert.deepEqual((await rpc(c, 'furniture_state')).inventory, []);
  assert.equal((await call(a, 'purchase_furniture', {...buy, request_id: randomUUID(), price: 0})).status, 404);
  record('outsider family, direct wallet write, inventory read and client price spoof rejected');
  const second = await rpc(b, 'purchase_furniture', {request_id: randomUUID(), product_sku: 'painting-starry', target_family: fixture.familyId});
  assert.equal(second.status, 'purchased');
  assert.equal((await rpc(a, 'furniture_state')).inventory.length, 2);
  record('second member personal payment supplies shared inventory');
  const tokens = [randomUUID(), randomUUID()];
  const leases = await Promise.all([a, b].map((u, i) => rpc(u, 'room_editor', {action: 'acquire', editor_token: tokens[i]})));
  assert.equal(leases.filter(l => l.status === 'acquired').length, 1);
  const winIndex = leases[0].status === 'acquired' ? 0 : 1;
  const winner = [a, b][winIndex], other = [a, b][1 - winIndex], token = tokens[winIndex];
  assert.equal((await rpc(other, 'family_state')).members.length, 2);
  assert.equal((await rpc(other, 'furniture_state')).inventory.length, 2);
  record('simultaneous editor acquisition admits one; other member retains normal read access');
  const item = {instance_id: receipts[0].instance_id, gx: 0, gy: 0, facing: 'x', slot: 'art-left-back', artwork: 'mona'};
  const layout = items => ({standard: 'room-standard-v1', items});
  async function rejectSave(items, reason) {
    const result = await rpc(winner, 'save_room_layout', {request_id: randomUUID(), editor_token: token, expected_version: 0, proposed: layout(items)});
    assert.equal(result.reason, reason); assert.equal((await rpc(winner, 'furniture_state')).version, 0);
  }
  await rejectSave([{...item, instance_id: randomUUID()}], 'inventory_missing');
  await rejectSave([item, item], 'duplicate_instance');
  await rejectSave([{...item, gx: 1}], 'fixed_position');
  await rejectSave([{...item, artwork: 'starry'}], 'artwork_mismatch');
  record('missing inventory, duplicated instance, free art movement and unbound artwork rejected');
  const save = {request_id: randomUUID(), editor_token: token, expected_version: 0, proposed: layout([item])};
  await rpc(winner, 'save_room_layout', save); // Discard success to model a lost receipt.
  assert.equal((await rpc(winner, 'furniture_request', {target_request: save.request_id})).version, 1);
  await rpc(winner, 'room_editor', {action: 'release', editor_token: token});
  const nextToken = randomUUID();
  await rpc(other, 'room_editor', {action: 'acquire', editor_token: nextToken});
  const stale = await rpc(other, 'save_room_layout', {request_id: randomUUID(), editor_token: nextToken, expected_version: 0, proposed: layout([])});
  assert.equal(stale.reason, 'version_conflict');
  const saved = await rpc(other, 'save_room_layout', {request_id: randomUUID(), editor_token: nextToken, expected_version: 1, proposed: layout([])});
  assert.equal(saved.version, 2);
  assert.equal((await rpc(winner, 'save_room_layout', save)).version, 1);
  state = await rpc(winner, 'furniture_state');
  assert.equal(state.version, 2); assert.deepEqual(state.layout.items, []); assert.equal(state.inventory.length, 2);
  record('lost receipt recovered; stale version denied; old successful retry cannot overwrite newer save');
  const ledger = await request('/rest/v1/wallet_entries?select=kind,miao_delta', a);
  assert.equal(ledger.value.filter(e => e.kind === 'furniture').length, 1);
  assert.equal((await call(null, 'furniture_state')).status, 401);
  record('one purchase ledger debit and unauthenticated state access denied');
  const renewed = await rpc(other, 'room_editor', {action: 'renew', editor_token: nextToken});
  assert.equal(renewed.status, 'acquired');
  console.log('Waiting for real 120-second cloud lease expiry');
  // Lease authority is the server clock; the workstation clock may differ.
  const remaining = Date.parse(renewed.lock_until) - Date.parse(renewed.server_time);
  assert(Number.isFinite(remaining) && remaining > 115000 && remaining <= 120000, 'Invalid lease duration');
  const deadline = performance.now() + remaining + 2000;
  while (performance.now() <= deadline) await new Promise(resolve => setTimeout(resolve, Math.min(15000, deadline + 100 - performance.now())));
  assert.equal((await rpc(other, 'room_editor', {action: 'renew', editor_token: nextToken})).reason, 'lease_expired');
  assert.equal((await rpc(other, 'save_room_layout', {request_id: randomUUID(), editor_token: nextToken, expected_version: 2, proposed: layout([item])})).reason, 'lease_expired');
  assert.equal((await rpc(winner, 'furniture_state')).version, 2);
  record('real lease expiry blocks renewal and save without changing version');
  // Only the fresh isolated fixture receives test rights; never the original owner.
  const originalPointer=JSON.parse(fs.readFileSync(path.join(root,'.tooling/account-cloud-migration-latest.json')));
  const original=JSON.parse(fs.readFileSync(path.join(originalPointer.directory,'source.json')));
  assert(fixture.users.every(u=>!original.owners.includes(u.user.id)));
  const grantFile=path.join(root,'.tooling',`photo-wall-fixture-grant-${Date.now()}.sql`);
  assert(/^[0-9a-f-]{36}$/.test(a.user.id));
  const studyRun=randomUUID();
  const studySql=[a,a,b].map((u,i)=>
    `insert into public.study_sessions(id,owner_id,run_id,started_at,recorded_until,confirmed) values('${randomUUID()}','${u.user.id}','${studyRun}','2026-10-01 ${i===1?'16:10':'15:55'}Z','2026-10-01 ${i===1?'16:20':'16:05'}Z',${i!==1});`).join('\n');
  fs.writeFileSync(grantFile,`begin; select public.grant_test_collection('${randomUUID()}','${a.user.id}'); ${studySql} commit;`,{flag:'wx'});
  const cli=path.join(root,'.tooling/supabase-cli/node_modules/@supabase/cli-windows-x64/bin/supabase.exe');
  const granted=spawnSync(cli,['db','query','--linked','--file',grantFile,'--output','json'],{encoding:'utf8',timeout:120000});
  fs.writeFileSync(grantFile+'.private.json',granted.stdout||'');
  assert.equal(granted.status,0,'Isolated photo fixture grant failed');
  const photo=(await rpc(a,'family_album')).photos.find(p=>p.source==='test_grant');
  assert(photo);
  const beforePhoto=await rpc(a,'furniture_state');
  const photoArgs={photo_id:photo.id,photo_source:'test_grant'};
  const photoReceipts=await Promise.all(Array.from({length:8},()=>rpc(a,'prepare_photo_placement',photoArgs)));
  assert(photoReceipts.every(r=>r.status==='ready'&&r.inventory_id===photoReceipts[0].inventory_id));
  const framed=await rpc(a,'furniture_state');
  assert.equal(beforePhoto.inventory.filter(i=>i.source==='photo').length,12);
  assert.equal(framed.inventory.length,beforePhoto.inventory.length);
  assert.deepEqual(framed.wallet,beforePhoto.wallet);
  assert.equal(framed.version,beforePhoto.version);
  assert.equal((await call(b,'prepare_photo_placement',photoArgs)).status,403);
  assert.equal((await call(c,'prepare_photo_placement',photoArgs)).status,403);
  record('all twelve unlocked photos automatically enter warehouse; eight retries mint nothing; no fee or autosave; personal rights protected');
  const photoItem={instance_id:photoReceipts[0].inventory_id,gx:0,gy:0,facing:'x',slot:'art-right-front',artwork:framed.products.find(p=>p.sku===framed.inventory.find(i=>i.id===photoReceipts[0].inventory_id).sku).geometry.artwork};
  const photoToken=randomUUID();
  assert.equal((await rpc(a,'room_editor',{action:'acquire',editor_token:photoToken})).status,'acquired');
  const photoSave={request_id:randomUUID(),editor_token:photoToken,expected_version:framed.version,proposed:layout([photoItem])};
  assert.equal((await rpc(a,'save_room_layout',photoSave)).status,'saved');
  assert.equal((await rpc(a,'furniture_request',{target_request:photoSave.request_id})).version,framed.version+1);
  assert.equal((await rpc(b,'furniture_state')).version,framed.version+1);
  assert.deepEqual((await rpc(b,'furniture_state')).layout,photoSave.proposed);
  await rpc(a,'room_editor',{action:'release',editor_token:photoToken});
  record('photo manually saved; second member sees version update and refreshes identical mounted artwork');
  const beforeHistory=await rpc(a,'furniture_state');
  const ownHistory=await rpc(a,'study_history'), otherHistory=await rpc(b,'study_history');
  assert.equal(ownHistory.length,2); assert.equal(otherHistory.length,1);
  assert(ownHistory.every(s=>s.owner_id===a.user.id&&s.run_id===studyRun&&s.activity==='study'));
  assert(otherHistory.every(s=>s.owner_id===b.user.id));
  assert.equal(ownHistory.filter(s=>s.confirmed).length,1);
  assert.deepEqual((await rpc(a,'furniture_state')).wallet,beforeHistory.wallet);
  assert.equal((await call(null,'study_history')).status,401);
  assert.equal((await call(a,'issue_photo_inventory',{visit:randomUUID(),unlocked:randomUUID()})).status,403);
  record('study history retains paused and interrupted evidence; other member hidden; anonymous and direct inventory mint denied; wallet unchanged');
  report.fixturePreservedForNativeVerification = true;
  report.createdTestIdentities = 3;
  report.result = 'PASS';
}
run().catch(error => {
  report.result = 'FAIL';
  // HTTP payloads, identity IDs, refresh tokens and headers never enter evidence.
  report.failure = error instanceof assert.AssertionError ? 'Assertion failed in hosted workflow' : 'Hosted request failed';
  report.failureLocation = error.stack?.split('\n').find(line => line.includes('test-cloud-workflow.cjs:'))?.trim();
  console.error(report.failure); process.exitCode = 1;
}).finally(() => {
  report.finishedAt = new Date().toISOString();
  fs.writeFileSync(reportFile, JSON.stringify(report, null, 2) + '\n');
});
