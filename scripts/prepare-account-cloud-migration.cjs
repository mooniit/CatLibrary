// Prepare an immutable private backup and execute a fully rolled-back restore.
const fs = require('node:fs'), path = require('node:path');
const assert = require('node:assert/strict');
const {spawnSync} = require('node:child_process');
const {createHash} = require('node:crypto');
const {readConfig, validateConfig} = require('./cloud-config.cjs');
const {buildAuthImport, authSchemaSql} = require('./auth-migration.cjs');
const {tables, exportSql, buildFamilyImport} = require('./family-data-migration.cjs');
const root = path.resolve(__dirname, '..'), ref = 'ludwvhsvknjgblfgouor';
const originalOwnerHash = 'a943f6a8f8bbfb85773c91bd116a8460154293a073efad8b8444ac4eeacc10a3';
const cloud = readConfig(path.join(root, '.tooling/cloud-phone-defines.json'));
validateConfig(cloud, {remoteOnly: true});
assert.equal(new URL(cloud.SUPABASE_URL).hostname, ref + '.supabase.co');
assert.equal(fs.readFileSync(path.join(root, 'supabase/.temp/project-ref'), 'utf8').trim(), ref);
const directory = path.join(root, '.tooling', 'account-cloud-migration-' + Date.now());
fs.mkdirSync(directory);
const cli = path.join(root, '.tooling/supabase-cli/node_modules/@supabase/cli-windows-x64/bin/supabase.exe');
const sha = bytes => createHash('sha256').update(bytes).digest('hex');
const report = {startedAt: new Date().toISOString(), projectRef: ref, ownerHash: originalOwnerHash,
  result: 'FAIL', originalIdentityMigrated: false, mobileInternetVerified: false};
function localSql(sql) {
  const r = spawnSync('docker', ['exec', '-i', 'supabase_db_CatLibrary', 'psql', '-U', 'postgres', '-d', 'postgres', '-qAt', '-v', 'ON_ERROR_STOP=1'], {input: sql, encoding: 'utf8', maxBuffer: 16 * 1024 * 1024});
  if (r.status !== 0) { fs.writeFileSync(path.join(directory, 'source-error.txt'), r.stderr || ''); throw new Error('Local backup failed'); }
  return r.stdout.trim();
}
function remoteSql(sql, name) {
  const file = path.join(directory, name + '.sql'); fs.writeFileSync(file, sql, {flag: 'wx'});
  const r = spawnSync(cli, ['db', 'query', '--linked', '--file', file, '--output', 'json'], {encoding: 'utf8', timeout: 120000, maxBuffer: 16 * 1024 * 1024});
  fs.writeFileSync(path.join(directory, name + '-output.json'), r.stdout || '');
  fs.writeFileSync(path.join(directory, name + '-stderr.txt'), r.stderr || '');
  if (r.status !== 0) throw new Error('Hosted migration dry run failed');
  return JSON.parse(r.stdout).rows;
}
try {
  const scope = JSON.parse(localSql(`begin read only;
    with original as (select * from public.family_members where encode(extensions.digest(user_id::text,'sha256'),'hex')='${originalOwnerHash}')
    select jsonb_build_object('matches',(select count(*) from original),'family',(select family_id from original),
      'owners',(select jsonb_agg(user_id order by user_id) from public.family_members where family_id=(select family_id from original)));
    commit;`));
  assert.equal(scope.matches, 1);
  const {family, owners} = scope;
  assert(/^[0-9a-f-]{36}$/.test(family) && owners.every(o => /^[0-9a-f-]{36}$/.test(o)));
  const ids = owners.map(o => "'" + o + "'").join(',');
  const sourceSql = `begin isolation level repeatable read read only; set local timezone='UTC';
    select jsonb_build_object('family','${family}','owners',to_jsonb(array[${ids}]::uuid[]),
      'auth',jsonb_build_object('users',(select jsonb_agg(to_jsonb(u) order by id) from auth.users u where id in(${ids})),
        'identities',coalesce((select jsonb_agg(to_jsonb(i) order by id) from auth.identities i where user_id in(${ids})),'[]'),
        'sessions',coalesce((select jsonb_agg(to_jsonb(s) order by id) from auth.sessions s where user_id in(${ids})),'[]'),
        'refresh_tokens',coalesce((select jsonb_agg(to_jsonb(t) order by id) from auth.refresh_tokens t where user_id in(${ids})),'[]')),
      'rows',(${exportSql(family, owners)}),
      'photoObjects',(select count(*) from storage.objects where split_part(name,'/',1) in(${ids})),
      'testFamily',(select count(*) from public.room_test_families where family_id='${family}'),
      'testInventory',(select count(*) from public.furniture_inventory i join public.furniture_products p using(sku) where family_id='${family}' and p.is_test),
      'missingPastSettlements',(select count(*) from public.families f cross join public.billing_activation a cross join lateral generate_series(greatest((f.created_at at time zone 'Asia/Shanghai')::date,a.start_day)::timestamp,((clock_timestamp() at time zone 'Asia/Shanghai')::date-1)::timestamp,interval '1 day') d where f.id='${family}' and not exists(select 1 from public.family_daily_settlements s where s.family_id=f.id and s.business_day=d::date)));
    commit;`;
  fs.writeFileSync(path.join(directory, 'source-export.sql'), sourceSql, {flag: 'wx'});
  const backup = localSql(sourceSql);
  fs.writeFileSync(path.join(directory, 'source.json'), backup + '\n', {flag: 'wx'});
  const data = JSON.parse(backup);
  assert.equal(data.photoObjects, 0, 'Photos require a separate binary transfer before commit');
  assert.equal(data.testFamily, 0); assert.equal(data.testInventory, 0);
  assert.equal(data.missingPastSettlements, 0, 'Historical settlement coverage incomplete');
  console.log('PASS scoped read-only backup, no missing historical settlements or photo files');
  const targetMeta = remoteSql("begin read only; select jsonb_build_object('versions',(select jsonb_agg(version order by version) from supabase_migrations.schema_migrations),'triggers',(select jsonb_agg(jsonb_build_object('name',t.tgname,'table',c.relname,'enabled',t.tgenabled::text) order by c.relname,t.tgname) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and not t.tgisinternal)) as metadata; commit;", 'target-metadata')[0].metadata;
  const versions = fs.readdirSync(path.join(root, 'supabase/migrations')).filter(f => /^\d+_.*\.sql$/.test(f)).map(f => f.split('_')[0]).sort();
  assert.deepEqual(targetMeta.versions, versions, 'Hosted schema must match every checked-in migration');
  const schema = remoteSql(authSchemaSql, 'target-auth-schema');
  const auth = buildAuthImport(data.auth, owners, schema);
  const business = buildFamilyImport(data, targetMeta.triggers);
  const guard = `do $$ begin if exists(select 1 from public.families where id='${family}' or invite_code=(select r.invite_code from jsonb_populate_recordset(null::public.families,${require('./auth-migration.cjs').jsonExpression(data.rows.families)}) r)) then raise exception 'Target family or invitation already exists'; end if; end $$;`;
  const body = ['begin;', "set local timezone='UTC';", "set local lock_timeout='10s';", auth.collisionGuard, guard,
    ...business.disable, ...auth.statements, ...business.statements, ...business.enable, ...business.verification,
    `do $$ declare why text; begin select public.validate_room_layout('${family}',layout) into why from public.room_layouts where family_id='${family}'; if why is not null then raise exception 'Restored room layout fails current rules'; end if; end $$;`].join('\n');
  const prepared = {directory, projectRef: ref, originalOwnerHash, sourceSha256: sha(backup + '\n'),
    sourceSqlSha256: sha(sourceSql), auth: auth.summary, business: business.summary,
    generatedColumnsExcluded: true, foreignKeysEnabled: true, ledgerSerialIdsReallocated: true, editorLeasesReleased: true};
  const afterRollback = `rollback; do $$ begin if exists(select 1 from auth.users where id in(${ids})) or exists(select 1 from public.families where id='${family}') then raise exception 'Dry run did not leave target empty for original account'; end if; end $$; select true as dry_run_rolled_back;`;
  const dry = remoteSql(body + '\n' + afterRollback, 'dry-run');
  assert.equal(dry[0].dry_run_rolled_back, true);
  // Never produce an executable commit plan before the full rollback succeeds.
  fs.writeFileSync(path.join(directory, 'apply.sql'), body + '\ncommit;\nselect true as migration_committed;\n', {flag: 'wx'});
  prepared.applySha256 = sha(fs.readFileSync(path.join(directory, 'apply.sql')));
  prepared.dryRunPassed = true;
  fs.writeFileSync(path.join(directory, 'prepared.json'), JSON.stringify(prepared, null, 2), {flag: 'wx'});
  fs.writeFileSync(path.join(root, '.tooling/account-cloud-migration-latest.json'), JSON.stringify({directory}));
  Object.assign(report, {result: 'PASS', backupSha256: prepared.sourceSha256, dryRunRolledBack: true,
    comparedBusinessTables: tables.length, rows: business.summary, authRows: auth.summary,
    foreignKeysEnabled: true, triggersRestored: true, pastSettlementsComplete: true,
    photoObjects: 0, ledgerSerialIdsReallocated: true, editorLeasesReleased: true});
  console.log(`PASS all ${tables.length} business tables and Auth restore verified inside a rolled-back cloud transaction`);
} catch (error) {
  report.failure = error instanceof assert.AssertionError ? 'Scoped migration assertion failed' : 'Migration preparation failed';
  report.failureLocation = error.stack?.split('\n').find(line => line.includes('prepare-account-cloud-migration.cjs:'))?.trim();
  console.error(report.failure); process.exitCode = 1;
} finally {
  report.finishedAt = new Date().toISOString();
  fs.writeFileSync(path.join(directory, 'report-private.json'), JSON.stringify(report, null, 2) + '\n');
  const publicReport = {...report};
  for (const key of ['ownerHash', 'backupSha256', 'failureLocation']) delete publicReport[key];
  fs.writeFileSync(path.join(root, 'docs/evidence/photo-wall-cloud-dry-run.json'), JSON.stringify(publicReport, null, 2) + '\n');
}
