const {chromium}=require('../.tooling/browser/node_modules/playwright-core');
const assert=require('node:assert/strict');
const fs=require('node:fs');
(async()=>{
 const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
 const errors=[],failed=[];
 try{
  const page=await browser.newPage({viewport:{width:920,height:1050}});
  page.on('pageerror',e=>errors.push(e.message));
  page.on('response',r=>{if(r.status()>=400&&!r.url().endsWith('favicon.ico'))failed.push(r.url())});
  await page.goto('http://127.0.0.1:21821/docs/plans/M5-prototype.html');
  await page.getByRole('button',{name:'模拟断网',exact:true}).click();
  assert((await page.locator('#saveState').textContent()).includes('原请求'));
  for(const theme of ['wood','lunar','royal']){
   await page.getByRole('combobox',{name:'套系',exact:true}).selectOption(theme);
   await page.waitForFunction(()=>[...document.images].every(i=>i.complete));
   assert(await page.evaluate(()=>[...document.images].every(i=>i.naturalWidth>0)),'broken image '+theme);
  }
  await page.getByRole('combobox',{name:'套系',exact:true}).selectOption('wood');
  await page.getByRole('heading',{name:'喵的图书馆',exact:true}).scrollIntoViewIfNeeded();
  await page.screenshot({path:'docs/evidence/m5-prototype-light.png'});
  await page.getByRole('button',{name:'切换白色／雾蓝夜晚',exact:true}).click();
  await page.screenshot({path:'docs/evidence/m5-prototype-night.png'});
  await page.setViewportSize({width:390,height:844});
  await page.getByRole('heading',{name:'喵的图书馆',exact:true}).scrollIntoViewIfNeeded();
  await page.screenshot({path:'docs/evidence/m5-prototype-mobile.png'});
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false,'horizontal overflow');
  assert.deepEqual(errors,[]);assert.deepEqual(failed,[]);
  fs.writeFileSync('docs/evidence/m5-prototype.json',JSON.stringify({scope:'Browser interface prototype only; no native/transactions proof',errors,failed,checks:['three theme images','offline message','light/night','390px no overflow']},null,2));
  console.log('PASS prototype themes, offline state, desktop/mobile and light/night; not native acceptance');
 }finally{await browser.close()}
})().catch(e=>{console.error(e.message);process.exitCode=1});
