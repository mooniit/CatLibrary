// Hosted private-photo checks on the independent workflow fixture only.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const {readConfig, validateConfig} = require('./cloud-config.cjs');
const root = path.resolve(__dirname, '..');
const config = readConfig(path.join(root, '.tooling/cloud-phone-defines.json'));
const endpoint = validateConfig(config, {remoteOnly: true});
const pointer = JSON.parse(fs.readFileSync(path.join(root, '.tooling/cloud-workflow-latest.json')));
const fixturePath = path.resolve(pointer.fixtureFile);
assert.equal(path.dirname(fixturePath), path.join(root, '.tooling'));
assert.match(path.basename(fixturePath), /^cloud-workflow-fixture-\d+\.json$/);
const fixture = JSON.parse(fs.readFileSync(fixturePath));
assert.equal(fixture.scope, 'isolated-hosted-workflow');
assert.equal(fixture.projectRef + '.supabase.co', new URL(endpoint.origin).hostname);
const [a, b, c] = fixture.users;
const report = {startedAt: new Date().toISOString(), environment: 'hosted Supabase HTTPS',
  scope: 'synthetic zero-duration task and PNG on independent fixture; no original account or reward',
  checks: [], originalIdentityMigrated: false, mobileInternetVerified: false};
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', 'base64');
async function request(route, user, method = 'GET', body, mime = 'application/json') {
  const response = await fetch(endpoint.origin + route, {method, redirect: 'error',
    headers: {apikey: config.SUPABASE_ANON_KEY, ...(user ? {Authorization: 'Bearer ' + user.access_token} : {}), 'Content-Type': mime},
    ...(body === undefined ? {} : {body: mime === 'application/json' ? JSON.stringify(body) : body}), signal: AbortSignal.timeout(20000)});
  return response;
}
async function rpc(user, name, args = {}) {
  const response = await request('/rest/v1/rpc/' + name, user, 'POST', args);
  assert(response.ok, 'RPC ' + name + ' HTTP ' + response.status);
  return response.json();
}
function pass(name) { report.checks.push(name); console.log('PASS ' + name); }
async function run() {
  const before = await rpc(a, 'furniture_state');
  const sessionId = randomUUID(), photo = a.user.id + '/' + sessionId;
  const args = {session_id: sessionId, task_activity: 'language', start_at: before.server_time,
    checkpoint_at: before.server_time, task_photo_path: null, is_confirmed: false};
  await rpc(a, 'sync_task_session', args);
  const confirm = {...args, task_photo_path: photo, is_confirmed: true};
  assert(!(await request('/rest/v1/rpc/sync_task_session', a, 'POST', confirm)).ok);
  pass('missing photo cannot confirm task');
  const uploadRoute = '/storage/v1/object/task-photos/' + photo;
  assert(!(await request(uploadRoute, c, 'POST', png, 'image/png')).ok);
  assert((await request(uploadRoute, a, 'POST', png, 'image/png')).ok);
  const download = '/storage/v1/object/authenticated/task-photos/' + photo;
  const own = await request(download, a);
  assert(own.ok); assert.deepEqual(Buffer.from(await own.arrayBuffer()), png);
  pass('only owner uploads matching task object and reads exact PNG');
  assert(!(await request(download, b)).ok);
  pass('household member cannot read unconfirmed task photo');
  await rpc(a, 'sync_task_session', confirm);
  const shared = await request(download, b);
  assert(shared.ok); assert.deepEqual(Buffer.from(await shared.arrayBuffer()), png);
  pass('confirmed task photo readable by second household member');
  assert(!(await request(download, c)).ok);
  assert(!(await request('/storage/v1/object/public/task-photos/' + photo, null)).ok);
  pass('outsider and public URL cannot download private task photo');
  assert(!(await request(uploadRoute, a, 'POST', png, 'image/png')).ok);
  pass('confirmed photo cannot be overwritten');
  assert.deepEqual((await rpc(a, 'furniture_state')).wallet, before.wallet);
  pass('zero-duration privacy verification leaves wallet unchanged');
  report.result = 'PASS';
}
run().catch(error => {
  report.result = 'FAIL';
  report.failure = error instanceof assert.AssertionError ? 'Assertion failed in hosted photo workflow' : 'Hosted photo request failed';
  report.failureLocation = error.stack?.split('\n').find(line => line.includes('test-cloud-task-photo.cjs:'))?.trim();
  console.error(report.failure); process.exitCode = 1;
}).finally(() => {
  report.finishedAt = new Date().toISOString();
  fs.writeFileSync(path.join(root, 'docs/evidence/m7-cloud-task-photo.json'), JSON.stringify(report, null, 2) + '\n');
});
