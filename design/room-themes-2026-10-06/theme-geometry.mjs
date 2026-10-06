// New theme silhouettes. Only the frozen projection and structural helpers are shared.
import {camera,project,slots} from '../room-structure-2026-10-05/geometry.mjs';
import {rounded,renderMesh,assetSvg,wallMaterial,floorAsset} from '../room-structure-2026-10-05/lunar-art.mjs';
export const themes={
  wood:{label:'简约木质',body:'#eac17d',light:'#ffe2a2',shade:'#be945b',edge:'#a37947',accent:'#bd9761',fabric:'#e8dfcb',wall:'#f4eddf'},
  royal:{label:'英式皇家',body:'#f6e8cd',light:'#fff6df',shade:'#d0b992',edge:'#876443',accent:'#c89b4b',fabric:'#7f2737',wall:'#f2e9d9'}
};
export const templates={landscape:{label:'横版',w:.20,h:.15},portrait:{label:'竖版',w:.15,h:.20},square:{label:'正方形',w:.175,h:.175}};
const mesh=()=>({faces:[],lines:[],images:[],topcoat:[],parts:[]});
const face=(m,points,color)=>m.faces.push({points,color});
function solid(m,loop,back,front,c){
  const area=loop.reduce((sum,p,i)=>{const q=loop[(i+1)%loop.length];return sum+p[0]*q[1]-q[0]*p[1];},0);if(area<0)loop=loop.toReversed();
  const a=loop.map(([v,z])=>[back,v,z]),b=loop.map(([v,z])=>[front,v,z]);
  face(m,a.toReversed(),c.shade);face(m,b,c.body);
  for(let i=0;i<a.length;i++){const j=(i+1)%a.length;face(m,[a[i],a[j],b[j],b[i]],i%3===0?c.light:c.body);}
}
function rail(m,v,z,w,h,c,royal=false){
  const levels=royal?[[-.004,.002],[0,0],[.005,.001],[.012,.002],[.017,.0002],[.022,.0012]]:[[-.004,.001],[0,0],[.017,0],[.022,.0015]];
  const rings=levels.map(([n,d])=>rounded(v+d,z+d,w-2*d,h-2*d,.0025).map(([V,Z])=>[n,V,Z]));
  face(m,rings[0].toReversed(),c.shade);face(m,rings.at(-1),c.body);
  for(let k=1;k<rings.length;k++)for(let i=0;i<rings[k].length;i++){const j=(i+1)%rings[k].length;face(m,[rings[k-1][i],rings[k-1][j],rings[k][j],rings[k][i]],royal&&k===4?c.accent:k===1?c.shade:k===rings.length-1?c.light:c.body);}
}
function relief(m,loop,c){solid(m,loop,.018,.022,{...c,body:c.accent,light:'#f3d596',shade:'#9f793c'});}
function leaf(m,v,z,s,c,angle=0){
  const rotate=([x,y])=>[v+s*(x*Math.cos(angle)-y*Math.sin(angle)),z+s*(x*Math.sin(angle)+y*Math.cos(angle))];
  const loop=[[0,1.8],[.3,1.1],[.8,1.2],[.52,.6],[1,.5],[.65,0],[.85,-.55],[.35,-.45],[.2,-1.2],[0,-1.7],[-.2,-1.2],[-.35,-.45],[-.85,-.55],[-.65,0],[-1,.5],[-.52,.6],[-.8,1.2],[-.3,1.1]].map(rotate);relief(m,loop,c);
  m.lines.push({points:[[0,-1.1],[0,.4],[0,1.35]].map(p=>{const[V,Z]=rotate(p);return[.0221,V,Z];}),color:'#f5dbac',width:.4});
}
export function casing(theme,w,h,window=false){
  const royal=theme==='royal',c=royal&&!window?{...themes[theme],body:'#825b3d',light:'#b48a58',shade:'#533823',accent:'#d8b477'}:themes[theme],p=royal?.016:.012,m=mesh(),top=royal?.031:p;
  rail(m,0,0,w,p,c,royal);rail(m,0,h-top,w,top,c,royal);
  rail(m,0,p,p,h-p-top,c,royal);rail(m,w-p,p,p,h-p-top,c,royal);
  if(royal){
    const crest=[[w/2-.014,h-.022],[w/2-.013,h-.011],[w/2-.006,h-.016],[w/2,h-.007],[w/2+.006,h-.016],[w/2+.013,h-.011],[w/2+.014,h-.022]];
    relief(m,crest,c);m.parts.push('raised crown crest');
    for(const v of [.008,w-.008])for(const z of [.012,h-.018])leaf(m,v,z,.0045,c,v<w/2?-.35:.35);
    for(const v of [.007,w-.007]){
      const loop=rounded(v-.001,p+.006,.002,h-p-top-.012,.0005).map(([V,Z])=>[.022,V,Z]);
      m.lines.push({points:loop,color:c.accent,width:.5,closed:true});
    }
    m.parts.push('profiled gilt collars','acanthus corner leaves');
  }else{
    // Grain is sparse and runs with each solid oak rail, with visible end joinery.
    for(const z of [.004,.008,h-.004,h-.008])m.lines.push({points:[[.0222,.008,z],[.0222,w-.008,z+.0008]],color:'#bc9256',width:.35});
    for(const v of [.004,w-.004])m.lines.push({points:[[.0222,v,.017],[.0222,v+.0007,h-.017]],color:'#bd975f',width:.4});
    m.parts.push('rounded oak rails','recessed mortise joint');
  }
  m.width=w;m.height=h;m.opening={left:p+.001,right:w-p-.001,bottom:p+.001,top:h-top-.001};
  if(window){
    for(const v of royal?[w/3,2*w/3]:[w/2])solid(m,rounded(v-.0025,p,.005,h-p-top,.001),-.002,.012,c);
    solid(m,rounded(p,h*(royal?.60:.49),w-2*p,.004,.001),-.002,.009,c);
    if(royal){
      const arch=[];for(let i=0;i<=32;i++){const t=i/32*Math.PI;arch.push([w/2+(w/2-p-.004)*Math.cos(t),h*.60+(h-top-h*.60-.004)*Math.sin(t)]);}
      for(let i=32;i>=0;i--){const t=i/32*Math.PI;arch.push([w/2+(w/2-p-.007)*Math.cos(t),h*.60+(h-top-h*.60-.007)*Math.sin(t)]);}
      solid(m,arch,.009,.015,{...c,body:c.accent,light:'#f4dba7'});m.parts.push('three-bay Georgian sash','raised fanlight arch');
    }else m.parts.push('four-pane oak sash','solid central mullion');
    m.parts.push('solid cross rail');
  }
  return m;
}
export function mounted(model,slot){
  const convert=([u,v,z])=>slot.wall==='left'?[u,slot.s-model.width/2+v,slot.z+z]:[slot.s-model.width/2+v,u,slot.z+z];
  return {...model,faces:model.faces.map(f=>({...f,points:(slot.wall==='right'?f.points.toReversed():f.points).map(convert)})),lines:model.lines.map(l=>({...l,points:l.points.map(convert)}))};
}
export function windowModel(theme,slot){
  const c=themes[theme],model=mounted(casing(theme,slot.w,slot.h,true),slot),W=slot.w+.032,D=.062,z=slot.z,s=slot.s-W/2;
  const loops=[[-.008,.001],[-.006,0],[-.001,0],[0,.001]].map(([dz,d])=>rounded(d,s+d,D-2*d,W-2*d,.003,z+dz));
  const convert=p=>slot.wall==='left'?p:[p[1],p[0],p[2]],add=(ps,color)=>face(model,(slot.wall==='left'?ps:ps.toReversed()).map(convert),color);
  add(loops[0].toReversed(),c.shade);add(loops.at(-1),c.light);
  for(let k=1;k<loops.length;k++)for(let i=0;i<loops[k].length;i++){const j=(i+1)%loops[k].length;add([loops[k-1][i],loops[k-1][j],loops[k][j],loops[k][i]],theme==='royal'&&k===2?c.accent:c.body);}
  model.parts.push(theme==='wood'?'rounded oak extended sill':'layered gilt extended sill');
  if(theme==='royal'){
    const apron=mesh();leaf(apron,0,-.003,.0018,c,Math.PI/2);
    // A small real relief on the sill front, not an ornament printed on a flat picture.
    for(const f of apron.faces)add(f.points.map(([u,v,Z])=>[.041+u,slot.s+v,slot.z+Z]),f.color);
    model.parts.push('small raised sill acanthus');
  }
  return model;
}
export function painted(model,theme){
  let svg=renderMesh(model);const colors=[...new Set([...svg.matchAll(/fill="(#[0-9a-f]{6})"/gi)].map(m=>m[1]))];
  const tone=(color,k)=>'#'+[1,3,5].map(i=>Math.min(255,Math.round(parseInt(color.slice(i,i+2),16)*k)).toString(16).padStart(2,'0')).join('');
  const defs=colors.map((color,i)=>`<linearGradient id="finish-${theme}-${i}" x2="0" y2="1"><stop stop-color="${tone(color,1.06)}"/><stop offset=".3" stop-color="${tone(color,1.09)}"/><stop offset="1" stop-color="${tone(color,.94)}"/></linearGradient>`).join('');
  for(const [i,color]of colors.entries())svg=svg.replaceAll(`fill="${color}"`,`fill="url(#finish-${theme}-${i})"`);return `<defs>${defs}</defs>`+svg;
}
export function modelSvg(model,theme){const a=assetSvg(model);return{viewBox:a.viewBox,svg:a.svg.replace(/(<svg[^>]*>)[\s\S]*(<\/svg>)/,'$1'+painted(model,theme)+'$2'),parts:model.parts,opening:model.opening};}
export function frameAsset(theme,key,wall){
  const t=templates[key],slot=slots.find(s=>s.id===`art-${wall}-back`),centerZ=slot.z+slot.h/2,local=casing(theme,t.w,t.h);
  return {...modelSvg(mounted(local,{...slot,z:centerZ-t.h/2}),theme),worldMountCenter:wall==='left'?[0,slot.s,centerZ]:[slot.s,0,centerZ],dimensionsL:[t.w,t.h,.026]};
}
export function flatFrame(theme,key){
  const t=templates[key],m=casing(theme,t.w,t.h),W=t.w*1600,H=t.h*1600,viewBox=[-6,-6,W+12,H+12];
  const normal=ps=>ps.reduce((sum,a,i)=>{const b=ps[(i+1)%ps.length];return sum+(a[1]-b[1])*(a[2]+b[2]);},0);
  const faces=m.faces.filter(f=>normal(f.points)>0).sort((a,b)=>a.points[0][0]-b.points[0][0]);
  return{viewBox,svg:`<svg xmlns="http://www.w3.org/2000/svg" width="${viewBox[2]}" height="${viewBox[3]}" viewBox="${viewBox.join(' ')}">${faces.map(f=>`<polygon points="${f.points.map(p=>[p[1]*1600,H-p[2]*1600].join(',')).join(' ')}" fill="${f.color}" stroke="${f.color}" stroke-width=".4"/>`).join('')}</svg>`,opening:m.opening,parts:m.parts};
}
export function material(theme,type,texture,open=true){
  const wall=type.startsWith('wall'),side=type.endsWith('left')?'left':'right',m=wall?wallMaterial(side,open):floorAsset(),a=assetSvg(m),point=(s,z)=>side==='left'?[.0001,s,z]:[s,.0001,z];
  const ps=wall?m.faces.filter(f=>f.points.every(p=>Math.abs(p[side==='left'?0:1])<1e-10)&&f.points.some(p=>p[2]>.1)).map(f=>f.points):[[[0,0,.0001],[1,0,.0001],[1,1,.0001],[0,1,.0001]]];
  const [A,B,C]=(wall?[point(0,camera().wallHeight),point(1,camera().wallHeight),point(0,0)]:[[0,0,.0001],[1,0,.0001],[0,1,.0001]]).map(p=>project(camera(),p));
  const id=`surface-${theme}-${type}-${open}`,matrix=`matrix(${B[0]-A[0]} ${B[1]-A[1]} ${C[0]-A[0]} ${C[1]-A[1]} ${A[0]} ${A[1]})`;
  const layer=`<defs><clipPath id="${id}">${ps.map(p=>`<polygon points="${p.map(q=>project(camera(),q).join(',')).join(' ')}"/>`).join('')}</clipPath></defs><g clip-path="url(#${id})"><image href="${texture}" width="1" height="1" preserveAspectRatio="none" transform="${matrix}"/></g>`;
  return{...a,svg:a.svg.replace('</svg>',layer+'</svg>')};
}
export function rugAsset(theme){
  const c=themes[theme],loop=rounded(.125,.125,.75,.75,.025,.0018),points=ps=>ps.map(p=>project(camera(),p).join(',')).join(' '),border=rounded(.14,.14,.72,.72,.021,.0019);
  const ps=loop.map(p=>project(camera(),p)),min=[0,1].map(i=>Math.floor(Math.min(...ps.map(p=>p[i])))-6),max=[0,1].map(i=>Math.ceil(Math.max(...ps.map(p=>p[i])))+6),viewBox=[...min,max[0]-min[0],max[1]-min[1]];
  let svg=`<defs><pattern id="weave-${theme}" width="3" height="3" patternUnits="userSpaceOnUse"><path d="M0 0L3 3" stroke="${theme==='wood'?'#b9a98c':'#b7717a'}" stroke-width=".3"/></pattern><clipPath id="rug-${theme}"><polygon points="${points(loop)}"/></clipPath></defs><polygon points="${points(loop)}" fill="${c.fabric}" stroke="${c.shade}" stroke-width="1.5"/><polygon points="${points(border)}" fill="none" stroke="${c.accent}" stroke-width="${theme==='wood'?1:2}"/><rect width="1080" height="1073" fill="url(#weave-${theme})" clip-path="url(#rug-${theme})" opacity=".28"/>`;
  if(theme==='royal')for(const r of [.09,.105])svg+=`<polygon points="${points(Array.from({length:64},(_,i)=>{const a=i/64*Math.PI*2;return[.5+r*Math.cos(a),.5+r*Math.sin(a),.002];}))}" fill="none" stroke="${c.accent}" stroke-width=".9"/>`;
  return{viewBox,svg:`<svg xmlns="http://www.w3.org/2000/svg" width="${viewBox[2]}" height="${viewBox[3]}" viewBox="${viewBox.join(' ')}">${svg}</svg>`};
}
export function skyAsset(slot,mode,source){
  const point=(s,z)=>slot.wall==='left'?[0,s,z]:[s,0,z],s0=slot.s-slot.w/2,z0=slot.z;
  const ps=[[s0,z0],[s0+slot.w,z0],[s0+slot.w,z0+slot.h],[s0,z0+slot.h]].map(([s,z])=>project(camera(),point(s,z)));
  // Screen-left of a left-wall picture is the larger wall coordinate. Keep the
  // image UVs upright instead of turning scenery and artworks into mirror images.
  const S=slot.wall==='left'?[s0+slot.w,s0]:[s0,s0+slot.w];
  const [A,B,C]=[[S[0],z0+slot.h],[S[1],z0+slot.h],[S[0],z0]].map(([s,z])=>project(camera(),point(s,z)));
  const matrix=[B[0]-A[0],B[1]-A[1],C[0]-A[0],C[1]-A[1],...A],crop=[slot.wall==='left'?80:360,slot.wall==='left'?70:200,1080,1080*slot.h/slot.w];
  const min=[0,1].map(i=>Math.floor(Math.min(...ps.map(p=>p[i])))-6),max=[0,1].map(i=>Math.ceil(Math.max(...ps.map(p=>p[i])))+6),viewBox=[...min,max[0]-min[0],max[1]-min[1]];
  return{viewBox,crop,imageMatrix:matrix,svg:`<svg xmlns="http://www.w3.org/2000/svg" width="${viewBox[2]}" height="${viewBox[3]}" viewBox="${viewBox.join(' ')}"><g data-window-mode="${mode}" transform="matrix(${matrix.join(' ')})"><svg width="1" height="1" viewBox="${crop.join(' ')}" preserveAspectRatio="none"><image href="${source}" width="1536" height="1024"/></svg></g></svg>`};
}
