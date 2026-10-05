// User-requested deterministic mirroring. No generation calls in this build.
const {chromium}=require('../../.tooling/browser/node_modules/playwright-core');
const {readFileSync,writeFileSync,mkdirSync}=require('node:fs');
const {join}=require('node:path');
const assert=require('node:assert/strict');
const {deflateSync}=require('node:zlib');
function pngRGBA(values,w,h){
  const crc=buffer=>{let n=0xffffffff;for(const b of buffer){n^=b;for(let k=0;k<8;k++)n=(n>>>1)^((n&1)?0xedb88320:0);}return(n^0xffffffff)>>>0;};
  const chunk=(name,data)=>{const type=Buffer.from(name),size=Buffer.alloc(4),sum=Buffer.alloc(4);size.writeUInt32BE(data.length);sum.writeUInt32BE(crc(Buffer.concat([type,data])));return Buffer.concat([size,type,data,sum]);};
  const header=Buffer.alloc(13);header.writeUInt32BE(w);header.writeUInt32BE(h,4);header[8]=8;header[9]=6;
  const pixels=Buffer.from(values),rows=Buffer.alloc(h*(w*4+1));for(let y=0;y<h;y++)pixels.copy(rows,y*(w*4+1)+1,y*w*4,(y+1)*w*4);
  return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',header),chunk('IDAT',deflateSync(rows)),chunk('IEND',Buffer.alloc(0))]);
}
const assetFolder=process.argv[2]||'lunar-assets-v2',dir=join(__dirname,assetFolder);mkdirSync(dir,{recursive:true});
const dataUrl=path=>'data:image/png;base64,'+readFileSync(path).toString('base64');
(async()=>{
  const G=await import('./geometry.mjs'),T=await import('./lunar-templates.mjs'),N=await import('./lunar-joinery.mjs');
  const old=JSON.parse(readFileSync(join(__dirname,'lunar-assets/manifest.json'),'utf8'));
  const manifest={id:assetFolder.replace('assets','content'),standardId:G.roomStandard.id,camera:G.camera(),placementChanged:false,artSlotsChanged:{beforeCells:[1.28,1],afterMaxCells:[1.6,1.6],horizontalCentersCells:[1.44,6.56],centerHeightCells:4.05},secondFacingMethod:'exact horizontal pixel mirror of canonical +X, explicitly requested by user',frameTemplates:T.frameTemplates,assets:[]};
  const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
  try{
    const page=await browser.newPage();
    if(['lunar-assets-v4','lunar-assets-v5'].includes(assetFolder)){
      const previous=JSON.parse(readFileSync(join(__dirname,'lunar-assets-v3/manifest.json'),'utf8'));
      manifest.decorSkins={wall:previous.decorSkins.wall,floor:previous.decorSkins.floor};
      T.configureDecorSkins(Object.fromEntries(Object.entries(manifest.decorSkins).map(([key,skin])=>[key,{...skin,url:dataUrl(join(dir,skin.file))}])));
      T.configureNativeJoinery();
      manifest.decorProduction={style:'native shaped joinery, lacquer moulding and solid beveled relief',windowAndFrameImageSkins:false,frameDerivation:'three size parameters applied to shared solid joinery construction',windowDerivation:'one native solid construction and a symmetric mirror',roomGenerated:false};
      if(assetFolder==='lunar-assets-v5'){manifest.cornerTrim=false;manifest.windowViews={modes:['day','night'],subject:'one crescent moon, five sparse night stars; same composition in daytime',layer:'independent content behind window joinery',fit:'contain'};manifest.sillChange={before:{widthL:.34,depthL:.046},after:{widthL:.352,depthL:N.windowSill.depth},bottomHeightCells:3.136};}
    }
    if(assetFolder==='lunar-assets-v3'){
      const skins={};
      for(const key of['frame','window','wall','floor']){
        const raw=dataUrl(join(dir,key+'-master-source.png'));
        const prepared=await page.evaluate(async({url,key})=>{
          const i=new Image();i.src=url;await i.decode();const c=document.createElement('canvas');c.width=i.width;c.height=i.height;const ctx=c.getContext('2d');ctx.drawImage(i,0,0);
          let crop=[0,0,i.width,i.height];
          if(key==='frame'||key==='window'){
            const im=ctx.getImageData(0,0,c.width,c.height),p=im.data;for(let n=3;n<p.length;n+=4)p[n]=p[n]<220?0:Math.min(255,Math.round((p[n]-220)*255/35));
            const seen=new Uint8Array(c.width*c.height);let biggest=[];
            for(let n=0;n<seen.length;n++){if(seen[n]||!p[n*4+3])continue;const queue=[n];seen[n]=1;for(let k=0;k<queue.length;k++){const q=queue[k],x=q%c.width,y=Math.floor(q/c.width);for(const[dx,dy]of[[-1,-1],[0,-1],[1,-1],[-1,0],[1,0],[-1,1],[0,1],[1,1]]){const X=x+dx,Y=y+dy,z=Y*c.width+X;if(X>=0&&X<c.width&&Y>=0&&Y<c.height&&!seen[z]&&p[z*4+3]){seen[z]=1;queue.push(z);}}}if(queue.length>biggest.length)biggest=queue;}
            const keep=new Uint8Array(seen.length);for(const n of biggest)keep[n]=1;for(let n=0;n<seen.length;n++)if(!keep[n])p[n*4+3]=0;
            let x=c.width,y=c.height,X=0,Y=0;for(let v=0;v<c.height;v++)for(let u=0;u<c.width;u++)if(p[(v*c.width+u)*4+3]>=32){x=Math.min(x,u);y=Math.min(y,v);X=Math.max(X,u+1);Y=Math.max(Y,v+1);}crop=[x,y,X-x,Y-y];ctx.putImageData(im,0,0);
          }
          const out=document.createElement('canvas');out.width=1000;out.height=key==='window'?664:key==='wall'?808:1000;const ox=out.getContext('2d');ox.imageSmoothingQuality='high';ox.drawImage(c,...crop,0,0,out.width,out.height);
          let insets;
          if(key==='frame'){
            const p=ox.getImageData(0,0,out.width,out.height).data,w=out.width,h=out.height,opaque=(x,y)=>p[(y*w+x)*4+3]>64;
            let l=0,r=w-1,t=0,b=h-1;while(l<w/2&&!opaque(l,Math.floor(h/2)))l++;while(r>w/2&&!opaque(r,Math.floor(h/2)))r--;while(t<h/2&&!opaque(Math.floor(w/2),t))t++;while(b>h/2&&!opaque(Math.floor(w/2),b))b--;while(l<w/2&&opaque(l,Math.floor(h/2)))l++;while(r>w/2&&opaque(r,Math.floor(h/2)))r--;while(t<h/2&&opaque(Math.floor(w/2),t))t++;while(b>h/2&&opaque(Math.floor(w/2),b))b--;
            insets=[l,t,w-1-r,h-1-b];if(insets.some(v=>v<20||v>300))throw Error('Frame opening is not a usable transparent master: '+insets);
          }
          return{png:out.toDataURL('image/png').split(',')[1],width:out.width,height:out.height,insets,sourceCrop:crop};
        },{url:raw,key});
        const file=key+'-master.png';writeFileSync(join(dir,file),Buffer.from(prepared.png,'base64'));skins[key]={file,width:prepared.width,height:prepared.height,...(prepared.insets?{insets:prepared.insets}:{}),sourceCrop:prepared.sourceCrop};
      }
      manifest.decorSkins=skins;manifest.decorProduction={style:'hand-painted cream lacquer, sculpted gold moulding, soft lunar relief and ivory wood marquetry',masterCount:4,frameDerivation:'nine-patch from one square master; center omitted',windowDerivation:'one front-plane master; right wall is exact symmetric mirror',roomGenerated:false};
      T.configureDecorSkins(Object.fromEntries(Object.entries(skins).map(([key,skin])=>[key,{...skin,url:dataUrl(join(dir,skin.file))}])));
    }
    for(const f of G.fixtures){
      const base=old.assets.find(a=>a.id===f.id+'-x'),template=dataUrl(join(__dirname,'lunar-assets',base.png)),source=dataUrl(join(dir,f.id+'-x-source.png'));
      const result=await page.evaluate(async({source,template,width,height,dimensions,ground,camera})=>{
        const load=async url=>{const i=new Image();i.src=url;await i.decode();return i;},src=await load(source),tpl=await load(template);
        const canvas=document.createElement('canvas');canvas.width=src.width;canvas.height=src.height;const ctx=canvas.getContext('2d');ctx.drawImage(src,0,0);
        const im=ctx.getImageData(0,0,canvas.width,canvas.height),p=im.data;
        // Eliminate semi-transparent generated backdrop and detached residue; color is untouched.
        for(let i=3;i<p.length;i+=4)p[i]=p[i]<=220?0:Math.min(255,Math.round((p[i]-220)*255/35));
        const seen=new Uint8Array(canvas.width*canvas.height),components=[];
        for(let i=0;i<seen.length;i++){if(seen[i]||!p[i*4+3])continue;const queue=[i];seen[i]=1;for(let k=0;k<queue.length;k++){const q=queue[k],x=q%canvas.width,y=Math.floor(q/canvas.width);for(const[dx,dy]of[[-1,-1],[0,-1],[1,-1],[-1,0],[1,0],[-1,1],[0,1],[1,1]]){const X=x+dx,Y=y+dy,n=Y*canvas.width+X;if(X>=0&&X<canvas.width&&Y>=0&&Y<canvas.height&&!seen[n]&&p[n*4+3]){seen[n]=1;queue.push(n);}}}components.push(queue);}
        components.sort((a,b)=>b.length-a.length);for(const component of components.slice(1))for(const q of component)p[q*4+3]=0;
        ctx.putImageData(im,0,0);
        const bbox=(p,w,h)=>{let x=w,y=h,X=0,Y=0;for(let i=0;i<w*h;i++)if(p[i*4+3]){const u=i%w,v=Math.floor(i/w);x=Math.min(x,u);y=Math.min(y,v);X=Math.max(X,u+1);Y=Math.max(Y,v+1);}return[x,y,X,Y];};
        const crop=bbox(p,canvas.width,canvas.height),dest=document.createElement('canvas');dest.width=width;dest.height=height;const dctx=dest.getContext('2d');dctx.drawImage(tpl,0,0);const target=bbox(dctx.getImageData(0,0,width,height).data,width,height);dctx.clearRect(0,0,width,height);
        const scale=Math.min((target[2]-target[0])/(crop[2]-crop[0]),(target[3]-target[1])/(crop[3]-crop[1])),W=(crop[2]-crop[0])*scale,H=(crop[3]-crop[1])*scale,x=(target[0]+target[2]-W)/2,y=target[3]-H;
        dctx.imageSmoothingEnabled=true;dctx.imageSmoothingQuality='high';dctx.drawImage(canvas,...[crop[0],crop[1],crop[2]-crop[0],crop[3]-crop[1]],x,y,W,H);
        // Fit the visible silhouette inside the projected declared prism, with a one-pixel AA allowance.
        const [fw,fd,fh]=dimensions,ps=[];for(const u of[0,fw])for(const v of[0,fd])for(const z of[0,fh])ps.push([ground[0]+u*camera.bx[0]+v*camera.by[0],ground[1]+u*camera.bx[1]+v*camera.by[1]+z*camera.bz[1]]);
        ps.sort((a,b)=>a[0]-b[0]||a[1]-b[1]);const cross=(a,b,c)=>(b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]);
        const lower=[],upper=[];for(const[list,hull]of[[ps,lower],[[...ps].reverse(),upper]])for(const p of list){while(hull.length>1&&cross(hull.at(-2),hull.at(-1),p)<=0)hull.pop();hull.push(p);}const hull=[...lower.slice(0,-1),...upper.slice(0,-1)];
        const outside=p=>{for(let v=0;v<height;v++)for(let u=0;u<width;u++){if(p[(v*width+u)*4+3]<32)continue;for(let i=0;i<hull.length;i++){const a=hull[i],b=hull[(i+1)%hull.length];if(cross(a,b,[u+.5,v+.5])<-Math.hypot(b[0]-a[0],b[1]-a[1]))return true;}}return false;};
        const pivot=[ground[0]+fw/2*camera.bx[0]+fd/2*camera.by[0],ground[1]+(fw+fd)/2*camera.bx[1]];let fitScale=1;
        while(outside(dctx.getImageData(0,0,width,height).data)&&fitScale>.7){fitScale*=.995;dctx.clearRect(0,0,width,height);dctx.drawImage(canvas,crop[0],crop[1],crop[2]-crop[0],crop[3]-crop[1],pivot[0]+(x-pivot[0])*fitScale,pivot[1]+(y-pivot[1])*fitScale,W*fitScale,H*fitScale);}
        const xData=dctx.getImageData(0,0,width,height).data,yData=new Uint8Array(xData.length);
        if(outside(xData))throw Error('Sprite exceeds declared prism');
        for(let v=0;v<height;v++)for(let u=0;u<width;u++)for(let c=0;c<4;c++)yData[(v*width+width-1-u)*4+c]=xData[(v*width+u)*4+c];
        let differences=0;for(let v=0;v<height;v++)for(let u=0;u<width;u++)for(let c=0;c<4;c++)if(xData[(v*width+u)*4+c]!==yData[(v*width+width-1-u)*4+c])differences++;
        return{xRGBA:Array.from(xData),yRGBA:Array.from(yData),differences,sourceCrop:crop,destination:[pivot[0]+(x-pivot[0])*fitScale,pivot[1]+(y-pivot[1])*fitScale,W*fitScale,H*fitScale],envelopeFitScale:fitScale,removedComponents:components.length-1};
      },{source,template,width:base.viewBox[2],height:base.viewBox[3],dimensions:base.dimensionsL,ground:base.pixelGroundOrigin,camera:G.camera()});
      assert.equal(result.differences,0,'pixel-exact mirror '+f.id);
      for(const facing of['x','y']){
        const actual=G.orient(f,facing),[w,h]=base.viewBox.slice(2),anchor=facing==='x'?base.pixelGroundOrigin:[w-base.pixelGroundOrigin[0],base.pixelGroundOrigin[1]],vb=[G.camera().origin[0]-anchor[0],G.camera().origin[1]-anchor[1],w,h];
        const id=f.id+'-'+facing,pngBuffer=pngRGBA(result[facing==='x'?'xRGBA':'yRGBA'],w,h),png=pngBuffer.toString('base64');writeFileSync(join(dir,id+'.png'),pngBuffer);
        writeFileSync(join(dir,id+'.svg'),`<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}"><image href="data:image/png;base64,${png}" width="${w}" height="${h}"/></svg>\n`);
        manifest.assets.push({id,label:f.label,category:'furniture',svg:id+'.svg',png:id+'.png',viewBox:vb,pixelGroundOrigin:anchor,worldGroundAnchor:[actual.x,actual.y,0],dimensionsL:[actual.w,actual.d,actual.h],dimensionsCells:[actual.w*8,actual.d*8,actual.h*8],gridAnchor:actual.anchor,gridSize:[actual.cols,actual.rows],cells:actual.cells,facing:'+'+facing.toUpperCase(),canonicalSource:f.id+'-x-source.png',canonicalFacing:'+X',mirrored:facing==='y',mirrorPixelDifferences:result.differences,sourceCrop:result.sourceCrop,sourceFit:result.destination,envelopeFitScale:result.envelopeFitScale,removedSourceComponents:result.removedComponents});
      }
    }
    // Reuse the cream surface from the first bookcase; no new image is generated.
    const cream=await page.evaluate(async url=>{const img=new Image();img.src=url;await img.decode();const c=document.createElement('canvas');c.width=128;c.height=128;const ctx=c.getContext('2d');ctx.drawImage(img,85,900,35,75,0,0,128,128);return c.toDataURL('image/png').split(',')[1];},dataUrl(join(dir,'bookshelf-x-source.png')));
    writeFileSync(join(dir,'cream-grain.png'),Buffer.from(cream,'base64'));
    const wood=await page.evaluate(()=>{const c=document.createElement('canvas');c.width=640;c.height=640;const x=c.getContext('2d');x.fillStyle='#e5cfab';x.fillRect(0,0,640,640);let seed=271;const rnd=()=>{seed=(seed*16807)%2147483647;return seed/2147483647;};for(let plank=0;plank<16;plank++){x.fillStyle=`rgba(${220+Math.floor(rnd()*20)},${196+Math.floor(rnd()*20)},${157+Math.floor(rnd()*20)},.22)`;x.fillRect(plank*40,0,40,640);for(let i=0;i<30;i++){const a=plank*40+rnd()*40;x.beginPath();x.moveTo(a,0);for(let y=0;y<=640;y+=20)x.lineTo(a+Math.sin(y/80+i)*rnd()*1.2,y);x.strokeStyle='rgba(161,119,65,.13)';x.lineWidth=rnd()*.7+.15;x.stroke();}}return c.toDataURL('image/png').split(',')[1];});
    writeFileSync(join(dir,'wood-grain.png'),Buffer.from(wood,'base64'));
    const grain=dataUrl(join(dir,'cream-grain.png')),woodUrl=dataUrl(join(dir,'wood-grain.png'));
    const sources={};for(const[key,filename]of[['starry','painting-starry.png'],['pearl','painting-pearl.png']])sources[key]=dataUrl(join(__dirname,'../../assets/images/room',filename));
    function save(id,a,extra={}){writeFileSync(join(dir,id+'.svg'),a.svg+'\n');manifest.assets.push({id,category:'decor',svg:id+'.svg',png:id+'.png',viewBox:a.viewBox,...extra});}
    for(const type of['floor','rug','wall-left','wall-right'])save(type,T.materialSvg(type,grain,woodUrl),{category:type.startsWith('wall')?'wall-material':type==='floor'?'floor-material':'rug'});
    for(const wall of['left','right'])save('wall-'+wall+'-closed',T.materialSvg('wall-'+wall,grain,woodUrl,false),{category:'wall-material',wall,windowOpening:false});
    if(assetFolder==='lunar-assets-v4')save('corner-transition',N.cornerSvg(),{category:'wall-trim',radiusL:.009,worldAnchor:[0,0,0],heightL:G.camera().wallHeight});
    if(assetFolder==='lunar-assets-v5'){
      const V=await import('./lunar-window-views.mjs');
      for(const mode of V.windowModes)for(const wall of ['left','right']){
        const sourceFile='view-'+mode+'-source.png',slot=G.slots.find(s=>s.id==='window-'+wall);
        const sourceSize=await page.evaluate(async src=>{const i=new Image();i.src=src;await i.decode();return{width:i.width,height:i.height};},dataUrl(join(dir,sourceFile)));
        save('view-'+wall+'-'+mode,V.windowViewSvg(slot,mode,dataUrl(join(dir,sourceFile)),sourceSize),{category:'window-view',wall,mode,slotId:slot.id,sourceFile,sourceSize,originalAspect:sourceSize.width/sourceSize.height,fit:'contain'});
      }
    }
    const win=T.windowSvg(grain);save('window-left',win,{category:'window',wall:'left'});
    const vb=[1080-win.viewBox[0]-win.viewBox[2],win.viewBox[1],...win.viewBox.slice(2)];save('window-right',{viewBox:vb,svg:`<svg xmlns="http://www.w3.org/2000/svg" width="${vb[2]}" height="${vb[3]}" viewBox="${vb.join(' ')}"><g transform="translate(1080 0) scale(-1 1)">${win.inner}</g></svg>`},{category:'window',wall:'right',mirroredFrom:'window-left'});
    for(const key of Object.keys(T.frameTemplates)){
      save('frame-'+key+'-flat',T.frameFlatSvg(key,grain),{category:'frame-template',template:key,...T.frameTemplates[key]});
      for(const wall of['left','right']){const slot=G.slots.find(s=>s.wall===wall&&s.type==='art');save('frame-'+key+'-'+wall,T.frameSvg(slot,key,null,{},grain),{category:'frame-template-wall',wall,template:key,...T.frameTemplates[key]});}
    }
    for(const wall of['left','right'])for(const kind of['starry','pearl']){const key=kind==='starry'?'landscape':'portrait',slot=G.slots.find(s=>s.wall===wall&&s.type==='art'&&s.id.endsWith(kind==='starry'?'back':'front'));save(kind+'-'+wall,T.frameSvg(slot,key,kind,sources,grain),{category:'wall-art',template:key,slotId:slot.id,originalAspect:kind==='starry'?1424/1104:1191/1320,fit:'contain'});}
    // Render all reusable SVGs to matching transparent PNGs through the same browser.
    for(const a of manifest.assets.filter(a=>a.category!=='furniture')){const encoded=await page.evaluate(async({svg,w,h})=>{const i=new Image();i.src='data:image/svg+xml;base64,'+btoa(unescape(encodeURIComponent(svg)));await i.decode();const c=document.createElement('canvas');c.width=w;c.height=h;c.getContext('2d').drawImage(i,0,0,w,h);return c.toDataURL('image/png').split(',')[1];},{svg:readFileSync(join(dir,a.svg),'utf8'),w:a.viewBox[2],h:a.viewBox[3]});writeFileSync(join(dir,a.png),Buffer.from(encoded,'base64'));}
    if(['lunar-assets-v3','lunar-assets-v4','lunar-assets-v5'].includes(assetFolder)){
      const right=manifest.assets.find(a=>a.id==='window-right'),[w,h]=right.viewBox.slice(2);
      const values=await page.evaluate(async url=>{const i=new Image();i.src=url;await i.decode();const c=document.createElement('canvas');c.width=i.width;c.height=i.height;const ctx=c.getContext('2d');ctx.drawImage(i,0,0);const input=ctx.getImageData(0,0,c.width,c.height).data,out=new Uint8Array(input.length);for(let y=0;y<c.height;y++)for(let x=0;x<c.width;x++)for(let k=0;k<4;k++)out[(y*c.width+c.width-1-x)*4+k]=input[(y*c.width+x)*4+k];return Array.from(out);},dataUrl(join(dir,'window-left.png')));
      const png=pngRGBA(values,w,h);writeFileSync(join(dir,right.png),png);
      if(assetFolder==='lunar-assets-v3')writeFileSync(join(dir,right.svg),`<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="${right.viewBox.join(' ')}"><image href="data:image/png;base64,${png.toString('base64')}" x="${right.viewBox[0]}" y="${right.viewBox[1]}" width="${w}" height="${h}"/></svg>\n`);
      right.mirrorPixelDifferences=0;
    }
    for(const a of manifest.assets){
      if(['lunar-assets-v4','lunar-assets-v5'].includes(assetFolder)&&['window','frame-template','frame-template-wall','wall-art'].includes(a.category)){
        const t=a.template?T.frameTemplates[a.template]:{w:.32,h:.2125},m=a.category==='window'?N.windowModel():N.joineryModel(t.w,t.h);
        Object.assign(a,{construction:'native solid mesh, no image skin',parts:m.parts,normalAxisDepthL:.026,opening:m.opening});
      }
      if(a.id==='floor')Object.assign(a,{dimensionsL:[1,1,G.roomStandard.floorThickness],dimensionsCells:[8,8,G.roomStandard.floorThickness*8],worldGroundAnchor:[0,0,0],gridAnchor:[0,0],gridSize:[8,8],layer:'floor'});
      if(a.id==='rug')Object.assign(a,{dimensionsL:[.75,.75,.001],dimensionsCells:[6,6,.008],worldGroundAnchor:[.125,.125,.0008],gridAnchor:[1,1],gridSize:[6,6],movable:false,layer:'rug'});
      if(a.category==='wall-material')Object.assign(a,{wall:a.id.includes('left')?'left':'right',lengthL:1,heightL:G.camera().wallHeight,thicknessL:G.roomStandard.wallThickness});
      if(a.category==='window'||a.category==='wall-art'||a.category==='frame-template-wall'){
        const slot=G.slots.find(s=>s.id===(a.slotId|| (a.category==='window'?'window-'+a.wall:'art-'+a.wall+'-back')));
        const centerZ=slot.z+slot.h/2;Object.assign(a,{slotId:slot.id,wall:slot.wall,worldMountCenter:slot.wall==='left'?[0,slot.s,centerZ]:[slot.s,0,centerZ],depthL:.026});
        if(a.category==='window')Object.assign(a,{widthL:slot.w,heightL:slot.h,dimensionsCells:[slot.w*8,slot.h*8],sillDimensionsL:[slot.w+N.windowSill.overhang*2,N.windowSill.depth,N.windowSill.thickness],bottomHeightCells:slot.z*8,sillBottomHeightCells:(slot.z-.008)*8});
      }
    }
    writeFileSync(join(dir,'manifest.json'),JSON.stringify(manifest,null,2)+'\n');
    console.log(JSON.stringify({assets:manifest.assets.length,furnitureMirrors:5,pixelDifferences:0,frameTemplates:3}));
  }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
