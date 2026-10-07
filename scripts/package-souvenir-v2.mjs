import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createRequire} from 'node:module';

// Only the six selected drafts authorized on 2026-10-07. Strict validation and
// the original failed measurements remain unchanged.
const dir='design/souvenirs-2026-10-07/v2',out='assets/images/room/souvenirs-v2';
const {products}=JSON.parse(fs.readFileSync(`${dir}/models.json`));
assert.deepEqual(products.map(p=>p.sku),['palace','louvre','fuji','pyramid','eiffel','liberty'].map(id=>`souvenir-${id}`));
const {chromium}=createRequire(path.resolve('.tooling/browser/package.json'))('playwright-core');
const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true}),page=await browser.newPage();
const manifest=[];fs.mkdirSync(out,{recursive:true});
const approved=fs.existsSync(`${out}/manifest.json`)
  ? new Map(JSON.parse(fs.readFileSync(`${out}/manifest.json`)).map(p=>[p.sku,p.sourceSha256])) : null;
try {
  for(const product of products){
    const id=product.sku.slice(9),source=fs.readFileSync(`${dir}/${id}-x-source.png`);
    const sourceSha256=createHash('sha256').update(source).digest('hex');
    if(approved)assert.equal(sourceSha256,approved.get(product.sku),'changed source requires separate review, not this selected-draft admission');
    const guide=JSON.parse(fs.readFileSync(`${dir}/${id}-coordinate-guide.json`));
    const report=JSON.parse(fs.readFileSync(`${dir}/${id}-registration.json`));
    assert.equal(report.id,id);assert.equal(report.registration.warp,'none');
    const result=await page.evaluate(async ({source,guide,registration})=>{
      const image=new Image();image.src=source;await image.decode();
      const scale=registration.scale,tx=guide.viewBox[0]+registration.translation[0],ty=guide.viewBox[1]+registration.translation[1];
      // Preserve the entire source. No foot search, per-axis scale or cropping.
      const half=Math.ceil(Math.max(540-tx,tx+image.width*scale-540))+3;
      const top=Math.floor(ty)-3,bottom=Math.ceil(ty+image.height*scale)+3;
      const rect=[540-half,top,half*2,bottom-top],density=3;
      const canvas=document.createElement('canvas');canvas.width=rect[2]*density;canvas.height=rect[3]*density;
      const ctx=canvas.getContext('2d');ctx.scale(density,density);
      ctx.drawImage(image,tx-rect[0],ty-rect[1],image.width*scale,image.height*scale);
      const pixels=ctx.getImageData(0,0,canvas.width,canvas.height),mirror=new Uint8ClampedArray(pixels.data.length);
      let opaque=0,edge=0;
      for(let y=0;y<canvas.height;y++)for(let x=0;x<canvas.width;x++){
        const i=(y*canvas.width+x)*4,j=(y*canvas.width+canvas.width-1-x)*4;
        if(pixels.data[i+3]<4)pixels.data.fill(0,i,i+4);
        if(pixels.data[i+3]){opaque++;if(x===0||y===0||x===canvas.width-1||y===canvas.height-1)edge++;}
        mirror.set(pixels.data.subarray(i,i+4),j);
      }
      ctx.putImageData(pixels,0,0);const first=canvas.toDataURL('image/png').split(',')[1];
      ctx.putImageData(new ImageData(mirror,canvas.width,canvas.height),0,0);
      return {rect,density,opaque,edge,first,second:canvas.toDataURL('image/png').split(',')[1]};
    },{source:'data:image/png;base64,'+source.toString('base64'),guide,registration:report.registration});
    assert(result.opaque>0);assert.equal(result.edge,0,'transparent edge padding');
    fs.writeFileSync(`${out}/${id}-x.png`,Buffer.from(result.first,'base64'));
    fs.writeFileSync(`${out}/${id}-y.png`,Buffer.from(result.second,'base64'));
    const sprite={x:`${out}/${id}-x.png`,y:`${out}/${id}-y.png`,rect:result.rect,density:result.density};
    const {faces,...geometry}=product.geometry;product.geometry={...geometry,sprite};
    manifest.push({sku:product.sku,label:product.label,sprite,sourceSha256,registration:report.registration,geometryPassed:report.passed,admission:'user-authorized-selected-draft-2026-10-07',transparentEdgePixels:result.edge,secondFacing:'exact RGBA pixel reflection of first'});
    console.log(product.label,result.rect.join(','),'3x, clear transparent edge, pixel mirrored facing');
  }
  fs.writeFileSync(`${out}/manifest.json`,JSON.stringify(manifest,null,2)+'\n');
  fs.writeFileSync('assets/data/souvenir-products.json',JSON.stringify(products,null,2)+'\n');
  const sql='-- Selected refined sprites authorized 2026-10-07; strict geometry reports remain failed.\n-- Preserve SKUs, reward provenance, inventory, layouts and 1x1 footprints.\n'+products.map(p=>`update public.furniture_products set label='${p.label}',geometry='${JSON.stringify(p.geometry)}'::jsonb where sku='${p.sku}';`).join('\n')+'\n';
  const migration='supabase/migrations/202610070009_souvenir_refined_sprites.sql';
  if(fs.existsSync(migration))assert.equal(fs.readFileSync(migration,'utf8').replaceAll('\r\n','\n'),sql,'never rewrite an applied migration');
  else fs.writeFileSync(migration,sql);
} finally {await browser.close();}
