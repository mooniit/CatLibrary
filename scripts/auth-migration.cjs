// Scoped Auth data import; executable SQL and backups contain private sessions.
const assert = require('node:assert/strict');
const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(value);
const identifier = name => { assert.match(name, /^[a-z_]+$/); return '"' + name + '"'; };
const jsonExpression = value => "convert_from(decode('" + Buffer.from(JSON.stringify(value)).toString('hex') + "','hex'),'UTF8')::jsonb";
const authSchemaSql = "begin read only; select table_name,column_name,data_type,is_nullable,is_generated,column_default from information_schema.columns where table_schema='auth' and table_name in ('users','identities','sessions','refresh_tokens') order by table_name,ordinal_position; commit;";
function validateAuthScope(data, expectedOwners) {
  assert(Array.isArray(expectedOwners) && expectedOwners.length >= 1 && expectedOwners.length <= 2);
  assert(expectedOwners.every(uuid) && new Set(expectedOwners).size === expectedOwners.length);
  for (const table of ['users', 'identities', 'sessions', 'refresh_tokens']) assert(Array.isArray(data[table]));
  const owners = new Set(expectedOwners);
  assert.equal(data.users.length, owners.size, 'Auth user count mismatch');
  assert.deepEqual(new Set(data.users.map(u => u.id)), owners, 'Auth owner mismatch');
  assert(data.users.every(u => u.is_anonymous === true && u.role === 'authenticated' && !u.is_super_admin && !u.deleted_at), 'Only active anonymous users are supported');
  assert.equal(data.identities.length, 0, 'Linked identities require a separate migration plan');
  const sessions = new Map();
  for (const session of data.sessions) {
    assert(uuid(session.id) && owners.has(session.user_id), 'Session scope mismatch');
    assert(!sessions.has(session.id), 'Duplicate session'); sessions.set(session.id, session.user_id);
    assert(!session.factor_id && !session.oauth_client_id, 'MFA/OAuth sessions require additional dependencies');
  }
  for (const token of data.refresh_tokens) {
    assert(owners.has(token.user_id) && sessions.get(token.session_id) === token.user_id, 'Refresh token scope mismatch');
    assert(typeof token.token === 'string' && token.token.length > 0, 'Missing refresh token');
  }
  for (const owner of owners) assert(data.refresh_tokens.some(t => t.user_id === owner && t.revoked === false), 'No active refresh token');
}
function buildAuthImport(data, expectedOwners, targetSchema) {
  validateAuthScope(data, expectedOwners);
  const statements = [];
  for (const table of ['users', 'sessions', 'refresh_tokens']) {
    const rows = data[table];
    if (!rows.length) continue;
    const schema = targetSchema.filter(c => c.table_name === table);
    assert(schema.length > 0, 'Target Auth table schema missing');
    const generated = new Set(schema.filter(c => c.is_generated !== 'NEVER').map(c => c.column_name));
    const available = new Set(schema.map(c => c.column_name));
    for (const row of rows) for (const [key, value] of Object.entries(row)) {
      assert(available.has(key) || value === null, 'Non-null source column missing from target');
    }
    const columns = schema.filter(c => !generated.has(c.column_name) && !(table === 'refresh_tokens' && c.column_name === 'id') && rows.some(r => Object.hasOwn(r, c.column_name))).map(c => c.column_name);
    for (const col of schema) if (col.is_nullable === 'NO' && !col.column_default && !generated.has(col.column_name)) {
      assert(columns.includes(col.column_name), 'Required target column missing');
    }
    const names = columns.map(identifier).join(',');
    statements.push('insert into auth.' + identifier(table) + '(' + names + ') select ' + columns.map(c => 'r.' + identifier(c)).join(',') + ' from jsonb_populate_recordset(null::auth.' + identifier(table) + ',' + jsonExpression(rows) + ') r;');
  }
  const owners = expectedOwners.map(id => "'" + id + "'::uuid").join(',');
  const sessionIds = data.sessions.map(s => "'" + s.id + "'::uuid").join(',');
  const collisionGuard = "do $$ begin if exists(select 1 from auth.users where id in (" + owners + "))" +
    (sessionIds ? ' or exists(select 1 from auth.sessions where id in (' + sessionIds + '))' : '') +
    " then raise exception 'Migration target already contains scoped identity/session'; end if; end $$;";
  return {statements, collisionGuard, summary: {users: data.users.length, sessions: data.sessions.length,
    refreshTokens: data.refresh_tokens.length, generatedColumnsExcluded: true, refreshSerialIdsReallocated: true}};
}
module.exports = {validateAuthScope, buildAuthImport, jsonExpression, authSchemaSql};
