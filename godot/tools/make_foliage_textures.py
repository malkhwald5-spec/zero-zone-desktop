"""Builds the foliage card textures from ambientCG photo scans (CC0).

    python3 tools/make_foliage_textures.py <dir with LeafSet001, LeafSet024, Foliage001> <out dir>

Writes:
  leaf_cluster.png  - a twig covered in real photographed leaves (tree crowns)
  pine_branch.png   - a drooping fir branch drawn needle by needle
  grass_tuft.png    - a tuft of real grass blades, some dry
"""
import math
import random
import sys

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

SRC, OUT = sys.argv[1], sys.argv[2]


def load_set(name):
    col = Image.open(f"{SRC}/{name}/{name}_1K-JPG_Color.jpg").convert("RGB")
    op = Image.open(f"{SRC}/{name}/{name}_1K-JPG_Opacity.jpg").convert("L")
    im = col.copy()
    im.putalpha(op)
    return im


def sprites_grid(im, cols, rows):
    """Cuts a sheet laid out as a grid into tightly cropped sprites."""
    out = []
    w, h = im.size
    for r in range(rows):
        for c in range(cols):
            cell = im.crop((c * w // cols, r * h // rows, (c + 1) * w // cols, (r + 1) * h // rows))
            box = cell.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox()
            if box:
                out.append(cell.crop(box))
    return out


def sprites_columns(im):
    """Cuts vertical strips (grass blades) apart using empty columns."""
    a = im.getchannel("A").point(lambda v: 255 if v > 40 else 0)
    w, h = im.size
    filled = [a.crop((x, 0, x + 1, h)).getbbox() is not None for x in range(w)]
    out, start = [], None
    for x in range(w + 1):
        f = x < w and filled[x]
        if f and start is None:
            start = x
        elif not f and start is not None:
            if x - start > 6:
                strip = im.crop((start, 0, x, h))
                out.append(strip.crop(strip.getchannel("A").getbbox()))
            start = None
    return out


def tint(sprite, bright, warm):
    rgb = sprite.convert("RGB")
    rgb = ImageEnhance.Brightness(rgb).enhance(bright)
    r, g, b = rgb.split()
    r = r.point(lambda v: min(255, int(v * (1.0 + warm))))
    b = b.point(lambda v: int(v * (1.0 - warm * 0.6)))
    out = Image.merge("RGB", (r, g, b))
    out.putalpha(sprite.getchannel("A"))
    return out


def paste_rot(canvas, sprite, centre, length, angle_deg):
    s = length / sprite.size[1]
    sp = sprite.resize((max(2, int(sprite.size[0] * s)), max(2, int(sprite.size[1] * s))), Image.LANCZOS)
    sp = sp.rotate(angle_deg, resample=Image.BICUBIC, expand=True)
    canvas.alpha_composite(sp, (int(centre[0] - sp.size[0] / 2), int(centre[1] - sp.size[1] / 2)))


def leaf_cluster(rng):
    leaves = sprites_grid(load_set("LeafSet001"), 3, 2) + sprites_grid(load_set("LeafSet024"), 3, 3)
    S = 1024
    cv = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(cv)
    # Twigs fanning out from the bottom centre.
    twigs = []
    for k in range(9):
        a = math.radians(-90 + rng.uniform(-42, 42))
        x0, y0 = S * 0.5 + rng.uniform(-40, 40), S * 0.97
        L = rng.uniform(0.5, 0.8) * S
        pts = []
        for i in range(12):
            t = i / 11
            bend = math.sin(t * 2.0) * rng.uniform(-0.15, 0.15)
            pts.append((x0 + math.cos(a + bend) * L * t, y0 + math.sin(a + bend) * L * t))
        twigs.append((pts, a))
        d.line(pts, fill=(78, 62, 44, 255), width=7)
    # Leaves along each twig, back layer darker so the clump reads as 3D.
    for layer, (bright_lo, bright_hi) in enumerate([(0.45, 0.65), (0.7, 0.95), (0.9, 1.2)]):
        for pts, a in twigs:
            for i in range(3, len(pts)):
                for side in (-1, 1):
                    if rng.random() < 0.25:
                        continue
                    p = pts[i]
                    ang = math.degrees(a) + side * rng.uniform(25, 70)
                    size = rng.uniform(80, 125) * (1.0 - i / 30)
                    off = (math.cos(math.radians(ang)) * size * 0.45, math.sin(math.radians(ang)) * size * 0.45)
                    lf = tint(rng.choice(leaves), rng.uniform(bright_lo, bright_hi), rng.uniform(-0.05, 0.12))
                    # Sprite points up; rotate so it points along `ang`.
                    paste_rot(cv, lf, (p[0] + off[0], p[1] + off[1]), size, -ang - 90 + rng.uniform(-15, 15))
    return cv


def pine_branch(rng):
    W, H = 1024, 512
    cv = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(cv)

    def needles_along(pts, density, length, width, light=0):
        for i in range(len(pts) - 1):
            (x0, y0), (x1, y1) = pts[i], pts[i + 1]
            seg = math.hypot(x1 - x0, y1 - y0)
            ang = math.atan2(y1 - y0, x1 - x0)
            for _ in range(int(seg * density)):
                t = rng.random()
                x, y = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
                side = rng.choice((-1, 1))
                na = ang + side * rng.uniform(0.6, 1.1)
                ln = length * rng.uniform(0.7, 1.15)
                g = rng.randint(48, 100) + light
                col = (int(g * rng.uniform(0.45, 0.6)), g, int(g * rng.uniform(0.45, 0.62)), 255)
                d.line((x, y, x + math.cos(na) * ln, y + math.sin(na) * ln), fill=col, width=width)

    # Main stem from the trunk side (left) to the tip (right), drooping.
    stem = [(8 + i * (W - 40) / 20, H * 0.42 + (i / 20) ** 2 * H * 0.22) for i in range(21)]
    subs = []
    for k in range(2, 19, 2):
        bx, by = stem[k]
        for side in (-1, 1):
            L = (W * 0.32) * (1.0 - k / 26) * rng.uniform(0.7, 1.05)
            a = side * rng.uniform(0.45, 0.8) + 0.12
            subs.append([(bx + math.cos(a) * L * t, by + math.sin(a) * L * t + t * t * 18) for t in [i / 6 for i in range(7)]])
    for s in subs:
        d.line(s, fill=(70, 52, 36, 255), width=4)
    d.line(stem, fill=(80, 58, 38, 255), width=9)
    # Two passes: darker needles behind, fresher lighter ones on top.
    needles_along(stem, 1.6, 40, 4)
    for s in subs:
        needles_along(s, 2.2, 30, 3)
    for s in subs:
        needles_along(s[3:], 1.2, 22, 3)
    # Fresh light-green growth near the tips.
    for s in subs:
        needles_along(s[5:], 0.6, 18, 2, 45)
    return cv


def grass_tuft(rng):
    blades = sprites_columns(load_set("Foliage001"))
    # Drop the curly one: it reads as a worm at game scale.
    blades = [b for b in blades if b.size[0] < b.size[1] * 0.08]
    W, H = 1024, 512
    cv = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for i in range(70):
        bl = rng.choice(blades)
        dry = rng.random() < 0.18
        bl = tint(bl, rng.uniform(0.75, 1.25) if not dry else 1.3, 0.35 if dry else rng.uniform(-0.05, 0.1))
        length = rng.uniform(0.55, 1.0) * H
        s = length / bl.size[1]
        sp = bl.resize((max(3, int(bl.size[0] * s * 1.3)), int(length)), Image.LANCZOS)
        ang = rng.uniform(-28, 28)
        sp = sp.rotate(ang, resample=Image.BICUBIC, expand=True)
        bx = W * 0.5 + rng.uniform(-0.32, 0.32) * W
        # Bottom of the blade stays on the ground line.
        x = int(bx - sp.size[0] / 2 - math.sin(math.radians(ang)) * length * 0.5)
        y = H - sp.size[1]
        cv.alpha_composite(sp, (max(0, min(W - sp.size[0], x)), max(0, y)))
    # Darken the base (self-shadowing inside the tuft).
    shade = Image.linear_gradient("L").resize((W, H))
    rgb = cv.convert("RGB")
    dark = ImageEnhance.Brightness(rgb).enhance(0.45)
    rgb = Image.composite(dark, rgb, shade.point(lambda v: int(max(0, v - 120) * 1.9)))
    rgb.putalpha(cv.getchannel("A"))
    return rgb


def bleed(im):
    """Fills transparent pixels with nearby colour so mipmaps do not get dark fringes."""
    a = im.getchannel("A")
    rgb = im.convert("RGB")
    blur = rgb.filter(ImageFilter.BoxBlur(12))
    out = Image.composite(rgb, blur, a.point(lambda v: 255 if v > 8 else 0))
    out.putalpha(a)
    return out


rng = random.Random(7)
bleed(leaf_cluster(rng)).save(f"{OUT}/leaf_cluster.png")
bleed(pine_branch(rng)).save(f"{OUT}/pine_branch.png")
bleed(grass_tuft(rng)).save(f"{OUT}/grass_tuft.png")
print("ok")
