#!/usr/bin/env node
// Solvabilité (convention du studio : forge/contracts/s9-build.yaml) — un bot JOUE et GAGNE.
// « Gagner », dans un jeu de 666 étages, c'est ici battre la section 1 : vaincre le premier
// Gardien (étage 18, tuning.floors.sectionLength) et atteindre le checkpoint de l'étage 19.
//
// Le bot `skilled` (tools/bots.mjs) ne lit que ce que voit un joueur (télégraphes, zones,
// projectiles), avec un temps de réaction de 0,15 s ; il ne lit jamais le RNG.
//
// Deux volets BLOQUANTS :
//   1. jouable  : le bot skilled bat la section 1 sur au moins MIN_CLEAR_RATE des graines ;
//   2. le dash compte : sans dash, on encaisse au moins MIN_DASH_VALUE fois plus de dégâts
//      par salle (pilier n°1 de la charte — mesure de plausibilité, pas une preuve de fun).
// Un volet de MESURE, non bloquant : taux de mort d'un joueur qui « martèle » sans lire.
//
// Usage : node solvability.mjs [graines=20]

import { runEpisode } from './tools/playtest.mjs';
import { DEFAULT_TUNING } from './src/sim/config.mjs';

const SEEDS = Number.parseInt(process.argv[2] ?? '20', 10);
const FIRST_SEED = 1;
const SECTION_FLOORS = DEFAULT_TUNING.floors.sectionLength;
const MAX_MINUTES = 30; // une section de 18 étages : ~12-15 min de jeu pour le bot
const MIN_CLEAR_RATE = 0.9;
const MIN_DASH_VALUE = 2;

function play(policy) {
  const runs = [];
  for (let s = FIRST_SEED; s < FIRST_SEED + SEEDS; s++) runs.push(runEpisode(policy, s, { floors: SECTION_FLOORS, minutes: MAX_MINUTES }));
  return runs;
}

function mean(xs) {
  return xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : 0;
}

const skilled = play('skilled');
const noDash = play('noDash');
const masher = play('masher');

const clearRate = skilled.filter((r) => r.sectionCleared).length / SEEDS;
const dmgSkilled = mean(skilled.map((r) => r.damagePerRoom));
const dmgNoDash = mean(noDash.map((r) => r.damagePerRoom));
const dashValue = dmgSkilled > 0 ? dmgNoDash / dmgSkilled : Infinity;
const masherDeathRate = masher.filter((r) => r.deaths > 0).length / SEEDS;
const failedSeeds = skilled.filter((r) => !r.sectionCleared).map((r) => ({ seed: r.seed, floor: r.floorReached, outcome: r.outcome, causes: r.deathCauses }));

const verdict = {
  seeds: SEEDS,
  clearRate,
  dashValue: Number(dashValue.toFixed(2)),
  damagePerRoom: { skilled: Number(dmgSkilled.toFixed(1)), noDash: Number(dmgNoDash.toFixed(1)) },
  masherDeathRate,
  failedSeeds,
};
console.log(`FORGE_ORACLE solvability ${JSON.stringify(verdict)}`);
console.log(`  section 1 battue par le bot skilled : ${(clearRate * 100).toFixed(0)} % (seuil ${MIN_CLEAR_RATE * 100} %)`);
console.log(`  valeur du dash (dégâts/salle sans dash ÷ avec) : ${dashValue.toFixed(2)} (seuil ${MIN_DASH_VALUE})`);
console.log(`  mesure : un joueur qui martèle sans lire meurt dans ${(masherDeathRate * 100).toFixed(0)} % des parties`);

const ok = clearRate >= MIN_CLEAR_RATE && dashValue >= MIN_DASH_VALUE;
console.log(`SOLVABILITY: ${ok ? 'PASS' : 'FAIL'}`);
process.exit(ok ? 0 : 1);
