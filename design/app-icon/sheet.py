# Build sheet.png: drafts + final at 512 (squircle-masked), final at 128/64/32/16 on light and dark.
# usage: python3 sheet.py <dir>   (expects drafts/draft-{A,B,C}.png and final/awake-final.png)
import sys, os
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter

D = sys.argv[1]

def squircle_mask(size=1024, box=824, n=5.0, ss=4):
    S = size * ss
    c = (S - 1) / 2
    a = box * ss / 2
    y, x = np.mgrid[0:S, 0:S]
    v = (np.abs((x - c) / a) ** n + np.abs((y - c) / a) ** n) <= 1.0
    m = Image.fromarray((v * 255).astype(np.uint8))
    return m.resize((size, size), Image.LANCZOS)

MASK = squircle_mask()

def icon(path):
    """1024 render -> RGBA icon: art masked to the 824 squircle, with a soft drop shadow like the macOS grid."""
    art = Image.open(path).convert("RGBA")
    out = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    sh = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
    sh.putalpha(MASK.point(lambda p: p * 0.35))
    sh = sh.transform(sh.size, Image.AFFINE, (1, 0, 0, 0, 1, -10)).filter(ImageFilter.GaussianBlur(14))
    out.alpha_composite(sh)
    a = art.copy()
    a.putalpha(Image.fromarray(np.minimum(np.array(art.getchannel("A")), np.array(MASK))))
    out.alpha_composite(a)
    return out

def font(sz):
    for f in ("/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/Helvetica.ttc"):
        if os.path.exists(f):
            return ImageFont.truetype(f, sz)
    return ImageFont.load_default()

items = [("Draft C  close crop", "drafts/draft-C.png"), ("Final C  cone as hero", "final/awake-final-C.png")]
items = [(l, os.path.join(D, p)) for l, p in items if os.path.exists(os.path.join(D, p))]
W = 40 + len(items) * 552
H = 40 + 40 + 512 + 60 + 2 * 180 + 40
sheet = Image.new("RGB", (W, H), (236, 236, 238))
dr = ImageDraw.Draw(sheet)
f = font(24)
for i, (label, p) in enumerate(items):
    x = 40 + i * 552
    dr.text((x, 40), label, fill=(30, 30, 34), font=f)
    ic = icon(p).resize((512, 512), Image.LANCZOS)
    sheet.paste(ic, (x, 80), ic)

final = [p for l, p in items if l.startswith("Final")]
if final:
    big = icon(final[0])
    y0 = 80 + 512 + 60
    for row, bgc in enumerate([(236, 236, 238), (30, 30, 34)]):
        y = y0 + row * 180
        dr.rectangle([0, y - 20, W, y + 160], fill=bgc)
        dr.text((40, y + 50), "light" if row == 0 else "dark", fill=(120, 120, 128), font=f)
        x = 160
        for s in (128, 64, 32, 16):
            ic = big.resize((s, s), Image.LANCZOS)
            sheet.paste(ic, (x, y + (128 - s) // 2), ic)
            dr.text((x, y + 134), f"{s}", fill=(120, 120, 128), font=font(16))
            x += s + 60
sheet.save(os.path.join(D, "sheet.png"))
for l, p in items:
    icon(p).save(p.replace(".png", "-masked.png"))
print("wrote", os.path.join(D, "sheet.png"))
