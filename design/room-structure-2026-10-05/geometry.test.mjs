import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fitCalibration,camera,project,unproject,rotateMask,connected,validCells,rectCells,fixtures,orient,gridSize,cellSize,rug,slots,roomStandard} from './geometry.mjs';
const fit=fitCalibration(JSON.parse(readFileSync(new URL('./calibration.json',import.meta.url),'utf8')));

test('portable standard data exactly matches the live frozen geometry',()=>{
  const exported=JSON.parse(readFileSync(new URL('./room-standard-v1.json',import.meta.url),'utf8'));
  assert.deepEqual(exported,JSON.parse(JSON.stringify(roomStandard)));
  assert.equal(roomStandard.floorSize,1);assert.equal(gridSize,8);
  assert.equal(roomStandard.wallThickness,.014);assert.equal(roomStandard.floorThickness,.022);
});
test('observed directions fit within sampled pixel tolerance',()=>{
  assert(fit.slope>.48&&fit.slope<.51);
  for(const r of fit.references)for(const e of r.residuals)assert(Math.abs(e.errorPixels)<=3);
});

test('all facing combinations reserve distinct complete footprints on the selected grid',()=>{
  const a=gridSize;
  for(let combination=0;combination<2**fixtures.length;combination++){
    const occupied=new Set();
    for(const [i,f] of fixtures.entries()){
      const actual=orient(f,combination&(1<<i)?'x':'y'),cells=actual.cells;
      assert(validCells(cells,a));
      const owned=new Set(cells.map(p=>p.join(',')));
      assert(rectCells(actual,a).every(p=>owned.has(p.join(','))),'visual silhouette must fit declared footprint');
      for(const p of cells){const key=p.join(',');assert(!occupied.has(key),`overlap ${a} ${combination} ${f.id} ${key}`);occupied.add(key);}
    }
  }
});
test('ground and wall inverse use the same projection',()=>{
  {const c=camera();
    for(const z of[0,.17,.6])for(const[x,y]of[[0,0],[1,1],[.12,.88],[.99,.001]]){const actual=unproject(c,project(c,[x,y,z]),z);assert(Math.abs(actual[0]-x)<1e-12);assert(Math.abs(actual[1]-y)<1e-12);}
  }
});
test('the accepted room standard is immutable and preserves all five landmark coordinates',()=>{
  const high=camera();assert.equal(roomStandard.id,'room-standard-v1');
  assert.equal(high.width,1080);assert.equal(high.height,1073);assert.equal(high.factor,1.5);
  assert.equal(high.wallHeight,0.8083190784267942);
  assert(Object.isFrozen(high));assert(Object.isFrozen(high.origin));assert(Object.isFrozen(high.bx));
  const landmarks=[[[0,0,high.wallHeight],[540,62]],[[0,0,0],[540,537.4716981132076]],
    [[1,0,0],[1020,777.0483635016901]],[[0,1,0],[60,777.0483635016901]],[[1,1,0],[540,1016.6250288901726]]];
  for(const[p,expected]of landmarks)project(high,p).forEach((value,i)=>assert(Math.abs(value-expected[i])<1e-10));
  assert(Math.abs(high.wallHeight/fit.referenceWallHeight-1.5)<1e-12);
  const delta=(c,a,b)=>project(c,b).map((v,i)=>v-project(c,a)[i]);
  assert.deepEqual(delta(high,[0,0,0],[.1,0,0]),delta(high,[.8,.8,0],[.9,.8,0]));
});
test('L footprint rotates with its empty corner and four turns restore it',()=>{
  const mask=[[0,0],[1,0],[0,1]],key=a=>a.map(p=>p.join(',')).sort();
  assert(connected(mask));assert(!connected([[0,0],[1,1]]));assert(!connected([[0,0],[0,0]]));
  let rotated=rotateMask(mask);assert.deepEqual(key(rotated),key([[1,0],[1,1],[0,0]]));
  for(let i=0;i<3;i++)rotated=rotateMask(rotated);assert.deepEqual(key(rotated),key(mask));
});
test('rectangular furniture is centered in its declared grid area in both orientations',()=>{
  for(const f of fixtures)for(const facing of['x','y']){
    const actual=orient(f,facing),[gx,gy]=actual.anchor;
    assert(Math.abs(actual.x+actual.w/2-(gx+actual.cols/2)*cellSize)<1e-12);
    assert(Math.abs(actual.y+actual.d/2-(gy+actual.rows/2)*cellSize)<1e-12);
    const keys=a=>a.map(p=>p.join(',')).sort();
    assert.deepEqual(keys(rectCells(actual,gridSize)),keys(actual.cells));
  }
  assert(!validCells([[gridSize,0]],gridSize));assert(!validCells([[-1,0]],gridSize));
});

test('fixed rug owns the central 36 cells with a one-cell perimeter',()=>{
  const cells=rectCells(rug,gridSize);
  assert.equal(cells.length,36);
  assert(cells.every(([x,y])=>x>=1&&x<=6&&y>=1&&y<=6));
  assert.equal(rug.x+rug.w/2,.5);assert.equal(rug.y+rug.d/2,.5);
});

test('enlarged central windows clear the bookcase reduced to 75 percent and keep aligned art',()=>{
  const c=camera(),book=fixtures.find(f=>f.id==='bookshelf');assert.equal(book.h,4*cellSize*.75);
  for(const wall of['left','right']){
    const window=slots.find(s=>s.wall===wall&&s.type==='window'),art=slots.filter(s=>s.wall===wall&&s.type==='art');
    assert.equal(window.s,.5);assert.equal(window.w,.32);assert.equal(window.h,1.7*cellSize);
    assert(window.z-.008>book.h);assert(window.z+window.h<c.wallHeight);
    assert(Math.abs((window.z-.008-book.h)/cellSize-.136)<1e-12,'sill leaves only a small clearance');
    assert.equal(art.length,2);assert(art[0].s+art[0].w/2<window.s-window.w/2);assert(art[1].s-art[1].w/2>window.s+window.w/2);
    for(const s of art)assert(Math.abs(s.z+s.h/2-(window.z+window.h/2))<1e-12);
  }
});
