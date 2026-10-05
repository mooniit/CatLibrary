const {chromium}=require('../../.tooling/browser/node_modules/playwright-core');
const {readFileSync,writeFileSync}=require('node:fs');
const {join}=require('node:path');
const dir=join(__dirname,'lunar-assets-v5');
(async()=>{
  const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
  try{
    const page=await browser.newPage();
    const manifest=JSON.parse(readFileSync(join(dir,'manifest.json'))),window=manifest.assets.find(a=>a.id==='window-left');
    for(const mode of ['day','night']){
      const view=manifest.assets.find(a=>a.id==='view-left-'+mode),svg=readFileSync(join(dir,window.svg),'utf8');
      const image=`<image x="${view.viewBox[0]}" y="${view.viewBox[1]}" width="${view.viewBox[2]}" height="${view.viewBox[3]}" href="data:image/svg+xml;base64,${readFileSync(join(dir,view.svg)).toString('base64')}"/>`;
      writeFileSync(join(dir,'window-detail-'+mode+'.svg'),svg.replace(/(<svg[^>]*>)/,'$1'+image));
    }
    const entries=[['window-detail-night.svg','窗户 · 侧框与加深窗台'],['frame-portrait-left.svg','画框 · 弧面线脚与侧面卷纹']].map(([file,label])=>({label,svg:readFileSync(join(dir,file),'utf8')}));
    const result=await page.evaluate(async entries=>{
      const c=document.createElement('canvas');c.width=1400;c.height=800;const ctx=c.getContext('2d');ctx.fillStyle='#eeeae2';ctx.fillRect(0,0,c.width,c.height);
      for(let n=0;n<entries.length;n++){
        const e=entries[n],img=new Image();img.src='data:image/svg+xml;base64,'+btoa(unescape(encodeURIComponent(e.svg)));await img.decode();
        const scale=Math.min((n?480:760)/img.width,600/img.height),x=n?1080:420;
        ctx.drawImage(img,x-img.width*scale/2,110+(600-img.height*scale)/2,img.width*scale,img.height*scale);
        ctx.fillStyle='#293e57';ctx.font='24px sans-serif';ctx.textAlign='center';ctx.fillText(e.label,x,55);
      }
      ctx.font='18px sans-serif';ctx.fillText('同一固定投影下的独立构件放大图',700,765);
      return c.toDataURL('image/png').split(',')[1];
    },entries);writeFileSync(join(dir,'joinery-details.png'),Buffer.from(result,'base64'));
    console.log('Detailed joinery sheet and two composed window SVGs exported.');
  }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
