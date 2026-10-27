"""The trailer's music, made from scratch (no samples, so no licences):
string pads and an ostinato, a choir, braams, taiko-style drums, a heartbeat
for the slow-motion moments, risers, whooshes and impacts, laid on a cue
sheet of cut times and run through a hall reverb.
Usage: python3 trailer_score.py out.wav cues.json
cues.json: {"length": s, "intro": [t...], "aerial": t, "plane": t, "skydive": t,
 "chute": t, "title": t, "action": t, "slowmo": [t...], "aim": t, "kill": t,
 "war": t, "impact": t, "car": t, "last": t, "end": t}"""
import sys, wave, json
import numpy as np
from scipy.signal import fftconvolve, butter, sosfilt

SR = 48000
rng = np.random.default_rng(11)

def T(sec):
	return np.arange(int(sec * SR)) / SR

def lp(x, f, order=2):
	return sosfilt(butter(order, min(f, SR / 2 - 100) / (SR / 2), "low", output="sos"), x)

def hp(x, f, order=2):
	return sosfilt(butter(order, f / (SR / 2), "high", output="sos"), x)

def bp(x, lo, hi):
	return sosfilt(butter(2, [lo / (SR / 2), hi / (SR / 2)], "band", output="sos"), x)

def saw(f, t, ph=0.0):
	return 2.0 * ((f * t + ph) % 1.0) - 1.0

def adsr(n, a, d, s, r):
	e = np.full(n, s)
	na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
	na = min(na, n)
	e[:na] = np.linspace(0, 1, na)
	nd = min(nd, n - na)
	e[na:na + nd] = np.linspace(1, s, nd)
	if nr > 0:
		nr = min(nr, n)
		e[-nr:] *= np.linspace(1, 0, nr)
	return e

def sweep_lp(x, f0, f1, curve=2.0):
	"""Low-pass whose cut-off moves from f0 to f1 over the sound."""
	out = np.zeros_like(x)
	seg = SR // 60
	zi = None
	for i in range(0, len(x), seg):
		k = (i / len(x)) ** curve
		f = f0 + (f1 - f0) * k
		sos = butter(2, min(max(f, 40), SR / 2 - 200) / (SR / 2), "low", output="sos")
		y = sosfilt(sos, x[max(0, i - seg * 3):i + seg])
		out[i:i + seg] = y[-len(x[i:i + seg]):]
	return out

NOTE = {"A1": 55.0, "E2": 82.41, "A2": 110.0, "C3": 130.81, "D3": 146.83, "E3": 164.81, "F2": 87.31, "G2": 98.0,
	"F3": 174.61, "G3": 196.0, "A3": 220.0, "B3": 246.94, "C4": 261.63, "D4": 293.66, "E4": 329.63, "F4": 349.23, "G4": 392.0, "A4": 440.0}

class Mix:
	def __init__(self, length):
		self.buf = np.zeros((2, int(length * SR)))

	def add(self, at, x, gain=1.0, pan=0.0):
		i = int(at * SR)
		if i >= self.buf.shape[1] or i + len(x) <= 0: return
		if i < 0:
			x = x[-i:]
			i = 0
		x = x[: self.buf.shape[1] - i]
		self.buf[0, i:i + len(x)] += x * gain * min(1.0, 1.0 - pan)
		self.buf[1, i:i + len(x)] += x * gain * min(1.0, 1.0 + pan)

# ---------------------------------------------------------------- instruments
def strings(freqs, sec, att=1.2, rel=1.5, bright=2200.0):
	t = T(sec)
	x = np.zeros_like(t)
	for f in freqs:
		vib = 1 + 0.004 * np.sin(2 * np.pi * 5.2 * t + rng.random() * 6)
		for d in (-0.35, -0.12, 0.0, 0.14, 0.33):
			fr = f * (1 + d / 100) * vib
			ph = 2 * np.pi * np.cumsum(fr) / SR
			x += (np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.33 * np.sin(3 * ph) + 0.25 * np.sin(4 * ph) + 0.2 * np.sin(5 * ph))
	x = lp(x, bright)
	return x * adsr(len(t), att, 0.5, 0.85, rel) / (len(freqs) * 5)

def stab(f, sec=0.22):
	t = T(sec)
	x = sum(saw(f * (1 + d / 100), t, rng.random()) for d in (-0.3, 0.0, 0.3))
	x += 0.5 * saw(f * 2, t)
	x = lp(x, 2600)
	return x * np.exp(-t * 11) * 0.22

def choir(freqs, sec, att=1.5, rel=2.0):
	"""'Aah': buzzy voices through vowel formants."""
	t = T(sec)
	src = np.zeros_like(t)
	for f in freqs:
		for d in (-0.5, 0.0, 0.45):
			vib = 1 + 0.006 * np.sin(2 * np.pi * 5.6 * t + rng.random() * 6)
			ph = np.cumsum(f * (1 + d / 100) * vib) / SR
			src += 2.0 * (ph % 1.0) - 1.0
	src += rng.standard_normal(len(t)) * 0.15
	v = bp(src, 600, 900) * 1.0 + bp(src, 1050, 1350) * 0.6 + bp(src, 2400, 2900) * 0.25
	return v * adsr(len(t), att, 0.3, 0.9, rel) / (len(freqs) * 2.0)

def braam(sec=4.0, gain=1.0):
	t = T(sec)
	x = np.zeros_like(t)
	for f in (NOTE["A1"], NOTE["E2"], NOTE["A2"], NOTE["C3"]):
		for d in (-0.5, 0.0, 0.6):
			x += saw(f * (1 + d / 100), t, rng.random())
			x += 0.6 * np.sign(np.sin(2 * np.pi * f * 0.5 * (1 + d / 100) * t))
	x = sweep_lp(x, 3200, 160, 0.6)
	x = np.tanh(x * 0.5) * 0.9
	sub = np.sin(2 * np.pi * 41.2 * t) * 0.8
	return (x * 0.55 + sub) * adsr(len(t), 0.03, 1.2, 0.35, sec * 0.5) * 0.4 * gain

def taiko(big=False):
	sec = 1.4 if big else 0.8
	t = T(sec)
	f0, f1 = (95, 38) if big else (130, 55)
	f = f1 + (f0 - f1) * np.exp(-t * 14)
	body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * (3.2 if big else 6.0))
	slap = lp(rng.standard_normal(len(t)), 3000) * np.exp(-t * 45) * 0.45
	skin = bp(rng.standard_normal(len(t)), 150, 600) * np.exp(-t * 9) * 0.5
	return np.tanh((body + slap + skin) * 1.3) * (1.0 if big else 0.7)

def snare():
	t = T(0.45)
	n = bp(rng.standard_normal(len(t)), 900, 5000) * np.exp(-t * 14) * 0.45
	b = np.sin(2 * np.pi * 185 * t) * np.exp(-t * 28) * 0.45
	return n + b

def hat(open_=False):
	t = T(0.25 if open_ else 0.06)
	return hp(rng.standard_normal(len(t)), 7000) * np.exp(-t * (14 if open_ else 70)) * 0.25

def heart():
	t = T(0.7)
	def thump(at):
		tt = np.clip(t - at, 0, None)
		return np.sin(2 * np.pi * 48 * tt) * np.exp(-tt * 14) * (t >= at)
	return (thump(0.0) + 0.7 * thump(0.22)) * 0.9

def riser(sec):
	t = T(sec)
	n = rng.standard_normal(len(t))
	x = sweep_lp(n, 200, 9000, 2.2) * 0.4
	f = 200 * (8 ** (t / sec))
	tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.15
	return (x + tone) * (t / sec) ** 2.2

def whoosh(sec=1.0):
	t = T(sec)
	x = sweep_lp(rng.standard_normal(len(t)), 500, 6000, 1.0)
	return x * np.sin(np.pi * t / sec) ** 2 * 0.5

def impact(sec=3.0, gain=1.0):
	t = T(sec)
	sub = np.sin(2 * np.pi * np.cumsum(30 + 55 * np.exp(-t * 7)) / SR) * np.exp(-t * 1.6)
	crack = lp(rng.standard_normal(len(t)), 5000) * np.exp(-t * 18) * 0.7
	return np.tanh((sub * 1.2 + crack + taiko(True)[:len(t)] * 0.6 if len(t) <= int(1.4 * SR) else sub * 1.2 + crack) * 1.2) * gain

def pluck(f, sec=1.6):
	t = T(sec)
	x = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(4 * np.pi * f * t) + 0.12 * np.sin(6 * np.pi * f * t)
	return x * np.exp(-t * 3.2) * 0.35

def drone(sec):
	t = T(sec)
	x = np.sin(2 * np.pi * 55 * t) * 0.6 + np.sin(2 * np.pi * 55.3 * t) * 0.4 + np.sin(2 * np.pi * 110.2 * t) * 0.12
	x += lp(rng.standard_normal(len(t)), 260) * 0.35
	return x * np.minimum(1, t / 2.5) * 0.4

def reverb(buf, sec=3.6, mix=0.3):
	t = T(sec)
	out = np.zeros_like(buf)
	for c in range(2):
		ir = rng.standard_normal(len(t)) * np.exp(-t * 2.4)
		ir = lp(ir, 6500)
		ir[: int(0.02 * SR)] *= np.linspace(0, 1, int(0.02 * SR))
		wet = fftconvolve(buf[c], ir)[: buf.shape[1]]
		wet *= np.max(np.abs(buf[c])) / (np.max(np.abs(wet)) + 1e-9)
		out[c] = buf[c] * (1 - mix) + wet * mix
	return out

# ---------------------------------------------------------------- the cue
def main():
	out = sys.argv[1]
	c = json.load(open(sys.argv[2]))
	L = c["length"]
	m = Mix(L + 1.0)
	am = [NOTE["A2"], NOTE["C3"], NOTE["E3"]]
	# Opening: drone; a pluck under each line; a riser into the first braam.
	m.add(0.0, drone(c["aerial"] + 1.0))
	for i, t in enumerate(c["intro"]):
		m.add(t, pluck([NOTE["A3"], NOTE["C4"], NOTE["E4"]][i % 3]), 0.9, [-0.3, 0.3, 0.0][i % 3])
		m.add(t, pluck([NOTE["A2"], NOTE["A2"], NOTE["A1"] * 2][i % 3]), 0.5)
	m.add(c["aerial"] - 2.0, riser(2.0), 0.8)
	# The island: braam, strings and the choir opening out.
	m.add(c["aerial"], braam(5.0), 1.0)
	m.add(c["aerial"], strings(am + [NOTE["A3"]], c["title"] - c["aerial"] - 0.6, 2.0, 1.0), 1.0)
	m.add(c["aerial"] + 1.0, choir([NOTE["A3"], NOTE["E4"]], c["plane"] - c["aerial"] + 1.5, 2.0, 1.5), 0.8)
	# The plane: slow taiko; whoosh past.
	beat = 60.0 / 100.0
	t = c["plane"]
	while t < c["skydive"]:
		m.add(t, taiko(True), 0.7, -0.15)
		m.add(t + beat, taiko(), 0.4, 0.2)
		t += beat * 2
	m.add(c["plane"] + 0.6, whoosh(1.6), 0.7)
	# The drop: ostinato starts, drums on the beat.
	t = c["skydive"]
	i = 0
	while t < c["title"] - 0.7:
		m.add(t, stab([NOTE["A2"], NOTE["A2"], NOTE["C3"], NOTE["A2"]][i % 4]), 1.0, 0.2 if i % 2 else -0.2)
		if i % 2 == 0: m.add(t, taiko(), 0.6)
		t += beat / 2
		i += 1
	m.add(c["chute"] - 0.4, whoosh(1.2), 0.8)
	m.add(c["title"] - 1.6, riser(1.6), 1.0)
	# Title: the big one.
	m.add(c["title"], braam(5.5, 1.3), 1.0)
	m.add(c["title"], impact(3.0, 1.2), 1.0)
	m.add(c["title"], choir([NOTE["A2"], NOTE["E3"], NOTE["A3"]], 3.0, 0.05, 2.0), 0.9)
	# Action: driving drums, hats, the ostinato, strings underneath.
	beat = 60.0 / 120.0
	slow = sorted(c.get("slowmo", []))
	def in_slow(tt):
		return any(s <= tt < s + 1.6 for s in slow)
	t = c["action"]
	i = 0
	prog = [[NOTE["A2"], NOTE["C3"], NOTE["E3"]], [NOTE["F2"], NOTE["A2"], NOTE["C3"]],
		[NOTE["C3"], NOTE["E3"], NOTE["G3"]], [NOTE["G2"], NOTE["B3"] / 2 * 2, NOTE["D3"]]]
	bar = beat * 4
	k = 0
	while c["action"] + k * bar < c["last"]:
		bt = c["action"] + k * bar
		if not in_slow(bt) and not (c["kill"] <= bt < c["war"]):
			m.add(bt, strings(prog[k % 4], bar + 0.4, 0.15, 0.4, 3000), 0.8)
		k += 1
	while t < c["last"]:
		if in_slow(t) or c["kill"] <= t < c["war"] - 0.1:
			t += beat / 2
			i += 1
			continue
		ost = [NOTE["A3"], NOTE["A3"], NOTE["C4"], NOTE["A3"], NOTE["E4"], NOTE["A3"], NOTE["D4"], NOTE["C4"]]
		m.add(t, stab(ost[i % 8] / 2), 0.9, 0.25 * ((i % 2) * 2 - 1))
		if i % 4 == 0: m.add(t, taiko(True), 0.75, -0.1)
		elif i % 2 == 0: m.add(t, taiko(), 0.55, 0.15)
		if i % 4 == 2: m.add(t, snare(), 0.55)
		m.add(t, lp(hat(i % 4 == 3), 9000), 0.16, 0.4)
		m.add(t + beat / 4, lp(hat(), 9000), 0.08, 0.4)
		t += beat / 2
		i += 1
	# Slow motion: the music holds its breath, a heartbeat, a low swell.
	for s in slow:
		m.add(s, impact(2.0, 0.6), 1.0)
		m.add(s + 0.15, heart(), 1.0)
		m.add(s + 0.95, heart(), 0.8)
		m.add(s, strings([NOTE["A2"], NOTE["E3"]], 1.8, 0.3, 0.8, 900), 0.9)
	# The aim: a riser; the kill: impact and a gap.
	m.add(c["kill"] - 1.4, riser(1.4), 0.9)
	m.add(c["kill"], impact(3.0, 1.2), 1.0)
	m.add(c["kill"] + 0.2, choir([NOTE["A3"], NOTE["C4"]], 2.0, 0.4, 1.2), 0.5)
	# War: braams over the drums, the near impact in slow motion.
	m.add(c["war"], braam(3.5, 1.1), 1.0)
	m.add(c["war"], choir([NOTE["A2"], NOTE["E3"], NOTE["C4"]], c["impact"] - c["war"] + 1.0, 0.3, 1.0), 0.7)
	m.add(c["impact"], impact(3.5, 1.4), 1.0)
	m.add(c["car"] - 0.8, whoosh(1.0), 0.8)
	m.add(c["car"], braam(2.6, 0.8), 1.0)
	# The last look: drums out, strings and choir carry it.
	m.add(c["last"] - 0.3, impact(2.5, 0.8), 1.0)
	lt = c["last"]
	chords = [[NOTE["A2"], NOTE["E3"], NOTE["C4"]], [NOTE["F2"], NOTE["C3"], NOTE["A3"]],
		[NOTE["C3"], NOTE["G3"], NOTE["E4"]], [NOTE["G2"], NOTE["D3"], NOTE["B3"]]]
	seg = (c["end"] - lt) / 4
	for j, ch in enumerate(chords):
		m.add(lt + j * seg, strings(ch, seg + 1.0, 0.6, 0.9, 2600), 1.0)
		m.add(lt + j * seg, choir(ch[1:], seg + 1.0, 0.6, 0.9), 0.6)
	m.add(c["end"] - 1.8, riser(1.8), 1.0)
	# End card.
	m.add(c["end"], braam(6.0, 1.4), 1.0)
	m.add(c["end"], impact(4.0, 1.3), 1.0)
	m.add(c["end"], choir([NOTE["A2"], NOTE["E3"], NOTE["A3"], NOTE["C4"]], 5.0, 0.05, 3.0), 0.9)
	m.add(c["end"], strings([NOTE["A1"] * 2, NOTE["E3"], NOTE["A3"]], 5.0, 0.05, 3.0), 0.8)
	buf = reverb(m.buf)
	buf = np.tanh(buf / (np.max(np.abs(buf)) + 1e-9) * 1.6) / np.tanh(1.6)
	n = int(L * SR)
	buf = buf[:, :n]
	fl = int(1.5 * SR)
	buf[:, -fl:] *= np.linspace(1, 0, fl)
	buf *= 0.92 / np.max(np.abs(buf))
	pcm = (buf.T * 32767).astype(np.int16)
	w = wave.open(out, "wb")
	w.setnchannels(2)
	w.setsampwidth(2)
	w.setframerate(SR)
	w.writeframes(pcm.tobytes())
	w.close()
	print(out, "%.1fs" % L)

main()
