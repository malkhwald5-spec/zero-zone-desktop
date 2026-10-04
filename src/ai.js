'use strict';

// Bot behaviour. Bots use the exact same actions as the player (G.tryFire, G.pickup, ...).
(() => {
  const ZZ = window.ZZ;
  const { WEAPONS, CLASS_RANGE, MEDS, AMMO_CAP } = ZZ;
  const TAU = Math.PI * 2;
  const rand = (a, b) => a + Math.random() * (b - a);
  const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
  const angDiff = (a, b) => { let d = (b - a) % TAU; if (d > Math.PI) d -= TAU; if (d < -Math.PI) d += TAU; return d; };

  function init(b) {
    b.ai = {
      mode: 'loot', target: null, lastSeenT: -99, lastSeenX: 0, lastSeenY: 0,
      thinkT: rand(0, 0.3), reactT: 0, aimErr: 0, burstT: 0, semiT: 0,
      wp: null, lootItem: null, ignore: new Set(),
      strafeDir: Math.random() < 0.5 ? 1 : -1, strafeT: 0,
      stuckCheckT: 0.6, lastX: 0, lastY: 0, unstuckT: 0, unstuckAng: 0,
      roam: null, zoneOffset: { a: rand(0, TAU), d: rand(0.1, 0.55) }, zonePhase: -2,
      // How eager this bot is to pick fights instead of looting/hiding.
      aggro: rand(0.15, 1),
      lookT: 0, lookAng: 0,
    };
  }

  // ---------- Helpers ----------
  function usableSlots(b) {
    const out = [];
    for (let i = 0; i < 3; i++) {
      const s = b.slots[i];
      if (s && (s.mag > 0 || b.ammo[WEAPONS[s.type].ammo] > 0)) out.push(i);
    }
    return out;
  }

  function slotScore(b, i, d) {
    const w = WEAPONS[b.slots[i].type];
    const pref = CLASS_RANGE[w.cls];
    const fit = 1 / (1 + Math.abs(d - pref) / 300);
    const outOfRange = d > w.range * 0.85 ? 0.2 : 1;
    return (w.tier + 2) * fit * outOfRange * (b.slots[i].mag > 0 ? 1 : 0.6);
  }

  function itemValue(b, it) {
    switch (it.kind) {
      case 'weapon': {
        const w = WEAPONS[it.type];
        if (w.cls === 'pistol') return b.slots[2] ? 0 : (b.slots[0] || b.slots[1] ? 2 : 9);
        const prim = [b.slots[0], b.slots[1]].filter(Boolean);
        if (prim.length < 2) return prim.some((s) => s.type === it.type) ? 3 : 10 + w.tier;
        const worst = Math.min(...prim.map((s) => WEAPONS[s.type].tier));
        return w.tier > worst + 1 ? 5 + w.tier : 0;
      }
      case 'ammo': {
        const uses = b.slots.some((s) => s && WEAPONS[s.type].ammo === it.type);
        if (!uses) return 0;
        const have = b.ammo[it.type];
        if (have >= AMMO_CAP[b.pack]) return 0;
        return have < 60 ? 9 : 4;
      }
      case 'vest': return it.lvl > b.vest ? 8 + it.lvl : 0;
      case 'helmet': return it.lvl > b.helmet ? 7 + it.lvl : 0;
      case 'pack': return it.lvl > b.pack ? 5 : 0;
      case 'med': return b.meds[it.type] < MEDS[it.type].max[b.pack] ? (it.type === 'bandage' ? 3 : 5) : 0;
      case 'grenade': return b.grenades < ZZ.GRENADE_MAX[b.pack] ? 2 : 0;
    }
    return 0;
  }

  function insideCircle(x, y, cx, cy, r) { return (x - cx) ** 2 + (y - cy) ** 2 < r * r; }

  // Waypoint that routes through doors when entering/leaving buildings.
  function navTarget(b, tx, ty, G) {
    const bi = G.buildingAt(b.x, b.y);
    const ti = G.buildingAt(tx, ty);
    if (bi === ti) return { x: tx, y: ty };
    if (bi >= 0) {
      const bld = G.map.buildings[bi];
      const door = nearestDoor(bld, tx, ty);
      if (Math.hypot(b.x - door.x, b.y - door.y) < 30) return { x: door.x + door.nx * 50, y: door.y + door.ny * 50 };
      return { x: door.x - door.nx * 6, y: door.y - door.ny * 6 };
    }
    const bld = G.map.buildings[ti];
    const door = nearestDoor(bld, b.x, b.y);
    if (Math.hypot(b.x - door.x, b.y - door.y) < 58) return { x: door.x - door.nx * 34, y: door.y - door.ny * 34 };
    return { x: door.x + door.nx * 44, y: door.y + door.ny * 44 };
  }

  function nearestDoor(bld, x, y) {
    let best = bld.doors[0], bd = Infinity;
    for (const d of bld.doors) {
      const dd = (d.x - x) ** 2 + (d.y - y) ** 2;
      if (dd < bd) { bd = dd; best = d; }
    }
    return best;
  }

  // ---------- Think (low frequency decisions) ----------
  function think(b, G) {
    const ai = b.ai;
    const now = G.time;
    const z = G.zone;

    // Perception: a forward vision cone, plus hearing nearby gunfire.
    const viewRange = 430 + b.skill * 300;
    const provoked = b.lastHitBy && now - b.lastHitT < 4;
    let seen = null, seenD = Infinity;
    for (const u of G.units) {
      if (u === b || !u.alive || u.phase !== 'ground') continue;
      const dx = u.x - b.x, dy = u.y - b.y;
      if (Math.abs(dx) > viewRange || Math.abs(dy) > viewRange) continue;
      const d = Math.hypot(dx, dy);
      if (d > viewRange || d >= seenD) continue;
      const heard = now - u.lastShotT < 0.8 && d < 750;
      if (heard && ai.lookT <= 0 && u !== ai.target) { ai.lookT = 1.2; ai.lookAng = Math.atan2(dy, dx); }
      const inCone = Math.abs(angDiff(b.angle, Math.atan2(dy, dx))) < 1.05;
      if (!inCone && d > 130) continue;
      // Tree canopies give some concealment at range.
      if (d > 320 && u.underCanopy && Math.random() < 0.6) continue;
      if (G.segmentHit(b.x, b.y, u.x, u.y) >= 0) continue;
      seen = u; seenD = d;
    }
    if (!seen && b.lastHitBy && b.lastHitBy.alive && now - b.lastHitT < 2.5) {
      // Got shot by someone out of sight: remember where it came from.
      const a = b.lastHitBy;
      if (ai.target !== a) { ai.target = a; ai.lastSeenX = a.x; ai.lastSeenY = a.y; ai.lastSeenT = now - 0.5; }
    }
    // Passive bots ignore distant enemies unless they were just shot at.
    // Right after landing bots concentrate on looting.
    const looting = now - (b.landT || 0) < 75;
    const engageR = looting ? 150 + ai.aggro * 200 : 200 + ai.aggro * 460;
    if (seen && !provoked && seenD > engageR && seen !== ai.target) seen = null;
    if (seen) {
      if (ai.target !== seen || now - ai.lastSeenT > 2) ai.reactT = Math.max(0.35, 1.2 - b.skill * 0.7) + rand(0, 0.4);
      ai.target = seen;
      ai.lastSeenT = now;
      ai.lastSeenX = seen.x; ai.lastSeenY = seen.y;
    }
    if (ai.target && (!ai.target.alive || now - ai.lastSeenT > 6)) ai.target = null;
    ai.aimErr = (0.07 + (1 - b.skill) * 0.25) * rand(-1, 1);

    const usable = usableSlots(b);
    const targetD = ai.target ? Math.hypot(ai.lastSeenX - b.x, ai.lastSeenY - b.y) : 0;

    // Weapon management
    if (usable.length) {
      let best = usable[0], bs = -1;
      for (const i of usable) { const s = slotScore(b, i, ai.target ? targetD : 400); if (s > bs) { bs = s; best = i; } }
      if (b.active !== best && b.reloadT <= 0) G.switchSlot(b, best);
      const s = b.slots[b.active];
      if (s && b.reloadT <= 0) {
        const w = WEAPONS[s.type];
        const reserve = b.ammo[w.ammo];
        if (s.mag === 0 && reserve > 0) G.startReload(b);
        else if (s.mag < w.mag * 0.4 && reserve > 0 && now - ai.lastSeenT > 1.5) G.startReload(b);
      }
    } else if (b.active !== -1) {
      G.switchSlot(b, -1);
    }

    // Pick up anything useful within reach.
    for (const it of G.items) {
      if (Math.abs(it.x - b.x) > 46 || Math.abs(it.y - b.y) > 46) continue;
      if (ai.ignore.has(it.id)) continue;
      if (itemValue(b, it) > 0) {
        const res = G.pickup(b, it);
        if (res === 'none') ai.ignore.add(it.id);
      }
    }

    // Zone awareness
    const zoneTarget = z.state === 'wait' && z.timer > 30 ? { x: z.cx, y: z.cy, r: z.r } : { x: z.nx, y: z.ny, r: z.nr };
    const safeR = Math.max(20, zoneTarget.r * 0.85);
    const outsideSafe = !insideCircle(b.x, b.y, zoneTarget.x, zoneTarget.y, safeR);
    const outsideNow = !insideCircle(b.x, b.y, z.cx, z.cy, z.r);
    if (ai.zonePhase !== z.phase) {
      ai.zonePhase = z.phase;
      ai.zoneOffset = { a: rand(0, TAU), d: rand(0.05, 0.6) };
      ai.roam = null;
    }

    const recentlySeen = ai.target && now - ai.lastSeenT < 3;

    const wantsOut = b.hp < 45 && ai.aggro < 0.75;
    // Cautious bots back off from enemies that haven't engaged them yet.
    const cautious = !provoked && ai.aggro < 0.55 && targetD > 150;
    if (recentlySeen && usable.length && (wantsOut || cautious)) {
      ai.mode = 'flee';
    } else if (recentlySeen && usable.length && !(outsideNow && z.dps >= 4)) {
      ai.mode = 'fight';
    } else if (recentlySeen && !usable.length) {
      ai.mode = targetD < 120 ? 'melee' : 'flee';
    } else if (outsideSafe && (outsideNow || z.state === 'shrink' || z.timer < 35)) {
      ai.mode = 'rotate';
      const a = ai.zoneOffset.a, d = ai.zoneOffset.d * zoneTarget.r;
      ai.wp = { x: zoneTarget.x + Math.cos(a) * d, y: zoneTarget.y + Math.sin(a) * d };
    } else {
      // Heal / boost when safe.
      if (b.healT <= 0 && b.reloadT <= 0 && !recentlySeen) {
        if (b.hp < 50 && b.meds.medkit) G.useMed(b, 'medkit');
        else if (b.hp < 70 && b.meds.firstaid) G.useMed(b, 'firstaid');
        else if (b.hp < 75 && b.meds.bandage) G.useMed(b, 'bandage');
        else if (b.boost < 40 && b.meds.drink && Math.random() < 0.15) G.useMed(b, 'drink');
        else if (b.boost < 30 && b.meds.pills && b.hp < 85 && Math.random() < 0.15) G.useMed(b, 'pills');
      }
      // Loot: avoid items another bot has claimed or that others are standing near.
      const others = [];
      for (const u of G.units) {
        if (u !== b && u.alive && u.phase === 'ground' && Math.abs(u.x - b.x) < 700 && Math.abs(u.y - b.y) < 700) others.push(u);
      }
      let best = null, bestScore = 0;
      for (const it of G.items) {
        const dx = it.x - b.x, dy = it.y - b.y;
        const reach = b.slots[0] || b.slots[1] ? 360 : 480;
        if (dx > reach || dx < -reach || dy > reach || dy < -reach) continue;
        if (ai.ignore.has(it.id)) continue;
        if (it.claim && it.claim !== b && it.claim.alive && now - it.claimT < 4) continue;
        const v = itemValue(b, it);
        if (v <= 0) continue;
        let crowd = 0;
        for (const u of others) if (Math.abs(u.x - it.x) < 260 && Math.abs(u.y - it.y) < 260) crowd++;
        const score = v / (1 + Math.hypot(dx, dy) / 220) / (1 + crowd * 2);
        if (score > bestScore) { bestScore = score; best = it; }
      }
      if (best) {
        ai.mode = 'loot';
        ai.lootItem = best;
        best.claim = b;
        best.claimT = now;
        ai.wp = { x: best.x, y: best.y };
      } else if (ai.aggro < 0.7 && usable.length) {
        // Hold a building (or stay put) until the zone forces a move.
        ai.mode = 'hold';
        if (!ai.hold || !insideCircle(ai.hold.x, ai.hold.y, zoneTarget.x, zoneTarget.y, safeR)) {
          let bestB = null, bd = 900;
          for (const bl of G.map.buildings) {
            const cx = bl.x + bl.w / 2, cy = bl.y + bl.h / 2;
            const d = Math.hypot(cx - b.x, cy - b.y);
            if (d < bd && insideCircle(cx, cy, zoneTarget.x, zoneTarget.y, safeR)) { bd = d; bestB = { x: cx + rand(-bl.w / 4, bl.w / 4), y: cy + rand(-bl.h / 4, bl.h / 4) }; }
          }
          ai.hold = bestB || { x: b.x, y: b.y };
        }
        ai.wp = ai.hold;
      } else {
        ai.mode = 'roam';
        if (!ai.roam || Math.hypot(ai.roam.x - b.x, ai.roam.y - b.y) < 60) {
          const a = rand(0, TAU), d = rand(0, zoneTarget.r * 0.7);
          ai.roam = {
            x: Math.max(100, Math.min(G.map.size - 100, zoneTarget.x + Math.cos(a) * d)),
            y: Math.max(100, Math.min(G.map.size - 100, zoneTarget.y + Math.sin(a) * d)),
          };
        }
        ai.wp = ai.roam;
      }
    }

    // Grenades at enemies behind light cover at mid range.
    if (ai.mode === 'fight' && b.grenades > 0 && targetD > 160 && targetD < 420 && now - ai.lastSeenT > 0.6 && Math.random() < 0.08 * b.skill) {
      G.throwGrenade(b, ai.lastSeenX, ai.lastSeenY);
    }
  }

  // ---------- Update (every frame) ----------
  function update(b, dt, G) {
    const ai = b.ai;
    ai.thinkT -= dt;
    if (ai.thinkT <= 0) { ai.thinkT = rand(0.2, 0.32); think(b, G); }
    ai.reactT -= dt;
    ai.lookT -= dt;

    let mx = 0, my = 0;
    const tgt = ai.target;
    const visible = tgt && G.time - ai.lastSeenT < 0.35;

    if ((ai.mode === 'fight' || ai.mode === 'melee' || ai.mode === 'flee') && tgt) {
      const tx = visible ? tgt.x : ai.lastSeenX, ty = visible ? tgt.y : ai.lastSeenY;
      const dx = tx - b.x, dy = ty - b.y;
      const d = Math.hypot(dx, dy) || 1;
      const ux = dx / d, uy = dy / d;
      if (ai.mode === 'flee') { mx = -ux; my = -uy; }
      else if (ai.mode === 'melee') { mx = ux; my = uy; }
      else {
        const s = b.slots[b.active];
        const pref = s ? CLASS_RANGE[WEAPONS[s.type].cls] : 60;
        if (!visible) {
          // Push to last known position, but carefully when hurt.
          if (b.hp > 45 && ai.aggro > 0.5) { const wp = navTarget(b, tx, ty, G); const wd = Math.hypot(wp.x - b.x, wp.y - b.y) || 1; mx = (wp.x - b.x) / wd; my = (wp.y - b.y) / wd; }
        } else {
          ai.strafeT -= dt;
          if (ai.strafeT <= 0) { ai.strafeT = rand(0.6, 1.6); ai.strafeDir *= Math.random() < 0.6 ? -1 : 1; }
          let fwd = 0;
          if (d > pref * 1.25) fwd = 1; else if (d < pref * 0.6) fwd = -0.8;
          const strafe = 0.55 + b.skill * 0.35;
          mx = ux * fwd - uy * ai.strafeDir * strafe;
          my = uy * fwd + ux * ai.strafeDir * strafe;
        }
        // Drift toward the zone while fighting outside it.
        const z = G.zone;
        if (!insideCircle(b.x, b.y, z.cx, z.cy, z.r)) {
          const zd = Math.hypot(z.cx - b.x, z.cy - b.y) || 1;
          mx += (z.cx - b.x) / zd * 0.8; my += (z.cy - b.y) / zd * 0.8;
        }
      }
      // Aim
      let aimX = tx, aimY = ty;
      if (visible) {
        const s = b.slots[b.active];
        const speed = s ? WEAPONS[s.type].speed : 1000;
        const lead = (d / speed) * b.skill;
        aimX += (tgt.vx || 0) * lead; aimY += (tgt.vy || 0) * lead;
      }
      const want = Math.atan2(aimY - b.y, aimX - b.x) + ai.aimErr;
      const turn = (3 + b.skill * 9) * dt;
      const diff = angDiff(b.angle, want);
      b.angle += Math.max(-turn, Math.min(turn, diff));

      // Fire
      if (visible && ai.reactT <= 0 && Math.abs(diff) < 0.14) {
        const s = b.slots[b.active];
        if (!s) { if (d < 50) G.tryFire(b); }
        else {
          const w = WEAPONS[s.type];
          b.aiming = (w.cls === 'ar' || w.cls === 'dmr' || w.cls === 'sr' || w.cls === 'lmg') && d > 350;
          if (d < w.range * 0.9) {
            if (w.auto) {
              // Fire in bursts with pauses; better bots pause less.
              ai.burstT -= dt;
              if (ai.burstT > 0) G.tryFire(b);
              else if (ai.burstT < -(0.2 + (1 - b.skill) * 0.45)) ai.burstT = rand(0.25, 0.7);
            } else {
              ai.semiT -= dt;
              if (ai.semiT <= 0 && G.tryFire(b)) ai.semiT = rand(0.08, 0.35) * (1.4 - b.skill) + (w.cls === 'sr' ? 0.4 : 0);
            }
          }
        }
      } else {
        b.aiming = false;
      }
    } else {
      b.aiming = false;
      if (ai.wp) {
        const wp = navTarget(b, ai.wp.x, ai.wp.y, G);
        const dx = wp.x - b.x, dy = wp.y - b.y;
        const d = Math.hypot(dx, dy);
        if (d > (ai.mode === 'hold' ? 24 : 8)) { mx = dx / d; my = dy / d; }
        if (ai.lookT > 0) {
          b.angle += Math.max(-7 * dt, Math.min(7 * dt, angDiff(b.angle, ai.lookAng)));
        } else if (d > 8) {
          const want = Math.atan2(dy, dx);
          b.angle += Math.max(-6 * dt, Math.min(6 * dt, angDiff(b.angle, want)));
        }
      }
    }

    // Unstick
    ai.stuckCheckT -= dt;
    if (ai.stuckCheckT <= 0) {
      ai.stuckCheckT = 0.6;
      const moved = Math.hypot(b.x - ai.lastX, b.y - ai.lastY);
      if ((mx || my) && moved < 12 && ai.unstuckT <= 0) {
        ai.unstuckT = rand(0.35, 0.8);
        ai.unstuckAng = Math.atan2(my, mx) + (Math.random() < 0.5 ? 1 : -1) * rand(1.2, 2.2);
      }
      ai.lastX = b.x; ai.lastY = b.y;
    }
    if (ai.unstuckT > 0) {
      ai.unstuckT -= dt;
      mx = Math.cos(ai.unstuckAng); my = Math.sin(ai.unstuckAng);
    }

    const l = Math.hypot(mx, my);
    b.moveX = l ? mx / l : 0;
    b.moveY = l ? my / l : 0;
    b.sprint = ai.mode === 'rotate' || ai.mode === 'flee';
    b.walk = ai.mode === 'loot' || ai.mode === 'roam' || ai.mode === 'hold';
    // Holding bots look around slowly instead of standing frozen.
    if (ai.mode === 'hold' && !b.moveX && !b.moveY && ai.lookT <= 0) b.angle += dt * 0.6 * ai.strafeDir;
  }

  ZZ.AI = { init, update, itemValue, navTarget };
})();
