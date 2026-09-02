#!/usr/bin/env node
// backfill_learning_curve.mjs — alimente knowledge_base/learning_curve.jsonl à partir des
// runs Forge ARCHIVÉS (EVIDENCE/runs/<run>/state.json), au lieu d'attendre un futur run
// coûteux pour obtenir une première ligne de base (plan 4 étapes ratifié Pierre
// 2026-07-26, étape 1 : instrumentation -> avoir des données).
//
// Ne réimplémente NI buildRecord/recordLearning (learning_metrics.mjs) NI measureReuseRatio
// (reuse_ratio.mjs) : ce module ORCHESTRE ces deux briques existantes sur les runs archivés.
//
// LEARNING_SUBJECT_MODEL_V1 (studio_brain/decisions/PROPOSED_2026-07-26_ratifications.md) :
// AVANT ce correctif, un run devait matcher un brick_id du catalogue (knowledge_base/
// catalog.json, entry_type=="brick") pour produire une ligne — mais TOUS les runs Forge
// forgent un JEU, jamais une brique de bibliothèque, donc cette exigence garantissait 0
// ligne (bug confirmé : backfill sur les 7 runs archivés connus -> 0 ligne). La correction :
// un run de JEU (`is_game===true`) produit `subject: {type:'game', id:<projet effectif>}`
// SANS exiger de correspondance catalogue — un jeu n'est pas une brique, il n'a jamais eu
// besoin d'en être une pour être mesuré. Un run non-jeu (`is_game!==true`) reste SKIPPED :
// ce pipeline (driver.py/state.json) n'a aucune source pour mesurer le reuse_ratio d'une
// brique de bibliothèque (pas de gameDir équivalent pour une brique) — brancher une source
// KB-reuse pour les briques est explicitement l'ÉTAPE 2 du plan ratifié, pas celle-ci
// (« pas d'anticipation d'étape »). Ce module ne crée ni ne promeut JAMAIS d'entrée dans
// knowledge_base/catalog.json : aucune brique n'est fabriquée à partir d'un jeu.
//
// Règle dure (anti-invention, CLAUDE.md « hypothèse inconnue => on ne verdit pas ») :
// un run est SKIPPED avec une raison explicite (jamais une ligne inventée) si l'oracle de
// code n'a jamais tourné vert, si le run n'est pas un jeu, si le gameDir est introuvable,
// ou si l'entrée existe déjà (idempotence).
//
// Chaque run produit exactement UNE entrée dans le tableau retourné par
// backfillLearningCurve() : {run, project, skipped, reason?, record?}. Rien n'est jamais
// silencieusement avalé (sauf les dossiers de run SANS state.json — hors périmètre de ce
// module, ce ne sont pas des "runs archivés" au sens de la tâche).
import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { recordLearning, normalizeSubject, DEFAULT_LEARNING_CURVE_PATH } from './learning_metrics.mjs';
import { measureReuseRatio } from './reuse_ratio.mjs';

const _MODULE_DIR = dirname(fileURLToPath(import.meta.url));
const _REPO_ROOT = join(_MODULE_DIR, '..');

export const DEFAULT_RUNS_DIR = join(_REPO_ROOT, 'EVIDENCE', 'runs');
export const DEFAULT_GAMES_DIR = join(_REPO_ROOT, 'GAMES');

// Ordre de préférence des étapes-oracle de code — s10a (profils full/increment/patch) avant
// s10s (profil standard). La première étape de cette liste au statut OK dans `steps` porte
// le nombre d'itérations d'oracle avant le vert.
const ORACLE_STEP_PRIORITY = ['s10a-oracle-code', 's10s-oracle-standard'];

/**
 * Normalise `escalations` : schéma hétérogène observé dans les state.json archivés
 * (entier dans les runs anciens, liste dans les runs récents). Jamais un crash sur une
 * valeur inattendue (null/undefined/string) — retombe sur 0.
 * @param {unknown} value
 * @returns {number}
 */
export function normalizeEscalations(value) {
  if (Array.isArray(value)) return value.length;
  if (typeof value === 'number' && Number.isInteger(value)) return value;
  return 0;
}

/**
 * Cherche, dans `steps`, la première étape-oracle de code (ordre ORACLE_STEP_PRIORITY)
 * au statut OK. Retourne {stepName, iterations, ts, detail} ou null si aucune étape-oracle
 * n'a jamais atteint le vert (steps vide/absent, ou toutes en FAIL/BLOCKED/PENDING).
 * @param {unknown} steps
 * @returns {{stepName:string, iterations:number, ts:(number|undefined), detail:unknown}|null}
 */
export function resolveOracleIterations(steps) {
  if (!steps || typeof steps !== 'object') return null;
  for (const name of ORACLE_STEP_PRIORITY) {
    const step = steps[name];
    if (step && step.status === 'OK' && Number.isInteger(step.attempts)) {
      return {
        stepName: name,
        iterations: step.attempts,
        ts: typeof step.ts === 'number' ? step.ts : undefined,
        detail: step.detail,
      };
    }
  }
  return null;
}

/** Dernier segment d'un chemin, quel que soit le séparateur (Windows `\` ou POSIX `/`). */
function _lastPathSegment(p) {
  const norm = String(p).replace(/\\/g, '/').replace(/\/+$/, '');
  const parts = norm.split('/').filter(Boolean);
  return parts.length ? parts[parts.length - 1] : '';
}

function _isoFromEpochSeconds(sec) {
  return new Date(sec * 1000).toISOString();
}

/** Une ligne de sujet {type:'game', id:brickId} + timestamp identique existe-t-elle déjà
 * dans targetPath ? Base de l'idempotence : re-exécuter le backfill sur le même run ne
 * duplique jamais. Lit CHAQUE ligne via normalizeSubject (lecture générique : gère aussi
 * bien les entrées historiques brick_id que les entrées subject) — une ligne qui ne se
 * normalise pas (JSON corrompu, sujet non identifiable) est ignorée, jamais fatale. */
function _recordExists(targetPath, subjectType, subjectId, timestamp) {
  if (!existsSync(targetPath)) return false;
  const text = readFileSync(targetPath, 'utf-8');
  for (const line of text.split('\n')) {
    const t = line.trim();
    if (!t) continue;
    let rec;
    try {
      rec = JSON.parse(t);
    } catch {
      continue; // ligne corrompue : ignorée, jamais fatale
    }
    let subject;
    try {
      subject = normalizeSubject(rec);
    } catch {
      continue; // sujet non identifiable sur cette ligne (ex. ligne étrangère) : ignorée
    }
    if (subject.type === subjectType && subject.id === subjectId && rec.timestamp === timestamp) return true;
  }
  return false;
}

/**
 * Backfill knowledge_base/learning_curve.jsonl depuis les runs Forge archivés.
 * @param {{runsDir?:string, gamesDir?:string, targetPath?:string}} [options]
 * @returns {Array<{run:string, project?:string, effective_project?:string, is_game?:boolean,
 *   escalations?:number, oracle_iterations?:number, skipped:boolean, reason?:string, record?:object}>}
 */
export function backfillLearningCurve(options = {}) {
  const {
    runsDir = DEFAULT_RUNS_DIR,
    gamesDir = DEFAULT_GAMES_DIR,
    targetPath = DEFAULT_LEARNING_CURVE_PATH,
  } = options;

  const results = [];

  let runNames;
  try {
    runNames = readdirSync(runsDir, { withFileTypes: true })
      .filter((e) => e.isDirectory())
      .map((e) => e.name)
      .sort();
  } catch (err) {
    return [{ run: null, skipped: true, reason: `runsDir illisible (${runsDir}) : ${err.message}` }];
  }

  for (const runName of runNames) {
    const statePath = join(runsDir, runName, 'state.json');
    // Pas de state.json = pas un "run archivé" au sens de cette tâche (7 runs connus) —
    // ignoré silencieusement, ce n'est pas une anomalie à rapporter.
    if (!existsSync(statePath)) continue;

    let state;
    try {
      state = JSON.parse(readFileSync(statePath, 'utf-8'));
    } catch (err) {
      results.push({ run: runName, skipped: true, reason: `state.json illisible/corrompu : ${err.message}` });
      continue;
    }

    const project = typeof state.project === 'string' && state.project.length > 0 ? state.project : runName;
    const isGame = state.is_game === true;
    const escalations = normalizeEscalations(state.escalations);
    const base = { run: runName, project, is_game: isGame, escalations };

    const oracleInfo = resolveOracleIterations(state.steps);
    if (!oracleInfo) {
      results.push({
        ...base, skipped: true,
        reason: 'aucune étape oracle de code (s10a-oracle-code / s10s-oracle-standard) '
          + "au statut OK dans steps — jamais atteint le vert (steps vide/absent, ou "
          + 'FAIL/BLOCKED/PENDING) : oracle_iterations non mesurable',
      });
      continue;
    }

    const withOracle = { ...base, oracle_iterations: oracleInfo.iterations };

    if (!isGame) {
      // Un run non-jeu n'est PAS automatiquement une brique (LEARNING_SUBJECT_MODEL_V1) :
      // ce pipeline (driver.py/state.json) n'a aucune source équivalente à gameDir pour
      // mesurer le reuse_ratio d'une brique de bibliothèque. Brancher une telle source
      // (knowledge_base/systems/<brick>/) est l'étape 2 du plan ratifié, pas celle-ci.
      results.push({
        ...withOracle, skipped: true,
        reason: 'is_game=false — ce run ne construit pas un JEU ; ce pipeline ne porte '
          + "aucune source de mesure de reuse_ratio pour une brique de bibliothèque "
          + '(brancher cette source est l\'étape 2 du plan ratifié, pas celle-ci)',
      });
      continue;
    }

    // gameDir réel : préférer celui du reçu de mutation déjà signé par ce run (autorité de
    // la mesure existante) plutôt que deviner gamesDir/<project> — les runs patch/art (ex.
    // shmup_slice_patch2) opèrent sur le JEU DE BASE (GAMES/shmup_slice), pas sur un dossier
    // GAMES/shmup_slice_patch2 qui n'existe pas.
    const mutationGameDir = oracleInfo.detail && oracleInfo.detail.mutation
      && oracleInfo.detail.mutation.receipt && oracleInfo.detail.mutation.receipt.detail
      ? oracleInfo.detail.mutation.receipt.detail.game_dir
      : undefined;
    const gameDir = mutationGameDir || join(gamesDir, project);
    const effectiveProject = mutationGameDir ? _lastPathSegment(mutationGameDir) : project;
    const withProject = { ...withOracle, effective_project: effectiveProject };

    if (!existsSync(gameDir)) {
      results.push({
        ...withProject, skipped: true,
        reason: `gameDir introuvable (${gameDir}) — reuse_ratio non mesurable`,
      });
      continue;
    }

    const timestamp = typeof oracleInfo.ts === 'number'
      ? _isoFromEpochSeconds(oracleInfo.ts)
      : (typeof state.updated_ts === 'number' ? _isoFromEpochSeconds(state.updated_ts) : undefined);

    if (timestamp === undefined) {
      results.push({
        ...withProject, skipped: true,
        reason: 'aucun horodatage exploitable (ni step.ts ni state.updated_ts) — timestamp '
          + 'requis pour une ligne, jamais inventé',
      });
      continue;
    }

    if (_recordExists(targetPath, 'game', effectiveProject, timestamp)) {
      results.push({
        ...withProject, skipped: true,
        reason: 'déjà présent dans la courbe (même subject + timestamp) — backfill '
          + 'idempotent, pas de doublon',
      });
      continue;
    }

    const reuse = measureReuseRatio(gameDir);
    const record = recordLearning(
      {
        subject: { type: 'game', id: effectiveProject },
        reuse_ratio: reuse.reuseRatio,
        oracle_iterations: oracleInfo.iterations,
        joust_delta: null,
      },
      timestamp,
      targetPath,
    );
    results.push({
      ...withProject, skipped: false, record,
      reuse_ratio_detail: { logicFileCount: reuse.logicFiles.length, reusedModules: reuse.reusedModules },
    });
  }

  return results;
}

function main() {
  const results = backfillLearningCurve();
  const written = results.filter((r) => !r.skipped);
  const skipped = results.filter((r) => r.skipped);
  console.error(`=== BACKFILL learning_curve.jsonl — ${results.length} run(s) archivé(s) examiné(s) ===\n`);
  for (const r of results) {
    if (r.skipped) {
      console.error(`SKIP  ${r.run ?? '(?)'} — ${r.reason}`);
    } else {
      console.error(`OK    ${r.run} -> subject=game:${r.effective_project} reuse_ratio=${r.record.reuse_ratio.toFixed(3)} oracle_iterations=${r.record.oracle_iterations}`);
    }
  }
  console.error(`\n${written.length} ligne(s) écrite(s), ${skipped.length} run(s) skipped.`);
  console.log(JSON.stringify(results, null, 2));
  process.exit(0); // mesure advisory, jamais un gate — toujours exit 0
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
