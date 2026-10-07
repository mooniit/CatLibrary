const fs = require('node:fs');
const path = require('node:path');
const {createHash} = require('node:crypto');
const {validateConfig, readConfig} = require('./cloud-config.cjs');
const root = path.resolve(__dirname, '..');

function migrationManifest() {
  const directory = path.join(root, 'supabase/migrations');
  return fs.readdirSync(directory).filter(file => /^\d+_.+\.sql$/.test(file)).sort()
    .map(file => ({file, sha256: createHash('sha256').update(fs.readFileSync(path.join(directory, file))).digest('hex')}));
}

async function probeServices(config, {fetcher = fetch, remoteOnly = true} = {}) {
  const endpoint = validateConfig(config, {remoteOnly});
  const checks = [];
  for (const [name, route] of [['auth', '/auth/v1/settings'], ['rest', '/rest/v1/']]) {
    try {
      const response = await fetcher(endpoint.origin + route, {
        method: 'GET', redirect: 'error',
        headers: {apikey: config.SUPABASE_ANON_KEY, Accept: 'application/json'},
        signal: AbortSignal.timeout(12000),
      });
      if (response.status !== 200) {
        checks.push({service: name, passed: false, httpStatus: response.status});
        await response.body?.cancel();
        continue;
      }
      const body = await response.json();
      const passed = name === 'auth'
        ? body?.external?.anonymous_users === true && body.disable_signup === false
        : !!(body?.swagger || body?.openapi) && !!body.paths && typeof body.paths === 'object';
      checks.push({service: name, passed, httpStatus: 200,
        ...(name === 'auth' ? {anonymousSignupEnabled: passed} : {})});
    } catch (_) {
      // Never log request headers, server bodies or exception text containing credentials.
      checks.push({service: name, passed: false, reason: '请求失败、超时或返回格式不正确'});
    }
  }
  return {...endpoint, checks, readOnlyPreflightPassed: checks.every(check => check.passed),
    migrationsVerified: false, originalIdentityMigrated: false, mobileInternetVerified: false};
}

module.exports = {migrationManifest, probeServices};
if (require.main === module) {
  (async () => {
    const args = process.argv.slice(2);
    let file, probe = false;
    for (let i = 0; i < args.length; i++) {
      if (args[i] === '--config' && args[i + 1]) file = args[++i];
      else if (args[i] === '--probe') probe = true;
      else throw new Error('用法：node scripts/cloud-preflight.cjs [--config <配置文件>] [--probe]');
    }
    if (probe && !file) throw new Error('只读联网检查需要先提供云端公开配置。');
    const config = file ? readConfig(file) : null;
    const migrations = migrationManifest();
    const report = {
      generatedAt: new Date().toISOString(),
      status: config ? 'awaiting_remote_verification' : 'awaiting_cloud_project',
      migrationCount: migrations.length, migrations,
      seedIncluded: false, databaseModified: false, accountsCreated: false,
      remoteProbePerformed: probe,
      ...(config ? {configuration: validateConfig(config, {remoteOnly: true})} : {}),
      ...(probe ? {services: await probeServices(config)} : {}),
    };
    if (probe) report.status = report.services.readOnlyPreflightPassed ? 'read_only_preflight_passed' : 'read_only_preflight_failed';
    const directory = path.join(root, '.tooling');
    fs.mkdirSync(directory, {recursive: true});
    const reportFile = path.join(directory, `cloud-preflight-${Date.now()}.json`);
    fs.writeFileSync(reportFile, JSON.stringify(report, null, 2) + '\n', {flag: 'wx'});
    console.log(JSON.stringify({status: report.status, migrationCount: migrations.length, report: reportFile}));
    if (probe && !report.services.readOnlyPreflightPassed) process.exitCode = 1;
  })().catch(error => { console.error(error.message); process.exitCode = 1; });
}
