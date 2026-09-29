// Two real local HTTP sessions race to feed the same cat; no service key.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const config = JSON.parse(fs.readFileSync(path.join(__dirname,
  '../.tooling/local-phone-defines.json'), 'utf8').replace(/^\uFEFF/, ''));
assert.equal(config.SUPABASE_URL, 'http://127.0.0.1:54321');
async function post(route, token, body = {}) {
  const response = await fetch(config.SUPABASE_URL + route, {
    method: 'POST', headers: {apikey: config.SUPABASE_ANON_KEY,
      ...(token ? {Authorization: `Bearer ${token}`} : {}),
      'Content-Type': 'application/json'}, body: JSON.stringify(body),
    signal: AbortSignal.timeout(15000),
  });
  const value = await response.json();
  return {ok: response.ok, status: response.status, value};
}
(async () => {
  const users = await Promise.all([0, 1, 2].map(async () => {
    const auth = await post('/auth/v1/signup', null);
    assert(auth.ok && auth.value.access_token);
    const token = auth.value.access_token;
    assert((await post('/rest/v1/rpc/bootstrap_identity', token)).ok);
    return token;
  }));
  const rpc = (index, name, body) => post(`/rest/v1/rpc/${name}`, users[index], body);
  const family = await rpc(0, 'create_family');
  assert(family.ok, JSON.stringify(family.value));
  assert((await rpc(1, 'request_family_join', {code: family.value.family.invite_code})).ok);
  const request = (await rpc(0, 'family_state')).value.requests[0];
  assert((await rpc(0, 'decide_family_join', {request_id: request.id, approve: true})).ok);
  const adopted = await rpc(0, 'adopt_cat',
    {appearance_key: 'black_short', cat_name: '喂食并发测试猫'});
  assert(adopted.ok, JSON.stringify(adopted.value));
  const cat = adopted.value.cats[0].id;
  assert.equal((await rpc(2, 'feed_cat', {target_cat: cat})).status, 403);
  const results = await Promise.all([0, 1].map(i => rpc(i, 'feed_cat', {target_cat: cat})));
  results.forEach(result => assert(result.ok, JSON.stringify(result.value)));
  assert.deepEqual(results.map(result => result.value.outcome).sort(), ['already_fed', 'fed']);
  const wallets = await Promise.all([0, 1].map(i => rpc(i, 'bootstrap_identity')));
  assert.equal(wallets.reduce((sum, result) => sum + result.value.miao_coins, 0), 45);
  assert.equal((await rpc(0, 'feed_cat', {target_cat: cat})).value.outcome, 'already_fed');
  console.log('PASS local HTTP: two members race; one 15-coin charge, retry and outsider rejected');
})().catch(error => { console.error(error); process.exitCode = 1; });
