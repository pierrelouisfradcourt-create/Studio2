// Tests issus de la relecture adversariale du lot BESTIAIRE (V2) : un test par défaut corrigé.
//
//   - un tireur (Archer, Pyromancienne) attaque encore quand le héros est derrière un obstacle ;
//   - frapper une invocation ne rapporte pas d'or (pas de ferme tant que l'invocateur vit) ;
//   - salle nettoyée : plus aucun coup ennemi en attente ne part ;
//   - une brûlure éteinte repart de zéro (la suivante brûle à sa propre intensité).
// Le champion des salles d'élite (bestiaire de l'étage) est dans v2_etages_relecture.test.mjs.
// Lancement : node --test tests/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createGame, stepGame, emptyInput, DT } from '../src/sim/game.mjs';
import { createEnemy } from '../src/sim/enemies.mjs';
import { damageEnemy, spawnHazard } from '../src/sim/combat.mjs';
import { spawnProjectile } from '../src/sim/projectiles.mjs';
import { lineOfSight } from '../src/sim/physics.mjs';

const ticks = (seconds) => Math.ceil(seconds / DT);

/** Avance de n pas, rend les événements. */
function run(g, n) {
  const evs = [];
  for (let i = 0; i < n; i++) {
    stepGame(g, emptyInput());
    evs.push(...g.events);
    g.events.length = 0;
  }
  return evs;
}

/** Salle réelle vidée de ses vagues (obstacles gardés), héros increvable. */
function emptied(seed, floor) {
  const g = createGame({ seed, startFloor: floor });
  g.enemies.length = 0;
  g.spawns.length = 0;
  g.room.waves = [];
  g.room.kind = 'event'; // la salle ne se « nettoie » pas pendant l'essai
  g.events.length = 0;
  g.player.maxHp = 1e6;
  g.player.hp = 1e6;
  return g;
}

// ---------------------------------------------------------------- tireurs derrière un obstacle

test('tireurs : héros immobile derrière un obstacle, l\'Archer et la Pyromancienne finissent par attaquer', () => {
  for (const kind of ['archer', 'pyromancer']) {
    // Disposition « lanes » (graine 77, étage 150) : héros collé sous le mur, tireur de l'autre côté.
    const g = emptied(77, 150);
    const p = g.player;
    const o = g.room.obstacles[1];
    assert.ok(o, 'la salle a ses obstacles');
    p.x = (o.x0 + o.x1) / 2 + 60;
    p.y = o.y1 + p.r;
    const e = createEnemy(g, kind, p.x - 100, o.y0 - 190, { spawnT: 0 });
    assert.equal(lineOfSight(g.room, e.x, e.y, p.x, p.y), false, `${kind} : pas de ligne de vue au départ`);
    const attacks = run(g, ticks(30)).filter((ev) => ev.type === 'enemyAttack').length;
    assert.ok(attacks > 0, `${kind} : ${attacks} attaque en 30 s (il vibrait sur place sans jamais tirer)`);
  }
});

// ---------------------------------------------------------------- invocations : pas de ferme

test('invocations : « Main avide » ne rapporte pas d\'or sur une invocation, mais bien sur un ennemi ordinaire', () => {
  const g = emptied(5, 3);
  g.tuning.combat.critChance = 0;
  g.player.procs.push({ on: 'hit', sources: ['melee'], effect: 'gold', chance: 1, value: 1 });
  const summoned = createEnemy(g, 'imp', g.player.x + 200, g.player.y, { spawnT: 0, summoned: true });
  const ordinary = createEnemy(g, 'imp', g.player.x - 200, g.player.y, { spawnT: 0 });
  for (const e of [summoned, ordinary]) {
    e.hp = 1e6;
    e.maxHp = 1e6;
  }
  const gold0 = g.run.gold;
  for (let i = 0; i < 20; i++) damageEnemy(g, summoned, { kind: 'melee', amount: 5, canCrit: false });
  assert.equal(g.run.gold, gold0, 'invocation : aucun or');
  damageEnemy(g, ordinary, { kind: 'melee', amount: 5, canCrit: false });
  assert.equal(g.run.gold, gold0 + 1, 'ennemi ordinaire : la bénédiction paie');
});

// ---------------------------------------------------------------- salle nettoyée

test('salle nettoyée : les zones en attente et les projectiles ennemis en vol sont annulés', () => {
  const g = createGame({ seed: 5, startFloor: 2 });
  const p = g.player;
  assert.ok(g.room.kind === 'combat' || g.room.kind === 'elite');
  // Un souffle d'élite ardent sous les pieds du héros (0,7 s de télégraphe) et une flèche vers lui.
  const hz = spawnHazard(g, { shape: 'circle', x: p.x, y: p.y, r: 110, delay: 0.7, damage: 18, hitsPlayer: true, hitsEnemies: false, kind: 'fireBlast', sourceId: 0 });
  const arrow = spawnProjectile(g, { owner: 'enemy', kind: 'arrow', x: p.x + 300, y: p.y, vx: -200, vy: 0, r: 7, damage: 10, range: 700, sourceId: 0 });
  // Le dernier ennemi tombe : la salle est nettoyée.
  g.room.waveIndex = g.room.waves.length - 1;
  g.spawns.length = 0;
  for (const e of g.enemies) e.dead = true;
  const hp0 = p.hp;
  for (let i = 0; i < 60 && !g.room.cleared; i++) stepGame(g, emptyInput());
  assert.equal(g.room.cleared, true);
  assert.equal(hz.done, true, 'la zone en attente est annulée');
  assert.equal(arrow.dead, true, 'la flèche en vol est retirée');
  const evs = run(g, ticks(2));
  assert.equal(evs.filter((ev) => ev.type === 'playerHurt').length, 0, 'plus aucun coup après « salle nettoyée »');
  assert.equal(p.hp, hp0);
});

// ---------------------------------------------------------------- brûlure

test('brûlure : une fois éteinte, son intensité repart de zéro', () => {
  const g = emptied(5, 3);
  const e = createEnemy(g, 'brute', g.player.x + 300, g.player.y, { spawnT: 0 });
  e.cooldown = 999;
  e.hp = 1e6;
  e.maxHp = 1e6;
  e.burn = 0.5;
  e.burnDps = 40;
  run(g, ticks(1));
  assert.ok(e.burn <= 0, 'la brûlure forte est éteinte');
  assert.equal(e.burnDps, 0, 'son intensité ne reste pas en mémoire');
  // Une brûlure faible posée ensuite (même règle que combat.mjs : le max des deux) brûle à 6/s.
  e.burn = 2;
  e.burnDps = Math.max(e.burnDps, 6);
  const hp0 = e.hp;
  run(g, ticks(2.2));
  const lost = hp0 - e.hp;
  // 12 PV nominaux ; chaque tick de 0,25 s (1,5 PV) est arrondi à l'entier : 16 au plus.
  assert.ok(lost >= 9 && lost <= 20, `2 s à 6/s : ${lost} PV perdus (40/s en aurait pris ~80)`);
});
