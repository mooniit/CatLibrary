// Dedicated anonymous fixtures; never touches the retained original account.
const fs = require('node:fs'), path = require('node:path');
const {randomUUID} = require('node:crypto');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const configPath = process.argv[2] || '.tooling/local-phone-defines.json';
const config = JSON.parse(fs.readFileSync(path.join(root, configPath), 'utf8').replace(/^\uFEFF/, ''));
const report = {environment: new URL(config.SUPABASE_URL).hostname, checks: [], result: 'FAIL'};
async function post(route, token, body) {
  const response = await fetch(config.SUPABASE_URL + route, {method: 'POST',
    headers: {apikey: config.SUPABASE_ANON_KEY, 'Content-Type': 'application/json',
      ...(token ? {Authorization: `Bearer ${token}`} : {})}, body: JSON.stringify(body),
    signal: AbortSignal.timeout(20000)});
  return {ok: response.ok, value: await response.json()};
}
const rpc = (token, body) => post('/rest/v1/rpc/sync_timed_task_session', token, body);
(async () => {
  const users = [];
  for (let i = 0; i < 2; i++) {
    const auth = await post('/auth/v1/signup', null, {});
    assert(auth.ok && auth.value.access_token, 'isolated signup failed');
    users.push(auth.value.access_token);
    assert((await post('/rest/v1/rpc/bootstrap_identity', users[i], {})).ok);
  }
  const today = new Date(Date.now() + 8 * 3600000).toISOString().slice(0, 10);
  const start = new Date(`${today}T00:00:00+08:00`);
  assert(Date.now() - start > 2 * 3600000, 'run after 02:00 UTC+8 to avoid future evidence');
  const run = randomUUID();
  const params = {session_id: randomUUID(), task_activity: 'language',
    timer_run_id: run, run_start_at: start.toISOString(), start_at: start.toISOString(),
    checkpoint_at: new Date(+start + 6 * 60000).toISOString(), is_confirmed: false, is_running: false};
  let result = await rpc(users[0], params);
  assert(result.ok); assert.equal(result.value.wallet.eagle_pounds, 0);
  result = await rpc(users[0], {...params, is_confirmed: true});
  assert(result.ok); assert.equal(result.value.wallet.eagle_pounds, 0);
  const second = {...params, session_id: randomUUID(),
    start_at: new Date(+start + 26 * 60000).toISOString(),
    checkpoint_at: new Date(+start + 31 * 60000).toISOString(), is_confirmed: true};
  result = await rpc(users[0], second);
  assert(result.ok); assert.equal(result.value.wallet.eagle_pounds, 2);
  report.checks.push('6 + 5 effective minutes earn 2; 20 paused minutes excluded; no photo');
  const retries = await Promise.all(Array.from({length: 4}, () => rpc(users[0], second)));
  for (const retry of retries) {assert(retry.ok); assert.equal(retry.value.wallet.eagle_pounds, 2);}
  assert((await rpc(users[0], {...second, is_confirmed: false})).ok);
  report.checks.push('concurrent confirmation retry and lost receipt do not issue twice');
  for (const [name, token, body] of [
    ['foreign owner', users[1], second],
    ['changed activity', users[0], {...second, task_activity: 'exercise'}],
    ['changed run anchor', users[0], {...second, run_start_at: second.start_at}],
    ['confirmed interval rewrite', users[0], {...second, checkpoint_at: new Date(+start + 32 * 60000).toISOString()}],
    ['overlap', users[0], {...second, session_id: randomUUID()}],
    ['six hour reset', users[0], {...second, session_id: randomUUID(), start_at: new Date(+start + 360 * 60000).toISOString(), checkpoint_at: new Date(+start + 361 * 60000).toISOString()}],
  ]) {assert(!(await rpc(token, body)).ok, name); report.checks.push(`${name} rejected`);}
  const cap = {...params, session_id: randomUUID(), timer_run_id: randomUUID(),
    start_at: new Date(+start + 40 * 60000).toISOString(),
    run_start_at: new Date(+start + 40 * 60000).toISOString(),
    checkpoint_at: new Date(+start + 110 * 60000).toISOString(), is_confirmed: true};
  result = await rpc(users[0], cap); assert(result.ok); assert.equal(result.value.wallet.eagle_pounds, 12);
  report.checks.push('daily language reward capped at 12');
  const yesterday = new Date(+start - 24 * 3600000);
  const cross = {...params, session_id: randomUUID(), timer_run_id: randomUUID(),
    run_start_at: new Date(+yesterday + 23 * 3600000 + 50 * 60000).toISOString(),
    start_at: new Date(+yesterday + 23 * 3600000 + 50 * 60000).toISOString(),
    checkpoint_at: new Date(+start + 10 * 60000).toISOString(), is_running: true};
  // The running checkpoint already closes yesterday, without confirming today's part.
  result = await rpc(users[1], cross); assert(result.ok);
  assert.equal(result.value.wallet.eagle_pounds, 2);
  result = await rpc(users[1], {...cross, is_confirmed: true, is_running: false}); assert(result.ok);
  assert.equal(result.value.wallet.eagle_pounds, 4);
  report.checks.push('UTC+8 midnight settles yesterday, today waits for confirmation');
  const interrupted = {...cross, session_id:randomUUID(),timer_run_id:randomUUID(),task_activity:'exercise',is_running:false,
    run_start_at:new Date(+yesterday+21*3600000).toISOString(),start_at:new Date(+yesterday+21*3600000).toISOString(),
    checkpoint_at:new Date(+yesterday+21*3600000+20*60000).toISOString()};
  result = await rpc(users[1],interrupted);assert(result.ok);assert.equal(result.value.wallet.gems,0);
  result = await rpc(users[1],{...interrupted,is_confirmed:true});assert(result.ok);assert.equal(result.value.wallet.gems,4);
  report.checks.push('interrupted past record waits for explicit confirmation');
  const feed = await post('/rest/v1/rpc/task_feed', users[1], {});
  assert(feed.ok); assert(feed.value.every(item => item.photo_path === null));
  report.checks.push('photo-free confirmed records appear in history');
  report.result = 'PASS';
})().catch(error => {report.error = error.message; process.exitCode = 1;}).finally(() => {
  const file = path.join(root, 'docs/evidence', `timed-tasks-${report.environment === '127.0.0.1' ? 'local' : 'cloud'}.json`);
  fs.writeFileSync(file, JSON.stringify(report, null, 2));
  console.log(JSON.stringify(report, null, 2));
});
