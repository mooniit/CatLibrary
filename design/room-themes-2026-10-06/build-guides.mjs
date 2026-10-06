import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {constructionGuide} from './furniture-geometry.mjs';
import {fixtures} from '../room-structure-2026-10-05/geometry.mjs';
const dir=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(dir,'../..');
const {chromium}=createRequire(path.join(root,'.tooling/browser/package.json'))('playwright-core');
const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true}),page=await browser.newPage();
const specs=process.argv.slice(2);if(!specs.length)specs.push(...['wood','royal'].flatMap(theme=>fixtures.map(f=>theme+'/'+f.id)));
async function raster(svg){return page.evaluate(async svg=>{const im=new Image();im.src='data:image/svg+xml;base64,'+btoa(unescape(encodeURIComponent(svg)));await im.decode();const c=document.createElement('canvas');c.width=im.width;c.height=im.height;c.getContext('2d').drawImage(im,0,0);return c.toDataURL('image/png').split(',')[1];},svg);}
function axisGuide(guide){return guide.svg.replace('</svg>',guide.checkEdges.map(e=>{const[a,b]=e.screen.map(p=>p.map((v,i)=>v+guide.viewBox[i]));return`<line x1="${a[0]}" y1="${a[1]}" x2="${b[0]}" y2="${b[1]}" stroke="${e.a[0]===e.b[0]?'#cc236b':'#187ebd'}" stroke-width="1.15"/>`;}).join('')+'</svg>');}
try{for(const spec of specs){const [theme,id]=spec.split('/'),guide=constructionGuide(theme,id),stem=path.join(dir,theme,id+'-coordinate-guide');await fs.writeFile(stem+'.svg',guide.svg);await fs.writeFile(stem+'.png',Buffer.from(await raster(guide.svg),'base64'));await fs.writeFile(stem+'.json',JSON.stringify({...guide,svg:undefined},null,2)+'\n');await fs.writeFile(stem+'-axes.png',Buffer.from(await raster(axisGuide(guide)),'base64'));console.log(theme,id,guide.dimensionsL,guide.checkEdges.length);}}finally{await browser.close();}
