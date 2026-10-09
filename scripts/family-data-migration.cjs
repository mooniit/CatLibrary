const assert = require('node:assert/strict');
const {jsonExpression} = require('./auth-migration.cjs');
// Dependency order keeps every foreign key enabled during the restore.
const tables = ['wallets', 'families', 'family_members', 'family_join_requests', 'cats',
  'repair_episodes', 'repair_windows', 'study_sessions', 'study_days', 'task_sessions', 'task_days',
  'weekly_task_offers', 'weekly_task_completions', 'daily_interest_charges', 'cat_feedings',
  'daily_cat_charges', 'proxy_payment_notices', 'family_daily_settlements', 'family_settlement_failures',
  'cat_trips', 'furniture_inventory', 'cat_travel_visits', 'travel_requests', 'travel_return_failures',
  'travel_return_seen', 'room_layouts', 'furniture_requests', 'wallet_entries'];
const ownerColumns = {wallets: 'owner_id', study_sessions: 'owner_id', study_days: 'owner_id',
  task_sessions: 'owner_id', task_days: 'owner_id', weekly_task_offers: 'owner_id', weekly_task_completions: 'owner_id',
  daily_interest_charges: 'owner_id', proxy_payment_notices: 'payer_id', travel_return_seen: 'user_id', wallet_entries: 'owner_id'};
const familyTables = new Set(['families', 'family_members', 'family_join_requests', 'cats', 'repair_episodes',
  'family_daily_settlements', 'family_settlement_failures', 'cat_trips', 'furniture_inventory', 'travel_return_failures', 'room_layouts']);
function selector(table, {family, owners}) {
  const owned = column => column + ' in (' + owners.map(o => "'" + o + "'").join(',') + ')';
  if (ownerColumns[table]) return owned(ownerColumns[table]);
  if (familyTables.has(table)) return (table === 'families' ? 'id' : 'family_id') + "='" + family + "'";
  if (table === 'cat_feedings' || table === 'daily_cat_charges' || table === 'cat_travel_visits') return "cat_id in (select id from public.cats where family_id='" + family + "')";
  if (table === 'repair_windows') return "episode_id in (select id from public.repair_episodes where family_id='" + family + "')";
  if (table === 'furniture_requests' || table === 'travel_requests') return owned('user_id');
  throw new Error('Unsupported migration table');
}
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
function validateFamilyScope(data) {
  const {family, owners, rows} = data;
  assert(uuidPattern.test(family)); assert(owners.length >= 1 && owners.length <= 2 && owners.every(o => uuidPattern.test(o)));
  assert.equal(new Set(owners).size, owners.length);
  assert.deepEqual(Object.keys(rows).sort(), [...tables].sort());
  for (const table of tables) assert(Array.isArray(rows[table]));
  assert.equal(rows.families.length, 1); assert.equal(rows.families[0].id, family);
  assert.deepEqual(new Set(rows.family_members.map(m => m.user_id)), new Set(owners));
  assert.deepEqual(new Set(rows.wallets.map(w => w.owner_id)), new Set(owners));
  const ownerSet = new Set(owners), cats = new Set(rows.cats.map(c => c.id)), trips = new Set(rows.cat_trips.map(t => t.id));
  const episodes = new Set(rows.repair_episodes.map(e => e.id)), inventory = new Set(rows.furniture_inventory.map(i => i.id));
  const offers = new Set(rows.weekly_task_offers.map(o => o.id));
  const referenceSets = {cat_id: cats, source_cat_id: cats, trip_id: trips, source_trip_id: trips,
    episode_id: episodes, inventory_id: inventory, offer_id: offers};
  const ownerFields = ['owner_id', 'user_id', 'creator_id', 'payer_id', 'arranged_by', 'purchased_by', 'edited_by', 'lock_user', 'applicant_id'];
  for (const table of tables) for (const row of rows[table]) {
    if (row.family_id != null) assert.equal(row.family_id, family, 'Foreign family row');
    for (const field of ownerFields) if (row[field] != null) assert(ownerSet.has(row[field]), 'Foreign owner reference');
    for (const [field, set] of Object.entries(referenceSets)) if (row[field] != null) assert(set.has(row[field]), 'Foreign dependency reference');
  }
  for (const room of rows.room_layouts) {
    assert.equal(room.layout.standard, 'room-standard-v1'); assert(Array.isArray(room.layout.items));
    assert(room.layout.items.every(i => inventory.has(i.instance_id)), 'Layout references unowned inventory');
  }
}
function normalizeRows(table, rows) {
  return rows.map(row => {
    const copy = {...row};
    if (table === 'wallet_entries') delete copy.id; // Only internal serial IDs are allocated by the target.
    if (table === 'room_layouts') Object.assign(copy, {lock_user: null, lock_token: null, lock_until: null});
    return copy;
  });
}
function exportSql(family, owners) {
  assert(uuidPattern.test(family) && owners.length > 0 && owners.every(o => uuidPattern.test(o)));
  const objects = tables.map(table => "'" + table + "',coalesce((select jsonb_agg(to_jsonb(r) order by to_jsonb(r)::text) from public." + table + ' r where ' + selector(table, {family, owners}) + "),'[]'::jsonb)");
  return "select jsonb_build_object(" + objects.join(',') + ')';
}
function buildFamilyImport(data, targetTriggers) {
  validateFamilyScope(data);
  const statements = [], verification = [];
  for (const table of tables) {
    const rows = normalizeRows(table, data.rows[table]);
    if (rows.length) {
      const columns = Object.keys(rows[0]);
      assert(columns.every(c => /^[a-z_]+$/.test(c)));
      for (const row of rows) assert.deepEqual(Object.keys(row).sort(), [...columns].sort());
      statements.push('insert into public.' + table + '(' + columns.join(',') + ') select ' + columns.map(c => 'r.' + c).join(',') + ' from jsonb_populate_recordset(null::public.' + table + ',' + jsonExpression(rows) + ') r;');
    }
    const target = 'select to_jsonb(t)' + (table === 'wallet_entries' ? "-'id'" : '') + ' as value from public.' + table + ' t where ' + selector(table, data);
    const expected = 'select value from jsonb_array_elements(' + jsonExpression(rows) + ')';
    verification.push("do $$ begin if exists((" + target + ' except all ' + expected + ') union all (' + expected + ' except all ' + target + ")) then raise exception 'Migration row mismatch: " + table + "'; end if; end $$;");
  }
  // Replay no historical adoption, billing or completion events; FK/CHECK constraints remain active.
  const knownTriggers = new Map(Object.entries({task_cross_overlap: 'task_sessions', study_cross_overlap: 'study_sessions',
    single_repair_after_settlement: 'family_daily_settlements', family_proxy_before_finish: 'family_daily_settlements',
    repair_completion_supersedes_later: 'repair_episodes', cat_adoption_repair_guard: 'cats', cat_feeding_repair_guard: 'cat_feedings'}));
  const disable = [], enable = [];
  assert.deepEqual(new Set(targetTriggers.map(t => t.name)), new Set(knownTriggers.keys()), 'Expected historical event triggers mismatch');
  for (const trigger of targetTriggers) {
    assert(knownTriggers.get(trigger.name) === trigger.table && trigger.enabled === 'O', 'Unexpected target trigger');
    disable.push('alter table public.' + trigger.table + ' disable trigger ' + trigger.name + ';');
    enable.push('alter table public.' + trigger.table + ' enable trigger ' + trigger.name + ';');
  }
  assert.equal(targetTriggers.length, knownTriggers.size, 'Expected historical event triggers missing');
  return {statements, verification, disable, enable,
    summary: Object.fromEntries(tables.map(t => [t, data.rows[t].length])),
    ledgerSerialIdsReallocated: true, editorLeasesReleased: true, foreignKeysEnabled: true};
}
module.exports = {tables, selector, validateFamilyScope, normalizeRows, exportSql, buildFamilyImport};
