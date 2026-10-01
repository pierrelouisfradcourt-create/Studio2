// Tests issus de la relecture adversariale du lot ÉTAGES (V2) : un test par défaut corrigé.
//
//   - la jauge de Super suit l'arme portée (même nombre de coups à l'étage 1 et en profondeur) ;
//   - victoire au 666 : aucun checkpoint sur le Gardien final, et l'écran a une issue (la Ville) ;
//   - salle d'élite : le champion sort du bestiaire de l'étage (entrée progressive en section 1) ;
//   - fontaine : une bénédiction sans niveau (Envol) ne se médite pas, et ne vaut jamais 1,5 charge ;
//   - chambre forte : la bourse verse exactement le montant annoncé ;
//   - un numéro d'étage illisible vaut l'étage 1 (ni plantage, ni NaN).
// Lancement : node --test tests/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createGame, stepGame, emptyInput, applyCommand } from '../src/sim/game.mjs';
import { createTuning } from '../src/sim/config.mjs';
import { createEnemy } from '../src/sim/enemies.mjs';
import { damageEnemy, killEnemy } from '../src/sim/combat.mjs';
import { floorInfo, floorScaling } from '../src/sim/floors.mjs';
import { enterFloor } from '../src/sim/run.mjs';
import { describeCalm } from '../src/sim/calm_rooms.mjs';
import { recomputeStats } from '../src/sim/stats.mjs';
import { maxDashCharges } from '../src/sim/player.mjs';

const T = createTuning();
const STEP_CAP = 600;

function stepUntil(g, done) {
  for (let i = 0; i < STEP_CAP && !done(g); i++) stepGame(g, emptyInput());
  return done(g);
}

function touchInteract(g) {
  g.player.x = g.room.interact.x;
  g.player.y = g.room.interact.y;
  return stepUntil(g, (x) => x.mode === 'choice');
}

// ---------------------------------------------------------------- jauge de Super

/** Jauge gagnée par UN coup de base (10 de dégâts) avec une arme `mult` fois plus forte que l'arme de base. */
function superGainPerHit(mult) {
  const g = createGame({ seed: 7 });
  g.spawns.length = 0;
  g.enemies.length = 0;
  g.room.waves = [];
  g.tuning.combat.critChance = 0;
  g.run.items.arme.base.damage = T.weaponBase * mult;
  recomputeStats(g);
  const e = createEnemy(g, 'brute', g.player.x + 60, g.player.y, { spawnT: 0 });
  e.hp = 1e9;
  e.maxHp = 1e9;
  g.player.superCharge = 0;
  const dealt = damageEnemy(g, e, { kind: 'melee', amount: 10, canCrit: false });
  return { gain: g.player.superCharge, dealt };
}

test('Super : la jauge demande le même nombre de coups quelle que soit l\'arme portée (étage 1 comme étage 649)', () => {
  const base = superGainPerHit(1);
  assert.ok(base.gain > 0, 'un coup remplit la jauge');
  assert.ok(Math.abs(base.gain - 10 / T.super.chargeDamage) < 1e-9, 'arme de base : dégâts ÷ chargeDamage, comme avant');
  const deepLevel = floorScaling(T, 649).level; // niveau d'objet en fin de descente
  const deep = superGainPerHit(deepLevel);
  assert.ok(deep.dealt > base.dealt * 10, `l'arme de niveau ${deepLevel.toFixed(1)} frappe bien plus fort (${deep.dealt} contre ${base.dealt})`);
  assert.ok(Math.abs(deep.gain - base.gain) < base.gain * 0.02, `jauge par coup : ${deep.gain.toFixed(5)} contre ${base.gain.toFixed(5)}`);
});

// ---------------------------------------------------------------- victoire au 666

function winTheGame(seed = 3) {
  const g = createGame({ seed, startFloor: T.floors.total });
  const boss = g.enemies.find((e) => e.boss);
  assert.ok(boss, 'le Gardien final est là');
  g.spawns.length = 0;
  killEnemy(g, boss, { kind: 'melee' });
  stepUntil(g, (x) => x.mode !== 'play');
  return g;
}

test('victoire au 666 : aucun checkpoint n\'est posé sur le Gardien final', () => {
  const g = winTheGame();
  assert.equal(g.mode, 'victory');
  assert.ok(!g.meta.checkpoints.includes(T.floors.total), `checkpoints : ${g.meta.checkpoints.join(', ')}`);
  for (const cp of g.meta.checkpoints) assert.equal(floorInfo(T, cp).indexInSection, 1, `le checkpoint ${cp} est un début de section`);
  assert.ok(g.meta.souls > 0, 'les Âmes du Gardien final sont gagnées');
});

test('victoire au 666 : l\'écran a une issue — retour en Ville accepté, profil conservé', () => {
  const g = winTheGame();
  const souls = g.meta.souls;
  assert.equal(applyCommand(g, { type: 'returnToTown' }), true, 'la commande est acceptée en mode victoire');
  assert.equal(g.mode, 'town');
  assert.equal(g.meta.souls, souls, 'le retour ne coûte rien');
  // Hors victoire, mort ou portail, quitter reste refusé (ce serait un abandon).
  const g2 = createGame({ seed: 3 });
  assert.equal(applyCommand(g2, { type: 'returnToTown' }), false);
});

// ---------------------------------------------------------------- champion des salles d'élite

test('salle d\'élite en section 1 : le champion appartient au bestiaire de l\'étage (aucun archétype en avance)', () => {
  let rooms = 0;
  for (let seed = 1; seed <= 300; seed++) {
    for (const floor of [2, 3, 4]) {
      const g = createGame({ seed, startFloor: floor - 1 });
      enterFloor(g, floor, { reward: 'elite' });
      if (g.room.kind !== 'elite') continue;
      rooms++;
      const roster = new Set(g.room.plan.roster.map((r) => r.kind));
      const champion = g.room.waves.flat().find((s) => s.elite);
      assert.ok(champion, `graine ${seed} étage ${floor} : la salle d'élite a son champion`);
      assert.ok(roster.has(champion.kind), `graine ${seed} étage ${floor} : champion « ${champion.kind} » hors du bestiaire [${[...roster].join(', ')}]`);
    }
  }
  assert.ok(rooms > 100, `${rooms} salles d'élite examinées`);
});

// ---------------------------------------------------------------- fontaine : méditation

function fountain(boons) {
  const g = createGame({ seed: 5, startFloor: 3 });
  g.run.boons = boons.map((id) => ({ id, rarity: 'commun', level: 1 }));
  recomputeStats(g);
  enterFloor(g, 4, { reward: 'rest' });
  assert.equal(g.room.kind, 'rest');
  return g;
}

test('fontaine : Envol (bénédiction sans niveau) ne se médite pas ; une autre bénédiction, oui', () => {
  const alone = fountain(['envol']);
  const opt = describeCalm(alone, alone.room.interact).options.find((o) => o.id === 'mediter');
  assert.equal(opt.disabled, true, 'Envol seul : rien à approfondir');

  const g = fountain(['envol', 'furie']);
  const med = describeCalm(g, g.room.interact).options.findIndex((o) => o.id === 'mediter');
  assert.ok(touchInteract(g));
  assert.equal(applyCommand(g, { type: 'choose', index: med }), true);
  assert.equal(g.run.boons.find((b) => b.id === 'furie').level, 2, 'la méditation va à Furie');
  assert.equal(g.run.boons.find((b) => b.id === 'envol').level, 1, 'Envol garde son niveau');
});

test('Envol : +1 charge de dash, entière, quel que soit son niveau', () => {
  const g = createGame({ seed: 5 });
  const base = maxDashCharges(g);
  for (const level of [1, 2, 3]) {
    g.run.boons = [{ id: 'envol', rarity: 'commun', level }];
    recomputeStats(g);
    assert.equal(maxDashCharges(g), base + 1, `niveau ${level}`);
  }
});

// ---------------------------------------------------------------- chambre forte : bourse

test('chambre forte : la bourse verse exactement le montant annoncé', () => {
  const n = T.economy.treasure.goldPickups;
  for (let seed = 1; seed <= 60; seed++) {
    const g = createGame({ seed, startFloor: 3 });
    enterFloor(g, 4, { reward: 'treasure' });
    const it = g.room.interact;
    assert.equal(it.gold % n, 0, `graine ${seed} : ${it.gold} or se partage en ${n} pièces égales`);
    const label = describeCalm(g, it).options.find((o) => o.id === 'bourse').label;
    assert.equal(label, `+${it.gold} or`);
    const gold0 = g.run.gold;
    assert.ok(touchInteract(g));
    assert.equal(applyCommand(g, { type: 'choose', index: 1 }), true);
    assert.equal(g.pickups.filter((k) => k.kind === 'gold').reduce((s, k) => s + k.value, 0), it.gold, `graine ${seed} : pièces au sol`);
    assert.ok(stepUntil(g, (x) => x.pickups.length === 0), 'les pièces sont ramassées');
    assert.equal(g.run.gold - gold0, it.gold, `graine ${seed} : annoncé ${it.gold}`);
  }
});

// ---------------------------------------------------------------- numéro d'étage illisible

test('étage illisible (NaN, texte, infini) : vaut l\'étage 1 — ni plantage, ni NaN', () => {
  for (const bad of [NaN, 'abc', undefined, Infinity, -Infinity]) {
    const info = floorInfo(T, bad);
    assert.ok(Number.isFinite(info.floor) && info.floor >= 1 && info.floor <= T.floors.total, `floorInfo(${bad}) -> ${info.floor}`);
    const s = floorScaling(T, bad);
    assert.ok(Number.isFinite(s.hp) && Number.isFinite(s.damage), `floorScaling(${bad})`);
  }
  assert.equal(floorInfo(T, NaN).floor, 1);
  assert.equal(floorInfo(T, 'abc').floor, 1);
  const g = createGame({ seed: 9, startFloor: NaN });
  assert.equal(g.run.floor, 1);
  for (let i = 0; i < 120; i++) stepGame(g, emptyInput());
  assert.ok(Number.isFinite(g.player.x) && Number.isFinite(g.player.hp));
});
