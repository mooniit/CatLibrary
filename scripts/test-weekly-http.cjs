// Local Supabase API test for the full weekly offer -> evidence -> reward flow.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const config = JSON.parse(fs.readFileSync(path.join(__dirname,
  '../.tooling/local-phone-defines.json'), 'utf8').replace(/^\uFEFF/, ''));
assert.equal(config.SUPABASE_URL, 'http://127.0.0.1:54321');
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=', 'base64');
async function post(route, token, body, mime = 'application/json') {
  const response = await fetch(config.SUPABASE_URL + route, {
    method: 'POST', headers: {apikey: config.SUPABASE_ANON_KEY,
      ...(token ? {Authorization: `Bearer ${token}`} : {}),
      'Content-Type': mime, ...(mime === 'image/png' ? {'x-upsert': 'true'} : {})},
    body: mime === 'application/json' ? JSON.stringify(body) : body,
    signal: AbortSignal.timeout(15000),
  });
  const value = await response.json();
  return {ok: response.ok, status: response.status, value};
}
(async () => {
  const auth = await post('/auth/v1/signup', null, {});
  assert(auth.ok && auth.value.access_token, 'anonymous auth failed');
  const token = auth.value.access_token, owner = auth.value.user.id;
  assert((await post('/rest/v1/rpc/bootstrap_identity', token, {})).ok);
  const offers = await post('/rest/v1/rpc/weekly_my_tasks', token, {});
  assert(offers.ok && offers.value.length === 2, JSON.stringify(offers.value));
  assert.notEqual(offers.value[0].task_id, offers.value[1].task_id);
  for (let index = 0; index < 2; index++) {
    const task = offers.value[index];
    const note = task.evidence_kind === 'text' ? '已完成本周任务' : null;
    const saved = await post('/rest/v1/rpc/weekly_save_draft', token,
      {target_offer: task.offer_id, draft_note: note});
    assert(saved.ok, JSON.stringify(saved.value));
    for (let slot = 0; slot < task.image_count; slot++) {
      const upload = await post(`/storage/v1/object/weekly-photos/${owner}/${task.offer_id}/${slot}`,
        token, png, 'image/png');
      assert(upload.ok, JSON.stringify(upload.value));
    }
    const args = {target_offer: task.offer_id, claimed_at: new Date().toISOString()};
    const confirmed = await post('/rest/v1/rpc/weekly_confirm', token, args);
    assert(confirmed.ok, JSON.stringify(confirmed.value));
    assert.equal(confirmed.value.wallet.gems, (index + 1) * 6);
    assert.equal(confirmed.value.wallet.eagle_pounds, (index + 1) * 6);
    const retry = await post('/rest/v1/rpc/weekly_confirm', token, args);
    assert(retry.ok, JSON.stringify(retry.value));
    assert.equal(retry.value.wallet.gems, (index + 1) * 6);
  }
  const feed = await post('/rest/v1/rpc/weekly_family_feed', token, {});
  assert(feed.ok && feed.value.length === 2, JSON.stringify(feed.value));
  console.log('PASS local HTTP: personal offers, evidence upload, 6+6 per task, idempotent retry and feed; types=' +
    offers.value.map(task => `${task.evidence_kind}:${task.image_count}`).join(','));
})().catch(error => { console.error(error); process.exitCode = 1; });
