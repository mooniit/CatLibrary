const {chromium}=require('../../.tooling/browser/node_modules/playwright-core');
const fs=require('node:fs');
(async()=>{
 const browser=await chromium.launch({executablePath:'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
 try{
  const page=await browser.newPage({viewport:{width:1100,height:1400},deviceScaleFactor:1});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto('http://127.0.0.1:8158/');
  await page.waitForFunction(()=>window.idlePreview?.layers.length===4);
  const checks=await page.evaluate(()=>{
   const {layers,paint}=window.idlePreview;
   const pixels=layer=>layer.context.getImageData(0,0,1000,1000).data;
   const difference=(a,b)=>{let count=0;for(let i=0;i<a.length;i++)if(Math.abs(a[i]-b[i])>2)count++;return count;};
   const views=layers.map(layer=>{
    paint(layer,0,'body');const body0=pixels(layer);
    paint(layer,layer.period/4,'body');const body1=pixels(layer);
    paint(layer,0,'tail');const tail0=pixels(layer);
    paint(layer,layer.period/4,'tail');const tail1=pixels(layer);
    return {id:layer.id,bodyChangedChannels:difference(body0,body1),tailChangedChannels:difference(tail0,tail1),size:[layer.image.width,layer.image.height]};
   });
   const mirrors=[];
   for(const pose of ['sleep','stand']){
    const x=layers.find(l=>l.id===pose+'-x'),y=layers.find(l=>l.id===pose+'-y');
    paint(x,1);paint(y,1);
    const canvas=document.createElement('canvas');canvas.width=canvas.height=1000;
    const context=canvas.getContext('2d');context.translate(1000,0);context.scale(-1,1);context.drawImage(x.context.canvas,0,0);
    mirrors.push({pose,changedChannels:difference(context.getImageData(0,0,1000,1000).data,pixels(y))});
   }
   return {views,mirrors,appearance:window.idlePreview.appearance};
  });
  if(checks.views.some(v=>v.bodyChangedChannels!==0||v.tailChangedChannels===0)||checks.mirrors.some(v=>v.changedChannels>1000)||errors.length)throw Error('Animation validation failed: '+JSON.stringify({checks,errors}));
  await page.getByRole('button',{name:'暂停动画',exact:true}).click();
  const phases=await page.evaluate(()=>{
   const sheet=document.createElement('canvas');sheet.width=1600;sheet.height=800;
   const c=sheet.getContext('2d');c.fillStyle='#f3f6f9';c.fillRect(0,0,1600,800);
   for(const [row,pose] of ['sleep','stand'].entries()){
    const layer=window.idlePreview.layers.find(l=>l.id===pose+'-x');
    for(let column=0;column<4;column++){
     window.idlePreview.paint(layer,layer.period*column/4);
     c.drawImage(layer.context.canvas,column*400,row*400,400,400);
     c.fillStyle='#293846';c.font='18px Microsoft YaHei';c.fillText(pose+' '+column+'/4',column*400+16,row*400+28);
    }
   }
   return sheet.toDataURL('image/png').split(',')[1];
  });
  fs.writeFileSync('design/room-cats-2026-10-08/idle-preview-phases.png',Buffer.from(phases,'base64'));
  await page.screenshot({path:'design/room-cats-2026-10-08/idle-preview-light.png',fullPage:true});
  await page.getByRole('button',{name:'切换夜晚底色',exact:true}).click();
  await page.screenshot({path:'design/room-cats-2026-10-08/idle-preview-night.png',fullPage:true});
  await page.getByRole('button',{name:'切换夜晚底色',exact:true}).click();
  await page.getByRole('button',{name:'播放动画',exact:true}).click();
  const video=await page.evaluate(async()=>{
   const canvas=document.createElement('canvas');canvas.width=1200;canvas.height=1260;
   const c=canvas.getContext('2d'),stream=canvas.captureStream(12);
   const type=MediaRecorder.isTypeSupported('video/webm;codecs=vp9')?'video/webm;codecs=vp9':'video/webm';
   const recorder=new MediaRecorder(stream,{mimeType:type,videoBitsPerSecond:2500000}),chunks=[];
   const ended=new Promise(resolve=>{recorder.ondataavailable=e=>chunks.push(e.data);recorder.onstop=resolve;});
   let active=true;const start=performance.now();
   function draw(){
    if(!active)return;
    c.fillStyle='#f3f6f9';c.fillRect(0,0,1200,1260);c.fillStyle='#293846';c.font='28px Microsoft YaHei';c.fillText('三花猫待机动作',40,45);
    for(const [index,layer] of window.idlePreview.layers.entries()){
     const x=(index%2)*600,y=Math.floor(index/2)*600+55;
     window.idlePreview.paint(layer,(performance.now()-start)/1000);c.drawImage(layer.context.canvas,x,y,600,600);
     c.font='24px Microsoft YaHei';c.fillText((layer.pose==='sleep'?'闭眼安睡':'四肢落地')+' · '+layer.facing.toUpperCase(),x+32,y+570);
    }
    requestAnimationFrame(draw);
   }
   recorder.start();draw();await new Promise(resolve=>setTimeout(resolve,5200));active=false;recorder.stop();await ended;stream.getTracks().forEach(t=>t.stop());
   const bytes=new Uint8Array(await new Blob(chunks,{type}).arrayBuffer());let binary='';for(let i=0;i<bytes.length;i+=32768)binary+=String.fromCharCode(...bytes.subarray(i,i+32768));return btoa(binary);
  });
  fs.writeFileSync('design/room-cats-2026-10-08/calico-idle-preview.webm',Buffer.from(video,'base64'));
  fs.writeFileSync('design/room-cats-2026-10-08/idle-preview-verification.json',JSON.stringify({date:'2026-10-08',browserPrototypeOnly:true,...checks,pageErrors:errors,staticAnatomy:'Light/night composite manually inspected: sleeping closed eyes with two visible forepaws and hidden hind paws; standing four separate paws. Fixed-room contact registration remains unverified.',tailAttachment:'Standing root manually declared inside rump; no body translation or automatic ground detection. Four-phase sheet requires manual inspection after each rerun.',nativeRoomVerified:false,phoneVerified:false},null,2)+'\n');
  console.log(JSON.stringify(checks));
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
