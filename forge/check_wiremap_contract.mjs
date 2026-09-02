#!/usr/bin/env node
// check_wiremap_contract.mjs — oracle d'AVANT-BUILD de l'étape s5-wiremap.
//
// ┌──────────────────────────────────────────────────────────────────────────────┐
// │ DEUX MOMENTS, DEUX ORACLES (arbitrage Pierre, 2026-08-04)                    │
// │  AVANT build : la WireMap est un CONTRAT — couvre-t-elle le plan ?   <- ICI  │
// │  APRÈS build : la WireMap est une PREUVE — correspond-elle au code ?         │
// │                -> forge.static_oracles.check_wiremap, INTOUCHÉ (oracle s10c).│
// └──────────────────────────────────────────────────────────────────────────────┘
//
// `check_wiremap` vérifie que chaque feature pointe des fichiers qui EXISTENT et
// des fonctions qui sont DÉFINIES. En amont, aucun fichier n'est écrit : cet oracle
// ne peut structurellement rien dire d'utile avant le build. Ici on pose l'autre
// question, celle qu'aucun oracle ne posait : la carte couvre-t-elle la décompo ?
//
// PÉRIMÈTRE STRICT — ce que cet oracle NE fait PAS, et pourquoi :
//   - les règles d'ÉTAT de ligne (REQUIRED/IMPLEMENTED/NOT_APPLICABLE/DEFERRED,
//     source_role obligatoire sur EXPECTED/ADDITIONS, reference sur EXPECTED) sont
//     déjà validées par forge.standard_oracles.check_line_states. Les redupliquer
//     ici créerait deux vérités concurrentes sur la même règle.
//   - le placement (system_parent désigne-t-il un système réel) appartient à
//     check_placement.
// Il ne reste, et c'est exactement le trou mesuré : la COUVERTURE featuremap -> wiremap.
//
// Usage :
//   node check_wiremap_contract.mjs <wiremap.json> --featuremap <featuremap.json> [--json]
// Exit 0 = OK · 1 = FAIL · 2 = usage.
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { isNonEmptyString, collectLeaves } from './upstream_schema.mjs';

const EMPTY_STATS = {
  lignes: 0, schema: 'inconnu', capacites: 0, capacites_couvertes: 0, lignes_sans_couvre: 0,
  affordances: 0, affordances_liees: 0,
};

// V4 GAME LOOP (2026-08-22, GO Pierre) — liaison affordance -> input -> systeme
// -> effet, verifiee par RESOLUTION D'IDS (aucun champ nouveau) : toute ligne
// dont `provides` contient `affordance:<x>` doit avoir un `requires` non vide qui
// resout (directement, ou transitivement via une chaine de `requires`, profondeur
// <= 3) une ligne dont le `couvre` porte une feuille d'EFFET (file_write|visual)
// de la MEME exigence (source_ref) que la feuille d'ENTREE couverte par la ligne
// d'affordance elle-meme.
const AFFORDANCE_PREFIX = 'affordance:';
const EFFECT_KINDS = ['file_write', 'visual'];
const MAX_DEPTH = 3;

/**
 * Vrai si `p` designe une affordance (`affordance:<x>`).
 * @param {unknown} p
 * @returns {boolean}
 */
function estAffordance(p) {
  return typeof p === 'string' && p.startsWith(AFFORDANCE_PREFIX) && p.length > AFFORDANCE_PREFIX.length;
}

/**
 * Cherche, a partir d'une liste de capacites `requires`, si une ligne atteignable
 * (resolution par `provides`, profondeur <= MAX_DEPTH) `couvre` une feuille
 * d'EFFET portant le meme `source_ref` que la feuille d'ENTREE de l'affordance.
 * @param {Array<{obj:object, loc:string}>} lignes toutes les lignes de la wiremap
 * @param {string[]} requires capacites requises par la ligne courante
 * @param {string} sourceRef source_ref de la feuille d'entree a retrouver en aval
 * @param {Map<string,string>} effectSourceRefById id de feuille EFFET -> son source_ref
 * @param {number} depth profondeur courante
 * @param {Set<object>} visited lignes deja visitees (evite les cycles)
 * @returns {boolean}
 */
function atteintEffetMemeExigence(lignes, requires, sourceRef, effectSourceRefById, depth, visited) {
  if (depth > MAX_DEPTH || !Array.isArray(requires) || requires.length === 0) return false;
  for (const cap of requires) {
    if (!isNonEmptyString(cap)) continue;
    for (const { obj } of lignes) {
      if (visited.has(obj)) continue;
      if (!Array.isArray(obj?.provides) || !obj.provides.includes(cap)) continue;
      visited.add(obj);
      const couvre = Array.isArray(obj.couvre) ? obj.couvre : [];
      const relie = couvre.some((c) => effectSourceRefById.get(c) === sourceRef);
      if (relie) return true;
      if (atteintEffetMemeExigence(lignes, obj.requires, sourceRef, effectSourceRefById, depth + 1, visited)) {
        return true;
      }
    }
  }
  return false;
}

/**
 * Extrait les lignes d'une WireMap, quel que soit son schéma : v2 (`lines`, standard
 * SCHEMA.md §3) ou v1 (`features`, forme historique consommée par check_wiremap).
 * Ne convertit rien — retourne les objets tels quels avec leur localisation.
 * @param {object} doc
 * @returns {{schema:'v2'|'v1'|'inconnu', lignes:Array<{obj:object, loc:string}>}}
 */
export function extraireLignes(doc) {
  if (Array.isArray(doc?.lines)) {
    return { schema: 'v2', lignes: doc.lines.map((obj, i) => ({ obj, loc: `lines[${i}]` })) };
  }
  if (Array.isArray(doc?.features)) {
    return { schema: 'v1', lignes: doc.features.map((obj, i) => ({ obj, loc: `features[${i}]` })) };
  }
  return { schema: 'inconnu', lignes: [] };
}

/**
 * Oracle complet sur une WireMap déjà parsée, confrontée à la featuremap qu'elle
 * doit couvrir.
 * @param {unknown} doc wiremap.json
 * @param {unknown} featuremap featuremap.json
 * @returns {object}
 */
export function checkWiremapContractDoc(doc, featuremap) {
  const problems = [];
  const capacites_non_couvertes = [];
  const couverture_fantome = [];

  if (doc === null || typeof doc !== 'object' || Array.isArray(doc)) {
    return {
      ok: false, verdict: 'FAIL', problems: ['wiremap.json: doit etre un objet'],
      capacites_non_couvertes, couverture_fantome, maillon_non_lie: [], stats: EMPTY_STATS,
    };
  }

  const { schema, lignes } = extraireLignes(doc);
  if (schema === 'inconnu') {
    problems.push("wiremap.json: ni `lines[]` (schema v2) ni `features[]` (schema v1) — aucune ligne a confronter au plan");
  }
  if (lignes.length === 0 && schema !== 'inconnu') {
    problems.push(`wiremap.json.${schema === 'v2' ? 'lines' : 'features'}: tableau vide`);
  }

  const feuilles = collectLeaves(featuremap);
  const capaciteIds = new Set(
    feuilles.filter((e) => isNonEmptyString(e.leaf?.id)).map((e) => e.leaf.id),
  );
  if (capaciteIds.size === 0) {
    problems.push('featuremap: aucune capacite identifiee — la couverture ne peut pas etre verifiee (ni sautee en silence)');
  }

  const couverts = new Set();
  let sansCouvre = 0;

  for (const { obj, loc } of lignes) {
    if (obj === null || typeof obj !== 'object' || Array.isArray(obj)) {
      problems.push(`${loc}: doit etre un objet`);
      continue;
    }
    if (!Array.isArray(obj.couvre) || obj.couvre.length === 0) {
      sansCouvre += 1;
      problems.push(
        `${loc}.couvre: tableau NON VIDE d'ids de capacites requis — `
        + "une ligne de wiremap qui ne declare pas ce qu'elle realise rend le delta plan/carte incalculable",
      );
      continue;
    }
    for (const c of obj.couvre) {
      if (!isNonEmptyString(c)) {
        problems.push(`${loc}.couvre: entree vide`);
      } else if (!capaciteIds.has(c)) {
        couverture_fantome.push(`${loc}.couvre: '${c}' ne resout aucune capacite de la featuremap`);
      } else {
        couverts.add(c);
      }
    }
  }

  for (const id of capaciteIds) {
    if (!couverts.has(id)) {
      capacites_non_couvertes.push(`capacite '${id}' de la featuremap n'est portee par aucune ligne de wiremap (omission silencieuse)`);
    }
  }

  // V4 GAME LOOP — liaison affordance -> input -> systeme -> effet, verifiee par
  // resolution d'ids (voir atteintEffetMemeExigence). `couvre` (deja valide plus
  // haut) donne la feuille d'ENTREE de la ligne d'affordance ; on cherche en aval
  // une feuille d'EFFET de la MEME exigence.
  const maillon_non_lie = [];
  const sourceRefById = new Map(
    feuilles.filter((e) => isNonEmptyString(e.leaf?.id)).map((e) => [e.leaf.id, e.leaf?.source_ref]),
  );
  const effectSourceRefById = new Map(
    feuilles
      .filter((e) => isNonEmptyString(e.leaf?.id) && EFFECT_KINDS.includes(e.leaf?.expected_proof?.kind))
      .map((e) => [e.leaf.id, e.leaf.source_ref]),
  );

  let affordances = 0;
  let affordancesLiees = 0;

  for (const { obj, loc } of lignes) {
    if (obj === null || typeof obj !== 'object' || Array.isArray(obj)) continue;
    if (!Array.isArray(obj.provides)) continue;
    const affordance = obj.provides.find(estAffordance);
    if (!affordance) continue;
    affordances += 1;

    const couvre = Array.isArray(obj.couvre) ? obj.couvre : [];
    const sourceRefs = [...new Set(
      couvre.map((c) => sourceRefById.get(c)).filter(isNonEmptyString),
    )];
    const nom = affordance.slice(AFFORDANCE_PREFIX.length);

    if (!Array.isArray(obj.requires) || obj.requires.length === 0) {
      maillon_non_lie.push(`${loc}: affordance '${nom}' n'atteint aucune regle (requires vide)`);
      continue;
    }
    if (sourceRefs.length === 0) {
      maillon_non_lie.push(`${loc}: affordance '${nom}' n'atteint aucune regle (couvre ne resout aucune feuille d'entree)`);
      continue;
    }

    const visited = new Set([obj]);
    const relie = sourceRefs.some(
      (ref) => atteintEffetMemeExigence(lignes, obj.requires, ref, effectSourceRefById, 1, visited),
    );
    if (relie) {
      affordancesLiees += 1;
    } else {
      maillon_non_lie.push(
        `${loc}: affordance '${nom}' n'atteint aucune regle (requires ne mene, en profondeur <= ${MAX_DEPTH}, `
        + "a aucune ligne dont 'couvre' porte une feuille d'effet de la meme exigence)",
      );
    }
  }

  const stats = {
    lignes: lignes.length,
    schema,
    capacites: capaciteIds.size,
    affordances,
    affordances_liees: affordancesLiees,
    capacites_couvertes: couverts.size,
    lignes_sans_couvre: sansCouvre,
  };

  const all = [...problems, ...capacites_non_couvertes, ...couverture_fantome, ...maillon_non_lie];
  const ok = all.length === 0;
  return {
    ok, verdict: ok ? 'OK' : 'FAIL', problems, capacites_non_couvertes, couverture_fantome, maillon_non_lie, stats,
  };
}

/**
 * Lit wiremap + featuremap sur disque et applique l'oracle. Ne lève jamais.
 * @param {string} wiremapPath
 * @param {string} featuremapPath
 * @returns {Promise<object>}
 */
export async function checkWiremapContractFiles(wiremapPath, featuremapPath) {
  const fail = (msg) => ({
    ok: false, verdict: 'FAIL', problems: [msg],
    capacites_non_couvertes: [], couverture_fantome: [], maillon_non_lie: [], stats: EMPTY_STATS,
  });
  const load = async (p, label) => {
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
  };
  const wm = await load(wiremapPath, 'wiremap');
  if (wm.err) return fail(wm.err);
  const fm = await load(featuremapPath, 'featuremap');
  if (fm.err) return fail(fm.err);
  return checkWiremapContractDoc(wm.doc, fm.doc);
}

// ---- CLI ----
const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const argv = process.argv.slice(2);
  const fmIdx = argv.indexOf('--featuremap');
  const fmPath = fmIdx >= 0 ? argv[fmIdx + 1] : null;
  const target = argv.filter((a) => !a.startsWith('--') && a !== fmPath)[0];

  if (!target || !fmPath) {
    console.error('usage: node check_wiremap_contract.mjs <wiremap.json> --featuremap <featuremap.json> [--json]');
    process.exit(2);
  }

  (async () => {
    const r = await checkWiremapContractFiles(target, fmPath);
    console.log(`VERDICT WIREMAP (contrat, avant build): ${r.verdict}`);
    r.problems.forEach((p) => console.error(`  FAIL: ${p}`));
    r.capacites_non_couvertes.forEach((p) => console.error(`  FAIL couverture: ${p}`));
    r.couverture_fantome.forEach((p) => console.error(`  FAIL couverture fantome: ${p}`));
    r.maillon_non_lie.forEach((p) => console.error(`  FAIL maillon: ${p}`));
    console.error(`  stats: schema ${r.stats.schema} / ${r.stats.lignes} ligne(s) / ${r.stats.capacites_couvertes} sur ${r.stats.capacites} capacite(s) couverte(s) / ${r.stats.affordances_liees} sur ${r.stats.affordances} affordance(s) liee(s)`);
    console.log(JSON.stringify({
      ok: r.ok,
      problems: r.problems,
      capacites_non_couvertes: r.capacites_non_couvertes,
      couverture_fantome: r.couverture_fantome,
      maillon_non_lie: r.maillon_non_lie,
      stats: r.stats,
    }, null, 2));
    process.exit(r.ok ? 0 : 1);
  })();
}
