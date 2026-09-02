#!/usr/bin/env node
// fill_usage_examples.mjs — R8 (Forge V2 §4-A, docs/audit/FORGE_V2_CONSOLIDATION.md) :
// `usage_examples` rempli AUTOMATIQUEMENT à l'import détecté (0/30 aujourd'hui, catalog.json).
// Déterministe, non-LLM, zéro réseau, idempotent. Ne juge rien — constate des imports réels,
// exactement comme scripts/forge/reuse_ratio.mjs (MÊME détection : imports ES `from "..."`
// référençant knowledge_base/, fichiers de logique produit seulement — harnais et tests
// exclus). reuse_ratio.mjs scanne UN dossier de jeu à la fois (non récursif) ; ce script
// scanne TOUT games/** récursivement, car une brique peut être importée depuis un
// sous-dossier (ex. games/shmup_slice/logic/collisions.mjs).
//
// N'ÉCRIT QUE le champ `usage_examples` de catalog.json (append factuel : le chemin
// repo-relatif du fichier importateur), jamais aucun autre champ, jamais un ordre d'entrées
// différent, jamais un changement d'indentation (préserve le format EXACT du fichier — JSON à
// indentation 1 espace + retour à la ligne final, vérifié à l'identique quand rien ne change).
//
// GAP DE SCHÉMA DÉCOUVERT EN CONSTRUISANT CE SCRIPT, PUIS DÉBLOQUÉ (arbitrage Pierre, relayé
// par l'orchestrateur) : kb-validate.mjs avait DEUX schémas de champs fermés distincts —
// `usage_examples` n'existait que sur ASSET_SPEC ; BRICK_SPEC (kind: system/pattern/template)
// ne l'avait pas (son équivalent de preuve d'usage était `proof_of_use`, un chemin unique).
// Les 2 imports réels connus de ce dépôt (games/kb_tactics/{game,level}.mjs,
// games/shmup_slice/logic/collisions.mjs → sys-damage-floor, sys-reachability) tombaient TOUS
// les deux sur des entrées `brick` — 0 entrée `asset` n'était importée nulle part dans
// games/**. kb-validate.mjs a depuis reçu l'extension ratifiée (BRICK_SPEC::usage_examples,
// FACULTATIF, même forme qu'ASSET_SPEC — cf. commentaire au site de déclaration) : ce script
// peut donc désormais écrire sur les entrées `asset` ET `brick`.
// Reste un gap ASSUMÉ, hors décision : le spec `role` n'a PAS été étendu (hors périmètre de
// l'arbitrage — "ne touche ni au spec role"). Un import qui résoudrait vers une entrée `role`
// (aucun cas réel aujourd'hui) est donc encore rapporté en `schemaGap`, jamais écrit.
//
// Usage : node fill_usage_examples.mjs
// Sortie : reçu JSON sur stdout (détection + application) + résumé lisible sur stderr.
// Exit 0 toujours (mesure + application factuelle, pas un oracle pass/fail — même convention
// que reuse_ratio.mjs).
import { readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { join, dirname, relative, resolve, extname, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = fileURLToPath(new URL('.', import.meta.url)); // .../knowledge_base/
const REPO_ROOT = resolve(HERE, '..');
const GAMES_DIR = join(REPO_ROOT, 'games');
const CATALOG_PATH = join(REPO_ROOT, 'knowledge_base', 'catalog.json');

// Miroir EXACT de scripts/forge/reuse_ratio.mjs (même périmètre "logique produit").
const HARNESS_FILES = new Set(['main.mjs', 'server.mjs', 'e2e.mjs', 'run-oracle.mjs', 'solvability.mjs']);
// Dossiers jamais traversés : vendored/build/vcs — reuse_ratio.mjs n'a pas ce problème (il ne
// scanne qu'un seul dossier plat) ; ce script marche récursivement sur tout games/**, où
// games/leviathan/node_modules existe réellement (constaté sur ce dépôt).
const SKIP_DIRS = new Set(['node_modules', '.git', 'dist', 'build', '.vite', 'coverage']);

function isLogicFile(fileName) {
  if (extname(fileName) !== '.mjs') return false;
  if (fileName.endsWith('.test.mjs')) return false;
  if (HARNESS_FILES.has(fileName)) return false;
  return true;
}

function toPosix(p) {
  return p.split(sep).join('/');
}

/** Parcourt récursivement `dir`, retourne les chemins ABSOLUS de tout fichier de logique produit. */
function walkLogicFiles(dir) {
  const out = [];
  let entries;
  try {
    entries = readdirSync(dir, { withFileTypes: true });
  } catch {
    return out; // dossier absent/illisible : silencieux, rien à scanner
  }
  for (const entry of entries) {
    if (entry.isDirectory()) {
      if (SKIP_DIRS.has(entry.name)) continue;
      out.push(...walkLogicFiles(join(dir, entry.name)));
    } else if (entry.isFile() && isLogicFile(entry.name)) {
      out.push(join(dir, entry.name));
    }
  }
  return out;
}

/** Extrait les specifiers d'import ES d'un fichier (texte brut — même limite déclarée que
 * reuse_ratio.mjs et kb-validate.mjs R10 : suffisant pour ce besoin, pas un compilateur). */
function extractImportSpecifiers(source) {
  const specs = [];
  const re = /\bfrom\s+["']([^"']+)["']/g;
  let m;
  while ((m = re.exec(source)) !== null) specs.push(m[1]);
  return specs;
}

/**
 * Détecte, dans TOUT `gamesDir` (récursif), les imports RÉELS de knowledge_base/ (même méthode
 * que reuse_ratio.mjs : imports ES `from "..."`, fichiers de logique produit seulement).
 * @param {string} [gamesDir]
 * @param {string} [repoRoot]
 * @returns {Array<{importer: string, kbPath: string}>} importer/kbPath = chemins repo-relatifs
 *   POSIX (portables) — importer = le fichier qui importe, kbPath = la cible knowledge_base/
 *   résolue (relative à l'importateur, donc valide même en cas de profondeur variable).
 */
export function detectKnowledgeBaseImports(gamesDir = GAMES_DIR, repoRoot = REPO_ROOT) {
  const found = [];
  for (const abs of walkLogicFiles(gamesDir)) {
    let source;
    try {
      source = readFileSync(abs, 'utf-8');
    } catch {
      continue;
    }
    for (const specifier of extractImportSpecifiers(source)) {
      if (!specifier.includes('knowledge_base/')) continue;
      const resolvedAbs = resolve(dirname(abs), specifier);
      found.push({
        importer: toPosix(relative(repoRoot, abs)),
        kbPath: toPosix(relative(repoRoot, resolvedAbs))
      });
    }
  }
  // Tri déterministe (parcours de dossier non garanti stable entre OS/versions Node).
  found.sort((a, b) => (a.importer + '|' + a.kbPath).localeCompare(b.importer + '|' + b.kbPath));
  return found;
}

// Types d'entrée dont le schéma catalog (kb-validate.mjs) déclare/accepte `usage_examples` :
// `asset` (ASSET_SPEC, historique) et `brick` (BRICK_SPEC, étendu — arbitrage Pierre, R8). Le
// spec `role` n'a PAS été étendu (hors périmètre de l'arbitrage) : une entrée role reste un vrai
// gap de schéma, jamais écrite. Lister ces 2 types ici (plutôt que sonder `'usage_examples' in
// entry`, l'ancienne heuristique) est nécessaire depuis que le champ est FACULTATIF côté
// validateur : une brick qui ne l'a pas ENCORE reçu ne doit plus être confondue avec une brick
// dont le schéma ne le permet structurellement pas.
const ELIGIBLE_ENTRY_TYPES = new Set(['asset', 'brick']);

/**
 * Applique les imports détectés à `entries` (tableau `catalog.json.entries`). PURE : retourne un
 * NOUVEAU tableau, ne mute rien sur place — l'appelant décide d'écrire ou non.
 *
 * Règles (mission R8) :
 *   - append factuel, idempotent (jamais de doublon dans usage_examples) ;
 *   - ne touche à AUCUN autre champ de l'entrée ;
 *   - si l'entrée correspondante n'est pas d'un type éligible (ELIGIBLE_ENTRY_TYPES — aujourd'hui
 *     `role` seul est exclu), l'import est classé `schemaGap`, JAMAIS écrit : ajouter la clé
 *     ferait échouer kb-validate (schéma fermé, non étendu pour ce type).
 *
 * @param {Array<Object>} entries - catalog.entries (jamais muté)
 * @param {Array<{importer:string, kbPath:string}>} detectedImports
 * @returns {{entries: Array, appended: Array, alreadyPresent: Array, schemaGap: Array, unmatched: Array}}
 */
export function applyUsageExamples(entries, detectedImports) {
  const byPath = new Map();
  entries.forEach((e, i) => {
    if (typeof e.path === 'string') byPath.set(e.path, i);
  });

  const appended = [];
  const alreadyPresent = [];
  const schemaGap = [];
  const unmatched = [];
  const nextEntries = entries.slice();

  for (const { importer, kbPath } of detectedImports) {
    const idx = byPath.get(kbPath);
    if (idx === undefined) {
      unmatched.push({ importer, kbPath });
      continue;
    }
    const entry = nextEntries[idx];
    const id = entry.asset_id || entry.brick_id || entry.role_id || '<sans-id>';

    if (!ELIGIBLE_ENTRY_TYPES.has(entry.entry_type)) {
      schemaGap.push({ importer, kbPath, id, entry_type: entry.entry_type, kind: entry.kind || null });
      continue;
    }

    const current = Array.isArray(entry.usage_examples) ? entry.usage_examples : [];
    if (current.includes(importer)) {
      alreadyPresent.push({ importer, kbPath, id });
      continue;
    }

    nextEntries[idx] = { ...entry, usage_examples: [...current, importer] };
    appended.push({ importer, kbPath, id });
  }

  return { entries: nextEntries, appended, alreadyPresent, schemaGap, unmatched };
}

function main() {
  const raw = readFileSync(CATALOG_PATH, 'utf-8');
  const catalog = JSON.parse(raw);

  const detected = detectKnowledgeBaseImports();
  const { entries, appended, alreadyPresent, schemaGap, unmatched } = applyUsageExamples(catalog.entries, detected);

  console.error(`=== R8 — fill_usage_examples : ${detected.length} import(s) knowledge_base/ détecté(s) dans games/** ===`);
  for (const a of appended) console.error(`  + ${a.id}: usage_examples += "${a.importer}"`);
  for (const a of alreadyPresent) console.error(`  = ${a.id}: "${a.importer}" déjà présent (idempotent, rien à faire)`);
  for (const g of schemaGap) {
    console.error(`  ! GAP DE SCHÉMA : ${g.id} (entry_type=${g.entry_type}${g.kind ? `, kind=${g.kind}` : ''}) importé par ${g.importer}`);
    console.error('    -> ce type d\'entrée (role) n\'a pas de champ usage_examples dans le schéma actuel de kb-validate.mjs');
    console.error('       (ROLE_SPEC n\'a que proof_of_use, non étendu — hors périmètre de l\'arbitrage R8) — l\'ajouter');
    console.error('       romprait kb-validate (schéma fermé). NON écrit. Décision HumanGate requise si besoin futur.');
  }
  for (const u of unmatched) console.error(`  ? aucune entrée catalog.json avec path="${u.kbPath}" (importé par ${u.importer})`);

  const newCatalog = { ...catalog, entries };
  const serialized = JSON.stringify(newCatalog, null, 1) + '\n';

  if (serialized === raw) {
    console.error('\ncatalog.json déjà à jour — 0 octet changé (idempotent).');
  } else {
    writeFileSync(CATALOG_PATH, serialized, 'utf-8');
    console.error(`\ncatalog.json mis à jour : ${appended.length} usage_example(s) ajouté(s).`);
  }

  console.log(JSON.stringify({
    detectedCount: detected.length,
    detected,
    appended,
    alreadyPresent,
    schemaGap,
    unmatched
  }, null, 2));

  process.exit(0); // mesure + application factuelle, pas un oracle pass/fail (cf. reuse_ratio.mjs)
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  main();
}
