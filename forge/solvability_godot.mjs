#!/usr/bin/env node
// solvability_godot.mjs — Oracle de solvabilite pour un projet Godot (declinaison
// R9 : « un bot doit reellement gagner » applique aux jeux Godot).
//
// runSolvability(cfg, trialFn) est PURE et testable sans Godot : trialFn(seed)
// est injectee (fake en test, vrai bot Godot en production via makeGodotRunTrial).
//
// Doctrine (« aucune preuve n'est pas une preuve », meme regle que le gate
// mutation quand total==0) :
//   - trials <= 0            -> BLOCKED, jamais OK
//   - une exception d'essai  -> BLOCKED immediat, jamais un vert par defaut
//   - won === trials         -> OK
//   - sinon                  -> FAIL, avec les seeds perdants nommes
//
// Vocabulaire de verdict : OK / FAIL / BLOCKED uniquement.
import { pathToFileURL } from 'node:url';
import { makeGodotRunTrial } from '../../knowledge_base/systems/adapters/godot_trial.mjs';

// Exportes (pas seulement des constantes de module) : godot_oracle.mjs les reuse
// comme valeurs de repli EXPLICITES quand un jeu ne declare pas de budget de
// tick dans forge/oracles.json (`solvability.max_ticks/trials/trial_timeout_ms`)
// - une seule source de verite pour « le comportement par defaut, si rien n'est
// declare », jamais deux litteraux dupliques qui pourraient diverger.
export const DEFAULT_MAX_TICKS = 200;
export const DEFAULT_TRIAL_TIMEOUT_MS = 10000;
export const DEFAULT_SEED_START = 1;

/**
 * Fait tourner `trials` essais a partir de `seed_start`, en appelant
 * `trialFn(seed) -> {succeeded, ticks}` pour chacun.
 *
 * @param {{trials: number, seed_start?: number}} cfg
 * @param {(seed: number) => {succeeded: boolean, ticks: (number|null)}} trialFn
 * @returns {{trials: number, won: number, lost: number, failed_seeds: number[], verdict: string, reason?: string}}
 */
export function runSolvability(cfg, trialFn, nowFn = Date.now) {
  const trials = cfg?.trials;
  const seedStart = cfg?.seed_start ?? DEFAULT_SEED_START;
  // BUDGET TOTAL, optionnel. La preuve par MUTATION lit deja `budget.total_timeout_s`
  // (`mutation_proof.py:707`, applique l.761) et rend un ARRET MOTIVE. La solvabilite, elle,
  // ne bornait rien : l'appelant imposait 300 s EN DUR (`oracle.py:76`, `driver.py:613`) sans
  // consulter le budget du jeu, et leur rencontre se resolvait par une MORT DE PROCESSUS
  // (bomberman_3d, run `proof4` : « TIMEOUT after 300s », aucun resultat partiel rendu).
  // Ici le jeu peut s'arreter AVANT, proprement, en gardant ce qu'il a mesure.
  // `Number.isFinite` + `> 0` : meme discipline que `resolveSolvabilityConfig` — une valeur
  // absurde est IGNOREE, jamais interpretee (un 0 pris au mot bloquerait tout).
  const totalTimeoutS = cfg?.total_timeout_s;
  const budgetMs = (Number.isFinite(totalTimeoutS) && totalTimeoutS > 0)
    ? totalTimeoutS * 1000
    : null;
  const debut = nowFn();

  if (typeof trials !== 'number' || !Number.isFinite(trials) || trials <= 0) {
    return {
      trials: typeof trials === 'number' ? trials : 0,
      won: 0,
      lost: 0,
      failed_seeds: [],
      verdict: 'BLOCKED',
      reason: "aucune preuve n'est pas une preuve : trials doit etre > 0",
    };
  }

  let won = 0;
  let lost = 0;
  const failed_seeds = [];

  for (let i = 0; i < trials; i++) {
    // Verifie AVANT de lancer l'essai : depasser puis constater rendrait le budget
    // consultatif. BLOCKED et jamais FAIL — un budget epuise est une preuve IMPOSSIBLE, pas
    // une preuve NEGATIVE (corollaire ratifie 2026-08-17). Le resultat PARTIEL voyage :
    // c'est toute la difference avec une mort de processus, qui ne rend rien. Et les echecs
    // deja mesures restent dans `failed_seeds` — « non mesure » ne recouvre pas
    // « mesure et rouge ».
    if (budgetMs !== null && (nowFn() - debut) >= budgetMs) {
      return {
        trials,
        trials_executes: i,
        won,
        lost,
        failed_seeds,
        verdict: 'BLOCKED',
        reason: `budget total epuise (total_timeout_s=${totalTimeoutS}) apres ${i}/${trials} `
                + "essais — preuve INCOMPLETE, jamais un echec de solvabilite",
      };
    }
    const seed = seedStart + i;
    let result;
    try {
      result = trialFn(seed);
    } catch (e) {
      return {
        trials,
        won,
        lost,
        failed_seeds,
        verdict: 'BLOCKED',
        reason: `essai seed=${seed} a leve une exception (jamais un vert par defaut) : ${e.message}`,
      };
    }
    if (result && result.succeeded === true) {
      won += 1;
    } else {
      lost += 1;
      failed_seeds.push(seed);
    }
  }

  const verdict = won === trials ? 'OK' : 'FAIL';
  return { trials, won, lost, failed_seeds, verdict };
}

/**
 * Construit un trialFn(seed) qui lance reellement Godot headless sur le
 * projet/script fournis, via l adaptateur godot_trial.mjs (qui resout le
 * binaire via resolveGodotBin() — jamais un chemin en dur).
 */
function buildGodotTrialFn(project, script, { maxTicks, trialTimeoutMs }) {
  const runTrial = makeGodotRunTrial();
  const cfg = {
    godot_project: project,
    godot_script: script,
    trial_timeout_ms: trialTimeoutMs,
    max_ticks: maxTicks,
  };
  return (seed) => runTrial(seed, cfg);
}

function printUsage() {
  console.error(
    'Usage: node solvability_godot.mjs <project> <script> <trials> [seed_start] [max_ticks] [trial_timeout_ms]'
  );
}

/**
 * Extremite AVAL du pont CLI : argv -> configuration. EXPORTEE pour etre testable.
 *
 * Le budget voyage entre deux processus par une ligne de commande POSITIONNELLE. Un champ
 * ajoute d'un cote et non lu de l'autre serait inerte en production ALORS QUE ses tests
 * unitaires passent — c'est le motif « producteur sans consommateur », rencontre plusieurs
 * fois dans ce studio. Rendre les DEUX extremites pures permet de prouver qu'elles
 * s'accordent (voir `solvability_total_timeout.test.mjs`, aller-retour argv).
 *
 * `total_timeout_s` : 7e position, OPTIONNELLE. Absente ou non finie => `undefined`, jamais
 * une valeur inventee — `runSolvability` l'ignore alors et le comportement est inchange.
 */
export function cfgFromArgv(argv) {
  const [project, script, trialsArg, seedStartArg, maxTicksArg, timeoutArg, totalArg] = argv;
  const total = totalArg !== undefined ? Number(totalArg) : NaN;
  return {
    project,
    script,
    trials: Number(trialsArg),
    seed_start: seedStartArg !== undefined ? Number(seedStartArg) : DEFAULT_SEED_START,
    maxTicks: maxTicksArg !== undefined ? Number(maxTicksArg) : DEFAULT_MAX_TICKS,
    trialTimeoutMs: timeoutArg !== undefined ? Number(timeoutArg) : DEFAULT_TRIAL_TIMEOUT_MS,
    total_timeout_s: Number.isFinite(total) ? total : undefined,
  };
}

function main(argv) {
  const [project, script, trialsArg] = argv;
  if (!project || !script || !trialsArg) {
    printUsage();
    process.exit(2);
    return;
  }

  const cfg = cfgFromArgv(argv);
  const { trials, seed_start, maxTicks, trialTimeoutMs, total_timeout_s } = cfg;

  const trialFn = buildGodotTrialFn(project, script, { maxTicks, trialTimeoutMs });
  const result = runSolvability({ trials, seed_start, total_timeout_s }, trialFn);
  const receipt = { project, ...result };

  console.log(JSON.stringify(receipt, null, 2));
  process.exit(result.verdict === 'OK' ? 0 : 1);
}

const isMain = process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url;
if (isMain) {
  main(process.argv.slice(2));
}
