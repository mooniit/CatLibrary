// Pure geometry shared by the structural preview and its tests. World floor = 1 × 1.
import {roomStandard} from './room-standard.mjs';
export {roomStandard};
export function fitCalibration(data) {
  let numerator=0,denominator=0;
  for(const ref of data.references)for(const s of ref.segments){
    const dx=Math.abs(s.b[0]-s.a[0]),dy=s.b[1]-s.a[1];
    numerator+=s.weight*dx*dy;denominator+=s.weight*dx*dx;
  }
  const slope=numerator/denominator,halfWidth=480;
  // Symmetric orthographic camera: screen ground slope = sin(camera elevation).
  const elevation=Math.asin(slope),zScale=halfWidth*Math.sqrt(2*(1-slope*slope));
  const ref=data.references[0],referenceWallPixels=ref.wallHeight/ref.halfWidth*halfWidth;
  const references=data.references.map(r=>({...r,residuals:r.segments.map(s=>{
    const observed=s.b[1]-s.a[1],predicted=Math.abs(s.b[0]-s.a[0])*slope;
    return {axis:s.axis,errorPixels:Number((observed-predicted).toFixed(3))};
  })}));
  return {slope,halfWidth,zScale,referenceWallPixels,referenceWallHeight:referenceWallPixels/zScale,
    elevationDegrees:elevation*180/Math.PI,azimuthDegrees:45,references};
}
export function camera() {return roomStandard.camera;}
export function project(c,[x,y,z=0]) {
  return [c.origin[0]+x*c.bx[0]+y*c.by[0]+z*c.bz[0],
    c.origin[1]+x*c.bx[1]+y*c.by[1]+z*c.bz[1]];
}
export function unproject(c,[u,v],z=0) {
  const a=u-c.origin[0]-z*c.bz[0],b=v-c.origin[1]-z*c.bz[1];
  const det=c.bx[0]*c.by[1]-c.by[0]*c.bx[1];
  return [(a*c.by[1]-c.by[0]*b)/det,(c.bx[0]*b-a*c.bx[1])/det];
}
export function rotateMask(mask) {
  const points=mask.map(([x,y])=>[-y,x]);
  const minX=Math.min(...points.map(p=>p[0])),minY=Math.min(...points.map(p=>p[1]));
  return points.map(([x,y])=>[x-minX,y-minY]);
}
export function connected(mask) {
  if(!mask.length)return false;
  const keys=new Set(mask.map(p=>p.join(',')));
  if(keys.size!==mask.length)return false;
  const seen=new Set(),todo=[mask[0]];
  while(todo.length){const[x,y]=todo.pop(),key=[x,y].join(',');if(seen.has(key))continue;seen.add(key);
    for(const[dx,dy]of[[1,0],[-1,0],[0,1],[0,-1]]){const p=[x+dx,y+dy],k=p.join(',');if(keys.has(k)&&!seen.has(k))todo.push(p);}}
  return seen.size===mask.length;
}
export function validCells(cells,a) {
  return cells.every(([x,y])=>Number.isInteger(x)&&Number.isInteger(y)&&x>=0&&y>=0&&x<a&&y<a);
}
export function rectCells(rect,a) {
  const{x,y,w,d}=rect,cells=[];
  for(let i=Math.floor(x*a+1e-9);i<Math.ceil((x+w)*a-1e-9);i++)
    for(let j=Math.floor(y*a+1e-9);j<Math.ceil((y+d)*a-1e-9);j++)cells.push([i,j]);
  return cells;
}
export const gridSize=roomStandard.gridSize,cellSize=roomStandard.floorSize/gridSize;
export const rug={x:cellSize,y:cellSize,w:6*cellSize,d:6*cellSize,r:.02};
// Anchors and rectangular footprints are grid coordinates; visual dimensions are world units.
// Center the complete horizontal silhouette, not just the legs or the screen image.
export function centerFixture(f) {
  const [gx,gy]=f.anchor,cells=[];
  for(let x=gx;x<gx+f.cols;x++)for(let y=gy;y<gy+f.rows;y++)cells.push([x,y]);
  return {...f,x:(gx+f.cols/2)*cellSize-f.w/2,y:(gy+f.rows/2)*cellSize-f.d/2,cells};
}
export const fixtures=[
  {id:'bookshelf',label:'书柜',anchor:[0,1],cols:1,rows:3,w:.12,d:.26,h:3*cellSize,facing:'x'},
  {id:'desk',label:'书桌',anchor:[4,2],cols:3,rows:2,w:.30,d:.17,h:.18,facing:'y'},
  {id:'chair',label:'椅子',anchor:[5,1],cols:1,rows:1,w:.12,d:.115,h:.20,facing:'y'},
  {id:'tree',label:'猫爬架',anchor:[0,5],cols:2,rows:2,w:.17,d:.17,h:.29,facing:'x'},
  {id:'bed',label:'猫窝',anchor:[5,6],cols:2,rows:2,w:.19,d:.19,h:.085,facing:'y'}
].map(centerFixture);
// Lower both windows and flanking artwork while retaining a small sill clearance.
const windowH=1.7*cellSize,windowZ=3.2*cellSize,artH=cellSize;
const artZ=windowZ+(windowH-artH)/2;
export const slots=[
  {id:'window-left',label:'左窗',wall:'left',s:.5,z:windowZ,w:.32,h:windowH,type:'window'},
  {id:'window-right',label:'右窗',wall:'right',s:.5,z:windowZ,w:.32,h:windowH,type:'window'},
  {id:'art-left-back',label:'左墙画位 1',wall:'left',s:.18,z:artZ,w:.16,h:artH,type:'art'},
  {id:'art-left-front',label:'左墙画位 2',wall:'left',s:.82,z:artZ,w:.16,h:artH,type:'art'},
  {id:'art-right-back',label:'右墙画位 1',wall:'right',s:.18,z:artZ,w:.16,h:artH,type:'art'},
  {id:'art-right-front',label:'右墙画位 2',wall:'right',s:.82,z:artZ,w:.16,h:artH,type:'art'}
];
export function orient(f,facing) {
  return centerFixture(facing===f.facing?{...f,facing}:{...f,w:f.d,d:f.w,cols:f.rows,rows:f.cols,facing});
}
export function box(x,y,z,w,d,h,color='#e2dccf',kind='solid') {return{x,y,z,w,d,h,color,kind};}
export function boxFaces(b) {
  const{x,y,z,w,d,h,color}=b,X=x+w,Y=y+d,Z=z+h;
  return [[[X,y,z],[X,Y,z],[X,Y,Z],[X,y,Z]],[[x,Y,z],[X,Y,z],[X,Y,Z],[x,Y,Z]],[[x,y,Z],[X,y,Z],[X,Y,Z],[x,Y,Z]]].map(points=>({points,color}));
}
export function sortBoxes(boxes,c) {
  const hull=b=>[[b.x,b.y,b.z+b.h],[b.x+b.w,b.y,b.z+b.h],[b.x+b.w,b.y,b.z],[b.x+b.w,b.y+b.d,b.z],[b.x,b.y+b.d,b.z],[b.x,b.y+b.d,b.z+b.h]].map(p=>project(c,p));
  const overlap=(a,b)=>{
    for(const poly of[a,b])for(let i=0;i<poly.length;i++){const p=poly[i],q=poly[(i+1)%poly.length],axis=[q[1]-p[1],p[0]-q[0]];
      const A=a.map(v=>v[0]*axis[0]+v[1]*axis[1]),B=b.map(v=>v[0]*axis[0]+v[1]*axis[1]);
      if(Math.max(...A)<=Math.min(...B)+1e-8||Math.max(...B)<=Math.min(...A)+1e-8)return false;}
    return true;
  };
  const behind=(a,b)=>a.x+a.w<=b.x+1e-8||a.y+a.d<=b.y+1e-8||a.z+a.h<=b.z+1e-8;
  const nodes=boxes.map(b=>({b,hull:hull(b),next:[],count:0}));
  for(let i=0;i<nodes.length;i++)for(let j=i+1;j<nodes.length;j++){const a=nodes[i],b=nodes[j];if(!overlap(a.hull,b.hull))continue;
    const ab=behind(a.b,b.b),ba=behind(b.b,a.b);if(ab&&!ba){a.next.push(b);b.count++;}else if(ba&&!ab){b.next.push(a);a.count++;}}
  const queue=nodes.filter(n=>!n.count),result=[];
  while(queue.length){const n=queue.shift();result.push(n.b);for(const next of n.next)if(--next.count===0)queue.push(next);}
  if(result.length!==boxes.length)throw Error('结构实体的遮挡关系存在环，需检查实体相交');
  return result;
}
