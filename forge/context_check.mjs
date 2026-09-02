#!/usr/bin/env node
// context_check.mjs — Context Integrity Check advisory (Context Loop V1.1, périmètre GO
// ratifié Pierre — docs/forge/CONTEXT_LOOP_V1_1_FRESHNESS.md §3-§4).
//
// Rôle : lecteur READ-ONLY. Diff les sources d'un manifest de contexte (produit par
// prepare_dispatch côté Python, schéma forge.context_manifest.v1) contre l'état actuel du
// repo, calcule un score de fraîcheur DÉTERMINISTE (aucun LLM, aucune pondération), et
// remonte des recommandations TEXTE pour un humain. Ne vérifie PAS le HMAC des manifests
// (c'est le rôle de verify_run.py côté Python — R1 étendu). Jamais de gate : advisory pur,
// exit code toujours 0.
//
// Entrée : EVIDENCE/runs/<projet>/context/<etape>.manifest.jsonl — 1 ligne JSON par
// enregistrement, kind "dispatch" ou "execution" (schéma forge.context_manifest.v1, voir
// CONTEXT_LOOP_V1_1_FRESHNESS.md §1). Fichier absent, ligne corrompue, kind inconnu :
// signalés proprement, jamais un crash.
//
// Score (première règle qui matche, doc §3) :
//   REQUIRES_REFRESH  ≥1 source role "upstream"/"contract" changed/removed
//   STALE_CRITICAL    ≥1 autre source changed OU nouvelles décisions Pierre > 0
//   STALE_WARNING     commits_since > 0 OU nouvelles entrées pré-mortem > 0 OU age_hours > 72
//   FRESH             rien de ce qui précède
//   NO_MANIFEST       (hors doc §3, ajouté ici) aucun manifest exploitable pour cette étape —
//                      information neutre, pas une dérive détectée.
//
// Usage : node forge/context_check.mjs <projet> [--etape <etape>] [--json]
// Exit codes : TOUJOURS 0 (advisory — jamais de gate). Une erreur interne inattendue est
// signalée dans le JSON (voir `internal_error`) mais l'exit code reste 0.
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join, dirname, resolve, isAbsolute } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';

const CRITICAL_ROLES = new Set(['upstream', 'contract']);
const AGE_WARNING_HOURS = 72;

// --- primitives --------------------------------------------------------------------------

/**
 * sha256 hexdigest d'un fichier repo-relatif. null si illisible (jamais une exception qui fuit).
 * @param {string} absPath
 * @returns {string|null}
 */
export function sha256File(absPath) {
  try {
    return createHash('sha256').update(readFileSync(absPath)).digest('hex');
  } catch {
    return null;
  }
}

/**
 * Convertit un ts de manifest (convention Forge : epoch secondes, ex. time.time()) ou une
 * chaîne ISO en epoch millisecondes. null si non exploitable — jamais de NaN qui fuit.
 * @param {number|string|null|undefined} ts
 * @returns {number|null}
 */
export function toEpochMs(ts) {
  if (typeof ts === 'number' && Number.isFinite(ts)) return ts * 1000;
  if (typeof ts === 'string' && ts.trim() !== '') {
    const parsed = Date.parse(ts);
    if (!Number.isNaN(parsed)) return parsed;
  }
  return null;
}

function resolveRepoPath(repoRoot, relOrAbsPath) {
  return isAbsolute(relOrAbsPath) ? relOrAbsPath : join(repoRoot, relOrAbsPath);
}

// --- chargement manifest -------------------------------------------------------------------

/**
 * Charge et classe les lignes d'un manifest JSONL, tolérant aux lignes corrompues et aux
 * kind inconnus.
 * @param {string} absManifestPath
 * @returns {{status:'OK'|'ABSENT', dispatches:object[], executions:object[], ignored_lines:number, unknown_kind_lines:number, total_lines:number}}
 */
export function loadManifest(absManifestPath) {
  if (!existsSync(absManifestPath)) {
    return { status: 'ABSENT', dispatches: [], executions: [], ignored_lines: 0, unknown_kind_lines: 0, total_lines: 0 };
  }
  const text = readFileSync(absManifestPath, 'utf-8');
  const lines = text.split(/\r?\n/).filter((l) => l.trim() !== '');
  const dispatches = [];
  const executions = [];
  let ignored = 0;
  let unknownKind = 0;
  for (const line of lines) {
    let parsed;
    try {
      parsed = JSON.parse(line);
    } catch {
      ignored += 1;
      continue;
    }
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
      ignored += 1;
      continue;
    }
    if (parsed.kind === 'dispatch') dispatches.push(parsed);
    else if (parsed.kind === 'execution') executions.push(parsed);
    else unknownKind += 1;
  }
  return { status: 'OK', dispatches, executions, ignored_lines: ignored, unknown_kind_lines: unknownKind, total_lines: lines.length };
}

// --- diff sources --------------------------------------------------------------------------

/**
 * Recalcule le sha256 actuel de chaque source déclarée par le dernier dispatch et classe
 * son statut vs le manifest.
 * @param {Array<{path:string, sha256?:string, exists?:boolean, role?:string}>} manifestSources
 * @param {string} repoRoot
 * @returns {object[]}
 */
export function diffSources(manifestSources, repoRoot) {
  return (manifestSources || []).map((src) => {
    const abs = resolveRepoPath(repoRoot, src.path);
    const currentExists = existsSync(abs);
    const currentSha256 = currentExists ? sha256File(abs) : null;
    const manifestExists = src.exists !== false; // absence du champ traitée comme "existait"

    let status;
    if (!manifestExists && currentExists) status = 'added';
    else if (manifestExists && !currentExists) status = 'removed';
    else if (manifestExists && currentExists) status = (src.sha256 === currentSha256) ? 'unchanged' : 'changed';
    else status = 'unchanged'; // absent au manifest, toujours absent

    return {
      path: src.path,
      role: src.role || null,
      manifest_sha256: src.sha256 ?? null,
      manifest_exists: manifestExists,
      current_exists: currentExists,
      current_sha256: currentSha256,
      status,
    };
  });
}

// --- signaux de fraîcheur --------------------------------------------------------------------

function gitRevListCount(gitHead, repoRoot) {
  if (!gitHead) return null;
  try {
    const out = execFileSync('git', ['rev-list', '--count', `${gitHead}..HEAD`], { cwd: repoRoot, encoding: 'utf-8', timeout: 5000 });
    const n = Number(out.trim());
    return Number.isFinite(n) ? n : null;
  } catch {
    return null; // gitHead invalide, hors historique, ou hors repo git — best-effort
  }
}

/**
 * Compte les lignes de EVIDENCE/reports/error_journal/*.jsonl dont ts > dispatchTsMs.
 * Répertoire absent ou vide : 0 (pas indisponible — il n'y a simplement rien de nouveau).
 * @param {string} repoRoot
 * @param {number|null} dispatchTsMs
 * @returns {number|null}
 */
export function countNewPremortemEntries(repoRoot, dispatchTsMs) {
  if (dispatchTsMs === null) return null;
  const dir = join(repoRoot, 'EVIDENCE', 'reports', 'error_journal');
  if (!existsSync(dir)) return 0;
  let files;
  try {
    files = readdirSync(dir).filter((f) => f.endsWith('.jsonl'));
  } catch {
    return 0;
  }
  let count = 0;
  for (const f of files) {
    let text;
    try {
      text = readFileSync(join(dir, f), 'utf-8');
    } catch {
      continue;
    }
    for (const line of text.split(/\r?\n/)) {
      if (line.trim() === '') continue;
      let parsed;
      try {
        parsed = JSON.parse(line);
      } catch {
        continue;
      }
      if (parsed === null || typeof parsed !== 'object') continue;
      const entryTsMs = toEpochMs(parsed.ts);
      if (entryTsMs !== null && entryTsMs > dispatchTsMs) count += 1;
    }
  }
  return count;
}

/**
 * Compte les lignes de EVIDENCE/reports/pending_review_decisions.jsonl dont ts (format ISO date,
 * parse tolérant) est postérieur au dispatch.
 * @param {string} repoRoot
 * @param {number|null} dispatchTsMs
 * @returns {number|null}
 */
export function countNewDecisions(repoRoot, dispatchTsMs) {
  if (dispatchTsMs === null) return null;
  const path = join(repoRoot, 'EVIDENCE', 'reports', 'pending_review_decisions.jsonl');
  if (!existsSync(path)) return 0;
  let text;
  try {
    text = readFileSync(path, 'utf-8');
  } catch {
    return 0;
  }
  let count = 0;
  for (const line of text.split(/\r?\n/)) {
    if (line.trim() === '') continue;
    let parsed;
    try {
      parsed = JSON.parse(line);
    } catch {
      continue;
    }
    if (parsed === null || typeof parsed !== 'object') continue;
    const entryTsMs = toEpochMs(parsed.ts);
    if (entryTsMs !== null && entryTsMs > dispatchTsMs) count += 1;
  }
  return count;
}

/**
 * @param {{dispatch:object, repoRoot:string, nowMs:number}} args
 */
export function computeSignals({ dispatch, repoRoot, nowMs }) {
  const dispatchTsMs = toEpochMs(dispatch?.ts);
  const ageHours = dispatchTsMs !== null ? Math.round(((nowMs - dispatchTsMs) / 3600000) * 100) / 100 : null;
  const commitsSince = gitRevListCount(dispatch?.git_head || null, repoRoot);
  const premortemNewCount = countNewPremortemEntries(repoRoot, dispatchTsMs);
  const decisionsNewCount = countNewDecisions(repoRoot, dispatchTsMs);
  return { age_hours: ageHours, commits_since: commitsSince, premortem_new_count: premortemNewCount, decisions_new_count: decisionsNewCount };
}

// --- score -----------------------------------------------------------------------------------

/**
 * @param {{sourceDiffs:object[], signals:object}} args
 * @returns {{score:string, causes:string[]}}
 */
export function computeScore({ sourceDiffs, signals }) {
  const causes = [];

  // 'added' compte comme une dérive : une source absente au dispatch qui existe
  // maintenant signifie que l'agent a travaillé SANS un contexte devenu disponible
  // (trou attrapé lors du test d'intégration du 2026-07-25, sonde _ctx_smoke).
  const DRIFTED = new Set(['changed', 'removed', 'added']);
  const criticalHit = sourceDiffs.filter((s) => CRITICAL_ROLES.has(s.role) && DRIFTED.has(s.status));
  if (criticalHit.length > 0) {
    for (const s of criticalHit) causes.push(`source ${s.path} (role=${s.role}) ${s.status} — refresh requis`);
    return { score: 'REQUIRES_REFRESH', causes };
  }

  const otherChanged = sourceDiffs.filter((s) => !CRITICAL_ROLES.has(s.role) && DRIFTED.has(s.status));
  const decisionsNew = signals.decisions_new_count ?? 0;
  if (otherChanged.length > 0 || decisionsNew > 0) {
    for (const s of otherChanged) causes.push(`source ${s.path} (role=${s.role || 'n/a'}) ${s.status}`);
    if (decisionsNew > 0) causes.push(`${decisionsNew} nouvelle(s) décision(s) Pierre depuis le dispatch`);
    return { score: 'STALE_CRITICAL', causes };
  }

  const commitsSince = signals.commits_since ?? 0;
  const premortemNew = signals.premortem_new_count ?? 0;
  const ageHours = signals.age_hours ?? 0;
  if (commitsSince > 0 || premortemNew > 0 || ageHours > AGE_WARNING_HOURS) {
    if (commitsSince > 0) causes.push(`${commitsSince} commit(s) depuis le dispatch (git_head)`);
    if (premortemNew > 0) causes.push(`${premortemNew} nouvelle(s) entrée(s) pré-mortem depuis le dispatch`);
    if (ageHours > AGE_WARNING_HOURS) causes.push(`age_hours=${ageHours} > ${AGE_WARNING_HOURS}h`);
    return { score: 'STALE_WARNING', causes };
  }

  return { score: 'FRESH', causes: [] };
}

// --- budget ------------------------------------------------------------------------------------

function extractBudget(execution) {
  // P7 (lot dégel 2) : le nom courant est `prompt_budget` (il ne mesure que le
  // prompt contractuel, ~8 % du contexte réel — l'ancien nom promettait plus).
  // `context_budget` n'est accepté qu'en LECTURE LEGACY, pour les manifestes
  // écrits avant 2026-07-31 — jamais réécrits (artefacts de runs passés).
  const budget = execution?.prompt_budget ?? execution?.context_budget;
  if (!execution || !budget) return { status: 'NO_EXECUTION_RECORD' };
  return {
    status: budget.status || 'UNKNOWN_WINDOW',
    model_window_tokens: budget.model_window_tokens ?? null,
    estimated_tokens: budget.estimated_tokens ?? null,
  };
}

// --- recommandations (texte humain, aucune action automatique) -------------------------------

function buildRecommendations(etape, score) {
  switch (score) {
    case 'REQUIRES_REFRESH':
      return [`${etape} : source critique (upstream/contract) modifiée ou disparue depuis la dernière activation — recommandation : re-dispatch ${etape} avec relecture des sources avant de réutiliser un résultat basé sur ce manifest.`];
    case 'STALE_CRITICAL':
      return [`${etape} : dérive significative (source secondaire modifiée et/ou décision(s) Pierre nouvelle(s) non reflétée(s)) — recommandation : relire les décisions récentes avant de faire confiance à un futur run de ${etape}.`];
    case 'STALE_WARNING':
      return [`${etape} : signal de dérive légère (commits/pré-mortem/âge) — recommandation : vérification manuelle avant un prochain dispatch de ${etape}, non bloquant.`];
    case 'NO_MANIFEST':
      return [`${etape} : aucun Context Manifest exploitable — information seulement (probablement une étape antérieure à V1.1, ou pas encore dispatchée). Aucune action requise.`];
    default:
      return [];
  }
}

// --- une étape -----------------------------------------------------------------------------

/**
 * @param {string} repoRoot
 * @param {string} project
 * @param {string} etape
 * @param {{nowMs?:number}} [opts]
 */
export function checkEtape(repoRoot, project, etape, opts = {}) {
  const nowMs = opts.nowMs ?? Date.now();
  const manifestRelPath = join('EVIDENCE', 'runs', project, 'context', `${etape}.manifest.jsonl`);
  const manifestAbsPath = join(repoRoot, manifestRelPath);
  const loaded = loadManifest(manifestAbsPath);

  const base = { etape, manifest_path: manifestRelPath };

  if (loaded.status === 'ABSENT') {
    return {
      ...base,
      manifest_status: 'ABSENT',
      score: 'NO_MANIFEST',
      causes: [`aucun manifest trouvé à ${manifestRelPath}`],
      diff: { sources: [] },
      signals: {},
      budget: { status: 'NO_EXECUTION_RECORD' },
      recommendations: buildRecommendations(etape, 'NO_MANIFEST'),
      ignored_lines: 0,
      unknown_kind_lines: 0,
    };
  }

  const dispatch = loaded.dispatches.length > 0 ? loaded.dispatches[loaded.dispatches.length - 1] : null;
  const execution = loaded.executions.length > 0 ? loaded.executions[loaded.executions.length - 1] : null;

  if (!dispatch) {
    return {
      ...base,
      manifest_status: 'OK_NO_DISPATCH',
      score: 'NO_MANIFEST',
      causes: ['manifest présent mais aucune ligne kind="dispatch" exploitable'],
      diff: { sources: [] },
      signals: {},
      budget: extractBudget(execution),
      recommendations: buildRecommendations(etape, 'NO_MANIFEST'),
      ignored_lines: loaded.ignored_lines,
      unknown_kind_lines: loaded.unknown_kind_lines,
    };
  }

  const sourceDiffs = diffSources(dispatch.sources, repoRoot);
  const signals = computeSignals({ dispatch, repoRoot, nowMs });
  const { score, causes } = computeScore({ sourceDiffs, signals });
  const budget = extractBudget(execution);
  const recommendations = buildRecommendations(etape, score);

  return {
    ...base,
    manifest_status: 'OK',
    score,
    causes,
    diff: { sources: sourceDiffs },
    signals,
    budget,
    recommendations,
    ignored_lines: loaded.ignored_lines,
    unknown_kind_lines: loaded.unknown_kind_lines,
    dispatch_ts: dispatch.ts ?? null,
    git_head: dispatch.git_head ?? null,
  };
}

// --- un projet (toutes les étapes ayant un manifest, ou l'étape demandée) ---------------------

/**
 * @param {string} repoRoot
 * @param {string} project
 * @param {{etape?:string|null, nowMs?:number}} [opts]
 */
export function checkProject(repoRoot, project, opts = {}) {
  const contextDir = join(repoRoot, 'EVIDENCE', 'runs', project, 'context');

  let etapes;
  if (opts.etape) {
    etapes = [opts.etape];
  } else if (existsSync(contextDir)) {
    let files;
    try {
      files = readdirSync(contextDir).filter((f) => f.endsWith('.manifest.jsonl'));
    } catch {
      files = [];
    }
    etapes = files.map((f) => f.slice(0, -'.manifest.jsonl'.length)).sort();
  } else {
    etapes = [];
  }

  const results = etapes.map((e) => checkEtape(repoRoot, project, e, { nowMs: opts.nowMs }));

  return {
    project,
    context_dir: join('EVIDENCE', 'runs', project, 'context'),
    context_dir_exists: existsSync(contextDir),
    generated_ts: (opts.nowMs ?? Date.now()) / 1000,
    etapes: results,
    claim_verdict: 'NO_CLAIM_ALLOWED',
  };
}

// --- CLI ---------------------------------------------------------------------------------------

function formatLine(e) {
  const causesTxt = e.causes && e.causes.length ? e.causes.join(' ; ') : '(aucune cause)';
  return `  ${e.etape.padEnd(24)} ${e.score.padEnd(18)} ${causesTxt}`;
}

function main() {
  const here = dirname(fileURLToPath(import.meta.url));
  const args = process.argv.slice(2);
  const positional = [];
  let etape = null;
  let asJson = false;
  for (let i = 0; i < args.length; i += 1) {
    if (args[i] === '--etape') {
      etape = args[i + 1] ?? null;
      i += 1;
    } else if (args[i] === '--json') {
      asJson = true;
    } else if (!args[i].startsWith('--')) {
      positional.push(args[i]);
    }
  }
  const project = positional[0];
  const repoRoot = resolve(here, '..');

  if (!project) {
    console.error('Usage: node forge/context_check.mjs <projet> [--etape <etape>] [--json]');
    console.error('Advisory only — exit 0 même sans argument valide (jamais de gate).');
    process.exit(0);
  }

  let result;
  try {
    result = checkProject(repoRoot, project, { etape });
  } catch (err) {
    console.error(`[context_check] ERREUR INTERNE (non bloquante, advisory) : ${err.message}`);
    console.log(JSON.stringify({ project, internal_error: err.message, etapes: [], claim_verdict: 'NO_CLAIM_ALLOWED' }, null, 2));
    process.exit(0);
    return;
  }

  console.error(`=== context_check — ${project} (advisory, jamais de gate) ===`);
  if (result.etapes.length === 0) {
    console.error(`  aucun manifest trouvé (dossier ${result.context_dir} ${result.context_dir_exists ? 'vide' : 'absent'})`);
  } else {
    for (const e of result.etapes) console.error(formatLine(e));
  }
  console.error('\nclaim_verdict: NO_CLAIM_ALLOWED — recommandations = texte pour humain, aucune action automatique.');

  if (asJson) {
    console.log(JSON.stringify(result, null, 2));
  }
  process.exit(0);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
