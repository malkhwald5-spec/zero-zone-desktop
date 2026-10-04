'use strict';

(() => {
  const ZZ = window.ZZ;
  const TAU = Math.PI * 2;
  const CELL = 250;
  const WALL = 12;
  const DOOR = 64;
  const WALL_SEG = 64; // walls are split into segments so explosions can break holes in them
  // Fenced "second chance" duel arena on its own islet in the north-west sea.
  const ARENA = { x: 160, y: 160, w: 560, h: 560 };
  const GROUND_SCALE = 0.3;
  const HSTEP = 25;          // heightmap resolution (world units per sample)
  const DEEP = -30;          // below this the water is too deep to walk through
  ZZ.WATER_LEVEL = -2;

  const TOWN_NAMES = ['الميناء', 'المدينة القديمة', 'المزرعة', 'المحطة', 'الوادي', 'القلعة', 'السوق', 'المصنع', 'التلال', 'الواحة',
    'المنارة', 'الجسر', 'المطار', 'النخيل', 'المنجم', 'البحيرة', 'الصخرة', 'الغابة'];
  const ROOF_COLORS = ['#8c3b2e', '#6e4a35', '#5c5f66', '#7a2f2f', '#4f5d4a', '#86643e'];

  function distToSegment(px, py, x1, y1, x2, y2) {
    const dx = x2 - x1, dy = y2 - y1;
    const l2 = dx * dx + dy * dy;
    let t = l2 ? ((px - x1) * dx + (py - y1) * dy) / l2 : 0;
    t = Math.max(0, Math.min(1, t));
    const cx = x1 + dx * t, cy = y1 + dy * t;
    return Math.hypot(px - cx, py - cy);
  }

  const smooth = (e0, e1, x) => { const t = Math.max(0, Math.min(1, (x - e0) / (e1 - e0))); return t * t * (3 - 2 * t); };

  // ---------- Value noise ----------
  function makeNoise(seed) {
    const perm = new Uint8Array(512);
    const rng = ZZ.mulberry32(seed ^ 0x9e3779b9);
    const p = Array.from({ length: 256 }, (_, i) => i).sort(() => rng() - 0.5);
    for (let i = 0; i < 512; i++) perm[i] = p[i & 255];
    const vals = new Float32Array(256).map(() => rng());
    const lerp = (a, b, t) => a + (b - a) * t;
    const noise = (x, y) => {
      const xi = Math.floor(x), yi = Math.floor(y);
      const xf = x - xi, yf = y - yi;
      const u = xf * xf * (3 - 2 * xf), v = yf * yf * (3 - 2 * yf);
      const X = xi & 255, Y = yi & 255;
      const a = vals[perm[perm[X] + Y]], b = vals[perm[perm[X + 1] + Y]];
      const c = vals[perm[perm[X] + Y + 1]], d = vals[perm[perm[X + 1] + Y + 1]];
      return lerp(lerp(a, b, u), lerp(c, d, u), v);
    };
    return (x, y, oct = 4) => {
      let sum = 0, amp = 1, freq = 1, norm = 0;
      for (let i = 0; i < oct; i++) { sum += noise(x * freq, y * freq) * amp; norm += amp; amp *= 0.5; freq *= 2.03; }
      return sum / norm;
    };
  }

  // ---------- Terrain ----------
  // An island: a large main landmass crossed by a river, and a smaller
  // southern island (military base) across a shallow channel.
  function buildTerrain(map, rng) {
    const S = map.size;
    const fbm = makeNoise(map.seed);
    const mainC = { x: S * 0.5, y: S * 0.45, r: S * 0.385 };
    const southC = { x: S * (0.45 + rng() * 0.12), y: S * 0.86, r: S * 0.12 };
    const channelY = (x) => S * 0.735 + Math.sin(x / 700) * 60;
    const riverY = (x) => S * (0.3 + rng0) + Math.sin(x / 950 + phase) * 420 + Math.sin(x / 330) * 120;
    const rng0 = rng() * 0.08, phase = rng() * TAU;
    map.riverY = riverY;
    map.channelY = channelY;

    const landMask = (x, y) => {
      const n = (fbm(x / 1100, y / 1100) - 0.5) * 0.55;
      const mMain = 1 - Math.hypot((x - mainC.x) / mainC.r, (y - mainC.y) / (mainC.r * 0.9)) + n;
      const mSouth = 1 - Math.hypot((x - southC.x) / southC.r, (y - southC.y) / (southC.r * 0.8)) + n * 0.6;
      const cy = channelY(x);
      let m = -1;
      if (y < cy - 70) m = Math.max(m, mMain);
      if (y > cy + 70) m = Math.max(m, mSouth);
      // The arena islet.
      if (x > ARENA.x - 90 && x < ARENA.x + ARENA.w + 90 && y > ARENA.y - 90 && y < ARENA.y + ARENA.h + 90) m = Math.max(m, 0.3);
      return m;
    };

    const n = Math.floor(S / HSTEP) + 1;
    const hm = new Float32Array(n * n);
    for (let j = 0; j < n; j++) {
      for (let i = 0; i < n; i++) {
        const x = i * HSTEP, y = j * HSTEP;
        const m = landMask(x, y);
        let h;
        if (m <= 0) {
          // Sea: shallow near the coast (and in the channel), deep further out.
          // The channel to the southern island is shallow near its middle, deeper towards the open sea.
          const cd = Math.abs(x - southC.x) / (southC.r * 1.4);
          const inChannel = Math.abs(y - channelY(x)) < 170 && cd < 1;
          h = inChannel ? -14 - cd * cd * 26 : Math.max(-80, -6 + m * 260);
        } else {
          const hills = Math.pow(fbm(x / 1500 + 7, y / 1500 + 3, 5), 2) * 330;
          h = 3 + hills * smooth(0, 0.18, m);
          // River: a shallow, wadeable stream with gentle banks.
          const dr = Math.abs(y - riverY(x));
          const rw = 70 + fbm(x / 400, 9) * 50;
          if (dr < rw) h = -14;
          else h = Math.min(h, 3 + (dr - rw) * 0.35 + h * smooth(rw, rw + 400, dr));
        }
        hm[j * n + i] = h;
      }
    }
    map.hm = hm; map.hn = n;
    map.landMask = landMask;
  }

  // Bilinear terrain height at (x, y).
  function heightAt(map, x, y) {
    const n = map.hn;
    const fx = Math.max(0, Math.min(n - 1.001, x / HSTEP)), fy = Math.max(0, Math.min(n - 1.001, y / HSTEP));
    const i = Math.floor(fx), j = Math.floor(fy);
    const tx = fx - i, ty = fy - j;
    const a = map.hm[j * n + i], b = map.hm[j * n + i + 1], c = map.hm[(j + 1) * n + i], d = map.hm[(j + 1) * n + i + 1];
    return (a + (b - a) * tx) * (1 - ty) + (c + (d - c) * tx) * ty;
  }

  // Flattens the heightmap inside a rectangle (plus a soft margin) to a single level.
  function flattenRect(map, x, y, w, h, margin, level) {
    const n = map.hn;
    const i0 = Math.max(0, Math.floor((x - margin) / HSTEP)), i1 = Math.min(n - 1, Math.ceil((x + w + margin) / HSTEP));
    const j0 = Math.max(0, Math.floor((y - margin) / HSTEP)), j1 = Math.min(n - 1, Math.ceil((y + h + margin) / HSTEP));
    for (let j = j0; j <= j1; j++) {
      for (let i = i0; i <= i1; i++) {
        const px = i * HSTEP, py = j * HSTEP;
        const dx = Math.max(x - px, 0, px - (x + w)), dy = Math.max(y - py, 0, py - (y + h));
        const k = 1 - smooth(0, margin, Math.hypot(dx, dy));
        const idx = j * n + i;
        map.hm[idx] += (level - map.hm[idx]) * k;
      }
    }
  }

  const isLand = (map, x, y) => heightAt(map, x, y) > 0.5;
  // True if hills block the straight line between two points at the given heights.
  function terrainBlocks(map, x1, y1, h1, x2, y2, h2) {
    const d = Math.hypot(x2 - x1, y2 - y1);
    const n = Math.min(24, Math.ceil(d / 60));
    for (let i = 1; i < n; i++) {
      const t = i / n;
      if (heightAt(map, x1 + (x2 - x1) * t, y1 + (y2 - y1) * t) > h1 + (h2 - h1) * t + 2) return true;
    }
    return false;
  }
  const isDeep = (map, x, y) => heightAt(map, x, y) < DEEP;
  const onBridge = (map, x, y) => map.bridges.some((b) => distToSegment(x, y, b.x1, b.y1, b.x2, b.y2) < b.w / 2 + 6);
  // Walking speed factor: wading through shallow water is slow (bridges are not).
  function terrainSpeed(map, x, y) {
    const h = heightAt(map, x, y);
    if (h >= 0) return 1;
    if (onBridge(map, x, y)) return 1;
    return h > -6 ? 0.8 : 0.5;
  }

  function createMap(seed) {
    const rng = ZZ.mulberry32(seed);
    const R = (a, b) => a + rng() * (b - a);
    const RI = (a, b) => Math.floor(R(a, b + 1));
    const S = ZZ.MAP_SIZE;
    const area = (S / 5000) ** 2; // scale prop counts with map area

    const map = {
      size: S, seed,
      obs: [],         // obstacles: {t:0 rect x,y,w,h | t:1 circle x,y,r, kind}
      buildings: [],   // {x,y,w,h,doors:[{x,y,nx,ny}],roof,military,floor}
      trees: [],       // references into obs with canopy radius
      towns: [],
      roads: [],
      bridges: [],
      lootSpots: [],   // {x,y,bld,military}
      grid: null, cols: 0, rows: 0,
      stamp: 0,
    };
    buildTerrain(map, rng);
    const landAt = (x, y, pad = 0) => {
      if (pad <= 0) return isLand(map, x, y);
      return isLand(map, x, y) && isLand(map, x - pad, y) && isLand(map, x + pad, y) && isLand(map, x, y - pad) && isLand(map, x, y + pad);
    };
    const nearRiver = (x, y, pad) => Math.abs(y - map.riverY(x)) < 140 + pad;

    // ----- Towns -----
    const names = TOWN_NAMES.slice().sort(() => rng() - 0.5);
    const townCount = 13;
    // The military base sits on the southern island.
    const sx0 = S * 0.45, sy0 = S * 0.86;
    let mil = null;
    for (let i = 0; i < 400 && !mil; i++) {
      const x = sx0 + R(-350, 350) + S * 0.06, y = sy0 + R(-150, 150);
      if (landAt(x, y, 520)) mil = { name: 'القاعدة العسكرية', x, y, r: 420, military: true };
    }
    if (!mil) mil = { name: 'القاعدة العسكرية', x: S * 0.5, y: S * 0.86, r: 360, military: true };
    map.towns.push(mil);
    let tries = 0;
    while (map.towns.length < townCount && tries++ < 4000) {
      const r = R(260, 430);
      const x = R(600, S - 600), y = R(600, map.channelY(S / 2) - 300);
      if (!landAt(x, y, r + 120)) continue;
      if (nearRiver(x, y, r + 60)) continue;
      if (map.towns.some((t) => Math.hypot(t.x - x, t.y - y) < t.r + r + 520)) continue;
      map.towns.push({ name: names.pop() || 'قرية', x, y, r, military: false });
    }
    // Towns are built on flat ground.
    for (const t of map.towns) flattenRect(map, t.x - t.r, t.y - t.r, t.r * 2, t.r * 2, 380, Math.max(4, heightAt(map, t.x, t.y) * 0.5));

    // ----- Roads: connect each town to its two nearest neighbours -----
    const roadKeys = new Set();
    map.towns.forEach((a, i) => {
      const near = map.towns
        .map((b, j) => ({ j, d: Math.hypot(a.x - b.x, a.y - b.y) }))
        .filter((o) => o.j !== i)
        .sort((p, q) => p.d - q.d)
        .slice(0, 2);
      for (const n of near) {
        const key = Math.min(i, n.j) + '-' + Math.max(i, n.j);
        if (roadKeys.has(key)) continue;
        roadKeys.add(key);
        const b = map.towns[n.j];
        map.roads.push({ x1: a.x, y1: a.y, x2: b.x, y2: b.y, w: 46 });
      }
    });
    // Bridges wherever a road crosses water.
    for (const rd of map.roads) {
      const len = Math.hypot(rd.x2 - rd.x1, rd.y2 - rd.y1);
      const steps = Math.ceil(len / 15);
      let start = -1;
      for (let k = 0; k <= steps; k++) {
        const t = k / steps;
        const x = rd.x1 + (rd.x2 - rd.x1) * t, y = rd.y1 + (rd.y2 - rd.y1) * t;
        const wet = heightAt(map, x, y) < 1;
        if (wet && start < 0) start = Math.max(0, t - 40 / len);
        if ((!wet || k === steps) && start >= 0) {
          const t2 = Math.min(1, t + 40 / len);
          map.bridges.push({
            x1: rd.x1 + (rd.x2 - rd.x1) * start, y1: rd.y1 + (rd.y2 - rd.y1) * start,
            x2: rd.x1 + (rd.x2 - rd.x1) * t2, y2: rd.y1 + (rd.y2 - rd.y1) * t2, w: 60,
          });
          start = -1;
        }
      }
    }
    const nearRoad = (x, y, pad) => map.roads.some((rd) => distToSegment(x, y, rd.x1, rd.y1, rd.x2, rd.y2) < rd.w / 2 + pad);

    // ----- Buildings -----
    const overlapsBuilding = (x, y, w, h, pad) => map.buildings.some((b) =>
      x < b.x + b.w + pad && x + w + pad > b.x && y < b.y + b.h + pad && y + h + pad > b.y) ||
      (x < ARENA.x + ARENA.w + pad && x + w + pad > ARENA.x && y < ARENA.y + ARENA.h + pad && y + h + pad > ARENA.y);

    // Adds a straight wall as several breakable segments.
    function pushWall(x, y, w, h, extra) {
      const horizontal = w >= h;
      const len = horizontal ? w : h;
      const n = Math.max(1, Math.round(len / WALL_SEG));
      const step = len / n;
      for (let i = 0; i < n; i++) {
        if (horizontal) map.obs.push({ t: 0, x: x + i * step, y, w: step, h, kind: 'wall', ...extra });
        else map.obs.push({ t: 0, x, y: y + i * step, w, h: step, kind: 'wall', ...extra });
      }
    }

    function addBuilding(x, y, w, h, military) {
      const bi = map.buildings.length;
      const b = { x, y, w, h, doors: [], roof: ROOF_COLORS[RI(0, ROOF_COLORS.length - 1)], military };
      if (military) b.roof = '#4d5245';
      // Sides: 0 top, 1 right, 2 bottom, 3 left
      const doorSides = new Set([RI(0, 3)]);
      if (rng() < 0.55) doorSides.add(RI(0, 3));
      for (let side = 0; side < 4; side++) {
        const horizontal = side === 0 || side === 2;
        const len = horizontal ? w : h;
        const sx = side === 1 ? x + w - WALL : x;
        const sy = side === 2 ? y + h - WALL : y;
        if (!doorSides.has(side)) {
          if (horizontal) pushWall(sx, sy, len, WALL, { bld: bi }); else pushWall(sx, sy, WALL, len, { bld: bi });
          continue;
        }
        const off = R(WALL + 20, len - WALL - 20 - DOOR);
        if (horizontal) {
          pushWall(sx, sy, off, WALL, { bld: bi });
          pushWall(sx + off + DOOR, sy, len - off - DOOR, WALL, { bld: bi });
          b.doors.push({ x: sx + off + DOOR / 2, y: sy + WALL / 2, nx: 0, ny: side === 0 ? -1 : 1 });
        } else {
          pushWall(sx, sy, WALL, off, { bld: bi });
          pushWall(sx, sy + off + DOOR, WALL, len - off - DOOR, { bld: bi });
          b.doors.push({ x: sx + WALL / 2, y: sy + off + DOOR / 2, nx: side === 3 ? -1 : 1, ny: 0 });
        }
      }
      // Level the ground under the building.
      b.floor = Math.max(3, heightAt(map, x + w / 2, y + h / 2));
      flattenRect(map, x, y, w, h, 90, b.floor);
      map.buildings.push(b);
      const spots = RI(2, military ? 5 : 4);
      for (let i = 0; i < spots; i++) {
        map.lootSpots.push({ x: R(x + 34, x + w - 34), y: R(y + 34, y + h - 34), bld: bi, military });
      }
    }

    for (const town of map.towns) {
      const count = town.military ? 12 : RI(5, 9);
      let placed = 0, attempts = 0;
      while (placed < count && attempts++ < 500) {
        const w = R(170, town.military ? 330 : 290);
        const h = R(150, town.military ? 280 : 250);
        const a = R(0, TAU), d = R(0, town.r);
        const x = town.x + Math.cos(a) * d - w / 2;
        const y = town.y + Math.sin(a) * d - h / 2;
        if (!landAt(x, y) || !landAt(x + w, y + h) || !landAt(x + w, y) || !landAt(x, y + h)) continue;
        if (overlapsBuilding(x, y, w, h, 70)) continue;
        if (nearRoad(x + w / 2, y + h / 2, Math.max(w, h) / 2 + 10)) continue;
        addBuilding(x, y, w, h, town.military);
        placed++;
      }
    }

    // Lone houses scattered across the countryside.
    let lone = 0, loneTries = 0;
    while (lone < Math.round(26 * area) && loneTries++ < 5000) {
      const w = R(150, 230), h = R(140, 210);
      const x = R(200, S - 200 - w), y = R(200, S - 200 - h);
      if (!landAt(x - 40, y - 40, 0) || !landAt(x + w + 40, y + h + 40, 0) || !landAt(x + w / 2, y + h / 2, Math.max(w, h))) continue;
      if (nearRiver(x + w / 2, y + h / 2, Math.max(w, h))) continue;
      if (map.towns.some((t) => Math.hypot(t.x - x, t.y - y) < t.r + 300)) continue;
      if (overlapsBuilding(x, y, w, h, 220)) continue;
      if (nearRoad(x + w / 2, y + h / 2, Math.max(w, h) / 2 + 10)) continue;
      addBuilding(x, y, w, h, false);
      lone++;
    }

    // Arena: closed fence (unbreakable) with a few crates for cover.
    const A = ARENA, F = 16;
    flattenRect(map, A.x, A.y, A.w, A.h, 60, 4);
    pushWall(A.x, A.y, A.w, F, { fence: true, bld: -1 });
    pushWall(A.x, A.y + A.h - F, A.w, F, { fence: true, bld: -1 });
    pushWall(A.x, A.y + F, F, A.h - 2 * F, { fence: true, bld: -1 });
    pushWall(A.x + A.w - F, A.y + F, F, A.h - 2 * F, { fence: true, bld: -1 });
    for (const [cx, cy] of [[0.5, 0.5], [0.3, 0.32], [0.7, 0.68], [0.3, 0.7], [0.7, 0.3]]) {
      map.obs.push({ t: 0, x: A.x + A.w * cx - 24, y: A.y + A.h * cy - 24, w: 48, h: 48, kind: 'crate', arena: true });
    }
    map.arena = { ...ARENA, spawnA: { x: A.x + A.w * 0.2, y: A.y + A.h * 0.5 }, spawnB: { x: A.x + A.w * 0.8, y: A.y + A.h * 0.5 } };

    const blockedForProp = (x, y, r) =>
      overlapsBuilding(x - r, y - r, r * 2, r * 2, 40) || nearRoad(x, y, r + 8) || !landAt(x, y, r) || heightAt(map, x, y) < 4;

    // ----- Crates / containers near towns (with outdoor loot) -----
    for (const town of map.towns) {
      const n = town.military ? 12 : RI(3, 6);
      for (let i = 0; i < n; i++) {
        const big = town.military && rng() < 0.5;
        const w = big ? 130 : 44, h = big ? 52 : 44;
        const a = R(0, TAU), d = R(town.r * 0.3, town.r + 120);
        const x = town.x + Math.cos(a) * d, y = town.y + Math.sin(a) * d;
        if (blockedForProp(x + w / 2, y + h / 2, Math.max(w, h) / 2 + 10)) continue;
        if (big && rng() < 0.5) map.obs.push({ t: 0, x, y, w: h, h: w, kind: 'container' });
        else map.obs.push({ t: 0, x, y, w, h, kind: big ? 'container' : 'crate' });
        if (rng() < 0.6) map.lootSpots.push({ x: x + w / 2 + (rng() < 0.5 ? -1 : 1) * (w / 2 + 26), y: y + h / 2, bld: -1, military: town.military });
      }
    }

    // ----- Trees (forests + scattered); two kinds: pines and broadleaf -----
    const addTree = (x, y, pine) => {
      if (blockedForProp(x, y, 30)) return;
      if (map.towns.some((t) => Math.hypot(t.x - x, t.y - y) < t.r * 0.75)) return;
      const tree = { t: 1, x, y, r: R(10, 14), kind: 'tree', canopy: R(32, 50), shade: R(0, 1), pine };
      map.obs.push(tree);
      map.trees.push(tree);
    };
    for (let f = 0; f < Math.round(46 * area); f++) {
      const cx = R(300, S - 300), cy = R(300, S - 300);
      const n = RI(18, 44);
      const pine = rng() < 0.55;
      for (let i = 0; i < n; i++) {
        const a = R(0, TAU), d = Math.abs(R(-1, 1) + R(-1, 1)) * 200;
        addTree(cx + Math.cos(a) * d, cy + Math.sin(a) * d, rng() < 0.85 ? pine : !pine);
      }
    }
    for (let i = 0; i < Math.round(420 * area); i++) addTree(R(100, S - 100), R(100, S - 100), rng() < 0.4);

    // ----- Rocks -----
    for (let i = 0; i < Math.round(130 * area); i++) {
      const x = R(150, S - 150), y = R(150, S - 150), r = R(20, 46);
      if (blockedForProp(x, y, r)) continue;
      map.obs.push({ t: 1, x, y, r, kind: 'rock', shade: R(0, 1) });
    }

    // A few outdoor loot spots in the wild.
    for (let i = 0; i < Math.round(40 * area); i++) {
      const x = R(200, S - 200), y = R(200, S - 200);
      if (blockedForProp(x, y, 20)) continue;
      map.lootSpots.push({ x, y, bld: -1, military: false });
    }

    buildGrid(map);
    map.ground = renderGround(map, rng);
    return map;
  }

  // ---------- Spatial grid ----------
  function buildGrid(map) {
    map.cols = map.rows = Math.ceil(map.size / CELL);
    map.grid = Array.from({ length: map.cols * map.rows }, () => []);
    map.obs.forEach((o, i) => {
      const x0 = o.t === 0 ? o.x : o.x - o.r, y0 = o.t === 0 ? o.y : o.y - o.r;
      const x1 = o.t === 0 ? o.x + o.w : o.x + o.r, y1 = o.t === 0 ? o.y + o.h : o.y + o.r;
      forCells(map, x0, y0, x1, y1, (c) => map.grid[c].push(i));
      o._s = 0;
    });
  }

  function forCells(map, x0, y0, x1, y1, fn) {
    const c0 = Math.max(0, Math.floor(x0 / CELL)), c1 = Math.min(map.cols - 1, Math.floor(x1 / CELL));
    const r0 = Math.max(0, Math.floor(y0 / CELL)), r1 = Math.min(map.rows - 1, Math.floor(y1 / CELL));
    for (let r = r0; r <= r1; r++) for (let c = c0; c <= c1; c++) fn(r * map.cols + c);
  }

  // Calls fn(obstacle) once for each obstacle whose cells overlap the AABB.
  function query(map, x0, y0, x1, y1, fn) {
    const stamp = ++map.stamp;
    forCells(map, x0, y0, x1, y1, (c) => {
      const cell = map.grid[c];
      for (let i = 0; i < cell.length; i++) {
        const o = map.obs[cell[i]];
        if (o._s === stamp || o.dead) continue;
        o._s = stamp;
        fn(o);
      }
    });
  }

  // ---------- Collision ----------
  // Pushes a circle entity {x,y,r} out of obstacles. Returns true on contact.
  function collideCircle(map, e) {
    let hit = false;
    query(map, e.x - e.r, e.y - e.r, e.x + e.r, e.y + e.r, (o) => {
      if (o.t === 0) {
        const cx = Math.max(o.x, Math.min(e.x, o.x + o.w));
        const cy = Math.max(o.y, Math.min(e.y, o.y + o.h));
        let dx = e.x - cx, dy = e.y - cy;
        const d2 = dx * dx + dy * dy;
        if (d2 >= e.r * e.r) return;
        hit = true;
        if (d2 > 0.0001) {
          const d = Math.sqrt(d2);
          e.x = cx + (dx / d) * e.r;
          e.y = cy + (dy / d) * e.r;
        } else {
          // Center inside the rect: push out along the shallowest axis.
          const left = e.x - o.x, right = o.x + o.w - e.x, top = e.y - o.y, bottom = o.y + o.h - e.y;
          const m = Math.min(left, right, top, bottom);
          if (m === left) e.x = o.x - e.r; else if (m === right) e.x = o.x + o.w + e.r;
          else if (m === top) e.y = o.y - e.r; else e.y = o.y + o.h + e.r;
        }
      } else {
        const dx = e.x - o.x, dy = e.y - o.y;
        const rr = e.r + o.r;
        const d2 = dx * dx + dy * dy;
        if (d2 >= rr * rr) return;
        hit = true;
        const d = Math.sqrt(d2) || 0.01;
        e.x = o.x + (dx / d) * rr;
        e.y = o.y + (dy / d) * rr;
      }
    });
    const S = map.size;
    e.x = Math.max(e.r, Math.min(S - e.r, e.x));
    e.y = Math.max(e.r, Math.min(S - e.r, e.y));
    return hit;
  }

  function isFree(map, x, y, r) {
    let free = x > r && y > r && x < map.size - r && y < map.size - r;
    if (!free) return false;
    query(map, x - r, y - r, x + r, y + r, (o) => {
      if (!free) return;
      if (o.t === 0) {
        const cx = Math.max(o.x, Math.min(x, o.x + o.w)), cy = Math.max(o.y, Math.min(y, o.y + o.h));
        if ((x - cx) ** 2 + (y - cy) ** 2 < r * r) free = false;
      } else if ((x - o.x) ** 2 + (y - o.y) ** 2 < (r + o.r) ** 2) free = false;
    });
    return free;
  }

  // Returns the fraction t (0..1) along the segment where it first hits an obstacle, or -1.
  function segmentHit(map, x1, y1, x2, y2) {
    const dx = x2 - x1, dy = y2 - y1;
    let best = 2;
    query(map, Math.min(x1, x2), Math.min(y1, y2), Math.max(x1, x2), Math.max(y1, y2), (o) => {
      let t;
      if (o.t === 0) t = segRect(x1, y1, dx, dy, o);
      else t = segCircle(x1, y1, dx, dy, o);
      if (t >= 0 && t < best) best = t;
    });
    return best <= 1 ? best : -1;
  }

  function segRect(x, y, dx, dy, o) {
    let tmin = 0, tmax = 1;
    if (Math.abs(dx) < 1e-9) { if (x < o.x || x > o.x + o.w) return -1; }
    else {
      let t1 = (o.x - x) / dx, t2 = (o.x + o.w - x) / dx;
      if (t1 > t2) [t1, t2] = [t2, t1];
      tmin = Math.max(tmin, t1); tmax = Math.min(tmax, t2);
      if (tmin > tmax) return -1;
    }
    if (Math.abs(dy) < 1e-9) { if (y < o.y || y > o.y + o.h) return -1; }
    else {
      let t1 = (o.y - y) / dy, t2 = (o.y + o.h - y) / dy;
      if (t1 > t2) [t1, t2] = [t2, t1];
      tmin = Math.max(tmin, t1); tmax = Math.min(tmax, t2);
      if (tmin > tmax) return -1;
    }
    return tmin;
  }

  function segCircle(x, y, dx, dy, o) {
    const fx = x - o.x, fy = y - o.y;
    const a = dx * dx + dy * dy;
    if (a < 1e-9) return -1;
    const b = 2 * (fx * dx + fy * dy);
    const c = fx * fx + fy * fy - o.r * o.r;
    if (c < 0) return 0;
    const disc = b * b - 4 * a * c;
    if (disc < 0) return -1;
    const t = (-b - Math.sqrt(disc)) / (2 * a);
    return t >= 0 && t <= 1 ? t : -1;
  }

  function buildingAt(map, x, y) {
    for (let i = 0; i < map.buildings.length; i++) {
      const b = map.buildings[i];
      if (x > b.x && x < b.x + b.w && y > b.y && y < b.y + b.h) return i;
    }
    return -1;
  }

  // ---------- Ground texture ----------
  // Painted from the heightmap: beaches, grass, darker hills, rock, river beds,
  // then fields, town dirt, roads and building floors on top.
  function renderGround(map, rng) {
    const S = map.size, gs = GROUND_SCALE;
    const size = Math.ceil(S * gs);
    const cv = document.createElement('canvas');
    cv.width = cv.height = size;
    const g = cv.getContext('2d');
    const img = g.createImageData(size, size);
    const d = img.data;
    const detail = makeNoise(map.seed + 11);
    for (let py = 0; py < size; py++) {
      for (let px = 0; px < size; px++) {
        const x = px / gs, y = py / gs;
        const h = heightAt(map, x, y);
        const n = detail(x / 260, y / 260, 3);
        let r, gg, b;
        if (h < -20) { r = 28; gg = 70; b = 92; }
        else if (h < 0.5) { r = 120 + n * 40; gg = 112 + n * 30; b = 80 + n * 20; }      // wet sand / river bed
        else if (h < 7) { r = 196 + n * 25; gg = 182 + n * 20; b = 130 + n * 20; }       // beach
        else {
          const hill = Math.min(1, h / 260);
          r = 78 + n * 34 + hill * 30;
          gg = 112 + n * 40 - hill * 10;
          b = 56 + n * 18;
          if (h > 200) { const k = (h - 200) / 120; r += k * 50; gg += k * 20; b += k * 40; } // rocky tops
        }
        const i = (py * size + px) * 4;
        d[i] = r; d[i + 1] = gg; d[i + 2] = b; d[i + 3] = 255;
      }
    }
    g.putImageData(img, 0, 0);
    g.scale(gs, gs);

    // Fields
    for (let i = 0; i < 26; i++) {
      const x = rng() * (S - 500), y = rng() * (S - 500), w = 260 + rng() * 360, h = 200 + rng() * 300;
      if (!isLand(map, x, y) || !isLand(map, x + w, y + h) || heightAt(map, x + w / 2, y + h / 2) > 120) continue;
      g.fillStyle = rng() < 0.5 ? 'rgba(186,160,84,0.45)' : 'rgba(128,150,62,0.4)';
      g.fillRect(x, y, w, h);
      g.strokeStyle = 'rgba(90,80,40,0.2)';
      g.lineWidth = 5;
      for (let k = 10; k < h; k += 24) { g.beginPath(); g.moveTo(x, y + k); g.lineTo(x + w, y + k); g.stroke(); }
    }
    // Town ground
    for (const t of map.towns) {
      g.fillStyle = t.military ? 'rgba(120,118,104,0.6)' : 'rgba(140,124,96,0.45)';
      g.beginPath(); g.arc(t.x, t.y, t.r + 90, 0, TAU); g.fill();
    }
    // Roads
    g.lineCap = 'round';
    for (const rd of map.roads) {
      g.strokeStyle = '#5f5446';
      g.lineWidth = rd.w + 12;
      g.beginPath(); g.moveTo(rd.x1, rd.y1); g.lineTo(rd.x2, rd.y2); g.stroke();
      g.strokeStyle = '#827565';
      g.lineWidth = rd.w;
      g.beginPath(); g.moveTo(rd.x1, rd.y1); g.lineTo(rd.x2, rd.y2); g.stroke();
      g.strokeStyle = 'rgba(230,220,180,0.35)';
      g.lineWidth = 3;
      g.setLineDash([30, 30]);
      g.beginPath(); g.moveTo(rd.x1, rd.y1); g.lineTo(rd.x2, rd.y2); g.stroke();
      g.setLineDash([]);
    }
    // Arena floor
    g.fillStyle = '#7d7f7a';
    g.fillRect(ARENA.x, ARENA.y, ARENA.w, ARENA.h);
    g.strokeStyle = 'rgba(255,255,255,0.35)';
    g.lineWidth = 6;
    g.strokeRect(ARENA.x + 40, ARENA.y + 40, ARENA.w - 80, ARENA.h - 80);
    // Building floors
    for (const b of map.buildings) {
      g.fillStyle = b.military ? '#77786f' : '#9a8569';
      g.fillRect(b.x, b.y, b.w, b.h);
      g.strokeStyle = 'rgba(0,0,0,0.12)';
      g.lineWidth = 2;
      for (let k = 24; k < b.w; k += 24) { g.beginPath(); g.moveTo(b.x + k, b.y); g.lineTo(b.x + k, b.y + b.h); g.stroke(); }
    }
    return cv;
  }

  // Breaks walls/crates within radius r of (x, y). Returns the destroyed obstacles.
  function destroyAt(map, x, y, r) {
    const out = [];
    query(map, x - r, y - r, x + r, y + r, (o) => {
      if (o.t !== 0 || o.fence || o.arena || (o.kind !== 'wall' && o.kind !== 'crate')) return;
      const cx = Math.max(o.x, Math.min(x, o.x + o.w)), cy = Math.max(o.y, Math.min(y, o.y + o.h));
      if ((x - cx) ** 2 + (y - cy) ** 2 < r * r) { o.dead = true; out.push(o); }
    });
    return out;
  }

  function inArena(map, x, y) {
    const A = map.arena;
    return x > A.x && x < A.x + A.w && y > A.y && y < A.y + A.h;
  }

  ZZ.Map = {
    CELL, GROUND_SCALE,
    createMap, collideCircle, isFree, segmentHit, buildingAt, query, destroyAt, inArena, distToSegment,
    heightAt, isLand, isDeep, terrainSpeed, terrainBlocks, HSTEP,
  };
})();
