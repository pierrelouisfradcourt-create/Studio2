// TRACES DE PARITÉ pour la version Godot : une partie jouée par un bot, notée pas à pas.
// Godot rejoue les mêmes entrées depuis le même départ et compare ses empreintes d'état.
//
// Une trace : { name, options, steps, ticks }
//   options : ce qu'on passe à createGame (graine, étage, profil, réglages, modes).
//   steps   : [0, mx, my, ax, ay, drapeaux, sx, sy]   une image d'entrées (voir quantize)
//             [1, commande, acceptée]                 une commande de menu TENTÉE (toutes notées,
//                                                     même refusées : Godot doit refuser pareil)
//             [2, empreinte]                          un point de contrôle (digest)
//
// Les entrées analogiques sont quantifiées au 1/1024 AVANT d'être jouées ici : la trace porte
// des entiers, Godot retrouve exactement les mêmes nombres (q / 1024).
// Égalité attendue côté Godot : EXACTE, au bit près, sur toute l'empreinte. C'est possible parce
// que la simulation ne calcule ses sinus, cosinus, exponentielles… que par src/core/trig.mjs.

import { createGame, stepGame, applyCommand, emptyInput, DT } from '../src/sim/game.mjs';
import { createTuning } from '../src/sim/config.mjs';
import { lastCheckpoint } from '../src/sim/run.mjs';
import { POLICIES } from './bots.mjs';
import { kitProfile } from './classes.mjs';

const Q = 1024; // pas de quantification des entrées analogiques
const CHECK_EVERY = 30; // images entre deux points de contrôle
const ANALOG = ['moveX', 'moveY', 'aimX', 'aimY', 'skillAimX', 'skillAimY'];
const FLAGS = ['attack', 'attackPressed', 'dashPressed', 'skillPressed', 'gadgetPressed', 'superPressed'];
const MAX_STEPS_FACTOR = 4; // garde-fou : pas plus de 4 éléments de trace par image demandée

function quantize(input) {
  const out = emptyInput();
  for (const k of ANALOG) out[k] = Math.round((input[k] || 0) * Q) / Q;
  for (const k of FLAGS) out[k] = !!input[k];
  return out;
}

function inputStep(q) {
  let flags = 0;
  FLAGS.forEach((k, i) => { if (q[k]) flags |= 1 << i; });
  return [0, q.moveX * Q, q.moveY * Q, q.aimX * Q, q.aimY * Q, flags, q.skillAimX * Q, q.skillAimY * Q];
}

/** Empreinte d'état : assez large pour qu'une règle mal portée se voie dans les 30 images. */
export function digest(game, events) {
  const p = game.player;
  const room = game.room;
  return {
    tick: game.tick,
    time: game.time,
    mode: game.mode,
    floor: game.run.floor,
    gold: game.run.gold,
    souls: game.meta.souls,
    rng: [game.rng.gen.s, game.rng.combat.s, game.rng.ai.s],
    nextId: game.nextId,
    hitstop: game.hitstop,
    bank: game.hitstopBank,
    p: [p.x, p.y, p.vx, p.vy, p.hp, p.maxHp, p.state, p.facing, p.dashCharges, p.superCharge, p.gadgetCharges, p.skillCd, p.iframes, p.freeze],
    e: game.enemies.map((e) => [e.id, e.kind, e.state, e.x, e.y, e.hp, e.stun, e.dead ? 1 : 0, e.eliteMod ?? '']),
    pr: game.projectiles.map((o) => [o.x, o.y]),
    hz: game.hazards.length,
    pk: game.pickups.length,
    sp: game.spawns.length,
    boons: game.run.boons.map((b) => `${b.id}:${b.level}:${b.rarity}`),
    room: [room.kind, room.layout ?? '', room.waveIndex, room.cleared ? 1 : 0, room.doors.map((d) => `${d.reward}${d.open ? '+' : '-'}`).join(',')],
    choice: game.choice?.kind ?? '',
    ev: events,
    tel: [game.telemetry.kills, game.telemetry.damageTaken, game.telemetry.damageDealt, game.telemetry.dodges],
  };
}

/**
 * Politique « au hasard » : toutes les commandes pressées aléatoirement, par courtes séquences
 * tenues. Aucun bot ne joue ainsi ; c'est ce qui exerce les bords du tampon d'entrées (dash
 * enchaîné, attaque pendant un dash, compétence pendant une récupération, visées manuelles).
 * RNG propre à la politique (jamais celui de la partie).
 */
function randomPolicy(seed) {
  let s = seed >>> 0;
  const rnd = () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  let hold = 0;
  let cur = emptyInput();
  return () => {
    if (hold-- <= 0) {
      hold = Math.floor(rnd() * 14);
      cur = emptyInput();
      if (rnd() < 0.8) { cur.moveX = rnd() * 2 - 1; cur.moveY = rnd() * 2 - 1; }
      if (rnd() < 0.3) { cur.aimX = rnd() * 2 - 1; cur.aimY = rnd() * 2 - 1; }
      cur.attack = rnd() < 0.55;
      cur.skillAimX = rnd() < 0.5 ? rnd() * 2 - 1 : 0;
      cur.skillAimY = rnd() < 0.5 ? rnd() * 2 - 1 : 0;
    }
    const out = { ...cur };
    out.attackPressed = rnd() < 0.12;
    out.dashPressed = rnd() < 0.1;
    out.skillPressed = rnd() < 0.04;
    out.gadgetPressed = rnd() < 0.01;
    out.superPressed = rnd() < 0.03;
    return out;
  };
}

function mixHash(...values) {
  let h = 2166136261;
  for (const v of values) h = Math.imul(h ^ (v >>> 0), 16777619) >>> 0;
  return h >>> 0;
}

/** Commandes de menu à tenter, dans l'ordre ; la première acceptée résout le menu. */
function menuCandidates(game) {
  const h = mixHash(game.seed, game.run.floor, game.run.boons.length, game.tick);
  return [
    { type: 'choose', index: h % 3 }, { type: 'equip' }, { type: 'choose', index: 0 }, { type: 'choose', index: 1 },
    { type: 'choose', index: 2 }, { type: 'stash' }, { type: 'salvage' }, { type: 'close' },
  ];
}

function tryCommands(game, steps, cmds) {
  for (const cmd of cmds) {
    const ok = !!applyCommand(game, cmd);
    steps.push([1, cmd, ok ? 1 : 0]);
    if (ok) return true;
  }
  return false;
}

/**
 * Joue et note une partie. spec : { name, seed, floor, kit: [classe, arme], policy, seconds,
 * tuning, sandbox, practice, godMode, deaths: 'respawn' | 'town' }. `every` : images entre deux
 * points de contrôle (1 = une empreinte par image, pour localiser une divergence).
 */
export function recordTrace(spec, every = CHECK_EVERY) {
  const base = createTuning();
  const options = {
    seed: spec.seed,
    startFloor: spec.floor ?? 1,
    meta: spec.kit ? kitProfile(base, spec.kit[0], spec.kit[1]) : null,
    tuning: spec.tuning ?? null,
    sandbox: !!spec.sandbox,
    practice: !!spec.practice,
    godMode: !!spec.godMode,
  };
  const game = createGame({ ...options, meta: options.meta ?? undefined, tuning: options.tuning ?? undefined });
  const policy = spec.policy === 'hasard' ? randomPolicy(spec.seed) : POLICIES[spec.policy ?? 'skilled'];
  const mem = {};
  const steps = [];
  let events = {};
  const drain = () => {
    for (const ev of game.events) events[ev.type] = (events[ev.type] ?? 0) + 1;
    game.events.length = 0;
  };
  const check = () => {
    drain();
    steps.push([2, digest(game, events)]);
    events = {};
  };
  check();
  const frames = Math.round(spec.seconds / DT);
  let played = 0;
  while (played < frames && steps.length < frames * MAX_STEPS_FACTOR) {
    if (game.mode === 'choice') {
      if (!tryCommands(game, steps, menuCandidates(game))) break;
      check();
      continue;
    }
    if (game.mode === 'dead') {
      const cmd = spec.deaths === 'town' ? { type: 'returnToTown' } : { type: 'respawn', floor: lastCheckpoint(game) };
      if (!tryCommands(game, steps, [cmd])) break;
      check();
      continue;
    }
    if (game.mode !== 'play') break; // Ville, victoire : fin de la partie notée
    const q = quantize(policy(game, mem));
    steps.push(inputStep(q));
    stepGame(game, q);
    played++;
    drain();
    if (played % every === 0) check();
  }
  check();
  return { name: spec.name, options, steps, ticks: game.tick };
}

// ---------------------------------------------------------------- catalogue

const KITS = [['revenant', 'lame'], ['revenant', 'dagues'], ['bourreau', 'hache'], ['bourreau', 'marteau'], ['chasseresse', 'arc'], ['chasseresse', 'arbalete']];
const GUARDIAN_FLOORS = [18, 36, 54, 72]; // Charon, Cerbère, Minos, Colosse (rotation)

function catalogue() {
  const out = [];
  // Chaque kit, du premier étage : combat, menus de bénédiction, portes.
  KITS.forEach(([c, w], i) => out.push({ name: `kit_${w}`, seed: 101 + i, floor: 1, kit: [c, w], policy: 'skilled', seconds: 45 }));
  // Le bestiaire entier (milieu et fin de section 1), joueurs maladroits compris (morts, reprises).
  out.push({ name: 'etage_7_habile', seed: 201, floor: 7, policy: 'skilled', seconds: 45 });
  out.push({ name: 'etage_12_sans_dash', seed: 202, floor: 12, policy: 'noDash', seconds: 45 });
  out.push({ name: 'etage_14_martele', seed: 203, floor: 14, policy: 'masher', seconds: 45 });
  out.push({ name: 'etage_5_martele_ville', seed: 204, floor: 5, policy: 'masher', seconds: 45, deaths: 'town' });
  // Salles calmes : halte de mi-section, antichambre.
  out.push({ name: 'halte_9', seed: 301, floor: 8, policy: 'skilled', seconds: 45 });
  out.push({ name: 'antichambre_17', seed: 302, floor: 16, policy: 'skilled', seconds: 45 });
  // Les quatre Gardiens, par les trois classes.
  GUARDIAN_FLOORS.forEach((f, i) => {
    const [c, w] = KITS[(i * 2) % KITS.length];
    out.push({ name: `gardien_${f}_${w}`, seed: 401 + i, floor: f, kit: [c, w], policy: 'skilled', seconds: 60 });
    out.push({ name: `gardien_${f}_sans_dash`, seed: 451 + i, floor: f, policy: 'noDash', seconds: 40 });
  });
  // Profondeur : Cercles lointains, finale, victoire.
  out.push({ name: 'profond_163', seed: 501, floor: 163, policy: 'skilled', seconds: 45 });
  out.push({ name: 'profond_400_arc', seed: 502, floor: 400, kit: ['chasseresse', 'arc'], policy: 'skilled', seconds: 45 });
  out.push({ name: 'finale_660', seed: 503, floor: 660, policy: 'skilled', seconds: 45 });
  out.push({ name: 'gardien_final_666', seed: 504, floor: 666, policy: 'skilled', seconds: 60, godMode: true });
  // Labo du feel : chaque variante hors référence.
  out.push({ name: 'labo_gel_local', seed: 601, floor: 6, policy: 'skilled', seconds: 40, tuning: { lab: { hitstop: 'local' } } });
  out.push({ name: 'labo_tout_dash', seed: 602, floor: 6, policy: 'skilled', seconds: 40, tuning: { lab: { dashStrike: 'toutDash' } } });
  out.push({ name: 'labo_apres_dash', seed: 603, floor: 6, policy: 'skilled', seconds: 40, tuning: { lab: { dashStrike: 'apresDash' } } });
  out.push({ name: 'labo_ancre', seed: 604, floor: 6, policy: 'skilled', seconds: 40, tuning: { lab: { comboMobility: 'ancre' } } });
  out.push({ name: 'labo_fluide', seed: 605, floor: 6, policy: 'skilled', seconds: 40, tuning: { lab: { comboMobility: 'fluide' } } });
  // Les trois phases de chaque Gardien : PV réduits (les seuils de phase tombent vite), héros invulnérable.
  for (const [f, kind] of [[18, 'gardien'], [36, 'cerbere'], [54, 'minos'], [72, 'colosse']]) {
    out.push({ name: `phases_${kind}`, seed: 801 + f, floor: f, policy: 'skilled', seconds: 120, godMode: true, tuning: { boss: { [kind]: { hp: 260 } } } });
  }
  // Sections entières (six à sept minutes) : la parité doit tenir sur la durée, sans dérive.
  out.push({ name: 'section_lame', seed: 901, floor: 1, kit: ['revenant', 'lame'], policy: 'skilled', seconds: 420 });
  out.push({ name: 'section_arbalete', seed: 902, floor: 1, kit: ['chasseresse', 'arbalete'], policy: 'skilled', seconds: 420 });
  out.push({ name: 'section_marteau_martele', seed: 903, floor: 1, kit: ['bourreau', 'marteau'], policy: 'masher', seconds: 300 });
  // Entrées au hasard, pour chaque kit : les bords que les bots ne touchent jamais.
  KITS.forEach(([c, w], i) => out.push({ name: `hasard_${w}`, seed: 1001 + i, floor: 2 + i * 3, kit: [c, w], policy: 'hasard', seconds: 90, godMode: i % 2 === 0 }));
  // Modes : arène d'essai, entraînement contre un Gardien.
  out.push({ name: 'arene', seed: 701, floor: 1, policy: 'skilled', seconds: 45, sandbox: true });
  out.push({ name: 'entrainement_cerbere', seed: 702, floor: 36, policy: 'masher', seconds: 40, practice: true });
  return out;
}

export const TRACES = catalogue();
