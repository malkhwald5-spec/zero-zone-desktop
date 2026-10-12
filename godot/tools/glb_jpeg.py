# Re-encodes the images inside a .glb: opaque ones as JPEG (quality 85),
# ones with real transparency stay PNG. usage: glb_jpeg.py in.glb out.glb
import sys, json, struct, io
from PIL import Image
src, dst = sys.argv[1], sys.argv[2]
d = open(src, 'rb').read()
jl = struct.unpack('<I', d[12:16])[0]
g = json.loads(d[20:20 + jl])
bin0 = 20 + jl + 8
blob = d[bin0:bin0 + struct.unpack('<I', d[20 + jl:24 + jl])[0]]
views = g['bufferViews']
img_views = {im['bufferView']: i for i, im in enumerate(g.get('images', [])) if 'bufferView' in im}
out = bytearray()
for vi, v in enumerate(views):
    data = blob[v.get('byteOffset', 0):v.get('byteOffset', 0) + v['byteLength']]
    if vi in img_views:
        im = Image.open(io.BytesIO(data))
        alpha = im.mode in ('RGBA', 'LA', 'P') and im.convert('RGBA').getextrema()[3][0] < 250
        bio = io.BytesIO()
        if alpha:
            im.convert('RGBA').save(bio, 'PNG', optimize=True)
            g['images'][img_views[vi]]['mimeType'] = 'image/png'
        else:
            im.convert('RGB').save(bio, 'JPEG', quality=85)
            g['images'][img_views[vi]]['mimeType'] = 'image/jpeg'
        data = bio.getvalue()
    while len(out) % 4: out.append(0)
    v['byteOffset'] = len(out)
    v['byteLength'] = len(data)
    out.extend(data)
while len(out) % 4: out.append(0)
g['buffers'][0]['byteLength'] = len(out)
js = json.dumps(g).encode()
while len(js) % 4: js += b' '
with open(dst, 'wb') as f:
    f.write(struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(out)))
    f.write(struct.pack('<II', len(js), 0x4E4F534A)); f.write(js)
    f.write(struct.pack('<II', len(out), 0x004E4942)); f.write(out)
print(dst, len(d), '->', 12 + 16 + len(js) + len(out))
