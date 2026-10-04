'use strict';

(() => {
  const ZZ = window.ZZ;
  const TAU = Math.PI * 2;
  const CELL = 250;
  const WALL = 12;
  const DOOR = 64;
  const WALL_SEG = 64; // walls are split into segments so explosions can break holes in them
  // Fenced "second chance" duel arena in the north-west corner.
  const ARENA = { x: 140, y: 140, w: 560, h: 560 };
  const GROUND_SCALE = 0.4;

  const TOWN_NAMES = ['الميناء', 'المدينة القديمة', 'المزرعة', 'المحطة', 'الوادي', 'القلعة', 'السوق', 'المصنع', 'التلال', 'الواحة',
    'المنارة', 'الجسر', 'المطار', 'النخيل', 'المنجم', 'البحيرة'];
  const ROOF_COLORS = ['#8c3b2e', '#6e4a35', '#5c5f66', '#7a2f2f', '#4f5d4a', '#86643e'];

  function distToSegment(px, py, x1, y1, x2, y2) {
    const dx = x2 - x1, dy = y2 - y1;
    const l2 = dx * dx + dy * dy;
    let t = l2 ? ((px - x1) * dx + (py - y1) * dy) / l2 : 0;
    t = Math.max(0, Math.min(1, t));
    const cx = x1 + dx * t, cy = y1 + dy * t;
    return Math.hypot(px - cx, py - cy);
  }

  function createMap(seed) {
    const rng = ZZ.mulberry32(seed);
    const R = (a, b) => a + rng() * (b - a);
    const RI = (a, b) => Math.floor(R(a, b + 1));
    const S = ZZ.MAP_SIZE;
    const area = (S / 5000) ** 2; // scale prop counts with map area
    const nearArena = (x, y, pad) => x > ARENA.x - pad && x < ARENA.x + ARENA.w + pad && y > ARENA.y - pad && y < ARENA.y + ARENA.h + pad;

    const map = {
      size: S, seed,
      obs: [],         // obstacles: {t:0 rect x,y,w,h | t:1 circle x,y,r, kind}
      buildings: [],   // {x,y,w,h,doors:[{x,y,nx,ny}],roof,military}
      trees: [],       // references into obs with canopy radius
      towns: [],
      roads: [],
      lootSpots: [],   // {x,y,bld,military}
      grid: null, cols: 0, rows: 0,
      stamp: 0,
    };

    // ----- Towns -----
    const names = TOWN_NAMES.slice().sort(() => rng() - 0.5);
    const townCount = Math.round(9 * Math.sqrt(area) + 1);
    let tries = 0;
    while (map.towns.length < townCount && tries++ < 2000) {
      const military = map.towns.length === 0;
      const r = military ? 480 : R(260, 420);
      const x = R(500 + r * 0.5, S - 500 - r * 0.5);
      const y = R(500 + r * 0.5, S - 500 - r * 0.5);
      if (map.towns.some((t) => Math.hypot(t.x - x, t.y - y) < t.r + r + 450)) continue;
      if (nearArena(x, y, r + 250)) continue;
      map.towns.push({ name: military ? 'القاعدة العسكرية' : names.pop() || 'قرية', x, y, r, military });
    }

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
      map.buildings.push(b);
      const spots = RI(2, military ? 5 : 4);
      for (let i = 0; i < spots; i++) {
        map.lootSpots.push({ x: R(x + 34, x + w - 34), y: R(y + 34, y + h - 34), bld: bi, military });
      }
    }

    for (const town of map.towns) {
      const count = town.military ? 11 : RI(4, 8);
      let placed = 0, attempts = 0;
      while (placed < count && attempts++ < 400) {
        const w = R(170, town.military ? 330 : 290);
        const h = R(150, town.military ? 280 : 250);
        const a = R(0, TAU), d = R(0, town.r);
        const x = town.x + Math.cos(a) * d - w / 2;
        const y = town.y + Math.sin(a) * d - h / 2;
        if (x < 120 || y < 120 || x + w > S - 120 || y + h > S - 120) continue;
        if (overlapsBuilding(x, y, w, h, 70)) continue;
        if (nearRoad(x + w / 2, y + h / 2, Math.max(w, h) / 2 + 10)) continue;
        addBuilding(x, y, w, h, town.military);
        placed++;
      }
    }

    // Lone houses scattered across the countryside.
    let lone = 0, loneTries = 0;
    while (lone < Math.round(24 * area) && loneTries++ < 3000) {
      const w = R(150, 230), h = R(140, 210);
      const x = R(200, S - 200 - w), y = R(200, S - 200 - h);
      if (map.towns.some((t) => Math.hypot(t.x - x, t.y - y) < t.r + 300)) continue;
      if (overlapsBuilding(x, y, w, h, 200)) continue;
      if (nearRoad(x + w / 2, y + h / 2, Math.max(w, h) / 2 + 10)) continue;
      addBuilding(x, y, w, h, false);
      lone++;
    }

    // Arena: closed fence (unbreakable) with a few crates for cover.
    const A = ARENA, F = 16;
    pushWall(A.x, A.y, A.w, F, { fence: true, bld: -1 });
    pushWall(A.x, A.y + A.h - F, A.w, F, { fence: true, bld: -1 });
    pushWall(A.x, A.y + F, F, A.h - 2 * F, { fence: true, bld: -1 });
    pushWall(A.x + A.w - F, A.y + F, F, A.h - 2 * F, { fence: true, bld: -1 });
    for (const [cx, cy] of [[0.5, 0.5], [0.3, 0.32], [0.7, 0.68], [0.3, 0.7], [0.7, 0.3]]) {
      map.obs.push({ t: 0, x: A.x + A.w * cx - 24, y: A.y + A.h * cy - 24, w: 48, h: 48, kind: 'crate', arena: true });
    }
    map.arena = { ...ARENA, spawnA: { x: A.x + A.w * 0.2, y: A.y + A.h * 0.5 }, spawnB: { x: A.x + A.w * 0.8, y: A.y + A.h * 0.5 } };

    const blockedForProp = (x, y, r) =>
      overlapsBuilding(x - r, y - r, r * 2, r * 2, 40) || nearRoad(x, y, r + 8) || x < 80 || y < 80 || x > S - 80 || y > S - 80;

    // ----- Crates / containers near towns (with outdoor loot) -----
    for (const town of map.towns) {
      const n = town.military ? 10 : RI(3, 6);
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

    // ----- Trees (forests + scattered) -----
    const addTree = (x, y) => {
      if (blockedForProp(x, y, 30)) return;
      if (map.towns.some((t) => Math.hypot(t.x - x, t.y - y) < t.r * 0.75)) return;
      const tree = { t: 1, x, y, r: R(10, 14), kind: 'tree', canopy: R(32, 48), shade: R(0, 1) };
      map.obs.push(tree);
      map.trees.push(tree);
    };
    for (let f = 0; f < Math.round(26 * area); f++) {
      const cx = R(300, S - 300), cy = R(300, S - 300);
      const n = RI(14, 34);
      for (let i = 0; i < n; i++) {
        const a = R(0, TAU), d = Math.abs(R(-1, 1) + R(-1, 1)) * 170;
        addTree(cx + Math.cos(a) * d, cy + Math.sin(a) * d);
      }
    }
    for (let i = 0; i < Math.round(220 * area); i++) addTree(R(100, S - 100), R(100, S - 100));

    // ----- Rocks -----
    for (let i = 0; i < Math.round(120 * area); i++) {
      const x = R(150, S - 150), y = R(150, S - 150), r = R(20, 42);
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

  // ---------- Ground pre-render ----------
  function renderGround(map, rng) {
    const S = map.size, gs = GROUND_SCALE;
    const cv = document.createElement('canvas');
    cv.width = cv.height = Math.ceil(S * gs);
    const g = cv.getContext('2d');
    g.scale(gs, gs);

    g.fillStyle = '#4d6e3b';
    g.fillRect(0, 0, S, S);
    // Grass variation
    for (let i = 0; i < 2600 * (S / 5000) ** 2; i++) {
      const x = rng() * S, y = rng() * S, r = 40 + rng() * 160;
      g.fillStyle = rng() < 0.5 ? 'rgba(90,128,62,0.1)' : 'rgba(58,86,44,0.12)';
      g.beginPath(); g.ellipse(x, y, r, r * (0.5 + rng() * 0.5), rng() * TAU, 0, TAU); g.fill();
    }
    // Wheat fields
    for (let i = 0; i < 14 * (S / 5000) ** 2; i++) {
      const x = rng() * (S - 500), y = rng() * (S - 500), w = 250 + rng() * 300, h = 200 + rng() * 260;
      g.fillStyle = rng() < 0.5 ? 'rgba(170,150,80,0.35)' : 'rgba(120,140,60,0.35)';
      g.fillRect(x, y, w, h);
      g.strokeStyle = 'rgba(90,80,40,0.18)';
      g.lineWidth = 4;
      for (let k = 10; k < h; k += 22) { g.beginPath(); g.moveTo(x, y + k); g.lineTo(x + w, y + k); g.stroke(); }
    }
    // Town ground
    for (const t of map.towns) {
      g.fillStyle = t.military ? 'rgba(120,118,104,0.55)' : 'rgba(132,118,92,0.4)';
      g.beginPath(); g.arc(t.x, t.y, t.r + 80, 0, TAU); g.fill();
    }
    // Roads
    g.lineCap = 'round';
    for (const rd of map.roads) {
      g.strokeStyle = '#6b5d44';
      g.lineWidth = rd.w + 10;
      g.beginPath(); g.moveTo(rd.x1, rd.y1); g.lineTo(rd.x2, rd.y2); g.stroke();
      g.strokeStyle = '#8d7c5c';
      g.lineWidth = rd.w;
      g.beginPath(); g.moveTo(rd.x1, rd.y1); g.lineTo(rd.x2, rd.y2); g.stroke();
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
  };
})();
