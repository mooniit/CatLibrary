// Two family members concurrently start one pending 72-hour repair window.
const {execFileSync, spawn} = require('node:child_process');
const assert = require('node:assert/strict');

const a = '64000000-0000-0000-0000-000000000001';
const b = '64000000-0000-0000-0000-000000000002';
const episode = '64000000-0000-0000-0000-000000000010';
const docker = ['exec', 'supabase_db_CatLibrary', 'psql', '-U', 'postgres',
  '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-Atc'];
const sql = query => execFileSync('docker', [...docker, query],
  {encoding: 'utf8'}).trim();
function concurrent(query) {
  return new Promise((resolve, reject) => {
    const child = spawn('docker', [...docker, query]);
    let out = '', err = '';
    child.stdout.on('data', chunk => out += chunk);
    child.stderr.on('data', chunk => err += chunk);
    child.on('error', reject);
    child.on('close', code => code === 0 ? resolve(out.trim()) : reject(Error(err)));
  });
}

(async () => {
  let home;
  try {
    sql(`begin;
      insert into auth.users(id) values('${a}'),('${b}');
      set local role authenticated;
      select set_config('request.jwt.claims','{"sub":"${a}"}',true);
      select public.bootstrap_identity();
      select public.create_family();
      commit;`);
    home = sql(`select family_id from public.family_members where user_id='${a}'`);
    sql(`begin;
      insert into public.family_members(user_id,family_id) values('${b}','${home}');
      insert into public.repair_episodes(id,family_id,status)
        values('${episode}','${home}','pending');
      commit;`);
    sql(`begin; set local role authenticated;
      select set_config('request.jwt.claims','{"sub":"${b}"}',true);
      select public.bootstrap_identity(); commit;`);
    const call = user => `begin; set local role authenticated;
      select set_config('request.jwt.claims','{"sub":"${user}"}',true);
      select public.repair_state(); commit;`;
    const states = await Promise.all([concurrent(call(a)), concurrent(call(b))]);
    const windows = states.map(text => JSON.parse(text.split('\n').find(x => x.includes('window_id'))));
    assert.equal(windows[0].status, 'active');
    assert.equal(windows[1].status, 'active');
    assert.equal(windows[0].window_id, windows[1].window_id);
    assert.equal(sql(`select count(*) from public.repair_windows
      where episode_id='${episode}'`), '1');
    console.log('PASS simultaneous member reads share one 72-hour repair window');
  } finally {
    if (home) {
      sql(`begin;
        delete from public.repair_windows where episode_id='${episode}';
        delete from public.repair_episodes where id='${episode}';
        delete from public.family_members where family_id='${home}';
        delete from public.families where id='${home}';
        delete from public.wallet_entries where owner_id in ('${a}','${b}');
        delete from public.wallets where owner_id in ('${a}','${b}');
        delete from auth.users where id in ('${a}','${b}');
        commit;`);
    }
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
