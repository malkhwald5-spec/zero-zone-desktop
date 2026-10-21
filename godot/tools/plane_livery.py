# Repaints the AC-130 texture (extracted from plane.glb) into the game livery:
# national markings and "MARINES" text inpainted away, darker grey-olive,
# "ZERO ZONE" on the sides, orange fin bands. Needs opencv-python-headless.
# Usage: python3 plane_livery.py original.jpg ../assets/models/air/plane_livery.jpg
import cv2, numpy as np, sys
src, out = sys.argv[1], sys.argv[2]
im = cv2.imread(src)
m = np.zeros(im.shape[:2], np.uint8)
def box(x0,y0,x1,y1): cv2.rectangle(m,(x0,y0),(x1,y1),255,-1)
def circ(x,y,r): cv2.circle(m,(x,y),r,255,-1)
# top strip
circ(78,500,24); box(28,483,128,517); box(598,480,692,517); box(160,485,205,515); box(630,480,680,515); box(685,488,780,515)
# under strip
circ(165,613,26); box(130,605,205,622); box(605,612,690,638)
# fins
box(490,288,540,355); box(633,288,680,355)
# side 1
box(460,722,630,748); box(280,762,425,815); circ(338,788,30); box(830,742,905,782)
# side 2
box(385,888,560,912); box(105,912,160,948); box(612,935,740,990); circ(675,960,30)
m = cv2.dilate(m, np.ones((5,5),np.uint8))
im = cv2.inpaint(im, m, 9, cv2.INPAINT_TELEA)
# Darker two-tone military grey-olive, more contrast, a little grime.
f = im.astype(np.float32) / 255.0
lum = f.mean(axis=2, keepdims=True)
green = np.clip((f[:,:,1:2] - f[:,:,2:3]) * 8.0, 0, 1)      # the greenish lower panels
top = np.array([0.50, 0.54, 0.52]); low = np.array([0.36, 0.40, 0.38])   # BGR
tint = top * (1 - green) + low * green
g = np.clip((lum - 0.5) * 1.25 + 0.5, 0, 1)
res = g * tint + (f - lum) * 0.3
rng = np.random.default_rng(3)
n = cv2.GaussianBlur(rng.random(im.shape[:2]).astype(np.float32), (0, 0), 6)
n = (n - n.mean()) / (n.std() + 1e-6)
res *= (1.0 + n[..., None] * 0.035)
# keep the wheel / special tiles (top right corner) as they were
res[0:390, 770:1024] = f[0:390, 770:1024]
im = np.clip(res * 255, 0, 255).astype(np.uint8)
def stencil(text, x, y, scale, col, flip):
    t = np.zeros((80, 900, 3), np.uint8)
    cv2.putText(t, text, (5, 60), cv2.FONT_HERSHEY_DUPLEX, scale, (255,255,255), 3, cv2.LINE_AA)
    ys, xs = np.where(t[:,:,0] > 0)
    t = t[ys.min():ys.max()+1, xs.min():xs.max()+1]
    if flip: t = cv2.flip(t, 0)
    h, w = t.shape[:2]
    a = (t[:,:,0:1] / 255.0) * 0.85
    reg = im[y:y+h, x:x+w].astype(np.float32)
    im[y:y+h, x:x+w] = (reg * (1 - a) + np.array(col) * a).astype(np.uint8)
stencil("ZERO ZONE", 470, 724, 1.0, (205, 212, 210), True)
stencil("ZERO ZONE", 392, 890, 1.0, (205, 212, 210), True)
# orange band on the fins
for x0 in (480, 625):
    cv2.rectangle(im, (x0, 318), (x0 + 60, 326), (40, 140, 245), -1)
cv2.imwrite(out, im, [cv2.IMWRITE_JPEG_QUALITY, 92])
