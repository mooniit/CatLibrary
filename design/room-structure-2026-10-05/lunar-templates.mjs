// Three permanent frame sizes. Artwork and frame are independent reusable layers.
import {camera,project,box,boxFaces,slots} from './geometry.mjs';
import {artwork,rounded,wallMaterial,renderMesh,floorAsset,rugAsset,assetSvg} from './lunar-art.mjs';
import {joineryModel,mountJoinery,renderJoinery,frontTemplate,windowModel} from './lunar-joinery.mjs';
export const frameTemplates=Object.freeze({
  landscape:Object.freeze({label:'横版',w:.20,h:.15,cells:[1.6,1.2]}),
  portrait:Object.freeze({label:'竖版',w:.15,h:.20,cells:[1.2,1.6]}),
  square:Object.freeze({label:'正方形',w:.175,h:.175,cells:[1.4,1.4]})
});
const r=n=>Number(n.toFixed(5)),NS='http://www.w3.org/2000/svg';
let serial=0;
let decorSkins=null;
let nativeJoinery=false;
const nativeCache=new Map();
export function configureDecorSkins(skins){decorSkins=skins;nativeCache.clear();}
export function configureNativeJoinery(enabled=true){nativeJoinery=enabled;nativeCache.clear();}
function ninePatch(skin,W,H,p){
  const [l,t,r,b]=skin.insets,sx=[0,l,skin.width-r,skin.width],sy=[0,t,skin.height-b,skin.height],dx=[0,p,W-p,W],dy=[0,p,H-p,H];
  let markup='';for(let y=0;y<3;y++)for(let x=0;x<3;x++){if(x===1&&y===1)continue;markup+=`<svg x="${dx[x]}" y="${dy[y]}" width="${dx[x+1]-dx[x]}" height="${dy[y+1]-dy[y]}" viewBox="${sx[x]} ${sy[y]} ${sx[x+1]-sx[x]} ${sy[y+1]-sy[y]}" preserveAspectRatio="none" overflow="hidden"><image href="${skin.url}" width="${skin.width}" height="${skin.height}"/></svg>`;}
  return markup;
}
const points=ps=>ps.map(p=>project(camera(),p).map(r).join(',')).join(' ');
function crescent(x,y,radius,color,tilt=0){return `<path d="M${x+radius*.6} ${y-radius*.8} A${radius} ${radius} 0 1 0 ${x+radius*.6} ${y+radius*.8} A${radius*.76} ${radius*.76} 0 0 1 ${x+radius*.6} ${y-radius*.8}Z" fill="${color}" transform="rotate(${tilt} ${x} ${y})"/>`;}
function star(x,y,size,color){return `<path d="M${x} ${y-size} L${x+size*.24} ${y-size*.24} L${x+size} ${y} L${x+size*.24} ${y+size*.24} L${x} ${y+size} L${x-size*.24} ${y+size*.24} L${x-size} ${y} L${x-size*.24} ${y-size*.24}Z" fill="${color}"/>`;}
function matrix(a,b,c){const[A,B,C]=[a,b,c].map(p=>project(camera(),p));return `matrix(${B[0]-A[0]} ${B[1]-A[1]} ${C[0]-A[0]} ${C[1]-A[1]} ${A[0]} ${A[1]})`;}
function wallPoint(wall,u,s,z){return wall==='left'?[u,s,z]:[s,u,z];}
export function frameLayout(slot,key){const t=frameTemplates[key];if(!t)throw Error('Unknown frame template '+key);const centerZ=slot.z+slot.h/2;return{...t,wall:slot.wall,s:slot.s,centerZ,z:centerZ-t.h/2,p:.014,depth:.026};}
function flatFrame(w,h,grain,window=false){
  const id='frame-'+serial++,W=w*1600,H=h*1600,p=window?18:22.4;
  if(decorSkins){const markup=window?`<image href="${decorSkins.window.url}" width="${W}" height="${H}" preserveAspectRatio="none"/>`:ninePatch(decorSkins.frame,W,H,p);return{markup,W,H,p};}
  const grainLayer=grain?`<pattern id="${id}-grain" width="92" height="130" patternUnits="userSpaceOnUse"><image href="${grain}" width="92" height="130" opacity=".35"/></pattern>`:'';
  const bevel=`<linearGradient id="${id}-gold" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#8f5e1f"/><stop offset=".2" stop-color="#f4cd70"/><stop offset=".37" stop-color="#fff4ba"/><stop offset=".55" stop-color="#c48b2e"/><stop offset=".82" stop-color="#ffe29b"/><stop offset="1" stop-color="#a97626"/></linearGradient><linearGradient id="${id}-ivory" x2="0" y2="1"><stop stop-color="#fff7e6"/><stop offset=".45" stop-color="#f9edd4"/><stop offset="1" stop-color="#dfc59c"/></linearGradient>`;
  // Hollow compound path: the same corner motif, rail section and inset in all sizes.
  let out=`<defs>${grainLayer}${bevel}</defs><path d="M8 0 H${W-8} Q${W} 0 ${W} 8 V${H-8} Q${W} ${H} ${W-8} ${H} H8 Q0 ${H} 0 ${H-8} V8 Q0 0 8 0 Z M${p} ${p} V${H-p} H${W-p} V${p} Z" fill="url(#${id}-ivory)" fill-rule="evenodd" stroke="#96703c" stroke-width="1.8"/>`;
  if(grain)out+=`<path d="M0 0 H${W} V${H} H0 Z M${p} ${p} V${H-p} H${W-p} V${p} Z" fill="url(#${id}-grain)" fill-rule="evenodd"/>`;
  for(const[inset,width]of[[3,3],[8,2],[p-3,4],[p,1]])out+=`<rect x="${inset}" y="${inset}" width="${W-2*inset}" height="${H-2*inset}" rx="${inset<p?5:0}" fill="none" stroke="${width===1?'#785d32':`url(#${id}-gold)`}" stroke-width="${width}"/>`;
  const gold=`url(#${id}-gold)`;
  if(window){
    // Soft arch inside the fixed rectangular aperture; no change to the window size or sill.
    out+=`<path d="M${p} ${p+46} Q${W/2} ${p-36} ${W-p} ${p+46}" fill="none" stroke="url(#${id}-ivory)" stroke-width="10"/><path d="M${p} ${p+46} Q${W/2} ${p-36} ${W-p} ${p+46}" fill="none" stroke="${gold}" stroke-width="2.4"/>`;
    out+=`<rect x="${W/2-4}" y="${p+6}" width="8" height="${H-2*p-6}" fill="url(#${id}-ivory)" stroke="${gold}" stroke-width="1.6"/><rect x="${p}" y="${H*.57-3}" width="${W-2*p}" height="6" fill="url(#${id}-ivory)" stroke="${gold}" stroke-width="1.3"/>`;
    out+=crescent(W/2,p/2,8,gold,-20);
    for(const x of[W*.24,W*.76])out+=star(x,p/2,4,gold)+star(x,H-p/2,3.5,gold);
    for(const[x,y]of[[p/2,p/2],[W-p/2,p/2],[p/2,H-p/2],[W-p/2,H-p/2]])out+=star(x,y,4.5,gold);
  }else{
    out+=`<rect x="${p-1}" y="${p-1}" width="${W-2*p+2}" height="${H-2*p+2}" fill="none" stroke="#294365" stroke-width="2.3"/>`;
    // Each template uses the same two moon medallions and two star medallions.
    for(const[i,[x,y]]of[[p/2,p/2],[W-p/2,p/2],[p/2,H-p/2],[W-p/2,H-p/2]].entries()){
      out+=`<circle cx="${x}" cy="${y}" r="${p*.38}" fill="#294365" stroke="${gold}" stroke-width="2"/>`;
      out+=(i===0||i===3)?crescent(x,y,p*.27,gold,-18):star(x,y,p*.25,gold);
    }
    out+=`<path d="M${p+6} ${H-p/2} Q${W/2} ${H-p*.9} ${W-p-6} ${H-p/2}" fill="none" stroke="${gold}" stroke-width=".9"/>`;
    for(const x of[W*.35,W*.65])out+=star(x,H-p/2,3,gold);
    out+=crescent(W/2,p/2,7.5,gold,-20);
  }
  return{markup:out,W,H,p};
}
export function frameFlatSvg(key,grain){const t=frameTemplates[key];if(nativeJoinery)return frontTemplate(joineryModel(t.w,t.h));const flat=flatFrame(t.w,t.h,grain),viewBox=[-6,-6,flat.W+12,flat.H+12];return{viewBox,svg:`<svg xmlns="${NS}" width="${viewBox[2]}" height="${viewBox[3]}" viewBox="${viewBox.join(' ')}">${flat.markup}</svg>`};}
function physicalFrame(f,grain,window=false){
  const {wall,s,w,h,z,depth}=f,u=s-w/2,p=window?.012:f.p,parts=[];
  const add=(v,zz,ww,hh)=>parts.push(wall==='left'?box(-.004,v,zz,depth,ww,hh):box(v,-.004,zz,ww,depth,hh));
  add(u,z,w,p);add(u,z+h-p,w,p);add(u,z+p,p,h-2*p);add(u+w-p,z+p,p,h-2*p);
  let out='';
  if(decorSkins){
    const mesh={faces:[],lines:[],images:[],topcoat:[]},rings=[];
    const face=(ps,color)=>mesh.faces.push({points:wall==='right'?[...ps].reverse():ps,color});
    for(const[n,inset,gap]of[[-.004,.0015,p-.002],[.004,0,p],[.013,.0006,p-.0008],[.020,.0012,p-.0015],[.022,0,p]]){
      const loop=(d,radius)=>rounded(d,d,w-2*d,h-2*d,radius).map(([s0,z0])=>wallPoint(wall,n,u+s0,z+z0));
      rings.push({outer:loop(inset,.003),inner:loop(gap,.0015)});
    }
    for(let k=1;k<rings.length;k++)for(let i=0;i<rings[k].outer.length;i++){
      const j=(i+1)%rings[k].outer.length,prev=rings[k-1],next=rings[k];
      face([prev.outer[i],prev.outer[j],next.outer[j],next.outer[i]],['#f4e3bf','#fff2d4','#e8cca0','#ffefd1'][k-1]);
      face([prev.inner[j],prev.inner[i],next.inner[i],next.inner[j]],['#ead3ad','#f8e8c7','#e8cfaa','#fff0d4'][k-1]);
    }
    for(let i=0;i<rings[0].outer.length;i++){const j=(i+1)%rings[0].outer.length,back=rings[0],front=rings.at(-1);face([back.outer[j],back.outer[i],back.inner[i],back.inner[j]],'#e6cda3');face([front.outer[i],front.outer[j],front.inner[j],front.inner[i]],'#fff0d2');}
    mesh.lines.push({points:rings[3].outer,color:'#c39a55',width:.65,closed:true});
    out=renderMesh(mesh);
  }else for(const b of parts)for(const[fi,face]of boxFaces(b).entries())out+=`<polygon points="${points(face.points)}" fill="${fi===2?'#fff4dc':fi===(wall==='left'?0:1)?'#e4cda5':'#d4b991'}" stroke="#c6a05e" stroke-width=".6"/>`;
  const flat=flatFrame(w,h,grain,window),a=wallPoint(wall,.0221,u,z+h),b=wallPoint(wall,.0221,u+w,z+h),c=wallPoint(wall,.0221,u,z);
  out+=`<g transform="${matrix(a,b,c)}"><svg width="1" height="1" viewBox="0 0 ${flat.W} ${flat.H}" preserveAspectRatio="none" overflow="visible">${flat.markup}</svg></g>`;
  return out;
}
export function wallArtwork(slot,key,kind=null,sources={},grain='lunar-assets-v2/cream-grain.png'){
  const f=frameLayout(slot,key),{w,h,p,wall,s,z}=f,u=s-w/2;
  if(nativeJoinery){
    const cacheKey=[slot.id,key,kind||'',sources[kind]||''].join('|');if(nativeCache.has(cacheKey))return nativeCache.get(cacheKey);
    const local=joineryModel(w,h),mesh=mountJoinery(local,{...slot,z:f.z}),o=local.opening;
    let picture='';
    if(kind){
      const art=artwork[kind],W=o.right-o.left,H=o.top-o.bottom,iw=Math.min(W,H*art.ratio),ih=iw/art.ratio,cx=u+(o.left+o.right)/2,cz=z+(o.bottom+o.top)/2;
      const ps=[[u+o.left,z+o.bottom],[u+o.right,z+o.bottom],[u+o.right,z+o.top],[u+o.left,z+o.top]].map(([v,z])=>wallPoint(wall,.0065,v,z));
      // The contained picture is a single recessed plane behind the solid joinery.
      // Do not BSP-split its embedded bitmap into repeated copies.
      const [a,b,c]=[[cx-iw/2,cz+ih/2],[cx+iw/2,cz+ih/2],[cx-iw/2,cz-ih/2]].map(([v,z])=>wallPoint(wall,.0068,v,z));
      picture=`<polygon points="${points(ps)}" fill="#f8ead0"/><image href="${sources[kind]||art.file}" width="1" height="1" preserveAspectRatio="none" transform="${matrix(a,b,c)}" data-artwork="${kind}" data-original-aspect="${art.ratio}"/>`;
    }
    const result=picture+renderJoinery(mesh);nativeCache.set(cacheKey,result);return result;
  }
  let out=physicalFrame(f,grain);
  if(kind){const art=artwork[kind],iw=Math.min(w-2*p,(h-2*p)*art.ratio),ih=iw/art.ratio;
    const a=wallPoint(wall,.0219,s-iw/2,f.centerZ+ih/2),b=wallPoint(wall,.0219,s+iw/2,f.centerZ+ih/2),c=wallPoint(wall,.0219,s-iw/2,f.centerZ-ih/2);
    out+=`<polygon points="${points([wallPoint(wall,.0217,u+p,z+p),wallPoint(wall,.0217,u+w-p,z+p),wallPoint(wall,.0217,u+w-p,z+h-p),wallPoint(wall,.0217,u+p,z+h-p)])}" fill="#f8ead0"/>`;
    out+=`<image href="${sources[kind]||art.file}" width="1" height="1" preserveAspectRatio="none" transform="${matrix(a,b,c)}" data-artwork="${kind}" data-original-aspect="${art.ratio}"/>`;
  }
  return out;
}
export function frameSvg(slot,key,kind=null,sources={},grain){
  const f=frameLayout(slot,key),ps=[];for(const u of[-.004,.022])for(const s of[f.s-f.w/2,f.s+f.w/2])for(const z of[f.z,f.z+f.h])ps.push(project(camera(),wallPoint(f.wall,u,s,z)));
  const min=[0,1].map(i=>Math.floor(Math.min(...ps.map(p=>p[i])))-6),max=[0,1].map(i=>Math.ceil(Math.max(...ps.map(p=>p[i])))+6),viewBox=[...min,max[0]-min[0],max[1]-min[1]];
  return{viewBox,svg:`<svg xmlns="${NS}" width="${viewBox[2]}" height="${viewBox[3]}" viewBox="${viewBox.join(' ')}">${wallArtwork(slot,key,kind,sources,grain)}</svg>`};
}
export function windowSvg(grain){
  if(nativeJoinery){const model=windowModel(),base=assetSvg(model),inner=renderJoinery(model);return{...base,inner,svg:`<svg xmlns="${NS}" width="${base.viewBox[2]}" height="${base.viewBox[3]}" viewBox="${base.viewBox.join(' ')}">${inner}</svg>`};}
  const slot=slots.find(s=>s.id==='window-left'),f={...slot,p:.012,depth:.026};
  let svg=physicalFrame(f,grain,true);
  const sill=box(0,slot.s-slot.w/2-.01,slot.z-.008,.046,slot.w+.02,.008);
  if(decorSkins){
    const mesh={faces:[],lines:[],images:[],topcoat:[]},s=slot.s-slot.w/2-.01,W=slot.w+.02;
    const loops=[[.001,slot.z-.008],[0,slot.z-.003],[.0008,slot.z]].map(([d,z])=>rounded(d,s+d,.046-2*d,W-2*d,.003,z));
    for(let k=1;k<loops.length;k++)for(let i=0;i<loops[k].length;i++){const j=(i+1)%loops[k].length;mesh.faces.push({points:[loops[k-1][i],loops[k-1][j],loops[k][j],loops[k][i]],color:k===1?'#ead0a0':'#fff0cf'});}
    mesh.faces.push({points:loops.at(-1),color:'#fff3d9'});mesh.faces.push({points:[...loops[0]].reverse(),color:'#debf8e'});mesh.lines.push({points:loops[1],color:'#c19a56',width:.7,closed:true});svg+=renderMesh(mesh);
  }else for(const[fi,face]of boxFaces(sill).entries())svg+=`<polygon points="${points(face.points)}" fill="${fi===2?'#fff2d5':'#ddc09b'}" stroke="#c5a160" stroke-width="1"/>`;
  const ps=boxFaces(sill).flatMap(f=>f.points).concat(boxFaces(box(-.004,slot.s-slot.w/2,slot.z,.026,slot.w,slot.h)).flatMap(f=>f.points)).map(p=>project(camera(),p)),min=[0,1].map(i=>Math.floor(Math.min(...ps.map(p=>p[i])))-6),max=[0,1].map(i=>Math.ceil(Math.max(...ps.map(p=>p[i])))+6),viewBox=[...min,max[0]-min[0],max[1]-min[1]];
  return {viewBox,inner:svg,svg:`<svg xmlns="${NS}" width="${viewBox[2]}" height="${viewBox[3]}" viewBox="${viewBox.join(' ')}">${svg}</svg>`};
}
export function materialSvg(type,grain,wood,windowEnabled=true){
  const m=type==='floor'?floorAsset():type==='rug'?rugAsset():wallMaterial(type.endsWith('left')?'left':'right',windowEnabled),base=assetSvg(m);
  const id='material-'+serial++,wall=type.startsWith('wall'),plane=wall?type.endsWith('left')?'left':'right':null;
  const image=wall?grain:wood;
  let layer='';
  if(decorSkins&&type!=='rug'){
    const polygons=wall?m.faces.filter(f=>f.points.every(p=>Math.abs(p[plane==='left'?0:1])<1e-10)&&f.points.some(p=>p[2]>.1)).map(f=>points(f.points)):[points([[0,0,0],[1,0,0],[1,1,0],[0,1,0]])];
    const a=wall?wallPoint(plane,.0001,0,camera().wallHeight):[0,0,.0001],b=wall?wallPoint(plane,.0001,1,camera().wallHeight):[1,0,.0001],c=wall?wallPoint(plane,.0001,0,0):[0,1,.0001];
    layer=`<defs><clipPath id="${id}">${polygons.map(p=>`<polygon points="${p}"/>`).join('')}</clipPath></defs><g clip-path="url(#${id})"><image href="${decorSkins[wall?'wall':'floor'].url}" width="1" height="1" preserveAspectRatio="none" transform="${matrix(a,b,c)}"/></g>`;
    if(wall){
      const stripId=id+'-moulding',a=wallPoint(plane,.0062,0,.032),b=wallPoint(plane,.0062,1,.032),c=wallPoint(plane,.0062,0,0);
      layer+=`<defs><linearGradient id="${stripId}" x2="0" y2="1"><stop stop-color="#fff5df"/><stop offset=".2" stop-color="#eed9b2"/><stop offset=".38" stop-color="#fff7e3"/><stop offset=".8" stop-color="#f1dfbe"/><stop offset="1" stop-color="#d9bc85"/></linearGradient></defs><g transform="${matrix(a,b,c)}"><svg width="1" height="1" viewBox="0 0 1000 32" preserveAspectRatio="none"><rect width="1000" height="32" fill="url(#${stripId})"/><path d="M0 1H1000 M0 28H1000" stroke="#bf9550" stroke-width="1.1"/><path d="M0 3H1000" stroke="#fff8e5" stroke-width="1.5"/></svg></g>`;
    }
    return{...base,svg:base.svg.replace('</svg>',layer+'</svg>')};
  }
  if(type!=='rug'){
    const polygons=wall?m.faces.filter(f=>f.points.every(p=>Math.abs(p[plane==='left'?0:1])<1e-10)&&f.points.some(p=>p[2]>.1)).map(f=>points(f.points)):[points([[0,0,0],[1,0,0],[1,1,0],[0,1,0]])];
    const a=wall?wallPoint(plane,.0001,0,camera().wallHeight):[0,0,.0001],b=wall?wallPoint(plane,.0001,1,camera().wallHeight):[1,0,.0001],c=wall?wallPoint(plane,.0001,0,0):[0,1,.0001];
    layer=`<defs><clipPath id="${id}">${polygons.map(p=>`<polygon points="${p}"/>`).join('')}</clipPath></defs><g clip-path="url(#${id})" opacity="${wall?.25:.38}"><image href="${image}" width="1" height="1" preserveAspectRatio="none" transform="${matrix(a,b,c)}"/></g>`;
  }else{
    // Fine woven grain on the existing exact square rug, with the existing embroidery above.
    const surface=m.faces.find(f=>f.points.length>4&&f.points.every(p=>Math.abs(p[2]-.0018)<1e-9));
    const id2=id+'-weave';layer=`<defs><pattern id="${id2}" width="3" height="3" patternUnits="userSpaceOnUse"><path d="M0 0L3 3 M-1 2L1 4" stroke="#7090ab" stroke-width=".28"/></pattern><clipPath id="${id}"><polygon points="${points(surface.points)}"/></clipPath></defs><rect x="0" y="0" width="1080" height="1073" fill="url(#${id2})" clip-path="url(#${id})" opacity=".18"/>`;
  }
  if(wall){
    // One sparse constellation above the fixed window, projected in the actual wall plane.
    const H=camera().wallHeight,a=wallPoint(plane,.0002,0,H),b=wallPoint(plane,.0002,1,H),c=wallPoint(plane,.0002,0,0),y=(1-.706/H)*800;
    let motif=`<path d="M210 ${y+11} Q500 ${y-30} 790 ${y+11} M310 ${y+16} Q540 ${y+38} 720 ${y+2}" fill="none" stroke="#b58f50" stroke-width="1.1"/>`;
    motif+=crescent(500,y,12,'#b58f50',-18)+star(236,y+8,5,'#b58f50')+star(762,y+8,5,'#b58f50')+star(638,y-2,3,'#b58f50');
    layer+=`<g transform="${matrix(a,b,c)}" opacity=".46"><svg width="1" height="1" viewBox="0 0 1000 800" preserveAspectRatio="none">${motif}</svg></g>`;
  }else if(type==='floor'){
    const a=[0,0,.0002],b=[1,0,.0002],c=[0,1,.0002];
    let motif=`<path d="M65 190 V810 M935 190 V810 M190 65 H810 M190 935 H810" fill="none" stroke="#ad8649" stroke-width="1.1"/>`;
    for(const[x,y]of[[85,85],[915,85],[85,915],[915,915]]){
      motif+=`<circle cx="${x}" cy="${y}" r="27" fill="none" stroke="#ad8649" stroke-width="1"/>`+crescent(x,y,14,'#ad8649',-20)+star(x+35,y,4,'#ad8649')+star(x,y+35,4,'#ad8649');
    }
    for(const[x,y]of[[65,500],[935,500],[500,65],[500,935]])motif+=star(x,y,6,'#ad8649');
    layer+=`<g transform="${matrix(a,b,c)}" opacity=".58"><svg width="1" height="1" viewBox="0 0 1000 1000" preserveAspectRatio="none">${motif}</svg></g>`;
  }
  return{...base,svg:base.svg.replace('</svg>',layer+'</svg>')};
}
