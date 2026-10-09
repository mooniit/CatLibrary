// Actual anonymous-session transplant on a new isolated local identity only.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {spawnSync} = require('node:child_process');
const {createHash} = require('node:crypto');
const {readConfig, validateConfig} = require('./cloud-config.cjs');
const {buildAuthImport, authSchemaSql} = require('./auth-migration.cjs');
const root = path.resolve(__dirname, '..');
const local = readConfig(path.join(root, '.tooling/local-phone-defines.json'));
const cloud = readConfig(path.join(root, '.tooling/cloud-phone-defines.json'));
assert.equal(local.SUPABASE_URL, 'http://127.0.0.1:54321');
validateConfig(cloud, {remoteOnly: true});
const ref = 'ludwvhsvknjgblfgouor';
assert.equal(new URL(cloud.SUPABASE_URL).hostname, ref + '.supabase.co');
assert.equal(fs.readFileSync(path.join(root, 'supabase/.temp/project-ref'), 'utf8').trim(), ref);
const cli = path.join(root, '.tooling/supabase-cli/node_modules/@supabase/cli-windows-x64/bin/supabase.exe');
const directory = path.join(root, '.tooling', 'auth-migration-probe-' + Date.now());
fs.mkdirSync(directory);
const report = {startedAt: new Date().toISOString(), scope: 'new isolated local anonymous identity imported to hosted Auth',
  projectRef: ref, checks: [], originalIdentityMigrated: false, mobileInternetVerified: false};
function pass(name) { report.checks.push(name); console.log('PASS ' + name); }
function localSql(sql) {
  const result = spawnSync('docker', ['exec', '-i', 'supabase_db_CatLibrary', 'psql', '-U', 'postgres', '-d', 'postgres', '-qAt', '-v', 'ON_ERROR_STOP=1'], {input: sql, encoding: 'utf8'});
  if (result.status !== 0) { fs.writeFileSync(path.join(directory, 'local-error.txt'), result.stderr || ''); throw new Error('Local SQL failed'); }
  return result.stdout.trim();
}
function remoteSql(sql, name) {
  const file = path.join(directory, name + '.sql'); fs.writeFileSync(file, sql, {flag: 'wx'});
  const result = spawnSync(cli, ['db', 'query', '--linked', '--file', file, '--output', 'json'], {encoding: 'utf8', timeout: 120000});
  fs.writeFileSync(path.join(directory, name + '-output.json'), result.stdout || '');
  fs.writeFileSync(path.join(directory, name + '-stderr.txt'), result.stderr || '');
  if (result.status !== 0) throw new Error('Hosted SQL failed');
  return JSON.parse(result.stdout).rows;
}
async function http(config, route, body, access) {
  const response = await fetch(config.SUPABASE_URL + route, {method: 'POST', redirect: 'error',
    headers: {apikey: config.SUPABASE_ANON_KEY, ...(access ? {Authorization: 'Bearer ' + access} : {}), 'Content-Type': 'application/json'},
    body: JSON.stringify(body), signal: AbortSignal.timeout(20000)});
  return {ok: response.ok, status: response.status, value: await response.json()};
}
async function run() {
  const signup = await http(local, '/auth/v1/signup', {});
  assert(signup.ok && signup.value.refresh_token, 'Local fixture signup failed');
  const session = signup.value;
  fs.writeFileSync(path.join(directory, 'source-session.json'), JSON.stringify(session));
  const owner = session.user.id;
  assert.match(owner, /^[0-9a-f-]{36}$/);
  report.ownerHash = createHash('sha256').update(owner).digest('hex');
  report.fixtureCreated = true;
  pass('isolated anonymous source session created without reading device credentials');
  const data = JSON.parse(localSql(`begin read only;
    select jsonb_build_object('users',(select jsonb_agg(to_jsonb(u)) from auth.users u where id='${owner}'),
      'identities',coalesce((select jsonb_agg(to_jsonb(i)) from auth.identities i where user_id='${owner}'),'[]'),
      'sessions',(select jsonb_agg(to_jsonb(s)) from auth.sessions s where user_id='${owner}'),
      'refresh_tokens',(select jsonb_agg(to_jsonb(t)) from auth.refresh_tokens t where user_id='${owner}'));
    commit;`));
  fs.writeFileSync(path.join(directory, 'source-auth.json'), JSON.stringify(data));
  const schema = remoteSql(authSchemaSql, 'target-schema');
  const plan = buildAuthImport(data, [owner], schema);
  report.authRows = plan.summary;
  pass('source rows scoped and target Auth schema checked before import');
  const before = await http(cloud, '/rest/v1/rpc/bootstrap_identity', {}, session.access_token);
  assert.equal(before.status, 401);
  pass('local access JWT cannot authenticate to hosted project');
  remoteSql('begin;\n' + plan.collisionGuard + '\n' + plan.statements.join('\n') + '\ncommit;\nselect true as imported;', 'import');
  report.isolatedAuthImported = true;
  const refresh = await http(cloud, '/auth/v1/token?grant_type=refresh_token', {refresh_token: session.refresh_token});
  assert(refresh.ok && refresh.value.user.id === owner, 'Imported refresh session failed');
  fs.writeFileSync(path.join(directory, 'cloud-session.json'), JSON.stringify(refresh.value));
  pass('original refresh token issues hosted tokens for the exact same user ID');
  await new Promise(resolve => setTimeout(resolve, 12000));
  const retry = await http(cloud, '/auth/v1/token?grant_type=refresh_token', {refresh_token: session.refresh_token});
  assert(retry.ok && retry.value.user.id === owner);
  fs.writeFileSync(path.join(directory, 'cloud-session.json'), JSON.stringify(retry.value));
  pass('lost first refresh receipt can be retried outside reuse interval without creating another identity');
  const bootstrap = await http(cloud, '/rest/v1/rpc/bootstrap_identity', {}, retry.value.access_token);
  assert(bootstrap.ok && bootstrap.value.owner_id === owner && bootstrap.value.miao_coins === 30);
  pass('hosted authenticated business RPC uses preserved identity');
  const rollback = await http(local, '/auth/v1/token?grant_type=refresh_token', {refresh_token: session.refresh_token});
  assert(rollback.ok && rollback.value.user.id === owner);
  fs.writeFileSync(path.join(directory, 'source-refreshed-session.json'), JSON.stringify(rollback.value));
  pass('source session remains recoverable after independent hosted refresh');
  report.result = 'PASS';
}
run().catch(error => {
  report.result = 'FAIL';
  report.failure = error instanceof assert.AssertionError ? 'Auth migration assertion failed' : 'Auth migration request failed';
  report.failureLocation = error.stack?.split('\n').find(line => line.includes('test-cloud-auth-migration.cjs:'))?.trim();
  console.error(report.failure); process.exitCode = 1;
}).finally(() => {
  report.finishedAt = new Date().toISOString();
  fs.writeFileSync(path.join(root, 'docs/evidence/m7-cloud-auth-migration-probe.json'), JSON.stringify(report, null, 2) + '\n');
});
