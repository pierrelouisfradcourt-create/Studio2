// Tests de propriétés de la simulation — indépendants des valeurs de tuning : ils vérifient
// des lois (déterminisme, invariants physiques, invulnérabilité, pause des menus,
// jouabilité) et non des nombres. Lancer : node --test tests/properties.test.mjs
//
// Les entrées « aléatoires » viennent d'un générateur seedé LOCAL au test (jamais du RNG de
// la partie, jamais de Math.random) : un échec se rejoue à l'identique.

import test from 'node:test';
import assert from 'node:assert/strict';
import { createGame, stepGame, emptyInput, applyCommand, stateHash } from '../src/sim/game.mjs';
import { maxDashCharges } from '../src/sim/player.mjs';
import { spawnProjectile } from '../src/sim/projectiles.mjs';
import { pointBlocked } from '../src/sim/physics.mjs';
import { POLICIES, resolveChoice } from '../tools/bots.mjs';
import { runEpisode } from '../tools/playtest.mjs';

const SEEDS = [1, 2, 3, 4, 5];
const DETERMINISM_STEPS = 3000;
const INVARIANT_STEPS = 6000;
const WALL_EPS = 1e-6; // u : arrondi flottant toléré sur la position contre un mur
const OBSTACLE_TOLERANCE = 1; // u : un centre d'ennemi ne doit pas être plus profond que ça
const MAX_EVENTS_PER_STEP = 500; // une image ne doit jamais produire d'avalanche d'événements
const MAX_CHOICE_ROUNDS = 8;
const CHOICE_PAUSE_STEPS = 120;
const CHOICE_SEARCH_STEPS = 20000;
const PLAYABILITY_SEEDS = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
const SECTION_FLOORS = 18; // gate Pierre 2026-10-01 (spec V2) : section de 18 étages
const SECTION_MINUTES = 30;
const PROBE_DAMAGE = 30; // dégâts du projectile témoin (test d'i-frames)
const IFRAME_PROBE_STEPS = 240;
const REACH_SAMPLES = 32;
const LAYOUT_SEED_LIMIT = 300;
const LAYOUT_FLOOR = 2; // premier étage où la disposition est tirée au hasard

// ---------------------------------------------------------------- outillage

/** Générateur seedé local (mulberry32). */
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

/** InputFrame pseudo-aléatoire : déplacement analogique, visée, et tous les boutons. */
function randomInput(rng) {
  const input = emptyInput();
  const a = rng() * Math.PI * 2;
  const m = rng() < 0.15 ? 0 : rng();
  input.moveX = Math.cos(a) * m;
  input.moveY = Math.sin(a) * m;
  if (rng() < 0.3) {
    input.aimX = rng() * 2 - 1;
    input.aimY = rng() * 2 - 1;
  }
  input.attack = rng() < 0.5;
  input.attackPressed = rng() < 0.1;
  input.dashPressed = rng() < 0.04;
  input.skillPressed = rng() < 0.02;
  input.skillAimX = rng() * 2 - 1;
  input.skillAimY = rng() * 2 - 1;
  input.gadgetPressed = rng() < 0.005;
  input.superPressed = rng() < 0.01;
  return input;
}

function settleChoice(game) {
  for (let i = 0; i < MAX_CHOICE_ROUNDS && game.mode === 'choice'; i++) resolveChoice(game, 'skilled');
  assert.notEqual(game.mode, 'choice', 'le menu ouvert doit pouvoir être résolu');
}

/**
 * Fait avancer la partie `steps` pas. `nextInput(game)` fournit l'InputFrame ; les menus sont
 * résolus, la mort mène à une reprise (respawn) ; `check(game, events)` est appelé après
 * chaque pas, avant que l'appelant ne vide les événements.
 */
function drive(game, steps, nextInput, check) {
  for (let i = 0; i < steps; i++) {
    if (game.mode === 'choice') settleChoice(game);
    if (game.mode === 'dead') applyCommand(game, { type: 'respawn' });
    if (game.mode !== 'play') break;
    stepGame(game, nextInput(game));
    if (check) check(game, game.events);
    game.events.length = 0;
  }
}

/**
 * Empreinte COMPLÈTE : stateHash + états des RNG + build + salle. stateHash seul ne suffit
 * pas à distinguer deux graines : il ignore les RNG, et un héros qui marche au hasard contre
 * les mêmes murs, salle vidée, converge vers la même position (constaté : graines 1 et 4).
 */
function fullFingerprint(game) {
  const r = game.rng;
  const run = game.run;
  return [
    stateHash(game), r.gen.s, r.combat.s, r.ai.s, game.time.toFixed(6), game.room.layout,
    run.boons.map((b) => `${b.id}:${b.rarity}:${b.level}`).join(','),
    Object.values(run.items).map((it) => it?.id ?? '-').join(','),
  ].join('|');
}

function runRandom(seed, inputs) {
  const game = createGame({ seed });
  let i = 0;
  drive(game, inputs.length, () => inputs[i++]);
  return { hash: stateHash(game), full: fullFingerprint(game) };
}

function finite(...values) {
  return values.every((v) => Number.isFinite(v));
}

// ---------------------------------------------------------------- invariants

function checkPlayer(game, where) {
  const p = game.player;
  const room = game.room;
  assert.ok(finite(p.x, p.y, p.vx, p.vy), `${where} : position/vitesse du héros non finie`);
  const lo = room.pad + p.r - WALL_EPS;
  assert.ok(p.x >= lo && p.x <= room.w - lo && p.y >= lo && p.y <= room.h - lo, `${where} : héros hors des murs (${p.x}, ${p.y})`);
  assert.ok(p.hp >= 0 && p.hp <= p.maxHp, `${where} : PV hors bornes (${p.hp} / ${p.maxHp})`);
  const maxDash = maxDashCharges(game);
  assert.ok(p.dashCharges >= 0 && p.dashCharges <= maxDash, `${where} : charges de dash hors bornes (${p.dashCharges} / ${maxDash})`);
  assert.ok(p.superCharge >= 0 && p.superCharge <= 1, `${where} : jauge de Super hors [0, 1] (${p.superCharge})`);
}

function insideObstacle(room, x, y, tol) {
  return room.obstacles.find((o) => x > o.x0 + tol && x < o.x1 - tol && y > o.y0 + tol && y < o.y1 - tol);
}

function checkEnemies(game, where) {
  for (const e of game.enemies) {
    if (e.dead) continue;
    assert.ok(finite(e.x, e.y, e.vx, e.vy, e.kvx, e.kvy), `${where} : ${e.kind}#${e.id} position/vitesse non finie`);
    const o = insideObstacle(game.room, e.x, e.y, OBSTACLE_TOLERANCE);
    assert.ok(!o, `${where} : ${e.kind}#${e.id} vivant DANS un obstacle (${e.x.toFixed(1)}, ${e.y.toFixed(1)}) ${JSON.stringify(o)}`);
  }
}

/** Vérificateur d'invariants ; `cover` compte ce que le test a réellement exercé. */
function invariantChecker(label, cover) {
  return (game, events) => {
    const where = `${label} tick ${game.tick} étage ${game.run.floor}`;
    checkPlayer(game, where);
    checkEnemies(game, where);
    assert.ok(events.length <= MAX_EVENTS_PER_STEP, `${where} : ${events.length} événements en une image`);
    cover.enemySteps += game.enemies.some((e) => !e.dead) ? 1 : 0;
    cover.maxFloor = Math.max(cover.maxFloor, game.run.floor);
  };
}

// ---------------------------------------------------------------- (a) déterminisme

test('(a) déterminisme : même graine + mêmes entrées => même état ; graines différentes => états différents', () => {
  const rng = makeRng(0xd666);
  const inputs = Array.from({ length: DETERMINISM_STEPS }, () => randomInput(rng));
  const states = SEEDS.map((seed) => {
    const a = runRandom(seed, inputs);
    const b = runRandom(seed, inputs);
    assert.equal(a.hash, b.hash, `graine ${seed} : même graine, mêmes entrées, stateHash différent`);
    assert.equal(a.full, b.full, `graine ${seed} : même graine, mêmes entrées, état complet différent`);
    return a.full;
  });
  assert.equal(new Set(states).size, SEEDS.length, `des graines différentes donnent le même état :\n  ${states.join('\n  ')}`);
});

test('(a bis) déterminisme du bot skilled : même graine => même partie', () => {
  const run = () => {
    const game = createGame({ seed: 11 });
    const mem = {};
    drive(game, DETERMINISM_STEPS, (g) => POLICIES.skilled(g, mem));
    return stateHash(game);
  };
  assert.equal(run(), run());
});

// ---------------------------------------------------------------- (b) invariants

test('(b) invariants sur 5 graines × 6000 pas — bot skilled', () => {
  const cover = { enemySteps: 0, maxFloor: 0 };
  for (const seed of SEEDS) {
    const game = createGame({ seed });
    const mem = {};
    drive(game, INVARIANT_STEPS, (g) => POLICIES.skilled(g, mem), invariantChecker(`skilled graine ${seed}`, cover));
  }
  assert.ok(cover.enemySteps > 0, 'couverture : des ennemis doivent avoir été présents');
  assert.ok(cover.maxFloor > 1, 'couverture : le bot doit avoir changé de salle');
});

test('(b) invariants sur 5 graines × 6000 pas — entrées aléatoires', () => {
  const cover = { enemySteps: 0, maxFloor: 0 };
  for (const seed of SEEDS) {
    const game = createGame({ seed });
    const rng = makeRng(seed * 7919);
    drive(game, INVARIANT_STEPS, () => randomInput(rng), invariantChecker(`aléatoire graine ${seed}`, cover));
  }
  assert.ok(cover.enemySteps > 0, 'couverture : des ennemis doivent avoir été présents');
});

// ---------------------------------------------------------------- (c) i-frames

/** Salle vidée de ses ennemis et de ses vagues : seuls nos projectiles témoins frappent. */
function quietGame(seed) {
  const game = createGame({ seed });
  game.enemies.length = 0;
  game.spawns.length = 0;
  game.room.waves = [];
  return game;
}

/** Pose un projectile ennemi immobile sur le héros (le coup part via la sim). */
function probeHit(game) {
  const p = game.player;
  spawnProjectile(game, { owner: 'enemy', kind: 'probe', x: p.x, y: p.y, vx: 0, vy: 0, r: 4, damage: PROBE_DAMAGE, range: 1e9 });
}

test('(c) pendant les i-frames (dash puis coup reçu), aucun coup ne retire de PV', () => {
  const game = quietGame(7);
  const p = game.player;
  const dash = emptyInput();
  dash.dashPressed = true;
  dash.moveX = 1;
  stepGame(game, dash);
  assert.equal(p.state, 'dash', 'le dash doit partir');
  let protectedHits = 0;
  let landed = 0;
  for (let i = 0; i < IFRAME_PROBE_STEPS; i++) {
    const hpBefore = p.hp;
    // i-frames encore actives APRÈS le décompte de cette image (sinon le coup est légitime).
    const shielded = p.iframes > 1 / 60 + 1e-9 && game.hitstop <= 0;
    probeHit(game);
    stepGame(game, emptyInput());
    game.projectiles.length = 0;
    if (shielded) {
      assert.equal(p.hp, hpBefore, `tick ${game.tick} : PV retirés pendant les i-frames (${p.iframes.toFixed(3)} s restantes)`);
      protectedHits++;
    } else if (p.hp < hpBefore) {
      landed++;
      // Un coup qui porte ouvre des i-frames : la propriété doit tenir aussi pour elles.
      assert.ok(p.iframes > 0, 'un coup reçu doit accorder des i-frames');
    }
    game.events.length = 0;
    if (p.state === 'dead') break;
  }
  assert.ok(protectedHits > 0, 'le test doit avoir provoqué des coups pendant des i-frames');
  assert.ok(landed > 0, 'témoin : hors i-frames, le projectile doit porter');
});

// ---------------------------------------------------------------- (d) pause des menus

test("(d) en mode 'choice', stepGame ne fait pas avancer le temps", () => {
  const game = createGame({ seed: 3 });
  const mem = {};
  for (let i = 0; i < CHOICE_SEARCH_STEPS && game.mode === 'play'; i++) {
    stepGame(game, POLICIES.skilled(game, mem));
    game.events.length = 0;
  }
  assert.equal(game.mode, 'choice', 'le bot doit atteindre un menu (récompense de salle)');
  const tick = game.tick;
  const time = game.time;
  const hash = stateHash(game);
  const rng = makeRng(99);
  for (let i = 0; i < CHOICE_PAUSE_STEPS; i++) stepGame(game, randomInput(rng));
  assert.equal(game.tick, tick, 'game.tick a avancé pendant un menu');
  assert.equal(game.time, time, 'game.time a avancé pendant un menu');
  assert.equal(stateHash(game), hash, "l'état a changé pendant un menu");
});

// ---------------------------------------------------------------- (e) jouabilité

test('(e) oracle de jouabilité : le bot skilled bat la section 1 (étage 19) sur au moins une graine', () => {
  const outcomes = [];
  for (const seed of PLAYABILITY_SEEDS) {
    const r = runEpisode('skilled', seed, { floors: SECTION_FLOORS, minutes: SECTION_MINUTES });
    outcomes.push(`graine ${seed} : ${r.outcome}, étage ${r.floorReached}`);
    if (r.floorReached >= SECTION_FLOORS + 1) return;
  }
  assert.fail(`aucune graine ne bat la section 1 :\n  ${outcomes.join('\n  ')}`);
});

// ---------------------------------------------------------------- (f) accessibilité de la récompense

/** Vide la salle et la termine via la sim : l'objet de récompense apparaît. */
function clearRoom(game) {
  game.enemies.length = 0;
  game.spawns.length = 0;
  game.room.waveIndex = game.room.waves.length - 1;
  stepGame(game, emptyInput());
  game.events.length = 0;
}

/** Le héros peut-il se placer assez près de l'objet pour le toucher sans être dans un obstacle ? */
function interactReachable(game) {
  const it = game.room.interact;
  const p = game.player;
  const reach = p.r + it.r;
  for (const f of [0, 0.5, 0.95]) {
    for (let k = 0; k < REACH_SAMPLES; k++) {
      const a = (k / REACH_SAMPLES) * Math.PI * 2;
      const x = it.x + Math.cos(a) * reach * f;
      const y = it.y + Math.sin(a) * reach * f;
      if (!pointBlocked(game.room, x, y, p.r)) return true;
    }
  }
  return false;
}

test("(f) l'objet de récompense d'une salle nettoyée est atteignable, pour chaque disposition", () => {
  const seen = new Map();
  for (let seed = 1; seed <= LAYOUT_SEED_LIMIT; seed++) {
    const game = createGame({ seed, startFloor: LAYOUT_FLOOR });
    const layout = game.room.layout;
    if (seen.has(layout)) continue;
    clearRoom(game);
    assert.ok(game.room.interact, `graine ${seed} : la salle nettoyée doit poser sa récompense`);
    seen.set(layout, { seed, reachable: interactReachable(game), at: [game.room.interact.x, game.room.interact.y] });
  }
  const blocked = [...seen].filter(([, v]) => !v.reachable).map(([layout, v]) => `${layout} (graine ${v.seed}, objet en ${v.at.map(Math.round).join(', ')})`);
  assert.deepEqual(blocked, [], `récompense inaccessible => portes jamais ouvertes (blocage) : ${blocked.join(' ; ')}`);
});
