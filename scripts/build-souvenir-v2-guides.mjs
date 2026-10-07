import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
import {roomStandard, project, box, boxFaces} from '../design/room-structure-2026-10-05/geometry.mjs';

const dir='design/souvenirs-2026-10-07/v2';fs.mkdirSync(dir,{recursive:true});
const products=JSON.parse(fs.readFileSync('assets/data/souvenir-products.json'));
const {chromium}=createRequire(path.resolve('.tooling/browser/package.json'))('playwright-core');
const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
const page=await browser.newPage();
try {for(const product of products){
  const id=product.sku.slice(9), faces=[], lines=[];
  const face=(points,color)=>faces.push({points,color});
  const slab=(x,y,z,w,d,h,c)=>faces.push(...boxFaces(box(x,y,z,w,d,h,c)));
  const line=(a,b,color='#94734d',width=.3)=>lines.push({a,b,color,width});
  const pyramid=(z,w,H,c)=>{const a=(.125-w)/2,b=a+w,t=[.0625,.0625,z+H];face([[b,a,z],[b,b,z],t],c);face([[a,b,z],[b,b,z],t],c);return {a,b,t};};
  slab(.0125,.0125,0,.10,.10,.008,'#c8ac7d');
  slab(.0125,.0125,.008,.10,.10,.004,'#f1dfb7');
  if(id==='palace'){
    slab(.023,.027,.012,.079,.071,.010,'#e6d9c0');
    slab(.029,.034,.022,.067,.057,.034,'#963f3c');
    for(const y of [.038,.052,.066,.080])slab(.097,y,.022,.004,.003,.035,'#c76147');
    for(const x of [.033,.051,.069,.087])slab(x,.093,.022,.003,.004,.035,'#c76147');
    // Chinese hip roof: curved eaves, long ridge and four sloping roof planes.
    const roof=(z,w,d,H)=>{
      const a=(.125-w)/2,b=a+w,c=(.125-d)/2,e=c+d;
      const ridgeA=[.0625,c+d*.28,z+H],ridgeB=[.0625,c+d*.72,z+H];
      face([[b,c,z+.003],[b,e,z+.003],ridgeB,ridgeA],'#d4a750');
      face([[a,e,z+.003],[b,e,z+.003],ridgeB],'#eed086');
      face([[a,c,z+.003],[a,e,z+.003],ridgeB,ridgeA],'#e3bb6b');
      for(let n=1;n<13;n++){const y=c+d*n/13;line([b,y,z+.003],[.063,y,z+H-.003],'#ac8440',.22);}
      slab(a,c,z,w,d,.003,'#e7c16c');
      line(ridgeA,ridgeB,'#f6db90',.8);
    };
    roof(.056,.094,.090,.022);
    slab(.041,.037,.078,.043,.051,.012,'#a24d41');
    roof(.089,.076,.080,.026);
    for(const y of [.043,.060,.077]){slab(.096,y,.033,.001,.010,.016,'#453b40');for(let n=1;n<4;n++)line([.097,y+.0025*n,.033],[.097,y+.0025*n,.049],'#d6a75c',.20);}
  } else if(id==='louvre'){
    product.label='维纳斯雕像';product.geometry.x.h=.21;product.geometry.y.h=.21;
    slab(.034,.034,.012,.057,.057,.020,'#d8c8ad');slab(.030,.030,.032,.065,.065,.004,'#f4e7cf');
    const rings=[];
    // Classical contrapposto torso and draped lower body; intentionally no arms.
    const levels=[[.036,.022,.018,0],[.064,.021,.017,0],[.095,.019,.014,-.003],[.122,.024,.016,.003],[.143,.016,.012,.005],[.162,.022,.014,0],[.176,.021,.012,-.003],[.183,.008,.008,-.003],[.197,.010,.009,-.001],[.210,.003,.003,0]];
    for(const [z,rx,ry,lean] of levels){rings.push(Array.from({length:32},(_,n)=>{const a=n/32*Math.PI*2,r=z<.125?1+.07*Math.sin(a*9):1;return[.0625+lean+rx*r*Math.cos(a),.0625+ry*r*Math.sin(a),z];}));}
    for(let k=0;k<rings.length-1;k++)for(let n=0;n<32;n++){const j=(n+1)%32;face([rings[k][n],rings[k][j],rings[k+1][j],rings[k+1][n]],n<16?'#e1d7c6':'#f3ebdb');}
    for(let n=0;n<32;n+=4)line(rings[0][n],rings[3][n],'#d4c5ac',.18);
  } else if(id==='fuji'){
    // A wide, gently irregular volcanic cone with a broad snowy summit.
    const rings=[];
    for(let k=0;k<=6;k++){const z=.012+.078*k/6,r=.048*(1-k/6)+.001;const ring=[];
      for(let n=0;n<24;n++){const a=n/24*Math.PI*2,rr=r*(1+.018*Math.sin(n*3));ring.push([.0625+rr*Math.cos(a),.0625+rr*Math.sin(a),z]);}rings.push(ring);}
    for(let k=0;k<6;k++)for(let n=0;n<24;n++){const j=(n+1)%24;face([rings[k][n],rings[k][j],rings[k+1][j],rings[k+1][n]],k>=4?'#f3f1e8':n<12?'#7f9dab':'#a0b6c0');}
    for(let n=0;n<24;n+=3)line(rings[0][n],rings[4][n],'#728d9b',.24);
  } else if(id==='pyramid'){
    const {a,b}=pyramid(.012,.096,.103,'#d9bd82');
    for(let n=1;n<17;n++){const t=n/17,z=.012+.103*t,A=a+(.0625-a)*t,B=b-(b-.0625)*t;
      line([B,A,z],[B,B,z],'#b49462',.28);line([A,B,z],[B,B,z],'#bd9a67',.28);
      for(let k=1;k<5;k++){const q=A+(B-A)*(k/5+(n%2)/10);if(q<B){line([B,q,z],[B-.0028,q,.012+.103*(t+1/17)],'#c7a56d',.2);}}
    }
  } else if(id==='eiffel'){
    const beam=(a,b,r,color='#887965')=>{
      // Individual structural steel strips, not solid blocks hiding the arches.
      const dx=b[0]-a[0],dy=b[1]-a[1],len=Math.hypot(dx,dy)||1;
      const ux=dy/len*r,uy=-dx/len*r;
      face([[a[0]-ux,a[1]-uy,a[2]],[a[0]+ux,a[1]+uy,a[2]],[b[0]+ux,b[1]+uy,b[2]],[b[0]-ux,b[1]-uy,b[2]]],color);
    };
    const level=[{z:.012,r:.043},{z:.086,r:.023},{z:.158,r:.009},{z:.21,r:.003}];
    for(let k=0;k<3;k++){
      const A=level[k],B=level[k+1];
      for(const sx of [-1,1])for(const sy of [-1,1])beam([.0625+sx*A.r,.0625+sy*A.r,A.z],[.0625+sx*B.r,.0625+sy*B.r,B.z],.0018);
      for(let n=0;n<5;n++)for(const axis of [0,1]){
        const t=n/5,u=(n+1)/5,z=A.z+(B.z-A.z)*t,Z=A.z+(B.z-A.z)*u,r=A.r+(B.r-A.r)*t,R=A.r+(B.r-A.r)*u;
        const p=(s,v,h)=>axis===0?[.0625+s,.0625+v,h]:[.0625+v,.0625+s,h];
        beam(p(r,-r,z),p(R,R,Z),.0008,'#9b8c75');beam(p(r,r,z),p(R,-R,Z),.0008,'#9b8c75');
      }
    }
    for(const [z,r] of [[.086,.028],[.158,.014]])slab(.0625-r,.0625-r,z,r*2,r*2,.005,'#bda57d');
    slab(.061,.061,.21,.003,.003,.010,'#887965');
    // Curved arch braces between all four splayed legs.
    for(const axis of [0,1])for(let n=0;n<16;n++){const t=n/16,u=(n+1)/16;const p=v=>axis===0?[.1055-.02*Math.sin(v*Math.PI),.0195+.086*v,.014+.044*Math.sin(v*Math.PI)]:[.0195+.086*v,.1055-.02*Math.sin(v*Math.PI),.014+.044*Math.sin(v*Math.PI)];beam(p(t),p(u),.0016);}
  } else {
    slab(.032,.032,.012,.061,.061,.010,'#d5c5a7');slab(.037,.037,.022,.051,.051,.024,'#bda987');slab(.032,.032,.046,.061,.061,.004,'#d8c7a7');
    // Draped robe with a flared hem, neck, oval head, seven crown rays.
    const rings=[];for(let k=0;k<7;k++){const z=.05+.083*k/6,rx=.025-.010*k/6,ry=.020-.006*k/6;const r=[];for(let n=0;n<20;n++){const a=n/20*Math.PI*2,f=1+.065*Math.sin(a*7);r.push([.064+rx*f*Math.cos(a),.066+ry*f*Math.sin(a),z]);}rings.push(r);}
    for(let k=0;k<6;k++)for(let n=0;n<20;n++){const j=(n+1)%20;face([rings[k][n],rings[k][j],rings[k+1][j],rings[k+1][n]],n%3===0?'#639b88':'#91b9a0');}
    const oval=(x,y,z,rx,ry,h,c)=>{const rings=[];for(let k=0;k<=10;k++){const t=k/10*Math.PI,r=Math.sin(t);rings.push(Array.from({length:20},(_,n)=>{const a=n/20*Math.PI*2;return[x+rx*r*Math.cos(a),y+ry*r*Math.sin(a),z+h*(1-Math.cos(t))/2];}));}for(let k=0;k<10;k++)for(let n=0;n<20;n++){const j=(n+1)%20;face([rings[k][n],rings[k][j],rings[k+1][j],rings[k+1][n]],c);}};
    oval(.063,.063,.132,.009,.008,.026,'#99bca5');
    for(let n=0;n<7;n++){const a=(n/6)*Math.PI;face([[.063+.010*Math.cos(a),.063+.010*Math.sin(a),.151],[.063+.020*Math.cos(a),.063+.020*Math.sin(a),.166],[.063+.008*Math.cos(a),.063+.008*Math.sin(a),.153]],'#7ba991');}
    face([[.045,.064,.12],[.038,.060,.119],[.023,.043,.184],[.032,.042,.186]],'#7ba991');
    slab(.018,.037,.183,.018,.014,.005,'#a8c0a0');
    face([[.020,.040,.188],[.033,.040,.188],[.030,.040,.21],[.025,.040,.201]],'#e7bd63');
    slab(.077,.068,.098,.015,.006,.034,'#6b9d8b');
    line([.071,.079,.072],[.067,.077,.124],'#5f8d79',.25);
  }
  const vertices=faces.flatMap(f=>f.points),h=product.geometry.x.h;
  if(!vertices.every(([x,y,z])=>x>=.0125-1e-9&&x<=.1125+1e-9&&y>=.0125-1e-9&&y<=.1125+1e-9&&z>=0&&z<=h+1e-9))throw Error(id+' dimensions');
  product.geometry={...product.geometry,faces};
  const ps=vertices.map(v=>project(roomStandard.camera,v)),xs=ps.map(p=>p[0]),ys=ps.map(p=>p[1]);
  const viewBox=[Math.floor(Math.min(...xs)-3),Math.floor(Math.min(...ys)-3),0,0];viewBox[2]=Math.ceil(Math.max(...xs)+3)-viewBox[0];viewBox[3]=Math.ceil(Math.max(...ys)+3)-viewBox[1];
  const checkEdges=[
    {a:[.0125,.1125,0],b:[.1125,.1125,0],label:'base X contact',outer:true,contrast:'alpha'},
    {a:[.1125,.0125,0],b:[.1125,.1125,0],label:'base Y contact',outer:true,contrast:'alpha'},
    {a:[.0125,.1125,.012],b:[.1125,.1125,.012],label:'base X top'},
    {a:[.1125,.0125,.012],b:[.1125,.1125,.012],label:'base Y top'},
  ].map(e=>({...e,screen:[e.a,e.b].map(v=>project(roomStandard.camera,v).map((v,i)=>v-viewBox[i]))}));
  const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="${viewBox[2]*8}" height="${viewBox[3]*8}" viewBox="${viewBox.join(' ')}">${faces.map(f=>`<polygon points="${f.points.map(p=>project(roomStandard.camera,p).join(',')).join(' ')}" fill="${f.color}" stroke="${f.color}" stroke-width=".08"/>`).join('')}${lines.map(l=>{const a=project(roomStandard.camera,l.a),b=project(roomStandard.camera,l.b);return `<line x1="${a[0]}" y1="${a[1]}" x2="${b[0]}" y2="${b[1]}" stroke="${l.color}" stroke-width="${l.width}"/>`;}).join('')}</svg>`;
  const guide={viewBox,dimensionsL:[.10,.10,h],pixelGroundOrigin:roomStandard.camera.origin.map((v,i)=>v-viewBox[i]),checkEdges};
  fs.writeFileSync(`${dir}/${id}-coordinate-guide.svg`,svg);
  fs.writeFileSync(`${dir}/${id}-coordinate-guide.json`,JSON.stringify(guide,null,2)+'\n');
  const png=await page.evaluate(async svg=>{const im=new Image();im.src='data:image/svg+xml;base64,'+btoa(svg);await im.decode();const c=document.createElement('canvas');c.width=im.width;c.height=im.height;c.getContext('2d').drawImage(im,0,0);return c.toDataURL('image/png').split(',')[1];},svg);
  fs.writeFileSync(`${dir}/${id}-coordinate-guide.png`,Buffer.from(png,'base64'));
  const axes=svg.replace('</svg>',checkEdges.map(e=>{const [a,b]=[e.a,e.b].map(p=>project(roomStandard.camera,p));return `<line x1="${a[0]}" y1="${a[1]}" x2="${b[0]}" y2="${b[1]}" stroke="${e.a[0]===e.b[0]?'#cc236b':'#187ebd'}" stroke-width=".50"/>`;}).join('')+'</svg>');
  const axesPng=await page.evaluate(async svg=>{const im=new Image();im.src='data:image/svg+xml;base64,'+btoa(svg);await im.decode();const c=document.createElement('canvas');c.width=im.width;c.height=im.height;c.getContext('2d').drawImage(im,0,0);return c.toDataURL('image/png').split(',')[1];},axes);
  fs.writeFileSync(`${dir}/${id}-coordinate-guide-axes.png`,Buffer.from(axesPng,'base64'));
  console.log(id,viewBox,faces.length);
}
fs.writeFileSync(`${dir}/models.json`,JSON.stringify({standard:roomStandard,products},null,2)+'\n');
} finally {await browser.close();}
