// Tests du lot CLASSES (V2, D11) : les deux défauts relevés par la relecture adversariale.
//
//   - GARDE : un ennemi qui sort d'un étourdissement n'est pas ré-étourdi par un coup d'arme
//     pendant combat.stunGuard. Sans elle, la Hache et le Maillet maintenus sur place
//     étourdissaient en boucle : plus aucun dégât de mêlée.
//   - CHASSERESSE : on ne distance pas la mêlée en tirant ; pour fuir, il faut cesser de tirer
//     ou dasher (le dash reste la fuite).
// La mesure sur une section entière (bots, 20 graines) est dans tools/classes.mjs.
// Lancement : node --test tests/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createGame, stepGame, emptyInput, DT } from '../src/sim/game.mjs';
import { createTuning } from '../src/sim/config.mjs';
import { createEnemy } from '../src/sim/enemies.mjs';
import { damageEnemy } from '../src/sim/combat.mjs';
import { kitProfile, holdHits, allKits, HOLD_PACKS, MIN_HOLD_HITS } from '../tools/classes.mjs';

const T = createTuning();
const ticks = (seconds) => Math.ceil(seconds / DT);

/** Partie de test : salle vidée (aucune vague, aucun obstacle), héros au centre. */
function sandbox(classId, weaponType, tuning) {
  const g = createGame({ seed: 11, meta: kitProfile(T, classId, weaponType), tuning });
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
  g.tuning.combat.critChance = 0;
  g.events.length = 0;
  return g;
}

function run(g, n, over = {}) {
  for (let i = 0; i < n; i++) {
    stepGame(g, { ...emptyInput(), ...over });
    g.events.length = 0;
  }
}

/** Mannequin loin du héros : ne riposte pas, ne meurt pas. */
function dummy(g, kind = 'brute') {
  const e = createEnemy(g, kind, g.player.x + 300, g.player.y, { spawnT: 0 });
  e.cooldown = 999;
  e.hp = 5000;
  e.maxHp = 5000;
  return e;
}

/** Étourdit le mannequin par une source comptée, puis attend la fin de l'étourdissement. */
function stunThenRecover(g, e, stun = 0.2) {
  damageEnemy(g, e, { kind: 'gadget', amount: 1, stun, canCrit: false });
  assert.ok(e.stun > 0, 'étourdi');
  run(g, ticks(stun) + 1);
  assert.ok(e.stun <= 0, 'l\'étourdissement est fini');
}

// ---------------------------------------------------------------- garde

test('garde : un ennemi qui sort d\'un étourdissement n\'est pas ré-étourdi par un coup d\'arme, mais il est blessé et repoussé', () => {
  const g = sandbox('bourreau', 'hache');
  const e = dummy(g);
  assert.equal(e.guard, 0, 'aucune garde tant qu\'il n\'a pas été étourdi');
  stunThenRecover(g, e);
  assert.ok(e.guard > 0 && e.guard <= g.tuning.combat.stunGuard, 'la garde commence à la fin de l\'étourdissement');
  for (const kind of g.tuning.combat.stunGuardSources) {
    const hp = e.hp;
    e.kvx = 0;
    e.kvy = 0;
    damageEnemy(g, e, { kind, amount: 20, stun: 0.7, knockback: 800, dirX: 1, dirY: 0, canCrit: false });
    assert.ok(e.stun <= 0, `${kind} : pas de ré-étourdissement pendant la garde`);
    assert.notEqual(e.state, 'stunned', `${kind} : il garde son état`);
    assert.ok(e.hp < hp, `${kind} : le coup blesse`);
    assert.ok(e.kvx > 0, `${kind} : le coup repousse`);
  }
});

test('garde : compétence, gadget, Super et mur étourdissent malgré la garde (ressources comptées, placement)', () => {
  for (const kind of ['skill', 'gadget', 'super', 'wall']) {
    const g = sandbox('bourreau', 'hache');
    const e = dummy(g);
    stunThenRecover(g, e);
    assert.ok(!g.tuning.combat.stunGuardSources.includes(kind), `${kind} n'est pas une source gardée`);
    damageEnemy(g, e, { kind, amount: 1, stun: 0.5, canCrit: false });
    assert.ok(e.stun > 0, `${kind} étourdit un ennemi en garde`);
  }
});

test('garde : elle dure combat.stunGuard, puis un coup d\'arme étourdit de nouveau', () => {
  const g = sandbox('bourreau', 'hache');
  const e = dummy(g);
  stunThenRecover(g, e);
  run(g, ticks(g.tuning.combat.stunGuard * 0.8));
  assert.ok(e.guard > 0, 'encore en garde à 80 % de sa durée');
  run(g, ticks(g.tuning.combat.stunGuard * 0.3));
  assert.equal(e.guard, 0, 'garde épuisée');
  damageEnemy(g, e, { kind: 'melee', amount: 1, stun: 0.5, canCrit: false });
  assert.ok(e.stun > 0, 'le coup d\'arme étourdit de nouveau');
});

test('garde : assez longue pour placer une attaque (recharge de sortie + télégraphe le plus long de la mêlée)', () => {
  const EXIT_COOLDOWN = 0.3; // enemies.mjs : recharge imposée en sortie d'étourdissement
  for (const [kind, def] of Object.entries(T.enemies)) {
    if (def.windup === undefined || def.attackRange === undefined) continue; // archétypes de mêlée
    assert.ok(T.combat.stunGuard >= EXIT_COOLDOWN + def.windup, `${kind} : ${EXIT_COOLDOWN} + ${def.windup} s tiennent dans la garde`);
  }
});

test('garde : réglée à 0, elle n\'existe pas (le réglage commande la règle)', () => {
  const g = sandbox('bourreau', 'hache', { combat: { stunGuard: 0 } });
  const e = dummy(g);
  stunThenRecover(g, e);
  damageEnemy(g, e, { kind: 'melee', amount: 1, stun: 0.5, canCrit: false });
  assert.ok(e.stun > 0, 'sans garde, le coup d\'arme ré-étourdit aussitôt');
});

// ---------------------------------------------------------------- Bourreau : attaque maintenue sur place

test('mêlée : attaque maintenue sur place, les brutes placent leurs coups avec chaque arme (pas d\'étourdissement en boucle)', () => {
  for (const kit of allKits(T)) {
    if (T.weapons[kit.weaponType].kind !== 'melee') continue;
    const hits = holdHits(kit.classId, kit.weaponType, HOLD_PACKS.brutes);
    assert.ok(hits >= MIN_HOLD_HITS, `${kit.id} : ${hits.toFixed(1)} coups reçus en moyenne (seuil ${MIN_HOLD_HITS})`);
  }
});

test('Maillet : c\'est la garde qui rend les coups aux brutes (sans elle, le fracas les étourdit en boucle)', () => {
  const guarded = holdHits('bourreau', 'marteau', HOLD_PACKS.brutes);
  const unguarded = holdHits('bourreau', 'marteau', HOLD_PACKS.brutes, { combat: { stunGuard: 0 } });
  assert.ok(guarded > unguarded, `avec la garde ${guarded.toFixed(1)} coups, sans ${unguarded.toFixed(1)}`);
});

// ---------------------------------------------------------------- Chasseresse : on ne distance pas la mêlée en tirant

test('Chasseresse : en tirant, elle avance moins vite qu\'un diablotin ; en cessant de tirer, plus vite', () => {
  const impSpeed = T.enemies.imp.speed;
  for (const weaponType of T.classes.chasseresse.weapons) {
    const g = sandbox('chasseresse', weaponType);
    const p = g.player;
    const x0 = p.x;
    const seconds = 2;
    run(g, ticks(seconds), { moveX: -1, attack: true, aimX: 1 }); // elle recule en tirant devant elle
    const shooting = (x0 - p.x) / seconds;
    assert.ok(shooting > 0, `${weaponType} : elle se déplace encore en tirant`);
    assert.ok(shooting < impSpeed, `${weaponType} : ${shooting.toFixed(0)} u/s en tirant < diablotin ${impSpeed} u/s`);

    const g2 = sandbox('chasseresse', weaponType);
    const x1 = g2.player.x;
    run(g2, ticks(seconds), { moveX: -1 });
    const running = (x1 - g2.player.x) / seconds;
    assert.ok(running > impSpeed, `${weaponType} : ${running.toFixed(0)} u/s en courant > diablotin ${impSpeed} u/s`);
  }
});

test('Chasseresse : le dash reste la fuite — pressé en plein tir, il part et couvre au moins la distance de base', () => {
  for (const weaponType of T.classes.chasseresse.weapons) {
    const g = sandbox('chasseresse', weaponType);
    const p = g.player;
    run(g, ticks(0.3), { attack: true, aimX: 1 }); // en plein tir
    const x0 = p.x;
    run(g, 1, { moveX: -1, dashPressed: true });
    run(g, ticks(g.tuning.dash.duration), { moveX: -1 });
    const dashed = x0 - p.x;
    assert.ok(dashed >= g.tuning.dash.distance, `${weaponType} : dash de ${dashed.toFixed(0)} u (classe : +30 %)`);
  }
});
