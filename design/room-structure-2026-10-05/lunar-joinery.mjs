// Window and picture-frame construction. All ornament has real normal-axis thickness.
// There are no image skins in this module. The only raster permitted by its caller is artwork.
import {camera,project,slots} from './geometry.mjs';
import {rounded,renderMesh,assetSvg} from './lunar-art.mjs';
const C={cream:'#fff2d6',ivory:'#fff9e8',warm:'#eed7ae',gold:'#d8a545',bright:'#ffe5a0',navy:'#284262'};
const fresh=()=>({faces:[],lines:[],images:[],topcoat:[],parts:[]});
const face=(m,points,color)=>m.faces.push({points,color});
function part(m,name,fn){const first=m.faces.length;fn();m.parts.push({name,firstFace:first,faceCount:m.faces.length-first});}
function extrude(m,loop,back,front,color=C.cream){
  const a=loop.map(([v,z])=>[back,v,z]),b=loop.map(([v,z])=>[front,v,z]);
  face(m,[...a].reverse(),color);face(m,b,color);
  for(let i=0;i<a.length;i++){const j=(i+1)%a.length;face(m,[a[i],a[j],b[j],b[i]],color);}
}
function slab(m,v,z,w,h,back,front,radius,color=C.cream){
  const levels=[[back,.001],[back+.0025,0],[front-.0015,0],[front,.001]],rings=levels.map(([u,d])=>rounded(v+d,z+d,w-2*d,h-2*d,Math.min(radius,w/3,h/3)).map(([V,Z])=>[u,V,Z]));
  face(m,[...rings[0]].reverse(),C.warm);face(m,rings.at(-1),color);
  for(let k=1;k<rings.length;k++)for(let i=0;i<rings[k].length;i++){const j=(i+1)%rings[k].length;face(m,[rings[k-1][i],rings[k-1][j],rings[k][j],rings[k][i]],k===1?C.warm:k===2?color:C.ivory);}
}
function bead(m,points,radius=.0007,color=C.gold,normal=[1,0,0]){
  const count=8,rings=points.map((p,i)=>{
    const a=points[Math.max(0,i-1)],b=points[Math.min(points.length-1,i+1)],raw=b.map((v,k)=>v-a[k]),len=Math.hypot(...raw)||1,tangent=raw.map(v=>v/len),dot=tangent.reduce((s,v,k)=>s+v*normal[k],0),nn=normal.map((v,k)=>v-dot*tangent[k]),nl=Math.hypot(...nn)||1,n=nn.map(v=>v/nl),binormal=[tangent[1]*n[2]-tangent[2]*n[1],tangent[2]*n[0]-tangent[0]*n[2],tangent[0]*n[1]-tangent[1]*n[0]];
    return Array.from({length:count},(_,k)=>{const t=k/count*Math.PI*2;return p.map((v,j)=>v+radius*(n[j]*Math.cos(t)+binormal[j]*Math.sin(t)));});
  });
  for(let j=1;j<rings.length;j++)for(let i=0;i<count;i++){const k=(i+1)%count;face(m,[rings[j-1][i],rings[j-1][k],rings[j][k],rings[j][i]],i<3?C.bright:color);}
  face(m,[...rings[0]].reverse(),color);face(m,rings.at(-1),color);
}
function relief(m,loop,center,back,front){
  // Narrow bevel around a genuine solid ornament; raised face is smaller than its base.
  const a=loop.map(([v,z])=>[back,v,z]),b=loop.map(([v,z])=>[front,center[0]+(v-center[0])*.86,center[1]+(z-center[1])*.86]);
  face(m,[...a].reverse(),C.gold);face(m,b,C.gold);
  for(let i=0;i<a.length;i++){const j=(i+1)%a.length;face(m,[a[i],a[j],b[j],b[i]],i<loop.length/2?C.bright:'#ba8538');}
}
function moon(m,v,z,r,back=.0182,front=.022){
  const p=[];for(let i=0;i<=24;i++){const a=(60+i*240/24)*Math.PI/180;p.push([v+r*Math.cos(a),z+r*Math.sin(a)]);}for(let i=24;i>=0;i--){const a=(82+i*196/24)*Math.PI/180;p.push([v+r*.47+r*.84*Math.cos(a),z+r*.84*Math.sin(a)]);}relief(m,p,[v,z],back,front);
}
function profiledSlab(m,v,z,w,h,back,front){
  // Ogee shoulders and two gilt collars are actual cross-section changes on the side.
  const levels=[[back,.0021],[back+.0012,.0016],[back+.003,.0026],[back+.006,.0016],[back+.008,.001],[front-.006,.0011],[front-.0045,.0024],[front-.0025,.0013],[front-.0012,.0018],[front,.0023]],rings=levels.map(([u,d])=>rounded(v+d,z+d,w-2*d,h-2*d,.0028).map(([V,Z])=>[u,V,Z]));
  face(m,[...rings[0]].reverse(),C.warm);face(m,rings.at(-1),C.cream);
  for(let k=1;k<rings.length;k++)for(let i=0;i<rings[k].length;i++){const j=(i+1)%rings[k].length;face(m,[rings[k-1][i],rings[k-1][j],rings[k][j],rings[k][i]],k===2||k===7?C.gold:k===4||k===8?C.ivory:C.cream);}
}
function sideCartouches(m,w,h,cap){
  for(const right of [false,true])part(m,(right?'right':'left')+' carved side cartouche',()=>{
    const t=fresh(),z=cap+.008,H=h-2*z,U=.0025,W=.0115;
    extrude(t,rounded(U,z,W,H,.003),0,.00065,C.cream);
    const rim=rounded(U+.0006,z+.001,W-.0012,H-.002,.0027).map(([V,Z])=>[.0009,V,Z]);bead(t,[...rim,rim[0]],.00028);
    const cy=h/2,span=Math.min(.035,H*.32);
    bead(t,Array.from({length:33},(_,i)=>{const s=i/32;return[.001,.008+.0035*Math.sin(s*Math.PI*2),cy-span+s*span*2];}),.00028);
    for(const sign of [-1,1])bead(t,Array.from({length:17},(_,i)=>{const a=i/16*Math.PI*2;return[.001,.008+.0022*Math.sin(a),cy+sign*(span+.006)+.0032*Math.cos(a)];}),.00025);
    const convert=([n,u,z])=>[u,right?w-.0014+n:.0014-n,z];
    for(const f of t.faces)face(m,(right?[...f.points].reverse():f.points).map(convert),f.color);
  });
}
function star(m,v,z,r,back=.0182,front=.0217){relief(m,[[v,z-r],[v+r*.23,z-r*.23],[v+r,z],[v+r*.23,z+r*.23],[v,z+r],[v-r*.23,z+r*.23],[v-r,z],[v-r*.23,z-r*.23]],[v,z],back,front);}
function header(m,w,h,window){
  const edge=window?.024:.018,bottom=window?.045:.025,drop=window?.016:.008,n=32;
  const top=t=>h-drop*Math.cos(t*Math.PI)**2,lower=t=>h-bottom+(window?.004:0)*Math.sin(t*Math.PI);
  const loop=[[edge,lower(0)],[w-edge,lower(1)]];for(let i=n;i>=0;i--){const t=i/n;loop.push([edge+(w-2*edge)*t,top(t)]);}
  part(m,'curved solid header',()=>{
    extrude(m,loop,-.001,.018,C.cream);
    const arc=Array.from({length:n+1},(_,i)=>{const t=i/n;return[.0182,edge+(w-2*edge)*t,top(t)-.0012];});bead(m,arc,.0009);
    const rim=Array.from({length:n+1},(_,i)=>{const t=i/n;return[.0182,edge+(w-2*edge)*t,lower(t)+.001];});bead(m,rim,.00075);
  });
  part(m,'raised crescent',()=>moon(m,w/2,h-(window?.021:.013),window?.012:.0075));
  part(m,'header stars',()=>{for(const v of[w*.29,w*.71])star(m,v,h-(window?.025:.0165),window?.0038:.0025);});
}
export function joineryModel(w,h,kind='frame'){
  const m=fresh(),window=kind==='window',p=window?.015:.0155,cap=window?.023:.020;
  // Solid rails with shaped sections, not a four-sided image surface.
  part(m,'back top rail',()=>slab(m,0,h-.010,w,.010,-.004,.010,.002,C.cream));
  part(m,'left pilaster',()=>profiledSlab(m,0,0,p,h,-.004,.017));
  part(m,'right pilaster',()=>profiledSlab(m,w-p,0,p,h,-.004,.017));
  part(m,'lower rail',()=>profiledSlab(m,0,0,w,window?.014:.017,-.004,.017));
  sideCartouches(m,w,h,cap);
  part(m,'gold rail beads',()=>{
    for(const v of[.0025,w-.0025])bead(m,[[.017,v,.006],[.017,v,h-.006]],.00075);
    bead(m,[[.017,.006,.0025],[.017,w-.006,.0025]],.00075);
    bead(m,[[.017,p+.0005,window?.014:.017],[.017,w-p-.0005,window?.014:.017]],.00065);
  });
  header(m,w,h,window);
  for(const[i,[v,z]]of[[0,0],[w-cap,0],[0,h-cap],[w-cap,h-cap]].entries())part(m,'rounded corner cap '+i,()=>{
    slab(m,v,z,cap,cap,.008,.018,.004,C.cream);
    const rim=rounded(v+.0018,z+.0018,cap-.0036,cap-.0036,.003).map(([V,Z])=>[.018,V,Z]);bead(m,[...rim,rim[0]],.0007);
    star(m,v+cap/2,z+cap/2,cap*.23);
  });
  if(window){
    part(m,'solid center mullion',()=>slab(m,w/2-.003,.014,.006,h-.058,-.002,.015,.0015,C.cream));
    part(m,'mullion collars',()=>{for(const z of[.014,h-.048]){slab(m,w/2-.007,z,.014,.012,.009,.018,.003,C.cream);star(m,w/2,z+.006,.0028);}});
  }else{
    part(m,'lower star orbit',()=>{
      bead(m,Array.from({length:25},(_,i)=>{const t=i/24;return[.0175,.025+(w-.050)*t,.008+.002*Math.sin(t*Math.PI)];}),.0005);
      for(const v of[w*.32,w*.68])star(m,v,.0085,.0026,.0177,.021);
    });
    part(m,'recessed navy fillet',()=>{
      extrude(m,[[p,.017],[p+.001,.017],[p+.001,h-.025],[p,h-.025]],.008,.011,C.navy);
      extrude(m,[[w-p-.001,.017],[w-p,.017],[w-p,h-.025],[w-p-.001,h-.025]],.008,.011,C.navy);
    });
  }
  m.kind=kind;m.width=w;m.height=h;m.opening={left:p+.001,right:w-p-.001,bottom:window?.014:.018,top:h-(window?.045:.027)};return m;
}
export function mountJoinery(model,slot){
  const convert=([u,v,z])=>slot.wall==='left'?[u,slot.s-model.width/2+v,slot.z+z]:[slot.s-model.width/2+v,u,slot.z+z];
  const map=s=>({...s,points:(slot.wall==='right'?[...s.points].reverse():s.points).map(convert)});
  return{...model,faces:model.faces.map(map),lines:[],images:[],topcoat:[]};
}
let serial=0;
function paint(svg){
  const id='joinery-paint-'+serial++,colors=[...new Set([...svg.matchAll(/fill="(#[a-f0-9]{6})"/gi)].map(m=>m[1]))],defs=[];
  const blend=(a,b,t)=>'#'+[0,1,2].map(k=>Math.round(parseInt(a.slice(1+k*2,3+k*2),16)*(1-t)+parseInt(b.slice(1+k*2,3+k*2),16)*t).toString(16).padStart(2,'0')).join('');
  for(const[i,c]of colors.entries()){
    const gold=parseInt(c.slice(3,5),16)-parseInt(c.slice(5,7),16)>65,navy=parseInt(c.slice(5,7),16)>parseInt(c.slice(1,3),16);if(navy)continue;
    const name=id+'-'+i;defs.push(`<linearGradient id="${name}" x1="0" y1="0" x2=".3" y2="1"><stop stop-color="${blend(c,'#fffae8',gold?.38:.17)}"/><stop offset=".24" stop-color="${c}"/><stop offset=".48" stop-color="${blend(c,'#fff7dc',gold?.25:.12)}"/><stop offset="1" stop-color="${blend(c,'#a77b40',gold?.18:.07)}"/></linearGradient>`);svg=svg.replaceAll('fill="'+c+'"','fill="url(#'+name+')"');
  }
  return `<defs>${defs.join('')}</defs>`+svg;
}
export function renderJoinery(model){return paint(renderMesh(model));}
export function frontTemplate(model){
  const W=model.width*1600,H=model.height*1600,vb=[-6,-6,W+12,H+12];
  const normalX=p=>p.reduce((n,a,i)=>{const b=p[(i+1)%p.length];return n+(a[1]-b[1])*(a[2]+b[2]);},0);
  const faces=model.faces.filter(f=>normalX(f.points)>1e-12).sort((a,b)=>a.points.reduce((s,p)=>s+p[0],0)/a.points.length-b.points.reduce((s,p)=>s+p[0],0)/b.points.length);
  const svg=paint(faces.map(f=>`<polygon points="${f.points.map(p=>[p[1]*1600,H-p[2]*1600].join(',')).join(' ')}" fill="${f.color}" stroke="${f.color}" stroke-width=".4"/>`).join(''));
  return{viewBox:vb,svg:`<svg xmlns="http://www.w3.org/2000/svg" width="${vb[2]}" height="${vb[3]}" viewBox="${vb.join(' ')}">${svg}</svg>`};
}
export const windowSill=Object.freeze({overhang:.016,depth:.064,bodyDepth:.062,thickness:.008});
export function windowModel(slot=slots.find(s=>s.id==='window-left')){
  const local=joineryModel(slot.w,slot.h,'window'),world=mountJoinery(local,slot),s=slot.s-slot.w/2-windowSill.overhang,W=slot.w+windowSill.overhang*2,D=windowSill.bodyDepth,loops=[[.0015,slot.z-.008],[.0004,slot.z-.007],[.0015,slot.z-.0058],[.0003,slot.z-.0048],[0,slot.z-.0035],[.0013,slot.z-.002],[.002,slot.z]].map(([d,z])=>rounded(d,s+d,D-2*d,W-2*d,.005,z));
  const convert=p=>slot.wall==='left'?p:[p[1],p[0],p[2]],add=(points,color)=>face(world,(slot.wall==='left'?points:[...points].reverse()).map(convert),color);
  part(world,'rounded solid sill',()=>{
    for(let k=1;k<loops.length;k++)for(let i=0;i<loops[k].length;i++){const j=(i+1)%loops[k].length;add([loops[k-1][i],loops[k-1][j],loops[k][j],loops[k][i]],k===2||k===5?C.gold:k===1?C.warm:C.cream);}
    add(loops.at(-1),C.ivory);add([...loops[0]].reverse(),C.warm);
  });
  const ornament=fresh();
  part(ornament,'sill upper orbit and rounded brass rim',()=>{
    const rim=rounded(.003,s+.003,D-.006,W-.006,.004,slot.z+.00015);bead(ornament,[...rim,rim[0]],.00045,C.gold,[0,0,1]);
    bead(ornament,Array.from({length:33},(_,i)=>{const t=i/32;return[.049+.003*Math.sin(t*Math.PI),s+.018+(W-.036)*t,slot.z+.0002];}),.00035,C.gold,[0,0,1]);
  });
  part(ornament,'sill crescent apron',()=>{
    moon(ornament,slot.s,slot.z-.004,.0027,.0616,.0632);
    for(const offset of [-.085,.085])star(ornament,slot.s+offset,slot.z-.004,.0016,.0616,.063);
    bead(ornament,Array.from({length:33},(_,i)=>{const t=i/32;return[.0622,s+.014+(W-.028)*t,slot.z-.0045+.0007*Math.sin(t*Math.PI*2)];}),.00035);
  });
  for(const right of [false,true])part(ornament,(right?'right':'left')+' sill end scroll',()=>{
    const t=fresh();bead(t,Array.from({length:25},(_,i)=>{const a=i/24;return[.0007,.010+.041*a,slot.z-.005+.0009*Math.sin(a*Math.PI*2)];}),.0003);
    for(const f of t.faces)face(ornament,(right?[...f.points].reverse():f.points).map(([n,u,z])=>[u,right?s+W-.0012+n:s+.0012-n,z]),f.color);
  });
  for(const p of ornament.parts){const firstFace=world.faces.length;for(const f of ornament.faces.slice(p.firstFace,p.firstFace+p.faceCount))add(f.points,f.color);world.parts.push({...p,firstFace});}
  world.sill={...windowSill,width:W};return world;
}
export function cornerModel(){
  const m=fresh(),R=.009,H=camera().wallHeight,n=20,loop=[[0,0,0]];
  for(let i=0;i<=n;i++){const t=i/n*Math.PI/2;loop.push([R*Math.cos(t),R*Math.sin(t),0]);}
  face(m,[...loop].reverse(),C.warm);face(m,loop.map(([x,y])=>[x,y,H]),C.ivory);
  for(let i=0;i<loop.length;i++){const j=(i+1)%loop.length;face(m,[loop[i],loop[j],[loop[j][0],loop[j][1],H],[loop[i][0],loop[i][1],H]],C.cream);}
  m.parts.push({name:'quarter-round inner corner',faceCount:m.faces.length});m.radius=R;return m;
}
export function cornerSvg(){const m=cornerModel(),a=assetSvg(m);return{...a,svg:a.svg.replace(/(<svg[^>]*>)[\s\S]*(<\/svg>)/,'$1'+renderJoinery(m)+'$2')};}
