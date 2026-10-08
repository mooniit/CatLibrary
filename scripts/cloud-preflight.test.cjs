const {test} = require('node:test');
const assert = require('node:assert/strict');
const {probeServices, migrationManifest} = require('./cloud-preflight.cjs');
const configuration = {
  SUPABASE_URL: 'https://abcdefghijklmnopqrst.supabase.co',
  SUPABASE_ANON_KEY: 'sb_publishable_test_fixture_not_a_real_key',
};
const response = (value, status = 200) => new Response(JSON.stringify(value), {status});
const auth = {external: {anonymous_users: true}, disable_signup: false};
const rest = {swagger: '2.0', paths: {}};

test('published-key schema restriction proves gateway reachability, not authenticated data access', async () => {
  const result = await probeServices(configuration, {fetcher: async url =>
    response(url.endsWith('/settings') ? auth : {message: 'Secret API key required'}, url.endsWith('/settings') ? 200 : 401),
  });
  assert.equal(result.readOnlyPreflightPassed, true);
  const check = result.checks.find(item => item.service === 'rest');
  assert.equal(check.schemaEnumerationRestricted, true);
  assert.equal(check.authenticatedDataAccessVerified, false);
  assert.equal(result.migrationsVerified, false);
});

test('schema restriction cannot bypass disabled anonymous login or invalid-key responses', async () => {
  for (const [settings, message] of [[{...auth, external: {anonymous_users: false}}, 'Secret API key required'], [auth, 'Invalid API key']]) {
    const result = await probeServices(configuration, {fetcher: async url =>
      response(url.endsWith('/settings') ? settings : {message}, url.endsWith('/settings') ? 200 : 401),
    });
    assert.equal(result.readOnlyPreflightPassed, false);
  }
});

test('read-only preflight does not claim identity, migration or mobile verification', async () => {
  const requests = [];
  const result = await probeServices(configuration, {fetcher: async (url, options) => {
    requests.push({url, options});
    return response(url.endsWith('/settings') ? auth : rest);
  }});
  assert.equal(result.readOnlyPreflightPassed, true);
  assert.equal(result.migrationsVerified, false);
  assert.equal(result.originalIdentityMigrated, false);
  assert.equal(result.mobileInternetVerified, false);
  assert.ok(!JSON.stringify(result).includes(configuration.SUPABASE_ANON_KEY));
  assert.equal(requests.length, 2);
  for (const {options} of requests) {
    assert.equal(options.method, 'GET');
    assert.equal(options.redirect, 'error');
    assert.equal(options.body, undefined);
  }
});
test('disabled anonymous signup prevents preflight success', async () => {
  for (const settings of [{external: {anonymous_users: false}}, {...auth, disable_signup: true}]) {
    const result = await probeServices(configuration, {fetcher: async url => response(url.endsWith('/settings') ? settings : rest)});
    assert.equal(result.readOnlyPreflightPassed, false);
  }
});
test('authentication errors, service errors, non-JSON and network failures remain failures', async () => {
  for (const fetcher of [async () => response({}, 401), async () => response({}, 503), async () => new Response('<html>'), async () => { throw new Error(configuration.SUPABASE_ANON_KEY); }]) {
    const result = await probeServices(configuration, {fetcher});
    assert.equal(result.readOnlyPreflightPassed, false);
    assert.ok(!JSON.stringify(result).includes(configuration.SUPABASE_ANON_KEY));
  }
});
test('root REST schema must be a valid API description', async () => {
  const result = await probeServices(configuration, {fetcher: async url => response(url.endsWith('/settings') ? auth : {})});
  assert.equal(result.readOnlyPreflightPassed, false);
});
test('local endpoints are rejected before any remote probe', async () => {
  let fetched = false;
  await assert.rejects(probeServices({...configuration, SUPABASE_URL: 'http://127.0.0.1:54321'}, {fetcher: async () => { fetched = true; }}), /本地/);
  assert.equal(fetched, false);
});
test('migration manifest uses actual ordered SQL files and excludes seed and fixtures', () => {
  const manifest = migrationManifest();
  assert.ok(manifest.length > 40);
  assert.ok(manifest.every(item => /^\d+_.+\.sql$/.test(item.file) && /^[a-f0-9]{64}$/.test(item.sha256)));
  assert.deepEqual(manifest.map(item => item.file), manifest.map(item => item.file).sort());
  assert.ok(manifest.some(item => item.file === '202610070009_souvenir_refined_sprites.sql'));
  assert.ok(!manifest.some(item => item.file === 'seed.sql'));
});
