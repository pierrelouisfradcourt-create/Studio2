#!/usr/bin/env node
// mutation_registry.mjs — API de LECTURE du MUTATION_REGISTRY_V1.
//
// Lecture seule, aucune logique métier, aucune écriture. Le registre est la source
// UNIQUE de vérité sur les mutations : le génome d'un agent n'en porte que les
// identifiants. Dupliquer une mutation dans un génome créerait deux versions d'un même
// fait, et deux faits qui disent la même chose finissent toujours par diverger.
//
// La `confidence` n'est PAS lue ici : elle vaut toujours 'AUTO' dans le fichier et
// n'existe qu'une fois DÉRIVÉE par check_mutation_registry.mjs. Un consommateur qui
// veut un chiffre doit demander la dérivation, pas lire un champ — sinon quelqu'un
// finira par écrire 0,95 à la main sans savoir d'où ça vient.

import { readFile } from 'node:fs/promises';
import { resolve, dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

export const CHEMIN_REGISTRE = join(
  dirname(fileURLToPath(import.meta.url)), 'mutation_registry.json',
);

/**
 * Charge le registre. Ne lève jamais : rend {ok, registre, erreur}.
 * @param {string} chemin
 * @returns {Promise<{ok:boolean, registre:object|null, erreur:string|null}>}
 */
export async function loadRegistry(chemin = CHEMIN_REGISTRE) {
  let raw;
  try {
    raw = await readFile(chemin, 'utf-8');
  } catch (err) {
    return { ok: false, registre: null, erreur: `${chemin}: illisible (${err.message})` };
  }
  try {
    const registre = JSON.parse(raw);
    return { ok: true, registre, erreur: null };
  } catch (err) {
    return { ok: false, registre: null, erreur: `${chemin}: JSON invalide (${err.message})` };
  }
}

/**
 * Toutes les mutations du registre.
 * @param {object} registre
 * @returns {Array}
 */
export function loadMutation(registre) {
  return Array.isArray(registre?.mutations) ? registre.mutations : [];
}

/**
 * Une mutation par id. `null` si absente — jamais une exception : demander une
 * mutation inconnue est une question légitime, pas une faute.
 * @param {object} registre
 * @param {string} id
 * @returns {object|null}
 */
export function findMutation(registre, id) {
  return loadMutation(registre).find((m) => m.id === id) || null;
}

/**
 * Mutations retenues scientifiquement. C'est ce que l'Agent Factory aura le droit de
 * sélectionner — et rien d'autre.
 * @param {object} registre
 * @returns {Array}
 */
export function findAccepted(registre) {
  return loadMutation(registre).filter((m) => m.accepted === true);
}

/**
 * Mutations acceptées ET utilisables en production. Sous-ensemble strict de
 * `findAccepted` : une mutation peut être valide et pas encore assez éprouvée pour
 * sortir du laboratoire.
 * @param {object} registre
 * @returns {Array}
 */
export function findProductionReady(registre) {
  return loadMutation(registre).filter((m) => m.accepted === true && m.production_ready === true);
}

/**
 * Mutations écartées, avec leur code de rejet lisible par machine.
 * @param {object} registre
 * @param {string|null} code filtre optionnel sur rejected_reason.code
 * @returns {Array}
 */
export function findRejected(registre, code = null) {
  return loadMutation(registre).filter(
    (m) => m.accepted === false && (code === null || m.rejected_reason?.code === code),
  );
}

/**
 * @param {object} registre
 * @param {string} layer
 * @returns {Array}
 */
export function findByLayer(registre, layer) {
  return loadMutation(registre).filter((m) => m.layer === layer);
}

/** Chemin du vocabulaire des layers — SOURCE UNIQUE, lue par le checker et le sélecteur. */
export const CHEMIN_LAYERS = join(
  dirname(fileURLToPath(import.meta.url)), 'layers.json',
);

/**
 * Vocabulaire des layers : `Map<id, {chain, broken_loop, …}>`.
 *
 * Une layer est une ZONE OÙ UNE BOUCLE PEUT CASSER — jamais un agent, un rôle, un
 * fichier ni une capacité. Le vocabulaire vit dans UN fichier ; les deux schémas
 * (`mutation_registry.schema.json`, `root_problem.schema.json`) en portent une copie
 * pour rester lisibles seuls, et un test vérifie qu'elles ne divergent pas.
 *
 * @param {string} [chemin]
 * @returns {Promise<Map<string, object>>} vide si le fichier est illisible — jamais d'exception
 */
export async function loadLayers(chemin = CHEMIN_LAYERS) {
  try {
    const doc = JSON.parse(await readFile(chemin, 'utf-8'));
    return new Map((doc.layers || []).map((l) => [l.id, l]));
  } catch {
    return new Map();
  }
}

/**
 * @param {object} registre
 * @param {string} worker
 * @returns {Array}
 */
export function findByWorker(registre, worker) {
  return loadMutation(registre).filter((m) => m.worker === worker);
}

/**
 * @param {object} registre
 * @param {string} target
 * @returns {Array}
 */
export function findByTarget(registre, target) {
  return loadMutation(registre).filter((m) => m.target === target);
}

/**
 * @param {object} registre
 * @param {string} mutation_class
 * @returns {Array}
 */
export function findByClass(registre, mutation_class) {
  return loadMutation(registre).filter((m) => m.mutation_class === mutation_class);
}

// ---- CLI ----
const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  (async () => {
    const { ok, registre, erreur } = await loadRegistry();
    if (!ok) {
      console.error(erreur);
      process.exitCode = 1;
      return;
    }
    const total = loadMutation(registre).length;
    const acc = findAccepted(registre);
    const prod = findProductionReady(registre);
    console.log(`MUTATION_REGISTRY_V1 — ${total} mutation(s)`);
    console.log(`  ACCEPTED         : ${acc.length}  (${acc.map((m) => m.id).join(', ') || '—'})`);
    console.log(`  production_ready : ${prod.length}  (${prod.map((m) => m.id).join(', ') || '—'})`);
    for (const code of ['REFUTED_FALSE_POSITIVE', 'NO_MEASURED_GAIN', 'BLIND_TO_TESTED_DEFECT',
      'NOT_REPRODUCIBLE', 'SUPERSEDED']) {
      const r = findRejected(registre, code);
      if (r.length) console.log(`  ${code.padEnd(24)} : ${r.map((m) => m.id).join(', ')}`);
    }
  })();
}
