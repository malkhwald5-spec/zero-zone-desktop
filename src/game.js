'use strict';

(() => {
  // ---------- Utilities ----------
  const TAU = Math.PI * 2;
  const WORLD = 2400;
  const rand = (a, b) => a + Math.random() * (b - a);
  const randInt = (a, b) => Math.floor(rand(a, b + 1));
  const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
  const dist2 = (ax, ay, bx, by) => { const dx = ax - bx, dy = ay - by; return dx * dx + dy * dy; };
  const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];

  const $ = (id) => document.getElementById(id);
  const canvas = $('game');
  const ctx = canvas.getContext('2d');
  let W = 0, H = 0;

  function resize() {
    const dpr = window.devicePixelRatio || 1;
    W = window.innerWidth;
    H = window.innerHeight;
    canvas.width = Math.floor(W * dpr);
    canvas.height = Math.floor(H * dpr);
    canvas.style.width = W + 'px';
    canvas.style.height = H + 'px';
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  }
  window.addEventListener('resize', resize);
  resize();

  // ---------- Storage ----------
  const store = {
    get(key, fallback) {
      try { const v = localStorage.getItem(key); return v === null ? fallback : JSON.parse(v); } catch { return fallback; }
    },
    set(key, value) {
      try { localStorage.setItem(key, JSON.stringify(value)); } catch { /* storage unavailable */ }
    },
  };

  // ---------- Definitions ----------
  const WEAPONS = {
    pistol:  { name: 'مسدس',  dmg: 24, rate: 0.26, speed: 950,  spread: 0.03, pellets: 1, mag: 12, reload: 0.9, color: '#ffe680', kick: 2, infinite: true },
    smg:     { name: 'رشاش',  dmg: 14, rate: 0.075, speed: 1050, spread: 0.09, pellets: 1, mag: 32, reload: 1.3, color: '#7cf7ff', kick: 1.5, pickupAmmo: 96, maxReserve: 288 },
    shotgun: { name: 'خرطوش', dmg: 17, rate: 0.7,  speed: 820,  spread: 0.32, pellets: 8, mag: 6,  reload: 1.6, color: '#ffa94d', kick: 7, pickupAmmo: 18, maxReserve: 54 },
  };
  const WEAPON_ORDER = ['pistol', 'smg', 'shotgun'];

  const ENEMIES = {
    runner:  { name: 'عدّاء', hp: 32,  speed: 170, r: 13, dmg: 10, score: 10,  color: '#ff4d6d' },
    brute:   { name: 'ضخم',   hp: 160, speed: 74,  r: 24, dmg: 24, score: 35,  color: '#ff9f1c' },
    shooter: { name: 'قنّاص', hp: 55,  speed: 105, r: 15, dmg: 9,  score: 25,  color: '#b388ff', range: 340, fireRate: 1.8 },
    boss:    { name: 'الحارس', hp: 1100, speed: 62, r: 44, dmg: 35, score: 600, color: '#ff1744', fireRate: 2.1 },
  };

  const ZONE_MAX_R = 1000;
  const ZONE_SHRINK_TIME = 40; // seconds per wave to reach the target radius

  // ---------- Input ----------
  const keys = new Set();
  const mouse = { x: 0, y: 0, down: false };

  window.addEventListener('keydown', (e) => {
    if (e.repeat) { if (state === 'playing') e.preventDefault(); return; }
    keys.add(e.code);
    Sound.init();
    if (e.code === 'KeyM') toggleMute();
    if (state === 'playing') {
      if (e.code === 'Escape' || e.code === 'KeyP') pauseGame();
      else if (e.code === 'KeyR') startReload();
      else if (e.code === 'Digit1') switchWeapon('pistol');
      else if (e.code === 'Digit2') switchWeapon('smg');
      else if (e.code === 'Digit3') switchWeapon('shotgun');
      else if (e.code === 'ShiftLeft' || e.code === 'ShiftRight' || e.code === 'Space') tryDash();
      if (e.code === 'Space') e.preventDefault();
    } else if (state === 'paused' && (e.code === 'Escape' || e.code === 'KeyP')) {
      resumeGame();
    }
  });
  window.addEventListener('keyup', (e) => keys.delete(e.code));
  window.addEventListener('mousemove', (e) => { mouse.x = e.clientX; mouse.y = e.clientY; });
  window.addEventListener('mousedown', (e) => { if (e.button === 0) mouse.down = true; Sound.init(); });
  window.addEventListener('mouseup', (e) => { if (e.button === 0) mouse.down = false; });
  window.addEventListener('wheel', (e) => {
    if (state !== 'playing') return;
    cycleWeapon(e.deltaY > 0 ? 1 : -1);
  }, { passive: true });
  window.addEventListener('contextmenu', (e) => e.preventDefault());
  window.addEventListener('blur', () => {
    keys.clear();
    mouse.down = false;
    if (state === 'playing') pauseGame();
  });

  // ---------- Game state ----------
  let state = 'menu'; // menu | playing | paused | over
  let player, enemies, bullets, particles, pickups, texts, spawnMarkers, zone, waveState, cam;
  let score, kills, combo, comboTimer, elapsed, shake, hurtFlash, best;
  best = store.get('zz_best', 0);

  function newPlayer() {
    return {
      x: WORLD / 2, y: WORLD / 2, r: 16,
      hp: 100, maxHp: 100, speed: 260,
      angle: 0,
      weapon: 'pistol',
      ammo: { pistol: { mag: WEAPONS.pistol.mag, reserve: Infinity }, smg: null, shotgun: null },
      fireCd: 0, reloadT: 0,
      dashCd: 0, dashT: 0, dashDx: 0, dashDy: 0,
      invuln: 0,
    };
  }

  function resetGame() {
    player = newPlayer();
    enemies = [];
    bullets = [];
    particles = [];
    pickups = [];
    texts = [];
    spawnMarkers = [];
    zone = { x: WORLD / 2, y: WORLD / 2, r: ZONE_MAX_R, targetR: ZONE_MAX_R, fromX: WORLD / 2, fromY: WORLD / 2, toX: WORLD / 2, toY: WORLD / 2, fromR: ZONE_MAX_R };
    waveState = { n: 0, queue: [], spawnTimer: 0, spawnInterval: 1, intermission: 0, intermissionMax: 0, waveTime: 0, cleared: true };
    cam = { x: player.x - W / 2, y: player.y - H / 2 };
    score = 0; kills = 0; combo = 0; comboTimer = 0; elapsed = 0; shake = 0; hurtFlash = 0;
    // Debug: index.html?wave=5 starts at a later wave.
    const startAt = parseInt(new URLSearchParams(location.search).get('wave'), 10);
    if (startAt > 1) waveState.n = startAt - 1;
    startIntermission(2.5);
    // The first zone is centered on the spawn point.
    zone.toX = player.x; zone.toY = player.y;
  }

  // ---------- Waves & zone ----------
  function startIntermission(duration) {
    waveState.intermission = duration;
    waveState.intermissionMax = duration;
    waveState.cleared = true;
    // Move the zone center and expand it back to full size during the break.
    const nextTarget = zoneTargetFor(waveState.n + 1);
    const margin = nextTarget + 80;
    zone.fromX = zone.x; zone.fromY = zone.y; zone.fromR = zone.r;
    zone.toX = rand(margin, WORLD - margin);
    zone.toY = rand(margin, WORLD - margin);
  }

  function zoneTargetFor(n) {
    return Math.max(210, 640 - n * 32);
  }

  function startWave(n) {
    waveState.n = n;
    waveState.cleared = false;
    waveState.waveTime = 0;
    const count = 6 + Math.floor(n * 3.2);
    const queue = [];
    for (let i = 0; i < count; i++) {
      const roll = Math.random();
      if (n >= 3 && roll < Math.min(0.22, 0.06 + n * 0.015)) queue.push('brute');
      else if (n >= 2 && roll < Math.min(0.5, 0.25 + n * 0.02)) queue.push('shooter');
      else queue.push('runner');
    }
    if (n % 5 === 0) queue.splice(Math.floor(queue.length / 3), 0, 'boss');
    waveState.queue = queue;
    waveState.spawnInterval = Math.max(0.3, 1.15 - n * 0.06);
    waveState.spawnTimer = 0.6;

    zone.x = zone.toX; zone.y = zone.toY; zone.r = ZONE_MAX_R;
    zone.fromR = ZONE_MAX_R;
    zone.targetR = zoneTargetFor(n);

    // Supply crates inside the new zone.
    const crates = n === 1 ? 1 : randInt(1, 2);
    for (let i = 0; i < crates; i++) {
      const pt = randomPointInZone(zone.targetR * 0.8);
      spawnPickup(pt.x, pt.y, 'weapon');
    }

    if (n % 5 === 0) {
      showBanner(`الموجة ${n}`, 'الحارس قادم!');
      Sound.play('boss');
    } else {
      showBanner(`الموجة ${n}`, `${queue.length} أعداء`);
      Sound.play('wave');
    }
  }

  function randomPointInZone(maxR) {
    const a = rand(0, TAU);
    const d = Math.sqrt(Math.random()) * maxR;
    return {
      x: clamp(zone.x + Math.cos(a) * d, 40, WORLD - 40),
      y: clamp(zone.y + Math.sin(a) * d, 40, WORLD - 40),
    };
  }

  function updateWave(dt) {
    if (waveState.intermission > 0) {
      waveState.intermission -= dt;
      const t = 1 - Math.max(0, waveState.intermission) / waveState.intermissionMax;
      const e = t * t * (3 - 2 * t);
      zone.x = zone.fromX + (zone.toX - zone.fromX) * e;
      zone.y = zone.fromY + (zone.toY - zone.fromY) * e;
      zone.r = zone.fromR + (ZONE_MAX_R - zone.fromR) * e;
      if (waveState.intermission <= 0) startWave(waveState.n + 1);
      return;
    }

    waveState.waveTime += dt;
    // Shrink the zone toward the wave target.
    const shrinkSpeed = (ZONE_MAX_R - zone.targetR) / ZONE_SHRINK_TIME;
    zone.r = Math.max(zone.targetR, zone.r - shrinkSpeed * dt);

    // Spawning.
    const cap = 22 + waveState.n * 2;
    waveState.spawnTimer -= dt;
    if (waveState.queue.length && waveState.spawnTimer <= 0 && enemies.length + spawnMarkers.length < cap) {
      waveState.spawnTimer = waveState.spawnInterval * rand(0.6, 1.3);
      const burst = Math.min(waveState.queue.length, waveState.n >= 6 ? randInt(1, 3) : randInt(1, 2));
      for (let i = 0; i < burst; i++) queueSpawn(waveState.queue.shift());
    }

    if (!waveState.queue.length && !enemies.length && !spawnMarkers.length && !waveState.cleared) {
      waveState.cleared = true;
      const bonus = waveState.n * 50;
      score += bonus;
      showBanner('تم تطهير الموجة', `+${bonus} نقطة`);
      Sound.play('clear');
      // Small heal between waves.
      player.hp = Math.min(player.maxHp, player.hp + 15);
      startIntermission(5);
    }
  }

  function queueSpawn(type) {
    let pt = null;
    for (let i = 0; i < 25; i++) {
      const cand = randomPointInZone(Math.max(zone.r - 30, 60));
      if (dist2(cand.x, cand.y, player.x, player.y) > 420 * 420) { pt = cand; break; }
    }
    if (!pt) {
      // Fall back to a ring around the player.
      const a = rand(0, TAU);
      pt = { x: clamp(player.x + Math.cos(a) * 520, 40, WORLD - 40), y: clamp(player.y + Math.sin(a) * 520, 40, WORLD - 40) };
    }
    spawnMarkers.push({ x: pt.x, y: pt.y, type, t: type === 'boss' ? 1.6 : 0.8, max: type === 'boss' ? 1.6 : 0.8 });
  }

  function spawnEnemy(type, x, y) {
    const def = ENEMIES[type];
    const n = waveState.n;
    const hpScale = 1 + (n - 1) * 0.09;
    const speedScale = 1 + Math.min(0.35, (n - 1) * 0.02);
    enemies.push({
      type, x, y,
      r: def.r,
      hp: def.hp * hpScale, maxHp: def.hp * hpScale,
      speed: def.speed * speedScale * (type === 'runner' ? rand(0.9, 1.1) : 1),
      dmg: def.dmg + (type === 'boss' ? 0 : Math.floor(n * 0.6)),
      color: def.color,
      fireCd: def.fireRate ? rand(0.8, def.fireRate) : 0,
      strafe: Math.random() < 0.5 ? 1 : -1,
      kx: 0, ky: 0,
      flash: 0,
      phase: 0,
      wobble: rand(0, TAU),
    });
    burst(x, y, def.color, type === 'boss' ? 40 : 12, 220);
  }

  // ---------- Player actions ----------
  function currentAmmo() { return player.ammo[player.weapon]; }

  function switchWeapon(id) {
    if (!player.ammo[id] || player.weapon === id) return;
    player.weapon = id;
    player.reloadT = 0;
    player.fireCd = Math.max(player.fireCd, 0.15);
    Sound.play('reload');
  }

  function cycleWeapon(dir) {
    const owned = WEAPON_ORDER.filter((w) => player.ammo[w]);
    const idx = owned.indexOf(player.weapon);
    switchWeapon(owned[(idx + dir + owned.length) % owned.length]);
  }

  function startReload() {
    const w = WEAPONS[player.weapon];
    const a = currentAmmo();
    if (player.reloadT > 0 || a.mag >= w.mag) return;
    if (a.reserve <= 0) { Sound.play('empty'); return; }
    player.reloadT = w.reload;
    Sound.play('reload');
  }

  function finishReload() {
    const w = WEAPONS[player.weapon];
    const a = currentAmmo();
    const take = Math.min(w.mag - a.mag, a.reserve);
    a.mag += take;
    if (a.reserve !== Infinity) a.reserve -= take;
  }

  function tryShoot() {
    const w = WEAPONS[player.weapon];
    const a = currentAmmo();
    if (player.reloadT > 0 || player.fireCd > 0) return;
    if (a.mag <= 0) {
      if (a.reserve > 0) startReload();
      else { Sound.play('empty'); player.fireCd = 0.25; switchWeapon('pistol'); }
      return;
    }
    a.mag--;
    player.fireCd = w.rate;
    const mx = player.x + Math.cos(player.angle) * (player.r + 10);
    const my = player.y + Math.sin(player.angle) * (player.r + 10);
    for (let i = 0; i < w.pellets; i++) {
      const ang = player.angle + rand(-w.spread, w.spread);
      const sp = w.speed * (w.pellets > 1 ? rand(0.85, 1.1) : 1);
      bullets.push({ x: mx, y: my, vx: Math.cos(ang) * sp, vy: Math.sin(ang) * sp, dmg: w.dmg, life: w.pellets > 1 ? 0.45 : 0.9, r: 3.5, friendly: true, color: w.color });
    }
    for (let i = 0; i < 5; i++) {
      const ang = player.angle + rand(-0.4, 0.4);
      particles.push({ x: mx, y: my, vx: Math.cos(ang) * rand(80, 260), vy: Math.sin(ang) * rand(80, 260), life: 0.12, max: 0.12, color: w.color, size: 3 });
    }
    shake = Math.min(12, shake + w.kick);
    player.x -= Math.cos(player.angle) * w.kick * 0.6;
    player.y -= Math.sin(player.angle) * w.kick * 0.6;
    Sound.play(player.weapon);
    if (a.mag === 0 && a.reserve > 0) startReload();
  }

  function tryDash() {
    if (player.dashCd > 0) return;
    let dx = 0, dy = 0;
    if (keys.has('KeyW') || keys.has('ArrowUp')) dy -= 1;
    if (keys.has('KeyS') || keys.has('ArrowDown')) dy += 1;
    if (keys.has('KeyA') || keys.has('ArrowLeft')) dx -= 1;
    if (keys.has('KeyD') || keys.has('ArrowRight')) dx += 1;
    if (!dx && !dy) { dx = Math.cos(player.angle); dy = Math.sin(player.angle); }
    const len = Math.hypot(dx, dy);
    player.dashDx = dx / len;
    player.dashDy = dy / len;
    player.dashT = 0.18;
    player.dashCd = 1.4;
    player.invuln = Math.max(player.invuln, 0.25);
    Sound.play('dash');
  }

  function damagePlayer(amount, srcX, srcY) {
    if (player.invuln > 0 || state !== 'playing') return;
    player.hp -= amount;
    player.invuln = 0.45;
    hurtFlash = 0.35;
    shake = Math.min(18, shake + 8);
    combo = 0;
    if (srcX !== undefined) {
      const a = Math.atan2(player.y - srcY, player.x - srcX);
      player.x += Math.cos(a) * 18;
      player.y += Math.sin(a) * 18;
    }
    burst(player.x, player.y, '#ff4060', 10, 200);
    Sound.play('hurt');
    if (player.hp <= 0) gameOver();
  }

  // ---------- Pickups ----------
  function spawnPickup(x, y, type) {
    const p = { x, y, type, life: type === 'weapon' ? 40 : 16, bob: rand(0, TAU) };
    if (type === 'weapon') p.weapon = pick(['smg', 'shotgun']);
    pickups.push(p);
  }

  function collectPickup(p) {
    if (p.type === 'health') {
      if (player.hp >= player.maxHp) return false;
      player.hp = Math.min(player.maxHp, player.hp + 30);
      floatText(p.x, p.y, '+30 صحة', '#7cffb2');
      Sound.play('pickup');
    } else if (p.type === 'ammo') {
      const owned = ['smg', 'shotgun'].filter((w) => player.ammo[w]);
      if (!owned.length) {
        score += 20;
        floatText(p.x, p.y, '+20', '#ffc23d');
      } else {
        owned.forEach((w) => {
          const a = player.ammo[w];
          a.reserve = Math.min(WEAPONS[w].maxReserve, a.reserve + Math.ceil(WEAPONS[w].pickupAmmo / 2));
        });
        floatText(p.x, p.y, 'ذخيرة', '#ffc23d');
      }
      Sound.play('pickup');
    } else if (p.type === 'weapon') {
      const w = WEAPONS[p.weapon];
      const a = player.ammo[p.weapon];
      if (a) {
        a.reserve = Math.min(w.maxReserve, a.reserve + w.pickupAmmo);
        floatText(p.x, p.y, `ذخيرة ${w.name}`, '#36d6ff');
      } else {
        player.ammo[p.weapon] = { mag: w.mag, reserve: w.pickupAmmo };
        floatText(p.x, p.y, `حصلت على ${w.name}!`, '#36d6ff');
        player.weapon = p.weapon;
        player.reloadT = 0;
      }
      Sound.play('weapon');
    }
    return true;
  }

  // ---------- Effects ----------
  function burst(x, y, color, count, speed) {
    for (let i = 0; i < count; i++) {
      const a = rand(0, TAU);
      const s = rand(speed * 0.2, speed);
      const life = rand(0.25, 0.6);
      particles.push({ x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life, max: life, color, size: rand(2, 4.5) });
    }
  }

  function floatText(x, y, text, color, size = 16) {
    texts.push({ x, y, text, color, size, life: 1, max: 1 });
  }

  let bannerTimer = null;
  function showBanner(title, sub) {
    const el = $('banner');
    el.textContent = title;
    if (sub) {
      const s = document.createElement('small');
      s.textContent = sub;
      el.appendChild(s);
    }
    el.classList.add('show');
    clearTimeout(bannerTimer);
    bannerTimer = setTimeout(() => el.classList.remove('show'), 2200);
  }

  // ---------- Update ----------
  function update(dt) {
    elapsed += dt;
    const p = player;

    // Timers
    p.fireCd = Math.max(0, p.fireCd - dt);
    p.dashCd = Math.max(0, p.dashCd - dt);
    p.invuln = Math.max(0, p.invuln - dt);
    hurtFlash = Math.max(0, hurtFlash - dt);
    shake = Math.max(0, shake - dt * 40);
    if (comboTimer > 0) { comboTimer -= dt; if (comboTimer <= 0) combo = 0; }
    if (p.reloadT > 0) { p.reloadT -= dt; if (p.reloadT <= 0) { p.reloadT = 0; finishReload(); } }

    // Movement
    let mx = 0, my = 0;
    if (keys.has('KeyW') || keys.has('ArrowUp')) my -= 1;
    if (keys.has('KeyS') || keys.has('ArrowDown')) my += 1;
    if (keys.has('KeyA') || keys.has('ArrowLeft')) mx -= 1;
    if (keys.has('KeyD') || keys.has('ArrowRight')) mx += 1;
    if (mx || my) { const l = Math.hypot(mx, my); mx /= l; my /= l; }
    if (p.dashT > 0) {
      p.dashT -= dt;
      p.x += p.dashDx * 1100 * dt;
      p.y += p.dashDy * 1100 * dt;
      if (Math.random() < 0.8) particles.push({ x: p.x, y: p.y, vx: 0, vy: 0, life: 0.25, max: 0.25, color: '#36d6ff', size: p.r * 0.8, ghost: true });
    } else {
      p.x += mx * p.speed * dt;
      p.y += my * p.speed * dt;
    }
    p.x = clamp(p.x, p.r, WORLD - p.r);
    p.y = clamp(p.y, p.r, WORLD - p.r);

    // Aim
    const wx = mouse.x + cam.x, wy = mouse.y + cam.y;
    p.angle = Math.atan2(wy - p.y, wx - p.x);
    if (mouse.down) tryShoot();

    // Zone damage
    const outside = Math.sqrt(dist2(p.x, p.y, zone.x, zone.y)) > zone.r;
    $('zone-warning').classList.toggle('hidden', !outside);
    if (outside) {
      p.hp -= (5 + waveState.n * 1.5) * dt;
      hurtFlash = Math.max(hurtFlash, 0.12);
      if (Math.random() < dt * 4) Sound.play('zone');
      if (p.hp <= 0) { gameOver(); return; }
    }

    // Camera
    const tx = p.x - W / 2, ty = p.y - H / 2;
    cam.x += (tx - cam.x) * Math.min(1, dt * 8);
    cam.y += (ty - cam.y) * Math.min(1, dt * 8);

    updateWave(dt);

    // Spawn markers
    for (let i = spawnMarkers.length - 1; i >= 0; i--) {
      const m = spawnMarkers[i];
      m.t -= dt;
      if (m.t <= 0) { spawnEnemy(m.type, m.x, m.y); spawnMarkers.splice(i, 1); }
    }

    updateEnemies(dt);
    updateBullets(dt);

    // Pickups
    for (let i = pickups.length - 1; i >= 0; i--) {
      const pk = pickups[i];
      pk.life -= dt;
      pk.bob += dt * 4;
      if (pk.life <= 0) { pickups.splice(i, 1); continue; }
      const rr = p.r + 18;
      if (dist2(pk.x, pk.y, p.x, p.y) < rr * rr && collectPickup(pk)) pickups.splice(i, 1);
    }

    // Particles & texts
    for (let i = particles.length - 1; i >= 0; i--) {
      const pt = particles[i];
      pt.life -= dt;
      if (pt.life <= 0) { particles.splice(i, 1); continue; }
      pt.x += pt.vx * dt; pt.y += pt.vy * dt;
      pt.vx *= 1 - dt * 4; pt.vy *= 1 - dt * 4;
    }
    for (let i = texts.length - 1; i >= 0; i--) {
      const t = texts[i];
      t.life -= dt;
      t.y -= 40 * dt;
      if (t.life <= 0) texts.splice(i, 1);
    }
  }

  function updateEnemies(dt) {
    const p = player;
    for (const e of enemies) {
      const dx = p.x - e.x, dy = p.y - e.y;
      const d = Math.hypot(dx, dy) || 1;
      const ux = dx / d, uy = dy / d;
      let vx = 0, vy = 0;
      e.flash = Math.max(0, e.flash - dt);
      e.wobble += dt * 6;

      if (e.type === 'shooter') {
        const range = ENEMIES.shooter.range;
        if (d > range) { vx = ux; vy = uy; }
        else if (d < range * 0.6) { vx = -ux; vy = -uy; }
        else { vx = -uy * e.strafe * 0.8; vy = ux * e.strafe * 0.8; if (Math.random() < dt * 0.4) e.strafe *= -1; }
        e.fireCd -= dt;
        if (e.fireCd <= 0 && d < range * 1.5) {
          e.fireCd = ENEMIES.shooter.fireRate * rand(0.8, 1.2);
          enemyShoot(e, Math.atan2(dy, dx) + rand(-0.06, 0.06), 430, e.dmg);
          Sound.play('enemyShot');
        }
      } else if (e.type === 'boss') {
        vx = ux; vy = uy;
        e.fireCd -= dt;
        if (e.fireCd <= 0) {
          e.fireCd = ENEMIES.boss.fireRate * (e.hp < e.maxHp * 0.4 ? 0.65 : 1);
          e.phase++;
          if (e.phase % 2) {
            const n = 18, off = rand(0, TAU);
            for (let i = 0; i < n; i++) enemyShoot(e, off + (i / n) * TAU, 300, 12);
          } else {
            const base = Math.atan2(dy, dx);
            for (let i = -2; i <= 2; i++) enemyShoot(e, base + i * 0.14, 420, 14);
          }
          shake = Math.min(14, shake + 4);
          Sound.play('enemyShot');
        }
      } else {
        // Runners weave a little so they don't stack in a straight line.
        const weave = e.type === 'runner' ? Math.sin(e.wobble) * 0.35 : 0;
        vx = ux - uy * weave; vy = uy + ux * weave;
      }

      e.x += (vx * e.speed + e.kx) * dt;
      e.y += (vy * e.speed + e.ky) * dt;
      e.kx *= 1 - Math.min(1, dt * 10);
      e.ky *= 1 - Math.min(1, dt * 10);
      e.x = clamp(e.x, e.r, WORLD - e.r);
      e.y = clamp(e.y, e.r, WORLD - e.r);

      // Contact damage
      const rr = e.r + p.r;
      if (dist2(e.x, e.y, p.x, p.y) < rr * rr) damagePlayer(e.dmg, e.x, e.y);
    }

    // Separation so enemies don't overlap.
    for (let i = 0; i < enemies.length; i++) {
      const a = enemies[i];
      for (let j = i + 1; j < enemies.length; j++) {
        const b = enemies[j];
        const rr = a.r + b.r;
        const dx = b.x - a.x, dy = b.y - a.y;
        const d2 = dx * dx + dy * dy;
        if (d2 > 0 && d2 < rr * rr) {
          const d = Math.sqrt(d2);
          const push = (rr - d) / 2;
          const wa = b.r / rr, wb = a.r / rr; // lighter enemies get pushed more
          a.x -= (dx / d) * push * wa * 2; a.y -= (dy / d) * push * wa * 2;
          b.x += (dx / d) * push * wb * 2; b.y += (dy / d) * push * wb * 2;
        }
      }
    }
  }

  function enemyShoot(e, ang, speed, dmg) {
    bullets.push({
      x: e.x + Math.cos(ang) * e.r, y: e.y + Math.sin(ang) * e.r,
      vx: Math.cos(ang) * speed, vy: Math.sin(ang) * speed,
      dmg, life: 3, r: 5, friendly: false, color: e.type === 'boss' ? '#ff5c7a' : '#d6a6ff',
    });
  }

  function updateBullets(dt) {
    for (let i = bullets.length - 1; i >= 0; i--) {
      const b = bullets[i];
      b.x += b.vx * dt; b.y += b.vy * dt;
      b.life -= dt;
      let dead = b.life <= 0 || b.x < 0 || b.y < 0 || b.x > WORLD || b.y > WORLD;

      if (!dead && b.friendly) {
        for (let j = 0; j < enemies.length; j++) {
          const e = enemies[j];
          const rr = e.r + b.r;
          if (dist2(b.x, b.y, e.x, e.y) < rr * rr) {
            hitEnemy(e, j, b);
            dead = true;
            break;
          }
        }
      } else if (!dead) {
        const rr = player.r + b.r - 3;
        if (dist2(b.x, b.y, player.x, player.y) < rr * rr) {
          damagePlayer(b.dmg, b.x - b.vx, b.y - b.vy);
          dead = true;
        }
      }

      if (dead) bullets.splice(i, 1);
    }
  }

  function hitEnemy(e, index, b) {
    e.hp -= b.dmg;
    e.flash = 0.08;
    const sp = Math.hypot(b.vx, b.vy) || 1;
    const kb = e.type === 'boss' ? 20 : e.type === 'brute' ? 90 : 260;
    e.kx += (b.vx / sp) * kb;
    e.ky += (b.vy / sp) * kb;
    for (let k = 0; k < 3; k++) {
      particles.push({ x: b.x, y: b.y, vx: -b.vx * rand(0.05, 0.25) + rand(-60, 60), vy: -b.vy * rand(0.05, 0.25) + rand(-60, 60), life: 0.2, max: 0.2, color: e.color, size: 2.5 });
    }
    Sound.play('hit');
    if (e.hp <= 0) killEnemy(e, index);
  }

  function killEnemy(e, index) {
    enemies.splice(index, 1);
    kills++;
    combo++;
    comboTimer = 2.5;
    const mult = comboMultiplier();
    const pts = Math.round(ENEMIES[e.type].score * mult);
    score += pts;
    floatText(e.x, e.y - e.r, `+${pts}`, mult > 1 ? '#ffc23d' : '#ffffff', e.type === 'boss' ? 26 : 15);
    burst(e.x, e.y, e.color, e.type === 'boss' ? 80 : e.type === 'brute' ? 26 : 16, e.type === 'boss' ? 420 : 260);
    shake = Math.min(20, shake + (e.type === 'boss' ? 18 : 3));
    Sound.play('kill');

    if (e.type === 'boss') {
      showBanner('سقط الحارس!', `+${pts} نقطة`);
      spawnPickup(e.x - 30, e.y, 'health');
      spawnPickup(e.x + 30, e.y, 'ammo');
      spawnPickup(e.x, e.y + 30, 'weapon');
      return;
    }
    const roll = Math.random();
    const healthChance = player.hp < 40 ? 0.14 : 0.07;
    if (roll < healthChance) spawnPickup(e.x, e.y, 'health');
    else if (roll < healthChance + (e.type === 'brute' ? 0.3 : 0.1)) spawnPickup(e.x, e.y, 'ammo');
  }

  function comboMultiplier() {
    return 1 + Math.min(3, Math.floor(combo / 5)) * 0.5;
  }

  // ---------- Rendering ----------
  function render() {
    ctx.fillStyle = '#07090f';
    ctx.fillRect(0, 0, W, H);
    if (!player) { drawMenuBackdrop(); return; }

    const sx = shake ? rand(-shake, shake) * 0.5 : 0;
    const sy = shake ? rand(-shake, shake) * 0.5 : 0;
    const ox = Math.round(-cam.x + sx), oy = Math.round(-cam.y + sy);

    ctx.save();
    ctx.translate(ox, oy);
    drawGrid();
    drawZone();
    drawSpawnMarkers();
    drawPickups();
    drawParticles(true);
    drawEnemies();
    drawPlayer();
    drawBullets();
    drawParticles(false);
    drawTexts();
    ctx.restore();

    drawVignette();
    drawMinimap();
    if (state === 'playing') drawCrosshair();
  }

  function drawGrid() {
    const step = 80;
    const x0 = Math.max(0, Math.floor(cam.x / step) * step);
    const y0 = Math.max(0, Math.floor(cam.y / step) * step);
    const x1 = Math.min(WORLD, cam.x + W + step);
    const y1 = Math.min(WORLD, cam.y + H + step);
    ctx.fillStyle = '#0c111c';
    ctx.fillRect(0, 0, WORLD, WORLD);
    ctx.strokeStyle = 'rgba(80, 140, 200, 0.07)';
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (let x = x0; x <= x1; x += step) { ctx.moveTo(x, Math.max(0, cam.y)); ctx.lineTo(x, y1); }
    for (let y = y0; y <= y1; y += step) { ctx.moveTo(Math.max(0, cam.x), y); ctx.lineTo(x1, y); }
    ctx.stroke();
    ctx.strokeStyle = 'rgba(54, 214, 255, 0.5)';
    ctx.lineWidth = 4;
    ctx.strokeRect(0, 0, WORLD, WORLD);
  }

  function drawZone() {
    // Darken/redden everything outside the safe circle.
    ctx.save();
    ctx.beginPath();
    ctx.rect(cam.x - 50, cam.y - 50, W + 100, H + 100);
    ctx.arc(zone.x, zone.y, zone.r, 0, TAU, true);
    ctx.fillStyle = 'rgba(160, 10, 40, 0.22)';
    ctx.fill('evenodd');
    ctx.restore();

    const pulse = 0.6 + Math.sin(elapsed * 5) * 0.25;
    ctx.strokeStyle = `rgba(255, 61, 90, ${pulse})`;
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.arc(zone.x, zone.y, zone.r, 0, TAU);
    ctx.stroke();

    // Next target ring while shrinking.
    if (waveState.intermission <= 0 && zone.r > zone.targetR + 1) {
      ctx.setLineDash([14, 12]);
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.35)';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(zone.x, zone.y, zone.targetR, 0, TAU);
      ctx.stroke();
      ctx.setLineDash([]);
    }
  }

  function drawSpawnMarkers() {
    for (const m of spawnMarkers) {
      const t = 1 - m.t / m.max;
      const r = ENEMIES[m.type].r * (1.8 - t * 0.8);
      ctx.strokeStyle = `rgba(255, 60, 90, ${0.3 + t * 0.6})`;
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(m.x, m.y, r, 0, TAU);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(m.x - r * 0.5, m.y - r * 0.5); ctx.lineTo(m.x + r * 0.5, m.y + r * 0.5);
      ctx.moveTo(m.x + r * 0.5, m.y - r * 0.5); ctx.lineTo(m.x - r * 0.5, m.y + r * 0.5);
      ctx.stroke();
    }
  }

  function drawPickups() {
    for (const pk of pickups) {
      if (pk.life < 4 && Math.floor(pk.life * 8) % 2 === 0) continue; // blink before expiring
      const y = pk.y + Math.sin(pk.bob) * 3;
      ctx.save();
      ctx.translate(pk.x, y);
      if (pk.type === 'health') {
        glow('#3dff8b', 14);
        ctx.fillStyle = '#123d25';
        roundRect(-12, -12, 24, 24, 5); ctx.fill();
        ctx.fillStyle = '#3dff8b';
        ctx.fillRect(-3, -8, 6, 16); ctx.fillRect(-8, -3, 16, 6);
      } else if (pk.type === 'ammo') {
        glow('#ffc23d', 14);
        ctx.fillStyle = '#3d2f0f';
        roundRect(-12, -10, 24, 20, 4); ctx.fill();
        ctx.fillStyle = '#ffc23d';
        for (let i = -1; i <= 1; i++) ctx.fillRect(i * 6 - 2, -6, 4, 12);
      } else {
        glow('#36d6ff', 18);
        ctx.rotate(Math.sin(pk.bob * 0.5) * 0.15);
        ctx.fillStyle = '#0f2c3a';
        roundRect(-16, -13, 32, 26, 4); ctx.fill();
        ctx.strokeStyle = '#36d6ff';
        ctx.lineWidth = 2;
        roundRect(-16, -13, 32, 26, 4); ctx.stroke();
        ctx.fillStyle = WEAPONS[pk.weapon].color;
        ctx.fillRect(-9, -3, 18, 6);
        ctx.fillRect(-9, -3, 5, 10);
      }
      ctx.restore();
    }
    ctx.shadowBlur = 0;
  }

  function glow(color, blur) { ctx.shadowColor = color; ctx.shadowBlur = blur; }

  function roundRect(x, y, w, h, r) {
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
  }

  function drawEnemies() {
    for (const e of enemies) {
      if (e.x < cam.x - 100 || e.x > cam.x + W + 100 || e.y < cam.y - 100 || e.y > cam.y + H + 100) continue;
      const ang = Math.atan2(player.y - e.y, player.x - e.x);
      ctx.save();
      ctx.translate(e.x, e.y);
      ctx.fillStyle = e.flash > 0 ? '#ffffff' : e.color;
      glow(e.color, e.type === 'boss' ? 30 : 12);

      if (e.type === 'runner') {
        ctx.rotate(ang);
        ctx.beginPath();
        ctx.moveTo(e.r + 4, 0);
        ctx.lineTo(-e.r, -e.r * 0.85);
        ctx.lineTo(-e.r * 0.5, 0);
        ctx.lineTo(-e.r, e.r * 0.85);
        ctx.closePath();
        ctx.fill();
      } else if (e.type === 'brute') {
        ctx.rotate(ang);
        roundRect(-e.r, -e.r, e.r * 2, e.r * 2, 6);
        ctx.fill();
        ctx.shadowBlur = 0;
        ctx.fillStyle = 'rgba(0,0,0,0.35)';
        ctx.fillRect(e.r * 0.2, -e.r * 0.5, e.r * 0.5, e.r);
      } else if (e.type === 'shooter') {
        ctx.rotate(ang);
        ctx.beginPath();
        for (let i = 0; i < 6; i++) {
          const a = (i / 6) * TAU;
          ctx.lineTo(Math.cos(a) * e.r, Math.sin(a) * e.r);
        }
        ctx.closePath();
        ctx.fill();
        ctx.fillStyle = '#2a1a4a';
        ctx.fillRect(e.r * 0.3, -3, e.r * 0.9, 6);
      } else {
        ctx.rotate(elapsed * 0.8);
        ctx.beginPath();
        for (let i = 0; i < 16; i++) {
          const a = (i / 16) * TAU;
          const rr = i % 2 ? e.r * 0.78 : e.r;
          ctx.lineTo(Math.cos(a) * rr, Math.sin(a) * rr);
        }
        ctx.closePath();
        ctx.fill();
        ctx.shadowBlur = 0;
        ctx.fillStyle = '#1a0006';
        ctx.beginPath(); ctx.arc(0, 0, e.r * 0.45, 0, TAU); ctx.fill();
        ctx.fillStyle = '#ff8a9e';
        ctx.beginPath(); ctx.arc(0, 0, e.r * 0.2 + Math.sin(elapsed * 6) * 3, 0, TAU); ctx.fill();
      }
      ctx.restore();

      // Health bar for damaged enemies.
      if (e.hp < e.maxHp) {
        const bw = e.type === 'boss' ? 110 : e.r * 2.2;
        const by = e.y - e.r - 12;
        ctx.fillStyle = 'rgba(0,0,0,0.6)';
        ctx.fillRect(e.x - bw / 2, by, bw, 4);
        ctx.fillStyle = e.type === 'boss' ? '#ff1744' : '#ff6b81';
        ctx.fillRect(e.x - bw / 2, by, bw * Math.max(0, e.hp / e.maxHp), 4);
      }
    }
    ctx.shadowBlur = 0;
  }

  function drawPlayer() {
    const p = player;
    if (p.invuln > 0 && p.dashT <= 0 && Math.floor(p.invuln * 20) % 2 === 0) return;
    ctx.save();
    ctx.translate(p.x, p.y);
    ctx.rotate(p.angle);
    glow('#36d6ff', 20);
    // Gun
    const w = WEAPONS[p.weapon];
    ctx.fillStyle = '#9fb3c8';
    const gunLen = p.weapon === 'shotgun' ? 22 : p.weapon === 'smg' ? 18 : 13;
    ctx.fillRect(p.r - 4, -3.5, gunLen, 7);
    ctx.fillStyle = w.color;
    ctx.fillRect(p.r - 4 + gunLen - 3, -3.5, 3, 7);
    // Body
    ctx.fillStyle = '#36d6ff';
    ctx.beginPath(); ctx.arc(0, 0, p.r, 0, TAU); ctx.fill();
    ctx.shadowBlur = 0;
    ctx.fillStyle = '#0a2a38';
    ctx.beginPath(); ctx.arc(0, 0, p.r * 0.55, 0, TAU); ctx.fill();
    ctx.fillStyle = '#e8fbff';
    ctx.beginPath(); ctx.arc(p.r * 0.35, 0, 3.5, 0, TAU); ctx.fill();
    ctx.restore();

    // Reload ring
    if (p.reloadT > 0) {
      const t = 1 - p.reloadT / w.reload;
      ctx.strokeStyle = '#ffc23d';
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(p.x, p.y, p.r + 8, -Math.PI / 2, -Math.PI / 2 + t * TAU);
      ctx.stroke();
    }
  }

  function drawBullets() {
    ctx.lineCap = 'round';
    for (const b of bullets) {
      ctx.strokeStyle = b.color;
      ctx.lineWidth = b.r * (b.friendly ? 1.2 : 1.6);
      glow(b.color, 8);
      ctx.beginPath();
      ctx.moveTo(b.x, b.y);
      ctx.lineTo(b.x - b.vx * 0.018, b.y - b.vy * 0.018);
      ctx.stroke();
    }
    ctx.shadowBlur = 0;
    ctx.lineCap = 'butt';
  }

  function drawParticles(ghosts) {
    for (const pt of particles) {
      if (!!pt.ghost !== ghosts) continue;
      const a = pt.life / pt.max;
      ctx.globalAlpha = ghosts ? a * 0.35 : a;
      ctx.fillStyle = pt.color;
      if (ghosts) {
        ctx.beginPath(); ctx.arc(pt.x, pt.y, pt.size, 0, TAU); ctx.fill();
      } else {
        ctx.fillRect(pt.x - pt.size / 2, pt.y - pt.size / 2, pt.size, pt.size);
      }
    }
    ctx.globalAlpha = 1;
  }

  function drawTexts() {
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    for (const t of texts) {
      ctx.globalAlpha = Math.min(1, t.life / t.max * 1.5);
      ctx.font = `bold ${t.size}px "Segoe UI", Tahoma, sans-serif`;
      ctx.direction = t.text[0] === '+' ? 'ltr' : 'rtl';
      ctx.fillStyle = 'rgba(0,0,0,0.6)';
      ctx.fillText(t.text, t.x + 1, t.y + 1);
      ctx.fillStyle = t.color;
      ctx.fillText(t.text, t.x, t.y);
    }
    ctx.globalAlpha = 1;
    ctx.direction = 'inherit';
  }

  function drawVignette() {
    const lowHp = player.hp / player.maxHp < 0.3;
    const intensity = Math.max(hurtFlash * 1.6, lowHp ? 0.25 + Math.sin(elapsed * 6) * 0.1 : 0);
    if (intensity <= 0) return;
    const g = ctx.createRadialGradient(W / 2, H / 2, Math.min(W, H) * 0.3, W / 2, H / 2, Math.max(W, H) * 0.7);
    g.addColorStop(0, 'rgba(255, 0, 40, 0)');
    g.addColorStop(1, `rgba(255, 0, 40, ${Math.min(0.7, intensity)})`);
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, W, H);
  }

  function drawMinimap() {
    const size = 160, pad = 16;
    const x = pad, y = pad;
    const s = size / WORLD;
    ctx.fillStyle = 'rgba(12, 18, 30, 0.8)';
    ctx.fillRect(x, y, size, size);
    ctx.strokeStyle = 'rgba(80, 200, 255, 0.35)';
    ctx.lineWidth = 1;
    ctx.strokeRect(x + 0.5, y + 0.5, size - 1, size - 1);

    ctx.save();
    ctx.beginPath(); ctx.rect(x, y, size, size); ctx.clip();
    ctx.strokeStyle = '#ff3d5a';
    ctx.lineWidth = 1.5;
    ctx.beginPath(); ctx.arc(x + zone.x * s, y + zone.y * s, zone.r * s, 0, TAU); ctx.stroke();
    if (waveState.intermission > 0) {
      ctx.setLineDash([3, 3]);
      ctx.strokeStyle = 'rgba(255,255,255,0.5)';
      ctx.beginPath(); ctx.arc(x + zone.toX * s, y + zone.toY * s, ZONE_MAX_R * s, 0, TAU); ctx.stroke();
      ctx.setLineDash([]);
    }
    for (const e of enemies) {
      ctx.fillStyle = e.color;
      const r = e.type === 'boss' ? 4 : 1.8;
      ctx.fillRect(x + e.x * s - r, y + e.y * s - r, r * 2, r * 2);
    }
    for (const pk of pickups) {
      ctx.fillStyle = pk.type === 'health' ? '#3dff8b' : pk.type === 'ammo' ? '#ffc23d' : '#36d6ff';
      ctx.fillRect(x + pk.x * s - 2, y + pk.y * s - 2, 4, 4);
    }
    ctx.fillStyle = '#ffffff';
    ctx.beginPath(); ctx.arc(x + player.x * s, y + player.y * s, 3, 0, TAU); ctx.fill();
    ctx.strokeStyle = 'rgba(255,255,255,0.25)';
    ctx.strokeRect(x + cam.x * s, y + cam.y * s, W * s, H * s);
    ctx.restore();
  }

  function drawCrosshair() {
    const { x, y } = mouse;
    const spread = WEAPONS[player.weapon].spread * 60 + 6 + (player.fireCd > 0 ? 3 : 0);
    ctx.strokeStyle = player.reloadT > 0 ? '#ffc23d' : '#ffffff';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(x - spread - 7, y); ctx.lineTo(x - spread, y);
    ctx.moveTo(x + spread, y); ctx.lineTo(x + spread + 7, y);
    ctx.moveTo(x, y - spread - 7); ctx.lineTo(x, y - spread);
    ctx.moveTo(x, y + spread); ctx.lineTo(x, y + spread + 7);
    ctx.stroke();
    ctx.fillStyle = '#ff3d5a';
    ctx.fillRect(x - 1.5, y - 1.5, 3, 3);
  }

  // Animated background behind the main menu.
  const menuDots = Array.from({ length: 70 }, () => ({ x: Math.random(), y: Math.random(), s: rand(0.02, 0.08), r: rand(1, 2.5) }));
  let menuT = 0;
  function drawMenuBackdrop() {
    menuT += 1 / 60;
    const cx = W / 2, cy = H / 2;
    const r = Math.min(W, H) * (0.33 + Math.sin(menuT * 0.7) * 0.03);
    ctx.strokeStyle = 'rgba(255, 61, 90, 0.35)';
    ctx.lineWidth = 3;
    ctx.beginPath(); ctx.arc(cx, cy, r, 0, TAU); ctx.stroke();
    ctx.strokeStyle = 'rgba(54, 214, 255, 0.08)';
    ctx.lineWidth = 1;
    for (let i = 0; i < 6; i++) {
      ctx.beginPath(); ctx.arc(cx, cy, r * (0.4 + i * 0.25) + ((menuT * 30) % 60), 0, TAU); ctx.stroke();
    }
    ctx.fillStyle = 'rgba(54, 214, 255, 0.5)';
    for (const d of menuDots) {
      d.y -= d.s / 60;
      if (d.y < 0) d.y = 1;
      ctx.fillRect(d.x * W, d.y * H, d.r, d.r);
    }
  }

  // ---------- HUD ----------
  const hud = {
    score: $('hud-score'), combo: $('hud-combo'), wave: $('hud-wave'), enemies: $('hud-enemies'), zone: $('hud-zone'),
    hp: $('hud-hp'), hpFill: $('hud-hp-fill'), weapon: $('hud-weapon'), ammo: $('hud-ammo'), reload: $('hud-reload'), dash: $('hud-dash'),
    slots: document.querySelectorAll('.slot'),
  };
  const hudCache = {};
  function setText(el, key, value) {
    if (hudCache[key] !== value) { hudCache[key] = value; el.textContent = value; }
  }

  function updateHud() {
    const p = player;
    setText(hud.score, 'score', score.toLocaleString('en-US'));
    const mult = comboMultiplier();
    setText(hud.combo, 'combo', mult > 1 ? `×${mult}` : '');
    setText(hud.wave, 'wave', String(Math.max(1, waveState.n)));
    setText(hud.enemies, 'enemies', String(enemies.length + spawnMarkers.length + waveState.queue.length));
    let zoneText;
    if (waveState.intermission > 0) zoneText = `استراحة ${Math.ceil(waveState.intermission)}`;
    else if (zone.r > zone.targetR + 1) zoneText = 'تتقلص…';
    else zoneText = 'مستقرة';
    setText(hud.zone, 'zone', zoneText);

    const hp = Math.max(0, Math.ceil(p.hp));
    setText(hud.hp, 'hp', String(hp));
    hud.hpFill.style.width = `${(hp / p.maxHp) * 100}%`;
    hud.hpFill.classList.toggle('low', hp / p.maxHp < 0.3);

    const w = WEAPONS[p.weapon];
    const a = currentAmmo();
    setText(hud.weapon, 'weapon', w.name);
    setText(hud.ammo, 'ammo', p.reloadT > 0 ? 'إعادة تلقيم…' : `${a.mag} / ${a.reserve === Infinity ? '∞' : a.reserve}`);
    hud.reload.style.width = p.reloadT > 0 ? `${(1 - p.reloadT / w.reload) * 100}%` : '0%';
    hud.dash.style.width = `${(1 - p.dashCd / 1.4) * 100}%`;

    hud.slots.forEach((el) => {
      const id = el.dataset.weapon;
      el.classList.toggle('owned', !!p.ammo[id]);
      el.classList.toggle('active', p.weapon === id);
    });
  }

  // ---------- State transitions ----------
  const overlays = ['menu', 'help', 'pause', 'gameover'];
  function showOverlay(id) {
    overlays.forEach((o) => $(o).classList.toggle('hidden', o !== id));
  }

  function startGame() {
    Sound.init();
    if (document.activeElement) document.activeElement.blur();
    resetGame();
    state = 'playing';
    showOverlay(null);
    $('hud').classList.remove('hidden');
    $('zone-warning').classList.add('hidden');
    document.body.classList.add('playing');
    Object.keys(hudCache).forEach((k) => delete hudCache[k]);
  }

  function pauseGame() {
    if (state !== 'playing') return;
    state = 'paused';
    mouse.down = false;
    shake = 0;
    showOverlay('pause');
    document.body.classList.remove('playing');
  }

  function resumeGame() {
    if (state !== 'paused') return;
    state = 'playing';
    showOverlay(null);
    document.body.classList.add('playing');
    lastTime = performance.now();
  }

  function gameOver() {
    if (state !== 'playing') return;
    state = 'over';
    mouse.down = false;
    player.hp = 0;
    burst(player.x, player.y, '#36d6ff', 60, 400);
    Sound.play('over');
    const isRecord = score > best;
    if (isRecord) { best = score; store.set('zz_best', best); }
    $('go-score').textContent = score.toLocaleString('en-US');
    $('go-wave').textContent = String(waveState.n);
    $('go-kills').textContent = String(kills);
    const secs = Math.floor(elapsed);
    $('go-time').textContent = `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, '0')}`;
    $('go-best').textContent = best.toLocaleString('en-US');
    $('new-record').classList.toggle('hidden', !isRecord);
    document.body.classList.remove('playing');
    $('zone-warning').classList.add('hidden');
    // Let the death burst play briefly before the results appear.
    setTimeout(() => { if (state === 'over') showOverlay('gameover'); }, 900);
  }

  function goToMenu() {
    state = 'menu';
    player = null;
    $('hud').classList.add('hidden');
    document.body.classList.remove('playing');
    $('menu-best').textContent = best.toLocaleString('en-US');
    showOverlay('menu');
  }

  function toggleMute() {
    Sound.setMuted(!Sound.muted);
    store.set('zz_muted', Sound.muted);
    $('btn-sound').textContent = Sound.muted ? 'الصوت: مكتوم' : 'الصوت: يعمل';
  }

  // ---------- Buttons ----------
  $('btn-start').addEventListener('click', startGame);
  $('btn-help').addEventListener('click', () => showOverlay('help'));
  $('btn-help-back').addEventListener('click', () => showOverlay('menu'));
  $('btn-sound').addEventListener('click', () => { Sound.init(); toggleMute(); });
  $('btn-quit').addEventListener('click', () => window.close());
  $('btn-resume').addEventListener('click', resumeGame);
  $('btn-restart').addEventListener('click', startGame);
  $('btn-menu').addEventListener('click', goToMenu);
  $('btn-again').addEventListener('click', startGame);
  $('btn-go-menu').addEventListener('click', goToMenu);

  if (store.get('zz_muted', false)) toggleMute();
  $('menu-best').textContent = best.toLocaleString('en-US');

  // ---------- Main loop ----------
  let lastTime = performance.now();
  function frame(now) {
    const dt = Math.min(0.05, (now - lastTime) / 1000);
    lastTime = now;
    if (state === 'playing') {
      update(dt);
      if (state === 'playing') updateHud();
    } else if (state === 'over') {
      // Keep effects animating behind the game-over screen.
      for (let i = particles.length - 1; i >= 0; i--) {
        const pt = particles[i];
        pt.life -= dt;
        if (pt.life <= 0) { particles.splice(i, 1); continue; }
        pt.x += pt.vx * dt; pt.y += pt.vy * dt;
      }
      shake = Math.max(0, shake - dt * 40);
    }
    render();
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);

  // Read-only hook used by automated smoke tests.
  window.__zeroZone = {
    get state() { return state; },
    get score() { return score; },
    get wave() { return waveState ? waveState.n : 0; },
    get enemies() { return enemies ? enemies.length : 0; },
    get player() { return player ? { x: player.x, y: player.y, hp: player.hp, weapon: player.weapon } : null; },
    get nearestEnemy() {
      if (!player || !enemies || !enemies.length) return null;
      let best = null, bd = Infinity;
      for (const e of enemies) { const d = dist2(e.x, e.y, player.x, player.y); if (d < bd) { bd = d; best = e; } }
      return { x: best.x - cam.x, y: best.y - cam.y, type: best.type };
    },
  };
})();
