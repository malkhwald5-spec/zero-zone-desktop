'use strict';

// Shared namespace for all game modules.
window.ZZ = window.ZZ || {};

(() => {
  const ZZ = window.ZZ;

  ZZ.MAP_SIZE = 8000; // shown in-game as an 8×8 grid of 1 km squares
  ZZ.PLAYER_COUNT = 50;

  // ---------- Ammo ----------
  ZZ.AMMO = {
    '9mm': { name: '9 ملم', stack: 30, color: '#e8c25a' },
    '556': { name: '5.56 ملم', stack: 30, color: '#7fd16b' },
    '762': { name: '7.62 ملم', stack: 30, color: '#e07b4f' },
    '12g': { name: 'خرطوش 12', stack: 10, color: '#d94a4a' },
    '300': { name: '.300 ماغنوم', stack: 10, color: '#59b7e8' },
  };
  ZZ.AMMO_TYPES = Object.keys(ZZ.AMMO);
  // Max carried ammo per type, indexed by backpack level (0-3).
  ZZ.AMMO_CAP = [90, 150, 210, 270];

  // ---------- Weapons ----------
  // cls: pistol | smg | shotgun | ar | dmr | sr | lmg
  // tier is used by bots (and auto-swap) to judge which gun is better.
  ZZ.WEAPONS = {
    p92:    { name: 'P92',    cls: 'pistol',  ammo: '9mm', dmg: 24, rate: 0.17,  mag: 15,  reload: 1.6, spread: 0.05,  speed: 1300, range: 750,  pellets: 1, auto: false, zoom: 1.0, tier: 1 },
    ump:    { name: 'UMP45',  cls: 'smg',     ammo: '9mm', dmg: 22, rate: 0.092, mag: 25,  reload: 2.0, spread: 0.065, speed: 1400, range: 950,  pellets: 1, auto: true,  zoom: 1.1, tier: 3 },
    vector: { name: 'Vector', cls: 'smg',     ammo: '9mm', dmg: 19, rate: 0.055, mag: 19,  reload: 1.8, spread: 0.075, speed: 1400, range: 850,  pellets: 1, auto: true,  zoom: 1.1, tier: 3 },
    s1897:  { name: 'S1897',  cls: 'shotgun', ammo: '12g', dmg: 12, rate: 0.85,  mag: 5,   reload: 2.6, spread: 0.2,   speed: 1100, range: 380,  pellets: 9, auto: false, zoom: 1.0, tier: 2 },
    s12k:   { name: 'S12K',   cls: 'shotgun', ammo: '12g', dmg: 10, rate: 0.3,   mag: 5,   reload: 2.8, spread: 0.22,  speed: 1100, range: 360,  pellets: 9, auto: false, zoom: 1.0, tier: 3 },
    m416:   { name: 'M416',   cls: 'ar',      ammo: '556', dmg: 22, rate: 0.086, mag: 30,  reload: 2.1, spread: 0.045, speed: 1800, range: 1500, pellets: 1, auto: true,  zoom: 1.3, tier: 4 },
    scar:   { name: 'SCAR-L', cls: 'ar',      ammo: '556', dmg: 22, rate: 0.096, mag: 30,  reload: 2.2, spread: 0.04,  speed: 1800, range: 1500, pellets: 1, auto: true,  zoom: 1.3, tier: 4 },
    akm:    { name: 'AKM',    cls: 'ar',      ammo: '762', dmg: 27, rate: 0.1,   mag: 30,  reload: 2.3, spread: 0.07,  speed: 1700, range: 1500, pellets: 1, auto: true,  zoom: 1.3, tier: 4 },
    mini14: { name: 'Mini14', cls: 'dmr',     ammo: '556', dmg: 40, rate: 0.22,  mag: 20,  reload: 2.8, spread: 0.015, speed: 2400, range: 2200, pellets: 1, auto: false, zoom: 1.6, tier: 4 },
    kar98:  { name: 'Kar98k', cls: 'sr',      ammo: '762', dmg: 85, rate: 1.5,   mag: 5,   reload: 3.2, spread: 0.004, speed: 2800, range: 2800, pellets: 1, auto: false, zoom: 1.9, tier: 5 },
    // Airdrop-only weapons.
    awm:    { name: 'AWM',    cls: 'sr',      ammo: '300', dmg: 120, rate: 1.7,  mag: 5,   reload: 3.6, spread: 0.003, speed: 3000, range: 3200, pellets: 1, auto: false, zoom: 2.1, tier: 7 },
    m249:   { name: 'M249',   cls: 'lmg',     ammo: '556', dmg: 21, rate: 0.075, mag: 100, reload: 6.0, spread: 0.07,  speed: 1800, range: 1500, pellets: 1, auto: true,  zoom: 1.3, tier: 6 },
  };

  // Preferred engagement distance per weapon class (used by bots).
  ZZ.CLASS_RANGE = { pistol: 300, smg: 280, shotgun: 140, ar: 450, dmr: 700, sr: 850, lmg: 450, fists: 30 };

  ZZ.FISTS = { name: 'قبضة', cls: 'fists', dmg: 14, rate: 0.5, range: 42 };

  // ---------- Gear ----------
  ZZ.VEST = [null,
    { name: 'سترة مستوى 1', reduce: 0.3, dur: 100, color: '#8d9a6b' },
    { name: 'سترة مستوى 2', reduce: 0.4, dur: 150, color: '#4e6fa8' },
    { name: 'سترة مستوى 3', reduce: 0.55, dur: 200, color: '#2b2b2b' },
  ];
  ZZ.HELMET = [null,
    { name: 'خوذة مستوى 1', reduce: 0.3, dur: 80, color: '#a8a27c' },
    { name: 'خوذة مستوى 2', reduce: 0.4, dur: 150, color: '#5a7a4a' },
    { name: 'خوذة مستوى 3', reduce: 0.55, dur: 230, color: '#1e1e1e' },
  ];
  ZZ.PACK = [null,
    { name: 'حقيبة مستوى 1' },
    { name: 'حقيبة مستوى 2' },
    { name: 'حقيبة مستوى 3' },
  ];

  // ---------- Consumables ----------
  // max[] is the carry limit indexed by backpack level.
  ZZ.MEDS = {
    bandage:  { name: 'ضمادة',      short: 'ضمادة', time: 3, heal: 10, cap: 75, max: [5, 10, 15, 20], key: '4', color: '#f0e6d2' },
    firstaid: { name: 'إسعاف أولي', short: 'إسعاف', time: 5, healTo: 75,         max: [2, 3, 4, 5],    key: '5', color: '#ffffff' },
    medkit:   { name: 'حقيبة طبية', short: 'طبية',  time: 7, healTo: 100,        max: [1, 1, 2, 3],    key: '6', color: '#ff5050' },
    drink:    { name: 'مشروب طاقة', short: 'طاقة',  time: 3, boost: 40,          max: [2, 3, 4, 5],    key: '7', color: '#5ac8ff' },
    pills:    { name: 'مسكّن',      short: 'مسكّن', time: 5, boost: 60,          max: [1, 2, 3, 4],    key: '8', color: '#ffb84d' },
  };
  ZZ.MED_ORDER = ['bandage', 'firstaid', 'medkit', 'drink', 'pills'];
  ZZ.GRENADE_MAX = [2, 3, 4, 5];

  // ---------- Loot tables ----------
  // Each entry: [weight, kind, type, extra]
  const common = [
    [8, 'weapon', 'p92'], [6, 'weapon', 'ump'], [3, 'weapon', 'vector'], [5, 'weapon', 's1897'], [2, 'weapon', 's12k'],
    [4, 'weapon', 'm416'], [4, 'weapon', 'scar'], [4, 'weapon', 'akm'], [2.5, 'weapon', 'mini14'], [1.2, 'weapon', 'kar98'],
    [8, 'ammo', '9mm'], [8, 'ammo', '556'], [7, 'ammo', '762'], [5, 'ammo', '12g'],
    [4, 'vest', 1], [2, 'vest', 2], [0.4, 'vest', 3],
    [4, 'helmet', 1], [2, 'helmet', 2], [0.3, 'helmet', 3],
    [3, 'pack', 1], [1.5, 'pack', 2], [0.4, 'pack', 3],
    [8, 'med', 'bandage'], [4, 'med', 'firstaid'], [0.8, 'med', 'medkit'], [4, 'med', 'drink'], [2, 'med', 'pills'],
    [3, 'grenade', 'frag'],
  ];
  const military = [
    [2, 'weapon', 'p92'], [3, 'weapon', 'ump'], [3, 'weapon', 'vector'], [2, 'weapon', 's12k'],
    [7, 'weapon', 'm416'], [6, 'weapon', 'scar'], [6, 'weapon', 'akm'], [5, 'weapon', 'mini14'], [3, 'weapon', 'kar98'],
    [6, 'ammo', '9mm'], [9, 'ammo', '556'], [9, 'ammo', '762'], [3, 'ammo', '12g'],
    [2, 'vest', 1], [4, 'vest', 2], [1.5, 'vest', 3],
    [2, 'helmet', 1], [4, 'helmet', 2], [1.2, 'helmet', 3],
    [2, 'pack', 1], [3, 'pack', 2], [1.2, 'pack', 3],
    [5, 'med', 'bandage'], [5, 'med', 'firstaid'], [2, 'med', 'medkit'], [4, 'med', 'drink'], [3, 'med', 'pills'],
    [5, 'grenade', 'frag'],
  ];
  ZZ.LOOT_TABLES = { common, military };

  // ---------- Zone phases ----------
  // wait: seconds before shrinking, shrink: shrink duration, r: target radius, dps: damage/s while outside.
  ZZ.ZONE_PHASES = [
    { wait: 120, shrink: 60, r: 2700, dps: 0.6 },
    { wait: 75,  shrink: 50, r: 1650, dps: 1.2 },
    { wait: 60,  shrink: 40, r: 960,  dps: 2.5 },
    { wait: 45,  shrink: 30, r: 530,  dps: 4 },
    { wait: 35,  shrink: 25, r: 260,  dps: 7 },
    { wait: 25,  shrink: 25, r: 85,   dps: 10 },
    { wait: 15,  shrink: 20, r: 0,    dps: 14 },
  ];
  ZZ.AIRDROP_PHASES = [1, 3]; // phase indexes at whose start a care package drops

  // ---------- Names ----------
  const first = ['صقر', 'ذيب', 'نمر', 'فهد', 'ليث', 'شبح', 'قناص', 'عقاب', 'برق', 'رعد', 'Ghost', 'Shadow', 'Viper', 'Falcon', 'Storm', 'Ninja', 'Hunter', 'Cobra', 'Wolf', 'Joker', 'Abu', 'Sniper', 'King', 'Hawk', 'Titan'];
  const second = ['_الليل', '_الصحراء', '_العرب', 'X', '_Pro', '99', '_7', '_KSA', '_IQ', '_SY', '_EG', '_JO', '_MA', '_Elite', '313', '_Gamer', '_YT', '_007', '_Zero', '_Boss'];
  ZZ.randomName = (rng) => first[Math.floor(rng() * first.length)] + second[Math.floor(rng() * second.length)];

  // ---------- Seeded RNG ----------
  ZZ.mulberry32 = (seed) => () => {
    seed |= 0; seed = (seed + 0x6D2B79F5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };

  ZZ.weightedPick = (table, rng) => {
    let total = 0;
    for (const e of table) total += e[0];
    let r = rng() * total;
    for (const e of table) { r -= e[0]; if (r <= 0) return e; }
    return table[table.length - 1];
  };
})();
