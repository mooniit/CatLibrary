// Furniture-specific construction guides, in the unmodified room-standard-v1 world.
// This is new geometry, not a picture of any previous furniture design.
import {camera,project,fixtures,orient} from '../room-structure-2026-10-05/geometry.mjs';
import {rounded,assetSvg} from '../room-structure-2026-10-05/lunar-art.mjs';
const palettes={wood:{wood:'#e8bd78',trim:'#c49655',cloth:'#e8dfca',book:'#849173'},royal:{wood:'#805138',trim:'#d1ad67',cloth:'#862a3c',book:'#657d55',ivory:'#f1dfbf'}};
function extrusion(m,loop,delta,color){const n=[0,0,0];for(let i=0;i<loop.length;i++){const a=loop[i],b=loop[(i+1)%loop.length];n[0]+=(a[1]-b[1])*(a[2]+b[2]);n[1]+=(a[2]-b[2])*(a[0]+b[0]);n[2]+=(a[0]-b[0])*(a[1]+b[1]);}if(n.reduce((s,v,i)=>s+v*delta[i],0)<0)loop=loop.toReversed();const top=loop.map(p=>p.map((v,i)=>v+delta[i]));m.faces.push({points:loop.toReversed(),color},{points:top,color});for(let i=0;i<loop.length;i++){const j=(i+1)%loop.length;m.faces.push({points:[loop[i],loop[j],top[j],top[i]],color});}}
const slab=(m,x,y,z,w,d,h,c,r=.003)=>extrusion(m,rounded(x,y,w,d,Math.min(r,w/2,d/2),z),[0,0,h],c);
function cylinder(m,x,y,z,r,h,c){extrusion(m,Array.from({length:24},(_,i)=>{const t=i/24*Math.PI*2;return[x+r*Math.cos(t),y+r*Math.sin(t),z];}),[0,0,h],c);}
function beam(m,a,b,r,c){const u=b.map((v,i)=>v-a[i]),len=Math.hypot(...u),v=Math.abs(u[2]/len)>.95?[1,0,0]:[-u[1]/Math.hypot(u[0],u[1]),u[0]/Math.hypot(u[0],u[1]),0],n=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]].map(k=>k/len);
  const loop=[[-1,-1],[1,-1],[1,1],[-1,1]].map(([s,t])=>a.map((p,i)=>i===2&&a[2]===0?0:p+r*(s*v[i]+t*n[i])));extrusion(m,loop,u,c);
}
function pad(m,x,y,z,w,d,h,c){const rings=[];for(let j=0;j<6;j++){const t=j/6*Math.PI/2,rx=w/2*Math.cos(t),ry=d/2*Math.cos(t);rings.push(Array.from({length:32},(_,i)=>{const a=i/32*Math.PI*2;return[x+w/2+rx*Math.cos(a),y+d/2+ry*Math.sin(a),z+h*Math.sin(t)];}));}rings.push([[x+w/2,y+d/2,z+h]]);for(let j=0;j<5;j++)for(let i=0;i<32;i++){const k=(i+1)%32;m.faces.push({points:[rings[j][i],rings[j][k],rings[j+1][k],rings[j+1][i]],color:c});}for(let i=0;i<32;i++)m.faces.push({points:[rings[5][i],rings[5][(i+1)%32],rings[6][0]],color:c});}
const edge=(m,a,b,label,outer=false)=>{m.checkEdges.push({a,b,label,outer});};
function desk(m,f,c){const {w:W,d:D,h:H}=f;
  slab(m,0,0,H-.016,W,D,.016,c.wood,.006);
  for(const y of [.018,D-.018]){beam(m,[.014,y,0],[W/2-.018,y,H-.017],.009,c.wood);beam(m,[W-.014,y,0],[W/2+.018,y,H-.017],.009,c.wood);beam(m,[.025,y,.042],[W-.025,y,.042],.007,c.wood);}
  slab(m,W/2-.006,.018,.04,.012,D-.036,.012,c.wood,.001);
  edge(m,[W,0,H],[W,D,H],'desktop front +Y');edge(m,[0,0,H],[W,0,H],'desktop outer side +X',true);edge(m,[0,0,H],[0,D,H],'desktop rear +Y',true);
}
function panel(m,x,y,z,w,h,depth,c,r=.004){extrusion(m,rounded(y,z,w,h,r).map(([v,Z])=>[x,v,Z]),[depth,0,0],c);}
function royalLeg(m,x,y,h,r,c){const rings=[];for(let k=0;k<=16;k++){const t=k/16,z=h*t,dx=r*.7*Math.sin(t*Math.PI*2),R=r*(.60+.40*Math.sin(t*Math.PI)+.35*Math.exp(-t*12));rings.push(Array.from({length:20},(_,i)=>{const a=i/20*Math.PI*2;return[x+dx+R*Math.cos(a),y+R*Math.sin(a),z];}));}m.faces.push({points:rings[0].toReversed(),color:c},{points:rings.at(-1),color:c});for(let k=1;k<rings.length;k++)for(let i=0;i<20;i++){const j=(i+1)%20;m.faces.push({points:[rings[k-1][i],rings[k-1][j],rings[k][j],rings[k][i]],color:c});}}
function turned(m,x,y,z,r,h,c){const rings=Array.from({length:25},(_,k)=>{const t=k/24,R=r*(.66+.34*Math.cos(t*Math.PI*6));return Array.from({length:24},(_,i)=>{const a=i/24*Math.PI*2;return[x+R*Math.cos(a),y+R*Math.sin(a),z+h*t];});});m.faces.push({points:rings[0].toReversed(),color:c},{points:rings.at(-1),color:c});for(let k=1;k<rings.length;k++)for(let i=0;i<24;i++){const j=(i+1)%24;m.faces.push({points:[rings[k-1][i],rings[k-1][j],rings[k][j],rings[k][i]],color:c});}}
function books(m,x,y,z,w,d,h,c){let v=y;for(let i=0;i<6;i++){const thickness=d/9,height=h*(.75+.25*(i%3)/2);slab(m,x,v,z,w,thickness,height,[c.book,'#e4d6b7',c.wood][i%3],.001);v+=thickness+.002;}}
function bookshelf(m,f,c,royal){const{w:W,d:D,h:H}=f;
  if(!royal){for(const y of [.011,D-.011])for(const x of [.012,W-.012])beam(m,[x,y,0],[x<W/2?.026:W-.026,y,H-.010],.006,c.wood);for(const z of [.022,.128,.234]){slab(m,0,0,z,W,D,.012,c.wood,.004);books(m,.021,.027,z+.012,W-.041,D-.08,.075,c);edge(m,[W,.01,z+.012],[W,D-.01,z+.012],'shelf front +Y');}slab(m,.017,0,H-.012,W-.034,D,.012,c.wood,.004);edge(m,[.017,0,H],[W-.017,0,H],'top outer depth +X',true);}
  else{
    for(const x of [.014,W-.014])for(const y of [.017,D-.017])slab(m,x-.010,y-.012,0,.020,.024,.020,c.wood,.004);
    slab(m,.008,0,.019,W-.008,D,.025,c.wood,.003);slab(m,.006,0,.037,.008,D,H-.067,c.wood,.002);
    for(const y of [0,D-.018]){slab(m,.014,y,.040,W-.027,.018,H-.080,c.wood,.002);cylinder(m,W-.010,y+.009,.050,.008,H-.102,c.ivory);}
    for(const z of [.040,.133,.235])slab(m,.007,.018,z,W-.007,D-.036,.011,c.wood,.001);
    for(const y of [.026,D/2+.003]){panel(m,W-.006,y,.053,D/2-.033,.066,.006,c.wood,.002);panel(m,W-.005,y+.006,.059,D/2-.045,.052,.003,c.trim,.002);panel(m,W-.002,y+.008,.061,D/2-.049,.048,.002,c.wood,.002);}
    books(m,.019,.025,.144,W-.038,D-.072,.079,c);books(m,.019,.025,.246,W-.038,D-.072,.060,c);
    const arch=[];for(let i=0;i<=32;i++){const y=D*i/32,z=H-.057+.038*Math.sin(i/32*Math.PI);arch.push([y,z]);}for(let i=32;i>=0;i--){const y=D*i/32,z=H-.066+.038*Math.sin(i/32*Math.PI);arch.push([y,z]);}
    extrusion(m,arch.map(([y,z])=>[.008,y,z]),[W-.008,0,0],c.wood);panel(m,W-.008,D/2-.012,H-.025,.024,.025,.008,c.trim,.004);
    edge(m,[W,.023,.144],[W,D-.023,.144],'lower shelf +Y');edge(m,[W,.023,.246],[W,D-.023,.246],'upper shelf +Y');edge(m,[.008,D,H-.057],[W,D,H-.057],'visible canopy depth +X',true);
  }
}
function royalDesk(m,f,c){const{w:W,d:D,h:H}=f;
  const loop=[[.006,0],[W-.007,0]];for(let i=0;i<=24;i++){const y=D*i/24;loop.push([W-.014*Math.sin(i/24*Math.PI)**2,y]);}loop.push([.006,D]);extrusion(m,loop.map(([x,y])=>[x,y,H-.014]),[0,0,.014],c.wood);
  slab(m,.023,.019,H-.001,W-.047,D-.038,.001,c.cloth,.006);
  for(const x of [.021,W-.021])for(const y of [.023,D-.023])royalLeg(m,x,y,H-.044,.009,c.ivory);
  slab(m,.017,.010,H-.044,W-.034,D-.020,.030,c.wood,.006);
  for(const y of [.019,D/2+.006]){panel(m,W-.020,y,H-.040,D/2-.028,.023,.006,c.wood,.003);panel(m,W-.013,y+.004,H-.037,D/2-.036,.017,.001,c.trim,.002);panel(m,W-.012,y+.006,H-.035,D/2-.040,.013,.001,c.wood,.002);}
  edge(m,[.006,.01,H],[.006,D-.01,H],'desktop rear +Y',true);edge(m,[.016,0,H],[W-.016,0,H],'desktop side +X',true);edge(m,[.023,.026,H],[.023,D-.026,H],'leather inset +Y');
}
function chair(m,f,c,royal){const{w:W,d:D,h:H}=f,seat=.074;
  slab(m,.008,.006,seat-.012,W-.016,D-.012,.012,c.wood,royal?.006:.002);if(royal)pad(m,.012,.012,seat,W-.024,D-.024,.014,c.cloth);else slab(m,.012,.012,seat,W-.024,D-.024,.014,c.cloth,.008);
  for(const x of [.020,W-.020])for(const y of [.022,D-.022])royal?royalLeg(m,x,y,seat-.012,.007,c.ivory):beam(m,[x,y,0],[x+(x<W/2?.006:-.006),y,seat-.012],.005,c.wood);
  if(!royal){for(const y of [.018,D/2,D-.018])cylinder(m,.017,y,seat,.004,H-seat-.010,c.wood);panel(m,.012,.009,H-.018,D-.018,.018,.010,c.wood,.007);}
  else{const shape=(inset,front,color)=>{const loop=[];for(let i=0;i<=32;i++){const a=i/32*Math.PI*2;let y=D/2+(D/2-.008-inset)*Math.cos(a),z=seat+.043+(H-seat-.053-inset)*Math.sin(a);loop.push([.013+front,y,z]);}extrusion(m,loop,[.007,0,0],color);};shape(0,0,c.ivory);shape(.007,.007,c.trim);shape(.010,.011,c.cloth);panel(m,.014,D/2-.010,H-.013,.020,.013,.009,c.trim,.004);
    for(const y of [.013,D-.013]){cylinder(m,W-.027,y,seat+.002,.004,.044,c.ivory);beam(m,[.018,y,seat+.046],[W-.027,y,seat+.046],.004,c.ivory);}
  }
  if(royal)edge(m,[W-.009,.013,seat],[W-.009,D-.013,seat],'seat upper front +Y');else edge(m,[W-.008,.019,seat-.012],[W-.008,D-.019,seat-.012],'seat lower front +Y');edge(m,[.017,royal?.006:D-.006,royal?seat:seat-.012],[W-.017,royal?.006:D-.006,royal?seat:seat-.012],'visible seat side +X');if(!royal)for(const e of m.checkEdges)e.contrast='alpha';if(royal)edge(m,[.023,.013,seat+.050],[W-.034,.013,seat+.050],'armrest +X');else edge(m,[.012,.03,H],[.012,D-.03,H],'backrest outer rail +Y',true);
}
function bed(m,f,c,royal){const{w:W,d:D,h:H}=f;
  for(const x of [.018,W-.018])for(const y of [.018,D-.018])royal?royalLeg(m,x,y,.020,.007,c.ivory):cylinder(m,x,y,0,.007,.014,c.wood);
  slab(m,.004,.004,.012,W-.008,D-.008,.014,royal?c.ivory:c.wood,.009);pad(m,.013,.013,.026,W-.026,D-.026,.020,c.cloth);
  if(!royal){for(const y of [.013,D-.013])cylinder(m,.015,y,.025,.006,H-.025,c.wood);for(const z of [.046,.061,.076])panel(m,.010,.020,z,D-.040,.008,.009,c.wood,.003);}
  else{panel(m,.006,.012,.026,D-.024,H-.026,.010,c.ivory,.012);panel(m,.016,.020,.040,D-.040,H-.047,.004,c.cloth,.012);for(const y of [.012,D-.012]){slab(m,.008,y-.007,.026,W-.035,.014,.017,c.ivory,.006);turned(m,W-.029,y,.029,.006,.024,c.ivory);}panel(m,W-.015,D/2-.015,.013,.030,.012,.010,c.trim,.004);}
  edge(m,[W-.004,.018,.026],[W-.004,D-.018,.026],'bed front base +Y');edge(m,[.018,D-.004,.012],[W-.018,D-.004,.012],'bed visible lower side +X');edge(m,[W-.004,.020,.012],[W-.004,D-.020,.012],'bed lower front base +Y');
}
function tree(m,f,c,royal){const{w:W,d:D,h:H}=f;
  const terrace=(x,y,z,w,d)=>{if(royal)extrusion(m,Array.from({length:40},(_,i)=>{const t=i/40*Math.PI*2;return[x+w/2+w/2*Math.cos(t),y+d/2+d/2*Math.sin(t),z];}),[0,0,.009],c.ivory);else slab(m,x,y,z,w,d,.009,c.wood,.007);pad(m,x+.006,y+.006,z+.009,w-.012,d-.012,.007,c.cloth);};
  if(!royal){terrace(0,0,0,W,D);for(const[x,y,h]of[[.032,.035,H-.027],[W-.034,D-.035,.158],[W/2,D/2,.087]])cylinder(m,x,y,.016,.011,h-.016,c.wood);terrace(.006,.006,.095,W-.012,D-.054);terrace(W-.100,D-.095,.170,.097,.092);terrace(.002,.002,H-.027,.103,.100);slab(m,.003,.002,H-.020,.013,.100,.020,c.wood,.003);slab(m,.016,.002,H-.020,.089,.012,.020,c.wood,.003);slab(m,.016,.090,H-.020,.089,.012,.020,c.wood,.003);}
  else{for(const x of [.018,W-.018])for(const y of [.018,D-.018])slab(m,x-.012,y-.012,0,.024,.024,.017,c.wood,.004);slab(m,.004,.004,.014,W-.008,D-.008,.009,c.ivory,.005);slab(m,.008,.008,.016,W-.016,D-.016,.022,c.wood,.004);pad(m,.018,.018,.038,W-.036,D-.036,.008,c.cloth);turned(m,.036,.042,.038,.014,H-.072,c.wood);turned(m,W-.038,D-.038,.038,.013,.124,c.wood);terrace(W-.108,D-.110,.148,.100,.104);terrace(.008,.005,H-.034,.108,.104);
    const rim=[];for(let i=0;i<=24;i++){const t=Math.PI/2+i/24*Math.PI;rim.push([.062+.054*Math.cos(t),.057+.052*Math.sin(t),H-.019]);}for(let i=24;i>=0;i--){const t=Math.PI/2+i/24*Math.PI;rim.push([.062+.047*Math.cos(t),.057+.045*Math.sin(t),H-.019]);}extrusion(m,rim,[0,0,.019],c.ivory);
  }
  const baseZ=royal?.023:0;edge(m,[W-(royal?.004:0),.019,baseZ],[W-(royal?.004:0),D-.019,baseZ],'tree base front +Y');edge(m,[.019,D-(royal?.004:0),baseZ],[W-.019,D-(royal?.004:0),baseZ],'tree visible base side +X');
  if(!royal)edge(m,[W-.006,.015,.095],[W-.006,D-.062,.095],'tree lower terrace bottom +Y');else edge(m,[W-.008,.021,.038],[W-.008,D-.021,.038],'pedestal front +Y');
}
export function furnitureModel(theme,id){const f=orient(fixtures.find(f=>f.id===id),'x'),c=palettes[theme],m={faces:[],lines:[],images:[],topcoat:[],checkEdges:[]};
  const royal=theme==='royal';if(id==='desk')royal?royalDesk(m,f,c):desk(m,f,c);else if(id==='bookshelf')bookshelf(m,f,c,royal);else if(id==='chair')chair(m,f,c,royal);else if(id==='bed')bed(m,f,c,royal);else if(id==='tree')tree(m,f,c,royal);else throw Error('Missing new construction model '+theme+'/'+id);
  for(const face of m.faces)for(const p of face.points)for(let i=0;i<3;i++)if(p[i]<-1e-8||p[i]>[f.w,f.d,f.h][i]+1e-8)throw Error('Model outside declared dimensions '+theme+'/'+id);
  return{...m,fixture:f};
}
export function constructionGuide(theme,id){const model=furnitureModel(theme,id),asset=assetSvg(model),factor=3,viewBox=asset.viewBox;
  const svg=asset.svg.replace(/width="[^"]+" height="[^"]+"/,`width="${viewBox[2]*factor}" height="${viewBox[3]*factor}"`);
  return{svg,viewBox,dimensionsL:[model.fixture.w,model.fixture.d,model.fixture.h],pixelGroundOrigin:camera().origin.map((v,i)=>v-viewBox[i]),checkEdges:model.checkEdges.map(e=>({...e,screen:[e.a,e.b].map(p=>project(camera(),p).map((v,i)=>v-viewBox[i]))}))};
}
export function projectionHull(f,viewBox){const points=[];for(const x of [0,f.w])for(const y of [0,f.d])for(const z of [0,f.h])points.push(project(camera(),[x,y,z]).map((v,i)=>v-viewBox[i]));points.sort((a,b)=>a[0]-b[0]||a[1]-b[1]);const cross=(a,b,c)=>(b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]),half=ps=>{const out=[];for(const p of ps){while(out.length>1&&cross(out.at(-2),out.at(-1),p)<=0)out.pop();out.push(p);}return out;};return[...half(points).slice(0,-1),...half(points.toReversed()).slice(0,-1)];}
export function auditAlpha(rgba,guide){const f={w:guide.dimensionsL[0],d:guide.dimensionsL[1],h:guide.dimensionsL[2]},poly=projectionHull(f,guide.viewBox),W=guide.viewBox[2],H=guide.viewBox[3];let overflow=0,edge=0;for(let y=0;y<H;y++)for(let x=0;x<W;x++){const a=rgba[(y*W+x)*4+3];if(a>=4&&(x===0||y===0||x===W-1||y===H-1))edge++;if(a>=32&&!poly.every((p,i)=>{const q=poly[(i+1)%poly.length];return(q[0]-p[0])*(y+.5-p[1])-(q[1]-p[1])*(x+.5-p[0])>=-1.1*Math.hypot(q[0]-p[0],q[1]-p[1]);}))overflow++;}return{overflow,edge};}
