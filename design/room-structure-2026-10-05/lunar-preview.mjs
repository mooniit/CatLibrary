import {fixtures,orient,roomStandard,slots,camera,project} from './geometry.mjs';
import {scene,bounds,furniture,artwork} from './lunar-art.mjs';
import {frameTemplates,frameLayout,wallArtwork,configureDecorSkins,configureNativeJoinery} from './lunar-templates.mjs';
const $=id=>document.getElementById(id),defaults=Object.fromEntries(fixtures.map(f=>[f.id,f.facing]));
const manifest=await(await fetch('./lunar-assets-v5/manifest.json')).json();
configureDecorSkins(Object.fromEntries(Object.entries(manifest.decorSkins).map(([key,skin])=>[key,{...skin,url:'lunar-assets-v5/'+skin.file}])));
configureNativeJoinery();
const defaultFrames=()=>Object.fromEntries(slots.filter(s=>s.type==='art').map(s=>[s.id,s.id.endsWith('back')?'landscape':'portrait']));
const defaultArt=()=>Object.fromEntries(slots.filter(s=>s.type==='art').map(s=>[s.id,s.id.endsWith('back')?'starry':'pearl']));
const initialMode=new URLSearchParams(location.search).get('mode');
const state={facings:{...defaults},hidden:[],grid:false,axes:false,leftWindow:true,rightWindow:true,art:true,rug:true,windowMode:initialMode==='day'?'day':'night',frames:defaultFrames(),artworks:defaultArt()};
$('window-mode').value=state.windowMode;
function setWindowMode(mode){if(!['day','night'].includes(mode))throw new Error('Unknown room mode '+mode);state.windowMode=mode;$('window-mode').value=mode;refresh();}
function refresh(){
  for(const key of['grid','axes','leftWindow','rightWindow','art','rug'])state[key]=$(key).checked;
  $('lunar-room').innerHTML=scene({...state,assets:manifest.assets,assetBase:'lunar-assets-v5/',wallDecor:s=>wallArtwork(s,state.frames[s.id],state.artworks[s.id])});
  const slotId=$('frame-slot').value; $('frame-template').value=state.frames[slotId];$('frame-artwork').value=state.artworks[slotId]||'';
  const selected=fixtures.find(f=>f.id===$('item').value),f=orient(selected,state.facings[selected.id]);
  $('rotate').textContent='正面 +'+f.facing.toUpperCase()+' → +'+(f.facing==='x'?'Y':'X');
  $('hide-item').textContent=state.hidden.includes(f.id)?'显示此件':'隐藏此件';
  $('item-status').textContent=f.label+' · '+f.cols+'×'+f.rows+' 格 · 格锚点 ['+f.anchor.join(',')+']\n尺寸 '+[f.w,f.d,f.h].map(v=>+(v*8).toFixed(3)).join(' × ')+' 格';
  const occupied=new Set(),conflicts=[];for(const f of fixtures.filter(f=>!state.hidden.includes(f.id)).map(f=>orient(f,state.facings[f.id])))for(const cell of f.cells){const key=cell.join(',');if(occupied.has(key))conflicts.push(key);occupied.add(key);}
  $('scene-status').textContent='固定房屋 room-standard-v1 · '+(conflicts.length?'占格冲突':'占格互斥，家具在房间内')+' · 全部位置沿用确认样稿';
  window.lunarStudy={state:structuredClone(state),standard:roomStandard,camera:camera(),slots,conflicts,manifest,frameTemplates,setWindowMode,frameLayouts:slots.filter(s=>s.type==='art').map(s=>({id:s.id,...frameLayout(s,state.frames[s.id])})),fixtures:fixtures.map(f=>{const actual=orient(f,state.facings[f.id]);return{...actual,bounds:bounds(furniture(actual))};}),project:p=>project(camera(),p)};
}
for(const id of['grid','axes','leftWindow','rightWindow','art','rug','item'])$(id).addEventListener('change',refresh);
$('rotate').addEventListener('click',()=>{const id=$('item').value;state.facings[id]=state.facings[id]==='x'?'y':'x';refresh();});
$('hide-item').addEventListener('click',()=>{const id=$('item').value;state.hidden=state.hidden.includes(id)?state.hidden.filter(k=>k!==id):[...state.hidden,id];refresh();});
$('reset').addEventListener('click',()=>{state.facings={...defaults};state.hidden=[];state.frames=defaultFrames();state.artworks=defaultArt();for(const key of['grid','axes','leftWindow','rightWindow','art','rug'])$(key).checked=!['grid','axes'].includes(key);refresh();});
$('frame-slot').addEventListener('change',refresh);
$('frame-template').addEventListener('change',()=>{state.frames[$('frame-slot').value]=$('frame-template').value;refresh();});
$('frame-artwork').addEventListener('change',()=>{state.artworks[$('frame-slot').value]=$('frame-artwork').value||null;refresh();});
$('window-mode').addEventListener('change',()=>setWindowMode($('window-mode').value));
for(const f of fixtures){
  const div=document.createElement('div');div.className='card';div.innerHTML=`<h3>${f.label}</h3><div class="pair">${['x','y'].map(dir=>`<a href="lunar-assets-v5/${f.id}-${dir}.svg"><img src="lunar-assets-v5/${f.id}-${dir}.svg" alt="${f.label}正面 +${dir.toUpperCase()}">+${dir.toUpperCase()}</a>`).join('')}</div><small>${f.id==='bed'?'低前沿，大开口，深蓝绗缝软垫':f.id==='tree'?'软垫底座、双支柱、月牙托座':f.id==='bookshelf'?'浅拱顶、三层书架、真实侧板深度':f.id==='desk'?'圆角桌板、曲线桌腿、深蓝桌垫':'弧形包裹靠背、软垫、金色脚套'}</small>`;$('furniture-gallery').append(div);
  for(const dir of['x','y']){const a=orient(f,dir),tr=document.createElement('tr');for(const s of[f.label+' / +'+dir.toUpperCase(),[a.w,a.d,a.h].map(v=>+(v*8).toFixed(3)).join(' × '),a.cols+' × '+a.rows,'['+a.anchor.join(',')+']',[a.x*8,a.y*8,0].map(v=>+v.toFixed(3)).join(', ')]){const td=document.createElement('td');td.textContent=s;tr.append(td);}$('furniture-table').append(tr);}
}
for(const[id,label]of[['window','窗户'],['starry','猫爪星空'],['pearl','戴珍珠耳环的猫'],['wall','奶油抹灰墙'],['floor','浅色木地板'],['rug','月轨地毯']]){const div=document.createElement('div');div.className='card';const files=['window','starry','pearl','wall'].includes(id)?[id+'-left',id+'-right']:[id];div.innerHTML=`<h3>${label}</h3><div class="pair">${files.map(file=>`<a href="lunar-assets-v5/${file}.svg"><img src="lunar-assets-v5/${file}.svg" alt="${label}">SVG</a>`).join('')}</div>`;$('decor-gallery').append(div);}
for(const[key,t]of Object.entries(frameTemplates)){const div=document.createElement('div');div.className='card';div.innerHTML=`<h3>${t.label} · ${t.cells.join(' × ')} 格</h3><div class="pair"><a href="lunar-assets-v5/frame-${key}-left.svg"><img src="lunar-assets-v5/frame-${key}-left.svg" alt="${t.label}月轨空画框">透明 SVG</a><a href="lunar-assets-v5/frame-${key}-left.png">透明 PNG</a></div><small>实体框条、浅拱框楣、圆润角帽和月牙浮雕。独立画芯，等比居中装入。</small>`;$('frame-gallery').append(div);}
{const div=document.createElement('div');div.className='card';div.innerHTML='<h3>窗外月色 · 日／夜</h3><div class="pair">'+['day','night'].map(mode=>`<a href="lunar-assets-v5/view-left-${mode}.svg"><img src="lunar-assets-v5/view-left-${mode}.svg" alt="${mode==='day'?'日间淡月':'夜间月牙与星点'}">${mode==='day'?'日间':'夜间'}</a>`).join('')+'</div><small>同一轮月亮，同一局部构图。景色独立于窗框。</small>';$('decor-gallery').append(div);}
refresh();
