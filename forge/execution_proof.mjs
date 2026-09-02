#!/usr/bin/env node
// execution_proof.mjs — EXECUTION PROOF V0 : le plan annoncé décrit-il ce que le
// runtime fait réellement ?
//
// La Factory produit un `FactoryExecutionPlan` PLAN_ONLY. Personne n'a jamais vérifié
// que ce plan corresponde à l'exécution. Cette couche ne fait QUE cette comparaison :
//
//     plan annoncé   vs   runtime observé   ->   MATCH | MISMATCH
//
// ELLE NE CORRIGE RIEN. Un écart est NOMMÉ (mauvais runtime, entrée manquante, sortie
// différente, fichier inattendu, preuve absente) et rendu à l'humain. Corriger
// automatiquement reviendrait à faire disparaître la seule information utile.
//
// ELLE N'AJOUTE AUCUN POUVOIR : elle lance le runtime que le PLAN désigne, avec les
// entrées que le PLAN déclare, dans le périmètre que le PLAN annonce. Aucun modèle
// supplémentaire, aucune boucle, aucune autonomie. L'exécution réelle exige `--confirm`
// (HumanGate) ; sans lui, ce fichier ne lance rien.
//
// Usage : node execution_proof.mjs <plan.json> <requete_runtime.json> --confirm [--out <dir>]
//
// claim_posture: NO_CLAIM_ALLOWED
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFile, readdir } from 'node:fs/promises';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const ICI = dirname(fileURLToPath(import.meta.url));
const RACINE = resolve(ICI, '..');

/** Vocabulaire FERMÉ des écarts. Un écart sans nom ne se corrige pas. */
export const MISMATCHES = {
  WRONG_RUNTIME: 'mauvais runtime',
  MISSING_INPUT: 'entree manquante',
  DIFFERENT_OUTPUT: 'sortie differente',
  UNEXPECTED_FILE: 'fichier inattendu',
  MISSING_EVIDENCE: 'preuve absente',
  ROOT_PROBLEM_DRIFT: 'root_problem_id different',
  WRONG_MUTATION: 'mutation differente',
  LEG_UNACCOUNTED: 'maillon de composition non justifie',
};

export const MATCH = 'MATCH';
export const MISMATCH = 'MISMATCH';

// --------------------------------------------------------------------------------
// Observation du système de fichiers
// --------------------------------------------------------------------------------

/** Empreinte de tous les fichiers d'un dossier, par chemin relatif. */
export async function snapshot(dossier) {
  const out = new Map();
  const visiter = async (d) => {
    let entrees = [];
    try {
      entrees = await readdir(d, { withFileTypes: true });
    } catch {
      return;
    }
    for (const e of entrees) {
      const p = join(d, e.name);
      // eslint-disable-next-line no-await-in-loop -- parcours séquentiel, volume connu
      if (e.isDirectory()) await visiter(p);
      else {
        // eslint-disable-next-line no-await-in-loop
        const buf = await readFile(p).catch(() => null);
        if (buf) out.set(relative(dossier, p).replace(/\\/g, '/'),
          createHash('sha256').update(buf).digest('hex').slice(0, 16));
      }
    }
  };
  await visiter(dossier);
  return out;
}

/** Séparateurs POSIX. Sans cette normalisation, un chemin Windows (`a\b`) ne
 *  correspond jamais à un périmètre déclaré en POSIX (`a/b`) — et TOUT fichier écrit
 *  passe pour hors scope. Défaut trouvé par la première exécution réelle. */
export const posix = (p) => String(p).split('\\').join('/');

/** Ce qui a changé entre deux empreintes. */
export function diffSnapshots(avant, apres) {
  const cree = [...apres.keys()].filter((k) => !avant.has(k));
  const modifie = [...apres.keys()].filter((k) => avant.has(k) && avant.get(k) !== apres.get(k));
  const supprime = [...avant.keys()].filter((k) => !apres.has(k));
  return { created: cree.sort(), modified: modifie.sort(), deleted: supprime.sort() };
}

// --------------------------------------------------------------------------------
// Exécution sous observation
// --------------------------------------------------------------------------------

/** Lance une commande et rend {code, stdout, stderr}. Ne lève jamais. */
export function lancer(cmd, args, opts = {}) {
  return new Promise((res) => {
    const p = spawn(cmd, args, { cwd: opts.cwd || RACINE, shell: false });
    let out = '';
    let err = '';
    p.stdout.on('data', (d) => { out += d; });
    p.stderr.on('data', (d) => { err += d; });
    p.on('error', (e) => res({ code: -1, stdout: '', stderr: String(e) }));
    p.on('close', (code) => res({ code, stdout: out, stderr: err }));
  });
}

/**
 * Quel module le plan désigne-t-il comme point d'appel ?
 *
 * AMBIGUÏTÉ LEVÉE : le plan porte désormais `callable` — le module qui accepte les
 * `required_inputs`, tranché par la Factory. On ne devine plus entre `entrypoints` et
 * `adapter`. Le repli sur ces deux champs reste, pour les plans écrits avant.
 */
export function pointDAppel(plan) {
  const rt = plan?.runtime_to_call || {};
  if (rt.callable) return { module: rt.callable, niveau: rt.callable_level ?? 'callable' };
  if (rt.adapter) return { module: rt.adapter, niveau: 'adapter' };
  if ((rt.entrypoints || []).length) return { module: rt.entrypoints[0], niveau: 'entrypoint' };
  return { module: null, niveau: null };
}

/**
 * Un maillon de composition non exécuté est-il justifié par une preuve versionnée ?
 *
 * Une composition ne s'exécute pas d'un bloc : `worldscan` est dispatché par le driver
 * (aucun `callable`), sa sortie est versionnée. On l'accepte comme REPRIS — à condition
 * que l'empreinte du fichier repris corresponde à celle attendue. Sans cette
 * vérification, « repris » voudrait dire « pas regardé ».
 */
export function verifierMaillonRepris(source, shaAttendu, racine = RACINE) {
  const chemin = join(racine, source);
  if (!existsSync(chemin)) return { source, verified: false, motif: 'fichier absent', sha256_16: null };
  const sha = createHash('sha256').update(readFileSync(chemin)).digest('hex').slice(0, 16);
  return {
    source,
    sha256_16: sha,
    verified: shaAttendu ? sha === shaAttendu : true,
    motif: shaAttendu && sha !== shaAttendu ? `sha ${sha} != ${shaAttendu}` : null,
  };
}

/**
 * Arguments à passer au callable, selon la convention DÉCLARÉE par son contrat.
 *
 *   `request_file`        le callable lit un JSON d'entrées nommées  -> on passe ce fichier
 *   `positional_artifact` le callable prend le CHEMIN de l'artefact  -> on passe ce chemin
 *
 * Déclaré, jamais déduit. Deviner reviendrait à appeler le runtime autrement que son
 * contrat ne le dit — et le MATCH ne vaudrait plus rien.
 */
export function argumentsDInvocation(plan, opts) {
  const style = plan?.runtime_to_call?.invocation ?? 'request_file';
  if (style === 'positional_artifact') {
    const chemin = (opts.declaredInputs || {}).artifact_ref;
    if (!chemin) throw new Error('invocation positional_artifact : artifact_ref absent des entrees declarees');
    return [chemin];
  }
  return [opts.requeteRuntime];
}

/**
 * Lit la sortie du callable. Deux conventions observées : JSON pur, ou une ligne
 * lisible SUIVIE du JSON (les CLI d'oracle affichent d'abord un verdict humain). On
 * essaie le strict, puis le bloc JSON final — et on ENREGISTRE lequel a marché. Un
 * parseur permissif qui tait son indulgence transforme une observation en supposition.
 */
export function parserSortie(stdout) {
  try {
    return { parsed: JSON.parse(stdout), mode: 'strict' };
  } catch { /* on tente la seconde convention */ }
  const i = String(stdout).indexOf('{');
  if (i >= 0) {
    try {
      return { parsed: JSON.parse(String(stdout).slice(i)), mode: 'trailing_json' };
    } catch { /* illisible */ }
  }
  return { parsed: null, mode: 'unparseable' };
}

/**
 * Mutations qu'une exécution peut légitimement rapporter : celle du plan, et celle qui
 * prouve la capacité du maillon réellement exécuté. Sur un plan non composé, les deux
 * sont la même.
 */
export function mutationsAcceptables(plan, moduleAppele) {
  const out = new Set([plan.mutation_id].filter(Boolean));
  const chaine = plan.runtime_chain || [];
  for (const [i, maillon] of chaine.entries()) {
    if (maillon.callable && maillon.callable === moduleAppele) {
      const ev = (plan.capability_chain || [])[i]?.evidence;
      if (ev) out.add(ev);
    }
  }
  return [...out];
}

/**
 * Exécute le runtime désigné par le plan, sous observation du système de fichiers.
 *
 * @param {object} plan FactoryExecutionPlan
 * @param {object} opts {requeteRuntime, scope, racine, executer}
 *        `executer` n'existe que pour les tests : il remplace le lancement réel.
 * @returns {Promise<object>} observation
 */
export async function executerSousObservation(plan, opts) {
  const racine = opts.racine || RACINE;
  const scope = opts.scope.map((d) => resolve(racine, d));
  const appel = pointDAppel(plan);

  const avant = new Map();
  for (const d of scope) {
    // eslint-disable-next-line no-await-in-loop
    for (const [k, v] of await snapshot(d)) avant.set(`${posix(relative(racine, d))}/${k}`, v);
  }

  const args = [appel.module, ...argumentsDInvocation(plan, opts), '--json'];
  const r = opts.executer
    ? await opts.executer({ cmd: 'node', args, appel })
    : await lancer('node', args, { cwd: racine });

  const apres = new Map();
  for (const d of scope) {
    // eslint-disable-next-line no-await-in-loop
    for (const [k, v] of await snapshot(d)) apres.set(`${posix(relative(racine, d))}/${k}`, v);
  }

  const lu = parserSortie(r.stdout);
  const sortie = lu.parsed;

  return {
    runtime_called: { module: appel.module, niveau: appel.niveau, cmd: 'node', args },
    exit_code: r.code,
    stdout_parsed: sortie !== null,
    stdout_parse_mode: lu.mode,
    output_keys: sortie ? Object.keys(sortie).sort() : [],
    output: sortie,
    files: diffSnapshots(avant, apres),
    stderr_head: (r.stderr || '').split('\n').slice(0, 3).join(' | '),
  };
}

// --------------------------------------------------------------------------------
// Comparaison — les sept vérifications
// --------------------------------------------------------------------------------

/**
 * Compare le plan annoncé à l'exécution observée. Ne corrige rien.
 * @returns {{match_status, mismatches, checks}}
 */
export function comparer(plan, obs, opts = {}) {
  const mismatches = [];
  const checks = [];
  const noter = (nom, ok, detail) => { checks.push({ check: nom, ok, detail }); return ok; };

  // 1. le runtime appelé correspond au plan
  const rt = plan.runtime_to_call || {};
  // `callable` fait partie des modules déclarés : depuis qu'il tranche l'ambiguïté
  // entrypoint/adapter, l'omettre rendrait « mauvais runtime » tout appel conforme.
  const declares = [...(rt.entrypoints || []), rt.adapter, rt.callable].filter(Boolean);
  const appele = obs.runtime_called?.module ?? null;
  if (!noter('runtime_called', declares.includes(appele),
    `appele=${appele} · declares=${declares.join(', ') || '(aucun)'}`)) {
    mismatches.push({ mismatch: MISMATCHES.WRONG_RUNTIME, detail: `${appele} n est pas declare dans le plan` });
  }

  // 2. les fichiers modifiés correspondent au scope
  const touches = [...obs.files.created, ...obs.files.modified, ...obs.files.deleted];
  const horsScope = touches.filter((f) => !(opts.scope || [])
    .some((d) => f.startsWith(d.replace(/\\/g, '/'))));
  if (!noter('files_in_scope', horsScope.length === 0, `${touches.length} fichier(s) touche(s)`)) {
    mismatches.push({ mismatch: MISMATCHES.UNEXPECTED_FILE, detail: horsScope.join(', ') });
  }

  // 3. les sorties produites correspondent aux expected_outputs
  const attendues = [...(plan.expected_outputs || [])].sort();
  const manquantes = attendues.filter((k) => !obs.output_keys.includes(k));
  if (!noter('expected_outputs', manquantes.length === 0,
    `attendues=${attendues.length} · observees=${obs.output_keys.length}`)) {
    mismatches.push({ mismatch: MISMATCHES.DIFFERENT_OUTPUT, detail: `absentes: ${manquantes.join(', ')}` });
  }

  // 4. les evidence_targets existent APRÈS exécution
  const racine = opts.racine || RACINE;
  const absentes = (plan.evidence_targets || []).filter((f) => !existsSync(join(racine, f)));
  if (!noter('evidence_targets', absentes.length === 0,
    `${(plan.evidence_targets || []).length} cible(s)`)) {
    mismatches.push({ mismatch: MISMATCHES.MISSING_EVIDENCE, detail: absentes.join(', ') });
  }

  // 5. le root_problem_id reste identique
  const rpObs = obs.output?.root_problem_id ?? null;
  if (!noter('root_problem_stable', rpObs === null || rpObs === plan.root_problem_id,
    `plan=${plan.root_problem_id} · observe=${rpObs}`)) {
    mismatches.push({ mismatch: MISMATCHES.ROOT_PROBLEM_DRIFT, detail: `${plan.root_problem_id} -> ${rpObs}` });
  }

  // 6. la mutation utilisée correspond à celle sélectionnée
  //
  // AMBIGUÏTÉ LEVÉE (observée sur M-ws6) : le plan porte la mutation de la COMPOSITION
  // (`M-ws6`), le runtime rapporte celle du MAILLON qu'il a exécuté
  // (`REPAIR-LOOP-V1`, la preuve de `targeted_field_repair`). Les deux sont justes à
  // leur niveau. Comparer l'un à l'autre produisait un faux écart. On accepte donc la
  // mutation du plan OU celle du maillon exécuté — et rien d'autre : une mutation
  // étrangère aux deux reste un écart.
  const mutObs = obs.output?.mutation_used ?? null;
  const acceptables = mutationsAcceptables(plan, appele);
  if (!noter('mutation_used', mutObs === null || acceptables.includes(mutObs),
    `plan=${plan.mutation_id} · observe=${mutObs} · acceptables=${acceptables.join(', ')}`)) {
    mismatches.push({
      mismatch: MISMATCHES.WRONG_MUTATION,
      detail: `${mutObs} n est ni la mutation du plan ni celle du maillon execute`,
    });
  }

  // 7. les entrées déclarées ont bien été fournies
  const fournies = Object.keys(opts.requeteFournie || {});
  const entreesManquantes = (plan.required_inputs || []).filter((k) => !fournies.includes(k));
  if (!noter('required_inputs', entreesManquantes.length === 0,
    `${fournies.length} fournie(s) / ${(plan.required_inputs || []).length} declaree(s)`)) {
    mismatches.push({ mismatch: MISMATCHES.MISSING_INPUT, detail: entreesManquantes.join(', ') });
  }

  // 8. COMPOSITION — chaque maillon est soit exécuté, soit repris sous empreinte vérifiée
  const chaine = plan.runtime_chain || [];
  if (chaine.length > 1) {
    const repris = new Map((opts.resumedLegs || []).map((r) => [r.capability, r]));
    const nonJustifies = [];
    for (const [i, maillon] of chaine.entries()) {
      const cap = (plan.capability_chain || [])[i]?.capability ?? maillon.runtime_role;
      const executé = maillon.callable && maillon.callable === appele;
      if (executé) continue;
      const r = repris.get(cap);
      if (!r || r.verified !== true) {
        nonJustifies.push(`${cap} (${maillon.runtime_role})${r ? ` : ${r.motif}` : ' : aucune reprise declaree'}`);
      }
    }
    if (!noter('composition_legs', nonJustifies.length === 0,
      `${chaine.length} maillon(s), ${repris.size} repris sous empreinte`)) {
      mismatches.push({ mismatch: MISMATCHES.LEG_UNACCOUNTED, detail: nonJustifies.join(' | ') });
    }
  }

  return { match_status: mismatches.length === 0 ? MATCH : MISMATCH, mismatches, checks };
}

/** Assemble la trace exigée. */
export function construireTrace(plan, obs, verdict) {
  return {
    schema: 'forge.execution_proof.v0',
    plan_id: plan.execution_id,
    root_problem_id: plan.root_problem_id,
    capability_chain: (plan.capability_chain || []).map((c) => c.capability),
    runtime_called: obs.runtime_called,
    runtime_role: plan.runtime_to_call?.runtime_role ?? null,
    callable_level: plan.runtime_to_call?.callable_level ?? null,
    invocation: plan.runtime_to_call?.invocation ?? null,
    stdout_parse_mode: obs.stdout_parse_mode ?? null,
    files_changed: obs.files,
    outputs_created: obs.output_keys,
    evidence_created: obs.output?.evidence_created ?? [],
    mutation_used: obs.output?.mutation_used ?? null,
    match_status: verdict.match_status,
    resumed_legs: verdict.resumed_legs ?? [],
    mismatches: verdict.mismatches,
    checks: verdict.checks,
    exit_code: obs.exit_code,
  };
}

// ---- CLI ----
const estMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (estMain) {
  const argv = process.argv.slice(2);
  const positionnels = argv.filter((a, i) => !a.startsWith('--') && argv[i - 1] !== '--out'
    && argv[i - 1] !== '--scope');
  if (!argv.includes('--confirm')) {
    console.error('HumanGate : ce module lance une EXECUTION REELLE. Relance avec --confirm.');
    process.exitCode = 2;
  } else if (positionnels.length < 2) {
    console.error('usage: node execution_proof.mjs <plan.json> <requete_runtime.json> --confirm '
      + '[--scope <dir,dir>] [--out <fichier>]');
    process.exitCode = 2;
  } else {
    const plan = JSON.parse(await readFile(positionnels[0], 'utf-8'));
    const requete = JSON.parse(await readFile(positionnels[1], 'utf-8'));
    const iScope = argv.indexOf('--scope');
    const scope = iScope >= 0 ? argv[iScope + 1].split(',')
      : [requete.evidence_ref, dirname(requete.artifact_ref)].filter(Boolean);
    const repris = [];
    for (let i = 0; i < argv.length; i += 1) {
      if (argv[i] !== '--resume') continue;
      const [cap, reste] = argv[i + 1].split('=');
      const [source, sha] = reste.split('@');
      repris.push({ capability: cap, ...verifierMaillonRepris(source, sha) });
    }
    const obs = await executerSousObservation(plan, {
      requeteRuntime: positionnels[1], scope, declaredInputs: requete,
    });
    const verdict = comparer(plan, obs, { scope, requeteFournie: requete, resumedLegs: repris });
    verdict.resumed_legs = repris;
    const trace = construireTrace(plan, obs, verdict);
    console.log(JSON.stringify(trace, null, 1));
    console.error(`\n${trace.match_status}  (${verdict.mismatches.length} ecart(s))`);
    for (const c of verdict.checks) console.error(`  ${c.ok ? 'OK  ' : 'FAIL'} ${c.check} : ${c.detail}`);
    for (const m of verdict.mismatches) console.error(`  ECART ${m.mismatch} : ${m.detail}`);
    process.exitCode = verdict.match_status === MATCH ? 0 : 1;
  }
}
