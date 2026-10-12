# Weld + decimate the Tinkercad dirt bike and write a small GLB (Godot axes:
# front +Z, up +Y, metres, ground at y=0). Wheels split out as their own nodes.
import sys,json,struct,numpy as np,fast_simplification as fs
sys.path.insert(0,sys.argv[3])
from gltfinfo import *
g,b=load(sys.argv[1]); OUT=sys.argv[2]; BUDGET=int(sys.argv[4]) if len(sys.argv)>4 else 26000
objs=[]
for i,name,m,M in walk(g):
    for p in g['meshes'][m]['primitives']:
        P=acc(g,b,p['attributes']['POSITION']); W=(np.c_[P,np.ones(len(P))]@M.T)[:,:3]
        I=acc(g,b,p['indices']).reshape(-1,3).astype(np.int64)
        q=np.round(W*200).astype(np.int64); u,first,inv=np.unique(q,axis=0,return_index=True,return_inverse=True)
        V=W[first]; F=inv.ravel()[I]; F=F[(F[:,0]!=F[:,1])&(F[:,1]!=F[:,2])&(F[:,0]!=F[:,2])]
        objs.append(dict(name=name,mat=p['material'],V=V,F=F))
# Wheels: tyres are Object_13; centres from its two halves.
ty=[o for o in objs if o['name']=='Object_13'][0]['V']
cen=[]
for sgn in (-1,1):
    h=ty[np.sign(ty[:,0])==sgn]; c=(h.min(0)+h.max(0))/2; cen.append(c)
rad=(ty[:,1].max()-ty[:,1].min())/2
print('centres',cen,'radius',rad)
SC=0.70/(2*rad)
zc=(cen[0][2]+cen[1][2])/2; xc=(cen[0][0]+cen[1][0])/2; ground=ty[:,1].min()
def tog(V):  # model -> godot (front +X -> +Z), metres
    X=(V[:,0]-xc)*SC; Y=(V[:,1]-ground)*SC; Z=(V[:,2]-zc)*SC
    return np.c_[-Z,Y,X]
def area(V,F): return np.linalg.norm(np.cross(V[F[:,1]]-V[F[:,0]],V[F[:,2]]-V[F[:,0]]),axis=1).sum()/2
tot=sum(len(o["F"]) for o in objs)
parts={}  # key -> list of (V,F,mat)
for o in objs:
    V,F=o['V'],o['F']; tgt=max(120,int(BUDGET*len(F)/tot)); 
    CELL=float(sys.argv[5]) if len(sys.argv)>5 else 0.7
    if len(F)>tgt:
        # Grid clustering first (kills tiny parts the edge collapser can't), then QEM.
        q=np.floor(V/CELL).astype(np.int64); u,inv=np.unique(q,axis=0,return_inverse=True); inv=inv.ravel()
        cnt=np.bincount(inv); Vc=np.zeros((len(u),3)); np.add.at(Vc,inv,V); Vc/=cnt[:,None]
        Fc=inv[F]; Fc=Fc[(Fc[:,0]!=Fc[:,1])&(Fc[:,1]!=Fc[:,2])&(Fc[:,0]!=Fc[:,2])]
        Fc=np.unique(np.sort(Fc,1),axis=0,return_index=True)[1]; Fc=inv[F][(inv[F][:,0]!=inv[F][:,1])&(inv[F][:,1]!=inv[F][:,2])&(inv[F][:,0]!=inv[F][:,2])][Fc]
        if len(Fc)>len(F)*0.2 or True: V,F=Vc,Fc
    if len(F)>tgt:
        V,F=fs.simplify(V.astype(np.float32),F.astype(np.int32),target_reduction=1-tgt/len(F))
        V=V.astype(np.float64); F=F.astype(np.int64)
    # Split wheel triangles off (tyre, rim, spokes, hub).
    key=lambda k:k
    if o['name'] in ('Object_2','Object_11','Object_13'):
        C=V[F].mean(1)
        for wi,c in enumerate(cen):
            d=np.hypot(C[:,0]-c[0],C[:,1]-c[1]); sel=d<rad*1.02
            if sel.any(): parts.setdefault('wheel_r' if wi==0 else 'wheel_f',[]).append((V,F[sel],o['mat']))
            F=F[~sel]; C=C[~sel]
    if len(F): parts.setdefault('body',[]).append((V,F,o['mat']))
    print(o['name'],len(o['F']),'->',len(F))
def crease_normals(V,F,cosang=np.cos(np.radians(40))):
    # Unweld then smooth across faces whose normals are within the angle.
    fn=np.cross(V[F[:,1]]-V[F[:,0]],V[F[:,2]]-V[F[:,0]]); fa=np.linalg.norm(fn,axis=1,keepdims=True); fu=fn/np.maximum(fa,1e-12)
    corners=F.ravel(); faces=np.repeat(np.arange(len(F)),3)
    order=np.argsort(corners,kind='stable'); out=np.zeros((len(corners),3))
    cs=corners[order]; br=np.flatnonzero(np.r_[True,cs[1:]!=cs[:-1],True])
    for a,bb in zip(br[:-1],br[1:]):
        idx=order[a:bb]; fi=faces[idx]; U=fu[fi]; Wn=fn[fi]
        dots=U@U.T; acc_=(dots>cosang).astype(float)@Wn
        out[idx]=acc_
    out/=np.maximum(np.linalg.norm(out,axis=1,keepdims=True),1e-12)
    return V[corners],out,np.arange(len(corners)).reshape(-1,3)
# Build the glb
mats=[]
for m in g['materials']:
    pbr=m.get('pbrMetallicRoughness',{}); bc=pbr.get('baseColorFactor',[0.35,0.36,0.38,1.0])
    mats.append({'name':m['name'],'pbrMetallicRoughness':{'baseColorFactor':bc,'metallicFactor':float(pbr.get('metallicFactor') or 0.0),'roughnessFactor':max(0.35,float(pbr.get('roughnessFactor') or 0.5))}})
blob=bytearray(); views=[]; accs=[]; meshes=[]; nodes=[]
def add(arr,target,typ,ctype):
    off=len(blob); data=arr.tobytes(); blob.extend(data); 
    while len(blob)%4: blob.append(0)
    views.append({'buffer':0,'byteOffset':off,'byteLength':len(data),'target':target}); 
    a={'bufferView':len(views)-1,'componentType':ctype,'count':len(arr),'type':typ}
    if typ=='VEC3': a['min']=arr.min(0).tolist(); a['max']=arr.max(0).tolist()
    accs.append(a); return len(accs)-1
for key,lst in parts.items():
    prims=[]; bymat={}
    for V,F,mi in lst: bymat.setdefault(mi,[]).append((V,F))
    org=np.zeros(3)
    if key.startswith('wheel'): c=cen[0] if key=='wheel_r' else cen[1]; org=tog(c[None])[0]
    tri=0
    for mi,l in bymat.items():
        Vs=[];Ns=[];Is=[];base=0
        for V,F in l:
            used=np.unique(F); remap=-np.ones(len(V),np.int64); remap[used]=np.arange(len(used))
            Vg=tog(V[used])-org; Fg=remap[F]
            Vu,Nu,Fu=crease_normals(Vg,Fg); Vs.append(Vu);Ns.append(Nu);Is.append(Fu+base); base+=len(Vu)
        Vv=np.vstack(Vs).astype(np.float32); Nn=np.vstack(Ns).astype(np.float32); II=np.vstack(Is).astype(np.uint32).ravel()
        # re-weld identical (pos, normal) corners
        k=np.c_[np.round(Vv*1e4),np.round(Nn*100)].astype(np.int64); u,first,inv=np.unique(k,axis=0,return_index=True,return_inverse=True)
        Vv=Vv[first];Nn=Nn[first];II=inv.ravel()[II].astype(np.uint32); tri+=len(II)//3
        prims.append({'attributes':{'POSITION':add(Vv,34962,'VEC3',5126),'NORMAL':add(Nn,34962,'VEC3',5126)},'indices':add(II,34963,'SCALAR',5125),'material':mi})
    meshes.append({'name':key,'primitives':prims}); nodes.append({'name':key,'mesh':len(meshes)-1,'translation':org.tolist()})
    print(key,'tris',tri,'origin',org.round(3))
gl={'asset':{'version':'2.0','generator':'zero-zone bike_bake'},'scene':0,'scenes':[{'nodes':list(range(len(nodes)))}],'nodes':nodes,'meshes':meshes,'materials':mats,
    'accessors':accs,'bufferViews':views,'buffers':[{'byteLength':len(blob)}]}
js=json.dumps(gl).encode(); 
while len(js)%4: js+=b' '
with open(OUT,'wb') as f:
    f.write(struct.pack('<III',0x46546C67,2,12+8+len(js)+8+len(blob)))
    f.write(struct.pack('<II',len(js),0x4E4F534A)); f.write(js)
    f.write(struct.pack('<II',len(blob),0x004E4942)); f.write(blob)
print('wrote',OUT,len(blob))
