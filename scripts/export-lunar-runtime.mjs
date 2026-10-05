// Package the approved independent pieces for Flame; geometry stays authoritative.
import {readFileSync,writeFileSync,mkdirSync,copyFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createRequire} from 'node:module';
import {roomStandard,fixtures,orient,slots,camera,project} from '../design/room-structure-2026-10-05/geometry.mjs';
import {configureDecorSkins,materialSvg,frameTemplates} from '../design/room-structure-2026-10-05/lunar-templates.mjs';
const require=createRequire(import.meta.url);
const {chromium}=require('../.tooling/browser/node_modules/playwright-core');
const source=resolve('design/room-structure-2026-10-05/lunar-assets-v5');
const target=resolve('assets/images/room/lunar-v5');mkdirSync(target,{recursive:true});
const approved=JSON.parse(readFileSync(resolve(source,'manifest.json')));
const layers={};
for(const a of approved.assets.filter(a=>a.category==='furniture'||['floor','rug','window-left','window-right'].includes(a.id)||/^frame-(landscape|portrait|square)-(left|right)$/.test(a.id))) {
  copyFileSync(resolve(source,a.png),resolve(target,a.png));
  let rect=a.viewBox;
  if(a.category==='furniture'){
    const f=orient(fixtures.find(f=>f.id===a.id.split('-')[0]),a.id.endsWith('-x')?'x':'y');
    const p=project(camera(),[f.x,f.y,0]);rect=[p[0]-a.pixelGroundOrigin[0],p[1]-a.pixelGroundOrigin[1],a.viewBox[2],a.viewBox[3]];
  }
  layers[a.id]={file:a.png,rect,mount:a.worldMountCenter,opening:a.opening};
}
for(const mode of ['day','night'])copyFileSync(resolve(source,`view-${mode}-source.png`),resolve(target,`sky-${mode}.png`));
const data=file=>'data:image/png;base64,'+readFileSync(resolve(source,file)).toString('base64');
configureDecorSkins({wall:{url:data('wall-master.png')},floor:{url:data('floor-master.png')}});
const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
try {
  const page=await browser.newPage();
  // Project each wall independently. Never reflect a finished wall bitmap.
  for(const side of ['left','right'])for(const open of [true,false]){
    const id=`wall-${side}${open?'':'-closed'}`,a=materialSvg('wall-'+side,undefined,undefined,open);
    const png=await page.evaluate(async svg=>{const img=new Image();img.src='data:image/svg+xml;base64,'+btoa(unescape(encodeURIComponent(svg)));await img.decode();const c=document.createElement('canvas');c.width=img.width*2;c.height=img.height*2;c.getContext('2d').drawImage(img,0,0,c.width,c.height);return c.toDataURL('image/png').split(',')[1];},a.svg);
    writeFileSync(resolve(target,id+'.png'),Buffer.from(png,'base64'));layers[id]={file:id+'.png',rect:a.viewBox};
  }
} finally {await browser.close();}
writeFileSync(resolve(target,'catalog.json'),JSON.stringify({version:'lunar-content-v5',standard:roomStandard,layers,fixtures:fixtures.map(f=>({id:f.id,defaultFacing:f.facing,orientations:Object.fromEntries(['x','y'].map(d=>[d,orient(f,d)]))})),slots,frameTemplates},null,2)+'\n');
console.log(`Packaged ${Object.keys(layers).length} independent layers for room-standard-v1.`);
