const assert = require('node:assert/strict');
const p = require('./test-android-probe.cjs');
const physical = process.argv.includes('--physical');
const prefix = process.argv.includes('--m6-v2') ? (physical ? 'm6-v2-phone' : 'm6-v2-emulator')
  : process.argv.includes('--m6') ? (physical ? 'm6-phone' : 'm6-emulator')
  : process.argv.includes('--m5') ? (physical ? 'm5-phone' : 'm5-emulator')
  : physical ? 'lunar-restored-phone' : 'lunar-restored-emulator';
function labels() { return p.nodes().map(n => n['content-desc'] || n.text || '').filter(Boolean); }
async function screenshot(name) {
  p.run('shell', 'screencap', '-p', '/sdcard/' + name + '.png');
  p.run('pull', '/sdcard/' + name + '.png', 'docs/evidence/' + name + '.png');
}
(async () => {
  let ready = false;
  for (let i = 0; i < 12; i++) {
    const current = labels();
    if (current.some(s => s.startsWith('猫窝\nTab'))) { ready = true; break; }
    await p.pause(900);
  }
  assert(ready, 'Configured startup did not reach home. Preview fallback is not allowed.');
  await p.tap('猫窝', true);
  assert(!labels().some(s => s.includes('交互预览')), 'Unexpected preview shell');
  await screenshot(prefix + '-home');
  await p.tap('任务板', true);
  p.shown('今日书签');
  assert(!labels().some(s => s.includes('无真实资产')), 'Preview tasks must not pass');
  await screenshot(prefix + '-tasks');
  await p.tap('学习记录');
  p.shown('留下的时间');
  await screenshot(prefix + '-task-history');
  p.run('shell', 'input', 'keyevent', '4');
  await p.pause(500);
  p.shown('今日书签');
  console.log('PASS real TaskBoardPage and separate history; no task started or confirmed');
  await p.tap('自习', true);
  p.shown('倒计时'); p.shown('今日自习');
  assert(!labels().some(s => s.includes('计时技术探针')), 'Preview timer must not pass');
  await screenshot(prefix + '-study');
  await p.tap('倒计时');
  p.shown('常用计时器');
  await screenshot(prefix + '-countdown');
  await p.tap('计时');
  console.log('PASS real StudyPage, timer modes/presets visible');
  await p.tap('阅读', true); p.shown('阅读功能筹备中');
  await p.tap('猫窝', true);
  console.log('PASS four-page navigation; no timers, purchases or data clearing performed');
  console.log(p.run('shell', 'dumpsys', 'package', 'com.catlibrary.cat_library_demo').split('\n').filter(s => /versionCode|versionName/.test(s)).join('\n'));
})().catch(error => { console.error(error.message); process.exitCode = 1; });
