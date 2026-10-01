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
import { pickEliteMod } from './foe_elites.mjs';

// Dispositions d'obstacles, en fractions de la salle (cx, cy, w, h en unités).
// Le bas-centre (entrée) et le haut (portes) restent toujours dégagés.
// BRIQUES réutilisables : le plan de section (sections.mjs) dit lesquelles un étage peut tirer
// et avec quel poids (thème du Cercle). Les six premières sont celles de tous les Cercles ;
// `cross`, `ring` et `alcoves` n'apparaissent que plus bas (tuning.circles).
const LAYOUTS = {
  open: [],
  pillars: [[0.27, 0.36, 70, 70], [0.73, 0.36, 70, 70], [0.27, 0.66, 70, 70], [0.73, 0.66, 70, 70]],
  center: [[0.5, 0.48, 150, 150]],
  lanes: [[0.3, 0.42, 260, 44], [0.7, 0.58, 260, 44]],
  bastions: [[0.18, 0.5, 60, 220], [0.82, 0.5, 60, 220], [0.5, 0.36, 120, 50]],
  scatter: [[0.22, 0.3, 60, 60], [0.5, 0.55, 80, 80], [0.78, 0.3, 60, 60], [0.35, 0.72, 50, 50], [0.65, 0.72, 50, 50]],
  // Croix : quatre bras autour du centre, des passages de 130 u entre eux.
  cross: [[0.5, 0.5, 44, 220], [0.33, 0.5, 170, 44], [0.67, 0.5, 170, 44]],
  // Anneau : huit piliers sur un cercle de 240 u autour du centre (arène dans l'arène).
  ring: [
    [0.6714, 0.5114, 56, 56], [0.6214, 0.7045, 56, 56], [0.5, 0.7841, 56, 56], [0.3786, 0.7045, 56, 56],
    [0.3286, 0.5114, 56, 56], [0.3786, 0.3182, 56, 56], [0.5, 0.2386, 56, 56], [0.6214, 0.3182, 56, 56],
  ],
  // Alcôves : des éperons collés aux murs latéraux découpent des niches, un bloc au centre.
  alcoves: [[0.0886, 0.36, 200, 40], [0.9114, 0.36, 200, 40], [0.0886, 0.68, 200, 40], [0.9114, 0.68, 200, 40], [0.5, 0.42, 110, 60]],
};
/** Identifiants des dispositions connues (le plan de section ne tire que parmi elles). */
export const LAYOUT_IDS = Object.freeze(Object.keys(LAYOUTS));
/** Les six dispositions de combat d'origine (toujours tirables ; repli sans plan). */
export const COMBAT_LAYOUTS = Object.freeze(['open', 'pillars', 'center', 'lanes', 'bastions', 'scatter']);
const BOSS_LAYOUT = [[0.15, 0.25, 64, 64], [0.85, 0.25, 64, 64], [0.15, 0.78, 64, 64], [0.85, 0.78, 64, 64]];

// Coût en « budget de vague » de chaque archétype, et étage d'apparition minimal (dans la section).
// Le plan de section (sections.mjs) en dérive le bestiaire PONDÉRÉ de chaque étage.
export const ROSTER = Object.freeze([
  { kind: 'imp', cost: 1, minIndex: 1, weight: 5 },
  { kind: 'exploder', cost: 1, minIndex: 1, weight: 2 },
  { kind: 'archer', cost: 1.5, minIndex: 1, weight: 3 },
  { kind: 'charger', cost: 2, minIndex: 1, weight: 2 }, // dès l'étage 1 : premier vrai professeur de dash
  { kind: 'brute', cost: 3, minIndex: 3, weight: 2 },
  ...EXTRA_ROSTER, // archétypes ajoutés (foe_data.mjs)
]);
// Modificateurs d'élite : tuning.elite.mods, tirés par foe_elites.pickEliteMod (introduction
// progressive dans la 1re section, exclusions par archétype).

const DOOR_W = 120;
const DOOR_H = 40;

/**
 * Salle d'un étage, COMPOSÉE à partir du plan (run.mjs → sections.mjs composeFloor) :
 * plan.kind dit le type (combat | elite | boss | shop | event | treasure | rest), plan.layouts
 * les dispositions permises et leurs poids, plan.waves / budget / roster le contenu des vagues.
 * Les salles calmes (marchand, autel, trésor, repos) restent dégagées.
 */
export function buildRoom(game, info, plan) {
  const t = game.tuning.room;
  const room = {
    w: t.width,
    h: t.height,
    pad: t.wallPad,
    kind: plan.kind, // combat | elite | shop | event | treasure | rest | boss
    reward: plan.reward, // boon | loot | gold | heal | shop | event | treasure | rest | boss
    layout: 'open',
    obstacles: [],
    waves: [],
    waveIndex: -1,
    cleared: false,
    clearedAt: 0,
    enteredAt: game.time,
    doors: [],
    interact: null, // objet à toucher : récompense, marchand, autel, coffre, fontaine
    theme: info.circle,
  };
  let rects = [];
  if (plan.kind === 'boss') {
    rects = BOSS_LAYOUT;
    room.layout = 'boss';
  } else if (plan.kind === 'combat' || plan.kind === 'elite') {
    room.layout = pickLayout(game, info, plan.layouts);
    rects = LAYOUTS[room.layout];
  }
  for (const [fx, fy, w, h] of rects) {
    const cx = fx * room.w;
    const cy = fy * room.h;
    room.obstacles.push({ x0: cx - w / 2, y0: cy - h / 2, x1: cx + w / 2, y1: cy + h / 2 });
  }
  if (plan.kind === 'combat' || plan.kind === 'elite') room.waves = planWaves(game, info, plan);
  room.nav = buildNav(room);
  return room;
}

/** Disposition tirée parmi celles du plan ([{id, weight}]) ; une seule = aucun tirage. */
function pickLayout(game, info, layouts) {
  const known = (layouts ?? []).filter((l) => LAYOUTS[l.id] && l.weight > 0);
  if (known.length === 1) return known[0].id;
  if (known.length > 1) return weightedPick(game.rng.gen, known, (l) => l.weight).id;
  // Repli sans plan (ancien comportement) : salle ouverte au tout premier étage.
  return info.floor === 1 ? 'open' : pick(game.rng.gen, COMBAT_LAYOUTS);
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

/**
 * Arène d'essai : quand les vagues sont épuisées, on en replanifie (combat sans fin), d'après
 * le plan d'arène préparé par run.mjs (room.refill : un étage de combat de début de section).
 */
export function refillSandboxWaves(game) {
  const room = game.room;
  const sb = game.tuning.section.sandbox;
  const base = room.refill ?? room.plan ?? {};
  const elite = rand(game.rng.gen) < sb.eliteChance;
  room.waves = planWaves(game, { ...game.info, floor: base.floor ?? sb.floor }, { ...base, elite });
  room.waveIndex = -1;
  launchNextWave(game);
}

/**
 * Vagues d'un étage de combat, d'après le plan composé : `waves` vagues de `budget` points de
 * menace (la dernière × lastWaveMult), tirées dans le bestiaire pondéré `roster` du plan
 * ([{kind, cost, weight}] — thème du Cercle compris). Salle d'élite : un champion en dernière
 * vague ; ailleurs, un élite égaré avec la probabilité `strayEliteChance` du plan.
 */
function planWaves(game, info, plan) {
  const t = game.tuning;
  const enc = t.encounter;
  const waveCount = plan.waves ?? t.section.paces[t.section.calmPace].waves;
  const budget = plan.budget ?? (enc.baseBudget + enc.perIndex * info.indexInSection) * floorScaling(t, info.floor).density;
  const pool = (plan.roster ?? ROSTER).filter((r) => t.enemies[r.kind] && r.weight > 0);
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
  const stray = plan.strayEliteChance ?? (info.floor >= enc.strayEliteFrom ? enc.strayEliteChance : 0);
  if (plan.elite) {
    // Salle d'élite : un champion (modificateur façon Diablo) dans la dernière vague.
    const kinds = ['brute', 'charger', 'imp', 'archer', ...EXTRA_ELITE_KINDS].filter((k) => t.enemies[k]);
    const kind = pick(game.rng.gen, kinds);
    waves[waves.length - 1].push({ kind, elite: pickEliteMod(game, kind, info) });
  } else if (stray > 0 && rand(game.rng.gen) < stray) {
    const kind = pick(game.rng.gen, ['imp', 'archer']);
    waves[waves.length - 1].push({ kind, elite: pickEliteMod(game, kind, info) });
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

/** Gardien de la section (modèle du plan : rotation floors.guardianFor). */
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
