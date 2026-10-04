'use strict';

// Three.js renderer. The simulation stays 2D (x, y on the ground); here it is
// drawn in 3D with sim x -> world x, sim y -> world z, and heights on world y.
(() => {
  const ZZ = window.ZZ;
  const T = window.THREE;
  const { WEAPONS, AMMO, VEST, HELMET } = ZZ;

  const H = {
    wall: 110, fence: 140, crate: 44, container: 64,
    unit: 40, chest: 28, plane: 1100, chute: 900,
  };
  ZZ.HEIGHTS = H;

  const GUN_LEN = { pistol: 10, smg: 16, shotgun: 22, ar: 24, dmr: 28, sr: 34, lmg: 28 };
  const tmpM = new T.Matrix4(), tmpQ = new T.Quaternion(), tmpS = new T.Vector3(), tmpP = new T.Vector3(), tmpC = new T.Color();
  const UP = new T.Vector3(0, 1, 0);
  const ZERO_SCALE = new T.Vector3(0, 0, 0);

  // Parses CSS colours once (rgba alpha is dropped; Three.js colours are opaque).
  const colorCache = new Map();
  function colorOf(str) {
    let c = colorCache.get(str);
    if (!c) {
      c = new T.Color(String(str).replace(/rgba\(([^,]+),([^,]+),([^,]+),[^)]+\)/, 'rgb($1,$2,$3)'));
      colorCache.set(str, c);
    }
    return c;
  }

  function setInst(mesh, i, x, y, z, sx, sy, sz, rotY = 0) {
    tmpQ.setFromAxisAngle(UP, rotY);
    tmpP.set(x, y, z);
    tmpS.set(sx, sy, sz);
    tmpM.compose(tmpP, tmpQ, tmpS);
    mesh.setMatrixAt(i, tmpM);
  }
  function hideInst(mesh, i) {
    tmpM.compose(tmpP.set(0, -1000, 0), tmpQ.identity(), ZERO_SCALE);
    mesh.setMatrixAt(i, tmpM);
  }

  class Renderer3D {
    constructor(canvas) {
      this.canvas = canvas;
      this.renderer = new T.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
      this.renderer.setPixelRatio(Math.min(2, window.devicePixelRatio || 1));
      this.renderer.shadowMap.enabled = true;
      this.renderer.shadowMap.type = T.PCFSoftShadowMap;

      this.scene = new T.Scene();
      const sky = new T.Color('#a9cdea');
      this.scene.background = sky;
      this.scene.fog = new T.Fog(sky, 1400, 4200);

      this.camera = new T.PerspectiveCamera(70, 1, 2, 12000);
      this.scene.add(new T.HemisphereLight(0xd8ecff, 0x4d6e3b, 0.9));
      const sun = new T.DirectionalLight(0xfff0d0, 1.6);
      sun.castShadow = true;
      sun.shadow.mapSize.set(2048, 2048);
      const sc = sun.shadow.camera;
      sc.left = -650; sc.right = 650; sc.top = 650; sc.bottom = -650; sc.near = 10; sc.far = 3000;
      sun.shadow.bias = -0.0008;
      this.scene.add(sun, sun.target);
      this.sun = sun;

      this.world = null;
      this.unitModels = new Map();
      this.dropModels = new Map();
    }

    resize(w, h) {
      this.renderer.setSize(w, h, false);
      this.camera.aspect = w / h;
      this.camera.updateProjectionMatrix();
    }

    // ---------- World construction ----------
    buildWorld(G) {
      if (this.world) {
        this.scene.remove(this.world);
        this.world.traverse((o) => { if (o.geometry) o.geometry.dispose(); if (o.material && o.material.map) o.material.map.dispose(); });
      }
      this.unitModels.clear();
      this.dropModels.clear();
      const map = G.map, S = map.size;
      const W = new T.Group();
      this.world = W;
      this.scene.add(W);
      const lambert = (color, extra = {}) => new T.MeshLambertMaterial({ color, ...extra });

      // Ground (re-uses the pre-rendered 2D ground canvas as texture), beach and sea.
      const tex = new T.CanvasTexture(map.ground);
      tex.colorSpace = T.SRGBColorSpace;
      tex.anisotropy = this.renderer.capabilities.getMaxAnisotropy();
      const ground = new T.Mesh(new T.PlaneGeometry(S, S), new T.MeshLambertMaterial({ map: tex }));
      ground.rotation.x = -Math.PI / 2;
      ground.position.set(S / 2, 0, S / 2);
      ground.receiveShadow = true;
      W.add(ground);
      const beach = new T.Mesh(new T.PlaneGeometry(S + 260, S + 260), lambert('#cdbb85'));
      beach.rotation.x = -Math.PI / 2;
      beach.position.set(S / 2, -1.5, S / 2);
      W.add(beach);
      const sea = new T.Mesh(new T.PlaneGeometry(40000, 40000), lambert('#2d6a8e'));
      sea.rotation.x = -Math.PI / 2;
      sea.position.set(S / 2, -4, S / 2);
      W.add(sea);

      const box = new T.BoxGeometry(1, 1, 1);
      box.translate(0, 0.5, 0);

      // Walls (instanced so explosions can hide single segments).
      const walls = map.obs.filter((o) => o.kind === 'wall');
      const wallPalette = ['#cbbba0', '#bba88c', '#d6c9b0', '#b7aa98'];
      const wallMesh = new T.InstancedMesh(box, lambert('#ffffff'), walls.length);
      walls.forEach((o, i) => {
        const h = o.fence ? H.fence : H.wall;
        setInst(wallMesh, i, o.x + o.w / 2, 0, o.y + o.h / 2, o.w, h, o.h);
        let col;
        if (o.fence) col = '#5d6266';
        else if (map.buildings[o.bld].military) col = '#6b6e66';
        else col = wallPalette[o.bld % wallPalette.length];
        wallMesh.setColorAt(i, tmpC.set(col));
        o.inst = i;
      });
      wallMesh.castShadow = wallMesh.receiveShadow = true;
      W.add(wallMesh);
      this.wallMesh = wallMesh;

      // Roofs (one per building, hidden for the building the player is in).
      const roofMesh = new T.InstancedMesh(box, lambert('#ffffff'), map.buildings.length);
      map.buildings.forEach((b, i) => {
        setInst(roofMesh, i, b.x + b.w / 2, H.wall, b.y + b.h / 2, b.w + 10, 10, b.h + 10);
        roofMesh.setColorAt(i, tmpC.set(b.roof));
      });
      roofMesh.castShadow = true;
      W.add(roofMesh);
      this.roofMesh = roofMesh;
      this.roofHidden = -1;

      // Crates and containers.
      const crates = map.obs.filter((o) => o.kind === 'crate');
      const crateMesh = new T.InstancedMesh(box, lambert('#8a6a3e'), crates.length);
      crates.forEach((o, i) => { setInst(crateMesh, i, o.x + o.w / 2, 0, o.y + o.h / 2, o.w, H.crate, o.h); o.inst = i; });
      crateMesh.castShadow = crateMesh.receiveShadow = true;
      W.add(crateMesh);
      this.crateMesh = crateMesh;
      const conts = map.obs.filter((o) => o.kind === 'container');
      const contMesh = new T.InstancedMesh(box, lambert('#ffffff'), Math.max(1, conts.length));
      const contCols = ['#7a3b2c', '#2f5d8a', '#3f6b3a', '#8a6d2c'];
      conts.forEach((o, i) => {
        setInst(contMesh, i, o.x + o.w / 2, 0, o.y + o.h / 2, o.w, H.container, o.h);
        contMesh.setColorAt(i, tmpC.set(contCols[i % contCols.length]));
      });
      contMesh.castShadow = contMesh.receiveShadow = true;
      W.add(contMesh);

      // Rocks
      const rocks = map.obs.filter((o) => o.kind === 'rock');
      const rockMesh = new T.InstancedMesh(new T.DodecahedronGeometry(1, 0), lambert('#ffffff', { flatShading: true }), Math.max(1, rocks.length));
      rocks.forEach((o, i) => {
        setInst(rockMesh, i, o.x, o.r * 0.25, o.y, o.r * 1.05, o.r * 0.8, o.r * 1.05, o.shade * 6);
        rockMesh.setColorAt(i, tmpC.set(o.shade < 0.5 ? '#868a85' : '#767a75'));
      });
      rockMesh.castShadow = rockMesh.receiveShadow = true;
      W.add(rockMesh);

      // Trees: trunks + canopies
      const trees = map.trees;
      const trunkGeo = new T.CylinderGeometry(0.7, 1, 1, 6);
      trunkGeo.translate(0, 0.5, 0);
      const trunkMesh = new T.InstancedMesh(trunkGeo, lambert('#5a3f2a'), trees.length);
      const canopyMesh = new T.InstancedMesh(new T.IcosahedronGeometry(1, 0), lambert('#ffffff', { flatShading: true }), trees.length);
      const greens = ['#2f5a2a', '#376630', '#2a4f27', '#3e6e34'];
      trees.forEach((t, i) => {
        const th = 60 + t.canopy * 0.6;
        setInst(trunkMesh, i, t.x, 0, t.y, t.r, th, t.r);
        setInst(canopyMesh, i, t.x, th + t.canopy * 0.55, t.y, t.canopy * 1.1, t.canopy * 1.35, t.canopy * 1.1, t.shade * 5);
        canopyMesh.setColorAt(i, tmpC.set(greens[Math.floor(t.shade * greens.length)]));
      });
      trunkMesh.castShadow = canopyMesh.castShadow = true;
      W.add(trunkMesh, canopyMesh);

      // Items on the ground
      this.itemMesh = new T.InstancedMesh(box, lambert('#ffffff', { emissive: '#222222' }), 2500);
      this.itemMesh.count = 0;
      this.itemMesh.frustumCulled = false;
      W.add(this.itemMesh);

      // Decals (blood, scorch marks)
      const disc = new T.CircleGeometry(1, 16);
      disc.rotateX(-Math.PI / 2);
      this.decalMesh = new T.InstancedMesh(disc, new T.MeshBasicMaterial({ color: '#ffffff', transparent: true, opacity: 0.75, depthWrite: false }), 300);
      this.decalMesh.count = 0;
      this.decalMesh.frustumCulled = false;
      W.add(this.decalMesh);

      // Grenades
      this.nadeMesh = new T.InstancedMesh(new T.SphereGeometry(4, 8, 6), lambert('#4c5a34'), 40);
      this.nadeMesh.count = 0;
      this.nadeMesh.frustumCulled = false;
      W.add(this.nadeMesh);

      // Bullet tracers
      const MAXB = 1200;
      const bGeo = new T.BufferGeometry();
      bGeo.setAttribute('position', new T.BufferAttribute(new Float32Array(MAXB * 6), 3));
      bGeo.setAttribute('color', new T.BufferAttribute(new Float32Array(MAXB * 6), 3));
      this.tracers = new T.LineSegments(bGeo, new T.LineBasicMaterial({ vertexColors: true, transparent: true, opacity: 0.9 }));
      this.tracers.frustumCulled = false;
      this.MAXB = MAXB;
      W.add(this.tracers);

      // Particles (sparks/blood) and smoke
      const mkPoints = (max, size, opacity) => {
        const g = new T.BufferGeometry();
        g.setAttribute('position', new T.BufferAttribute(new Float32Array(max * 3), 3));
        g.setAttribute('color', new T.BufferAttribute(new Float32Array(max * 3), 3));
        const p = new T.Points(g, new T.PointsMaterial({ size, vertexColors: true, transparent: true, opacity, depthWrite: false, sizeAttenuation: true }));
        p.frustumCulled = false;
        p.userData.max = max;
        W.add(p);
        return p;
      };
      this.sparks = mkPoints(3000, 5, 0.95);
      this.flashes = mkPoints(200, 26, 0.9);
      this.smoke = mkPoints(800, 40, 0.45);

      // Zone walls
      const cyl = new T.CylinderGeometry(1, 1, 1, 128, 1, true);
      cyl.translate(0, 0.5, 0);
      this.zoneMesh = new T.Mesh(cyl, new T.MeshBasicMaterial({ color: '#3d7bff', transparent: true, opacity: 0.3, side: T.DoubleSide, depthWrite: false, fog: false }));
      this.zoneMesh.renderOrder = 10;
      this.nextMesh = new T.Mesh(cyl, new T.MeshBasicMaterial({ color: '#ffffff', transparent: true, opacity: 0.08, side: T.DoubleSide, depthWrite: false, fog: false }));
      this.nextMesh.renderOrder = 9;
      const loopPts = [];
      for (let i = 0; i <= 128; i++) loopPts.push(new T.Vector3(Math.cos((i / 128) * Math.PI * 2), 0, Math.sin((i / 128) * Math.PI * 2)));
      this.nextRing = new T.Line(new T.BufferGeometry().setFromPoints(loopPts), new T.LineBasicMaterial({ color: '#ffffff', fog: false }));
      W.add(this.zoneMesh, this.nextMesh, this.nextRing);

      // Plane
      this.planeModel = makePlane();
      W.add(this.planeModel);

      // Instanced meshes span the whole island; skip per-mesh frustum culling.
      W.traverse((o) => { if (o.isInstancedMesh) o.frustumCulled = false; });
      this.lastBroken = 0;
    }

    // ---------- Per-frame sync ----------
    render(G, view) {
      if (!this.world) return;
      const cam = this.camera;
      cam.position.set(view.x, view.y, view.z);
      cam.lookAt(view.tx, view.ty, view.tz);
      if (Math.abs(cam.fov - view.fov) > 0.01) { cam.fov = view.fov; cam.updateProjectionMatrix(); }
      // See much further while high in the air.
      const far = view.y > 300 ? 9000 : 4200;
      this.scene.fog.far += (far - this.scene.fog.far) * 0.05;
      this.scene.fog.near = this.scene.fog.far * 0.33;

      // Sun shadow box follows the focus point.
      this.sun.position.set(view.fx + 500, 1100, view.fz + 300);
      this.sun.target.position.set(view.fx, 0, view.fz);
      this.sun.target.updateMatrixWorld();

      this.syncBroken(G);
      this.syncRoofs(G);
      this.syncUnits(G, view);
      this.syncItems(G, view);
      this.syncDecals(G);
      this.syncFx(G);
      this.syncZone(G);
      this.syncPlane(G);
      this.syncAirdrops(G);
      this.renderer.render(this.scene, cam);
    }

    syncBroken(G) {
      const list = G.broken;
      if (!list || list.length === this.lastBroken) return;
      for (let i = this.lastBroken; i < list.length; i++) {
        const o = list[i];
        if (o.kind === 'wall') { hideInst(this.wallMesh, o.inst); this.wallMesh.instanceMatrix.needsUpdate = true; }
        else if (o.kind === 'crate') { hideInst(this.crateMesh, o.inst); this.crateMesh.instanceMatrix.needsUpdate = true; }
      }
      this.lastBroken = list.length;
    }

    syncRoofs(G) {
      const idx = G.insideIdx;
      if (idx === this.roofHidden) return;
      const map = G.map;
      if (this.roofHidden >= 0) {
        const b = map.buildings[this.roofHidden];
        setInst(this.roofMesh, this.roofHidden, b.x + b.w / 2, H.wall, b.y + b.h / 2, b.w + 10, 10, b.h + 10);
      }
      if (idx >= 0) hideInst(this.roofMesh, idx);
      this.roofMesh.instanceMatrix.needsUpdate = true;
      this.roofHidden = idx;
    }

    syncUnits(G, view) {
      const seen = new Set();
      for (const u of G.units) {
        if (u.phase === 'plane') continue;
        const deadFor = u.alive ? 0 : G.time - u.deathTime;
        if (!u.alive && (deadFor > 45 || u.inDuel)) continue;
        const dx = u.x - view.fx, dz = u.y - view.fz;
        if (dx * dx + dz * dz > 2600 * 2600 && u.phase === 'ground') continue;
        let m = this.unitModels.get(u.id);
        if (!m) { m = makeUnitModel(u); this.unitModels.set(u.id, m); this.world.add(m.root); }
        seen.add(u.id);
        updateUnitModel(m, u, G, view);
      }
      for (const [id, m] of this.unitModels) {
        if (!seen.has(id)) m.root.visible = false;
      }
    }

    syncItems(G, view) {
      const mesh = this.itemMesh;
      let n = 0;
      const t = G.time;
      for (const it of G.items) {
        const dx = it.x - view.fx, dz = it.y - view.fz;
        if (dx * dx + dz * dz > 1600 * 1600) continue;
        if (n >= 2500) break;
        const s = itemShape(it);
        const bob = 3 + Math.sin(t * 3 + it.id) * 1.5;
        setInst(mesh, n, it.x, bob, it.y, s[0], s[1], s[2], t * 1.2 + it.id);
        mesh.setColorAt(n, tmpC.set(itemColor(it)));
        n++;
      }
      mesh.count = n;
      mesh.instanceMatrix.needsUpdate = true;
      if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    }

    syncDecals(G) {
      const mesh = this.decalMesh;
      let n = 0;
      for (const d of G.decals) {
        if (n >= 300) break;
        setInst(mesh, n, d.x, 0.6 + n * 0.002, d.y, d.r, 1, d.r);
        mesh.setColorAt(n, tmpC.set(d.body ? '#6e1018' : '#2a261e'));
        n++;
      }
      mesh.count = n;
      mesh.instanceMatrix.needsUpdate = true;
      if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    }

    syncFx(G) {
      // Tracers
      const pos = this.tracers.geometry.attributes.position, col = this.tracers.geometry.attributes.color;
      let n = 0;
      for (const b of G.bullets) {
        if (n >= this.MAXB) break;
        const k = n * 6;
        const tail = b.cls === 'sr' ? 0.05 : 0.03;
        pos.array[k] = b.x; pos.array[k + 1] = H.chest; pos.array[k + 2] = b.y;
        pos.array[k + 3] = b.x - b.vx * tail; pos.array[k + 4] = H.chest; pos.array[k + 5] = b.y - b.vy * tail;
        const c = b.owner.isPlayer ? [1, 0.92, 0.55] : [1, 0.75, 0.45];
        col.array[k] = c[0]; col.array[k + 1] = c[1]; col.array[k + 2] = c[2];
        col.array[k + 3] = c[0] * 0.3; col.array[k + 4] = c[1] * 0.3; col.array[k + 5] = c[2] * 0.3;
        n++;
      }
      this.tracers.geometry.setDrawRange(0, n * 2);
      pos.needsUpdate = col.needsUpdate = true;

      // Particles
      const fill = (points, filter, heightOf) => {
        const p = points.geometry.attributes.position, c = points.geometry.attributes.color;
        let m = 0;
        for (const pt of G.particles) {
          if (!filter(pt)) continue;
          if (m >= points.userData.max) break;
          const a = Math.max(0, pt.life / pt.max);
          p.array[m * 3] = pt.x; p.array[m * 3 + 1] = heightOf(pt, a); p.array[m * 3 + 2] = pt.y;
          tmpC.copy(colorOf(pt.color || '#ffffff'));
          const f = pt.smoke ? 1 : 0.4 + 0.6 * a;
          c.array[m * 3] = tmpC.r * f; c.array[m * 3 + 1] = tmpC.g * f; c.array[m * 3 + 2] = tmpC.b * f;
          m++;
        }
        points.geometry.setDrawRange(0, m);
        p.needsUpdate = c.needsUpdate = true;
      };
      fill(this.sparks, (pt) => !pt.smoke && !pt.flash, (pt, a) => (pt.h !== undefined ? pt.h : 22) + (pt.vh || 0) * (1 - a));
      fill(this.flashes, (pt) => pt.flash, () => H.chest);
      fill(this.smoke, (pt) => pt.smoke, (pt, a) => 15 + (1 - a) * 160);

      // Grenades
      let gi = 0;
      for (const g of G.grenades) {
        if (gi >= 40) break;
        const speed = Math.hypot(g.vx, g.vy);
        setInst(this.nadeMesh, gi++, g.x, 5 + Math.min(70, speed * 0.12), g.y, 1, 1, 1);
      }
      this.nadeMesh.count = gi;
      this.nadeMesh.instanceMatrix.needsUpdate = true;
    }

    syncZone(G) {
      const z = G.zone;
      const r = Math.max(1, z.r);
      this.zoneMesh.position.set(z.cx, 0, z.cy);
      this.zoneMesh.scale.set(r, 1400, r);
      const showNext = z.state !== 'done' && z.nr > 1;
      this.nextMesh.visible = this.nextRing.visible = showNext;
      if (showNext) {
        this.nextMesh.position.set(z.nx, 0, z.ny);
        this.nextMesh.scale.set(z.nr, 260, z.nr);
        this.nextRing.position.set(z.nx, 2, z.ny);
        this.nextRing.scale.set(z.nr, 1, z.nr);
      }
    }

    syncPlane(G) {
      const pl = G.plane;
      this.planeModel.visible = pl.active;
      if (!pl.active) return;
      this.planeModel.position.set(pl.x, H.plane, pl.y);
      this.planeModel.rotation.y = -pl.angle;
      this.planeModel.userData.prop.rotation.x += 0.8;
    }

    syncAirdrops(G) {
      G.airdrops.forEach((d, i) => {
        let m = this.dropModels.get(i);
        if (!m) { m = makeAirdrop(); this.dropModels.set(i, m); this.world.add(m); }
        m.position.set(d.x, d.landed ? 0 : d.alt * H.chute, d.y);
        m.userData.canopy.visible = !d.landed;
      });
    }

    // World point -> screen pixels (or null if behind the camera).
    project(x, h, y, w, hgt) {
      tmpP.set(x, h, y).project(this.camera);
      if (tmpP.z > 1) return null;
      return { x: (tmpP.x * 0.5 + 0.5) * w, y: (-tmpP.y * 0.5 + 0.5) * hgt };
    }
  }

  // ---------- Models ----------
  function makePlane() {
    const g = new T.Group();
    const mat = new T.MeshLambertMaterial({ color: '#c9cdd2' });
    const dark = new T.MeshLambertMaterial({ color: '#7b8189' });
    const body = new T.Mesh(new T.CylinderGeometry(16, 12, 230, 12), mat);
    body.rotation.z = Math.PI / 2;
    const wings = new T.Mesh(new T.BoxGeometry(46, 4, 300), mat);
    wings.position.x = 10;
    const tail = new T.Mesh(new T.BoxGeometry(26, 4, 90), mat);
    tail.position.x = -100;
    const fin = new T.Mesh(new T.BoxGeometry(30, 40, 4), dark);
    fin.position.set(-100, 22, 0);
    const prop = new T.Mesh(new T.BoxGeometry(2, 50, 6), dark);
    prop.position.x = 118;
    g.add(body, wings, tail, fin, prop);
    g.userData.prop = prop;
    g.traverse((o) => { if (o.isMesh) o.castShadow = true; });
    return g;
  }

  function makeAirdrop() {
    const g = new T.Group();
    const crate = new T.Mesh(new T.BoxGeometry(34, 30, 34), new T.MeshLambertMaterial({ color: '#2f6fb0' }));
    crate.position.y = 15;
    const band = new T.Mesh(new T.BoxGeometry(35, 6, 35), new T.MeshLambertMaterial({ color: '#c9302c' }));
    band.position.y = 15;
    const canopy = new T.Mesh(new T.SphereGeometry(50, 16, 8, 0, Math.PI * 2, 0, Math.PI / 2), new T.MeshLambertMaterial({ color: '#e8e8e8', side: T.DoubleSide }));
    canopy.position.y = 90;
    g.add(crate, band, canopy);
    g.userData.canopy = canopy;
    crate.castShadow = true;
    return g;
  }

  function makeUnitModel(u) {
    const root = new T.Group();
    const body = new T.Group();
    root.add(body);
    const skin = new T.MeshLambertMaterial({ color: '#e0b48a' });
    const clothes = new T.MeshLambertMaterial({ color: u.clothes });
    const pants = new T.MeshLambertMaterial({ color: '#3b3f45' });
    const torsoMat = new T.MeshLambertMaterial({ color: u.clothes });
    const gunMat = new T.MeshLambertMaterial({ color: '#202225' });
    const helmetMat = new T.MeshLambertMaterial({ color: '#666' });

    const leg = (z) => {
      const pivot = new T.Group();
      pivot.position.set(0, 18, z);
      const m = new T.Mesh(new T.BoxGeometry(6, 18, 6), pants);
      m.position.y = -9;
      pivot.add(m);
      body.add(pivot);
      return pivot;
    };
    const legL = leg(-4), legR = leg(4);
    const torso = new T.Mesh(new T.BoxGeometry(10, 15, 16), torsoMat);
    torso.position.y = 25.5;
    const head = new T.Mesh(new T.SphereGeometry(5.5, 10, 8), skin);
    head.position.y = 37.5;
    const helmet = new T.Mesh(new T.SphereGeometry(6.4, 10, 6, 0, Math.PI * 2, 0, Math.PI / 2), helmetMat);
    helmet.position.y = 38;
    const pack = new T.Mesh(new T.BoxGeometry(6, 13, 12), new T.MeshLambertMaterial({ color: '#5a4a2e' }));
    pack.position.set(-8, 26, 0);
    const armR = new T.Mesh(new T.BoxGeometry(14, 4, 4), clothes);
    armR.position.set(6, 28, 6);
    const armL = new T.Mesh(new T.BoxGeometry(16, 4, 4), clothes);
    armL.position.set(9, 28, -3);
    armL.rotation.y = 0.45;
    const gun = new T.Mesh(new T.BoxGeometry(1, 4, 3), gunMat);
    gun.position.set(14, 29, 3);
    body.add(torso, head, helmet, pack, armR, armL, gun);

    // Parachute canopy (only while gliding)
    const canopy = new T.Mesh(new T.SphereGeometry(42, 14, 6, 0, Math.PI * 2, 0, Math.PI / 2.4),
      new T.MeshLambertMaterial({ color: u.isPlayer ? '#f2a900' : '#c84f3a', side: T.DoubleSide }));
    canopy.position.y = 85;
    canopy.scale.y = 0.55;
    root.add(canopy);

    root.traverse((o) => { if (o.isMesh) o.castShadow = true; });
    canopy.castShadow = false;
    return { root, body, legL, legR, torso, torsoMat, helmet, helmetMat, pack, gun, gunMat, armR, armL, canopy, walk: 0, gunCls: null };
  }

  function updateUnitModel(m, u, G, view) {
    const { root } = m;
    root.visible = !(u.isPlayer && view.hidePlayer);
    const y = u.phase === 'chute' ? u.alt * H.chute : 0;
    root.position.set(u.x, y, u.y);
    root.rotation.y = -u.angle;
    m.canopy.visible = u.phase === 'chute' && u.alive;

    if (!u.alive) {
      // Lying on the ground.
      m.body.rotation.z = -Math.PI / 2;
      m.body.position.y = 6;
      m.gun.visible = false;
      m.legL.rotation.z = m.legR.rotation.z = 0;
      return;
    }
    m.body.rotation.z = 0;
    m.body.position.y = 0;

    // Walk animation
    const speed = Math.hypot(u.vx || 0, u.vy || 0);
    if (speed > 20 && u.phase === 'ground') m.walk += speed * 0.0009 * 16;
    const swing = u.phase === 'ground' && speed > 20 ? Math.sin(m.walk) * 0.7 : u.phase === 'chute' ? 0.3 : 0;
    m.legL.rotation.z = swing;
    m.legR.rotation.z = -swing;
    // Sliding crouch
    m.body.scale.y = u.slideT > 0 ? 0.65 : 1;

    // Gear
    m.torsoMat.color.set(u.vest ? VEST[u.vest].color : u.clothes);
    m.helmet.visible = !!u.helmet;
    if (u.helmet) m.helmetMat.color.set(HELMET[u.helmet].color);
    m.pack.visible = !!u.pack;
    m.torsoMat.emissive.setRGB(u.hitFlash > 0 ? 0.6 : 0, u.hitFlash > 0 ? 0.6 : 0, u.hitFlash > 0 ? 0.6 : 0);

    const s = u.slots[u.active];
    const cls = s ? WEAPONS[s.type].cls : null;
    if (cls !== m.gunCls) {
      m.gunCls = cls;
      m.gun.visible = !!cls;
      if (cls) {
        const len = GUN_LEN[cls];
        m.gun.scale.x = len;
        m.gun.position.x = 10 + len / 2;
        m.gunMat.color.set(WEAPONS[s.type].tier >= 6 ? '#b8902e' : '#202225');
      }
    }
    // Punch: extend the right arm.
    m.armR.position.x = !s && u.punchT > 0.25 ? 12 : 6;
  }

  // ---------- Item look ----------
  function itemShape(it) {
    switch (it.kind) {
      case 'weapon': return [GUN_LEN[WEAPONS[it.type].cls] + 6, 5, 6];
      case 'ammo': return [10, 8, 10];
      case 'vest': return [14, 16, 7];
      case 'helmet': return [11, 9, 11];
      case 'pack': return [11, 15, 8];
      case 'med': return [10, 10, 10];
      case 'grenade': return [7, 8, 7];
    }
    return [8, 8, 8];
  }
  function itemColor(it) {
    switch (it.kind) {
      case 'weapon': return WEAPONS[it.type].tier >= 6 ? '#e2b13c' : '#3a3d42';
      case 'ammo': return AMMO[it.type].color;
      case 'vest': return VEST[it.lvl].color;
      case 'helmet': return HELMET[it.lvl].color;
      case 'pack': return it.lvl === 3 ? '#a07cd0' : it.lvl === 2 ? '#5a8fd0' : '#7a6a48';
      case 'med': return ZZ.MEDS[it.type].color;
      case 'grenade': return '#4c5a34';
    }
    return '#ffffff';
  }

  ZZ.Renderer3D = Renderer3D;
})();
