const fs = require('node:fs');
const net = require('node:net');

function localHost(host) {
  const ip = host.replace(/^\[|\]$/g, '');
  if (ip === 'localhost' || ip.endsWith('.localhost') || ip.endsWith('.local')) return true;
  if (net.isIPv4(ip)) {
    const [a, b] = ip.split('.').map(Number);
    return a === 0 || a === 10 || a === 127 || a === 192 && b === 168 ||
      a === 172 && b >= 16 && b <= 31 || a === 169 && b === 254 ||
      a === 100 && b >= 64 && b <= 127;
  }
  return net.isIPv6(ip) && (ip === '::1' || ip === '::' ||
    /^(fc|fd|fe[89ab]|::ffff:)/i.test(ip));
}

function validateConfig(config, {remoteOnly = false} = {}) {
  const fields = ['SUPABASE_URL', 'SUPABASE_ANON_KEY'];
  if (!config || typeof config !== 'object' || Array.isArray(config) ||
      Object.keys(config).some(field => !fields.includes(field))) {
    throw new Error('正常安装包配置仅允许 SUPABASE_URL 和 SUPABASE_ANON_KEY。');
  }
  if (fields.some(field => typeof config[field] !== 'string' || !config[field].trim())) {
    throw new Error('请填写项目 URL 和公开密钥。');
  }
  let endpoint;
  try { endpoint = new URL(config.SUPABASE_URL); } catch (_) {
    throw new Error('项目 URL 必须是合法根地址。');
  }
  if (!['http:', 'https:'].includes(endpoint.protocol) || endpoint.username ||
      endpoint.password || endpoint.search || endpoint.hash || endpoint.pathname !== '/') {
    throw new Error('项目 URL 必须是无凭据、参数和路径的根地址。');
  }
  const local = localHost(endpoint.hostname);
  if (remoteOnly && local) throw new Error('这是本地或局域网服务，不能用于远程联网验收。');
  if (!local && endpoint.protocol !== 'https:') throw new Error('远程项目必须使用 HTTPS。');

  const key = config.SUPABASE_ANON_KEY;
  let keyType = 'publishable';
  if (!/^sb_publishable_[A-Za-z0-9_-]+$/.test(key)) {
    let claims;
    try {
      const parts = key.split('.');
      if (parts.length !== 3 || parts.some(part => !/^[A-Za-z0-9_-]+$/.test(part))) throw new Error();
      claims = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    } catch (_) { throw new Error('仅接受 publishable 或 anon 公开密钥。'); }
    if (claims?.role !== 'anon') throw new Error('仅接受 publishable 或 anon 公开密钥。');
    const hosted = endpoint.hostname.match(/^([a-z0-9]+)\.supabase\.co$/);
    if (hosted && claims.ref && claims.ref !== hosted[1]) {
      throw new Error('anon 密钥与项目 URL 不匹配。');
    }
    keyType = 'anon';
  }
  // This checks key type only. The service must verify that the key is valid.
  return {origin: endpoint.origin, environment: local ? 'local' : 'remote', keyType};
}

function readConfig(file) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '')); }
  catch (_) { throw new Error('无法读取配置 JSON；请检查文件路径和格式。'); }
}

module.exports = {validateConfig, readConfig};
if (require.main === module) {
  try {
    if (!process.argv[2]) throw new Error('用法：node scripts/cloud-config.cjs <配置文件> [--remote]');
    console.log(JSON.stringify(validateConfig(readConfig(process.argv[2]), {
      remoteOnly: process.argv.includes('--remote'),
    })));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
