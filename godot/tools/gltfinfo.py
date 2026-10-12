import json,sys,numpy as np
def load(path):
    g=json.load(open(path)); d=path.rsplit('/',1)[0]
    bins=[open(f"{d}/{b['uri']}",'rb').read() for b in g['buffers']]
    return g,bins
CT={5126:np.float32,5123:np.uint16,5125:np.uint32,5121:np.uint8}
NC={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}
def acc(g,bins,i):
    a=g['accessors'][i]; bv=g['bufferViews'][a['bufferView']]
    dt=np.dtype(CT[a['componentType']]); n=NC[a['type']]
    off=bv.get('byteOffset',0)+a.get('byteOffset',0); stride=bv.get('byteStride',0)
    buf=bins[bv['buffer']]
    if stride and stride!=dt.itemsize*n:
        arr=np.ndarray((a['count'],n),dt,buf,off,(stride,dt.itemsize))
    else:
        arr=np.frombuffer(buf,dt,a['count']*n,off).reshape(a['count'],n)
    return np.array(arr)
def nodemat(nd):
    if 'matrix' in nd: return np.array(nd['matrix']).reshape(4,4).T
    M=np.eye(4)
    if 'scale' in nd: M=np.diag(list(nd['scale'])+[1])@M
    if 'rotation' in nd:
        x,y,z,w=nd['rotation']
        R=np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])
        T=np.eye(4); T[:3,:3]=R; M=T@M
    if 'translation' in nd:
        T=np.eye(4); T[:3,3]=nd['translation']; M=T@M
    return M
def walk(g):
    out=[]
    def rec(i,P):
        nd=g['nodes'][i]; M=P@nodemat(nd)
        if 'mesh' in nd: out.append((i,nd.get('name'),nd['mesh'],M))
        for c in nd.get('children',[]): rec(c,M)
    for r in g['scenes'][g.get('scene',0)]['nodes']: rec(r,np.eye(4))
    return out
if __name__=='__main__':
    g,b=load(sys.argv[1])
    for i,name,m,M in walk(g):
        for p in g['meshes'][m]['primitives']:
            P=acc(g,b,p['attributes']['POSITION']); W=(np.c_[P,np.ones(len(P))]@M.T)[:,:3]
            print(i,name,'mat',p.get('material'),'n',len(P),'idx' if 'indices' in p else 'noidx','min',W.min(0).round(3),'max',W.max(0).round(3))
