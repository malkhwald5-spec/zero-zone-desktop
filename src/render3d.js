'use strict';

// Three.js renderer. The simulation stays 2D (x, y on the ground); here it is
// drawn in 3D with sim x -> world x, sim y -> world z, and heights on world y.
(() => {
  const ZZ = window.ZZ;
  const T = window.THREE;
  const M = ZZ.Map;
  const { WEAPONS, AMMO, VEST, HELMET } = ZZ;

  const H = {
    wall: 110, fence: 140, crate: 44, container: 64,
    unit: 40, chest: 28, plane: 1120, metersToUnits: 1.4, bridge: 7,
  };
  ZZ.HEIGHTS = H;

  const GUN_LEN = { pistol: 9, smg: 15, shotgun: 21, ar: 23, dmr: 27, sr: 32, lmg: 27 };
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

  // Ground level for things standing at (x, y): bridges, land, or a wading depth in water.
  function groundY(map, x, y) {
    const h = M.heightAt(map, x, y);
    if (h < 1) {
      for (const b of map.bridges) if (M.distToSegment(x, y, b.x1, b.y1, b.x2, b.y2) < b.w / 2 + 4) return H.bridge;
    }
    return Math.max(h, -14);
  }
  ZZ.groundY = groundY;

  // ---------- Procedural textures ----------
  function canvasTex(w, h, draw, repeat) {
    const c = document.createElement('canvas');
    c.width = w; c.height = h;
    draw(c.getContext('2d'), w, h);
    const t = new T.CanvasTexture(c);
    t.colorSpace = T.SRGBColorSpace;
    if (repeat) { t.wrapS = t.wrapT = T.RepeatWrapping; }
    return t;
  }
  const wallTexture = () => canvasTex(128, 256, (g, w, h) => {
    g.fillStyle = '#e8e2d6'; g.fillRect(0, 0, w, h);
    for (let i = 0; i < 900; i++) { g.fillStyle = `rgba(0,0,0,${Math.random() * 0.05})`; g.fillRect(Math.random() * w, Math.random() * h, 2, 2); }
    // Window (upper part); the bottom ~20% is below ground.
    g.fillStyle = '#5b5f63'; g.fillRect(34, 70, 60, 70);
    g.fillStyle = '#29414f'; g.fillRect(40, 76, 48, 58);
    g.fillStyle = 'rgba(160,200,230,0.35)'; g.fillRect(40, 76, 20, 58);
    g.fillStyle = '#5b5f63'; g.fillRect(62, 76, 4, 58); g.fillRect(40, 103, 48, 4);
    g.fillStyle = 'rgba(0,0,0,0.25)'; g.fillRect(0, 200, w, 6);
  });
  const roofTexture = () => canvasTex(128, 128, (g, w, h) => {
    g.fillStyle = '#ffffff'; g.fillRect(0, 0, w, h);
    for (let y = 0; y < h; y += 12) { g.fillStyle = 'rgba(0,0,0,0.18)'; g.fillRect(0, y, w, 3); }
    for (let x = 0; x < w; x += 16) { g.fillStyle = 'rgba(0,0,0,0.08)'; g.fillRect(x, 0, 2, h); }
  }, true);
  const cloudTexture = () => canvasTex(256, 128, (g, w, h) => {
    for (let i = 0; i < 26; i++) {
      const x = 40 + Math.random() * (w - 80), y = 50 + Math.random() * 40, r = 18 + Math.random() * 34;
      const grd = g.createRadialGradient(x, y, 0, x, y, r);
      grd.addColorStop(0, 'rgba(255,255,255,0.9)');
      grd.addColorStop(1, 'rgba(255,255,255,0)');
      g.fillStyle = grd;
      g.beginPath(); g.arc(x, y, r, 0, Math.PI * 2); g.fill();
    }
  });

  // Gable roof: triangular prism along X, base at y=0, ridge at y=1.
  function gableGeometry() {
    const p = [
      // two slopes
      -0.5, 0, -0.5, 0.5, 0, -0.5, 0.5, 1, 0, -0.5, 0, -0.5, 0.5, 1, 0, -0.5, 1, 0,
      -0.5, 0, 0.5, -0.5, 1, 0, 0.5, 1, 0, -0.5, 0, 0.5, 0.5, 1, 0, 0.5, 0, 0.5,
      // gable ends
      -0.5, 0, -0.5, -0.5, 1, 0, -0.5, 0, 0.5,
      0.5, 0, -0.5, 0.5, 0, 0.5, 0.5, 1, 0,
    ];
    const uv = [0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1, 0, 0, 0, 1, 1, 1, 0, 0, 1, 1, 1, 0, 0, 0, 0.5, 1, 1, 0, 0, 0, 1, 0, 0.5, 1];
    const g = new T.BufferGeometry();
    g.setAttribute('position', new T.Float32BufferAttribute(p, 3));
    g.setAttribute('uv', new T.Float32BufferAttribute(uv, 2));
    g.computeVertexNormals();
    return g;
  }

  class Renderer3D {
    constructor(canvas) {
      this.canvas = canvas;
      this.renderer = new T.WebGLRenderer({ canvas, antialias: true, powerPreference: 'high-performance' });
      this.renderer.toneMapping = T.ACESFilmicToneMapping;
      this.renderer.toneMappingExposure = 1.05;
      this.renderer.shadowMap.enabled = true;
      this.renderer.shadowMap.type = T.PCFSoftShadowMap;

      this.scene = new T.Scene();
      const horizon = new T.Color('#c7dcea');
      this.scene.background = horizon;
      this.scene.fog = new T.Fog(horizon, 1500, 4600);

      this.camera = new T.PerspectiveCamera(70, 1, 2, 16000);
      this.scene.add(new T.HemisphereLight(0xdcecff, 0x5a6b3a, 1.1));
      const sun = new T.DirectionalLight(0xfff0d6, 2.2);
      sun.castShadow = true;
      sun.shadow.mapSize.set(2048, 2048);
      const sc = sun.shadow.camera;
      sc.left = -700; sc.right = 700; sc.top = 700; sc.bottom = -700; sc.near = 10; sc.far = 3500;
      sun.shadow.bias = -0.0006;
      sun.shadow.normalBias = 0.6;
      this.scene.add(sun, sun.target);
      this.sun = sun;
      this.sunDir = new T.Vector3(0.45, 0.8, 0.3).normalize();

      this.addSky();
      this.world = null;
      this.unitModels = new Map();
      this.dropModels = new Map();
      this.quality = 'high';
      this.setQuality(this.quality);
    }

    setQuality(q) {
      this.quality = q;
      this.renderer.setPixelRatio(q === 'high' ? Math.min(2, window.devicePixelRatio || 1) : 1);
      this.renderer.shadowMap.enabled = q !== 'low';
      this.sun.shadow.mapSize.set(q === 'high' ? 2048 : 1024, q === 'high' ? 2048 : 1024);
      if (this.sun.shadow.map) { this.sun.shadow.map.dispose(); this.sun.shadow.map = null; }
      if (this.grass) this.grass.visible = q !== 'low';
      this.scene.traverse((o) => { if (o.material) o.material.needsUpdate = true; });
    }

    addSky() {
      // Gradient dome
      const geo = new T.SphereGeometry(12000, 32, 16);
      const cols = [];
      const top = new T.Color('#4f8fd4'), hor = new T.Color('#c7dcea');
      const pos = geo.attributes.position;
      for (let i = 0; i < pos.count; i++) {
        const k = Math.max(0, pos.getY(i) / 12000);
        const c = hor.clone().lerp(top, Math.pow(k, 0.6));
        cols.push(c.r, c.g, c.b);
      }
      geo.setAttribute('color', new T.Float32BufferAttribute(cols, 3));
      this.sky = new T.Mesh(geo, new T.MeshBasicMaterial({ vertexColors: true, side: T.BackSide, fog: false, depthWrite: false }));
      this.sky.renderOrder = -10;
      this.scene.add(this.sky);
      const sunDisk = new T.Mesh(new T.SphereGeometry(260, 16, 8), new T.MeshBasicMaterial({ color: '#fff6d8', fog: false }));
      sunDisk.position.copy(this.sunDir).multiplyScalar(11000);
      this.sky.add(sunDisk);
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
        this.world.traverse((o) => {
          if (o.geometry) o.geometry.dispose();
          if (o.material) { const ms = Array.isArray(o.material) ? o.material : [o.material]; ms.forEach((m) => { if (m.map) m.map.dispose(); m.dispose(); }); }
        });
      }
      this.unitModels.clear();
      this.dropModels.clear();
      const map = G.map, S = map.size;
      this.map = map;
      const W = new T.Group();
      this.world = W;
      this.scene.add(W);
      const lambert = (color, extra = {}) => new T.MeshLambertMaterial({ color, ...extra });
      const hAt = (x, y) => M.heightAt(map, x, y);

      // Terrain mesh displaced by the heightmap, textured with the painted ground.
      const segs = 220;
      const tgeo = new T.PlaneGeometry(S, S, segs, segs);
      tgeo.rotateX(-Math.PI / 2);
      const tp = tgeo.attributes.position;
      for (let i = 0; i < tp.count; i++) {
        const x = tp.getX(i) + S / 2, z = tp.getZ(i) + S / 2;
        tp.setY(i, hAt(x, z));
      }
      tgeo.computeVertexNormals();
      const tex = new T.CanvasTexture(map.ground);
      tex.colorSpace = T.SRGBColorSpace;
      tex.anisotropy = this.renderer.capabilities.getMaxAnisotropy();
      const terrain = new T.Mesh(tgeo, new T.MeshLambertMaterial({ map: tex }));
      terrain.position.set(S / 2, 0, S / 2);
      terrain.receiveShadow = true;
      W.add(terrain);
      // Sea floor beyond the map and the water surface.
      const floor = new T.Mesh(new T.PlaneGeometry(60000, 60000), lambert('#1d4d63'));
      floor.rotation.x = -Math.PI / 2;
      floor.position.set(S / 2, -82, S / 2);
      W.add(floor);
      const water = new T.Mesh(new T.PlaneGeometry(60000, 60000), new T.MeshPhongMaterial({
        color: '#2b6f8f', specular: '#9fc4d8', shininess: 90, transparent: true, opacity: 0.86,
      }));
      water.rotation.x = -Math.PI / 2;
      water.position.set(S / 2, ZZ.WATER_LEVEL, S / 2);
      water.receiveShadow = true;
      W.add(water);

      const box = new T.BoxGeometry(1, 1, 1);
      box.translate(0, 0.5, 0);

      // Walls (instanced; explosions hide single segments). Fences use a plain material.
      const walls = map.obs.filter((o) => o.kind === 'wall' && !o.fence);
      const fences = map.obs.filter((o) => o.kind === 'wall' && o.fence);
      const wallPalette = ['#f1e6d0', '#e2d2b4', '#efe9de', '#d9cbb8', '#e8d9c4'];
      const wallMesh = new T.InstancedMesh(box, new T.MeshLambertMaterial({ map: wallTexture() }), Math.max(1, walls.length));
      walls.forEach((o, i) => {
        const b = map.buildings[o.bld];
        setInst(wallMesh, i, o.x + o.w / 2, b.floor - 30, o.y + o.h / 2, o.w, H.wall + 30, o.h);
        wallMesh.setColorAt(i, tmpC.set(b.military ? '#a7aa9f' : wallPalette[o.bld % wallPalette.length]));
        o.inst = i; o.mesh = 'wall';
      });
      wallMesh.castShadow = wallMesh.receiveShadow = true;
      W.add(wallMesh);
      this.wallMesh = wallMesh;
      const fenceMesh = new T.InstancedMesh(box, lambert('#5d6266'), Math.max(1, fences.length));
      fences.forEach((o, i) => setInst(fenceMesh, i, o.x + o.w / 2, 0, o.y + o.h / 2, o.w, H.fence, o.h));
      fenceMesh.castShadow = true;
      W.add(fenceMesh);

      // Gable roofs (hidden for the building the player is in) and ceilings.
      const roofMesh = new T.InstancedMesh(gableGeometry(), new T.MeshLambertMaterial({ map: roofTexture(), side: T.DoubleSide }), map.buildings.length);
      const slabMesh = new T.InstancedMesh(box, lambert('#8a8478'), map.buildings.length);
      this.roofPose = [];
      map.buildings.forEach((b, i) => {
        const along = b.w >= b.h;
        const pose = [b.x + b.w / 2, b.floor + H.wall + 4, b.y + b.h / 2, (along ? b.w : b.h) + 16, b.military ? 10 : 34, (along ? b.h : b.w) + 18, along ? 0 : Math.PI / 2];
        this.roofPose.push(pose);
        setInst(roofMesh, i, ...pose);
        roofMesh.setColorAt(i, tmpC.set(b.roof));
        setInst(slabMesh, i, b.x + b.w / 2, b.floor + H.wall, b.y + b.h / 2, b.w + 4, 5, b.h + 4);
      });
      roofMesh.castShadow = slabMesh.castShadow = true;
      W.add(roofMesh, slabMesh);
      this.roofMesh = roofMesh;
      this.slabMesh = slabMesh;
      this.roofHidden = -1;

      // Crates and containers.
      const crates = map.obs.filter((o) => o.kind === 'crate');
      const crateMesh = new T.InstancedMesh(box, lambert('#8a6a3e'), Math.max(1, crates.length));
      crates.forEach((o, i) => { setInst(crateMesh, i, o.x + o.w / 2, hAt(o.x + o.w / 2, o.y + o.h / 2) - 2, o.y + o.h / 2, o.w, H.crate, o.h); o.inst = i; o.mesh = 'crate'; });
      crateMesh.castShadow = crateMesh.receiveShadow = true;
      W.add(crateMesh);
      this.crateMesh = crateMesh;
      const conts = map.obs.filter((o) => o.kind === 'container');
      const contMesh = new T.InstancedMesh(box, lambert('#ffffff'), Math.max(1, conts.length));
      const contCols = ['#8a3b2c', '#2f5d8a', '#3f6b3a', '#9a7a2c'];
      conts.forEach((o, i) => {
        setInst(contMesh, i, o.x + o.w / 2, hAt(o.x + o.w / 2, o.y + o.h / 2) - 2, o.y + o.h / 2, o.w, H.container, o.h);
        contMesh.setColorAt(i, tmpC.set(contCols[i % contCols.length]));
      });
      contMesh.castShadow = contMesh.receiveShadow = true;
      W.add(contMesh);

      // Rocks
      const rocks = map.obs.filter((o) => o.kind === 'rock');
      const rockMesh = new T.InstancedMesh(new T.DodecahedronGeometry(1, 1), lambert('#ffffff', { flatShading: true }), Math.max(1, rocks.length));
      rocks.forEach((o, i) => {
        setInst(rockMesh, i, o.x, hAt(o.x, o.y) + o.r * 0.2, o.y, o.r * 1.1, o.r * 0.85, o.r * 1.05, o.shade * 6);
        rockMesh.setColorAt(i, tmpC.set(o.shade < 0.5 ? '#8d8f88' : '#7a7d76'));
      });
      rockMesh.castShadow = rockMesh.receiveShadow = true;
      W.add(rockMesh);

      // Trees: pines (stacked cones) and broadleaf (two leafy blobs).
      const trunkGeo = new T.CylinderGeometry(0.65, 1, 1, 6);
      trunkGeo.translate(0, 0.5, 0);
      const pines = map.trees.filter((t) => t.pine), leafy = map.trees.filter((t) => !t.pine);
      const trunkMesh = new T.InstancedMesh(trunkGeo, lambert('#5a3f2a'), map.trees.length);
      const coneGeo = new T.ConeGeometry(1, 1, 7);
      coneGeo.translate(0, 0.5, 0);
      const pineLow = new T.InstancedMesh(coneGeo, lambert('#ffffff', { flatShading: true }), Math.max(1, pines.length));
      const pineHigh = new T.InstancedMesh(coneGeo, lambert('#ffffff', { flatShading: true }), Math.max(1, pines.length));
      const blobGeo = new T.IcosahedronGeometry(1, 1);
      const leafA = new T.InstancedMesh(blobGeo, lambert('#ffffff', { flatShading: true }), Math.max(1, leafy.length));
      const leafB = new T.InstancedMesh(blobGeo, lambert('#ffffff', { flatShading: true }), Math.max(1, leafy.length));
      const pineCols = ['#2d4f2a', '#335a2e', '#284526'], leafCols = ['#4a7432', '#3f6a2e', '#577d38', '#46702f'];
      let ti = 0;
      pines.forEach((t, i) => {
        const g0 = hAt(t.x, t.y), th = 50 + t.canopy * 1.2;
        setInst(trunkMesh, ti++, t.x, g0, t.y, t.r * 0.9, th, t.r * 0.9);
        setInst(pineLow, i, t.x, g0 + th * 0.35, t.y, t.canopy * 1.05, th * 0.8, t.canopy * 1.05, t.shade * 6);
        setInst(pineHigh, i, t.x, g0 + th * 0.8, t.y, t.canopy * 0.7, th * 0.65, t.canopy * 0.7, t.shade * 6);
        tmpC.set(pineCols[Math.floor(t.shade * pineCols.length)]);
        pineLow.setColorAt(i, tmpC); pineHigh.setColorAt(i, tmpC);
      });
      leafy.forEach((t, i) => {
        const g0 = hAt(t.x, t.y), th = 46 + t.canopy * 0.7;
        setInst(trunkMesh, ti++, t.x, g0, t.y, t.r, th, t.r);
        setInst(leafA, i, t.x, g0 + th + t.canopy * 0.35, t.y, t.canopy * 1.15, t.canopy * 0.95, t.canopy * 1.1, t.shade * 5);
        setInst(leafB, i, t.x + t.canopy * 0.3, g0 + th + t.canopy * 0.95, t.y - t.canopy * 0.2, t.canopy * 0.8, t.canopy * 0.7, t.canopy * 0.8, t.shade * 3);
        tmpC.set(leafCols[Math.floor(t.shade * leafCols.length)]);
        leafA.setColorAt(i, tmpC); leafB.setColorAt(i, tmpC.multiplyScalar(1.12));
      });
      for (const m of [trunkMesh, pineLow, pineHigh, leafA, leafB]) { m.castShadow = true; m.receiveShadow = true; W.add(m); }

      // Bridges: deck + rails.
      const deckMesh = new T.InstancedMesh(box, lambert('#7b746a'), Math.max(1, map.bridges.length * 3));
      map.bridges.forEach((b, i) => {
        const len = Math.hypot(b.x2 - b.x1, b.y2 - b.y1), ang = -Math.atan2(b.y2 - b.y1, b.x2 - b.x1);
        const cx = (b.x1 + b.x2) / 2, cz = (b.y1 + b.y2) / 2;
        setInst(deckMesh, i * 3, cx, H.bridge - 8, cz, len, 8, b.w, ang);
        const nx = -Math.sin(-ang) * (b.w / 2), nz = Math.cos(-ang) * (b.w / 2);
        setInst(deckMesh, i * 3 + 1, cx + nx, H.bridge, cz + nz, len, 10, 3, ang);
        setInst(deckMesh, i * 3 + 2, cx - nx, H.bridge, cz - nz, len, 10, 3, ang);
      });
      deckMesh.castShadow = deckMesh.receiveShadow = true;
      W.add(deckMesh);

      // Grass tufts around the player (re-scattered as the player moves).
      const blade = new T.ConeGeometry(0.9, 5.5, 3);
      blade.translate(0, 2.7, 0);
      this.grass = new T.InstancedMesh(blade, lambert('#5d8a3a'), 6000);
      this.grass.count = 0;
      this.grass.visible = this.quality !== 'low';
      W.add(this.grass);
      this.grassAt = null;

      // Clouds
      const ctex = cloudTexture();
      for (let i = 0; i < 70; i++) {
        const s = new T.Sprite(new T.SpriteMaterial({ map: ctex, transparent: true, opacity: 0.75 + Math.random() * 0.2, depthWrite: false, fog: false }));
        s.position.set(Math.random() * S * 1.6 - S * 0.3, 1700 + Math.random() * 900, Math.random() * S * 1.6 - S * 0.3);
        const sz = 900 + Math.random() * 1400;
        s.scale.set(sz, sz * 0.45, 1);
        W.add(s);
      }

      // Items on the ground
      this.itemMesh = new T.InstancedMesh(box, lambert('#ffffff', { emissive: '#1a1a1a' }), 2500);
      this.itemMesh.count = 0;
      W.add(this.itemMesh);

      // Decals (blood, scorch marks)
      const disc = new T.CircleGeometry(1, 16);
      disc.rotateX(-Math.PI / 2);
      this.decalMesh = new T.InstancedMesh(disc, new T.MeshBasicMaterial({ color: '#ffffff', transparent: true, opacity: 0.75, depthWrite: false }), 300);
      this.decalMesh.count = 0;
      W.add(this.decalMesh);

      // Grenades
      this.nadeMesh = new T.InstancedMesh(new T.SphereGeometry(4, 8, 6), lambert('#4c5a34'), 40);
      this.nadeMesh.count = 0;
      W.add(this.nadeMesh);

      // Bullet tracers
      const MAXB = 1200;
      const bGeo = new T.BufferGeometry();
      bGeo.setAttribute('position', new T.BufferAttribute(new Float32Array(MAXB * 6), 3));
      bGeo.setAttribute('color', new T.BufferAttribute(new Float32Array(MAXB * 6), 3));
      this.tracers = new T.LineSegments(bGeo, new T.LineBasicMaterial({ vertexColors: true, transparent: true, opacity: 0.9, toneMapped: false }));
      this.tracers.frustumCulled = false;
      this.MAXB = MAXB;
      W.add(this.tracers);

      // Particles (sparks/blood), muzzle flashes, smoke
      const mkPoints = (max, size, opacity, glow) => {
        const g = new T.BufferGeometry();
        g.setAttribute('position', new T.BufferAttribute(new Float32Array(max * 3), 3));
        g.setAttribute('color', new T.BufferAttribute(new Float32Array(max * 3), 3));
        const p = new T.Points(g, new T.PointsMaterial({ size, vertexColors: true, transparent: true, opacity, depthWrite: false, sizeAttenuation: true, toneMapped: !glow }));
        p.frustumCulled = false;
        p.userData.max = max;
        W.add(p);
        return p;
      };
      this.sparks = mkPoints(3000, 5, 0.95);
      this.flashes = mkPoints(200, 26, 0.9, true);
      this.smoke = mkPoints(800, 44, 0.45);

      // Zone walls
      const cyl = new T.CylinderGeometry(1, 1, 1, 160, 1, true);
      cyl.translate(0, 0.5, 0);
      this.zoneMesh = new T.Mesh(cyl, new T.MeshBasicMaterial({ color: '#3d7bff', transparent: true, opacity: 0.3, side: T.DoubleSide, depthWrite: false, fog: false }));
      this.zoneMesh.renderOrder = 10;
      this.nextMesh = new T.Mesh(cyl, new T.MeshBasicMaterial({ color: '#ffffff', transparent: true, opacity: 0.08, side: T.DoubleSide, depthWrite: false, fog: false }));
      this.nextMesh.renderOrder = 9;
      W.add(this.zoneMesh, this.nextMesh);

      // Plane
      this.planeModel = makePlane();
      W.add(this.planeModel);

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
      const far = view.y > 300 ? 11000 : 4600;
      this.scene.fog.far += (far - this.scene.fog.far) * 0.05;
      this.scene.fog.near = this.scene.fog.far * 0.3;
      this.sky.position.set(view.x, 0, view.z);

      // Sun shadow box follows the focus point.
      const fy = M.heightAt(G.map, view.fx, view.fz);
      this.sun.position.set(view.fx + this.sunDir.x * 1500, fy + this.sunDir.y * 1500, view.fz + this.sunDir.z * 1500);
      this.sun.target.position.set(view.fx, fy, view.fz);
      this.sun.target.updateMatrixWorld();

      this.syncBroken(G);
      this.syncRoofs(G);
      this.syncGrass(G, view);
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
        if (o.mesh === 'wall') { hideInst(this.wallMesh, o.inst); this.wallMesh.instanceMatrix.needsUpdate = true; }
        else if (o.mesh === 'crate') { hideInst(this.crateMesh, o.inst); this.crateMesh.instanceMatrix.needsUpdate = true; }
      }
      this.lastBroken = list.length;
    }

    syncRoofs(G) {
      const idx = G.insideIdx;
      if (idx === this.roofHidden) return;
      const map = G.map;
      if (this.roofHidden >= 0) {
        const i = this.roofHidden, b = map.buildings[i];
        setInst(this.roofMesh, i, ...this.roofPose[i]);
        setInst(this.slabMesh, i, b.x + b.w / 2, b.floor + H.wall, b.y + b.h / 2, b.w + 4, 5, b.h + 4);
      }
      if (idx >= 0) { hideInst(this.roofMesh, idx); hideInst(this.slabMesh, idx); }
      this.roofMesh.instanceMatrix.needsUpdate = this.slabMesh.instanceMatrix.needsUpdate = true;
      this.roofHidden = idx;
    }

    // Deterministic grass tufts on a grid near the focus point.
    syncGrass(G, view) {
      if (!this.grass.visible) return;
      const cx = Math.round(view.fx / 120) * 120, cz = Math.round(view.fz / 120) * 120;
      if (this.grassAt && this.grassAt.x === cx && this.grassAt.z === cz) return;
      this.grassAt = { x: cx, z: cz };
      const map = G.map, step = 11, R = 460;
      let n = 0;
      for (let gz = cz - R; gz <= cz + R && n < 6000; gz += step) {
        for (let gx = cx - R; gx <= cx + R && n < 6000; gx += step) {
          const hsh = Math.sin(gx * 12.9898 + gz * 78.233) * 43758.5453;
          const r1 = hsh - Math.floor(hsh), r2 = (r1 * 7.13) % 1;
          if (r1 > 0.45) continue;
          const x = gx + (r2 - 0.5) * step, z = gz + (r1 * 2 - 0.5) * step;
          if ((x - cx) ** 2 + (z - cz) ** 2 > R * R) continue;
          const h = M.heightAt(map, x, z);
          if (h < 8 || M.buildingAt(map, x, z) >= 0) continue;
          setInst(this.grass, n++, x, h - 1, z, 1 + r2, 0.7 + r1 * 1.4, 1 + r2, r1 * 6);
        }
      }
      this.grass.count = n;
      this.grass.instanceMatrix.needsUpdate = true;
    }

    syncUnits(G, view) {
      const seen = new Set();
      for (const u of G.units) {
        if (u.phase === 'plane') continue;
        const deadFor = u.alive ? 0 : G.time - u.deathTime;
        if (!u.alive && (deadFor > 45 || u.inDuel)) continue;
        const dx = u.x - view.fx, dz = u.y - view.fz;
        const d2 = dx * dx + dz * dz;
        if (d2 > 3200 * 3200) continue;
        let m = this.unitModels.get(u.id);
        if (!m) { m = makeSoldier({ clothes: u.clothes, chute: u.isPlayer ? '#f2a900' : '#c84f3a', skin: u.skin }); this.unitModels.set(u.id, m); this.world.add(m.root); }
        seen.add(u.id);
        updateSoldier(m, u, G, view, d2);
      }
      for (const [id, m] of this.unitModels) if (!seen.has(id)) m.root.visible = false;
    }

    syncItems(G, view) {
      const mesh = this.itemMesh;
      let n = 0;
      const t = G.time;
      for (const it of G.items) {
        const dx = it.x - view.fx, dz = it.y - view.fz;
        if (dx * dx + dz * dz > 1600 * 1600) continue;
        if (n >= 2500) break;
        if (it.gy === undefined) it.gy = groundY(G.map, it.x, it.y);
        const s = itemShape(it);
        const bob = 3 + Math.sin(t * 3 + it.id) * 1.5;
        setInst(mesh, n, it.x, it.gy + bob, it.y, s[0], s[1], s[2], t * 1.2 + it.id);
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
        if (d.gy === undefined) d.gy = groundY(G.map, d.x, d.y);
        setInst(mesh, n, d.x, d.gy + 0.8 + n * 0.002, d.y, d.r, 1, d.r);
        mesh.setColorAt(n, tmpC.set(d.body ? '#6e1018' : '#2a261e'));
        n++;
      }
      mesh.count = n;
      mesh.instanceMatrix.needsUpdate = true;
      if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    }

    syncFx(G) {
      const map = G.map;
      // Tracers
      const pos = this.tracers.geometry.attributes.position, col = this.tracers.geometry.attributes.color;
      let n = 0;
      for (const b of G.bullets) {
        if (n >= this.MAXB) break;
        const k = n * 6;
        const tail = b.cls === 'sr' ? 0.05 : 0.03;
        const by = b.y0 + b.slope * b.dist, tailLen = Math.hypot(b.vx, b.vy) * tail;
        pos.array[k] = b.x; pos.array[k + 1] = by; pos.array[k + 2] = b.y;
        pos.array[k + 3] = b.x - b.vx * tail; pos.array[k + 4] = by - b.slope * tailLen; pos.array[k + 5] = b.y - b.vy * tail;
        const c = b.owner.isPlayer ? [1.4, 1.25, 0.7] : [1.4, 1.0, 0.6];
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
          if (pt.gy === undefined) pt.gy = groundY(map, pt.x, pt.y);
          const a = Math.max(0, pt.life / pt.max);
          p.array[m * 3] = pt.x; p.array[m * 3 + 1] = pt.gy + heightOf(pt, a); p.array[m * 3 + 2] = pt.y;
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
        setInst(this.nadeMesh, gi++, g.x, groundY(map, g.x, g.y) + 5 + Math.min(70, speed * 0.12), g.y, 1, 1, 1);
      }
      this.nadeMesh.count = gi;
      this.nadeMesh.instanceMatrix.needsUpdate = true;
    }

    syncZone(G) {
      const z = G.zone;
      const r = Math.max(1, z.r);
      this.zoneMesh.position.set(z.cx, -90, z.cy);
      this.zoneMesh.scale.set(r, 1900, r);
      const showNext = z.state !== 'done' && z.nr > 1;
      this.nextMesh.visible = showNext;
      if (showNext) {
        this.nextMesh.position.set(z.nx, -90, z.ny);
        this.nextMesh.scale.set(z.nr, 500, z.nr);
      }
    }

    syncPlane(G) {
      const pl = G.plane;
      this.planeModel.visible = pl.active;
      if (!pl.active) return;
      this.planeModel.position.set(pl.x, H.plane, pl.y);
      this.planeModel.rotation.y = -pl.angle;
      this.planeModel.userData.props.forEach((p) => { p.rotation.x += 0.9; });
    }

    syncAirdrops(G) {
      G.airdrops.forEach((d, i) => {
        let m = this.dropModels.get(i);
        if (!m) { m = makeAirdrop(); this.dropModels.set(i, m); this.world.add(m); }
        const gy = groundY(G.map, d.x, d.y);
        m.position.set(d.x, d.landed ? gy : gy + d.alt * 1300, d.y);
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
    const dark = new T.MeshLambertMaterial({ color: '#5d636b' });
    const glass = new T.MeshLambertMaterial({ color: '#223344' });
    const body = new T.Mesh(new T.CylinderGeometry(18, 13, 260, 14), mat);
    body.rotation.z = Math.PI / 2;
    const nose = new T.Mesh(new T.SphereGeometry(18, 12, 8, 0, Math.PI * 2, 0, Math.PI / 2), mat);
    nose.rotation.z = -Math.PI / 2;
    nose.position.x = 130;
    const cockpit = new T.Mesh(new T.BoxGeometry(24, 8, 22), glass);
    cockpit.position.set(118, 12, 0);
    const wings = new T.Mesh(new T.BoxGeometry(52, 5, 340), mat);
    wings.position.x = 15;
    const tail = new T.Mesh(new T.BoxGeometry(30, 4, 110), mat);
    tail.position.x = -112;
    const fin = new T.Mesh(new T.BoxGeometry(36, 50, 4), mat);
    fin.position.set(-110, 28, 0);
    g.add(body, nose, cockpit, wings, tail, fin);
    const props = [];
    for (const z of [-90, -45, 45, 90]) {
      const eng = new T.Mesh(new T.CylinderGeometry(7, 8, 34, 10), dark);
      eng.rotation.z = Math.PI / 2;
      eng.position.set(30, -4, z);
      const prop = new T.Mesh(new T.BoxGeometry(2, 34, 4), dark);
      prop.position.set(49, -4, z);
      g.add(eng, prop);
      props.push(prop);
    }
    g.userData.props = props;
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

  // Shared geometries for soldiers.
  const SG = {};
  function soldierGeos() {
    if (SG.ready) return SG;
    SG.thigh = new T.CapsuleGeometry(2.7, 6, 3, 8); SG.thigh.translate(0, -4.5, 0);
    SG.shin = new T.CapsuleGeometry(2.3, 6, 3, 8); SG.shin.translate(0, -4.5, 0);
    SG.boot = new T.BoxGeometry(6.5, 2.6, 4); SG.boot.translate(1.2, -9.4, 0);
    SG.hips = new T.BoxGeometry(6.5, 5, 11);
    SG.torso = new T.CapsuleGeometry(4.6, 6, 4, 10);
    SG.vest = new T.BoxGeometry(9.8, 10, 12.6);
    SG.head = new T.SphereGeometry(4.1, 14, 10);
    SG.helmet = new T.SphereGeometry(4.7, 14, 8, 0, Math.PI * 2, 0, Math.PI / 1.9);
    SG.upper = new T.CapsuleGeometry(1.75, 5, 3, 8); SG.upper.translate(0, -3.8, 0);
    SG.fore = new T.CapsuleGeometry(1.55, 5, 3, 8); SG.fore.translate(0, -3.8, 0);
    SG.hand = new T.SphereGeometry(1.7, 8, 6);
    SG.pack = new T.BoxGeometry(5.5, 12, 10);
    SG.receiver = new T.BoxGeometry(1, 3.4, 2.4);
    SG.barrel = new T.CylinderGeometry(0.6, 0.6, 1, 6); SG.barrel.rotateZ(Math.PI / 2);
    SG.mag = new T.BoxGeometry(2, 4.5, 1.8);
    SG.stock = new T.BoxGeometry(5, 3, 2);
    SG.canopy = new T.SphereGeometry(42, 16, 6, 0, Math.PI * 2, 0, Math.PI / 2.4);
    SG.proxy = new T.CapsuleGeometry(5, 26, 3, 6); SG.proxy.translate(0, 18, 0);
    SG.ready = true;
    return SG;
  }

  // A low-poly soldier facing +x. Exposed so the lobby can show the same character.
  function makeSoldier(opts = {}) {
    const g = soldierGeos();
    const L = (c) => new T.MeshLambertMaterial({ color: c });
    const mats = {
      skin: L(opts.skin || '#d9a77f'), shirt: L(opts.clothes || '#4a5d6b'), pants: L(opts.pants || '#33373d'),
      boots: L('#1d1d1f'), vest: L('#4e6fa8'), helmet: L('#5a7a4a'), pack: L('#5a4a2e'), gun: L('#1f2124'), gunAccent: L('#3a3d42'),
    };
    const root = new T.Group();
    const body = new T.Group(); // feet at origin
    root.add(body);
    const hip = new T.Group(); hip.position.y = 19; body.add(hip);
    const mk = (geo, mat, parent, x = 0, y = 0, z = 0) => { const m = new T.Mesh(geo, mat); m.position.set(x, y, z); parent.add(m); return m; };
    mk(g.hips, mats.pants, hip, 0, 0.5, 0);

    const leg = (z) => {
      const thighP = new T.Group(); thighP.position.set(0, 0, z); hip.add(thighP);
      mk(g.thigh, mats.pants, thighP);
      const knee = new T.Group(); knee.position.y = -9; thighP.add(knee);
      mk(g.shin, mats.pants, knee);
      mk(g.boot, mats.boots, knee);
      return { thigh: thighP, knee };
    };
    const legL = leg(-3), legR = leg(3);

    const spine = new T.Group(); spine.position.y = 2.5; hip.add(spine);
    const torso = mk(g.torso, mats.shirt, spine, 0, 6.5, 0); torso.scale.set(0.95, 1, 1.25);
    const vest = mk(g.vest, mats.vest, spine, 0, 7, 0);
    const head = mk(g.head, mats.skin, spine, 0.6, 16.5, 0);
    const helmet = mk(g.helmet, mats.helmet, spine, 0.3, 17.2, 0);
    const pack = mk(g.pack, mats.pack, spine, -7, 7.5, 0);

    const arm = (z, side) => {
      const sh = new T.Group(); sh.position.set(0, 12, z); spine.add(sh);
      mk(g.upper, mats.shirt, sh);
      const el = new T.Group(); el.position.y = -7.6; sh.add(el);
      mk(g.fore, mats.shirt, el);
      mk(g.hand, mats.skin, el, 0, -8.6, 0);
      return { sh, el, side };
    };
    const armR = arm(6.3, 1), armL = arm(-6.3, -1);

    // Weapon held at chest height, pointing +x.
    const gun = new T.Group(); gun.position.set(6, 10, 2.5); spine.add(gun);
    const receiver = mk(g.receiver, mats.gun, gun);
    const barrel = mk(g.barrel, mats.gunAccent, gun);
    const mag = mk(g.mag, mats.gunAccent, gun, 3, -3, 0);
    const stock = mk(g.stock, mats.gun, gun, -4, -0.4, 0);

    const canopy = new T.Mesh(g.canopy, new T.MeshLambertMaterial({ color: opts.chute || '#c84f3a', side: T.DoubleSide }));
    canopy.position.y = 95; canopy.scale.y = 0.55;
    root.add(canopy);
    canopy.visible = false;

    const proxy = new T.Mesh(g.proxy, mats.shirt);
    root.add(proxy);
    proxy.visible = false;

    root.traverse((o) => { if (o.isMesh) o.castShadow = true; });
    canopy.castShadow = false;
    return { root, body, hip, spine, legL, legR, armR, armL, torso, vest, head, helmet, pack, gun, receiver, barrel, mag, stock, canopy, proxy, mats, walk: 0, gunCls: undefined, lod: 'full' };
  }

  // Poses: 'stand' | 'crouch' | 'prone' | 'fall' | 'chute' | 'dead'
  function poseSoldier(m, pose, walk, armed, t) {
    const sw = Math.sin(walk), sw2 = Math.sin(walk + Math.PI);
    m.body.rotation.set(0, 0, 0);
    m.body.position.set(0, 0, 0);
    m.hip.position.y = 19;
    m.spine.rotation.set(0, 0, 0);
    let thL = sw * 0.6, thR = sw2 * 0.6, knL = -Math.max(0, -sw) * 0.9, knR = -Math.max(0, -sw2) * 0.9;
    // Arms: rifle hold by default.
    let shR = [0, 0, armed ? 1.25 : sw2 * 0.4], elR = armed ? 0.25 : -0.2;
    let shL = [0.35, 0, armed ? 1.45 : sw * 0.4], elL = armed ? 0.55 : -0.2;
    if (pose === 'crouch') {
      m.hip.position.y = 12.5;
      thL = thR = 1.25 + sw * 0.2; knL = knR = -2.0;
      m.spine.rotation.z = -0.25;
    } else if (pose === 'prone' || pose === 'dead') {
      m.body.rotation.z = pose === 'dead' ? Math.PI / 2 : -Math.PI / 2;
      m.body.position.set(pose === 'dead' ? 18 : -18, 4, 0);
      thL = sw * 0.25; thR = sw2 * 0.25; knL = knR = 0;
      if (pose === 'prone' && armed) { shR = [0, 0, 2.5]; shL = [0.3, 0, 2.7]; elR = 0.4; elL = 0.6; }
      if (pose === 'dead') { shR = [1.2, 0, 0.4]; shL = [-1.2, 0, 0.4]; elR = elL = 0; }
    } else if (pose === 'fall') {
      // Skydiving: horizontal, arms and legs spread.
      m.body.rotation.z = -Math.PI / 2 + 0.25;
      m.body.position.set(-16, 6, 0);
      thL = 0.3; thR = 0.3; knL = knR = -0.6;
      m.legL.thigh.rotation.x = -0.35; m.legR.thigh.rotation.x = 0.35;
      shR = [1.3 + Math.sin(t * 9) * 0.05, 0, 0.6]; shL = [-1.3, 0, 0.6]; elR = elL = 0.3;
    } else if (pose === 'chute') {
      thL = 0.25 + sw * 0.1; thR = 0.15; knL = knR = -0.3;
      shR = [0.25, 0, 2.9]; shL = [-0.25, 0, 2.9]; elR = elL = 0.2;
    }
    if (pose !== 'fall') { m.legL.thigh.rotation.x = 0; m.legR.thigh.rotation.x = 0; }
    m.legL.thigh.rotation.z = thL; m.legR.thigh.rotation.z = thR;
    m.legL.knee.rotation.z = knL; m.legR.knee.rotation.z = knR;
    m.armR.sh.rotation.set(shR[0], shR[1], shR[2]); m.armR.el.rotation.z = elR;
    m.armL.sh.rotation.set(-shL[0], shL[1], shL[2]); m.armL.el.rotation.z = elL;
  }

  function setGun(m, type) {
    const cls = type ? WEAPONS[type].cls : null;
    if (m.gunCls === cls) return;
    m.gunCls = cls;
    m.gun.visible = !!cls;
    if (!cls) return;
    const len = GUN_LEN[cls];
    m.receiver.scale.x = len * 0.55;
    m.receiver.position.x = len * 0.1;
    m.barrel.scale.x = len * 0.55;
    m.barrel.position.x = len * 0.55;
    m.mag.visible = cls !== 'shotgun' && cls !== 'sr';
    m.mag.scale.y = cls === 'lmg' ? 1.6 : 1;
    m.stock.visible = cls !== 'pistol';
    m.mats.gun.color.set(WEAPONS[type].tier >= 6 ? '#8a6a24' : '#1f2124');
  }

  function updateSoldier(m, u, G, view, d2) {
    const { root } = m;
    root.visible = !(u.isPlayer && view.hidePlayer);
    if (!root.visible) return;
    const airborne = u.phase === 'fall' || u.phase === 'chute';
    const gy = airborne ? u.altM * H.metersToUnits : groundY(G.map, u.x, u.y);
    u.gy = gy;
    root.position.set(u.x, gy + (u.jumpT > 0 ? Math.sin((u.jumpT / 0.45) * Math.PI) * 14 : 0), u.y);
    root.rotation.y = -u.angle;
    m.canopy.visible = u.phase === 'chute' && u.alive;

    // Far away: a single cheap proxy instead of the full rig.
    const far = d2 > 1300 * 1300 && !airborne;
    if (far !== (m.lod === 'proxy')) {
      m.lod = far ? 'proxy' : 'full';
      m.body.visible = !far;
      m.proxy.visible = far;
    }
    if (far) { m.proxy.rotation.z = u.alive ? (u.stance === 'prone' ? -Math.PI / 2 : 0) : Math.PI / 2; return; }

    const near = d2 < 700 * 700;
    if (m.shadowNear !== near) { m.shadowNear = near; m.body.traverse((o) => { if (o.isMesh) o.castShadow = near; }); }

    const s = u.slots[u.active];
    setGun(m, s ? s.type : null);
    m.vest.visible = !!u.vest;
    if (u.vest) m.mats.vest.color.set(VEST[u.vest].color);
    m.helmet.visible = !!u.helmet;
    if (u.helmet) m.mats.helmet.color.set(HELMET[u.helmet].color);
    m.pack.visible = !!u.pack;
    m.pack.scale.set(1, 0.8 + (u.pack || 0) * 0.15, 1);
    const flash = u.hitFlash > 0 ? 0.5 : 0;
    m.mats.shirt.emissive.setRGB(flash, flash, flash);

    const speed = Math.hypot(u.vx || 0, u.vy || 0);
    if (u.phase === 'ground' && speed > 15) m.walk += speed * 0.014 * (u.stance === 'prone' ? 0.6 : 1) * (1 / 60) * 6;
    let pose = 'stand';
    if (!u.alive) pose = 'dead';
    else if (u.phase === 'fall') pose = 'fall';
    else if (u.phase === 'chute') pose = 'chute';
    else if (u.stance === 'prone') pose = 'prone';
    else if (u.stance === 'crouch' || u.slideT > 0) pose = 'crouch';
    poseSoldier(m, pose, u.phase === 'ground' && speed > 15 ? m.walk : 0, !!s && u.alive, G.time);
    m.gun.visible = !!s && u.alive && !airborne;
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
  ZZ.makeSoldier = makeSoldier;
  ZZ.poseSoldier = poseSoldier;
  ZZ.setSoldierGun = setGun;
})();
