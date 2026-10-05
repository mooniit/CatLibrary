import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fixtures,orient,rectCells,slots,project,camera} from './geometry.mjs';
import {furniture,bounds,assetSvg,wallAsset,artwork} from './lunar-art.mjs';
test('complete curved meshes remain inside declared centered footprints in all 32 facing combinations',()=>{
  for(let combo=0;combo<32;combo++){
    const used=new Set();
    for(const[i,f]of fixtures.entries()){
      const a=orient(f,combo&(1<<i)?'x':'y'),m=furniture(a),b=bounds(m);
      assert(b.min[0]>=a.x-1e-10&&b.min[1]>=a.y-1e-10);
      assert(b.max[0]<=a.x+a.w+1e-10&&b.max[1]<=a.y+a.d+1e-10);
      assert(Math.abs(b.min[2])<1e-10);assert(Math.abs(b.max[2]-a.h)<1e-10);
      assert(m.faces.length>150,'curved structure must be present');
      assert(Math.abs((b.min[0]+b.max[0])/2-(a.anchor[0]+a.cols/2)/8)<1e-10);
      assert(Math.abs((b.min[1]+b.max[1])/2-(a.anchor[1]+a.rows/2)/8)<1e-10);
      for(const p of rectCells(a,8))assert(a.cells.some(c=>c.join(',')===p.join(',')));
      for(const c of a.cells){assert(c.every(v=>v>=0&&v<8));const k=c.join(',');assert(!used.has(k));used.add(k);}
    }
  }
});
test('footprint calibration meshes follow +X / +Y and keep the bed front low',()=>{
  for(const f of fixtures){const x=assetSvg(furniture({...orient(f,'x'),x:0,y:0})),y=assetSvg(furniture({...orient(f,'y'),x:0,y:0}));assert.notEqual(x.svg,y.svg);assert(!/rotate\(|scale\(-1/.test(y.svg));}
  for(const dir of['x','y']){const a={...orient(fixtures.find(f=>f.id==='bed'),dir),x:0,y:0},m=furniture(a);
    const front=m.faces.flatMap(f=>f.points).filter(p=>p[dir==='x'?0:1]>(dir==='x'?a.w:a.d)-.001);
    assert(Math.max(...front.map(p=>p[2]))<.04,'front lip stays low');assert.equal(bounds(m).max[2],.085);
  }
});
test('window sill uses the standard clearance; artwork image planes preserve original aspect',()=>{
  for(const wall of['left','right']){
    const win=slots.find(s=>s.wall===wall&&s.type==='window'),b=bounds(wallAsset(win));assert(Math.abs(b.min[2]-(win.z-.008))<1e-12);
    assert(Math.abs((b.min[2]-.375)*8-.136)<1e-12);
    for(const kind of['starry','pearl']){const slot=slots.find(s=>s.wall===wall&&s.type==='art'),m=wallAsset(slot,kind),p=m.images[0].points;
      const w=Math.hypot(...p[1].map((v,i)=>v-p[0][i])),h=Math.hypot(...p[2].map((v,i)=>v-p[0][i]));assert(Math.abs(w/h-artwork[kind].ratio)<1e-12);
      const bb=bounds(m);assert(bb.min[2]>=slot.z-1e-12&&bb.max[2]<=slot.z+slot.h+1e-12);
    }
  }
});
test('exported sprite pixel ground anchors reconstruct exact world placement',()=>{
  const manifest=JSON.parse(readFileSync(new URL('./lunar-assets-v5/manifest.json',import.meta.url),'utf8'));
  const catalog=JSON.parse(readFileSync(new URL('../../assets/images/room/lunar-v5/catalog.json',import.meta.url),'utf8'));
  for(const a of manifest.assets.filter(a=>a.category==='furniture')){
    const f=orient(fixtures.find(f=>f.id===a.id.split('-')[0]),a.id.endsWith('-x')?'x':'y');
    assert.deepEqual(a.worldGroundAnchor,[f.x,f.y,0]);assert.deepEqual(a.dimensionsL,[f.w,f.d,f.h]);assert.deepEqual(a.cells,f.cells);
    const p=project(camera(),a.worldGroundAnchor),rect=catalog.layers[a.id].rect;
    for(let i=0;i<2;i++)assert(Math.abs(rect[i]+a.pixelGroundOrigin[i]-p[i])<1e-9);
    assert.deepEqual(rect.slice(2),a.viewBox.slice(2));
  }
});
