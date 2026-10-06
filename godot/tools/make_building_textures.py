"""Builds tileable textures for warehouses, containers and barns from
ambientCG photo scans (CC0).

    python3 tools/make_building_textures.py <dir with Metal032, Wood049> <out dir>

Writes:
  corrugated_col.jpg / corrugated_nrm.jpg - ribbed sheet metal with rust runs
  planks_col.jpg / planks_nrm.jpg         - vertical weathered barn boards
"""
import math
import random
import sys

from PIL import Image, ImageChops, ImageEnhance, ImageFilter

SRC, OUT = sys.argv[1], sys.argv[2]
S = 512
rng = random.Random(3)


def load(name, kind):
    return Image.open(f"{SRC}/{name}/{name}_1K-JPG_{kind}.jpg").convert("RGB").resize((S, S), Image.LANCZOS)


def normal_from_profile(profile, strength):
    """Normal map (OpenGL) for a surface whose height only varies along x."""
    img = Image.new("RGB", (S, S))
    px = img.load()
    for x in range(S):
        d = (profile[(x + 1) % S] - profile[(x - 1) % S]) * 0.5 * strength
        n = (-d, 0.0, 1.0)
        l = math.sqrt(n[0] ** 2 + 1.0)
        c = (int((n[0] / l * 0.5 + 0.5) * 255), 128, int((1.0 / l * 0.5 + 0.5) * 255))
        for y in range(S):
            px[x, y] = c
    return img


def corrugated():
    period = 32
    prof = [math.sin(x / period * math.tau) for x in range(S)]
    base = load("Metal032", "Color")
    base = ImageEnhance.Color(base).enhance(0.4)
    shade = Image.new("L", (S, S))
    sp = shade.load()
    for x in range(S):
        v = int(200 + 45 * math.cos(x / period * math.tau - 0.8))
        for y in range(S):
            sp[x, y] = v
    col = ImageChops.multiply(base, Image.merge("RGB", (shade, shade, shade)))
    # Rust and dirt running down from the top of the sheets.
    rust = Image.new("RGB", (S, S), (120, 70, 40))
    mask = Image.new("L", (S, S), 0)
    mp = mask.load()
    for _ in range(26):
        x0 = rng.randrange(S)
        w = rng.randint(3, 14)
        length = rng.randint(60, 380)
        a = rng.uniform(0.25, 0.6)
        for x in range(x0, x0 + w):
            for y in range(length):
                fade = 1.0 - y / length
                v = int(255 * a * fade * (0.6 + 0.4 * rng.random()))
                xx = x % S
                mp[xx, y] = max(mp[xx, y], v)
    mask = mask.filter(ImageFilter.GaussianBlur(2))
    col = Image.composite(rust, col, mask)
    col.save(f"{OUT}/corrugated_col.jpg", quality=90)
    normal_from_profile([p * period / math.tau for p in prof], 0.4).save(f"{OUT}/corrugated_nrm.jpg", quality=92)


def planks():
    wood = load("Wood049", "Color").rotate(90)
    board = 64
    col = Image.new("RGB", (S, S))
    for i in range(S // board):
        # Each board is a different strip of the grain, a bit lighter or darker.
        off = rng.randrange(S - board)
        strip = wood.crop((off, 0, off + board, S))
        strip = ImageEnhance.Brightness(strip).enhance(rng.uniform(0.75, 1.15))
        strip = ImageChops.offset(strip, 0, rng.randrange(S))
        col.paste(strip, (i * board, 0))
    prof = []
    for x in range(S):
        u = x % board
        prof.append(-6.0 if u < 3 or u > board - 3 else 0.0)
    shade = Image.new("L", (S, S))
    sp = shade.load()
    for x in range(S):
        u = x % board
        v = 90 if u < 3 or u > board - 3 else 255
        for y in range(S):
            sp[x, y] = v
    col = ImageChops.multiply(col, Image.merge("RGB", (shade, shade, shade)))
    col.save(f"{OUT}/planks_col.jpg", quality=90)
    normal_from_profile(prof, 0.6).filter(ImageFilter.GaussianBlur(1)).save(f"{OUT}/planks_nrm.jpg", quality=92)


corrugated()
planks()
print("ok")
