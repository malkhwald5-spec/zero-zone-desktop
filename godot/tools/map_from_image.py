# Coast of the authored island from a painted map (as on "جزيرة الفصول"):
#   python3 tools/map_from_image.py ../map/seasons_reference.jpg assets/map/seasons_land.png
# Water is the blue-green paint; lakes and rivers inside the island count as
# land (the game carves them itself). Writes a 1024x1024 signed distance to
# the coast: 128 = shore, +1 per 2 m inland, -1 per 2 m out to sea.
import sys
import numpy as np
from PIL import Image
from scipy import ndimage

src, dst = sys.argv[1], sys.argv[2]
N = 1024
im = np.asarray(Image.open(src).convert("RGB").resize((N, N), Image.BILINEAR)).astype(np.int32)
r, g, b = im[..., 0], im[..., 1], im[..., 2]
water = (b >= r + 25) & (b >= g - 12)
water = ndimage.binary_closing(water, iterations=2)
land = ~water
# Thin things on the sea (labels, the scale bar) are not land.
land = ndimage.binary_opening(land, iterations=3)
lab, n = ndimage.label(land)
sizes = ndimage.sum(land, lab, range(1, n + 1))
keep = np.zeros(n + 1, bool)
keep[1:] = sizes > 600
land = keep[lab]
# Lakes and rivers: water not reaching the edge of the picture is filled in.
sea_lab, m = ndimage.label(~land)
edge = set(np.unique(np.concatenate([sea_lab[0], sea_lab[-1], sea_lab[:, 0], sea_lab[:, -1]])))
inland = ~land & ~np.isin(sea_lab, list(edge))
land = land | inland
# The lake and the river that runs from it to the sea are carved by the game:
# here they are land (positions as in scripts/island.gd, picture pixels of 1932).
from PIL import ImageDraw
k = N / 1932.0
fill = Image.fromarray((land * 255).astype(np.uint8))
d = ImageDraw.Draw(fill)
d.ellipse([825 * k, 950 * k, 1105 * k, 1125 * k], fill=255)
river = [(1060, 1060), (1100, 1080), (1150, 1105), (1200, 1160), (1250, 1230), (1278, 1300), (1288, 1400),
	(1292, 1500), (1310, 1580), (1338, 1650), (1362, 1715), (1372, 1735)]
d.line([(x * k, y * k) for x, y in river], fill=255, width=int(48 * k))
land = np.asarray(fill) > 127
land = ndimage.binary_closing(land, iterations=2)
metres = 8192.0 / N
inside = ndimage.distance_transform_edt(land) * metres
outside = ndimage.distance_transform_edt(~land) * metres
sdf = np.where(land, inside, -outside)
out = np.clip(128 + sdf / 2.0, 0, 255).astype(np.uint8)
out = ndimage.gaussian_filter(out.astype(np.float32), 1.0).round().clip(0, 255).astype(np.uint8)
Image.fromarray(out, "L").save(dst)
print("land share", land.mean(), "components kept", int(keep.sum()))
