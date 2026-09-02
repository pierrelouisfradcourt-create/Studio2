#!/usr/bin/env node
// check_mutation_registry.mjs — validateur MÉCANIQUE du MUTATION_REGISTRY_V1.
//
// Le registre doit être entièrement validable sans lire une ligne de prose. Ce qu'il
// vérifie, et pourquoi chaque règle existe :
//
//   1. unicité des ids                      — deux mutations homonymes rendent toute
//                                             référence (requires/conflicts/génome) ambiguë
//   2. ACCEPTED sans evidence_refs -> FAIL  — « une mutation ne peut pas être ACCEPTED
//                                             si sa seule preuve est une conversation »
//   3. chaque référence existe sur disque   — c'est CETTE règle qui empêche le registre
//                                             de vieillir en mentant : une preuve
//                                             déplacée ou supprimée le fait échouer
//   4. REJECTED sans justification -> FAIL  — un rejet sans code n'apprend rien
//   5. confidence hors [0,1] -> FAIL        — elle est DÉRIVÉE, jamais saisie
//   6. sample_size négatif -> FAIL
//   plus : requires/conflicts pointant un id inexistant, production_ready sans accepted,
//   et evidence_status VERSIONED sans aucune référence.
//
// Usage : node check_mutation_registry.mjs [chemin] [--json]
// Exit 0 = OK · 1 = FAIL · 2 = usage.

import { access } from 'node:fs/promises';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  loadRegistry, loadMutation, loadLayers, CHEMIN_REGISTRE,
} from './mutation_registry.mjs';

const RACINE = join(dirname(fileURLToPath(import.meta.url)), '..');

// Plus grand échantillon de connus-bons réellement constitué à ce jour (12 artefacts :
// 5 références + 7 sorties Qwen validées). Sert d'échelle à la couverture. Déclaré ici
// et non caché dans une formule : le jour où l'échantillon grandit, ce chiffre doit
// bouger visiblement, pas en silence.
export const ECHANTILLON_DE_REFERENCE = 12;

const CODES_REJET = new Set([
  'REFUTED_FALSE_POSITIVE', 'NO_MEASURED_GAIN', 'BLIND_TO_TESTED_DEFECT',
  'NOT_REPRODUCIBLE', 'SUPERSEDED', 'VIOLATES_CONTRACT_CONSTRAINT',
]);

/**
 * DÉRIVE la confidence depuis les seuls compteurs mesurés. Jamais saisie à la main.
 *
 *   précision  = TP / (TP + FP)            — ce que le signal dit de juste
 *   couverture = min(1, n / ÉCHANTILLON)   — sur quelle base il l'a dit
 *   confidence = précision × couverture
 *
 * Une précision parfaite sur 1 seul cas ne vaut pas une précision parfaite sur 12 :
 * multiplier par la couverture est ce qui empêche « 1/1 » de se présenter comme une
 * certitude. Rend `null` (=UNKNOWN) dès qu'un compteur manque — on ne dérive rien
 * d'une inconnue.
 *
 * @param {object} m
 * @returns {number|null}
 */
export function deriverConfidence(m) {
  const n = m.sample_size;
  const fp = m.false_positive;
  const tp = m.true_positive;
  if (![n, fp, tp].every((x) => Number.isInteger(x))) return null;
  if (n === 0) return 0;
  const denom = tp + fp;
  // ZÉRO DÉTECTION => AUCUNE CONFIANCE DÉRIVABLE, et surtout pas 1.
  // Défaut trouvé en exécutant le checker sur le registre réel : M-Q5-C et M-Q5-D,
  // qui n'ont RIEN détecté (TP=0, FP=0), ressortaient à 1,00 — la formule récompensait
  // le silence. Un détecteur qui ne s'est jamais déclenché n'a pas une précision
  // parfaite : il n'a pas de précision du tout.
  if (denom === 0) return null;
  const precision = tp / denom;
  const couverture = Math.min(1, n / ECHANTILLON_DE_REFERENCE);
  return Number((precision * couverture).toFixed(2));
}

/**
 * Une référence de preuve existe-t-elle physiquement ?
 * @param {string} ref chemin relatif à la racine du dépôt
 * @returns {Promise<boolean>}
 */
export async function referenceExiste(ref) {
  try {
    await access(join(RACINE, ref));
    return true;
  } catch {
    return false;
  }
}

/**
 * Toutes les références de preuve d'une mutation, hors commits (un sha n'est pas un
 * fichier : sa vérification demanderait git, ce que ce checker n'exige pas).
 * @param {object} m
 * @returns {string[]}
 */
export function referencesFichiers(m) {
  const e = m.evidence_refs || {};
  return [...(e.artifacts || []), ...(e.tests || []), ...(e.reports || []), ...(e.telemetry || [])];
}

/**
 * Valide le registre entier.
 * @param {object} registre
 * @returns {Promise<{ok:boolean, problems:string[], confidences:object, stats:object}>}
 */
export async function checkRegistry(registre) {
  const problems = [];
  const confidences = {};
  const mutations = loadMutation(registre);

  if (registre?.schema_version !== 1) problems.push('schema_version doit valoir exactement 1');
  if (mutations.length === 0) problems.push('mutations: tableau vide — un registre sans mutation ne memorise rien');

  // 1. unicité des ids
  const vus = new Set();
  for (const m of mutations) {
    if (vus.has(m.id)) problems.push(`id duplique: '${m.id}' — toute reference devient ambigue`);
    vus.add(m.id);
  }

  let accepted = 0;
  let versioned = 0;

  // 0. VOCABULAIRE DES LAYERS — le champ `layer` est desormais VALIDE, pas decoratif.
  // Avant le 2026-08-04, l enum vivait en double dans deux .schema.json que AUCUN code
  // ne lisait : un champ declare, jamais verifie. Le vocabulaire a une source unique
  // (layers.json) et cette boucle est son premier lecteur mecanique.
  const layers = await loadLayers();
  if (layers.size === 0) {
    problems.push('layers.json illisible ou vide — le vocabulaire des layers est la source '
      + 'unique, son absence rend `layer` invalidable');
  }

  for (const m of mutations) {
    const loc = `[${m.id}]`;

    if (m.layer !== undefined && layers.size > 0 && !layers.has(m.layer)) {
      problems.push(`${loc} layer '${m.layer}' hors vocabulaire — valeurs connues : `
        + `${[...layers.keys()].join(', ')}`);
    }

    // 5 & 6 — compteurs
    if (m.confidence !== 'AUTO') {
      problems.push(`${loc} confidence doit valoir exactement 'AUTO' — elle est DERIVEE, jamais saisie`);
    }
    for (const cle of ['sample_size', 'false_positive', 'true_positive']) {
      const v = m[cle];
      if (v !== 'UNKNOWN' && (!Number.isInteger(v) || v < 0)) {
        problems.push(`${loc} ${cle}: entier >= 0 ou 'UNKNOWN' requis (recu ${JSON.stringify(v)})`);
      }
    }
    const c = deriverConfidence(m);
    confidences[m.id] = c;
    if (c !== null && (c < 0 || c > 1)) problems.push(`${loc} confidence derivee hors [0,1]: ${c}`);

    // 2 & 4 — accepted / rejected
    const refs = referencesFichiers(m);
    if (m.accepted === true) {
      accepted += 1;
      if (refs.length === 0 && (m.evidence_refs?.commits || []).length === 0) {
        problems.push(`${loc} ACCEPTED sans aucune evidence_ref — une mutation dont la seule preuve `
          + 'est une conversation ne peut pas etre acceptee');
      }
      if (m.rejected_reason !== null) {
        problems.push(`${loc} ACCEPTED mais rejected_reason non nul`);
      }
      if (m.evidence_status !== 'VERSIONED') {
        problems.push(`${loc} ACCEPTED avec evidence_status='${m.evidence_status}' — seule une preuve VERSIONED autorise l acceptation`);
      }
    } else {
      const r = m.rejected_reason;
      if (r === null || typeof r !== 'object') {
        problems.push(`${loc} non accepte sans rejected_reason — un rejet sans justification n apprend rien`);
      } else {
        if (!CODES_REJET.has(r.code)) problems.push(`${loc} rejected_reason.code inconnu: '${r.code}'`);
        if (typeof r.note !== 'string' || r.note.trim().length === 0) {
          problems.push(`${loc} rejected_reason.note vide — la machine lit le code, l humain lit la note`);
        }
      }
    }

    if (m.production_ready === true && m.accepted !== true) {
      problems.push(`${loc} production_ready sans accepted — utilisable en production sans etre scientifiquement retenue`);
    }

    // 3 — chaque référence existe physiquement
    if (m.evidence_status === 'VERSIONED' && refs.length === 0) {
      problems.push(`${loc} evidence_status=VERSIONED sans aucune reference fichier`);
    }
    if (m.evidence_status === 'UNKNOWN' && refs.length > 0) {
      problems.push(`${loc} evidence_status=UNKNOWN alors que des references sont listees — statut incoherent`);
    }
    if (m.evidence_status === 'VERSIONED') versioned += 1;
    for (const ref of refs) {
      // eslint-disable-next-line no-await-in-loop -- volume faible, sortie deterministe
      if (!(await referenceExiste(ref))) {
        problems.push(`${loc} evidence_ref introuvable sur disque: ${ref}`);
      }
    }

    // reproducibility : la commande doit citer un script qui existe
    const cmd = m.reproducibility?.command;
    if (typeof cmd === 'string' && cmd.trim()) {
      const script = cmd.split(/\s+/).find((t) => /[\\/].+\.(mjs|js|py)$/.test(t));
      // eslint-disable-next-line no-await-in-loop
      if (script && !(await referenceExiste(script))) {
        problems.push(`${loc} reproducibility.command cite un script introuvable: ${script}`);
      }
      if (!script) {
        problems.push(`${loc} reproducibility.command ne cite aucun script verifiable: '${cmd}'`);
      }
    }
    for (const chemin of [...(m.reproducibility?.inputs || []), ...(m.reproducibility?.expected_outputs || [])]) {
      // eslint-disable-next-line no-await-in-loop
      if (!(await referenceExiste(chemin))) {
        problems.push(`${loc} reproducibility cite un fichier introuvable: ${chemin}`);
      }
    }

    // --- V2 : eligibilite MCTS ---
    // OBSERVED <=> aucun contrat de recompense applicable. Les deux doivent bouger
    // ensemble : un statut qui dit "cherchable" alors qu aucun contrat ne permet de
    // comparer produirait un classement sans regle, c est-a-dire un score global
    // improvise — exactement ce que cette couche interdit.
    const sansContrat = m.reward_contract_ref === null || m.reward_contract_ref === undefined;
    if (sansContrat && m.status !== 'OBSERVED') {
      problems.push(`${loc} status='${m.status}' sans reward_contract_ref — une mutation sans `
        + 'contrat applicable doit rester memoire (status OBSERVED), jamais candidate MCTS');
    }
    if (!sansContrat && m.status === 'OBSERVED') {
      problems.push(`${loc} status=OBSERVED alors qu un reward_contract_ref est declare`);
    }
    if (m.root_problem_id === null && !sansContrat) {
      problems.push(`${loc} reward_contract_ref sans root_problem_id — le contrat appartient au probleme`);
    }

    // liens
    for (const cle of ['requires', 'conflicts']) {
      for (const ref of m[cle] || []) {
        if (!vus.has(ref) && !mutations.some((x) => x.id === ref)) {
          problems.push(`${loc} ${cle} pointe une mutation inexistante: '${ref}'`);
        }
      }
    }
  }

  return {
    ok: problems.length === 0,
    problems,
    confidences,
    stats: { mutations: mutations.length, accepted, versioned },
  };
}

// ---- CLI ----
const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  (async () => {
    const cible = process.argv.slice(2).find((a) => !a.startsWith('--')) || CHEMIN_REGISTRE;
    const { ok, registre, erreur } = await loadRegistry(cible);
    if (!ok) {
      console.error(`VERDICT REGISTRE: FAIL\n  ${erreur}`);
      process.exitCode = 1;
      return;
    }
    const r = await checkRegistry(registre);
    console.log(`VERDICT REGISTRE: ${r.ok ? 'OK' : 'FAIL'}`);
    r.problems.forEach((p) => console.error(`  FAIL: ${p}`));
    console.error(`  stats: ${r.stats.mutations} mutation(s) / ${r.stats.accepted} acceptee(s) / ${r.stats.versioned} a preuve versionnee`);
    console.error('  confidences DERIVEES (precision x couverture) :');
    for (const [id, c] of Object.entries(r.confidences)) {
      console.error(`    ${id.padEnd(30)} ${c === null ? 'UNKNOWN' : c}`);
    }
    console.log(JSON.stringify({ ok: r.ok, problems: r.problems, confidences: r.confidences, stats: r.stats }, null, 1));
    process.exitCode = r.ok ? 0 : 1;
  })();
}
