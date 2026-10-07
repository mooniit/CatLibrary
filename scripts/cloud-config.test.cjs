const {test} = require('node:test');
const assert = require('node:assert/strict');
const {validateConfig} = require('./cloud-config.cjs');

const url = 'https://abcdefghijklmnopqrst.supabase.co';
const publishable = 'sb_publishable_test_fixture_not_a_real_key';
const config = (endpoint = url, key = publishable) => ({
  SUPABASE_URL: endpoint, SUPABASE_ANON_KEY: key,
});
const jwt = claims => `eyJhbGciOiJIUzI1NiJ9.${Buffer.from(JSON.stringify(claims)).toString('base64url')}.fixture`;

test('public hosted configuration is accepted without returning its key', () => {
  const result = validateConfig(config(), {remoteOnly: true});
  assert.deepEqual(result, {origin: url, environment: 'remote', keyType: 'publishable'});
  assert.ok(!JSON.stringify(result).includes(publishable));
});
test('legacy anon is accepted and a mismatched project is rejected', () => {
  assert.equal(validateConfig(config(url, jwt({role: 'anon', ref: 'abcdefghijklmnopqrst'}))).keyType, 'anon');
  assert.throws(() => validateConfig(config(url, jwt({role: 'anon', ref: 'differentproject'}))), /项目/);
});
test('admin and session credentials cannot be compiled into an APK', () => {
  for (const key of ['sb_secret_fixture', jwt({role: 'service_role'}), jwt({role: 'authenticated'}), 'not-a-key']) {
    assert.throws(() => validateConfig(config(url, key)), /公开/);
  }
});
test('fixture parameters and additional credential fields are rejected', () => {
  for (const field of ['M6_A_REFRESH', 'M5_TEST_SKU', 'SUPABASE_SERVICE_ROLE_KEY']) {
    assert.throws(() => validateConfig({...config(), [field]: 'fixture'}), /仅允许/);
  }
});
test('URL credentials, query parameters, fragments and API paths are rejected', () => {
  for (const endpoint of ['https://user:password@abcdefghijklmnopqrst.supabase.co', `${url}?key=fixture`, `${url}#fixture`, `${url}/rest/v1`]) {
    assert.throws(() => validateConfig(config(endpoint)), /根地址/);
  }
});
test('remote endpoints require HTTPS', () => {
  assert.throws(() => validateConfig(config(url.replace('https:', 'http:'))), /HTTPS/);
});
test('local packages remain usable but cannot pass the remote gate', () => {
  for (const endpoint of ['http://127.0.0.1:54321', 'http://localhost:54321', 'http://192.168.1.5:54321', 'http://10.0.2.2:54321', 'http://172.20.1.5:54321', 'http://[::1]:54321', 'https://[::ffff:127.0.0.1]:54321']) {
    assert.equal(validateConfig(config(endpoint)).environment, 'local');
    assert.throws(() => validateConfig(config(endpoint), {remoteOnly: true}), /本地/);
  }
});
test('empty, placeholder and non-object configuration fail without echoing values', () => {
  for (const input of [null, [], {}, config('', ''), config(url, 'REPLACE_WITH_PUBLISHABLE_KEY')]) {
    assert.throws(() => validateConfig(input));
  }
  try { validateConfig(config(url, 'sb_secret_fixture')); } catch (error) {
    assert.ok(!error.message.includes('sb_secret_fixture'));
  }
});
