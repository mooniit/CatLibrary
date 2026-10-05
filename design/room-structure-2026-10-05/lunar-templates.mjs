// Three permanent frame sizes. Artwork and frame are independent reusable layers.
import {camera,project} from './geometry.mjs';
import {artwork,wallMaterial,floorAsset,rugAsset,assetSvg} from './lunar-art.mjs';
import {joineryModel,mountJoinery,renderJoinery,frontTemplate,windowModel} from './lunar-joinery.mjs';
export const frameTemplates=Object.freeze({
  landscape:Object.freeze({label:'横版',w:.20,h:.15,cells:[1.6,1.2]}),
  portrait:Object.freeze({label:'竖版',w:.15,h:.20,cells:[1.2,1.6]}),
  square:Object.freeze({label:'正方形',w:.175,h:.175,cells:[1.4,1.4]})
});
const r=n=>Number(n.toFixed(5)),NS='http://www.w3.org/2000/svg';
let serial=0;
let decorSkins=null;
const nativeCache=new Map();
export function configureDecorSkins(skins){decorSkins=skins;nativeCache.clear();}
const points=ps=>ps.map(p=>project(camera(),p).map(r).join(',')).join(' ');
function crescent(x,y,radius,color,tilt=0){return `<path d="M${x+radius*.6} ${y-radius*.8} A${radius} ${radius} 0 1 0 ${x+radius*.6} ${y+radius*.8} A${radius*.76} ${radius*.76} 0 0 1 ${x+radius*.6} ${y-radius*.8}Z" fill="${color}" transform="rotate(${tilt} ${x} ${y})"/>`;}
function star(x,y,size,color){return `<path d="M${x} ${y-size} L${x+size*.24} ${y-size*.24} L${x+size} ${y} L${x+size*.24} ${y+size*.24} L${x} ${y+size} L${x-size*.24} ${y+size*.24} L${x-size} ${y} L${x-size*.24} ${y-size*.24}Z" fill="${color}"/>`;}
function matrix(a,b,c){const[A,B,C]=[a,b,c].map(p=>project(camera(),p));return `matrix(${B[0]-A[0]} ${B[1]-A[1]} ${C[0]-A[0]} ${C[1]-A[1]} ${A[0]} ${A[1]})`;}
function wallPoint(wall,u,s,z){return wall==='left'?[u,s,z]:[s,u,z];}
export function frameLayout(slot,key){const t=frameTemplates[key];if(!t)throw Error('Unknown frame template '+key);const centerZ=slot.z+slot.h/2;return{...t,wall:slot.wall,s:slot.s,centerZ,z:centerZ-t.h/2,p:.014,depth:.026};}
export function frameFlatSvg(key){const t=frameTemplates[key];return frontTemplate(joineryModel(t.w,t.h));}
export function wallArtwork(slot,key,kind=null,sources={}){
  const f=frameLayout(slot,key),{w,h,wall,s,z}=f,u=s-w/2;
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
export function frameSvg(slot,key,kind=null,sources={}){
  const f=frameLayout(slot,key),ps=[];for(const u of[-.004,.022])for(const s of[f.s-f.w/2,f.s+f.w/2])for(const z of[f.z,f.z+f.h])ps.push(project(camera(),wallPoint(f.wall,u,s,z)));
  const min=[0,1].map(i=>Math.floor(Math.min(...ps.map(p=>p[i])))-6),max=[0,1].map(i=>Math.ceil(Math.max(...ps.map(p=>p[i])))+6),viewBox=[...min,max[0]-min[0],max[1]-min[1]];
  return{viewBox,svg:`<svg xmlns="${NS}" width="${viewBox[2]}" height="${viewBox[3]}" viewBox="${viewBox.join(' ')}">${wallArtwork(slot,key,kind,sources)}</svg>`};
}
export function windowSvg(){
  const model=windowModel(),base=assetSvg(model),inner=renderJoinery(model);
  return{...base,inner,svg:`<svg xmlns="${NS}" width="${base.viewBox[2]}" height="${base.viewBox[3]}" viewBox="${base.viewBox.join(' ')}">${inner}</svg>`};
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
