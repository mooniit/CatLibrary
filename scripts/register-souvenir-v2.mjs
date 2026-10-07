import fs from 'node:fs';
import path from 'node:path';
import {createRequire} from 'node:module';
import {registerSource} from '../design/room-themes-2026-10-06/register-source.mjs';
const dir='design/souvenirs-2026-10-07/v2', out='assets/images/room/souvenirs-v2';
const {chromium}=createRequire(path.resolve('.tooling/browser/package.json'))('playwright-core');
const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true}),page=await browser.newPage();
const data=p=>'data:image/png;base64,'+fs.readFileSync(p).toString('base64');
const reports=[];fs.mkdirSync(out,{recursive:true});
try {for(const id of process.argv.slice(2).length?process.argv.slice(2):['palace','louvre','fuji','pyramid','eiffel','liberty']){
 const guide=JSON.parse(fs.readFileSync(`${dir}/${id}-coordinate-guide.json`));
 const r=await registerSource(page,{source:data(`${dir}/${id}-x-source.png`),guide,guideImage:data(`${dir}/${id}-coordinate-guide.png`)});
 const report={id,passed:r.passed,registration:r.registration,axisChecks:r.axisChecks};reports.push(report);
 fs.writeFileSync(`${dir}/${id}-registration.json`,JSON.stringify(report,null,2)+'\n');
 console.log(id,r.passed,'aspect',r.registration.aspectError.toFixed(4),r.axisChecks.map(e=>[e.label,e.angleError.toFixed(2),e.distance.toFixed(2),e.passed]));
 if(!r.passed)continue;
 const png=await page.evaluate(({rgba,w,h})=>{const c=document.createElement('canvas');c.width=w;c.height=h;c.getContext('2d').putImageData(new ImageData(new Uint8ClampedArray(rgba),w,h),0,0);return c.toDataURL('image/png').split(',')[1];},{rgba:r.rgba,w:guide.viewBox[2],h:guide.viewBox[3]});
 fs.writeFileSync(`${out}/${id}-x.png`,Buffer.from(png,'base64'));
 }
 fs.writeFileSync(`${dir}/verification.json`,JSON.stringify(reports,null,2)+'\n');
 if(reports.some(r=>!r.passed))process.exitCode=1;
} finally {await browser.close();}
