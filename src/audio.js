'use strict';

// Synthesized sound effects (Web Audio) so the game ships without audio assets.
const Sound = {
  ctx: null,
  master: null,
  noiseBuf: null,
  muted: false,
  volume: 0.35,

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

    const len = Math.floor(this.ctx.sampleRate * 0.6);
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
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    o.connect(g);
    g.connect(this.master);
    o.start(t);
    o.stop(t + dur + 0.02);
  },

  noise(dur, vol = 0.3, freq = 1500, type = 'lowpass') {
    if (!this.ctx || this.muted) return;
    const t = this.ctx.currentTime;
    const src = this.ctx.createBufferSource();
    src.buffer = this.noiseBuf;
    const f = this.ctx.createBiquadFilter();
    f.type = type;
    f.frequency.value = freq;
    const g = this.ctx.createGain();
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.001, t + dur);
    src.connect(f);
    f.connect(g);
    g.connect(this.master);
    src.start(t);
    src.stop(t + dur + 0.02);
  },

  play(name) {
    switch (name) {
      case 'pistol': this.noise(0.12, 0.35, 2200); this.tone(320, 0.08, 'square', 0.12, 90); break;
      case 'smg': this.noise(0.07, 0.25, 2800); this.tone(260, 0.05, 'square', 0.07, 100); break;
      case 'shotgun': this.noise(0.3, 0.5, 900); this.tone(140, 0.2, 'sawtooth', 0.15, 50); break;
      case 'enemyShot': this.tone(700, 0.12, 'triangle', 0.08, 300); break;
      case 'hit': this.tone(180, 0.05, 'square', 0.08, 120); break;
      case 'kill': this.noise(0.18, 0.25, 600); this.tone(220, 0.15, 'triangle', 0.15, 60); break;
      case 'hurt': this.tone(140, 0.2, 'sawtooth', 0.25, 60); this.noise(0.15, 0.2, 500); break;
      case 'pickup': this.tone(660, 0.08, 'sine', 0.2); this.tone(990, 0.12, 'sine', 0.2, null, 0.07); break;
      case 'weapon': [520, 660, 880].forEach((f, i) => this.tone(f, 0.1, 'square', 0.12, null, i * 0.06)); break;
      case 'reload': this.tone(400, 0.05, 'square', 0.08); this.tone(600, 0.05, 'square', 0.08, null, 0.12); break;
      case 'empty': this.tone(900, 0.03, 'square', 0.06); break;
      case 'dash': this.noise(0.2, 0.18, 3000, 'highpass'); break;
      case 'wave': [330, 440, 550].forEach((f, i) => this.tone(f, 0.25, 'triangle', 0.18, null, i * 0.12)); break;
      case 'clear': [523, 659, 784, 1046].forEach((f, i) => this.tone(f, 0.18, 'square', 0.1, null, i * 0.08)); break;
      case 'boss': this.tone(80, 1.2, 'sawtooth', 0.3, 40); this.noise(1.0, 0.2, 300); break;
      case 'zone': this.tone(110, 0.15, 'sine', 0.15); break;
      case 'over': [440, 330, 220, 110].forEach((f, i) => this.tone(f, 0.35, 'triangle', 0.2, null, i * 0.2)); break;
    }
  },
};
