"""The coast of وادي الرمال (Dune Valley): land / sea as a 1024 px map of
signed distance to the shore, the same coding as seasons_land.png
(grey 128 = the shoreline, +1 grey = 2 m inland, -1 = 2 m out to sea).
The outline is drawn in the layout's 1000-px frame (see Island.DUNES) and
roughened so the shore is not a row of straight lines.
Usage: python3 tools/make_dunes_coast.py godot/assets/map/dunes_land.png"""
import sys
import numpy as np
from PIL import Image, ImageDraw
from scipy.ndimage import distance_transform_edt, gaussian_filter

W = 1024
MAP_M = 4096.0
OUTLINE = [(95, 120), (210, 85), (330, 70), (470, 95), (600, 70), (730, 60), (850, 95), (905, 170), (895, 300),
	(870, 400), (900, 470), (905, 580), (860, 660), (885, 760), (860, 860), (780, 915), (640, 935), (500, 950),
	(360, 940), (230, 915), (120, 870), (70, 760), (85, 640), (60, 520), (80, 400), (60, 280)]

def main():
	out = sys.argv[1]
	k = W / 1000.0
	img = Image.new("L", (W, W), 0)
	ImageDraw.Draw(img).polygon([(x * k, y * k) for x, y in OUTLINE], fill=255)
	land = np.array(img) > 127
	# Roughen the shore: wobble the land edge with smoothed noise.
	rng = np.random.default_rng(4)
	n = gaussian_filter(rng.standard_normal((W, W)), 14) * 60.0
	inside = distance_transform_edt(land) - distance_transform_edt(~land) + n
	land = inside > 0
	# The lighthouse islet off the north-east coast, and a sandbar to the south-west.
	yy, xx = np.mgrid[0:W, 0:W]
	for cx, cy, r in [(955, 135, 16), (70, 965, 12)]:
		land |= (xx - cx * k) ** 2 + (yy - cy * k) ** 2 < (r * k) ** 2
	m_per_px = MAP_M / W
	d = (distance_transform_edt(land) - distance_transform_edt(~land)) * m_per_px
	g = np.clip(128.0 + d / 2.0, 0, 255).astype(np.uint8)
	Image.fromarray(g, "L").save(out)
	print("saved", out, "land %.0f%%" % (land.mean() * 100))

if __name__ == "__main__":
	main()
