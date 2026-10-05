// Isolated localhost validation of the one frozen room standard.
const {chromium}=require('../../.tooling/browser/node_modules/playwright-core');
const assert=require('node:assert/strict');
const {writeFileSync,readFileSync}=require('node:fs');
const {join}=require('node:path');
(async()=>{
  const browser=await chromium.launch({executablePath:process.env.ROOM_STUDY_BROWSER||'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
  try{
    const page=await browser.newPage({viewport:{width:1440,height:1100}}),errors=[],badResponses=[],artRequests=[];
    page.on('pageerror',e=>errors.push(e.message));
    page.on('console',m=>{if(m.type()==='error')errors.push(m.text());});
    page.on('response',r=>{if(r.status()>=400)badResponses.push([r.url(),r.status()]);});
    page.on('request',r=>{if(/lunar-style/.test(r.url()))artRequests.push(r.url());});
    await page.goto('http://127.0.0.1:4181/design/room-structure-2026-10-05/');
    await page.waitForFunction(()=>window.roomStudy);
    assert(await page.locator('#room').isVisible());
    assert.equal(await page.locator('#presentation,#height,#styled-room').count(),0);
    const standard=JSON.parse(readFileSync(join(__dirname,'room-standard-v1.json'),'utf8'));
    assert.deepEqual(await page.evaluate(()=>window.roomStudy.standard),standard);
    const initialBox=await page.locator('#room').boundingBox();
    async function stable(){
      assert.deepEqual(await page.evaluate(()=>window.roomStudy.camera),standard.camera);
      const box=await page.locator('#room').boundingBox();
      assert(Math.abs(box.width-initialBox.width)<.1&&Math.abs(box.height-initialBox.height)<.1);
    }
    let states=0;
    for(const id of['bookshelf','desk','chair','tree','bed']){
      await page.locator('#selected').selectOption(id);
      for(let turn=0;turn<2;turn++){
        await page.locator('#turn').click();
        const result=await page.evaluate(()=>{
          const s=window.roomStudy,occupied=new Set(),conflicts=[];
          for(const m of s.masks)for(const cell of m.cells){const key=cell.join(',');if(occupied.has(key))conflicts.push(key);occupied.add(key);}
          const escaped=s.parts.filter(k=>['bookshelf','desk','chair','tree','bed'].includes(k.kind)).filter(k=>{
            const owner=s.masks.find(m=>m.id===k.kind),e=1e-9;
            return k.x<owner.x-e||k.y<owner.y-e||k.x+k.w>owner.x+owner.w+e||k.y+k.d>owner.y+owner.d+e;
          });
          return {conflicts,escaped,a:s.state.a,masks:s.masks.map(m=>m.cells),centering:s.masks.map(m=>[m.x+m.w/2-(m.anchor[0]+m.cols/2)/8,m.y+m.d/2-(m.anchor[1]+m.rows/2)/8])};
        });
        assert.deepEqual(result.conflicts,[]);assert.deepEqual(result.escaped,[]);assert.equal(result.a,8);
        assert(result.centering.flat().every(v=>Math.abs(v)<1e-9));
        assert(result.masks.flat().every(([x,y])=>x>=0&&y>=0&&x<8&&y<8));await stable();states++;
      }
    }
    const layout=await page.evaluate(()=>({rug:window.roomStudy.rug,bookHeight:window.roomStudy.masks.find(m=>m.id==='bookshelf').h,slots:window.roomStudy.slots}));
    assert.deepEqual([layout.rug.x,layout.rug.y,layout.rug.w,layout.rug.d],[1/8,1/8,6/8,6/8]);assert.equal(layout.bookHeight,3/8);
    for(const wall of['left','right']){
      const win=layout.slots.find(s=>s.wall===wall&&s.type==='window');assert.equal(win.s,.5);
      assert(Math.abs((win.z-.008-layout.bookHeight)*8-.136)<1e-12);
      for(const s of layout.slots.filter(s=>s.wall===wall&&s.type==='art'))assert(Math.abs(s.z+s.h/2-(win.z+win.h/2))<1e-12);
    }
    await page.locator('#mode').selectOption('l');
    for(let i=0;i<2;i++){assert.equal(await page.locator('#room [data-owner="l"]').count(),3);await page.locator('#turn').click();await stable();}
    await page.locator('#mode').selectOption('empty');assert.equal(await page.locator('#room [data-owner]').count(),0);assert(await page.locator('#turn').isDisabled());await stable();
    for(const side of['left','right']){
      await page.locator('#'+side+'-window').uncheck();assert.equal(await page.locator('#room [data-piece="sill"]').count(),1);await stable();
      await page.locator('#'+side+'-window').check();
    }
    for(const id of['grid','axes','art','rug']){await page.locator('#'+id).uncheck();await stable();await page.locator('#'+id).check();}
    for(const reference of['empty','furnished','editing']){
      await page.locator('#reference').selectOption(reference);
      assert(await page.evaluate(async()=>{const i=new Image();i.src=document.querySelector('#reference-svg image').getAttribute('href');await i.decode();return i.naturalWidth>0;}));await stable();
    }
    await page.locator('#overlay').uncheck();assert.equal(await page.locator('#reference-svg line').count(),0);await page.locator('#overlay').check();
    await page.locator('#mode').selectOption('fixtures');await page.locator('#selected').selectOption('bookshelf');await stable();
    await page.screenshot({path:join(__dirname,'preview-desktop.png'),fullPage:true});
    await page.locator('#room').screenshot({path:join(__dirname,'structure-preview.png')});
    await page.locator('#grid').uncheck();await page.locator('#axes').uncheck();
    await page.locator('#room').screenshot({path:join(__dirname,'structure-clean.png')});
    await page.locator('#grid').check();await page.locator('#axes').check();
    for(const width of[360,390]){
      await page.setViewportSize({width,height:844});
      assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
      const box=await page.locator('#room').boundingBox();assert(box.width>300&&box.height>300);
      assert(Math.abs(box.height/box.width-1073/1080)<.001);assert.deepEqual(await page.evaluate(()=>window.roomStudy.camera),standard.camera);
    }
    await page.screenshot({path:join(__dirname,'preview-mobile.png'),fullPage:true});
    assert.deepEqual(errors,[]);assert.deepEqual(badResponses,[]);assert.deepEqual(artRequests,[]);
    const report={standardId:standard.id,checkedFacingStates:states,geometryFrozen:true,errors,badResponses,obsoleteArtLoaded:false,
      mobileWidths:[360,390],mobileOverflow:false,selectedGrid:8,rugFootprint:'central 6x6',bookcaseHeightCells:3,windowBottomCells:3.2,sillClearanceCells:.136,wallDecorCenterCells:4.05};
    writeFileSync(join(__dirname,'verification.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify(report));
  }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
