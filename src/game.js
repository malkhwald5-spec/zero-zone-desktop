'use strict';

(() => {
  const ZZ = window.ZZ;
  const { WEAPONS, AMMO, AMMO_CAP, MEDS, MED_ORDER, VEST, HELMET, PACK, FISTS, ZONE_PHASES } = ZZ;
  const M = ZZ.Map;

  // ---------- Utilities ----------
  const TAU = Math.PI * 2;
  const rand = (a, b) => a + Math.random() * (b - a);
  const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
  const lerp = (a, b, t) => a + (b - a) * t;
  const fmtTime = (s) => { s = Math.max(0, Math.ceil(s)); return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`; };
  const $ = (id) => document.getElementById(id);
  const params = new URLSearchParams(location.search);
  const DEBUG = {
    god: params.get('god') === '1',
    speed: clamp(parseFloat(params.get('speed')) || 1, 0.25, 20),
    seed: parseInt(params.get('seed'), 10) || 0,
    bots: parseInt(params.get('bots'), 10) || 0,
  };

  const canvas = $('game');
  const ctx = canvas.getContext('2d');
  let W = 0, H = 0, DPR = 1;
  function resize() {
    DPR = window.devicePixelRatio || 1;
    W = window.innerWidth;
    H = window.innerHeight;
    canvas.width = Math.floor(W * DPR);
    canvas.height = Math.floor(H * DPR);
    canvas.style.width = W + 'px';
    canvas.style.height = H + 'px';
  }
  window.addEventListener('resize', resize);
  resize();

  const store = {
    get(key, fallback) { try { const v = localStorage.getItem(key); return v === null ? fallback : JSON.parse(v); } catch { return fallback; } },
    set(key, value) { try { localStorage.setItem(key, JSON.stringify(value)); } catch { /* storage unavailable */ } },
  };

  const DIFFICULTY = {
    easy: { skill: [0.1, 0.45] },
    normal: { skill: [0.3, 0.72] },
    hard: { skill: [0.55, 0.95] },
  };
  let difficulty = store.get('zz_diff', 'normal');
  if (!DIFFICULTY[difficulty]) difficulty = 'normal';

  // ---------- Input ----------
  const keys = new Set();
  const mouse = { x: W / 2, y: H / 2, down: false, right: false };
  let shotQueueT = 0;

  // ---------- Game state ----------
  // G is the shared world object; bots act through the same functions as the player.
  const G = {
    time: 0, map: null, units: [], items: [], bullets: [], grenades: [], particles: [], decals: [], texts: [],
    zone: null, plane: null, airdrops: [], player: null, killfeed: [],
  };
  let state = 'menu'; // menu | playing | paused | over
  let cam = { x: 2500, y: 2500, scale: 1 };
  let shake = 0, hurtT = 0, hitMarkT = 0, hitMarkHead = false;
  let dmgIndicators = [];
  let mapOpen = false, marker = null;
  let roofAlpha = [];
  let nextItemId = 1, nextUnitId = 1;
  let matchResult = null;
  let alivePrev = 0;

  // ---------- Units ----------
  const CLOTHES = ['#5b6b4a', '#6b5a48', '#3f4f5f', '#704848', '#56565e', '#7a6a3a', '#4a5d6b', '#5e4a6b'];

  function makeUnit(name, isPlayer, skill) {
    const u = {
      id: nextUnitId++, name, isPlayer, skill,
      x: 0, y: 0, r: 15, angle: 0, vx: 0, vy: 0,
      hp: 100, alive: true, phase: 'plane', alt: 0,
      slots: [null, null, null], active: -1,
      ammo: { '9mm': 0, '556': 0, '762': 0, '12g': 0, '300': 0 },
      meds: { bandage: 0, firstaid: 0, medkit: 0, drink: 0, pills: 0 },
      grenades: 0, vest: 0, vestDur: 0, helmet: 0, helmetDur: 0, pack: 0, boost: 0,
      fireCd: 0, reloadT: 0, reloadMax: 0, healT: 0, healMax: 0, healType: null, punchT: 0,
      aiming: false, sprint: false, moveX: 0, moveY: 0,
      kills: 0, damage: 0, killer: null, killerWeapon: null, deathTime: 0,
      lastHitBy: null, lastHitT: -99, lastShotT: -99, hitFlash: 0, underCanopy: false,
      clothes: isPlayer ? '#2d6fb8' : CLOTHES[Math.floor(Math.random() * CLOTHES.length)],
      jumpAt: 1, dropX: 0, dropY: 0,
    };
    if (!isPlayer) ZZ.AI.init(u);
    return u;
  }

  function activeWeapon(u) {
    const s = u.slots[u.active];
    return s ? WEAPONS[s.type] : null;
  }

  // ---------- Items ----------
  function itemLabel(it) {
    switch (it.kind) {
      case 'weapon': return WEAPONS[it.type].name;
      case 'ammo': return AMMO[it.type].name;
      case 'vest': return VEST[it.lvl].name;
      case 'helmet': return HELMET[it.lvl].name;
      case 'pack': return PACK[it.lvl].name;
      case 'med': return MEDS[it.type].name;
      case 'grenade': return 'قنبلة يدوية';
    }
    return '';
  }

  function spawnItem(kind, type, x, y, extra = {}) {
    const it = { id: nextItemId++, kind, type, x, y, amount: 1, lvl: 0, mag: 0, dur: 0, ...extra };
    if (kind === 'ammo' && !extra.amount) it.amount = AMMO[type].stack;
    if ((kind === 'vest' || kind === 'helmet') && !extra.dur) it.dur = (kind === 'vest' ? VEST : HELMET)[it.lvl].dur;
    if (kind === 'med' && !extra.amount) it.amount = type === 'bandage' ? 5 : 1;
    G.items.push(it);
    return it;
  }

  // Drops an item near (x, y), searching for a free spot.
  function dropItem(kind, type, x, y, extra) {
    for (let i = 0; i < 14; i++) {
      const a = Math.random() * TAU, d = i === 0 ? 0 : 18 + i * 6;
      const px = x + Math.cos(a) * d, py = y + Math.sin(a) * d;
      if (M.isFree(G.map, px, py, 9)) return spawnItem(kind, type, px, py, extra);
    }
    return spawnItem(kind, type, x, y, extra);
  }

  function populateLoot(rng) {
    for (const spot of G.map.lootSpots) {
      const table = spot.military ? ZZ.LOOT_TABLES.military : ZZ.LOOT_TABLES.common;
      const n = 1 + Math.floor(rng() * (spot.military ? 3 : 2.4));
      for (let i = 0; i < n; i++) {
        const e = ZZ.weightedPick(table, rng);
        const x = spot.x + (rng() - 0.5) * 40, y = spot.y + (rng() - 0.5) * 40;
        if (e[1] === 'weapon') {
          spawnItem('weapon', e[2], x, y);
          const ammo = WEAPONS[e[2]].ammo;
          spawnItem('ammo', ammo, x + 16, y + 10, { amount: AMMO[ammo].stack * (1 + Math.floor(rng() * 2)) });
        } else if (e[1] === 'vest' || e[1] === 'helmet' || e[1] === 'pack') {
          spawnItem(e[1], e[1], x, y, { lvl: e[2] });
        } else if (e[1] === 'grenade') {
          spawnItem('grenade', 'frag', x, y);
        } else {
          spawnItem(e[1], e[2], x, y);
        }
      }
    }
  }

  // Returns 'all' (item consumed), 'some' (partially taken) or 'none'.
  function pickup(u, it) {
    if (!u.alive || u.phase !== 'ground') return 'none';
    let res = 'none';
    switch (it.kind) {
      case 'weapon': {
        const w = WEAPONS[it.type];
        let slot;
        if (w.cls === 'pistol') slot = 2;
        else if (!u.slots[0]) slot = 0;
        else if (!u.slots[1]) slot = 1;
        else if (u.isPlayer) slot = u.active === 0 || u.active === 1 ? u.active : 0;
        else slot = WEAPONS[u.slots[0].type].tier <= WEAPONS[u.slots[1].type].tier ? 0 : 1; // bots swap out their weaker gun
        const old = u.slots[slot];
        if (old) dropItem('weapon', old.type, u.x, u.y, { mag: old.mag });
        u.slots[slot] = { type: it.type, mag: it.mag };
        if (u.active === -1 || u.active === slot || !u.slots[u.active]) switchSlot(u, slot, true);
        res = 'all';
        break;
      }
      case 'ammo': case 'med': case 'grenade': {
        let have, cap;
        if (it.kind === 'ammo') { have = u.ammo[it.type]; cap = AMMO_CAP[u.pack]; }
        else if (it.kind === 'med') { have = u.meds[it.type]; cap = MEDS[it.type].max[u.pack]; }
        else { have = u.grenades; cap = ZZ.GRENADE_MAX[u.pack]; }
        const take = Math.min(it.amount, cap - have);
        if (take <= 0) return 'none';
        if (it.kind === 'ammo') u.ammo[it.type] += take;
        else if (it.kind === 'med') u.meds[it.type] += take;
        else u.grenades += take;
        it.amount -= take;
        res = it.amount <= 0 ? 'all' : 'some';
        break;
      }
      case 'vest': case 'helmet': {
        const key = it.kind, durKey = key + 'Dur';
        if (it.lvl < u[key] || (it.lvl === u[key] && it.dur <= u[durKey])) return 'none';
        if (u[key]) dropItem(key, key, u.x, u.y, { lvl: u[key], dur: u[durKey] });
        u[key] = it.lvl;
        u[durKey] = it.dur;
        res = 'all';
        break;
      }
      case 'pack': {
        if (it.lvl <= u.pack) return 'none';
        if (u.pack) dropItem('pack', 'pack', u.x, u.y, { lvl: u.pack });
        u.pack = it.lvl;
        res = 'all';
        break;
      }
    }
    if (res === 'all') G.items.splice(G.items.indexOf(it), 1);
    if (res !== 'none' && u.isPlayer) Sound.play(it.kind === 'weapon' || it.kind === 'vest' || it.kind === 'helmet' || it.kind === 'pack' ? 'equip' : 'pickup');
    return res;
  }

  function wouldAutoPick(u, it) {
    switch (it.kind) {
      case 'ammo': return u.slots.some((s) => s && WEAPONS[s.type].ammo === it.type) && u.ammo[it.type] < AMMO_CAP[u.pack];
      case 'med': return u.meds[it.type] < MEDS[it.type].max[u.pack];
      case 'grenade': return u.grenades < ZZ.GRENADE_MAX[u.pack];
      case 'vest': case 'helmet': return it.lvl > u[it.kind];
      case 'pack': return it.lvl > u.pack;
    }
    return false;
  }

  // ---------- Actions ----------
  function switchSlot(u, i, silent) {
    if (i !== -1 && !u.slots[i]) return;
    if (u.active === i) return;
    u.active = i;
    u.reloadT = 0;
    cancelHeal(u);
    u.fireCd = Math.max(u.fireCd, 0.35);
    if (u.isPlayer && !silent) Sound.play('equip');
  }

  function startReload(u) {
    const s = u.slots[u.active];
    if (!s || u.reloadT > 0) return;
    const w = WEAPONS[s.type];
    if (s.mag >= w.mag) return;
    if (u.ammo[w.ammo] <= 0) { if (u.isPlayer) Sound.play('empty'); return; }
    cancelHeal(u);
    u.reloadT = u.reloadMax = w.reload;
    if (u.isPlayer) Sound.play('reload');
  }

  function finishReload(u) {
    const s = u.slots[u.active];
    if (!s) return;
    const w = WEAPONS[s.type];
    const take = Math.min(w.mag - s.mag, u.ammo[w.ammo]);
    s.mag += take;
    u.ammo[w.ammo] -= take;
  }

  function soundAt(name, x, y) {
    const p = G.player;
    const d = p ? Math.hypot(x - p.x, y - p.y) : 0;
    Sound.play(name, clamp(1 - d / 1900, 0, 1));
  }

  function tryFire(u) {
    if (!u.alive || u.phase !== 'ground' || u.reloadT > 0 || u.fireCd > 0) return false;
    const s = u.slots[u.active];
    cancelHeal(u);
    if (!s) return punch(u);
    const w = WEAPONS[s.type];
    if (s.mag <= 0) {
      if (u.ammo[w.ammo] > 0) startReload(u);
      else { u.fireCd = 0.3; if (u.isPlayer) Sound.play('empty'); }
      return false;
    }
    s.mag--;
    u.fireCd = w.rate;
    u.lastShotT = G.time;
    u.shots = (u.shots || 0) + w.pellets;
    const moving = Math.hypot(u.vx, u.vy) > 40;
    let spread = w.spread * (u.aiming ? 0.45 : 1) * (moving ? (u.sprint ? 2 : 1.35) : 1);
    if (!u.aiming && (w.cls === 'sr' || w.cls === 'dmr')) spread += 0.05; // hip-firing scoped guns is inaccurate
    if (!u.isPlayer) spread += 0.03 + (1 - u.skill) * 0.07;
    const mx = u.x + Math.cos(u.angle) * (u.r + 14), my = u.y + Math.sin(u.angle) * (u.r + 14);
    for (let i = 0; i < w.pellets; i++) {
      const a = u.angle + (Math.random() + Math.random() - 1) * spread;
      const sp = w.speed * (w.pellets > 1 ? rand(0.85, 1.05) : 1);
      G.bullets.push({
        x: mx, y: my, px: u.x, py: u.y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp,
        life: (w.range / w.speed) * (w.pellets > 1 ? rand(0.8, 1) : 1),
        dmg: w.dmg, owner: u, weapon: s.type, cls: w.cls,
      });
    }
    G.particles.push({ x: mx, y: my, vx: 0, vy: 0, life: 0.06, max: 0.06, color: '#ffe9a8', size: w.cls === 'sr' ? 16 : 10, flash: true });
    const snd = w.cls === 'ar' ? 'ar' : w.cls === 'sr' ? 'sr' : w.cls;
    if (u.isPlayer) {
      Sound.play(snd);
      shake = Math.min(10, shake + (w.cls === 'sr' ? 6 : w.cls === 'shotgun' ? 5 : 1.4));
    } else soundAt(snd, u.x, u.y);
    if (s.mag === 0 && u.ammo[w.ammo] > 0) startReload(u);
    return true;
  }

  function punch(u) {
    if (u.punchT > 0) return false;
    u.punchT = FISTS.rate;
    u.fireCd = FISTS.rate;
    const hx = u.x + Math.cos(u.angle) * (u.r + 14), hy = u.y + Math.sin(u.angle) * (u.r + 14);
    for (const t of G.units) {
      if (t === u || !t.alive || t.phase !== 'ground') continue;
      if (Math.hypot(t.x - hx, t.y - hy) < t.r + 16) {
        applyDamage(t, FISTS.dmg, u, 'fists', false);
        break;
      }
    }
    soundAt('punch', u.x, u.y);
    return true;
  }

  function throwGrenade(u, tx, ty) {
    if (u.grenades <= 0 || u.phase !== 'ground' || !u.alive || u.fireCd > 0) return;
    cancelHeal(u);
    u.grenades--;
    u.fireCd = 0.6;
    const dx = tx - u.x, dy = ty - u.y;
    const d = Math.min(460, Math.hypot(dx, dy));
    const a = Math.atan2(dy, dx);
    G.grenades.push({ x: u.x + Math.cos(a) * 20, y: u.y + Math.sin(a) * 20, r: 6, vx: Math.cos(a) * d * 1.6, vy: Math.sin(a) * d * 1.6, fuse: 2.4, owner: u, spin: 0 });
    soundAt('throw', u.x, u.y);
  }

  function explode(g) {
    const R = 210;
    for (const t of G.units) {
      if (!t.alive || t.phase !== 'ground') continue;
      const d = Math.hypot(t.x - g.x, t.y - g.y);
      if (d > R) continue;
      if (M.segmentHit(G.map, g.x, g.y, t.x, t.y) >= 0) continue;
      applyDamage(t, 115 * (1 - d / R) + 10, g.owner, 'grenade', false, true);
    }
    for (let i = 0; i < 40; i++) {
      const a = rand(0, TAU), s = rand(60, 420);
      G.particles.push({ x: g.x, y: g.y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: rand(0.3, 0.8), max: 0.8, color: i % 3 ? '#ffb347' : '#555', size: rand(4, 10) });
    }
    G.decals.push({ x: g.x, y: g.y, r: 34, t: 30, color: 'rgba(40,36,28,0.35)' });
    const p = G.player;
    const d = p ? Math.hypot(p.x - g.x, p.y - g.y) : 9999;
    shake = Math.min(24, shake + Math.max(0, 22 - d / 40));
    soundAt('explosion', g.x, g.y);
  }

  function useMed(u, type) {
    if (!u.alive || u.phase !== 'ground' || u.meds[type] <= 0 || u.healT > 0) return false;
    const m = MEDS[type];
    if (m.heal && u.hp >= m.cap) return false;
    if (m.healTo && u.hp >= m.healTo) return false;
    if (m.boost && u.boost >= 100) return false;
    u.reloadT = 0;
    u.healT = u.healMax = m.time;
    u.healType = type;
    return true;
  }

  function finishHeal(u) {
    const m = MEDS[u.healType];
    u.meds[u.healType]--;
    if (m.heal) u.hp = Math.min(m.cap, u.hp + m.heal);
    if (m.healTo) u.hp = Math.max(u.hp, m.healTo);
    if (m.boost) u.boost = Math.min(100, u.boost + m.boost);
    u.healType = null;
    if (u.isPlayer) Sound.play('heal');
  }

  function cancelHeal(u) { u.healT = 0; u.healType = null; }

  // ---------- Damage ----------
  function applyDamage(t, dmg, attacker, weapon, canHead = true, isBlast = false) {
    if (!t.alive) return;
    if (DEBUG.god && t.isPlayer) return;
    let head = false;
    if (canHead && weapon !== 'zone') {
      const cls = WEAPONS[weapon] ? WEAPONS[weapon].cls : '';
      head = Math.random() < (cls === 'sr' ? 0.28 : cls === 'shotgun' ? 0.05 : 0.14);
    }
    if (head) {
      dmg *= WEAPONS[weapon].cls === 'sr' ? 2.2 : 1.8;
      if (t.helmet) {
        const h = HELMET[t.helmet];
        t.helmetDur -= dmg * 0.7;
        dmg *= 1 - h.reduce;
        if (t.helmetDur <= 0) { t.helmet = 0; t.helmetDur = 0; }
      }
    } else if (weapon !== 'zone' && t.vest) {
      const v = VEST[t.vest];
      t.vestDur -= dmg * (isBlast ? 0.5 : 0.7);
      dmg *= 1 - v.reduce * (isBlast ? 0.5 : 1);
      if (t.vestDur <= 0) { t.vest = 0; t.vestDur = 0; }
    }
    t.hp -= dmg;
    t.hitFlash = 0.1;
    if (attacker && attacker !== t) {
      attacker.damage += dmg;
      if (WEAPONS[weapon]) attacker.hits = (attacker.hits || 0) + 1;
      t.lastHitBy = attacker;
      t.lastHitT = G.time;
    }
    if (t.isPlayer && weapon !== 'zone') {
      hurtT = 0.4;
      shake = Math.min(14, shake + 4);
      if (attacker) dmgIndicators.push({ a: Math.atan2(attacker.y - t.y, attacker.x - t.x), t: 1.2 });
      Sound.play('hurt');
    }
    if (attacker && attacker.isPlayer && attacker !== t) {
      hitMarkT = 0.25;
      hitMarkHead = head;
      Sound.play(head ? 'headshot' : 'hit');
      G.texts.push({ x: t.x + rand(-10, 10), y: t.y - 24, text: String(Math.round(dmg)), color: head ? '#ff5c5c' : '#ffffff', life: 0.8, max: 0.8, size: head ? 18 : 15 });
    }
    if (weapon !== 'zone') {
      for (let i = 0; i < 4; i++) G.particles.push({ x: t.x, y: t.y, vx: rand(-90, 90), vy: rand(-90, 90), life: 0.3, max: 0.3, color: '#b3122a', size: 3 });
    }
    if (t.hp <= 0) killUnit(t, attacker, weapon);
  }

  function killUnit(t, attacker, weapon) {
    t.alive = false;
    t.hp = 0;
    t.deathTime = G.time;
    t.killer = attacker && attacker !== t ? attacker : null;
    t.killerWeapon = weapon;
    if (t.killer) t.killer.kills++;
    // Drop everything.
    t.slots.forEach((s) => { if (s) dropItem('weapon', s.type, t.x, t.y, { mag: s.mag }); });
    for (const a of ZZ.AMMO_TYPES) if (t.ammo[a] > 0) dropItem('ammo', a, t.x, t.y, { amount: t.ammo[a] });
    for (const m of MED_ORDER) if (t.meds[m] > 0) dropItem('med', m, t.x, t.y, { amount: t.meds[m] });
    if (t.grenades) dropItem('grenade', 'frag', t.x, t.y, { amount: t.grenades });
    if (t.vest) dropItem('vest', 'vest', t.x, t.y, { lvl: t.vest, dur: t.vestDur });
    if (t.helmet) dropItem('helmet', 'helmet', t.x, t.y, { lvl: t.helmet, dur: t.helmetDur });
    if (t.pack) dropItem('pack', 'pack', t.x, t.y, { lvl: t.pack });
    G.decals.push({ x: t.x, y: t.y, r: 20, t: 90, color: 'rgba(120,10,20,0.55)', body: true, clothes: t.clothes });

    const wname = weapon === 'zone' ? null : weapon === 'grenade' ? 'قنبلة' : weapon === 'fists' ? 'قبضة' : WEAPONS[weapon] ? WEAPONS[weapon].name : '';
    addKillfeed(t, t.killer, wname);
    if (t.killer && t.killer.isPlayer) {
      Sound.play('kill');
      showBanner(`قتلت ${t.name}`, `${t.killer.kills} قتيل`, 1600);
    }
    if (t.isPlayer) endMatch(false);
    else if (G.player && G.player.alive && aliveCount() === 1) endMatch(true);
  }

  function aliveCount() {
    let n = 0;
    for (const u of G.units) if (u.alive) n++;
    return n;
  }

  // ---------- Match setup ----------
  function newMatch() {
    const seed = DEBUG.seed || Math.floor(Math.random() * 1e9);
    const rng = ZZ.mulberry32(seed + 7);
    G.map = M.createMap(seed);
    G.time = 0;
    G.units = []; G.items = []; G.bullets = []; G.grenades = []; G.particles = []; G.decals = []; G.texts = [];
    G.airdrops = []; G.killfeed = [];
    roofAlpha = G.map.buildings.map(() => 1);
    nextItemId = 1; nextUnitId = 1;
    populateLoot(rng);

    const S = G.map.size;
    // Plane route across the island.
    const a = rand(0, TAU);
    const cx = S / 2 + rand(-S * 0.18, S * 0.18), cy = S / 2 + rand(-S * 0.18, S * 0.18);
    const L = S * 0.75;
    G.plane = {
      x1: cx - Math.cos(a) * L, y1: cy - Math.sin(a) * L, x2: cx + Math.cos(a) * L, y2: cy + Math.sin(a) * L,
      angle: a, t: 0, dur: (2 * L) / 480, x: 0, y: 0, active: true,
    };

    // Zone
    G.zone = { phase: 0, state: 'wait', timer: ZONE_PHASES[0].wait, cx: S / 2, cy: S / 2, r: S * 0.76, dps: 0.4 };
    pickNextZone();

    // Units
    const player = makeUnit((ZZ.Profile && ZZ.Profile.name()) || 'أنت', true, 1);
    G.player = player;
    G.units.push(player);
    const [s0, s1] = DIFFICULTY[difficulty].skill;
    const botCount = DEBUG.bots || ZZ.PLAYER_COUNT - 1;
    const usedNames = new Set();
    for (let i = 0; i < botCount; i++) {
      let name = ZZ.randomName(Math.random);
      for (let k = 0; k < 5 && usedNames.has(name); k++) name = ZZ.randomName(Math.random);
      usedNames.add(name);
      const b = makeUnit(name, false, rand(s0, s1));
      // Choose a drop target (a town, a random building, or open countryside) away from other bots.
      let tx, ty;
      for (let k = 0; k < 20; k++) {
        const roll = Math.random();
        if (roll < 0.35) {
          const towns = G.map.towns;
          const t = towns[Math.floor(Math.random() * towns.length)];
          const ang = rand(0, TAU), d = rand(0, t.r);
          tx = t.x + Math.cos(ang) * d; ty = t.y + Math.sin(ang) * d;
        } else if (roll < 0.75) {
          const bl = G.map.buildings[Math.floor(Math.random() * G.map.buildings.length)];
          tx = bl.x + bl.w / 2; ty = bl.y + bl.h / 2;
        } else {
          tx = rand(300, S - 300); ty = rand(300, S - 300);
        }
        const minGap = k < 15 ? 380 : 200;
        if (!G.units.some((o) => !o.isPlayer && Math.hypot(o.dropX - tx, o.dropY - ty) < minGap)) break;
      }
      b.dropX = clamp(tx, 100, S - 100); b.dropY = clamp(ty, 100, S - 100);
      // Jump when the plane is closest to the target.
      const pl = G.plane;
      const vx = pl.x2 - pl.x1, vy = pl.y2 - pl.y1;
      const t = ((b.dropX - pl.x1) * vx + (b.dropY - pl.y1) * vy) / (vx * vx + vy * vy);
      b.jumpAt = clamp(t - rand(0.0, 0.05), 0.12, 0.92);
      G.units.push(b);
    }
    alivePrev = G.units.length;
    matchResult = null;
    marker = null;
    mapOpen = false;
    shake = 0; hurtT = 0; hitMarkT = 0; dmgIndicators = [];
    updatePlane(0);
    cam.x = G.plane.x; cam.y = G.plane.y;
    cam.scale = baseScale() * 0.45;
    Sound.setHum(true);
    showBanner('مرحباً في منطقة الصفر', 'اضغط F للقفز من الطائرة', 3500);
  }

  // ---------- Plane & parachutes ----------
  function updatePlane(dt) {
    const pl = G.plane;
    if (!pl.active) return;
    pl.t += dt / pl.dur;
    pl.x = lerp(pl.x1, pl.x2, pl.t);
    pl.y = lerp(pl.y1, pl.y2, pl.t);
    const overLand = planeOverLand();
    let anyone = false;
    for (const u of G.units) {
      if (u.phase !== 'plane') continue;
      u.x = pl.x; u.y = pl.y;
      const auto = u.isPlayer ? pl.t > 0.93 : pl.t >= u.jumpAt;
      if (auto && overLand) jump(u);
      else if (auto && pl.t > 0.97) jump(u);
      if (u.phase === 'plane') anyone = true;
    }
    if (pl.t >= 1 || (!anyone && pl.t > 0.5)) { pl.active = false; Sound.setHum(false); }
  }

  function planeOverLand() {
    const pl = G.plane, S = G.map.size;
    return pl.x > 150 && pl.y > 150 && pl.x < S - 150 && pl.y < S - 150;
  }

  function jump(u) {
    if (u.phase !== 'plane') return;
    const S = G.map.size;
    if (u.isPlayer && !planeOverLand() && G.plane.t < 0.97) {
      showBanner('', 'انتظر حتى تصل الطائرة فوق الجزيرة', 1200);
      return;
    }
    u.phase = 'chute';
    u.alt = 1;
    u.x = clamp(u.x, 120, S - 120);
    u.y = clamp(u.y, 120, S - 120);
    if (u.isPlayer) {
      Sound.play('jump');
      Sound.setHum(false);
      showBanner('', 'وجّه المظلة بأزرار الحركة', 2200);
    }
  }

  function updateChute(u, dt) {
    u.alt -= dt / 8;
    let mx = 0, my = 0;
    if (u.isPlayer) {
      if (keys.has('KeyW') || keys.has('ArrowUp')) my -= 1;
      if (keys.has('KeyS') || keys.has('ArrowDown')) my += 1;
      if (keys.has('KeyA') || keys.has('ArrowLeft')) mx -= 1;
      if (keys.has('KeyD') || keys.has('ArrowRight')) mx += 1;
    } else {
      const dx = u.dropX - u.x, dy = u.dropY - u.y;
      if (Math.hypot(dx, dy) > 20) { mx = dx; my = dy; }
    }
    const l = Math.hypot(mx, my);
    const speed = 270;
    if (l) { u.x += (mx / l) * speed * dt; u.y += (my / l) * speed * dt; u.angle = Math.atan2(my, mx); }
    const S = G.map.size;
    u.x = clamp(u.x, 60, S - 60); u.y = clamp(u.y, 60, S - 60);
    if (u.alt <= 0) {
      u.alt = 0;
      u.phase = 'ground';
      u.landT = G.time;
      M.collideCircle(G.map, u);
      if (u.isPlayer) { Sound.play('land'); showBanner('', 'اجمع الأسلحة بسرعة!', 1800); }
    }
  }

  // ---------- Zone ----------
  function pickNextZone() {
    const z = G.zone;
    const ph = ZONE_PHASES[z.phase];
    const S = G.map.size;
    const maxOff = Math.max(0, z.r - ph.r);
    let nx = z.cx, ny = z.cy;
    for (let i = 0; i < 40; i++) {
      const a = rand(0, TAU), d = Math.sqrt(Math.random()) * maxOff;
      const x = z.cx + Math.cos(a) * d, y = z.cy + Math.sin(a) * d;
      const margin = Math.min(ph.r * 0.6, 900) + 150;
      if (x < margin || y < margin || x > S - margin || y > S - margin) continue;
      nx = x; ny = y; break;
    }
    z.nx = nx; z.ny = ny; z.nr = ph.r;
  }

  function updateZone(dt) {
    const z = G.zone;
    if (z.state === 'done') return;
    z.timer -= dt;
    const ph = ZONE_PHASES[z.phase];
    if (z.state === 'wait') {
      if (z.timer <= 0) {
        z.state = 'shrink';
        z.timer = ph.shrink;
        z.ox = z.cx; z.oy = z.cy; z.or = z.r;
        z.dps = ph.dps;
        Sound.play('zone');
        showBanner('المنطقة تتقلص!', 'تحرّك نحو الدائرة البيضاء', 2500);
      } else if (Math.abs(z.timer - 30) < dt && G.player.alive) {
        showBanner('', 'تقلص المنطقة خلال 30 ثانية', 2200);
      }
    } else if (z.state === 'shrink') {
      const k = clamp(1 - z.timer / ph.shrink, 0, 1);
      z.cx = lerp(z.ox, z.nx, k); z.cy = lerp(z.oy, z.ny, k); z.r = lerp(z.or, z.nr, k);
      if (z.timer <= 0) {
        z.cx = z.nx; z.cy = z.ny; z.r = z.nr;
        z.phase++;
        if (z.phase >= ZONE_PHASES.length) { z.state = 'done'; return; }
        z.state = 'wait';
        z.timer = ZONE_PHASES[z.phase].wait;
        pickNextZone();
        if (ZZ.AIRDROP_PHASES.includes(z.phase)) spawnAirdrop();
      }
    }
  }

  function outsideZone(u) {
    const z = G.zone;
    return (u.x - z.cx) ** 2 + (u.y - z.cy) ** 2 > z.r * z.r;
  }

  // ---------- Airdrops ----------
  function spawnAirdrop() {
    const z = G.zone;
    let x = z.nx, y = z.ny;
    for (let i = 0; i < 30; i++) {
      const a = rand(0, TAU), d = Math.sqrt(Math.random()) * z.nr * 0.8;
      const px = z.nx + Math.cos(a) * d, py = z.ny + Math.sin(a) * d;
      if (M.isFree(G.map, px, py, 40) && M.buildingAt(G.map, px, py) < 0) { x = px; y = py; break; }
    }
    G.airdrops.push({ x, y, alt: 1, landed: false, smoke: 40 });
    Sound.play('airdrop');
    showBanner('إنزال جوي!', 'ابحث عن الدخان الأحمر', 2600);
    addKillfeedText('📦 إنزال جوي قادم');
  }

  function updateAirdrops(dt) {
    for (const d of G.airdrops) {
      if (!d.landed) {
        d.alt -= dt / 14;
        if (d.alt <= 0) {
          d.landed = true;
          const gun = Math.random() < 0.55 ? 'awm' : 'm249';
          const w = WEAPONS[gun];
          spawnItem('weapon', gun, d.x - 14, d.y - 10, { mag: w.mag });
          spawnItem('ammo', w.ammo, d.x + 14, d.y - 10, { amount: gun === 'awm' ? 20 : 100 });
          const gear = Math.random() < 0.5 ? 'vest' : 'helmet';
          spawnItem(gear, gear, d.x - 14, d.y + 12, { lvl: 3 });
          spawnItem('med', 'medkit', d.x + 14, d.y + 12, { amount: 1 });
          if (Math.random() < 0.6) spawnItem('pack', 'pack', d.x, d.y + 26, { lvl: 3 });
        }
      } else if (d.smoke > 0) {
        d.smoke -= dt;
        if (Math.random() < dt * 18) G.particles.push({ x: d.x + rand(-6, 6), y: d.y + rand(-6, 6), vx: rand(-15, 25), vy: rand(-45, -15), life: 3, max: 3, color: 'rgba(230,50,50,0.5)', size: rand(14, 26), smoke: true });
      }
    }
  }

  // ---------- Update ----------
  function update(dt) {
    G.time += dt;
    updatePlane(dt);
    updateZone(dt);
    updateAirdrops(dt);

    const p = G.player;
    if (p.alive) updatePlayerInput(dt);

    for (const u of G.units) {
      if (!u.alive) continue;
      if (u.phase === 'chute') { updateChute(u, dt); continue; }
      if (u.phase !== 'ground') continue;
      if (!u.isPlayer) ZZ.AI.update(u, dt, G);
      updateUnit(u, dt);
    }
    separateUnits();
    updateBullets(dt);
    updateGrenades(dt);
    updateEffects(dt);

    // Roof fading for the building the player stands in.
    const inside = p.phase === 'ground' ? M.buildingAt(G.map, p.x, p.y) : -1;
    for (let i = 0; i < roofAlpha.length; i++) {
      const target = i === inside ? 0 : 1;
      roofAlpha[i] += (target - roofAlpha[i]) * Math.min(1, dt * 8);
    }
    G.insideIdx = inside;

    const alive = aliveCount();
    if (alive !== alivePrev) alivePrev = alive;
    updateCamera(dt);
  }

  function updatePlayerInput(dt) {
    const p = G.player;
    if (p.phase === 'plane') {
      return;
    }
    let mx = 0, my = 0;
    if (keys.has('KeyW') || keys.has('ArrowUp')) my -= 1;
    if (keys.has('KeyS') || keys.has('ArrowDown')) my += 1;
    if (keys.has('KeyA') || keys.has('ArrowLeft')) mx -= 1;
    if (keys.has('KeyD') || keys.has('ArrowRight')) mx += 1;
    const l = Math.hypot(mx, my);
    p.moveX = l ? mx / l : 0;
    p.moveY = l ? my / l : 0;
    if (p.phase !== 'ground') return;

    const wx = cam.x + (mouse.x - W / 2) / cam.scale;
    const wy = cam.y + (mouse.y - H / 2) / cam.scale;
    if (!mapOpen) p.angle = Math.atan2(wy - p.y, wx - p.x);
    p.aiming = mouse.right && !mapOpen && p.healT <= 0;
    p.sprint = (keys.has('ShiftLeft') || keys.has('ShiftRight')) && !p.aiming && p.healT <= 0;

    if (!mapOpen) {
      const w = activeWeapon(p);
      shotQueueT = Math.max(0, shotQueueT - dt);
      if (w && w.auto && mouse.down) tryFire(p);
      else if (shotQueueT > 0 && tryFire(p)) shotQueueT = 0;
    }

    // Auto-pickup of ammo, meds and better gear.
    for (let i = G.items.length - 1; i >= 0; i--) {
      const it = G.items[i];
      if (Math.abs(it.x - p.x) > 34 || Math.abs(it.y - p.y) > 34) continue;
      if (it.kind !== 'weapon' && wouldAutoPick(p, it)) pickup(p, it);
    }
  }

  function updateUnit(u, dt) {
    u.fireCd = Math.max(0, u.fireCd - dt);
    u.punchT = Math.max(0, u.punchT - dt);
    u.hitFlash = Math.max(0, u.hitFlash - dt);
    if (u.reloadT > 0) { u.reloadT -= dt; if (u.reloadT <= 0) { u.reloadT = 0; finishReload(u); } }
    if (u.healT > 0) { u.healT -= dt; if (u.healT <= 0) { u.healT = 0; finishHeal(u); } }

    // Boost: slow healing and a small speed bonus.
    if (u.boost > 0) {
      u.boost = Math.max(0, u.boost - dt * 0.55);
      u.hp = Math.min(100, u.hp + dt * (u.boost > 60 ? 1.1 : u.boost > 20 ? 0.6 : 0.3));
    }

    const w = activeWeapon(u);
    let speed = 225;
    if (u.sprint && !u.aiming) speed *= 1.35;
    else if (u.walk) speed *= 0.8;
    if (u.aiming) speed *= 0.6;
    if (u.healT > 0) speed *= 0.45;
    if (u.boost > 60) speed *= 1.06;
    if (w && (w.cls === 'sr' || w.cls === 'lmg')) speed *= 0.94;
    const ox = u.x, oy = u.y;
    u.x += u.moveX * speed * dt;
    u.y += u.moveY * speed * dt;
    M.collideCircle(G.map, u);
    u.vx = (u.x - ox) / Math.max(dt, 1e-4);
    u.vy = (u.y - oy) / Math.max(dt, 1e-4);

    // Zone damage
    if (outsideZone(u)) {
      applyDamage(u, G.zone.dps * dt, null, 'zone', false);
      if (u.isPlayer && Math.random() < dt * 1.5) Sound.play('zoneTick');
      if (!u.alive) return;
    }

    // Canopy check (cheap: only nearby trees via grid query).
    u.underCanopy = false;
    M.query(G.map, u.x - 50, u.y - 50, u.x + 50, u.y + 50, (o) => {
      if (o.kind === 'tree' && Math.hypot(o.x - u.x, o.y - u.y) < o.canopy) u.underCanopy = true;
    });
  }

  function separateUnits() {
    const us = G.units;
    for (let i = 0; i < us.length; i++) {
      const a = us[i];
      if (!a.alive || a.phase !== 'ground') continue;
      for (let j = i + 1; j < us.length; j++) {
        const b = us[j];
        if (!b.alive || b.phase !== 'ground') continue;
        const dx = b.x - a.x, dy = b.y - a.y;
        const rr = a.r + b.r;
        const d2 = dx * dx + dy * dy;
        if (d2 > 0 && d2 < rr * rr) {
          const d = Math.sqrt(d2), push = (rr - d) / 2;
          a.x -= (dx / d) * push; a.y -= (dy / d) * push;
          b.x += (dx / d) * push; b.y += (dy / d) * push;
        }
      }
    }
  }

  function segCircleT(x, y, dx, dy, cx, cy, r) {
    const fx = x - cx, fy = y - cy;
    const a = dx * dx + dy * dy;
    const b = 2 * (fx * dx + fy * dy);
    const c = fx * fx + fy * fy - r * r;
    const disc = b * b - 4 * a * c;
    if (disc < 0 || a < 1e-9) return -1;
    const t = (-b - Math.sqrt(disc)) / (2 * a);
    return t >= 0 && t <= 1 ? t : c < 0 ? 0 : -1;
  }

  function updateBullets(dt) {
    for (let i = G.bullets.length - 1; i >= 0; i--) {
      const b = G.bullets[i];
      const sx = b.px !== undefined ? b.px : b.x, sy = b.py !== undefined ? b.py : b.y;
      b.px = undefined; b.py = undefined;
      const ex = b.x + b.vx * dt, ey = b.y + b.vy * dt;
      const dx = ex - sx, dy = ey - sy;
      let tHit = M.segmentHit(G.map, sx, sy, ex, ey);
      let unitHit = null;
      for (const u of G.units) {
        if (u === b.owner || !u.alive || u.phase !== 'ground') continue;
        if (Math.abs(u.x - sx) > 900 && Math.abs(u.x - ex) > 900) continue;
        const t = segCircleT(sx, sy, dx, dy, u.x, u.y, u.r);
        if (t >= 0 && (tHit < 0 || t < tHit)) { tHit = t; unitHit = u; }
      }
      b.life -= dt;
      if (tHit >= 0) {
        const hx = sx + dx * tHit, hy = sy + dy * tHit;
        if (unitHit) {
          // Shotgun pellets lose damage with distance.
          let dmg = b.dmg;
          if (b.cls === 'shotgun') {
            const travelled = WEAPONS[b.weapon].range * (1 - b.life / (WEAPONS[b.weapon].range / WEAPONS[b.weapon].speed));
            dmg *= clamp(1.15 - travelled / 400, 0.35, 1.15);
          }
          applyDamage(unitHit, dmg, b.owner, b.weapon, true);
        } else {
          for (let k = 0; k < 3; k++) G.particles.push({ x: hx, y: hy, vx: rand(-80, 80), vy: rand(-80, 80), life: 0.25, max: 0.25, color: '#d8c8a0', size: 2.5 });
        }
        G.bullets.splice(i, 1);
        continue;
      }
      b.x = ex; b.y = ey;
      if (b.life <= 0) G.bullets.splice(i, 1);
    }
  }

  function updateGrenades(dt) {
    for (let i = G.grenades.length - 1; i >= 0; i--) {
      const g = G.grenades[i];
      g.fuse -= dt;
      g.x += g.vx * dt; g.y += g.vy * dt;
      g.vx *= 1 - Math.min(1, dt * 2.6); g.vy *= 1 - Math.min(1, dt * 2.6);
      g.spin += dt * Math.hypot(g.vx, g.vy) * 0.05;
      const ox = g.x, oy = g.y;
      if (M.collideCircle(G.map, g)) {
        // Bounce: reflect along the push direction.
        const nx = g.x - ox, ny = g.y - oy, nl = Math.hypot(nx, ny);
        if (nl > 0) {
          const ux = nx / nl, uy = ny / nl;
          const dot = g.vx * ux + g.vy * uy;
          g.vx = (g.vx - 2 * dot * ux) * 0.45; g.vy = (g.vy - 2 * dot * uy) * 0.45;
        }
      }
      if (g.fuse <= 0) { explode(g); G.grenades.splice(i, 1); }
    }
  }

  function updateEffects(dt) {
    for (let i = G.particles.length - 1; i >= 0; i--) {
      const pt = G.particles[i];
      pt.life -= dt;
      if (pt.life <= 0) { G.particles.splice(i, 1); continue; }
      pt.x += pt.vx * dt; pt.y += pt.vy * dt;
      if (!pt.smoke) { pt.vx *= 1 - dt * 4; pt.vy *= 1 - dt * 4; } else pt.size += dt * 8;
    }
    for (let i = G.decals.length - 1; i >= 0; i--) { G.decals[i].t -= dt; if (G.decals[i].t <= 0) G.decals.splice(i, 1); }
    for (let i = G.texts.length - 1; i >= 0; i--) { const t = G.texts[i]; t.life -= dt; t.y -= 30 * dt; if (t.life <= 0) G.texts.splice(i, 1); }
    for (let i = dmgIndicators.length - 1; i >= 0; i--) { dmgIndicators[i].t -= dt; if (dmgIndicators[i].t <= 0) dmgIndicators.splice(i, 1); }
    hurtT = Math.max(0, hurtT - dt);
    hitMarkT = Math.max(0, hitMarkT - dt);
    shake = Math.max(0, shake - dt * 30);
  }

  function baseScale() {
    return clamp(Math.min(W, H) / 820, 0.55, 1.4);
  }

  function updateCamera(dt) {
    const p = G.player;
    let tx = p.x, ty = p.y, ts = baseScale();
    if (p.phase === 'plane') { tx = G.plane.x; ty = G.plane.y; ts *= 0.42; }
    else if (p.phase === 'chute') ts *= lerp(1, 0.55, p.alt);
    else if (!p.alive && p.killer && p.killer.alive) { tx = p.killer.x; ty = p.killer.y; }
    else if (p.aiming) {
      const w = activeWeapon(p);
      if (w) {
        ts /= w.zoom;
        // Peek toward the cursor when scoped.
        const k = (w.zoom - 1) * 0.55;
        tx += (mouse.x - W / 2) / (ts) * k;
        ty += (mouse.y - H / 2) / (ts) * k;
      }
    }
    const f = Math.min(1, dt * 7);
    cam.x += (tx - cam.x) * f;
    cam.y += (ty - cam.y) * f;
    cam.scale += (ts - cam.scale) * Math.min(1, dt * 5);
  }

  // ---------- Killfeed / banners ----------
  function addKillfeed(victim, killer, wname) {
    let html;
    const esc = (s) => s.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
    if (!killer) html = `<b>${esc(victim.name)}</b> <span class="w">مات في المنطقة الزرقاء</span>`;
    else html = `<b>${esc(killer.name)}</b> <span class="w">[${esc(wname)}]</span> <b>${esc(victim.name)}</b>`;
    const cls = killer && killer.isPlayer ? 'me' : victim.isPlayer ? 'died' : '';
    pushFeed(html, cls);
  }
  function addKillfeedText(text) { pushFeed(text, ''); }
  function pushFeed(html, cls) {
    const el = document.createElement('div');
    el.className = 'kf ' + cls;
    el.innerHTML = html;
    const feed = $('killfeed');
    feed.appendChild(el);
    while (feed.children.length > 6) feed.removeChild(feed.firstChild);
    setTimeout(() => el.classList.add('fade'), 6000);
    setTimeout(() => el.remove(), 6600);
  }

  let bannerTimer = null;
  function showBanner(title, sub, ms = 2200) {
    const el = $('banner');
    el.textContent = title;
    if (sub) { const s = document.createElement('small'); s.textContent = sub; el.appendChild(s); }
    el.classList.add('show');
    clearTimeout(bannerTimer);
    bannerTimer = setTimeout(() => el.classList.remove('show'), ms);
  }

  // ---------- Rendering ----------
  function viewRect() {
    const hw = W / 2 / cam.scale, hh = H / 2 / cam.scale;
    return { x0: cam.x - hw, y0: cam.y - hh, x1: cam.x + hw, y1: cam.y + hh };
  }

  function render() {
    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    ctx.fillStyle = '#0b0f14';
    ctx.fillRect(0, 0, W, H);
    if (!G.map) { drawMenuBackdrop(); return; }

    const v = viewRect();
    const sx = shake ? rand(-shake, shake) * 0.4 : 0, sy = shake ? rand(-shake, shake) * 0.4 : 0;
    ctx.save();
    ctx.translate(W / 2, H / 2);
    ctx.scale(cam.scale, cam.scale);
    ctx.translate(-cam.x + sx / cam.scale, -cam.y + sy / cam.scale);

    M.drawGround(ctx, G.map, v);
    drawDecals(v);
    drawAirdropsGround(v);
    drawItems(v);
    M.drawObstacles(ctx, G.map, v);
    drawGrenades();
    for (const u of G.units) if (u.alive && u.phase === 'ground') drawUnit(u, v);
    drawBullets();
    drawParticles(false);
    M.drawRoofs(ctx, G.map, v, G.insideIdx, roofAlpha);
    M.drawCanopies(ctx, G.map, v, G.player.x, G.player.y);
    drawParticles(true);
    for (const u of G.units) if (u.alive && u.phase === 'chute') drawChute(u, v);
    drawAirdropsAir(v);
    drawPlane();
    drawZone(v);
    drawTexts();
    ctx.restore();

    drawScreenEffects();
    drawMinimap();
    if (mapOpen) drawFullMap();
    if (state === 'playing' && !mapOpen && G.player.phase === 'ground' && G.player.alive) drawCrosshair();
  }

  function drawDecals(v) {
    for (const d of G.decals) {
      if (!M.inView(v, d.x, d.y, 40)) continue;
      ctx.globalAlpha = Math.min(1, d.t / 5);
      ctx.fillStyle = d.color;
      ctx.beginPath(); ctx.arc(d.x, d.y, d.r, 0, TAU); ctx.fill();
      if (d.body) {
        ctx.fillStyle = d.clothes;
        ctx.beginPath(); ctx.ellipse(d.x, d.y, 15, 10, 0.6, 0, TAU); ctx.fill();
      }
    }
    ctx.globalAlpha = 1;
  }

  function drawItems(v) {
    const p = G.player;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    for (const it of G.items) {
      if (!M.inView(v, it.x, it.y, 30)) continue;
      ctx.save();
      ctx.translate(it.x, it.y);
      ctx.fillStyle = 'rgba(0,0,0,0.25)';
      ctx.beginPath(); ctx.arc(0, 2, 13, 0, TAU); ctx.fill();
      switch (it.kind) {
        case 'weapon': {
          const w = WEAPONS[it.type];
          const len = { pistol: 16, smg: 22, shotgun: 28, ar: 30, dmr: 34, sr: 38, lmg: 34 }[w.cls];
          ctx.rotate(-0.5);
          ctx.fillStyle = '#26282b';
          ctx.fillRect(-len / 2, -3.5, len, 7);
          ctx.fillRect(-len / 2 + 3, 0, 5, 9);
          ctx.fillStyle = w.tier >= 6 ? '#e2b13c' : '#5c6066';
          ctx.fillRect(len / 2 - 6, -3.5, 6, 7);
          break;
        }
        case 'ammo':
          ctx.fillStyle = '#3a3324';
          ctx.fillRect(-9, -7, 18, 14);
          ctx.fillStyle = AMMO[it.type].color;
          ctx.fillRect(-7, -5, 3, 10); ctx.fillRect(-2, -5, 3, 10); ctx.fillRect(3, -5, 3, 10);
          break;
        case 'vest':
          ctx.fillStyle = VEST[it.lvl].color;
          ctx.beginPath(); ctx.moveTo(-10, -10); ctx.lineTo(10, -10); ctx.lineTo(12, 10); ctx.lineTo(-12, 10); ctx.closePath(); ctx.fill();
          break;
        case 'helmet':
          ctx.fillStyle = HELMET[it.lvl].color;
          ctx.beginPath(); ctx.arc(0, 0, 10, 0, TAU); ctx.fill();
          break;
        case 'pack':
          ctx.fillStyle = '#6b5a3a';
          ctx.fillRect(-9, -11, 18, 22);
          ctx.fillStyle = '#4a3d27';
          ctx.fillRect(-9, -3, 18, 4);
          break;
        case 'med':
          ctx.fillStyle = MEDS[it.type].color;
          ctx.fillRect(-9, -9, 18, 18);
          ctx.fillStyle = it.type === 'drink' || it.type === 'pills' ? '#333' : '#d33';
          if (it.type === 'drink' || it.type === 'pills') { ctx.fillRect(-3, -6, 6, 12); }
          else { ctx.fillRect(-2, -6, 4, 12); ctx.fillRect(-6, -2, 12, 4); }
          break;
        case 'grenade':
          ctx.fillStyle = '#4c5a34';
          ctx.beginPath(); ctx.arc(0, 0, 8, 0, TAU); ctx.fill();
          ctx.fillStyle = '#999'; ctx.fillRect(-2, -11, 4, 5);
          break;
      }
      if (it.lvl && (it.kind === 'vest' || it.kind === 'helmet' || it.kind === 'pack')) {
        ctx.fillStyle = '#fff';
        ctx.font = 'bold 10px sans-serif';
        ctx.fillText(String(it.lvl), 0, 1);
      }
      ctx.restore();
      if (p.alive && Math.hypot(it.x - p.x, it.y - p.y) < 130) {
        ctx.direction = 'rtl';
        ctx.font = '11px "Segoe UI", Tahoma, sans-serif';
        ctx.fillStyle = 'rgba(0,0,0,0.6)';
        const label = itemLabel(it) + (it.amount > 1 ? ` ×${it.amount}` : '');
        const tw = ctx.measureText(label).width + 8;
        ctx.fillRect(it.x - tw / 2, it.y + 13, tw, 15);
        ctx.fillStyle = '#fff';
        ctx.fillText(label, it.x, it.y + 21);
        ctx.direction = 'inherit';
      }
    }
  }

  function drawUnit(u, v) {
    if (!M.inView(v, u.x, u.y, 60)) return;
    const w = activeWeapon(u);
    ctx.save();
    ctx.translate(u.x, u.y);
    ctx.fillStyle = 'rgba(0,0,0,0.25)';
    ctx.beginPath(); ctx.ellipse(3, 4, u.r + 1, u.r - 2, 0, 0, TAU); ctx.fill();
    ctx.rotate(u.angle);
    // Arms + weapon
    if (w) {
      const len = { pistol: 14, smg: 22, shotgun: 26, ar: 30, dmr: 34, sr: 40, lmg: 34 }[w.cls];
      ctx.fillStyle = '#222';
      ctx.fillRect(u.r - 8, -3, len + 6, 6);
      ctx.fillStyle = '#e0b48a';
      ctx.beginPath(); ctx.arc(u.r - 4, 5, 4.5, 0, TAU); ctx.fill();
      ctx.beginPath(); ctx.arc(u.r + 6, -1, 4.5, 0, TAU); ctx.fill();
    } else {
      const jab = u.punchT > FISTS.rate * 0.5 ? 8 : 0;
      ctx.fillStyle = '#e0b48a';
      ctx.beginPath(); ctx.arc(u.r + 1 + jab, -8, 5, 0, TAU); ctx.fill();
      ctx.beginPath(); ctx.arc(u.r + 1, 8, 5, 0, TAU); ctx.fill();
    }
    // Body (vest colour if wearing one)
    ctx.fillStyle = u.vest ? VEST[u.vest].color : u.clothes;
    ctx.beginPath(); ctx.arc(0, 0, u.r, 0, TAU); ctx.fill();
    if (u.pack) {
      ctx.fillStyle = '#5a4a2e';
      ctx.fillRect(-u.r - 3, -8, 8, 16);
    }
    // Head / helmet
    ctx.fillStyle = u.helmet ? HELMET[u.helmet].color : '#e0b48a';
    ctx.beginPath(); ctx.arc(1, 0, u.r * 0.55, 0, TAU); ctx.fill();
    if (u.hitFlash > 0) {
      ctx.fillStyle = 'rgba(255,255,255,0.6)';
      ctx.beginPath(); ctx.arc(0, 0, u.r, 0, TAU); ctx.fill();
    }
    ctx.restore();
    if (u.isPlayer) {
      ctx.strokeStyle = 'rgba(255, 210, 60, 0.85)';
      ctx.lineWidth = 2;
      ctx.beginPath(); ctx.arc(u.x, u.y, u.r + 5, 0, TAU); ctx.stroke();
    }
    if (u.healT > 0 && u.isPlayer) {
      ctx.strokeStyle = '#7dff9b';
      ctx.lineWidth = 3;
      ctx.beginPath(); ctx.arc(u.x, u.y, u.r + 9, -Math.PI / 2, -Math.PI / 2 + (1 - u.healT / u.healMax) * TAU); ctx.stroke();
    }
  }

  function drawChute(u, v) {
    if (!M.inView(v, u.x, u.y, 200)) return;
    const s = 1 + u.alt * 1.2;
    // Shadow on the ground
    ctx.fillStyle = 'rgba(0,0,0,0.25)';
    ctx.beginPath(); ctx.ellipse(u.x + u.alt * 60, u.y + u.alt * 80, 14, 9, 0, 0, TAU); ctx.fill();
    ctx.save();
    ctx.translate(u.x, u.y);
    ctx.scale(s, s);
    ctx.strokeStyle = 'rgba(255,255,255,0.6)';
    ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(-26, -22); ctx.lineTo(0, 0); ctx.lineTo(26, -22); ctx.stroke();
    ctx.fillStyle = u.isPlayer ? '#f2a900' : '#c84f3a';
    ctx.beginPath(); ctx.ellipse(0, -26, 30, 14, 0, Math.PI, TAU); ctx.fill();
    ctx.fillStyle = 'rgba(255,255,255,0.25)';
    ctx.beginPath(); ctx.ellipse(0, -26, 30, 14, 0, Math.PI, Math.PI * 1.35); ctx.lineTo(0, -26); ctx.fill();
    ctx.fillStyle = u.clothes;
    ctx.beginPath(); ctx.arc(0, 0, 9, 0, TAU); ctx.fill();
    ctx.restore();
  }

  function drawPlane() {
    const pl = G.plane;
    if (!pl || !pl.active) return;
    ctx.save();
    // Shadow
    ctx.translate(pl.x + 120, pl.y + 160);
    ctx.rotate(pl.angle);
    ctx.fillStyle = 'rgba(0,0,0,0.2)';
    planeShape(1.6);
    ctx.restore();
    ctx.save();
    ctx.translate(pl.x, pl.y);
    ctx.rotate(pl.angle);
    ctx.fillStyle = '#c9cdd2';
    planeShape(1.6);
    ctx.fillStyle = '#7b8189';
    ctx.fillRect(40, -6, 30, 12);
    ctx.restore();
  }

  function planeShape(s) {
    ctx.beginPath();
    ctx.ellipse(0, 0, 90 * s, 14 * s, 0, 0, TAU);
    ctx.fill();
    ctx.beginPath();
    ctx.moveTo(10 * s, 0); ctx.lineTo(-20 * s, -95 * s); ctx.lineTo(-38 * s, -95 * s); ctx.lineTo(-20 * s, 0);
    ctx.lineTo(-38 * s, 95 * s); ctx.lineTo(-20 * s, 95 * s); ctx.closePath(); ctx.fill();
    ctx.beginPath();
    ctx.moveTo(-70 * s, 0); ctx.lineTo(-88 * s, -32 * s); ctx.lineTo(-96 * s, -32 * s); ctx.lineTo(-90 * s, 0);
    ctx.lineTo(-96 * s, 32 * s); ctx.lineTo(-88 * s, 32 * s); ctx.closePath(); ctx.fill();
  }

  function drawAirdropsGround(v) {
    for (const d of G.airdrops) {
      if (!d.landed || !M.inView(v, d.x, d.y, 60)) continue;
      ctx.strokeStyle = 'rgba(200,40,40,0.6)';
      ctx.lineWidth = 3;
      ctx.setLineDash([8, 6]);
      ctx.beginPath(); ctx.arc(d.x, d.y, 44, 0, TAU); ctx.stroke();
      ctx.setLineDash([]);
    }
  }

  function drawAirdropsAir(v) {
    for (const d of G.airdrops) {
      if (d.landed || !M.inView(v, d.x, d.y, 300)) continue;
      const s = 1 + d.alt * 1.5;
      ctx.fillStyle = 'rgba(0,0,0,0.25)';
      ctx.beginPath(); ctx.ellipse(d.x + d.alt * 80, d.y + d.alt * 100, 22, 16, 0, 0, TAU); ctx.fill();
      ctx.save();
      ctx.translate(d.x, d.y);
      ctx.scale(s, s);
      ctx.fillStyle = '#d9d9d9';
      ctx.beginPath(); ctx.ellipse(0, -34, 38, 18, 0, Math.PI, TAU); ctx.fill();
      ctx.strokeStyle = '#ddd'; ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(-34, -30); ctx.lineTo(0, 0); ctx.lineTo(34, -30); ctx.stroke();
      ctx.fillStyle = '#2f6fb0';
      ctx.fillRect(-14, -12, 28, 24);
      ctx.fillStyle = '#c9302c';
      ctx.fillRect(-14, -3, 28, 6);
      ctx.restore();
    }
  }

  function drawGrenades() {
    for (const g of G.grenades) {
      ctx.save();
      ctx.translate(g.x, g.y);
      ctx.rotate(g.spin);
      ctx.fillStyle = '#4c5a34';
      ctx.beginPath(); ctx.arc(0, 0, 6, 0, TAU); ctx.fill();
      ctx.fillStyle = '#aaa'; ctx.fillRect(-1.5, -9, 3, 4);
      ctx.restore();
      if (g.fuse < 0.8 && Math.floor(g.fuse * 10) % 2 === 0) {
        ctx.fillStyle = 'rgba(255,60,60,0.6)';
        ctx.beginPath(); ctx.arc(g.x, g.y, 9, 0, TAU); ctx.fill();
      }
    }
  }

  function drawBullets() {
    ctx.lineCap = 'round';
    for (const b of G.bullets) {
      ctx.strokeStyle = b.owner.isPlayer ? 'rgba(255,230,140,0.95)' : 'rgba(255,200,120,0.75)';
      ctx.lineWidth = b.cls === 'sr' ? 3 : 2;
      ctx.beginPath();
      ctx.moveTo(b.x, b.y);
      ctx.lineTo(b.x - b.vx * 0.022, b.y - b.vy * 0.022);
      ctx.stroke();
    }
    ctx.lineCap = 'butt';
  }

  function drawParticles(smoke) {
    for (const pt of G.particles) {
      if (!!pt.smoke !== smoke) continue;
      const a = pt.life / pt.max;
      ctx.globalAlpha = smoke ? a * 0.8 : a;
      ctx.fillStyle = pt.color;
      if (pt.flash || smoke) { ctx.beginPath(); ctx.arc(pt.x, pt.y, pt.size * (pt.flash ? a : 1), 0, TAU); ctx.fill(); }
      else ctx.fillRect(pt.x - pt.size / 2, pt.y - pt.size / 2, pt.size, pt.size);
    }
    ctx.globalAlpha = 1;
  }

  function drawZone(v) {
    const z = G.zone;
    ctx.save();
    ctx.beginPath();
    ctx.rect(v.x0 - 100, v.y0 - 100, v.x1 - v.x0 + 200, v.y1 - v.y0 + 200);
    ctx.arc(z.cx, z.cy, z.r, 0, TAU, true);
    ctx.fillStyle = 'rgba(30, 80, 255, 0.24)';
    ctx.fill('evenodd');
    ctx.restore();
    ctx.strokeStyle = 'rgba(70, 130, 255, 0.95)';
    ctx.lineWidth = 6 / Math.max(0.4, cam.scale);
    ctx.beginPath(); ctx.arc(z.cx, z.cy, z.r, 0, TAU); ctx.stroke();
    if (z.state !== 'done') {
      ctx.strokeStyle = 'rgba(255,255,255,0.9)';
      ctx.lineWidth = 3 / Math.max(0.4, cam.scale);
      ctx.beginPath(); ctx.arc(z.nx, z.ny, Math.max(1, z.nr), 0, TAU); ctx.stroke();
    }
  }

  function drawTexts() {
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.direction = 'ltr';
    for (const t of G.texts) {
      ctx.globalAlpha = Math.min(1, (t.life / t.max) * 2);
      ctx.font = `bold ${t.size}px "Segoe UI", Tahoma, sans-serif`;
      ctx.fillStyle = 'rgba(0,0,0,0.7)';
      ctx.fillText(t.text, t.x + 1, t.y + 1);
      ctx.fillStyle = t.color;
      ctx.fillText(t.text, t.x, t.y);
    }
    ctx.globalAlpha = 1;
    ctx.direction = 'inherit';
  }

  function drawScreenEffects() {
    const p = G.player;
    // Blue tint when outside the zone
    if (p.alive && p.phase === 'ground' && outsideZone(p)) {
      ctx.fillStyle = 'rgba(30, 70, 220, 0.16)';
      ctx.fillRect(0, 0, W, H);
    }
    const low = p.alive && p.hp < 30;
    const intensity = Math.max(hurtT * 1.3, low ? 0.22 + Math.sin(G.time * 6) * 0.08 : 0);
    if (intensity > 0) {
      const g = ctx.createRadialGradient(W / 2, H / 2, Math.min(W, H) * 0.3, W / 2, H / 2, Math.max(W, H) * 0.7);
      g.addColorStop(0, 'rgba(200,0,20,0)');
      g.addColorStop(1, `rgba(200,0,20,${Math.min(0.6, intensity)})`);
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, W, H);
    }
    // Damage direction indicators
    for (const d of dmgIndicators) {
      ctx.save();
      ctx.translate(W / 2, H / 2);
      ctx.rotate(d.a);
      ctx.globalAlpha = Math.min(1, d.t);
      ctx.strokeStyle = '#ff3b3b';
      ctx.lineWidth = 6;
      ctx.beginPath(); ctx.arc(0, 0, 110, -0.28, 0.28); ctx.stroke();
      ctx.restore();
    }
    ctx.globalAlpha = 1;
    // Scope vignette
    if (p.aiming && cam.scale < baseScale() * 0.85) {
      const g = ctx.createRadialGradient(W / 2, H / 2, Math.min(W, H) * 0.42, W / 2, H / 2, Math.max(W, H) * 0.65);
      g.addColorStop(0, 'rgba(0,0,0,0)');
      g.addColorStop(1, 'rgba(0,0,0,0.55)');
      ctx.fillStyle = g;
      ctx.fillRect(0, 0, W, H);
    }
  }

  function drawCrosshair() {
    const p = G.player;
    const { x, y } = mouse;
    const w = activeWeapon(p);
    const moving = Math.hypot(p.vx, p.vy) > 40;
    let spread = w ? w.spread * (p.aiming ? 0.45 : 1) * (moving ? 1.4 : 1) : 0.05;
    const dist = Math.hypot((x - W / 2) / cam.scale, (y - H / 2) / cam.scale);
    const gap = clamp(Math.tan(spread) * dist * cam.scale, 4, 80);
    ctx.strokeStyle = p.reloadT > 0 ? '#ffcf5a' : 'rgba(255,255,255,0.95)';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(x - gap - 8, y); ctx.lineTo(x - gap, y);
    ctx.moveTo(x + gap, y); ctx.lineTo(x + gap + 8, y);
    ctx.moveTo(x, y - gap - 8); ctx.lineTo(x, y - gap);
    ctx.moveTo(x, y + gap); ctx.lineTo(x, y + gap + 8);
    ctx.stroke();
    ctx.fillStyle = '#ff3d4a';
    ctx.fillRect(x - 1, y - 1, 2, 2);
    if (hitMarkT > 0) {
      ctx.strokeStyle = hitMarkHead ? '#ff4040' : '#ffffff';
      ctx.lineWidth = 2.5;
      ctx.beginPath();
      for (const [sx, sy] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) { ctx.moveTo(x + sx * 6, y + sy * 6); ctx.lineTo(x + sx * 13, y + sy * 13); }
      ctx.stroke();
    }
  }

  // Local minimap around the player (bottom-left).
  function drawMinimap() {
    const size = 180, pad = 14;
    const x = pad, y = H - size - pad;
    const p = G.player;
    const range = 1400;
    const s = size / range;
    const cx = p.phase === 'plane' ? G.plane.x : p.x, cy = p.phase === 'plane' ? G.plane.y : p.y;
    const toX = (wx) => x + size / 2 + (wx - cx) * s;
    const toY = (wy) => y + size / 2 + (wy - cy) * s;

    ctx.save();
    ctx.beginPath(); ctx.rect(x, y, size, size); ctx.clip();
    ctx.fillStyle = '#2b5a78';
    ctx.fillRect(x, y, size, size);
    const gs = M.GROUND_SCALE;
    const sx0 = cx - range / 2, sy0 = cy - range / 2;
    ctx.drawImage(G.map.ground, sx0 * gs, sy0 * gs, range * gs, range * gs, x, y, size, size);
    ctx.fillStyle = 'rgba(70,60,50,0.9)';
    for (const b of G.map.buildings) {
      if (b.x > sx0 + range || b.x + b.w < sx0 || b.y > sy0 + range || b.y + b.h < sy0) continue;
      ctx.fillRect(toX(b.x), toY(b.y), b.w * s, b.h * s);
    }
    drawZoneOn(ctx, toX, toY, s);
    for (const d of G.airdrops) {
      ctx.fillStyle = '#e33';
      ctx.fillRect(toX(d.x) - 3, toY(d.y) - 3, 6, 6);
    }
    if (marker) {
      ctx.fillStyle = '#ffd34d';
      ctx.beginPath(); ctx.arc(toX(marker.x), toY(marker.y), 4, 0, TAU); ctx.fill();
    }
    // Guide line to the safe zone when outside it.
    const z = G.zone;
    if (p.alive && p.phase === 'ground') {
      const dz = Math.hypot(p.x - z.nx, p.y - z.ny);
      if (dz > z.nr) {
        ctx.strokeStyle = 'rgba(255,255,255,0.7)';
        ctx.setLineDash([4, 4]);
        ctx.lineWidth = 1.5;
        ctx.beginPath(); ctx.moveTo(toX(p.x), toY(p.y));
        const k = (dz - z.nr) / dz;
        ctx.lineTo(toX(p.x + (z.nx - p.x) * k), toY(p.y + (z.ny - p.y) * k));
        ctx.stroke();
        ctx.setLineDash([]);
      }
    }
    // Player arrow
    ctx.save();
    ctx.translate(toX(cx), toY(cy));
    ctx.rotate(p.phase === 'plane' ? G.plane.angle : p.angle);
    ctx.fillStyle = '#ffd34d';
    ctx.beginPath(); ctx.moveTo(7, 0); ctx.lineTo(-5, -5); ctx.lineTo(-2, 0); ctx.lineTo(-5, 5); ctx.closePath(); ctx.fill();
    ctx.restore();
    ctx.restore();
    ctx.strokeStyle = 'rgba(255,255,255,0.35)';
    ctx.lineWidth = 1;
    ctx.strokeRect(x + 0.5, y + 0.5, size - 1, size - 1);
  }

  function drawZoneOn(c, toX, toY, s) {
    const z = G.zone;
    c.strokeStyle = '#3d7bff';
    c.lineWidth = 2;
    c.beginPath(); c.arc(toX(z.cx), toY(z.cy), z.r * s, 0, TAU); c.stroke();
    if (z.state !== 'done') {
      c.strokeStyle = '#fff';
      c.lineWidth = 1.5;
      c.beginPath(); c.arc(toX(z.nx), toY(z.ny), Math.max(1, z.nr * s), 0, TAU); c.stroke();
    }
  }

  function fullMapRect() {
    const size = Math.min(W, H) - 80;
    return { x: (W - size) / 2, y: (H - size) / 2, size };
  }

  function drawFullMap() {
    const { x, y, size } = fullMapRect();
    const S = G.map.size;
    const s = size / S;
    const toX = (wx) => x + wx * s, toY = (wy) => y + wy * s;
    ctx.fillStyle = 'rgba(0,0,0,0.6)';
    ctx.fillRect(0, 0, W, H);
    ctx.drawImage(G.map.ground, x, y, size, size);
    ctx.fillStyle = 'rgba(60,50,40,0.85)';
    for (const b of G.map.buildings) ctx.fillRect(toX(b.x), toY(b.y), Math.max(2, b.w * s), Math.max(2, b.h * s));
    // Outside-zone tint
    ctx.save();
    ctx.beginPath(); ctx.rect(x, y, size, size); ctx.clip();
    ctx.beginPath();
    ctx.rect(x, y, size, size);
    ctx.arc(toX(G.zone.cx), toY(G.zone.cy), G.zone.r * s, 0, TAU, true);
    ctx.fillStyle = 'rgba(30,80,255,0.22)';
    ctx.fill('evenodd');
    drawZoneOn(ctx, toX, toY, s);
    ctx.restore();
    // Grid letters
    ctx.strokeStyle = 'rgba(255,255,255,0.12)';
    ctx.lineWidth = 1;
    for (let i = 1; i < 8; i++) {
      const k = (size / 8) * i;
      ctx.beginPath(); ctx.moveTo(x + k, y); ctx.lineTo(x + k, y + size); ctx.moveTo(x, y + k); ctx.lineTo(x + size, y + k); ctx.stroke();
    }
    // Plane path
    const pl = G.plane;
    if (pl.active) {
      ctx.strokeStyle = 'rgba(255,255,255,0.6)';
      ctx.setLineDash([8, 6]);
      ctx.beginPath(); ctx.moveTo(toX(pl.x1), toY(pl.y1)); ctx.lineTo(toX(pl.x2), toY(pl.y2)); ctx.stroke();
      ctx.setLineDash([]);
      ctx.fillStyle = '#fff';
      ctx.beginPath(); ctx.arc(toX(pl.x), toY(pl.y), 5, 0, TAU); ctx.fill();
    }
    // Town names
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.font = 'bold 13px "Segoe UI", Tahoma, sans-serif';
    for (const t of G.map.towns) {
      ctx.fillStyle = 'rgba(0,0,0,0.7)';
      ctx.fillText(t.name, toX(t.x) + 1, toY(t.y) + 1);
      ctx.fillStyle = t.military ? '#ffcf5a' : '#fff';
      ctx.fillText(t.name, toX(t.x), toY(t.y));
    }
    for (const d of G.airdrops) {
      ctx.fillStyle = '#e33';
      ctx.fillRect(toX(d.x) - 4, toY(d.y) - 4, 8, 8);
    }
    if (marker) {
      ctx.fillStyle = '#ffd34d';
      ctx.beginPath(); ctx.arc(toX(marker.x), toY(marker.y), 6, 0, TAU); ctx.fill();
    }
    const p = G.player;
    const px = p.phase === 'plane' ? pl.x : p.x, py = p.phase === 'plane' ? pl.y : p.y;
    ctx.save();
    ctx.translate(toX(px), toY(py));
    ctx.rotate(p.phase === 'plane' ? pl.angle : p.angle);
    ctx.fillStyle = '#ffd34d';
    ctx.strokeStyle = '#000';
    ctx.beginPath(); ctx.moveTo(9, 0); ctx.lineTo(-6, -6); ctx.lineTo(-2, 0); ctx.lineTo(-6, 6); ctx.closePath(); ctx.fill(); ctx.stroke();
    ctx.restore();
    ctx.strokeStyle = 'rgba(255,255,255,0.4)';
    ctx.strokeRect(x, y, size, size);
    ctx.fillStyle = '#fff';
    ctx.font = '13px "Segoe UI", Tahoma, sans-serif';
    ctx.fillText('انقر لوضع علامة — M للإغلاق', W / 2, y + size + 20);
  }

  // Menu backdrop: drifting island silhouette and rings.
  let menuT = 0;
  function drawMenuBackdrop() {
    menuT += 1 / 60;
    const cx = W / 2, cy = H / 2;
    const r = Math.min(W, H) * 0.36;
    ctx.fillStyle = '#10161d';
    ctx.fillRect(0, 0, W, H);
    ctx.strokeStyle = 'rgba(70,130,255,0.35)';
    ctx.lineWidth = 3;
    ctx.beginPath(); ctx.arc(cx, cy, r * (1 + Math.sin(menuT * 0.6) * 0.04), 0, TAU); ctx.stroke();
    ctx.strokeStyle = 'rgba(255,255,255,0.25)';
    ctx.lineWidth = 2;
    ctx.beginPath(); ctx.arc(cx + Math.cos(menuT * 0.3) * 40, cy + Math.sin(menuT * 0.3) * 30, r * 0.55, 0, TAU); ctx.stroke();
    // Plane crossing
    const px = ((menuT * 60) % (W + 400)) - 200;
    ctx.save();
    ctx.translate(px, cy - r * 0.6);
    ctx.fillStyle = 'rgba(200,205,210,0.25)';
    planeShape(0.6);
    ctx.restore();
  }

  // ---------- HUD ----------
  const hudCache = {};
  function setText(el, key, v) { if (hudCache[key] !== v) { hudCache[key] = v; el.textContent = v; } }
  function setHTML(el, key, v) { if (hudCache[key] !== v) { hudCache[key] = v; el.innerHTML = v; } }
  function setClass(el, key, cls) { if (hudCache[key] !== cls) { hudCache[key] = cls; el.className = cls; } }
  const H$ = {
    alive: $('hud-alive'), kills: $('hud-kills'), zone: $('zone-info'), prompt: $('prompt'), pickups: $('pickup-list'),
    action: $('action'), actionLabel: $('action-label'), actionFill: $('action-fill'),
    hpFill: $('hp-fill'), hpGhost: $('hp-ghost'), boost: $('boost-fill'), mag: $('hud-mag'), reserve: $('hud-reserve'), ammoType: $('hud-ammo-type'), ammoLine: $('ammo-line'),
    slots: [...document.querySelectorAll('.wslot')], meds: [...document.querySelectorAll('.med')],
    helmet: $('gear-helmet'), vest: $('gear-vest'), pack: $('gear-pack'),
  };
  let nearbyItems = [];

  function updateHud() {
    const p = G.player;
    setText(H$.alive, 'alive', String(aliveCount()));
    setText(H$.kills, 'kills', String(p.kills));

    const z = G.zone;
    let zt, zc = 'pill';
    if (z.state === 'wait') zt = `تقلص المنطقة خلال ${fmtTime(z.timer)}`;
    else if (z.state === 'shrink') { zt = `المنطقة تتقلص ${fmtTime(z.timer)}`; zc += ' shrinking'; }
    else zt = 'المنطقة النهائية';
    if (p.alive && p.phase === 'ground' && outsideZone(p)) { zt = `⚠ خارج المنطقة — ${zt}`; zc += ' outside'; }
    setText(H$.zone, 'zone', zt);
    setClass(H$.zone, 'zoneC', zc);

    // Health / boost
    const hp = Math.max(0, p.hp);
    H$.hpFill.style.width = hp + '%';
    H$.hpGhost.style.width = hp + '%';
    setClass(H$.hpFill, 'hpC', hp < 30 ? 'low' : hp < 60 ? 'mid' : '');
    H$.boost.style.width = p.boost + '%';

    // Weapons
    H$.slots.forEach((el, i) => {
      const s = p.slots[i];
      const name = s ? WEAPONS[s.type].name : 'فارغ';
      setText(el.children[1], 'wn' + i, name);
      setText(el.children[2], 'wa' + i, s ? `${s.mag}/${p.ammo[WEAPONS[s.type].ammo]}` : '');
      setClass(el, 'ws' + i, 'wslot' + (s ? ' filled' : '') + (p.active === i ? ' active' : ''));
    });
    const s = p.slots[p.active];
    if (s) {
      const w = WEAPONS[s.type];
      setText(H$.mag, 'mag', p.reloadT > 0 ? '…' : String(s.mag));
      setText(H$.reserve, 'res', `/ ${p.ammo[w.ammo]}`);
      setText(H$.ammoType, 'amT', AMMO[w.ammo].name);
      setClass(H$.ammoLine, 'amC', s.mag === 0 ? 'empty' : '');
    } else {
      setText(H$.mag, 'mag', '✊');
      setText(H$.reserve, 'res', '');
      setText(H$.ammoType, 'amT', '');
      setClass(H$.ammoLine, 'amC', '');
    }

    // Meds
    H$.meds.forEach((el) => {
      const k = el.dataset.med;
      const n = k === 'grenade' ? p.grenades : p.meds[k];
      setText(el.lastElementChild, 'm' + k, String(n));
      setClass(el, 'mc' + k, 'med' + (n > 0 ? ' has' : ''));
    });

    // Gear
    const gear = (el, key, lvl, dur, max) => {
      setText(el.children[1], 'g' + key, lvl ? 'Lv' + lvl : '-');
      setClass(el, 'gc' + key, 'gear-item' + (lvl ? ' on l' + lvl : ''));
      if (el.children[2]) el.children[2].style.width = lvl ? `${clamp(dur / max, 0, 1) * 100}%` : '0';
    };
    gear(H$.helmet, 'h', p.helmet, p.helmetDur, p.helmet ? HELMET[p.helmet].dur : 1);
    gear(H$.vest, 'v', p.vest, p.vestDur, p.vest ? VEST[p.vest].dur : 1);
    gear(H$.pack, 'p', p.pack, 1, 1);

    // Action bar (reload / heal)
    if (p.healT > 0) {
      H$.action.classList.remove('hidden');
      setText(H$.actionLabel, 'act', `استخدام ${MEDS[p.healType].name}…`);
      H$.actionFill.style.width = `${(1 - p.healT / p.healMax) * 100}%`;
    } else if (p.reloadT > 0) {
      H$.action.classList.remove('hidden');
      setText(H$.actionLabel, 'act', 'إعادة تلقيم…');
      H$.actionFill.style.width = `${(1 - p.reloadT / p.reloadMax) * 100}%`;
    } else H$.action.classList.add('hidden');

    // Prompt + nearby items
    let prompt = '';
    nearbyItems = [];
    if (p.phase === 'plane') prompt = planeOverLand() ? 'اضغط <kbd>F</kbd> للقفز من الطائرة' : 'الطائرة تقترب من الجزيرة…';
    else if (p.phase === 'ground' && p.alive) {
      for (const it of G.items) {
        const d = Math.hypot(it.x - p.x, it.y - p.y);
        if (d < 70) nearbyItems.push({ it, d });
      }
      nearbyItems.sort((a, b) => a.d - b.d);
      nearbyItems = nearbyItems.slice(0, 7).map((o) => o.it);
    }
    setHTML(H$.prompt, 'prompt', prompt);
    H$.prompt.classList.toggle('hidden', !prompt);
    const listKey = nearbyItems.map((it) => it.id + ':' + it.amount).join(',');
    if (hudCache.list !== listKey) {
      hudCache.list = listKey;
      H$.pickups.innerHTML = '';
      nearbyItems.forEach((it, i) => {
        const el = document.createElement('div');
        el.className = 'pk' + (i === 0 ? ' first' : '');
        const name = document.createElement('span');
        name.textContent = itemLabel(it);
        const right = document.createElement('span');
        if (i === 0) { right.className = 'f'; right.textContent = 'F'; }
        else if (it.amount > 1) { right.className = 'amt'; right.textContent = '×' + it.amount; }
        el.append(name, right);
        el.addEventListener('mousedown', (e) => { e.stopPropagation(); pickup(G.player, it); });
        H$.pickups.appendChild(el);
      });
    }
  }

  // ---------- Input handlers ----------
  window.addEventListener('keydown', (e) => {
    if (e.target && e.target.tagName === 'INPUT') return;
    if (e.code === 'Tab') e.preventDefault();
    if (e.repeat) return;
    keys.add(e.code);
    Sound.init();
    if (e.code === 'KeyN') toggleMute();
    if (state === 'playing') {
      const p = G.player;
      if (e.code === 'Escape') { if (mapOpen) toggleMap(false); else pauseGame(); }
      else if (e.code === 'KeyM' || e.code === 'Tab') toggleMap();
      else if (!p.alive) return;
      else if (e.code === 'KeyF') { if (p.phase === 'plane') jump(p); else if (nearbyItems[0]) pickup(p, nearbyItems[0]); }
      else if (e.code === 'KeyR') startReload(p);
      else if (e.code === 'Digit1') switchSlot(p, 0);
      else if (e.code === 'Digit2') switchSlot(p, 1);
      else if (e.code === 'Digit3') switchSlot(p, 2);
      else if (e.code === 'KeyX') switchSlot(p, -1);
      else if (e.code === 'KeyG') throwGrenade(p, cam.x + (mouse.x - W / 2) / cam.scale, cam.y + (mouse.y - H / 2) / cam.scale);
      else {
        const med = MED_ORDER.find((m) => 'Digit' + MEDS[m].key === e.code);
        if (med && !useMed(p, med) && p.meds[med] > 0) showBanner('', p.hp >= 75 && med !== 'medkit' && !MEDS[med].boost ? 'لا يمكن الشفاء أكثر بهذا الغرض' : '', 1200);
      }
      if (e.code === 'Space') e.preventDefault();
    } else if (state === 'paused' && e.code === 'Escape') resumeGame();
  });
  window.addEventListener('keyup', (e) => keys.delete(e.code));
  window.addEventListener('mousemove', (e) => { mouse.x = e.clientX; mouse.y = e.clientY; });
  window.addEventListener('mousedown', (e) => {
    Sound.init();
    if (state !== 'playing') return;
    if (mapOpen && e.button === 0) {
      const { x, y, size } = fullMapRect();
      if (e.clientX >= x && e.clientX <= x + size && e.clientY >= y && e.clientY <= y + size) {
        const S = G.map.size;
        const mx = ((e.clientX - x) / size) * S, my = ((e.clientY - y) / size) * S;
        marker = marker && Math.hypot(marker.x - mx, marker.y - my) < 80 ? null : { x: mx, y: my };
      }
      return;
    }
    if (e.button === 0) { mouse.down = true; shotQueueT = 0.2; }
    if (e.button === 2) mouse.right = true;
  });
  window.addEventListener('mouseup', (e) => {
    if (e.button === 0) mouse.down = false;
    if (e.button === 2) mouse.right = false;
  });
  window.addEventListener('wheel', (e) => {
    if (state !== 'playing' || !G.player.alive) return;
    const p = G.player;
    const owned = [0, 1, 2].filter((i) => p.slots[i]);
    if (!owned.length) return;
    const idx = owned.indexOf(p.active);
    const next = owned[(idx + (e.deltaY > 0 ? 1 : -1) + owned.length) % owned.length];
    switchSlot(p, next);
  }, { passive: true });
  window.addEventListener('contextmenu', (e) => e.preventDefault());
  window.addEventListener('blur', () => {
    keys.clear();
    mouse.down = false; mouse.right = false;
    if (state === 'playing') pauseGame();
  });

  function toggleMap(force) {
    mapOpen = force === undefined ? !mapOpen : force;
    document.body.classList.toggle('map-open', mapOpen);
    mouse.down = false;
  }

  // ---------- State transitions ----------
  const overlays = ['menu', 'help', 'pause', 'results'];
  function showOverlay(id) { overlays.forEach((o) => $(o).classList.toggle('hidden', o !== id)); }

  function startGame() {
    Sound.init();
    if (document.activeElement) document.activeElement.blur();
    $('killfeed').innerHTML = '';
    Object.keys(hudCache).forEach((k) => delete hudCache[k]);
    newMatch();
    state = 'playing';
    showOverlay(null);
    $('hud').classList.remove('hidden');
    document.body.classList.add('playing');
    lastTime = performance.now();
  }

  function pauseGame() {
    if (state !== 'playing') return;
    state = 'paused';
    mouse.down = false;
    shake = 0;
    Sound.setHum(false);
    showOverlay('pause');
    document.body.classList.remove('playing');
  }

  function resumeGame() {
    if (state !== 'paused') return;
    state = 'playing';
    showOverlay(null);
    document.body.classList.add('playing');
    if (G.player.phase === 'plane') Sound.setHum(true);
    lastTime = performance.now();
  }

  function endMatch(won) {
    if (matchResult) return;
    const p = G.player;
    const rank = won ? 1 : aliveCount() + 1;
    matchResult = { won, rank };
    Sound.setHum(false);
    Sound.play(won ? 'win' : 'over');
    if (won) showBanner('فوز!', 'أنت الناجي الأخير', 3000);

    const stats = store.get('zz_stats', { wins: 0, best: 0, kills: 0, games: 0 });
    stats.games++;
    stats.kills += p.kills;
    if (won) stats.wins++;
    if (!stats.best || rank < stats.best) stats.best = rank;
    store.set('zz_stats', stats);

    $('res-win').classList.toggle('hidden', !won);
    $('res-title').textContent = `#${rank}`;
    $('res-sub').textContent = `من أصل ${G.units.length} لاعباً`;
    $('res-kills').textContent = String(p.kills);
    $('res-damage').textContent = String(Math.round(p.damage));
    $('res-time').textContent = fmtTime(won ? G.time : p.deathTime);
    $('res-acc').textContent = p.shots ? `${Math.round((100 * (p.hits || 0)) / p.shots)}%` : '-';
    let killerText = '';
    if (!won) {
      if (p.killer) {
        const wn = p.killerWeapon === 'grenade' ? 'قنبلة' : p.killerWeapon === 'fists' ? 'قبضة' : WEAPONS[p.killerWeapon] ? WEAPONS[p.killerWeapon].name : '';
        killerText = `قُتلت على يد ${p.killer.name} بسلاح ${wn}`;
      } else killerText = 'مت في المنطقة الزرقاء';
    }
    $('res-killer').textContent = killerText;
    setTimeout(() => {
      if (!matchResult) return;
      state = 'over';
      document.body.classList.remove('playing');
      toggleMap(false);
      showOverlay('results');
    }, won ? 2500 : 1800);
  }

  function goToMenu() {
    state = 'menu';
    G.map = null;
    matchResult = null;
    Sound.setHum(false);
    $('hud').classList.add('hidden');
    document.body.classList.remove('playing');
    refreshMenuStats();
    showOverlay('menu');
  }

  function refreshMenuStats() {
    const st = store.get('zz_stats', { wins: 0, best: 0, kills: 0, games: 0 });
    $('st-wins').textContent = String(st.wins);
    $('st-best').textContent = st.best ? '#' + st.best : '-';
    $('st-kills').textContent = String(st.kills);
    $('st-games').textContent = String(st.games);
    document.querySelectorAll('#diff-seg button').forEach((b) => b.classList.toggle('on', b.dataset.diff === difficulty));
    if (ZZ.onMenuRefresh) ZZ.onMenuRefresh(st);
  }

  function toggleMute() {
    Sound.setMuted(!Sound.muted);
    store.set('zz_muted', Sound.muted);
    $('btn-sound').textContent = Sound.muted ? 'الصوت: مكتوم' : 'الصوت: يعمل';
  }

  $('btn-start').addEventListener('click', startGame);
  $('btn-help').addEventListener('click', () => showOverlay('help'));
  $('btn-help-back').addEventListener('click', () => showOverlay(G.map && state === 'paused' ? 'pause' : 'menu'));
  $('btn-sound').addEventListener('click', () => { Sound.init(); toggleMute(); });
  $('btn-quit').addEventListener('click', () => window.close());
  $('btn-resume').addEventListener('click', resumeGame);
  $('btn-restart').addEventListener('click', startGame);
  $('btn-menu').addEventListener('click', goToMenu);
  $('btn-again').addEventListener('click', startGame);
  $('btn-res-menu').addEventListener('click', goToMenu);
  document.querySelectorAll('#diff-seg button').forEach((b) => b.addEventListener('click', () => {
    difficulty = b.dataset.diff;
    store.set('zz_diff', difficulty);
    refreshMenuStats();
  }));

  if (store.get('zz_muted', false)) toggleMute();
  refreshMenuStats();

  // Bots call into the world through these.
  Object.assign(G, {
    tryFire, startReload, switchSlot, pickup, useMed, throwGrenade,
    segmentHit: (x1, y1, x2, y2) => M.segmentHit(G.map, x1, y1, x2, y2),
    buildingAt: (x, y) => M.buildingAt(G.map, x, y),
  });

  // ---------- Main loop ----------
  let lastTime = performance.now();
  let hudT = 0;
  function frame(now) {
    const rawDt = Math.min(0.05, (now - lastTime) / 1000);
    lastTime = now;
    if (state === 'playing') {
      // Fixed sub-steps keep fast-forwarded debug runs stable.
      const total = rawDt * DEBUG.speed;
      const steps = Math.ceil(total / 0.034);
      for (let i = 0; i < steps; i++) update(total / steps);
      hudT -= rawDt;
      if (hudT <= 0) { hudT = 0.05; updateHud(); }
    } else if (state === 'over' && G.map) {
      updateEffects(rawDt);
    }
    render();
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);

  if (params.get('debug') === '1') window.__G = G;

  // Read-only hook used by automated smoke tests.
  window.__zeroZone = {
    get state() { return state; },
    get alive() { return G.map ? aliveCount() : 0; },
    get time() { return G.time; },
    get zone() { return G.zone && { phase: G.zone.phase, state: G.zone.state, r: Math.round(G.zone.r) }; },
    get player() { const p = G.player; return p && { x: p.x, y: p.y, hp: p.hp, phase: p.phase, alive: p.alive, kills: p.kills, slots: p.slots.map((s) => s && s.type), ammo: p.ammo, vest: p.vest, helmet: p.helmet, meds: p.meds }; },
    get result() { return matchResult; },
    get items() { return G.items.length; },
    get deathsBy() { const o = {}; G.units.forEach((u) => { if (!u.alive) o[u.killerWeapon] = (o[u.killerWeapon] || 0) + 1; }); return o; },
    get zoneDeaths() { return G.units.filter((u) => !u.alive && !u.killer).length; },
    get bots() { return G.units.filter((u) => !u.isPlayer && u.alive).map((u) => ({ phase: u.phase, mode: u.ai.mode, armed: !!u.slots.find(Boolean), hp: Math.round(u.hp) })); },
    nearest() {
      const p = G.player;
      let best = null, bd = Infinity;
      for (const u of G.units) {
        if (u === p || !u.alive || u.phase !== 'ground') continue;
        const d = Math.hypot(u.x - p.x, u.y - p.y);
        if (d < bd) { bd = d; best = u; }
      }
      return best && { sx: (best.x - cam.x) * cam.scale + W / 2, sy: (best.y - cam.y) * cam.scale + H / 2, d: bd };
    },
    nearestItem() {
      const p = G.player;
      let best = null, bd = Infinity;
      for (const it of G.items) {
        if (it.kind !== 'weapon') continue;
        const d = Math.hypot(it.x - p.x, it.y - p.y);
        if (d < bd) { bd = d; best = it; }
      }
      return best && { x: best.x, y: best.y, d: bd };
    },
  };
})();
