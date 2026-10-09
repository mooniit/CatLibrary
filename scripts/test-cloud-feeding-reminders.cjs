// Isolated public-client checks. No original identity, wallet, family or cat is used.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {createHash, randomUUID} = require('node:crypto');
const {readConfig, validateConfig} = require('./cloud-config.cjs');
const config = readConfig('.tooling/cloud-phone-defines.json');
const {origin} = validateConfig(config, {remoteOnly: true});
assert.equal(origin, 'https://ludwvhsvknjgblfgouor.supabase.co');
const report = {at: new Date().toISOString(), result: 'FAIL',
  scope: 'One new anonymous hosted identity; no wallet initialization or family creation',
  originalIdentityTouched: false, phoneVerified: false, checks: []};
async function request(route, {token, body, method = 'POST'} = {}) {
  const response = await fetch(origin + route, {method, redirect: 'error',
    headers: {apikey: config.SUPABASE_ANON_KEY, 'Content-Type': 'application/json',
      ...(token ? {Authorization: 'Bearer ' + token} : {})},
    ...(body === undefined ? {} : {body: JSON.stringify(body)}),
    signal: AbortSignal.timeout(20000)});
  return {status: response.status, data: await response.json()};
}
function pass(name) { report.checks.push(name); console.log('PASS ' + name); }
async function run() {
  const signup = await request('/auth/v1/signup', {body: {}});
  assert.equal(signup.status, 200, 'Isolated signup failed');
  assert(signup.data.access_token && signup.data.refresh_token && signup.data.user?.id);
  const session = signup.data;
  fs.writeFileSync(path.join('.tooling', 'feeding-reminder-cloud-' + randomUUID() + '.json'),
    JSON.stringify(session), {flag: 'wx'});
  report.fixtureOwnerHash = createHash('sha256').update(session.user.id).digest('hex');
  const token = session.access_token;
  const reminder = await request('/rest/v1/rpc/get_feeding_reminder', {token, body: {}});
  assert.equal(reminder.status, 200);
  assert(['before_time', 'empty'].includes(reminder.data.status), 'Fresh identity must have no eligible cats');
  pass('zero-argument reminder API works without initializing any assets');
  const privateClock = await request('/rest/v1/rpc/feeding_reminder_at', {token, body: {as_of: '2099-10-09T13:00:00Z'}});
  assert([401, 403].includes(privateClock.status));
  assert.equal(privateClock.data.code, '42501');
  pass('authenticated client cannot inject the reminder clock');
  const day = new Date(Date.now() + 8 * 3600000).toISOString().slice(0, 10);
  const ack = await request('/rest/v1/rpc/ack_feeding_reminder', {token,
    body: {target_day: day, target_channel: 'in_app'}});
  assert.equal(ack.status, 200); assert.equal(ack.data.status, 'not_found');
  assert.equal(ack.data.owner_id, session.user.id);
  pass('acknowledgment cannot manufacture an absent reminder');
  const invalid = await request('/rest/v1/rpc/ack_feeding_reminder', {token,
    body: {target_day: day, target_channel: 'email'}});
  assert.equal(invalid.data.code, '22023'); assert.notEqual(invalid.status, 200);
  pass('unsupported channel is rejected');
  const forged = await request('/rest/v1/feeding_reminders', {token, body: {
    owner_id: session.user.id, family_id: randomUUID(), business_day: day,
    cats: [{id: randomUUID(), name: 'isolated-test'}], created_at: new Date().toISOString()}});
  assert.equal(forged.data.code, '42501'); assert.notEqual(forged.status, 200);
  pass('direct reminder insertion is forbidden');
  const anonymous = await request('/rest/v1/rpc/get_feeding_reminder', {body: {}});
  assert.equal(anonymous.data.code, '42501'); assert.notEqual(anonymous.status, 200);
  pass('anonymous public role cannot call the reminder API');
  const rows = await request('/rest/v1/feeding_reminders?select=business_day', {token, method: 'GET'});
  assert.equal(rows.status, 200); assert.deepEqual(rows.data, []);
  pass('fixture still has no reminder rows');
  report.result = 'PASS';
}
run().catch(() => { console.error('FAIL hosted reminder verification; credentials and responses omitted'); process.exitCode = 1; })
  .finally(() => fs.writeFileSync('docs/evidence/m7-feeding-reminders-cloud.json', JSON.stringify(report, null, 2) + '\n'));
