// Regenerate all SVG masters and placement metadata without browser or image generation.
import {mkdirSync,writeFileSync,readFileSync} from 'node:fs';
import {fixtures,orient,slots,roomStandard,project,camera} from './geometry.mjs';
import {furniture,wallAsset,wallMaterial,floorAsset,rugAsset,assetSvg,bounds,artwork,palette} from './lunar-art.mjs';
const dir=new URL('./lunar-assets/',import.meta.url);mkdirSync(dir,{recursive:true});
const sources=Object.fromEntries(Object.entries(artwork).map(([key,a])=>[key,'data:image/png;base64,'+readFileSync(new URL(a.file,import.meta.url)).toString('base64')]));
const manifest={standardId:roomStandard.id,worldUnit:'L; cell=L/8',camera:roomStandard.camera,palette,placementChanged:false,gridAnchorRule:'minimum cell indices; zero based',spritePlacement:'image origin = project(worldGroundAnchor) - pixelGroundOrigin; native pixels at 1080x1073; scale the whole room once',assets:[]};
function save(id,m,extra={}){
  const a=assetSvg(m),b=bounds(m);writeFileSync(new URL(id+'.svg',dir),a.svg+'\n');
  manifest.assets.push({id,svg:id+'.svg',png:id+'.png',viewBox:a.viewBox,pixelGroundOrigin:a.screenGroundOrigin,worldBounds:b,...extra});
}
for(const f of fixtures)for(const facing of['x','y']){
  const actual=orient(f,facing),local={...actual,x:0,y:0};
  const a=assetSvg(furniture(local)),pixelGroundOrigin=a.screenGroundOrigin;
  save(f.id+'-'+facing,furniture(local),{category:'furniture',label:f.label,facing:'+'+facing.toUpperCase(),dimensionsL:[actual.w,actual.d,actual.h],dimensionsCells:[actual.w*8,actual.d*8,actual.h*8],gridAnchor:actual.anchor,cells:actual.cells,gridSize:[actual.cols,actual.rows],worldGroundAnchor:[actual.x,actual.y,0],worldCenter:[actual.x+actual.w/2,actual.y+actual.d/2,0],pixelGroundOrigin,renderOrigin:project(camera(),[actual.x,actual.y,0]).map((v,i)=>v-pixelGroundOrigin[i])});
}
for(const wall of['left','right']){
  const window=slots.find(s=>s.wall===wall&&s.type==='window');save('window-'+wall,wallAsset(window),{category:'window',slotId:window.id,slot:window,facing:wall==='left'?'+X':'+Y',worldMountCenter:wall==='left'?[0,window.s,window.z+window.h/2]:[window.s,0,window.z+window.h/2],sillBottomCells:(window.z-.008)*8,depthL:.046,aperture:'empty'});
  for(const kind of['starry','pearl']){const slot=slots.find(s=>s.wall===wall&&s.type==='art'&&s.id.endsWith(kind==='starry'?'back':'front'));save(kind+'-'+wall,wallAsset(slot,kind,sources),{category:'wall-art',slotId:slot.id,slot,facing:wall==='left'?'+X':'+Y',originalAspect:artwork[kind].ratio,originalFile:artwork[kind].file,fit:'contain; original aspect; no crop',worldMountCenter:wall==='left'?[0,slot.s,slot.z+slot.h/2]:[slot.s,0,slot.z+slot.h/2]});}
  save('wall-'+wall,wallMaterial(wall),{category:'wall-material',fixedWindow:true});
}
save('floor',floorAsset(),{category:'floor-material',dimensionsCells:[8,8],groundZ:0});
save('rug',rugAsset(),{category:'rug',gridAnchor:[1,1],gridSize:[6,6],fixed:true,groundZ:.0008});
writeFileSync(new URL('manifest.json',dir),JSON.stringify(manifest,null,2)+'\n');
console.log('Exported '+manifest.assets.length+' transparent SVG masters and manifest.');
