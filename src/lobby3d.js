'use strict';

// Lobby scene: a night-time courtyard with arches, palms, lanterns and string
// lights, with the player's soldier standing in the middle. Drag to rotate.
(() => {
  const ZZ = window.ZZ;
  const T = window.THREE;

  function canvasTex(w, h, draw, repeat) {
    const c = document.createElement('canvas');
    c.width = w; c.height = h;
    draw(c.getContext('2d'), w, h);
    const t = new T.CanvasTexture(c);
    t.colorSpace = T.SRGBColorSpace;
    if (repeat) { t.wrapS = t.wrapT = T.RepeatWrapping; t.repeat.set(repeat, repeat); }
    return t;
  }

  class Lobby3D {
    constructor(renderer) {
      this.renderer = renderer;
      this.scene = new T.Scene();
      this.scene.background = new T.Color('#0d1022');
      this.scene.fog = new T.Fog('#0d1022', 260, 900);
      this.camera = new T.PerspectiveCamera(42, 1, 1, 3000);
      this.camera.position.set(115, 46, 0);
      this.camera.lookAt(0, 26, 0);
      this.rot = 0.5;
      this.t = 0;
      this.build();
      this.setupDrag();
    }

    build() {
      const S = this.scene;
      const L = (c, extra = {}) => new T.MeshLambertMaterial({ color: c, ...extra });
      S.add(new T.HemisphereLight(0x6a78b8, 0x2a1d14, 0.55));
      const moonLight = new T.DirectionalLight(0xaab8ff, 0.5);
      moonLight.position.set(-200, 300, 150);
      S.add(moonLight);
      const key = new T.SpotLight(0xffd7a0, 900, 400, 0.6, 0.6, 1.3);
      key.position.set(120, 160, 60);
      key.target.position.set(0, 20, 0);
      key.castShadow = true;
      key.shadow.mapSize.set(1024, 1024);
      S.add(key, key.target);

      // Floor tiles
      const floorTex = canvasTex(256, 256, (g, w, h) => {
        g.fillStyle = '#c9b496'; g.fillRect(0, 0, w, h);
        g.strokeStyle = 'rgba(70,50,30,0.35)'; g.lineWidth = 3;
        for (let i = 0; i <= 4; i++) { g.beginPath(); g.moveTo(i * 64, 0); g.lineTo(i * 64, h); g.moveTo(0, i * 64); g.lineTo(w, i * 64); g.stroke(); }
        for (let i = 0; i < 500; i++) { g.fillStyle = `rgba(0,0,0,${Math.random() * 0.06})`; g.fillRect(Math.random() * w, Math.random() * h, 3, 3); }
      }, 14);
      const floor = new T.Mesh(new T.PlaneGeometry(1400, 1400), new T.MeshLambertMaterial({ map: floorTex }));
      floor.rotation.x = -Math.PI / 2;
      floor.receiveShadow = true;
      S.add(floor);
      // Platform under the character
      const plat = new T.Mesh(new T.CylinderGeometry(26, 28, 3, 40), L('#8b7a63'));
      plat.position.y = 1.5;
      plat.receiveShadow = true;
      S.add(plat);

      // Arcade of arches on both sides and a gate at the back.
      const wallMat = L('#b48a62'), trim = L('#7a5236');
      const arch = (x, z, rotY) => {
        const g = new T.Group();
        const p1 = new T.Mesh(new T.BoxGeometry(8, 60, 8), wallMat); p1.position.set(-22, 30, 0);
        const p2 = new T.Mesh(new T.BoxGeometry(8, 60, 8), wallMat); p2.position.set(22, 30, 0);
        const top = new T.Mesh(new T.TorusGeometry(22, 4, 6, 16, Math.PI), wallMat); top.position.y = 60;
        const lintel = new T.Mesh(new T.BoxGeometry(56, 14, 9), wallMat); lintel.position.y = 88;
        const band = new T.Mesh(new T.BoxGeometry(57, 3, 10), trim); band.position.y = 96;
        g.add(p1, p2, top, lintel, band);
        // Hanging lantern
        const lantern = new T.Mesh(new T.BoxGeometry(5, 8, 5), new T.MeshBasicMaterial({ color: '#ffcf6a' }));
        lantern.position.y = 64;
        g.add(lantern);
        g.position.set(x, 0, z);
        g.rotation.y = rotY;
        S.add(g);
      };
      for (let i = -4; i <= 4; i++) { arch(-60 + i * 0, 0, 0); }
      for (let i = 0; i < 7; i++) {
        arch(-160 + i * 60 - 40, -150, 0);
        arch(-160 + i * 60 - 40, 150, 0);
      }
      const back = new T.Mesh(new T.BoxGeometry(20, 140, 260), wallMat);
      back.position.set(-260, 70, 0);
      S.add(back);
      const gate = new T.Mesh(new T.TorusGeometry(40, 8, 8, 20, Math.PI), trim);
      gate.rotation.y = Math.PI / 2;
      gate.position.set(-249, 80, 0);
      const gateDark = new T.Mesh(new T.PlaneGeometry(80, 80), L('#2a1a10'));
      gateDark.rotation.y = Math.PI / 2;
      gateDark.position.set(-249, 40, 0);
      S.add(gate, gateDark);
      for (const z of [-90, 90]) {
        const tower = new T.Mesh(new T.BoxGeometry(40, 200, 40), wallMat);
        tower.position.set(-250, 100, z);
        const crown = new T.Mesh(new T.BoxGeometry(46, 10, 46), trim);
        crown.position.set(-250, 200, z);
        S.add(tower, crown);
      }

      // Palm trees
      const palm = (x, z, h) => {
        const g = new T.Group();
        for (let i = 0; i < 8; i++) {
          const seg = new T.Mesh(new T.CylinderGeometry(2.6 - i * 0.12, 3 - i * 0.12, h / 8, 7), L('#6b4a2f'));
          seg.position.set(Math.sin(i * 0.3) * 4, (i + 0.5) * (h / 8), 0);
          g.add(seg);
        }
        for (let i = 0; i < 9; i++) {
          const leaf = new T.Mesh(new T.ConeGeometry(4, 46, 4), L('#2f5a2b', { flatShading: true }));
          const a = (i / 9) * Math.PI * 2;
          leaf.position.set(Math.sin(2.4) * 4 + Math.cos(a) * 18, h + 2, Math.sin(a) * 18);
          leaf.rotation.set(Math.sin(a) * 1.3, 0, -Math.cos(a) * 1.3);
          g.add(leaf);
        }
        g.position.set(x, 0, z);
        S.add(g);
      };
      palm(-150, -70, 120); palm(-150, 75, 130); palm(-40, -110, 110); palm(-40, 115, 115);

      // Gold-trimmed crate (loot chest) next to the character
      const chest = new T.Group();
      const cb = new T.Mesh(new T.BoxGeometry(26, 18, 18), L('#e9e2d4'));
      cb.position.y = 9;
      const cl = new T.Mesh(new T.BoxGeometry(27, 6, 19), L('#9b2b2b'));
      cl.position.y = 20;
      const glow = new T.PointLight(0xffc04d, 300, 90, 1.5);
      glow.position.set(0, 26, 0);
      chest.add(cb, cl, glow);
      chest.position.set(-30, 0, -48);
      chest.rotation.y = 0.5;
      S.add(chest);

      // String lights
      const bulbs = [];
      for (const z of [-120, 120]) {
        for (let i = 0; i <= 40; i++) {
          const x = -230 + i * 8;
          bulbs.push(x, 110 - Math.sin((i / 40) * Math.PI) * 18, z * (0.6 + 0.4 * Math.sin((i / 40) * Math.PI)));
        }
      }
      for (let i = 0; i <= 30; i++) bulbs.push(-230 + i * 9, 120 - Math.sin((i / 30) * Math.PI) * 25, 0);
      const bg = new T.BufferGeometry();
      bg.setAttribute('position', new T.Float32BufferAttribute(bulbs, 3));
      this.bulbs = new T.Points(bg, new T.PointsMaterial({ color: '#ffd36b', size: 4, sizeAttenuation: true }));
      S.add(this.bulbs);
      for (const [x, z] of [[-120, -90], [-120, 90], [-40, 0]]) {
        const pl = new T.PointLight(0xffb85a, 220, 160, 1.6);
        pl.position.set(x, 90, z);
        S.add(pl);
      }

      // Night sky: stars and a crescent moon
      const stars = [];
      for (let i = 0; i < 700; i++) {
        const a = Math.random() * Math.PI * 2, e = Math.random() * 1.2 + 0.15, r = 1600;
        stars.push(Math.cos(a) * Math.cos(e) * r - 400, Math.sin(e) * r, Math.sin(a) * Math.cos(e) * r);
      }
      const sg = new T.BufferGeometry();
      sg.setAttribute('position', new T.Float32BufferAttribute(stars, 3));
      S.add(new T.Points(sg, new T.PointsMaterial({ color: '#ffffff', size: 2.2, sizeAttenuation: false, fog: false })));
      const moonTex = canvasTex(128, 128, (g) => {
        g.fillStyle = '#fff6dc'; g.beginPath(); g.arc(64, 64, 50, 0, Math.PI * 2); g.fill();
        g.globalCompositeOperation = 'destination-out';
        g.beginPath(); g.arc(84, 52, 46, 0, Math.PI * 2); g.fill();
      });
      const moon = new T.Sprite(new T.SpriteMaterial({ map: moonTex, fog: false, transparent: true }));
      moon.position.set(-700, 380, -160);
      moon.scale.set(140, 140, 1);
      S.add(moon);

      // The character
      this.holder = new T.Group();
      S.add(this.holder);
      this.setOutfit(ZZ.lobbyOutfit || {});
    }

    setOutfit(o) {
      if (this.soldier) this.holder.remove(this.soldier.root);
      const s = ZZ.makeSoldier({ clothes: o.clothes || '#2d6fb8', pants: o.pants || '#2f3338', chute: '#f2a900' });
      ZZ.setSoldierGun(s, 'm416');
      s.vest.visible = true; s.mats.vest.color.set('#4e6fa8');
      s.helmet.visible = true; s.mats.helmet.color.set('#5a7a4a');
      s.pack.visible = true;
      s.root.position.y = 3;
      s.root.scale.setScalar(1.15);
      s.root.traverse((m) => { if (m.isMesh) m.castShadow = true; });
      this.soldier = s;
      this.holder.add(s.root);
    }

    setupDrag() {
      let last = null;
      const el = this.renderer.domElement;
      el.addEventListener('pointerdown', (e) => { if (this.active) last = e.clientX; });
      window.addEventListener('pointermove', (e) => { if (last !== null) { this.rot += (e.clientX - last) * 0.01; last = e.clientX; } });
      window.addEventListener('pointerup', () => { last = null; });
    }

    render(dt, w, h) {
      this.t += dt;
      if (this.camera.aspect !== w / h) { this.camera.aspect = w / h; this.camera.updateProjectionMatrix(); }
      // Keep the character slightly right of centre, like a lobby screen.
      this.camera.position.set(118, 44, -26);
      this.camera.lookAt(0, 30, -14);
      this.holder.rotation.y = this.rot + Math.sin(this.t * 0.3) * 0.08;
      // Idle breathing
      ZZ.poseSoldier(this.soldier, 'stand', 0, true, this.t);
      this.soldier.spine.rotation.x = Math.sin(this.t * 1.6) * 0.03;
      this.soldier.armR.sh.rotation.z = 1.0 + Math.sin(this.t * 1.6) * 0.03;
      this.soldier.armL.sh.rotation.z = 1.2 + Math.sin(this.t * 1.6) * 0.03;
      this.bulbs.material.size = 4 + Math.sin(this.t * 3) * 0.6;
      this.renderer.render(this.scene, this.camera);
    }
  }

  ZZ.Lobby3D = Lobby3D;
})();
