# Repaints the "Street Rider Helmet" texture (Sketchfab, sevai, CC-BY) as a
# plain matte shell: brand marks, number, slogan and stickers removed.
# Usage: python3 helmet_clean.py Material.006_baseColor.png out.png (needs opencv-python-headless)
import cv2, numpy as np, sys
# Turns the photo-scanned street helmet into a plain matte shell: no brand
# marks, numbers, slogans or stickers; the inside padding is left as it is.
src, out = sys.argv[1], sys.argv[2]
im = cv2.imread(src, cv2.IMREAD_UNCHANGED)
alpha = im[:, :, 3] if im.shape[2] == 4 else None
rgb = im[:, :, :3].astype(np.float32)
h, w = rgb.shape[:2]
k = h / 768.0
# The outer shell pieces of the sheet: the big piece top left and the strip under it.
region = np.zeros((h, w), np.uint8)
cv2.rectangle(region, (0, 0), (int(392 * k), int(500 * k)), 255, -1)
cv2.rectangle(region, (0, int(480 * k)), (int(310 * k), int(615 * k)), 255, -1)
lit = (rgb.max(axis=2) > 14).astype(np.uint8) * 255
shell = cv2.bitwise_and(region, lit)
# Shading only (light and shadow of the scan), blurred so no letters survive.
luma = cv2.cvtColor(rgb.astype(np.uint8), cv2.COLOR_BGR2GRAY).astype(np.float32) / 255.0
soft = cv2.GaussianBlur(luma, (0, 0), 10 * k)
shade = np.clip(0.55 + (soft - soft[shell > 0].mean()) * 1.4, 0.3, 1.25)
base = np.array([58, 55, 52], np.float32)            # matte black (BGR)
paint = base[None, None, :] * shade[..., None]
sel = (cv2.GaussianBlur(shell, (0, 0), 1.5) / 255.0)[..., None]
res = rgb * (1 - sel) + paint * sel
out_im = np.clip(res, 0, 255).astype(np.uint8)
if alpha is not None: out_im = np.dstack([out_im, alpha])
cv2.imwrite(out, out_im)
