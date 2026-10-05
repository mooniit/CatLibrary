// Moon Orbit: independent, deterministic assets in the frozen world coordinate system.
import {camera,project,fixtures,orient,slots,rug,roomStandard} from './geometry.mjs';
export const palette={cream:'#f4e9d3',ivory:'#fff7e8',edge:'#c9bba2',navy:'#233c60',blue:'#36557b',gold:'#c6a05e',ink:'#786950',wall:'#f5eddf',floor:'#eee1c9'};
const C=palette,TAU=Math.PI*2;
const lerp=(a,b,t)=>a.map((v,i)=>v+(b[i]-v)*t);
const normal=p=>p.reduce((n,a,i)=>{const b=p[(i+1)%p.length];return[n[0]+(a[1]-b[1])*(a[2]+b[2]),n[1]+(a[2]-b[2])*(a[0]+b[0]),n[2]+(a[0]-b[0])*(a[1]+b[1])];},[0,0,0]);
const hex=(color,k)=>'#'+color.slice(1).match(/../g).map(v=>Math.max(0,Math.min(255,Math.round(parseInt(v,16)*k))).toString(16).padStart(2,'0')).join('');
function mesh(){return {faces:[],lines:[],images:[],topcoat:[]};}
function face(m,p,color){m.faces.push({points:p,color});}
function path(m,p,color=C.gold,width=1,closed=false){m.lines.push({points:p,color,width,closed});}
export function rounded(x,y,w,d,r,z=0){const p=[];for(const[a,b,start]of[[x+w-r,y+r,-90],[x+w-r,y+d-r,0],[x+r,y+d-r,90],[x+r,y+r,180]])for(let i=0;i<=10;i++){const t=(start+i*9)*Math.PI/180;p.push([a+r*Math.cos(t),b+r*Math.sin(t),z]);}return p;}
function extrusion(m,base,delta,color){
  const top=base.map(p=>p.map((v,i)=>v+delta[i]));
  face(m,base.toReversed(),color);face(m,top,color);
  for(let i=0;i<base.length;i++){const j=(i+1)%base.length;face(m,[base[i],base[j],top[j],top[i]],color);}
}
function slab(m,x,y,z,w,d,h,r,color=C.cream){extrusion(m,rounded(x,y,w,d,r,z),[0,0,h],color);}
function block(m,x,y,z,w,d,h,color=C.cream){slab(m,x,y,z,w,d,h,0,color);}
function ellipse(cx,cy,rx,ry,z,n=64){return Array.from({length:n},(_,i)=>{const t=i*TAU/n;return[cx+rx*Math.cos(t),cy+ry*Math.sin(t),z];});}
function cylinder(m,x,y,z,r,h,color=C.cream){extrusion(m,ellipse(x,y,r,r,z,32),[0,0,h],color);}
function leg(m,x,y,h,r=.008){
  const rings=[[0,r*.65],[.012,r*.75],[h*.65,r*.7],[h,r]].map(([z,R])=>ellipse(x+(h-z)*.025,y,R,R,z,20));
  for(let k=0;k<rings.length-1;k++)for(let i=0;i<20;i++){const j=(i+1)%20;face(m,[rings[k][i],rings[k][j],rings[k+1][j],rings[k+1][i]],k===0?C.gold:C.cream);}
  face(m,rings.at(-1),C.cream);face(m,rings[0].toReversed(),C.gold);
}
function pillow(m,x,y,z,w,d,h){
  // A padded, rounded cover with fixed material shading; no cast shadow or scene light.
  const rings=[];
  for(let k=0;k<=7;k++){const t=k/7*Math.PI/2,R=Math.cos(t);rings.push(ellipse(x+w/2,y+d/2,w/2*R,d/2*R,z+h*Math.sin(t),48));}
  for(let k=0;k<7;k++)for(let i=0;i<48;i++){const j=(i+1)%48;face(m,[rings[k][i],rings[k][j],rings[k+1][j],rings[k+1][i]],C.blue);}
  path(m,ellipse(x+w/2,y+d/2,w/2,d/2,z),C.navy,.9,true);
  for(const t of[-.38,.38]){
    const p=[];for(let i=0;i<=28;i++){const a=-Math.sqrt(1-t*t)+2*Math.sqrt(1-t*t)*i/28;p.push([x+w/2+a*w/2,y+d/2+t*d/2,z+h*Math.sqrt(Math.max(0,1-a*a-t*t))+.0001]);}path(m,p,C.navy,.7);
  }
  for(const [a,b]of[[-.24,-.24],[.24,.24]])cylinder(m,x+w/2+a*w,y+d/2+b*d,z+h*Math.sqrt(1-4*a*a-4*b*b),.0018,.001,C.gold);
}
function moon(m,plane,v,z,r){
  const p=[];for(let i=0;i<=32;i++){const a=(60+i*240/32)*Math.PI/180;p.push([plane,v+r*Math.cos(a),z+r*Math.sin(a)]);}
  for(let i=32;i>=0;i--){const a=(82+i*196/32)*Math.PI/180;p.push([plane,v+r*.47+r*.84*Math.cos(a),z+r*.84*Math.sin(a)]);}face(m,p,C.gold);
}
function star(m,u,v,z,r){face(m,[[u,v,z+r],[u,v+r*.24,z+r*.24],[u,v+r,z],[u,v+r*.24,z-r*.24],[u,v,z-r],[u,v-r*.24,z-r*.24],[u,v-r,z],[u,v-r*.24,z+r*.24]],C.gold);}
function crest(m,u,v,z,w,h,t){
  const p=[[u,v,z],[u,v+w,z]];for(let i=0;i<=40;i++){const a=i*Math.PI/40;p.push([u,v+w/2+w/2*Math.cos(a),z+h*Math.sin(a)]);}extrusion(m,p,[t,0,0],C.cream);
  path(m,p.slice(1).map(([x,y,Z])=>[x+t,y,Z]),C.gold,1.15);
}
function cradle(m,cx,cy,z,rx,ry,height){
  const n=72,outer=[],inner=[];
  for(let i=0;i<n;i++){const t=i*TAU/n,back=(1-Math.cos(t))/2,h=.014+(height-.014)*back*back;
    outer.push([cx+rx*Math.cos(t),cy+ry*Math.sin(t),z+h]);inner.push([cx+(rx-.009)*Math.cos(t),cy+(ry-.009)*Math.sin(t),z+h-.003]);}
  for(let i=0;i<n;i++){const j=(i+1)%n,a=outer[i],b=outer[j],A=inner[i],B=inner[j];
    face(m,[[a[0],a[1],z],[b[0],b[1],z],b,a],C.cream);
    face(m,[a,b,B,A],C.ivory);
    face(m,[A,B,[B[0],B[1],z],[A[0],A[1],z]],C.navy);
  }
  path(m,outer,C.gold,1.1,true);path(m,inner,C.edge,.6,true);
}
function buildLocal(f){
  const m=mesh(),D=f.facing==='x'?f.w:f.d,W=f.facing==='x'?f.d:f.w,H=f.h;
  if(f.id==='bookshelf'){
    // Three shelves, solid side panels, a deep inset back and an arched cornice.
    block(m,0,.009,.012,.009,W-.018,H-.058,C.navy);
    slab(m,0,0,0,D,W,.017,.008);
    for(const v of[0,W-.016])block(m,.004,v,.017,D-.004,.016,H-.05);
    for(const z of[.119,.232,H-.052])slab(m,.006,.012,z,D-.006,W-.024,.012,.003);
    crest(m,D-.023,.004,H-.052,W-.008,.052,.023);
    moon(m,D,W/2,H-.028,.014);
    for(const [row,z]of[.017,.131,.244].entries()){
      let v=.028;for(let i=0;i<7;i++){const bw=[.019,.022,.016,.024,.017,.022,.019][i],bh=.064+((i+row)%3)*.009;
        block(m,.035,v,z,.069,bw,bh,(i+row)%4===0?C.cream:(i%2?C.navy:C.blue));
        for(const zz of[z+.008,z+bh-.008])path(m,[[.1042,v+.003,zz],[.1042,v+bw-.003,zz]],C.gold,.6);
        v+=bw+.006;
      }
    }
    for(const v of[.008,W-.008])path(m,[[D,v,.026],[D,v,H-.045]],C.gold,.8);
  }else if(f.id==='desk'){
    for(const u of[.019,D-.019])for(const v of[.024,W-.024])leg(m,u,v,H-.023,.009);
    block(m,D-.016,.025,H-.050,.012,W-.050,.026);
    path(m,[[D-.0039,.035,H-.045],[D-.0039,W-.035,H-.045]],C.edge,.7);
    moon(m,D-.0038,W/2,H-.035,.006);
    slab(m,0,0,H-.023,D,W,.0222,.025);
    path(m,rounded(.003,.003,D-.006,W-.006,.023,H-.012),C.gold,1.1,true);
    slab(m,.014,.016,H-.0008,D-.028,W-.032,.0008,.016,C.navy);
    path(m,rounded(.019,.021,D-.038,W-.042,.012,H),C.gold,.8,true);
    // Nothing stands above this surface: draw the continuous leather topcoat once,
    // after the body, to avoid subdivision seams across the flat desk inlay.
    m.topcoat.push({points:rounded(.014,.016,D-.028,W-.032,.016,H),color:C.navy});
    m.topcoat.push({points:rounded(.019,.021,D-.038,W-.042,.012,H),color:C.gold,width:.8});
  }else if(f.id==='chair'){
    for(const u of[.019,D-.019])for(const v of[.019,W-.019])leg(m,u,v,.089,.0065);
    slab(m,0,0,.084,D,W,.014,.025);
    pillow(m,.006,.006,.098,D-.012,W-.012,.014);
    // Curved barrel shell opening toward +u. The back is tall, arms fall toward the front.
    const n=48,outer=[],inner=[];
    for(let i=0;i<=n;i++){const t=(65+i*230/n)*Math.PI/180,h=.12+.08*((1-Math.cos(t))/2);
      outer.push([D/2+(D/2)*Math.cos(t),W/2+(W/2)*Math.sin(t),h]);inner.push([D/2+(D/2-.007)*Math.cos(t),W/2+(W/2-.007)*Math.sin(t),h-.004]);}
    for(let i=0;i<n;i++){const a=outer[i],b=outer[i+1],A=inner[i],B=inner[i+1];face(m,[[a[0],a[1],.096],[b[0],b[1],.096],b,a],C.cream);face(m,[a,b,B,A],C.ivory);face(m,[A,B,[B[0],B[1],.108],[A[0],A[1],.108]],C.navy);}
    for(const i of[0,n]){const a=outer[i],b=inner[i];face(m,[[a[0],a[1],.096],a,b,[b[0],b[1],.108]],C.cream);}
    path(m,outer,C.gold,1.05);path(m,inner,C.blue,.8);
  }else if(f.id==='bed'){
    extrusion(m,ellipse(D/2,W/2,D/2,W/2,0),[0,0,.013],C.cream);
    pillow(m,.012,.012,.016,D-.024,W-.024,.027);
    cradle(m,D/2,W/2,.013,D/2,W/2,H-.013);
    path(m,ellipse(D/2,W/2,D/2-.001,W/2-.001,.009),C.gold,.9,true);
    // Small moon on the lower open front leaves the future cat unobstructed.
    moon(m,D,W/2,.021,.006);
  }else if(f.id==='tree'){
    slab(m,0,0,0,D,W,.017,.038);
    pillow(m,.012,.012,.017,D-.024,W-.024,.008);
    const posts=[[.043,.050,.027,.224],[.116,.112,.027,.102]];
    for(const[x,y,z,h]of posts){cylinder(m,x,y,z,.012,h,'#ddcba8');
      for(let k=0;k<Math.floor(h/.006);k++)path(m,ellipse(x,y,.0121,.0121,z+k*.006,32).slice(0,17),C.edge,.6);
      cylinder(m,x,y,z,.013,.008,C.gold);cylinder(m,x,y,z+h-.008,.013,.008,C.gold);
    }
    slab(m,.067,.059,.125,.096,.097,.010,.035);
    pillow(m,.073,.065,.135,.084,.085,.008);
    extrusion(m,ellipse(.066,.068,.062,.065,.239),[0,0,.012],C.cream);
    pillow(m,.014,.015,.251,.104,.106,.009);
    cradle(m,.066,.068,.251,.062,.065,H-.251);
    const orbit=[];for(let i=0;i<=48;i++){const t=i/48;orbit.push([.043+.073*t+.009*Math.sin(t*Math.PI),.050+.062*t,.226-.083*t]);}path(m,orbit,C.gold,2.5);
  }
  return m;
}
function transform(m,fn,reflect=false){for(const s of[...m.faces,...m.lines,...m.topcoat])s.points=s.points.map(fn);for(const s of m.images)s.points=s.points.map(fn);if(reflect)for(const s of m.faces)s.points.reverse();return m;}
export function furniture(f){return transform(buildLocal(f),([u,v,z])=>f.facing==='x'?[f.x+u,f.y+v,z]:[f.x+f.w-v,f.y+u,z]);}
export function bounds(m){const p=[...m.faces,...m.lines,...m.images,...m.topcoat].flatMap(s=>s.points);return{min:[0,1,2].map(i=>Math.min(...p.map(v=>v[i]))),max:[0,1,2].map(i=>Math.max(...p.map(v=>v[i])))};}
export const artwork={starry:{file:'../../assets/images/room/painting-starry.png',ratio:1424/1104,label:'猫爪星空'},pearl:{file:'../../assets/images/room/painting-pearl.png',ratio:1191/1320,label:'戴珍珠耳环的猫'}};
export function wallAsset(slot,kind='window',sources={}){
  const m=mesh(),W=slot.w,H=slot.h,D=.026,p=kind==='window'?.012:.005;
  let w=W,h=H,art;
  if(kind!=='window'){art=artwork[kind];const ratio=art.ratio;w=Math.min(W,H*ratio);h=w/ratio;}
  const v=(W-w)/2,z=(H-h)/2;
  block(m,-.004,v,z,D,w,p);block(m,-.004,v,z+h-p,D,w,p);
  for(const vv of[v,v+w-p])block(m,-.004,vv,z+p,D,p,h-2*p);
  path(m,[[D-.0039,v+p/2,z+p/2],[D-.0039,v+w-p/2,z+p/2],[D-.0039,v+w-p/2,z+h-p/2],[D-.0039,v+p/2,z+h-p/2]],C.gold,1,true);
  if(kind==='window'){
    block(m,0,-.01,-.008,.046,W+.02,.008);
    block(m,.004,W/2-.003,p,.014,.006,H-2*p);
    path(m,[[D-.0039,p,H-p],[D-.0039,W*.35,H-.028],[D-.0039,W*.65,H-.028],[D-.0039,W-p,H-p]],C.gold,1);
    moon(m,D-.0039,W/2,H-p/2,.0045);
  }else{
    block(m,.008,v+p,z+p,.008,w-2*p,h-2*p,C.navy);
    // Fit the original aspect within a mat; no cropping or anamorphic stretching.
    const iw=Math.min(w-2*p,(h-2*p)*art.ratio),ih=iw/art.ratio;
    m.images.push({points:[[.0161,v+(w-iw)/2,z+(h+ih)/2],[.0161,v+(w+iw)/2,z+(h+ih)/2],[.0161,v+(w-iw)/2,z+(h-ih)/2]],href:sources[kind]||art.file,label:art.label});
  }
  const start=slot.s-W/2;
  return transform(m,([u,v,z])=>slot.wall==='left'?[u,start+v,slot.z+z]:[start+v,u,slot.z+z],slot.wall==='right');
}
const fmt=n=>Number(n.toFixed(4));
const points=p=>p.map(v=>project(camera(),v).map(fmt).join(',')).join(' ');
let clipSerial=0;
// Painter order uses actual surface planes. Centroid sorting fails on curved upholstery,
// open shells and tiny inlays on large slabs, even with a correct camera.
function painter(items){
  const planes=items.filter(s=>s.type!=='line');if(!planes.length)return items;
  const root=planes[Math.floor(planes.length/2)],raw=normal(root.points),length=Math.hypot(...raw);
  if(length<1e-14)return items;
  const sign=raw[0]+raw[1]+raw[2]*(-2*camera().bx[1]/camera().bz[1])>=0?1:-1;
  const n=raw.map(v=>v/length*sign),d=n.reduce((sum,v,i)=>sum+v*root.points[0][i],0),side=p=>n.reduce((sum,v,i)=>sum+v*p[i],0)-d;
  const back=[],front=[],same=[];
  for(const item of items){if(item===root){same.push(item);continue;}const distances=item.points.map(side),low=Math.min(...distances),high=Math.max(...distances),e=1e-8;
    if(low>=-e&&high<=e){same.push(item);continue;}
    if(high<=e){back.push(item);continue;}if(low>=-e){front.push(item);continue;}
    const a=[],b=[],closed=item.type!=='line',count=closed?item.points.length:item.points.length-1;
    for(let i=0;i<count;i++){const j=(i+1)%item.points.length,p=item.points[i],q=item.points[j],dp=distances[i],dq=distances[j];
      if(dp>=-e)a.push(p);if(dp<=e)b.push(p);
      if((dp>e&&dq<-e)||(dp<-e&&dq>e)){const hit=lerp(p,q,dp/(dp-dq));a.push(hit);b.push(hit);}
    }
    if(!closed){const p=item.points.at(-1),dp=distances.at(-1);if(dp>=-e)a.push(p);if(dp<=e)b.push(p);}
    if(a.length>=(closed?3:2))front.push({...item,points:a});if(b.length>=(closed?3:2))back.push({...item,points:b});
  }
  same.sort((a,b)=>({face:0,image:1,line:2}[a.type]-{face:0,image:1,line:2}[b.type]));
  return [...painter(back),...same,...painter(front)];
}
export function renderMesh(m){
  const surfaces=m.faces.filter(s=>{const n=normal(s.points);return n[0]+n[1]+n[2]*(-2*camera().bx[1]/camera().bz[1])>1e-12;}).map(s=>{const n=normal(s.points),len=Math.hypot(...n),k=.88+.12*Math.max(0,n[2]/len)+.06*Math.max(0,n[0]/len);return {...s,type:'face',fill:hex(s.color,k)};});
  for(const s of m.images){const[a,b,c]=s.points;surfaces.push({...s,type:'image',original:s.points,points:[a,b,b.map((v,i)=>v+c[i]-a[i]),c]});}
  for(const s of m.lines){const p=s.closed?[...s.points,s.points[0]]:s.points;for(let i=0;i<p.length-1;i++)surfaces.push({...s,type:'line',points:[p[i],p[i+1]]});}
  return painter(surfaces).map(s=>{
    if(s.type==='face')return `<polygon points="${points(s.points)}" fill="${s.fill}" stroke="${s.fill}" stroke-width=".65" stroke-linejoin="round" shape-rendering="crispEdges"/>`;
    if(s.type==='line')return `<polyline points="${points(s.points)}" fill="none" stroke="${s.color}" stroke-width="${s.width}" stroke-linecap="round"/>`;
    const[a,b,c]=s.original.map(p=>project(camera(),p)),id='art-clip-'+clipSerial++;
    return `<defs><clipPath id="${id}"><polygon points="${points(s.points)}"/></clipPath></defs><g clip-path="url(#${id})"><image href="${s.href}" width="1" height="1" preserveAspectRatio="none" transform="matrix(${b[0]-a[0]} ${b[1]-a[1]} ${c[0]-a[0]} ${c[1]-a[1]} ${a[0]} ${a[1]})"><title>${s.label}</title></image></g>`;
  }).join('')+m.topcoat.map(s=>s.width?`<polygon points="${points(s.points)}" fill="none" stroke="${s.color}" stroke-width="${s.width}"/>`:`<polygon points="${points(s.points)}" fill="${s.color}"/>`).join('');
}
export function assetSvg(m,padding=6){
  const ps=[...m.faces,...m.lines,...m.images,...m.topcoat].flatMap(s=>s.points).map(p=>project(camera(),p));
  const x=Math.floor(Math.min(...ps.map(p=>p[0])))-padding,y=Math.floor(Math.min(...ps.map(p=>p[1])))-padding;
  const w=Math.ceil(Math.max(...ps.map(p=>p[0])))-x+padding,h=Math.ceil(Math.max(...ps.map(p=>p[1])))-y+padding;
  return{svg:`<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="${x} ${y} ${w} ${h}">${renderMesh(m)}</svg>`,viewBox:[x,y,w,h],screenGroundOrigin:project(camera(),[0,0,0]).map((v,i)=>v-[x,y][i])};
}
function polygon(p,color){return `<polygon points="${points(p)}" fill="${color}"/>`;}
function line(p,color,width=.8){return `<polyline points="${points(p)}" fill="none" stroke="${color}" stroke-width="${width}"/>`;}
export function floorAsset(){
  const m=mesh();block(m,0,0,-roomStandard.floorThickness,1,1,roomStandard.floorThickness,C.floor);
  for(let i=1;i<16;i++)path(m,[[i/16,0,.0001],[i/16,1,.0001]],'#d6c8b1',.65);
  for(let i=0;i<16;i++)for(let j=1;j<4;j++){const y=(j+(i%2)*.5)/4;if(y<1)path(m,[[i/16,y,.0001],[(i+1)/16,y,.0001]],'#d6c8b1',.65);}
  return m;
}
export function rugAsset(){
  const m=mesh();slab(m,rug.x,rug.y,.0008,rug.w,rug.d,.001,.04,C.navy);
  for(const inset of[.009,.017])path(m,rounded(rug.x+inset,rug.y+inset,rug.w-2*inset,rug.d-2*inset,.038,.0019),C.gold,inset===.009?1.15:.6,true);
  for(const radius of[.12,.245])path(m,ellipse(.5,.5,radius,radius,.0019,96),C.gold,.6,true);
  const moonPts=[];for(let i=0;i<=40;i++){const a=(55+i*250/40)*Math.PI/180;moonPts.push([.5+.054*Math.cos(a),.5+.054*Math.sin(a),.00195]);}for(let i=40;i>=0;i--){const a=(82+i*196/40)*Math.PI/180;moonPts.push([.525+.047*Math.cos(a),.5+.047*Math.sin(a),.00195]);}face(m,moonPts,C.gold);
  for(const t of[0,Math.PI*.68,Math.PI*1.32]){const x=.5+.245*Math.cos(t),y=.5+.245*Math.sin(t);face(m,[[x-.006,y,.00195],[x,y-.010,.00195],[x+.006,y,.00195],[x,y+.010,.00195]],C.gold);}
  return m;
}
export function wallMaterial(wall,enabled=true){
  const m=mesh(),t=roomStandard.wallThickness,H=camera().wallHeight,s=slots.find(s=>s.id==='window-'+wall);
  const add=(v,z,w,h)=>block(m,-t,v,z,t,w,h,C.wall);
  if(enabled){const a=s.s-s.w/2;add(0,0,a,H);add(a+s.w,0,1-a-s.w,H);add(a,0,s.w,s.z);add(a,s.z+s.h,s.w,H-s.z-s.h);}else add(0,0,1,H);
  // A shallow cream baseboard and one quiet brass line. No patterned wallpaper.
  block(m,0,0,0,.006,1,.032,C.cream);path(m,[[.0061,0,.032],[.0061,1,.032]],C.gold,.8);
  path(m,[[0,0,H],[0,1,H]],C.edge,1.2);path(m,[[0,1,0],[0,1,H]],C.edge,1.2);
  return wall==='left'?m:transform(m,([u,v,z])=>[v,u,z],true);
}
export function scene({facings={},grid=false,axes=false,hidden=[],leftWindow=true,rightWindow=true,art=true,rug:hasRug=true,assets=[],assetBase='lunar-assets/',wallDecor,windowMode='day'}={}){
  const staticArt=(id,fallback)=>{const a=assets.find(a=>a.id===id&&a.category!=='furniture');return a?`<image href="${assetBase+a.svg}" x="${a.viewBox[0]}" y="${a.viewBox[1]}" width="${a.viewBox[2]}" height="${a.viewBox[3]}"/>`:fallback();};
  let out=staticArt('floor',()=>renderMesh(floorAsset()));
  if(hasRug)out+=`<g data-asset="rug">${staticArt('rug',()=>renderMesh(rugAsset()))}</g>`;
  const items=fixtures.filter(f=>!hidden.includes(f.id)).map(f=>orient(f,facings[f.id]||f.facing));
  if(grid){for(let i=0;i<=8;i++){out+=line([[i/8,0,.003],[i/8,1,.003]],'#77899c',.8);out+=line([[0,i/8,.003],[1,i/8,.003]],'#77899c',.8);}for(const f of items)for(const[x,y]of f.cells)out+=polygon([[x/8,y/8,.004],[(x+1)/8,y/8,.004],[(x+1)/8,(y+1)/8,.004],[x/8,(y+1)/8,.004]],'#6a8aa12a');}
  out+=(leftWindow?staticArt('wall-left',()=>renderMesh(wallMaterial('left',true))):staticArt('wall-left-closed',()=>renderMesh(wallMaterial('left',false))))+(rightWindow?staticArt('wall-right',()=>renderMesh(wallMaterial('right',true))):staticArt('wall-right-closed',()=>renderMesh(wallMaterial('right',false))));
  for(const s of slots.filter(s=>s.type==='window'&&(s.wall==='left'?leftWindow:rightWindow)))if(windowMode&&assets.some(a=>a.id===`view-${s.wall}-${windowMode}`))out+=`<g data-window-view="${s.wall}" data-mode="${windowMode}">${staticArt(`view-${s.wall}-${windowMode}`,()=> '')}</g>`;
  for(const s of slots){if(s.type==='window'&&(s.wall==='left'?leftWindow:rightWindow))out+=`<g data-asset="${s.id}">${staticArt(s.id,()=>renderMesh(wallAsset(s)))}</g>`;else if(s.type==='art'&&art)out+=`<g data-asset="${s.id}">${wallDecor?wallDecor(s):renderMesh(wallAsset(s,s.id.endsWith('back')?'starry':'pearl'))}</g>`;}
  // Whole-object ordering from depth intervals, including the tall bookcase and wall fixtures.
  items.sort((a,b)=>(a.x+a.y+a.w/2+a.d/2)-(b.x+b.y+b.w/2+b.d/2));
  for(const f of items){const sprite=assets.find(a=>a.id===f.id+'-'+f.facing);let content;
    if(sprite){const p=project(camera(),[f.x,f.y,0]);content=`<image href="${assetBase+sprite.svg}" x="${p[0]-sprite.pixelGroundOrigin[0]}" y="${p[1]-sprite.pixelGroundOrigin[1]}" width="${sprite.viewBox[2]}" height="${sprite.viewBox[3]}"/>`;}else content=renderMesh(furniture(f));
    out+=`<g data-asset="${f.id}" data-facing="${f.facing}">${content}</g>`;
  }
  if(axes){for(const[p,label,color]of[[[1,0,0],'+X','#ae5650'],[[0,1,0],'+Y','#467b62'],[[0,0,camera().wallHeight],'+Z','#496d90']]){out+=line([[0,0,0],p],color,2);const[x,y]=project(camera(),p);out+=`<text x="${x+7}" y="${y-8}" font-size="17" fill="${color}">${label}</text>`;}}
  return out;
}
