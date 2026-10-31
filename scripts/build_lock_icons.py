"""Render two language-independent padlock icons for native UMG Image widgets."""
from pathlib import Path
from PIL import Image, ImageDraw

out=Path(__file__).resolve().parents[1]/'mods/FrostrailQuickstash/icons'
out.mkdir(parents=True,exist_ok=True)
scale=4
for state in ('locked','unlocked'):
    im=Image.new('RGBA',(32*scale,32*scale))
    draw=ImageDraw.Draw(im)
    def box(values): return tuple(int(x*scale) for x in values)
    white=(255,255,255,255)
    draw.rounded_rectangle(box((6,14,26,30)),radius=3*scale,outline=white,width=2*scale)
    if state=='locked':
        draw.arc(box((10,3,22,17)),180,360,fill=white,width=2*scale)
        draw.line([box((10,10)),box((10,15))],fill=white,width=2*scale)
        draw.line([box((22,10)),box((22,15))],fill=white,width=2*scale)
    else:
        draw.arc(box((16,2,28,16)),180,360,fill=white,width=2*scale)
        draw.line([box((16,9)),box((16,15))],fill=white,width=2*scale)
        draw.line([box((28,9)),box((28,11))],fill=white,width=2*scale)
    draw.ellipse(box((14,19,18,23)),fill=white)
    draw.line([box((16,22)),box((16,26))],fill=white,width=2*scale)
    im.resize((64,64),Image.Resampling.LANCZOS).save(out/(state+'.png'))
    print(out/(state+'.png'))
