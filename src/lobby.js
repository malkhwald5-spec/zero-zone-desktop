'use strict';

// Lobby: player profile (name + photo), rank/level from career stats,
// the showcase stage, the photo viewer and the profile editor.
(() => {
  const ZZ = window.ZZ;
  const $ = (id) => document.getElementById(id);

  const DEFAULT_NAME = 'المحارب';
  const DEFAULT_HERO = 'assets/hero.jpg';
  const DEFAULT_AVATAR = 'assets/avatar.jpg';

  const store = {
    get(key, fallback) { try { const v = localStorage.getItem(key); return v === null ? fallback : JSON.parse(v); } catch { return fallback; } },
    set(key, value) { try { localStorage.setItem(key, JSON.stringify(value)); return true; } catch { return false; } },
  };

  let profile = Object.assign({ name: DEFAULT_NAME, hero: null, avatar: null }, store.get('zz_profile', {}));

  ZZ.Profile = { name: () => profile.name || DEFAULT_NAME };

  // ---------- Rank ----------
  const TIERS = [
    { min: 1, name: 'برونزي', cls: 't-bronze' },
    { min: 5, name: 'فضي', cls: 't-silver' },
    { min: 10, name: 'ذهبي', cls: 't-gold' },
    { min: 15, name: 'بلاتيني', cls: 't-plat' },
    { min: 20, name: 'ماسي', cls: 't-diamond' },
    { min: 30, name: 'التاج', cls: 't-crown' },
    { min: 40, name: 'الفاتح', cls: 't-conq' },
  ];
  const xpFor = (lvl) => 25 * (lvl - 1) * (lvl - 1);

  function rankOf(st) {
    const xp = st.kills * 10 + st.wins * 150 + st.games * 20;
    const level = Math.min(99, Math.floor(Math.sqrt(xp / 25)) + 1);
    const progress = level >= 99 ? 1 : (xp - xpFor(level)) / (xpFor(level + 1) - xpFor(level));
    let tier = TIERS[0];
    for (const t of TIERS) if (level >= t.min) tier = t;
    return { xp, level, progress, tier };
  }

  // ---------- Render ----------
  function setText(id, v) { const el = $(id); if (el) el.textContent = v; }
  function setSrc(id, v) { const el = $(id); if (el && el.getAttribute('src') !== v) el.src = v; }

  function render(st) {
    st = st || store.get('zz_stats', { wins: 0, best: 0, kills: 0, games: 0 });
    const r = rankOf(st);
    const name = ZZ.Profile.name();
    const hero = profile.hero || DEFAULT_HERO;
    const avatar = profile.avatar || DEFAULT_AVATAR;

    ['pf-name', 'hero-name', 'viewer-name', 'hud-name', 'res-name'].forEach((id) => setText(id, name));
    ['hero-img', 'viewer-img'].forEach((id) => setSrc(id, hero));
    ['pf-avatar', 'hud-avatar', 'res-avatar'].forEach((id) => setSrc(id, avatar));

    setText('pf-level', String(r.level));
    setText('pf-tier', r.tier.name);
    setText('hero-tier', r.tier.name);
    setText('hero-sub', `المستوى ${r.level} · ${r.xp} نقطة خبرة`);
    setText('viewer-tier', `${r.tier.name} · المستوى ${r.level}`);
    setText('pf-wins', String(st.wins));
    setText('pf-kills', String(st.kills));
    setText('pf-games', String(st.games));
    $('pf-xp-fill').style.width = `${Math.round(r.progress * 100)}%`;

    const menu = $('menu');
    TIERS.forEach((t) => menu.classList.toggle(t.cls, t === r.tier));
  }

  ZZ.onMenuRefresh = render;

  // ---------- Showcase tilt ----------
  const reduceMotion = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const showcase = $('showcase');
  const frame = $('hero-frame');
  if (!reduceMotion) {
    showcase.addEventListener('mousemove', (e) => {
      const b = showcase.getBoundingClientRect();
      const nx = (e.clientX - b.left) / b.width - 0.5;
      const ny = (e.clientY - b.top) / b.height - 0.5;
      frame.style.transform = `rotateY(${(nx * 14).toFixed(2)}deg) rotateX(${(-ny * 10).toFixed(2)}deg)`;
      frame.style.setProperty('--sx', `${Math.round((nx + 0.5) * 100)}%`);
      frame.style.setProperty('--sy', `${Math.round((ny + 0.5) * 100)}%`);
    });
    showcase.addEventListener('mouseleave', () => { frame.style.transform = ''; });
  }

  // ---------- Modals ----------
  function openModal(id) { $(id).classList.remove('hidden'); }
  function closeModal(id) { $(id).classList.add('hidden'); }
  const isOpen = (id) => !$(id).classList.contains('hidden');

  showcase.addEventListener('click', () => openModal('viewer'));
  $('viewer-close').addEventListener('click', () => closeModal('viewer'));
  $('viewer').addEventListener('click', (e) => { if (e.target.id === 'viewer') closeModal('viewer'); });

  // ---------- Profile editor ----------
  let draft = null;

  function openEditor() {
    draft = { name: ZZ.Profile.name(), hero: profile.hero, avatar: profile.avatar };
    $('pe-name').value = draft.name;
    $('pe-avatar').src = draft.avatar || DEFAULT_AVATAR;
    $('pe-msg').textContent = '';
    openModal('profile');
    $('pe-name').focus();
    $('pe-name').select();
  }

  function saveEditor() {
    const name = $('pe-name').value.replace(/\s+/g, ' ').trim().slice(0, 16);
    const next = { name: name || DEFAULT_NAME, hero: draft.hero, avatar: draft.avatar };
    if (!store.set('zz_profile', next)) {
      $('pe-msg').textContent = 'تعذّر حفظ الصورة — جرّب صورة أصغر.';
      return;
    }
    profile = next;
    closeModal('profile');
    render();
    if (typeof Sound !== 'undefined') { Sound.init(); Sound.play('equip'); }
  }

  function loadImage(file) {
    return new Promise((resolve, reject) => {
      const url = URL.createObjectURL(file);
      const img = new Image();
      img.onload = () => { URL.revokeObjectURL(url); resolve(img); };
      img.onerror = () => { URL.revokeObjectURL(url); reject(new Error('bad image')); };
      img.src = url;
    });
  }

  // Draws the source rect (sx, sy, sw, sh) of img into a w×h JPEG data URL.
  function toJpeg(img, sx, sy, sw, sh, w, h, q) {
    const c = document.createElement('canvas');
    c.width = w;
    c.height = h;
    const g = c.getContext('2d');
    g.imageSmoothingQuality = 'high';
    g.drawImage(img, sx, sy, sw, sh, 0, 0, w, h);
    return c.toDataURL('image/jpeg', q);
  }

  async function pickPhoto(file) {
    if (!file) return;
    $('pe-msg').textContent = 'جارٍ التحميل…';
    try {
      const img = await loadImage(file);
      const iw = img.naturalWidth, ih = img.naturalHeight;
      const k = Math.min(1, 720 / iw, 1000 / ih);
      draft.hero = toJpeg(img, 0, 0, iw, ih, Math.round(iw * k), Math.round(ih * k), 0.84);
      // Square avatar biased toward the top, where faces usually are.
      const side = Math.min(iw, ih);
      draft.avatar = toJpeg(img, (iw - side) / 2, (ih - side) * 0.15, side, side, 256, 256, 0.86);
      $('pe-avatar').src = draft.avatar;
      $('pe-msg').textContent = 'اضغط حفظ لاعتماد الصورة.';
    } catch {
      $('pe-msg').textContent = 'تعذّرت قراءة الصورة.';
    }
  }

  $('profile-chip').addEventListener('click', openEditor);
  $('btn-profile').addEventListener('click', openEditor);
  $('pe-photo').addEventListener('click', () => $('pe-file').click());
  $('pe-file').addEventListener('change', (e) => { pickPhoto(e.target.files[0]); e.target.value = ''; });
  $('pe-reset').addEventListener('click', () => {
    draft.hero = null;
    draft.avatar = null;
    $('pe-avatar').src = DEFAULT_AVATAR;
    $('pe-msg').textContent = 'اضغط حفظ لاعتماد الصورة.';
  });
  $('pe-save').addEventListener('click', saveEditor);
  $('pe-cancel').addEventListener('click', () => closeModal('profile'));
  $('pe-name').addEventListener('keydown', (e) => { if (e.key === 'Enter') saveEditor(); });

  window.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape') return;
    if (isOpen('viewer')) closeModal('viewer');
    else if (isOpen('profile')) closeModal('profile');
  });

  // Starting a match closes any open lobby modal.
  $('btn-start').addEventListener('click', () => { closeModal('viewer'); closeModal('profile'); });

  render();
})();
