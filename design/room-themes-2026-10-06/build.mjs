// Standalone design assets. Never writes application assets or changes the frozen room.
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {deflateSync} from 'node:zlib';
import {createRequire} from 'node:module';
import {camera,project,fixtures,orient,slots} from '../room-structure-2026-10-05/geometry.mjs';
import {frameAsset,flatFrame,windowModel,modelSvg,material,rugAsset,skyAsset,themes,templates} from './theme-geometry.mjs';
const dir=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(dir,'../..');
const {chromium}=createRequire(path.join(root,'.tooling/browser/package.json'))('playwright-core');
const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
const page=await browser.newPage();
const dataURL=async p=>'data:image/png;base64,'+(await fs.readFile(p)).toString('base64');
// Measured straight ground edges of the fresh first-facing artwork. Calibrate
// the bitmap to the house axes, never the camera to the bitmap. Verticals stay vertical.
const sourceAxes={wood:{bookshelf:[.50,-.273],desk:[.44,-.40],chair:[.55,-.38],tree:[.30,-.50],bed:[.49,-.47]},royal:{bookshelf:[.47,-.30],desk:[.55,-.27],chair:[.55,-.38],tree:[.44,-.28],bed:[.50,-.35]}};
function crc(buffer){let c=0xffffffff;for(const b of buffer){c^=b;for(let i=0;i<8;i++)c=(c>>>1)^((c&1)?0xedb88320:0);}return(c^0xffffffff)>>>0;}
function chunk(type,data){const t=Buffer.from(type),out=Buffer.alloc(12+data.length);out.writeUInt32BE(data.length);t.copy(out,4);data.copy(out,8);out.writeUInt32BE(crc(Buffer.concat([t,data])),8+data.length);return out;}
function png(w,h,rgba){const header=Buffer.alloc(13);header.writeUInt32BE(w);header.writeUInt32BE(h,4);header[8]=8;header[9]=6;const rows=Buffer.alloc((w*4+1)*h);for(let y=0;y<h;y++)Buffer.from(rgba).copy(rows,y*(w*4+1)+1,y*w*4,(y+1)*w*4);return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',header),chunk('IDAT',deflateSync(rows)),chunk('IEND',Buffer.alloc(0))]);}
function hull(points){const sorted=[...points].sort((a,b)=>a[0]-b[0]||a[1]-b[1]),cross=(a,b,c)=>(b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]);const half=arr=>{const q=[];for(const p of arr){while(q.length>1&&cross(q.at(-2),q.at(-1),p)<=0)q.pop();q.push(p);}return q;};return [...half(sorted).slice(0,-1),...half(sorted.toReversed()).slice(0,-1)];}
function prism(f){const ps=[];for(const x of [0,f.w])for(const y of [0,f.d])for(const z of [0,f.h])ps.push(project(camera(),[x,y,z]));const min=[0,1].map(i=>Math.floor(Math.min(...ps.map(p=>p[i])))-6),max=[0,1].map(i=>Math.ceil(Math.max(...ps.map(p=>p[i])))+6);return{viewBox:[...min,max[0]-min[0],max[1]-min[1]],hull:hull(ps).map(p=>p.map((v,i)=>v-min[i]))};}
async function sprite(theme,f){
  const a=prism(f),source=await dataURL(path.join(dir,theme,f.id+'-x-source.png'));
  const foot=project(camera(),[f.w-.008,f.d-.008,0]).map((v,i)=>v-a.viewBox[i]);
  const [positive,negative]=sourceAxes[theme][f.id],slope=camera().bx[1]/camera().bx[0],vertical=2*slope/(positive-negative),shear=slope-vertical*positive;
  const result=await page.evaluate(async({source,W,H,poly,foot,vertical,shear})=>{
    const im=new Image();im.src=source;await im.decode();const raw=document.createElement('canvas');raw.width=im.width;raw.height=im.height;const ctx=raw.getContext('2d',{willReadFrequently:true});ctx.drawImage(im,0,0);const pix=ctx.getImageData(0,0,im.width,im.height),edge=[];let minX=im.width,minY=im.height,maxX=0,maxY=0;
    for(let y=0;y<im.height;y++){let left=im.width,right=-1;for(let x=0;x<im.width;x++){const alpha=pix.data[(y*im.width+x)*4+3];if(alpha>=32){left=Math.min(left,x);right=Math.max(right,x);minX=Math.min(minX,x);maxX=Math.max(maxX,x);minY=Math.min(minY,y);maxY=Math.max(maxY,y);}}if(right>=0)edge.push([left,y],[right,y]);}
    const sourceBounds=[minX,minY,maxX,maxY];for(const p of edge)p[1]=vertical*p[1]+shear*p[0];minY=Math.min(...edge.map(p=>p[1]));maxY=Math.max(...edge.map(p=>p[1]));
    const bottom=edge.filter(p=>p[1]>=maxY-5),ground=[bottom.reduce((s,p)=>s+p[0],0)/bottom.length,maxY];
    const inside=p=>poly.every((a,i)=>{const b=poly[(i+1)%poly.length];return (b[0]-a[0])*(p[1]-a[1])-(b[1]-a[1])*(p[0]-a[0])>=-.25*Math.hypot(b[0]-a[0],b[1]-a[1]);});
    let best={s:0};const initial=Math.min((W-12)/(maxX-minX+1),(H-12)/(maxY-minY+1));
    for(let dx=-8;dx<=8;dx+=2)for(let dy=-6;dy<=2;dy+=2){let lo=0,hi=initial;const target=[foot[0]+dx,foot[1]+dy];for(let n=0;n<15;n++){const s=(lo+hi)/2;if(edge.every(p=>inside([target[0]+(p[0]-ground[0])*s,target[1]+(p[1]-ground[1])*s])))lo=s;else hi=s;}if(lo>best.s)best={s:lo,target};}
    if(best.s<initial*.45)throw Error('Projection does not fit declared prism: '+JSON.stringify({ratio:best.s/initial,best,ground,poly,bounds:[minX,minY,maxX,maxY],initial}));
    const out=document.createElement('canvas');out.width=W;out.height=H;const o=out.getContext('2d');o.imageSmoothingQuality='high';o.setTransform(best.s,shear*best.s,0,vertical*best.s,best.target[0]-ground[0]*best.s,best.target[1]-ground[1]*best.s);o.drawImage(raw,0,0);const rgba=o.getImageData(0,0,W,H).data;
    // Transparent RGB has no visual content. Canonicalize it for a clean exact mirror.
    for(let i=0;i<rgba.length;i+=4)if(rgba[i+3]<4)rgba.fill(0,i,i+4);
    return{rgba:Array.from(rgba),fit:{scale:best.s,initialScale:initial,ratio:best.s/initial,sourceBounds,calibratedGround:ground,projectedGround:best.target,vertical,shear}};
  },{source,W:a.viewBox[2],H:a.viewBox[3],poly:a.hull,foot,vertical,shear});
  const bytes=Buffer.from(result.rgba),W=a.viewBox[2],H=a.viewBox[3],mirror=Buffer.alloc(bytes.length);for(let y=0;y<H;y++)for(let x=0;x<W;x++)bytes.copy(mirror,(y*W+(W-1-x))*4,(y*W+x)*4,(y*W+x)*4+4);
  const records=[];
  for(const facing of ['x','y']){const actual=orient(fixtures.find(v=>v.id===f.id),facing),name=f.id+'-'+facing,rgba=facing==='x'?bytes:mirror,encoded=png(W,H,rgba),origin=[camera().origin[0]-a.viewBox[0],camera().origin[1]-a.viewBox[1]];if(facing==='y')origin[0]=W-origin[0];
    await fs.writeFile(path.join(dir,theme,name+'.png'),encoded);
    const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="${W}" height="${H}" viewBox="${a.viewBox.join(' ')}"><image href="data:image/png;base64,${encoded.toString('base64')}" x="${a.viewBox[0]}" y="${a.viewBox[1]}" width="${W}" height="${H}"/></svg>`;await fs.writeFile(path.join(dir,theme,name+'.svg'),svg);
    records.push({id:name,category:'furniture',png:name+'.png',svg:name+'.svg',viewBox:a.viewBox,pixelGroundOrigin:origin,dimensionsL:[actual.w,actual.d,actual.h],dimensionsCells:[actual.w,actual.d,actual.h].map(v=>v*8),gridAnchor:actual.anchor,cells:actual.cells,worldGroundAnchor:[actual.x,actual.y,0],facing,mirrorOf:facing==='y'?f.id+'-x':null,projectionHull:facing==='x'?a.hull:a.hull.map(([x,y])=>[W-x,y]).toReversed(),fit:result.fit});
  }return records;
}
async function save(theme,id,a,extra={}){await fs.writeFile(path.join(dir,theme,id+'.svg'),a.svg);const result=await page.evaluate(async svg=>{const im=new Image();im.src='data:image/svg+xml;base64,'+btoa(unescape(encodeURIComponent(svg)));await im.decode();const c=document.createElement('canvas');c.width=im.width;c.height=im.height;c.getContext('2d').drawImage(im,0,0);return c.toDataURL('image/png').split(',')[1];},a.svg);await fs.writeFile(path.join(dir,theme,id+'.png'),Buffer.from(result,'base64'));return{id,category:'decor',svg:id+'.svg',png:id+'.png',...a,svgSource:undefined,svg:id+'.svg',...extra};}
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
    await fs.writeFile(path.join(dir,theme,'manifest.json'),JSON.stringify({standard:'room-standard-v1',theme,label:themes[theme].label,sourcePolicy:'Fresh text-only furniture; +Y exact RGBA mirror of +X; no old furniture input image',assets},null,2)+'\n');console.log(theme,assets.length,'assets complete');
  }
}finally{await browser.close();}
