// Independent scenery content, projected into the frozen aperture behind the joinery.
import {camera,project} from './geometry.mjs';
export const windowModes=Object.freeze(['day','night']);
let serial=0;
export function windowViewSvg(slot,mode,source,{width=1536,height=1024}={}){
  if(!windowModes.includes(mode))throw new Error('Unknown window mode: '+mode);
  const point=(s,z)=>slot.wall==='left'?[0,s,z]:[s,0,z],s0=slot.s-slot.w/2,z0=slot.z;
  const ps=[[s0,z0],[s0+slot.w,z0],[s0+slot.w,z0+slot.h],[s0,z0+slot.h]].map(([s,z])=>project(camera(),point(s,z)));
  const ratio=width/height,w=Math.min(slot.w,slot.h*ratio),h=w/ratio;
  const [a,b,c]=[[slot.s-w/2,z0+slot.h/2+h/2],[slot.s+w/2,z0+slot.h/2+h/2],[slot.s-w/2,z0+slot.h/2-h/2]].map(([s,z])=>project(camera(),point(s,z)));
  const transform=`matrix(${b[0]-a[0]} ${b[1]-a[1]} ${c[0]-a[0]} ${c[1]-a[1]} ${a[0]} ${a[1]})`,id='window-view-'+serial++;
  const min=[0,1].map(i=>Math.floor(Math.min(...ps.map(p=>p[i])))-6),max=[0,1].map(i=>Math.ceil(Math.max(...ps.map(p=>p[i])))+6),viewBox=[...min,max[0]-min[0],max[1]-min[1]];
  const poly=ps.map(p=>p.join(',')).join(' '),background=mode==='day'?'#becfdc':'#12243e';
  const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="${viewBox[2]}" height="${viewBox[3]}" viewBox="${viewBox.join(' ')}"><defs><clipPath id="${id}"><polygon points="${poly}"/></clipPath></defs><g clip-path="url(#${id})" data-window-mode="${mode}"><polygon points="${poly}" fill="${background}"/><image href="${source}" width="1" height="1" preserveAspectRatio="none" transform="${transform}" data-original-aspect="${ratio}"/></g></svg>`;
  return{svg,viewBox,originalAspect:ratio,fit:'contain'};
}
