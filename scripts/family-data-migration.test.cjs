const {test} = require('node:test');
const assert = require('node:assert/strict');
const {tables, validateFamilyScope, normalizeRows, exportSql, buildFamilyImport} = require('./family-data-migration.cjs');
const owner = '10000000-0000-0000-0000-000000000001', family = '20000000-0000-0000-0000-000000000001';
const fixture = () => ({family, owners: [owner], rows: {...Object.fromEntries(tables.map(t => [t, []])),
  wallets: [{owner_id: owner, miao_coins: 7}], families: [{id: family, creator_id: owner}], family_members: [{user_id: owner, family_id: family}]}});
test('Family snapshot scope rejects foreign family and owners before generating SQL', () => {
  validateFamilyScope(fixture());
  for (const mutate of [d => d.rows.cats.push({id: family, family_id: owner, owner_id: owner}), d => d.rows.wallets[0].owner_id = family,
    d => d.rows.family_join_requests.push({family_id: family, applicant_id: family}), d => d.rows.unrecognized_table = []]) {
    const data = fixture(); mutate(data); assert.throws(() => validateFamilyScope(data));
  }
});
test('Inventory and saved room cannot refer to missing cats, trips or instances', () => {
  const data = fixture(); data.rows.furniture_inventory.push({id: family, family_id: family, source_cat_id: owner});
  assert.throws(() => validateFamilyScope(data));
  data.rows.furniture_inventory = []; data.rows.room_layouts.push({family_id: family, layout: {standard: 'room-standard-v1', items: [{instance_id: owner}]}});
  assert.throws(() => validateFamilyScope(data));
});
test('Transfer preserves economic values and UUID instances; only serial ledger IDs and edit leases change', () => {
  const ledger = {id: 99, miao_delta: -17, operation_id: owner};
  assert.deepEqual(normalizeRows('wallet_entries', [ledger]), [{miao_delta: -17, operation_id: owner}]);
  assert.deepEqual(normalizeRows('furniture_inventory', [{id: owner}]), [{id: owner}]);
  const room = {version: 9, layout: {items: []}, lock_user: owner, lock_token: family, lock_until: 'future'};
  assert.deepEqual(normalizeRows('room_layouts', [room])[0], {...room, lock_user: null, lock_token: null, lock_until: null});
  assert.equal(ledger.id, 99); assert.equal(room.lock_user, owner);
});
test('Export contains all business dependencies but no global policies, catalog, test grants or sample data', () => {
  const sql = exportSql(family, [owner]);
  for (const t of tables) assert(sql.includes('public.' + t + ' '));
  for (const t of ['room_test_families', 'billing_activation', 'furniture_products', 'm0_probe_notes']) assert(!sql.includes('public.' + t + ' '));
  assert.throws(() => exportSql("';delete from auth.users;--", [owner]));
});
test('Unexpected or disabled target event triggers block import; no blanket trigger or constraint disabling', () => {
  const triggers = Object.entries({task_cross_overlap: 'task_sessions', study_cross_overlap: 'study_sessions',
    single_repair_after_settlement: 'family_daily_settlements', family_proxy_before_finish: 'family_daily_settlements',
    repair_completion_supersedes_later: 'repair_episodes', cat_adoption_repair_guard: 'cats', cat_feeding_repair_guard: 'cat_feedings'})
    .map(([name, table]) => ({name, table, enabled: 'O'}));
  const plan = buildFamilyImport(fixture(), triggers);
  assert(plan.foreignKeysEnabled); assert.equal(plan.disable.length, 7); assert.equal(plan.enable.length, 7);
  assert(!plan.disable.some(s => /all|replication_role/i.test(s)));
  assert(plan.verification.some(s => s.includes('Migration row mismatch: wallets')));
  assert.throws(() => buildFamilyImport(fixture(), [...triggers, {name: 'unknown', table: 'cats', enabled: 'O'}]));
  assert.throws(() => buildFamilyImport(fixture(), triggers.slice(1)));
  assert.throws(() => buildFamilyImport(fixture(), [triggers[1], ...triggers.slice(1)]));
  assert.throws(() => buildFamilyImport(fixture(), triggers.map((t, i) => i ? t : {...t, table: 'cats'})));
});
