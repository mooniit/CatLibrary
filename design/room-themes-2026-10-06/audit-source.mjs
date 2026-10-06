import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createRequire} from 'node:module';
import {constructionGuide,auditAlpha} from './furniture-geometry.mjs';
import {registerSource} from './register-source.mjs';
const dir=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(dir,'../..'),[theme,id,file]=process.argv.slice(2);
const {chromium}=createRequire(path.join(root,'.tooling/browser/package.json'))('playwright-core'),browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true}),page=await browser.newPage(),url=async file=>'data:image/png;base64,'+(await fs.readFile(file)).toString('base64');
try{const guide=constructionGuide(theme,id),r=await registerSource(page,{source:await url(file),guide,guideImage:await url(path.join(dir,theme,id+'-coordinate-guide.png'))}),alpha=auditAlpha(r.rgba,guide),passed=r.passed&&!alpha.overflow&&!alpha.edge;console.log(JSON.stringify({passed,alpha,registration:r.registration,axisChecks:r.axisChecks},null,2));if(!passed)process.exitCode=1;}finally{await browser.close();}
