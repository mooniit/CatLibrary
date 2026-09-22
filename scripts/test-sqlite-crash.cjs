// Desktop SQLite process-death probe; not Flutter/Android, power-loss or storage-hardware proof.
const {DatabaseSync} = require('node:sqlite');
const {spawn} = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
const oldRecord = JSON.stringify({start:'2026-09-21T15:59:00.000Z', checkpoint:'2026-09-21T15:59:30.000Z', running:true});
const newRecord = JSON.stringify({start:'2026-09-21T15:59:00.000Z', checkpoint:'2026-09-21T16:01:00.000Z', running:true});
if (process.argv[2] === '--writer') {
  const db = new DatabaseSync(process.argv[3]);
  db.exec('PRAGMA synchronous=FULL; BEGIN IMMEDIATE');
  db.prepare('UPDATE probe_records SET payload=? WHERE id=1').run(newRecord);
  if (process.argv[4] === 'committed') db.exec('COMMIT');
  process.stdout.write('READY\n');
  setInterval(() => {}, 1000); // Parent terminates this exact child, without graceful close.
} else {
  (async () => {
    const directory = fs.mkdtempSync(path.join(root, '.tooling/sqlite-crash-'));
    const evidence = {scope:'Windows Node SQLite abrupt writer termination; no mobile, power-loss or currency proof', startedAt:new Date().toISOString(), checks:[]};
    for (const phase of ['uncommitted', 'committed']) {
      const file = path.join(directory, `${phase}.sqlite`);
      const seed = new DatabaseSync(file);
      seed.exec('PRAGMA journal_mode=DELETE; PRAGMA synchronous=FULL; CREATE TABLE probe_records(id INTEGER PRIMARY KEY CHECK(id=1), payload TEXT NOT NULL)');
      seed.prepare('INSERT INTO probe_records VALUES(1,?)').run(oldRecord);
      seed.close();
      const child = spawn(process.execPath, [__filename, '--writer', file, phase], {stdio:['ignore','pipe','pipe'], windowsHide:true});
      let errorOutput = '';
      child.stderr.on('data', chunk => { errorOutput += chunk; });
      const closed = new Promise(resolve => child.once('close', (code, signal) => resolve({code, signal})));
      try {
        await new Promise((resolve, reject) => {
          const timeout = setTimeout(() => reject(new Error('Writer ready timeout')), 15000);
          let output = '';
          child.stdout.on('data', chunk => {
            output += chunk;
            if (output.includes('READY\n')) {clearTimeout(timeout); resolve();}
          });
          child.once('error', error => {clearTimeout(timeout); reject(error);});
          child.once('exit', () => {clearTimeout(timeout); reject(new Error(`Writer exited before termination: ${errorOutput}`));});
        });
        assert(child.kill('SIGKILL'), 'Must terminate the test writer');
        const exit = await closed;
        const recovered = new DatabaseSync(file);
        try {
          assert.equal(recovered.prepare('PRAGMA integrity_check').get().integrity_check, 'ok');
          const payload = recovered.prepare('SELECT payload FROM probe_records WHERE id=1').get().payload;
          assert.equal(payload, phase === 'committed' ? newRecord : oldRecord);
          evidence.checks.push({phase,result:'pass',termination:exit,recoveredCheckpoint:JSON.parse(payload).checkpoint});
        } finally {recovered.close();}
      } finally {
        if (child.exitCode === null && child.signalCode === null) {child.kill('SIGKILL'); await closed;}
      }
    }
    evidence.finishedAt = new Date().toISOString();
    fs.writeFileSync(path.join(root,'docs/evidence/m0-desktop-sqlite-crash.json'), JSON.stringify(evidence,null,2)+'\n');
    console.log('PASS 2/2: abrupt writer termination before and after COMMIT; integrity_check ok');
  })().catch(error => {console.error(error);process.exitCode=1;});
}
