const {chromium}=require('../../.tooling/browser/node_modules/playwright-core');
const assert=require('node:assert/strict');
const {readFileSync,writeFileSync}=require('node:fs');
const {join}=require('node:path');
const dir=join(__dirname,'lunar-assets-v5'),standard=JSON.parse(readFileSync(join(__dirname,'room-standard-v1.json'),'utf8'));
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
    await page.locator('#lunar-room').screenshot({path:join(dir,'scene-night.png')});
    const beforeMode=await page.evaluate(()=>({facings:window.lunarStudy.state.facings,frames:window.lunarStudy.state.frames}));
    for(const mode of ['day','night','day','night']){
      await page.locator('#window-mode').selectOption(mode);await imagesReady();await validate();
      assert.equal(await page.locator('#lunar-room [data-window-view][data-mode="'+mode+'"]').count(),2);
      assert.deepEqual(await page.evaluate(()=>({facings:window.lunarStudy.state.facings,frames:window.lunarStudy.state.frames})),beforeMode);
      if(mode==='day')await page.locator('#lunar-room').screenshot({path:join(dir,'scene-day.png')});
    }
    await page.evaluate(()=>window.lunarStudy.setWindowMode('day'));await imagesReady();assert.equal(await page.locator('#window-mode').inputValue(),'day');
    await page.evaluate(()=>window.lunarStudy.setWindowMode('night'));await imagesReady();
    for(const side of ['left','right']){await page.locator('#'+side+'Window').uncheck();assert.equal(await page.locator('#lunar-room [data-window-view="'+side+'"]').count(),0);await page.locator('#'+side+'Window').check();}
    await page.locator('#grid').check();await page.locator('#axes').check();await validate();await page.locator('#lunar-room').screenshot({path:join(dir,'scene-grid.png')});
    for(const id of ids){await page.locator('#item').selectOption(id);await page.locator('#hide-item').click();assert.equal(await page.locator('#lunar-room [data-asset="'+id+'"]').count(),0);await page.locator('#hide-item').click();}
    for(const key of['leftWindow','rightWindow','art','rug']){await page.locator('#'+key).uncheck();await validate();await page.locator('#'+key).check();}
    await page.locator('#reset').click();
    // Every template is reusable at each fixed slot; artwork aspect stays unchanged.
    for(const id of['art-left-back','art-left-front','art-right-back','art-right-front']){
      await page.locator('#frame-slot').selectOption(id);
      for(const template of['landscape','portrait','square']){
        await page.locator('#frame-template').selectOption(template);
        for(const kind of['starry','pearl','']){await page.locator('#frame-artwork').selectOption(kind);await imagesReady();
          const f=await page.evaluate(id=>window.lunarStudy.frameLayouts.find(f=>f.id===id),id);
          assert(Math.abs(f.centerZ*8-4.05)<1e-10);assert(f.w<=.20&&f.h<=.20);assert(f.s-f.w/2>=0&&f.s+f.w/2<=1);
          const image=page.locator('#lunar-room [data-asset="'+id+'"] [data-artwork]');assert.equal(await image.count(),kind?1:0);
          if(kind)assert(Math.abs(Number(await image.getAttribute('data-original-aspect'))-(kind==='starry'?1424/1104:1191/1320))<1e-10);
        }
      }
    }
    await page.locator('#reset').click();
    // One combined alternate view. Never re-render the byte-exact furniture PNGs.
    for(const id of ids){await page.locator('#item').selectOption(id);await page.locator('#rotate').click();}
    await imagesReady();await page.locator('#lunar-room').screenshot({path:join(dir,'scene-alternate.png')});await page.locator('#reset').click();
    const exportPage=await browser.newPage();await exportPage.goto(base+'lunar.html');await exportPage.waitForFunction(()=>window.lunarStudy);
    const pairs=[...ids.map(id=>({id,files:[id+'-x.png',id+'-y.png']})),{id:'window',files:['window-left.png','window-right.png']}];
    const mirrorDifferences=await exportPage.evaluate(async({pairs,base})=>{const result={};for(const pair of pairs){const buffers=[];let w,h;for(const file of pair.files){const img=new Image();img.src=base+'lunar-assets-v5/'+file;await img.decode();w=img.width;h=img.height;const c=document.createElement('canvas');c.width=w;c.height=h;const ctx=c.getContext('2d');ctx.drawImage(img,0,0);buffers.push(ctx.getImageData(0,0,w,h).data);}let difference=0;for(let v=0;v<h;v++)for(let u=0;u<w;u++)for(let c=0;c<4;c++)if(buffers[0][(v*w+u)*4+c]!==buffers[1][(v*w+w-1-u)*4+c])difference++;result[pair.id]=difference;}return result;},{pairs,base});
    for(const difference of Object.values(mirrorDifferences))assert.equal(difference,0);
    // Export an audit contact sheet on pale and navy backgrounds, without modifying the assets.
    const entries=manifest.assets.filter(a=>a.category==='furniture');
    const sheet=await exportPage.evaluate(async({entries,base})=>{const canvas=document.createElement('canvas');canvas.width=1200;canvas.height=1100;const ctx=canvas.getContext('2d');ctx.fillStyle='#f4f1eb';ctx.fillRect(0,0,600,1100);ctx.fillStyle='#17283e';ctx.fillRect(600,0,600,1100);
      for(let i=0;i<entries.length;i++){const a=entries[i],img=new Image();img.src=base+'lunar-assets-v5/'+a.svg;await img.decode();const scale=Math.min(250/a.viewBox[2],175/a.viewBox[3]);for(const offset of[0,600]){const x=offset+(i%2)*300,y=Math.floor(i/2)*220;ctx.fillStyle=offset?'#f4e9d3':'#293e57';ctx.font='16px sans-serif';ctx.fillText(a.label+' '+a.facing,x+20,y+22);ctx.drawImage(img,x+150-a.viewBox[2]*scale/2,y+205-a.viewBox[3]*scale,a.viewBox[2]*scale,a.viewBox[3]*scale);}}return canvas.toDataURL('image/png').split(',')[1];},{entries,base});writeFileSync(join(dir,'edge-contact-sheet.png'),Buffer.from(sheet,'base64'));
    const frameSheet=await exportPage.evaluate(async({base})=>{const c=document.createElement('canvas');c.width=1080;c.height=440;const x=c.getContext('2d');x.fillStyle='#eeeae2';x.fillRect(0,0,c.width,c.height);for(const[i,key]of['landscape','portrait','square'].entries()){const img=new Image();img.src=base+'lunar-assets-v5/frame-'+key+'-left.svg';await img.decode();const scale=Math.min(290/img.width,320/img.height);x.drawImage(img,i*360+(360-img.width*scale)/2,70+(340-img.height*scale)/2,img.width*scale,img.height*scale);x.fillStyle='#293e57';x.font='20px sans-serif';x.textAlign='center';x.fillText(['横版 · 1.6 × 1.2 格','竖版 · 1.2 × 1.6 格','正方形 · 1.4 × 1.4 格'][i],i*360+180,40);}return c.toDataURL('image/png').split(',')[1];},{base});writeFileSync(join(dir,'frame-templates-sheet.png'),Buffer.from(frameSheet,'base64'));
    await page.screenshot({path:join(dir,'page-desktop.png'),fullPage:true});
    for(const width of[360,390]){await page.setViewportSize({width,height:844});await imagesReady();assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);const box=await page.locator('#lunar-room').boundingBox();assert(Math.abs(box.height/box.width-1073/1080)<.001);await validate();}
    await page.screenshot({path:join(dir,'page-mobile.png'),fullPage:true});
    assert.deepEqual(errors,[]);assert.deepEqual(badResponses,[]);
    assert(!requests.some(url=>/lunar-style-v[12]|lunar-style-draft|lunar-room-.*study/.test(url)));
    assert(requests.some(url=>/bookshelf-x.svg/.test(url))&&requests.some(url=>/bookshelf-y.svg/.test(url)));
    assert.equal(manifest.decorProduction.windowAndFrameImageSkins,false);
    assert.equal(manifest.decorProduction.roomGenerated,false);
    assert.equal(await page.locator('#lunar-room [data-asset="corner-transition"]').count(),0);assert.equal(manifest.cornerTrim,false);
    assert(!requests.some(url=>/frame-master|window-master/.test(url)));
    for(const svg of ['window-left.svg','window-right.svg','frame-square-flat.svg','frame-portrait-left.svg']){
      const source=readFileSync(join(dir,svg),'utf8');assert(!/<image|data:image/.test(source));assert((source.match(/<polygon/g)||[]).length>100);
    }
    for(const[key,svg]of[['wall','wall-left.svg'],['floor','floor.svg']])assert(readFileSync(join(dir,svg),'utf8').includes(readFileSync(join(dir,manifest.decorSkins[key].file)).toString('base64')));
    const unchanged=manifest.assets.filter(a=>['furniture','wall-material'].includes(a.category)||['floor','rug'].includes(a.id));
    for(const a of unchanged)for(const ext of ['svg','png'])assert(readFileSync(join(dir,a[ext])).equals(readFileSync(join(__dirname,'lunar-assets-v3',a[ext]))),a.id+' '+ext+' changed');
    const report={standardId:standard.id,geometryFrozen:true,allFacingCombinations:32,independentSvgCount:manifest.assets.length,transparentPngCount:manifest.assets.length,spriteComposition:true,positionsChanged:false,frameDimensionsUnchanged:true,nativeDecor:true,windowAndFrameImageSkins:false,cornerTrimRemoved:true,windowModes:['day','night'],modeChangesPreserveFurnitureAndFrames:true,modeApiVerified:true,hiddenWindowsHideScenery:true,sillChange:manifest.sillChange,acceptedMaterialsAndFurnitureUnchanged:true,frameTemplates:3,frameSlotTemplateArtworkChecks:36,mirrorDifferences,mobileWidths:[360,390],mobileOverflow:false,errors,badResponses,obsoleteRoomArtLoaded:false};
    writeFileSync(join(dir,'verification.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));
  }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
