// Propriétés STRICTES — complètent tests/properties.test.mjs (qui reste tel quel) là où un test
// de mutation a montré qu'un défaut de la sim passait inaperçu :
//   dash sans i-frames, dash immobile, esquive non comptée      -> (g)
//   menu qui consomme les entrées (gadget tiré pendant la pause) -> (h)
//   stateHash constant ou aveugle aux RNG                        -> (i)
//   Math.random / horloge dans la sim ou les bots                -> (j)
//   ennemis poussés dans les murs, héros dans un obstacle,
//   soin au-delà des PV max                                      -> (k)
//   salle de boss vide (oracle de jouabilité trivialement vert)  -> (l)
//   récompense posée hors d'atteinte, disposition non couverte   -> (m)
//   bot qui triche (lit le RNG, un compteur caché) ou qui écrit  -> (n)
// Comme le fichier d'origine : des lois, pas des valeurs de tuning (les seuils lisent
// game.tuning). Lancer : node --test tests/properties_strict.test.mjs

import test from 'node:test';
import assert from 'node:assert/strict';
import { createGame, stepGame, emptyInput, applyCommand, stateHash } from '../src/sim/game.mjs';
import { maxDashCharges } from '../src/sim/player.mjs';
import { spawnProjectile } from '../src/sim/projectiles.mjs';
import { pointBlocked } from '../src/sim/physics.mjs';
import { POLICIES, resolveChoice } from '../tools/bots.mjs';
import { runEpisode } from '../tools/playtest.mjs';

const DT = 1 / 60;
const GEOM_EPS = 0.5; // u : arrondi toléré sur un contact mur / obstacle
const PROBE_RADIUS = 40; // u : projectile témoin assez gros pour toucher même pendant un dash
const PROBE_DAMAGE = 30;
const DASH_SEED = 7;
const DASH_MAX_STEPS = 120;
const DASH_DISTANCE_TOLERANCE = 0.25; // fraction de dash.distance (sortie de dash à la course)
const MENU_SEED = 3;
const MENU_SEARCH_STEPS = 20000;
const MENU_PAUSE_STEPS = 120;
const HASH_SEED = 1;
const HASH_SEARCH_STEPS = 600;
const CLOCK_STEPS = 3000;
const SECTION_SEEDS = [1, 2, 3, 4];
const SECTION_FLOORS = 6;
const SECTION_TICK_CAP = 12 * 60 * 60; // 12 min de sim
const RANDOM_START_FLOORS = [2, 3, 4, 5, 6];
const RANDOM_SEEDS = [1, 2, 3];
const RANDOM_STEPS = 2000;
const MIN_OBSTACLE_LAYOUTS = 3; // dispositions à obstacles réellement exercées avec des ennemis
const PLAYABILITY_SEEDS = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
const PLAYABILITY_MINUTES = 12;
const LAYOUT_SEED_LIMIT = 300;
const LAYOUT_FLOOR = 2;
const BOSS_FLOOR = 6;
// Miroir de LAYOUTS (combat) et de BOSS_LAYOUT dans src/sim/room.mjs : une disposition ajoutée
// là-bas doit l'être ici pour être couverte.
const EXPECTED_LAYOUTS = ['open', 'pillars', 'center', 'lanes', 'bastions', 'scatter', 'boss'];
const PATH_CELL = 8; // u : pas de la grille de recherche de chemin
const AUDIT_STEPS = 2500;
// Champs qu'un joueur ne voit pas à l'écran (le rendu ne les dessine pas, ou seulement à
// travers un indice visuel que le bot lit déjà : tele, jauges, barres de PV, cercles).
const FORBIDDEN_READS = [
  'game.rng', 'game.nextId',
  'enemies[].cooldown', 'enemies[].stateTime', 'enemies[].atkId', 'enemies[].hitPlayer',
  'enemies[].pattern', 'enemies[].patternT', 'enemies[].patternStep', 'enemies[].restFor',
  'enemies[].strafe', 'enemies[].flank', 'enemies[].dirX', 'enemies[].dirY',
  'enemies[].dmgScale', 'enemies[].burnAcc', 'enemies[].bornAt',
];

// ---------------------------------------------------------------- outillage

function makeRng(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function randomMove(input, rng) {
  const a = rng() * Math.PI * 2;
  const m = rng();
  input.moveX = Math.cos(a) * m;
  input.moveY = Math.sin(a) * m;
  input.aimX = rng() * 2 - 1;
  input.aimY = rng() * 2 - 1;
  return input;
}

function randomInput(rng) {
  const input = randomMove(emptyInput(), rng);
  input.attack = rng() < 0.5;
  input.attackPressed = rng() < 0.1;
  input.dashPressed = rng() < 0.04;
  input.skillPressed = rng() < 0.02;
  input.gadgetPressed = rng() < 0.005;
  input.superPressed = rng() < 0.01;
  return input;
}

/** Tous les boutons pressés à la fois : le pire cas pour une pause. */
function allButtons(rng) {
  const input = randomMove(emptyInput(), rng);
  Object.assign(input, { attack: true, attackPressed: true, dashPressed: true, skillPressed: true, gadgetPressed: true, superPressed: true });
  return input;
}

function settleChoice(game) {
  for (let i = 0; i < 8 && game.mode === 'choice'; i++) resolveChoice(game, 'skilled');
}

/** Un pas de jeu « joueur » : menus résolus, reprise après la mort, événements rendus. */
function playStep(game, input) {
  if (game.mode === 'choice') settleChoice(game);
  if (game.mode === 'dead') applyCommand(game, { type: 'respawn' });
  if (game.mode !== 'play') return [];
  stepGame(game, input);
  const events = game.events.slice();
  game.events.length = 0;
  return events;
}

/**
 * Salle d'arrivée vidée : seuls nos projectiles témoins frappent. Marquée nettoyée d'avance,
 * sinon elle se termine à la première image (gel d'impact du dernier ennemi + récompense).
 */
function quietGame(seed) {
  const game = createGame({ seed });
  game.enemies.length = 0;
  game.spawns.length = 0;
  game.room.waves = [];
  game.room.cleared = true;
  return game;
}

function probeHit(game) {
  const p = game.player;
  spawnProjectile(game, { owner: 'enemy', kind: 'probe', x: p.x, y: p.y, vx: 0, vy: 0, r: PROBE_RADIUS, damage: PROBE_DAMAGE, range: 1e9 });
}

/** État complet sérialisé (événements exclus, tableaux typés lisibles). */
function snapshot(game) {
  return JSON.stringify(game, (k, v) => (k === 'events' ? undefined : ArrayBuffer.isView(v) ? Array.from(v) : v));
}

/** Profondeur (u) d'un cercle dans un rectangle ; <= 0 si pas de chevauchement. */
function rectOverlap(o, x, y, r) {
  const cx = Math.min(Math.max(x, o.x0), o.x1);
  const cy = Math.min(Math.max(y, o.y0), o.y1);
  const inside = x > o.x0 && x < o.x1 && y > o.y0 && y < o.y1;
  if (inside) return r + Math.min(x - o.x0, o.x1 - x, y - o.y0, o.y1 - y);
  return r - Math.hypot(x - cx, y - cy);
}

/** Viole-t-il la géométrie de la salle (hors des murs ou dans un obstacle) ? Rend un message ou null. */
function geometryViolation(room, x, y, r) {
  const lo = room.pad + r - GEOM_EPS;
  if (x < lo || x > room.w - lo || y < lo || y > room.h - lo) return `hors des murs (${x.toFixed(1)}, ${y.toFixed(1)}, r ${r})`;
  for (const o of room.obstacles) {
    const depth = rectOverlap(o, x, y, r);
    if (depth > GEOM_EPS) return `${depth.toFixed(1)} u dans l'obstacle ${JSON.stringify(o)} (${x.toFixed(1)}, ${y.toFixed(1)}, r ${r})`;
  }
  return null;
}

// ---------------------------------------------------------------- (g) dash

test('(g) le dash accorde des i-frames, un coup pendant le dash est une esquive comptée, et le dash déplace le héros', () => {
  const game = quietGame(DASH_SEED);
  const p = game.player;
  const x0 = p.x;
  const y0 = p.y;
  const dash = emptyInput();
  dash.dashPressed = true;
  dash.moveY = -1; // vers le haut : la salle d'arrivée est ouverte
  stepGame(game, dash);
  assert.equal(p.state, 'dash', 'le dash doit partir');
  assert.ok(p.iframes > DT, `le dash doit accorder des i-frames (reste ${p.iframes})`);
  const hp = p.hp;
  const dodges = game.telemetry.dodges;
  probeHit(game);
  stepGame(game, emptyInput());
  game.projectiles.length = 0;
  assert.equal(p.hp, hp, 'un coup pendant le dash ne doit pas retirer de PV');
  assert.equal(game.telemetry.dodges, dodges + 1, 'le coup évité doit être compté comme esquive (télémétrie)');
  assert.ok(game.events.some((e) => e.type === 'dodge'), "le coup évité doit émettre l'événement 'dodge'");
  for (let i = 0; i < DASH_MAX_STEPS && p.state === 'dash'; i++) stepGame(game, emptyInput());
  const moved = Math.hypot(p.x - x0, p.y - y0);
  const d = game.tuning.dash.distance;
  assert.ok(Math.abs(moved - d) <= d * DASH_DISTANCE_TOLERANCE, `le dash doit parcourir ~${d} u (mesuré ${moved.toFixed(1)} u)`);
});

// ---------------------------------------------------------------- (h) pause des menus

function reachChoice(seed) {
  const game = createGame({ seed });
  const mem = {};
  for (let i = 0; i < MENU_SEARCH_STEPS && game.mode === 'play'; i++) {
    stepGame(game, POLICIES.skilled(game, mem));
    game.events.length = 0;
  }
  assert.equal(game.mode, 'choice', 'le bot doit atteindre un menu (récompense de salle)');
  return game;
}

test("(h) menu ouvert : pause TOTALE — aucun champ de l'état ne change, aucun événement, même tous boutons pressés", () => {
  const game = reachChoice(MENU_SEED);
  const before = snapshot(game);
  const rng = makeRng(0x5eed);
  for (let i = 0; i < MENU_PAUSE_STEPS; i++) {
    stepGame(game, allButtons(rng));
    assert.equal(game.events.length, 0, `pas ${i} : événement émis pendant un menu (${game.events.map((e) => e.type).join(', ')})`);
  }
  assert.equal(snapshot(game), before, "l'état a changé pendant un menu (entrées lues, gadget tiré, temps écoulé…)");
});

// ---------------------------------------------------------------- (i) empreinte

test("(i) stateHash est sensible : héros, ennemi, RNG, temps, étage, or changent l'empreinte", () => {
  const base = createGame({ seed: HASH_SEED });
  for (let i = 0; i < HASH_SEARCH_STEPS && !base.enemies.length; i++) playStep(base, emptyInput());
  assert.ok(base.enemies.length > 0, 'il faut un ennemi présent pour tester son empreinte');
  const h0 = stateHash(base);
  const mutations = {
    'héros déplacé de 1 u': (g) => { g.player.x += 1; },
    'PV du héros -1': (g) => { g.player.hp -= 1; },
    'PV d\'un ennemi -1': (g) => { g.enemies[0].hp -= 1; },
    'RNG gen avancé': (g) => { g.rng.gen.s = (g.rng.gen.s + 1) >>> 0; },
    'RNG combat avancé': (g) => { g.rng.combat.s = (g.rng.combat.s + 1) >>> 0; },
    'RNG ai avancé': (g) => { g.rng.ai.s = (g.rng.ai.s + 1) >>> 0; },
    'temps +1 pas': (g) => { g.time += DT; },
    'étage +1': (g) => { g.run.floor += 1; },
    'or +1': (g) => { g.run.gold += 1; },
  };
  for (const [label, mutate] of Object.entries(mutations)) {
    const g = structuredClone(base);
    mutate(g);
    assert.notEqual(stateHash(g), h0, `stateHash ne voit pas : ${label}`);
  }
});

// ---------------------------------------------------------------- (j) aucune source externe

test("(j) ni la sim ni les bots n'appellent Math.random, Date.now ou performance.now", () => {
  const saved = { random: Math.random, now: Date.now, perfNow: performance.now };
  const trap = (name) => () => {
    throw new Error(`${name} appelé pendant une partie : le déterminisme est rompu`);
  };
  Math.random = trap('Math.random');
  Date.now = trap('Date.now');
  performance.now = trap('performance.now');
  try {
    for (const name of Object.keys(POLICIES)) {
      const game = createGame({ seed: 2 });
      const mem = {};
      for (let i = 0; i < CLOCK_STEPS; i++) playStep(game, POLICIES[name](game, mem));
    }
  } finally {
    Math.random = saved.random;
    Date.now = saved.now;
    performance.now = saved.perfNow;
  }
});

// ---------------------------------------------------------------- (k) invariants stricts

function checkStrict(game, where, cover) {
  const p = game.player;
  const room = game.room;
  const pv = geometryViolation(room, p.x, p.y, p.r);
  assert.equal(pv, null, `${where} : héros ${pv}`);
  assert.ok(p.hp >= 0 && p.hp <= p.maxHp, `${where} : PV du héros hors bornes (${p.hp} / ${p.maxHp})`);
  assert.equal(p.hp <= 0, p.state === 'dead', `${where} : PV ${p.hp} incohérents avec l'état '${p.state}'`);
  assert.ok(p.dashCharges >= 0 && p.dashCharges <= maxDashCharges(game), `${where} : charges de dash ${p.dashCharges}`);
  assert.ok(p.gadgetCharges >= 0, `${where} : charges de gadget négatives (${p.gadgetCharges})`);
  assert.ok(p.superCharge >= 0 && p.superCharge <= 1, `${where} : jauge de Super ${p.superCharge}`);
  for (const e of game.enemies) {
    if (e.dead) continue;
    const ev = geometryViolation(room, e.x, e.y, e.r);
    assert.equal(ev, null, `${where} : ${e.kind}#${e.id} ${ev}`);
    assert.ok(e.hp > 0 && e.hp <= e.maxHp, `${where} : ${e.kind}#${e.id} vivant avec ${e.hp} / ${e.maxHp} PV`);
    if (room.obstacles.length) cover.obstacleLayouts.add(room.layout);
    if (e.boss) cover.bossSteps++;
  }
  for (const pk of game.pickups) {
    const kv = geometryViolation(room, pk.x, pk.y, pk.r);
    assert.equal(kv, null, `${where} : objet au sol ${pk.kind} ${kv}`);
  }
}

function newCover() {
  return { obstacleLayouts: new Set(), bossSteps: 0, heals: 0 };
}

function countHeals(events, cover) {
  for (const e of events) if (e.type === 'heal' || (e.type === 'pickup' && e.kind === 'heal')) cover.heals++;
}

test('(k) invariants stricts (cercles entiers, murs, obstacles, PV) — sections complètes du bot skilled', () => {
  const cover = newCover();
  for (const seed of SECTION_SEEDS) {
    const game = createGame({ seed });
    const mem = {};
    while (game.run.floor <= SECTION_FLOORS && game.tick < SECTION_TICK_CAP) {
      const events = playStep(game, POLICIES.skilled(game, mem));
      checkStrict(game, `skilled graine ${seed} tick ${game.tick} étage ${game.run.floor}`, cover);
      countHeals(events, cover);
    }
  }
  assert.ok(cover.obstacleLayouts.size >= MIN_OBSTACLE_LAYOUTS, `couverture : dispositions à obstacles exercées = ${[...cover.obstacleLayouts].join(', ')}`);
  assert.ok(cover.bossSteps > 0, 'couverture : un boss doit avoir été combattu');
  assert.ok(cover.heals > 0, 'couverture : un soin doit avoir eu lieu (le plafond des PV est-il testé ?)');
});

test('(k bis) invariants stricts — entrées aléatoires, départ dans chaque type de salle (étages 2 à 6)', () => {
  const cover = newCover();
  for (const startFloor of RANDOM_START_FLOORS) {
    for (const seed of RANDOM_SEEDS) {
      const game = createGame({ seed, startFloor });
      const rng = makeRng(seed * 7919 + startFloor);
      for (let i = 0; i < RANDOM_STEPS; i++) {
        playStep(game, randomInput(rng));
        checkStrict(game, `aléatoire graine ${seed} départ ${startFloor} tick ${game.tick}`, cover);
      }
    }
  }
  assert.ok(cover.obstacleLayouts.size >= MIN_OBSTACLE_LAYOUTS, `couverture : dispositions à obstacles exercées = ${[...cover.obstacleLayouts].join(', ')}`);
  assert.ok(cover.bossSteps > 0, 'couverture : la salle du boss doit avoir été exercée');
});

// ---------------------------------------------------------------- (l) oracle de jouabilité honnête

test("(l) le run qui bat la section 1 a réellement tué le boss (l'oracle ne passe pas sur une salle vide)", () => {
  const bossKinds = new Set(Object.keys(createGame().tuning.boss));
  const outcomes = [];
  for (const seed of PLAYABILITY_SEEDS) {
    const r = runEpisode('skilled', seed, { floors: SECTION_FLOORS, minutes: PLAYABILITY_MINUTES });
    outcomes.push(`graine ${seed} : ${r.outcome}, étage ${r.floorReached}`);
    if (!r.sectionCleared) continue;
    const bossKills = r.killTimes.filter((k) => bossKinds.has(k.kind));
    assert.equal(bossKills.length, 1, `graine ${seed} : section battue sans tuer le boss (${JSON.stringify(r.killTimes.map((k) => k.kind))})`);
    assert.ok(r.bossFightSeconds > 0, `graine ${seed} : durée du combat de boss absente`);
    return;
  }
  assert.fail(`aucune graine ne bat la section 1 :\n  ${outcomes.join('\n  ')}`);
});

// ---------------------------------------------------------------- (m) récompense atteignable

function clearRoom(game) {
  game.enemies.length = 0;
  game.spawns.length = 0;
  game.room.waveIndex = game.room.waves.length - 1;
  stepGame(game, emptyInput());
  game.events.length = 0;
}

/** Recherche en largeur sur une grille : le héros peut-il MARCHER jusqu'à toucher l'objet ? */
function pathToInteract(game) {
  const room = game.room;
  const p = game.player;
  const it = room.interact;
  const cols = Math.ceil(room.w / PATH_CELL);
  const rows = Math.ceil(room.h / PATH_CELL);
  const free = (c, r) => !pointBlocked(room, (c + 0.5) * PATH_CELL, (r + 0.5) * PATH_CELL, p.r);
  const touches = (c, r) => Math.hypot((c + 0.5) * PATH_CELL - it.x, (r + 0.5) * PATH_CELL - it.y) < p.r + it.r;
  const start = [Math.floor(p.x / PATH_CELL), Math.floor(p.y / PATH_CELL)];
  const seen = new Uint8Array(cols * rows);
  const queue = [start];
  seen[start[1] * cols + start[0]] = 1;
  for (let head = 0; head < queue.length; head++) {
    const [c, r] = queue[head];
    if (touches(c, r)) return true;
    for (const [dc, dr] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const nc = c + dc;
      const nr = r + dr;
      if (nc < 0 || nr < 0 || nc >= cols || nr >= rows || seen[nr * cols + nc] || !free(nc, nr)) continue;
      seen[nr * cols + nc] = 1;
      queue.push([nc, nr]);
    }
  }
  return false;
}

function layoutSample(seed, startFloor) {
  const game = createGame({ seed, startFloor });
  const layout = game.room.layout;
  clearRoom(game);
  assert.ok(game.room.interact, `graine ${seed} étage ${startFloor} (${layout}) : la salle nettoyée doit poser sa récompense`);
  return { layout, seed, reachable: pathToInteract(game), at: [game.room.interact.x, game.room.interact.y] };
}

test("(m) chaque disposition (boss compris) est couverte et sa récompense est atteignable À PIED depuis l'entrée", () => {
  const seen = new Map();
  for (let seed = 1; seed <= LAYOUT_SEED_LIMIT && seen.size < EXPECTED_LAYOUTS.length - 1; seed++) {
    const layout = createGame({ seed, startFloor: LAYOUT_FLOOR }).room.layout;
    if (!seen.has(layout)) seen.set(layout, layoutSample(seed, LAYOUT_FLOOR));
  }
  seen.set('boss', layoutSample(1, BOSS_FLOOR));
  const missing = EXPECTED_LAYOUTS.filter((l) => !seen.has(l));
  assert.deepEqual(missing, [], `dispositions jamais tirées (non testées) : ${missing.join(', ')}`);
  const blocked = [...seen.values()].filter((v) => !v.reachable).map((v) => `${v.layout} (graine ${v.seed}, objet en ${v.at.map(Math.round).join(', ')})`);
  assert.deepEqual(blocked, [], `récompense hors d'atteinte => portes jamais ouvertes : ${blocked.join(' ; ')}`);
});

// ---------------------------------------------------------------- (n) les bots ne trichent pas

/** Proxy récursif qui note chaque chemin LU et refuse toute écriture (identité des objets conservée). */
function observer(reads) {
  const cache = new WeakMap();
  const wrap = (obj, path) => {
    if (obj === null || typeof obj !== 'object' || ArrayBuffer.isView(obj)) return obj;
    if (cache.has(obj)) return cache.get(obj);
    const proxy = new Proxy(obj, {
      get(target, key, receiver) {
        const value = Reflect.get(target, key, receiver);
        if (typeof key === 'symbol' || typeof value === 'function') return value;
        const sub = Array.isArray(target) && /^\d+$/.test(key) ? `${path}[]` : `${path}.${key}`;
        reads.add(sub.replace(/^game\.(enemies|hazards|projectiles|spawns|pickups)\[\]/, '$1[]'));
        return wrap(value, sub);
      },
      set(target, key) {
        throw new Error(`le bot ÉCRIT dans l'état de la partie : ${path}.${String(key)}`);
      },
      deleteProperty(target, key) {
        throw new Error(`le bot SUPPRIME un champ de l'état : ${path}.${String(key)}`);
      },
    });
    cache.set(obj, proxy);
    return proxy;
  };
  return (game) => wrap(game, 'game');
}

test("(n) les bots n'écrivent jamais dans la partie et ne lisent ni le RNG ni les compteurs cachés", () => {
  for (const name of Object.keys(POLICIES)) {
    const reads = new Set();
    const game = createGame({ seed: 4 });
    const view = observer(reads)(game);
    const mem = {};
    for (let i = 0; i < AUDIT_STEPS; i++) playStep(game, POLICIES[name](view, mem));
    const cheats = [...reads].filter((r) => FORBIDDEN_READS.some((f) => r === f || r.startsWith(`${f}.`)));
    assert.deepEqual(cheats, [], `${name} lit des champs invisibles pour un joueur : ${cheats.join(', ')}`);
    assert.ok(reads.has('enemies[].x'), `${name} : l'audit doit avoir observé des lectures d'ennemis`);
  }
});
