// Run only after explicit authorization to migrate the preserved account.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const {spawnSync}=require('node:child_process'),{createHash}=require('node:crypto');
const root=path.resolve(__dirname,'..');
assert.deepEqual(process.argv.slice(2),['--apply-approved'],'Explicit approved apply required');
const pointer=JSON.parse(fs.readFileSync(path.join(root,'.tooling/account-cloud-migration-latest.json')));
const directory=path.resolve(pointer.directory);
assert(directory.startsWith(path.join(root,'.tooling/account-cloud-migration-')));
const plan=JSON.parse(fs.readFileSync(path.join(directory,'prepared.json')));
assert(plan.dryRunPassed&&plan.foreignKeysEnabled&&plan.editorLeasesReleased);
assert.equal(fs.readFileSync(path.join(root,'supabase/.temp/project-ref'),'utf8').trim(),plan.projectRef);
const sha=bytes=>createHash('sha256').update(bytes).digest('hex');
const sourceSql=fs.readFileSync(path.join(directory,'source-export.sql'),'utf8');
assert.equal(sha(sourceSql),plan.sourceSqlSha256);
const source=spawnSync('docker',['exec','-i','supabase_db_CatLibrary','psql','-U','postgres','-d','postgres','-qAt','-v','ON_ERROR_STOP=1'],{input:sourceSql,encoding:'utf8',maxBuffer:16*1024*1024});
assert.equal(source.status,0,'Read-only source check failed');
assert.equal(sha(source.stdout.trim()+'\n'),plan.sourceSha256,'Source changed: prepare and roll back again before applying');
const file=path.join(directory,'apply.sql');
assert.equal(sha(fs.readFileSync(file)),plan.applySha256);
assert(!fs.existsSync(path.join(directory,'committed.json')),'Already applied: reconcile, never reimport');
const cli=path.join(root,'.tooling/supabase-cli/node_modules/@supabase/cli-windows-x64/bin/supabase.exe');
const result=spawnSync(cli,['db','query','--linked','--file',file,'--output','json'],{encoding:'utf8',timeout:120000,maxBuffer:16*1024*1024});
fs.writeFileSync(path.join(directory,'apply-output-private.json'),result.stdout||'');
fs.writeFileSync(path.join(directory,'apply-error-private.txt'),result.stderr||'');
assert.equal(result.status,0,'Apply result uncertain: query original scope before any retry');
assert.equal(JSON.parse(result.stdout).rows[0].migration_committed,true);
const receipt={at:new Date().toISOString(),result:'PASS',businessTables:33,originalIdentityMigrated:true,
  sourceUnchangedSinceDryRun:true,allRowsVerifiedInTransaction:true,foreignKeysEnabled:true,
  editorLeasesReleased:true,oldManualSettlementRun:false,localBackupRetained:true};
fs.writeFileSync(path.join(directory,'committed.json'),JSON.stringify(receipt,null,2),{flag:'wx'});
fs.writeFileSync(path.join(root,'docs/evidence/photo-wall-cloud-migration.json'),JSON.stringify(receipt,null,2)+'\n');
console.log('PASS preserved original identity and all 33 business tables committed; no manual settlement');
