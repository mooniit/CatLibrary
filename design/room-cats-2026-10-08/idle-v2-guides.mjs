// Current user prototype: calico only, fixed body, two idle poses, tail motion only.
import {camera,project} from '../room-structure-2026-10-05/geometry.mjs';
import {writeFileSync,mkdirSync} from 'node:fs';
const c=camera(), origin=project(c,[0,0,0]);
mkdirSync(new URL('../../.tooling/',import.meta.url),{recursive:true});
const poses=[];
for(const pose of ['standing','curled']){
  const parts=[],tail=[],contacts=[];
  const P=(p,tile=0)=>{const v=project(c,p);return [512+1024*tile+(v[0]-origin[0])*8,760+(v[1]-origin[1])*8];};
  function ball(list,center,radii,tint='#b9c8d0',tile=0){
    const points=[];
    for(let i=0;i<=24;i++)for(let j=0;j<48;j++){
      const a=Math.PI*i/24,b=Math.PI*2*j/48;
      points.push(P(center.map((v,k)=>v+radii[k]*[Math.sin(a)*Math.cos(b),Math.sin(a)*Math.sin(b),Math.cos(a)][k]),tile));
    }
    list.push({points,tint});
  }
  function paw(x,y){ball(parts,[x,y,.006],[.01,.007,.006],'#dde5e8');contacts.push(P([x,y,0]));}
  const standing=pose==='standing', head=standing?[.035,0,.105]:[.032,-.005,.036];
  if(standing){
    for(const x of [-.027,.027])for(const y of [-.017,.017]){
      ball(parts,[x,y,.028],[.006,.006,.025]);paw(x+.003,y);
    }
    ball(parts,[-.008,0,.070],[.033,.022,.024]);
    ball(parts,[.021,0,.083],[.016,.019,.023]);
  }else{
    ball(parts,[-.009,0,.029],[.035,.027,.026]);
    // Exactly two visible forepaws; both rear legs are concealed inside the curl.
    paw(.040,-.018);paw(.040,.012);
  }
  ball(parts,head,standing?[.021,.022,.021]:[.020,.021,.019],'#d3dce1');
  for(const side of [-1,1]){
    const z=standing?.120:.049;
    parts.push({points:[P([head[0]-.011,head[1]+side*.018,z]),P([head[0]-.004,head[1]+side*.020,z+.024]),P([head[0]+.007,head[1]+side*.014,z+.003])],tint:'#a1afb9'});
  }
  const root=standing?[-.038,.012,.079]:[-.037,.021,.028];
  for(let i=0;i<=32;i++){
    const t=i/32;
    const point=standing?
      [root[0]-.015*Math.sin(t*Math.PI*.8),root[1]+t*.025,root[2]+.046*Math.sin(t*Math.PI*.8)] :
      [root[0]+.047*(1-Math.cos(t*Math.PI*.78)),root[1]+.018*Math.sin(t*Math.PI*.78),root[2]-.017*t];
    ball(tail,point,[.0048,.0054,.0054],'#a1afb9',1);
  }
  poses.push({pose,canvas:[2048,1024],tile:[1024,1024],scale:8,groundAnchor:[512,760],bodyParts:parts,tailParts:tail,contacts,tailRoot:root,tailRootPixel:P(root),tailRootTilePixel:P(root,1),bounds:{x:[-.062,.062],y:[-.062,.062],z:[0,.15]}});
}
writeFileSync(new URL('../../.tooling/room-cat-idle-v2-guides.json',import.meta.url),JSON.stringify({standard:'room-standard-v1',poses}));
writeFileSync(new URL('./idle-v2-contract.json',import.meta.url),JSON.stringify({standard:'room-standard-v1',camera:c,prototypeOnly:true,appearance:'black_short',poses:poses.map(({bodyParts,tailParts,...rest})=>rest)},null,2));
