// Real asset and preview checks; does not touch the native application.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import assert from 'node:assert/strict';
import {fixtures,orient,connected,validCells,slots} from '../room-structure-2026-10-05/geometry.mjs';
import {casing,windowModel,templates} from './theme-geometry.mjs';
const dir=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(dir,'../..'),url='http://127.0.0.1:4181/design/room-themes-2026-10-06/';
const {chromium}=createRequire(path.join(root,'.tooling/browser/package.json'))('playwright-core');
const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
const page=await browser.newPage({viewport:{width:1500,height:1250}}),errors=[],missing=[];page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.status()>=400)missing.push(r.url());});
const report={geometry:[],sprites:[],frames:[],browser:[],screenshots:[]};
try{
 for(const theme of ['wood','royal']){
  const manifest=JSON.parse(await fs.readFile(path.join(dir,theme,'manifest.json'),'utf8'));assert.equal(manifest.standard,'room-standard-v1');assert.equal(manifest.assets.length,31);
  const views=manifest.assets.filter(a=>a.id.startsWith('view-'));for(const v of views){const [a,b,c,d]=v.imageMatrix;assert(a*d-b*c>0,'Scenery must not be mirrored');assert(v.crop[0]+v.crop[2]<=1536&&v.crop[1]+v.crop[3]<=1024);}assert.notDeepEqual(views[0].crop,views[2].crop);
  for(const [key,t]of Object.entries(templates)){const m=casing(theme,t.w,t.h);for(const f of m.faces)for(const [u,v,z]of f.points){assert(u>=-.00401&&u<=.02201);assert(v>=-1e-8&&v<=t.w+1e-8);assert(z>=-1e-8&&z<=t.h+1e-8);}report.geometry.push(theme+' '+key+' profile inside template envelope');}
  for(const slot of slots.filter(s=>s.type==='window')){const points=windowModel(theme,slot).faces.flatMap(f=>f.points);assert(Math.abs(Math.min(...points.map(p=>p[2]))-(slot.z-.008))<1e-8);assert(points.every(p=>p[slot.wall==='left'?0:1]<=.06401));report.geometry.push(theme+' '+slot.id+' sill clearance .136 cells preserved');}
  await page.goto(url+'?theme='+theme,{waitUntil:'networkidle'});await page.waitForFunction(()=>window.themeStudy);
  for(const key of Object.keys(templates)){const url='data:image/png;base64,'+(await fs.readFile(path.join(dir,theme,`frame-${key}-flat.png`))).toString('base64');const audit=await page.evaluate(async url=>{const im=new Image();im.src=url;await im.decode();const c=document.createElement('canvas');c.width=im.width;c.height=im.height;const ctx=c.getContext('2d');ctx.drawImage(im,0,0);const rgba=ctx.getImageData(0,0,c.width,c.height).data;let gold=0;for(let i=0;i<rgba.length;i+=4)if(rgba[i+3]>=32&&rgba[i]>180&&rgba[i+1]>150&&rgba[i+2]<170)gold++;return{transparentCenter:ctx.getImageData(Math.floor(c.width/2),Math.floor(c.height/2),1,1).data[3],visibleGoldPixels:gold};},url);assert.equal(audit.transparentCenter,0,'Reusable frame must have a clear opening');if(theme==='royal')assert(audit.visibleGoldPixels>30,'Raised front ornaments must render');report.frames.push({theme,key,...audit});}
  for(const f of fixtures){const records=manifest.assets.filter(a=>a.id===f.id+'-x'||a.id===f.id+'-y'),sources=await Promise.all(records.map(async a=>({a,url:'data:image/png;base64,'+(await fs.readFile(path.join(dir,theme,a.png))).toString('base64')})));
   const audit=await page.evaluate(async sources=>{
    const rasters=[];for(const {url,a}of sources){const im=new Image();im.src=url;await im.decode();const c=document.createElement('canvas');c.width=im.width;c.height=im.height;const ctx=c.getContext('2d',{willReadFrequently:true});ctx.drawImage(im,0,0);const rgba=ctx.getImageData(0,0,c.width,c.height).data;let overflow=0,edge=0,count=0;const poly=a.projectionHull;
     for(let y=0;y<c.height;y++)for(let x=0;x<c.width;x++){const alpha=rgba[(y*c.width+x)*4+3];if(alpha>=4&&(x===0||y===0||x===c.width-1||y===c.height-1))edge++;if(alpha>=32){count++;const inside=poly.every((p,i)=>{const q=poly[(i+1)%poly.length];return(q[0]-p[0])*(y+.5-p[1])-(q[1]-p[1])*(x+.5-p[0])>=-1.1*Math.hypot(q[0]-p[0],q[1]-p[1]);});if(!inside)overflow++;}}
     rasters.push({rgba,w:c.width,h:c.height,overflow,edge,count});}
    const [a,b]=rasters;let mirrorDifferences=0;for(let y=0;y<a.h;y++)for(let x=0;x<a.w;x++)for(let k=0;k<4;k++)if(a.rgba[(y*a.w+x)*4+k]!==b.rgba[(y*a.w+(a.w-1-x))*4+k])mirrorDifferences++;
    return{mirrorDifferences,rasters:rasters.map(({rgba,...r})=>r)};
   },sources);
   assert.equal(audit.mirrorDifferences,0,theme+' '+f.id+' mirror must preserve all pixels');for(const r of audit.rasters){assert.equal(r.edge,0,'Cropped edge '+f.id);assert.equal(r.overflow,0,'Projected outside prism '+theme+' '+f.id);assert(r.count>100);}report.sprites.push({theme,id:f.id,...audit});
  }
  for(let mask=0;mask<32;mask++){const facings=Object.fromEntries(fixtures.map((f,i)=>[f.id,mask&(1<<i)?'y':'x'])),occupied=new Set();for(const f of fixtures.map(f=>orient(f,facings[f.id]))){assert(connected(f.cells)&&validCells(f.cells,8));assert(f.x>=0&&f.y>=0&&f.x+f.w<=1&&f.y+f.d<=1);for(const cell of f.cells){const k=cell.join(',');assert(!occupied.has(k),'Occupancy conflict '+mask);occupied.add(k);}}
   await page.evaluate(facings=>window.themeStudy.setState({facings}),facings);assert.equal(await page.locator('#room [data-facing]').count(),5);assert.deepEqual(await page.evaluate(()=>window.themeStudy.conflicts),[]);
  }report.browser.push({theme,orientationCombinations:32});
  for(const template of Object.keys(templates))for(const slot of slots.filter(s=>s.type==='art')){await page.selectOption('#frame-slot',slot.id);await page.selectOption('#frame-template',template);for(const picture of ['starry','pearl','']){await page.selectOption('#picture',picture);assert.equal(await page.locator(`#room [data-asset="${slot.id}"] [data-frame="${template}"]`).count(),1);assert.equal(await page.locator(`#room [data-asset="${slot.id}"] [data-artwork]`).count(),picture?1:0);if(picture){const determinant=await page.locator(`#room [data-asset="${slot.id}"] [data-artwork]`).evaluate(el=>{const values=el.getAttribute('transform').slice(7,-1).split(' ').map(Number);return values[0]*values[3]-values[1]*values[2];});assert(determinant>0,'Artwork must not be mirrored');}}}
  report.browser.push({theme,frameCombinations:36});await page.click('#reset');
  for(const mode of ['day','night']){await page.selectOption('#mode',mode);assert.equal(await page.locator(`#room [data-window-view][data-mode="${mode}"]`).count(),2);const snapshotStyle=await page.addStyleTag({content:'.layout{display:block}.stage{width:1080px}aside{display:none}main{max-width:none}'});await page.locator('#room').evaluate(async el=>{await Promise.all(Array.from(el.querySelectorAll('image')).map(node=>new Promise((resolve,reject)=>{const im=new Image();im.onload=resolve;im.onerror=reject;im.src=node.getAttribute('href');})));});
   const name=theme+'-'+mode+'-preview.png';await page.locator('.stage').screenshot({path:path.join(dir,name)});report.screenshots.push(name);await snapshotStyle.evaluate(el=>el.remove());
  }
  for(const flag of ['leftWindow','rightWindow','rug','art']){await page.evaluate(flag=>window.themeStudy.setState({[flag]:false}),flag);const selector=flag==='rug'?'[data-asset="rug"]':flag==='art'?'[data-asset^="art-"]':`[data-asset="window-${flag==='leftWindow'?'left':'right'}"]`;assert.equal(await page.locator('#room '+selector).count(),0);await page.evaluate(flag=>window.themeStudy.setState({[flag]:true}),flag);}
 }
 assert.deepEqual(errors,[]);assert.deepEqual(missing,[]);report.consoleErrors=errors;report.failedRequests=missing;await fs.writeFile(path.join(dir,'verification.json'),JSON.stringify(report,null,2)+'\n');console.log(JSON.stringify({themes:2,assetPairs:report.sprites.length,prismOverflow:0,mirrorDifferences:0,orientationCombinations:64,frameCombinations:72,consoleErrors:0,failedRequests:0,screenshots:report.screenshots},null,2));
}finally{await browser.close();}
