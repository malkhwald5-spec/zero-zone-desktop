'use strict';

// Synthesized sound effects (Web Audio) so the game ships without audio assets.
const Sound = {
  ctx: null,
  master: null,
  noiseBuf: null,
  muted: false,
  volume: 0.35,
  vmul: 1,
  hum: null,

  init() {
    if (this.ctx) {
      if (this.ctx.state === 'suspended') this.ctx.resume();
      return;
    }
    const AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return;
    this.ctx = new AC();
    this.master = this.ctx.createGain();
    this.master.gain.value = this.muted ? 0 : this.volume;
    this.master.connect(this.ctx.destination);

    const len = Math.floor(this.ctx.sampleRate * 1.2);
    this.noiseBuf = this.ctx.createBuffer(1, len, this.ctx.sampleRate);
    const data = this.noiseBuf.getChannelData(0);
    for (let i = 0; i < len; i++) data[i] = Math.random() * 2 - 1;
  },

  setMuted(m) {
    this.muted = m;
    if (this.master) this.master.gain.value = m ? 0 : this.volume;
  },

  tone(freq, dur, type = 'square', vol = 0.25, slideTo = null, delay = 0) {
    if (!this.ctx || this.muted) return;
    const t = this.ctx.currentTime + delay;
    const o = this.ctx.createOscillator();
    const g = this.ctx.createGain();
    o.type = type;
    o.frequency.setValueAtTime(freq, t);
    if (slideTo) o.frequency.exponentialRampToValueAtTime(slideTo, t + dur);
    g.gain.setValueAtTime(vol * this.vmul, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    o.connect(g);
    g.connect(this.master);
    o.start(t);
    o.stop(t + dur + 0.02);
  },

  noise(dur, vol = 0.3, freq = 1500, type = 'lowpass', delay = 0) {
    if (!this.ctx || this.muted) return;
    const t = this.ctx.currentTime + delay;
    const src = this.ctx.createBufferSource();
    src.buffer = this.noiseBuf;
    const f = this.ctx.createBiquadFilter();
    f.type = type;
    f.frequency.value = freq;
    const g = this.ctx.createGain();
    g.gain.setValueAtTime(vol * this.vmul, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    src.connect(f);
    f.connect(g);
    g.connect(this.master);
    src.start(t);
    src.stop(t + dur + 0.02);
  },

  // Low drone while riding the plane.
  setHum(on) {
    if (!this.ctx) return;
    if (on && !this.hum) {
      const o = this.ctx.createOscillator();
      const o2 = this.ctx.createOscillator();
      const g = this.ctx.createGain();
      o.type = 'sawtooth'; o.frequency.value = 55;
      o2.type = 'sawtooth'; o2.frequency.value = 57.5;
      g.gain.value = 0.05;
      const f = this.ctx.createBiquadFilter();
      f.type = 'lowpass'; f.frequency.value = 300;
      o.connect(f); o2.connect(f); f.connect(g); g.connect(this.master);
      o.start(); o2.start();
      this.hum = { o, o2, g };
    } else if (!on && this.hum) {
      const { o, o2, g } = this.hum;
      g.gain.setTargetAtTime(0, this.ctx.currentTime, 0.3);
      o.stop(this.ctx.currentTime + 1.2);
      o2.stop(this.ctx.currentTime + 1.2);
      this.hum = null;
    }
  },

  play(name, vol = 1) {
    if (vol <= 0.03) return;
    this.vmul = vol;
    switch (name) {
      case 'pistol': this.noise(0.12, 0.35, 2200); this.tone(320, 0.08, 'square', 0.1, 90); break;
      case 'smg': this.noise(0.08, 0.28, 2600); this.tone(260, 0.05, 'square', 0.07, 100); break;
      case 'ar': this.noise(0.14, 0.38, 1800); this.tone(180, 0.08, 'sawtooth', 0.1, 70); break;
      case 'lmg': this.noise(0.13, 0.36, 1500); this.tone(150, 0.08, 'sawtooth', 0.1, 60); break;
      case 'dmr': this.noise(0.22, 0.45, 1500); this.tone(140, 0.15, 'sawtooth', 0.12, 50); break;
      case 'sr': this.noise(0.45, 0.6, 1100); this.tone(110, 0.3, 'sawtooth', 0.18, 40); break;
      case 'shotgun': this.noise(0.32, 0.55, 900); this.tone(130, 0.2, 'sawtooth', 0.15, 50); break;
      case 'punch': this.noise(0.08, 0.3, 700); break;
      case 'hit': this.tone(1400, 0.04, 'square', 0.07); break;
      case 'headshot': this.tone(1800, 0.06, 'square', 0.1); this.tone(2400, 0.06, 'square', 0.08, null, 0.04); break;
      case 'kill': this.tone(880, 0.1, 'triangle', 0.18); this.tone(1320, 0.18, 'triangle', 0.18, null, 0.08); break;
      case 'hurt': this.tone(140, 0.18, 'sawtooth', 0.22, 60); this.noise(0.12, 0.18, 500); break;
      case 'pickup': this.tone(660, 0.06, 'sine', 0.15); this.tone(990, 0.08, 'sine', 0.15, null, 0.05); break;
      case 'equip': this.noise(0.1, 0.2, 3000, 'highpass'); this.tone(500, 0.05, 'square', 0.06, null, 0.05); break;
      case 'reload': this.tone(400, 0.05, 'square', 0.07); this.tone(620, 0.05, 'square', 0.07, null, 0.15); break;
      case 'empty': this.tone(900, 0.03, 'square', 0.06); break;
      case 'heal': [520, 660, 780].forEach((f, i) => this.tone(f, 0.12, 'sine', 0.14, null, i * 0.08)); break;
      case 'jump': this.noise(0.8, 0.25, 1200, 'bandpass'); break;
      case 'chute': this.noise(0.5, 0.25, 400); this.tone(200, 0.2, 'triangle', 0.1, 120); break;
      case 'land': this.noise(0.18, 0.35, 400); break;
      case 'throw': this.noise(0.15, 0.15, 2500, 'highpass'); break;
      case 'explosion': this.noise(1.1, 0.8, 500); this.tone(70, 0.8, 'sawtooth', 0.35, 30); break;
      case 'zone': this.tone(220, 0.4, 'triangle', 0.18); this.tone(165, 0.5, 'triangle', 0.18, null, 0.35); break;
      case 'zoneTick': this.tone(110, 0.15, 'sine', 0.12); break;
      case 'airdrop': this.tone(80, 1.5, 'sawtooth', 0.12, 60); this.tone(392, 0.3, 'triangle', 0.15, null, 0.2); break;
      case 'win': [523, 659, 784, 1046, 1318].forEach((f, i) => this.tone(f, 0.3, 'triangle', 0.2, null, i * 0.13)); break;
      case 'over': [440, 330, 220, 110].forEach((f, i) => this.tone(f, 0.35, 'triangle', 0.2, null, i * 0.2)); break;
    }
    this.vmul = 1;
  },
};
