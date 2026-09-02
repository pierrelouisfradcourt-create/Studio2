#!/usr/bin/env node
// learning_metrics.mjs — instrumentation d'apprentissage de la Forge (Task 12 + généralisation
// LEARNING_SUBJECT_MODEL_V1, ratifiée Pierre 2026-07-26).
//
// Objectif : ne pas seulement produire des jeux, mais consigner CE QUE LA FORGE A APPRIS
// en forgeant chaque SUJET — reuse_ratio (combien vient de la bibliothèque), le nombre
// d'itérations d'oracle nécessaires avant le vert, et un delta de joute quand une
// comparaison à l'état de l'art existe. Une seule mécanique n'a AUCUNE valeur statistique
// (spec §10) : cette instrumentation établit la ligne de base et prouve qu'elle enregistre,
// rien de plus. Voir knowledge_base/LEARNING_CURVE_README.md pour la mention complète de la limite.
//
// LEARNING_SUBJECT_MODEL_V1 (studio_brain/decisions/PROPOSED_2026-07-26_ratifications.md) :
// `brick_id` (seule unité au lancement de l'instrumentation) devient un SUJET TYPÉ
// `subject: {type, id}` avec `type` ∈ SUBJECT_TYPES — parce que tous les runs Forge
// forgent un JEU, pas une brique de bibliothèque (le backfill sur 7 runs archivés produisait
// 0 ligne en indexant par brick_id). `type` est une ÉNUMÉRATION CONTRAINTE, jamais un champ
// libre : une valeur inconnue est refusée explicitement (sinon la prolifération qu'on refuse
// au niveau des fichiers reviendrait au niveau des valeurs).
//
// Rétro-compatibilité : PAR NORMALISATION À LA LECTURE, jamais en réécrivant une ligne
// existante. `buildRecord`/`recordLearning` (écriture) exigent désormais `subject` — ils
// n'écrivent QUE le nouveau format. La ligne historique {brick_id} (knowledge_base/
// learning_curve.jsonl, sys-grid-nav-m01, saisie manuelle) n'est JAMAIS réécrite ; c'est
// `normalizeSubject` (lecture) qui l'interprète, même patron déjà établi dans ce dépôt :
// `hook_guard.marker_key` (marqueur historique 2-champs -> triplet avec attempt=0) et
// `studio_link.premortem` (entrées de journal sans resolution/status).
//
// Discipline stricte : buildRecord() est PUR — pas de disque, pas d'horloge interne
// (le timestamp est injecté en paramètre), donc testable et déterministe.
// recordLearning() est l'unique point d'effet de bord (écriture JSONL en append).
import { appendFileSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

// Chemin par défaut de la courbe d'apprentissage — ANCRÉ SUR L'EMPLACEMENT DU MODULE
// (import.meta.url), calculé UNE FOIS à l'import, jamais sur process.cwd() (règle du
// dépôt : chemins repo-relatifs, jamais dépendants du répertoire d'appel). Avant ce
// correctif, le défaut était la chaîne littérale 'knowledge_base/learning_curve.jsonl',
// silencieusement fausse dès que le script tournait depuis un autre cwd (ex. driver.py
// lancé depuis EVIDENCE/runs/<run>/). forge/learning_metrics.mjs -> deux
// niveaux au-dessus == racine du dépôt (même schéma que _SEARCH_LOG_DEFAULT côté Python
// dans static_oracles.py).
const _MODULE_DIR = dirname(fileURLToPath(import.meta.url));
export const DEFAULT_LEARNING_CURVE_PATH = join(_MODULE_DIR, '..', 'knowledge_base', 'learning_curve.jsonl');

// Énumération contrainte du sujet observé par la courbe d'apprentissage. `brick` = une
// capacité réutilisable de knowledge_base/ (entry_type=="brick" du catalogue) ; `game` =
// un jeu assemblé (GAMES/<projet>). Un jeu n'est PAS une brique (LEARNING_SUBJECT_MODEL_V1,
// alternative rejetée « promouvoir tous les jeux en briques ») : ce sont deux familles
// disjointes, jamais l'une déguisée en l'autre. `Object.freeze` : jamais muté à l'exécution.
export const SUBJECT_TYPES = Object.freeze(['brick', 'game']);

/**
 * Valide un `subject` candidat ({type, id}) et retourne sa forme canonique verrouillée
 * (jamais de champs additionnels invités par accident). Lève une erreur explicite sur
 * tout sujet mal formé — jamais de coercion silencieuse (le fondement de l'énumération
 * contrainte : une valeur de `type` inconnue doit être un ÉCHEC visible, pas une ligne
 * inventée sous un nom approximatif).
 * @param {unknown} subject
 * @returns {{type:string, id:string}}
 */
function _validateSubject(subject) {
  if (subject === undefined || subject === null || typeof subject !== 'object' || Array.isArray(subject)) {
    throw new Error(
      'subject manquant ou invalide (objet {type, id} attendu) : pas de ligne anonyme dans la courbe d\'apprentissage',
    );
  }
  if (!SUBJECT_TYPES.includes(subject.type)) {
    throw new Error(
      `subject.type invalide (attendu ${JSON.stringify(SUBJECT_TYPES)}, énumération contrainte) : ${JSON.stringify(subject.type)}`,
    );
  }
  if (typeof subject.id !== 'string' || subject.id.length === 0) {
    throw new Error('subject.id manquant ou vide : pas de ligne anonyme dans la courbe d\'apprentissage');
  }
  return { type: subject.type, id: subject.id };
}

/**
 * Normalise N'IMPORTE QUELLE ligne persistée (déjà parsée depuis JSON) vers la forme
 * canonique `{type, id}` — SEUL point de lecture du sujet, à utiliser par tout futur
 * consommateur de knowledge_base/learning_curve.jsonl plutôt que d'inspecter `record.subject`
 * ou `record.brick_id` directement. Deux formes acceptées :
 *  - `{subject: {type, id}}` (format courant, post LEARNING_SUBJECT_MODEL_V1) ;
 *  - `{brick_id: "..."}` (format historique, jamais réécrit sur disque) -> normalisé en
 *    `{type: 'brick', id: brick_id}` (une brique était la SEULE unité avant cette généralisation).
 * `subject` ET `brick_id` présents simultanément -> REFUS explicite (règle décidée ici,
 * anti-invention : on ne devine JAMAIS lequel des deux prime ; un enregistrement porte
 * l'un OU l'autre, jamais les deux — un futur bug d'écriture double ne doit pas produire
 * une lecture silencieusement fausse).
 * @param {unknown} record
 * @returns {{type:string, id:string}}
 */
export function normalizeSubject(record) {
  if (!record || typeof record !== 'object' || Array.isArray(record)) {
    throw new Error('record invalide (objet attendu) : impossible de normaliser le sujet');
  }
  const hasSubject = record.subject !== undefined && record.subject !== null;
  const hasBrickId = record.brick_id !== undefined && record.brick_id !== null;
  if (hasSubject && hasBrickId) {
    throw new Error(
      'record porte à la fois subject et brick_id : ambigu, refusé (anti-invention) — un ' +
      'enregistrement doit porter l\'un OU l\'autre, jamais les deux',
    );
  }
  if (hasSubject) {
    return _validateSubject(record.subject);
  }
  if (hasBrickId) {
    if (typeof record.brick_id !== 'string' || record.brick_id.length === 0) {
      throw new Error('brick_id historique manquant ou vide : sujet non identifiable');
    }
    return { type: 'brick', id: record.brick_id };
  }
  throw new Error('record sans subject ni brick_id : sujet non identifiable');
}

/**
 * Construit (et valide) une ligne de la courbe d'apprentissage. Fonction pure : aucun
 * accès disque, aucun Date.now() interne — le timestamp est fourni par l'appelant pour
 * rester déterministe et testable.
 * @param {{subject:{type:string,id:string}, reuse_ratio:number, oracle_iterations:number, joust_delta:(number|null)}} params
 * @param {string} [timestamp] ISO 8601, injecté par l'appelant (défaut: non fourni -> omis du record par recordLearning)
 * @returns {{subject:{type:string,id:string}, reuse_ratio:number, oracle_iterations:number, joust_delta:(number|null), no_comparison:boolean, timestamp:(string|undefined)}}
 */
export function buildRecord({ subject, reuse_ratio, oracle_iterations, joust_delta }, timestamp) {
  const resolvedSubject = _validateSubject(subject);
  if (typeof reuse_ratio !== 'number' || Number.isNaN(reuse_ratio) || reuse_ratio < 0) {
    throw new Error(`reuse_ratio invalide (nombre >= 0 attendu) : ${reuse_ratio}`);
  }
  if (typeof oracle_iterations !== 'number' || !Number.isInteger(oracle_iterations) || oracle_iterations < 0) {
    throw new Error(`oracle_iterations invalide (entier >= 0 attendu) : ${oracle_iterations}`);
  }
  if (joust_delta !== null && typeof joust_delta !== 'number') {
    throw new Error(`joust_delta invalide (nombre ou null attendu) : ${joust_delta}`);
  }

  const record = {
    subject: resolvedSubject,
    reuse_ratio,
    oracle_iterations,
    joust_delta,
    no_comparison: joust_delta === null,
  };
  if (timestamp !== undefined) record.timestamp = timestamp;
  return record;
}

/**
 * Ajoute une ligne à knowledge_base/learning_curve.jsonl. Seul point d'effet de bord
 * du module : construit via buildRecord() (donc validé), puis écrit en append (une ligne
 * JSON par appel, jamais réécrit).
 * @param {{subject:{type:string,id:string}, reuse_ratio:number, oracle_iterations:number, joust_delta:(number|null)}} params
 * @param {string} [timestamp] ISO 8601 ; par défaut new Date().toISOString() (seul endroit du
 *   module où l'horloge réelle apparaît — jamais dans buildRecord()).
 * @param {string} [targetPath] chemin du fichier JSONL cible (paramétrable pour les tests).
 * @returns {object} le record écrit
 */
export function recordLearning(params, timestamp = new Date().toISOString(), targetPath = DEFAULT_LEARNING_CURVE_PATH) {
  const record = buildRecord(params, timestamp);
  const dir = dirname(targetPath);
  if (dir && dir !== '.' && !existsSync(dir)) mkdirSync(dir, { recursive: true });
  appendFileSync(targetPath, JSON.stringify(record) + '\n', 'utf-8');
  return record;
}

// --- CLI ---------------------------------------------------------------------------
// Point d'entrée en ligne de commande — AJOUTÉ pour rendre l'instrumentation appelable
// depuis un processus externe (driver.py, Python, n'importe quel appelant non-JS) sans
// jamais réimplémenter buildRecord/recordLearning ailleurs. Ne change ni ne contourne
// les deux fonctions ci-dessus : le CLI n'est qu'un habillage argv -> params.
//
// Usage : node learning_metrics.mjs record --subject-type <brick|game> --subject-id <id>
//   --reuse-ratio <n> --oracle-iterations <n> [--joust-delta <n>] [--timestamp <iso>] [--target <path>]
//
// Sortie : le record JSON (une ligne) sur stdout, exit 0. Toute erreur de validation
// (subject manquant, type inconnu, nombre invalide...) sort sur stderr avec exit 2 — RIEN
// n'est écrit dans ce cas (buildRecord lève avant que recordLearning touche le disque).
function _parseCliArgs(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    const token = argv[i];
    if (token.startsWith('--')) {
      const key = token.slice(2);
      const next = argv[i + 1];
      args[key] = next;
      i++;
    }
  }
  return args;
}

function _parseNumberArg(raw, label) {
  if (raw === undefined) return undefined;
  const n = Number(raw);
  if (Number.isNaN(n)) throw new Error(`${label} invalide (nombre attendu) : ${raw}`);
  return n;
}

export function runCli(argv) {
  const [command, ...rest] = argv;
  if (command !== 'record') {
    console.error(
      `Commande inconnue: ${command ?? '(aucune)'}. Usage:\n` +
      '  node learning_metrics.mjs record --subject-type <brick|game> --subject-id <id> ' +
      '--reuse-ratio <n> --oracle-iterations <n> [--joust-delta <n>] [--timestamp <iso>] [--target <path>]',
    );
    return 2;
  }
  const args = _parseCliArgs(rest);
  try {
    const hasSubjectArgs = args['subject-type'] !== undefined || args['subject-id'] !== undefined;
    const params = {
      subject: hasSubjectArgs ? { type: args['subject-type'], id: args['subject-id'] } : undefined,
      reuse_ratio: _parseNumberArg(args['reuse-ratio'], 'reuse_ratio'),
      oracle_iterations: _parseNumberArg(args['oracle-iterations'], 'oracle_iterations'),
      joust_delta: args['joust-delta'] === undefined ? null : _parseNumberArg(args['joust-delta'], 'joust_delta'),
    };
    const cliArgs = [params, args.timestamp ?? new Date().toISOString()];
    if (args.target !== undefined) cliArgs.push(args.target);
    const record = recordLearning(...cliArgs);
    console.log(JSON.stringify(record));
    return 0;
  } catch (err) {
    console.error(`learning_metrics record: ${err.message}`);
    return 2;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exit(runCli(process.argv.slice(2)));
}
