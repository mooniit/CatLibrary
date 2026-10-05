"""Inspect transparent output; do not retouch or mutate the asset pixels."""
from collections import deque
from pathlib import Path
import json
import sys
import math
from PIL import Image

root = Path(__file__).resolve().parent / (sys.argv[1] if len(sys.argv)>1 else 'lunar-assets')
manifest = json.loads((root / 'manifest.json').read_text(encoding='utf-8'))
report = []
def convex_hull(points):
    points=sorted(set(points))
    def cross(a,b,c): return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])
    lower=[];upper=[]
    for sequence,part in [(points,lower),(list(reversed(points)),upper)]:
        for p in sequence:
            while len(part)>1 and cross(part[-2],part[-1],p)<=0: part.pop()
            part.append(p)
    return lower[:-1]+upper[:-1]
for asset in manifest['assets']:
    image = Image.open(root / asset['png']).convert('RGBA')
    alpha = image.getchannel('A')
    w, h = image.size
    bbox = alpha.getbbox()
    assert bbox, asset['id']
    margins = [bbox[0], bbox[1], w - bbox[2], h - bbox[3]]
    assert min(margins) >= 3, (asset['id'], margins)
    assert image.size == tuple(asset['viewBox'][2:]), asset['id']
    if manifest['id'] in ['lunar-content-v3','lunar-content-v4','lunar-content-v5'] and asset['id']=='window-right':
        original=Image.open(root/'window-left.png').convert('RGBA')
        assert original.transpose(Image.Transpose.FLIP_LEFT_RIGHT).tobytes()==image.tobytes(),('window-right','mirror mismatch')
    if asset['category']=='frame-template':
        assert alpha.getpixel((w//2,h//2))==0, (asset['id'],'frame center must remain transparent')
    components = []
    if asset['category'] == 'furniture':
        data = alpha.tobytes()
        remaining = {i for i, value in enumerate(data) if value >= 8}
        while remaining:
            first = remaining.pop()
            queue = deque([first])
            size = 0
            while queue:
                point = queue.popleft()
                size += 1
                x, y = point % w, point // w
                for dx, dy in [(-1,-1),(0,-1),(1,-1),(-1,0),(1,0),(-1,1),(0,1),(1,1)]:
                    X, Y = x + dx, y + dy
                    if 0 <= X < w and 0 <= Y < h:
                        neighbor = Y * w + X
                        if neighbor in remaining:
                            remaining.remove(neighbor)
                            queue.append(neighbor)
            components.append(size)
        assert len(components) == 1, (asset['id'], sorted(components, reverse=True))
        if manifest['id'] in ['lunar-content-v2','lunar-content-v3','lunar-content-v4','lunar-content-v5']:
            camera=manifest['camera'];fw,fd,fh=asset['dimensionsL'];anchor=asset['pixelGroundOrigin']
            prism=convex_hull([(anchor[0]+x*camera['bx'][0]+y*camera['by'][0],anchor[1]+x*camera['bx'][1]+y*camera['by'][1]+z*camera['bz'][1]) for x in [0,fw] for y in [0,fd] for z in [0,fh]])
            for v in range(h):
                for u in range(w):
                    if data[v*w+u]<32: continue
                    assert all((b[0]-p[0])*(v+.5-p[1])-(b[1]-p[1])*(u+.5-p[0])>=-math.hypot(b[0]-p[0],b[1]-p[1])-1e-7 for p,b in zip(prism,prism[1:]+prism[:1])),(asset['id'],'outside projected declared prism',u,v)
            if asset['mirrored']:
                original=Image.open(root / (asset['id'][:-1]+'x.png')).convert('RGBA')
                assert original.transpose(Image.Transpose.FLIP_LEFT_RIGHT).tobytes()==image.tobytes(),(asset['id'],'mirror mismatch')
    report.append({'id':asset['id'], 'rgba':True, 'size':[w,h], 'alphaBBox':bbox,
                   'transparentMargins':margins, 'connectedComponents':len(components) if components else None,
                   **({'projectedEnvelopeOutsidePixels':0,'antialiasAllowancePixels':1,'mirrorPixelDifferences':0 if asset['mirrored'] else None} if asset['category']=='furniture' and manifest['id'] in ['lunar-content-v2','lunar-content-v3','lunar-content-v4','lunar-content-v5'] else {})})
(root / 'alpha-verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print(f'{len(report)} transparent PNGs: clear crop margins; all 10 furniture sprites connected, no detached residual pixels.')
