#!/usr/bin/env node
// check_prisme_manifest.mjs — oracle déterministe non-LLM de l'étape s1-prisme,
// sur l'artefact STRUCTURÉ prisme.json.
//
// Ne remplace PAS forge/prisme/check_prisme.mjs : celui-là vérifie la forme
// markdown des sorties du panel (product_snapshot.md), il reste le check du panel.
// Celui-ci juge l'artefact que la chaîne CONSOMME réellement en aval.
//
// CE QU'IL MESURE (spec Pierre, 2026-08-04) — jamais la beauté du texte, jamais un
// LLM-as-judge : la chaîne
//     Observation -> Exigence -> Preuve attendue -> Destination
// et la provenance de chaque exigence.
//
// DEUX NIVEAUX, VOLONTAIREMENT SÉPARÉS :
//   1. CONFORMITÉ STRUCTURELLE (`problems`) -> décide le verdict OK/FAIL.
//      id, observation, énoncé, provenance (source/source_role/reference).
//   2. ACTIONNABILITÉ (`non_actionnables`) -> CLASSÉE, pas jugée.
//      Une exigence sans preuve attendue exploitable ou sans destination valide ne
//      peut pas être routée : c'est un FAIT mesurable qu'on remonte, avec un taux.
//      Elle ne fait basculer le verdict que si AUCUNE exigence de l'artefact n'est
//      actionnable — un artefact qui ne route rien n'est pas un artefact.
//
// Pourquoi ce partage : un oracle qui FAIL sur la première exigence bancale rend
// tout artefact candidat incomparable, donc rend la substitution de worker
// indécidable — exactement l'impasse mesurée le 2026-08-03. On classe pour mesurer,
// on refuse le vacant.
//
// Usage :
//   node check_prisme_manifest.mjs <prisme.json> [--worldscan <worldscan.json>] [--json]
// Exit 0 = OK · 1 = FAIL · 2 = usage.
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  DESTINATIONS,
  isNonEmptyString,
  validateExpectedProof,
  validateProvenance,
  validateChaine,
  duplicateIds,
  normalizeText,
  isLoopExigence,
  hasGmSource,
} from './upstream_schema.mjs';

/**
 * Extrait les jetons de référence citables d'un manifeste World Scan (ids de jeux,
 * URLs de sources). Sert à vérifier qu'une `reference` d'exigence EXPECTED désigne
 * quelque chose de RÉEL dans l'observation, et pas une source inventée.
 * @param {object|null} worldscan
 * @returns {Set<string>} jetons normalisés
 */
export function worldscanTokens(worldscan) {
  const out = new Set();
  const games = Array.isArray(worldscan?.games) ? worldscan.games : [];
  games.forEach((g, gi) => {
    if (isNonEmptyString(g?.game)) out.add(normalizeText(g.game));
    out.add(`games ${gi}`);
    const sources = Array.isArray(g?.sources) ? g.sources : [];
    sources.forEach((s, si) => {
      if (isNonEmptyString(s?.url)) out.add(normalizeText(s.url));
      out.add(normalizeText(`games[${gi}].sources[${si}]`));
    });
  });
  return out;
}

/**
 * Vrai si une `reference` d'exigence EXPECTED est ancrée dans le World Scan fourni.
 * Ancrage = le jeton normalisé du World Scan apparaît dans la référence (ou
 * l'inverse) — appariement de SOUS-CHAÎNE, jamais une inférence sémantique.
 * @param {string} reference
 * @param {Set<string>} tokens
 * @returns {boolean}
 */
export function referenceAncree(reference, tokens) {
  const ref = normalizeText(reference);
  if (ref.length === 0) return false;
  for (const t of tokens) {
    if (t.length === 0) continue;
    if (ref.includes(t) || t.includes(ref)) return true;
  }
  return false;
}

/**
 * Oracle complet sur un prisme.json déjà parsé.
 * @param {unknown} doc
 * @param {object|null} worldscan manifeste World Scan (optionnel) — si fourni, les
 *   références des exigences EXPECTED sont vérifiées comme ANCRÉES dedans.
 * @returns {{ok:boolean, verdict:'OK'|'FAIL', problems:string[],
 *            non_actionnables:string[], references_non_ancrees:string[], stats:object}}
 */
export function checkPrismeDoc(doc, worldscan = null) {
  const empty = {
    exigences: 0, expected: 0, additions: 0,
    actionnables: 0, non_actionnables: 0,
    references_ancrees: 0, references_verifiees: 0,
    exigences_boucle: 0, exigences_sourcees_gm: 0,
  };
  if (doc === null || typeof doc !== 'object' || Array.isArray(doc)) {
    return {
      ok: false, verdict: 'FAIL',
      problems: ['prisme.json: doit etre un objet {game_id, exigences}'],
      non_actionnables: [], references_non_ancrees: [], stats: empty,
    };
  }

  const problems = [];
  const non_actionnables = [];
  const references_non_ancrees = [];

  if (!isNonEmptyString(doc.game_id)) problems.push('prisme.json.game_id: absent ou vide');

  const exigences = Array.isArray(doc.exigences) ? doc.exigences : null;
  if (exigences === null || exigences.length === 0) {
    problems.push('prisme.json.exigences: doit etre un tableau NON VIDE (un Prisme qui n\'exige rien ne transforme aucune connaissance)');
    return { ok: false, verdict: 'FAIL', problems, non_actionnables, references_non_ancrees, stats: empty };
  }

  const tokens = worldscan ? worldscanTokens(worldscan) : null;
  let expected = 0;
  let additions = 0;
  let actionnables = 0;
  let referencesAncrees = 0;
  let referencesVerifiees = 0;
  // Lot B, T3 (2026-08-23) : mesure du sourçage GM des exigences de boucle —
  // ADVISORY, jamais gatant ici (verrou GO Pierre : gate seulement au run 10).
  // Baseline mesurée run 9 (sans bloc `game_master`) : 13/13 non sourcées.
  let exigencesBoucle = 0;
  let exigencesSourceesGm = 0;

  exigences.forEach((ex, i) => {
    const loc = `exigences[${i}]`;
    if (ex === null || typeof ex !== 'object' || Array.isArray(ex)) {
      problems.push(`${loc}: doit etre un objet`);
      return;
    }
    // --- niveau 1 : conformité structurelle (décide le verdict) ---
    if (!isNonEmptyString(ex.id)) problems.push(`${loc}.id: absent ou vide`);
    problems.push(...validateChaine(ex, loc));
    problems.push(...validateProvenance(ex, loc));

    if (ex.source === 'EXPECTED') expected += 1;
    if (ex.source === 'ADDITIONS') additions += 1;

    if (isLoopExigence(ex)) {
      exigencesBoucle += 1;
      if (hasGmSource(ex)) exigencesSourceesGm += 1;
    }

    // Ancrage de la référence dans le World Scan (seulement si on nous l'a donné —
    // sans World Scan on ne PRÉTEND pas avoir vérifié : `references_verifiees` reste 0).
    if (tokens && ex.source === 'EXPECTED' && isNonEmptyString(ex.reference)) {
      referencesVerifiees += 1;
      if (referenceAncree(ex.reference, tokens)) referencesAncrees += 1;
      else references_non_ancrees.push(`${loc}.reference: '${ex.reference}' n'est ancree dans aucune source du World Scan`);
    }

    // --- niveau 2 : actionnabilité (classée, jamais jugée) ---
    const proofFindings = validateExpectedProof(ex.expected_proof, loc);
    const destOk = DESTINATIONS.includes(ex.destination);
    if (proofFindings.length === 0 && destOk) {
      actionnables += 1;
    } else {
      non_actionnables.push(...proofFindings);
      if (!destOk) {
        non_actionnables.push(`${loc}.destination: invalide (attendu: ${DESTINATIONS.join('|')}) — exigence non routable`);
      }
    }
  });

  problems.push(...duplicateIds(
    exigences.filter((e) => e && isNonEmptyString(e.id)).map((e) => e.id),
    'prisme.json.exigences',
  ));

  // Le seul cas où l'actionnabilité fait basculer le verdict : ZÉRO exigence
  // actionnable. L'artefact ne route rien vers aucune étape aval.
  if (actionnables === 0) {
    problems.push('prisme.json: AUCUNE exigence actionnable (preuve attendue + destination valides) — l\'artefact ne route rien vers l\'aval');
  }

  const stats = {
    exigences: exigences.length,
    expected,
    additions,
    actionnables,
    non_actionnables: exigences.length - actionnables,
    references_ancrees: referencesAncrees,
    references_verifiees: referencesVerifiees,
    exigences_boucle: exigencesBoucle,
    exigences_sourcees_gm: exigencesSourceesGm,
  };
  const ok = problems.length === 0;
  return { ok, verdict: ok ? 'OK' : 'FAIL', problems, non_actionnables, references_non_ancrees, stats };
}

/**
 * Lit et vérifie un prisme.json sur disque. Ne lève jamais : un fichier absent,
 * vide ou non-JSON est un FAIL explicite avec sa raison.
 * @param {string} filePath
 * @param {string|null} worldscanPath
 * @returns {Promise<object>}
 */
export async function checkPrismeFile(filePath, worldscanPath = null) {
  const fail = (msg) => ({
    ok: false, verdict: 'FAIL', problems: [msg],
    non_actionnables: [], references_non_ancrees: [],
    stats: {
      exigences: 0, expected: 0, additions: 0, actionnables: 0, non_actionnables: 0,
      references_ancrees: 0, references_verifiees: 0, exigences_boucle: 0, exigences_sourcees_gm: 0,
    },
  });
  let raw;
  try {
    raw = await readFile(filePath, 'utf-8');
  } catch (err) {
    return fail(`${filePath}: absent ou illisible (${err.message})`);
  }
  if (raw.trim().length === 0) return fail(`${filePath}: present mais vide`);
  let doc;
  try {
    doc = JSON.parse(raw);
  } catch (err) {
    return fail(`${filePath}: JSON invalide (${err.message})`);
  }
  let worldscan = null;
  if (worldscanPath) {
    try {
      worldscan = JSON.parse(await readFile(worldscanPath, 'utf-8'));
    } catch (err) {
      return fail(`${worldscanPath}: World Scan illisible ou invalide (${err.message}) — sans lui l'ancrage des references ne peut pas etre verifie, on ne le pretend pas`);
    }
  }
  return checkPrismeDoc(doc, worldscan);
}

// ---- CLI ----
const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const argv = process.argv.slice(2);
  const positional = argv.filter((a) => !a.startsWith('--'));
  const wsIdx = argv.indexOf('--worldscan');
  const worldscanPath = wsIdx >= 0 ? argv[wsIdx + 1] : null;
  const target = positional.filter((p) => p !== worldscanPath)[0];

  if (!target) {
    console.error('usage: node check_prisme_manifest.mjs <prisme.json> [--worldscan <worldscan.json>] [--json]');
    process.exit(2);
  }

  (async () => {
    const r = await checkPrismeFile(target, worldscanPath);
    console.log(`VERDICT PRISME: ${r.verdict}`);
    r.problems.forEach((p) => console.error(`  FAIL: ${p}`));
    r.non_actionnables.forEach((p) => console.error(`  CLASSE non-actionnable: ${p}`));
    r.references_non_ancrees.forEach((p) => console.error(`  CLASSE reference non ancree: ${p}`));
    console.error(`  stats: ${r.stats.exigences} exigence(s) / ${r.stats.expected} EXPECTED / ${r.stats.additions} ADDITIONS / ${r.stats.actionnables} actionnable(s) / ${r.stats.references_ancrees} sur ${r.stats.references_verifiees} reference(s) ancree(s) / ${r.stats.exigences_sourcees_gm} sur ${r.stats.exigences_boucle} exigence(s) de boucle sourcee(s) GM`);
    console.log(JSON.stringify({
      ok: r.ok,
      problems: r.problems,
      non_actionnables: r.non_actionnables,
      references_non_ancrees: r.references_non_ancrees,
      stats: r.stats,
    }, null, 2));
    process.exit(r.ok ? 0 : 1);
  })();
}
