#!/usr/bin/env node
// search.mjs — moteur de RECHERCHE PAR INTENTION dans knowledge_base/catalog.json.
// Zéro réseau, zéro LLM, zéro embedding — un scoreur déterministe par recouvrement de
// mots-clés sur les champs texte du catalogue, explicable ligne à ligne (pourquoi CE
// résultat matche). Comble le manque nommé dans docs/forge/STUDIO_MASTER_SCHEMA.html /
// PRISM_SCOPING.md context : « chercher dans la bibliothèque par intention plutôt que
// copier-coller à la main » — la pièce la plus manquante de la Forge (`P1..P5` roadmap).
//
// Usage :
//   node search.mjs "zone de controle qui bloque un deplacement"
//   node search.mjs "degats" --genre tactical --tier validated
//   node search.mjs "reachability" --kind system --json
//
// Filtres optionnels : --genre <g> --kind <system|pattern|asset|template>
//   --tier <candidate|validated> --format <2D|3D> --runtime <html|agnostic|godot|...>
//   --min-score <n> (défaut 1) --json (sortie machine-lisible sur stdout)
//
// Exit 0 = au moins 1 résultat au-dessus du seuil · 1 = zéro résultat · 2 = erreur
// (catalogue illisible, argument invalide) — utilisable en script.
import { readFileSync, appendFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { missingCapabilities } from './kb-validate.mjs';

const __dirname = dirname(fileURLToPath(import.meta.url));
const DEFAULT_CATALOG_PATH = resolve(__dirname, 'catalog.json');
const DEFAULT_SYNONYMS_PATH = resolve(__dirname, 'synonyms.json');
const DEFAULT_MIN_SCORE = 1;
// Auto-journalisation CLI (preuve mécanique passive qu'une recherche a eu lieu — pas une
// déclaration de contrat espérée). Runtime, append-only, churne : gitignoré comme
// lab/events.jsonl (cf. .gitignore racine), PAS une preuve à committer.
const DEFAULT_SEARCH_LOG_PATH = resolve(__dirname, 'search_log.jsonl');

/** Valeur d'un `caller` non déclaré. C'est une VALEUR, pas une absence : le journal
 *  doit pouvoir dire « personne ne s'est nommé » sans qu'on ait à le deviner. */
export const CALLER_UNDECLARED = 'undeclared';

/** Liste FERMÉE des appelants (SEARCH_USAGE_CONTRACT_V1). Une valeur hors liste
 *  retombe sur `undeclared` — jamais enregistrée telle quelle, sinon la liste ne
 *  ferme rien. */
export const CALLERS = new Set(['preflight', 's9-build', 'cli', 'test', CALLER_UNDECLARED]);

// Mots vides FR/EN courts — retirés de la requête pour éviter les faux matches triviaux
// ("de", "un", "qui"...) qui gonfleraient le score sans rien dire de l'intention.
const STOPWORDS = new Set([
  'le', 'la', 'les', 'un', 'une', 'des', 'de', 'du', 'et', 'ou', 'qui', 'que', 'a', 'à',
  'pour', 'avec', 'sur', 'dans', 'est', 'en', 'au', 'aux', 'ce', 'cet', 'cette', 'ces',
  'se', 'son', 'sa', 'ses', 'ne', 'pas', 'tout', 'toute', 'tous', 'toutes', 'plus', 'si',
  'dont', 'ai', 'as', 'ont', 'suis', 'es', 'sont', 'j', 'l', 'd', 'n', 'c', 'm', 's', 'y',
  'the', 'an', 'of', 'for', 'with', 'on', 'in', 'is', 'and', 'or', 'that', 'which', 'to',
  'be', 'have', 'not', 'all', 'some', 'any', 'i', 'you', 'it', 'this',
]);

/**
 * Normalise une chaîne pour la comparaison : minuscules, accents retirés, ponctuation
 * réduite à des espaces. Déterministe, aucune dépendance externe.
 * @param {string} str
 * @returns {string}
 */
function normalize(str) {
  return String(str)
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

/**
 * Découpe une requête normalisée en tokens uniques, mots vides retirés.
 * @param {string} query
 * @returns {string[]}
 */
function tokenize(query) {
  return [...new Set(normalize(query).split(' ').filter((t) => t.length > 1 && !STOPWORDS.has(t)))];
}

/**
 * Élargit un ensemble de tokens de requête via un dictionnaire de synonymes déterministe
 * (aucun embedding, aucun LLM) : pour chaque token présent — comme CLÉ de groupe OU comme
 * MEMBRE d'un groupe — tous les autres membres du groupe sont ajoutés au résultat.
 * Le résultat est TOUJOURS un sur-ensemble de `tokens` (jamais de suppression) et jamais
 * de mutation de l'entrée — fonction pure.
 * @param {string[]} tokens tokens de requête (déjà normalisés, cf. tokenize())
 * @param {object} synonymMap {groupe_canonique: [synonyme, ...]} — peut être vide/absent
 * @returns {string[]} nouveau tableau de tokens uniques, sur-ensemble de `tokens`
 */
export function expandWithSynonyms(tokens, synonymMap) {
  const expanded = new Set(tokens);
  if (!synonymMap || typeof synonymMap !== 'object') return [...expanded];

  for (const token of tokens) {
    for (const [groupKey, members] of Object.entries(synonymMap)) {
      if (!Array.isArray(members)) continue;
      const inGroup = token === groupKey || members.includes(token);
      if (!inGroup) continue;
      expanded.add(groupKey);
      for (const member of members) expanded.add(member);
    }
  }
  return [...expanded];
}

/**
 * Charge synonyms.json de façon best-effort : fichier absent/illisible/JSON invalide →
 * objet vide (comportement IDENTIQUE à avant l'existence de cette feature, pas de crash).
 * @param {string} synonymsPath
 * @returns {object}
 */
function loadSynonyms(synonymsPath) {
  try {
    const raw = readFileSync(synonymsPath, 'utf-8');
    const parsed = JSON.parse(raw);
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch {
    return {};
  }
}

/**
 * Concatène tous les champs texte pertinents d'une entrée en un seul blob normalisé,
 * pour le scoring — même traitement quel que soit `entry_type` (asset/brick).
 * @param {object} entry
 * @returns {string}
 */
function searchableBlob(entry) {
  const parts = [
    entry.entry_type,
    entry.asset_id,
    entry.brick_id,
    // archetype (prose libre du rôle) est délibérément EXCLU du scoring textuel : son
    // vocabulaire descriptif fait gonfler le score au-delà des pièces qui IMPLÉMENTENT
    // réellement le mécanisme (régression mesurée : role-guardian-static primait sur
    // sys-guardian-zoc). Chercher un rôle mécaniquement = --fulfills, pas le scoring flou.
    entry.role_id,
    entry.kind,
    entry.function,
    entry.source,
    entry.style,
    entry.biome,
    entry.format,
    entry.runtime,
    entry.license,
    ...(entry.genre || []),
    ...(entry.genre_compatible || []),
    ...(entry.invariants || []),
    ...(entry.dependencies || []),
  ].filter(Boolean);
  return normalize(parts.join(' '));
}

// 5, pas 4 : un seuil à 4 faisait matcher "poursuite" contre le mot français courant
// "pour" (préfixe de 4) dans un texte sans rapport (invariant "... pour tout ...") —
// faux positif réel trouvé en vérifiant search.mjs sur le catalogue enrichi (rôles).
// "degat"/"degats" (préfixe partagé de 5) reste couvert par ce seuil.
const MIN_SHARED_PREFIX = 5;

/**
 * Un token de requête "matche" un mot du blob si l'un est préfixe de l'autre, avec au
 * moins MIN_SHARED_PREFIX caractères communs — tolère les variations singulier/pluriel
 * simples ("degat" / "degats") SANS stemmer ni dictionnaire (déterministe, explicable).
 * Bug réel trouvé en testant : un pur `blob.includes(token)` ratait "degats" (requête,
 * pluriel) contre "degat_effectif" (catalogue, singulier) — corrigé ici.
 * @param {string} token
 * @param {string} word
 * @returns {boolean}
 */
function tokenMatchesWord(token, word) {
  if (token === word) return true;
  const shared = Math.min(token.length, word.length);
  if (shared < MIN_SHARED_PREFIX) return false;
  return token.startsWith(word) || word.startsWith(token);
}

/**
 * Score une entrée pour une liste de tokens de requête : nombre de tokens distincts qui
 * matchent au moins un mot du blob de l'entrée (préfixe partagé, cf. tokenMatchesWord),
 * + quels tokens ont matché (transparence, jamais une boîte noire).
 * @param {object} entry
 * @param {string[]} queryTokens
 * @returns {{score:number, matchedTokens:string[]}}
 */
function scoreEntry(entry, queryTokens) {
  const blobWords = searchableBlob(entry).split(' ').filter(Boolean);
  const matchedTokens = queryTokens.filter((token) => blobWords.some((word) => tokenMatchesWord(token, word)));
  return { score: matchedTokens.length, matchedTokens };
}

/**
 * Applique les filtres exacts (genre/kind/tier/format/runtime) déclarés en options —
 * AVANT le scoring textuel, comme un pré-filtre déterministe classique.
 * @param {object} entry
 * @param {object} filters
 * @returns {boolean}
 */
function passesFilters(entry, filters) {
  if (filters.genre) {
    const genres = [...(entry.genre || []), ...(entry.genre_compatible || [])].map((g) => g.toLowerCase());
    if (!genres.includes(filters.genre.toLowerCase())) return false;
  }
  if (filters.kind) {
    const kind = (entry.kind || entry.entry_type || '').toLowerCase();
    if (kind !== filters.kind.toLowerCase()) return false;
  }
  if (filters.tier && (entry.tier || '').toLowerCase() !== filters.tier.toLowerCase()) return false;
  if (filters.format && (entry.format || '').toLowerCase() !== filters.format.toLowerCase()) return false;
  if (filters.runtime && (entry.runtime || '').toLowerCase() !== filters.runtime.toLowerCase()) return false;
  return true;
}

/**
 * Recherche par intention dans le catalogue chargé.
 * @param {string} query texte libre décrivant le besoin
 * @param {object} catalog {entries:[...]}
 * @param {object} [options] {genre,kind,tier,format,runtime,minScore}
 * @returns {Array<{entry:object, score:number, matchedTokens:string[]}>} trié par score
 *   décroissant, puis tier (validated avant candidate), puis id alphabétique — déterministe.
 */
export function search(query, catalog, options = {}) {
  const rawTokens = tokenize(query);
  const synonymMap = loadSynonyms(options.synonymsPath ? resolve(options.synonymsPath) : DEFAULT_SYNONYMS_PATH);
  const queryTokens = expandWithSynonyms(rawTokens, synonymMap);
  const minScore = Number.isFinite(options.minScore) ? options.minScore : DEFAULT_MIN_SCORE;
  const entries = (catalog && catalog.entries) || [];

  const results = [];
  for (const entry of entries) {
    if (!passesFilters(entry, options)) continue;
    const { score, matchedTokens } = scoreEntry(entry, queryTokens);
    if (score >= minScore) results.push({ entry, score, matchedTokens });
  }

  results.sort((a, b) => {
    if (b.score !== a.score) return b.score - a.score;
    const tierRank = (t) => (t === 'validated' ? 0 : 1);
    const tierDiff = tierRank(a.entry.tier) - tierRank(b.entry.tier);
    if (tierDiff !== 0) return tierDiff;
    const idA = a.entry.brick_id || a.entry.asset_id || a.entry.role_id || '';
    const idB = b.entry.brick_id || b.entry.asset_id || b.entry.role_id || '';
    return idA.localeCompare(idB);
  });

  return results;
}

/**
 * Le pont SEARCH↔ROLE (Tier 1 #4) : « quelles pièces du catalogue couvrent réellement
 * ce rôle ? » — une comparaison mécanique (affordances ⊇ requires), pas une lecture de
 * `fulfilled_by` (qui reste une déclaration, désormais vérifiée par kb-validate.mjs R14,
 * mais limitée aux bricks QUE le rôle cite). Ici on balaie TOUT le catalogue : une pièce
 * non encore déclarée dans `fulfilled_by` mais qui couvre déjà `requires` est trouvée.
 * @param {string} roleId
 * @param {object} catalog
 * @returns {{role:object, fulfilling:object[], declaredButNotCovered:object[]}}
 *   `fulfilling` = bricks dont affordances ⊇ requires (le rôle EST réellement couvert par).
 *   `declaredButNotCovered` = bricks cités par fulfilled_by dont la couverture est fausse
 *   (signal direct d'un catalogue périmé — cf. R14).
 */
export function findFulfilling(roleId, catalog) {
  const entries = (catalog && catalog.entries) || [];
  const role = entries.find((e) => e.entry_type === 'role' && e.role_id === roleId);
  if (!role) return { role: null, fulfilling: [], declaredButNotCovered: [] };

  const bricks = entries.filter((e) => e.entry_type === 'brick');
  const fulfilling = bricks.filter((b) => missingCapabilities(role.requires, b.affordances).length === 0);
  const fulfillingIds = new Set(fulfilling.map((b) => b.brick_id));
  const declaredButNotCovered = bricks.filter(
    (b) => (role.fulfilled_by || []).includes(b.brick_id) && !fulfillingIds.has(b.brick_id)
  );
  return { role, fulfilling, declaredButNotCovered };
}

/**
 * Auto-journalisation best-effort d'un appel CLI de recherche : append UNE ligne JSONL
 * {query, matchCount, ts} à logPath. N'est appelée QUE depuis main() (CLI) — search() et
 * findFulfilling() restent des fonctions pures sans effet de bord (utilisées par les tests).
 * Best-effort volontaire (même esprit que studio_link.py `_append` en Python, mais ici on
 * catch explicitement) : si l'écriture échoue (dossier absent, permissions, disque plein…),
 * la recherche doit TOUJOURS répondre — le log ne doit jamais faire planter l'outil.
 * @param {string} query
 * @param {number} matchCount
 * @param {string} [logPath]
 * @returns {void}
 */
export function logSearchInvocation(query, resultats, options = {}) {
  try {
    // `options` accepte encore une CHAÎNE (l'ancien 3e argument `logPath`) : 29 entrées
    // du journal ont été écrites avec cette signature, et un appelant oublié ne doit
    // pas cesser de journaliser en silence.
    const opts = typeof options === 'string' ? { logPath: options } : options;
    const logPath = opts.logPath || DEFAULT_SEARCH_LOG_PATH;

    // matchCount seul (legacy) OU la liste des résultats. Enregistrer les IDENTITÉS
    // est ce qui rend la consommation vérifiable plus tard : sans elles, « telle brique
    // a été réutilisée » ne peut pas être rapproché de « telle brique avait été
    // proposée ». Aucun score n'est enregistré — l'ordre est celui que `search` rend.
    const estListe = Array.isArray(resultats);
    // `search()` rend {entry, score, matchedTokens} ; l'identité est dans `entry`.
    // Le SCORE n'est pas enregistré — seulement l'identité et l'ordre rendu.
    const matchedIds = estListe
      ? resultats
        .map((r) => r?.entry?.brick_id ?? r?.entry?.asset_id ?? r?.brick_id ?? r?.asset_id)
        .filter(Boolean)
      : null;

    const record = {
      kind: 'search',
      // CALLER DÉCLARÉ, jamais deviné. `undeclared` est une valeur, pas un trou : un
      // appel non attribué doit être visible, sinon on relit le journal en devinant
      // (c'est ce qui a produit une conclusion fausse le 2026-08-04).
      caller: CALLERS.has(opts.caller) ? opts.caller : CALLER_UNDECLARED,
      query,
      matchCount: estListe ? resultats.length : resultats,
      ...(matchedIds ? { matched_ids: matchedIds } : {}),
      ts: new Date().toISOString(),
    };
    mkdirSync(dirname(logPath), { recursive: true });
    appendFileSync(logPath, JSON.stringify(record) + '\n', 'utf-8');
  } catch {
    // Best-effort, intentionnel : un log qui échoue ne doit jamais empêcher la recherche
    // de répondre. Pas de re-throw, pas de log d'erreur bruyant (silencieux par design).
  }
}

/**
 * Lit search_log.jsonl et retourne les entrées dont `ts >= sinceIso` — sert de PREUVE
 * mécanique qu'au moins une recherche a eu lieu depuis un instant donné (ex: le début
 * d'une étape Forge), sans faire confiance à une déclaration de contrat.
 * @param {string} sinceIso date ISO 8601 (comparaison lexicale, valide pour ISO 8601 UTC)
 * @param {string} [logPath]
 * @returns {{count:number, entries:object[]}}
 */
export function searchLogSince(sinceIso, logPath = DEFAULT_SEARCH_LOG_PATH) {
  let raw;
  try {
    raw = readFileSync(logPath, 'utf-8');
  } catch {
    return { count: 0, entries: [] };
  }
  const entries = [];
  for (const line of raw.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    try {
      const record = JSON.parse(trimmed);
      if (record.ts && record.ts >= sinceIso) entries.push(record);
    } catch {
      // ligne corrompue : ignorée, jamais fatale.
    }
  }
  return { count: entries.length, entries };
}

function loadCatalog(catalogPath) {
  const raw = readFileSync(catalogPath, 'utf-8');
  return JSON.parse(raw);
}

function parseArgs(argv) {
  const positional = [];
  const options = {};
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--json') {
      options.json = true;
    } else if (arg.startsWith('--')) {
      const key = arg.slice(2).replace(/-([a-z])/g, (_, c) => c.toUpperCase());
      const value = argv[i + 1];
      i += 1;
      options[key] = key === 'minScore' ? Number(value) : value;
    } else {
      positional.push(arg);
    }
  }
  return { query: positional.join(' '), options };
}

function formatResultLine(result) {
  const { entry, score, matchedTokens } = result;
  const id = entry.brick_id || entry.asset_id || entry.role_id;
  const label = entry.function || entry.style || '(sans description)';
  const tier = entry.tier || '?';
  return `[score=${score}] ${id} (${entry.kind || entry.entry_type}, tier=${tier})\n    ${label}\n    matché sur : ${matchedTokens.join(', ')}\n    path : ${entry.path}`;
}

function main() {
  const argv = process.argv.slice(2);
  const { query, options } = parseArgs(argv);

  let catalog;
  try {
    catalog = loadCatalog(options.catalog ? resolve(options.catalog) : DEFAULT_CATALOG_PATH);
  } catch (err) {
    console.error(`catalogue illisible : ${err.message}`);
    process.exit(2);
  }

  // Tier 1 #4 : --fulfills <role_id> bascule sur le pont SEARCH↔ROLE (affordances ⊇
  // requires), mécanique, indépendant du scoring textuel.
  if (options.fulfills) {
    const { role, fulfilling, declaredButNotCovered } = findFulfilling(options.fulfills, catalog);
    if (!role) {
      console.error(`role inconnu dans le catalogue : ${options.fulfills}`);
      process.exit(2);
    }
    if (options.json) {
      console.log(JSON.stringify({ role: role.role_id, fulfilling, declaredButNotCovered }, null, 2));
    } else {
      console.log(`=== PONT SEARCH<->ROLE — ${role.role_id} ===\n`);
      console.log(`requires : ${Object.keys(role.requires).join(', ')}\n`);
      if (fulfilling.length === 0) {
        console.log('Aucune piece du catalogue ne couvre ce role.');
      } else {
        for (const b of fulfilling) console.log(`  - ${b.brick_id} (tier=${b.tier}) : ${b.function}`);
      }
      if (declaredButNotCovered.length > 0) {
        console.log(`\nATTENTION — declare dans fulfilled_by mais couverture fausse (catalogue perime) :`);
        for (const b of declaredButNotCovered) console.log(`  - ${b.brick_id}`);
      }
    }
    process.exit(fulfilling.length > 0 ? 0 : 1);
  }

  if (!query.trim()) {
    console.error('Usage: node search.mjs "<intention en texte libre>" [--genre X] [--kind system|pattern|asset] [--tier validated|candidate] [--format 2D|3D] [--runtime html|agnostic] [--min-score N] [--json] | --fulfills <role_id>');
    process.exit(2);
  }

  const results = search(query, catalog, options);
  logSearchInvocation(query, results, { logPath: options.logPath, caller: options.caller });

  if (options.json) {
    console.log(JSON.stringify({ query, count: results.length, results }, null, 2));
  } else {
    console.log(`=== RECHERCHE — "${query}" ===\n`);
    if (results.length === 0) {
      console.log('Aucun résultat au-dessus du seuil de score.');
    } else {
      for (const r of results) console.log(formatResultLine(r) + '\n');
      console.log(`${results.length} résultat(s).`);
    }
  }

  process.exit(results.length > 0 ? 0 : 1);
}

if (import.meta.url === `file://${process.argv[1]}` || import.meta.url === `file:///${(process.argv[1] || '').replace(/\\/g, '/')}`) {
  main();
}
