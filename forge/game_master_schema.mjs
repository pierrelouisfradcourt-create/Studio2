#!/usr/bin/env node
// game_master_schema.mjs — schéma + validateur DÉTERMINISTE du bloc `game_master`
// de `gm_worldscan.json` (Lot B, 2026-08-23, plan
// docs/superpowers/plans/2026-08-23-forge-lot-b-game-master.md ; boucles 9 + champs
// producteur/consommateur, Lot C.4-code, 2026-08-24, plan
// docs/superpowers/plans/2026-08-24-forge-lot-c4-code-boucles.md).
//
// Vocabulaire fermé (9 sorties du GM) : world_interpretation, loops (9 boucles —
// vocabulaire figé C.3/C.4 : core_loop, gameplay_loop, progression_loop,
// content_loop, economy_loop, skill_loop, world_loop, quest_loop, meta_loop ;
// `player_loop` de l'ancien schema Lot B est ABSORBE par `gameplay_loop`, non
// retro-compatible PAR CONSTRUCTION — cf. plan Lot C.4-code, « la Forge devient
// incapable de declarer un jeu complet sans boucles fermees »), economy_model,
// progression_metrics, proof_model, grey_blocks, artist_requirements
// (+ dimensions/games_observed du scan de genre Lot 0, sources_consumed du Lot A —
// ces deux derniers NE SONT PAS revalidés ici, cf. `_validate_gm_worldscan` /
// `_validate_sources_consumed` dans run_real.py).
//
// Lot C.4-code (2026-08-24) : chaque boucle de `loops` devient un OBJET
// {steps, produces, consumes, unlocks, transformation_perceptible, metric_propre}
// au lieu d'un simple tableau d'etapes (les etapes vivent desormais sous
// `.steps`, forme inchangee). Regles ajoutees, cf. contrats C.3/C.4
// (studio_brain/gamedesign/kitten_clicker_game_loop_architecture_v1.md,
// kitten_clicker_mutual_completion_contract_v1.md) :
//   R2a (globale) : le `produces` de CHAQUE boucle doit etre reference par le
//     `consumes` d'au moins une AUTRE boucle (sinon boucle orpheline, refusee) ;
//   R2b : `transformation_perceptible.text` non vide + `proof_ref` qui resout un
//     proof_model dont le `how` != 'humangate' (une transformation prouvee QUE
//     par HumanGate seul n'est jamais COMPLETE mecaniquement) ;
//   exclusivite `metric_propre` : chaque boucle porte un id de
//     `progression_metrics` qui n'est utilise par AUCUNE AUTRE boucle — ni comme
//     `metric_propre`, ni comme `metric_ref` d'une de ses etapes.
//
// `validateGameMaster(gm)` -> {ok, problems[]} : refus NOMMÉ par bloc/id, jamais
// d'exception sur une entrée malformée (types incorrects = problème listé, pas crash).
// `projectEconomy(gm)` -> economy.json DÉTERMINISTE (aucune horloge, aucun aléa) :
// même entrée -> même sortie, triée par id.
//
// Usage CLI :
//   node game_master_schema.mjs <gm_worldscan.json> [--json] [--economy <out>]
// Exit 0 = bloc game_master valide · 1 = refus (voir problems) · 2 = usage/fichier illisible.
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

export const LOOP_NAMES = [
  'core_loop', 'gameplay_loop', 'progression_loop', 'content_loop',
  'economy_loop', 'skill_loop', 'world_loop', 'quest_loop', 'meta_loop',
];

// `how` de proof_model INTERDIT seul pour transformation_perceptible.proof_ref
// (R2b, C.4) : une transformation dont la SEULE preuve est HumanGate n'est
// jamais mecaniquement COMPLETE.
const TRANSFORMATION_PROOF_HOW_FORBIDDEN = 'humangate';

export const STEP_KINDS = ['action', 'feedback', 'reward', 'progression', 'decision', 'other'];

// Ordre relatif imposé par le plan (§ Verrous GO Pierre) : chaque boucle doit
// comporter au moins une étape de CHAQUE kind ci-dessous, dans cet ordre relatif
// (les steps 'other' ne comptent pas et peuvent apparaître n'importe où).
export const REQUIRED_STEP_ORDER = ['action', 'feedback', 'reward', 'progression', 'decision'];

export const METRIC_KINDS = ['invariant', 'target', 'observation'];

export const PROOF_HOW = ['player_loop', 'decision', 'registry', 'hud', 'humangate'];

export const BLOCK_TYPES = ['LOCATION', 'ACTOR', 'ITEM', 'RULE', 'UI', 'RESOURCE'];

export const BLOCK_ROLES = [
  'PROGRESSION_GATE', 'AFFORDANCE', 'FEEDBACK', 'REWARD', 'CONTENT', 'META',
];

export const BLOCK_STATES = ['LOCKED', 'AVAILABLE', 'OWNED', 'PLACED', 'CONSUMED'];

const SOURCE_PREFIXES = ['worldscan:', 'story_bible:', 'art_bible:'];
const ARTIST_REQUIREMENT_TYPES = new Set(['LOCATION', 'ACTOR', 'ITEM', 'UI']);

function isStr(v) {
  return typeof v === 'string' && v.trim().length > 0;
}

function isPlainObject(v) {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

function isArr(v) {
  return Array.isArray(v);
}

function isFiniteNumber(v) {
  return typeof v === 'number' && Number.isFinite(v);
}

/**
 * Valide le bloc `game_master` complet. Ne lève jamais : toute anomalie de type
 * devient un problème nommé, jamais une exception.
 * @param {unknown} gm
 * @returns {{ok:boolean, problems:string[]}}
 */
export function validateGameMaster(gm) {
  const problems = [];

  if (!isPlainObject(gm)) {
    return { ok: false, problems: ["'game_master' absent ou n'est pas un objet"] };
  }

  // --- world_interpretation --------------------------------------------------
  const wi = gm.world_interpretation;
  if (!isArr(wi) || wi.length < 3) {
    problems.push("'game_master.world_interpretation' doit etre une liste d'au moins 3 faits");
  } else {
    wi.forEach((fact, i) => {
      const tag = `world_interpretation[${i}]`;
      if (!isPlainObject(fact)) {
        problems.push(`${tag} : doit etre un objet {fact, source}`);
        return;
      }
      if (!isStr(fact.fact)) {
        problems.push(`${tag} : 'fact' non vide obligatoire`);
      }
      if (!isStr(fact.source) || !SOURCE_PREFIXES.some((p) => fact.source.startsWith(p))) {
        problems.push(`${tag} : 'source' doit commencer par worldscan:|story_bible:|art_bible: (recu: ${fact.source ?? 'absent'})`);
      }
    });
  }

  // --- progression_metrics (validee AVANT loops : les steps referencent ses ids) --
  const metrics = gm.progression_metrics;
  const metricIds = new Set();
  const metricKindById = new Map();
  if (!isArr(metrics) || metrics.length === 0) {
    problems.push("'game_master.progression_metrics' doit etre une liste non vide");
  } else {
    let invariantCount = 0;
    let targetCount = 0;
    metrics.forEach((m, i) => {
      const tag = `progression_metrics[${i}]`;
      if (!isPlainObject(m)) {
        problems.push(`${tag} : doit etre un objet`);
        return;
      }
      if (!isStr(m.id)) {
        problems.push(`${tag} : 'id' non vide obligatoire`);
      } else if (metricIds.has(m.id)) {
        problems.push(`progression_metrics : id '${m.id}' duplique`);
      } else {
        metricIds.add(m.id);
        metricKindById.set(m.id, m.kind);
      }
      if (!METRIC_KINDS.includes(m.kind)) {
        problems.push(`${tag} (${m.id ?? '?'}) : 'kind' doit etre l'un de ${METRIC_KINDS.join('|')} (recu: ${m.kind ?? 'absent'})`);
      } else if (m.kind === 'invariant') {
        invariantCount += 1;
        if (!isFiniteNumber(m.value)) {
          problems.push(`${tag} (${m.id ?? '?'}) : kind=invariant exige 'value' numerique`);
        }
        if (!isStr(m.unit)) {
          problems.push(`${tag} (${m.id ?? '?'}) : kind=invariant exige 'unit' non vide`);
        }
      } else if (m.kind === 'target') {
        targetCount += 1;
        const range = m.range;
        if (!isPlainObject(range) || !isFiniteNumber(range.min) || !isFiniteNumber(range.max) || !(range.min < range.max)) {
          problems.push(`${tag} (${m.id ?? '?'}) : kind=target exige 'range' {min<max} numerique`);
        }
        if (!isStr(m.unit)) {
          problems.push(`${tag} (${m.id ?? '?'}) : kind=target exige 'unit' non vide`);
        }
      } else if (m.kind === 'observation') {
        if (!isStr(m.unit)) {
          problems.push(`${tag} (${m.id ?? '?'}) : kind=observation exige 'unit' non vide`);
        }
      }
      if (!isStr(m.why)) {
        problems.push(`${tag} (${m.id ?? '?'}) : 'why' non vide obligatoire`);
      }
    });
    if (invariantCount < 1) {
      problems.push("'game_master.progression_metrics' doit contenir au moins 1 metrique kind=invariant");
    }
    if (targetCount < 1) {
      problems.push("'game_master.progression_metrics' doit contenir au moins 1 metrique kind=target");
    }
  }

  // --- proof_model (validee avant loops : les steps referencent ses ids) --------
  const proofs = gm.proof_model;
  const proofIds = new Set();
  if (!isArr(proofs) || proofs.length === 0) {
    problems.push("'game_master.proof_model' doit etre une liste non vide");
  } else {
    proofs.forEach((p, i) => {
      const tag = `proof_model[${i}]`;
      if (!isPlainObject(p)) {
        problems.push(`${tag} : doit etre un objet`);
        return;
      }
      if (!isStr(p.id)) {
        problems.push(`${tag} : 'id' non vide obligatoire`);
      } else if (proofIds.has(p.id)) {
        problems.push(`proof_model : id '${p.id}' duplique`);
      } else {
        proofIds.add(p.id);
      }
      if (!isStr(p.measures)) {
        problems.push(`${tag} (${p.id ?? '?'}) : 'measures' non vide obligatoire`);
      }
      if (!PROOF_HOW.includes(p.how)) {
        problems.push(`${tag} (${p.id ?? '?'}) : 'how' doit etre l'un de ${PROOF_HOW.join('|')} (recu: ${p.how ?? 'absent'})`);
      }
      if (!isStr(p.expected)) {
        problems.push(`${tag} (${p.id ?? '?'}) : 'expected' non vide obligatoire`);
      }
    });
  }

  // --- loops -------------------------------------------------------------------
  // Lot C.4-code : chaque boucle est un OBJET {steps, produces, consumes, unlocks,
  // transformation_perceptible, metric_propre}, jamais plus un simple tableau.
  const loops = gm.loops;
  const allStepIds = new Set();
  const producesByLoop = new Map();
  const consumesByLoop = new Map();
  const metricPropreByLoop = new Map();
  const stepMetricRefsByLoop = new Map();
  if (!isPlainObject(loops)) {
    problems.push("'game_master.loops' doit etre un objet portant les 9 boucles");
  } else {
    LOOP_NAMES.forEach((loopName) => {
      const loopVal = loops[loopName];
      const tag = `loops.${loopName}`;
      if (!isPlainObject(loopVal)) {
        problems.push(`${tag} : doit etre un objet {steps, produces, consumes, unlocks, transformation_perceptible, metric_propre}`);
        return;
      }
      const steps = loopVal.steps;
      const localMetricRefs = new Set();
      if (!isArr(steps) || steps.length === 0) {
        problems.push(`${tag}.steps : doit etre une liste non vide d'etapes`);
      } else {
        const seenKinds = [];
        const localIds = new Set();
        steps.forEach((s, i) => {
          const stag = `${tag}.steps[${i}]`;
          if (!isPlainObject(s)) {
            problems.push(`${stag} : doit etre un objet`);
            return;
          }
          if (!isStr(s.id)) {
            problems.push(`${stag} : 'id' non vide obligatoire`);
          } else if (localIds.has(s.id)) {
            problems.push(`${tag} : id '${s.id}' duplique`);
          } else {
            localIds.add(s.id);
            allStepIds.add(s.id);
          }
          if (!STEP_KINDS.includes(s.kind)) {
            problems.push(`${stag} (${s.id ?? '?'}) : 'kind' doit etre l'un de ${STEP_KINDS.join('|')} (recu: ${s.kind ?? 'absent'})`);
          } else if (s.kind !== 'other') {
            seenKinds.push(s.kind);
          }
          if (s.actor !== 'PLAYER' && s.actor !== 'SYSTEM') {
            problems.push(`${stag} (${s.id ?? '?'}) : 'actor' doit etre PLAYER|SYSTEM (recu: ${s.actor ?? 'absent'})`);
          }
          if (!isStr(s.why)) {
            problems.push(`${stag} (${s.id ?? '?'}) : 'why' non vide obligatoire`);
          }
          if (!isStr(s.metric_ref)) {
            problems.push(`${stag} (${s.id ?? '?'}) : 'metric_ref' non vide obligatoire`);
          } else {
            localMetricRefs.add(s.metric_ref);
            if (isArr(metrics) && !metricIds.has(s.metric_ref)) {
              problems.push(`${stag} (${s.id ?? '?'}) : 'metric_ref' ('${s.metric_ref}') ne resout aucun id de progression_metrics`);
            }
          }
          if (!isStr(s.proof_ref)) {
            problems.push(`${stag} (${s.id ?? '?'}) : 'proof_ref' non vide obligatoire`);
          } else if (isArr(proofs) && !proofIds.has(s.proof_ref)) {
            problems.push(`${stag} (${s.id ?? '?'}) : 'proof_ref' ('${s.proof_ref}') ne resout aucun id de proof_model`);
          }
        });
        // Ordre relatif : chaque kind requis doit apparaitre, dans cet ordre.
        let cursor = -1;
        for (const kind of REQUIRED_STEP_ORDER) {
          const idx = seenKinds.indexOf(kind, cursor + 1);
          if (idx === -1) {
            problems.push(`${tag}.steps : etape de kind '${kind}' manquante (ordre requis: ${REQUIRED_STEP_ORDER.join(' -> ')})`);
            break;
          }
          cursor = idx;
        }
      }
      stepMetricRefsByLoop.set(loopName, localMetricRefs);

      // --- produces (R2a) --------------------------------------------------
      if (!isStr(loopVal.produces)) {
        problems.push(`${tag}.produces : chaine non vide obligatoire`);
      } else {
        producesByLoop.set(loopName, loopVal.produces);
      }

      // --- consumes / unlocks : listes de noms de boucles existants --------
      if (!isArr(loopVal.consumes) || !loopVal.consumes.every((c) => isStr(c) && LOOP_NAMES.includes(c))) {
        problems.push(`${tag}.consumes : doit etre une liste de noms de boucles existants (${LOOP_NAMES.join('|')})`);
      } else {
        consumesByLoop.set(loopName, loopVal.consumes);
      }
      if (!isArr(loopVal.unlocks) || !loopVal.unlocks.every((u) => isStr(u) && LOOP_NAMES.includes(u))) {
        problems.push(`${tag}.unlocks : doit etre une liste de noms de boucles existants (${LOOP_NAMES.join('|')})`);
      }

      // --- transformation_perceptible (R2b) ---------------------------------
      const tp = loopVal.transformation_perceptible;
      if (!isPlainObject(tp)) {
        problems.push(`${tag}.transformation_perceptible : doit etre un objet {text, proof_ref}`);
      } else {
        if (!isStr(tp.text)) {
          problems.push(`${tag}.transformation_perceptible.text : chaine non vide obligatoire`);
        }
        if (!isStr(tp.proof_ref)) {
          problems.push(`${tag}.transformation_perceptible.proof_ref : chaine non vide obligatoire`);
        } else if (isArr(proofs)) {
          const proof = proofs.find((p) => isPlainObject(p) && p.id === tp.proof_ref);
          if (!proof) {
            problems.push(`${tag}.transformation_perceptible.proof_ref ('${tp.proof_ref}') ne resout aucun id de proof_model`);
          } else if (proof.how === TRANSFORMATION_PROOF_HOW_FORBIDDEN) {
            problems.push(`${tag}.transformation_perceptible.proof_ref ('${tp.proof_ref}') : 'how'='humangate' seul refuse (doit etre l'un de player_loop|hud|decision|registry)`);
          }
        }
      }

      // --- metric_propre (exclusivite verifiee APRES la boucle) ------------
      if (!isStr(loopVal.metric_propre)) {
        problems.push(`${tag}.metric_propre : id non vide obligatoire`);
      } else if (isArr(metrics) && !metricIds.has(loopVal.metric_propre)) {
        problems.push(`${tag}.metric_propre ('${loopVal.metric_propre}') ne resout aucun id de progression_metrics`);
      } else {
        metricPropreByLoop.set(loopName, loopVal.metric_propre);
      }
    });

    // R2a GLOBALE : chaque 'produces' doit etre reference par le 'consumes' d'au
    // moins une AUTRE boucle -- sinon boucle orpheline, refusee en la nommant.
    const consumedLoopNames = new Set();
    consumesByLoop.forEach((list, loopName) => {
      list.forEach((c) => { if (c !== loopName) consumedLoopNames.add(c); });
    });
    producesByLoop.forEach((_produces, loopName) => {
      if (!consumedLoopNames.has(loopName)) {
        problems.push(`loops.${loopName} : 'produces' n'est reference par le 'consumes' d'aucune autre boucle (R2a, boucle orpheline)`);
      }
    });

    // Exclusivite metric_propre (C.4) : un id de progression_metrics utilise en
    // metric_propre par une boucle ne doit apparaitre NULLE PART ailleurs -- ni
    // comme metric_propre d'une autre boucle, ni comme metric_ref d'une de ses
    // etapes.
    metricPropreByLoop.forEach((mid, loopName) => {
      LOOP_NAMES.forEach((otherLoop) => {
        if (otherLoop === loopName) return;
        if (metricPropreByLoop.get(otherLoop) === mid) {
          problems.push(`loops.${loopName}.metric_propre ('${mid}') : partagee avec loops.${otherLoop}.metric_propre (exclusivite requise)`);
        }
        const otherRefs = stepMetricRefsByLoop.get(otherLoop);
        if (otherRefs && otherRefs.has(mid)) {
          problems.push(`loops.${loopName}.metric_propre ('${mid}') : deja utilisee comme metric_ref dans loops.${otherLoop} (exclusivite requise)`);
        }
      });
    });
  }

  // --- economy_model -------------------------------------------------------------
  const economy = gm.economy_model;
  const resourceIds = new Set();
  if (!isPlainObject(economy)) {
    problems.push("'game_master.economy_model' doit etre un objet {resources[], formulas[]}");
  } else {
    const resources = economy.resources;
    if (!isArr(resources) || resources.length === 0) {
      problems.push("'game_master.economy_model.resources' doit etre une liste non vide");
    } else {
      resources.forEach((r, i) => {
        const tag = `economy_model.resources[${i}]`;
        if (!isPlainObject(r)) {
          problems.push(`${tag} : doit etre un objet`);
          return;
        }
        if (!isStr(r.id)) {
          problems.push(`${tag} : 'id' non vide obligatoire`);
        } else if (resourceIds.has(r.id)) {
          problems.push(`economy_model.resources : id '${r.id}' duplique`);
        } else {
          resourceIds.add(r.id);
        }
        if (!isStr(r.unit)) {
          problems.push(`${tag} (${r.id ?? '?'}) : 'unit' non vide obligatoire`);
        }
        if (!isArr(r.sources)) {
          problems.push(`${tag} (${r.id ?? '?'}) : 'sources' doit etre un tableau`);
        }
        if (!isArr(r.sinks)) {
          problems.push(`${tag} (${r.id ?? '?'}) : 'sinks' doit etre un tableau`);
        }
        if (!isFiniteNumber(r.initial_stock)) {
          problems.push(`${tag} (${r.id ?? '?'}) : 'initial_stock' doit etre numerique`);
        }
      });
    }
    const formulas = economy.formulas;
    const formulaIds = new Set();
    if (!isArr(formulas) || formulas.length === 0) {
      problems.push("'game_master.economy_model.formulas' doit etre une liste non vide");
    } else {
      formulas.forEach((f, i) => {
        const tag = `economy_model.formulas[${i}]`;
        if (!isPlainObject(f)) {
          problems.push(`${tag} : doit etre un objet`);
          return;
        }
        if (!isStr(f.id)) {
          problems.push(`${tag} : 'id' non vide obligatoire`);
        } else if (formulaIds.has(f.id)) {
          problems.push(`economy_model.formulas : id '${f.id}' duplique`);
        } else {
          formulaIds.add(f.id);
        }
        if (!isStr(f.text)) {
          problems.push(`${tag} (${f.id ?? '?'}) : 'text' non vide obligatoire`);
        }
        if (!isPlainObject(f.params)) {
          problems.push(`${tag} (${f.id ?? '?'}) : 'params' doit etre un objet`);
        }
      });
    }
  }

  // Chaque metrique invariant|target doit etre mesuree par >=1 preuve.
  if (isArr(metrics) && isArr(proofs)) {
    for (const [id, kind] of metricKindById) {
      if (kind !== 'invariant' && kind !== 'target') continue;
      if (!proofs.some((p) => isPlainObject(p) && p.measures === id)) {
        problems.push(`progression_metrics : metrique '${id}' (kind=${kind}) n'est mesuree par aucun proof_model`);
      }
    }
  }

  // --- grey_blocks -----------------------------------------------------------
  const greyBlocks = gm.grey_blocks;
  const greyBlockIds = new Set();
  const greyBlockTypeById = new Map();
  if (!isArr(greyBlocks) || greyBlocks.length === 0) {
    problems.push("'game_master.grey_blocks' doit etre une liste non vide");
  } else {
    greyBlocks.forEach((b, i) => {
      const tag = `grey_blocks[${i}]`;
      if (!isPlainObject(b)) {
        problems.push(`${tag} : doit etre un objet`);
        return;
      }
      if (!isStr(b.id)) {
        problems.push(`${tag} : 'id' non vide obligatoire`);
      } else if (greyBlockIds.has(b.id)) {
        problems.push(`grey_blocks : id '${b.id}' duplique`);
      } else {
        greyBlockIds.add(b.id);
        greyBlockTypeById.set(b.id, b.type);
      }
      if (!BLOCK_TYPES.includes(b.type)) {
        problems.push(`${tag} (${b.id ?? '?'}) : 'type' doit etre l'un de ${BLOCK_TYPES.join('|')} (recu: ${b.type ?? 'absent'})`);
      }
      if (!BLOCK_ROLES.includes(b.role)) {
        problems.push(`${tag} (${b.id ?? '?'}) : 'role' doit etre l'un de ${BLOCK_ROLES.join('|')} (recu: ${b.role ?? 'absent'})`);
      }
      if (!BLOCK_STATES.includes(b.state)) {
        problems.push(`${tag} (${b.id ?? '?'}) : 'state' doit etre l'un de ${BLOCK_STATES.join('|')} (recu: ${b.state ?? 'absent'})`);
      }
      if (!isArr(b.requires)) {
        problems.push(`${tag} (${b.id ?? '?'}) : 'requires' doit etre un tableau`);
      }
      if (!isStr(b.player_meaning)) {
        problems.push(`${tag} (${b.id ?? '?'}) : 'player_meaning' non vide obligatoire`);
      }
      if (!isStr(b.builder_contract)) {
        problems.push(`${tag} (${b.id ?? '?'}) : 'builder_contract' non vide obligatoire`);
      }
      if (!isStr(b.proof_ref)) {
        problems.push(`${tag} (${b.id ?? '?'}) : 'proof_ref' non vide obligatoire`);
      } else if (isArr(proofs) && !proofIds.has(b.proof_ref)) {
        problems.push(`${tag} (${b.id ?? '?'}) : 'proof_ref' ('${b.proof_ref}') ne resout aucun id de proof_model`);
      }
      // Lot D (2026-08-23, GO Pierre, contrat s2.7 C.2) : `unlock`/`next_goal`
      // ADDITIFS et OPTIONNELS — valides SEULEMENT s'ils sont presents (fixtures
      // existantes, sans ces champs, restent inchangees). Regle maitresse :
      // UNLOCK != +X% ; UNLOCK = possibilite PERCEPTIBLE (a voir et/ou a faire) —
      // validee ici au minimum deterministe (builder_contract + player_meaning
      // non vides, deja verifies ci-dessus), le reste (le changement de scene/
      // interaction est-il REEL) est red-team/HumanGate, jamais cette fonction.
      if (b.unlock !== undefined) {
        if (!isArr(b.unlock) || !b.unlock.every((u) => isStr(u))) {
          problems.push(`${tag} (${b.id ?? '?'}) : 'unlock' doit etre un tableau d'ids non vides`);
        }
      }
      if (b.next_goal !== undefined && !isStr(b.next_goal)) {
        problems.push(`${tag} (${b.id ?? '?'}) : 'next_goal' doit etre une chaine non vide`);
      }
    });
    // requires[] resolus APRES la 1ere passe (metricIds + greyBlockIds connus).
    greyBlocks.forEach((b, i) => {
      if (!isPlainObject(b) || !isArr(b.requires)) return;
      const tag = `grey_blocks[${i}] (${b.id ?? '?'})`;
      b.requires.forEach((ref) => {
        if (!isStr(ref) || (!metricIds.has(ref) && !greyBlockIds.has(ref))) {
          problems.push(`${tag} : 'requires' reference '${ref}' qui ne resout ni une metrique ni un grey_block`);
        }
      });
    });
    // unlock[] resolus APRES la 1ere passe (greyBlockIds + affordances des
    // loops connus) — un id de grey_block OU une affordance citee par un step
    // de boucle (Lot D, contrat s2.7 C.2 : "ids de grey blocks / affordances").
    const loopAffordances = new Set();
    if (isPlainObject(loops)) {
      LOOP_NAMES.forEach((loopName) => {
        const stepsForLoop = isPlainObject(loops[loopName]) ? loops[loopName].steps : undefined;
        if (!isArr(stepsForLoop)) return;
        stepsForLoop.forEach((s) => {
          if (isPlainObject(s) && isStr(s.affordance)) loopAffordances.add(s.affordance);
        });
      });
    }
    greyBlocks.forEach((b, i) => {
      if (!isPlainObject(b) || !isArr(b.unlock)) return;
      const tag = `grey_blocks[${i}] (${b.id ?? '?'})`;
      b.unlock.forEach((ref) => {
        if (!isStr(ref) || (!greyBlockIds.has(ref) && !loopAffordances.has(ref))) {
          problems.push(`${tag} : 'unlock' reference '${ref}' qui ne resout ni un grey_block ni une affordance de loops`);
        }
      });
    });
  }

  // --- artist_requirements -----------------------------------------------------
  const artistReqs = gm.artist_requirements;
  const artistReqIds = new Set();
  const requirementsByGreyBlock = new Map();
  if (!isArr(artistReqs) || artistReqs.length === 0) {
    problems.push("'game_master.artist_requirements' doit etre une liste non vide");
  } else {
    artistReqs.forEach((a, i) => {
      const tag = `artist_requirements[${i}]`;
      if (!isPlainObject(a)) {
        problems.push(`${tag} : doit etre un objet`);
        return;
      }
      if (!isStr(a.id)) {
        problems.push(`${tag} : 'id' non vide obligatoire`);
      } else if (artistReqIds.has(a.id)) {
        problems.push(`artist_requirements : id '${a.id}' duplique`);
      } else {
        artistReqIds.add(a.id);
      }
      if (!isStr(a.grey_block) || (isArr(greyBlocks) && !greyBlockIds.has(a.grey_block))) {
        problems.push(`${tag} (${a.id ?? '?'}) : 'grey_block' ne resout aucun id de grey_blocks (recu: ${a.grey_block ?? 'absent'})`);
      } else {
        const list = requirementsByGreyBlock.get(a.grey_block) || [];
        list.push(a.id);
        requirementsByGreyBlock.set(a.grey_block, list);
      }
      if (!isArr(a.states_to_show) || a.states_to_show.length === 0
          || !a.states_to_show.every((st) => BLOCK_STATES.includes(st))) {
        problems.push(`${tag} (${a.id ?? '?'}) : 'states_to_show' doit etre une liste non vide sous-ensemble de ${BLOCK_STATES.join('|')}`);
      }
      if (typeof a.visible_reason !== 'boolean') {
        problems.push(`${tag} (${a.id ?? '?'}) : 'visible_reason' doit etre booleen`);
      }
      if (!isStr(a.visible_requirement)) {
        problems.push(`${tag} (${a.id ?? '?'}) : 'visible_requirement' non vide obligatoire`);
      }
      if (typeof a.preview !== 'boolean') {
        problems.push(`${tag} (${a.id ?? '?'}) : 'preview' doit etre booleen`);
      }
      if (!isStr(a.affordance_visual)) {
        problems.push(`${tag} (${a.id ?? '?'}) : 'affordance_visual' non vide obligatoire`);
      }
      if (!isStr(a.readability)) {
        problems.push(`${tag} (${a.id ?? '?'}) : 'readability' non vide obligatoire`);
      }
    });
  }

  // Couverture : chaque grey_block de type LOCATION|ACTOR|ITEM|UI a >=1 requirement.
  if (isArr(greyBlocks)) {
    for (const [id, type] of greyBlockTypeById) {
      if (!ARTIST_REQUIREMENT_TYPES.has(type)) continue;
      if (!(requirementsByGreyBlock.get(id) || []).length) {
        problems.push(`grey_blocks : '${id}' (type=${type}) n'a aucun artist_requirements`);
      }
    }
  }

  // Ressource citee par une etape reward/progression (champ optionnel `resource`).
  if (isPlainObject(loops) && isArr(gm.economy_model?.resources)) {
    LOOP_NAMES.forEach((loopName) => {
      const steps = isPlainObject(loops[loopName]) ? loops[loopName].steps : undefined;
      if (!isArr(steps)) return;
      steps.forEach((s, i) => {
        if (!isPlainObject(s) || s.resource === undefined) return;
        if (!isStr(s.resource) || !resourceIds.has(s.resource)) {
          problems.push(`loops.${loopName}.steps[${i}] (${s.id ?? '?'}) : 'resource' ('${s.resource}') ne resout aucun id de economy_model.resources`);
        }
      });
    });
  }

  return { ok: problems.length === 0, problems };
}

/**
 * Projection DÉTERMINISTE de `economy_model` + `progression_metrics[kind=invariant]`
 * vers `economy.json`. Fonction PURE : aucune horloge, aucun aléa. Trie tout par id
 * pour un hash stable entre deux appels sur la même entrée.
 * @param {unknown} gm
 * @returns {{schema_version:1, resources:object[], formulas:object[], invariants:object[]}}
 */
export function projectEconomy(gm) {
  const economy = isPlainObject(gm?.economy_model) ? gm.economy_model : {};
  const resources = (isArr(economy.resources) ? economy.resources : [])
    .filter(isPlainObject)
    .map((r) => ({
      id: isStr(r.id) ? r.id : '',
      unit: isStr(r.unit) ? r.unit : '',
      sources: isArr(r.sources) ? [...r.sources] : [],
      sinks: isArr(r.sinks) ? [...r.sinks] : [],
      initial_stock: isFiniteNumber(r.initial_stock) ? r.initial_stock : 0,
    }))
    .sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));

  const formulas = (isArr(economy.formulas) ? economy.formulas : [])
    .filter(isPlainObject)
    .map((f) => ({
      id: isStr(f.id) ? f.id : '',
      text: isStr(f.text) ? f.text : '',
      params: isPlainObject(f.params) ? { ...f.params } : {},
    }))
    .sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));

  const metrics = isArr(gm?.progression_metrics) ? gm.progression_metrics : [];
  const invariants = metrics
    .filter((m) => isPlainObject(m) && m.kind === 'invariant')
    .map((m) => ({
      id: isStr(m.id) ? m.id : '',
      value: isFiniteNumber(m.value) ? m.value : 0,
      unit: isStr(m.unit) ? m.unit : '',
      why: isStr(m.why) ? m.why : '',
    }))
    .sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));

  return { schema_version: 1, resources, formulas, invariants };
}

// ---- CLI ----
const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const argv = process.argv.slice(2);
  const jsonFlag = argv.includes('--json');
  const econIdx = argv.indexOf('--economy');
  const econOut = econIdx >= 0 ? argv[econIdx + 1] : null;
  const target = argv.find((a, i) => a !== '--json' && a !== '--economy'
    && (econIdx < 0 || i !== econIdx + 1));

  if (!target) {
    console.error('usage: node game_master_schema.mjs <gm_worldscan.json> [--json] [--economy <out>]');
    process.exit(2);
  }

  let data;
  try {
    data = JSON.parse(readFileSync(target, 'utf-8'));
  } catch (err) {
    console.error(`game_master_schema: ${target}: absent, illisible ou JSON invalide (${err.message})`);
    process.exit(2);
  }

  const gm = data && typeof data === 'object' ? data.game_master : undefined;
  const result = validateGameMaster(gm);

  if (econOut) {
    const economy = projectEconomy(isPlainObject(gm) ? gm : {});
    writeFileSync(econOut, JSON.stringify(economy, null, 1), 'utf-8');
  }

  if (jsonFlag) {
    process.stdout.write(JSON.stringify(result));
  } else {
    console.log(`VERDICT GAME_MASTER: ${result.ok ? 'OK' : 'FAIL'}`);
    result.problems.forEach((p) => console.error(`  FAIL: ${p}`));
    console.log(JSON.stringify(result, null, 2));
  }
  process.exit(result.ok ? 0 : 1);
}
