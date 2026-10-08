"""Numeric template PNG creation only. Does not read or edit generated artwork."""
import json
from pathlib import Path
from PIL import Image, ImageDraw
import sys

root = Path(__file__).parent
input_file = Path(sys.argv[1]) if len(sys.argv)>1 else root.parents[1] / '.tooling/room-cat-idle-v2-guides.json'
data = json.loads(input_file.read_text())

def hull(points):
    points=sorted(set(tuple(p) for p in points))
    def cross(o,a,b): return (a[0]-o[0])*(b[1]-o[1])-(a[1]-o[1])*(b[0]-o[0])
    result=[]
    for sequence in [points,list(reversed(points))]:
        half=[]
        for p in sequence:
            while len(half)>1 and cross(half[-2],half[-1],p)<=0: half.pop()
            half.append(p)
        result.extend(half[:-1])
    return result

for pose in data['poses']:
    image=Image.new('RGBA',tuple(pose['canvas']),(255,255,255,255))
    draw=ImageDraw.Draw(image)
    for part in pose['bodyParts']+pose['tailParts']:
        pts=hull(part['points']) if len(part['points'])>3 else [tuple(p) for p in part['points']]
        draw.polygon(pts,fill=part['tint']);draw.line(pts+[pts[0]],fill='#748794',width=2)
    for x,y in pose['contacts']: draw.ellipse((x-4,y-4,x+4,y+4),fill='#297c68')
    for x,y in [pose['tailRootPixel'],pose['tailRootTilePixel']]:
        draw.line((x-5,y,x+5,y),fill='#b86060',width=2);draw.line((x,y-5,x,y+5),fill='#b86060',width=2)
    draw.line((1024,0,1024,1024),fill='#dadfe3',width=1)
    image.save(root / pose.get('guideFile', f"{pose['pose']}-idle-v2-guide.png"))
