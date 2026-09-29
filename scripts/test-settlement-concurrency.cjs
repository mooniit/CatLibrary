// Two actual database connections race on one family/day; fixture is removed.
const {execFileSync, spawn} = require('node:child_process');
const assert = require('node:assert/strict');

const user = '63000000-0000-0000-0000-000000000001';
const db = 'supabase_db_CatLibrary';
function sql(query) {
  return execFileSync('docker', ['exec', db, 'psql', '-U', 'postgres', '-d',
    'postgres', '-v', 'ON_ERROR_STOP=1', '-Atc', query],
  {encoding: 'utf8'}).trim();
}
function concurrent(query) {
  return new Promise((resolve, reject) => {
    const child = spawn('docker', ['exec', db, 'psql', '-U', 'postgres', '-d',
      'postgres', '-v', 'ON_ERROR_STOP=1', '-Atc', query]);
    let out = '', err = '';
    child.stdout.on('data', part => out += part);
    child.stderr.on('data', part => err += part);
    child.on('error', reject);
    child.on('close', code => code === 0 ? resolve(out.trim()) : reject(Error(err)));
  });
}

(async () => {
  let home;
  try {
    sql(`begin;
      insert into auth.users(id) values('${user}');
      set local role authenticated;
      select set_config('request.jwt.claims','{"sub":"${user}"}',true);
      select public.bootstrap_identity();
      select public.create_family();
      select public.adopt_cat('black_short','并发结算测试猫');
      commit;`);
    home = sql(`select family_id from public.family_members where user_id='${user}'`);
    sql(`update public.wallets set miao_coins=0 where owner_id='${user}'`);
    const day = sql("select (now() at time zone 'Asia/Shanghai')::date");
    const call = `select public.settle_family_day('${home}','${day}')`;
    const outcomes = await Promise.all([concurrent(call), concurrent(call)]);
    assert(outcomes.some(x => x.includes('"status": "settled"')));
    assert(outcomes.some(x => x.includes('"status": "already_settled"')));
    assert.equal(sql(`select miao_coins from public.wallets where owner_id='${user}'`), '-20');
    assert.equal(sql(`select count(*) from public.wallet_entries where owner_id='${user}'
      and kind='cat_fee' and business_day='${day}'`), '1');
    assert.equal(sql(`select count(*) from public.daily_cat_charges where owner_id='${user}'
      and business_day='${day}'`), '1');
    console.log('PASS two simultaneous settlement calls: one fee, one ledger entry');
  } finally {
    if (home) {
      sql(`begin;
        delete from public.proxy_payment_notices where payer_id='${user}';
        delete from public.daily_cat_charges where owner_id='${user}';
        delete from public.daily_interest_charges where owner_id='${user}';
        delete from public.family_daily_settlements where family_id='${home}';
        delete from public.wallet_entries where owner_id='${user}';
        delete from public.cats where family_id='${home}';
        delete from public.family_members where family_id='${home}';
        delete from public.families where id='${home}';
        delete from public.wallets where owner_id='${user}';
        delete from auth.users where id='${user}';
        commit;`);
    }
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
