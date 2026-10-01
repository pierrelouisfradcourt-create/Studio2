// Règles issues de la revue « game feel » et lisibilité (2026-10-01). Fichier CRÉÉ dans cette
// passe : chaque test fige un correctif. Les valeurs sont lues dans le tuning.
// Lancement : node --test tests/*.test.mjs

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createGame, stepGame, emptyInput, DT } from '../src/sim/game.mjs';
import { damageEnemy } from '../src/sim/combat.mjs';

const ticks = (seconds) => Math.ceil(seconds / DT);
const input = (over = {}) => ({ ...emptyInput(), ...over });

/** Partie vide (aucune vague), héros au centre. */
function sandbox() {
  const g = createGame({ seed: 11 });
  g.spawns.length = 0;
  g.enemies.length = 0;
  g.room.waves = [];
  g.room.waveIndex = 0;
  g.room.obstacles = [];
  g.room.cleared = true;
  g.room.interact = null;
  g.room.doors = [];
  g.player.x = g.room.w / 2;
  g.player.y = g.room.h / 2;
  g.events.length = 0;
  return g;
}

/** Attaque maintenue jusqu'au premier tick du finisher (coup 3), puis relâchée. */
function toFinisher(g) {
  for (let i = 0; i < 240; i++) {
    stepGame(g, input({ attack: true }));
    const started = g.events.some((ev) => ev.type === 'attackStart' && ev.index === 2);
    g.events.length = 0;
    if (started) return;
  }
  assert.fail('le finisher n\'a jamais démarré');
}

/** Durée pendant laquelle le finisher interdit le coup suivant. */
function finisherLock(t) {
  const f = t.combo[2];
  return f.startup + f.active + f.recovery * t.comboCancelFrom.hits[2];
}

test('tampon : un tap d\'attaque au tout début du finisher fait partir le coup suivant', () => {
  const g = sandbox();
  toFinisher(g);
  stepGame(g, input({ attackPressed: true }));
  let next = -1;
  const limit = ticks(finisherLock(g.tuning)) + 3;
  for (let i = 1; i <= limit && next < 0; i++) {
    stepGame(g, input());
    if (g.events.some((ev) => ev.type === 'attackStart')) next = i;
    g.events.length = 0;
  }
  assert.ok(next > 0, `le tap a été perdu (aucune attaque en ${limit} ticks)`);
});

test('tampon : une Lance tapée au début du finisher part pendant sa récupération', () => {
  const g = sandbox();
  toFinisher(g);
  stepGame(g, input({ skillPressed: true, skillAimX: 1, skillAimY: 0 }));
  let cast = false;
  const f = g.tuning.combo[2];
  for (let i = 0; i < ticks(f.startup + f.active + f.recovery) + 3 && !cast; i++) {
    stepGame(g, input());
    cast = g.events.some((ev) => ev.type === 'castStart');
    g.events.length = 0;
  }
  assert.ok(cast, 'la Lance a été perdue');
});

/** Gardien seul, en début de pattern donné. */
function bossIn(pattern, phase = 1) {
  const g = createGame({ seed: 3, startFloor: 6 });
  g.spawns.length = 0;
  for (let i = 0; i < 200 && !g.enemies.some((e) => e.boss && !(e.spawnT > 0)); i++) stepGame(g, input());
  const boss = g.enemies.find((e) => e.boss);
  assert.ok(boss, 'Gardien présent');
  g.enemies = [boss];
  boss.phase = phase;
  boss.state = pattern;
  boss.stateTime = 0;
  boss.patternStep = 0;
  boss.patternT = 0;
  boss.tele = null;
  // Héros loin et invulnérable : on observe le boss.
  g.player.x = boss.x + 400;
  g.player.y = boss.y;
  g.player.iframes = 99;
  g.events.length = 0;
  return { g, boss };
}

test('anneau du Gardien : le cercle d\'alerte reste affiché entre les vagues', () => {
  const { g, boss } = bossIn('ring');
  const r = g.tuning.boss[boss.kind].ring;
  let waves = 0;
  let missing = 0;
  for (let i = 0; i < 600 && boss.state === 'ring'; i++) {
    stepGame(g, input());
    const fired = g.events.filter((ev) => ev.type === 'enemyAttack' && ev.enemy === 'bossRing').length;
    g.events.length = 0;
    waves += fired;
    // Après la 1re vague et tant qu'une autre doit partir : l'alerte est visible.
    if (waves >= 1 && boss.state === 'ring' && !fired && !(boss.tele && boss.tele.shape === 'circle' && boss.tele.r === r.teleRadius)) missing++;
  }
  assert.equal(waves, r.waves, 'toutes les vagues de la phase 1 sont parties');
  assert.equal(missing, 0, `${missing} ticks sans alerte entre deux vagues`);
});

test('invocation du Gardien : alerte marquée inoffensive (le rouge reste « ça fait mal »)', () => {
  const { g, boss } = bossIn('summon', 3);
  stepGame(g, input());
  assert.ok(boss.tele, 'alerte affichée');
  assert.equal(boss.tele.harmless, true);
});

test('gel d\'impact sur le Gardien : plafonné par le tuning, le finisher pèse plus qu\'un coup léger', () => {
  const { g, boss } = bossIn('rest');
  const t = g.tuning;
  const cap = t.boss[boss.kind].hitstopCap;
  boss.invuln = 0;
  g.hitstop = 0;
  damageEnemy(g, boss, { kind: 'melee', amount: 1, dirX: 1, dirY: 0, hitstop: t.combo[0].hitstop });
  const light = g.hitstop;
  g.hitstop = 0;
  g.hitstopBank = 1;
  damageEnemy(g, boss, { kind: 'melee', amount: 1, dirX: 1, dirY: 0, hitstop: t.combo[2].hitstop });
  const heavy = g.hitstop;
  assert.ok(heavy <= cap + 1e-9, `gel ${heavy} > plafond ${cap}`);
  assert.ok(heavy > light, `finisher ${heavy} vs coup léger ${light}`);
});
