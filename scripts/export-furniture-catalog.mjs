// Copies validated pieces and preserves authoritative coordinates. No image transforms.
import {readFileSync,writeFileSync,mkdirSync,copyFileSync} from 'node:fs';
import {roomStandard,fixtures,orient,slots,project,camera} from '../design/room-structure-2026-10-05/geometry.mjs';
import {approvedEconomy} from './furniture-economy.mjs';
import {unifyWallArt} from './wall-art-catalog.mjs';
const read=p=>JSON.parse(readFileSync(p,'utf8'));
const verification=read('design/room-themes-2026-10-06/verification.json');
if(verification.consoleErrors.length||verification.failedRequests.length)throw Error('Theme verification failed');
const lunar=read('assets/images/room/lunar-v5/catalog.json');
const products=[];
const retired=read('assets/data/furniture-products.json').filter(p=>p.kind==='frame').map(p=>({...p,active:false}));
const labels={bookshelf:'书柜',desk:'书桌',chair:'椅子',tree:'猫爬架',bed:'开放猫窝',window:'窗户',rug:'地毯',wall:'墙面',floor:'地板'};
for(const theme of ['lunar','wood','royal']){
  let catalog=lunar;
  let manifest;
  if(theme!=='lunar'){
    const source='design/room-themes-2026-10-06/'+theme;
    manifest=read(source+'/manifest.json');
    if(manifest.standard!==roomStandard.id)throw Error('Wrong room standard');
    const target='assets/images/room/'+theme;mkdirSync(target,{recursive:true});
    const layers={};
    for(const a of manifest.assets.filter(a=>!a.id.endsWith('-flat'))){
      if(a.category==='furniture'){
        if(a.axisChecks.length<3||a.axisChecks.some(e=>!e.passed)||a.registration.warp!=='none')throw Error('Unverified edges: '+a.id);
        if(a.facing==='y'&&a.mirrorOf!==a.id.replace(/-y$/,'-x'))throw Error('Missing mirror provenance');
      }
      copyFileSync(source+'/'+a.png,target+'/'+a.png);
      let rect=a.viewBox;
      if(a.category==='furniture'){
        const p=project(camera(),a.worldGroundAnchor);
        rect=[p[0]-a.pixelGroundOrigin[0],p[1]-a.pixelGroundOrigin[1],a.viewBox[2],a.viewBox[3]];
      }
      layers[a.id]={file:a.png,rect,mount:a.worldMountCenter,opening:a.opening};
    }
    catalog={version:theme+'-content-v1',standard:roomStandard,layers,
      fixtures:lunar.fixtures,slots,frameTemplates:lunar.frameTemplates};
    writeFileSync(target+'/catalog.json',JSON.stringify(catalog,null,2)+'\n');
  }
  for(const kind of Object.keys(labels)){
    const placement=fixtures.some(f=>f.id===kind)?'ground':kind;
    const geometry={};
    if(placement==='ground')for(const facing of ['x','y']){
      const f=orient(fixtures.find(f=>f.id===kind),facing);
      const dims=manifest?.assets.find(a=>a.id===kind+'-'+facing).dimensionsL??[f.w,f.d,f.h];
      geometry[facing]={cells:f.cells.map(([x,y])=>[x-f.anchor[0],y-f.anchor[1]]),w:dims[0],d:dims[1],h:dims[2]};
    }
    products.push({sku:theme+'-'+kind,label:({lunar:'月轨',wood:'木质',royal:'皇家'})[theme]+labels[kind],theme,kind,placement,geometry,price:null,currency:null,purchase_limit:null,active:false,is_test:false});
  }
  for(const [artwork,label,template] of [
    ['starry','爪印星夜','landscape'],['mona','猫娜丽莎','portrait'],['scream','喵的呐喊','portrait'],['pearl','戴珍珠耳环的猫','portrait'],['sunflowers','向日葵','square']]){
    products.push({sku:theme+'-painting-'+artwork,label:({lunar:'月轨',wood:'木质',royal:'皇家'})[theme]+label,theme,kind:'painting',placement:'art',geometry:{template,artwork},price:null,currency:null,purchase_limit:null,active:false,is_test:false});
  }
}
mkdirSync('assets/data',{recursive:true});
for(const p of products)Object.assign(p,approvedEconomy(p.theme,p.kind));
products.push(...retired);
const catalogProducts=unifyWallArt(products);
writeFileSync('assets/data/furniture-products.json',JSON.stringify(catalogProducts,null,2)+'\n');
// The original migration is historical. Apply catalog changes incrementally.
console.log('Exported '+catalogProducts.filter(p=>p.active).length+' approved products; fixed wood frames; footprints unchanged.');
