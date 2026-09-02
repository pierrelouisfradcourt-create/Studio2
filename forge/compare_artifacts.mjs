#!/usr/bin/env node
// compare_artifacts.mjs — COMPARATEUR d'artefacts amont : artefact de RÉFÉRENCE
// (produit par le worker connu-bon) vs artefact CANDIDAT (worker qu'on évalue).
//
// Problème qu'il résout : les oracles disent « conforme / non conforme ». Ils ne
// disent pas « ce candidat retrouve-t-il ce que la référence avait trouvé ». Sans
// cette seconde mesure, remplacer un worker par un autre est une préférence
// déguisée. Le comparateur est la vérité COMPARATIVE ; l'oracle reste la vérité
// MÉCANIQUE. Aucun des deux ne juge le style.
//
// TROIS ENSEMBLES, JAMAIS UN SCORE (arbitrage Pierre, 2026-08-04) :
//   CONVERGENCE — items appariés des deux côtés
//   LOSS        — présents chez la référence, absents chez le candidat
//   ADDITION    — présents chez le candidat seul (invention, bonne ou mauvaise)
// Puis des métriques SÉPARÉES (couverture · traçabilité · actionnabilité ·
// compatibilité). Volontairement AUCUN score agrégé : une composite s'optimise sans
// qu'on sache ce qu'on a amélioré.
//
// ORDRE D'ALIGNEMENT (imposé, dans cet ordre exact) :
//   1. `source_ref` identiques           -> apparié (align_mode: 'source_ref')
//   2. sinon, SI l'un des deux au moins n'a PAS de source_ref -> similarité de
//      Jaccard >= JACCARD_SEUIL          -> apparié (align_mode: 'texte')
//   3. sinon                             -> NON ALIGNÉ
// Deux items qui déclarent des provenances DIFFÉRENTES ne sont jamais rapprochés
// par ressemblance de texte : la similarité ne sert pas à INVENTER une
// correspondance que les provenances contredisent.
//
// Usage :
//   node compare_artifacts.mjs <type> <reference.json> <candidat.json> [--amont <amont.json>] [--json]
//   <type> = prisme | featuremap | blueprint | wiremap
// Exit 0 = comparaison produite · 1 = entrée illisible/invalide · 2 = usage.
// ATTENTION : l'exit code ne vaut PAS verdict de qualité. Le comparateur MESURE, il
// ne prononce ni OK ni FAIL — c'est le rôle des oracles et de HumanGate.
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  DESTINATIONS,
  JACCARD_SEUIL,
  isNonEmptyString,
  jaccard,
  normalizeText,
  collectLeaves,
  validateExpectedProof,
} from './upstream_schema.mjs';

export const TYPES = ['prisme', 'featuremap', 'blueprint', 'wiremap'];

/**
 * Projette un artefact d'un type donné en liste d'items comparables. Un item porte
 * toujours les mêmes 6 champs, quel que soit l'artefact d'origine — c'est ce qui
 * permet UN comparateur au lieu de quatre.
 *
 * @param {string} type prisme|featuremap|blueprint|wiremap
 * @param {object} doc artefact parsé
 * @returns {Array<{id:string, source_ref:string|null, provenance_declaree:boolean,
 *                  texte:string, expected_proof:unknown, cible:string|null, loc:string}>}
 */
export function itemsOf(type, doc) {
  if (type === 'prisme') {
    const ex = Array.isArray(doc?.exigences) ? doc.exigences : [];
    return ex.map((e, i) => ({
      id: isNonEmptyString(e?.id) ? e.id : `exigences[${i}]`,
      source_ref: isNonEmptyString(e?.reference) ? e.reference : null,
      // Une ADDITION avec `reference: null` EXPLICITE a une provenance déclarée
      // (invention assumée) — ce n'est pas la même chose qu'un champ omis.
      provenance_declaree: isNonEmptyString(e?.reference)
        || (e?.source === 'ADDITIONS' && e?.reference === null),
      texte: [e?.enonce, e?.claim, e?.observation].filter(isNonEmptyString).join(' '),
      expected_proof: e?.expected_proof,
      cible: isNonEmptyString(e?.destination) ? e.destination : null,
      loc: `exigences[${i}]`,
    }));
  }
  if (type === 'featuremap') {
    return collectLeaves(doc).map((entry) => ({
      id: isNonEmptyString(entry.leaf?.id) ? entry.leaf.id : entry.loc,
      source_ref: isNonEmptyString(entry.leaf?.source_ref) ? entry.leaf.source_ref : null,
      provenance_declaree: isNonEmptyString(entry.leaf?.source_ref),
      texte: [entry.leaf?.capacite, entry.feature].filter(isNonEmptyString).join(' '),
      expected_proof: entry.leaf?.expected_proof,
      cible: isNonEmptyString(entry.feature) ? entry.feature : null,
      loc: entry.loc,
    }));
  }
  if (type === 'blueprint') {
    const resp = Array.isArray(doc?.responsabilites) ? doc.responsabilites : [];
    return resp.map((r, i) => ({
      id: isNonEmptyString(r?.module) ? r.module : `responsabilites[${i}]`,
      source_ref: null, // un module ne cite pas de source externe : il COUVRE des features
      provenance_declaree: Array.isArray(r?.couvre) && r.couvre.length > 0,
      texte: [r?.responsabilite, ...(Array.isArray(r?.couvre) ? r.couvre : [])]
        .filter(isNonEmptyString).join(' '),
      expected_proof: r?.preuve_attendue,
      cible: Array.isArray(r?.couvre) && r.couvre.length > 0 ? r.couvre.join(',') : null,
      loc: `responsabilites[${i}]`,
    }));
  }
  if (type === 'wiremap') {
    const lines = Array.isArray(doc?.lines) ? doc.lines
      : (Array.isArray(doc?.features) ? doc.features : []);
    const key = Array.isArray(doc?.lines) ? 'lines' : 'features';
    return lines.map((l, i) => ({
      id: isNonEmptyString(l?.id) ? l.id : (isNonEmptyString(l?.feature) ? l.feature : `${key}[${i}]`),
      source_ref: isNonEmptyString(l?.reference) ? l.reference : null,
      provenance_declaree: Array.isArray(l?.couvre) && l.couvre.length > 0,
      texte: [l?.id, l?.feature, ...(Array.isArray(l?.couvre) ? l.couvre : [])]
        .filter(isNonEmptyString).join(' '),
      expected_proof: l?.expected_proof,
      cible: Array.isArray(l?.couvre) && l.couvre.length > 0 ? l.couvre.join(',') : null,
      loc: `${key}[${i}]`,
    }));
  }
  return [];
}

/**
 * Apparie deux listes d'items selon l'ordre d'alignement imposé.
 * @param {Array} ref
 * @param {Array} cand
 * @param {number} seuil
 * @returns {{paires:Array, refRestants:Array, candRestants:Array}}
 */
export function aligner(ref, cand, seuil = JACCARD_SEUIL) {
  const paires = [];
  const refPris = new Set();
  const candPris = new Set();

  // --- passe 1 : source_ref identiques (normalisées) ---
  const indexCand = new Map();
  cand.forEach((c, j) => {
    if (c.source_ref === null) return;
    const k = normalizeText(c.source_ref);
    if (!indexCand.has(k)) indexCand.set(k, []);
    indexCand.get(k).push(j);
  });
  ref.forEach((r, i) => {
    if (r.source_ref === null) return;
    const libres = (indexCand.get(normalizeText(r.source_ref)) || []).filter((j) => !candPris.has(j));
    if (libres.length === 0) return;
    const j = libres[0];
    refPris.add(i);
    candPris.add(j);
    paires.push({ ref: r, cand: cand[j], align_mode: 'source_ref', similarite: null });
  });

  // --- passe 2 : similarité de texte, UNIQUEMENT si l'un des deux au moins n'a
  // pas de source_ref. Deux provenances déclarées et différentes ne sont jamais
  // rapprochées par le texte. ---
  const candidatsPasse2 = [];
  ref.forEach((r, i) => {
    if (refPris.has(i)) return;
    cand.forEach((c, j) => {
      if (candPris.has(j)) return;
      if (r.source_ref !== null && c.source_ref !== null) return; // provenances contradictoires
      const s = jaccard(r.texte, c.texte);
      if (s >= seuil) candidatsPasse2.push({ i, j, s });
    });
  });
  // Appariement glouton par similarité décroissante — déterministe (tri stable sur
  // (s, i, j)), jamais dépendant de l'ordre d'itération.
  candidatsPasse2.sort((a, b) => (b.s - a.s) || (a.i - b.i) || (a.j - b.j));
  for (const { i, j, s } of candidatsPasse2) {
    if (refPris.has(i) || candPris.has(j)) continue;
    refPris.add(i);
    candPris.add(j);
    paires.push({ ref: ref[i], cand: cand[j], align_mode: 'texte', similarite: Number(s.toFixed(3)) });
  }

  return {
    paires,
    refRestants: ref.filter((_, i) => !refPris.has(i)),
    candRestants: cand.filter((_, j) => !candPris.has(j)),
  };
}

/**
 * Métriques d'un côté (référence OU candidat), calculées à l'identique des deux
 * côtés — la référence n'est jamais supposée parfaite, elle est mesurée aussi.
 * @param {string} type
 * @param {Array} items
 * @param {Set<string>|null} idsAmont ids de l'artefact amont, si fourni
 * @returns {object}
 */
export function metriques(type, items, idsAmont = null) {
  const n = items.length;
  const part = (k) => (n === 0 ? 0 : Number((k / n).toFixed(3)));

  let tracables = 0;
  let actionnables = 0;
  let compatibles = 0;
  let resolus = 0;

  for (const it of items) {
    if (it.provenance_declaree) tracables += 1;
    const proofOk = validateExpectedProof(it.expected_proof, 'x').length === 0;
    const destOk = type === 'prisme' ? DESTINATIONS.includes(it.cible) : true;
    if (proofOk && destOk) actionnables += 1;
    if (type === 'prisme') {
      if (DESTINATIONS.includes(it.cible)) compatibles += 1;
    } else if (isNonEmptyString(it.cible)) {
      compatibles += 1;
    }
    if (idsAmont && it.source_ref !== null && idsAmont.has(it.source_ref)) resolus += 1;
  }

  return {
    items: n,
    tracabilite: part(tracables),
    actionnabilite: part(actionnables),
    compatibilite: part(compatibles),
    // `null` et non `0` quand aucun amont n'a été fourni : on ne prétend pas avoir
    // vérifié une résolution qu'on n'a pas pu faire.
    resolution: idsAmont ? part(resolus) : null,
  };
}

/**
 * Ids résolvables d'un artefact amont (celui que le candidat est censé citer).
 * @param {object|null} amont
 * @returns {Set<string>|null}
 */
export function idsAmontDe(amont) {
  if (!amont || typeof amont !== 'object') return null;
  const out = new Set();
  if (Array.isArray(amont.exigences)) {
    for (const e of amont.exigences) if (isNonEmptyString(e?.id)) out.add(e.id);
  }
  for (const entry of collectLeaves(amont)) {
    if (isNonEmptyString(entry.leaf?.id)) out.add(entry.leaf.id);
  }
  return out.size > 0 ? out : null;
}

/**
 * Comparaison complète référence vs candidat.
 * @param {string} type
 * @param {object} refDoc
 * @param {object} candDoc
 * @param {object|null} amontDoc
 * @param {number} seuil
 * @returns {object}
 */
export function comparer(type, refDoc, candDoc, amontDoc = null, seuil = JACCARD_SEUIL) {
  const ref = itemsOf(type, refDoc);
  const cand = itemsOf(type, candDoc);
  const idsAmont = idsAmontDe(amontDoc);
  const { paires, refRestants, candRestants } = aligner(ref, cand, seuil);

  const convergence = paires.map((p) => ({
    reference: p.ref.id,
    candidat: p.cand.id,
    align_mode: p.align_mode,
    similarite: p.similarite,
  }));
  const loss = refRestants.map((r) => ({ id: r.id, loc: r.loc, source_ref: r.source_ref, texte: r.texte }));
  const addition = candRestants.map((c) => ({
    id: c.id,
    loc: c.loc,
    source_ref: c.source_ref,
    texte: c.texte,
    // Une addition qui ne déclare AUCUNE provenance est une invention non déclarée
    // — distincte d'une addition assumée (ADDITIONS/reference:null).
    provenance_declaree: c.provenance_declaree,
  }));

  return {
    type,
    convergence,
    loss,
    addition,
    couverture: ref.length === 0 ? null : Number((convergence.length / ref.length).toFixed(3)),
    metriques: {
      reference: metriques(type, ref, idsAmont),
      candidat: metriques(type, cand, idsAmont),
    },
    alignement: {
      par_source_ref: convergence.filter((c) => c.align_mode === 'source_ref').length,
      par_texte: convergence.filter((c) => c.align_mode === 'texte').length,
      non_aligne_reference: loss.length,
      non_aligne_candidat: addition.length,
      seuil_jaccard: seuil,
    },
    amont_fourni: idsAmont !== null,
    score_agrege: null, // volontairement absent — cf. en-tête
  };
}

/**
 * Charge un JSON. Retourne {doc} ou {err} — ne lève jamais.
 * @param {string} p
 * @param {string} label
 * @returns {Promise<{doc?:object, err?:string}>}
 */
async function charger(p, label) {
  let raw;
  try {
    raw = await readFile(p, 'utf-8');
  } catch (err) {
    return { err: `${label} ${p}: absent ou illisible (${err.message})` };
  }
  if (raw.trim().length === 0) return { err: `${label} ${p}: present mais vide` };
  try {
    return { doc: JSON.parse(raw) };
  } catch (err) {
    return { err: `${label} ${p}: JSON invalide (${err.message})` };
  }
}

/**
 * Comparaison depuis des chemins sur disque.
 * @param {string} type
 * @param {string} refPath
 * @param {string} candPath
 * @param {string|null} amontPath
 * @returns {Promise<{ok:boolean, erreurs:string[], rapport:object|null}>}
 */
export async function comparerFichiers(type, refPath, candPath, amontPath = null) {
  if (!TYPES.includes(type)) {
    return { ok: false, erreurs: [`type inconnu '${type}' (attendu: ${TYPES.join('|')})`], rapport: null };
  }
  const r = await charger(refPath, 'reference');
  if (r.err) return { ok: false, erreurs: [r.err], rapport: null };
  const c = await charger(candPath, 'candidat');
  if (c.err) return { ok: false, erreurs: [c.err], rapport: null };
  let amont = null;
  if (amontPath) {
    const a = await charger(amontPath, 'amont');
    if (a.err) return { ok: false, erreurs: [a.err], rapport: null };
    amont = a.doc;
  }
  return { ok: true, erreurs: [], rapport: comparer(type, r.doc, c.doc, amont) };
}

// ---- CLI ----
const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const argv = process.argv.slice(2);
  const amIdx = argv.indexOf('--amont');
  const amontPath = amIdx >= 0 ? argv[amIdx + 1] : null;
  const pos = argv.filter((a) => !a.startsWith('--') && a !== amontPath);

  if (pos.length < 3) {
    console.error('usage: node compare_artifacts.mjs <prisme|featuremap|blueprint|wiremap> <reference.json> <candidat.json> [--amont <amont.json>] [--json]');
    process.exit(2);
  }

  (async () => {
    const { ok, erreurs, rapport } = await comparerFichiers(pos[0], pos[1], pos[2], amontPath);
    if (!ok) {
      erreurs.forEach((e) => console.error(`  ERREUR: ${e}`));
      process.exit(1);
    }
    const m = rapport.metriques;
    console.log(`COMPARAISON ${rapport.type} — reference vs candidat (AUCUN verdict de qualite ici)`);
    console.log(`  CONVERGENCE ${rapport.convergence.length}  (source_ref ${rapport.alignement.par_source_ref} / texte ${rapport.alignement.par_texte}, seuil ${rapport.alignement.seuil_jaccard})`);
    console.log(`  LOSS        ${rapport.loss.length}  (presents chez la reference, absents chez le candidat)`);
    console.log(`  ADDITION    ${rapport.addition.length}  (dont ${rapport.addition.filter((a) => !a.provenance_declaree).length} sans provenance declaree)`);
    console.log(`  couverture  ${rapport.couverture}`);
    console.log(`  metriques   reference: tracabilite ${m.reference.tracabilite} · actionnabilite ${m.reference.actionnabilite} · compatibilite ${m.reference.compatibilite} · resolution ${m.reference.resolution}`);
    console.log(`              candidat : tracabilite ${m.candidat.tracabilite} · actionnabilite ${m.candidat.actionnabilite} · compatibilite ${m.candidat.compatibilite} · resolution ${m.candidat.resolution}`);
    console.log(JSON.stringify(rapport, null, 2));
    process.exit(0);
  })();
}
