#!/usr/bin/env node
// cross_field_quality.mjs — ORACLE QUALITY LAYER V2 : détection des DÉPLACEMENTS de
// défaut, c'est-à-dire des contaminations d'un champ par un AUTRE champ.
//
// LE DÉFAUT QU'IL VISE (mesuré le 2026-08-04, en réparant) : la réparation d'une
// discriminance sur `games[1].victory_condition` a produit « Survivre et éliminer les
// autres joueurs » — mot pour mot le `player_goal` de `games[0]`. Le signal était
// satisfait, le défaut avait seulement changé d'adresse. `oracle_quality.mjs` ne
// pouvait pas le voir : il compare le MÊME champ entre entrées, jamais deux champs
// DIFFÉRENTS.
//
// AUCUN LLM, aucune interprétation : normalisation, tokenisation, similarité, seuils
// déclarés. Chaque signal est recalculable à la main.
//
// DIFFICULTÉ CENTRALE, ET RAISON DES 4 STRATÉGIES : dans BEAUCOUP de jeux,
// `player_goal` et `victory_condition` se ressemblent LÉGITIMEMENT — à Bomberman, le
// but du joueur EST d'être le dernier en vie. Une règle « ces deux champs ne doivent
// jamais se ressembler » produirait donc des fausses alertes sur des artefacts justes.
// C'est la calibration qui tranche, pas l'intuition : une stratégie qui crie sur une
// référence valide est rejetée, quelle que soit son élégance.
//
// Usage : node cross_field_quality.mjs <artefact.json> [--strategie A|B|C|D]

import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { normalizeText, jaccard } from './upstream_schema.mjs';
import { feuillesTexte, estChampDeSens } from './oracle_quality.mjs';

// Seuil de similarité pour les stratégies qui en utilisent un. Déclaré ici, reporté
// dans chaque signal : une mesure dont le seuil est invisible n'est pas relisible.
export const SEUIL_CROISE = 0.7;

/**
 * Paires de champs déclarées INCOMPATIBLES : deux rôles qui ne peuvent pas être
 * remplis par la même phrase sans perte d'information. Utilisé par la stratégie D.
 *
 * `retention_answer` (ce qui fait REVENIR) n'est ni un objectif ni une condition de
 * fin : les confondre est toujours une perte. En revanche `player_goal` et
 * `victory_condition` ne sont PAS listés comme incompatibles à l'intérieur d'une même
 * entrée — ils coïncident légitimement dans de nombreux genres.
 */
export const PAIRES_INCOMPATIBLES = [
  ['player_goal', 'retention_answer'],
  ['victory_condition', 'retention_answer'],
  ['defeat_condition', 'retention_answer'],
  ['victory_condition', 'defeat_condition'],
];

/**
 * Nom court d'un champ depuis son chemin. `games[1].objectives[0].player_goal` ->
 * `player_goal`.
 * @param {string} chemin
 * @returns {string}
 */
export function nomDeChamp(chemin) {
  return chemin.split('.').pop().replace(/\[\d+\]$/, '');
}

/**
 * Index de l'entrée racine à laquelle appartient un chemin (`games[1]...` -> 1).
 * Rend `null` hors d'un tableau racine.
 * @param {string} chemin
 * @returns {number|null}
 */
export function entreeDe(chemin) {
  const m = chemin.match(/^[A-Za-z_]\w*\[(\d+)\]/);
  return m ? Number(m[1]) : null;
}

/**
 * Toutes les paires de champs de sens comparables (noms de champ DIFFÉRENTS).
 * @param {object} artefact
 * @returns {Array<{a:object, b:object}>}
 */
export function pairesCroisees(artefact) {
  const f = feuillesTexte(artefact).filter((x) => estChampDeSens(x.chemin));
  const out = [];
  for (let i = 0; i < f.length; i += 1) {
    for (let j = i + 1; j < f.length; j += 1) {
      if (nomDeChamp(f[i].chemin) === nomDeChamp(f[j].chemin)) continue; // même champ = oracle_quality V1
      out.push({ a: f[i], b: f[j] });
    }
  }
  return out;
}

const signal = (a, b, detail, strategie) => ({
  signal: 'WARNING_CROSS_FIELD_COPY',
  strategie,
  chemins: [a.chemin, b.chemin],
  champs: [nomDeChamp(a.chemin), nomDeChamp(b.chemin)],
  detail,
});

/**
 * M-Q5-A — ÉGALITÉ NORMALISÉE, entre entrées DIFFÉRENTES uniquement.
 *
 * À l'intérieur d'une même entrée, deux champs peuvent légitimement coïncider (le but
 * du joueur EST la condition de victoire dans un versus). D'une entrée à l'autre, en
 * revanche, un champ qui reprend mot pour mot un AUTRE champ d'une AUTRE entrée ne
 * décrit plus l'entrée à laquelle il appartient : c'est une contamination.
 * @param {object} artefact
 * @returns {Array}
 */
export function strategieA(artefact) {
  const out = [];
  for (const { a, b } of pairesCroisees(artefact)) {
    const ea = entreeDe(a.chemin);
    const eb = entreeDe(b.chemin);
    if (ea === null || eb === null || ea === eb) continue;
    if (normalizeText(a.valeur) !== normalizeText(b.valeur)) continue;
    out.push(signal(a, b, `'${nomDeChamp(b.chemin)}' de l entree ${eb} reprend MOT POUR MOT `
      + `le '${nomDeChamp(a.chemin)}' de l entree ${ea} — le champ ne decrit plus son entree`, 'A'));
  }
  return out;
}

/**
 * M-Q5-B — SIMILARITÉ DE JACCARD entre entrées différentes, seuil déclaré.
 * @param {object} artefact
 * @param {number} seuil
 * @returns {Array}
 */
export function strategieB(artefact, seuil = SEUIL_CROISE) {
  const out = [];
  for (const { a, b } of pairesCroisees(artefact)) {
    const ea = entreeDe(a.chemin);
    const eb = entreeDe(b.chemin);
    if (ea === null || eb === null || ea === eb) continue;
    const s = jaccard(a.valeur, b.valeur);
    if (s < seuil) continue;
    out.push(signal(a, b, `recouvrement ${s.toFixed(3)} >= ${seuil} entre '${nomDeChamp(a.chemin)}' `
      + `(entree ${ea}) et '${nomDeChamp(b.chemin)}' (entree ${eb})`, 'B'));
  }
  return out;
}

/**
 * M-Q5-C — CHAMPS FRÈRES uniquement (même conteneur), égalité normalisée.
 * @param {object} artefact
 * @returns {Array}
 */
export function strategieC(artefact) {
  const out = [];
  for (const { a, b } of pairesCroisees(artefact)) {
    const pa = a.chemin.slice(0, a.chemin.lastIndexOf('.'));
    const pb = b.chemin.slice(0, b.chemin.lastIndexOf('.'));
    if (pa !== pb) continue;
    if (normalizeText(a.valeur) !== normalizeText(b.valeur)) continue;
    out.push(signal(a, b, `deux champs FRERES identiques dans ${pa}`, 'C'));
  }
  return out;
}

/**
 * M-Q5-D — GRAPHE DE RÔLES : uniquement les paires déclarées incompatibles, quelle que
 * soit l'entrée, avec seuil de similarité.
 * @param {object} artefact
 * @param {number} seuil
 * @returns {Array}
 */
export function strategieD(artefact, seuil = SEUIL_CROISE) {
  const interdit = new Set(PAIRES_INCOMPATIBLES.map((p) => [...p].sort().join('|')));
  const out = [];
  for (const { a, b } of pairesCroisees(artefact)) {
    const cle = [nomDeChamp(a.chemin), nomDeChamp(b.chemin)].sort().join('|');
    if (!interdit.has(cle)) continue;
    const s = jaccard(a.valeur, b.valeur);
    if (s < seuil) continue;
    out.push(signal(a, b, `roles incompatibles (${cle}) remplis par la meme phrase, `
      + `recouvrement ${s.toFixed(3)} >= ${seuil}`, 'D'));
  }
  return out;
}

export const STRATEGIES = { A: strategieA, B: strategieB, C: strategieC, D: strategieD };

// Stratégies ACTIVES par défaut — décidées par la calibration du 2026-08-04, jamais
// par préférence :
//   A : 0 faux positif sur 12 artefacts connus-bons, 1 vrai positif (le déplacement
//       réellement mesuré). Aucun seuil à régler.
//   B : mêmes chiffres, mais introduit un seuil sans gagner un seul vrai positif de
//       plus sur cet échantillon -> disponible, PAS active (un risque non payé).
//   C, D : 0 faux positif MAIS 0 vrai positif — aveugles au seul défaut observé.
//       Conservées parce qu'elles coûtent zéro, jamais activées sans mesure.
export const STRATEGIES_ACTIVES = ['A'];

/**
 * Désigne, dans une paire contaminée, qui est la SOURCE (à protéger) et qui est la
 * CIBLE (à régénérer).
 *
 * Règle : la contamination va de l'entrée déjà écrite vers celle écrite ensuite. La
 * cible est donc celle dont l'index d'entrée est le plus GRAND ; à index égal, la
 * seconde du couple. Se tromper de sens ferait réécrire la valeur d'origine — on
 * détruirait la seule des deux qui était peut-être juste.
 * @param {object} signal
 * @returns {{source:string, target:string}}
 */
export function cibleEtSource(signal) {
  const [x, y] = signal.chemins;
  const ex = entreeDe(x);
  const ey = entreeDe(y);
  if (ex !== null && ey !== null && ey < ex) return { source: y, target: x };
  return { source: x, target: y };
}

/**
 * Prompt de réparation d'une contamination inter-champs. Format imposé :
 * DEFECT_CLASS / SOURCE / TARGET / ACTION.
 *
 * La SOURCE est CITÉE mais déclarée intouchable : le modèle doit savoir de quoi il
 * doit s'éloigner. Ne pas la lui montrer reviendrait à lui demander d'éviter une
 * phrase qu'il ne connaît pas.
 * @param {object} signal
 * @param {{source:string, target:string}} roles
 * @param {unknown} valeurSource
 * @param {object} voisins contexte du champ cible
 * @returns {string}
 */
export function promptReparationCroisee(signal, roles, valeurSource, voisins) {
  return [
    'Un contrôle mécanique a détecté qu\'un champ a été contaminé par un AUTRE champ,',
    'appartenant à une autre entrée. Le défaut n\'a pas disparu : il a changé d\'adresse.',
    '\nDEFECT_CLASS:\ncross_field_copy',
    `\nSOURCE (intouchable — c'est elle qui est à sa place) :\n${roles.source}\n"${valeurSource}"`,
    `\nTARGET (le champ à réécrire) :\n${roles.target}`,
    `\nRAISON:\n${signal.detail}`,
    `\nVALID_CONTEXT (ce que TARGET doit décrire) :\n${JSON.stringify(voisins, null, 1)}`,
    '\nACTION:\nregenerate TARGET only',
    '\nFORBIDDEN:',
    '- ne reprends pas la phrase de SOURCE, même reformulée',
    `- ne touche pas à ${roles.source}, ni à aucun autre chemin`,
    `- écris ce qui est PROPRE au rôle « ${nomDeChamp(roles.target)} » de CETTE entrée`,
    '\nRends EXACTEMENT cet objet, et rien d\'autre :',
    '```json',
    '{ "path": "<TARGET, à l\'identique>", "value": "<la nouvelle valeur>" }',
    '```',
  ].join('\n');
}

/**
 * Mesure croisée. `strategies` liste les stratégies ACTIVES — seules celles dont la
 * calibration a montré 0 faux positif sur les artefacts connus-bons y figurent par
 * défaut.
 *
 * Verdict `WARNING_CROSS_FIELD_COPY` et jamais `FAIL` : tant que le taux de fausse
 * alerte n'est pas ratifié, ce signal informe, il ne condamne pas.
 * @param {object} artefact
 * @param {string[]} strategies
 * @returns {{verdict:'PASS'|'WARNING_CROSS_FIELD_COPY', signaux:Array, compte:object}}
 */
export function mesurerCroise(artefact, strategies = ['A']) {
  const signaux = strategies.flatMap((s) => (STRATEGIES[s] ? STRATEGIES[s](artefact) : []));
  const compte = signaux.reduce((a, s) => { a[s.strategie] = (a[s.strategie] || 0) + 1; return a; }, {});
  return {
    verdict: signaux.length === 0 ? 'PASS' : 'WARNING_CROSS_FIELD_COPY',
    signaux,
    compte,
    bloquant: false, // jamais un FAIL en V2 — cf. en-tête
  };
}

// ---- CLI ----
const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const argv = process.argv.slice(2);
  const iS = argv.indexOf('--strategie');
  const strategies = iS >= 0 ? argv[iS + 1].split(',') : ['A'];
  const cible = argv.find((a, i) => !a.startsWith('--') && argv[i - 1] !== '--strategie');
  if (!cible) {
    console.error('usage: node cross_field_quality.mjs <artefact.json> [--strategie A|B|C|D]');
    process.exitCode = 2;
  } else {
    (async () => {
      let doc;
      try {
        doc = JSON.parse(await readFile(cible, 'utf-8'));
      } catch (err) {
        console.error(`FAIL: ${cible} illisible (${err.message})`);
        process.exitCode = 1;
        return;
      }
      const r = mesurerCroise(doc, strategies);
      console.log(`CROSS_FIELD: ${r.verdict}  (strategies ${strategies.join(',')} — ADVISORY)`);
      for (const s of r.signaux) console.error(`  [${s.strategie}] ${s.chemins.join(' <- ')}\n      ${s.detail}`);
      console.log(JSON.stringify(r, null, 1));
      process.exitCode = 0;
    })();
  }
}
