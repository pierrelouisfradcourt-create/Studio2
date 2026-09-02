#!/usr/bin/env node
// candidate_selector.mjs — DECISION PLANE V0 : le premier consommateur MÉCANIQUE des
// registres de décision.
//
// Ce que l'audit « Consumers First » a mesuré le 2026-08-04 : `root_problems.json` avait
// ZÉRO lecteur de code, `agent_recipes.json` ZÉRO, et le CONTENU des `reward_contract`
// (objective, constraints, penalties) n'était lu par personne — seule leur RÉFÉRENCE
// était vérifiée. Trois registres écrits à la main, lus par rien. Ce fichier est leur
// premier lecteur.
//
// PÉRIMÈTRE STRICT — sélection DÉTERMINISTE, rien d'autre :
//   * aucun LLM, aucun appel réseau, aucun runtime lancé, aucun jeu touché ;
//   * aucune écriture : ni registre, ni root_problems, ni recette, ni capacité ;
//   * aucun score inventé. Les `forbidden_aggregation` de chaque problème racine
//     interdisent nommément `mutation_score` / `quality_score` / `global_score`, et
//     rien ici n'en fabrique un — le classement est LEXICOGRAPHIQUE sur trois priorités
//     déclarées, jamais une somme pondérée.
//
// EX AEQUO : quand deux candidats ne sont pas départageables par les trois priorités,
// ils sont TOUS rendus. Choisir arbitrairement serait fabriquer une préférence que la
// mesure ne porte pas.
//
// Usage : node candidate_selector.mjs <root_problem_id> [--context <json>] [--json]
//
// claim_posture: NO_CLAIM_ALLOWED
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  loadRegistry, loadMutation, loadLayers, CHEMIN_REGISTRE,
} from './mutation_registry.mjs';
import { parseRoleNames } from './agent_context_map.mjs';

const ICI = dirname(fileURLToPath(import.meta.url));
const RACINE = resolve(ICI, '..');

export const CHEMIN_PROBLEMES = join(ICI, 'root_problems.json');
export const CHEMIN_CAPACITES = join(ICI, 'capabilities.json');
export const CHEMIN_RECETTES = join(ICI, 'agent_recipes.json');
export const CHEMIN_ROLES = join(ICI, 'contracts', 'roles.yaml');

/** Motifs de rejet — vocabulaire fermé. Un rejet sans motif nommé est un rejet opaque. */
export const MOTIFS = {
  AUTRE_PROBLEME: 'root_problem_id different',
  CONTEXTE_DIFFERENT: 'evaluation_context different',
  NON_ACCEPTEE: 'mutation non acceptee (accepted=false)',
  SANS_PREUVE: 'evidence_ref absente ou fichier introuvable',
  CONTRAINTE_VIOLEE: 'contrainte du reward_contract violee',
};

// --------------------------------------------------------------------------------
// PHASE 2 — lecture MÉCANIQUE du reward_contract
// --------------------------------------------------------------------------------

/**
 * Sépare ce qui est exploitable par une machine de ce qui ne l'est pas. **Ne devine
 * jamais** : un champ non exploitable est SIGNALÉ, jamais interprété.
 *
 * Cas réels rencontrés dans le dépôt, et c'est pour eux que cette fonction existe :
 *   * `{metric: completion_tokens, operator: max, value: "declared"}` — « declared »
 *     n'est pas un nombre. Aucune machine ne peut trancher.
 *   * `penalties: ["cost_tokens"]` — un nom qui ne correspond à aucune métrique
 *     déclarée du problème. Une pénalité qu'on ne sait pas mesurer ne pénalise rien.
 *   * `measurement_method: "NON DEFINI — ..."` — le contrat le dit lui-même.
 *
 * @param {object} contrat reward_contract d'un root_problem
 * @param {object} probleme le root_problem entier (pour ses `metrics` déclarées)
 * @returns {{objective, constraints, penalties, forbidden, non_exploitable}}
 */
export function analyserRewardContract(contrat, probleme = {}) {
  const nonExploitable = [];
  const metriquesConnues = new Set((probleme.metrics || []).map((m) => m.name));

  const obj = contrat?.objective || {};
  let objective = null;
  if (!obj.metric) {
    nonExploitable.push({ champ: 'objective.metric', valeur: null, raison: 'absent' });
  } else if (!['maximize', 'minimize'].includes(obj.direction)) {
    nonExploitable.push({
      champ: 'objective.direction', valeur: obj.direction ?? null,
      raison: 'direction non reconnue (attendu maximize | minimize)',
    });
  } else {
    objective = { metric: obj.metric, direction: obj.direction };
  }

  const constraints = [];
  for (const [i, c] of (contrat?.constraints || []).entries()) {
    if (typeof c?.value !== 'number' || !['max', 'min'].includes(c?.operator)) {
      nonExploitable.push({
        champ: `constraints[${i}]`, valeur: `${c?.metric} ${c?.operator} ${c?.value}`,
        raison: typeof c?.value !== 'number'
          ? `valeur non numerique (${JSON.stringify(c?.value)}) — non evaluable mecaniquement`
          : `operateur inconnu (${c?.operator})`,
      });
      continue;
    }
    constraints.push({ metric: c.metric, operator: c.operator, value: c.value });
  }

  const penalties = [];
  for (const p of contrat?.penalties || []) {
    if (metriquesConnues.has(p)) penalties.push(p);
    else {
      nonExploitable.push({
        champ: 'penalties', valeur: p,
        raison: 'ne correspond a aucune metrique declaree du probleme — non mesurable',
      });
    }
  }

  const mm = contrat?.measurement_method;
  if (!mm || /NON DEFINI/i.test(mm)) {
    nonExploitable.push({
      champ: 'measurement_method', valeur: mm ?? null,
      raison: 'methode de mesure non definie — la metrique objectif ne peut pas etre comparee',
    });
  }

  return {
    objective,
    constraints,
    penalties,
    forbidden: [...(contrat?.forbidden || [])],
    non_exploitable: nonExploitable,
  };
}

// --------------------------------------------------------------------------------
// Filtres V0
// --------------------------------------------------------------------------------

/** Deux contextes d'évaluation sont-ils les mêmes ? Comparaison sur les seules clés
 *  FOURNIES par la requête : ne pas exiger ce qu'on n'a pas demandé. */
export function memeContexte(demande, contexteMutation) {
  if (!demande || Object.keys(demande).length === 0) return true;
  for (const [k, v] of Object.entries(demande)) {
    if ((contexteMutation ?? {})[k] !== v) return false;
  }
  return true;
}

/** Toutes les preuves déclarées existent-elles physiquement ? Une référence vers un
 *  fichier absent n'est pas une preuve. */
export function preuvesPresentes(mutation, racine = RACINE) {
  const refs = mutation.evidence_refs || {};
  const fichiers = [...(refs.artifacts || []), ...(refs.tests || [])];
  if (fichiers.length === 0) return { ok: false, manquants: ['(aucune reference)'] };
  const manquants = fichiers.filter((f) => !existsSync(join(racine, f)));
  return { ok: manquants.length === 0, manquants };
}

/** Contraintes exploitables respectées par les métriques mesurées ? */
export function contraintesRespectees(mesures, contraintes) {
  const violations = [];
  for (const c of contraintes) {
    const v = (mesures || {})[c.metric];
    if (v === undefined || v === null) {
      violations.push(`${c.metric} non mesure (contrainte ${c.operator} ${c.value})`);
      continue;
    }
    if (c.operator === 'max' && v > c.value) violations.push(`${c.metric}=${v} > max ${c.value}`);
    if (c.operator === 'min' && v < c.value) violations.push(`${c.metric}=${v} < min ${c.value}`);
  }
  return violations;
}

/**
 * ZONE DE LA DÉCISION — premier consommateur de décision du champ `layer`.
 *
 * Le problème racine déclare la zone où sa boucle casse (`root_problem.layer`). Une
 * mutation déclare la zone qu'elle touche (`mutation.layer`). Une mutation qui agit
 * **ailleurs** que là où la boucle casse peut être juste — mais elle ne répare pas ce
 * problème-là, et le sélecteur doit le DIRE plutôt que de la classer comme les autres.
 *
 * Ce n'est PAS un filtre : une telle mutation reste candidate (elle a pu être mesurée
 * sur ce problème). C'est une **information portée par la sortie**, et une priorité de
 * départage : à mérite égal, celle qui agit dans la zone du problème passe devant.
 *
 * @param {object} mutation
 * @param {object} probleme
 * @param {Map<string,object>} layers vocabulaire (source unique layers.json)
 * @returns {{layer, problem_layer, same_layer, known, broken_loop}}
 */
export function zoneDeLaDecision(mutation, probleme, layers) {
  const l = mutation.layer ?? null;
  const pl = probleme.layer ?? null;
  return {
    layer: l,
    problem_layer: pl,
    same_layer: l !== null && pl !== null && l === pl,
    known: l !== null && layers.has(l),
    broken_loop: pl !== null ? (layers.get(pl)?.broken_loop ?? null) : null,
  };
}

/** Signal de régression. Deux sources possibles, dans cet ordre — déclaré, pas deviné. */
export function regressionDe(mutation) {
  const mm = mutation.measured_metrics || {};
  if (typeof mm.regression_count === 'number') {
    return { valeur: mm.regression_count, source: 'measured_metrics.regression_count' };
  }
  if (typeof mutation.false_positive === 'number') {
    return { valeur: mutation.false_positive, source: 'false_positive' };
  }
  return { valeur: null, source: null };
}

// --------------------------------------------------------------------------------
// Classement — trois priorités LEXICOGRAPHIQUES, jamais une somme
// --------------------------------------------------------------------------------

/**
 * Ordonne les candidats retenus. Rend des GROUPES : chaque groupe est un ensemble
 * d'ex aequo. Le premier groupe est le meilleur au sens du contrat déclaré.
 *
 * P1 amelioration de la metrique objectif  (les non-mesures ne peuvent pas etre
 *    montrees meilleures : ils tombent dans un groupe « objectif non mesure », APRES
 *    ceux qui ont une valeur — mais entre eux, tous ex aequo)
 * P2 absence de regression
 * P3 cout le plus faible (measured_cost.token_cost)
 * P4 ZONE : a merite egal, celle qui agit dans la zone ou la boucle casse passe devant
 *    (ajoutee le 2026-08-04 — premier consommateur de DECISION du champ `layer`)
 *
 * P4 est en DERNIER a dessein : la zone ne doit jamais primer sur une mesure. Une
 * mutation mieux mesuree gagne meme si elle agit ailleurs. La zone ne departage que ce
 * que la mesure laisse ex aequo — et elle reduit donc le nombre de choix arbitraires
 * sans jamais en fabriquer un.
 */
export function ordonner(candidats, analyse, currentMetrics = {}) {
  const clef = (c) => {
    const m = c.mutation.measured_metrics || {};
    const metrique = analyse.objective?.metric;
    const brut = metrique ? m[metrique] : undefined;
    const mesure = typeof brut === 'number' ? brut : null;
    let gain = null;
    if (mesure !== null) {
      const base = currentMetrics[metrique];
      const delta = typeof base === 'number' ? mesure - base : mesure;
      gain = analyse.objective.direction === 'maximize' ? delta : -delta;
    }
    const reg = regressionDe(c.mutation).valeur;
    const cout = c.mutation.measured_cost?.token_cost;
    return {
      objectif_mesure: mesure !== null,
      gain,
      regression: typeof reg === 'number' ? reg : Number.POSITIVE_INFINITY,
      cout: typeof cout === 'number' ? cout : Number.POSITIVE_INFINITY,
      // P4 : 0 = agit dans la zone du probleme, 1 = agit ailleurs (ou zone inconnue).
      hors_zone: c.zone?.same_layer === true ? 0 : 1,
    };
  };

  const avecClef = candidats.map((c) => ({ ...c, _k: clef(c) }));
  const cmp = (a, b) => {
    if (a._k.objectif_mesure !== b._k.objectif_mesure) return a._k.objectif_mesure ? -1 : 1;
    if (a._k.objectif_mesure && a._k.gain !== b._k.gain) return b._k.gain - a._k.gain;
    if (a._k.regression !== b._k.regression) return a._k.regression - b._k.regression;
    if (a._k.cout !== b._k.cout) return a._k.cout - b._k.cout;
    return a._k.hors_zone - b._k.hors_zone;
  };
  avecClef.sort(cmp);

  const groupes = [];
  for (const c of avecClef) {
    const dernier = groupes[groupes.length - 1];
    if (dernier && cmp(dernier[0], c) === 0) dernier.push(c);
    else groupes.push([c]);
  }
  return groupes;
}

// --------------------------------------------------------------------------------
// PHASE 3 — résolution mutation -> recette -> capacité -> runtime (lecture seule)
// --------------------------------------------------------------------------------

/** Où cette mutation est-elle exécutable ? Ne génère ni recette ni capacité : si le
 *  maillon n'existe pas, il est déclaré absent. */
export function resoudreExecution(mutationId, { capacites, recettes, roles }) {
  const liens = [];
  for (const rec of recettes?.recipes || []) {
    for (const et of rec.capability_chain || []) {
      if (et.evidence !== mutationId) continue;
      const cap = (capacites?.capabilities || []).find((c) => c.id === et.capability) || null;
      const assignation = (rec.runtime_roles || []).find((r) => r.capability === et.capability);
      const role = assignation?.capability_role ?? cap?.runtime_role ?? null;
      liens.push({
        recipe: rec.id,
        recipe_status: rec.recipe_status ?? null,
        capability: et.capability,
        capability_status: cap?.capability_status ?? null,
        runtime_role: role,
        runtime_declared: role !== null && roles.has(role),
      });
    }
  }
  return liens;
}

// --------------------------------------------------------------------------------
// Sélection
// --------------------------------------------------------------------------------

export async function chargerContexte(chemins = {}) {
  const lire = async (p) => JSON.parse(await readFile(p, 'utf-8'));
  // `loadRegistry` rend {ok, registre, erreur} — on ne déballe QUE via `loadMutation`,
  // le lecteur canonique. Réimplémenter l'accès aux mutations créerait une deuxième
  // définition de « la liste des mutations ».
  const charge = await loadRegistry(chemins.registre || CHEMIN_REGISTRE);
  if (!charge.ok) throw new Error(`registre illisible : ${charge.erreur}`);
  return {
    mutations: loadMutation(charge.registre),
    problemes: await lire(chemins.problemes || CHEMIN_PROBLEMES),
    capacites: await lire(chemins.capacites || CHEMIN_CAPACITES),
    recettes: await lire(chemins.recettes || CHEMIN_RECETTES),
    roles: parseRoleNames(chemins.roles || CHEMIN_ROLES),
    layers: await loadLayers(chemins.layers),
  };
}

/**
 * @param {object} requete {root_problem_id, evaluation_context, available_constraints, current_metrics}
 * @param {object} ctx sortie de `chargerContexte`
 * @returns {{selected_candidates, rejected_candidates, reasoning, selection_basis}}
 */
export function selectionner(requete, ctx, racine = RACINE) {
  const probleme = (ctx.problemes.root_problems || [])
    .find((p) => p.id === requete.root_problem_id);
  if (!probleme) {
    return {
      selected_candidates: [], rejected_candidates: [],
      reasoning: [`root_problem inconnu : ${requete.root_problem_id}`],
      selection_basis: { error: 'ROOT_PROBLEM_NOT_FOUND' },
    };
  }

  const layers = ctx.layers ?? new Map();
  const analyse = analyserRewardContract(probleme.reward_contract, probleme);
  const contraintes = [...analyse.constraints, ...(requete.available_constraints || [])];

  const retenus = [];
  const rejetes = [];
  for (const m of ctx.mutations) {
    if (m.root_problem_id !== requete.root_problem_id) continue; // hors sujet, pas un rejet
    if (!memeContexte(requete.evaluation_context, m.evaluation_context)) {
      rejetes.push({ id: m.id, motif: MOTIFS.CONTEXTE_DIFFERENT,
        detail: JSON.stringify(m.evaluation_context ?? null) });
      continue;
    }
    if (m.accepted !== true) {
      rejetes.push({ id: m.id, motif: MOTIFS.NON_ACCEPTEE,
        detail: m.rejected_reason?.code ?? m.status ?? null });
      continue;
    }
    const preuve = preuvesPresentes(m, racine);
    if (!preuve.ok) {
      rejetes.push({ id: m.id, motif: MOTIFS.SANS_PREUVE, detail: preuve.manquants.join(', ') });
      continue;
    }
    const violations = contraintesRespectees(m.measured_metrics, contraintes);
    if (violations.length) {
      rejetes.push({ id: m.id, motif: MOTIFS.CONTRAINTE_VIOLEE, detail: violations.join(' | ') });
      continue;
    }
    retenus.push({ id: m.id, mutation: m, zone: zoneDeLaDecision(m, probleme, layers) });
  }

  const groupes = ordonner(retenus, analyse, requete.current_metrics || {});
  const meilleur = groupes[0] || [];
  const reasoning = [];
  if (analyse.objective) {
    reasoning.push(`objectif : ${analyse.objective.metric} a ${analyse.objective.direction}`);
  } else {
    reasoning.push('objectif NON exploitable mecaniquement — aucun classement sur l objectif');
  }
  for (const c of analyse.constraints) {
    reasoning.push(`contrainte appliquee : ${c.metric} ${c.operator} ${c.value}`);
  }
  for (const x of analyse.non_exploitable) {
    reasoning.push(`NON EXPLOITABLE — ${x.champ} = ${x.valeur} : ${x.raison}`);
  }
  if (meilleur.length > 1) {
    reasoning.push(`${meilleur.length} candidats EX AEQUO : les trois priorites ne les `
      + 'departagent pas. Aucun choix arbitraire — tous rendus.');
  }
  if (layers.size === 0) {
    reasoning.push('vocabulaire des layers illisible — la zone de decision n a pas pu etre lue');
  } else if (probleme.layer) {
    const dedans = meilleur.filter((c) => c.zone.same_layer).length;
    reasoning.push(`zone du probleme : ${probleme.layer} — `
      + `${layers.get(probleme.layer)?.broken_loop ?? 'boucle non decrite'}`);
    if (dedans < meilleur.length) {
      reasoning.push(`${meilleur.length - dedans} candidat(s) retenu(s) agissent HORS de cette `
        + 'zone : mesures sur ce probleme, mais ils ne touchent pas la ou la boucle casse.');
    }
  }
  if (meilleur.length && !meilleur[0]._k.objectif_mesure) {
    reasoning.push('aucun candidat ne mesure la metrique objectif : le classement s est '
      + 'fait sur la regression puis le cout, jamais sur l objectif.');
  }

  return {
    selected_candidates: meilleur.map((c) => ({
      mutation_id: c.id,
      objective_value: analyse.objective
        ? (c.mutation.measured_metrics || {})[analyse.objective.metric] ?? null : null,
      regression: regressionDe(c.mutation),
      zone: c.zone,
      token_cost: c.mutation.measured_cost?.token_cost ?? null,
      evidence_status: c.mutation.evidence_status ?? null,
      execution: resoudreExecution(c.id, ctx),
    })),
    rejected_candidates: rejetes,
    reasoning,
    selection_basis: {
      root_problem_id: probleme.id,
      reward_contract_ref: `${probleme.id}#reward_contract`,
      objective: analyse.objective,
      constraints_applied: contraintes,
      penalties_exploitable: analyse.penalties,
      non_exploitable_fields: analyse.non_exploitable,
      forbidden_aggregation: probleme.forbidden_aggregation || [],
      priority_order: ['objective_improvement', 'no_regression', 'lowest_token_cost',
        'same_layer_as_problem'],
      problem_layer: probleme.layer ?? null,
      layer_vocabulary_size: layers.size,
      tie_policy: 'ex_aequo_returned_in_full',
      candidates_examined: retenus.length + rejetes.length,
      groups: groupes.length,
    },
  };
}

// ---- CLI ----
const estMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (estMain) {
  const argv = process.argv.slice(2);
  const rp = argv.find((a) => !a.startsWith('--'));
  if (!rp) {
    console.error('usage: node candidate_selector.mjs <root_problem_id> [--context <json>] [--json]');
    process.exitCode = 2;
  } else {
    const iCtx = argv.indexOf('--context');
    const requete = {
      root_problem_id: rp,
      evaluation_context: iCtx >= 0 ? JSON.parse(argv[iCtx + 1]) : {},
      available_constraints: [],
      current_metrics: {},
    };
    const ctx = await chargerContexte();
    const res = selectionner(requete, ctx);
    if (argv.includes('--json')) {
      console.log(JSON.stringify(res, null, 1));
    } else {
      console.log(`# ${rp} — ${res.selected_candidates.length} retenu(s), `
        + `${res.rejected_candidates.length} rejete(s)`);
      for (const c of res.selected_candidates) {
        console.log(`  RETENU  ${c.mutation_id}  objectif=${c.objective_value} `
          + `regression=${c.regression.valeur} cout=${c.token_cost} `
          + `zone=${c.zone.layer ?? '-'}${c.zone.same_layer ? ' (zone du probleme)' : ' [HORS ZONE]'}`);
        if (c.execution.length === 0) {
          console.log('          -> AUCUNE recette ne reference cette mutation : '
            + 'selectionnable, pas executable en l etat');
        }
        for (const e of c.execution) {
          console.log(`          -> ${e.recipe} / ${e.capability} / runtime=${e.runtime_role}`
            + ` (declare=${e.runtime_declared})`);
        }
      }
      for (const r of res.rejected_candidates) console.log(`  REJETE  ${r.id} : ${r.motif}`);
      for (const l of res.reasoning) console.log(`  · ${l}`);
    }
    process.exitCode = res.selected_candidates.length ? 0 : 1;
  }
}
