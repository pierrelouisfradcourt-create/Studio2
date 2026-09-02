#!/usr/bin/env node
// knowledge_trace.mjs — Knowledge Resolver V1, pièce 1/2 (contrat :
// docs/forge/KNOWLEDGE_RESOLVER_V1_PROTOCOL.md, statut PROPOSED en attente gate Pierre).
//
// Rôle : aide + validateur de TRACE DE LECTURE. Ce n'est PAS un nouveau magasin de savoir —
// c'est du lineage : quels items des 3 canaux existants (pré-mortem, knowledge_base,
// mandatory_read/packet) ont été servis à un run, avec provenance et date de validité.
//
// Deux modes :
//   ÉCRIRE  — valide un schéma strict AVANT toute écriture (champ manquant/enum invalide =
//             refus, RIEN n'est écrit) puis dépose EVIDENCE/runs/<run>/knowledge_trace.json.
//             C'est le SEUL chemin d'écriture runtime de toute la V1 (§ protocole, invariant
//             ADR-002 : zone evidence, sur commande explicite). Un garde-fou refuse d'écrire
//             en dehors de EVIDENCE/runs/ même si on le lui demande.
//   VÉRIFIER — la sonde ANTI-THÉÂTRE (protocole §5, la plus importante) : pour chaque item de
//             la trace, cherche une preuve de consommation réelle dans les fichiers du run
//             (artifacts/, evidence/, et tout fichier à la racine du run — state.json,
//             verdict.json, charter.yaml, etc.). `ref` doit apparaître textuellement quelque
//             part. Un item tracé mais introuvable = FAUX POSITIF de trace = échec visible
//             (exit 1), jamais un vert par défaut.
//
// Usage :
//   node forge/knowledge_trace.mjs write <run_dir> <items.json> [--repo-root <path>]
//   node forge/knowledge_trace.mjs --verify <run_dir> [--repo-root <path>]
//
//   <items.json> : soit un tableau d'items, soit {run_id?, items:[...]}. Schéma par item :
//     { source: "premortem"|"knowledge_base"|"mandatory_read"|"packet",
//       ref: "<id ou chemin>", provenance: "VERIFIED"|"HUMAN_RATIFIED"|"ADVISORY"|"DERIVED"|"DOCTRINE",
//       valid_as_of: "<date ISO>", reason: "<motif court>" }
//
// Exit codes (documentés, jamais un 0 par défaut) :
//   write  : 0 = écrit · 1 = schéma invalide, rien écrit · 2 = erreur interne (run_dir hors
//            zone autorisée, items.json illisible/corrompu, run_dir introuvable)
//   verify : 0 = trace présente, tous les items FOUND · 1 = au moins un NOT_FOUND (théâtre) ·
//            3 = trace absente (distinct de FAIL) · 2 = erreur interne (JSON de trace corrompu)
//
// Déterministe, non-LLM, zéro réseau. Usage également programmatique : les fonctions
// exportées (writeTrace, verifyTrace, validateTraceItems) peuvent être importées directement
// par l'orchestrateur plutôt que de passer par un fichier items.json temporaire sur disque.
import { existsSync, readFileSync, writeFileSync, statSync, readdirSync } from 'node:fs';
import { join, resolve, relative, dirname, basename, isAbsolute } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const ALLOWED_SOURCES = ['premortem', 'knowledge_base', 'mandatory_read', 'packet'];
export const ALLOWED_PROVENANCE = ['VERIFIED', 'HUMAN_RATIFIED', 'ADVISORY', 'DERIVED', 'DOCTRINE'];
export const SCHEMA_VERSION = 1;
const TRACE_FILENAME = 'knowledge_trace.json';
const RUNS_ROOT_REL = join('EVIDENCE', 'runs');

// Limites assumées — imprimées dans le rapport, dans l'esprit des autres capteurs Forge.
export const OUT_OF_SCOPE = [
  "la vérification anti-théâtre est une recherche TEXTUELLE (sous-chaîne), pas sémantique : "
    + "un `ref` reformulé ou paraphrasé dans les artefacts sans être cité littéralement sera "
    + "signalé NOT_FOUND à tort. C'est un faux négatif assumé, pas un faux positif — le capteur "
    + "reste du côté strict (mieux vaut sur-signaler que sous-signaler le théâtre).",
  "seuls les fichiers texte lisibles en UTF-8 sous <run_dir> sont scannés ; un artefact binaire "
    + "(image, etc.) est silencieusement ignoré du corpus de preuve et listé dans `skipped_files`.",
  "le fichier knowledge_trace.json lui-même est exclu du corpus de preuve — se citer soi-même "
    + "ne constitue pas une consommation.",
  "RISQUE CONNU (constaté en démo) : seul knowledge_trace.json est exclu du corpus. Si "
    + "l'appelant dépose le fichier items.json (source de l'écriture) À L'INTÉRIEUR de "
    + "<run_dir>, la vérification le trouvera dans ce fichier et déclarera FOUND alors qu'aucun "
    + "artefact du run n'a réellement consommé la référence — auto-confirmation, pas une preuve. "
    + "Le corpus scanné inclut TOUT fichier sous <run_dir> à l'exécution ; il ne devine pas quels "
    + "fichiers sont des « vrais » artefacts de run. Recommandation à l'appelant : garder "
    + "items.json HORS de <run_dir> (ex. répertoire temporaire), ce que l'usage CLI documenté ne "
    + "force pas mais permet nativement — voir `corpus_files_scanned` / le détail `found_in` du "
    + "rapport pour repérer ce cas si un fichier d'entrée traîne malgré tout dans le run.",
];

/**
 * Valide un tableau d'items de trace contre le schéma strict.
 * @param {unknown} items
 * @returns {{ok:boolean, errors:string[]}}
 */
export function validateTraceItems(items) {
  const errors = [];
  if (!Array.isArray(items)) {
    return { ok: false, errors: ['items doit être un tableau'] };
  }
  items.forEach((item, i) => {
    if (item === null || typeof item !== 'object' || Array.isArray(item)) {
      errors.push(`item[${i}] : doit être un objet`);
      return;
    }
    if (!ALLOWED_SOURCES.includes(item.source)) {
      errors.push(`item[${i}].source invalide (${JSON.stringify(item.source)}) — attendu l'un de : ${ALLOWED_SOURCES.join(', ')}`);
    }
    if (typeof item.ref !== 'string' || item.ref.trim() === '') {
      errors.push(`item[${i}].ref manquant ou vide`);
    }
    if (!ALLOWED_PROVENANCE.includes(item.provenance)) {
      errors.push(`item[${i}].provenance invalide (${JSON.stringify(item.provenance)}) — attendu l'un de : ${ALLOWED_PROVENANCE.join(', ')}`);
    }
    if (typeof item.valid_as_of !== 'string' || item.valid_as_of.trim() === '' || Number.isNaN(Date.parse(item.valid_as_of))) {
      errors.push(`item[${i}].valid_as_of manquant ou n'est pas une date ISO valide`);
    }
    if (typeof item.reason !== 'string' || item.reason.trim() === '') {
      errors.push(`item[${i}].reason manquant ou vide`);
    }
  });
  return { ok: errors.length === 0, errors };
}

/**
 * Résout run_dir (relatif ou absolu) sous repoRoot et vérifie qu'il reste dans EVIDENCE/runs/.
 * @param {string} repoRoot
 * @param {string} runDirArg
 * @returns {{absRunDir:string, inScope:boolean}}
 */
function resolveRunDir(repoRoot, runDirArg) {
  const absRunDir = resolve(repoRoot, runDirArg);
  const runsRoot = join(repoRoot, RUNS_ROOT_REL);
  const rel = relative(runsRoot, absRunDir);
  const inScope = rel !== '' && !rel.startsWith('..') && !isAbsolute(rel);
  return { absRunDir, inScope };
}

/**
 * Mode ÉCRIRE. Valide puis, seulement si valide, écrit knowledge_trace.json.
 * @param {string} repoRoot
 * @param {string} runDirArg chemin du run (relatif ou absolu), doit être sous EVIDENCE/runs/
 * @param {unknown[]} items
 * @param {{runId?:string}} [opts]
 * @returns {{written:boolean, path:string|null, errors:string[]}}
 */
export function writeTrace(repoRoot, runDirArg, items, opts = {}) {
  const { absRunDir, inScope } = resolveRunDir(repoRoot, runDirArg);
  if (!inScope) {
    return { written: false, path: null, errors: [`run_dir hors zone autorisée : "${runDirArg}" ne résout pas sous ${RUNS_ROOT_REL}${'/'}<run> — écriture refusée`] };
  }
  if (!existsSync(absRunDir) || !statSync(absRunDir).isDirectory()) {
    return { written: false, path: null, errors: [`run_dir introuvable ou n'est pas un dossier : ${absRunDir}`] };
  }
  const { ok, errors } = validateTraceItems(items);
  const targetPath = join(absRunDir, TRACE_FILENAME);
  if (!ok) {
    return { written: false, path: targetPath, errors };
  }
  const runId = opts.runId || basename(absRunDir);
  const trace = {
    run_id: runId,
    created: new Date().toISOString(),
    schema_version: SCHEMA_VERSION,
    items,
  };
  writeFileSync(targetPath, JSON.stringify(trace, null, 2) + '\n', 'utf-8');
  return { written: true, path: targetPath, errors: [] };
}

/**
 * Liste récursive de tous les fichiers réguliers sous root (hors le fichier exclu).
 * @param {string} root
 * @param {string} excludeAbsPath
 * @returns {string[]} chemins absolus
 */
function listFilesRecursive(root, excludeAbsPath) {
  const out = [];
  const stack = [root];
  while (stack.length) {
    const dir = stack.pop();
    let entries;
    try {
      entries = readdirSync(dir, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const e of entries) {
      const p = join(dir, e.name);
      if (e.isDirectory()) {
        stack.push(p);
      } else if (e.isFile() && p !== excludeAbsPath) {
        out.push(p);
      }
    }
  }
  return out;
}

/**
 * Mode VÉRIFIER — sonde anti-théâtre : chaque `ref` doit apparaître dans un artefact du run.
 * @param {string} repoRoot
 * @param {string} runDirArg
 * @returns {{status:string, ok:boolean, run_id?:string, items:Array<object>, corpus_files_scanned?:number, skipped_files?:string[], errors?:string[]}}
 */
export function verifyTrace(repoRoot, runDirArg) {
  const { absRunDir } = resolveRunDir(repoRoot, runDirArg);
  const tracePath = join(absRunDir, TRACE_FILENAME);
  if (!existsSync(absRunDir) || !statSync(absRunDir).isDirectory()) {
    return { status: 'RUN_DIR_ABSENT', ok: false, items: [], errors: [`run_dir introuvable : ${absRunDir}`] };
  }
  if (!existsSync(tracePath)) {
    return { status: 'TRACE_ABSENT', ok: false, items: [] };
  }
  let trace;
  try {
    trace = JSON.parse(readFileSync(tracePath, 'utf-8'));
  } catch (err) {
    return { status: 'TRACE_CORRUPT', ok: false, items: [], errors: [`knowledge_trace.json illisible : ${err.message}`] };
  }
  if (!trace || !Array.isArray(trace.items)) {
    return { status: 'TRACE_CORRUPT', ok: false, items: [], errors: ['knowledge_trace.json : champ "items" absent ou non-tableau'] };
  }

  const files = listFilesRecursive(absRunDir, tracePath);
  const corpus = [];
  const skipped = [];
  for (const f of files) {
    try {
      corpus.push({ path: f, text: readFileSync(f, 'utf-8') });
    } catch {
      skipped.push(relative(repoRoot, f));
    }
  }

  const results = trace.items.map((item) => {
    const needles = [item.ref, String(item.ref || '').replace(/\\/g, '/'), String(item.ref || '').replace(/\//g, '\\')];
    const matches = [];
    for (const c of corpus) {
      if (needles.some((n) => n && c.text.includes(n))) {
        matches.push(relative(repoRoot, c.path));
      }
    }
    return {
      source: item.source,
      ref: item.ref,
      provenance: item.provenance,
      status: matches.length > 0 ? 'FOUND' : 'NOT_FOUND',
      found_in: matches.slice(0, 5),
    };
  });

  const ok = results.every((r) => r.status === 'FOUND');
  return {
    status: 'VERIFIED',
    ok,
    run_id: trace.run_id,
    items: results,
    corpus_files_scanned: corpus.length,
    skipped_files: skipped,
  };
}

function readJsonFile(p) {
  return JSON.parse(readFileSync(p, 'utf-8'));
}

function main() {
  const here = dirname(fileURLToPath(import.meta.url));
  const args = process.argv.slice(2);
  const repoRootFlagIdx = args.indexOf('--repo-root');
  const repoRoot = repoRootFlagIdx !== -1 ? resolve(args[repoRootFlagIdx + 1]) : resolve(here, '..');
  const positional = args.filter((a, i) => !a.startsWith('--') && args[i - 1] !== '--repo-root');

  const verifyFlagIdx = args.indexOf('--verify');
  if (verifyFlagIdx !== -1) {
    const runDirArg = args[verifyFlagIdx + 1];
    if (!runDirArg) {
      console.error('[knowledge_trace] --verify requiert <run_dir>');
      process.exit(2);
    }
    const r = verifyTrace(repoRoot, runDirArg);
    console.error(`=== knowledge_trace --verify — ${runDirArg} ===`);
    console.error(`statut : ${r.status}`);
    if (r.status === 'TRACE_ABSENT') {
      console.error('aucune trace à vérifier (knowledge_trace.json absent).');
      console.log(JSON.stringify(r, null, 2));
      process.exit(3);
    }
    if (r.status === 'RUN_DIR_ABSENT' || r.status === 'TRACE_CORRUPT') {
      for (const e of r.errors || []) console.error(`  ERREUR : ${e}`);
      console.log(JSON.stringify(r, null, 2));
      process.exit(2);
    }
    console.error(`corpus scanné : ${r.corpus_files_scanned} fichier(s)${r.skipped_files.length ? ` (${r.skipped_files.length} ignoré(s), non-UTF8)` : ''}`);
    for (const it of r.items) {
      const mark = it.status === 'FOUND' ? '✅' : '⚠';
      console.error(`  ${mark} [${it.source}] ${it.ref} — ${it.status}${it.found_in.length ? ` (${it.found_in.join(', ')})` : ''}`);
    }
    console.error(`\nVERDICT : ${r.ok ? 'FOUND partout — trace corroborée' : 'ANTI-THÉÂTRE : au moins un item NOT_FOUND'}`);
    console.log(JSON.stringify(r, null, 2));
    process.exit(r.ok ? 0 : 1);
  }

  if (positional[0] === 'write') {
    const runDirArg = positional[1];
    const itemsPath = positional[2];
    if (!runDirArg || !itemsPath) {
      console.error('[knowledge_trace] usage : write <run_dir> <items.json>');
      process.exit(2);
    }
    let raw;
    try {
      raw = readJsonFile(resolve(itemsPath));
    } catch (err) {
      console.error(`[knowledge_trace] items.json illisible/corrompu : ${err.message}`);
      process.exit(2);
    }
    const items = Array.isArray(raw) ? raw : raw.items;
    const runId = Array.isArray(raw) ? undefined : raw.run_id;
    if (!Array.isArray(items)) {
      console.error('[knowledge_trace] items.json doit être un tableau ou {run_id?, items:[...]}');
      process.exit(2);
    }
    const r = writeTrace(repoRoot, runDirArg, items, { runId });
    if (!r.written) {
      console.error('[knowledge_trace] ÉCRITURE REFUSÉE :');
      for (const e of r.errors) console.error(`  - ${e}`);
      console.log(JSON.stringify(r, null, 2));
      process.exit(r.path === null ? 2 : 1);
    }
    console.error(`[knowledge_trace] écrit → ${r.path}`);
    console.log(JSON.stringify(r, null, 2));
    process.exit(0);
  }

  console.error('Usage :');
  console.error('  node forge/knowledge_trace.mjs write <run_dir> <items.json> [--repo-root <path>]');
  console.error('  node forge/knowledge_trace.mjs --verify <run_dir> [--repo-root <path>]');
  process.exit(2);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
