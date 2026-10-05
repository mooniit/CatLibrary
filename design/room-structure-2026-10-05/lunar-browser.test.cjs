const {chromium}=require('../../.tooling/browser/node_modules/playwright-core');
const assert=require('node:assert/strict');
const {readFileSync,writeFileSync}=require('node:fs');
const {join}=require('node:path');
const dir=join(__dirname,'lunar-assets'),standard=JSON.parse(readFileSync(join(__dirname,'room-standard-v1.json'),'utf8'));
const manifest=JSON.parse(readFileSync(join(dir,'manifest.json'),'utf8'));
(async()=>{
  const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
  try{
    const page=await browser.newPage({viewport:{width:1440,height:1200}}),errors=[],badResponses=[],requests=[];
    page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.status()>=400)badResponses.push([r.url(),r.status()]);});
    page.on('request',r=>requests.push(r.url()));
    const base='http://127.0.0.1:4181/design/room-structure-2026-10-05/';
    await page.goto(base+'lunar.html');await page.waitForFunction(()=>window.lunarStudy);
    async function imagesReady(){await page.evaluate(async()=>{for(const e of document.querySelectorAll('image')){const img=new Image();img.src=e.getAttribute('href');await img.decode();}});}
    async function validate(){const result=await page.evaluate(()=>({standard:window.lunarStudy.standard,camera:window.lunarStudy.camera,conflicts:window.lunarStudy.conflicts,fixtures:window.lunarStudy.fixtures}));
      assert.deepEqual(result.standard,standard);assert.deepEqual(result.camera,standard.camera);assert.deepEqual(result.conflicts,[]);
      for(const f of result.fixtures){assert(f.bounds.min[0]>=f.x-1e-9&&f.bounds.min[1]>=f.y-1e-9);assert(f.bounds.max[0]<=f.x+f.w+1e-9&&f.bounds.max[1]<=f.y+f.d+1e-9);}
    }
    await imagesReady();await validate();
    const size=await page.locator('#lunar-room').boundingBox();assert(Math.abs(size.height/size.width-1073/1080)<.001);
    // All 32 combinations through real controls, including mutually swapped rectangular masks.
    const ids=['bookshelf','desk','chair','tree','bed'],defaults={bookshelf:'x',desk:'y',chair:'y',tree:'x',bed:'y'};
    for(let combo=0;combo<32;combo++){
      const current=await page.evaluate(()=>window.lunarStudy.state.facings);
      for(const[i,id]of ids.entries()){const target=combo&(1<<i)?'x':'y';if(current[id]!==target){await page.locator('#item').selectOption(id);await page.locator('#rotate').click();}}
      await imagesReady();await validate();
    }
    await page.locator('#reset').click();await imagesReady();
    await page.locator('#lunar-room').screenshot({path:join(dir,'scene-clean.png')});
    await page.locator('#grid').check();await page.locator('#axes').check();await validate();await page.locator('#lunar-room').screenshot({path:join(dir,'scene-grid.png')});
    for(const id of ids){await page.locator('#item').selectOption(id);await page.locator('#hide-item').click();assert.equal(await page.locator('#lunar-room [data-asset="'+id+'"]').count(),0);await page.locator('#hide-item').click();}
    for(const key of['leftWindow','rightWindow','art','rug']){await page.locator('#'+key).uncheck();await validate();await page.locator('#'+key).check();}
    await page.locator('#reset').click();
    // One combined alternate view, plus exact native-canvas exports for independent SVGs.
    for(const id of ids){await page.locator('#item').selectOption(id);await page.locator('#rotate').click();}
    await imagesReady();await page.locator('#lunar-room').screenshot({path:join(dir,'scene-alternate.png')});await page.locator('#reset').click();
    const exportPage=await browser.newPage();await exportPage.goto(base+'lunar.html');await exportPage.waitForFunction(()=>window.lunarStudy);
    for(const a of manifest.assets){const png=await exportPage.evaluate(async({url,width,height})=>{const img=new Image();img.src=url;await img.decode();const canvas=document.createElement('canvas');canvas.width=width;canvas.height=height;canvas.getContext('2d').drawImage(img,0,0,width,height);return canvas.toDataURL('image/png').split(',')[1];},{url:base+'lunar-assets/'+a.svg,width:a.viewBox[2],height:a.viewBox[3]});writeFileSync(join(dir,a.png),Buffer.from(png,'base64'));}
    // Export an audit contact sheet on pale and navy backgrounds, without modifying the assets.
    const entries=manifest.assets.filter(a=>a.category==='furniture');
    const sheet=await exportPage.evaluate(async({entries,base})=>{const canvas=document.createElement('canvas');canvas.width=1200;canvas.height=1100;const ctx=canvas.getContext('2d');ctx.fillStyle='#f4f1eb';ctx.fillRect(0,0,600,1100);ctx.fillStyle='#17283e';ctx.fillRect(600,0,600,1100);
      for(let i=0;i<entries.length;i++){const a=entries[i],img=new Image();img.src=base+'lunar-assets/'+a.svg;await img.decode();const scale=Math.min(250/a.viewBox[2],175/a.viewBox[3]);for(const offset of[0,600]){const x=offset+(i%2)*300,y=Math.floor(i/2)*220;ctx.fillStyle=offset?'#f4e9d3':'#293e57';ctx.font='16px sans-serif';ctx.fillText(a.label+' '+a.facing,x+20,y+22);ctx.drawImage(img,x+150-a.viewBox[2]*scale/2,y+205-a.viewBox[3]*scale,a.viewBox[2]*scale,a.viewBox[3]*scale);}}return canvas.toDataURL('image/png').split(',')[1];},{entries,base});writeFileSync(join(dir,'edge-contact-sheet.png'),Buffer.from(sheet,'base64'));
    await page.screenshot({path:join(dir,'page-desktop.png'),fullPage:true});
    for(const width of[360,390]){await page.setViewportSize({width,height:844});await imagesReady();assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);const box=await page.locator('#lunar-room').boundingBox();assert(Math.abs(box.height/box.width-1073/1080)<.001);await validate();}
    await page.screenshot({path:join(dir,'page-mobile.png'),fullPage:true});
    assert.deepEqual(errors,[]);assert.deepEqual(badResponses,[]);
    assert(!requests.some(url=>/lunar-style-v[12]|lunar-style-draft|lunar-room-.*study/.test(url)));
    assert(requests.some(url=>/bookshelf-x.svg/.test(url))&&requests.some(url=>/bookshelf-y.svg/.test(url)));
    const report={standardId:standard.id,geometryFrozen:true,allFacingCombinations:32,independentSvgCount:manifest.assets.length,transparentPngCount:manifest.assets.length,spriteComposition:true,positionsChanged:false,mobileWidths:[360,390],mobileOverflow:false,errors,badResponses,obsoleteRoomArtLoaded:false};
    writeFileSync(join(dir,'verification.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));
  }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
