import fs from 'node:fs';
import assert from 'node:assert/strict';
import {roomStandard,project,box,boxFaces,sortBoxes} from '../design/room-structure-2026-10-05/geometry.mjs';

assert(!fs.existsSync('assets/images/room/souvenirs-v2/manifest.json'),
  'Historical numeric prototype generator is retired. Use package-souvenir-v2.mjs; do not overwrite integrated artwork or applied migrations.');

// Deterministic vector sculptures. All visible faces are the actual numeric model,
// rather than AI textures fitted to an envelope. World cell = .125L.
const dir='design/souvenirs-2026-10-07';fs.mkdirSync(dir,{recursive:true});
const entries=[['palace','故宫宫殿',.115],['louvre','玻璃金字塔',.10],['fuji','富士山',.09],['pyramid','埃及金字塔',.115],['eiffel','埃菲尔铁塔',.22],['liberty','自由女神像',.21]];
const products=[];
for(const [id,label,h] of entries){
  const boxes=[box(.0125,.0125,0,.10,.10,.012,'#b8c8d1')];
  const extras=[];
  const pyramid=(z,w,d,H,color)=>{
    const x=(.125-w)/2,y=(.125-d)/2,tip=[.0625,.0625,z+H];
    extras.push({points:[[x+w,y,z],[x+w,y+d,z],tip],color},
      {points:[[x,y+d,z],[x+w,y+d,z],tip],color});
  };
  if(id==='palace'){
    boxes.push(box(.026,.026,.012,.073,.073,.05,'#be746c'));
    for(const x of [.034,.078])boxes.push(box(x,.101,.012,.012,.006,.05,'#ecd3aa'));
    pyramid(.062,.092,.092,.053,'#d8b968');
  }else if(id==='louvre')pyramid(.012,.096,.096,.088,'#a5c8d8');
  else if(id==='fuji'){
    pyramid(.012,.096,.096,.078,'#8ba9b4');
    pyramid(.067,.0283,.0283,.023,'#f4f6f1');
  }else if(id==='pyramid')pyramid(.012,.096,.096,.103,'#d4bc87');
  else if(id==='eiffel'){
    for(const x of [.025,.088])for(const y of [.025,.088])boxes.push(box(x,y,.012,.012,.012,.065,'#889ba9'));
    boxes.push(box(.022,.022,.077,.081,.081,.01,'#b2c0c7'),box(.044,.044,.087,.037,.037,.07,'#889ba9'),box(.039,.039,.157,.047,.047,.008,'#b2c0c7'),box(.0575,.0575,.165,.01,.01,.055,'#889ba9'));
  }else{
    boxes.push(box(.034,.034,.012,.057,.057,.038,'#a2b5bc'),box(.044,.044,.05,.037,.037,.071,'#78a79d'),box(.049,.049,.121,.027,.027,.039,'#8db9ad'),box(.051,.051,.16,.023,.023,.017,'#8db9ad'),box(.035,.035,.113,.008,.008,.076,'#78a79d'),box(.03,.03,.189,.018,.018,.021,'#d8bc74'),box(.074,.044,.112,.012,.019,.034,'#b2c8be'));
  }
  const faces=[...sortBoxes(boxes,roomStandard.camera).flatMap(boxFaces),...extras];
  const vertices=faces.flatMap(f=>f.points);
  assert(vertices.every(([x,y,z])=>x>=.0125-1e-9&&y>=.0125-1e-9&&x<=.1125+1e-9&&y<=.1125+1e-9&&z>=0&&z<=h+1e-9));
  const orientation={cells:[[0,0]],w:.10,d:.10,h};
  const geometry={standard:roomStandard.id,anchor:[0,0],x:orientation,y:orientation,faces};
  const product={sku:`souvenir-${id}`,label,theme:'souvenir',kind:'souvenir',placement:'ground',geometry,active:false,is_test:false};
  products.push(product);
  const projected=vertices.map(v=>project(roomStandard.camera,v));
  const xs=projected.map(v=>v[0]),ys=projected.map(v=>v[1]);
  const view=[Math.min(...xs)-3,Math.min(...ys)-3,Math.max(...xs)-Math.min(...xs)+6,Math.max(...ys)-Math.min(...ys)+6];
  fs.writeFileSync(`${dir}/${id}-coordinate-guide.svg`,`<svg xmlns="http://www.w3.org/2000/svg" width="240" height="300" viewBox="${view.join(' ')}">${faces.map(f=>`<polygon points="${f.points.map(p=>project(roomStandard.camera,p).join(',')).join(' ')}" fill="${f.color}" stroke="#526773" stroke-width=".45" stroke-linejoin="round"/>`).join('')}</svg>\n`);
}
fs.writeFileSync('assets/data/souvenir-products.json',JSON.stringify(products,null,2)+'\n');
fs.writeFileSync(`${dir}/models.json`,JSON.stringify({standard:roomStandard,products},null,2)+'\n');
const sql=`-- T32: non-purchasable reward catalog; 1x1 footprints, immutable model faces.\n`+products.map(p=>`insert into public.furniture_products(sku,label,theme,kind,placement,geometry,active,is_test) values('${p.sku}','${p.label}','souvenir','souvenir','ground','${JSON.stringify(p.geometry)}'::jsonb,false,false);`).join('\n')+'\n';
const migration='supabase/migrations/202610070005_souvenir_catalog.sql';
if(fs.existsSync(migration))assert.equal(fs.readFileSync(migration,'utf8').replaceAll('\r\n','\n'),sql,'never rewrite an applied migration');
else fs.writeFileSync(migration,sql);
console.log('6 registered numeric models; 1x1 footprints; six coordinate guides; non-purchasable catalog');
