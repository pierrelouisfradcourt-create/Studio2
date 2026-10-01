// Tests V2 — LA BOUCLE : Ville → donjon → Gardien → checkpoint, PERMANENT vs TEMPORAIRE, et
// le LABO du feel (D5, D8, D9 restent ouvertes : on teste que chaque variante fait ce qu'elle dit,
// jamais laquelle est « la bonne »).
//
// Fichier NEUF (régime des tests du studio : créer est permis, modifier un test existant ne l'est
// pas). Les valeurs viennent du tuning ou du profil, jamais recopiées : un réglage ne casse pas un
// test, une règle cassée oui. Le contenu d'essai (classe, arme, compétence, gadget payants) est
// AJOUTÉ à une copie du tuning sous des identifiants « v2t_* » : ces tests ne dépendent pas du
// catalogue réel des kits, qui évolue en parallèle.
//
// Lancement : node --test tests/

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createGame, stepGame, applyCommand, emptyInput, stateHash, DT } from '../src/sim/game.mjs';
import { createTuning, DEFAULT_TUNING } from '../src/sim/config.mjs';
import { createEnemy } from '../src/sim/enemies.mjs';
import { damagePlayer, killEnemy } from '../src/sim/combat.mjs';
import { spawnProjectile } from '../src/sim/projectiles.mjs';
import { floorInfo, sectionBounds, guardianFor } from '../src/sim/floors.mjs';
import { generateItem } from '../src/sim/loot.mjs';
import { addBoon, BOONS } from '../src/sim/boons.mjs';
import { openInteract } from '../src/sim/run.mjs';
import { LAB_AXES, applyLab, setLab, labSummary } from '../src/sim/lab.mjs';
import {
  PROFILE_SCHEMA, STASH_MAX, createProfile, sanitizeProfile, unlock, unlockCost, buyUpgrade, upgradeCost,
  selectClass, selectSkill, selectGadget, equipFromStash, salvageFromStash, salvageSouls, starterWeapon,
} from '../src/sim/profile.mjs';
import { POLICIES, resolveChoice } from '../tools/bots.mjs';
import { runEpisode } from '../tools/playtest.mjs';

// ---------------------------------------------------------------- outils

const SECTION = DEFAULT_TUNING.floors.sectionLength;
const GUARDIAN_FLOOR = SECTION; // 18
const CHECKPOINT = SECTION + 1; // 19
const SETTLE_TICKS = 240; // garde-fou des boucles « jusqu'à ce que… »
const DETERMINISM_TICKS = 1800; // 30 s de jeu

const ticks = (seconds) => Math.ceil(seconds / DT);

function input(over = {}) {
  return { ...emptyInput(), ...over };
}

function steps(g, n, over = {}) {
  for (let i = 0; i < n; i++) stepGame(g, input(over));
}

/** Partie de test : salle vidée (aucune vague), héros au centre, rien ne l'interrompt. */
function sandbox(opts = {}) {
  const g = createGame({ seed: 21, ...opts });
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

/** Ennemi immobile au combat (ne riposte pas), très résistant : on teste le héros. */
function dummy(g, dx, dy, kind = 'brute') {
  const e = createEnemy(g, kind, g.player.x + dx, g.player.y + dy, { spawnT: 0 });
  e.cooldown = 99;
  e.hp = 99999;
  e.maxHp = 99999;
  return e;
}

/** Tue le Gardien de la salle et laisse la salle se résoudre (checkpoint, portes). */
function defeatGuardian(g) {
  const boss = g.enemies.find((e) => e.boss);
  assert.ok(boss, 'un Gardien doit être présent');
  for (const e of g.enemies) if (!e.dead && !e.boss) e.dead = true;
  g.spawns.length = 0;
  killEnemy(g, boss, { kind: 'melee' });
  for (let i = 0; i < SETTLE_TICKS && !g.room.cleared; i++) stepGame(g, input());
  assert.equal(g.room.cleared, true, 'la salle du Gardien doit être nettoyée');
}

/** Pose le héros dans la porte d'indice i et laisse la simulation la franchir. */
function takeDoor(g, i) {
  const d = g.room.doors[i];
  assert.ok(d && d.open, `porte ${i} ouverte`);
  g.room.interact = null; // le butin du Gardien n'est pas sur le chemin du test
  g.player.x = d.x + d.w / 2;
  g.player.y = d.y + d.h + g.player.r - 2;
  stepGame(g, input());
}

function kill(g, source = 'test') {
  g.godMode = false;
  g.player.iframes = 0;
  damagePlayer(g, 99999, { kind: source, id: 4242 });
  for (let i = 0; i < SETTLE_TICKS && g.mode === 'play'; i++) stepGame(g, input());
  assert.equal(g.mode, 'dead');
}

/** Copie du tuning avec du contenu d'essai payant (une classe, son arme, sa compétence, son gadget). */
function contentWithExtras() {
  const lame = DEFAULT_TUNING.weapons[DEFAULT_TUNING.classes[Object.keys(DEFAULT_TUNING.classes)[0]].weapons[0]];
  const skill = Object.values(DEFAULT_TUNING.skills)[0];
  const gadget = Object.values(DEFAULT_TUNING.gadgets)[0];
  const superId = Object.keys(DEFAULT_TUNING.supers)[0];
  return createTuning(structuredClone({
    weapons: {
      v2t_faux: { ...lame, name: 'Faux d\'essai', className: 'v2t_faucheur', starterName: 'Faux d\'essai', cost: 30 },
      v2t_serpe: { ...lame, name: 'Serpe d\'essai', className: 'v2t_faucheur', starterName: 'Serpe d\'essai', cost: 25 },
    },
    skills: { v2t_trait: { ...skill, name: 'Trait d\'essai', cost: 20 } },
    gadgets: { v2t_fiole: { ...gadget, name: 'Fiole d\'essai', cost: 10 } },
    classes: {
      v2t_faucheur: {
        name: 'Faucheur d\'essai', text: 'Classe de test.', stats: { maxHpBonus: 7 }, cost: 50,
        weapons: ['v2t_faux', 'v2t_serpe'], skills: ['v2t_trait'], gadgets: ['v2t_fiole'], super: superId,
      },
    },
  }));
}

const firstClassId = (t) => Object.keys(t.classes)[0];
// Deux bénédictions d'emplacements différents (une bénédiction d'attaque en remplace une autre).
const BOON_A = BOONS.find((b) => b.slot === 'attack');
const BOON_B = BOONS.find((b) => b.slot === 'passive');

// ---------------------------------------------------------------- profil

test('profil neuf : schéma courant, checkpoint 1, kit de départ de la 1re classe, rien dans le coffre', () => {
  const t = createTuning();
  const p = createProfile(t);
  const c = t.classes[firstClassId(t)];
  assert.equal(p.schema, PROFILE_SCHEMA);
  assert.deepEqual(p.checkpoints, [1]);
  assert.equal(p.souls, 0);
  assert.equal(p.gold, 0);
  assert.deepEqual(p.unlocked, { classes: [firstClassId(t)], weapons: [c.weapons[0]], skills: [c.skills[0]], gadgets: [c.gadgets[0]] });
  assert.deepEqual(p.loadout, { classId: firstClassId(t), skillId: c.skills[0], gadgetId: c.gadgets[0] });
  assert.deepEqual(p.stash, []);
  // La 1re partie complète l'équipement vide avec l'équipement de départ (permanent).
  const g = createGame({ seed: 1, meta: p });
  assert.ok(g.meta.equipment.arme && g.meta.equipment.armure);
  assert.equal(g.run.items, g.meta.equipment, 'run.items EST l\'équipement du profil');
});

test('profil : migration d\'une sauvegarde schéma 2 {checkpoints, bestFloor, items, snapshots}', () => {
  const t = createTuning();
  const g0 = createGame({ seed: 3 });
  const arme = generateItem(g0, { slot: 'arme', rarity: 'rare' });
  const armure = generateItem(g0, { slot: 'armure', rarity: 'magique' });
  const old = {
    checkpoints: [1, 7, 13, CHECKPOINT],
    bestFloor: 22,
    items: { arme, armure, talisman: null },
    snapshots: { 7: { boons: [{ id: BOONS[0].id, rarity: 'rare', level: 1 }], gold: 120 } },
  };
  const p = sanitizeProfile(JSON.parse(JSON.stringify(old)), t);
  assert.equal(p.schema, PROFILE_SCHEMA);
  // Les checkpoints d'avant la V2 (Gardien tous les 6 étages : 7, 13) ne sont plus des points de
  // reprise : seuls restent l'étage 1 et les débuts de section (étage qui suit un Gardien).
  assert.deepEqual(p.checkpoints, [1, CHECKPOINT]);
  for (const f of p.checkpoints) assert.equal(floorInfo(t, f).indexInSection, 1);
  assert.equal(p.bestFloor, 22);
  assert.equal(p.equipment.arme.name, arme.name, 'l\'équipement de l\'ancien champ `items` est repris');
  assert.equal(p.equipment.armure.name, armure.name);
  assert.ok(p.equipment.arme.uid && p.equipment.armure.uid, 'chaque objet repris reçoit un identifiant stable');
  assert.equal(p.snapshots, undefined, 'les instantanés de build sont abandonnés');
  // Repartir du checkpoint migré : aucune bénédiction (le temporaire ne survit pas), l'équipement est là.
  const g = createGame({ seed: 3, meta: old, startFloor: CHECKPOINT });
  assert.deepEqual(g.run.boons, []);
  assert.equal(g.run.items.arme.name, arme.name);
});

test('profil : données corrompues ou hostiles → défauts, jamais de blocage', () => {
  const t = createTuning();
  for (const raw of [null, undefined, 42, 'texte', [], [1, 2]]) assert.deepEqual(sanitizeProfile(raw, t), createProfile(t));
  const bad = {
    checkpoints: 'x', bestFloor: 1e9, souls: -50, gold: Number.NaN,
    unlocked: { classes: ['inconnue', 42, null], weapons: 'lame', skills: [{}], gadgets: null },
    upgrades: { vitalite: 99, inconnue: 1, celerite: -1, ferocite: 1.5 },
    loadout: { classId: 'inconnue', skillId: 7, gadgetId: 'nope' },
    equipment: { arme: { slot: 'armure', name: 'x', affixes: [], base: {} }, armure: 'chaîne', talisman: { slot: 'talisman' } },
    stash: [1, null, {}, { slot: 'arme', name: 'bonne', affixes: [], base: { damage: 3 } }],
    itemSeq: -4, guardians: { inconnu: 3, [Object.keys(t.boss)[0]]: 'x' }, stats: { runs: -1, deaths: 'beaucoup', kills: 5 },
  };
  const p = sanitizeProfile(structuredClone(bad), t);
  assert.deepEqual(p.checkpoints, [1]);
  assert.equal(p.bestFloor, 1);
  assert.equal(p.souls, 0);
  assert.equal(p.gold, 0);
  assert.deepEqual(p.unlocked, createProfile(t).unlocked);
  assert.deepEqual(p.upgrades, {});
  assert.deepEqual(p.loadout, createProfile(t).loadout);
  assert.deepEqual(p.equipment, { arme: null, armure: null, talisman: null });
  assert.equal(p.stash.length, 1);
  assert.equal(p.stash[0].name, 'bonne');
  assert.deepEqual(p.guardians, {});
  assert.deepEqual(p.stats, { runs: 0, deaths: 0, kills: 5, guardianKills: 0 });
  // Une partie démarre avec ce profil réparé.
  const g = createGame({ seed: 5, meta: bad });
  assert.equal(g.mode, 'play');
  assert.ok(g.player.hp > 0);
  // Coffre plein : la migration le borne.
  const many = Array.from({ length: STASH_MAX + 10 }, (_, i) => ({ slot: 'armure', name: `a${i}`, affixes: [], base: { hp: 1 } }));
  assert.equal(sanitizeProfile({ stash: many }, t).stash.length, STASH_MAX);
});

test('profil : un aller-retour JSON (sauvegarde puis relance) ne change rien', () => {
  const t = createTuning();
  const g = createGame({ seed: 8 });
  g.meta.souls = 77;
  g.meta.upgrades.vitalite = 2;
  g.meta.checkpoints.push(CHECKPOINT);
  const p = sanitizeProfile(JSON.parse(JSON.stringify(g.meta)), t);
  assert.deepEqual(sanitizeProfile(JSON.parse(JSON.stringify(p)), t), p);
  assert.equal(p.souls, 77);
  assert.equal(p.upgrades.vitalite, 2);
  assert.deepEqual(p.checkpoints, [1, CHECKPOINT]);
});

// ---------------------------------------------------------------- mort : temporaire perdu, permanent gardé

test('mort : bénédictions remises à zéro ; équipement, coffre, kit, Âmes, déblocages, améliorations conservés ; taxe de Charon', () => {
  const g = createGame({ seed: 12 });
  const meta = g.meta;
  meta.souls = 120;
  meta.upgrades.vitalite = 1;
  const arme = generateItem(g, { slot: 'arme', rarity: 'rare' });
  const coffre = generateItem(g, { slot: 'talisman', rarity: 'magique' });
  g.run.items.arme = arme;
  meta.stash.push(coffre);
  addBoon(g.run, { id: BOON_A.id, rarity: 'rare' });
  addBoon(g.run, { id: BOON_B.id, rarity: 'commun' });
  g.run.gold = 101;
  const before = structuredClone({ loadout: meta.loadout, unlocked: meta.unlocked, upgrades: meta.upgrades, checkpoints: meta.checkpoints });
  kill(g);
  // Récapitulatif de mort : ce qui est perdu (temporaire) et ce qui est gardé (permanent).
  const r = g.run.deathRecap;
  assert.equal(r.boonsLost, 2);
  assert.equal(r.goldLost, 101 - Math.floor(101 * g.tuning.economy.deathGoldKeep));
  assert.equal(g.run.gold, Math.floor(101 * g.tuning.economy.deathGoldKeep), 'Charon prélève sa part');
  assert.equal(meta.gold, g.run.gold, 'la bourse du profil suit');
  assert.equal(meta.stats.deaths, 1);
  assert.equal(applyCommand(g, { type: 'respawn' }), true);
  assert.equal(g.mode, 'play');
  assert.deepEqual(g.run.boons, [], 'le temporaire repart de zéro');
  assert.equal(g.run.items.arme, arme, 'équipement conservé');
  assert.ok(meta.stash.includes(coffre), 'coffre conservé');
  assert.equal(meta.souls, 120, 'Âmes conservées');
  assert.deepEqual({ loadout: meta.loadout, unlocked: meta.unlocked, upgrades: meta.upgrades, checkpoints: meta.checkpoints }, before);
  assert.equal(g.player.hp, g.player.maxHp);
  // Les PV max après la reprise = ceux d'une partie neuve avec le même profil (Vitalité comprise).
  const ref = createGame({ seed: 12, meta });
  assert.equal(g.player.maxHp, ref.player.maxHp);
  assert.ok(g.player.stats.maxHpBonus >= g.tuning.town.upgrades.vitalite.perLevel, 'l\'amélioration de Vitalité compte toujours');
});

test('mort : l\'amélioration « Avidité de Charon » réduit la taxe (bornée à 100 %)', () => {
  const up = DEFAULT_TUNING.town.upgrades.avidite;
  for (let lv = 0; lv <= up.max; lv++) {
    const meta = createProfile(createTuning());
    meta.upgrades.avidite = lv;
    const g2 = createGame({ seed: 13, meta });
    g2.run.gold = 200;
    kill(g2);
    const keep = Math.min(1, g2.tuning.economy.deathGoldKeep + up.perLevel * lv);
    assert.equal(g2.run.gold, Math.floor(200 * keep), `Avidité niveau ${lv}`);
  }
});

test('mort : reprise au DERNIER checkpoint par défaut ; un point de TP débloqué peut être choisi ; un étage non débloqué est refusé', () => {
  const t = createTuning();
  const cp2 = sectionBounds(t, 2).checkpoint; // 37
  const g = createGame({ seed: 14, startFloor: cp2 + 3, meta: { checkpoints: [1, CHECKPOINT, cp2] } });
  assert.deepEqual(g.meta.checkpoints, [1, CHECKPOINT, cp2]);
  kill(g);
  assert.equal(g.run.deathRecap.checkpoint, cp2);
  applyCommand(g, { type: 'respawn' });
  assert.equal(g.run.floor, cp2, 'dernier checkpoint');
  kill(g);
  applyCommand(g, { type: 'respawn', floor: CHECKPOINT });
  assert.equal(g.run.floor, CHECKPOINT, 'point de téléportation choisi');
  kill(g);
  applyCommand(g, { type: 'respawn', floor: cp2 + 5 });
  assert.equal(g.run.floor, cp2, 'un étage non débloqué retombe sur le dernier checkpoint');
  assert.equal(applyCommand(g, { type: 'respawn' }), false, 'pas de reprise sans être mort');
});

// ---------------------------------------------------------------- Gardien, checkpoint, téléportation

test('Gardien vaincu (étage 18) : checkpoint 19 + point de TP, Âmes, butin, portes [suite, Ville]', () => {
  const g = createGame({ seed: 15, startFloor: GUARDIAN_FLOOR });
  assert.equal(g.info.isBoss, true);
  const kind = guardianFor(g.tuning, 1);
  assert.ok(g.enemies.some((e) => e.boss && e.kind === kind), 'le Gardien de la section 1');
  const souls0 = g.meta.souls;
  defeatGuardian(g);
  assert.ok(g.meta.checkpoints.includes(CHECKPOINT), 'checkpoint 19');
  assert.equal(g.meta.guardians[kind], 1);
  assert.equal(g.meta.stats.guardianKills, 1);
  assert.equal(g.meta.souls, souls0 + g.tuning.progression.souls.guardian);
  assert.ok(g.events.some((e) => e.type === 'checkpoint' && e.floor === CHECKPOINT));
  assert.equal(g.room.interact?.kind, 'loot', 'butin du Gardien');
  const rewards = g.room.doors.map((d) => d.reward);
  assert.equal(rewards.length, 2);
  assert.equal(rewards[1], 'town', 'portail de la Ville');
  assert.ok(!['town', 'boss'].includes(rewards[0]), `porte de la section suivante : ${rewards[0]}`);
  assert.ok(g.room.doors.every((d) => d.open));
  // Point de téléportation : une nouvelle descente peut partir de l'étage 19.
  const tp = createGame({ seed: 16, meta: g.meta, startFloor: CHECKPOINT });
  assert.equal(tp.run.floor, CHECKPOINT);
  assert.equal(tp.info.indexInSection, 1);
});

test('après le Gardien, « suite » garde le build (pas d\'instantané) ; mourir plus loin le vide quand même', () => {
  const g = createGame({ seed: 17, startFloor: GUARDIAN_FLOOR });
  addBoon(g.run, { id: BOONS[0].id, rarity: 'rare' });
  defeatGuardian(g);
  takeDoor(g, 0);
  assert.equal(g.run.floor, CHECKPOINT);
  assert.equal(g.mode, 'play');
  assert.equal(g.run.boons.length, 1, 'le run continue avec son build');
  addBoon(g.run, { id: BOON_B.id, rarity: 'commun' });
  assert.equal(g.run.boons.length, 2);
  kill(g);
  applyCommand(g, { type: 'respawn' });
  assert.equal(g.run.floor, CHECKPOINT);
  assert.deepEqual(g.run.boons, [], 'aucun build figé au Gardien');
});

test('retour en Ville par le portail : fin du run sans taxe, checkpoint gardé, nouvelle descente sans bénédiction', () => {
  const g = createGame({ seed: 18, startFloor: GUARDIAN_FLOOR });
  addBoon(g.run, { id: BOONS[0].id, rarity: 'rare' });
  g.run.gold = 90;
  defeatGuardian(g);
  const arme = g.run.items.arme;
  takeDoor(g, 1);
  assert.equal(g.mode, 'town');
  assert.ok(g.events.some((e) => e.type === 'returnTown'));
  assert.equal(g.meta.gold, 90, 'le portail n\'est pas une mort : Charon ne prend rien');
  assert.equal(g.meta.stats.deaths, 0);
  assert.ok(g.meta.checkpoints.includes(CHECKPOINT));
  // La partie terminée ne bouge plus.
  const tick = g.tick;
  steps(g, 30);
  assert.equal(g.tick, tick);
  // Ville → nouvelle descente depuis le checkpoint (ce que fait main.mjs avec le profil sauvegardé).
  const saved = JSON.parse(JSON.stringify(g.meta));
  const g2 = createGame({ seed: 19, meta: saved, startFloor: CHECKPOINT });
  assert.equal(g2.run.floor, CHECKPOINT);
  assert.deepEqual(g2.run.boons, []);
  assert.equal(g2.run.gold, 90);
  assert.equal(g2.run.items.arme.name, arme.name);
});

test('retour en Ville par la commande : depuis l\'écran de mort, ou au portail ouvert ; jamais en plein combat', () => {
  const g = createGame({ seed: 20, startFloor: 2 });
  assert.equal(applyCommand(g, { type: 'returnToTown' }), false, 'pas de sortie gratuite en plein combat (c\'est « abandon »)');
  assert.equal(g.mode, 'play');
  g.run.gold = 50;
  kill(g);
  const taxed = g.run.gold;
  assert.equal(applyCommand(g, { type: 'returnToTown' }), true);
  assert.equal(g.mode, 'town');
  assert.equal(g.meta.gold, taxed, 'la taxe a été payée une seule fois, à la mort');
  // Au portail du Gardien, la commande équivaut à franchir la porte « Ville ».
  const b = createGame({ seed: 20, startFloor: GUARDIAN_FLOOR });
  defeatGuardian(b);
  assert.equal(applyCommand(b, { type: 'returnToTown' }), true);
  assert.equal(b.mode, 'town');
  assert.equal(applyCommand(b, { type: 'returnToTown' }), false, 'déjà en Ville');
});

test('abandon : compte comme une mort (taxe, récap, bénédictions perdues) et ramène en Ville', () => {
  const g = createGame({ seed: 22, startFloor: 3 });
  addBoon(g.run, { id: BOONS[0].id, rarity: 'commun' });
  g.run.gold = 80;
  assert.equal(applyCommand(g, { type: 'abandon' }), true);
  assert.equal(g.mode, 'town');
  assert.equal(g.meta.gold, Math.floor(80 * g.tuning.economy.deathGoldKeep));
  assert.equal(g.meta.stats.deaths, 1);
  assert.equal(g.run.deathRecap.boonsLost, 1);
  assert.equal(applyCommand(g, { type: 'abandon' }), false, 'rien à abandonner hors partie');
  // Abandon pendant un menu de choix.
  const c = createGame({ seed: 23 });
  c.mode = 'choice';
  c.choice = { kind: 'boon', options: [] };
  assert.equal(applyCommand(c, { type: 'abandon' }), true);
  assert.equal(c.mode, 'town');
});

test('entraînement (Ville → « Défier ») : ni Âmes, ni checkpoint, ni taxe ; seule porte : la Ville', () => {
  const t = createTuning();
  const meta = createProfile(t);
  meta.gold = 60;
  const g = createGame({ seed: 24, startFloor: GUARDIAN_FLOOR, practice: true, meta });
  assert.equal(g.practice, true);
  assert.equal(g.meta.stats.runs, 0, 'un entraînement n\'est pas une descente');
  const before = structuredClone({ souls: g.meta.souls, checkpoints: g.meta.checkpoints, guardians: g.meta.guardians, kills: g.meta.stats.guardianKills });
  // Mourir à l'entraînement : aucune taxe, aucune mort comptée.
  kill(g);
  assert.equal(g.run.gold, 60);
  assert.equal(g.meta.stats.deaths, 0);
  applyCommand(g, { type: 'respawn' });
  assert.equal(g.run.floor, GUARDIAN_FLOOR);
  defeatGuardian(g);
  assert.deepEqual({ souls: g.meta.souls, checkpoints: g.meta.checkpoints, guardians: g.meta.guardians, kills: g.meta.stats.guardianKills }, before);
  assert.deepEqual(g.room.doors.map((d) => d.reward), ['town']);
  assert.equal(g.room.interact, null, 'aucun butin');
  takeDoor(g, 0);
  assert.equal(g.mode, 'town');
});

test('Âmes : chaque ennemi tué en donjon en rapporte (pas les invocations, pas l\'arène, pas l\'entraînement)', () => {
  const souls = DEFAULT_TUNING.progression.souls;
  const count = (opts, summoned = false) => {
    const g = sandbox(opts);
    const e = createEnemy(g, 'imp', g.player.x + 300, g.player.y, { spawnT: 0, summoned });
    const s0 = g.meta.souls;
    killEnemy(g, e, { kind: 'melee' });
    return g.meta.souls - s0;
  };
  assert.equal(count({}), souls.kill);
  assert.equal(count({}, true), 0);
  assert.equal(count({ sandbox: true }), 0);
  assert.equal(count({ practice: true }), 0);
});

// ---------------------------------------------------------------- opérations de la Ville

test('Ville · déblocage : refus (Âmes insuffisantes, inconnu, déjà débloqué), paiement, arme forgée au coffre', () => {
  const t = contentWithExtras();
  const p = createProfile(t);
  assert.equal(unlockCost(t, 'classes', 'v2t_faucheur'), 50);
  assert.equal(unlockCost(t, 'classes', firstClassId(t)), t.classes[firstClassId(t)].cost ?? 0);
  assert.deepEqual(unlock(p, t, 'classes', 'v2t_faucheur'), { ok: false, reason: 'Âmes insuffisantes' });
  assert.deepEqual(unlock(p, t, 'classes', 'introuvable'), { ok: false, reason: 'inconnu' });
  assert.deepEqual(unlock(p, t, 'pouvoirs', 'v2t_faucheur'), { ok: false, reason: 'inconnu' });
  assert.deepEqual(unlock(p, t, 'classes', firstClassId(t)), { ok: false, reason: 'déjà débloqué' });
  p.souls = 75;
  assert.deepEqual(unlock(p, t, 'classes', 'v2t_faucheur'), { ok: true });
  assert.equal(p.souls, 25);
  assert.ok(p.unlocked.classes.includes('v2t_faucheur'));
  assert.deepEqual(unlock(p, t, 'classes', 'v2t_faucheur'), { ok: false, reason: 'déjà débloqué' });
  // Le kit de départ de la classe vient avec elle ; le reste de son arsenal se paie.
  assert.deepEqual(unlock(p, t, 'skills', 'v2t_trait'), { ok: false, reason: 'déjà débloqué' });
  assert.deepEqual(unlock(p, t, 'gadgets', 'v2t_fiole'), { ok: false, reason: 'déjà débloqué' });
  assert.deepEqual(unlock(p, t, 'weapons', 'v2t_faux'), { ok: false, reason: 'déjà débloqué' });
  p.souls = 24;
  assert.deepEqual(unlock(p, t, 'weapons', 'v2t_serpe'), { ok: false, reason: 'Âmes insuffisantes' });
  assert.equal(p.souls, 24, 'un refus ne prélève rien');
  // Arme : forgée en exemplaire commun et rangée au coffre.
  p.souls = 25;
  const stash0 = p.stash.length;
  assert.deepEqual(unlock(p, t, 'weapons', 'v2t_serpe'), { ok: true });
  assert.equal(p.souls, 0);
  assert.equal(p.stash.length, stash0 + 1);
  const forged = p.stash[p.stash.length - 1];
  assert.equal(forged.weaponType, 'v2t_serpe');
  assert.equal(forged.rarity, 'commun');
  assert.ok(forged.uid);
});

test('Ville · classe : verrouillée refusée ; choisie, elle apporte son arme (l\'ancienne au coffre) et son kit de départ', () => {
  const t = contentWithExtras();
  const p = createProfile(t);
  const g = createGame({ seed: 30, tuning: t, meta: p }); // 1re partie : équipement de départ
  const profile = structuredClone(g.meta);
  const oldWeapon = profile.equipment.arme;
  assert.deepEqual(selectClass(profile, t, 'v2t_faucheur'), { ok: false, reason: 'classe verrouillée' });
  profile.souls = 50;
  assert.equal(unlock(profile, t, 'classes', 'v2t_faucheur').ok, true);
  assert.deepEqual(selectClass(profile, t, 'v2t_faucheur'), { ok: true });
  assert.equal(profile.loadout.classId, 'v2t_faucheur');
  assert.equal(profile.equipment.arme.weaponType, 'v2t_faux', 'arme de départ de la classe');
  assert.ok(profile.stash.some((it) => it.name === oldWeapon.name && it.weaponType === oldWeapon.weaponType), 'l\'ancienne arme est au coffre');
  // Le kit de départ de la classe (1re arme, 1re compétence, 1er gadget) est possédé, pas « à débloquer ».
  assert.ok(profile.unlocked.weapons.includes('v2t_faux'));
  assert.ok(profile.unlocked.skills.includes('v2t_trait'));
  assert.ok(profile.unlocked.gadgets.includes('v2t_fiole'));
  assert.equal(profile.loadout.skillId, 'v2t_trait');
  assert.equal(profile.loadout.gadgetId, 'v2t_fiole');
  // La 2e arme de la classe reste à forger.
  assert.ok(!profile.unlocked.weapons.includes('v2t_serpe'));
  // La partie suivante joue le kit choisi (permanent).
  const g2 = createGame({ seed: 31, tuning: t, meta: profile });
  assert.equal(g2.kit.classId, 'v2t_faucheur');
  assert.equal(g2.kit.weaponType, 'v2t_faux');
  assert.equal(g2.player.stats.maxHpBonus, 7, 'bonus permanent de la classe');
  // Revenir à la classe de départ : son arme ressort du coffre.
  assert.deepEqual(selectClass(profile, t, firstClassId(t)), { ok: true });
  assert.equal(profile.equipment.arme.name, oldWeapon.name);
});

test('Ville · compétence et gadget : seulement ceux de la classe, et débloqués', () => {
  const t = contentWithExtras();
  const p = createProfile(t);
  const c0 = t.classes[firstClassId(t)];
  assert.deepEqual(selectSkill(p, t, 'v2t_trait'), { ok: false, reason: 'indisponible' });
  assert.deepEqual(selectGadget(p, t, 'v2t_fiole'), { ok: false, reason: 'indisponible' });
  assert.deepEqual(selectSkill(p, t, c0.skills[0]), { ok: true });
  assert.deepEqual(selectGadget(p, t, c0.gadgets[0]), { ok: true });
  p.souls = 999;
  unlock(p, t, 'skills', 'v2t_trait');
  assert.deepEqual(selectSkill(p, t, 'v2t_trait'), { ok: false, reason: 'indisponible' }, 'débloquée mais d\'une autre classe');
});

test('Ville · Sanctuaire : refus (Âmes insuffisantes, niveau maximal), prix par niveau, effet sur la partie suivante', () => {
  const t = createTuning();
  const up = t.town.upgrades.vitalite;
  const p = createProfile(t);
  assert.deepEqual(buyUpgrade(p, t, 'vitalite'), { ok: false, reason: 'Âmes insuffisantes' });
  assert.deepEqual(buyUpgrade(p, t, 'inconnue'), { ok: false, reason: 'niveau maximal' });
  p.souls = up.costs.reduce((a, b) => a + b, 0) + 3;
  for (let lv = 0; lv < up.max; lv++) {
    assert.equal(upgradeCost(t, 'vitalite', lv), up.costs[lv]);
    assert.deepEqual(buyUpgrade(p, t, 'vitalite'), { ok: true });
    assert.equal(p.upgrades.vitalite, lv + 1);
  }
  assert.equal(p.souls, 3);
  assert.equal(upgradeCost(t, 'vitalite', up.max), null);
  assert.deepEqual(buyUpgrade(p, t, 'vitalite'), { ok: false, reason: 'niveau maximal' });
  const base = createGame({ seed: 32 });
  const boosted = createGame({ seed: 32, meta: p });
  assert.equal(boosted.player.maxHp - base.player.maxHp, up.perLevel * up.max);
  assert.equal(boosted.player.hp, boosted.player.maxHp);
});

test('Ville · coffre : équiper (l\'objet porté prend sa place), refus d\'une arme d\'une autre classe, recycler en Âmes', () => {
  const t = contentWithExtras();
  const g = createGame({ seed: 33, tuning: t });
  const p = structuredClone(g.meta);
  const worn = p.equipment.armure;
  const armure = { ...generateItem(g, { slot: 'armure', rarity: 'rare' }), uid: 'u-armure' };
  const faux = { ...starterWeapon(t, 'v2t_faux'), uid: 'u-faux' };
  const tal = { ...generateItem(g, { slot: 'talisman', rarity: 'legendaire' }), uid: 'u-tal' };
  p.stash.push(armure, faux, tal);
  assert.deepEqual(equipFromStash(p, t, 'absent'), { ok: false, reason: 'objet introuvable' });
  assert.deepEqual(equipFromStash(p, t, 'u-faux'), { ok: false, reason: 'arme réservée à une autre classe' });
  assert.deepEqual(equipFromStash(p, t, 'u-armure'), { ok: true });
  assert.equal(p.equipment.armure, armure);
  assert.ok(p.stash.includes(worn), 'l\'armure portée part au coffre');
  assert.ok(!p.stash.includes(armure));
  const s0 = p.souls;
  assert.deepEqual(salvageFromStash(p, t, 'u-tal'), { ok: true });
  assert.equal(p.souls, s0 + salvageSouls(t, tal));
  assert.equal(salvageSouls(t, tal), t.town.salvageSouls.legendaire);
  assert.deepEqual(salvageFromStash(p, t, 'u-tal'), { ok: false, reason: 'objet introuvable' });
});

test('butin en donjon : équiper envoie l\'ancien au coffre ; « garder » le range ; arme d\'une autre classe refusée', () => {
  const t = contentWithExtras();
  const g = sandbox({ tuning: t });
  const old = g.run.items.arme;
  const found = generateItem(g, { slot: 'arme', rarity: 'rare', weaponType: g.kit.weaponType });
  g.room.interact = { kind: 'loot', x: g.player.x, y: g.player.y, r: 30, used: false, item: found };
  openInteract(g);
  assert.equal(g.mode, 'choice');
  assert.equal(applyCommand(g, { type: 'equip' }), true);
  assert.equal(g.run.items.arme, found);
  assert.equal(g.meta.equipment.arme, found, 'équipement PERMANENT');
  assert.ok(g.meta.stash.includes(old), 'l\'ancienne arme est au coffre, jamais perdue');
  assert.ok(old.uid, 'rangée avec un identifiant stable');
  // « Garder au coffre ».
  const tal = generateItem(g, { slot: 'talisman', rarity: 'magique' });
  g.room.interact = { kind: 'loot', x: g.player.x, y: g.player.y, r: 30, used: false, item: tal };
  openInteract(g);
  assert.equal(applyCommand(g, { type: 'stash' }), true);
  assert.ok(g.meta.stash.includes(tal));
  // Arme d'une autre classe : on ne l'équipe pas, on peut la garder pour plus tard.
  const faux = generateItem(g, { slot: 'arme', rarity: 'magique', weaponType: 'v2t_faux' });
  g.room.interact = { kind: 'loot', x: g.player.x, y: g.player.y, r: 30, used: false, item: faux };
  openInteract(g);
  assert.equal(g.choice.wieldable, false);
  assert.equal(applyCommand(g, { type: 'equip' }), false);
  assert.equal(applyCommand(g, { type: 'stash' }), true);
  assert.ok(g.meta.stash.includes(faux));
  // Tout survit à la mort.
  kill(g);
  applyCommand(g, { type: 'respawn' });
  assert.equal(g.run.items.arme, found);
  assert.ok(g.meta.stash.includes(tal) && g.meta.stash.includes(faux) && g.meta.stash.includes(old));
});

// ---------------------------------------------------------------- labo du feel

const LAB_DEFAULTS = { dashStrike: 'fin', hitstop: 'global', comboMobility: 'mobile' };

function readPath(obj, path) {
  return path.split('.').reduce((o, k) => o[k], obj);
}

test('labo : la variante par défaut de chaque axe redonne EXACTEMENT les valeurs d\'origine du tuning', () => {
  assert.deepEqual(DEFAULT_TUNING.lab, LAB_DEFAULTS);
  for (const [axis, def] of Object.entries(LAB_AXES)) {
    assert.equal(def.reference, DEFAULT_TUNING.lab[axis], `${axis} : la référence du labo est le réglage de config.mjs`);
    for (const [path, v] of Object.entries(def.options[def.reference].set)) {
      assert.equal(readPath(DEFAULT_TUNING, path), v, `${axis} : ${path}`);
    }
  }
  const raw = createTuning();
  const applied = applyLab(createTuning());
  assert.deepEqual(applied, raw, 'appliquer le labo par défaut ne change aucune valeur');
  // Labo absent, partiel ou illisible (vieille sauvegarde de réglages) : retour aux références.
  for (const lab of [null, {}, { comboMobility: 'inconnu', hitstop: 42 }]) {
    const t = createTuning();
    t.lab = lab;
    applyLab(t);
    t.lab = raw.lab;
    assert.deepEqual(t, raw, `labo ${JSON.stringify(lab)} : valeurs d'origine`);
  }
  // Une partie avec le labo explicite par défaut = la même partie, à l'octet près.
  const a = createGame({ seed: 40 });
  const b = createGame({ seed: 40, tuning: { lab: { ...LAB_DEFAULTS } } });
  const mem = [{}, {}];
  for (let i = 0; i < 900; i++) {
    for (const [k, g] of [a, b].entries()) {
      if (g.mode === 'choice') resolveChoice(g, 'skilled');
      stepGame(g, POLICIES.skilled(g, mem[k]));
    }
  }
  assert.equal(stateHash(a), stateHash(b));
});

test('labo : setLab change la variante en cours de partie ; une variante inconnue est refusée sans effet', () => {
  const g = sandbox();
  const before = structuredClone(g.tuning);
  assert.equal(setLab(g.tuning, 'hitstop', 'nimporte'), false);
  assert.equal(setLab(g.tuning, 'axeInconnu', 'local'), false);
  assert.deepEqual(g.tuning, before);
  assert.equal(setLab(g.tuning, 'hitstop', 'local'), true);
  assert.equal(g.tuning.hitstopMode, 'local');
  assert.equal(g.tuning.lab.hitstop, 'local');
  const sum = labSummary(g.tuning);
  assert.deepEqual(sum.map((s) => s.axis), Object.keys(LAB_AXES));
  assert.equal(sum.find((s) => s.axis === 'hitstop').choiceLabel, LAB_AXES.hitstop.options.local.label);
});

/** Dash vers la droite, puis attaque pressée à l'image suivante. Rend la trace du héros. */
function dashThenAttack(variant) {
  const g = sandbox({ tuning: { lab: { dashStrike: variant } } });
  const p = g.player;
  const x0 = p.x;
  stepGame(g, input({ moveX: 1, dashPressed: true }));
  assert.equal(p.state, 'dash');
  stepGame(g, input({ moveX: 1, attackPressed: true }));
  const trace = { g, x0, stateAfterPress: p.state, strikeAt: null, strike: null, cancels: 0, dashEndBeforeStrike: false };
  for (let i = 0; i < SETTLE_TICKS && trace.strikeAt === null; i++) {
    for (const ev of g.events) {
      if (ev.type === 'cancel' && ev.from === 'dash') trace.cancels++;
      if (ev.type === 'dashEnd') trace.dashEndBeforeStrike = true;
      if (ev.type === 'attackStart') {
        trace.strikeAt = p.x - x0;
        trace.strike = ev.strike;
      }
    }
    g.events.length = 0;
    if (trace.strikeAt === null) stepGame(g, input({ moveX: 1 }));
  }
  return trace;
}

test('labo D5 · toutDash : une attaque au DÉBUT du dash le coupe aussitôt en frappe de dash', () => {
  const tr = dashThenAttack('toutDash');
  const dist = tr.g.tuning.dash.distance;
  assert.equal(tr.stateAfterPress, 'attack', 'la frappe part à l\'image même');
  assert.equal(tr.strike, true, 'c\'est une frappe de dash');
  assert.equal(tr.cancels, 1, 'le dash est coupé');
  assert.equal(tr.dashEndBeforeStrike, false);
  assert.ok(tr.strikeAt < dist * 0.3, `frappe après ${tr.strikeAt.toFixed(0)} u (dash : ${dist} u)`);
});

test('labo D5 · fin (référence) : la même attaque attend la fin du dash (dernier 45 %) puis le coupe en frappe', () => {
  const tr = dashThenAttack('fin');
  const t = tr.g.tuning.dash;
  assert.equal(tr.stateAfterPress, 'dash', 'au début du dash, l\'attaque attend dans le tampon');
  assert.equal(tr.strike, true);
  assert.equal(tr.cancels, 1);
  assert.ok(tr.strikeAt >= t.distance * (1 - t.strikeCancelFrom) - 20, `frappe après ${tr.strikeAt.toFixed(0)} u`);
  assert.ok(tr.strikeAt < t.distance, 'le dash est tout de même coupé avant son terme');
});

test('labo D5 · apresDash : le dash n\'est JAMAIS coupé ; la frappe part après, à sa sortie', () => {
  const tr = dashThenAttack('apresDash');
  const dist = tr.g.tuning.dash.distance;
  assert.equal(tr.stateAfterPress, 'dash');
  assert.equal(tr.cancels, 0, 'aucune annulation du dash');
  assert.equal(tr.dashEndBeforeStrike, true, 'le dash va à son terme');
  assert.equal(tr.strike, true, 'l\'attaque qui suit est une frappe de dash');
  assert.ok(tr.strikeAt >= dist - 12, `frappe après ${tr.strikeAt.toFixed(0)} u (dash complet : ${dist} u)`);
  // Et une attaque tardive, dans la fenêtre d'après-dash, reste une frappe (même règle pour les trois variantes).
  for (const variant of Object.keys(LAB_AXES.dashStrike.options)) {
    const g = sandbox({ tuning: { lab: { dashStrike: variant } } });
    stepGame(g, input({ moveX: 1, dashPressed: true }));
    steps(g, ticks(g.tuning.dash.duration) + 2, { moveX: 1 });
    assert.equal(g.player.state, 'free');
    g.events.length = 0;
    stepGame(g, input({ attackPressed: true }));
    stepGame(g, input());
    const ev = g.events.find((e) => e.type === 'attackStart');
    assert.equal(ev?.strike, true, `${variant} : attaque dans la fenêtre d'après-dash = frappe`);
  }
});

/**
 * Scène D8 : le héros frappe une brute ; un diablotin marche au loin ; un projectile ennemi vole
 * ailleurs. Rend l'état juste après l'impact, et une image plus tard.
 */
function hitstopScene(mode) {
  const g = sandbox({ tuning: { lab: { hitstop: mode } } });
  const p = g.player;
  const brute = dummy(g, 60, 0);
  const imp = createEnemy(g, 'imp', p.x - 420, p.y + 200, { spawnT: 0 });
  imp.cooldown = 99;
  const arrow = spawnProjectile(g, { owner: 'enemy', kind: 'arrow', x: 160, y: 120, vx: 300, vy: 0, r: 7, damage: 5, range: 5000 });
  let hitTick = -1;
  for (let i = 0; i < SETTLE_TICKS && hitTick < 0; i++) {
    stepGame(g, input({ attackPressed: i === 0, aimX: 1 }));
    if (g.events.some((e) => e.type === 'hit' || e.type === 'enemyHit') || brute.hp < brute.maxHp) hitTick = g.tick;
    g.events.length = 0;
  }
  assert.ok(hitTick > 0, 'le coup doit porter');
  const snap = () => ({ time: g.time, px: p.x, aT: p.attack?.t ?? null, bx: brute.x, by: brute.y, ix: imp.x, iy: imp.y, ax: arrow.x, ay: arrow.y });
  const at = snap();
  stepGame(g, input({ aimX: 1 }));
  return { g, at, next: snap(), brute, imp };
}

test('labo D8 · local : le héros et l\'ennemi touché se figent ; le projectile ennemi et les autres ennemis continuent', () => {
  const { g, at, next } = hitstopScene('local');
  assert.equal(g.hitstop, 0, 'aucun gel global');
  assert.ok(next.time > at.time, 'le temps du monde avance');
  assert.equal(next.aT, at.aT, 'le coup du héros est figé');
  assert.equal(next.px, at.px);
  assert.equal(next.bx, at.bx);
  assert.equal(next.by, at.by);
  assert.ok(Math.abs(next.ax - at.ax - 300 * DT) < 1e-6, 'le projectile ennemi avance pendant le gel');
  assert.ok(Math.hypot(next.ix - at.ix, next.iy - at.iy) > 0, 'un autre ennemi bouge pendant le gel');
});

test('labo D8 · global (référence) : toute la scène se fige, projectiles compris', () => {
  const { at, next } = hitstopScene('global');
  assert.equal(next.time, at.time, 'le temps du monde s\'arrête');
  assert.equal(next.aT, at.aT);
  assert.equal(next.ax, at.ax, 'le projectile ennemi est figé lui aussi');
  assert.equal(next.ix, at.ix);
  assert.equal(next.iy, at.iy);
});

test('labo D8 · local : le dash interrompt le gel du héros (le dash reste roi)', () => {
  const g = sandbox({ tuning: { lab: { hitstop: 'local' } } });
  dummy(g, 60, 0);
  for (let i = 0; i < SETTLE_TICKS && g.player.freeze <= 0; i++) stepGame(g, input({ attackPressed: i === 0, aimX: 1 }));
  assert.ok(g.player.freeze > 0);
  stepGame(g, input({ moveX: -1, dashPressed: true }));
  assert.equal(g.player.freeze, 0);
  assert.equal(g.player.state, 'dash');
});

test('labo D8 · local : partie déterministe (même graine + mêmes entrées = même état, à l\'octet)', () => {
  const run = () => {
    const g = createGame({ seed: 44, tuning: { lab: { hitstop: 'local', dashStrike: 'toutDash', comboMobility: 'fluide' } } });
    const mem = {};
    const hashes = [];
    for (let i = 0; i < DETERMINISM_TICKS; i++) {
      if (g.mode === 'choice') resolveChoice(g, 'skilled');
      stepGame(g, POLICIES.skilled(g, mem));
      g.events.length = 0;
      if (i % 120 === 0) hashes.push(stateHash(g));
    }
    return { hashes, frozen: g.telemetry.attacks };
  };
  const a = run();
  const b = run();
  assert.deepEqual(a.hashes, b.hashes);
  assert.ok(a.frozen > 0, 'le héros a frappé (le gel local a été exercé)');
});

/** Combo maintenu sur une cible : intervalle (s) entre le coup 1 et le coup 2, et vitesse en frappant. */
function comboProfile(variant) {
  const g = sandbox({ tuning: { lab: { comboMobility: variant } } });
  dummy(g, 70, 0);
  const starts = [];
  for (let i = 0; i < ticks(1.5) && starts.length < 2; i++) {
    stepGame(g, input({ attack: true, aimX: 1 }));
    for (const ev of g.events) if (ev.type === 'attackStart') starts.push(g.time);
    g.events.length = 0;
  }
  // Vitesse pendant un coup : on marche vers le bas en frappant dans le vide.
  const m = sandbox({ tuning: { lab: { comboMobility: variant } } });
  const y0 = m.player.y;
  stepGame(m, input({ attackPressed: true, aimX: 1 }));
  let moved = 0;
  for (let i = 0; i < 6 && m.player.state === 'attack'; i++) {
    const y = m.player.y;
    stepGame(m, input({ moveY: 1, aimX: 1 }));
    moved += m.player.y - y;
  }
  return { gap: starts[1] - starts[0], moved, y0, t: g.tuning.player };
}

test('labo D9 : préréglages appliqués (vitesse et annulations) et effet mesurable ancré < mobile < fluide', () => {
  const expect = { ancre: LAB_AXES.comboMobility.options.ancre.set, mobile: LAB_AXES.comboMobility.options.mobile.set, fluide: LAB_AXES.comboMobility.options.fluide.set };
  const prof = {};
  for (const [variant, set] of Object.entries(expect)) {
    const g = createGame({ seed: 45, tuning: { lab: { comboMobility: variant } } });
    assert.equal(g.tuning.player.attackMoveMult, set['player.attackMoveMult'], `${variant} : vitesse en frappant`);
    assert.equal(g.tuning.player.cancelMult, set['player.cancelMult'], `${variant} : annulations`);
    prof[variant] = comboProfile(variant);
  }
  assert.ok(prof.fluide.gap < prof.mobile.gap && prof.mobile.gap < prof.ancre.gap, `coup 2 après : ${Object.entries(prof).map(([k, v]) => `${k} ${v.gap.toFixed(3)} s`).join(', ')}`);
  assert.ok(prof.ancre.moved < prof.mobile.moved && prof.mobile.moved < prof.fluide.moved, `déplacement en frappant : ${Object.entries(prof).map(([k, v]) => `${k} ${v.moved.toFixed(1)} u`).join(', ')}`);
  // Le dash annule toujours tout, quelle que soit la variante (le dash reste roi).
  for (const variant of Object.keys(expect)) {
    const g = sandbox({ tuning: { lab: { comboMobility: variant } } });
    stepGame(g, input({ attackPressed: true, aimX: 1 }));
    stepGame(g, input({ moveX: -1, dashPressed: true }));
    assert.equal(g.player.state, 'dash', `${variant} : le dash coupe le coup`);
  }
});

// ---------------------------------------------------------------- bots et oracles

test('bots : le portail de la Ville n\'est jamais pris sans demande ; sur demande, l\'épisode finit proprement en Ville', () => {
  const g = createGame({ seed: 50, startFloor: GUARDIAN_FLOOR });
  defeatGuardian(g);
  g.room.interact = null;
  const mem = {};
  let floor = g.run.floor;
  for (let i = 0; i < ticks(20) && g.mode !== 'town' && floor === g.run.floor; i++) {
    if (g.mode === 'choice') resolveChoice(g, 'skilled');
    stepGame(g, POLICIES.skilled(g, mem));
  }
  assert.notEqual(g.mode, 'town', 'le bot ne rentre pas en Ville de lui-même');
  assert.equal(g.run.floor, CHECKPOINT, 'il descend dans la section suivante');
  floor = 0;
  const h = createGame({ seed: 50, startFloor: GUARDIAN_FLOOR });
  defeatGuardian(h);
  h.room.interact = null;
  const want = { wantTown: true };
  for (let i = 0; i < ticks(20) && h.mode !== 'town'; i++) stepGame(h, POLICIES.skilled(h, want));
  assert.equal(h.mode, 'town', 'sur demande, le bot prend le portail');
  // runEpisode : une section, puis la Ville sur demande — l'épisode se termine (pas de boucle infinie).
  const r = runEpisode('skilled', 1, { floors: SECTION, minutes: 30, town: true });
  assert.equal(r.outcome, 'town');
  assert.equal(r.sectionCleared, true, 'le Gardien est tombé, le checkpoint est ouvert');
  assert.ok(r.checkpoints.includes(CHECKPOINT));
});
