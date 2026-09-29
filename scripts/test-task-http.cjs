// Local Supabase API test: real private Storage upload, task settlement and exchange.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const config = JSON.parse(fs.readFileSync(path.join(__dirname, '../.tooling/local-phone-defines.json'), 'utf8').replace(/^\uFEFF/, ''));
assert.equal(config.SUPABASE_URL, 'http://127.0.0.1:54321');
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', 'base64');
async function post(route, token, body, mime = 'application/json') {
  const response = await fetch(config.SUPABASE_URL + route, {
    method: 'POST',
    headers: {apikey: config.SUPABASE_ANON_KEY,
      ...(token ? {Authorization: `Bearer ${token}`} : {}), 'Content-Type': mime},
    body: mime === 'application/json' ? JSON.stringify(body) : body,
    signal: AbortSignal.timeout(15000),
  });
  const value = await response.json();
  return {status: response.status, ok: response.ok, value};
}
(async () => {
  const auth = await post('/auth/v1/signup', null, {});
  assert(auth.ok && auth.value.access_token, 'anonymous auth failed');
  const token = auth.value.access_token;
  const owner = auth.value.user.id;
  assert((await post('/rest/v1/rpc/bootstrap_identity', token, {})).ok);
  async function task(activity, start, end) {
    const id = randomUUID(), photo = `${owner}/${id}`;
    const args = {session_id: id, task_activity: activity, start_at: start,
      checkpoint_at: end, task_photo_path: null, is_confirmed: false};
    const before = await post('/rest/v1/rpc/sync_task_session', token, args);
    assert(before.ok, JSON.stringify(before.value));
    assert.equal(before.value.wallet.eagle_pounds, 0);
    const missing = await post('/rest/v1/rpc/sync_task_session', token,
      {...args, task_photo_path: photo, is_confirmed: true});
    assert(!missing.ok, 'missing photo must not earn currency');
    const upload = await post(`/storage/v1/object/task-photos/${photo}`, token, png, 'image/png');
    assert(upload.ok, JSON.stringify(upload.value));
    const duplicate = await post(`/storage/v1/object/task-photos/${photo}`, token, png, 'image/png');
    assert.equal(duplicate.value.statusCode, '409', JSON.stringify(duplicate.value));
    const confirmed = await post('/rest/v1/rpc/sync_task_session', token,
      {...args, task_photo_path: photo, is_confirmed: true});
    assert(confirmed.ok, JSON.stringify(confirmed.value));
    const retry = await post('/rest/v1/rpc/sync_task_session', token, args);
    assert(retry.ok, JSON.stringify(retry.value));
    return confirmed.value.wallet;
  }
  let wallet = await task('language', '2026-09-01T00:00:00Z', '2026-09-01T00:06:00Z');
  assert.equal(wallet.eagle_pounds, 0);
  const feed = await post('/rest/v1/rpc/task_feed', token, {});
  assert(feed.ok && feed.value.length === 1, JSON.stringify(feed.value));
  wallet = await task('language', '2026-09-01T01:00:00Z', '2026-09-01T01:05:00Z');
  assert.equal(wallet.eagle_pounds, 2);
  const exchangeId = randomUUID();
  const args = {request_id: exchangeId, source_currency: 'eagle'};
  const exchanged = await post('/rest/v1/rpc/exchange_special', token, args);
  assert(exchanged.ok, JSON.stringify(exchanged.value));
  assert.equal(exchanged.value.wallet.eagle_pounds, 1);
  assert.equal(exchanged.value.wallet.miao_coins, 35);
  const retry = await post('/rest/v1/rpc/exchange_special', token, args);
  assert(retry.ok && retry.value.wallet.miao_coins === 35);
  console.log('PASS local HTTP: private photo upload gates 6+5 minute rewards; retries and 1:5 exchange are idempotent');
})().catch(error => { console.error(error); process.exitCode = 1; });
