#!/usr/bin/env node
// repair_runtime_adapter.mjs — ADAPTATEUR DE CONTRAT, pas un réparateur.
//
// Le réparateur existe déjà et n'est pas touché : `repair_step.mjs` → `repair_loop.mjs`
// → modèle local. Ce fichier ne contient AUCUNE logique de réparation, AUCUN oracle,
// AUCUN prompt, AUCUNE liste blanche interne. Il fait exactement trois choses :
//
//   1. traduire une REQUÊTE DE CONTRAT (finding_id · root_problem_id · artifact_ref ·
//      evidence_ref · allowed_fields · forbidden_fields) vers l'appel que
//      `repair_step.mjs` sait déjà recevoir (`etape`, `runDir`) ;
//   2. faire respecter le périmètre REÇU — et non le périmètre déduit. C'est le seul
//      écart de comportement introduit ici, et il va toujours dans le sens restrictif :
//      une écriture hors `allowed_fields` annule la réparation entière ;
//   3. matérialiser la preuve exigée par le contrat sous `evidence_ref`.
//
// POURQUOI UN ADAPTATEUR ET PAS UNE RÉÉCRITURE : le réparateur actuel est prouvé
// (REPAIR-LOOP-V1 : 68 tokens, 0 régression) et branché sur 5 étapes du driver. Le
// réécrire pour lui donner une nouvelle signature jetterait la preuve avec le code.
//
// PÉRIMÈTRE DE LA GARDE : `repair_step.mjs` lance aussi une phase QUALITÉ (signaux
// sémantiques, déplacements) qui peut écrire des champs que l'oracle n'avait PAS
// signalés. Sous contrat, ces champs sont hors `allowed_fields` : c'est une violation,
// et elle est traitée comme telle. Passer `qualiteActive: false` est la façon
// explicite de composer une réparation strictement structurelle.
//
// claim_posture: NO_CLAIM_ALLOWED
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { ETAPES, reparerEtape } from './repair_step.mjs';
import { analyserFindings, cheminsFeuilles } from './repair_loop.mjs';

const ICI = dirname(fileURLToPath(import.meta.url));

/** Capacité que ce runtime implémente. Sert à résoudre `mutation_used` depuis le
 *  catalogue — l'exécution est ainsi reliée à la preuve, pas à une constante écrite ici. */
export const CAPABILITY = 'targeted_field_repair';

/** Champs d'entrée du contrat (REPAIR_RUNTIME_CONTRACT_V1). */
export const CHAMPS_REQUETE = [
  'finding_id', 'root_problem_id', 'artifact_ref', 'evidence_ref',
  'allowed_fields', 'forbidden_fields',
];

/** artefact réparable -> étape de `repair_step.mjs`. Dérivée de ETAPES, jamais recopiée. */
export function etapeDepuisArtefact(cheminArtefact) {
  const nom = basename(String(cheminArtefact));
  const trouvees = Object.entries(ETAPES).filter(([, s]) => s.artefact === nom);
  if (trouvees.length !== 1) return null;
  return trouvees[0][0];
}

/**
 * Identifiants stables des findings d'un oracle : `<oracle>:<chemin>` pour un finding
 * de champ, `<oracle>:#<n>` pour un finding structurel (non réparable par nature).
 * Stable = ne dépend pas de l'ordre de sortie de l'oracle pour les findings de champ.
 * @param {string} oracle
 * @param {string[]} problems
 * @returns {Array<{finding_id:string, chemin:string|null, brut:string}>}
 */
export function identifiantsFindings(oracle, problems) {
  return analyserFindings(problems).map((f, i) => ({
    finding_id: f.chemin ? `${oracle}:${f.chemin}` : `${oracle}:#${i}`,
    chemin: f.chemin,
    brut: f.brut,
  }));
}

/**
 * Valide une requête de contrat. Lève sur toute anomalie : un réparateur qui démarre
 * sur une requête douteuse est exactement ce que le contrat cherche à empêcher.
 *
 * `finding_id` accepte une chaîne ou un tableau non vide. Raison assumée : un oracle
 * émet un ENSEMBLE de findings pour un artefact, et le runtime les traite en une passe.
 * Imposer un appel par finding multiplierait les exécutions d'oracle sans changer le
 * résultat — la composition M-ws6 en répare deux d'un coup.
 * @param {object} req
 * @returns {{finding_ids:string[], root_problem_id:string, artifact_ref:string,
 *            evidence_ref:string, allowed_fields:string[], forbidden_fields:string[]}}
 */
export function validerRequete(req) {
  if (req === null || typeof req !== 'object') throw new Error('requete: objet attendu');
  const inconnus = Object.keys(req).filter((k) => !CHAMPS_REQUETE.includes(k));
  if (inconnus.length) throw new Error(`requete: champs hors contrat -> ${inconnus.join(', ')}`);
  for (const c of CHAMPS_REQUETE) {
    if (!(c in req)) throw new Error(`requete: champ obligatoire manquant -> ${c}`);
  }
  const ids = Array.isArray(req.finding_id) ? req.finding_id : [req.finding_id];
  if (!ids.length || ids.some((x) => typeof x !== 'string' || !x.trim())) {
    throw new Error('requete: finding_id doit être une chaîne non vide ou un tableau de chaînes');
  }
  for (const c of ['root_problem_id', 'artifact_ref', 'evidence_ref']) {
    if (typeof req[c] !== 'string' || !req[c].trim()) throw new Error(`requete: ${c} doit être une chaîne non vide`);
  }
  for (const c of ['allowed_fields', 'forbidden_fields']) {
    if (!Array.isArray(req[c]) || req[c].some((x) => typeof x !== 'string')) {
      throw new Error(`requete: ${c} doit être un tableau de chaînes`);
    }
  }
  if (!req.allowed_fields.length) throw new Error('requete: allowed_fields vide — aucun champ réparable déclaré');
  const collision = req.allowed_fields.filter((x) => req.forbidden_fields.includes(x));
  if (collision.length) {
    throw new Error(`requete: chemin à la fois autorisé et interdit -> ${collision.join(', ')}`);
  }
  return {
    finding_ids: ids,
    root_problem_id: req.root_problem_id,
    artifact_ref: req.artifact_ref,
    evidence_ref: req.evidence_ref,
    allowed_fields: req.allowed_fields,
    forbidden_fields: req.forbidden_fields,
  };
}

/** Traduit la requête validée en arguments de `reparerEtape`. Lève si l'artefact ne
 *  correspond à aucune étape connue — on ne devine pas. */
export function versRepairStep(reqValide) {
  const etape = etapeDepuisArtefact(reqValide.artifact_ref);
  if (etape === null) {
    throw new Error(`artifact_ref: aucune étape connue pour ${basename(reqValide.artifact_ref)} `
      + `(attendus: ${Object.values(ETAPES).map((s) => s.artefact).join(', ')})`);
  }
  return { etape, runDir: dirname(resolve(reqValide.artifact_ref)) };
}

/** Chemins de feuilles dont la valeur diffère entre deux artefacts.
 *  `cheminsFeuilles` rend une Map<chemin, valeurJSON> — on la lit comme telle, sans en
 *  refaire une copie locale : c'est la même définition de « feuille » que celle qui sert
 *  déjà de preuve de non-régression dans `repair_loop.mjs`. */
export function diffFeuilles(avant, apres) {
  const a = cheminsFeuilles(avant);
  const b = cheminsFeuilles(apres);
  const cles = new Set([...a.keys(), ...b.keys()]);
  const val = (m, c) => (m.has(c) ? JSON.parse(m.get(c)) : null);
  const patch = [];
  for (const cle of [...cles].sort()) {
    if (a.get(cle) !== b.get(cle)) {
      patch.push({ path: cle, before: val(a, cle), after: val(b, cle) });
    }
  }
  return patch;
}

/** Résout la mutation qui prouve la capacité, depuis le catalogue. `null` si absente :
 *  on déclare le trou plutôt que d'inventer un identifiant. */
export async function mutationDeLaCapacite(cheminCatalogue = join(ICI, 'capabilities.json')) {
  try {
    const cat = JSON.parse(await readFile(cheminCatalogue, 'utf-8'));
    return cat.capabilities.find((c) => c.id === CAPABILITY)?.source_mutation ?? null;
  } catch {
    return null;
  }
}

/**
 * Exécute une réparation SOUS CONTRAT.
 *
 * @param {object} requete requête de contrat (6 champs)
 * @param {object} [opts] {appelerModele, maxCycles, qualiteActive, executer}
 *        `executer` n'existe que pour les tests : il remplace `reparerEtape` sans
 *        toucher au réparateur réel.
 * @returns {Promise<object>} sortie de contrat
 */
export async function executerReparation(requete, opts = {}) {
  const req = validerRequete(requete);
  const { etape, runDir } = versRepairStep(req);
  const spec = ETAPES[etape];
  const cheminArtefact = join(runDir, spec.artefact);
  const executer = opts.executer || reparerEtape;

  const avant = JSON.parse(await readFile(cheminArtefact, 'utf-8'));
  const oracleAvant = await spec.valider(runDir);
  const problemsAvant = oracleAvant.problems || [];

  // Le finding doit exister AVANT. « Réparer un défaut déjà identifié » : si le défaut
  // n'est pas dans la sortie de l'oracle, le runtime n'a rien à faire — et surtout pas
  // à décider tout seul quoi corriger.
  const connus = identifiantsFindings(spec.oracle, problemsAvant);
  const idsConnus = new Set(connus.map((f) => f.finding_id));
  const orphelins = req.finding_ids.filter((x) => !idsConnus.has(x));
  if (orphelins.length) {
    return sortie({
      req, etape, oracleAvant, oracleApres: oracleAvant, avant, apres: avant,
      patch: [], mutation: await mutationDeLaCapacite(), mesure: null,
      contract_status: 'FINDING_INCONNU',
      contract_detail: `finding(s) absent(s) de l'oracle : ${orphelins.join(', ')}`,
      evidence_created: [],
    });
  }

  const mesure = await executer({
    etape,
    runDir,
    appelerModele: opts.appelerModele,
    maxCycles: opts.maxCycles ?? 3,
    qualiteActive: opts.qualiteActive ?? true,
  });

  let apres = JSON.parse(await readFile(cheminArtefact, 'utf-8'));
  let patch = diffFeuilles(avant, apres);

  // GARDE DE PÉRIMÈTRE REÇU. La liste blanche interne de `repair_loop.mjs` reste en
  // place et fait son travail ; celle-ci s'applique PAR-DESSUS, sur les chemins déclarés
  // par l'appelant. Une écriture hors périmètre annule tout : un contrat à moitié
  // respecté ne se rattrape pas en gardant la moitié qui arrange.
  const horsPerimetre = patch
    .map((p) => p.path)
    .filter((p) => !req.allowed_fields.includes(p) || req.forbidden_fields.includes(p));
  let contract_status = 'CONFORME';
  let contract_detail = null;
  if (horsPerimetre.length) {
    await writeFile(cheminArtefact, JSON.stringify(avant, null, 1), 'utf-8');
    apres = avant;
    patch = [];
    contract_status = 'CONTRACT_VIOLATION';
    contract_detail = `écriture hors périmètre déclaré -> ${horsPerimetre.join(', ')} (artefact restauré)`;
  }
  const oracleApres = await spec.valider(runDir);

  const evidence_created = await ecrirePreuve(req, {
    avant, apres, oracleAvant, oracleApres, patch, mesure, contract_status, contract_detail, etape,
    mutation: await mutationDeLaCapacite(),
  });

  return sortie({
    req, etape, oracleAvant, oracleApres, avant, apres, patch, mesure,
    mutation: await mutationDeLaCapacite(), contract_status, contract_detail, evidence_created,
  });
}

/** Assemble la sortie de contrat (7 champs obligatoires + traçabilité). */
function sortie({ req, etape, oracleAvant, oracleApres, avant, apres, patch, mesure,
  mutation, contract_status, contract_detail, evidence_created }) {
  return {
    finding_id: req.finding_ids.length === 1 ? req.finding_ids[0] : req.finding_ids,
    root_problem_id: req.root_problem_id,
    step: etape,
    patch,
    before: avant,
    after: apres,
    oracle_before: { ok: !!oracleAvant.ok, problems: oracleAvant.problems || [] },
    oracle_after: { ok: !!oracleApres.ok, problems: oracleApres.problems || [] },
    evidence_created,
    mutation_used: mutation,
    contract_status,
    contract_detail,
    // La fermeture d'un défaut mesuré ne dit RIEN de la justesse de la valeur écrite.
    // Ce drapeau est constant à dessein : aucune exécution de ce runtime ne peut le
    // faire passer à false — il faudrait une mesure de qualité, qui n'existe pas ici.
    quality_not_proven: true,
    measure: mesure,
  };
}

/** Matérialise la preuve sous `evidence_ref`. Rend la liste des chemins réellement écrits. */
async function ecrirePreuve(req, d) {
  const dossier = resolve(req.evidence_ref);
  await mkdir(dossier, { recursive: true });
  const fichiers = {
    'before.json': d.avant,
    'after.json': d.apres,
    'oracle_before.json': { ok: !!d.oracleAvant.ok, problems: d.oracleAvant.problems || [] },
    'oracle_after.json': { ok: !!d.oracleApres.ok, problems: d.oracleApres.problems || [] },
    'patch.json': d.patch,
    'measured_metrics.json': {
      capability: CAPABILITY,
      mutation_used: d.mutation,
      root_problem_id: req.root_problem_id,
      finding_id: req.finding_ids,
      step: d.etape,
      contract_status: d.contract_status,
      contract_detail: d.contract_detail,
      problems_before: (d.oracleAvant.problems || []).length,
      problems_after: (d.oracleApres.problems || []).length,
      oracle_pass: !!d.oracleApres.ok,
      fields_changed: d.patch.map((p) => p.path),
      regression_count: d.mesure?.REGRESSION?.length ?? 0,
      completion_tokens: d.mesure?.TOKENS ?? null,
      allowed_fields: req.allowed_fields,
      forbidden_fields: req.forbidden_fields,
      quality_not_proven: true,
      quality_note: ('La fermeture du défaut mesuré ne prouve PAS la justesse des valeurs '
        + 'écrites. Ce runtime converge vers l\'oracle, pas vers la qualité.'),
    },
  };
  const ecrits = [];
  for (const [nom, contenu] of Object.entries(fichiers)) {
    // eslint-disable-next-line no-await-in-loop -- écritures séquentielles, ordre lisible
    await writeFile(join(dossier, nom), JSON.stringify(contenu, null, 1), 'utf-8');
    ecrits.push(join(req.evidence_ref, nom).replace(/\\/g, '/'));
  }
  return ecrits;
}

// ---- CLI ----
const estMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (estMain) {
  const chemin = process.argv[2];
  if (!chemin) {
    console.error('usage: node repair_runtime_adapter.mjs <requete.json>');
    console.error(`champs: ${CHAMPS_REQUETE.join(' · ')}`);
    process.exitCode = 2;
  } else {
    const requete = JSON.parse(await readFile(chemin, 'utf-8'));
    const res = await executerReparation(requete);
    for (const cle of ['contract_status', 'step', 'mutation_used', 'quality_not_proven']) {
      console.error(`${cle}: ${JSON.stringify(res[cle])}`);
    }
    console.error(`oracle: ${res.oracle_before.ok ? 'OK' : 'FAIL'} -> ${res.oracle_after.ok ? 'OK' : 'FAIL'}`);
    console.log(JSON.stringify(res, null, 1));
    process.exitCode = res.contract_status === 'CONFORME' && res.oracle_after.ok ? 0 : 1;
  }
}
