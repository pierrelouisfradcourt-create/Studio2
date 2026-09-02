#!/usr/bin/env node
// execution_binding.mjs — EXECUTION BINDING V1 : « cette mutation est-elle EXÉCUTABLE
// avec les composants disponibles, ou bloquée — et par quoi exactement ? »
//
// Ce que le Candidate Selector rend : « voici la meilleure mutation selon le contrat ».
// Ce qu'il ne dit pas : s'il existe un chemin réel pour l'exécuter. Ce module répond à
// cette seule question, et rien d'autre.
//
// IL NE FAIT PAS : sélectionner (c'est `candidate_selector.mjs`), exécuter, réparer,
// écrire un registre, créer une recette, créer une capacité, appeler un modèle.
// **Il détermine si un chemin existe.** Un chemin absent est déclaré absent, jamais
// comblé par une inférence.
//
// LES HUIT RÈGLES, dans l'ordre où elles deviennent vérifiables. Chacune peut produire
// un blocker nommé ; les règles dont la précondition est déjà tombée ne produisent PAS
// de blocker en cascade (un `capability_status` inconnu parce que la recette manque
// n'est pas un deuxième problème, c'est le même).
//
// Usage : node execution_binding.mjs <mutation_id> [--capability <id>] [--json]
//
// claim_posture: NO_CLAIM_ALLOWED
import { readFile, readdir } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chargerContexte, preuvesPresentes, CHEMIN_ROLES } from './candidate_selector.mjs';

const ICI = dirname(fileURLToPath(import.meta.url));
const RACINE = resolve(ICI, '..');

/** Vocabulaire FERMÉ des blocages. Un blocage sans nom est un blocage qu'on ne peut pas
 *  corriger : chaque valeur ici désigne un maillon précis et un seul. */
export const BLOCKERS = {
  MUTATION_NOT_FOUND: 'mutation_not_found',
  MUTATION_NOT_ACCEPTED: 'mutation_not_accepted',
  EVIDENCE_MISSING: 'evidence_missing',
  RECIPE_MISSING: 'recipe_missing',
  RECIPE_NOT_PROVEN: 'recipe_not_proven',
  CAPABILITY_MISSING: 'capability_missing',
  CAPABILITY_STATUS_INCOMPATIBLE: 'capability_status_incompatible',
  RUNTIME_ROLE_MISSING: 'runtime_role_missing',
  RUNTIME_CONTRACT_MISSING: 'runtime_contract_missing',
};

/** Seul statut de capacité compatible avec une exécution. `MEASURED_NOT_EXECUTABLE` et
 *  `PROVEN_BLOCKED_RUNTIME` disent eux-mêmes qu'ils ne le sont pas. */
export const CAPABILITY_STATUS_COMPATIBLE = new Set(['PROVEN_EXECUTABLE']);

/**
 * Clés déclarées sous `runtime_contracts:` de roles.yaml. Extraction line-based ciblée
 * (même technique que `agent_context_map.parseRoleNames`) : pas de parseur YAML côté
 * Node, et surtout pas un deuxième format de vérité.
 * @param {string} texte contenu de roles.yaml
 * @returns {Set<string>}
 */
export function parseRuntimeContracts(texte) {
  const out = new Set();
  let dedans = false;
  for (const brut of String(texte).split(/\r?\n/)) {
    const ligne = brut.replace(/\t/g, '  ');
    if (/^runtime_contracts:\s*$/.test(ligne)) { dedans = true; continue; }
    if (!dedans) continue;
    if (/^\S/.test(ligne)) break;                       // retour au niveau racine
    const m = ligne.match(/^ {2}([A-Za-z_][\w-]*):\s*$/);
    if (m) out.add(m[1]);
  }
  return out;
}

/**
 * Un chemin de preuve cite-t-il cette mutation ? Comparaison sur les SEGMENTS du chemin,
 * jamais par sous-chaîne : `lab/.../M-ws6/measured_metrics.json` cite `M-ws6`, mais
 * `.../M-ws60/...` ne le citerait pas. Une correspondance approximative rendrait
 * exécutables des mutations qui ne le sont pas — le contraire du défaut qu'on corrige.
 * @param {string} chemin
 * @param {string} mutationId
 * @returns {boolean}
 */
export function cheminCiteLaMutation(chemin, mutationId) {
  return String(chemin).split(/[\\/]/).includes(mutationId);
}

/**
 * Rôles qui portent un CONTRAT D'ÉTAPE (`contracts/<etape>.yaml` déclarant
 * `capability_role: <role>`).
 *
 * Pourquoi cette deuxième source : un rôle qui EST une étape de chaîne a déjà son
 * contrat — dans `contracts/`. Lui écrire en plus une entrée `runtime_contracts`
 * créerait deux déclarations du même fait, exactement le doublon qu'on vient de
 * résoudre ailleurs. `runtime_contracts` reste réservé aux runtimes qui ne sont PAS
 * des étapes (`repair_runtime`, `deterministic`).
 * @param {string} dossier
 * @returns {Promise<Map<string, string[]>>} rôle -> contrats qui le déclarent
 */
export async function parseContratsDEtape(dossier) {
  const out = new Map();
  let fichiers = [];
  try {
    fichiers = (await readdir(dossier)).filter((f) => f.endsWith('.yaml') && f !== 'roles.yaml');
  } catch {
    return out;
  }
  for (const f of fichiers) {
    // eslint-disable-next-line no-await-in-loop -- lecture séquentielle, volume connu
    const t = await readFile(join(dossier, f), 'utf-8');
    const m = t.match(/^capability_role:\s*([a-z_0-9]+)/m);
    if (m) out.set(m[1], [...(out.get(m[1]) || []), f]);
  }
  return out;
}

export async function chargerContexteExecution(chemins = {}) {
  const ctx = await chargerContexte(chemins);
  const cheminRoles = chemins.roles || CHEMIN_ROLES;
  const texte = await readFile(cheminRoles, 'utf-8');
  return {
    ...ctx,
    runtime_contracts: parseRuntimeContracts(texte),
    contrats_etape: await parseContratsDEtape(chemins.contrats || dirname(cheminRoles)),
  };
}

/**
 * Détermine si un chemin d'exécution existe pour une mutation.
 *
 * @param {object} requete {mutation_id, root_problem_id, evaluation_context, selected_capability}
 * @param {object} ctx sortie de `chargerContexteExecution`
 * @returns {object} execution_plan
 */
export function planifier(requete, ctx, racine = RACINE) {
  const blockers = [];
  const chaine = [];
  const plan = {
    executable: false,
    mutation_id: requete.mutation_id ?? null,
    root_problem_id: requete.root_problem_id ?? null,
    selected_capability: requete.selected_capability ?? null,
    recipe: null,
    recipe_status: null,
    capability: null,
    capability_status: null,
    runtime_role: null,
    runtime_status: null,
    composition: false,
    chain_bindings: [],
    blockers,
    execution_chain: chaine,
  };

  // --- 1. la mutation existe et est acceptée
  const mutation = (ctx.mutations || []).find((m) => m.id === requete.mutation_id);
  if (!mutation) {
    blockers.push({ blocker: BLOCKERS.MUTATION_NOT_FOUND, detail: requete.mutation_id ?? null });
    return plan;   // sans mutation, aucune autre règle n'a de sujet
  }
  plan.root_problem_id = plan.root_problem_id ?? mutation.root_problem_id ?? null;
  chaine.push({ step: 'mutation', id: mutation.id, ok: true });

  if (mutation.accepted !== true) {
    blockers.push({
      blocker: BLOCKERS.MUTATION_NOT_ACCEPTED,
      detail: mutation.rejected_reason?.code ?? mutation.status ?? 'accepted=false',
    });
  }

  // --- 2. les preuves existent PHYSIQUEMENT
  const preuve = preuvesPresentes(mutation, racine);
  if (!preuve.ok) {
    blockers.push({ blocker: BLOCKERS.EVIDENCE_MISSING, detail: preuve.manquants.join(', ') });
  } else {
    chaine.push({ step: 'evidence', id: mutation.evidence_status ?? 'PRESENT', ok: true });
  }

  // --- 3/4. une recette référence cette mutation, et elle est prouvée
  //
  // DEUX FAÇONS d'être référencé, et il fallait les deux (faux négatif corrigé le
  // 2026-08-04) : `capability_chain[].evidence` cite la mutation qui PROUVE une
  // capacité ; `evidence_requirements` cite les preuves que la recette EXIGE — dont,
  // pour une composition, la mutation qui prouve la composition elle-même. `M-ws6`
  // était couvert par la seconde et déclaré `recipe_missing` parce qu'on ne lisait
  // que la première.
  const citeeParChaine = (r) => (r.capability_chain || []).some((e) => e.evidence === mutation.id
    && (!requete.selected_capability || e.capability === requete.selected_capability));
  const citeeParPreuves = (r) => (r.evidence_requirements || [])
    .some((f) => cheminCiteLaMutation(f, mutation.id));
  const recettes = (ctx.recettes?.recipes || [])
    .filter((r) => citeeParChaine(r) || citeeParPreuves(r));
  if (recettes.length === 0) {
    blockers.push({
      blocker: BLOCKERS.RECIPE_MISSING,
      detail: requete.selected_capability
        ? `aucune recette avec evidence=${mutation.id} et capability=${requete.selected_capability}`
        : `aucune recette avec evidence=${mutation.id}`,
    });
    return plan;   // sans recette, capacité et runtime n'ont pas d'adresse : pas de cascade
  }
  const recette = recettes[0];
  plan.recipe = recette.id;
  plan.recipe_status = recette.recipe_status ?? null;
  chaine.push({ step: 'recipe', id: recette.id, ok: recette.proven === true });
  if (recette.proven !== true) {
    blockers.push({ blocker: BLOCKERS.RECIPE_NOT_PROVEN, detail: `${recette.id}: proven=${recette.proven}` });
  }

  // --- 5/6/7/8. quelles capacités doivent tenir ?
  //   * mutation citée dans `capability_chain` -> UNE capacité, celle qu'elle prouve ;
  //   * mutation citée par `evidence_requirements` seulement -> c'est une COMPOSITION :
  //     tous les maillons de la chaîne doivent tenir, sinon on déclarerait exécutable
  //     une composition dont la moitié ne l'est pas.
  const parChaine = (recette.capability_chain || []).filter((e) => e.evidence === mutation.id
    && (!requete.selected_capability || e.capability === requete.selected_capability));
  const etapes = parChaine.length ? parChaine : (recette.capability_chain || []);
  const capIds = etapes.map((e) => e.capability)
    .filter((x) => x) ;
  if (capIds.length === 0 && requete.selected_capability) capIds.push(requete.selected_capability);
  plan.composition = parChaine.length === 0 && capIds.length > 1;

  for (const capId of capIds) {
    const capacite = (ctx.capacites?.capabilities || []).find((c) => c.id === capId);
    const lien = { capability: capId, capability_status: null, runtime_role: null, runtime_status: null };
    plan.chain_bindings.push(lien);
    if (!capacite) {
      blockers.push({ blocker: BLOCKERS.CAPABILITY_MISSING, detail: capId });
      chaine.push({ step: 'capability', id: capId, ok: false });
      continue;   // sans capacité, aucun runtime à résoudre POUR CE MAILLON
    }
    lien.capability_status = capacite.capability_status ?? null;
    const capOk = CAPABILITY_STATUS_COMPATIBLE.has(lien.capability_status);
    chaine.push({ step: 'capability', id: capacite.id, ok: capOk });
    if (!capOk) {
      blockers.push({
        blocker: BLOCKERS.CAPABILITY_STATUS_INCOMPATIBLE,
        detail: `${capacite.id}: ${lien.capability_status} (attendu ${[...CAPABILITY_STATUS_COMPATIBLE].join(' | ')})`,
      });
    }

    const assignation = (recette.runtime_roles || []).find((r) => r.capability === capId);
    const role = assignation?.capability_role ?? capacite.runtime_role ?? null;
    lien.runtime_role = role;
    const roleDeclare = role !== null && ctx.roles.has(role);
    const contratRuntime = role !== null && ctx.runtime_contracts.has(role);
    const contratEtape = role !== null && !!ctx.contrats_etape?.has(role);
    const contratPresent = contratRuntime || contratEtape;
    lien.contract_source = contratRuntime ? 'runtime_contracts'
      : (contratEtape ? `contracts/${(ctx.contrats_etape.get(role) || [])[0]}` : null);
    lien.runtime_status = role === null ? 'ABSENT'
      : (!roleDeclare ? 'NON_DECLARE'
        : (contratRuntime ? 'DECLARE_AVEC_CONTRAT_RUNTIME'
          : (contratEtape ? 'DECLARE_AVEC_CONTRAT_ETAPE' : 'DECLARE_SANS_CONTRAT')));
    chaine.push({ step: 'runtime', id: role, ok: roleDeclare && contratPresent });
    if (!roleDeclare) {
      blockers.push({ blocker: BLOCKERS.RUNTIME_ROLE_MISSING, detail: role ?? '(aucun role assigne)' });
    } else if (!contratPresent) {
      blockers.push({
        blocker: BLOCKERS.RUNTIME_CONTRACT_MISSING,
        detail: `${role} declare dans roles.yaml mais absent de runtime_contracts`,
      });
    }
  }

  // Champs scalaires : le PREMIER maillon. Une composition les expose tous dans
  // `chain_bindings` — les aplatir en une seule valeur ferait disparaître le maillon
  // qui bloque.
  const premier = plan.chain_bindings[0];
  if (premier) {
    plan.capability = premier.capability;
    plan.capability_status = premier.capability_status;
    plan.runtime_role = premier.runtime_role;
    plan.runtime_status = premier.runtime_status;
  }

  plan.executable = blockers.length === 0;
  return plan;
}

// ---- CLI ----
const estMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (estMain) {
  const argv = process.argv.slice(2);
  const id = argv.find((a) => !a.startsWith('--') && argv[argv.indexOf(a) - 1] !== '--capability');
  if (!id) {
    console.error('usage: node execution_binding.mjs <mutation_id> [--capability <id>] [--json]');
    process.exitCode = 2;
  } else {
    const iCap = argv.indexOf('--capability');
    const ctx = await chargerContexteExecution();
    const plan = planifier({
      mutation_id: id,
      selected_capability: iCap >= 0 ? argv[iCap + 1] : null,
    }, ctx);
    if (argv.includes('--json')) {
      console.log(JSON.stringify(plan, null, 1));
    } else {
      console.log(`# ${plan.mutation_id} -> executable=${plan.executable}`);
      console.log(`  recipe=${plan.recipe} (${plan.recipe_status})`);
      console.log(`  capability=${plan.capability} (${plan.capability_status})`);
      console.log(`  runtime=${plan.runtime_role} (${plan.runtime_status})`);
      for (const c of plan.execution_chain) console.log(`  chain ${c.ok ? 'OK  ' : 'FAIL'} ${c.step}=${c.id}`);
      for (const b of plan.blockers) console.log(`  BLOCKER ${b.blocker} : ${b.detail}`);
    }
    process.exitCode = plan.executable ? 0 : 1;
  }
}
