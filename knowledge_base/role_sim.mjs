#!/usr/bin/env node
// role_sim.mjs — ROLE-SIM Oracle (docs/forge/STUDIO_AGENT_ATLAS.md §2.3), service non-LLM.
// Valide un ROLE gameplay PAR SIMULATION : ne mesure jamais un booléen gagné/perdu
// (ça, c'est solvability.mjs) — mesure une BANDE DE DIFFICULTÉ sur N essais seedés, et la
// compare à la bande DÉCLARÉE dans le contrat rôle (knowledge_base/roles/<role>.yaml).
//
// GÉNÉRIQUE depuis le 2e rôle (2026-07-13, test de généralisation) : ce fichier ne
// connaît PLUS la mécanique d'un rôle précis (poursuite, zone de contrôle, ...) — chaque
// contrat rôle déclare son propre `simulation_module`, un .mjs exportant
// `runTrial(seed, cfg) -> {succeeded, ticks}`, chargé dynamiquement. La logique
// pursuer-vs-evader d'origine a été EXTRAITE (inchangée) vers
// systems/ai/pursuer_scenario.mjs — vérifié : mêmes médianes mesurées après extraction.
//
// Lecteur YAML volontairement MINIMAL (pas de dépendance npm) : ne comprend QUE le
// sous-ensemble utilisé par les contrats rôle (scalaires top-level `key: value`, blocs
// plats `key:\n  subkey: value` sur UN niveau d'indentation, listes `- item`). Suffisant
// et robuste pour ce format contrôlé — pas un parseur YAML générique.
//
// Usage : node role_sim.mjs <role.yaml>
// Exit 0 = bande mesurée DANS la bande déclarée · 1 = hors bande (rapporté tel quel,
// jamais édulcoré) · 2 = contrat invalide (champ Critique absent) ou erreur.
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');

// ---- lecteur YAML minimal (sous-ensemble contrôlé, cf. en-tête) ----

/**
 * Extrait la valeur d'un scalaire top-level `key: value` (une ligne, pas de bloc).
 * Gère `>-` (repliage sur les lignes indentées suivantes, comme YAML block scalar).
 * @param {string} text
 * @param {string} key
 * @returns {string|null} null si la clé est absente
 */
function extractScalar(text, key) {
  const lineMatch = text.match(new RegExp(`^${key}:[ \\t]*(.*)$`, 'm'));
  if (!lineMatch) return null;
  const inline = lineMatch[1].trim();
  if (inline && inline !== '>-' && inline !== '|-') return stripQuotes(inline);
  if (inline === '>-' || inline === '|-') {
    // Bloc replié : concatène les lignes indentées qui suivent jusqu'à la 1re ligne
    // non-indentée (ou EOF).
    const afterIdx = lineMatch.index + lineMatch[0].length;
    const rest = text.slice(afterIdx + 1);
    const blockLines = [];
    for (const line of rest.split('\n')) {
      if (line === '' || /^[ \t]/.test(line)) {
        blockLines.push(line.trim());
      } else {
        break;
      }
    }
    return blockLines.join(' ').trim();
  }
  return null;
}

function stripQuotes(str) {
  if ((str.startsWith('"') && str.endsWith('"')) || (str.startsWith("'") && str.endsWith("'"))) {
    return str.slice(1, -1);
  }
  return str;
}

/**
 * Extrait un bloc plat `blockKey:\n  sub: value\n  sub2: value` — UN niveau
 * d'indentation, valeurs numériques auto-converties. Retourne null si le bloc est absent.
 * @param {string} text
 * @param {string} blockKey
 * @returns {Object<string, (string|number)>|null}
 */
function extractFlatBlock(text, blockKey) {
  const blockMatch = text.match(new RegExp(`^${blockKey}:[ \\t]*$`, 'm'));
  if (!blockMatch) return null;
  const afterIdx = blockMatch.index + blockMatch[0].length;
  const rest = text.slice(afterIdx + 1);
  const result = {};
  for (const line of rest.split('\n')) {
    if (!/^[ \t]+\S/.test(line)) break; // dédent = fin du bloc
    const m = line.match(/^\s+([a-zA-Z_][\w]*):\s*(.*)$/);
    if (!m) continue;
    const [, key, rawValue] = m;
    const trimmed = stripQuotes(rawValue.trim());
    result[key] = /^-?\d+(\.\d+)?$/.test(trimmed) ? Number(trimmed) : trimmed;
  }
  return Object.keys(result).length ? result : null;
}

// Ouverture aux futurs runtimes — FAIL-CLOSED (spec etape 0 §5). Le schema NOMME des
// runtimes futurs pour que les contrats restent ecrits sans eux ; l executeur REFUSE
// tout ce qu il ne sait pas executer. Declarer un point d extension sans le fermer,
// c est reproduire le mode de panne « declare != execute ».
export const IMPLEMENTED_RUNTIMES = ['node', 'godot'];
export const RESERVED_RUNTIMES = ['unity', 'unreal'];

/**
 * @param {string|null} value valeur deja nettoyee (commentaire retire, trim) — null/absent = defaut 'node'
 * @returns {string[]} findings (vide = accepte)
 */
export function checkSimulationRuntime(value) {
  if (value === null || value === undefined || value === '') return [];
  if (IMPLEMENTED_RUNTIMES.includes(value)) return [];
  if (RESERVED_RUNTIMES.includes(value)) {
    return [`simulation_runtime '${value}' : reconnu par le schema, non implemente par l executeur `
      + `(implementes : ${IMPLEMENTED_RUNTIMES.join(', ')})`];
  }
  const knownRuntimes = [...IMPLEMENTED_RUNTIMES, ...RESERVED_RUNTIMES];
  const caseInsensitiveMatch = knownRuntimes.find((r) => r.toLowerCase() === value.toLowerCase());
  if (caseInsensitiveMatch) {
    return [`simulation_runtime '${value}' : casse invalide — comparaison strictement sensible a la `
      + `casse, orthographe attendue '${caseInsensitiveMatch}'`];
  }
  return [`simulation_runtime '${value}' : inconnu du schema `
    + `(implementes : ${IMPLEMENTED_RUNTIMES.join(', ')} · reserves : ${RESERVED_RUNTIMES.join(', ')})`];
}

/**
 * Retire un commentaire de fin de ligne (` #...`) d'un scalaire deja extrait, et trim.
 * @param {string} raw
 * @returns {string}
 */
function stripInlineComment(raw) {
  const idx = raw.search(/\s#/);
  return (idx === -1 ? raw : raw.slice(0, idx)).trim();
}

const SIMULATION_RUNTIME_ILLISIBLE =
  'simulation_runtime : champ present mais illisible (liste YAML, bloc, ou valeur vide) — '
  + 'ce lecteur YAML minimal n\'accepte ici qu\'un scalaire unique sur une ligne, '
  + `ex: simulation_runtime: ${IMPLEMENTED_RUNTIMES[0]}`;

/**
 * Valide le champ `simulation_runtime` a partir du TEXTE BRUT du contrat, pas de la
 * valeur deja extraite — c'est justement l'extraction qui ment sur une liste/bloc (elle
 * renvoie null, indiscernable d'un champ absent). La detection de presence se fait donc
 * par une regex sur le texte ; extractScalar ne sert plus qu'a recuperer la valeur QUAND
 * elle est un scalaire exploitable.
 * @param {string} text texte complet du contrat
 * @returns {{findings: string[], value: (string|null)}}
 */
export function checkSimulationRuntimePresence(text) {
  const keyPresent = /^simulation_runtime:/m.test(text);
  if (!keyPresent) return { findings: [], value: null };

  const rawValue = extractScalar(text, 'simulation_runtime');
  if (rawValue === null || rawValue === undefined || rawValue === '') {
    return { findings: [SIMULATION_RUNTIME_ILLISIBLE], value: null };
  }

  const cleaned = stripInlineComment(rawValue);
  if (cleaned === '') {
    return { findings: [SIMULATION_RUNTIME_ILLISIBLE], value: null };
  }

  return { findings: checkSimulationRuntime(cleaned), value: cleaned };
}

/**
 * Charge et valide la structure minimale d'un contrat rôle (règle des 3 états, SCHEMA.md).
 * @param {string} filePath
 * @returns {{role:object, findings:string[]}}
 */
export function loadRole(filePath) {
  const text = readFileSync(filePath, 'utf-8');
  const findings = [];

  const roleId = extractScalar(text, 'role_id');
  const archetype = extractScalar(text, 'archetype');
  const tier = extractScalar(text, 'tier');
  const license = extractScalar(text, 'license');
  const path = extractScalar(text, 'path');
  const proofOfUse = extractScalar(text, 'proof_of_use');
  const simulationModule = extractScalar(text, 'simulation_module');
  const simulationConfig = extractFlatBlock(text, 'simulation_config');
  const difficultyTarget = extractFlatBlock(text, 'difficulty_target');
  const requiresPresent = /^requires:[ \t]*$/m.test(text);
  const { findings: simulationRuntimeFindings, value: simulationRuntime } = checkSimulationRuntimePresence(text);
  findings.push(...simulationRuntimeFindings);

  if (!roleId) findings.push('champ Critique absent : role_id');
  if (!archetype || archetype.length < 20) findings.push('champ Critique absent/trop court : archetype');
  if (!requiresPresent) findings.push('champ Critique absent : requires');
  if (!simulationModule) findings.push('champ Critique absent : simulation_module');
  if (!simulationConfig) findings.push('champ Critique absent : simulation_config');
  if (!difficultyTarget) findings.push('champ Critique absent : difficulty_target');
  if (!tier) findings.push('champ Critique absent : tier');
  if (!license) findings.push('champ Critique absent : license');
  if (!path) findings.push('champ Critique absent : path');
  if (tier === 'validated' && (!proofOfUse || proofOfUse === 'null')) {
    findings.push("tier=validated mais proof_of_use absent/null — contrat invalide (garde is_clean_pass-style)");
  }

  return {
    role: { roleId, archetype, tier, license, path, proofOfUse, simulationModule, simulationConfig, difficultyTarget, simulationRuntime },
    findings,
  };
}

function median(sortedNums) {
  const n = sortedNums.length;
  if (n === 0) return null;
  const mid = Math.floor(n / 2);
  return n % 2 === 0 ? (sortedNums[mid - 1] + sortedNums[mid]) / 2 : sortedNums[mid];
}

/**
 * Lance `trials` essais (seeds seed_start..seed_start+trials-1) via `runTrial` (fourni
 * par le module de scénario déclaré par le rôle) et calcule la bande de difficulté
 * mesurée. GÉNÉRIQUE — ne connaît aucune mécanique de jeu précise.
 * @param {object} cfg simulation_config complet (trials, seed_start, + params du scénario)
 * @param {(seed:number, cfg:object) => {succeeded:boolean, ticks:(number|null)}} runTrial
 * @returns {{trials:number, succeeded:number, notSucceeded:number, successRate:number, min:(number|null), median:(number|null), max:(number|null), ticksToSucceed:number[]}}
 */
export function measureDifficultyBand(cfg, runTrial) {
  const ticksToSucceed = [];
  let notSucceeded = 0;

  for (let i = 0; i < cfg.trials; i += 1) {
    const seed = cfg.seed_start + i;
    const result = runTrial(seed, cfg);
    if (result.succeeded) ticksToSucceed.push(result.ticks);
    else notSucceeded += 1;
  }

  const sorted = [...ticksToSucceed].sort((a, b) => a - b);
  return {
    trials: cfg.trials,
    succeeded: ticksToSucceed.length,
    notSucceeded,
    successRate: ticksToSucceed.length / cfg.trials,
    min: sorted.length ? sorted[0] : null,
    median: median(sorted),
    max: sorted.length ? sorted[sorted.length - 1] : null,
    ticksToSucceed: sorted,
  };
}

// Alias de métrique : chaque rôle peut nommer sa métrique dans son propre vocabulaire de
// domaine (ticks_to_catch_median, ticks_to_reach_goal_median, ...) — tous pointent vers
// les mêmes champs génériques de measureDifficultyBand.
const METRIC_KEYS = {
  ticks_to_catch_median: 'median', ticks_to_catch_min: 'min', ticks_to_catch_max: 'max', catch_rate: 'successRate',
  ticks_to_reach_goal_median: 'median', ticks_to_reach_goal_min: 'min', ticks_to_reach_goal_max: 'max', reach_rate: 'successRate',
  ticks_median: 'median', ticks_min: 'min', ticks_max: 'max', success_rate: 'successRate',
};

async function main() {
  const rolePath = process.argv[2];
  if (!rolePath) {
    console.error('Usage: node role_sim.mjs <role.yaml>');
    process.exit(2);
  }

  console.log('=== ROLE-SIM ORACLE — bande de difficulté par simulation ===\n');

  const { role, findings } = loadRole(resolve(rolePath));
  if (findings.length > 0) {
    console.log(`✗ Contrat rôle INVALIDE : ${role.roleId || rolePath}`);
    for (const f of findings) console.log(`    - ${f}`);
    console.log('\nRESULT: INVALID_CONTRACT');
    process.exit(2);
  }

  console.log(`Rôle : ${role.roleId} (tier=${role.tier})`);
  console.log(`Scénario : ${role.simulationModule}`);
  console.log(`Config simulation : ${JSON.stringify(role.simulationConfig)}`);

  const moduleUrl = pathToFileURL(resolve(REPO_ROOT, role.simulationModule)).href;
  let scenario;
  try {
    scenario = await import(moduleUrl);
  } catch (e) {
    console.log(`\n✗ simulation_module illisible/introuvable : ${role.simulationModule}\n    ${e.message}`);
    console.log('\nRESULT: INVALID_CONTRACT');
    process.exit(2);
  }
  if (typeof scenario.runTrial !== 'function') {
    console.log(`\n✗ simulation_module n'exporte pas runTrial(seed, cfg) : ${role.simulationModule}`);
    console.log('\nRESULT: INVALID_CONTRACT');
    process.exit(2);
  }

  const measured = measureDifficultyBand(role.simulationConfig, scenario.runTrial);
  const metricKey = METRIC_KEYS[role.difficultyTarget.metric];
  const measuredValue = metricKey ? measured[metricKey] : undefined;

  console.log(`\nMesuré sur ${measured.trials} essais (seeds ${role.simulationConfig.seed_start}..${role.simulationConfig.seed_start + role.simulationConfig.trials - 1}) :`);
  console.log(`  succès : ${measured.succeeded}/${measured.trials} (success_rate=${measured.successRate.toFixed(3)})`);
  console.log(`  ticks_to_succeed : min=${measured.min} médiane=${measured.median} max=${measured.max}`);
  console.log(`\nCible déclarée (${role.difficultyTarget.metric}) : [${role.difficultyTarget.min}, ${role.difficultyTarget.max}]`);
  console.log(`Valeur mesurée pour cette métrique : ${measuredValue}`);

  const inBand =
    metricKey !== undefined &&
    measuredValue !== null &&
    measuredValue >= role.difficultyTarget.min &&
    measuredValue <= role.difficultyTarget.max;

  const receipt = {
    role_id: role.roleId,
    simulation_config: role.simulationConfig,
    difficulty_target: role.difficultyTarget,
    measured,
    in_declared_band: inBand,
  };
  console.log(`\n--- reçu mécanique (JSON) ---\n${JSON.stringify(receipt, null, 2)}`);

  if (inBand) {
    console.log('\nRESULT: PASS (bande mesurée dans la bande déclarée)');
    process.exit(0);
  } else {
    console.log('\nRESULT: FAIL (bande mesurée HORS de la bande déclarée — rapporté tel quel)');
    process.exit(1);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((e) => {
    console.error(`ERREUR INTERNE: ${e && e.stack || e}`);
    process.exit(2);
  });
}
