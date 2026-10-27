"""CMU (cgspeed) BVH -> GLB with a Mixamo-named skeleton for tools/retarget_mixamo.gd.
The clip's first frame (the added T-pose) becomes the skeleton's rest pose;
the rest is resampled to 30 fps. Usage: bvh2glb.py in.bvh out.glb [start_s end_s]"""
import sys, json, struct, math
import numpy as np
from scipy.spatial.transform import Rotation as R

NAMES = {"Hips": "Hips", "LeftUpLeg": "LeftUpLeg", "LeftLeg": "LeftLeg", "LeftFoot": "LeftFoot", "LeftToeBase": "LeftToeBase",
	"RightUpLeg": "RightUpLeg", "RightLeg": "RightLeg", "RightFoot": "RightFoot", "RightToeBase": "RightToeBase",
	"LowerBack": "Spine", "Spine": "Spine1", "Spine1": "Spine2", "Neck": "Neck", "Head": "Head",
	"LeftShoulder": "LeftShoulder", "LeftArm": "LeftArm", "LeftForeArm": "LeftForeArm", "LeftHand": "LeftHand",
	"RightShoulder": "RightShoulder", "RightArm": "RightArm", "RightForeArm": "RightForeArm", "RightHand": "RightHand"}

def parse(path):
	toks = open(path).read().split()
	i = 0
	joints = []   # {name, parent, offset, channels}
	stack = []
	while True:
		t = toks[i]
		if t in ("ROOT", "JOINT"):
			joints.append({"name": toks[i + 1], "parent": stack[-1] if stack else -1, "offset": None, "ch": []})
			i += 2
		elif t == "End":
			# skip End Site block
			depth = 0
			i += 2
			while True:
				if toks[i] == "{": depth += 1
				elif toks[i] == "}":
					depth -= 1
					if depth == 0:
						i += 1
						break
				i += 1
		elif t == "{":
			stack.append(len(joints) - 1)
			i += 1
		elif t == "}":
			stack.pop()
			i += 1
		elif t == "OFFSET":
			joints[stack[-1]]["offset"] = [float(x) for x in toks[i + 1:i + 4]]
			i += 4
		elif t == "CHANNELS":
			n = int(toks[i + 1])
			joints[stack[-1]]["ch"] = toks[i + 2:i + 2 + n]
			i += 2 + n
		elif t == "MOTION":
			break
		else:
			i += 1
	nf = int(toks[i + 2])
	ft = float(toks[i + 5])
	vals = np.array([float(x) for x in toks[i + 6:]]).reshape(nf, -1)
	return joints, vals, ft

def main():
	src, dst = sys.argv[1], sys.argv[2]
	t0 = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
	t1 = float(sys.argv[4]) if len(sys.argv) > 4 else 1e9
	# "loop": cut one whole gait cycle (two steps) out of [t0, t1] whose last
	# pose runs back into its first, so the clip repeats without a jump.
	loop = len(sys.argv) > 5 and sys.argv[5] == "loop"
	# "land": a drop onto lower ground; lift the hips so it ends standing at
	# its starting height (the floor of the clip is where it lands).
	land = len(sys.argv) > 5 and sys.argv[5] == "land"
	lmin = float(sys.argv[6]) if len(sys.argv) > 6 else 0.55   # loop length range (s)
	lmax = float(sys.argv[7]) if len(sys.argv) > 7 else 1.6
	joints, vals, ft = parse(src)
	nj = len(joints)
	nf = vals.shape[0]
	rots = np.zeros((nf, nj, 4))
	root_pos = np.zeros((nf, 3))
	c = 0
	for j, jt in enumerate(joints):
		ch = jt["ch"]
		pos = [k for k in ch if k.endswith("position")]
		rot = [k for k in ch if k.endswith("rotation")]
		cols = {k: c + ch.index(k) for k in ch}
		if pos: root_pos = vals[:, [cols["Xposition"], cols["Yposition"], cols["Zposition"]]]
		order = "".join(k[0] for k in rot)        # e.g. ZYX, intrinsic
		ang = vals[:, [cols[k] for k in rot]]
		rots[:, j] = R.from_euler(order.upper(), ang, degrees=True).as_quat()   # x y z w
		c += len(ch)
	# Scale: hips height in the T-pose frame -> 0.95 m.
	hip_h = root_pos[0, 1]
	# leg length from offsets (more robust than the frame's height)
	scale = 1.0
	legs = 0.0
	k = next(j for j, jt in enumerate(joints) if jt["name"] == "LeftUpLeg")
	while True:
		legs += 0.0
		break
	scale = 0.95 / max(hip_h, 1e-3)
	# Frames: skip the T-pose frame 0, resample to 30 fps within [t0, t1].
	src_fps = 1.0 / ft
	step = max(1, int(round(src_fps / 30.0)))
	idx = [f for f in range(1, nf, step) if t0 <= (f - 1) * ft <= t1]
	if loop:
		# Pose of each frame: every joint's rotation (the hips' without its
		# heading), plus the hips' height; find the closest pair 0.55..1.6 s apart.
		def feat(f):
			q = rots[f].copy()
			hr = R.from_quat(q[0]).as_euler("YXZ")
			q[0] = R.from_euler("YXZ", [0.0, hr[1], hr[2]]).as_quat()
			q = q * np.sign(q[:, 3:4] + 1e-9)
			return np.concatenate([q.flatten(), [root_pos[f, 1] * scale * 4.0]])
		F = {f: feat(f) for f in idx}
		best = (1e9, idx[0], idx[-1])
		for a_i, fa in enumerate(idx):
			for fb in idx[a_i + 1:]:
				dt = (fb - fa) * ft
				if dt < lmin: continue
				if dt > lmax: break
				d = float(np.sum((F[fa] - F[fb]) ** 2))
				if d < best[0]: best = (d, fa, fb)
		idx = [f for f in idx if best[1] <= f < best[2]]
		print("loop %.2f-%.2fs err %.3f" % ((best[1] - 1) * ft, (best[2] - 1) * ft, best[0]))
	times = np.array([(f - idx[0]) * ft for f in idx], dtype=np.float32)
	if land:
		root_pos[1:, 1] += root_pos[0, 1] - root_pos[idx[-1], 1]
	# Turn the whole clip so the actor starts out facing +Z (the way the T-pose
	# faces, toes forward), starting at the origin; leave the hips height.
	hips_r = R.from_quat(rots[idx[0]:idx[0] + 6, 0])
	fwd = hips_r.apply([0.0, 0.0, 1.0]).mean(axis=0)
	if loop and np.linalg.norm((root_pos[idx[-1]] - root_pos[idx[0]])[[0, 2]]) > 0.5 / scale:
		# A stride cycle: the way it travels (the hips swing about inside it).
		fwd = root_pos[idx[-1]] - root_pos[idx[0]]
	yaw = math.atan2(fwd[0], fwd[2])
	turn = R.from_euler("Y", -yaw)
	for f in range(1, nf):
		rots[f, 0] = (turn * R.from_quat(rots[f, 0])).as_quat()
	p0 = root_pos[idx[0]].copy()
	rel = root_pos - np.array([p0[0], 0.0, p0[2]])
	root_pos = turn.apply(rel)
	# Nodes: rest = frame-0 pose.
	nodes = []
	for j, jt in enumerate(joints):
		nm = "mixamorig_" + NAMES.get(jt["name"], "cmu_" + jt["name"])
		off = np.array(jt["offset"]) * scale
		if jt["parent"] < 0: off = np.array([0.0, hip_h * scale, 0.0])
		q = rots[0, j]
		nodes.append({"name": nm, "translation": off.tolist(), "rotation": q.tolist(), "children": []})
	for j, jt in enumerate(joints):
		if jt["parent"] >= 0: nodes[jt["parent"]]["children"].append(j)
	for nd in nodes:
		if not nd["children"]: del nd["children"]
	# Global rest matrices for inverse bind.
	G = [None] * nj
	for j, jt in enumerate(joints):
		m = np.eye(4)
		m[:3, :3] = R.from_quat(nodes[j]["rotation"]).as_matrix()
		m[:3, 3] = nodes[j]["translation"]
		G[j] = m if jt["parent"] < 0 else G[jt["parent"]] @ m
	ibm = np.array([np.linalg.inv(g).T.flatten() for g in G], dtype=np.float32)   # column-major
	# A tiny skinned triangle so the importer builds a Skeleton3D.
	mesh_node = len(nodes)
	nodes.append({"name": "cmu_body", "mesh": 0, "skin": 0})
	blob = bytearray()
	views, accs = [], []
	def add(arr, ctype, typ, target=None, minmax=False):
		b = arr.tobytes()
		while len(blob) % 4: blob.append(0)
		off = len(blob)
		blob.extend(b)
		v = {"buffer": 0, "byteOffset": off, "byteLength": len(b)}
		if target: v["target"] = target
		views.append(v)
		a = {"bufferView": len(views) - 1, "componentType": ctype, "count": int(arr.shape[0]), "type": typ}
		if minmax:
			a["min"] = arr.min(axis=0).tolist() if arr.ndim > 1 else [float(arr.min())]
			a["max"] = arr.max(axis=0).tolist() if arr.ndim > 1 else [float(arr.max())]
		accs.append(a)
		return len(accs) - 1
	pos = np.array([[0, 0, 0], [0.01, 0, 0], [0, 0.01, 0]], dtype=np.float32)
	a_pos = add(pos, 5126, "VEC3", 34962, True)
	a_j = add(np.zeros((3, 4), dtype=np.uint16), 5123, "VEC4", 34962)
	a_w = add(np.array([[1, 0, 0, 0]] * 3, dtype=np.float32), 5126, "VEC4", 34962)
	a_ibm = add(ibm, 5126, "MAT4")
	a_t = add(times, 5126, "SCALAR", None, True)
	channels, samplers = [], []
	for j in range(nj):
		q = rots[idx, j].astype(np.float32)
		# keep quaternions continuous
		for f in range(1, len(q)):
			if np.dot(q[f], q[f - 1]) < 0: q[f] = -q[f]
		a_q = add(q, 5126, "VEC4")
		samplers.append({"input": a_t, "output": a_q, "interpolation": "LINEAR"})
		channels.append({"sampler": len(samplers) - 1, "target": {"node": j, "path": "rotation"}})
	rp = (root_pos[idx] * scale).astype(np.float32)
	a_rp = add(rp, 5126, "VEC3")
	samplers.append({"input": a_t, "output": a_rp, "interpolation": "LINEAR"})
	channels.append({"sampler": len(samplers) - 1, "target": {"node": 0, "path": "translation"}})
	gl = {"asset": {"version": "2.0", "generator": "bvh2glb"},
		"scene": 0, "scenes": [{"nodes": [0, mesh_node]}], "nodes": nodes,
		"meshes": [{"primitives": [{"attributes": {"POSITION": a_pos, "JOINTS_0": a_j, "WEIGHTS_0": a_w}}]}],
		"skins": [{"joints": list(range(nj)), "inverseBindMatrices": a_ibm, "skeleton": 0}],
		"animations": [{"name": "mixamo_com", "channels": channels, "samplers": samplers}],
		"accessors": accs, "bufferViews": views, "buffers": [{"byteLength": len(blob)}]}
	js = json.dumps(gl).encode()
	while len(js) % 4: js += b" "
	while len(blob) % 4: blob.append(0)
	out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob))
	out += struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(blob), 0x004E4942) + bytes(blob)
	open(dst, "wb").write(out)
	print(dst, "frames", len(idx), "len %.2fs" % times[-1], "hip_h %.2f" % hip_h)

main()
