#!/usr/bin/env node
// loop_spec.mjs — dérivation DÉTERMINISTE de `loop.json` depuis `prisme.json`.
//
// VERROU ABSOLU (GO Pierre 2026-08-22) : `loop.json` est une PROJECTION du
// Prisme, jamais une source de vérité. `deriveLoopSpec` est une fonction PURE —
// même entrée -> même sortie, JAMAIS `Date.now()`, JAMAIS `Math.random()` —
// écrite par l'EXÉCUTEUR (run_real.py), aucun LLM ne l'écrit. Si la sortie d'un
// agent s1 contient un bloc ```json``` nommé `loop` ou un fichier `loop.json`,
// il est IGNORÉ.
//
// Usage :
//   node loop_spec.mjs <prisme.json> [--json]
// Exit 0 = boucle complète (checkLoopSpec OK) · 1 = boucle incomplète (FAIL,
// mesure du diagnostic) · 2 = usage / fichier illisible.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

// Séquence imposée (Pierre, Gameplay Contract 2026-08-22) — 10 rôles de boucle
// (A..J), NONE exclu (hors boucle par définition). Ordre de tri des steps :
// ordre des rôles, puis ordre des ids. C n'est pas un rôle (AFFORDANCE est
// portée par B, cf. loop_spec.mjs commentaire de tête).
export const ROLE_ORDER = [
  'PLAYER_GOAL', 'PLAYER_ACTION', 'GAME_RESPONSE', 'REWARD', 'DECISION',
  'UNLOCK', 'NEXT_GOAL', 'REPEAT', 'META_LOOP', 'ADVANTAGE',
];

// Lettre du contrat (A..J, C absent car porté par B) par rôle — utilisée pour
// nommer chaque problème `maillon <lettre> (<ROLE>) : …`.
export const LETTER_BY_ROLE = {
  PLAYER_GOAL: 'A',
  PLAYER_ACTION: 'B',
  GAME_RESPONSE: 'D',
  REWARD: 'E',
  UNLOCK: 'F',
  NEXT_GOAL: 'G',
  REPEAT: 'H',
  META_LOOP: 'I',
  ADVANTAGE: 'J',
};

// Rôles rejouables par un maillon H (REPEAT) : B..F du contrat.
const REPLAYABLE_ROLES = new Set(['PLAYER_ACTION', 'GAME_RESPONSE', 'REWARD', 'UNLOCK']);

function maillon(role) {
  return `maillon ${LETTER_BY_ROLE[role] || '?'} (${role || '?'})`;
}

// DECISION n'a pas de lettre A..J (extension 2026-08-23, cf. plan du point de
// decision significative) : messages nommes `maillon DECISION (<ref>) : …`.
function maillonDecision(ref) {
  return `maillon DECISION (${ref || '?'})`;
}

/**
 * Dérive `loop.json` depuis un `prisme.json` déjà parsé. PURE : aucune horloge,
 * aucun aléa, aucun effet de bord. Steps = exigences dont `loop_role` est un des
 * 7 rôles de ROLE_ORDER (NONE et absent sont exclus), triées par ordre de rôle
 * puis par `id` (tri stable : à id égal ou absent, l'ordre d'apparition dans
 * `exigences` est conservé).
 * `opts` reserve pour extension future (non utilise a ce jour) ; ne change
 * aucun comportement, present pour compat d'appel.
 * @param {unknown} prisme
 * @param {{}} [opts]
 * @returns {{schema_version:1, game_id:string, steps:object[]}}
 */
export function deriveLoopSpec(prisme, opts = {}) {
  const gameId = typeof prisme?.game_id === 'string' ? prisme.game_id : '';
  const exigences = Array.isArray(prisme?.exigences) ? prisme.exigences : [];

  const candidats = [];
  exigences.forEach((ex, idx) => {
    if (ex && typeof ex === 'object' && ROLE_ORDER.includes(ex.loop_role)) {
      candidats.push({ ex, idx });
    }
  });

  // FUITE 2 (Lot D, 2026-08-23, GO Pierre) : le tri alphabetique des `id` au sein
  // d'un role cassait la precedence VOULUE par le Prisme (ex. G2 avant G1 alors
  // que le Prisme les avait ecrites dans l'ordre G2 -> G1 par intention). Le
  // Prisme ECRIT les exigences dans l'ordre ou le joueur les vit (P01 -> P12,
  // cf. contrat s1) — cet ordre D'APPARITION dans `prisme.exigences` EST la
  // precedence jouee, plus jamais l'alphabet. Determinisme conserve : `idx` est
  // l'index d'apparition, stable, jamais une horloge ni un alea.
  candidats.sort((a, b) => {
    const ra = ROLE_ORDER.indexOf(a.ex.loop_role);
    const rb = ROLE_ORDER.indexOf(b.ex.loop_role);
    if (ra !== rb) return ra - rb;
    return a.idx - b.idx; // ordre d'apparition dans prisme.exigences (precedence Prisme)
  });

  const steps = candidats.map(({ ex }) => {
    const step = {
      role: ex.loop_role,
      ref: typeof ex.id === 'string' ? ex.id : '',
    };
    if (typeof ex.affordance === 'string' && ex.affordance.trim().length > 0) {
      step.affordance = ex.affordance;
    }
    step.repeat = Number.isInteger(ex.repeat) && ex.repeat >= 1 ? ex.repeat : 1;
    if (ex.observe !== null && typeof ex.observe === 'object' && !Array.isArray(ex.observe)) {
      const observe = {};
      if (typeof ex.observe.hud === 'string' && ex.observe.hud.trim().length > 0) {
        observe.hud = ex.observe.hud;
      }
      if (typeof ex.observe.predicate === 'string' && ex.observe.predicate.trim().length > 0) {
        observe.predicate = ex.observe.predicate;
      }
      if (typeof ex.observe.appears === 'string' && ex.observe.appears.trim().length > 0) {
        observe.appears = ex.observe.appears;
      }
      if (Object.keys(observe).length > 0) step.observe = observe;
      if (Number.isInteger(ex.observe.wait_frames)) step.wait_frames = ex.observe.wait_frames;
    }
    if (ex.loop_role === 'REPEAT' && Array.isArray(ex.replay)) {
      const replay = ex.replay.filter((r) => typeof r === 'string' && r.trim().length > 0);
      if (replay.length > 0) step.replay = replay;
    }
    if (ex.loop_role === 'ADVANTAGE' && typeof ex.replay_ref === 'string' && ex.replay_ref.trim().length > 0) {
      step.replay_ref = ex.replay_ref;
    }
    if (ex.loop_role === 'DECISION') {
      if (Array.isArray(ex.options)) {
        step.options = ex.options.filter((o) => typeof o === 'string' && o.trim().length > 0);
      }
      if (typeof ex.metric === 'string' && ex.metric.trim().length > 0) {
        step.metric = ex.metric;
      }
      if (Number.isInteger(ex.horizon_frames)) {
        step.horizon_frames = ex.horizon_frames;
      }
      if (Array.isArray(ex.policies)) {
        step.policies = ex.policies
          .filter((p) => p && typeof p === 'object' && !Array.isArray(p))
          .map((p) => ({
            name: typeof p.name === 'string' ? p.name : '',
            click: p.click === null ? null : (typeof p.click === 'string' ? p.click : null),
            every_frames: Number.isInteger(p.every_frames) ? p.every_frames : 0,
          }));
      }
    }
    // target_frames (Lot B T4, 2026-08-23) : champ pose par le Prisme en
    // recopiant une metrique `target` du Game Master (unite frames, deja
    // convertie depuis des secondes a 60 fps), cite dans `target.ref`
    // (adresse `gm_worldscan:game_master.progression_metrics.<id>`). Projete
    // des lors que la forme est exploitable (entiers, min >= 0, ref non vide) ;
    // la relation min < max est validee par checkLoopSpec (jamais ici), pour
    // que l'incoherence produise un probleme NOMME plutot qu'une omission
    // silencieuse.
    if (ex.target !== null && typeof ex.target === 'object' && !Array.isArray(ex.target)) {
      const minF = ex.target.min_frames;
      const maxF = ex.target.max_frames;
      const ref = ex.target.ref;
      if (Number.isInteger(minF) && minF >= 0 && Number.isInteger(maxF)
        && typeof ref === 'string' && ref.trim().length > 0) {
        step.target_frames = { min: minF, max: maxF, ref };
      }
    }
    return step;
  });

  return { schema_version: 1, game_id: gameId, steps };
}

/**
 * Le Gameplay Contract check (GO Pierre 2026-08-22) : vérifie que la boucle
 * dérivée ferme réellement (G -> H -> I -> J -> H'), pas seulement qu'elle
 * s'ouvre. Règles a..i (lettres du contrat, cf. le plan) :
 *   (a) `observe` {hud, predicate} obligatoire pour TOUT step (rôle != NONE,
 *       déjà exclu par construction de `deriveLoopSpec`).
 *   (b) A (PLAYER_GOAL) >= 1.
 *   (c) B (PLAYER_ACTION) >= 1, au moins une avec `affordance`.
 *   (d) D (GAME_RESPONSE) >= 1, E (REWARD) >= 1.
 *   (e) F (UNLOCK) >= 1, au moins une avec `affordance` ET `observe.appears`
 *       non vide (preuve de Progression).
 *   (f) G (NEXT_GOAL) >= 2, toutes `predicate === 'new_distinct'`, même hud.
 *   (g) H (REPEAT) >= 1, `replay` non vide dont chaque ref existe et est de
 *       rôle B..F (PLAYER_ACTION|GAME_RESPONSE|REWARD|UNLOCK).
 *   (h) I (META_LOOP) >= 1, au moins une avec `affordance`.
 *   (i) J (ADVANTAGE) >= 1, `replay_ref` = ref d'un step B, `observe.predicate`
 *       cohérent (`increases_more_than:<replay_ref>`).
 * Chaque problème est nommé `maillon <lettre> (<ROLE>) : …`.
 * @param {unknown} spec sortie de deriveLoopSpec
 * @returns {{ok:boolean, verdict:'OK'|'FAIL', problems:string[]}}
 */
export function checkLoopSpec(spec) {
  const problems = [];
  const steps = Array.isArray(spec?.steps) ? spec.steps : [];
  const byRole = (role) => steps.filter((s) => s && s.role === role);

  // (a) observe {hud, predicate} obligatoire pour tout step.
  steps.forEach((s, i) => {
    if (!s || typeof s !== 'object') {
      problems.push(`steps[${i}]: doit etre un objet`);
      return;
    }
    const ok = s.observe && typeof s.observe === 'object' && !Array.isArray(s.observe)
      && typeof s.observe.hud === 'string' && s.observe.hud.trim().length > 0
      && typeof s.observe.predicate === 'string' && s.observe.predicate.trim().length > 0;
    if (!ok) {
      problems.push(`${maillon(s.role)} (${s.ref || '?'}) : observe {hud, predicate} obligatoire`);
    }
  });

  // (a2) target_frames (Lot B T4) : si present, doit etre valide (min < max,
  // ref string non vide) — jamais exige (un step peut ne jamais en porter).
  steps.forEach((s) => {
    if (!s || typeof s !== 'object' || !s.target_frames) return;
    const tf = s.target_frames;
    const shapeOk = tf && typeof tf === 'object' && !Array.isArray(tf)
      && Number.isInteger(tf.min) && Number.isInteger(tf.max)
      && typeof tf.ref === 'string' && tf.ref.trim().length > 0;
    if (!shapeOk) {
      problems.push(`${maillon(s.role)} (${s.ref || '?'}) : target_frames malforme`);
      return;
    }
    if (!(tf.min < tf.max)) {
      problems.push(`${maillon(s.role)} (${s.ref || '?'}) : target_frames min (${tf.min}) >= max (${tf.max})`);
    }
  });

  // (b) A >= 1.
  if (byRole('PLAYER_GOAL').length < 1) {
    problems.push(`${maillon('PLAYER_GOAL')} : au moins 1 exigence attendue (0 trouvee)`);
  }

  // (c) B >= 1, au moins une avec affordance.
  const bSteps = byRole('PLAYER_ACTION');
  if (bSteps.length < 1) {
    problems.push(`${maillon('PLAYER_ACTION')} : au moins 1 exigence attendue (0 trouvee)`);
  } else if (!bSteps.some((s) => typeof s.affordance === 'string' && s.affordance.trim().length > 0)) {
    problems.push(`${maillon('PLAYER_ACTION')} : au moins une exigence doit porter affordance`);
  }

  // (d) D, E >= 1.
  if (byRole('GAME_RESPONSE').length < 1) {
    problems.push(`${maillon('GAME_RESPONSE')} : au moins 1 exigence attendue (0 trouvee)`);
  }
  if (byRole('REWARD').length < 1) {
    problems.push(`${maillon('REWARD')} : au moins 1 exigence attendue (0 trouvee)`);
  }

  // (e) F >= 1, au moins une avec affordance ET observe.appears.
  const fSteps = byRole('UNLOCK');
  if (fSteps.length < 1) {
    problems.push(`${maillon('UNLOCK')} : au moins 1 exigence attendue (0 trouvee)`);
  } else {
    if (!fSteps.some((s) => typeof s.affordance === 'string' && s.affordance.trim().length > 0)) {
      problems.push(`${maillon('UNLOCK')} : au moins une exigence doit porter affordance`);
    }
    if (!fSteps.some((s) => s.observe && typeof s.observe.appears === 'string' && s.observe.appears.trim().length > 0)) {
      problems.push(`${maillon('UNLOCK')} : au moins une exigence doit porter observe.appears (preuve de Progression)`);
    }
  }

  // (f) G >= 2, toutes new_distinct, meme hud.
  const gSteps = byRole('NEXT_GOAL');
  if (gSteps.length < 2) {
    problems.push(`${maillon('NEXT_GOAL')} : au moins 2 exigences attendues (${gSteps.length} trouvee(s))`);
  } else {
    const badPredicate = gSteps.filter((s) => !s.observe || s.observe.predicate !== 'new_distinct');
    if (badPredicate.length > 0) {
      problems.push(`${maillon('NEXT_GOAL')} : observe.predicate doit valoir 'new_distinct' pour toutes les exigences (fautif(s): ${badPredicate.map((s) => s.ref || '?').join(', ')})`);
    }
    const huds = new Set(gSteps.map((s) => s.observe && s.observe.hud).filter((h) => typeof h === 'string' && h.length > 0));
    if (huds.size > 1) {
      problems.push(`${maillon('NEXT_GOAL')} : toutes les exigences doivent observer le meme hud (recu: ${[...huds].join(', ')})`);
    }
  }

  // (g) H >= 1, replay non vide, chaque ref existe et est de role B..F.
  const hSteps = byRole('REPEAT');
  if (hSteps.length < 1) {
    problems.push(`${maillon('REPEAT')} : au moins 1 exigence attendue (0 trouvee)`);
  } else {
    const replayableRefs = new Set(steps.filter((s) => s && REPLAYABLE_ROLES.has(s.role)).map((s) => s.ref));
    hSteps.forEach((s) => {
      if (!Array.isArray(s.replay) || s.replay.length === 0) {
        problems.push(`${maillon('REPEAT')} (${s.ref || '?'}) : replay doit etre un tableau non vide`);
        return;
      }
      const invalides = s.replay.filter((ref) => !replayableRefs.has(ref));
      if (invalides.length > 0) {
        problems.push(`${maillon('REPEAT')} (${s.ref || '?'}) : replay reference des refs invalides ou hors role B..F (${invalides.join(', ')})`);
      }
    });
  }

  // (h) I >= 1, au moins une avec affordance.
  const iSteps = byRole('META_LOOP');
  if (iSteps.length < 1) {
    problems.push(`${maillon('META_LOOP')} : au moins 1 exigence attendue (0 trouvee)`);
  } else if (!iSteps.some((s) => typeof s.affordance === 'string' && s.affordance.trim().length > 0)) {
    problems.push(`${maillon('META_LOOP')} : au moins une exigence doit porter affordance`);
  }

  // (i) J >= 1, replay_ref = ref d'un step B, predicate coherent.
  const jSteps = byRole('ADVANTAGE');
  if (jSteps.length < 1) {
    problems.push(`${maillon('ADVANTAGE')} : au moins 1 exigence attendue (0 trouvee)`);
  } else {
    const bRefs = new Set(bSteps.map((s) => s.ref));
    const bByRef = new Map(bSteps.map((s) => [s.ref, s]));
    jSteps.forEach((s) => {
      if (typeof s.replay_ref !== 'string' || s.replay_ref.trim().length === 0 || !bRefs.has(s.replay_ref)) {
        problems.push(`${maillon('ADVANTAGE')} (${s.ref || '?'}) : replay_ref doit referencer une exigence de role PLAYER_ACTION (recu: ${s.replay_ref || 'absent'})`);
        return;
      }
      // FUITE 1 (Lot D, 2026-08-23, GO Pierre) : un J dont le replay_ref pointe
      // un B SANS affordance est une production PASSIVE mesuree, pas un vrai
      // clic (mesure run 9 : j_advantage sans affordance -> la sonde a mesure
      // la production passive) — nomme ici au lieu de laisser player_loop.gd
      // rejouer un step qui n'a rien a cliquer.
      const bTarget = bByRef.get(s.replay_ref);
      if (!bTarget || typeof bTarget.affordance !== 'string' || bTarget.affordance.trim().length === 0) {
        problems.push(`${maillon('ADVANTAGE')} (${s.ref || '?'}) : replay_ref ('${s.replay_ref}') doit referencer une exigence PLAYER_ACTION portant affordance (production passive non rejouable)`);
      }
      const attendu = `increases_more_than:${s.replay_ref}`;
      if (!s.observe || s.observe.predicate !== attendu) {
        problems.push(`${maillon('ADVANTAGE')} (${s.ref || '?'}) : observe.predicate doit valoir '${attendu}' (coherent avec replay_ref)`);
      }
    });
  }

  // DECISION (extension 2026-08-23, point de decision significative) : >= 1 step,
  // options = refs de steps B (PLAYER_ACTION) ou F (UNLOCK) portant `affordance`,
  // affordances distinctes ; policies >= 2, chaque click non null reference une
  // affordance B ; metric = un observe.hud d'au moins un AUTRE step ; observe.hud
  // vaut 'objectif' sur le step DECISION.
  const decisionSteps = byRole('DECISION');
  if (decisionSteps.length < 1) {
    problems.push('maillon DECISION : au moins 1 exigence attendue (0 trouvee)');
  } else {
    const affordanceRoles = new Set(['PLAYER_ACTION', 'UNLOCK']);
    const stepByRef = new Map(steps.filter((s) => s && typeof s.ref === 'string').map((s) => [s.ref, s]));
    const bAffordances = new Set(
      steps.filter((s) => s && s.role === 'PLAYER_ACTION' && typeof s.affordance === 'string' && s.affordance.trim().length > 0)
        .map((s) => s.affordance),
    );

    decisionSteps.forEach((s) => {
      const tag = maillonDecision(s.ref);

      if (!Array.isArray(s.options) || s.options.length !== 2) {
        problems.push(`${tag} : options doit etre un tableau de 2 refs`);
      } else {
        const resolved = s.options.map((ref) => stepByRef.get(ref));
        resolved.forEach((target, i) => {
          if (!target || !affordanceRoles.has(target.role) || typeof target.affordance !== 'string' || target.affordance.trim().length === 0) {
            problems.push(`${tag} : options[${i}] ('${s.options[i]}') doit referencer un step PLAYER_ACTION ou UNLOCK portant affordance`);
          }
        });
        if (resolved.every((t) => t && typeof t.affordance === 'string' && t.affordance.trim().length > 0)) {
          if (resolved[0].affordance === resolved[1].affordance) {
            problems.push(`${tag} : les affordances des 2 options doivent etre distinctes (recu: '${resolved[0].affordance}')`);
          }
        }
      }

      if (!Array.isArray(s.policies) || s.policies.length < 2) {
        problems.push(`${tag} : policies doit etre un tableau d'au moins 2 politiques (${Array.isArray(s.policies) ? s.policies.length : 0} trouvee(s))`);
      } else {
        s.policies.forEach((p) => {
          if (p && typeof p.click === 'string' && p.click.trim().length > 0 && !bAffordances.has(p.click)) {
            problems.push(`${tag} : policies['${p.name || '?'}'].click ('${p.click}') doit referencer une affordance PLAYER_ACTION`);
          }
        });
      }

      if (!isNonEmptyStringLocal(s.metric)) {
        problems.push(`${tag} : metric absent ou vide`);
      } else {
        const observedHuds = new Set(
          steps.filter((other) => other !== s && other.observe && typeof other.observe.hud === 'string')
            .map((other) => other.observe.hud),
        );
        if (!observedHuds.has(s.metric)) {
          problems.push(`${tag} : metric ('${s.metric}') doit etre un observe.hud deja observe par un AUTRE step`);
        }
      }

      if (!s.observe || s.observe.hud !== 'objectif') {
        problems.push(`${tag} : observe.hud doit valoir 'objectif' (recu: '${s.observe && s.observe.hud}')`);
      }
    });
  }

  const ok = problems.length === 0;
  return { ok, verdict: ok ? 'OK' : 'FAIL', problems };
}

function isNonEmptyStringLocal(v) {
  return typeof v === 'string' && v.trim().length > 0;
}

// ---- CLI ----
const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const argv = process.argv.slice(2);
  const jsonFlag = argv.includes('--json');
  const target = argv.find((a) => a !== '--json');

  if (!target) {
    console.error('usage: node loop_spec.mjs <prisme.json> [--json]');
    process.exit(2);
  }

  let prisme;
  try {
    prisme = JSON.parse(readFileSync(target, 'utf-8'));
  } catch (err) {
    console.error(`loop_spec: ${target}: absent, illisible ou JSON invalide (${err.message})`);
    process.exit(2);
  }

  const spec = deriveLoopSpec(prisme);
  const check = checkLoopSpec(spec);

  if (jsonFlag) {
    process.stdout.write(JSON.stringify({ spec, check }));
  } else {
    console.log(`VERDICT LOOP_SPEC: ${check.verdict}`);
    check.problems.forEach((p) => console.error(`  FAIL: ${p}`));
    console.log(`  steps derives: ${spec.steps.length}`);
    console.log(JSON.stringify({ spec, check }, null, 2));
  }
  process.exit(check.ok ? 0 : 1);
}
