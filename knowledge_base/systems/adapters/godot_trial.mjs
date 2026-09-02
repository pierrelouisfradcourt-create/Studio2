// godot_trial.mjs — ADAPTATEUR : expose la signature runTrial(seed, cfg) attendue par
// role_sim.mjs, en deleguant l execution a Godot headless. role_sim.mjs n est PAS
// modifie : le couplage au moteur vit ici, dans un module de scenario, exactement la
// ou le schema de contrat le prevoit deja (champ simulation_module).
//
// Contrat de sortie du projet Godot : une ligne stdout `FORGE_TRIAL <json>` avec
// {"succeeded": bool, "ticks": number|null}. Exit 0 exige.
import { spawnSync } from 'node:child_process';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { resolveGodotBin } from '../../../scripts/forge/godot_bin.mjs';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const PREFIX = 'FORGE_TRIAL ';
// Canal de DIAGNOSTIC, distinct du recu (2026-08-18). `bomberman_3d/solvability.gd`
// l'emet a cote du verdict pour qu'« un essai perdu puisse etre DIAGNOSTIQUE » — mais
// `parseReceipt` filtrait sur le seul prefixe du recu, et TOUT le reste partait avec le
// stdout. L'intention du producteur etait annulee par le consommateur : producteur sans
// consommateur, sur la seule information qui dirait POURQUOI un essai echoue.
const PREFIX_DIAG = 'FORGE_DIAG ';
const REQUIRED_CFG = ['godot_project', 'godot_script', 'trial_timeout_ms'];

/**
 * Extrait le recu JSON d une sortie Godot bruitee (banniere moteur, warnings…), et le
 * diagnostic optionnel qui l accompagne.
 *
 * `diag` est un CONFORT, jamais une condition : un diagnostic absent, illisible ou en
 * double ne fait JAMAIS perdre un verdict valide (best-effort strict). Le RECU, lui, reste
 * STRICT — absent, illisible ou en double = erreur. Elargir ce que l adaptateur RETIENT ne
 * relache pas ce qu il VALIDE.
 * @param {string} stdout
 * @returns {{succeeded: boolean, ticks: (number|null), diag: (object|null)}}
 */
export function parseReceipt(stdout) {
  const lines = String(stdout).split(/\r?\n/).filter((l) => l.startsWith(PREFIX));
  if (lines.length === 0) throw new Error(`aucun recu FORGE_TRIAL dans la sortie Godot`);
  if (lines.length > 1) {
    throw new Error(`${lines.length} recus FORGE_TRIAL trouves dans la sortie Godot (ambigu, 1 attendu)`);
  }
  const line = lines[0];
  let parsed;
  try {
    parsed = JSON.parse(line.slice(PREFIX.length));
  } catch (e) {
    throw new Error(`recu FORGE_TRIAL illisible : ${e.message}`);
  }
  if (typeof parsed.succeeded !== 'boolean') throw new Error('champ succeeded absent ou non booleen');
  if (parsed.ticks !== null && typeof parsed.ticks !== 'number') throw new Error('champ ticks doit etre number ou null');
  // Diagnostic : PREMIER trouve, ordre indifferent (le producteur ecrit DIAG puis TRIAL,
  // mais rien ne l impose). Un JSON casse ici est IGNORE — `null`, jamais un objet vide qui
  // laisserait croire a un diagnostic vierge.
  let diag = null;
  const ligneDiag = String(stdout).split(/\r?\n/).find((l) => l.startsWith(PREFIX_DIAG));
  if (ligneDiag !== undefined) {
    try {
      const d = JSON.parse(ligneDiag.slice(PREFIX_DIAG.length));
      if (d !== null && typeof d === 'object' && !Array.isArray(d)) diag = d;
    } catch { /* diagnostic illisible : ignore, le verdict prime */ }
  }
  return { succeeded: parsed.succeeded, ticks: parsed.ticks, diag };
}

/**
 * Fabrique un runTrial. Les dependances sont injectables pour rendre l adaptateur
 * testable sans lancer Godot (tests unitaires) tout en restant reel en production.
 * @param {Function} [spawnFn] signature (bin, args, opts) -> {status, stdout, stderr}
 * @param {Function} [binResolver]
 */
export function makeGodotRunTrial(spawnFn, binResolver) {
  const doSpawn = spawnFn ?? ((bin, args, opts) => spawnSync(bin, args, opts));
  const getBin = binResolver ?? resolveGodotBin;

  return function runTrial(seed, cfg) {
    for (const k of REQUIRED_CFG) {
      if (cfg == null || cfg[k] === undefined) {
        throw new Error(`simulation_config incomplet : champ '${k}' requis par godot_trial`);
      }
    }
    if (typeof cfg.trial_timeout_ms !== 'number' || !Number.isFinite(cfg.trial_timeout_ms) || cfg.trial_timeout_ms <= 0) {
      throw new Error(`simulation_config invalide : champ 'trial_timeout_ms' doit etre un nombre fini strictement positif`);
    }
    const bin = getBin();
    const args = [
      '--headless',
      '--path', resolve(REPO_ROOT, cfg.godot_project),
      '--script', cfg.godot_script,
      '--',
      `--seed=${seed}`,
      `--max_ticks=${cfg.max_ticks ?? 0}`,
    ];
    const res = doSpawn(bin, args, {
      encoding: 'utf-8',
      timeout: cfg.trial_timeout_ms,
      windowsHide: true,
    });
    if (res.error) throw new Error(`spawn Godot impossible : ${res.error.message}`);
    if (res.status !== 0) {
      throw new Error(`Godot exit ${res.status} (seed=${seed})\nstderr: ${res.stderr}\nstdout: ${res.stdout}`);
    }
    return parseReceipt(res.stdout);
  };
}

export const runTrial = makeGodotRunTrial();
