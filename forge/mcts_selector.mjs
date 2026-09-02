#!/usr/bin/env node
// mcts_selector.mjs — MCTS SELECTOR V0.
//
// CE QU'IL FAIT : composer les deux briques déjà prouvées — `candidate_selector` (qui
// classe selon le reward_contract) puis `execution_binding` (qui dit si un chemin
// existe) — et ne rendre que les candidats **réellement exécutables**, chacun avec son
// chemin complet et la preuve qu'il devra produire.
//
// CE QU'IL NE FAIT PAS, ET POURQUOI — dit franchement : **il n'explore aucun arbre.**
// Un MCTS a besoin d'un facteur de branchement. Mesuré au 2026-08-04 : après filtrage
// sur l'exécutabilité, chaque root_problem rend **au plus un** chemin exécutable.
// Dérouler un UCT sur un arbre à une branche produirait une cérémonie, pas une décision.
// La sélection déterministe doit être prouvée avant l'exploration — c'est la règle de
// cette lane, et elle s'applique d'abord à ce fichier.
//
// INTERDITS TENUS : aucun score inventé, aucune agrégation cachée (le classement reste
// celui du `candidate_selector` : lexicographique sur trois priorités déclarées), aucun
// LLM, aucun appel réseau, aucune écriture.
//
// Usage : node mcts_selector.mjs <root_problem_id> [--json]
//
// claim_posture: NO_CLAIM_ALLOWED
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { selectionner } from './candidate_selector.mjs';
import { chargerContexteExecution, planifier } from './execution_binding.mjs';

/** Motifs d'écartement propres à cette couche — distincts des rejets du sélecteur. */
export const ECARTES = {
  NON_EXECUTABLE: 'selectionne par le contrat, mais aucun chemin d execution',
};

/**
 * Ce que le candidat devra produire s'il est exécuté. Lu depuis la recette, jamais
 * inventé : une preuve attendue qu'on fabrique ici ne serait exigée par personne.
 */
export function preuveAttendue(recetteId, ctx) {
  const r = (ctx.recettes?.recipes || []).find((x) => x.id === recetteId);
  if (!r) return null;
  return {
    evidence_requirements: [...(r.evidence_requirements || [])],
    validation_contract: r.validation_contract ?? null,
    quality_not_proven: r.quality_not_proven ?? null,
  };
}

/**
 * Sélectionne les chemins exécutables pour un problème racine.
 *
 * @param {object} requete {root_problem_id, evaluation_context, available_constraints, current_metrics}
 * @param {object} ctx sortie de `chargerContexteExecution`
 * @returns {object}
 */
export function selectionnerExecutable(requete, ctx) {
  const base = selectionner(requete, ctx);

  const retenus = [];
  const ecartes = [];
  for (const c of base.selected_candidates) {
    const plan = planifier({
      mutation_id: c.mutation_id,
      root_problem_id: requete.root_problem_id,
      evaluation_context: requete.evaluation_context,
    }, ctx);
    if (!plan.executable) {
      ecartes.push({
        mutation_id: c.mutation_id,
        motif: ECARTES.NON_EXECUTABLE,
        blockers: plan.blockers.map((b) => b.blocker),
      });
      continue;
    }
    retenus.push({
      mutation_id: c.mutation_id,
      recipe: plan.recipe,
      capability: plan.chain_bindings.map((b) => b.capability),
      runtime: plan.chain_bindings.map((b) => b.runtime_role),
      composition: plan.composition,
      objective_value: c.objective_value,
      regression: c.regression,
      token_cost: c.token_cost,
      expected_proof: preuveAttendue(plan.recipe, ctx),
    });
  }

  const raisonnement = [...base.reasoning];
  if (ecartes.length) {
    raisonnement.push(`${ecartes.length} candidat(s) ecarte(s) : classes premiers par le `
      + 'contrat, mais sans chemin d execution.');
  }
  if (retenus.length > 1) {
    raisonnement.push(`${retenus.length} chemins executables — ils restent EX AEQUO : `
      + 'aucun departage supplementaire n est invente a cet etage.');
  }
  // Le fait qui interdit l'exploration, mesuré et non supposé.
  raisonnement.push(`facteur de branchement = ${retenus.length} : `
    + (retenus.length > 1
      ? 'une exploration deviendrait justifiable a partir d ici.'
      : 'aucune exploration justifiable (arbre a une branche ou moins).'));

  return {
    root_problem_id: requete.root_problem_id,
    executable_candidates: retenus,
    discarded_not_executable: ecartes,
    rejected_by_contract: base.rejected_candidates,
    reasoning: raisonnement,
    selection_basis: {
      ...base.selection_basis,
      execution_filter: 'execution_binding.planifier — executable=true exige',
      branching_factor: retenus.length,
      exploration: 'AUCUNE (V0 deterministe)',
    },
  };
}

// ---- CLI ----
const estMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (estMain) {
  const argv = process.argv.slice(2);
  const rp = argv.find((a) => !a.startsWith('--'));
  if (!rp) {
    console.error('usage: node mcts_selector.mjs <root_problem_id> [--json]');
    process.exitCode = 2;
  } else {
    const ctx = await chargerContexteExecution();
    const res = selectionnerExecutable({ root_problem_id: rp }, ctx);
    if (argv.includes('--json')) {
      console.log(JSON.stringify(res, null, 1));
    } else {
      console.log(`# ${rp} — ${res.executable_candidates.length} chemin(s) executable(s)`);
      for (const c of res.executable_candidates) {
        console.log(`  ${c.mutation_id}`);
        console.log(`    recipe     ${c.recipe}${c.composition ? ' (composition)' : ''}`);
        console.log(`    capability ${c.capability.join(' -> ')}`);
        console.log(`    runtime    ${c.runtime.join(' -> ')}`);
        console.log(`    preuve     ${c.expected_proof?.evidence_requirements?.length ?? 0} fichier(s) exiges`
          + ` · metrique ${c.expected_proof?.validation_contract?.objective_metric ?? '-'}`);
      }
      for (const e of res.discarded_not_executable) {
        console.log(`  ECARTE  ${e.mutation_id} : ${e.blockers.join(', ')}`);
      }
      for (const l of res.reasoning) console.log(`  · ${l}`);
    }
    process.exitCode = res.executable_candidates.length ? 0 : 1;
  }
}
