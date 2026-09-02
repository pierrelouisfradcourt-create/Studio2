#!/usr/bin/env node
// wiremap_nav.mjs — Navigation Wiremap des directeurs (Context Loop V2, Brique 6 —
// docs/forge/CONTEXT_LOOP_V2_PROPOSAL.md §2 Brique 6, décision D2 ratifiée Pierre
// 2026-07-25 « GO maintenant »).
//
// Rôle : lecteur READ-ONLY (famille context_check.mjs / declaration_readers.mjs). La Wiremap
// devient le système de coordonnées de la mémoire du projet : deux requêtes de navigation
// historique sur des artefacts EXISTANTS, zéro nouvelle donnée stockée, zéro écriture.
//
//   AVANT   : feature -> fichiers/fonction (wiremap) -> runs/étapes qui les ont touchés
//             (state.json + dispatch_audit.jsonl) -> modèle/rôle par étape (dispatch_audit) ->
//             décisions du projet (pending_review_decisions.jsonl) -> tests/preuve (champ
//             `preuve` de la wiremap) -> rapports d'agents (artifacts/*.txt, auto-déclarés).
//   INVERSE : fichier -> features qui le référencent -> même chaîne.
//   (aucun des deux) : vue d'ensemble — liste des features + compteurs.
//
// Sources lues (schémas réels observés le 2026-07-26 sur shmup_slice et card_engine — les
// deux projets divergent et ce lecteur reste TOLÉRANT aux deux) :
//   EVIDENCE/runs/<projet>/wiremap.json         — {features:[{feature,fonction,fichiers[],
//                                                    version,statut,preuve,section?}]}
//   EVIDENCE/runs/<projet>/wiremap_frozen.json  — {features:[<nom>,...]} (liste de NOMS,
//                                                    pas d'objets complets) — sert à détecter
//                                                    la dérive gel vs wiremap courante.
//   EVIDENCE/runs/<projet>/state.json           — driver Python (chemin riche) : présent sur
//                                                    shmup_slice, ABSENT sur card_engine (run
//                                                    prose) — absence signalée, jamais inventée.
//   EVIDENCE/bundles/dispatch_audit.jsonl      — 1 ligne par activation d'agent, TOUS
//                                                    projets confondus, filtrée par
//                                                    run_id.startsWith(projet).
//   EVIDENCE/reports/pending_review_decisions.jsonl   — décisions HumanGate, filtrées par le champ
//                                                    `item` (ou `queue`) qui mentionne le projet.
//   EVIDENCE/runs/<projet>/artifacts/*.txt      — rapports d'agents AUTO-DÉCLARÉS (pas une
//                                                    trace mécanique) — étiquetés comme tels.
//   EVIDENCE/runs/<projet>/context/*.manifest.jsonl   — Brique 1-2 (si présent) : enrichit,
//                                                    n'est requis nulle part.
//   EVIDENCE/runs/<projet>/context/*.checkpoint.json  — Brique 4, N'EXISTE PAS ENCORE : le
//                                                    branchement est prévu (voir
//                                                    loadCheckpoints ci-dessous) mais son
//                                                    absence est tolérée EN SILENCE (aucune
//                                                    note, aucun bruit tant que la brique
//                                                    n'existe pas).
//   git log --oneline -5 -- <fichier>            — best-effort, jamais fatal.
//
// Limite honnête (répétée dans CHAQUE sortie, jamais tue) : l'attribution est au niveau
// run+étape+modèle, PAS fichier-par-agent ligne-à-ligne — les agents ne commitent pas, git
// blame ne remonte qu'aux commits de Pierre. state.json ne mappe pas davantage un fichier
// précis à une étape précise (sauf le gate mutation quand ses métadonnées listent les
// fichiers couverts) ; c'est le rôle futur de la Brique 4 (checkpoints avec « fichiers
// concernés ») d'affiner cette granularité.
//
// Usage : node forge/wiremap_nav.mjs <projet> [--feature <id-ou-nom>] [--file <chemin>] [--json]
// Exit codes : TOUJOURS 0 — outil de lecture/navigation, jamais un gate.
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { join, dirname, resolve, isAbsolute, relative } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { execFileSync } from 'node:child_process';

export const GRANULARITY_NOTE =
  "Attribution au niveau run+étape+modèle (state.json/dispatch_audit), PAS fichier-par-agent " +
  "ligne-à-ligne — les agents ne commitent pas. artifacts/*.txt sont des rapports AUTO-DÉCLARÉS " +
  "(auto-attestation de l'agent), pas des traces mécaniques. La Brique 4 (checkpoints, " +
  "'fichiers concernés') affinera progressivement cette granularité quand elle existera.";

// --- primitives JSON tolérantes --------------------------------------------------------------

function readJsonTolerant(absPath) {
  if (!existsSync(absPath)) return { status: 'ABSENT', data: null };
  let text;
  try {
    text = readFileSync(absPath, 'utf-8');
  } catch (err) {
    return { status: 'UNREADABLE', data: null, error: err.message };
  }
  try {
    return { status: 'OK', data: JSON.parse(text) };
  } catch (err) {
    return { status: 'CORRUPT', data: null, error: err.message };
  }
}

function readJsonlTolerant(absPath) {
  if (!existsSync(absPath)) return { status: 'ABSENT', lines: [], ignored: 0 };
  let text;
  try {
    text = readFileSync(absPath, 'utf-8');
  } catch (err) {
    return { status: 'UNREADABLE', lines: [], ignored: 0, error: err.message };
  }
  const lines = [];
  let ignored = 0;
  for (const raw of text.split(/\r?\n/)) {
    if (raw.trim() === '') continue;
    try {
      const parsed = JSON.parse(raw);
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) lines.push(parsed);
      else ignored += 1;
    } catch {
      ignored += 1;
    }
  }
  return { status: 'OK', lines, ignored };
}

// --- 1. Wiremap (feature -> fichiers/fonction/preuve) ----------------------------------------

/**
 * Normalise une entrée de wiremap.json (les deux schémas réels observés diffèrent :
 * shmup_slice n'a pas `section`, card_engine oui ; `statut` vaut "fait" ou "construit" selon
 * le projet — jamais interprété, juste transmis tel quel).
 */
function normalizeFeatureEntry(raw) {
  return {
    feature: typeof raw?.feature === 'string' ? raw.feature : null,
    fonction: typeof raw?.fonction === 'string' && raw.fonction !== '' ? raw.fonction : null,
    fichiers: Array.isArray(raw?.fichiers) ? raw.fichiers.filter((f) => typeof f === 'string') : [],
    version: raw?.version ?? null,
    statut: raw?.statut ?? null,
    preuve: typeof raw?.preuve === 'string' ? raw.preuve : null,
    section: typeof raw?.section === 'string' ? raw.section : null,
  };
}

/**
 * @param {string} repoRoot
 * @param {string} project
 * @returns {{status:string, path:string, features:object[], run_id:?string, etape:?string, comment:?string, error?:string}}
 */
export function loadWiremap(repoRoot, project) {
  const relPath = join('EVIDENCE', 'runs', project, 'wiremap.json');
  const abs = join(repoRoot, relPath);
  const loaded = readJsonTolerant(abs);
  if (loaded.status !== 'OK') {
    return { status: loaded.status, path: relPath, features: [], run_id: null, etape: null, comment: null, error: loaded.error };
  }
  const raw = loaded.data;
  const featuresRaw = Array.isArray(raw?.features) ? raw.features : [];
  return {
    status: 'OK',
    path: relPath,
    features: featuresRaw.map(normalizeFeatureEntry).filter((f) => f.feature !== null),
    run_id: raw?.run_id ?? null,
    etape: raw?.etape ?? null,
    comment: typeof raw?._comment === 'string' ? raw._comment : null,
  };
}

/**
 * wiremap_frozen.json — schéma réel : {features:[<nom-string>,...]} (une liste de noms,
 * PAS d'objets complets). Tolérant si un jour des objets {feature:...} y apparaissent.
 * @param {string} repoRoot
 * @param {string} project
 */
export function loadWiremapFrozen(repoRoot, project) {
  const relPath = join('EVIDENCE', 'runs', project, 'wiremap_frozen.json');
  const abs = join(repoRoot, relPath);
  const loaded = readJsonTolerant(abs);
  if (loaded.status !== 'OK') {
    return { status: loaded.status, path: relPath, names: [], error: loaded.error };
  }
  const featuresRaw = Array.isArray(loaded.data?.features) ? loaded.data.features : [];
  const names = featuresRaw
    .map((f) => (typeof f === 'string' ? f : (f && typeof f.feature === 'string' ? f.feature : null)))
    .filter((n) => n !== null);
  return { status: 'OK', path: relPath, names };
}

/**
 * Compare la wiremap courante au gel : features apparues depuis le gel / features gelées
 * disparues de la wiremap courante (renommage ou suppression non répercutée). Advisory —
 * ne juge pas si c'est une dérive fautive ou une évolution voulue, seulement le fait.
 * @param {object[]} features wiremap courante normalisée
 * @param {?object} frozen résultat de loadWiremapFrozen
 */
export function computeFrozenDrift(features, frozen) {
  if (!frozen || frozen.status !== 'OK') {
    return { checked: false, reason: `wiremap_frozen.json ${frozen ? frozen.status : 'ABSENT'}`, divergent: false, added_since_freeze: [], missing_since_freeze: [] };
  }
  const currentNames = new Set(features.map((f) => f.feature));
  const frozenNames = new Set(frozen.names);
  const added_since_freeze = [...currentNames].filter((n) => !frozenNames.has(n));
  const missing_since_freeze = [...frozenNames].filter((n) => !currentNames.has(n));
  return {
    checked: true,
    divergent: added_since_freeze.length > 0 || missing_since_freeze.length > 0,
    added_since_freeze,
    missing_since_freeze,
  };
}

// --- 2. state.json (driver Python — chemin riche, peut être ABSENT) ---------------------------

/**
 * @param {string} repoRoot
 * @param {string} project
 * @returns {{status:string, run_id:?string, run_status:?string, steps:object[], error?:string}}
 */
export function loadStateSteps(repoRoot, project) {
  const relPath = join('EVIDENCE', 'runs', project, 'state.json');
  const abs = join(repoRoot, relPath);
  const loaded = readJsonTolerant(abs);
  if (loaded.status !== 'OK') {
    return { status: loaded.status, path: relPath, run_id: null, run_status: null, steps: [], error: loaded.error };
  }
  const raw = loaded.data;
  const stepsObj = raw?.steps && typeof raw.steps === 'object' ? raw.steps : {};
  const steps = Object.entries(stepsObj).map(([etape, s]) => ({
    etape,
    status: s?.status ?? null,
    attempts: s?.attempts ?? null,
    ts: typeof s?.ts === 'number' ? s.ts : null,
    model: s?.detail?.model ?? null,
    reviewer: s?.detail?.reviewer ?? null,
    artifact_path: s?.detail?.artifact_path ?? null,
    is_oracle_step: !s?.detail?.model, // heuristique : étapes s10a/b/c (oracle code/archi/wiremap) n'ont pas de champ model
  }));
  steps.sort((a, b) => (a.ts ?? 0) - (b.ts ?? 0));
  return { status: 'OK', path: relPath, run_id: raw?.run_id ?? null, run_status: raw?.run_status ?? null, steps };
}

// --- 3. dispatch_audit.jsonl (modèle/rôle signé HMAC, tous projets, filtré) --------------------

/**
 * @param {string} repoRoot
 * @param {string} project
 * @returns {{status:string, entries:object[], total_lines:number}}
 */
export function loadDispatchAudit(repoRoot, project) {
  const relPath = join('EVIDENCE', 'bundles', 'dispatch_audit.jsonl');
  const abs = join(repoRoot, relPath);
  const loaded = readJsonlTolerant(abs);
  if (loaded.status !== 'OK') return { status: loaded.status, path: relPath, entries: [], total_lines: 0 };
  const entries = loaded.lines
    .filter((l) => typeof l.run_id === 'string' && l.run_id.startsWith(project))
    .map((l) => ({
      etape: l.etape ?? null,
      model: l.model ?? null,
      capability_role: l.capability_role ?? null,
      provider: l.provider ?? null,
      run_id: l.run_id,
      ts: typeof l.ts === 'number' ? l.ts : null,
    }));
  return { status: 'OK', path: relPath, entries, total_lines: loaded.lines.length };
}

function groupByEtape(entries) {
  const map = new Map();
  for (const e of entries) {
    const key = e.etape ?? '(étape inconnue)';
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(e);
  }
  return map;
}

// --- 4. décisions du projet (pending_review_decisions.jsonl) -----------------------------------

/**
 * @param {string} repoRoot
 * @param {string} project
 * @returns {{status:string, decisions:object[]}}
 */
export function loadProjectDecisions(repoRoot, project) {
  const relPath = join('EVIDENCE', 'reports', 'pending_review_decisions.jsonl');
  const abs = join(repoRoot, relPath);
  const loaded = readJsonlTolerant(abs);
  if (loaded.status !== 'OK') return { status: loaded.status, path: relPath, decisions: [] };
  const decisions = loaded.lines.filter((l) => {
    const item = typeof l.item === 'string' ? l.item : '';
    const queue = typeof l.queue === 'string' ? l.queue : '';
    return item.includes(project) || queue.includes(project);
  });
  return { status: 'OK', path: relPath, decisions };
}

// --- 5. artifacts/*.txt (rapports d'agents auto-déclarés) ---------------------------------------

/**
 * @param {string} repoRoot
 * @param {string} project
 * @returns {{status:string, files:object[]}}
 */
export function loadArtifacts(repoRoot, project) {
  const relDir = join('EVIDENCE', 'runs', project, 'artifacts');
  const abs = join(repoRoot, relDir);
  if (!existsSync(abs)) return { status: 'ABSENT', dir: relDir, files: [] };
  let names;
  try {
    names = readdirSync(abs).filter((f) => f.endsWith('.txt')).sort();
  } catch (err) {
    return { status: 'UNREADABLE', dir: relDir, files: [], error: err.message };
  }
  const files = names.map((f) => ({ etape: f.slice(0, -'.txt'.length), filename: f, label: 'auto-déclaré' }));
  return { status: 'OK', dir: relDir, files };
}

// --- 6. context/ (manifests brique 1-2 si présents, checkpoints brique 4 futurs) ---------------

/**
 * Manifests de contexte (brique 1-2) : optionnels, purement une liste — le contenu détaillé
 * est déjà exploité par context_check.mjs, ici on ne fait que signaler leur EXISTENCE par
 * étape pour enrichir la chaîne « fourni ».
 * @param {string} repoRoot
 * @param {string} project
 */
export function loadContextManifestList(repoRoot, project) {
  const relDir = join('EVIDENCE', 'runs', project, 'context');
  const abs = join(repoRoot, relDir);
  if (!existsSync(abs)) return { status: 'ABSENT', dir: relDir, etapes: [] };
  let names;
  try {
    names = readdirSync(abs).filter((f) => f.endsWith('.manifest.jsonl'));
  } catch (err) {
    return { status: 'UNREADABLE', dir: relDir, etapes: [], error: err.message };
  }
  return { status: 'OK', dir: relDir, etapes: names.map((f) => f.slice(0, -'.manifest.jsonl'.length)).sort() };
}

/**
 * Checkpoints (Brique 4) — N'EXISTENT PAS ENCORE au moment de l'écriture de cet outil.
 * Branchement prévu, absence tolérée EN SILENCE (aucune note émise si absent : ce n'est
 * pas une dérive, la brique n'existe simplement pas encore).
 * @param {string} repoRoot
 * @param {string} project
 */
export function loadCheckpointList(repoRoot, project) {
  const relDir = join('EVIDENCE', 'runs', project, 'context');
  const abs = join(repoRoot, relDir);
  if (!existsSync(abs)) return { status: 'ABSENT', dir: relDir, etapes: [] };
  let names;
  try {
    names = readdirSync(abs).filter((f) => f.endsWith('.checkpoint.json'));
  } catch {
    return { status: 'ABSENT', dir: relDir, etapes: [] };
  }
  return { status: names.length > 0 ? 'OK' : 'ABSENT', dir: relDir, etapes: names.map((f) => f.slice(0, -'.checkpoint.json'.length)).sort() };
}

// --- résolution de chemin fichier + git log best-effort -----------------------------------------

/**
 * Un chemin de wiremap est le plus souvent relatif à GAMES/<projet>/ (ex. "logic/ship.mjs")
 * mais rien ne garantit qu'un projet futur ne stocke pas déjà un chemin repo-relatif complet.
 * On essaie les deux, dans cet ordre.
 * @param {string} repoRoot
 * @param {string} project
 * @param {string} fichier chemin tel qu'il apparaît dans la wiremap
 * @returns {{resolved:?string, exists:boolean, tried:string[]}}
 */
export function resolveGameFile(repoRoot, project, fichier) {
  const normalized = fichier.replace(/\\/g, '/');
  const candidates = [join('games', project, normalized), normalized];
  const tried = [];
  for (const rel of candidates) {
    tried.push(rel);
    if (existsSync(join(repoRoot, rel))) return { resolved: rel, exists: true, tried };
  }
  return { resolved: null, exists: false, tried };
}

/**
 * `git log --oneline -5 -- <chemin>` — best-effort, jamais fatal (repo pas git, chemin hors
 * historique, git absent du PATH...). null si indisponible, jamais une exception qui fuit.
 * @param {string} repoRoot
 * @param {string} relPath chemin repo-relatif (séparateurs '/')
 * @returns {?string[]}
 */
export function gitLogForFile(repoRoot, relPath) {
  try {
    const out = execFileSync('git', ['log', '--oneline', '-5', '--', relPath], { cwd: repoRoot, encoding: 'utf-8', timeout: 5000 });
    const lines = out.split(/\r?\n/).filter((l) => l.trim() !== '');
    return lines;
  } catch {
    return null;
  }
}

// --- recherche de feature / fichier --------------------------------------------------------------

/**
 * Résout une requête --feature contre la liste normalisée : essaie d'abord une égalité
 * exacte (nom de feature, puis nom de fonction), insensible à la casse, puis une recherche
 * par sous-chaîne en dernier recours. Retourne TOUTES les correspondances (jamais un choix
 * arbitraire caché) — le CLI/l'appelant décide quoi faire de plusieurs résultats.
 * @param {object[]} features
 * @param {string} query
 * @returns {{matches:object[], match_kind:string}}
 */
export function findFeaturesByQuery(features, query) {
  const q = query.trim().toLowerCase();
  const exactFeature = features.filter((f) => f.feature && f.feature.toLowerCase() === q);
  if (exactFeature.length > 0) return { matches: exactFeature, match_kind: 'exact_feature_name' };

  const exactFonction = features.filter((f) => f.fonction && f.fonction.toLowerCase() === q);
  if (exactFonction.length > 0) return { matches: exactFonction, match_kind: 'exact_fonction_name' };

  const substrFeature = features.filter((f) => f.feature && f.feature.toLowerCase().includes(q));
  if (substrFeature.length > 0) return { matches: substrFeature, match_kind: 'substring_feature_name' };

  const substrFonction = features.filter((f) => f.fonction && f.fonction.toLowerCase().includes(q));
  if (substrFonction.length > 0) return { matches: substrFonction, match_kind: 'substring_fonction_name' };

  return { matches: [], match_kind: 'none' };
}

/**
 * Résout une requête --file : normalise le chemin donné (retire un préfixe GAMES/<projet>/
 * s'il est présent, uniformise les séparateurs), puis compare à chaque `fichiers[]` de
 * chaque feature — égalité exacte d'abord, puis endsWith réciproque en tolérance de préfixe.
 * @param {object[]} features
 * @param {string} project
 * @param {string} query
 * @returns {{matches:object[], normalized_query:string, match_kind:string}}
 */
export function findFeaturesByFileQuery(features, project, query) {
  let normalized = query.trim().replace(/\\/g, '/');
  const gamePrefix = `GAMES/${project}/`;
  if (normalized.startsWith(gamePrefix)) normalized = normalized.slice(gamePrefix.length);

  const exact = features.filter((f) => f.fichiers.some((fi) => fi.replace(/\\/g, '/') === normalized));
  if (exact.length > 0) return { matches: exact, normalized_query: normalized, match_kind: 'exact' };

  const loose = features.filter((f) => f.fichiers.some((fi) => {
    const n = fi.replace(/\\/g, '/');
    return n.endsWith(normalized) || normalized.endsWith(n);
  }));
  if (loose.length > 0) return { matches: loose, normalized_query: normalized, match_kind: 'loose_suffix' };

  return { matches: [], normalized_query: normalized, match_kind: 'none' };
}

// --- assemblage de la chaîne complète pour UNE feature -------------------------------------------

/**
 * Assemble la chaîne complète (fichiers/git · runs/étapes · modèle/rôle · décisions ·
 * rapports d'agents) pour une feature déjà résolue. Ne relit rien depuis disque que les
 * fichiers/git — les autres sources sont passées en contexte (déjà chargées une fois par
 * l'appelant, pour ne pas relire dispatch_audit/decisions/state par feature).
 * @param {string} repoRoot
 * @param {string} project
 * @param {object} feature entrée normalisée de la wiremap
 * @param {{stateSteps:object, dispatchByEtape:Map, decisions:object[], artifacts:object[]}} ctx
 */
export function buildFeatureChain(repoRoot, project, feature, ctx) {
  const files = feature.fichiers.map((fi) => {
    const resolution = resolveGameFile(repoRoot, project, fi);
    const gitLog = resolution.exists ? gitLogForFile(repoRoot, resolution.resolved) : null;
    return { declared_path: fi, resolved: resolution, git_log: gitLog };
  });

  // runs/étapes : union des étapes vues dans state.json (si présent) et dispatch_audit —
  // granularité RUN, pas fichier (voir GRANULARITY_NOTE). On ne prétend PAS qu'une étape a
  // touché CE fichier précis ; on liste les étapes du run qui a produit cette wiremap.
  const etapeNames = new Set([
    ...ctx.stateSteps.steps.map((s) => s.etape),
    ...ctx.dispatchByEtape.keys(),
  ]);
  const artifactByEtape = new Map(ctx.artifacts.map((a) => [a.etape, a]));
  const run_steps = [...etapeNames].map((etape) => {
    const stateStep = ctx.stateSteps.steps.find((s) => s.etape === etape) || null;
    const dispatchEntries = ctx.dispatchByEtape.get(etape) || [];
    return {
      etape,
      status: stateStep?.status ?? null,
      attempts: stateStep?.attempts ?? null,
      ts: stateStep?.ts ?? (dispatchEntries[0]?.ts ?? null),
      models_roles: dispatchEntries.map((d) => ({ model: d.model, capability_role: d.capability_role, provider: d.provider, ts: d.ts })),
      artifact: artifactByEtape.get(etape) || null,
    };
  }).sort((a, b) => (a.ts ?? 0) - (b.ts ?? 0));

  return {
    feature: feature.feature,
    fonction: feature.fonction,
    section: feature.section,
    version: feature.version,
    statut: feature.statut,
    preuve: feature.preuve,
    files,
    run_steps,
    decisions: ctx.decisions,
    granularity_note: GRANULARITY_NOTE,
    claim_verdict: 'NO_CLAIM_ALLOWED',
  };
}

// --- vue d'ensemble --------------------------------------------------------------------------

/**
 * @param {string} repoRoot
 * @param {string} project
 */
export function buildOverview(repoRoot, project) {
  const wiremap = loadWiremap(repoRoot, project);
  const frozen = loadWiremapFrozen(repoRoot, project);
  const drift = computeFrozenDrift(wiremap.features, frozen);
  const stateSteps = loadStateSteps(repoRoot, project);
  const dispatchAudit = loadDispatchAudit(repoRoot, project);
  const decisions = loadProjectDecisions(repoRoot, project);
  const artifacts = loadArtifacts(repoRoot, project);
  const contextManifests = loadContextManifestList(repoRoot, project);

  const allFiles = new Set();
  for (const f of wiremap.features) for (const fi of f.fichiers) allFiles.add(fi);

  const orchestration_note = stateSteps.status === 'ABSENT'
    ? 'orchestration prose — traçabilité réduite (pas de state.json pour ce projet ; dispatch_audit.jsonl reste la seule source modèle/rôle par étape).'
    : `state.json présent (run_id=${stateSteps.run_id ?? 'n/a'}, run_status=${stateSteps.run_status ?? 'n/a'}).`;

  return {
    project,
    wiremap: { status: wiremap.status, path: wiremap.path, feature_count: wiremap.features.length, unique_file_count: allFiles.size },
    wiremap_frozen: { status: frozen.status, drift },
    state: { status: stateSteps.status, run_id: stateSteps.run_id, run_status: stateSteps.run_status, step_count: stateSteps.steps.length },
    dispatch_audit: { status: dispatchAudit.status, matched_entries: dispatchAudit.entries.length },
    decisions: { status: decisions.status, count: decisions.decisions.length },
    artifacts: { status: artifacts.status, count: artifacts.files.length },
    context_manifests: { status: contextManifests.status, etape_count: contextManifests.etapes.length },
    features: wiremap.features.map((f) => ({ feature: f.feature, fonction: f.fonction, statut: f.statut, fichiers_count: f.fichiers.length })),
    orchestration_note,
    granularity_note: GRANULARITY_NOTE,
    claim_verdict: 'NO_CLAIM_ALLOWED',
  };
}

// --- assemblage haut niveau pour le CLI (charge tout une fois, dispatch feature/file/overview) --

function loadAllSources(repoRoot, project) {
  const wiremap = loadWiremap(repoRoot, project);
  const frozen = loadWiremapFrozen(repoRoot, project);
  const stateSteps = loadStateSteps(repoRoot, project);
  const dispatchAudit = loadDispatchAudit(repoRoot, project);
  const decisions = loadProjectDecisions(repoRoot, project);
  const artifacts = loadArtifacts(repoRoot, project);
  return {
    wiremap, frozen, stateSteps, dispatchAudit, decisions, artifacts,
    dispatchByEtape: groupByEtape(dispatchAudit.entries),
  };
}

export function runFeatureQuery(repoRoot, project, query) {
  const src = loadAllSources(repoRoot, project);
  if (src.wiremap.status !== 'OK') {
    return { project, query_type: 'feature', query, wiremap_status: src.wiremap.status, matches: [], granularity_note: GRANULARITY_NOTE, claim_verdict: 'NO_CLAIM_ALLOWED' };
  }
  const { matches, match_kind } = findFeaturesByQuery(src.wiremap.features, query);
  const drift = computeFrozenDrift(src.wiremap.features, src.frozen);
  const chains = matches.map((f) => buildFeatureChain(repoRoot, project, f, {
    stateSteps: src.stateSteps, dispatchByEtape: src.dispatchByEtape,
    decisions: src.decisions.decisions, artifacts: src.artifacts.files,
  }));
  return {
    project, query_type: 'feature', query, match_kind,
    match_count: chains.length,
    chains,
    frozen_drift: drift,
    orchestration_note: src.stateSteps.status === 'ABSENT'
      ? 'orchestration prose — traçabilité réduite (pas de state.json pour ce projet ; dispatch_audit.jsonl reste la seule source modèle/rôle par étape).'
      : null,
    granularity_note: GRANULARITY_NOTE,
    claim_verdict: 'NO_CLAIM_ALLOWED',
  };
}

export function runFileQuery(repoRoot, project, query) {
  const src = loadAllSources(repoRoot, project);
  if (src.wiremap.status !== 'OK') {
    return { project, query_type: 'file', query, wiremap_status: src.wiremap.status, matches: [], granularity_note: GRANULARITY_NOTE, claim_verdict: 'NO_CLAIM_ALLOWED' };
  }
  const { matches, normalized_query, match_kind } = findFeaturesByFileQuery(src.wiremap.features, project, query);
  const drift = computeFrozenDrift(src.wiremap.features, src.frozen);
  const chains = matches.map((f) => buildFeatureChain(repoRoot, project, f, {
    stateSteps: src.stateSteps, dispatchByEtape: src.dispatchByEtape,
    decisions: src.decisions.decisions, artifacts: src.artifacts.files,
  }));
  return {
    project, query_type: 'file', query, normalized_query, match_kind,
    match_count: chains.length,
    chains,
    frozen_drift: drift,
    orchestration_note: src.stateSteps.status === 'ABSENT'
      ? 'orchestration prose — traçabilité réduite (pas de state.json pour ce projet ; dispatch_audit.jsonl reste la seule source modèle/rôle par étape).'
      : null,
    granularity_note: GRANULARITY_NOTE,
    claim_verdict: 'NO_CLAIM_ALLOWED',
  };
}

// --- CLI ---------------------------------------------------------------------------------------

function formatChain(chain) {
  const lines = [];
  lines.push(`  feature      : ${chain.feature}`);
  if (chain.fonction) lines.push(`  fonction     : ${chain.fonction}`);
  if (chain.section) lines.push(`  section      : ${chain.section}`);
  lines.push(`  statut       : ${chain.statut ?? 'n/a'} (version=${chain.version ?? 'n/a'})`);
  if (chain.preuve) lines.push(`  preuve/test  : ${chain.preuve}`);
  lines.push('  fichiers     :');
  for (const f of chain.files) {
    const status = f.resolved.exists ? `résolu -> ${f.resolved.resolved}` : `INTROUVABLE (essayé : ${f.resolved.tried.join(', ')})`;
    lines.push(`    - ${f.declared_path}  [${status}]`);
    if (f.git_log && f.git_log.length) {
      for (const l of f.git_log) lines.push(`        git: ${l}`);
    } else if (f.resolved.exists) {
      lines.push('        git: (aucun historique trouvé ou git indisponible)');
    }
  }
  lines.push('  runs/étapes du projet (granularité run+étape, pas fichier) :');
  if (chain.run_steps.length === 0) lines.push('    (aucune étape trouvée dans state.json ni dispatch_audit.jsonl pour ce projet)');
  for (const s of chain.run_steps) {
    // Affichage humain : dédoublonné avec compteur (×N). Le JSON garde la liste
    // brute complète (models_roles) — seule la vue lisible est compactée.
    let mr = '(aucune entrée dispatch_audit)';
    if (s.models_roles.length) {
      const counts = new Map();
      for (const m of s.models_roles) {
        const key = `${m.capability_role ?? '?'}/${m.model ?? '?'}`;
        counts.set(key, (counts.get(key) ?? 0) + 1);
      }
      mr = [...counts.entries()].map(([k, n]) => (n > 1 ? `${k} ×${n}` : k)).join(', ');
    }
    lines.push(`    - ${s.etape}  status=${s.status ?? 'n/a'} attempts=${s.attempts ?? 'n/a'}  modèle/rôle: ${mr}`);
    if (s.artifact) lines.push(`        rapport auto-déclaré : ${s.artifact.filename} (${s.artifact.label})`);
  }
  lines.push(`  décisions HumanGate du projet : ${chain.decisions.length}`);
  for (const d of chain.decisions.slice(0, 10)) {
    lines.push(`    - ${d.ts ?? 'n/a'} ${d.queue ?? ''} ${d.item ?? ''} -> ${d.decision ?? 'n/a'} (${d.motif ?? ''})`);
  }
  return lines.join('\n');
}

function main() {
  const here = dirname(fileURLToPath(import.meta.url));
  const args = process.argv.slice(2);
  const positional = [];
  let featureQuery = null;
  let fileQuery = null;
  let asJson = false;
  for (let i = 0; i < args.length; i += 1) {
    if (args[i] === '--feature') {
      featureQuery = args[i + 1] ?? null;
      i += 1;
    } else if (args[i] === '--file') {
      fileQuery = args[i + 1] ?? null;
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
    console.error('Usage: node forge/wiremap_nav.mjs <projet> [--feature <id-ou-nom>] [--file <chemin>] [--json]');
    console.error('Lecture seule, advisory — exit 0 même sans argument valide (jamais de gate).');
    process.exit(0);
  }

  let result;
  try {
    if (featureQuery) {
      result = runFeatureQuery(repoRoot, project, featureQuery);
    } else if (fileQuery) {
      result = runFileQuery(repoRoot, project, fileQuery);
    } else {
      result = buildOverview(repoRoot, project);
    }
  } catch (err) {
    console.error(`[wiremap_nav] ERREUR INTERNE (non bloquante) : ${err.message}`);
    console.log(JSON.stringify({ project, internal_error: err.message, claim_verdict: 'NO_CLAIM_ALLOWED' }, null, 2));
    process.exit(0);
    return;
  }

  console.error(`=== wiremap_nav — ${project} (lecture seule, jamais de gate) ===`);
  if (featureQuery || fileQuery) {
    console.error(`requête ${featureQuery ? '--feature' : '--file'} = "${featureQuery || fileQuery}"  (match_kind=${result.match_kind}, ${result.match_count} résultat(s))`);
    if (result.wiremap_status && result.wiremap_status !== 'OK') {
      console.error(`  wiremap.json : ${result.wiremap_status} — aucune navigation possible pour ce projet.`);
    } else if (result.match_count === 0) {
      console.error('  aucune feature/fichier correspondant trouvé dans la wiremap.');
    } else {
      for (const c of result.chains) {
        console.error('---');
        console.error(formatChain(c));
      }
    }
    if (result.frozen_drift && result.frozen_drift.checked && result.frozen_drift.divergent) {
      console.error(`  ⚠ dérive gel détecté : +${result.frozen_drift.added_since_freeze.length} depuis le gel, -${result.frozen_drift.missing_since_freeze.length} disparues du gel`);
    }
    if (result.orchestration_note) console.error(`  ${result.orchestration_note}`);
  } else {
    console.error(`wiremap: ${result.wiremap.status} (${result.wiremap.feature_count} features, ${result.wiremap.unique_file_count} fichiers uniques)`);
    console.error(`wiremap_frozen: ${result.wiremap_frozen.status}${result.wiremap_frozen.drift.checked && result.wiremap_frozen.drift.divergent ? ' — DIVERGENTE (voir JSON)' : ''}`);
    console.error(`state.json: ${result.state.status} (${result.state.step_count} étapes)`);
    console.error(`dispatch_audit: ${result.dispatch_audit.status} (${result.dispatch_audit.matched_entries} entrées pour ce projet)`);
    console.error(`décisions HumanGate: ${result.decisions.count}`);
    console.error(`artifacts auto-déclarés: ${result.artifacts.count}`);
    console.error(`${result.orchestration_note}`);
    console.error('features :');
    for (const f of result.features) console.error(`  - ${f.feature}  (${f.fichiers_count} fichier(s), statut=${f.statut ?? 'n/a'})`);
  }
  console.error(`\n${GRANULARITY_NOTE}`);
  console.error('claim_verdict: NO_CLAIM_ALLOWED — navigation historique, aucun jugement.');

  if (asJson) console.log(JSON.stringify(result, null, 2));
  process.exit(0);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
