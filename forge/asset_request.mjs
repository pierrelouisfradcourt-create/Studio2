#!/usr/bin/env node
// asset_request.mjs — résolveur NON-LLM d'un `asset_request` (Asset Contract V0, cf.
// docs/forge/ASSET_CONTRACT_V0.md). Un asset_request est un artefact PAR-RUN (comme une
// WireMap) — jamais écrit dans knowledge_base/catalog.json (lecture seule ici). Zéro
// réseau, zéro LLM : ne juge jamais l'esthétique, ne fait que filtrer/vérifier des
// métadonnées mécaniquement contre l'offre déjà cataloguée.
//
// Usage :
//   node asset_request.mjs <request.json> [--catalog <path>] [--json]
// Exit 0 = OK (résolu, tous les acceptance_tests passent) · 1 = BLOCKED (bien formé, rien
// ne satisfait) · 2 = FAIL (requête malformée) · 3 = erreur interne/catalogue illisible.
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { search } from '../../knowledge_base/search.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DEFAULT_CATALOG_PATH = resolve(__dirname, '..', 'knowledge_base', 'catalog.json');

const ASSET_LICENSES = ['CC0-1.0', 'MIT', 'CC-BY-4.0', 'CC-BY-3.0'];
const REQUEST_TYPES = ['sprite', 'tileset', 'portrait', 'icon', 'vfx', 'audio', 'model3d'];
const FORMATS = ['2D', '3D'];
const RUNTIMES = ['html', 'godot'];
const KNOWN_CHECKS = [
  'resolved',
  'license_in_allowlist',
  'format_runtime_match',
  'style_tag_match',
  'on_disk',
  'usage_referenced',
];

// v0.1 (2026-07-14, gate 4 + sonde adversariale "deceptive builder") — ferme le vecteur
// de gaming trouve en vivo : une art_bible pouvait affirmer en prose "personnage/obstacles/
// decor couverts" avec seulement 2 requetes generiques, sans qu'aucun mecanisme ne
// verifie la COUVERTURE besoin<->requete. `entity_role` est la cle mecanique de ce
// rapprochement (cf. check_artbible.mjs::checkCoverage) -- jamais une metrique esthetique,
// une simple etiquette de "a quoi sert cette requete dans le jeu".
export const ENTITY_ROLES = [
  'player', 'enemy', 'npc', 'boss', 'item', 'collectible', 'obstacle',
  'environment', 'terrain', 'effect', 'ui', 'icon', 'other',
];
// `purpose` est captur en FORME (Critique, jamais absent) mais n'est pas encore
// consomme par un oracle -- declare pour permettre un futur rapprochement plus fin
// (ex. differencier un sprite de gameplay d'un sprite de decor pur), pas une metrique
// active aujourd'hui. Honnete : ne pas laisser croire qu'un champ valide = un champ verifie.
export const PURPOSES = ['gameplay', 'navigation', 'decoration', 'ui', 'feedback', 'animation'];

/**
 * Normalise un tag de style pour comparaison exacte (pas de similarité floue — cf.
 * docs/forge/ASSET_CONTRACT_V0.md "limites connues").
 * @param {string} s
 * @returns {string}
 */
function normalizeTag(s) {
  return String(s ?? '').toLowerCase().trim().replace(/[-_\s]+/g, '-');
}

/**
 * Règle des 3 états (absent = oubli -> rejet ; déclaré vide = décision assumée).
 * Retourne la liste des erreurs de FORME (vide = requête bien formée). N'exécute rien.
 * @param {object} request
 * @returns {string[]}
 */
export function validateRequestShape(request) {
  const errors = [];
  if (request === null || typeof request !== 'object' || Array.isArray(request)) {
    return ['asset_request doit etre un objet'];
  }

  // Critiques : absent -> erreur explicite (pas de valeur par defaut silencieuse).
  // v0.1 : id/entity_role/purpose -- sans entity_role, la couverture besoin<->requete
  // (checkCoverage) ne peut mecaniquement rien rapprocher (cf. changelog v0.1 de
  // docs/forge/ASSET_CONTRACT_V0.md).
  if (!('id' in request)) errors.push('champ Critique absent: id');
  else if (typeof request.id !== 'string' || request.id.trim().length === 0) errors.push('id doit etre une chaine non vide');

  if (!('entity_role' in request)) errors.push('champ Critique absent: entity_role');
  else if (!ENTITY_ROLES.includes(request.entity_role)) errors.push(`entity_role invalide: ${request.entity_role} (attendu: ${ENTITY_ROLES.join('|')})`);

  if (!('purpose' in request)) errors.push('champ Critique absent: purpose');
  else if (!PURPOSES.includes(request.purpose)) errors.push(`purpose invalide: ${request.purpose} (attendu: ${PURPOSES.join('|')})`);

  if (!('type' in request)) errors.push('champ Critique absent: type');
  else if (!REQUEST_TYPES.includes(request.type)) errors.push(`type invalide: ${request.type} (attendu: ${REQUEST_TYPES.join('|')})`);

  if (!('style' in request)) errors.push('champ Critique absent: style');
  else if (typeof request.style !== 'string' || request.style.length === 0) errors.push('style doit etre une chaine non vide');

  if (!('constraints' in request)) errors.push('champ Critique absent: constraints');
  else {
    const c = request.constraints;
    if (c === null || typeof c !== 'object') errors.push('constraints doit etre un objet');
    else {
      if (!('format' in c)) errors.push('champ Critique absent: constraints.format');
      else if (!FORMATS.includes(c.format)) errors.push(`constraints.format invalide: ${c.format}`);

      if (!('runtime' in c)) errors.push('champ Critique absent: constraints.runtime');
      else if (!RUNTIMES.includes(c.runtime)) errors.push(`constraints.runtime invalide: ${c.runtime}`);

      // Important : doit etre declare (null/[] autorise), jamais absent.
      if (!('license_allowed' in c)) errors.push('champ Important absent (declarez [] ou une liste): constraints.license_allowed');
      else if (c.license_allowed !== null && !(Array.isArray(c.license_allowed) && c.license_allowed.every((l) => typeof l === 'string'))) {
        errors.push('constraints.license_allowed doit etre null ou un tableau de chaines');
      }

      if (!('genre' in c)) errors.push('champ Important absent (declarez [] ou une liste): constraints.genre');
      else if (!(Array.isArray(c.genre) && c.genre.every((g) => typeof g === 'string'))) errors.push('constraints.genre doit etre un tableau de chaines');

      if (!('max_size_kb' in c)) errors.push('champ Important absent (declarez null ou un nombre): constraints.max_size_kb');
      else if (c.max_size_kb !== null && !(typeof c.max_size_kb === 'number' && c.max_size_kb > 0)) errors.push('constraints.max_size_kb doit etre null ou un nombre positif');
    }
  }

  if (!('references' in request)) errors.push('champ Important absent (declarez []): references');
  else if (!(Array.isArray(request.references) && request.references.every((r) => typeof r === 'string'))) errors.push('references doit etre un tableau de chaines');

  if (!('acceptance_tests' in request)) errors.push('champ Critique absent: acceptance_tests');
  else if (!Array.isArray(request.acceptance_tests) || request.acceptance_tests.length === 0) {
    errors.push('acceptance_tests doit etre un tableau non vide (au moins "resolved")');
  } else {
    for (const t of request.acceptance_tests) {
      if (t === null || typeof t !== 'object' || typeof t.check !== 'string') {
        errors.push('acceptance_tests: chaque entree doit etre {check: <nom>}');
      } else if (!KNOWN_CHECKS.includes(t.check)) {
        errors.push(`acceptance_tests: check inconnu (liste fermee): ${t.check}`);
      }
    }
  }

  return errors;
}

/**
 * Filtre le catalogue selon les contraintes mécaniques de la requête (avant scoring).
 * @param {object} entry
 * @param {object} constraints
 * @param {string} styleNormalized
 * @returns {boolean}
 */
function passesConstraints(entry, constraints, styleNormalized) {
  if (entry.entry_type !== 'asset') return false;
  if (entry.format !== constraints.format) return false;
  if (entry.runtime !== constraints.runtime) return false;
  const allowed = constraints.license_allowed && constraints.license_allowed.length > 0 ? constraints.license_allowed : ASSET_LICENSES;
  if (!allowed.includes(entry.license)) return false;
  if (constraints.genre && constraints.genre.length > 0) {
    const entryGenres = (entry.genre || []).map((g) => g.toLowerCase());
    if (!constraints.genre.some((g) => entryGenres.includes(g.toLowerCase()))) return false;
  }
  if (constraints.max_size_kb !== null && typeof constraints.max_size_kb === 'number') {
    // entry.size_kb === null (manifest-only 3D, jamais telecharge) : la contrainte
    // ne peut pas etre VERIFIEE, donc elle n'est pas satisfaite (gate 4 Qwen,
    // 2026-07-14) -- avant ce fix, une taille inconnue passait silencieusement.
    if (entry.size_kb === null || entry.size_kb > constraints.max_size_kb) return false;
  }
  if (normalizeTag(entry.style) !== styleNormalized) return false;
  return true;
}

/**
 * Résout un asset_request contre le catalogue chargé : filtre par contraintes, trie par
 * le même ordre déterministe que search.mjs (score texte sur `style`, puis tier, puis id).
 * @param {object} request requête déjà validée en forme
 * @param {object} catalog {entries:[...]}
 * @returns {{candidates: object[], resolved: object|null}}
 */
export function resolveRequest(request, catalog) {
  const styleNormalized = normalizeTag(request.style);
  const preFiltered = (catalog.entries || []).filter((e) => passesConstraints(e, request.constraints, styleNormalized));
  // Réutilise search() pour le tri déterministe (tier validated avant candidate, puis id) ;
  // le style est déjà garanti égal par passesConstraints, donc score>=0 accepté ici.
  const scored = search(request.style, { entries: preFiltered }, { minScore: 0 });
  const candidates = scored.map((r) => r.entry);
  return { candidates, resolved: candidates.length > 0 ? candidates[0] : null };
}

/**
 * Exécute un check individuel sur l'entrée résolue (ou null si BLOCKED).
 * @param {{check: string}} test
 * @param {object} request
 * @param {object|null} entry
 * @returns {{check: string, ok: boolean, detail: string}}
 */
function runOneCheck(test, request, entry) {
  const c = test.check;
  if (c === 'resolved') {
    return { check: c, ok: entry !== null, detail: entry ? `resolu: ${entry.asset_id}` : 'aucune entree du catalogue ne satisfait constraints' };
  }
  if (entry === null) return { check: c, ok: false, detail: 'non evalue : aucune entree resolue' };

  if (c === 'license_in_allowlist') {
    const allowed = request.constraints.license_allowed && request.constraints.license_allowed.length > 0 ? request.constraints.license_allowed : ASSET_LICENSES;
    const ok = allowed.includes(entry.license);
    return { check: c, ok, detail: `entry.license=${entry.license} allowlist=${allowed.join(',')}` };
  }
  if (c === 'format_runtime_match') {
    const ok = entry.format === request.constraints.format && entry.runtime === request.constraints.runtime;
    return { check: c, ok, detail: `entry=${entry.format}/${entry.runtime} attendu=${request.constraints.format}/${request.constraints.runtime}` };
  }
  if (c === 'style_tag_match') {
    const ok = normalizeTag(entry.style) === normalizeTag(request.style);
    return { check: c, ok, detail: `entry.style=${entry.style} request.style=${request.style}` };
  }
  if (c === 'on_disk') {
    if (entry.ingested === false) {
      const ok = request.constraints.format === '3D';
      return { check: c, ok, detail: ok ? 'manifest-only 3D coherent (ingested=false attendu)' : 'ingested=false mais format demande != 3D' };
    }
    // ingested=true : la realite disque (sha256/existence) est deja garantie par
    // kb-validate.mjs a l'admission dans le catalogue (porte unique, cf. R7) — ce check
    // relit le champ, ne re-scanne pas le disque (evite une double dependance de garde).
    const ok = entry.path !== null && typeof entry.sha256 === 'string';
    return { check: c, ok, detail: ok ? `path=${entry.path}` : 'ingested=true sans path/sha256 coherents' };
  }
  if (c === 'usage_referenced') {
    const ok = entry.tier === 'validated' && Array.isArray(entry.usage_examples) && entry.usage_examples.length > 0;
    return { check: c, ok, detail: ok ? `usage_examples=${entry.usage_examples.length}` : `tier=${entry.tier} usage_examples=${(entry.usage_examples || []).length}` };
  }
  return { check: c, ok: false, detail: `check non implemente: ${c}` };
}

/**
 * Exécute tous les acceptance_tests déclarés, dans l'ordre.
 * @param {object} request
 * @param {object|null} entry
 * @returns {{check:string, ok:boolean, detail:string}[]}
 */
export function runAcceptanceTests(request, entry) {
  return request.acceptance_tests.map((t) => runOneCheck(t, request, entry));
}

/**
 * Point d'entrée complet : forme -> résolution -> checks -> verdict.
 * @param {object} request
 * @param {object} catalog
 * @returns {{verdict: 'OK'|'BLOCKED'|'FAIL', shape_errors: string[], resolved: object|null,
 *   checks: object[], fog: string|null}}
 */
export function evaluateAssetRequest(request, catalog) {
  const shapeErrors = validateRequestShape(request);
  if (shapeErrors.length > 0) {
    return { verdict: 'FAIL', shape_errors: shapeErrors, resolved: null, checks: [], fog: null };
  }
  const { resolved } = resolveRequest(request, catalog);
  const checks = runAcceptanceTests(request, resolved);
  const allOk = checks.every((c) => c.ok);
  if (!allOk) {
    return {
      verdict: 'BLOCKED',
      shape_errors: [],
      resolved: null,
      checks,
      fog: 'aucune entree du catalogue ne satisfait tous les acceptance_tests — sourcer un nouvel asset ou revoir la requete (HumanGate)',
    };
  }
  return {
    verdict: 'OK',
    shape_errors: [],
    resolved,
    checks,
    fog: 'conformite esthetique non evaluee — jugement Pierre requis (cf. docs/forge/ASSET_CONTRACT_V0.md)',
  };
}

// ---- CLI ----
const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const argv = process.argv.slice(2);
  const positional = argv.filter((a) => !a.startsWith('--'));
  const asJson = argv.includes('--json');
  const catalogFlagIdx = argv.indexOf('--catalog');
  const catalogPath = catalogFlagIdx !== -1 ? resolve(argv[catalogFlagIdx + 1]) : DEFAULT_CATALOG_PATH;
  const requestPath = positional[0];

  if (!requestPath) {
    console.error('usage: node asset_request.mjs <request.json> [--catalog <path>] [--json]');
    process.exit(3);
  }

  try {
    const request = JSON.parse(readFileSync(resolve(requestPath), 'utf-8'));
    const catalog = JSON.parse(readFileSync(catalogPath, 'utf-8'));
    const result = evaluateAssetRequest(request, catalog);

    if (asJson) {
      console.log(JSON.stringify(result, null, 2));
    } else {
      console.log(`VERDICT ASSET_REQUEST: ${result.verdict}`);
      if (result.shape_errors.length > 0) result.shape_errors.forEach((e) => console.error(`  FORME: ${e}`));
      result.checks.forEach((c) => console.error(`  [${c.ok ? 'OK' : 'FAIL'}] ${c.check}: ${c.detail}`));
      if (result.resolved) console.log(`  resolu: ${result.resolved.asset_id}`);
      if (result.fog) console.error(`  FOG: ${result.fog}`);
    }
    process.exit(result.verdict === 'OK' ? 0 : result.verdict === 'BLOCKED' ? 1 : 2);
  } catch (e) {
    console.error(`ERREUR INTERNE: ${String((e && e.stack) || e)}`);
    process.exit(3);
  }
}
