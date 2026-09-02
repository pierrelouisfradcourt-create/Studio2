#!/usr/bin/env node
// agent_genome.mjs — AGENT_GENOME_V1 : SCHÉMA d'un worker de la Forge.
//
// PÉRIMÈTRE STRICT — schéma + validateur, RIEN D'AUTRE. Pas d'Agent Factory, pas de
// sélection, pas d'exécution. Ce fichier décrit ce qu'on devra savoir d'un worker pour
// qu'un MCTS puisse un jour choisir entre plusieurs ; il ne choisit rien.
//
// Pourquoi poser le schéma AVANT la fabrique : les mutations qu'on mesure aujourd'hui
// (prompt, oracle, stratégie de réparation) sont perdues si rien ne les enregistre.
// Un génome vide aujourd'hui mais VALIDE est un endroit où déposer ces mesures ; une
// fabrique sans schéma produirait des workers dont on ne saurait rien comparer.
//
// RÈGLE DE REMPLISSAGE, héritée de tout ce qui précède : `successful_mutations` et
// `failed_mutations` ne s'écrivent QUE depuis une mesure (0 faux positif sur des
// artefacts connus-bons, vrai positif observé). Un génome qui se déclare bon sans
// reçu est une opinion avec un nom de fichier.
//
// Usage : node agent_genome.mjs <genome.json>

import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { isNonEmptyString } from './upstream_schema.mjs';

// Le génome ne contient PAS les mutations : uniquement leurs identifiants. Le
// MUTATION_REGISTRY reste la source unique de vérité sur ce qui a été mesuré. Recopier
// une mesure dans un génome créerait deux versions d'un même fait, et deux faits qui
// disent la même chose finissent toujours par diverger.
export const STRATEGIES_REPARATION_STACK = ['champ_local', 'par_classe', 'cross_field'];

export const ROLES = ['worldscan', 'prisme', 'decompose', 'architect', 'wiremap', 'repair'];
export const STRATEGIES_REPARATION = ['aucune', 'champ_local', 'par_classe', 'cross_field'];

/**
 * Valide un génome complet.
 * @param {unknown} g
 * @returns {string[]} findings (vide = conforme)
 */
export function validateGenome(g) {
  if (g === null || typeof g !== 'object' || Array.isArray(g)) {
    return ['genome: doit etre un objet'];
  }
  const f = [];
  if (!ROLES.includes(g.worker_role)) {
    f.push(`worker_role: invalide (attendu: ${ROLES.join('|')})`);
  }
  if (!isNonEmptyString(g.model)) f.push('model: absent ou vide');
  if (!isNonEmptyString(g.prompt_version)) f.push('prompt_version: absent ou vide');

  if (!Array.isArray(g.oracle_stack) || g.oracle_stack.length === 0) {
    f.push('oracle_stack: liste NON VIDE requise — un worker sans oracle n est pas evaluable, '
      + 'donc pas selectionnable');
  }
  if (!STRATEGIES_REPARATION.includes(g.repair_strategy)) {
    f.push(`repair_strategy: invalide (attendu: ${STRATEGIES_REPARATION.join('|')})`);
  }

  // Ces tableaux peuvent être VIDES mais jamais ABSENTS : « aucune panne connue » et
  // « on n'a pas regardé » sont deux états différents, et seul le premier est une
  // information. Même discipline que `reference: null` explicite du Prisme.
  for (const cle of ['known_failures', 'successful_mutations', 'rejected_mutations',
    'known_blind_spots', 'repair_stack']) {
    if (!Array.isArray(g[cle])) {
      f.push(`${cle}: tableau requis (vide autorise, JAMAIS absent — « rien de connu » `
        + 'et « pas regarde » ne sont pas le meme etat)');
    }
  }
  // IDENTIFIANTS SEULEMENT — jamais un objet de mesure recopie du registre.
  for (const cle of ['successful_mutations', 'rejected_mutations']) {
    (g[cle] || []).forEach((m, i) => {
      if (!isNonEmptyString(m)) {
        f.push(`${cle}[${i}]: identifiant de mutation (chaine) attendu — le genome ne `
          + 'contient PAS les mutations, seulement leurs ids ; le registre est la source unique');
      }
    });
  }
  for (const s2 of g.repair_stack || []) {
    if (!STRATEGIES_REPARATION_STACK.includes(s2)) {
      f.push(`repair_stack: strategie inconnue '${s2}' (attendu: ${STRATEGIES_REPARATION_STACK.join('|')})`);
    }
  }
  // `confidence_profile` est DÉRIVÉ du registre, jamais saisi : il vaut toujours 'AUTO'.
  if (g.confidence_profile !== 'AUTO') {
    f.push("confidence_profile: doit valoir exactement 'AUTO' — il se derive des mutations "
      + 'citees, il ne se saisit pas');
  }

  const c = g.cost_profile;
  if (c === null || typeof c !== 'object' || Array.isArray(c)) {
    f.push('cost_profile: objet {tokens_moyen, latence_ms_moyenne, appels_par_artefact} requis');
  } else {
    for (const cle of ['tokens_moyen', 'latence_ms_moyenne', 'appels_par_artefact']) {
      if (typeof c[cle] !== 'number' || c[cle] < 0) f.push(`cost_profile.${cle}: nombre >= 0 requis`);
    }
  }
  return f;
}

/**
 * Génome vide mais VALIDE : le point de départ légitime d'un worker dont on n'a encore
 * rien mesuré. Les compteurs sont à zéro et les listes vides, ce qui se lit « rien de
 * mesuré », pas « rien à signaler ».
 *
 * `oracleStack` est OBLIGATOIRE, et c'est volontaire : il ne décrit pas une mesure
 * mais la façon dont ce worker sera jugé. Un worker qu'on ne sait pas juger n'a pas
 * de raison d'exister — le lui laisser vide « pour plus tard » créerait exactement
 * l'agent non évaluable que toute cette couche existe pour empêcher.
 * @param {string} role
 * @param {string} model
 * @param {string[]} oracleStack oracles qui jugent ce worker (NON VIDE)
 * @returns {object}
 */
export function genomeVierge(role, model, oracleStack) {
  if (!Array.isArray(oracleStack) || oracleStack.length === 0) {
    throw new Error('genomeVierge: oracle_stack NON VIDE requise — un worker qu on ne sait pas juger n a pas de raison d exister');
  }
  return {
    schema_version: 1,
    worker_role: role,
    model,
    prompt_version: 'v0',
    oracle_stack: [...oracleStack],
    repair_stack: [],
    known_failures: [],
    known_blind_spots: [],
    repair_strategy: 'aucune',
    successful_mutations: [],
    rejected_mutations: [],
    confidence_profile: 'AUTO',
    cost_profile: { tokens_moyen: 0, latence_ms_moyenne: 0, appels_par_artefact: 0 },
  };
}

// ---- CLI ----
const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const cible = process.argv.slice(2).find((a) => !a.startsWith('--'));
  if (!cible) {
    console.error('usage: node agent_genome.mjs <genome.json>');
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
      const f = validateGenome(doc);
      console.log(`VERDICT GENOME: ${f.length === 0 ? 'OK' : 'FAIL'}`);
      f.forEach((x) => console.error(`  FAIL: ${x}`));
      console.log(JSON.stringify({ ok: f.length === 0, problems: f }, null, 1));
      process.exitCode = f.length === 0 ? 0 : 1;
    })();
  }
}
