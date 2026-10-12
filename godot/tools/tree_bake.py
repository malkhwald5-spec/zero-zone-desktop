# Cut one tree out of a Sketchfab pack into a small GLB: base at the origin,
# scaled to HEIGHT m, primitives merged per material, leaves alpha-tested,
# textures embedded and shrunk. usage: tree_bake.py src.gltf out.glb height regex [maxtex]
import sys,json,struct,re,io,numpy as np
sys.path.insert(0,sys.argv[5] if len(sys.argv)>5 else '.')
from gltfinfo import *
from PIL import Image
src,out,H,rx=sys.argv[1],sys.argv[2],float(sys.argv[3]),re.compile(sys.argv[4]); MAXT=int(sys.argv[6]) if len(sys.argv)>6 else 512
g,b=load(src); d=src.rsplit('/',1)[0]
bymat={}
for i,name,m,M in walk(g):
    if not rx.search(name or ''): continue
    N3=np.linalg.inv(M[:3,:3]).T
    for p in g['meshes'][m]['primitives']:
        P=acc(g,b,p['attributes']['POSITION']); W=(np.c_[P,np.ones(len(P))]@M.T)[:,:3]
        Nn=acc(g,b,p['attributes']['NORMAL'])@N3.T if 'NORMAL' in p['attributes'] else np.zeros_like(W)
        Nn/=np.maximum(np.linalg.norm(Nn,axis=1,keepdims=True),1e-9)
        UV=acc(g,b,p['attributes']['TEXCOORD_0']) if 'TEXCOORD_0' in p['attributes'] else np.zeros((len(P),2))
        I=acc(g,b,p['indices']).ravel().astype(np.int64) if 'indices' in p else np.arange(len(P))
        if np.linalg.det(M[:3,:3])<0: I=I.reshape(-1,3)[:,::-1].ravel()
        bymat.setdefault(p.get('material',0),[]).append((W,Nn,UV,I))
allW=np.vstack([w for l in bymat.values() for w,_,_,_ in l])
lo=allW.min(0); hi=allW.max(0)
# Base centre: the lowest 5% of the points (the trunk foot).
foot=allW[allW[:,1]<lo[1]+0.05*(hi[1]-lo[1])]; c=foot.mean(0); s=H/(hi[1]-lo[1])
blob=bytearray(); views=[]; accs=[]; images=[]; textures=[]; mats=[]; prims=[]
def add_view(data,target=None):
    off=len(blob); blob.extend(data)
    while len(blob)%4: blob.append(0)
    v={'buffer':0,'byteOffset':off,'byteLength':len(data)}
    if target: v['target']=target
    views.append(v); return len(views)-1
def add_acc(arr,typ,ctype,target):
    a={'bufferView':add_view(arr.tobytes(),target),'componentType':ctype,'count':len(arr),'type':typ}
    if typ=='VEC3': a['min']=arr.min(0).tolist(); a['max']=arr.max(0).tolist()
    accs.append(a); return len(accs)-1
texmap={}
def tex(ti,alpha):
    if ti in texmap: return texmap[ti]
    uri=g['images'][g['textures'][ti]['source']]['uri']; im=Image.open(f"{d}/{uri}")
    im=im.convert('RGBA' if alpha else 'RGB'); w,h=im.size; k=min(1.0,MAXT/max(w,h))
    if k<1: im=im.resize((max(4,int(w*k)),max(4,int(h*k))),Image.LANCZOS)
    bio=io.BytesIO(); im.save(bio,'PNG',optimize=True)
    images.append({'bufferView':add_view(bio.getvalue()),'mimeType':'image/png'}); textures.append({'source':len(images)-1})
    texmap[ti]=len(textures)-1; return texmap[ti]
tris=0
for mi,l in bymat.items():
    src_m=g['materials'][mi]; pbr=src_m.get('pbrMetallicRoughness',{})
    leafy=src_m.get('alphaMode') in ('BLEND','MASK') and src_m.get('doubleSided',False)
    nm={'name':src_m.get('name','m'),'doubleSided':bool(leafy),'pbrMetallicRoughness':{'metallicFactor':0.0,'roughnessFactor':0.85}}
    if 'baseColorFactor' in pbr: nm['pbrMetallicRoughness']['baseColorFactor']=pbr['baseColorFactor']
    if 'baseColorTexture' in pbr: nm['pbrMetallicRoughness']['baseColorTexture']={'index':tex(pbr['baseColorTexture']['index'],leafy)}
    if leafy: nm['alphaMode']='MASK'; nm['alphaCutoff']=float(src_m.get('alphaCutoff',0.45))
    mats.append(nm)
    W=np.vstack([x[0] for x in l]); Nn=np.vstack([x[1] for x in l]); UV=np.vstack([x[2] for x in l])
    base=np.cumsum([0]+[len(x[0]) for x in l[:-1]]); I=np.concatenate([x[3]+o for x,o in zip(l,base)])
    V=((W-c)*s).astype(np.float32); V[:,1]=((W[:,1]-lo[1])*s).astype(np.float32)
    prims.append({'attributes':{'POSITION':add_acc(V,'VEC3',5126,34962),'NORMAL':add_acc(Nn.astype(np.float32),'VEC3',5126,34962),
        'TEXCOORD_0':add_acc(UV.astype(np.float32),'VEC2',5126,34962)},'indices':add_acc(I.astype(np.uint32),'SCALAR',5125,34963),'material':len(mats)-1})
    tris+=len(I)//3
gl={'asset':{'version':'2.0','generator':'zero-zone tree_bake'},'scene':0,'scenes':[{'nodes':[0]}],'nodes':[{'name':'tree','mesh':0}],
    'meshes':[{'name':'tree','primitives':prims}],'materials':mats,'accessors':accs,'bufferViews':views,'buffers':[{'byteLength':len(blob)}]}
if images: gl['images']=images; gl['textures']=textures; gl['samplers']=[{}]
for t in textures: t['sampler']=0
js=json.dumps(gl).encode()
while len(js)%4: js+=b' '
with open(out,'wb') as f:
    f.write(struct.pack('<III',0x46546C67,2,12+8+len(js)+8+len(blob))); f.write(struct.pack('<II',len(js),0x4E4F534A)); f.write(js)
    f.write(struct.pack('<II',len(blob),0x004E4942)); f.write(blob)
print(out,'tris',tris,'mats',[m['name'] for m in mats],'bytes',len(blob),'size_m',((hi-lo)*s).round(2))
