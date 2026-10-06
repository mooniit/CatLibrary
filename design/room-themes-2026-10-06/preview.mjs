import {fixtures,orient,slots,camera,project,roomStandard} from '../room-structure-2026-10-05/geometry.mjs';
import {scene,artwork} from '../room-structure-2026-10-05/lunar-art.mjs';
import {templates,themes} from './theme-geometry.mjs';
const $=id=>document.getElementById(id),manifest=Object.fromEntries(await Promise.all(Object.keys(themes).map(async key=>[key,await(await fetch('./'+key+'/manifest.json')).json()])));
const descriptions={wood:{bookshelf:'开放梯架 · 三层木板 · 榫接侧架',desk:'A 字支架 · 连贯横撑 · 圆角桌板',chair:'三根椅背竖杆 · 亚麻坐垫 · 收细椅腿',tree:'矩形阶梯 · 木质立柱 · 开放木托台',bed:'三道低背木条 · 亚麻软垫 · 低前沿'},royal:{bookshelf:'拱顶藏书柜 · 壁柱 · 下部双门',desk:'弧边写字桌 · 酒红软包桌心 · 曲腿',chair:'盾形软包椅背 · 开放扶手 · 雕饰曲腿',tree:'车木立柱 · 椭圆高台 · 雕饰柜式底座',bed:'低背小躺椅 · 低扶手圆钮 · 绗缝绒垫'}};
const defaults=()=>Object.fromEntries(fixtures.map(f=>[f.id,f.facing])),frames=()=>Object.fromEntries(slots.filter(s=>s.type==='art').map(s=>[s.id,s.id.endsWith('back')?'landscape':'portrait'])),pictures=()=>Object.fromEntries(slots.filter(s=>s.type==='art').map(s=>[s.id,s.id.endsWith('back')?'starry':'pearl']));
const query=new URLSearchParams(location.search),state={theme:query.get('theme')==='royal'?'royal':'wood',windowMode:query.get('mode')==='night'?'night':'day',facings:defaults(),frames:frames(),pictures:pictures(),hidden:[],grid:false,leftWindow:true,rightWindow:true,rug:true,art:true};
function wallDecor(slot){
  const key=state.frames[slot.id],a=manifest[state.theme].assets.find(a=>a.id===`frame-${key}-${slot.wall}`),t=templates[key],centerZ=slot.z+slot.h/2,z=centerZ-t.h/2,o=a.opening,u=slot.s-t.w/2;
  const point=(v,Z)=>slot.wall==='left'?[.0068,v,Z]:[v,.0068,Z],ps=arr=>arr.map(([v,Z])=>project(camera(),point(v,Z))),kind=state.pictures[slot.id];let picture='';
  if(kind){const W=o.right-o.left,H=o.top-o.bottom,iw=Math.min(W,H*artwork[kind].ratio),ih=iw/artwork[kind].ratio,cx=u+(o.left+o.right)/2,cz=z+(o.bottom+o.top)/2;
    const S=slot.wall==='left'?[cx+iw/2,cx-iw/2]:[cx-iw/2,cx+iw/2];
    const [A,B,C]=ps([[S[0],cz+ih/2],[S[1],cz+ih/2],[S[0],cz-ih/2]]),matrix=`matrix(${B[0]-A[0]} ${B[1]-A[1]} ${C[0]-A[0]} ${C[1]-A[1]} ${A[0]} ${A[1]})`;
    picture=`<polygon points="${ps([[u+o.left,z+o.bottom],[u+o.right,z+o.bottom],[u+o.right,z+o.top],[u+o.left,z+o.top]]).map(p=>p.join(',')).join(' ')}" fill="#f6eedb"/><image href="${artwork[kind].file}" width="1" height="1" transform="${matrix}" preserveAspectRatio="none" data-artwork="${kind}" data-original-aspect="${artwork[kind].ratio}"/>`;
  }
  const axis=slot.wall==='left'?camera().by:camera().bx,delta=slot.s-.18;
  return picture+`<image href="${state.theme}/${a.svg}" x="${a.viewBox[0]+axis[0]*delta}" y="${a.viewBox[1]+axis[1]*delta}" width="${a.viewBox[2]}" height="${a.viewBox[3]}" data-frame="${key}"/>`;
}
function refresh(){
  const assets=manifest[state.theme].assets; $('theme').value=state.theme;$('mode').value=state.windowMode;
  $('room').innerHTML=scene({...state,assets,assetBase:state.theme+'/',wallDecor});
  if($('coordinate-guides').checked)for(const f of fixtures.filter(f=>!state.hidden.includes(f.id)).map(f=>orient(f,state.facings[f.id]))){const a=assets.find(a=>a.id===f.id+'-'+f.facing),p=project(camera(),[f.x,f.y,0]),W=a.viewBox[2],H=a.viewBox[3],x=p[0]-a.pixelGroundOrigin[0],y=p[1]-a.pixelGroundOrigin[1];$('room').innerHTML+=`<g data-coordinate-guide="${f.id}" transform="translate(${x} ${y})"><image href="${state.theme}/${a.coordinateGuide}" width="${W}" height="${H}" opacity=".3" ${f.facing==='y'?`transform="translate(${W} 0) scale(-1 1)"`:''}/>${a.guideEdges.map(e=>`<line x1="${e.screen[0][0]}" y1="${e.screen[0][1]}" x2="${e.screen[1][0]}" y2="${e.screen[1][1]}" stroke="#367f98" stroke-width="1"/>`).join('')}</g>`;}
  $('subtitle').textContent=state.theme==='wood'?'浅黄橡木、亚麻与开放结构，轻巧安静。':'胡桃木、象牙色雕饰与酒红绒垫，古典而温暖。';
  $('frame-template').value=state.frames[$('frame-slot').value];$('picture').value=state.pictures[$('frame-slot').value]||'';
  const selected=orient(fixtures.find(f=>f.id===$('item').value),state.facings[$('item').value]);$('rotate').textContent='转向：+'+selected.facing.toUpperCase()+' → +'+(selected.facing==='x'?'Y':'X');
  $('hide').textContent=state.hidden.includes(selected.id)?'显示此件':'隐藏此件';
  const occupied=new Set(),conflicts=[];for(const f of fixtures.filter(f=>!state.hidden.includes(f.id)).map(f=>orient(f,state.facings[f.id])))for(const cell of f.cells){const k=cell.join(',');if(occupied.has(k))conflicts.push(k);occupied.add(k);}
  $('status').textContent=conflicts.length?'检测到占格冲突':'8 × 8 固定房屋 · 家具沿用原位置 · 占格互斥';
  $('gallery').innerHTML=fixtures.map(f=>`<article><h3>${f.label}</h3><div class="pair">${['x','y'].map(dir=>`<a href="${state.theme}/${f.id}-${dir}.png"><img src="${state.theme}/${f.id}-${dir}.svg" alt="${f.label} +${dir.toUpperCase()}"><span>+${dir.toUpperCase()}</span></a>`).join('')}</div><p>${descriptions[state.theme][f.id]}</p></article>`).join('');
  $('frame-gallery').innerHTML=Object.entries(templates).map(([key,t])=>`<article><h3>${t.label} · ${t.w*8} × ${t.h*8} 格</h3><div class="pair"><a href="${state.theme}/frame-${key}-flat.svg"><img src="${state.theme}/frame-${key}-flat.svg" alt="${t.label}正面"></a><a href="${state.theme}/frame-${key}-left.svg"><img src="${state.theme}/frame-${key}-left.svg" alt="${t.label}实体厚度"></a></div><p>${state.theme==='wood'?'圆润木条与榫口，框边顺木纹。':'层叠线脚、金色领圈与浅浮雕。'} 画芯独立，保持原画比例。</p></article>`).join('');
  $('window-gallery').innerHTML=['left','right'].map(side=>{const w=assets.find(a=>a.id==='window-'+side),v=assets.find(a=>a.id===`view-${side}-${state.windowMode}`);return `<article><h3>${side==='left'?'左墙':'右墙'}窗</h3><svg style="width:100%;height:170px" viewBox="${w.viewBox.join(' ')}" aria-label="实体窗户与天空">${[v,w].map(a=>`<image href="${state.theme}/${a.svg}" x="${a.viewBox[0]}" y="${a.viewBox[1]}" width="${a.viewBox[2]}" height="${a.viewBox[3]}"/>`).join('')}</svg><p>${state.theme==='wood'?'四格木窗、圆润木窗台。':'三联窗扇、弧形窗楣、雕饰窗台。'} 天空独立切换。</p></article>`;}).join('');
  $('table').innerHTML=fixtures.flatMap(f=>['x','y'].map(dir=>{const a=orient(f,dir);return `<tr><td>${f.label} / +${dir.toUpperCase()}</td><td>${[a.w,a.d,a.h].map(v=>+(v*8).toFixed(3)).join(' × ')}</td><td>${a.cols} × ${a.rows}</td><td>[${a.anchor}]</td><td>${[a.x*8,a.y*8,0].map(v=>+v.toFixed(3)).join(', ')}</td></tr>`;})).join('');
  window.themeStudy={state:structuredClone(state),standard:roomStandard,camera:camera(),slots,conflicts,manifest:manifest[state.theme],fixtures:fixtures.map(f=>orient(f,state.facings[f.id])),setState:patch=>{Object.assign(state,patch);refresh();}};
}
$('theme').onchange=()=>{state.theme=$('theme').value;history.replaceState(null,'','?theme='+state.theme+'&mode='+state.windowMode);refresh();};$('mode').onchange=()=>{state.windowMode=$('mode').value;refresh();};
for(const id of ['grid','leftWindow','rightWindow','rug','art'])$(id).onchange=()=>{state[id]=$(id).checked;refresh();};
for(const id of ['item','frame-slot'])$(id).onchange=refresh;
$('coordinate-guides').onchange=refresh;
$('rotate').onclick=()=>{const id=$('item').value;state.facings[id]=state.facings[id]==='x'?'y':'x';refresh();};$('hide').onclick=()=>{const id=$('item').value;state.hidden=state.hidden.includes(id)?state.hidden.filter(s=>s!==id):[...state.hidden,id];refresh();};
$('frame-template').onchange=()=>{state.frames[$('frame-slot').value]=$('frame-template').value;refresh();};$('picture').onchange=()=>{state.pictures[$('frame-slot').value]=$('picture').value||null;refresh();};
$('reset').onclick=()=>{state.facings=defaults();state.hidden=[];state.frames=frames();state.pictures=pictures();$('coordinate-guides').checked=false;for(const id of ['grid','leftWindow','rightWindow','rug','art'])state[id]=$(id).checked=id!=='grid';refresh();};
refresh();
