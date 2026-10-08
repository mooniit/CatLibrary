const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const allowed = new Set(['idle-preview.html', 'calico-standing-idle-v2.png', 'calico-sleeping-idle-v4.png']);
const server = http.createServer((req, res) => {
  const name = new URL(req.url, 'http://127.0.0.1').pathname.slice(1) || 'idle-preview.html';
  if (!allowed.has(name)) { res.writeHead(404); res.end(); return; }
  const file = path.join(__dirname, name);
  res.setHeader('Content-Type', name.endsWith('.html') ? 'text/html; charset=utf-8' : 'image/png');
  res.setHeader('Cache-Control', 'no-store');
  const stream = fs.createReadStream(file);
  stream.on('error', () => { res.destroy(); });
  stream.pipe(res);
});
server.on('error', error => { console.error(error.message); process.exitCode = 1; });
server.listen(8158, '127.0.0.1', () => console.log('http://127.0.0.1:8158/'));
