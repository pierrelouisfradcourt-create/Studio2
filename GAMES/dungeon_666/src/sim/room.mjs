// Salles : géométrie (dispositions d'obstacles), vagues d'ennemis, apparitions,
// détection de fin de combat et portes de sortie.
//
// Une salle = un étage. Le héros entre en bas, deux portes s'ouvrent en haut une fois la
// salle nettoyée ; chacune annonce la récompense de la salle suivante (façon Hades).

import { rand, randInt, pick, weightedPick } from '../core/rng.mjs';
import { emit } from './state.mjs';
import { createEnemy, aliveEnemies } from './enemies.mjs';
import { queueSpawn, findSpawnPoint } from './spawns.mjs';
import { floorScaling } from './floors.mjs';
import { buildNav } from './nav.mjs';
import { pointBlocked } from './physics.mjs';
import { EXTRA_ROSTER, EXTRA_ELITE_KINDS } from './foe_data.mjs';

// Dispositions d'obstacles, en fractions de la salle (cx, cy, w, h en unités).
// Le bas-centre (entrée) et le haut (portes) restent toujours dégagés.
const LAYOUTS = {
  open: [],
  pillars: [[0.27, 0.36, 70, 70], [0.73, 0.36, 70, 70], [0.27, 0.66, 70, 70], [0.73, 0.66, 70, 70]],
  center: [[0.5, 0.48, 150, 150]],
  lanes: [[0.3, 0.42, 260, 44], [0.7, 0.58, 260, 44]],
  bastions: [[0.18, 0.5, 60, 220], [0.82, 0.5, 60, 220], [0.5, 0.36, 120, 50]],
  scatter: [[0.22, 0.3, 60, 60], [0.5, 0.55, 80, 80], [0.78, 0.3, 60, 60], [0.35, 0.72, 50, 50], [0.65, 0.72, 50, 50]],
};
const COMBAT_LAYOUTS = ['open', 'pillars', 'center', 'lanes', 'bastions', 'scatter'];
const BOSS_LAYOUT = [[0.15, 0.25, 64, 64], [0.85, 0.25, 64, 64], [0.15, 0.78, 64, 64], [0.85, 0.78, 64, 64]];

// Coût en « budget de vague » de chaque archétype, et étage d'apparition minimal (dans la section).
const ROSTER = [
  { kind: 'imp', cost: 1, minIndex: 1, weight: 5 },
  { kind: 'exploder', cost: 1, minIndex: 1, weight: 2 },
  { kind: 'archer', cost: 1.5, minIndex: 1, weight: 3 },
  { kind: 'charger', cost: 2, minIndex: 1, weight: 2 }, // dès l'étage 1 : premier vrai professeur de dash
  { kind: 'brute', cost: 3, minIndex: 3, weight: 2 },
  ...EXTRA_ROSTER, // archétypes ajoutés (foe_data.mjs)
];
const ELITE_MODS = ['rapide', 'blinde', 'ardent'];

const DOOR_W = 120;
const DOOR_H = 40;

export function buildRoom(game, info, plan) {
  const t = game.tuning.room;
  const room = {
    w: t.width,
    h: t.height,
    pad: t.wallPad,
    kind: plan.kind, // combat | elite | shop | event | boss
    reward: plan.reward, // boon | loot | gold | heal | shop | event | boss
    layout: 'open',
    obstacles: [],
    waves: [],
    waveIndex: -1,
    cleared: false,
    clearedAt: 0,
    enteredAt: game.time,
    doors: [],
    interact: null, // objet à toucher : récompense, marchand, autel
    theme: info.circle,
  };
  let rects = [];
  if (plan.kind === 'boss') {
    rects = BOSS_LAYOUT;
    room.layout = 'boss';
  } else if (plan.kind === 'combat' || plan.kind === 'elite') {
    room.layout = info.floor === 1 ? 'open' : pick(game.rng.gen, COMBAT_LAYOUTS);
    rects = LAYOUTS[room.layout];
  }
  for (const [fx, fy, w, h] of rects) {
    const cx = fx * room.w;
    const cy = fy * room.h;
    room.obstacles.push({ x0: cx - w / 2, y0: cy - h / 2, x1: cx + w / 2, y1: cy + h / 2 });
  }
  if (plan.kind === 'combat' || plan.kind === 'elite') room.waves = planWaves(game, info, plan.kind === 'elite');
  room.nav = buildNav(room);
  return room;
}

const REWARD_CLEARANCE = 60; // u libres autour d'une récompense (le héros doit pouvoir la toucher)

/**
 * Point libre pour poser une récompense : le centre de la salle si possible, sinon le point
 * libre le plus proche sur une spirale. Jamais dans un obstacle (sinon : partie bloquée).
 */
export function rewardSpot(room) {
  const cx = room.w / 2;
  const cy = room.h * 0.45;
  if (!pointBlocked(room, cx, cy, REWARD_CLEARANCE)) return { x: cx, y: cy };
  for (let ring = 1; ring < 20; ring++) {
    const d = ring * 30;
    for (let k = 0; k < 16; k++) {
      const a = (k / 16) * Math.PI * 2 + Math.PI / 2; // commence sous l'obstacle
      const x = cx + Math.cos(a) * d;
      const y = cy + Math.sin(a) * d;
      if (!pointBlocked(room, x, y, REWARD_CLEARANCE)) return { x, y };
    }
  }
  return playerStart(room);
}

export function playerStart(room) {
  return { x: room.w / 2, y: room.h - room.pad - 70 };
}

/** Arène d'essai : quand les vagues sont épuisées, on en replanifie (combat sans fin). */
export function refillSandboxWaves(game) {
  const room = game.room;
  room.waves = planWaves(game, { ...game.info, indexInSection: 4, floor: Math.max(3, game.info.floor) }, rand(game.rng.gen) < 0.35);
  room.waveIndex = -1;
  launchNextWave(game);
}

function planWaves(game, info, elite) {
  const t = game.tuning;
  const scale = floorScaling(t, info.floor);
  const idx = info.indexInSection;
  // Plan de section : étages courts au début, assauts avant le Gardien (tuning.section.waves).
  const waveCount = t.section.waves[Math.min(idx, t.section.waves.length) - 1] ?? 2;
  const enc = t.encounter;
  const budget = (enc.baseBudget + enc.perIndex * idx) * scale.density;
  // Les archétypes entrent progressivement dans la 1re section ; ensuite tous sont là.
  const pool = ROSTER.filter((r) => r.minIndex <= (info.section > 1 ? t.floors.sectionLength : idx) && t.enemies[r.kind]);
  const waves = [];
  for (let w = 0; w < waveCount; w++) {
    let b = budget * (w === waveCount - 1 ? enc.lastWaveMult : 1);
    const wave = [];
    let guard = 0;
    while (b >= 1 && guard++ < 40) {
      const choice = weightedPick(game.rng.gen, pool.filter((r) => r.cost <= b), (r) => r.weight);
      if (!choice) break;
      wave.push({ kind: choice.kind, elite: null });
      b -= choice.cost;
    }
    waves.push(wave);
  }
  if (elite) {
    // Salle d'élite : un champion (modificateur façon Diablo) dans la dernière vague.
    const kinds = ['brute', 'charger', 'imp', 'archer', ...EXTRA_ELITE_KINDS];
    waves[waves.length - 1].push({ kind: pick(game.rng.gen, kinds), elite: pick(game.rng.gen, ELITE_MODS) });
  } else if (info.floor > 2 && rand(game.rng.gen) < enc.strayEliteChance) {
    waves[waves.length - 1].push({ kind: pick(game.rng.gen, ['imp', 'archer']), elite: pick(game.rng.gen, ELITE_MODS) });
  }
  return waves;
}

export function launchNextWave(game) {
  const room = game.room;
  room.waveIndex++;
  const wave = room.waves[room.waveIndex];
  if (!wave) return false;
  for (const s of wave) {
    const pt = findSpawnPoint(game, 30, game.tuning.room.spawnMinPlayerDist);
    if (pt) queueSpawn(game, s.kind, pt.x, pt.y, { elite: s.elite });
  }
  emit(game, 'wave', { index: room.waveIndex, count: room.waves.length });
  return true;
}

/** Gardien de la section (modèle tiré de la rotation, floors.guardianFor). */
export function spawnBoss(game, kind = 'gardien') {
  const room = game.room;
  createEnemy(game, kind, room.w / 2, room.h * 0.35, { boss: true, spawnT: 1.2 });
}

export function updateSpawns(game, dt) {
  let w = 0;
  for (let i = 0; i < game.spawns.length; i++) {
    const s = game.spawns[i];
    s.t -= dt;
    if (s.t <= 0) createEnemy(game, s.kind, s.x, s.y, { elite: s.elite, summoned: s.summoned });
    else game.spawns[w++] = s;
  }
  game.spawns.length = w;
}

/** Vagues suivantes et fin de salle. Rend true à l'image où la salle est nettoyée. */
export function updateWaves(game) {
  const room = game.room;
  if (room.cleared) return false;
  if (room.kind !== 'combat' && room.kind !== 'elite' && room.kind !== 'boss') return false;
  const alive = aliveEnemies(game);
  const pending = game.spawns.length;
  if (room.kind === 'boss') {
    const boss = game.enemies.find((e) => e.boss);
    if (boss && !boss.dead) return false;
    if (alive + pending > 0) {
      // Le boss est tombé : ses invocations meurent avec lui.
      for (const e of game.enemies) if (!e.dead) e.dead = true;
      game.spawns.length = 0;
    }
    // ... et ses attaques en cours aussi : aucun coup ne part d'un Gardien mort.
    for (const h of game.hazards) {
      if (!h.done && h.hitsPlayer) {
        h.done = true;
        emit(game, 'hazardCancel', { id: h.id, x: h.x, y: h.y });
      }
    }
    for (const pr of game.projectiles) if (pr.owner === 'enemy') pr.dead = true;
    return true;
  }
  // Vague suivante quand il ne reste presque plus personne : rythme continu.
  if (room.waveIndex < room.waves.length - 1) {
    const cur = room.waves[room.waveIndex] ?? [];
    const threshold = Math.max(0, Math.floor(cur.length * 0.25));
    if (alive + pending <= threshold) launchNextWave(game);
    return false;
  }
  return alive + pending === 0;
}

/** `descs` : [{reward, family?}] — une porte par descripteur, réparties en haut de la salle. */
export function makeDoors(game, descs) {
  const room = game.room;
  const n = descs.length;
  room.doors = descs.map((desc, i) => {
    const cx = n === 1 ? room.w / 2 : room.w * (0.32 + (0.36 * i) / (n - 1));
    return { ...desc, x: cx - DOOR_W / 2, y: 0, w: DOOR_W, h: room.pad + DOOR_H, open: true };
  });
}

/** Porte touchée par le héros (ou null). */
export function doorTouched(game) {
  const p = game.player;
  for (let i = 0; i < game.room.doors.length; i++) {
    const d = game.room.doors[i];
    if (!d.open) continue;
    if (p.x > d.x && p.x < d.x + d.w && p.y - p.r < d.y + d.h) return i;
  }
  return -1;
}

export function randomGold(game) {
  const [lo, hi] = game.tuning.economy.goldPerRoom;
  return randInt(game.rng.gen, lo, hi);
}
