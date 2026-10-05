import {test} from 'node:test';
import assert from 'node:assert/strict';
import {camera,slots,project} from './geometry.mjs';
import {joineryModel,mountJoinery,windowModel,windowSill} from './lunar-joinery.mjs';
import {scene} from './lunar-art.mjs';
import {windowViewSvg} from './lunar-window-views.mjs';
import {frameTemplates,frameLayout,wallArtwork} from './lunar-templates.mjs';
const near=(a,b)=>assert(Math.abs(a-b)<1e-9,`${a} != ${b}`);

test('all three frame casings fit the reserved sizes with real rail and relief thickness',()=>{
  for(const t of Object.values(frameTemplates)){
    const m=joineryModel(t.w,t.h);assert.equal(m.images.length,0);
    for(const f of m.faces)for(const [u,v,z]of f.points){assert(u>=-.004-1e-9&&u<=.022+1e-9);assert(v>=-1e-9&&v<=t.w+1e-9);assert(z>=-1e-9&&z<=t.h+1e-9);}
    const relief=m.parts.find(p=>p.name==='raised crescent');
    const depth=m.faces.slice(relief.firstFace,relief.firstFace+relief.faceCount).flatMap(f=>f.points.map(p=>p[0]));
    near(Math.max(...depth)-Math.min(...depth),.0038);
    const {left,right,bottom,top}=m.opening;assert(right>left&&top>bottom);
    // A usable opening remains below the curved header, above the sill rail, and between side rails.
    assert(right-left>.11&&top-bottom>.10);
    for(const p of m.parts.filter(p=>/pilaster|lower rail|curved solid header/.test(p.name))){
      const d=m.faces.slice(p.firstFace,p.firstFace+p.faceCount).flatMap(f=>f.points.map(p=>p[0]));assert(Math.max(...d)-Math.min(...d)>.015);
    }
    for(const side of ['left','right'])assert(m.parts.some(p=>p.name===side+' carved side cartouche'));
  }
});

test('opposing walls mount the same canonical frame without changing its design or center',()=>{
  for(const t of Object.values(frameTemplates)){
    const model=joineryModel(t.w,t.h),left=mountJoinery(model,{wall:'left',s:.5,z:.4}),right=mountJoinery(model,{wall:'right',s:.5,z:.4});
    assert.equal(left.faces.length,right.faces.length);
    for(let i=0;i<left.faces.length;i++)for(const[p,q]of left.faces[i].points.map((p,j)=>[p,right.faces[i].points.at(-1-j)])){
      near(p[0],q[1]);near(p[1],q[0]);near(p[2],q[2]);const [a,b]=[p,q].map(p=>project(camera(),p));near(a[0]+b[0],1080);near(a[1],b[1]);
    }
  }
});

test('window opening, frame envelope and solid sill preserve confirmed coordinates',()=>{
  const slot=slots.find(s=>s.id==='window-left'),m=windowModel(slot);assert.equal(m.images.length,0);
  const ps=m.faces.flatMap(f=>f.points);
  near(Math.min(...ps.map(p=>p[2])),slot.z-.008);near(Math.max(...ps.map(p=>p[2])),slot.z+slot.h);
  assert(Math.max(...ps.map(p=>p[0]))>.062&&Math.max(...ps.map(p=>p[0]))<=windowSill.depth);
  assert(m.parts.some(p=>p.name==='solid center mullion'));assert(m.parts.some(p=>p.name==='rounded solid sill'));
  for(const p of ps){assert(p[1]>=slot.s-slot.w/2-windowSill.overhang-1e-9&&p[1]<=slot.s+slot.w/2+windowSill.overhang+1e-9);}
  for(const name of ['sill crescent apron','left sill end scroll','right sill end scroll'])assert(m.parts.some(p=>p.name===name));
});

test('reusable frame body has no picture skin; only the separately contained original is an image',()=>{
  const slot=slots.find(s=>s.type==='art');
  for(const key of Object.keys(frameTemplates)){
    const f=frameLayout(slot,key);near(f.centerZ*8,4.05);
    const empty=wallArtwork(slot,key);assert(!/<image|data:image/.test(empty));
    for(const kind of ['starry','pearl']){
      const full=wallArtwork(slot,key,kind);assert.equal((full.match(/<image /g)||[]).length,1);assert(full.includes(`data-artwork="${kind}"`));
    }
  }
});

test('corner addition is removed; scenery is a separate plane with unchanged source ratio',()=>{
  const result=scene({assets:[{id:'corner-transition',category:'wall-trim',svg:'corner.svg',viewBox:[0,0,8,400]}]});assert(!result.includes('corner-transition')&&!result.includes('corner.svg'));
  for(const wall of ['left','right'])for(const mode of ['day','night']){
    const s=slots.find(s=>s.id==='window-'+wall),v=windowViewSvg(s,mode,'sky.png');near(v.originalAspect,1.5);assert.equal((v.svg.match(/<image /g)||[]).length,1);assert(v.svg.includes('clip-path=')&&v.svg.includes('data-window-mode="'+mode+'"'));
  }
  assert.throws(()=>windowViewSvg(slots.find(s=>s.type==='window'),'sunset','sky.png'));
});
