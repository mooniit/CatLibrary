// Local synthetic fixtures only. No device sessions, cloud credentials or cleanup.
const fs = require('node:fs'), path = require('node:path');
const assert = require('node:assert/strict');
const {execFileSync, spawn} = require('node:child_process');
const {randomUUID, createHash} = require('node:crypto');
const root = path.resolve(__dirname, '..');
const stamp = Date.now();
const args = ['exec', 'supabase_db_CatLibrary', 'psql', '-U', 'postgres', '-d', 'postgres', '-qAt', '-v', 'ON_ERROR_STOP=1'];
const fixtures = {scope: 'isolated-local-business-contention', families: []};
const report = {startedAt: new Date().toISOString(), result: 'FAIL', environment: 'local Docker PostgreSQL',
  syntheticClocksAndWallets: true, remoteVerified: false, originalSettlementExecuted: false, checks: []};
const persist = () => fs.writeFileSync(path.join(root, '.tooling', `business-contention-${stamp}.json`), JSON.stringify(fixtures, null, 2));
const sql = query => execFileSync('docker', [...args, '-c', query], {encoding: 'utf8', timeout: 20000}).trim();
const json = query => JSON.parse(sql(query).split('\n').findLast(line => line.startsWith('{')));
const auth = owner => `set local role authenticated; set local "request.jwt.claims"='{"sub":"${owner}"}';`;
const uid = value => {assert.match(value, /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/); return value;};
function connection(query) {
  const child = spawn('docker', [...args.slice(0, 1), '-i', ...args.slice(1)], {stdio: ['pipe', 'pipe', 'pipe']});
  let output = '', error = '';
  child.stdout.on('data', part => output += part);
  child.stderr.on('data', part => error += part);
  const done = new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('close', code => code === 0 ? resolve(output.trim()) : reject(new Error('Isolated SQL worker failed')));
  });
  // Register rejection immediately while the lock barrier is being inspected.
  done.catch(() => {});
  child.stdin.write(query + '\n');
  return {child, done, output: () => output, error: () => error};
}
async function waitUntil(ready) {
  const deadline = performance.now() + 10000;
  while (!ready()) {
    assert(performance.now() < deadline, 'Real lock barrier not reached');
    await new Promise(resolve => setTimeout(resolve, 100));
  }
}
async function race(fixture, lock, operations) {
  const names = operations.map((_, i) => `m8_${stamp}_${report.checks.length}_${i}`);
  const key = lock === 'wallets' ? `owner_id='${fixture.users[0]}'` : `id='${fixture.home}'`;
  const barrier = connection(`begin; set local statement_timeout='15s';
    select 1 from public.${lock} where ${key} for update; select 'BARRIER_READY';`);
  const workers = [];
  try {
    await waitUntil(() => barrier.output().includes('BARRIER_READY'));
    for (let i = 0; i < operations.length; i++) {
      const worker = connection(`set application_name='${names[i]}'; begin;
        set local statement_timeout='15s'; ${operations[i]}; commit;`);
      worker.child.stdin.end(); workers.push(worker);
      await waitUntil(() => Number(sql(`select count(*) from pg_stat_activity
        where application_name in (${names.slice(0, i + 1).map(n => `'${n}'`).join(',')})
        and wait_event_type='Lock'`)) === i + 1);
    }
    barrier.child.stdin.end('commit;\n');
    await barrier.done;
    const output = await Promise.all(workers.map(worker => worker.done));
    return output.map(text => JSON.parse(text.split('\n').findLast(line => line.startsWith('{'))));
  } finally {
    if (!barrier.child.stdin.destroyed && !barrier.child.stdin.writableEnded) {
      barrier.child.stdin.end('rollback;\n');
    }
    await Promise.allSettled([barrier.done, ...workers.map(worker => worker.done)]);
  }
}
function setup(members = 1) {
  const fixture = {users: Array.from({length: members}, () => randomUUID()), home: null};
  fixtures.families.push(fixture); persist();
  const [a, b] = fixture.users;
  sql(`begin; insert into auth.users(id) values ${fixture.users.map(id => `('${id}')`).join(',')};
    ${auth(a)} select public.bootstrap_identity(); select public.create_family();
    reset role; ${b ? `insert into public.family_members(user_id,family_id)
      select '${b}',family_id from public.family_members where user_id='${a}';
      ${auth(b)} select public.bootstrap_identity(); reset role;` : ''} commit;`);
  fixture.home = uid(sql(`select family_id from public.family_members where user_id='${a}'`));
  persist(); return fixture;
}
function cat(fixture, day) {
  const owner = fixture.users[0];
  sql(`begin; ${auth(owner)} select public.adopt_cat('black_short','隔离并发猫'); reset role;
    update public.cats set adopted_at=('${day}'::date::timestamp at time zone 'Asia/Shanghai')+interval '1 hour'
      where owner_id='${owner}' and family_id='${fixture.home}'; commit;`);
}
function snapshot(fixture, day) {
  const owner = fixture.users[0];
  return json(`select json_build_object('balance',(select miao_coins from public.wallets where owner_id='${owner}'),
    'study',(select coalesce(sum(miao_delta),0) from public.wallet_entries where owner_id='${owner}' and kind='study'),
    'studyEntries',(select count(*) from public.wallet_entries where owner_id='${owner}' and kind='study'),
    'interest',(select paid from public.daily_interest_charges where owner_id='${owner}' and business_day='${day}'),
    'afterReward',(select balance_after_reward from public.daily_interest_charges where owner_id='${owner}' and business_day='${day}'),
    'fee',(select coalesce(sum(paid),0) from public.daily_cat_charges where owner_id='${owner}' and business_day='${day}'),
    'feeEntries',(select count(*) from public.wallet_entries where owner_id='${owner}' and kind='cat_fee'),
    'settlements',(select count(*) from public.family_daily_settlements where family_id='${fixture.home}'),
    'inventory',(select count(*) from public.furniture_inventory where family_id='${fixture.home}'),
    'purchaseEntries',(select count(*) from public.wallet_entries where owner_id='${owner}' and kind='furniture'))`);
}
function record(name, detail) {report.checks.push({name, blockedConnectionsVerified: 2, ...detail}); console.log('PASS ' + name);}
function originalSnapshot() {
  return sql(`with member as (select user_id,family_id from public.family_members where
    encode(extensions.digest(user_id::text,'sha256'),'hex')='a943f6a8f8bbfb85773c91bd116a8460154293a073efad8b8444ac4eeacc10a3')
    select encode(extensions.digest(jsonb_build_object(
      'wallet',(select jsonb_agg(to_jsonb(w) order by w.owner_id) from public.wallets w join member m on m.user_id=w.owner_id),
      'ledger',(select count(*) from public.wallet_entries w join member m on m.user_id=w.owner_id),
      'inventory',(select jsonb_agg(to_jsonb(i) order by i.id) from public.furniture_inventory i join member m on m.family_id=i.family_id),
      'room',(select jsonb_agg(to_jsonb(r) order by r.family_id) from public.room_layouts r join member m on m.family_id=r.family_id)
    )::text,'sha256'),'hex')`);
}
async function run() {
  persist();
  assert.equal(sql('select count(*) from supabase_migrations.schema_migrations'), '45');
  assert.equal(sql(`select count(*) from public.family_members where
    encode(extensions.digest(user_id::text,'sha256'),'hex')='a943f6a8f8bbfb85773c91bd116a8460154293a073efad8b8444ac4eeacc10a3'`), '1');
  const originalBefore = originalSnapshot();
  const day = sql("select (clock_timestamp() at time zone 'Asia/Shanghai')::date-1");
  assert.match(day, /^\d{4}-\d{2}-\d{2}$/);
  for (const order of ['reward-first', 'settlement-first']) {
    const f = setup(); cat(f, day); const owner = f.users[0], session = randomUUID();
    sql(`begin; update public.wallets set miao_coins=-10 where owner_id='${owner}';
      insert into public.study_sessions(id,owner_id,started_at,recorded_until,confirmed,run_id)
      values('${session}','${owner}','${day} 12:00+08','${day} 12:05+08',true,'${session}'); commit;`);
    const reward = `${auth(owner)} select public.study_state()`;
    const settlement = `select public.settle_family_day('${f.home}','${day}')`;
    await race(f, 'wallets', order === 'reward-first' ? [reward, settlement] : [settlement, reward]);
    const state = snapshot(f, day);
    assert.equal(state.balance, -20); assert.equal(state.study, 10); assert.equal(state.studyEntries, 1);
    assert.equal(state.afterReward, 0); assert.equal(state.interest, 0); assert.equal(state.fee, 20);
    assert.equal(state.feeEntries, 1); assert.equal(state.settlements, 1);
    assert.equal(json(`select public.settle_family_day('${f.home}','${day}')`).status, 'already_settled');
    assert.deepEqual(snapshot(f, day), state);
    record(order, {finalBalance: -20, reward: 10, interest: 0, catFee: 20, duplicateSettlementUnchanged: true});
  }
  const repair = setup(2), episode = randomUUID(), window = randomUUID();
  const [a, b] = repair.users;
  sql(`begin; update public.wallets set miao_coins=-150 where owner_id in ('${a}','${b}');
    insert into public.repair_episodes(id,family_id,triggered_at,status)
      values('${episode}','${repair.home}',clock_timestamp()-interval '3 hours','active');
    insert into public.repair_windows(id,episode_id,cycle_no,starts_at,ends_at,status)
      values('${window}','${episode}',1,now()-interval '3 hours',now()+interval '69 hours','active');
    insert into public.study_sessions(id,owner_id,started_at,recorded_until,confirmed)
      values('${randomUUID()}','${a}',now()-interval '2 hours',now()-interval '1 hour',true),
        ('${randomUUID()}','${b}',now()-interval '1 hour',now(),true); commit;`);
  const completed = await race(repair, 'families', [a, b].map(owner => `${auth(owner)} select public.repair_state()`));
  assert.equal(completed.filter(state => state.status === 'completed').length, 1);
  assert.equal(completed.filter(state => state.status === 'none' && state.grace_through).length, 1);
  const audit = json(`select json_build_object('windows',(select count(*) from public.repair_windows where episode_id='${episode}'),
    'status',(select status from public.repair_episodes where id='${episode}'),
    'progress',(select progress_ms from public.repair_windows where id='${window}'),
    'completedAt',(select completed_at from public.repair_episodes where id='${episode}'))`);
  assert.equal(audit.windows, 1); assert.equal(audit.status, 'completed'); assert.equal(audit.progress, 7200000);
  for (const owner of [a, b]) {
    const result = json(`begin; ${auth(owner)} select public.study_state(); commit;`);
    assert.equal(result.wallet.miao_coins, -150);
  }
  assert.equal(sql(`select count(*) from public.wallet_entries where owner_id in ('${a}','${b}') and kind='study'`), '0');
  assert.equal(json(`select json_build_object('completedAt',completed_at) from public.repair_episodes where id='${episode}'`).completedAt, audit.completedAt);
  record('two members complete repair', {completedOnce: true, sharedProgressMs: 7200000, repairTimerRewards: 0});
  for (const order of ['purchase-first', 'fee-first']) {
    const f = setup(); cat(f, day); const owner = f.users[0], request = randomUUID();
    const product = json("select json_build_object('price',price,'limit',purchase_limit,'test',is_test,'active',active) from public.furniture_products where sku='wood-painting-mona'");
    assert.deepEqual(product, {price: 30, limit: 1, test: false, active: true});
    const buy = `${auth(owner)} select public.purchase_furniture('${request}','wood-painting-mona','${f.home}',1)`;
    const fee = `select public.settle_family_day('${f.home}','${day}')`;
    const results = await race(f, 'families', order === 'purchase-first' ? [buy, fee] : [fee, buy]);
    const receipt = results.find(value => value.request_id === request);
    const state = snapshot(f, day), bought = order === 'purchase-first';
    assert.equal(receipt.status, bought ? 'purchased' : 'rejected');
    if (!bought) assert.equal(receipt.reason, 'insufficient_balance');
    assert.equal(state.balance, bought ? -20 : 10); assert.equal(state.inventory, bought ? 1 : 0);
    assert.equal(state.purchaseEntries, state.inventory); assert.equal(state.fee, 20);
    assert.equal(state.feeEntries, 1); assert.equal(state.settlements, 1);
    const retry = json(`begin; ${auth(owner)} select public.purchase_furniture('${request}','wood-painting-mona','${f.home}',1); commit;`);
    assert.deepEqual(retry, receipt); assert.deepEqual(snapshot(f, day), state);
    record(order, {finalBalance: state.balance, inventory: state.inventory, purchaseStatus: receipt.status, retryUnchanged: true});
  }
  assert.equal(originalSnapshot(), originalBefore);
  report.originalAccountSnapshotUnchanged = true;
  report.fixtureFamiliesPreserved = fixtures.families.length;
  report.fixtureUsersCreated = fixtures.families.reduce((count, f) => count + f.users.length, 0);
  report.fixtureFamilyHashes = fixtures.families.map(f => createHash('sha256').update(f.home).digest('hex'));
  report.result = 'PASS';
}
run().catch(error => {
  report.failure = error instanceof assert.AssertionError ? 'Business contention assertion failed' : 'Local isolated SQL failed';
  report.failureLocation = error.stack?.split('\n').find(line => line.includes('test-business-contention.cjs:'))?.trim();
  console.error(report.failure); process.exitCode = 1;
}).finally(() => {
  report.finishedAt = new Date().toISOString();
  fs.writeFileSync(path.join(root, 'docs/evidence/m8-business-contention.json'), JSON.stringify(report, null, 2) + '\n');
});
