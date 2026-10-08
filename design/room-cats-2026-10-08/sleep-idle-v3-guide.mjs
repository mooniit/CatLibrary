// Relaxed prone sleep, not the superseded alert curled-resting pose.
import {camera,project} from '../room-structure-2026-10-05/geometry.mjs';
import {writeFileSync} from 'node:fs';
const c=camera(),o=project(c,[0,0,0]),bodyParts=[],tailParts=[];
const P=(p,tile=0)=>{const v=project(c,p);return [512+tile*1024+(v[0]-o[0])*8,760+(v[1]-o[1])*8];};
function ball(list,center,radii,tint='#b9c8d0',tile=0){
  const points=[];
  for(let i=0;i<=24;i++)for(let j=0;j<48;j++){
    const a=Math.PI*i/24,b=Math.PI*2*j/48;
    points.push(P(center.map((v,k)=>v+radii[k]*[Math.sin(a)*Math.cos(b),Math.sin(a)*Math.sin(b),Math.cos(a)][k]),tile));
  }
  list.push({points,tint});
}
ball(bodyParts,[-.009,0,.025],[.035,.028,.022]);
const contacts=[[.040,-.018,0],[.040,.012,0]];
for(const [x,y] of contacts)ball(bodyParts,[x,y,.006],[.011,.007,.006],'#dde5e8');
// Chin and cheek rest on the two forepaws; no raised neck or visible hind paw.
ball(bodyParts,[.032,-.004,.022],[.021,.022,.017],'#d3dce1');
for(const side of [-1,1]){
  bodyParts.push({points:[P([.019,-.004+side*.018,.032]),P([.025,-.004+side*.028,.052]),P([.036,-.004+side*.014,.039])],tint:'#a1afb9'});
}
const tailRoot=[-.037,.021,.020];
for(let i=0;i<=32;i++){
  const t=i/32;
  ball(tailParts,[tailRoot[0]+.047*(1-Math.cos(t*Math.PI*.78)),tailRoot[1]+.018*Math.sin(t*Math.PI*.78),tailRoot[2]-.012*t],[.0035,.004,.004],'#a1afb9',1);
}
const pose={pose:'sleeping',guideFile:'sleeping-idle-v3-guide.png',canvas:[2048,1024],tile:[1024,1024],scale:8,groundAnchor:[512,760],bodyParts,tailParts,contacts:contacts.map(p=>P(p)),tailRoot,tailRootPixel:P(tailRoot),tailRootTilePixel:P(tailRoot,1),bounds:{x:[-.062,.062],y:[-.062,.062],z:[0,.056]}};
writeFileSync(new URL('../../.tooling/room-cat-sleep-v3-guide.json',import.meta.url),JSON.stringify({standard:'room-standard-v1',poses:[pose]}));
const {bodyParts:unusedBody,tailParts:unusedTail,...contract}=pose;
writeFileSync(new URL('./sleep-idle-v3-contract.json',import.meta.url),JSON.stringify({standard:'room-standard-v1',camera:c,appearance:'black_short',prototypeOnly:true,pose:contract,secondFacing:'runtime exact horizontal pixel mirror; no independent generation'},null,2));
