// Isolated localhost browser; no application login, production state or user profile.
const {chromium}=require('../../.tooling/browser/node_modules/playwright-core');
const assert=require('node:assert/strict');
const {writeFileSync}=require('node:fs');
const {join}=require('node:path');

(async()=>{
  const browser=await chromium.launch({executablePath:process.env.ROOM_STUDY_BROWSER||'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
  try{
    const page=await browser.newPage({viewport:{width:1440,height:1100}}),errors=[],badResponses=[];
    page.on('pageerror',e=>errors.push(e.message));
    page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
    page.on('response',r=>{if(r.status()>=400)badResponses.push([r.url(),r.status()]);});
    await page.goto('http://127.0.0.1:4181/design/room-structure-2026-10-05/');
    await page.waitForFunction(()=>window.roomStudy);
    let states=0;
    for(const a of['6','8','10']){
      await page.locator('#density').selectOption(a);
      for(const height of['1','1.5']){
        await page.locator('#height').selectOption(height);
        for(const id of['bookshelf','desk','chair','tree','bed']){
          await page.locator('#selected').selectOption(id);
          for(let turn=0;turn<2;turn++){
            await page.locator('#turn').click();
            const result=await page.evaluate(()=>{
              const s=window.roomStudy,occupied=new Set(),conflicts=[];
              for(const m of s.masks)for(const cell of m.cells){const key=cell.join(',');if(occupied.has(key))conflicts.push(key);occupied.add(key);}
              const escaped=s.parts.filter(k=>['bookshelf','desk','chair','tree','bed'].includes(k.kind)).filter(k=>{
                const owner=s.masks.find(m=>m.id===k.kind),epsilon=1e-9;
                return k.x<owner.x-epsilon||k.y<owner.y-epsilon||k.x+k.w>owner.x+owner.w+epsilon||k.y+k.d>owner.y+owner.d+epsilon;
              });
              return {conflicts,escaped,masks:s.masks.map(m=>m.cells),a:s.state.a};
            });
            assert.deepEqual(result.conflicts,[]);assert.deepEqual(result.escaped,[]);
            assert(result.masks.flat().every(([x,y])=>x>=0&&y>=0&&x<result.a&&y<result.a));states++;
          }
        }
      }
    }
    // Real UI controls, both L directions, and the empty corner remains unoccupied.
    await page.locator('#mode').selectOption('l');
    for(let i=0;i<2;i++){
      const count=await page.locator('#room [data-owner="l"]').count();assert.equal(count,3);
      await page.locator('#turn').click();
    }
    await page.locator('#mode').selectOption('empty');assert.equal(await page.locator('#room [data-owner]').count(),0);
    assert(await page.locator('#turn').isDisabled());
    for(const side of['left','right']){
      await page.locator('#'+side+'-window').uncheck();
      assert.equal(await page.locator('#room [data-piece="sill"]').count(),1);
      assert.equal(await page.evaluate(side=>window.roomStudy.state[side+'Window'],side),false);
      await page.locator('#'+side+'-window').check();
    }
    for(const id of['grid','axes','art','rug']){await page.locator('#'+id).uncheck();await page.locator('#'+id).check();}
    for(const reference of['empty','furnished','editing']){
      await page.locator('#reference').selectOption(reference);
      const loaded=await page.evaluate(async()=>{
        const image=document.querySelector('#reference-svg image'),url=image.getAttribute('href');
        const probe=new Image();probe.src=url;await probe.decode();return probe.naturalWidth;
      });assert(loaded>0);
    }
    await page.locator('#overlay').uncheck();assert.equal(await page.locator('#reference-svg line').count(),0);await page.locator('#overlay').check();
    await page.locator('#mode').selectOption('fixtures');await page.locator('#density').selectOption('8');await page.locator('#selected').selectOption('bookshelf');
    await page.locator('#height').selectOption('1');
    const low=await page.locator('#room').boundingBox();
    await page.locator('#height').selectOption('1.5');const high=await page.locator('#room').boundingBox();
    assert(Math.abs(low.width-high.width)<.1);assert(high.height>low.height);
    const fit=await page.evaluate(()=>window.roomStudy.fit);
    await page.screenshot({path:join(__dirname,'preview-desktop.png'),fullPage:true});
    await page.locator('#room').screenshot({path:join(__dirname,'structure-preview.png')});
    await page.setViewportSize({width:390,height:844});
    const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth);assert.equal(overflow,false);
    const mobile=await page.locator('#room').boundingBox();assert(mobile.width>300&&mobile.height>300);
    await page.screenshot({path:join(__dirname,'preview-mobile.png'),fullPage:true});
    assert.deepEqual(errors,[]);assert.deepEqual(badResponses,[]);
    const report={checkedStates:states,errors,badResponses,mobileOverflow:overflow,desktopFloorWidthPreserved:true,
      fit:{slope:fit.slope,elevationDegrees:fit.elevationDegrees,referenceWallHeight:fit.referenceWallHeight,
        maximumSampleResidual:Math.max(...fit.references.flatMap(r=>r.residuals.map(e=>Math.abs(e.errorPixels))))}};
    writeFileSync(join(__dirname,'verification.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));
  }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
