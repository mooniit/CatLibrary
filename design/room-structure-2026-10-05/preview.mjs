import {fitCalibration,camera,project,box,boxFaces,sortBoxes,fixtures,slots,orient,rectCells,rotateMask,validCells} from './geometry.mjs';
const data=await (await fetch('./calibration.json')).json(),fit=fitCalibration(data),NS='http://www.w3.org/2000/svg';
const $=id=>document.getElementById(id);
const state={a:8,factor:1.5,mode:'fixtures',grid:true,axes:true,leftWindow:true,rightWindow:true,art:true,rug:true,selected:'bookshelf',facings:Object.fromEntries(fixtures.map(f=>[f.id,f.facing])),lFacing:'x'};
function element(type,attrs,parent){const e=document.createElementNS(NS,type);for(const[k,v]of Object.entries(attrs))e.setAttribute(k,v);parent.append(e);return e;}
function poly(parent,c,points,fill,stroke='#75808a',width=1.5,extra={}){return element('polygon',{points:points.map(p=>project(c,p).join(',')).join(' '),fill,stroke,'stroke-width':width,'stroke-linejoin':'round',...extra},parent);}
function line(parent,c,a,b,color='#8ba8b8',width=1.5,dash=''){const A=project(c,a),B=project(c,b);return element('line',{x1:A[0],y1:A[1],x2:B[0],y2:B[1],stroke:color,'stroke-width':width,'stroke-dasharray':dash},parent);}
function text(parent,c,p,value,color='#315f77',dx=0,dy=0){const A=project(c,p),e=element('text',{x:A[0]+dx,y:A[1]+dy,fill:color,stroke:'#f6f8f8','stroke-width':4,'paint-order':'stroke'},parent);e.textContent=value;return e;}
function rounded(x,y,w,d,r,z){const points=[];for(const[cx,cy,start]of[[x+w-r,y+r,-90],[x+w-r,y+d-r,0],[x+r,y+d-r,90],[x+r,y+r,180]])for(let i=0;i<=8;i++){const t=(start+i*90/8)*Math.PI/180;points.push([cx+r*Math.cos(t),cy+r*Math.sin(t),z]);}return points;}
function paintBoxes(parent,c,parts){for(const b of sortBoxes(parts,c)){const group=element('g',{'data-piece':b.kind},parent);for(const f of boxFaces(b))poly(group,c,f.points,f.color,'#75808a',b.kind==='wall'?0:1.5);}}
function wallPieces(c,s,enabled){
  const t=.014,h=c.wallHeight;
  const make=(u,z,w,hh)=>s==='left'?box(-t,u,z,t,w,hh,'#eeeae0','wall'):box(u,-t,z,w,t,hh,'#eeeae0','wall');
  if(!enabled)return[make(0,0,1,h)];
  const slot=slots.find(p=>p.id==='window-'+s),u=slot.s-slot.w/2,z=slot.z;
  return[make(0,0,u,h),make(u+slot.w,0,1-u-slot.w,h),make(u,0,slot.w,z),make(u,z+slot.h,slot.w,h-z-slot.h)];
}
function wallFixtures(s,c,enabled,type){
  const parts=[],normal=.026,p=.016;
  for(const slot of slots.filter(p=>p.wall===s&&p.type===type)){
    if(!enabled||slot.z+slot.h>c.wallHeight)continue;
    const a=slot.s-slot.w/2,z=slot.z,w=slot.w,h=slot.h;
    const add=(u,zz,ww,hh,color='#ded8ca')=>parts.push(s==='left'?box(-.004,u,zz,normal,ww,hh,color,'slot'):box(u,-.004,zz,ww,normal,hh,color,'slot'));
    add(a,z,w,p);add(a,z+h-p,w,p);add(a,z+p,p,h-2*p);add(a+w-p,z+p,p,h-2*p);
    if(type==='window')parts.push(s==='left'?box(0,a-.01,z-.008,.046,w+.02,.008,'#ded8ca','sill'):box(a-.01,0,z-.008,w+.02,.046,.008,'#ded8ca','sill'));
    else add(a+p,z+p,w-2*p,h-2*p,'#94a7b2');
  }
  return parts;
}
function furnitureParts(f){
  const parts=[],p=.014,depth=f.facing==='x'?f.w:f.d,width=f.facing==='x'?f.d:f.w;
  const add=(u,v,z,du,dv,h,color='#e2dccf')=>parts.push(f.facing==='x'?box(f.x+u,f.y+v,z,du,dv,h,color,f.id):box(f.x+width-v-dv,f.y+u,z,dv,du,h,color,f.id));
  if(f.id==='bookshelf'){
    add(0,0,p,p,width,f.h-2*p,'#8a9da8');add(p,0,p,depth-p,p,f.h-2*p);add(p,width-p,p,depth-p,p,f.h-2*p);
    for(const z of[0,f.h-p])add(0,0,z,depth,width,p);
    const step=(f.h-p)/3;
    for(const z of[step,step*2])add(p,p,z,depth-p,width-2*p,p);
    for(let i=0;i<3;i++)for(let n=0;n<4;n++)add(p*2,p+.04+n*.045,p+i*step,depth*.48,.022,step*.7,'#708b9c');
  }else if(f.id==='desk'){
    add(0,0,f.h-.018,depth,width,.018);
    for(const u of[.012,depth-.03])for(const v of[.012,width-.03])add(u,v,0,.018,.018,f.h-.018);
    add(depth-.018,.03,f.h-.047,.018,width-.06,.029,'#d5cebf');
  }else if(f.id==='chair'){
    add(0,0,.093,depth,width,.016,'#7c96a7');
    for(const u of[.007,depth-.024])for(const v of[.007,width-.024])add(u,v,0,.017,.017,.093);
    add(0,0,.109,.014,width,f.h-.109);
  }else if(f.id==='tree'){
    add(0,0,0,depth,width,.015);
    for(const[z,h]of[[.015,.075],[.102,.078],[.192,.063]])add(.05,.06,z,.022,.022,h);
    for(const[u,v,z,w,d]of[[.03,.035,.09,.125,.12],[.02,.035,.18,.12,.12],[.01,.03,.255,.12,.12]]){
      add(u,v,z,w,d,.012,'#7c96a7');add(u,v,z+.012,.01,d,.02);
    }
  }else if(f.id==='bed'){
    add(0,0,0,depth,width,.014);add(p,p,.014,depth-2*p,width-2*p,.018,'#7c96a7');
    add(0,0,.014,p,width,.065);
    for(const v of[0,width-p])add(p,v,.014,depth-p,p,.042);
    add(depth-p,p,.014,p,width-2*p,.018);
  }
  return parts;
}
function masks(config){
  if(config.mode==='empty')return[];
  if(config.mode==='l'){
    const mask=config.lFacing==='x'?[[0,0],[1,0],[0,1]]:rotateMask([[0,0],[1,0],[0,1]]),anchor=Math.floor(config.a*.4);
    return[{id:'l',label:'L 形',cells:mask.map(([x,y])=>[x+anchor,y+anchor])}];
  }
  return fixtures.map(f=>{const actual=orient(f,config.facings[f.id]);return{...actual,cells:rectCells(actual,config.a)};});
}
function render(svg,config){
  const c=camera(fit,config.factor);svg.setAttribute('viewBox','0 0 '+c.width+' '+c.height);svg.replaceChildren();
  const layer=element('g',{},svg);
  paintBoxes(layer,c,[box(0,0,-.022,1,1,.022,'#e6e0d4','floor')]);
  if(config.rug)poly(layer,c,rounded(.27,.28,.5,.52,.06,.001),'#c1cdd2','none');
  const occupied=masks(config),selected=config.mode==='l'?'l':config.selected;
  if(config.grid){
    for(let i=0;i<=config.a;i++){line(layer,c,[i/config.a,0,.003],[i/config.a,1,.003]);line(layer,c,[0,i/config.a,.003],[1,i/config.a,.003]);}
    for(const e of occupied)for(const[x,y]of e.cells){
      const a=config.a,isSelected=e.id===selected;
      poly(layer,c,[[x/a,y/a,.004],[(x+1)/a,y/a,.004],[(x+1)/a,(y+1)/a,.004],[x/a,(y+1)/a,.004]],isSelected?'#659db74d':'#607d8b0a',isSelected?'#376d88':'#8ba8b8',isSelected?2:1,{'data-cell':x+','+y,'data-owner':e.id});
    }
  }
  paintBoxes(layer,c,[...wallPieces(c,'left',config.leftWindow),...wallPieces(c,'right',config.rightWindow)]);
  // Draw only the whole wall boundaries, never seams from the aperture tessellation.
  for(const b of[box(-.014,0,0,.014,1,c.wallHeight),box(0,-.014,0,1,.014,c.wallHeight)])
    for(const f of boxFaces(b))poly(layer,c,f.points,'none');
  const parts=[...wallFixtures('left',c,config.leftWindow,'window'),...wallFixtures('right',c,config.rightWindow,'window'),
    ...wallFixtures('left',c,config.art,'art'),...wallFixtures('right',c,config.art,'art')];
  if(config.mode==='fixtures')for(const f of fixtures)parts.push(...furnitureParts(orient(f,config.facings[f.id])));
  if(config.mode==='l')for(const[x,y]of occupied[0].cells)parts.push(box(x/config.a,y/config.a,0,1/config.a,1/config.a,.095,'#a2b7c2','l'));
  paintBoxes(layer,c,parts);
  // Occupancy contour stays visible during structural review, including under furniture.
  if(config.grid)for(const e of occupied.filter(e=>e.id===selected))for(const[x,y]of e.cells)
    poly(layer,c,[[x/config.a,y/config.a,.006],[(x+1)/config.a,y/config.a,.006],[(x+1)/config.a,(y+1)/config.a,.006],[x/config.a,(y+1)/config.a,.006]],'none','#315f77',2.4);
  if(config.axes){
    for(const[end,name,color]of[[[1.03,0,0],'+X','#b0443d'],[[0,1.03,0],'+Y','#28724b'],[[0,0,c.wallHeight+.06],'+Z','#315f77']]){
      line(layer,c,[0,0,0],end,color,3);text(layer,c,end,name,color,name==='+Y'?-28:7,name==='+Z'?-7:24);
    }
    text(layer,c,[0,0,0],'O','#315f77',9,-9);
  }
  if(config.mode!=='empty'){
    const e=occupied.find(e=>e.id===selected),f=config.mode==='l'?{x:Math.floor(config.a*.4)/config.a,y:Math.floor(config.a*.4)/config.a,w:2/config.a,d:2/config.a,h:.11}:e;
    if(f){const facing=config.mode==='l'?config.lFacing:config.facings[f.id],start=[f.x+f.w/2,f.y+f.d/2,f.h+.025],end=[start[0]+(facing==='x'?.09:0),start[1]+(facing==='y'?.09:0),start[2]];line(layer,c,start,end,'#315f77',4);text(layer,c,end,'朝 +'+facing.toUpperCase(),'#315f77',3,-5);}
  }
  return{camera:c,masks:occupied,parts};
}
function renderReference(){
  const ref=fit.references.find(r=>r.id===$('reference').value),svg=$('reference-svg');
  svg.setAttribute('viewBox','0 0 '+ref.size.join(' '));svg.replaceChildren();
  element('image',{href:ref.path,x:0,y:0,width:ref.size[0],height:ref.size[1]},svg);
  if($('overlay').checked){
    const[x,y]=ref.origin,w=ref.halfWidth,h=w*fit.slope;
    element('polyline',{points:[[x,y],[x+w,y+h],[x,y+2*h],[x-w,y+h],[x,y]].map(p=>p.join(',')).join(' '),fill:'none',stroke:'#67edf0','stroke-width':1.8,'stroke-dasharray':'5 3'},svg);
    for(const seg of ref.segments){
      const end=[seg.b[0],seg.a[1]+Math.abs(seg.b[0]-seg.a[0])*fit.slope];
      element('line',{x1:seg.a[0],y1:seg.a[1],x2:end[0],y2:end[1],stroke:'#67edf0','stroke-width':1.5},svg);
      for(const p of[seg.a,seg.b])element('circle',{cx:p[0],cy:p[1],r:2.4,fill:'#ffca74'},svg);
    }
  }
  const max=Math.max(...ref.residuals.map(p=>Math.abs(p.errorPixels)));
  $('reference-note').textContent=ref.note+' 采样线最大方向残差约 '+max.toFixed(2)+' 像素。';
}
function refresh(){
  state.a=Number($('density').value);state.factor=Number($('height').value);state.mode=$('mode').value;state.selected=$('selected').value;
  for(const[key,id]of[['grid','grid'],['axes','axes'],['leftWindow','left-window'],['rightWindow','right-window'],['art','art'],['rug','rug']])state[key]=$(id).checked;
  const result=render($('room'),state),selected=state.mode==='l'?'l':state.selected,entry=result.masks.find(p=>p.id===selected);
  $('turn').disabled=state.mode==='empty';$('selected').disabled=state.mode!=='fixtures';
  const facing=state.mode==='l'?state.lFacing:state.facings[state.selected];$('turn').textContent='切换朝向：+'+facing.toUpperCase();
  const valid=result.masks.every(e=>validCells(e.cells,state.a));
  $('status').textContent=state.mode==='empty'?'空房间 · 地板宽度保持一致':(entry?.label||'')+' · '+(entry?.cells.length||0)+' 格 · 正面 +'+facing.toUpperCase()+' · '+(valid?'占地在地板内':'存在越界');
  $('parameters').textContent='地面线斜率 ±'+fit.slope.toFixed(5)+'\n地面边线角度 ±'+(Math.atan(fit.slope)*180/Math.PI).toFixed(2)+'°\n在对称正交约束下：相机俯视约 '+fit.elevationDegrees.toFixed(2)+'°\nX = 540 + 480(x − y)\nY = O_y + '+(480*fit.slope).toFixed(3)+'(x + y) − '+fit.zScale.toFixed(3)+'z\n参考墙高 H = '+fit.referenceWallHeight.toFixed(4)+' L\n当前墙高 = '+result.camera.wallHeight.toFixed(4)+' L\n视图宽 1080；高 '+result.camera.height;
  window.roomStudy={fit,state:{...state,facings:{...state.facings}},...result,project:p=>project(result.camera,p)};
}
for(const id of['density','height','mode','selected','grid','axes','left-window','right-window','art','rug'])$(id).addEventListener('change',refresh);
$('turn').addEventListener('click',()=>{if(state.mode==='l')state.lFacing=state.lFacing==='x'?'y':'x';else state.facings[state.selected]=state.facings[state.selected]==='x'?'y':'x';refresh();});
$('reference').addEventListener('change',renderReference);$('overlay').addEventListener('change',renderReference);
for(const a of[6,8,10]){
  const card=document.createElement('div');card.className='compare-card';const heading=document.createElement('h3');heading.textContent=a+' × '+a;card.append(heading);
  const svg=element('svg',{class:'scene',role:'img','aria-label':a+'格结构比较'},card);
  const config={...state,a,axes:false,factor:1.5},result=render(svg,config),count=result.masks.find(e=>e.id==='bookshelf').cells.length;
  const note=document.createElement('small');note.textContent='同一书柜预留 '+count+' 格；地板和家具比例保持一致。';card.append(note);
  $('comparisons').append(card);
}
for(const s of slots){const tr=document.createElement('tr');for(const value of[s.label,s.wall==='left'?'左墙 X=0':'右墙 Y=0',s.s.toFixed(2),s.z.toFixed(2),s.w.toFixed(2)+' × '+s.h.toFixed(2)]){const td=document.createElement('td');td.textContent=value;tr.append(td);}$('slot-table').append(tr);}
refresh();renderReference();
