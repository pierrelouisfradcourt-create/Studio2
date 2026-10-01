// Tests V2 — ÉTAGES : le système qui COMPOSE les 666 étages à partir de briques réutilisables,
// au lieu de les écrire à la main (demande de Pierre, priorité 6).
//   floors.mjs      structure (sections de 18, Gardien au 18e, checkpoints) et scaling ;
//   sections.mjs    plan PUR d'une section : rythme, portes imposées, vagues, budget,
//                   dispositions, thème du Cercle, Gardien ;
//   room.mjs        dispositions et vagues ; run.mjs : composition de l'étage et des portes ;
//   calm_rooms.mjs  salles calmes réutilisables (chambre forte, fontaine de repos).
// Fichier NEUF (les tests préexistants ne sont pas modifiés). Des lois, pas des valeurs : les
// seuils sont lus dans le tuning, sauf les exigences de la demande (666 étages, Gardien tous
// les 18). Lancer : node --test tests/v2_floors.test.mjs

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createGame, stepGame, emptyInput, applyCommand, DT } from '../src/sim/game.mjs';
import { floorInfo, checkpointAfterBoss, floorScaling, sectionBounds, guardianFor, sectionStartDifficulty } from '../src/sim/floors.mjs';
import { sectionPlan, composeFloor, floorSlot, sectionCount, circleTheme, FLOOR_TYPE_OF_REWARD } from '../src/sim/sections.mjs';
import { enterFloor, onRoomClear } from '../src/sim/run.mjs';
import { LAYOUT_IDS, COMBAT_LAYOUTS, ROSTER, buildRoom, playerStart, rewardSpot, launchNextWave } from '../src/sim/room.mjs';
import { findSpawnPoint } from '../src/sim/spawns.mjs';
import { CALM_KINDS } from '../src/sim/calm_rooms.mjs';
import { pointBlocked } from '../src/sim/physics.mjs';
import { addBoon, BOONS } from '../src/sim/boons.mjs';
import { generateItem } from '../src/sim/loot.mjs';
import { POLICIES, resolveChoice } from '../tools/bots.mjs';
import { runEpisode } from '../tools/playtest.mjs';

// Exigences de la demande (pas des réglages) : 666 étages, un Gardien tous les 18.
const TOTAL_FLOORS = 666;
const GUARDIAN_EVERY = 18;
const SECTIONS = TOTAL_FLOORS / GUARDIAN_EVERY; // 37
const PLAN_SEEDS = [1, 7, 12345];
const FLOOR_TYPES = ['combat', 'elite', 'boss', 'shop', 'event', 'treasure', 'rest'];
const ALL_OFFERS_EVERY = 7; // étages dont on construit la salle pour CHAQUE porte possible
const PATH_CELL = 8; // u : grille de la recherche de chemin à pied
const GEOM_EPS = 0.5; // u : arrondi toléré sur un contact mur / obstacle
const GEOMETRY_STEPS = 1800; // 30 s de combat par disposition nouvelle
const STEP_CAP = 600; // pas de sim pour franchir une porte / ouvrir un menu
const RHYTHM_SEEDS = [1, 2, 3, 4];
const DEEP_SECTIONS = [2, 20];
const DEEP_SEEDS = [1, 2];
const DEEP_MINUTES = 30;
const SECONDS_PER_MINUTE = 60;

const T = createGame().tuning;

// ---------------------------------------------------------------- outillage

/** Tous les flux RNG de la partie (pour prouver qu'un calcul ne les consomme pas). */
function rngState(g) {
  return [g.rng.gen.s, g.rng.combat.s, g.rng.ai.s].join(':');
}

/**
 * Salle de combat vidée et terminée par la sim (récompense posée, portes préparées). Le gel
 * d'impact de la salle précédente peut retarder la fin de quelques images.
 */
function clearCombat(g) {
  g.enemies.length = 0;
  g.spawns.length = 0;
  g.room.waveIndex = g.room.waves.length - 1;
  stepUntil(g, (x) => x.room.cleared);
  g.events.length = 0;
}

/** Gardien abattu : la sim termine la salle (après un éventuel gel d'impact). */
function killGuardian(g) {
  for (const e of g.enemies) e.dead = true;
  g.spawns.length = 0;
  stepUntil(g, (x) => x.room.cleared);
  g.events.length = 0;
}

/** Pas de sim jusqu'à ce que `done(g)` soit vrai (ou STEP_CAP). */
function stepUntil(g, done) {
  for (let i = 0; i < STEP_CAP && !done(g); i++) stepGame(g, emptyInput());
  return done(g);
}

/** Le héros marche jusqu'à l'objet d'interaction (placé dessus) et le menu s'ouvre. */
function touchInteract(g) {
  g.player.x = g.room.interact.x;
  g.player.y = g.room.interact.y;
  return stepUntil(g, (x) => x.mode === 'choice');
}

/** Recherche en largeur : le héros peut-il MARCHER de (x0, y0) jusqu'à toucher `goal` ? */
function walkable(room, r, x0, y0, goal) {
  const cols = Math.ceil(room.w / PATH_CELL);
  const rows = Math.ceil(room.h / PATH_CELL);
  const seen = new Uint8Array(cols * rows);
  const start = [Math.floor(x0 / PATH_CELL), Math.floor(y0 / PATH_CELL)];
  const queue = [start];
  seen[start[1] * cols + start[0]] = 1;
  for (let head = 0; head < queue.length; head++) {
    const [c, rw] = queue[head];
    if (goal((c + 0.5) * PATH_CELL, (rw + 0.5) * PATH_CELL)) return true;
    for (const [dc, dr] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const nc = c + dc;
      const nr = rw + dr;
      if (nc < 0 || nr < 0 || nc >= cols || nr >= rows || seen[nr * cols + nc]) continue;
      if (pointBlocked(room, (nc + 0.5) * PATH_CELL, (nr + 0.5) * PATH_CELL, r)) continue;
      seen[nr * cols + nc] = 1;
      queue.push([nc, nr]);
    }
  }
  return false;
}

// ---------------------------------------------------------------- structure

test('structure : 666 étages, 37 sections de 18, un Gardien tous les 18 étages (18, 36, …, 666)', () => {
  assert.equal(T.floors.total, TOTAL_FLOORS);
  assert.equal(T.floors.sectionLength, GUARDIAN_EVERY);
  assert.equal(sectionCount(T), SECTIONS);
  const bosses = [];
  for (let f = 1; f <= TOTAL_FLOORS; f++) if (floorInfo(T, f).isBoss) bosses.push(f);
  assert.deepEqual(bosses, Array.from({ length: SECTIONS }, (_, i) => (i + 1) * GUARDIAN_EVERY));
  for (let s = 1; s <= SECTIONS; s++) {
    const b = sectionBounds(T, s);
    assert.equal(b.first, (s - 1) * GUARDIAN_EVERY + 1);
    assert.equal(b.guardian, s * GUARDIAN_EVERY);
    assert.equal(floorInfo(T, b.first).indexInSection, 1);
    assert.equal(floorInfo(T, b.guardian).section, s);
  }
  assert.equal(floorInfo(T, TOTAL_FLOORS).isFinal, true);
});

test('checkpoints : chaque Gardien ouvre le checkpoint 19, 37, … — le premier étage de la section suivante', () => {
  for (let s = 1; s < SECTIONS; s++) {
    const g = s * GUARDIAN_EVERY;
    assert.equal(checkpointAfterBoss(T, g), g + 1);
    assert.equal(sectionBounds(T, s).checkpoint, g + 1);
    assert.equal(sectionBounds(T, s + 1).first, g + 1, 'le checkpoint est le début de la section suivante');
  }
  assert.ok(checkpointAfterBoss(T, TOTAL_FLOORS) <= TOTAL_FLOORS, 'aucun checkpoint au-delà du 666e étage');
});

test('Gardien de section : vaincu, il ouvre le checkpoint et le portail ; la porte suivante entre dans la nouvelle section', () => {
  for (const s of [1, 2]) {
    const { guardian, checkpoint } = sectionBounds(T, s);
    const g = createGame({ seed: 9, startFloor: guardian });
    assert.equal(g.room.kind, 'boss');
    const boss = g.enemies.find((e) => e.boss);
    assert.ok(boss, 'la salle du Gardien a son Gardien');
    assert.equal(boss.kind, guardianFor(T, s));
    killGuardian(g);
    assert.ok(g.meta.checkpoints.includes(checkpoint), `checkpoint ${checkpoint} débloqué`);
    assert.equal(g.room.doors.length, 2);
    assert.equal(g.room.doors[1].reward, 'town', 'point de téléportation vers la Ville');
    // Le butin du Gardien pris, la porte « section suivante » mène au checkpoint.
    if (touchInteract(g)) applyCommand(g, { type: 'salvage' });
    const d = g.room.doors[0];
    g.player.x = d.x + d.w / 2;
    g.player.y = d.h;
    assert.ok(stepUntil(g, (x) => x.run.floor === checkpoint), 'la porte mène au checkpoint');
    assert.equal(g.info.section, s + 1);
    assert.equal(g.info.indexInSection, 1);
  }
});

// ---------------------------------------------------------------- plan de section

test('plan de section : pur, déterministe et complet pour les 37 sections', () => {
  const g = createGame({ seed: 4 });
  const before = rngState(g);
  for (const seed of PLAN_SEEDS) {
    for (let s = 1; s <= SECTIONS; s++) {
      const plan = sectionPlan(T, seed, s);
      assert.deepEqual(plan, sectionPlan(T, seed, s), `section ${s} : même graine, même plan`);
      const b = sectionBounds(T, s);
      assert.equal(plan.section, s);
      assert.equal(plan.floors.length, GUARDIAN_EVERY);
      plan.floors.forEach((e, i) => {
        const where = `graine ${seed} section ${s} index ${i + 1}`;
        assert.equal(e.index, i + 1, where);
        assert.equal(e.floor, b.first + i, where);
        assert.ok(Number.isInteger(e.waves) && e.waves >= 1, `${where} : vagues ${e.waves}`);
        assert.ok(Number.isFinite(e.budget) && e.budget >= 1, `${where} : budget ${e.budget}`);
        assert.ok(e.layouts.length > 0 && e.layouts.every((l) => LAYOUT_IDS.includes(l.id) && l.weight > 0), `${where} : dispositions`);
        assert.ok(e.roster.length > 0 && e.roster.every((r) => T.enemies[r.kind] && r.weight > 0 && Number.isFinite(r.weight)), `${where} : bestiaire`);
        assert.ok(e.offers.length > 0 && e.types.every((k) => FLOOR_TYPES.includes(k)), `${where} : types ${e.types}`);
      });
      const last = plan.floors[GUARDIAN_EVERY - 1];
      assert.equal(last.slot, 'gardien');
      assert.deepEqual(last.doors, ['boss']);
      assert.equal(last.guardian, guardianFor(T, s));
      assert.equal(plan.guardian, guardianFor(T, s));
    }
  }
  assert.equal(rngState(g), before, 'le plan ne consomme aucun flux RNG de la partie');
  // Des graines différentes donnent des sections différentes (rythme, halte, chambre forte).
  const shapes = new Set();
  for (let seed = 1; seed <= 20; seed++) {
    const p = sectionPlan(T, seed, 5);
    shapes.add(JSON.stringify([p.rhythmId, p.treasureAt, p.floors.map((e) => e.doors)]));
  }
  assert.ok(shapes.size > 1, 'les sections varient avec la graine');
});

test('portes imposées : Gardien au 18e, halte et antichambre imposées, élite et chambre forte garanties', () => {
  const sec = T.section;
  for (const seed of PLAN_SEEDS) {
    for (let s = 1; s <= SECTIONS; s++) {
      const plan = sectionPlan(T, seed, s);
      let treasures = 0;
      for (const e of plan.floors) {
        if (e.slot === 'halte') {
          assert.equal(e.doors.length, sec.halte.doors);
          assert.equal(new Set(e.doors).size, sec.halte.doors, 'portes distinctes');
          const fixed = sec.halte.fixed ?? [];
          assert.ok(fixed.every((r) => e.doors.includes(r)), 'la halte propose toujours ses portes fixes (repos)');
          assert.ok(e.doors.every((r) => sec.halte.pool[r] > 0 || fixed.includes(r)));
        } else if (e.slot === 'antichambre') {
          assert.deepEqual(e.doors, sec.antichambre);
        } else if (e.slot !== 'gardien') {
          assert.equal(e.doors, null, `index ${e.index} : portes tirées`);
        }
        if (sec.eliteAt.includes(e.index) && !e.doors) assert.equal(e.guarantee, 'elite');
        if (e.guarantee === 'treasure') {
          treasures++;
          assert.ok(e.index >= sec.treasure.from && e.index <= sec.treasure.to);
        }
      }
      assert.equal(treasures, 1, `graine ${seed} section ${s} : une chambre forte garantie`);
    }
  }
});

test('portes à l\'exécution : chaque sortie respecte le plan de l\'étage suivant (sections 1 et 2)', () => {
  const g = createGame({ seed: 3 });
  for (let f = 1; f <= 2 * GUARDIAN_EVERY - 1; f++) {
    enterFloor(g, f, { reward: 'gold' });
    if (g.room.kind === 'boss') killGuardian(g);
    else clearCombat(g);
    const next = floorSlot(T, g.seed, f + 1);
    const rewards = g.room.doors.map((d) => d.reward);
    const where = `étage ${f} -> ${f + 1}`;
    if (g.room.kind === 'boss') {
      assert.equal(rewards[1], 'town', where);
      assert.ok(next.offers.includes(rewards[0]), where);
    } else if (next.doors) {
      assert.deepEqual(rewards, next.doors, where);
    } else {
      assert.equal(rewards.length, 2, where);
      assert.notEqual(rewards[0], rewards[1], where);
      assert.ok(rewards.every((r) => next.offers.includes(r)), `${where} : ${rewards}`);
      if (next.guarantee) assert.ok(rewards.includes(next.guarantee), `${where} : ${next.guarantee} garanti`);
    }
  }
});

// ---------------------------------------------------------------- composition des 666 étages

function checkComposed(g, f, reward) {
  const where = `étage ${f}, porte ${reward}`;
  enterFloor(g, f, { reward });
  const slot = floorSlot(T, g.seed, f);
  const expected = floorInfo(T, f).isBoss ? 'boss' : FLOOR_TYPE_OF_REWARD[reward] ?? 'combat';
  assert.equal(g.room.kind, expected, where);
  assert.equal(g.run.floor, f, where);
  const start = playerStart(g.room);
  assert.ok(!pointBlocked(g.room, start.x, start.y, g.player.r), `${where} : entrée bouchée`);
  if (expected === 'boss') {
    assert.equal(g.enemies.filter((e) => e.boss && e.kind === guardianFor(T, floorInfo(T, f).section)).length, 1, where);
  } else if (expected === 'combat' || expected === 'elite') {
    assert.ok(slot.layouts.some((l) => l.id === g.room.layout), `${where} : disposition ${g.room.layout}`);
    assert.equal(g.room.waves.length, slot.waves, where);
    assert.ok(g.room.waves.every((w) => w.length > 0), `${where} : vague vide`);
    assert.ok(g.spawns.length > 0, `${where} : la première vague apparaît`);
    if (expected === 'elite') assert.ok(g.room.waves.at(-1).some((s) => s.elite), `${where} : champion`);
  } else {
    assert.equal(g.room.interact?.kind, expected, where);
    assert.ok(g.room.doors.length > 0 && g.room.doors.every((d) => d.open), `${where} : salle calme, portes ouvertes`);
  }
}

test('chaque étage 1..666 est composable : la salle se construit sans erreur, pour chaque porte possible', () => {
  const g = createGame({ seed: 21 });
  g.godMode = true;
  for (let f = 1; f <= TOTAL_FLOORS; f++) {
    const slot = floorSlot(T, g.seed, f);
    const offers = f % ALL_OFFERS_EVERY === 0 ? slot.offers : [slot.offers[(f * 7) % slot.offers.length]];
    for (const reward of offers) checkComposed(g, f, reward);
    // Composition pure : même résultat, pour toutes les portes.
    for (const reward of slot.offers) assert.deepEqual(composeFloor(T, g.seed, f, { reward }), composeFloor(T, g.seed, f, { reward }));
  }
});

test('répartition des types d\'étage : chaque section offre combats, élites, chambre forte, repos, marchand/autel, Gardien', () => {
  const totals = Object.fromEntries(FLOOR_TYPES.map((k) => [k, 0]));
  const paces = {};
  for (let s = 1; s <= SECTIONS; s++) {
    const plan = sectionPlan(T, 1, s);
    const types = new Set(plan.floors.flatMap((e) => e.types));
    for (const k of ['combat', 'elite', 'treasure', 'rest', 'boss']) assert.ok(types.has(k), `section ${s} : aucun étage ${k}`);
    assert.ok(types.has('shop') || types.has('event'), `section ${s} : ni marchand ni autel`);
    for (const e of plan.floors) {
      for (const k of e.types) totals[k]++;
      paces[e.slot] = (paces[e.slot] ?? 0) + 1;
    }
    const combatSlots = plan.floors.filter((e) => T.section.paces[e.slot]).length;
    const calmSlots = plan.floors.filter((e) => e.slot === 'halte' || e.slot === 'antichambre').length;
    assert.ok(combatSlots >= GUARDIAN_EVERY / 2, `section ${s} : ${combatSlots} combats seulement`);
    assert.ok(calmSlots >= 2, `section ${s} : au moins deux haltes`);
  }
  assert.equal(paces.gardien, SECTIONS);
  for (const k of FLOOR_TYPES) assert.ok(totals[k] > 0, `type ${k} jamais proposé`);
});

// ---------------------------------------------------------------- rythme

test('rythme : vagues par index — départ de section court, jamais deux assauts de suite, une pause avant le Gardien', () => {
  const { paces, rhythms } = T.section;
  const wavesOf = (slot) => paces[slot]?.waves ?? 0;
  const maxWaves = Math.max(...Object.values(paces).map((p) => p.waves));
  for (const [i, r] of rhythms.entries()) {
    assert.equal(r.length, GUARDIAN_EVERY, `rythme ${i}`);
    assert.equal(r.at(-1), 'gardien', `rythme ${i} : le 18e est le Gardien`);
    assert.equal(wavesOf(r[0]), Math.min(...Object.values(paces).map((p) => p.waves)), `rythme ${i} : on repart du checkpoint par un étage court`);
    assert.equal(wavesOf(r.at(-2)), 0, `rythme ${i} : l'antichambre du Gardien est calme`);
    assert.ok(r.slice(2, -2).some((slot) => !paces[slot]), `rythme ${i} : une halte au milieu`);
    for (let k = 1; k < r.length; k++) assert.ok(!(wavesOf(r[k]) === maxWaves && wavesOf(r[k - 1]) === maxWaves), `rythme ${i} : deux assauts de suite (index ${k})`);
  }
  // Le plan applique le rythme : vagues de l'index = vagues de son allure ; budget croissant à allure égale.
  for (let s = 1; s <= SECTIONS; s++) {
    const plan = sectionPlan(T, 5, s);
    const lastBudget = {};
    for (const e of plan.floors) {
      assert.equal(e.waves, paces[e.pace].waves, `section ${s} index ${e.index}`);
      if (lastBudget[e.pace] !== undefined) assert.ok(e.budget > lastBudget[e.pace], `section ${s} index ${e.index} : budget non croissant`);
      lastBudget[e.pace] = e.budget;
    }
  }
});

test('rythme mobile mesuré : le bot boucle la section 1 en une session courte (estimation humaine ≤ tuning)', () => {
  const ses = T.section.session;
  for (const seed of RHYTHM_SEEDS) {
    const r = runEpisode('skilled', seed, { floors: GUARDIAN_EVERY, minutes: DEEP_MINUTES });
    assert.ok(r.sectionCleared, `graine ${seed} : ${r.outcome} à l'étage ${r.floorReached}`);
    const menus = r.eventCounts.choiceOpen ?? 0;
    const human = (r.simSeconds * ses.humanPace + menus * ses.menuSeconds) / SECONDS_PER_MINUTE;
    assert.ok(human <= ses.maxMinutes, `graine ${seed} : section estimée à ${human.toFixed(1)} min (bot ${(r.simSeconds / SECONDS_PER_MINUTE).toFixed(1)} min, ${menus} menus)`);
  }
});

// ---------------------------------------------------------------- scaling jusqu'à 666

test('scaling : fini jusqu\'à 666, croissant dans chaque section, Gardien le plus coriace, débuts de section croissants', () => {
  let prevStart = null;
  let prev = null;
  for (let s = 1; s <= SECTIONS; s++) {
    const b = sectionBounds(T, s);
    let last = null;
    for (let f = b.first; f <= b.guardian; f++) {
      const sc = floorScaling(T, f);
      for (const k of ['hp', 'damage', 'density']) assert.ok(Number.isFinite(sc[k]) && sc[k] >= 1, `étage ${f} : ${k} = ${sc[k]}`);
      if (last) assert.ok(sc.hp > last.hp && sc.damage > last.damage, `étage ${f} : la difficulté recule dans la section`);
      if (prev) assert.ok(sc.damage >= prev.damage && sc.density >= prev.density, `étage ${f} : dégâts ou densité en recul`);
      last = sc;
      prev = sc;
    }
    const start = floorScaling(T, b.first);
    if (prevStart) assert.ok(start.hp > prevStart.hp && start.damage > prevStart.damage, `section ${s} : plus facile que la précédente`);
    prevStart = start;
  }
});

test('début de section abordable : face au seul équipement permanent (aucune bénédiction), difficulté bornée', () => {
  // Temps pour tuer : croissant d'une section à l'autre. Part des PV par coup : elle plafonne
  // (D sature) — bornée, sans exiger de croissance (l'écart d'un étage d'équipement s'amenuise).
  const max = T.floors.sectionStartMax;
  let prev = null;
  for (let s = 1; s <= SECTIONS; s++) {
    const d = sectionStartDifficulty(T, s);
    assert.ok(d.toughness <= max.toughness && d.lethality <= max.lethality, `section ${s} : ${JSON.stringify(d)}`);
    assert.ok(d.toughness >= 1 && d.lethality >= 1, `section ${s} : plus facile que l'étage 1 (${JSON.stringify(d)})`);
    if (prev) assert.ok(d.toughness >= prev.toughness - 1e-9, `section ${s} : le temps pour tuer recule`);
    prev = d;
  }
  assert.deepEqual(sectionStartDifficulty(T, 1), { floor: 1, toughness: 1, lethality: 1 });
});

/** Équipement permanent « à niveau » : objets communs de l'étage précédant le checkpoint. */
function levelGear(level) {
  const g = createGame({ seed: 77 });
  return Object.fromEntries(['arme', 'armure', 'talisman'].map((slot) => [slot, generateItem(g, { slot, rarity: 'commun', floor: level })]));
}

test('reprise profonde jouable : le bot repart d\'un checkpoint profond, équipement commun à niveau, et bat la section', () => {
  for (const s of DEEP_SECTIONS) {
    const b = sectionBounds(T, s);
    for (const seed of DEEP_SEEDS) {
      const g = createGame({ seed, startFloor: b.first, items: levelGear(b.first - 1) });
      const mem = {};
      while (g.tick < (DEEP_MINUTES * SECONDS_PER_MINUTE) / DT && g.run.floor <= b.guardian && (g.mode === 'play' || g.mode === 'choice')) {
        if (g.mode === 'choice') {
          assert.ok(resolveChoice(g, 'skilled'), 'menu sans issue');
          continue;
        }
        stepGame(g, POLICIES.skilled(g, mem));
        g.events.length = 0;
      }
      assert.ok(g.run.floor > b.guardian || g.mode === 'victory', `section ${s} graine ${seed} : ${g.mode} à l'étage ${g.run.floor}`);
    }
  }
});

// ---------------------------------------------------------------- salles calmes

function calmRoom(kind, seed = 5) {
  const g = createGame({ seed, startFloor: 3 });
  enterFloor(g, 4, { reward: kind });
  g.events.length = 0;
  return g;
}

test('chambre forte : salle sans combat, trois trésors annoncés, un seul pris (objet, bourse ou relique)', () => {
  const g = calmRoom('treasure');
  assert.equal(g.room.kind, 'treasure');
  assert.equal(g.enemies.length + g.spawns.length, 0, 'aucun combat');
  assert.ok(g.room.doors.every((d) => d.open), 'les portes ne retiennent pas le joueur');
  const it = g.room.interact;
  assert.ok(it.item && it.gold > 0 && it.family, 'contenu tiré à l\'entrée');
  assert.ok(touchInteract(g));
  assert.equal(g.choice.kind, 'treasure');
  assert.equal(g.choice.options.length, 3);
  // Bourse : l'or tombe au sol et rejoint la bourse.
  const gold0 = g.run.gold;
  assert.equal(applyCommand(g, { type: 'choose', index: 1 }), true);
  assert.equal(g.mode, 'play');
  assert.ok(g.room.interact.used, 'le coffre ne s\'ouvre qu\'une fois');
  stepUntil(g, (x) => x.pickups.length === 0);
  const each = Math.max(1, Math.round(it.gold / T.economy.treasure.goldPickups));
  assert.equal(g.run.gold - gold0, each * T.economy.treasure.goldPickups);
  // Objet : il attend d'être touché, puis rejoint l'équipement PERMANENT.
  const g2 = calmRoom('treasure');
  const item = g2.room.interact.item;
  touchInteract(g2);
  assert.equal(applyCommand(g2, { type: 'choose', index: 0 }), true);
  assert.equal(g2.room.interact.kind, 'loot');
  assert.ok(stepUntil(g2, (x) => x.mode === 'choice'));
  assert.equal(g2.choice.kind, 'loot');
  if (g2.choice.wieldable !== false) {
    applyCommand(g2, { type: 'equip' });
    assert.equal(g2.run.items[item.slot], item);
    assert.equal(g2.meta.equipment[item.slot], item, 'équipement du profil (permanent)');
  }
  // Relique : une bénédiction (TEMPORAIRE) de la famille annoncée.
  const g3 = calmRoom('treasure');
  const fam = g3.room.interact.family;
  touchInteract(g3);
  applyCommand(g3, { type: 'choose', index: 2 });
  assert.ok(stepUntil(g3, (x) => x.mode === 'choice'));
  assert.equal(g3.choice.kind, 'boon');
  assert.equal(g3.choice.family, fam);
  applyCommand(g3, { type: 'choose', index: 0 });
  assert.equal(g3.run.boons.length, 1);
});

test('fontaine de repos : boire soigne, méditer fait monter une bénédiction, les fioles rechargent ; jamais sans issue', () => {
  const g = calmRoom('rest');
  assert.equal(g.room.kind, 'rest');
  assert.equal(g.enemies.length + g.spawns.length, 0);
  const p = g.player;
  p.hp = Math.round(p.maxHp * 0.3);
  const hp0 = p.hp;
  touchInteract(g);
  assert.equal(g.choice.kind, 'rest');
  assert.equal(g.choice.options[1].disabled, true, 'méditer exige une bénédiction');
  assert.equal(applyCommand(g, { type: 'choose', index: 1 }), false);
  assert.equal(applyCommand(g, { type: 'choose', index: 0 }), true);
  assert.equal(p.hp, Math.min(p.maxHp, hp0 + p.maxHp * T.economy.rest.heal));
  assert.ok(g.room.interact.used, 'une seule grâce');
  // Méditer : la bénédiction la moins avancée gagne un niveau.
  const g2 = calmRoom('rest');
  addBoon(g2.run, { id: BOONS[0].id, rarity: 'commun' });
  touchInteract(g2);
  assert.equal(applyCommand(g2, { type: 'choose', index: 1 }), true);
  assert.equal(g2.run.boons[0].level, 2);
  // Fioles : gadget plein, jauge de Super remontée.
  const g3 = calmRoom('rest');
  g3.player.gadgetCharges = 0;
  g3.player.superCharge = 0;
  touchInteract(g3);
  assert.equal(applyCommand(g3, { type: 'choose', index: 2 }), true);
  assert.equal(g3.player.gadgetCharges, T.gadget.chargesPerSection + g3.player.stats.gadgetChargesBonus);
  assert.equal(g3.player.superCharge, T.economy.rest.superCharge);
  // Pleine santé, aucune bénédiction, fioles pleines : un choix reste possible.
  const g4 = calmRoom('rest');
  g4.player.superCharge = 1;
  touchInteract(g4);
  assert.ok(g4.choice.options.some((o) => !o.disabled));
});

test('salles calmes : le bot les traverse (menus résolus, portes franchies)', () => {
  for (const kind of CALM_KINDS) {
    const g = calmRoom(kind, 8);
    const mem = {};
    for (let i = 0; i < STEP_CAP * 4 && g.run.floor === 4; i++) {
      if (g.mode === 'choice') assert.ok(resolveChoice(g, 'skilled'), `${kind} : menu sans issue pour le bot`);
      else stepGame(g, POLICIES.skilled(g, mem));
    }
    assert.equal(g.run.floor, 5, `${kind} : le bot reste bloqué`);
  }
});

// ---------------------------------------------------------------- dispositions et thèmes

test('dispositions : chacune (anciennes et nouvelles) laisse l\'entrée libre, la récompense et les portes atteignables à pied', () => {
  const g = createGame({ seed: 2, startFloor: 2 });
  for (const id of LAYOUT_IDS) {
    const plan = { ...composeFloor(T, g.seed, 2, { reward: 'boon' }), layouts: [{ id, weight: 1 }] };
    g.room = buildRoom(g, g.info, plan);
    g.room.plan = plan;
    assert.equal(g.room.layout, id);
    const start = playerStart(g.room);
    Object.assign(g.player, start);
    assert.ok(!pointBlocked(g.room, start.x, start.y, g.player.r), `${id} : entrée bouchée`);
    assert.ok(findSpawnPoint(g, 30, T.room.spawnMinPlayerDist), `${id} : aucun point d'apparition`);
    g.room.waveIndex = g.room.waves.length - 1;
    onRoomClear(g);
    const it = g.room.interact;
    assert.ok(it, `${id} : récompense posée`);
    assert.deepEqual([it.x, it.y], Object.values(rewardSpot(g.room)));
    const r = g.player.r;
    assert.ok(walkable(g.room, r, start.x, start.y, (x, y) => Math.hypot(x - it.x, y - it.y) < r + it.r), `${id} : récompense hors d'atteinte`);
    for (const d of g.room.doors) {
      assert.ok(walkable(g.room, r, start.x, start.y, (x, y) => x > d.x && x < d.x + d.w && y - r < d.y + d.h), `${id} : porte ${d.reward} hors d'atteinte`);
    }
  }
});

/** Profondeur d'un cercle dans un rectangle (> 0 : chevauchement). */
function rectDepth(o, x, y, r) {
  const inside = x > o.x0 && x < o.x1 && y > o.y0 && y < o.y1;
  if (inside) return r + Math.min(x - o.x0, o.x1 - x, y - o.y0, o.y1 - y);
  return r - Math.hypot(x - Math.min(Math.max(x, o.x0), o.x1), y - Math.min(Math.max(y, o.y0), o.y1));
}

test('dispositions nouvelles : combat réel (bot, ennemis, charges) sans jamais entrer dans un obstacle ni un mur', () => {
  const fresh = LAYOUT_IDS.filter((id) => !COMBAT_LAYOUTS.includes(id));
  assert.ok(fresh.length > 0);
  for (const id of fresh) {
    const g = createGame({ seed: 6, startFloor: 300, godMode: true });
    g.enemies.length = 0;
    g.spawns.length = 0;
    const plan = { ...composeFloor(T, g.seed, 300, { reward: 'boon' }), layouts: [{ id, weight: 1 }] };
    g.room = buildRoom(g, g.info, plan);
    g.room.plan = plan;
    Object.assign(g.player, playerStart(g.room));
    launchNextWave(g);
    const mem = {};
    let seen = 0;
    for (let i = 0; i < GEOMETRY_STEPS && g.mode !== 'dead'; i++) {
      if (g.mode === 'choice') resolveChoice(g, 'skilled');
      else stepGame(g, POLICIES.skilled(g, mem));
      g.events.length = 0;
      const room = g.room;
      for (const b of [g.player, ...g.enemies.filter((e) => !e.dead)]) {
        const lo = room.pad + b.r - GEOM_EPS;
        assert.ok(b.x >= lo && b.x <= room.w - lo && b.y >= lo && b.y <= room.h - lo, `${id} : ${b.kind ?? 'héros'} hors des murs`);
        for (const o of room.obstacles) assert.ok(rectDepth(o, b.x, b.y, b.r) <= GEOM_EPS, `${id} : ${b.kind ?? 'héros'} dans un obstacle`);
      }
      seen += g.enemies.filter((e) => !e.dead).length;
    }
    assert.ok(seen > 0, `${id} : aucun ennemi n'a été exercé`);
  }
});

test('dispositions : l\'étage 1 est ouvert, l\'étage 2 tire parmi exactement les 6 d\'origine, les nouvelles servent plus bas', () => {
  const used = new Set();
  for (const seed of PLAN_SEEDS) {
    assert.deepEqual(floorSlot(T, seed, 1).layouts.map((l) => l.id), ['open']);
    assert.deepEqual(floorSlot(T, seed, 2).layouts.map((l) => l.id).sort(), [...COMBAT_LAYOUTS].sort());
    for (let s = 1; s <= SECTIONS; s++) for (const e of sectionPlan(T, seed, s).floors) for (const l of e.layouts) used.add(l.id);
  }
  assert.deepEqual([...used].sort(), [...LAYOUT_IDS].sort(), 'toute disposition sert quelque part');
});

test('thèmes des Cercles : 9 Cercles + finale, bestiaire pondéré par coût sans nom d\'archétype, tout le bestiaire présent', () => {
  assert.equal(T.circles.length, T.floors.circleNames.length + 1);
  const present = ROSTER.filter((r) => T.enemies[r.kind]);
  const base = Object.fromEntries(present.map((r) => [r.kind, r.weight]));
  // Cercle 1 neutre : les poids d'origine, à l'identique.
  for (const r of sectionPlan(T, 1, 1).floors.at(-2).roster) assert.equal(r.weight, base[r.kind]);
  for (let s = 2; s <= SECTIONS; s++) {
    const plan = sectionPlan(T, 3, s);
    const theme = circleTheme(T, plan.circle);
    const roster = plan.floors[0].roster;
    assert.deepEqual(roster.map((r) => r.kind).sort(), present.map((r) => r.kind).sort(), `section ${s} : un archétype présent manque au tirage`);
    assert.equal(plan.theme.featured.length, Math.min(theme.featured, present.length));
    // Biais de coût : à poids de base égal, le plus cher gagne si costBias > 0, perd si < 0.
    const ratio = (r) => r.weight / base[r.kind] / (plan.theme.featured.includes(r.kind) ? theme.featuredMult : 1);
    const cheap = roster.reduce((a, b) => (b.cost < a.cost ? b : a));
    const dear = roster.reduce((a, b) => (b.cost > a.cost ? b : a));
    const sign = Math.sign(ratio(dear) - ratio(cheap));
    assert.equal(sign, Math.sign(theme.costBias), `section ${s} : biais de coût ${theme.costBias}`);
  }
  // Aucun nom d'archétype dans le plan ni dans les thèmes : un archétype ajouté y entre seul.
  const src = readFileSync(new URL('../src/sim/sections.mjs', import.meta.url), 'utf8');
  const themes = JSON.stringify(T.circles);
  for (const kind of Object.keys(T.enemies)) {
    assert.ok(!src.includes(`'${kind}'`), `sections.mjs nomme l'archétype ${kind}`);
    assert.ok(!themes.includes(`"${kind}"`), `tuning.circles nomme l'archétype ${kind}`);
  }
});

test('arène d\'essai : les vagues sans fin suivent le plan d\'un étage de début de section', () => {
  const g = createGame({ seed: 2, sandbox: true });
  assert.ok(g.room.refill && g.room.refill.waves >= 1);
  g.enemies.length = 0;
  g.spawns.length = 0;
  g.room.waveIndex = g.room.waves.length - 1;
  stepGame(g, emptyInput());
  assert.ok(g.spawns.length > 0, 'nouvelles vagues');
  assert.equal(g.room.waves.length, g.room.refill.waves);
});
