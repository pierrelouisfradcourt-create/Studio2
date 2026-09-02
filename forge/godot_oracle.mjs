#!/usr/bin/env node
// godot_oracle.mjs — Oracle maitre pour un projet Godot de la Forge.
// Enchaine (1) run_tests.gd (mecanique, headless) puis (2) solvability_godot.mjs
// (R9 : un bot doit reellement gagner). Exit 0 SEULEMENT si les DEUX sont
// verts ; sinon exit 1 des le premier rouge (jamais un vert par defaut).
//
// Le binaire Godot est toujours resolu via resolveGodotBin() (Tache 1) —
// jamais un chemin en dur.
import { spawnSync } from 'node:child_process';
import { readFileSync, existsSync } from 'node:fs';
import { resolve, dirname, basename } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { resolveGodotBin } from './godot_bin.mjs';
import {
  DEFAULT_MAX_TICKS,
  DEFAULT_TRIAL_TIMEOUT_MS,
  DEFAULT_SEED_START,
} from './solvability_godot.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = resolve(HERE, '..');
const ORACLES_CONFIG = resolve(HERE, 'oracles.json');

const TEST_SCRIPT = 'res://tests/run_tests.gd';
const SOLVABILITY_SCRIPT = 'res://solvability.gd';
const SOLVABILITY_TRIALS = 50;

/**
 * Budget de la solvabilite DECLARE PAR JEU (correction 2026-07-28) : une partie
 * gagnante peut prendre bien plus que DEFAULT_MAX_TICKS (200) — mesure sur
 * `snake` : parties gagnantes de 266-417 ticks, faux negatif 0/50 avec le
 * defaut. Lu depuis l'entree `oracles.json` du jeu (cle = basename(project),
 * meme convention que forge/oracle.py::resolve_oracle), champ optionnel
 * `solvability: {max_ticks, trials, trial_timeout_ms}`.
 *
 * Absence totale (fichier illisible, entree manquante, champ manquant) ->
 * REPLI EXACT sur les valeurs historiques (DEFAULT_MAX_TICKS/SOLVABILITY_TRIALS/
 * DEFAULT_TRIAL_TIMEOUT_MS) : comportement INCHANGE pour tout jeu qui ne
 * declare rien (ex. grid_nav_probe) — jamais un chemin d'erreur silencieux qui
 * modifierait un budget par accident.
 */
export function resolveSolvabilityConfig(project, configPath = ORACLES_CONFIG) {
  const key = basename(project);
  let raw;
  try {
    raw = readFileSync(configPath, 'utf8');
  } catch (e) {
    console.warn(`[godot_oracle] oracles.json illisible (${e.message}) — budget par defaut`);
    raw = null;
  }
  let entry = null;
  if (raw !== null) {
    try {
      const config = JSON.parse(raw);
      entry = config && typeof config === 'object' ? config[key] : null;
    } catch (e) {
      console.warn(`[godot_oracle] oracles.json invalide (${e.message}) — budget par defaut`);
      entry = null;
    }
  }
  const solv = entry && typeof entry === 'object' && entry.solvability &&
    typeof entry.solvability === 'object' ? entry.solvability : {};
  return {
    trials: Number.isFinite(solv.trials) ? solv.trials : SOLVABILITY_TRIALS,
    maxTicks: Number.isFinite(solv.max_ticks) ? solv.max_ticks : DEFAULT_MAX_TICKS,
    trialTimeoutMs: Number.isFinite(solv.trial_timeout_ms)
      ? solv.trial_timeout_ms
      : DEFAULT_TRIAL_TIMEOUT_MS,
    // BUDGET TOTAL, optionnel et SANS defaut : `null` quand le jeu n'en declare pas, jamais
    // une valeur inventee. Un plafond par defaut borner ait des runs qui passent aujourd'hui
    // — le champ n'agit que si un jeu le demande explicitement.
    totalTimeoutS: Number.isFinite(solv.total_timeout_s) ? solv.total_timeout_s : null,
    seedStart: DEFAULT_SEED_START,
  };
}

/**
 * Chemin sur disque de res://solvability.gd pour un projet donne (constante
 * SOLVABILITY_SCRIPT, ancree au projet comme dans runSolvabilityGate).
 */
/** Prefixe de la ligne de resume machine, meme convention que `FORGE_ORACLE`/`FORGE_TRIAL`/
 * `FORGE_DIAG` : un prefixe, un JSON, UNE ligne — extractible d un flux bruite sans le
 * parser entier. */
export const SUMMARY_PREFIX = 'FORGE_ORACLE_SUMMARY ';

/**
 * Extrait le recu de solvabilite d une sortie BRUITEE (banniere moteur, lignes
 * `[godot_oracle] ...`, warnings). BEST-EFFORT STRICT : `null` en cas d absence ou
 * d illisibilite, JAMAIS une exception — le recu structure est un GAIN, jamais une
 * condition ; un oracle qui tourne sans emettre de JSON ne doit pas devenir un echec de
 * parsing.
 *
 * DISCRIMINE ce qui est un recu : sans cela, n importe quel objet imprime par le moteur
 * passerait pour tel, et le driver conserverait du bruit dans un detail signe. Le DERNIER
 * recu gagne — un run peut relancer la solvabilite, c est l etat final qui fait foi.
 * @param {string} stdout
 * @returns {object|null}
 */
export function parseSolvabilityReceipt(stdout) {
  const texte = typeof stdout === 'string' ? stdout : '';
  if (!texte) return null;
  let trouve = null;
  // Le recu est imprime par `solvability_godot.mjs` avec `JSON.stringify(x, null, 2)` :
  // il s etale sur plusieurs lignes. On balaie donc les debuts d objet et on tente de
  // parser des blocs croissants — couteux mais borne, et sans dependance a un formatage.
  const lignes = texte.split(/\r?\n/);
  for (let i = 0; i < lignes.length; i += 1) {
    if (!lignes[i].trimStart().startsWith('{')) continue;
    for (let j = i; j < lignes.length; j += 1) {
      let obj;
      try {
        obj = JSON.parse(lignes.slice(i, j + 1).join('\n'));
      } catch { continue; }
      if (estUnRecuDeSolvabilite(obj)) trouve = obj;
      break;
    }
  }
  return trouve;
}

/** Un recu de solvabilite porte AU MOINS un verdict et un compte d essais gagnes. */
function estUnRecuDeSolvabilite(o) {
  return o !== null && typeof o === 'object' && !Array.isArray(o)
    && typeof o.verdict === 'string' && typeof o.won === 'number';
}

/**
 * Ligne de resume destinee au consommateur (Python, `oracle.run_oracle`). EMISE MEME quand
 * la solvabilite n a produit aucun recu : `solvabilite: null` est une INFORMATION, alors
 * qu une ligne absente serait indistinguable d un oracle qui n aurait pas tourne — meme
 * discipline que `NOT_MEASURED != OK`, appliquee au transport.
 * @param {{mecanique: boolean, solvabilite: (object|null)}} resume
 */
export function buildSummaryLine(resume) {
  return SUMMARY_PREFIX + JSON.stringify({
    mecanique: resume.mecanique === true,
    solvabilite: resume.solvabilite ?? null,
  });
}

function solvabilityScriptPath(project) {
  return resolve(REPO_ROOT, project, 'solvability.gd');
}

/**
 * Distingue un JEU (a un point d'entree jouable) d'un MODULE BIBLIOTHEQUE
 * (harnais de logique pure, jamais lance) par un critere MECANIQUE et lisible
 * lu directement dans project.godot : `run/main_scene`.
 *
 * Pourquoi ce critere : c'est deja l'invariant du studio pour « ce projet
 * DOIT demarrer » (POINT DUR #5 du charter, ex. GAMES/breakout_v2/project.godot
 * qui commente explicitement `run/main_scene="res://main.tscn"`). Un module
 * bibliotheque (ex. GAMES/grid_nav_probe, GAMES/p5_gridnav) n'a ni scene ni
 * raison d'en avoir une — donc n'a pas de raison d'avoir un bot de
 * solvabilite (R9) non plus : R9 mesure qu'un bot peut GAGNER une PARTIE,
 * et une partie suppose une scene jouable.
 *
 * Defaut fail-safe : project.godot illisible/absent -> traite comme JEU
 * (R9 reste exige). En cas de doute, on n'affaiblit jamais l'invariant R9,
 * on l'assouplit seulement pour un cas mecaniquement prouve « pas un jeu ».
 *
 * (Correction 2026-08-02, campagne P5 : SOLVABILITY_SCRIPT etait exige sans
 * condition, quel que soit le projet -> 3 activations LLM/4 gaspillees sur
 * p5_gridnav, un module de bibliotheque pure, a produire un solvability.gd
 * qui n'avait aucune raison d'etre.)
 */
function hasMainScene(project) {
  const path = resolve(REPO_ROOT, project, 'project.godot');
  let raw;
  try {
    raw = readFileSync(path, 'utf8');
  } catch (e) {
    console.warn(
      `[godot_oracle] project.godot illisible (${e.message}) — traite comme JEU par defaut ` +
      `(fail-safe : R9 reste exige en cas de doute)`
    );
    return true;
  }
  const match = raw.match(/^\s*run\/main_scene\s*=\s*"([^"]*)"/m);
  return Boolean(match && match[1].length > 0);
}

/** Lance run_tests.gd headless sur le projet. true si exit 0. */
function runMechanicalTests(project) {
  console.log('[godot_oracle] === run_tests.gd (mecanique) ===');
  let bin;
  try {
    bin = resolveGodotBin();
  } catch (e) {
    console.error(`[godot_oracle] resolution du binaire Godot impossible : ${e.message}`);
    return false;
  }
  const res = spawnSync(
    bin,
    ['--headless', '--path', resolve(REPO_ROOT, project), '--script', TEST_SCRIPT],
    { stdio: 'inherit', windowsHide: true }
  );
  if (res.error) {
    console.error(`[godot_oracle] spawn Godot impossible : ${res.error.message}`);
    return false;
  }
  return res.status === 0;
}

/**
 * Extremite AMONT du pont CLI : configuration -> argv. EXPORTEE pour etre testable.
 *
 * Le budget voyage entre deux processus par une ligne de commande POSITIONNELLE : un champ
 * remonte par le resolveur mais jamais passe ici serait INERTE en production alors que ses
 * tests unitaires passent. Defaut mesure le 2026-08-17 : `totalTimeoutS` etait bien resolu
 * depuis `oracles.json` et n'etait NI destructure NI transmis — le mecanisme d'arret motive
 * ne pouvait pas s'armer. Les deux extremites sont donc PURES, et un test d'aller-retour
 * prouve qu'elles s'accordent (`solvability_total_timeout.test.mjs`).
 *
 * `total_timeout_s` en 7e position, OPTIONNELLE : omise quand le jeu n'en declare pas —
 * l'aval retombe alors sur `undefined` et le comportement reste strictement inchange.
 */
export function buildSolvabilityArgv(script, project, cfg) {
  const argv = [
    script, project, SOLVABILITY_SCRIPT,
    String(cfg.trials), String(cfg.seedStart), String(cfg.maxTicks),
    String(cfg.trialTimeoutMs),
  ];
  if (cfg.totalTimeoutS !== null && cfg.totalTimeoutS !== undefined) {
    argv.push(String(cfg.totalTimeoutS));
  }
  return argv;
}

/** Lance l oracle de solvabilite (sous-processus node) sur le projet. true si exit 0. */
function runSolvabilityGate(project) {
  console.log('[godot_oracle] === solvability_godot.mjs (R9) ===');
  const script = resolve(HERE, 'solvability_godot.mjs');
  const cfg = resolveSolvabilityConfig(project);
  console.log(
    `[godot_oracle] budget solvabilite : trials=${cfg.trials} max_ticks=${cfg.maxTicks} ` +
    `trial_timeout_ms=${cfg.trialTimeoutMs}` +
    (cfg.totalTimeoutS !== null ? ` total_timeout_s=${cfg.totalTimeoutS}` : '') +
    ' (declare par jeu, defaut si absent)'
  );
  // CAPTURE au lieu d HERITER (2026-08-18) : avec `stdio: 'inherit'`, le JSON du recu
  // allait DIRECTEMENT sur la sortie du parent et `godot_oracle` ne voyait que
  // `res.status` — le recu n existait que dans un journal exclu par .gitignore. PRIX
  // ASSUME (GO Pierre) : la sortie de l enfant n apparait plus EN CONTINU mais a la fin.
  // On la RE-IMPRIME integralement — un operateur qui lisait ce flux continue de le lire.
  const res = spawnSync(
    process.execPath,
    buildSolvabilityArgv(script, project, cfg),
    { cwd: REPO_ROOT, encoding: 'utf-8', maxBuffer: 20 * 1024 * 1024 }
  );
  if (res.stdout) process.stdout.write(res.stdout);
  if (res.stderr) process.stderr.write(res.stderr);
  if (res.error) {
    console.error(`[godot_oracle] spawn node solvability_godot.mjs impossible : ${res.error.message}`);
    return { ok: false, recu: null };
  }
  return { ok: res.status === 0, recu: parseSolvabilityReceipt(res.stdout) };
}

function main(argv) {
  const project = argv[0];
  if (!project) {
    console.error('Usage: node godot_oracle.mjs <project>');
    process.exit(2);
    return;
  }

  if (!runMechanicalTests(project)) {
    console.error('[godot_oracle] FAIL : run_tests.gd (mecanique)');
    // Resume EMIS meme en echec : un consommateur doit pouvoir distinguer « la mecanique a
    // echoue » de « l oracle n a pas tourne ». Une ligne absente ne dit ni l un ni l autre.
    console.log(buildSummaryLine({ mecanique: false, solvabilite: null }));
    process.exit(1);
    return;
  }
  console.log('[godot_oracle] OK : run_tests.gd (mecanique)');

  let solvabiliteRecu = null;
  const scriptExists = existsSync(solvabilityScriptPath(project));
  if (!scriptExists) {
    if (hasMainScene(project)) {
      // JEU sans solvability.gd : R9 est un invariant du studio pour un jeu,
      // ce n'est pas mesurable-donc-ignorable. FAIL, pas un vert par defaut.
      console.error(
        '[godot_oracle] FAIL : solvabilite (R9) — solvability.gd absent et le projet ' +
        'declare run/main_scene (c\'est un JEU) : R9 est obligatoire pour un jeu.'
      );
      process.exit(1);
      return;
    }
    // MODULE BIBLIOTHEQUE (pas de run/main_scene) sans solvability.gd : rien
    // a mesurer (pas de partie a gagner), volet rendu NOT_MEASURED — jamais
    // FAIL pour une absence de preuve qui n'a pas de raison d'exister.
    console.log(
      '[godot_oracle] NOT_MEASURED : solvabilite (R9) — module bibliotheque ' +
      '(project.godot sans run/main_scene), solvability.gd absent, aucun bot ' +
      'de solvabilite requis.'
    );
  } else {
    // `runSolvabilityGate` rend desormais `{ok, recu}` : lire `.ok` EXPLICITEMENT. Tester
    // `!runSolvabilityGate(...)` sur un OBJET serait toujours faux — le gate ne pourrait
    // plus jamais echouer. Piege introduit puis corrige le 2026-08-18.
    const r = runSolvabilityGate(project);
    solvabiliteRecu = r.recu;
    if (!r.ok) {
      console.error('[godot_oracle] FAIL : solvabilite (R9)');
      console.log(buildSummaryLine({ mecanique: true, solvabilite: solvabiliteRecu }));
      process.exit(1);
      return;
    }
    console.log('[godot_oracle] OK : solvabilite (R9)');
  }
  console.log(buildSummaryLine({ mecanique: true, solvabilite: solvabiliteRecu }));

  console.log('[godot_oracle] ALL CHECKS PASSED');
  process.exit(0);
}

const isMain = process.argv[1] && pathToFileURL(process.argv[1]).href === import.meta.url;
if (isMain) {
  main(process.argv.slice(2));
}
