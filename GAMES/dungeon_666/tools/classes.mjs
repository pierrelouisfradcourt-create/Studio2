#!/usr/bin/env node
// Mesure des CLASSES (D11) : chaque kit (classe + arme) joué par les bots sur la section 1, et
// une expérience contrôlée « attaque maintenue sur place ». Écrit reports/classes.md.
//
//   node tools/classes.mjs [graines=20] [--md chemin] [--no-md] [--tuning '{json}']
//
// --tuning : surcharges de réglage, pour un CONTREFACTUEL (le rapport n'est alors pas écrit) :
//   node tools/classes.mjs --tuning '{"combat":{"stunGuard":0}}'    le jeu sans la garde -> ROUGE
//
// Quatre volets BLOQUANTS, par kit (ils gardent les deux défauts relevés par la relecture de
// la V2 : Hache et Maillet qui étourdissaient en boucle, Chasseresse qui se passait du dash) :
//   1. jouable     : le bot skilled bat la section 1 sur au moins MIN_CLEAR_RATE des graines ;
//   2. le dash compte : sans dash, au moins MIN_DASH_VALUE fois plus de dégâts par salle ;
//   3. sans dash, on paie : au moins MIN_NODASH_SHARE des dégâts par salle de l'étalon
//      (Revenant, Lame) joué sans dash — un kit ne remplace pas le dash par sa portée ;
//   4. sur place : attaque maintenue sans bouger, des brutes increvables placent au moins
//      MIN_HOLD_HITS coups en HOLD_SECONDS (armes de mêlée) — pas d'étourdissement en boucle.
// MESURES non bloquantes : section battue sans dash, mort du joueur qui martèle, durée, écart
// de dégâts reçus entre classes. Elles ne tranchent pas l'équilibrage : D11 se juge en main.

import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createGame, stepGame, emptyInput, DT } from '../src/sim/game.mjs';
import { createTuning, DEFAULT_TUNING } from '../src/sim/config.mjs';
import { createProfile, starterWeapon } from '../src/sim/profile.mjs';
import { createEnemy } from '../src/sim/enemies.mjs';
import { runEpisode } from './playtest.mjs';

const GAME_DIR = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const DEFAULT_SEEDS = 20;
const DEFAULT_MD = 'reports/classes.md';
const SECTION_FLOORS = DEFAULT_TUNING.floors.sectionLength;
const MAX_MINUTES = 30;
const REFERENCE_KIT = 'revenant/lame'; // l'étalon : les autres kits se lisent par rapport à lui
const POLICIES = ['skilled', 'noDash', 'masher'];

export const MIN_CLEAR_RATE = 0.9;
export const MIN_DASH_VALUE = 2;
export const MIN_NODASH_SHARE = 0.7;
export const HOLD_SECONDS = 30;
export const MIN_HOLD_HITS = 3;
const HOLD_SEEDS = 10;
const HOLD_RING = 160; // u : distance de départ des ennemis autour du héros
const HOLD_HP = 1e9; // increvables : on mesure les coups placés, pas la vitesse de mise à mort
export const HOLD_PACKS = {
  brutes: ['brute', 'brute'],
  diablotins: ['imp', 'imp', 'imp'],
  mêlée: ['brute', 'imp', 'brute', 'imp', 'imp'],
};
const HOLD_GATING_PACK = 'brutes'; // les diablotins sont tenus à distance par le RECUL : mesure seulement

/** Tous les kits jouables : [{id, classId, weaponType}], dans l'ordre des classes. */
export function allKits(tuning = DEFAULT_TUNING) {
  const out = [];
  for (const [classId, c] of Object.entries(tuning.classes)) {
    for (const weaponType of c.weapons) out.push({ id: `${classId}/${weaponType}`, classId, weaponType });
  }
  return out;
}

/** Profil permanent : tout débloqué, la classe et l'arme demandées, compétence et gadget de départ. */
export function kitProfile(tuning, classId, weaponType) {
  const m = createProfile(tuning);
  for (const k of ['classes', 'weapons', 'skills', 'gadgets']) m.unlocked[k] = Object.keys(tuning[k]);
  const c = tuning.classes[classId];
  m.loadout = { classId, skillId: c.skills[0], gadgetId: c.gadgets[0] };
  m.equipment.arme = starterWeapon(tuning, weaponType ?? c.weapons[0]);
  m.equipment.arme.uid = 'i9000';
  return m;
}

function mean(xs) {
  return xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : 0;
}

/**
 * Expérience contrôlée : salle vide, héros au centre qui MAINTIENT l'attaque sans bouger,
 * entouré d'ennemis increvables. Rend le nombre de coups reçus en HOLD_SECONDS.
 * `tuning` : surcharges (ex. {combat: {stunGuard: 0}} pour mesurer le jeu sans la garde).
 */
export function holdTrial(classId, weaponType, pack, seed, tuning) {
  const t = createTuning();
  const g = createGame({ seed, meta: kitProfile(t, classId, weaponType), tuning });
  g.spawns.length = 0;
  g.enemies.length = 0;
  g.room.waves = [];
  g.room.waveIndex = 0;
  g.room.obstacles = [];
  g.room.cleared = true;
  g.room.interact = null;
  g.room.doors = [];
  const p = g.player;
  p.x = g.room.w / 2;
  p.y = g.room.h / 2;
  p.maxHp = HOLD_HP;
  p.hp = HOLD_HP;
  pack.forEach((kind, i) => {
    const a = (i / pack.length) * Math.PI * 2;
    const e = createEnemy(g, kind, p.x + Math.cos(a) * HOLD_RING, p.y + Math.sin(a) * HOLD_RING, { spawnT: 0 });
    e.hp = HOLD_HP;
    e.maxHp = HOLD_HP;
  });
  g.events.length = 0;
  const input = { ...emptyInput(), attack: true };
  let hits = 0;
  for (let i = 0; i < HOLD_SECONDS / DT; i++) {
    stepGame(g, input);
    for (const ev of g.events) if (ev.type === 'playerHurt') hits++;
    g.events.length = 0;
  }
  return hits;
}

/** Coups reçus sur place, en moyenne sur HOLD_SEEDS graines. */
export function holdHits(classId, weaponType, pack, tuning) {
  const runs = [];
  for (let s = 1; s <= HOLD_SEEDS; s++) runs.push(holdTrial(classId, weaponType, pack, s, tuning));
  return mean(runs);
}

function playKit(kit, policy, seeds, tuning) {
  const t = createTuning();
  const runs = [];
  for (let s = 1; s <= seeds; s++) {
    runs.push(runEpisode(policy, s, { floors: SECTION_FLOORS, minutes: MAX_MINUTES, tuning, meta: kitProfile(t, kit.classId, kit.weaponType) }));
  }
  return {
    clearRate: runs.filter((r) => r.sectionCleared).length / seeds,
    deathRate: runs.filter((r) => r.deaths > 0).length / seeds,
    damagePerRoom: mean(runs.map((r) => r.damagePerRoom ?? 0)),
    floorReached: mean(runs.map((r) => r.floorReached)),
    minutes: mean(runs.map((r) => r.simSeconds)) / 60,
  };
}

/**
 * Mesure complète. Rend {seeds, kits: [{id, melee, skilled, noDash, masher, dashValue, hold}], failures}.
 * `overrides` : surcharges de réglage appliquées à toutes les parties (contrefactuel).
 */
export function measureClasses(seeds = DEFAULT_SEEDS, overrides) {
  const tuning = DEFAULT_TUNING;
  const kits = allKits(tuning).map((kit) => {
    const row = { ...kit, melee: tuning.weapons[kit.weaponType].kind === 'melee' };
    for (const policy of POLICIES) row[policy] = playKit(kit, policy, seeds, overrides);
    row.dashValue = row.skilled.damagePerRoom > 0 ? row.noDash.damagePerRoom / row.skilled.damagePerRoom : Infinity;
    row.hold = {};
    for (const [name, pack] of Object.entries(HOLD_PACKS)) row.hold[name] = holdHits(kit.classId, kit.weaponType, pack, overrides);
    return row;
  });
  const ref = kits.find((k) => k.id === REFERENCE_KIT);
  const failures = [];
  for (const k of kits) {
    k.noDashShare = ref && ref.noDash.damagePerRoom > 0 ? k.noDash.damagePerRoom / ref.noDash.damagePerRoom : 1;
    if (k.skilled.clearRate < MIN_CLEAR_RATE) failures.push(`${k.id} : section battue ${(k.skilled.clearRate * 100).toFixed(0)} % < ${MIN_CLEAR_RATE * 100} %`);
    if (k.dashValue < MIN_DASH_VALUE) failures.push(`${k.id} : valeur du dash ${k.dashValue.toFixed(2)} < ${MIN_DASH_VALUE}`);
    if (k.noDashShare < MIN_NODASH_SHARE) failures.push(`${k.id} : sans dash, ${(k.noDashShare * 100).toFixed(0)} % des dégâts de l'étalon < ${MIN_NODASH_SHARE * 100} %`);
    if (k.melee && k.hold[HOLD_GATING_PACK] < MIN_HOLD_HITS) failures.push(`${k.id} : sur place, ${k.hold[HOLD_GATING_PACK].toFixed(1)} coups de brutes en ${HOLD_SECONDS} s < ${MIN_HOLD_HITS}`);
  }
  return { seeds, kits, failures };
}

const pct = (x) => `${(x * 100).toFixed(0)} %`;

export function renderMarkdown(report) {
  const name = (k) => `${DEFAULT_TUNING.classes[k.classId].name} · ${DEFAULT_TUNING.weapons[k.weaponType].name}`;
  const lines = [
    '# Dungeon 666 — mesure des classes (bots)',
    '',
    `Généré par \`node tools/classes.mjs ${report.seeds}\` : ${report.seeds} graines par kit et par bot, section 1 (${SECTION_FLOORS} étages).`,
    'Les bots mesurent des conséquences (dégâts reçus, survie). Ils ne mesurent ni le plaisir ni',
    'l\'équilibrage ressenti : **D11 se juge en main**.',
    '',
    '## Section 1 jouée par les bots',
    '',
    '| Kit | Habile : section battue | Habile : dégâts/salle | Sans dash : dégâts/salle | Valeur du dash | Sans dash vs étalon | Sans dash : section battue | Martèle : meurt | Martèle : étage atteint | Durée (habile) |',
    '|---|---|---|---|---|---|---|---|---|---|',
  ];
  for (const k of report.kits) {
    lines.push(`| ${name(k)} | ${pct(k.skilled.clearRate)} | ${k.skilled.damagePerRoom.toFixed(1)} | ${k.noDash.damagePerRoom.toFixed(1)} | ×${k.dashValue.toFixed(1)} | ${pct(k.noDashShare)} | ${pct(k.noDash.clearRate)} | ${pct(k.masher.deathRate)} | ${k.masher.floorReached.toFixed(1)} | ${k.skilled.minutes.toFixed(1)} min |`);
  }
  lines.push(
    '',
    `Seuils bloquants : section battue ≥ ${pct(MIN_CLEAR_RATE)} ; valeur du dash ≥ ×${MIN_DASH_VALUE} ; sans dash, au moins ${pct(MIN_NODASH_SHARE)} des dégâts/salle de l'étalon (${REFERENCE_KIT}).`,
    '',
    '## Attaque maintenue sur place (ennemis increvables)',
    '',
    `Le héros ne bouge pas et maintient l'attaque ${HOLD_SECONDS} s. Coups reçus, moyenne de ${HOLD_SEEDS} graines.`,
    '',
    `| Kit | ${Object.entries(HOLD_PACKS).map(([n, p]) => `${n} (${p.length})`).join(' | ')} |`,
    `|---|${Object.keys(HOLD_PACKS).map(() => '---').join('|')}|`,
  );
  for (const k of report.kits) {
    lines.push(`| ${name(k)}${k.melee ? '' : ' (à distance)'} | ${Object.keys(HOLD_PACKS).map((n) => k.hold[n].toFixed(1)).join(' | ')} |`);
  }
  lines.push(
    '',
    `Seuil bloquant (armes de mêlée) : au moins ${MIN_HOLD_HITS} coups de brutes en ${HOLD_SECONDS} s. Les diablotins restent une mesure :`,
    'une arme lourde les tient à distance par son recul, pas par l\'étourdissement.',
    '',
    `## Verdict : ${report.failures.length ? 'ROUGE' : 'VERT'}`,
    '',
    ...(report.failures.length ? report.failures.map((f) => `- ${f}`) : ['Tous les seuils bloquants passent.']),
    '',
  );
  return lines.join('\n');
}

function main() {
  const argv = process.argv.slice(2);
  const seeds = Number.parseInt(argv.find((a) => /^\d+$/.test(a)) ?? String(DEFAULT_SEEDS), 10);
  const mdAt = argv.indexOf('--md');
  const tuningAt = argv.indexOf('--tuning');
  const overrides = tuningAt >= 0 ? JSON.parse(argv[tuningAt + 1]) : undefined;
  // Un contrefactuel ne remplace jamais le rapport de référence.
  const md = argv.includes('--no-md') || overrides ? null : mdAt >= 0 ? argv[mdAt + 1] : DEFAULT_MD;
  const report = measureClasses(seeds, overrides);
  for (const k of report.kits) {
    console.log(`  ${k.id.padEnd(22)} battue ${pct(k.skilled.clearRate).padStart(5)} · dash ×${k.dashValue.toFixed(1).padStart(4)} · sans dash ${pct(k.noDashShare).padStart(5)} de l'étalon (battue ${pct(k.noDash.clearRate)}) · martèle : étage ${k.masher.floorReached.toFixed(1)} · sur place (brutes) ${k.hold[HOLD_GATING_PACK].toFixed(1)}`);
  }
  if (md) {
    const path = resolve(GAME_DIR, md);
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, renderMarkdown(report));
    console.log(`  rapport : ${md}`);
  }
  const verdict = {
    seeds,
    kits: Object.fromEntries(report.kits.map((k) => [k.id, {
      clearRate: k.skilled.clearRate, dashValue: Number(k.dashValue.toFixed(2)), noDashShare: Number(k.noDashShare.toFixed(2)),
      noDashClearRate: k.noDash.clearRate, masherDeathRate: k.masher.deathRate, holdHits: Number(k.hold[HOLD_GATING_PACK].toFixed(1)),
    }])),
    failures: report.failures,
  };
  console.log(`FORGE_ORACLE classes ${JSON.stringify(verdict)}`);
  for (const f of report.failures) console.log(`  ROUGE — ${f}`);
  console.log(`CLASSES: ${report.failures.length ? 'FAIL' : 'PASS'}`);
  process.exit(report.failures.length ? 1 : 0);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
