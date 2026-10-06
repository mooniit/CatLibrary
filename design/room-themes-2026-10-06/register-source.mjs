// Register to the furniture's actual numeric model, not an inferred single foot.
// Only uniform scale and one template-derived translation are allowed.
export async function registerSource(page,{source,guide,guideImage}){
  return page.evaluate(async({source,guide,guideImage})=>{
    const read=async url=>{const im=new Image();im.src=url;await im.decode();return im;};
    const canvas=(w,h)=>{const c=document.createElement('canvas');c.width=w;c.height=h;return c;};
    const bounds=(rgba,w,h)=>{let x0=w,y0=h,x1=0,y1=0;for(let y=0;y<h;y++)for(let x=0;x<w;x++)if(rgba[(y*w+x)*4+3]>=32){x0=Math.min(x0,x);y0=Math.min(y0,y);x1=Math.max(x1,x);y1=Math.max(y1,y);}return[x0,y0,x1+1,y1+1];};
    const im=await read(source),template=await read(guideImage),W=guide.viewBox[2],H=guide.viewBox[3],raw=canvas(im.width,im.height),rawCtx=raw.getContext('2d',{willReadFrequently:true});rawCtx.drawImage(im,0,0);
    const rawBounds=bounds(rawCtx.getImageData(0,0,im.width,im.height).data,im.width,im.height),target=canvas(W*3,H*3),targetCtx=target.getContext('2d',{willReadFrequently:true});targetCtx.drawImage(template,0,0,W*3,H*3);
    const targetBounds=bounds(targetCtx.getImageData(0,0,W*3,H*3).data,W*3,H*3).map(v=>v/3),sx=(targetBounds[2]-targetBounds[0])/(rawBounds[2]-rawBounds[0]),sy=(targetBounds[3]-targetBounds[1])/(rawBounds[3]-rawBounds[1]);
    const aspectError=Math.abs(sx/sy-1),scale=(sx+sy)/2,translation=[0,1].map(i=>(targetBounds[i]+targetBounds[i+2])/2-scale*(rawBounds[i]+rawBounds[i+2])/2);
    const hi=canvas(W*3,H*3),ctx=hi.getContext('2d',{willReadFrequently:true});ctx.imageSmoothingQuality='high';ctx.setTransform(scale*3,0,0,scale*3,translation[0]*3,translation[1]*3);ctx.drawImage(im,0,0);const pix=ctx.getImageData(0,0,W*3,H*3).data;
    const silhouette=canvas(W*9,H*9),silhouetteCtx=silhouette.getContext('2d',{willReadFrequently:true});silhouetteCtx.imageSmoothingQuality='high';silhouetteCtx.setTransform(scale*9,0,0,scale*9,translation[0]*9,translation[1]*9);silhouetteCtx.drawImage(im,0,0);const alphaPixels=silhouetteCtx.getImageData(0,0,W*9,H*9).data;
    // Measure visible color, not unpremultiplied RGB hidden in almost-clear pixels.
    const sample=(x,y,alpha=false)=>{const factor=alpha?9:3,data=alpha?alphaPixels:pix;x=Math.round(x*factor);y=Math.round(y*factor);if(x<0||y<0||x>=W*factor||y>=H*factor)return[0,0,0,0];const i=(y*W*factor+x)*4,a=data[i+3];return[data[i]*a/255,data[i+1]*a/255,data[i+2]*a/255,a];};
    const checks=[];for(const e of guide.checkEdges){const [A,B]=e.screen,dx=B[0]-A[0],dy=B[1]-A[1],len=Math.hypot(dx,dy),T=[dx/len,dy/len],N=[-T[1],T[0]],samples=[],profiles=[];
      for(let k=0;k<=40;k++){const along=len*(.18+.64*k/40),p=[A[0]+T[0]*along,A[1]+T[1]*along],scores=[];for(let d=-4;d<=4;d+=.25){const a=sample(p[0]+N[0]*(d-.65),p[1]+N[1]*(d-.65)),b=sample(p[0]+N[0]*(d+.65),p[1]+N[1]*(d+.65));scores.push(e.contrast==='alpha'?Math.abs(a[3]-b[3]):Math.max(...a.map((v,i)=>Math.abs(v-b[i]))));}profiles.push({along,scores});}
      if(e.contrast==='alpha'){
        // A silhouette is measured at its 50% alpha crossing. Wide contrast
        // plateaus can drift along a bevel or a nearby leg despite exact geometry.
        for(const p of profiles){const q=[A[0]+T[0]*p.along,A[1]+T[1]*p.along],hits=[];let previous=sample(q[0]-N[0]*4,q[1]-N[1]*4,true)[3];
          for(let d=-3.875;d<=4;d+=.125){const next=sample(q[0]+N[0]*d,q[1]+N[1]*d,true)[3];if((previous<128&&next>=128)||(previous>=128&&next<128))hits.push(d-.125+.125*(128-previous)/(next-previous));previous=next;}
          hits.sort((a,b)=>Math.abs(a)-Math.abs(b));if(hits.length)samples.push([p.along,hits[0]]);
        }
      }else{
      // Fit a coherent visible ridge across the entire edge. Independent maxima
      // can jump between a gold bevel, a book binding and another board boundary.
      // Search freely through +/-10 degrees; never constrain the fit to <=1 degree.
      let ridge={score:-Infinity,offset:0,drift:0};
      const scoreLine=(offset,drift)=>{let score=0,count=0;for(const p of profiles){const d=offset+drift*(p.along-len/2),i=Math.round((d+4)*4);if(i>=0&&i<33){score+=p.scores[i];count++;}}return count>=profiles.length*.9?score/count*(1-.012*Math.abs(offset)):-Infinity;};
      for(let drift=-.176;drift<=.176;drift+=.004)for(let offset=-4;offset<=4;offset+=.25){const score=scoreLine(offset,drift);if(score>ridge.score)ridge={score,offset,drift};}
      const coarse={...ridge};for(let drift=coarse.drift-.004;drift<=coarse.drift+.004;drift+=.0008)for(let offset=coarse.offset-.25;offset<=coarse.offset+.25;offset+=.05){const score=scoreLine(offset,drift);if(score>ridge.score)ridge={score,offset,drift};}
      for(const p of profiles){const predicted=ridge.offset+ridge.drift*(p.along-len/2);let best={score:-1};for(let i=0;i<33;i++){const d=-4+i*.25;if(Math.abs(d-predicted)<=.5&&p.scores[i]>best.score)best={score:p.scores[i],d};}if(best.score>=12)samples.push([p.along,best.d]);}
      }
      const slopes=[];for(let i=0;i<samples.length;i++)for(let j=i+1;j<samples.length;j++)if(samples[j][0]-samples[i][0]>len*.2)slopes.push((samples[j][1]-samples[i][1])/(samples[j][0]-samples[i][0]));
      const median=a=>{const s=a.toSorted((a,b)=>a-b);return s.length?s[Math.floor(s.length/2)]:Infinity;},drift=median(slopes),intercept=median(samples.map(([x,y])=>y-drift*x)),residual=median(samples.map(([x,y])=>Math.abs(y-intercept-drift*x))),angleError=Math.abs(Math.atan(drift)*180/Math.PI),distance=median(samples.map(p=>Math.abs(p[1])));
      const positionTolerance=e.outer?2:4,boundarySamples=samples.filter(([,d])=>Math.abs(d)>=3.75).length;
      let expectedAngle=Math.atan2(dy,dx)*180/Math.PI;if(expectedAngle>90)expectedAngle-=180;if(expectedAngle<-90)expectedAngle+=180;
      checks.push({label:e.label,family:Math.abs(e.a[0]-e.b[0])>1e-8?'X':'Y',expectedAngle,measuredAngle:expectedAngle+Math.atan(drift)*180/Math.PI,angleError,distance,residual,positionTolerance,samples:samples.length,boundarySamples,passed:samples.length>=20&&boundarySamples<=samples.length*.2&&angleError<=1&&distance<=positionTolerance&&residual<=1});
    }
    const out=canvas(W,H),o=out.getContext('2d');o.imageSmoothingQuality='high';o.drawImage(hi,0,0,W,H);const rgba=o.getImageData(0,0,W,H).data;for(let i=0;i<rgba.length;i+=4)if(rgba[i+3]<4)rgba.fill(0,i,i+4);
    return{rgba:Array.from(rgba),registration:{scale,translation,sourceBounds:rawBounds,targetBounds,aspectError,warp:'none',anchor:'numeric construction guide'},axisChecks:checks,passed:aspectError<=.035&&checks.length>=3&&checks.every(c=>c.passed)};
  },{source,guide,guideImage});
}
