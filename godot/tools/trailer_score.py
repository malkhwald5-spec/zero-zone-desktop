"""The trailer's music, made from scratch (no samples, so no licences):
a low drone and riser under the opening lines, braams on the big cuts,
taiko-style drums that build through the action, a pulsing string ostinato,
whooshes and impacts on the cuts, and a last braam with a long tail.
Usage: python3 trailer_score.py out.wav "4.7,9.9,..."(cut times) length"""
import sys, wave
import numpy as np
from scipy.signal import fftconvolve, butter, sosfilt

SR = 48000

def t_arr(sec):
	return np.arange(int(sec * SR)) / SR

def env(n, a, d, sustain=0.0, r=0.0):
	"""Attack/decay envelope over n samples (seconds for a, d, r)."""
	e = np.ones(n)
	na = max(1, int(a * SR))
	e[:na] = np.linspace(0, 1, na)
	nd = max(1, int(d * SR))
	e[na:na + nd] = np.exp(-np.linspace(0, 5, len(e[na:na + nd]))) * (1 - sustain) + sustain
	e[na + nd:] = sustain
	if r > 0:
		nr = min(n, int(r * SR))
		e[-nr:] *= np.linspace(1, 0, nr)
	return e

def lowpass(x, f):
	return sosfilt(butter(4, f / (SR / 2), "low", output="sos"), x)

def highpass(x, f):
	return sosfilt(butter(2, f / (SR / 2), "high", output="sos"), x)

def saw(f, t):
	return 2.0 * ((f * t) % 1.0) - 1.0

def add(buf, at, x, gain=1.0, pan=0.0):
	i = int(at * SR)
	if i >= buf.shape[1]: return
	x = x[: buf.shape[1] - i]
	buf[0, i:i + len(x)] += x * gain * (1 - max(0, pan))
	buf[1, i:i + len(x)] += x * gain * (1 + min(0, pan))

def braam(sec=3.5):
	t = t_arr(sec)
	x = np.zeros_like(t)
	for f in [55.0, 82.41, 110.0, 130.81, 164.81]:
		for d in (-0.6, 0.0, 0.7):
			x += saw(f * (1 + d / 100), t)
	# Brass-like opening of the filter, then closing down.
	out = np.zeros_like(x)
	seg = SR // 50
	for i in range(0, len(x), seg):
		k = i / len(x)
		cut = 180 + 2600 * np.exp(-k * 5) * min(1.0, k * 30)
		out[i:i + seg] = lowpass(x[max(0, i - seg * 4):i + seg], cut)[-len(x[i:i + seg]):]
	return out * env(len(t), 0.04, sec * 0.8, 0.05, 0.4) * 0.12

def drum(f0=110.0, f1=45.0, sec=0.9, noise=0.25):
	t = t_arr(sec)
	f = f1 + (f0 - f1) * np.exp(-t * 18)
	ph = 2 * np.pi * np.cumsum(f) / SR
	body = np.sin(ph) * np.exp(-t * 5.5)
	hit = lowpass(np.random.randn(len(t)), 2500) * np.exp(-t * 40) * noise
	return (body + hit) * 0.8

def snare(sec=0.4):
	t = t_arr(sec)
	return (highpass(np.random.randn(len(t)), 900) * np.exp(-t * 16) * 0.35 + np.sin(2 * np.pi * 190 * t) * np.exp(-t * 25) * 0.3)

def whoosh(sec=1.2, rise=True):
	t = t_arr(sec)
	n = np.random.randn(len(t))
	out = np.zeros_like(n)
	seg = SR // 40
	for i in range(0, len(n), seg):
		k = i / len(n)
		k = k if rise else 1 - k
		out[i:i + seg] = lowpass(n[max(0, i - seg * 4):i + seg], 300 + 6000 * k ** 2)[-len(n[i:i + seg]):]
	e = np.linspace(0, 1, len(t)) ** 2 if rise else np.exp(-t * 4)
	return out * e * 0.35

def impact(sec=2.5):
	t = t_arr(sec)
	sub = np.sin(2 * np.pi * (38 + 40 * np.exp(-t * 6)) * t) * np.exp(-t * 2.2)
	return sub * 0.9 + drum(90, 35, sec, 0.6) * 0.6

def drone(sec):
	t = t_arr(sec)
	x = np.sin(2 * np.pi * 55 * t) * 0.5 + np.sin(2 * np.pi * 55.4 * t) * 0.4 + np.sin(2 * np.pi * 82.4 * t) * 0.15
	x += lowpass(np.random.randn(len(t)), 220) * 0.4
	return x * np.linspace(0, 1, len(t)) ** 1.5 * 0.35

def ostinato(sec, bpm, notes):
	t = t_arr(sec)
	step = 60.0 / bpm / 4
	x = np.zeros_like(t)
	n = int(sec / step)
	for i in range(n):
		f = notes[(i // 2) % len(notes)]
		s = int(i * step * SR)
		tt = t_arr(step * 0.9)
		tone = (saw(f, tt) + saw(f * 1.004, tt) + 0.5 * saw(f * 2, tt))
		tone *= np.exp(-tt * 9)
		x[s:s + len(tone)] += tone[: len(x) - s]
	return lowpass(x, 1800) * 0.06

def reverb(buf, sec=2.8, mix=0.28):
	ir_t = t_arr(sec)
	out = np.zeros_like(buf)
	for c in range(2):
		ir = np.random.randn(len(ir_t)) * np.exp(-ir_t * 3.2)
		ir = lowpass(ir, 5000)
		wet = fftconvolve(buf[c], ir)[: buf.shape[1]]
		wet /= np.max(np.abs(wet)) + 1e-9
		out[c] = buf[c] * (1 - mix) + wet * np.max(np.abs(buf[c])) * mix
	return out

def main():
	out = sys.argv[1]
	cuts = [float(x) for x in sys.argv[2].split(",")]
	length = float(sys.argv[3])
	np.random.seed(7)
	buf = np.zeros((2, int(length * SR)))
	aerial, plane, skydive, chute, title, sprint, aim, drop, shelling, car, zone, end = cuts
	bpm = 100.0
	beat = 60.0 / bpm
	# Opening: drone and a riser into the first braam.
	add(buf, 0.0, drone(aerial + 0.5), 1.0)
	add(buf, aerial - 1.6, whoosh(1.6, True), 0.8)
	add(buf, aerial, braam(4.5), 1.0)
	add(buf, aerial, impact(3.0), 0.7)
	# The plane: slow taiko, low.
	t = plane
	while t < skydive:
		add(buf, t, drum(95, 42, 1.0), 0.6, -0.2)
		t += beat * 2
	add(buf, skydive - 0.9, whoosh(0.9, True), 0.6)
	add(buf, skydive, impact(2.0), 0.6)
	# Freefall and canopy: drums on the beat, a whoosh on the opening.
	t = skydive
	i = 0
	while t < title - 0.6:
		add(buf, t, drum(110, 48, 0.8), 0.55 if i % 2 else 0.75, 0.2 if i % 2 else -0.2)
		t += beat
		i += 1
	add(buf, chute, whoosh(1.0, False), 0.7)
	# Drop out to nothing for a breath, then the title braam.
	add(buf, title - 1.0, whoosh(1.0, True), 0.9)
	add(buf, title, braam(5.0), 1.2)
	add(buf, title, impact(3.0), 1.0)
	# Action: driving drums (eighths), snares on 2 and 4, the ostinato.
	add(buf, sprint, ostinato(zone - sprint + 1.0, bpm * 1.2, [110.0, 110.0, 130.81, 98.0]), 1.0)
	t = sprint
	i = 0
	b2 = 60.0 / (bpm * 1.2)
	while t < zone + 2.5:
		if t < drop or t > shelling:
			add(buf, t, drum(120 if i % 4 == 0 else 150, 50, 0.6), 0.8 if i % 4 == 0 else 0.45, 0.25 * ((i % 2) * 2 - 1))
			if i % 4 == 2: add(buf, t, snare(), 0.6)
		t += b2 / 2
		i += 1
	# The kill in slow motion: the music sinks, a deep hit.
	add(buf, drop, impact(2.6), 1.0)
	add(buf, drop + 0.3, drone(1.2) [::-1], 0.6)
	add(buf, shelling, braam(3.0), 0.7)
	add(buf, car - 0.8, whoosh(0.8, True), 0.6)
	add(buf, car, impact(1.6), 0.6)
	add(buf, zone, braam(3.2), 0.8)
	# End card: the last braam with a long tail.
	add(buf, end - 1.4, whoosh(1.4, True), 1.0)
	add(buf, end, braam(6.0), 1.3)
	add(buf, end, impact(4.0), 1.1)
	buf = reverb(buf)
	# Fade the tail and normalise to -1 dBFS.
	n = buf.shape[1]
	fl = int(1.5 * SR)
	buf[:, -fl:] *= np.linspace(1, 0, fl)
	buf /= np.max(np.abs(buf)) / 0.89
	pcm = (buf.T * 32767).astype(np.int16)
	w = wave.open(out, "wb")
	w.setnchannels(2)
	w.setsampwidth(2)
	w.setframerate(SR)
	w.writeframes(pcm.tobytes())
	w.close()
	print(out, "%.1fs" % (n / SR))

main()
