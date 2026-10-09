const {test} = require('node:test');
const assert = require('node:assert/strict');
const {validateAuthScope, buildAuthImport, jsonExpression} = require('./auth-migration.cjs');
const owner = '10000000-0000-0000-0000-000000000001';
const session = '20000000-0000-0000-0000-000000000001';
const other = '10000000-0000-0000-0000-000000000002';
const fixture = () => ({users: [{id: owner, role: 'authenticated', is_anonymous: true, confirmed_at: '2026-01-01'}],
  identities: [], sessions: [{id: session, user_id: owner}],
  refresh_tokens: [{id: 999, token: 'fixture-token-only', user_id: owner, session_id: session, revoked: false}]});
const schema = Object.entries(fixture()).flatMap(([table_name, rows]) => Object.keys(rows[0] || {}).map(column_name => ({table_name, column_name,
  is_generated: column_name === 'confirmed_at' ? 'ALWAYS' : 'NEVER', is_nullable: 'YES', column_default: null})));
test('Auth scope accepts the expected anonymous owner and rejects foreign users, sessions and tokens', () => {
  validateAuthScope(fixture(), [owner]);
  for (const mutate of [d => d.users.push({...d.users[0], id: other}), d => d.sessions[0].user_id = other, d => d.refresh_tokens[0].user_id = other,
    d => d.refresh_tokens[0].session_id = other, d => d.refresh_tokens[0].revoked = true]) {
    const d = fixture(); mutate(d); assert.throws(() => validateAuthScope(d, [owner]));
  }
});
test('Privileged, linked, deleted and MFA/OAuth identities cannot use the anonymous migration path', () => {
  for (const mutate of [d => d.users[0].is_super_admin = true, d => d.users[0].is_anonymous = false, d => d.users[0].deleted_at = '2026-01-01',
    d => d.identities.push({user_id: owner}), d => d.sessions[0].factor_id = other, d => d.sessions[0].oauth_client_id = other]) {
    const d = fixture(); mutate(d); assert.throws(() => validateAuthScope(d, [owner]));
  }
});
test('Import preserves session keys, drops generated values and reallocates refresh serial IDs', () => {
  const result = buildAuthImport(fixture(), [owner], schema);
  assert(!result.statements[0].split(' select ')[0].includes('confirmed_at'));
  assert(!result.statements[2].split(' select ')[0].includes('"id"'));
  assert(result.statements[1].split(' select ')[0].includes('"id"'));
  assert(result.collisionGuard.includes('Migration target already contains'));
  assert(result.summary.refreshSerialIdsReallocated);
});
test('Schema mismatch cannot silently discard data or invent required values', () => {
  const d = fixture(); d.sessions[0].unknown_critical_key = 'preserve me';
  assert.throws(() => buildAuthImport(d, [owner], schema));
  assert.throws(() => buildAuthImport(fixture(), [owner], [...schema, {table_name: 'users', column_name: 'required_field', is_nullable: 'NO', is_generated: 'NEVER', column_default: null}]));
});
test('JSON SQL encoding preserves quotes, backslashes and dollar delimiters without executable interpolation', () => {
  const data = {note: "' ; rollback; -- $$ \\ new\nline"};
  const expression = jsonExpression(data);
  assert(!expression.includes('rollback'));
  const encoded = expression.match(/decode\('([a-f0-9]+)'/)[1];
  assert.deepEqual(JSON.parse(Buffer.from(encoded, 'hex').toString()), data);
});
