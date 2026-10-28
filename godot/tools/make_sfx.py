"""Small sound effects made from scratch (no recordings, so no licences):
bullet impacts on dirt, concrete, metal and wood, ricochet whines, flesh hits,
brass casings landing, footsteps on metal and the rustle of worn gear.
Usage: python3 tools/make_sfx.py godot/assets/sounds   (writes <name>.ogg)"""
import os, subprocess, sys, tempfile, wave
import numpy as np
from scipy.signal import butter, sosfilt

SR = 44100
rng = np.random.default_rng(7)

def T(sec):
	return np.arange(int(sec * SR)) / SR

def bp(x, lo, hi, order=2):
	return sosfilt(butter(order, [lo / (SR / 2), min(hi, SR / 2 - 100) / (SR / 2)], "band", output="sos"), x)

def lp(x, f, order=2):
	return sosfilt(butter(order, min(f, SR / 2 - 100) / (SR / 2), "low", output="sos"), x)

def hp(x, f, order=2):
	return sosfilt(butter(order, f / (SR / 2), "high", output="sos"), x)

def env(n, att, dec):
	t = np.arange(n) / SR
	e = np.exp(-t / dec)
	na = max(1, int(att * SR))
	e[:na] *= np.linspace(0, 1, na)
	return e

def noise(sec):
	return rng.standard_normal(int(sec * SR))

def ring(freqs, sec, dec, amps=None):
	t = T(sec)
	out = np.zeros_like(t)
	for i, f in enumerate(freqs):
		a = amps[i] if amps else 1.0 / (i + 1)
		out += a * np.sin(2 * np.pi * f * t + rng.random() * 6.28) * np.exp(-t / (dec * rng.uniform(0.7, 1.3)))
	return out

def pad(x, sec):
	n = int(sec * SR)
	return np.concatenate([x, np.zeros(max(0, n - len(x)))])[:n] if n else x

def mix(*parts):
	n = max(len(p) for p in parts)
	out = np.zeros(n)
	for p in parts: out[:len(p)] += p
	return out

def delay(x, sec):
	return np.concatenate([np.zeros(int(sec * SR)), x])

def norm(x, peak=0.9):
	x = x - np.mean(x)
	return x / (np.max(np.abs(x)) + 1e-9) * peak

def debris(sec, n, lo, hi, gain=0.4):
	"""Bits of grit falling after the hit: tiny ticks spread over `sec`."""
	out = np.zeros(int(sec * SR) + SR // 5)
	for _ in range(n):
		at = int(rng.uniform(0.02, sec) * SR)
		k = bp(noise(0.02), lo, hi) * env(int(0.02 * SR), 0.0005, 0.004) * rng.uniform(0.2, 1.0)
		out[at:at + len(k)] += k
	return out * gain

def impact_dirt():
	thud = lp(noise(0.25), 900) * env(int(0.25 * SR), 0.001, 0.035) * 1.6
	snap = bp(noise(0.05), 1500, 6000) * env(int(0.05 * SR), 0.0005, 0.006)
	return norm(mix(thud, snap, debris(0.35, 14, 800, 4000, 0.25)), 0.8)

def impact_concrete():
	crack = hp(noise(0.08), 1800) * env(int(0.08 * SR), 0.0003, 0.007) * 1.4
	body = bp(noise(0.2), 400, 2500) * env(int(0.2 * SR), 0.001, 0.025)
	return norm(mix(crack, body, debris(0.4, 22, 2000, 8000, 0.35)), 0.85)

def impact_metal():
	f0 = rng.uniform(900, 1700)
	clang = ring([f0, f0 * 2.31, f0 * 3.87, f0 * 5.1, f0 * 0.53], 0.9, 0.18, [1, 0.6, 0.4, 0.25, 0.5])
	hit = hp(noise(0.03), 2500) * env(int(0.03 * SR), 0.0002, 0.003) * 2.0
	return norm(mix(clang * env(len(clang), 0.0005, 0.25), hit), 0.8)

def impact_wood():
	knock = ring([rng.uniform(180, 260), rng.uniform(420, 560), rng.uniform(900, 1200)], 0.3, 0.04, [1, 0.6, 0.3])
	crack = bp(noise(0.06), 1200, 5000) * env(int(0.06 * SR), 0.0004, 0.008)
	return norm(mix(knock, crack, debris(0.25, 8, 1000, 5000, 0.2)), 0.8)

def ricochet():
	sec = rng.uniform(0.45, 0.8)
	t = T(sec)
	f = np.linspace(rng.uniform(3200, 4200), rng.uniform(900, 1500), len(t))
	ph = 2 * np.pi * np.cumsum(f) / SR
	whine = (np.sin(ph) + 0.3 * np.sin(2.01 * ph)) * env(len(t), 0.004, sec * 0.45)
	tick = hp(noise(0.03), 2000) * env(int(0.03 * SR), 0.0002, 0.004) * 1.5
	return norm(mix(tick, whine * 0.8), 0.7)

def flesh():
	thump = lp(noise(0.18), 500) * env(int(0.18 * SR), 0.001, 0.03) * 1.5
	slap = bp(noise(0.06), 600, 3000) * env(int(0.06 * SR), 0.0005, 0.01)
	return norm(mix(thump, slap), 0.8)

def casing():
	"""A spent brass case: a bright tink, then two or three smaller bounces."""
	out = np.zeros(int(0.7 * SR))
	f0 = rng.uniform(3800, 5200)
	at = 0.0
	g = 1.0
	for _ in range(rng.integers(3, 5)):
		r = ring([f0, f0 * 1.52, f0 * 2.7, f0 * 4.1], 0.25, 0.05, [1, 0.5, 0.4, 0.2]) * g
		i = int(at * SR)
		out[i:i + len(r)] += r[:len(out) - i]
		at += rng.uniform(0.07, 0.16) * g
		g *= rng.uniform(0.35, 0.6)
	return norm(hp(out, 1500), 0.6)

def step_metal():
	f0 = rng.uniform(140, 220)
	boom = ring([f0, f0 * 2.7, f0 * 5.3, rng.uniform(1100, 1500)], 0.4, 0.07, [1, 0.5, 0.3, 0.25])
	scuff = bp(noise(0.08), 800, 4000) * env(int(0.08 * SR), 0.002, 0.012) * 0.6
	return norm(mix(boom, scuff), 0.75)

def cloth():
	sec = rng.uniform(0.25, 0.45)
	n = int(sec * SR)
	s = bp(noise(sec), 700, 5000)
	# Rustle: the noise comes in uneven little swells.
	am = np.abs(lp(rng.standard_normal(n), 25)) * 6.0
	e = np.sin(np.linspace(0, np.pi, n)) ** 1.5
	buckle = ring([rng.uniform(2500, 3500), rng.uniform(5000, 6500)], sec, 0.03, [0.15, 0.08])
	return norm(mix(s * am * e, delay(buckle, rng.uniform(0.05, sec * 0.6))[:n]), 0.5)

SETS = {"impact_dirt": (impact_dirt, 3), "impact_concrete": (impact_concrete, 3), "impact_metal": (impact_metal, 3),
	"impact_wood": (impact_wood, 2), "ricochet": (ricochet, 3), "hit_flesh": (flesh, 2), "casing": (casing, 4),
	"step_metal": (step_metal, 4), "cloth": (cloth, 4)}

def write_ogg(x, path):
	with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
		tmp = f.name
	pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
	with wave.open(tmp, "wb") as w:
		w.setnchannels(1)
		w.setsampwidth(2)
		w.setframerate(SR)
		w.writeframes(pcm.tobytes())
	subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp, "-c:a", "libvorbis", "-q:a", "5", path], check=True)
	os.remove(tmp)

def main():
	out = sys.argv[1]
	for name, (fn, n) in SETS.items():
		for i in range(1, n + 1):
			write_ogg(fn(), os.path.join(out, "%s_%d.ogg" % (name, i)))
			print("made", name, i)

if __name__ == "__main__":
	main()
