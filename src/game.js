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
    noRender: params.get('norender') === '1', // skip 3D drawing in long automated simulations
  };

  // 3D world on #game (WebGL), HUD graphics (minimap, crosshair, labels) on #overlay (2D).
  let R3;
  try {
    R3 = new ZZ.Renderer3D($('game'));
  } catch (err) {
    document.querySelector('#menu .tagline').textContent = 'تعذّر تشغيل الرسوميات ثلاثية الأبعاد (WebGL) على هذا الجهاز. حدّث تعريف كرت الشاشة ثم أعد المحاولة.';
    $('btn-start').disabled = true;
    throw err;
  }
  const HT = ZZ.HEIGHTS;
  const LOBBY = new ZZ.Lobby3D(R3.renderer);
  const canvas = $('overlay');
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
    R3.resize(W, H);
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
  const OUTFITS = ['#2d6fb8', '#3f5f3a', '#7a2f2f', '#2b2b2e', '#c9b48a', '#5e4a6b'];
  const profile = Object.assign({ name: '', outfit: 0 }, store.get('zz_profile', {}));
  // On-screen buttons by default (like mobile battle royales); keyboard + mouse can be chosen in settings.
  const settings = Object.assign({ ctrl: 'touch', gfx: 'high' }, store.get('zz_settings', {}));
  let difficulty = store.get('zz_diff', 'normal');
  if (!DIFFICULTY[difficulty]) difficulty = 'normal';

  // ---------- Input ----------
  const keys = new Set();
  const mouse = { x: W / 2, y: H / 2, down: false, right: false };
  const look = { yaw: 0, pitch: -0.12, sens: store.get('zz_sens', 0.0024) };
  let shotQueueT = 0;
  let aimPoint = { x: 0, y: 0 };

  // ---------- Game state ----------
  // G is the shared world object; bots act through the same functions as the player.
  const G = {
    time: 0, map: null, units: [], items: [], bullets: [], grenades: [], particles: [], decals: [], texts: [],
    zone: null, plane: null, airdrops: [], player: null, killfeed: [],
    broken: [], insideIdx: -1, uavT: 0, arenaUsed: false, duel: null,
  };
  let state = 'menu'; // menu | playing | paused | over
  // 3D camera: position (x, y=height, z), look target, field of view, focus point on the ground.
  const cam = { x: 0, y: 0, z: 0, tx: 0, ty: 0, tz: 0, fov: 70, fx: 0, fz: 0, hidePlayer: false };
  let shake = 0, hurtT = 0, hitMarkT = 0, hitMarkHead = false;
  let dmgIndicators = [];
  let mapOpen = false, marker = null;
  let nextItemId = 1, nextUnitId = 1;
  let matchResult = null;
  let alivePrev = 0;

  // ---------- Units ----------
  const CLOTHES = ['#5b6b4a', '#6b5a48', '#3f4f5f', '#704848', '#56565e', '#7a6a3a', '#4a5d6b', '#5e4a6b'];

  function makeUnit(name, isPlayer, skill) {
    const u = {
      id: nextUnitId++, name, isPlayer, skill,
      x: 0, y: 0, r: 15, angle: 0, vx: 0, vy: 0,
      hp: 100, alive: true, phase: 'plane', altM: 0, airV: 0,
      stance: 'stand', jumpT: 0,
      slots: [null, null, null], active: -1,
      ammo: { '9mm': 0, '556': 0, '762': 0, '12g': 0, '300': 0 },
      meds: { bandage: 0, firstaid: 0, medkit: 0, drink: 0, pills: 0 },
      grenades: 0, vest: 0, vestDur: 0, helmet: 0, helmetDur: 0, pack: 0, boost: 0,
      fireCd: 0, reloadT: 0, reloadMax: 0, healT: 0, healMax: 0, healType: null, punchT: 0,
      aiming: false, sprint: false, moveX: 0, moveY: 0, slideT: 0, slideCd: 0, inDuel: false,
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
    if (u.stance === 'crouch') spread *= 0.78;
    else if (u.stance === 'prone') spread *= 0.55;
    if (u.jumpT > 0) spread *= 2.5;
    if (!u.isPlayer) spread += 0.03 + (1 - u.skill) * 0.07;
    const mx = u.x + Math.cos(u.angle) * (u.r + 14), my = u.y + Math.sin(u.angle) * (u.r + 14);
    // Vertical aim: bullets fly from chest height toward the target's chest (or the crosshair point).
    const y0 = ZZ.groundY(G.map, u.x, u.y) + chestOf(u);
    let slope = 0;
    const tgt = u.isPlayer ? aimPoint : u.ai && u.ai.target;
    if (tgt) {
      const ty = ZZ.groundY(G.map, tgt.x, tgt.y) + (u.isPlayer ? HT.chest : chestOf(tgt));
      const dd = Math.hypot(tgt.x - u.x, tgt.y - u.y);
      if (dd > 30) slope = clamp((ty - y0) / dd, -0.6, 0.6);
    }
    for (let i = 0; i < w.pellets; i++) {
      const a = u.angle + (Math.random() + Math.random() - 1) * spread;
      const sp = w.speed * (w.pellets > 1 ? rand(0.85, 1.05) : 1);
      G.bullets.push({
        x: mx, y: my, px: u.x, py: u.y, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp,
        life: (w.range / w.speed) * (w.pellets > 1 ? rand(0.8, 1) : 1),
        dmg: w.dmg, owner: u, weapon: s.type, cls: w.cls, y0, slope, dist: 0,
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

  function chestOf(u) { return u.stance === 'prone' ? 6 : u.stance === 'crouch' ? 19 : HT.chest; }

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
      G.particles.push({ x: g.x, y: g.y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: rand(0.3, 0.8), max: 0.8, color: i % 3 ? '#ffb347' : '#555', size: rand(4, 10), h: rand(5, 70), vh: 40 });
    }
    G.decals.push({ x: g.x, y: g.y, r: 34, t: 30, color: 'rgba(40,36,28,0.35)' });
    // Battlefield-style destruction: blow holes in nearby walls and crates.
    for (const o of M.destroyAt(G.map, g.x, g.y, 78)) {
      G.broken.push(o);
      const cx = o.x + o.w / 2, cy = o.y + o.h / 2;
      for (let i = 0; i < 14; i++) {
        const a = rand(0, TAU), sp = rand(40, 260);
        G.particles.push({ x: cx, y: cy, vx: Math.cos(a) * sp, vy: Math.sin(a) * sp, life: rand(0.5, 1.1), max: 1.1, color: o.kind === 'crate' ? '#8a6a3e' : '#b8a68a', size: 4, h: rand(5, 90), vh: -60 });
      }
    }
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
    const wasDuel = t.inDuel;
    if (wasDuel) endDuel(t);
    if (t.killer && t.killer.isPlayer) {
      Sound.play('kill');
      showBanner(`قتلت ${t.name}`, `${t.killer.kills} قتيل`, 1600);
      // Kill streak reward: a recon drone reveals enemies on the maps.
      if (t.killer.kills % 3 === 0) {
        G.uavT = 25;
        Sound.play('uav');
        showBanner('طائرة استطلاع!', 'مواقع الأعداء ظاهرة على الخريطة لمدة 25 ثانية', 2600);
      }
    }
    if (t.isPlayer) {
      if (!wasDuel && canSecondChance()) startDuel();
      else endMatch(false);
    } else if (G.player && G.player.alive && aliveCount() === 1) endMatch(true);
  }

  // ---------- Second chance arena ----------
  // The first time the player dies early, they duel the most recently fallen
  // bot in the arena. The winner parachutes back into the match.
  function canSecondChance() {
    return !G.arenaUsed && G.zone.phase < 3 && G.units.some((u) => !u.isPlayer && !u.alive) && aliveCount() >= 2;
  }

  function startDuel() {
    const p = G.player;
    G.arenaUsed = true;
    let opp = null;
    for (const u of G.units) if (!u.isPlayer && !u.alive && (!opp || u.deathTime > opp.deathTime)) opp = u;
    const A = G.map.arena;
    const gun = ['p92', 'ump', 's1897', 'vector'][Math.floor(Math.random() * 4)];
    const w = WEAPONS[gun];
    for (const u of [p, opp]) {
      Object.assign(u, {
        alive: true, hp: 100, inDuel: true, phase: 'ground', altM: 0, stance: 'stand',
        slots: [null, null, null], grenades: 0, vest: 0, vestDur: 0, helmet: 0, helmetDur: 0, pack: 0, boost: 0,
        healT: 0, healType: null, reloadT: 0, slideT: 0, fireCd: 1, killer: null, lastHitBy: null,
      });
      u.ammo = { '9mm': 0, '556': 0, '762': 0, '12g': 0, '300': 0 };
      u.meds = { bandage: 2, firstaid: 0, medkit: 0, drink: 0, pills: 0 };
      const slot = w.cls === 'pistol' ? 2 : 0;
      u.slots[slot] = { type: gun, mag: w.mag };
      u.active = slot;
      u.ammo[w.ammo] = w.mag * 3;
    }
    p.x = A.spawnA.x; p.y = A.spawnA.y;
    opp.x = A.spawnB.x; opp.y = A.spawnB.y;
    look.yaw = p.angle = Math.atan2(opp.y - p.y, opp.x - p.x);
    look.pitch = -0.1;
    ZZ.AI.init(opp);
    opp.ai.aggro = 1;
    opp.landT = -999;
    G.duel = { opp };
    G.duelZone = { cx: A.x + A.w / 2, cy: A.y + A.h / 2, r: 260, nx: A.x + A.w / 2, ny: A.y + A.h / 2, nr: 260, state: 'wait', timer: 999, dps: 0, phase: G.zone.phase };
    showBanner('الفرصة الثانية!', `مبارزة ضد ${opp.name} — اربح لتعود إلى المعركة`, 3200);
    addKillfeedText('⚔ مبارزة الفرصة الثانية بدأت');
    Sound.play('zone');
  }

  function endDuel(loser) {
    const winner = loser.isPlayer ? G.duel.opp : G.player;
    G.duel = null;
    loser.inDuel = false;
    winner.inDuel = false;
    // Winner redeploys by parachute inside the next safe zone.
    const z = G.zone;
    const a = rand(0, TAU), d = Math.sqrt(Math.random()) * Math.max(50, z.nr * 0.7);
    winner.phase = 'chute';
    winner.altM = 260;
    winner.hp = 100;
    winner.x = clamp(z.nx + Math.cos(a) * d, 200, G.map.size - 200);
    winner.y = clamp(z.ny + Math.sin(a) * d, 200, G.map.size - 200);
    winner.dropX = winner.x; winner.dropY = winner.y;
    if (winner.isPlayer) {
      showBanner('عدت إلى المعركة!', 'وجّه المظلة وابحث عن سلاح', 2600);
      Sound.play('jump');
    }
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
    G.broken = []; G.insideIdx = -1; G.uavT = 0; G.arenaUsed = false; G.duel = null;
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
    G.zone = { phase: 0, state: 'wait', timer: ZONE_PHASES[0].wait, cx: S / 2, cy: S * 0.52, r: S * 0.72, dps: 0.4 };
    pickNextZone();

    // Units
    const player = makeUnit(profile.name || 'أنت', true, 1);
    player.clothes = OUTFITS[profile.outfit] || OUTFITS[0];
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
          if (!M.isLand(G.map, tx, ty)) continue;
        }
        const minGap = k < 15 ? 380 : 200;
        if (!G.units.some((o) => !o.isPlayer && Math.hypot(o.dropX - tx, o.dropY - ty) < minGap)) break;
      }
      b.dropX = clamp(tx, 100, S - 100); b.dropY = clamp(ty, 100, S - 100);
      if (M.inArena(G.map, b.dropX, b.dropY)) { b.dropX += G.map.arena.w; b.dropY += G.map.arena.h; }
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
    look.yaw = G.plane.angle;
    look.pitch = -0.75;
    R3.buildWorld(G);
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
    const pl = G.plane;
    return M.isLand(G.map, pl.x, pl.y);
  }

  const PLANE_ALT = 800;   // metres
  const CHUTE_AUTO = 160;  // the parachute opens automatically at this altitude

  function jump(u) {
    if (u.phase !== 'plane') return;
    const S = G.map.size;
    if (u.isPlayer && !planeOverLand() && G.plane.t < 0.97) {
      showBanner('', 'انتظر حتى تصل الطائرة فوق الجزيرة', 1200);
      return;
    }
    u.phase = 'fall';
    u.altM = PLANE_ALT;
    u.x = clamp(u.x, 120, S - 120);
    u.y = clamp(u.y, 120, S - 120);
    if (u.isPlayer) {
      Sound.play('jump');
      Sound.setHum(false);
      showBanner('', 'اضغط للأمام للغوص أسرع — F لفتح المظلة', 2400);
    }
  }

  function openChute(u) {
    if (u.phase !== 'fall' || u.altM > PLANE_ALT - 60) return;
    u.phase = 'chute';
    if (u.isPlayer) Sound.play('chute');
  }

  // Free fall then parachute. Diving (forward) falls and travels faster.
  function updateAir(u, dt) {
    let mx = 0, my = 0, dive = 0;
    if (u.isPlayer) {
      [mx, my] = moveInput();
      if (mx || my) dive = Math.max(0, mx * Math.cos(look.yaw) + my * Math.sin(look.yaw));
      if (mx || my) u.angle = Math.atan2(my, mx); else u.angle = look.yaw;
    } else {
      const dx = u.dropX - u.x, dy = u.dropY - u.y;
      const d = Math.hypot(dx, dy);
      if (d > 30) { mx = dx / d; my = dy / d; dive = d > 900 ? 1 : 0.3; u.angle = Math.atan2(dy, dx); }
    }
    const l = Math.hypot(mx, my);
    let hs, vs;
    if (u.phase === 'fall') {
      hs = l ? 170 + 170 * dive : 0;
      vs = 50 + 16 * dive;
      if (u.altM <= CHUTE_AUTO) openChute(u);
    } else {
      hs = l ? 220 + 40 * dive : 0;
      vs = 13;
    }
    if (l) { u.x += (mx / l) * hs * dt; u.y += (my / l) * hs * dt; }
    u.airV = Math.hypot(hs * 0.12, vs) * 3.6; // km/h for the HUD
    u.vx = l ? (mx / l) * hs : 0; u.vy = l ? (my / l) * hs : 0;
    u.altM -= vs * dt;
    const S = G.map.size;
    u.x = clamp(u.x, 60, S - 60); u.y = clamp(u.y, 60, S - 60);
    if (u.altM <= 0) land(u);
  }

  function land(u) {
    u.altM = 0;
    u.phase = 'ground';
    u.stance = 'stand';
    // Never land in deep water or inside the arena: slide to the nearest dry spot.
    const map = G.map;
    if (M.inArena(map, u.x, u.y) || !M.isLand(map, u.x, u.y)) {
      let best = null;
      for (let r = 40; r < 3000 && !best; r += 40) {
        for (let k = 0; k < 16; k++) {
          const a = (k / 16) * TAU;
          const x = u.x + Math.cos(a) * r, y = u.y + Math.sin(a) * r;
          if (M.isLand(map, x, y) && !M.inArena(map, x, y)) { best = { x, y }; break; }
        }
      }
      if (best) { u.x = best.x; u.y = best.y; }
    }
    u.landT = G.time;
    M.collideCircle(map, u);
    if (u.isPlayer) { Sound.play('land'); showBanner('', 'اجمع الأسلحة بسرعة!', 1800); }
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
      if (!M.isLand(G.map, x, y) && i < 35) continue; // keep the circle centred on land
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
      if (M.isFree(G.map, px, py, 40) && M.buildingAt(G.map, px, py) < 0 && M.isLand(G.map, px, py)) { x = px; y = py; break; }
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
      if (u.phase === 'fall' || u.phase === 'chute') { updateAir(u, dt); continue; }
      if (u.phase !== 'ground') continue;
      if (!u.isPlayer) ZZ.AI.update(u, dt, G);
      updateUnit(u, dt);
    }
    separateUnits();
    updateBullets(dt);
    updateGrenades(dt);
    updateEffects(dt);

    // The roof of the building the player is in is hidden by the renderer.
    G.insideIdx = p.phase === 'ground' && p.alive ? M.buildingAt(G.map, p.x, p.y) : -1;
    G.uavT = Math.max(0, G.uavT - dt);

    const alive = aliveCount();
    if (alive !== alivePrev) alivePrev = alive;
    updateCamera(dt);
  }

  function updatePlayerInput(dt) {
    const p = G.player;
    if (p.phase === 'plane') {
      return;
    }
    const [mx, my] = moveInput();
    p.moveX = mx;
    p.moveY = my;
    if (p.phase !== 'ground') return;

    // Face where the crosshair points.
    const dx = aimPoint.x - p.x, dy = aimPoint.y - p.y;
    p.angle = Math.hypot(dx, dy) > 40 ? Math.atan2(dy, dx) : look.yaw;
    p.aiming = mouse.right && !mapOpen && p.healT <= 0;
    const touchSprint = ZZ.Touch.enabled && (ZZ.Touch.sprintLock || ZZ.Touch.move.y < -0.92);
    p.sprint = (keys.has('ShiftLeft') || keys.has('ShiftRight') || touchSprint) && !p.aiming && p.healT <= 0 && p.stance !== 'prone';
    if (p.sprint && p.stance === 'crouch' && p.slideT <= 0) p.stance = 'stand';

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

  // WASD relative to the camera direction, as a normalised ground vector.
  function moveInput() {
    let f = 0, r = 0;
    if (keys.has('KeyW') || keys.has('ArrowUp')) f += 1;
    if (keys.has('KeyS') || keys.has('ArrowDown')) f -= 1;
    if (keys.has('KeyD') || keys.has('ArrowRight')) r += 1;
    if (keys.has('KeyA') || keys.has('ArrowLeft')) r -= 1;
    if (ZZ.Touch.enabled) { f -= ZZ.Touch.move.y; r += ZZ.Touch.move.x; }
    if (Math.abs(f) < 0.12 && Math.abs(r) < 0.12) return [0, 0];
    const c = Math.cos(look.yaw), s = Math.sin(look.yaw);
    const x = c * f - s * r, y = s * f + c * r;
    const l = Math.hypot(x, y);
    return [x / l, y / l];
  }

  // Slide (sprint + C): a short, fast, low dash.
  function trySlide(u) {
    if (u.slideCd > 0 || !u.sprint || (!u.moveX && !u.moveY) || u.phase !== 'ground') return;
    u.slideT = 0.5;
    u.slideCd = 1.6;
    u.slideX = u.moveX; u.slideY = u.moveY;
    if (u.isPlayer) Sound.play('slide');
  }

  // Stances (PUBG style): crouch and prone are quieter, slower and steadier.
  function setStance(u, st) {
    if (u.phase !== 'ground' || !u.alive) return;
    if (st === 'crouch' && u.sprint && u.stance === 'stand' && (u.moveX || u.moveY)) { trySlide(u); u.stance = 'crouch'; return; }
    u.stance = u.stance === st ? 'stand' : st;
  }
  function tryJump(u) {
    if (u.phase !== 'ground' || u.jumpT > 0) return;
    if (u.stance !== 'stand') { u.stance = 'stand'; return; }
    u.jumpT = 0.45;
  }

  function updateUnit(u, dt) {
    u.fireCd = Math.max(0, u.fireCd - dt);
    u.punchT = Math.max(0, u.punchT - dt);
    u.slideCd = Math.max(0, u.slideCd - dt);
    u.jumpT = Math.max(0, u.jumpT - dt);
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
    if (u.stance === 'crouch') speed *= u.sprint ? 0.85 : 0.6;
    else if (u.stance === 'prone') speed *= 0.28;
    speed *= M.terrainSpeed(G.map, u.x, u.y);
    const ox = u.x, oy = u.y;
    if (u.slideT > 0) {
      u.slideT -= dt;
      u.x += u.slideX * 225 * 1.9 * dt;
      u.y += u.slideY * 225 * 1.9 * dt;
    } else {
      u.x += u.moveX * speed * dt;
      u.y += u.moveY * speed * dt;
    }
    M.collideCircle(G.map, u);
    // Deep water stops you: slide along the shore instead of swimming out to sea.
    if (M.isDeep(G.map, u.x, u.y)) {
      const nx = u.x, ny = u.y;
      if (!M.isDeep(G.map, nx, oy)) { u.y = oy; }
      else if (!M.isDeep(G.map, ox, ny)) { u.x = ox; }
      else { u.x = ox; u.y = oy; }
    }
    u.vx = (u.x - ox) / Math.max(dt, 1e-4);
    u.vy = (u.y - oy) / Math.max(dt, 1e-4);

    // Zone damage
    if (!u.inDuel && outsideZone(u)) {
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
      const step = Math.hypot(ex - sx, ey - sy);
      b.dist += step;
      if (b.y0 !== undefined && M.heightAt(G.map, ex, ey) > b.y0 + b.slope * b.dist + 3) tHit = tHit >= 0 ? Math.min(tHit, 0.99) : 0.99;
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

  // Third-person shoulder camera (first-person when scoped with a sniper/DMR).
  function updateCamera(dt) {
    const p = G.player;
    const yaw = look.yaw, pitch = look.pitch;
    const cp = Math.cos(pitch);
    const dx = Math.cos(yaw) * cp, dy = Math.sin(pitch), dz = Math.sin(yaw) * cp;
    const rx = -Math.sin(yaw), rz = Math.cos(yaw);
    let fx, fz, fy, dist, shoulder, lift, fov = 70, hide = false;
    if (p.phase === 'plane') {
      fx = G.plane.x; fz = G.plane.y; fy = HT.plane; dist = 520; shoulder = 0; lift = 60;
    } else if ((p.phase === 'fall' || p.phase === 'chute') && p.alive) {
      fx = p.x; fz = p.y; fy = p.altM * HT.metersToUnits + (p.phase === 'chute' ? 60 : 20);
      dist = p.phase === 'fall' ? 150 : 230; shoulder = 0; lift = 26;
    } else if (!p.alive) {
      const k = p.killer && p.killer.alive ? p.killer : p;
      fx = k.x; fz = k.y; fy = ZZ.groundY(G.map, k.x, k.y) + 40; dist = 180; shoulder = 0; lift = 50;
    } else {
      fx = p.x; fz = p.y;
      const g0 = ZZ.groundY(G.map, p.x, p.y);
      fy = g0 + (p.stance === 'prone' ? 16 : p.stance === 'crouch' || p.slideT > 0 ? 32 : 46) + (p.jumpT > 0 ? Math.sin((p.jumpT / 0.45) * Math.PI) * 14 : 0);
      const w = activeWeapon(p);
      if (p.aiming && w) {
        fov = 70 / w.zoom;
        if (w.zoom >= 1.6) { dist = 0; shoulder = 0; lift = 0; hide = true; }
        else { dist = 46; shoulder = 17; lift = 4; }
      } else { dist = 98; shoulder = 21; lift = 10; }
    }
    let cx = fx - dx * dist + rx * shoulder;
    let cz = fz - dz * dist + rz * shoulder;
    let cy = fy - dy * dist + lift;
    // Keep the camera out of walls.
    if (p.phase === 'ground' && p.alive && dist > 0) {
      const t = M.segmentHit(G.map, fx, fz, cx, cz);
      if (t >= 0) {
        const k = Math.max(0.05, t - 0.1);
        cx = fx + (cx - fx) * k; cz = fz + (cz - fz) * k;
        // Pushed in close by a wall: look over the head instead of through it.
        cy += (1 - k) * 34;
      }
    }
    cy = Math.max(cy, M.heightAt(G.map, cx, cz) + 8, ZZ.WATER_LEVEL + 4);
    if (shake > 0) { cx += rand(-shake, shake) * 0.25; cy += rand(-shake, shake) * 0.25; }
    cam.x = cx; cam.y = cy; cam.z = cz;
    cam.tx = cx + dx * 1000; cam.ty = cy + dy * 1000; cam.tz = cz + dz * 1000;
    cam.fov += (fov - cam.fov) * Math.min(1, dt * 12);
    cam.fx = fx; cam.fz = fz;
    cam.hidePlayer = hide;

    // Where the crosshair points: march the view ray until it meets the terrain (at chest height).
    let t = 2500;
    if (dy < 0.05) {
      for (let k = 30; k <= 2500; k += k < 300 ? 15 : 45) {
        const x = cx + dx * k, z = cz + dz * k, y = cy + dy * k;
        if (y < M.heightAt(G.map, x, z) + HT.chest) { t = k; break; }
      }
    }
    aimPoint = { x: cx + dx * t, y: cz + dz * t };
  }

  // ---------- Killfeed / banners ----------
  function addKillfeed(victim, killer, wname) {
    let html;
    const esc = (s) => s.replace(/[&<>]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]));
    if (!killer && wname) html = `<b>${esc(victim.name)}</b> <span class="w">قُتل بـ${esc(wname)}</span>`;
    else if (!killer) html = `<b>${esc(victim.name)}</b> <span class="w">مات في المنطقة الزرقاء</span>`;
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
  function render(dt) {
    ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
    ctx.clearRect(0, 0, W, H);
    if (!G.map) { LOBBY.active = true; if (!DEBUG.noRender) LOBBY.render(dt, W, H); return; }
    LOBBY.active = false;
    if (!DEBUG.noRender) R3.render(G, cam);
    drawTownLabels();
    drawItemLabels();
    drawTexts();
    drawScreenEffects();
    drawCompass();
    drawAirGauges();
    drawMinimap();
    if (mapOpen) drawFullMap();
    if (state === 'playing' && !mapOpen && G.player.phase === 'ground' && G.player.alive) drawCrosshair();
  }

  function project(x, h, y) { return R3.project(x, h, y, W, H); }

  // Compass strip at the top (bearing 0° = north, clockwise).
  function drawCompass() {
    const p = G.player;
    const yaw = p.phase === 'ground' && p.alive ? look.yaw : look.yaw;
    const bearing = (((yaw + Math.PI / 2) * 180) / Math.PI + 360) % 360;
    const w = Math.min(560, W * 0.42), cx = W / 2, y = 8;
    const pxPerDeg = w / 120;
    ctx.save();
    ctx.beginPath(); ctx.rect(cx - w / 2, y, w, 34); ctx.clip();
    ctx.textAlign = 'center';
    ctx.textBaseline = 'top';
    ctx.direction = 'ltr';
    const names = { 0: 'ش', 45: 'ش.ق', 90: 'ق', 135: 'ج.ق', 180: 'ج', 225: 'ج.غ', 270: 'غ', 315: 'ش.غ' };
    for (let d = Math.floor((bearing - 70) / 15) * 15; d <= bearing + 70; d += 15) {
      const dd = ((d % 360) + 360) % 360;
      const sx = cx + (d - bearing) * pxPerDeg;
      const major = dd % 45 === 0;
      ctx.globalAlpha = 1 - Math.min(1, Math.abs(d - bearing) / 62) * 0.75;
      ctx.fillStyle = '#fff';
      ctx.fillRect(sx - 0.5, y, 1, major ? 8 : 5);
      ctx.font = major ? 'bold 15px "Segoe UI", Tahoma, sans-serif' : '11px "Segoe UI", Tahoma, sans-serif';
      ctx.fillText(names[dd] || String(dd), sx, y + 11);
    }
    ctx.restore();
    ctx.globalAlpha = 1;
    ctx.fillStyle = '#ffd34d';
    ctx.beginPath(); ctx.moveTo(cx - 6, y + 34); ctx.lineTo(cx + 6, y + 34); ctx.lineTo(cx, y + 27); ctx.fill();
    ctx.direction = 'inherit';
  }

  // Altitude and speed scales while skydiving.
  function drawAirGauges() {
    const p = G.player;
    if (!p.alive || (p.phase !== 'fall' && p.phase !== 'chute')) return;
    const h = Math.min(380, H * 0.48), top = H / 2 - h / 2;
    const gauge = (x, value, max, label, unit, alignLeft) => {
      ctx.strokeStyle = 'rgba(255,255,255,0.8)';
      ctx.lineWidth = 2;
      ctx.beginPath(); ctx.moveTo(x, top); ctx.lineTo(x, top + h); ctx.stroke();
      for (let i = 0; i <= 10; i++) {
        const yy = top + (h * i) / 10;
        ctx.beginPath(); ctx.moveTo(x, yy); ctx.lineTo(x + (alignLeft ? -1 : 1) * (i % 5 === 0 ? 12 : 6), yy); ctx.stroke();
      }
      const yv = top + h * (1 - Math.min(1, value / max));
      ctx.fillStyle = 'rgba(0,0,0,0.5)';
      ctx.fillRect(x + (alignLeft ? -86 : 14), yv - 18, 72, 36);
      ctx.fillStyle = '#fff';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.direction = 'ltr';
      ctx.font = 'bold 20px "Segoe UI", Tahoma, sans-serif';
      ctx.fillText(String(Math.round(value)), x + (alignLeft ? -50 : 50), yv - 5);
      ctx.font = '11px "Segoe UI", Tahoma, sans-serif';
      ctx.fillText(unit, x + (alignLeft ? -50 : 50), yv + 11);
      ctx.font = '13px "Segoe UI", Tahoma, sans-serif';
      ctx.fillText(label, x, top + h + 16);
      ctx.direction = 'inherit';
    };
    gauge(W / 2 - 170, p.altM, 800, 'الارتفاع', 'متر', true);
    gauge(W / 2 + 170, Math.min(234, p.airV || 0), 250, 'السرعة', 'كم/س', false);
  }

  // Big town names floating over the island while in the air.
  function drawTownLabels() {
    const p = G.player;
    const airborne = p.phase === 'plane' || ((p.phase === 'fall' || p.phase === 'chute') && p.altM > 120);
    if (!airborne) return;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    for (const t of G.map.towns) {
      const sc = project(t.x, M.heightAt(G.map, t.x, t.y) + 60, t.y);
      if (!sc || sc.x < -100 || sc.x > W + 100 || sc.y < 40 || sc.y > H) continue;
      const d = Math.hypot(cam.x - t.x, cam.z - t.y, cam.y);
      const size = clamp(9000 / d, 13, 30);
      ctx.font = `italic 900 ${size}px "Segoe UI", Tahoma, sans-serif`;
      ctx.lineWidth = 4;
      ctx.strokeStyle = 'rgba(0,0,0,0.65)';
      ctx.strokeText(t.name, sc.x, sc.y);
      ctx.fillStyle = t.military ? '#ffe08a' : '#ffffff';
      ctx.fillText(t.name, sc.x, sc.y);
    }
  }

  function drawItemLabels() {
    const p = G.player;
    if (!p.alive || p.phase !== 'ground') return;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.direction = 'rtl';
    ctx.font = '12px "Segoe UI", Tahoma, sans-serif';
    for (const it of G.items) {
      if (Math.abs(it.x - p.x) > 140 || Math.abs(it.y - p.y) > 140) continue;
      if (Math.hypot(it.x - p.x, it.y - p.y) > 140) continue;
      const s = project(it.x, 22, it.y);
      if (!s) continue;
      const label = itemLabel(it) + (it.amount > 1 ? ` ×${it.amount}` : '');
      const tw = ctx.measureText(label).width + 10;
      ctx.fillStyle = 'rgba(0,0,0,0.55)';
      ctx.fillRect(s.x - tw / 2, s.y - 9, tw, 18);
      ctx.fillStyle = '#fff';
      ctx.fillText(label, s.x, s.y);
    }
    ctx.direction = 'inherit';
  }

  function drawTexts() {
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.direction = 'ltr';
    for (const t of G.texts) {
      const k = 1 - t.life / t.max;
      const s = project(t.x, 48 + k * 18, t.y);
      if (!s) continue;
      ctx.globalAlpha = Math.min(1, (t.life / t.max) * 2);
      ctx.font = `bold ${t.size + 2}px "Segoe UI", Tahoma, sans-serif`;
      ctx.fillStyle = 'rgba(0,0,0,0.7)';
      ctx.fillText(t.text, s.x + 1, s.y + 1);
      ctx.fillStyle = t.color;
      ctx.fillText(t.text, s.x, s.y);
    }
    ctx.globalAlpha = 1;
    ctx.direction = 'inherit';
  }

  function drawScreenEffects() {
    const p = G.player;
    if (p.alive && p.phase === 'ground' && !p.inDuel && outsideZone(p)) {
      ctx.fillStyle = 'rgba(30, 70, 220, 0.18)';
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
    // Damage direction indicators, relative to where the camera faces.
    for (const d of dmgIndicators) {
      ctx.save();
      ctx.translate(W / 2, H / 2);
      ctx.rotate(d.a - look.yaw - Math.PI / 2);
      ctx.globalAlpha = Math.min(1, d.t);
      ctx.strokeStyle = '#ff3b3b';
      ctx.lineWidth = 6;
      ctx.beginPath(); ctx.arc(0, 0, 120, -0.28, 0.28); ctx.stroke();
      ctx.restore();
    }
    ctx.globalAlpha = 1;
    // Sniper scope
    if (cam.hidePlayer) {
      const r = Math.min(W, H) * 0.44;
      ctx.fillStyle = '#000';
      ctx.beginPath();
      ctx.rect(0, 0, W, H);
      ctx.arc(W / 2, H / 2, r, 0, TAU, true);
      ctx.fill('evenodd');
      ctx.strokeStyle = 'rgba(0,0,0,0.85)';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(W / 2 - r, H / 2); ctx.lineTo(W / 2 - 14, H / 2);
      ctx.moveTo(W / 2 + 14, H / 2); ctx.lineTo(W / 2 + r, H / 2);
      ctx.moveTo(W / 2, H / 2 - r); ctx.lineTo(W / 2, H / 2 - 14);
      ctx.moveTo(W / 2, H / 2 + 14); ctx.lineTo(W / 2, H / 2 + r);
      ctx.stroke();
      for (let i = 1; i <= 4; i++) { ctx.beginPath(); ctx.moveTo(W / 2 - 6, H / 2 + i * 22); ctx.lineTo(W / 2 + 6, H / 2 + i * 22); ctx.stroke(); }
    }
  }

  function drawCrosshair() {
    const p = G.player;
    const x = W / 2, y = H / 2;
    const w = activeWeapon(p);
    const moving = Math.hypot(p.vx, p.vy) > 40;
    const spread = w ? w.spread * (p.aiming ? 0.45 : 1) * (moving ? 1.4 : 1) : 0.05;
    const gap = clamp((Math.tan(spread) / Math.tan((cam.fov * Math.PI) / 360)) * (H / 2), 3, 90);
    ctx.strokeStyle = p.reloadT > 0 ? '#ffcf5a' : 'rgba(255,255,255,0.95)';
    ctx.lineWidth = 2;
    if (!cam.hidePlayer) {
      ctx.beginPath();
      ctx.moveTo(x - gap - 9, y); ctx.lineTo(x - gap, y);
      ctx.moveTo(x + gap, y); ctx.lineTo(x + gap + 9, y);
      ctx.moveTo(x, y - gap - 9); ctx.lineTo(x, y - gap);
      ctx.moveTo(x, y + gap); ctx.lineTo(x, y + gap + 9);
      ctx.stroke();
    }
    ctx.fillStyle = '#ff3d4a';
    ctx.fillRect(x - 1.5, y - 1.5, 3, 3);
    if (hitMarkT > 0) {
      ctx.strokeStyle = hitMarkHead ? '#ff4040' : '#ffffff';
      ctx.lineWidth = 2.5;
      ctx.beginPath();
      for (const [sx, sy] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) { ctx.moveTo(x + sx * 7, y + sy * 7); ctx.lineTo(x + sx * 15, y + sy * 15); }
      ctx.stroke();
    }
  }



  // Local minimap around the player (bottom-left).
  function drawMinimap() {
    const size = 200, pad = 12;
    const x = W - size - pad, y = pad;
    const p = G.player;
    const range = 1600;
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
    // 1 km grid lines
    ctx.strokeStyle = 'rgba(255,255,255,0.18)';
    ctx.lineWidth = 1;
    for (let k = Math.ceil(sx0 / 1000) * 1000; k < sx0 + range; k += 1000) { ctx.beginPath(); ctx.moveTo(toX(k), y); ctx.lineTo(toX(k), y + size); ctx.stroke(); }
    for (let k = Math.ceil(sy0 / 1000) * 1000; k < sy0 + range; k += 1000) { ctx.beginPath(); ctx.moveTo(x, toY(k)); ctx.lineTo(x + size, toY(k)); ctx.stroke(); }
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
    drawUavDots(toX, toY, 3);
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

  // Recon drone (kill streak): enemy positions as red dots.
  function drawUavDots(toX, toY, r) {
    if (G.uavT <= 0) return;
    ctx.fillStyle = Math.floor(G.time * 4) % 2 ? '#ff4d4d' : '#ff9a9a';
    for (const u of G.units) {
      if (u.isPlayer || !u.alive || u.phase !== 'ground' || u.inDuel) continue;
      ctx.beginPath(); ctx.arc(toX(u.x), toY(u.y), r, 0, TAU); ctx.fill();
    }
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
    // 8×8 grid of 1 km squares with letters/numbers on the edges.
    ctx.strokeStyle = 'rgba(255,255,255,0.22)';
    ctx.lineWidth = 1;
    for (let i = 1; i < 8; i++) {
      const k = (size / 8) * i;
      ctx.beginPath(); ctx.moveTo(x + k, y); ctx.lineTo(x + k, y + size); ctx.moveTo(x, y + k); ctx.lineTo(x + size, y + k); ctx.stroke();
    }
    ctx.fillStyle = 'rgba(255,255,255,0.8)';
    ctx.font = 'bold 12px "Segoe UI", Tahoma, sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    const letters = 'ABCDEFGH';
    for (let i = 0; i < 8; i++) {
      ctx.fillText(letters[i], x + (size / 8) * (i + 0.5), y + 10);
      ctx.fillText(String(i + 1), x + 10, y + (size / 8) * (i + 0.5));
    }
    // Scale bar
    ctx.fillRect(x + size - 20 - size / 8, y + size - 14, size / 8, 3);
    ctx.fillText('1 كم', x + size - 20 - size / 16, y + size - 26);
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
    drawUavDots(toX, toY, 3.5);
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
    // Context button for touch controls.
    let ctxLabel = '';
    if (p.alive) {
      if (p.phase === 'plane') ctxLabel = planeOverLand() ? 'اقفز' : '';
      else if (p.phase === 'fall' && p.altM < 740) ctxLabel = 'افتح المظلة';
      else if (p.phase === 'ground' && nearbyItems[0]) ctxLabel = 'التقاط';
    }
    ZZ.Touch.setContext(ctxLabel);
    if (ZZ.Touch.enabled && p.phase === 'plane') prompt = '';
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

  // F / the context button: jump from the plane, open the parachute, or pick up.
  function interact() {
    const p = G.player;
    if (!p.alive) return;
    if (p.phase === 'plane') jump(p);
    else if (p.phase === 'fall') openChute(p);
    else if (p.phase === 'ground' && nearbyItems[0]) pickup(p, nearbyItems[0]);
  }

  // Heal button: the best item for the current health.
  function smartHeal(p) {
    const order = p.hp < 50 ? ['medkit', 'firstaid', 'bandage', 'pills', 'drink'] : p.hp < 75 ? ['firstaid', 'bandage', 'pills', 'drink'] : ['drink', 'pills'];
    for (const m of order) if (useMed(p, m)) return;
  }

  ZZ.Touch.init({
    look(dx, dy) {
      if (state !== 'playing' || mapOpen) return;
      const k = look.sens * 1.6 * (G.player && G.player.aiming ? 0.5 : 1);
      look.yaw += dx * k;
      look.pitch = clamp(look.pitch - dy * k, -1.25, 0.8);
    },
    action(act, down) {
      Sound.init();
      if (act === 'pause') { if (down) pauseGame(); return; }
      if (state !== 'playing') return;
      if (act === 'map') { if (down) toggleMap(); return; }
      const p = G.player;
      if (!p.alive) return;
      if (act === 'fire') { mouse.down = down; if (down) shotQueueT = 0.2; return; }
      if (!down) return;
      if (act === 'aim') mouse.right = !mouse.right;
      else if (act === 'reload') startReload(p);
      else if (act === 'jump') { if (p.phase === 'plane') jump(p); else tryJump(p); }
      else if (act === 'crouch') setStance(p, 'crouch');
      else if (act === 'prone') setStance(p, 'prone');
      else if (act === 'grenade') throwGrenade(p, aimPoint.x, aimPoint.y);
      else if (act === 'heal') smartHeal(p);
      else if (act === 'interact') interact();
    },
  });
  // Weapon cards are tappable in touch mode.
  document.querySelectorAll('.wslot').forEach((el) => el.addEventListener('pointerdown', (e) => {
    if (!ZZ.Touch.enabled || state !== 'playing') return;
    e.stopPropagation();
    switchSlot(G.player, +el.dataset.slot);
  }));

  // ---------- Input handlers ----------
  window.addEventListener('keydown', (e) => {
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
      else if (e.code === 'KeyF') interact();
      else if (e.code === 'KeyR') startReload(p);
      else if (e.code === 'Digit1') switchSlot(p, 0);
      else if (e.code === 'Digit2') switchSlot(p, 1);
      else if (e.code === 'Digit3') switchSlot(p, 2);
      else if (e.code === 'KeyX') switchSlot(p, -1);
      else if (e.code === 'KeyG') throwGrenade(p, aimPoint.x, aimPoint.y);
      else if (e.code === 'KeyC' || e.code === 'ControlLeft') setStance(p, 'crouch');
      else if (e.code === 'KeyZ') setStance(p, 'prone');
      else if (e.code === 'Space') { if (p.phase === 'plane') jump(p); else tryJump(p); }
      else {
        const med = MED_ORDER.find((m) => 'Digit' + MEDS[m].key === e.code);
        if (med && !useMed(p, med) && p.meds[med] > 0) showBanner('', p.hp >= 75 && med !== 'medkit' && !MEDS[med].boost ? 'لا يمكن الشفاء أكثر بهذا الغرض' : '', 1200);
      }
      if (e.code === 'Space') e.preventDefault();
    } else if (state === 'paused' && e.code === 'Escape' && performance.now() - pausedAt > 400) resumeGame();
  });
  window.addEventListener('keyup', (e) => keys.delete(e.code));
  // Mouse look (pointer lock gives unlimited movement; without it deltas still work).
  window.addEventListener('mousemove', (e) => {
    mouse.x = e.clientX; mouse.y = e.clientY;
    if (state !== 'playing' || mapOpen || ZZ.Touch.enabled) return;
    const k = look.sens * (G.player && G.player.aiming ? 0.55 : 1);
    look.yaw += e.movementX * k;
    look.pitch = clamp(look.pitch - e.movementY * k, -1.25, 0.8);
  });
  function lockPointer() {
    const el = $('game');
    if (ZZ.Touch.enabled || document.pointerLockElement || !el.requestPointerLock) return;
    try { const r = el.requestPointerLock(); if (r && r.catch) r.catch(() => {}); } catch { /* not supported */ }
  }
  let unlockingForMap = false;
  document.addEventListener('pointerlockchange', () => {
    if (document.pointerLockElement) return;
    if (unlockingForMap) { unlockingForMap = false; return; }
    // Esc releases the mouse in the browser; treat it as pause.
    if (state === 'playing' && !mapOpen) pauseGame();
  });
  window.addEventListener('mousedown', (e) => {
    Sound.init();
    if (state !== 'playing') return;
    if (!mapOpen) lockPointer();
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
    if (mapOpen && document.pointerLockElement) { unlockingForMap = true; document.exitPointerLock(); }
    else if (!mapOpen && state === 'playing') lockPointer();
  }

  // ---------- State transitions ----------
  const overlays = ['menu', 'help', 'pause', 'results', 'stats', 'outfit', 'settings'];
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
    lockPointer();
    lastTime = performance.now();
  }

  let pausedAt = 0;
  function pauseGame() {
    if (state !== 'playing') return;
    state = 'paused';
    pausedAt = performance.now();
    if (document.pointerLockElement) document.exitPointerLock();
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
    lockPointer();
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
      } else if (p.killerWeapon === 'grenade') killerText = 'قتلتك قنبلتك';
      else killerText = 'مت في المنطقة الزرقاء';
    }
    $('res-killer').textContent = killerText;
    setTimeout(() => {
      if (!matchResult) return;
      state = 'over';
      if (document.pointerLockElement) document.exitPointerLock();
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
    const st0 = store.get('zz_stats', { wins: 0, best: 0, kills: 0, games: 0 });
    $('lb-wins').textContent = String(st0.wins);
    $('lb-kills').textContent = String(st0.kills);
    $('lb-name').textContent = profile.name || 'لاعب';
    $('lb-avatar').textContent = (profile.name || 'ص').trim().charAt(0) || 'ص';
    $('lb-level').textContent = `المستوى ${1 + Math.floor((st0.kills * 10 + st0.games * 25 + st0.wins * 100) / 200)}`;
    $('mode-diff').textContent = 'الخصوم: ' + { easy: 'سهل', normal: 'عادي', hard: 'صعب' }[difficulty];
    document.querySelectorAll('#ctrl-seg button').forEach((b) => b.classList.toggle('on', b.dataset.v === settings.ctrl));
    document.querySelectorAll('#gfx-seg button').forEach((b) => b.classList.toggle('on', b.dataset.v === settings.gfx));
    $('in-sens').value = String(+(look.sens * 1000).toFixed(1));
    const st = store.get('zz_stats', { wins: 0, best: 0, kills: 0, games: 0 });
    $('st-wins').textContent = String(st.wins);
    $('st-best').textContent = st.best ? '#' + st.best : '-';
    $('st-kills').textContent = String(st.kills);
    $('st-games').textContent = String(st.games);
    document.querySelectorAll('#diff-seg button').forEach((b) => b.classList.toggle('on', b.dataset.diff === difficulty));
  }

  function toggleMute() {
    Sound.setMuted(!Sound.muted);
    store.set('zz_muted', Sound.muted);
    $('btn-sound').textContent = Sound.muted ? 'الصوت: مكتوم' : 'الصوت: يعمل';
  }

  $('btn-start').addEventListener('click', startGame);
  $('btn-help').addEventListener('click', () => showOverlay('help'));
  $('btn-stats').addEventListener('click', () => { refreshMenuStats(); showOverlay('stats'); });
  $('btn-settings').addEventListener('click', () => { refreshMenuStats(); showOverlay('settings'); });
  $('btn-settings2').addEventListener('click', () => { refreshMenuStats(); showOverlay('settings'); });
  $('btn-outfit').addEventListener('click', () => { $('in-name').value = profile.name || ''; buildSwatches(); showOverlay('outfit'); });
  $('mode-card').addEventListener('click', () => {
    const order = ['easy', 'normal', 'hard'];
    difficulty = order[(order.indexOf(difficulty) + 1) % 3];
    store.set('zz_diff', difficulty);
    refreshMenuStats();
  });
  document.querySelectorAll('.back-btn').forEach((b) => b.addEventListener('click', () => {
    if (!$('outfit').classList.contains('hidden')) {
      profile.name = $('in-name').value.trim().slice(0, 16);
      store.set('zz_profile', profile);
      LOBBY.setOutfit({ clothes: OUTFITS[profile.outfit] });
    }
    refreshMenuStats();
    showOverlay(state === 'paused' ? 'pause' : 'menu');
  }));
  document.querySelectorAll('#ctrl-seg button').forEach((b) => b.addEventListener('click', () => {
    settings.ctrl = b.dataset.v; store.set('zz_settings', settings); applySettings(); refreshMenuStats();
  }));
  document.querySelectorAll('#gfx-seg button').forEach((b) => b.addEventListener('click', () => {
    settings.gfx = b.dataset.v; store.set('zz_settings', settings); applySettings(); refreshMenuStats();
  }));
  $('in-sens').addEventListener('input', () => {
    look.sens = (+$('in-sens').value) / 1000;
    store.set('zz_sens', look.sens);
  });
  function buildSwatches() {
    const box = $('swatches');
    box.innerHTML = '';
    OUTFITS.forEach((c, i) => {
      const b = document.createElement('button');
      b.className = `swatch sw-${i}` + (i === profile.outfit ? ' on' : '');
      b.setAttribute('aria-label', 'لون ' + (i + 1));
      b.addEventListener('click', () => {
        profile.outfit = i;
        store.set('zz_profile', profile);
        LOBBY.setOutfit({ clothes: c });
        buildSwatches();
      });
      box.appendChild(b);
    });
  }
  function applySettings() {
    ZZ.Touch.setEnabled(settings.ctrl === 'touch');
    R3.setQuality(settings.gfx);
    if (ZZ.Touch.enabled && document.pointerLockElement) document.exitPointerLock();
  }
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
  applySettings();
  LOBBY.setOutfit({ clothes: OUTFITS[profile.outfit] });
  refreshMenuStats();

  // Bots call into the world through these.
  Object.assign(G, {
    tryFire, startReload, switchSlot, pickup, useMed, throwGrenade,
    segmentHit: (x1, y1, x2, y2) => M.segmentHit(G.map, x1, y1, x2, y2),
    terrainBlocks: (a, b) => M.terrainBlocks(G.map, a.x, a.y, ZZ.groundY(G.map, a.x, a.y) + chestOf(a), b.x, b.y, ZZ.groundY(G.map, b.x, b.y) + chestOf(b)),
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
    render(rawDt);
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
      return best && { x: best.x, y: best.y, d: bd, ang: Math.atan2(best.y - p.y, best.x - p.x) };
    },
    // Debug-only: point the camera (used by automated tests that can't move a real mouse).
    setLook(yaw, pitch) { if (params.get('debug') === '1') { look.yaw = yaw; if (pitch !== undefined) look.pitch = pitch; } },
    get look() { return { yaw: look.yaw, pitch: look.pitch }; },
    get duel() { return !!G.duel; },
    // Debug-only: kill a unit (the player, the duel opponent, or the nearest bot) as if shot by `byPlayer`.
    debugKill(which, byPlayer) {
      if (params.get('debug') !== '1') return;
      const p = G.player;
      let t = which === 'player' ? p : which === 'opp' ? G.duel && G.duel.opp : null;
      if (which === 'bot') {
        let bd = Infinity;
        for (const u of G.units) { if (u === p || !u.alive) continue; const d = Math.hypot(u.x - p.x, u.y - p.y); if (d < bd) { bd = d; t = u; } }
      }
      if (!t) return;
      const killer = byPlayer ? p : G.units.find((u) => u !== t && u.alive && !u.isPlayer);
      killUnit(t, killer, 'akm');
    },
    get uav() { return G.uavT; },
    get broken() { return G.broken.length; },
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
