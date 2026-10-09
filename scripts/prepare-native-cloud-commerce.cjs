// New isolated identities with ordinary starting wallets and production SKUs.
// No grants, seed data, device sessions, settlement or administrator API keys.
const fs = require('node:fs'), path = require('node:path');
const assert = require('node:assert/strict');
const {createHash} = require('node:crypto');
const {readConfig, validateConfig} = require('./cloud-config.cjs');
const root = path.resolve(__dirname, '..');
const config = readConfig(path.join(root, '.tooling/cloud-phone-defines.json'));
validateConfig(config, {remoteOnly: true});
assert.equal(config.SUPABASE_URL, 'https://ludwvhsvknjgblfgouor.supabase.co');
const stamp = Date.now();
const fixtureFile = path.join(root, '.tooling', `cloud-native-commerce-${stamp}.json`);
const definesFile = `.tooling/native-cloud-commerce-defines-${stamp}.json`;
const fixture = {scope: 'isolated-native-production-commerce', users: []};
const report = {startedAt: new Date().toISOString(), result: 'FAIL',
  originalIdentityMigrated: false, administratorGrants: false, testProductsUsed: false};
const persist = () => fs.writeFileSync(fixtureFile, JSON.stringify(fixture, null, 2));
const hash = value => createHash('sha256').update(value).digest('hex');
async function request(route, user, body) {
  const response = await fetch(config.SUPABASE_URL + route, {method: 'POST', redirect: 'error',
    headers: {apikey: config.SUPABASE_ANON_KEY, 'Content-Type': 'application/json',
      ...(user ? {Authorization: 'Bearer ' + user.access_token} : {})},
    body: JSON.stringify(body), signal: AbortSignal.timeout(20000)});
  assert(response.ok, 'Independent fixture request failed');
  return response.json();
}
const rpc = (user, method, args = {}) => request('/rest/v1/rpc/' + method, user, args);
async function run() {
  persist();
  for (let i = 0; i < 2; i++) {
    const session = await request('/auth/v1/signup', null, {});
    assert(session.user.is_anonymous && session.refresh_token);
    fixture.users.push(session); persist();
    const wallet = await rpc(session, 'bootstrap_identity');
    assert.equal(wallet.owner_id, session.user.id);
    assert.equal(wallet.miao_coins, 30);
  }
  const [a, b] = fixture.users;
  assert.notEqual(a.user.id, b.user.id);
  const state = await rpc(a, 'create_family');
  fixture.familyId = state.family.id; persist();
  await rpc(b, 'request_family_join', {code: state.family.invite_code});
  const applications = (await rpc(a, 'family_state')).requests;
  assert.equal(applications.length, 1);
  await rpc(a, 'decide_family_join', {request_id: applications[0].id, approve: true});
  const room = await rpc(b, 'furniture_state');
  assert.equal(room.family_id, fixture.familyId);
  assert.equal(room.inventory.length, 0); assert.equal(room.version, 0);
  assert.equal(room.test_scope, false);
  for (const sku of ['wood-painting-mona', 'wood-painting-pearl']) {
    const product = room.products.find(p => p.sku === sku);
    assert(product.active && !product.is_test && product.price === 30 && product.purchase_limit === 1);
  }
  fs.writeFileSync(path.join(root, definesFile), JSON.stringify({...config,
    M7_A_REFRESH: a.refresh_token, M7_B_REFRESH: b.refresh_token,
    ISOLATED_HOSTED_COMMERCE: 'true'}), {flag: 'wx'});
  fs.writeFileSync(path.join(root, '.tooling/cloud-native-commerce-latest.json'), JSON.stringify({fixtureFile, definesFile}));
  Object.assign(report, {result: 'PASS', initialWallets: [30, 30], emptyInitialInventory: true,
    ownerHashes: fixture.users.map(u => hash(u.user.id)), familyHash: hash(fixture.familyId),
    productionCatalogCount: room.products.filter(p => p.active && !p.is_test).length,
    purchaseSkus: ['wood-painting-mona', 'wood-painting-pearl'], initialLayoutVersion: 0});
  console.log('PASS two independent hosted members; ordinary wallets and production catalog; no grants');
}
run().catch(() => { console.error('Independent hosted fixture preparation failed; private partial fixture retained'); process.exitCode = 1; })
  .finally(() => { report.finishedAt = new Date().toISOString();
    fs.writeFileSync(path.join(root, 'docs/evidence/m7-cloud-native-preparation.json'), JSON.stringify(report, null, 2) + '\n'); });
