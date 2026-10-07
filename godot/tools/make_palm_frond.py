"""Draws the palm frond leaf card (a feather-shaped palm leaf on transparent).

    python3 tools/make_palm_frond.py <out png>

The leaf runs along the width: stem end at the left (u = 0), tip at the right,
like the pine branch card.
"""
import math
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

W, H = 1024, 256
rng = random.Random(4)
img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
mid = H // 2
# Leaflets on both sides of the midrib, longest in the middle, drooping.
n = 46
for i in range(n):
    t = i / (n - 1)
    x0 = 40 + t * (W - 80)
    length = math.sin(min(1.0, t * 1.15) * math.pi) * 110 + 16
    for side in (-1, 1):
        ang = side * (0.95 - 0.35 * t) + rng.uniform(-0.08, 0.08)
        x1 = x0 + math.cos(abs(ang)) * length * 0.55
        y1 = mid + math.sin(ang) * length
        g = rng.randint(95, 140)
        col = (int(g * 0.42), g, int(g * 0.28), 255)
        # A leaflet: a thin tapered polygon.
        wdt = 5.5 * (1.0 - t * 0.5)
        nx, ny = -(y1 - mid), (x1 - x0)
        ln = math.hypot(nx, ny) or 1.0
        nx, ny = nx / ln * wdt, ny / ln * wdt
        d.polygon([(x0, mid), (x0 + nx, mid + ny), (x1, y1), (x0 - nx * 0.3, mid - ny * 0.3)], fill=col)
# Midrib.
d.line([(0, mid), (W - 30, mid)], fill=(120, 110, 60, 255), width=6)
img = img.filter(ImageFilter.GaussianBlur(0.6))
img.save(sys.argv[1])
print("ok")
