import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fitCalibration,camera,project,unproject,rotateMask,connected,validCells,rectCells,fixtures,orient} from './geometry.mjs';
const fit=fitCalibration(JSON.parse(readFileSync(new URL('./calibration.json',import.meta.url),'utf8')));
test('observed directions fit within sampled pixel tolerance',()=>{
  assert(fit.slope>.48&&fit.slope<.51);
  for(const r of fit.references)for(const e of r.residuals)assert(Math.abs(e.errorPixels)<=3);
});

test('all facing combinations reserve distinct complete footprints on every grid',()=>{
  for(const a of[6,8,10])for(let combination=0;combination<2**fixtures.length;combination++){
    const occupied=new Set();
    for(const [i,f] of fixtures.entries()){
      const actual=orient(f,combination&(1<<i)?'x':'y'),cells=rectCells(actual,a);
      assert(validCells(cells,a));
      for(const p of cells){const key=p.join(',');assert(!occupied.has(key),`overlap ${a} ${combination} ${f.id} ${key}`);occupied.add(key);}
    }
  }
});
test('ground and wall inverse use the same projection',()=>{
  for(const factor of[1,1.5]){const c=camera(fit,factor);
    for(const z of[0,.17,.6])for(const[x,y]of[[0,0],[1,1],[.12,.88],[.99,.001]]){const actual=unproject(c,project(c,[x,y,z]),z);assert(Math.abs(actual[0]-x)<1e-12);assert(Math.abs(actual[1]-y)<1e-12);}
  }
});
test('higher wall increases scene height, never floor width or unit scale',()=>{
  const low=camera(fit,1),high=camera(fit,1.5);
  assert.equal(low.width,high.width);assert.deepEqual(low.bx,high.bx);assert.deepEqual(low.by,high.by);
  assert(Math.abs(high.wallHeight/low.wallHeight-1.5)<1e-12);assert(high.height>low.height);
  const delta=(c,a,b)=>project(c,b).map((v,i)=>v-project(c,a)[i]);
  assert.deepEqual(delta(high,[0,0,0],[.1,0,0]),delta(high,[.8,.8,0],[.9,.8,0]));
});
test('L footprint rotates with its empty corner and four turns restore it',()=>{
  const mask=[[0,0],[1,0],[0,1]],key=a=>a.map(p=>p.join(',')).sort();
  assert(connected(mask));assert(!connected([[0,0],[1,1]]));assert(!connected([[0,0],[0,0]]));
  let rotated=rotateMask(mask);assert.deepEqual(key(rotated),key([[1,0],[1,1],[0,0]]));
  for(let i=0;i<3;i++)rotated=rotateMask(rotated);assert.deepEqual(key(rotated),key(mask));
});
test('all three grids contain distinct representative fixtures',()=>{
  for(const a of[6,8,10]){const occupied=new Set();
    for(const f of fixtures){const cells=rectCells(f,a);assert(validCells(cells,a));for(const p of cells){const k=p.join(',');assert(!occupied.has(k),'fixture overlap '+a+' '+f.id+' '+k);occupied.add(k);}}
    assert(!validCells([[a,0]],a));assert(!validCells([[-1,0]],a));
  }
});
