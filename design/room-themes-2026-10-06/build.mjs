// Standalone design assets. Never writes application assets or changes the frozen room.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {deflateSync} from 'node:zlib';
import {createRequire} from 'node:module';
import {camera,fixtures,orient,slots} from '../room-structure-2026-10-05/geometry.mjs';
import {frameAsset,flatFrame,windowModel,modelSvg,material,rugAsset,skyAsset,themes,templates} from './theme-geometry.mjs';
import {constructionGuide,projectionHull,auditAlpha} from './furniture-geometry.mjs';
import {registerSource} from './register-source.mjs';
const dir=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(dir,'../..');
const {chromium}=createRequire(path.join(root,'.tooling/browser/package.json'))('playwright-core');
const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
const page=await browser.newPage();
const dataURL=async p=>'data:image/png;base64,'+(await fs.readFile(p)).toString('base64');
async function writeChanged(file,contents){
  const bytes=Buffer.isBuffer(contents)?contents:Buffer.from(contents);
  try{if((await fs.readFile(file)).equals(bytes))return;}catch(e){if(e.code!=='ENOENT')throw e;}
  await fs.writeFile(file,bytes);
}
function crc(buffer){let c=0xffffffff;for(const b of buffer){c^=b;for(let i=0;i<8;i++)c=(c>>>1)^((c&1)?0xedb88320:0);}return(c^0xffffffff)>>>0;}
function chunk(type,data){const t=Buffer.from(type),out=Buffer.alloc(12+data.length);out.writeUInt32BE(data.length);t.copy(out,4);data.copy(out,8);out.writeUInt32BE(crc(Buffer.concat([t,data])),8+data.length);return out;}
function png(w,h,rgba){const header=Buffer.alloc(13);header.writeUInt32BE(w);header.writeUInt32BE(h,4);header[8]=8;header[9]=6;const rows=Buffer.alloc((w*4+1)*h);for(let y=0;y<h;y++)Buffer.from(rgba).copy(rows,y*(w*4+1)+1,y*w*4,(y+1)*w*4);return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',header),chunk('IDAT',deflateSync(rows)),chunk('IEND',Buffer.alloc(0))]);}
async function sprite(theme,f){
  const a=constructionGuide(theme,f.id),source=await dataURL(path.join(dir,theme,f.id+'-x-source.png')),guideImage=await dataURL(path.join(dir,theme,f.id+'-coordinate-guide.png'));
  const savedGuide=await fs.readFile(path.join(dir,theme,f.id+'-coordinate-guide.svg'),'utf8');if(savedGuide!==a.svg)throw Error('Construction guide is stale; rebuild guides and remake source '+theme+'/'+f.id);
  const prompt=await fs.readFile(path.join(dir,theme,f.id+'-prompt.txt'),'utf8');if(!prompt.includes('MANDATORY COORDINATE CONTRACT')||!prompt.includes('room-standard-v1'))throw Error('Missing mandatory generation requirements '+theme+'/'+f.id);
  const result=await registerSource(page,{source,guide:a,guideImage});if(!result.passed)throw Error('Source must be remade; no skew/stretch/anchor search is permitted: '+JSON.stringify({theme,id:f.id,registration:result.registration,axisChecks:result.axisChecks}));
  const alpha=auditAlpha(result.rgba,a);if(alpha.edge||alpha.overflow)throw Error('Source must be remade; projected outside prism or cropped '+theme+'/'+f.id+' '+JSON.stringify(alpha));a.hull=projectionHull(f,a.viewBox);
  const bytes=Buffer.from(result.rgba),W=a.viewBox[2],H=a.viewBox[3],mirror=Buffer.alloc(bytes.length);for(let y=0;y<H;y++)for(let x=0;x<W;x++)bytes.copy(mirror,(y*W+(W-1-x))*4,(y*W+x)*4,(y*W+x)*4+4);
  const records=[];
  for(const facing of ['x','y']){const actual=orient(fixtures.find(v=>v.id===f.id),facing),name=f.id+'-'+facing,rgba=facing==='x'?bytes:mirror,encoded=png(W,H,rgba),origin=[camera().origin[0]-a.viewBox[0],camera().origin[1]-a.viewBox[1]];if(facing==='y')origin[0]=W-origin[0];
    await writeChanged(path.join(dir,theme,name+'.png'),encoded);
    const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="${a.viewBox.join(' ')}"><image href="data:image/png;base64,${encoded.toString('base64')}" x="${a.viewBox[0]}" y="${a.viewBox[1]}" width="${W}" height="${H}"/></svg>`;await writeChanged(path.join(dir,theme,name+'.svg'),svg);
    const swapLabel=label=>label.replace(/\+[XY]/g,axis=>axis==='+X'?'+Y':'+X');
    const axisChecks=result.axisChecks.map(e=>facing==='x'?e:{...e,label:swapLabel(e.label),family:e.family==='X'?'Y':'X',expectedAngle:-e.expectedAngle,measuredAngle:-e.measuredAngle,derivedFrom:f.id+'-x exact mirror'});
    const guideEdges=a.checkEdges.map(e=>facing==='x'?e:{...e,label:swapLabel(e.label),a:[e.a[1],e.a[0],e.a[2]],b:[e.b[1],e.b[0],e.b[2]],screen:e.screen.map(([x,y])=>[W-x,y])});
    records.push({id:name,category:'furniture',png:name+'.png',svg:name+'.svg',viewBox:a.viewBox,pixelGroundOrigin:origin,dimensionsL:[actual.w,actual.d,actual.h],dimensionsCells:[actual.w,actual.d,actual.h].map(v=>v*8),gridAnchor:actual.anchor,cells:actual.cells,worldGroundAnchor:[actual.x,actual.y,0],facing,mirrorOf:facing==='y'?f.id+'-x':null,projectionHull:facing==='x'?a.hull:a.hull.map(([x,y])=>[W-x,y]).toReversed(),coordinateGuide:f.id+'-coordinate-guide.png',guideEdges,registration:result.registration,axisChecks});
  }return records;
}
async function save(theme,id,a,extra={}){await writeChanged(path.join(dir,theme,id+'.svg'),a.svg);const result=await page.evaluate(async svg=>{const im=new Image();im.src='data:image/svg+xml;base64,'+btoa(unescape(encodeURIComponent(svg)));await im.decode();const c=document.createElement('canvas');c.width=im.width;c.height=im.height;c.getContext('2d').drawImage(im,0,0);return c.toDataURL('image/png').split(',')[1];},a.svg);await writeChanged(path.join(dir,theme,id+'.png'),Buffer.from(result,'base64'));return{id,category:'decor',svg:id+'.svg',png:id+'.png',...a,svgSource:undefined,svg:id+'.svg',...extra};}
try{
  for(const theme of process.argv.slice(2).length?process.argv.slice(2):Object.keys(themes)){
    const assets=[];for(const f of fixtures){assets.push(...await sprite(theme,orient(f,'x')));console.log(theme,f.id,'packed');}
    for(const side of ['left','right']){
      const slot=slots.find(s=>s.id==='window-'+side);assets.push(await save(theme,slot.id,modelSvg(windowModel(theme,slot),theme),{dimensionsL:[slot.w,slot.h,.063],worldMountCenter:side==='left'?[0,slot.s,slot.z+slot.h/2]:[slot.s,0,slot.z+slot.h/2],sillBottom:slot.z-.008}));
      for(const key of Object.keys(templates))assets.push(await save(theme,`frame-${key}-${side}`,frameAsset(theme,key,side),{template:key,wall:side}));
      for(const open of [true,false])assets.push(await save(theme,`wall-${side}`+(open?'':'-closed'),material(theme,'wall-'+side,await dataURL(path.join(dir,theme,'wall-source.png')),open),{projection:'independent; not mirrored'}));
      for(const mode of ['day','night'])assets.push(await save(theme,`view-${side}-${mode}`,skyAsset(slot,mode,await dataURL(path.join(dir,'shared',mode+'-source.png'))),{mode,projection:'upright, different sky crop per window; positive determinant, never mirrored'}));
    }
    for(const key of Object.keys(templates))assets.push(await save(theme,`frame-${key}-flat`,flatFrame(theme,key),{template:key,dimensionsL:[templates[key].w,templates[key].h,.026]}));
    assets.push(await save(theme,'floor',material(theme,'floor',await dataURL(path.join(dir,theme,'floor-source.png')))),await save(theme,'rug',rugAsset(theme),{worldFootprint:[.125,.125,.75,.75],cells:'central 6×6'}));
    await writeChanged(path.join(dir,theme,'manifest.json'),JSON.stringify({standard:'room-standard-v1',theme,label:themes[theme].label,sourcePolicy:'New numeric construction guide constrains every generation; actual pixel edges checked; uniform registration only; +Y exact mirror',generationRequirements:'../../room-structure-2026-10-05/FURNITURE-GENERATION.md',assets},null,2)+'\n');console.log(theme,assets.length,'assets complete');
  }
}finally{await browser.close();}
