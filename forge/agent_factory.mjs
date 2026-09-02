#!/usr/bin/env node
// agent_factory.mjs — AGENT FACTORY V0 : instancier un chemin DÉJÀ PROUVÉ.
//
// Elle ne choisit pas (`mcts_selector`), ne classe pas (`candidate_selector`), ne juge
// pas de l'exécutabilité (`execution_binding`). Elle reçoit une décision **déjà
// validée** et fabrique le plan d'exécution correspondant — rien de plus.
//
// V0 NE LANCE RIEN. Elle produit un `FactoryExecutionPlan` et s'arrête. Le mode
// `--execute` n'existe pas encore, à dessein : il est conditionné à une preuve qui
// n'existe pas — « plan généré == plan exécuté ». Ajouter le drapeau avant cette preuve
// reviendrait à exécuter sur la foi d'un plan que personne n'a vérifié.
//
// DÉTERMINISME STRICT : aucun LLM, aucun réseau, aucune écriture, aucune horloge,
// aucun aléa. `execution_id` est l'empreinte du plan lui-même — deux requêtes
// identiques rendent le même identifiant, et un plan différent en rend un autre.
//
// Usage : node agent_factory.mjs <requete.json> [--json]
//         node agent_factory.mjs --mutation REPAIR-LOOP-V1        (requête dérivée)
//
// claim_posture: NO_CLAIM_ALLOWED
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { CHEMIN_ROLES } from './candidate_selector.mjs';
import { chargerContexteExecution, planifier, CAPABILITY_STATUS_COMPATIBLE } from './execution_binding.mjs';

const ICI = dirname(fileURLToPath(import.meta.url));
const RACINE = resolve(ICI, '..');

/** Champs du contrat d'entrée `FactoryRequest`. */
export const CHAMPS_REQUETE = [
  'root_problem_id', 'mutation_id', 'recipe_id', 'capability_id', 'runtime_role',
  'evidence_required', 'execution_contract_ref',
];

/** Vocabulaire FERMÉ des blocages de la Factory. Chaque valeur désigne UNE des sept
 *  vérifications mécaniques, et une seule. */
export const BLOCKERS = {
  REQUEST_INVALID: 'request_invalid',
  MUTATION_NOT_FOUND: 'mutation_not_found',
  MUTATION_NOT_ACCEPTED: 'mutation_not_accepted',
  RECIPE_NOT_FOUND: 'recipe_not_found',
  RECIPE_NOT_EXECUTABLE: 'recipe_not_executable',
  CAPABILITY_NOT_FOUND: 'capability_not_found',
  CAPABILITY_NOT_PROVEN_EXECUTABLE: 'capability_not_proven_executable',
  RUNTIME_CONTRACT_MISSING: 'runtime_contract_missing',
  EVIDENCE_MISSING: 'evidence_missing',
  DECLARATION_MISMATCH: 'declaration_mismatch',
};

// --------------------------------------------------------------------------------
// Lecture du contrat de runtime (sous-ensemble ciblé de roles.yaml)
// --------------------------------------------------------------------------------

/** Bloc brut d'un rôle sous `runtime_contracts:`. `null` si absent. */
export function blocContratRuntime(texte, role) {
  const lignes = String(texte).split(/\r?\n/);
  let i = lignes.findIndex((l) => /^runtime_contracts:\s*$/.test(l));
  if (i < 0) return null;
  const debut = lignes.findIndex((l, k) => k > i && new RegExp(`^  ${role}:\\s*$`).test(l));
  if (debut < 0) return null;
  const out = [];
  for (let k = debut + 1; k < lignes.length; k += 1) {
    if (/^\S/.test(lignes[k])) break;                       // retour racine
    if (/^ {2}\S/.test(lignes[k])) break;                   // rôle suivant
    out.push(lignes[k]);
  }
  return out.join('\n');
}

/**
 * Ce dont la Factory a besoin dans un contrat de runtime : par où appeler, avec quoi,
 * quoi attendre. Extraction ciblée — jamais un parseur YAML complet, jamais un second
 * format de vérité.
 */
export function parseContratRuntime(texte, role) {
  const bloc = blocContratRuntime(texte, role);
  if (bloc === null) return null;
  const scalaire = (cle) => {
    const m = bloc.match(new RegExp(`^\\s*${cle}:\\s*(.+)$`, 'm'));
    return m ? m[1].trim().replace(/\s+#.*$/, '') : null;
  };
  const liste = (cle) => {
    const m = bloc.match(new RegExp(`^\\s*${cle}:\\s*\\[(.*)\\]\\s*$`, 'm'));
    return m ? m[1].split(',').map((x) => x.trim()).filter(Boolean) : [];
  };
  // `entrypoint:` (un runtime) ou `entrypoints:` (une famille, ex. deterministic)
  const entrypoints = [];
  const un = scalaire('entrypoint');
  if (un) entrypoints.push(un);
  const bloc2 = bloc.match(/^\s*entrypoints:\s*\n((?:\s*-\s.*\n?)+)/m);
  if (bloc2) {
    for (const l of bloc2[1].split(/\r?\n/)) {
      const m = l.match(/^\s*-\s+(\S+)/);
      if (m) entrypoints.push(m[1]);
    }
  }
  return {
    role,
    entrypoints,
    adapter: scalaire('adapter'),
    called_by: scalaire('called_by'),
    model: scalaire('model'),
    kill_switch: scalaire('kill_switch'),
    invocation: scalaire('invocation'),
    inputs: liste('inputs'),
    outputs: liste('outputs'),
  };
}

// --------------------------------------------------------------------------------
// Contrat d'entrée
// --------------------------------------------------------------------------------

/**
 * Décrit UN runtime : par quoi l'appeler, avec quoi, quoi attendre.
 *
 * AMBIGUÏTÉ LEVÉE (2026-08-04) : le contrat déclare `entrypoint` (le moteur) ET
 * `adapter` (la porte qui accepte les `inputs`). Le plan ne disait pas lequel appeler —
 * la couche de preuve devait le deviner. `callable` tranche : c'est le module qui
 * accepte les entrées déclarées, et rien d'autre. `null` = ce runtime n'est pas
 * appelable directement (il est dispatché par le driver, comme les rôles d'étape) —
 * déclaré absent plutôt que deviné.
 */
export function decrireRuntime(role, ctx) {
  const contrat = ctx.runtime_contracts_detail?.get(role) ?? null;
  const etape = ctx.contrats_etape?.get(role) ?? null;
  if (contrat) {
    return {
      runtime_role: role,
      contract_ref: `roles.yaml#runtime_contracts.${role}`,
      contract_kind: 'runtime_contract',
      entrypoints: contrat.entrypoints,
      adapter: contrat.adapter,
      callable: contrat.adapter ?? contrat.entrypoints[0] ?? null,
      callable_level: contrat.adapter ? 'adapter' : (contrat.entrypoints[0] ? 'entrypoint' : null),
      model: contrat.model,
      kill_switch: contrat.kill_switch,
      // Comment ce callable reçoit ses entrées. Déclaré, jamais déduit : deviner
      // entre « fichier de requête » et « argument positionnel » ferait appeler le
      // runtime autrement que son contrat ne le dit.
      invocation: contrat.invocation,
      required_inputs: [...contrat.inputs],
      expected_outputs: [...contrat.outputs],
    };
  }
  if (etape) {
    return {
      runtime_role: role,
      contract_ref: `contracts/${etape[0]}`,
      contract_kind: 'step_contract',
      entrypoints: [],
      adapter: null,
      // Un rôle d'étape est dispatché par le driver sous contrat : il n'a pas de porte
      // directe. Le déclarer non appelable est un fait, pas une lacune.
      callable: null,
      callable_level: null,
      model: null,
      kill_switch: null,
      invocation: null,
      required_inputs: [],
      expected_outputs: [],
    };
  }
  return {
    runtime_role: role, contract_ref: null, contract_kind: null, entrypoints: [],
    adapter: null, callable: null, callable_level: null, model: null, kill_switch: null,
    invocation: null, required_inputs: [], expected_outputs: [],
  };
}

/** Valide la FORME de la requête. Lève sur toute anomalie : instancier depuis une
 *  requête douteuse est exactement ce que cette couche doit empêcher. */
export function validerRequete(req) {
  if (req === null || typeof req !== 'object') throw new Error('FactoryRequest: objet attendu');
  const inconnus = Object.keys(req).filter((k) => !CHAMPS_REQUETE.includes(k));
  if (inconnus.length) throw new Error(`FactoryRequest: champs hors contrat -> ${inconnus.join(', ')}`);
  for (const c of CHAMPS_REQUETE) {
    if (!(c in req)) throw new Error(`FactoryRequest: champ obligatoire manquant -> ${c}`);
  }
  for (const c of ['root_problem_id', 'mutation_id', 'recipe_id', 'capability_id',
    'runtime_role', 'execution_contract_ref']) {
    if (typeof req[c] !== 'string' || !req[c].trim()) {
      throw new Error(`FactoryRequest: ${c} doit être une chaîne non vide`);
    }
  }
  if (!Array.isArray(req.evidence_required) || req.evidence_required.some((x) => typeof x !== 'string')) {
    throw new Error('FactoryRequest: evidence_required doit être un tableau de chaînes');
  }
  return req;
}

/** Empreinte du plan — DÉTERMINISTE. Ni horloge, ni compteur, ni aléa : deux requêtes
 *  identiques sur le même dépôt rendent le même `execution_id`. */
export function empreinteExecution(parties) {
  return `exec-${createHash('sha256').update(JSON.stringify(parties)).digest('hex').slice(0, 16)}`;
}

// --------------------------------------------------------------------------------
// Instanciation
// --------------------------------------------------------------------------------

/**
 * Fabrique le `FactoryExecutionPlan`. Ne lance RIEN.
 *
 * Les sept vérifications, dans l'ordre. Une famille tombée n'entraîne pas les
 * suivantes en cascade : un maillon dont l'adresse n'existe pas n'est pas un second
 * problème.
 *
 * @param {object} requete FactoryRequest
 * @param {object} ctx sortie de `chargerContexteFactory`
 * @returns {object} FactoryExecutionPlan
 */
export function instancier(requete, ctx, racine = RACINE) {
  const blockers = [];
  const plan = {
    execution_id: null,
    root_problem_id: requete?.root_problem_id ?? null,
    mutation_id: requete?.mutation_id ?? null,
    selected_recipe: null,
    runtime_to_call: null,
    capability_chain: [],
    runtime_chain: [],
    required_inputs: [],
    expected_outputs: [],
    evidence_targets: [],
    blockers,
    executable: false,
    // La Factory décrit, elle n'exécute pas. Constant en V0.
    execution_mode: 'PLAN_ONLY',
  };

  let req;
  try {
    req = validerRequete(requete);
  } catch (err) {
    blockers.push({ blocker: BLOCKERS.REQUEST_INVALID, detail: err.message });
    return plan;
  }

  // --- 1/2. la mutation existe et est acceptée
  const mutation = (ctx.mutations || []).find((m) => m.id === req.mutation_id);
  if (!mutation) {
    blockers.push({ blocker: BLOCKERS.MUTATION_NOT_FOUND, detail: req.mutation_id });
    return plan;
  }
  if (mutation.accepted !== true) {
    blockers.push({
      blocker: BLOCKERS.MUTATION_NOT_ACCEPTED,
      detail: mutation.rejected_reason?.code ?? mutation.status ?? 'accepted=false',
    });
  }
  if (req.root_problem_id !== mutation.root_problem_id) {
    blockers.push({
      blocker: BLOCKERS.DECLARATION_MISMATCH,
      detail: `root_problem_id demande=${req.root_problem_id} mais la mutation declare `
        + `${mutation.root_problem_id}`,
    });
  }

  // --- 3/4. la recette existe et elle est exécutable
  const recette = (ctx.recettes?.recipes || []).find((r) => r.id === req.recipe_id);
  if (!recette) {
    blockers.push({ blocker: BLOCKERS.RECIPE_NOT_FOUND, detail: req.recipe_id });
    return plan;
  }
  plan.selected_recipe = recette.id;
  // `executable` ne se lit pas dans la recette : il se RECALCULE par le binding, qui
  // est le seul juge de l'exécutabilité. Recopier `recipe_status` reviendrait à faire
  // confiance à un champ que personne n'a revérifié.
  const bind = planifier({
    mutation_id: req.mutation_id, root_problem_id: req.root_problem_id,
  }, ctx, racine);
  if (!bind.executable) {
    blockers.push({
      blocker: BLOCKERS.RECIPE_NOT_EXECUTABLE,
      detail: `execution_binding: ${bind.blockers.map((b) => b.blocker).join(', ') || 'non executable'}`,
    });
  }
  if (bind.recipe && bind.recipe !== recette.id) {
    blockers.push({
      blocker: BLOCKERS.DECLARATION_MISMATCH,
      detail: `recipe_id demande=${recette.id} mais le binding resout ${bind.recipe}`,
    });
  }

  // --- 5. la capacité existe et est PROVEN_EXECUTABLE
  const capacite = (ctx.capacites?.capabilities || []).find((c) => c.id === req.capability_id);
  if (!capacite) {
    blockers.push({ blocker: BLOCKERS.CAPABILITY_NOT_FOUND, detail: req.capability_id });
    return plan;
  }
  if (!CAPABILITY_STATUS_COMPATIBLE.has(capacite.capability_status)) {
    blockers.push({
      blocker: BLOCKERS.CAPABILITY_NOT_PROVEN_EXECUTABLE,
      detail: `${capacite.id}: ${capacite.capability_status}`,
    });
  }
  plan.capability_chain = (recette.capability_chain || []).map((e) => ({
    capability: e.capability,
    evidence: e.evidence,
    runtime_role: (recette.runtime_roles || [])
      .find((r) => r.capability === e.capability)?.capability_role ?? null,
  }));

  // --- 6. CHAQUE runtime de la chaîne possède un contrat
  //
  // AMBIGUÏTÉ LEVÉE (2026-08-04, observée par Execution Proof V0) : une chaîne à deux
  // capacités n'exposait qu'UN `runtime_to_call`. Le maillon `worldscan` de
  // `world_scan_repair_v1` était invisible dans la section runtime — un plan de
  // composition ne disait donc pas ce qu'il fallait appeler, ni combien de fois.
  // `runtime_chain` porte désormais un maillon par capacité ; `runtime_to_call` reste
  // celui de la `capability_id` demandée.
  plan.runtime_chain = plan.capability_chain.map((et) => decrireRuntime(et.runtime_role, ctx));
  const sansContrat = plan.runtime_chain.filter((r) => r.contract_ref === null);
  for (const r of sansContrat) {
    blockers.push({
      blocker: BLOCKERS.RUNTIME_CONTRACT_MISSING,
      detail: `${r.runtime_role}: ni runtime_contracts, ni contrat d etape`,
    });
  }
  const demande = decrireRuntime(req.runtime_role, ctx);
  if (demande.contract_ref === null && !sansContrat.some((r) => r.runtime_role === req.runtime_role)) {
    blockers.push({
      blocker: BLOCKERS.RUNTIME_CONTRACT_MISSING,
      detail: `${req.runtime_role}: ni runtime_contracts, ni contrat d etape`,
    });
  }
  if (demande.contract_ref !== null) {
    plan.runtime_to_call = demande;
    plan.required_inputs = [...demande.required_inputs];
    plan.expected_outputs = [...demande.expected_outputs];
  }
  const refAttendue = plan.runtime_to_call?.contract_ref;
  if (refAttendue && req.execution_contract_ref !== refAttendue) {
    blockers.push({
      blocker: BLOCKERS.DECLARATION_MISMATCH,
      detail: `execution_contract_ref demande=${req.execution_contract_ref} mais le `
        + `contrat resolu est ${refAttendue}`,
    });
  }

  // --- 7. les preuves exigées existent PHYSIQUEMENT
  const cibles = [...new Set([...(recette.evidence_requirements || []), ...req.evidence_required])];
  plan.evidence_targets = cibles;
  const manquantes = cibles.filter((f) => !existsSync(join(racine, f)));
  if (cibles.length === 0) {
    blockers.push({ blocker: BLOCKERS.EVIDENCE_MISSING, detail: '(aucune preuve exigee)' });
  } else if (manquantes.length) {
    blockers.push({ blocker: BLOCKERS.EVIDENCE_MISSING, detail: manquantes.join(', ') });
  }

  plan.executable = blockers.length === 0;
  plan.execution_id = empreinteExecution({
    root_problem_id: req.root_problem_id,
    mutation_id: req.mutation_id,
    recipe: plan.selected_recipe,
    capability_chain: plan.capability_chain,
    runtime: plan.runtime_to_call,
    runtime_chain: plan.runtime_chain,
    evidence_targets: plan.evidence_targets,
    executable: plan.executable,
  });
  return plan;
}

/**
 * EXÉCUTION CONTRÔLÉE — ouverte le 2026-08-04 après trois MATCH sur trois familles.
 *
 * Ce n'est **pas un nouveau chemin d'exécution** : c'est celui de la preuve, avec la
 * trace conservée. Elle appelle `execution_proof.executerSousObservation` puis
 * `execution_proof.comparer` — les mêmes fonctions, les mêmes vérifications. Si elle
 * exécutait autrement que la preuve, la preuve ne prouverait plus rien.
 *
 * LES CINQ CONDITIONS, appliquées ici et vérifiées par les tests :
 *   1. HumanGate PAR EXÉCUTION — `confirm: true` obligatoire, jamais mémorisé ;
 *   2. périmètre déclaré obligatoire — `scope` non vide ;
 *   3. MISMATCH = arrêt — aucun retry, aucune réparation, aucun second essai ;
 *   4. aucune boucle — un appel, une exécution ;
 *   5. aucun pouvoir de dispatch — un maillon sans `callable` n'est pas exécuté ici.
 *
 * Elle n'écrit AUCUN registre et ne touche PAS `production_ready`.
 *
 * @returns {Promise<object>} {plan, execution: {trace, verdict} | null, refus}
 */
export async function executerPlan(plan, opts = {}) {
  const refus = [];
  if (opts.confirm !== true) {
    refus.push('HUMANGATE_ABSENT : --confirm est exige a CHAQUE execution, jamais memorise');
  }
  if (!Array.isArray(opts.scope) || opts.scope.length === 0) {
    refus.push('SCOPE_ABSENT : le perimetre doit etre declare avant toute ecriture');
  }
  if (!opts.runtimeRequest) {
    refus.push('RUNTIME_REQUEST_ABSENTE : la Factory ne fabrique pas les VALEURS des entrees');
  }
  // Un plan non validé ne s'exécute jamais — c'est la première des conditions.
  if (!plan || plan.executable !== true) {
    refus.push(`PLAN_NON_EXECUTABLE : ${(plan?.blockers || []).map((b) => b.blocker).join(', ') || 'plan absent'}`);
  }
  if (refus.length) return { plan, execution: null, refus };

  const proof = await import('./execution_proof.mjs');
  const obs = await proof.executerSousObservation(plan, {
    requeteRuntime: opts.runtimeRequest,
    scope: opts.scope,
    declaredInputs: opts.declaredInputs,
    racine: opts.racine,
    executer: opts.executer,   // injection de TEST uniquement — jamais fournie par la CLI
  });
  const verdict = proof.comparer(plan, obs, {
    scope: opts.scope,
    requeteFournie: opts.declaredInputs,
    resumedLegs: opts.resumedLegs,
    racine: opts.racine,
  });
  // MISMATCH = arrêt. On rend la trace telle quelle : aucune correction, aucun retry.
  return {
    plan,
    execution: { trace: proof.construireTrace(plan, obs, verdict), verdict },
    refus: [],
  };
}

export async function chargerContexteFactory(chemins = {}) {
  const ctx = await chargerContexteExecution(chemins);
  const texte = await readFile(chemins.roles || CHEMIN_ROLES, 'utf-8');
  const detail = new Map();
  for (const role of ctx.runtime_contracts) {
    const c = parseContratRuntime(texte, role);
    if (c) detail.set(role, c);
  }
  return { ...ctx, runtime_contracts_detail: detail };
}

/** Dérive une FactoryRequest depuis une mutation déjà validée par les couches amont.
 *  Commodité de CLI — elle ne DÉCIDE rien, elle recopie ce que le binding a résolu. */
export function requeteDepuisMutation(mutationId, ctx, racine = RACINE) {
  const bind = planifier({ mutation_id: mutationId }, ctx, racine);
  const mutation = (ctx.mutations || []).find((m) => m.id === mutationId);
  const recette = (ctx.recettes?.recipes || []).find((r) => r.id === bind.recipe);
  const lien = bind.chain_bindings[bind.chain_bindings.length - 1] ?? {};
  const role = lien.runtime_role ?? null;
  return {
    root_problem_id: mutation?.root_problem_id ?? null,
    mutation_id: mutationId,
    recipe_id: bind.recipe,
    capability_id: lien.capability ?? null,
    runtime_role: role,
    evidence_required: [...(recette?.evidence_requirements || [])],
    execution_contract_ref: ctx.runtime_contracts?.has(role)
      ? `roles.yaml#runtime_contracts.${role}`
      : `contracts/${(ctx.contrats_etape?.get(role) || [])[0]}`,
  };
}

// ---- CLI ----
const estMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (estMain) {
  const argv = process.argv.slice(2);
  {
    const iMut = argv.indexOf('--mutation');
    const ctx = await chargerContexteFactory();
    let requete;
    if (iMut >= 0) {
      requete = requeteDepuisMutation(argv[iMut + 1], ctx);
    } else {
      const chemin = argv.find((a) => !a.startsWith('--'));
      if (!chemin) {
        console.error('usage: node agent_factory.mjs <requete.json> | --mutation <id> [--json]');
        process.exitCode = 2;
      } else {
        requete = JSON.parse(await readFile(chemin, 'utf-8'));
      }
    }
    if (requete) {
      const plan = instancier(requete, ctx);
      const opt = (nom) => { const i = argv.indexOf(nom); return i >= 0 ? argv[i + 1] : null; };
      if (argv.includes('--execute')) {
        const scope = (opt('--scope') || '').split(',').filter(Boolean);
        const fichierEntrees = opt('--runtime-request');
        const entrees = fichierEntrees ? JSON.parse(await readFile(fichierEntrees, 'utf-8')) : null;
        const repris = [];
        const proof = await import('./execution_proof.mjs');
        for (let i = 0; i < argv.length; i += 1) {
          if (argv[i] !== '--resume') continue;
          const [cap, reste] = argv[i + 1].split('=');
          const [source, sha] = reste.split('@');
          repris.push({ capability: cap, ...proof.verifierMaillonRepris(source, sha) });
        }
        const r = await executerPlan(plan, {
          confirm: argv.includes('--confirm'),
          scope,
          runtimeRequest: fichierEntrees,
          declaredInputs: entrees,
          resumedLegs: repris,
        });
        if (r.refus.length) {
          for (const x of r.refus) console.error(`REFUS ${x}`);
          console.error('\nusage: node agent_factory.mjs --mutation <id> --execute --confirm '
            + '--scope <dir,dir> --runtime-request <fichier.json> [--resume cap=fichier@sha]');
          process.exitCode = 2;
        } else {
          const { trace, verdict } = r.execution;
          console.log(JSON.stringify(trace, null, 1));
          console.error(`\n${trace.match_status}  (${verdict.mismatches.length} ecart(s))`);
          for (const c of verdict.checks) console.error(`  ${c.ok ? 'OK  ' : 'FAIL'} ${c.check} : ${c.detail}`);
          for (const m of verdict.mismatches) console.error(`  ECART ${m.mismatch} : ${m.detail}`);
          if (verdict.match_status !== 'MATCH') {
            console.error('\nMISMATCH = ARRET. Aucune reprise, aucune correction, aucun retry.');
          }
          process.exitCode = verdict.match_status === 'MATCH' ? 0 : 1;
        }
      } else if (argv.includes('--json')) {
        console.log(JSON.stringify(plan, null, 1));
      } else {
        console.log(`# ${plan.execution_id ?? '(aucun plan)'} — executable=${plan.executable}`
          + `  mode=${plan.execution_mode}`);
        console.log(`  recipe      ${plan.selected_recipe}`);
        console.log(`  runtime     ${plan.runtime_to_call?.runtime_role} `
          + `<- ${plan.runtime_to_call?.contract_ref ?? '-'}`);
        console.log(`  entrypoints ${(plan.runtime_to_call?.entrypoints || []).join(', ') || '-'}`);
        console.log(`  modele      ${plan.runtime_to_call?.model ?? '-'} `
          + `· coupure ${plan.runtime_to_call?.kill_switch ?? '-'}`);
        console.log(`  chaine      ${plan.capability_chain.map((c) => c.capability).join(' -> ')}`);
        for (const r of plan.runtime_chain) {
          console.log(`    maillon   ${r.runtime_role} (${r.contract_kind ?? 'AUCUN CONTRAT'})`
            + ` callable=${r.callable ?? 'AUCUN — dispatche par le driver'}`);
        }
        console.log(`  entrees     ${plan.required_inputs.join(', ') || '-'}`);
        console.log(`  sorties     ${plan.expected_outputs.join(', ') || '-'}`);
        console.log(`  preuves     ${plan.evidence_targets.length} fichier(s) exiges`);
        for (const b of plan.blockers) console.log(`  BLOCKER ${b.blocker} : ${b.detail}`);
      }
      process.exitCode = plan.executable ? 0 : 1;
    }
  }
}
