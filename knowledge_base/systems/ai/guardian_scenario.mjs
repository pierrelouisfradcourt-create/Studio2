// guardian_scenario.mjs — scénario de simulation pour role-guardian-static (2e ROLE,
// 2026-07-13 — test de généralisation du mécanisme Role-Sim au-delà de la poursuite).
//
// Un attaquant marche EN LIGNE DROITE (glouton, ne contourne jamais, ne "voit" pas le
// gardien pour planifier — même discipline que le bot solvability.mjs : le bot le plus
// simple possible, pas un bot optimal) depuis un point de départ vers un point d'arrivée
// symétrique, à distance de croisement FIXE, en traversant potentiellement la zone de
// contrôle d'un gardien STATIQUE fixé au centre de l'arène.
//
// Choix de conception (déclaré, pas accidentel — cf. RESULTS_pursuer_mobile.md §5bis
// pour l'historique de ce choix) : la distance de croisement (`crossing_half_distance`)
// est FIXE, seule la hauteur d'approche (y) varie entre essais. Une 1re version faisait
// varier la distance ET la hauteur ensemble — la variance de distance de base (10 à 40
// ticks) noyait complètement l'effet de la zone (au plus 1 tick de délai par franchissement)
// dans le bruit : bande mesurée IDENTIQUE avec la zone activée ou désactivée (vérifié,
// pas supposé). En fixant la distance, seule la hauteur varie, et l'effet de la zone
// devient directement lisible dans la bande mesurée (min=baseline, max=baseline+1).
//
// Contrat exigé par role_sim.mjs : export runTrial(seed, cfg) -> {succeeded, ticks}.
import { chebyshevDistance, stepToward } from './pursuer.mjs';
import { stepTowardWithZoC } from './zone_of_control.mjs';

function mulberry32(seed) {
  let a = seed >>> 0;
  return function next() {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * Simule UNE traversée à distance fixe (un seed = une hauteur d'approche y), jusqu'à
 * arrivée ou max_ticks. Gardien FIXE au centre (0,0) — pas aléatoire, c'est le rôle testé.
 * @param {number} seed
 * @param {object} cfg simulation_config du rôle (arena_half_size, zoc_radius,
 *   attacker_speed, crossing_half_distance, max_ticks)
 * @returns {{succeeded:boolean, ticks:(number|null)}}
 */
export function runTrial(seed, cfg) {
  const rng = mulberry32(seed);
  const guardian = { x: 0, y: 0 };
  const half = cfg.crossing_half_distance;

  const y = Math.round((rng() * 2 - 1) * cfg.arena_half_size);
  let pos = { x: -half, y };
  const target = { x: half, y };

  for (let tick = 1; tick <= cfg.max_ticks; tick += 1) {
    pos = stepTowardWithZoC(pos, target, cfg.attacker_speed, guardian, cfg.zoc_radius);
    if (chebyshevDistance(pos, target) === 0) {
      return { succeeded: true, ticks: tick };
    }
  }
  return { succeeded: false, ticks: null };
}

/**
 * Même scénario, mais SANS zone de contrôle (mouvement glouton simple) — utilisé
 * UNIQUEMENT pour la vérification croisée (pas par role_sim.mjs). Sert de preuve que
 * l'effet mesuré par `runTrial` vient bien de la zone, pas d'un artefact du chemin.
 * @param {number} seed
 * @param {object} cfg
 * @returns {{succeeded:boolean, ticks:(number|null)}}
 */
export function runTrialWithoutZone(seed, cfg) {
  const rng = mulberry32(seed);
  const half = cfg.crossing_half_distance;
  const y = Math.round((rng() * 2 - 1) * cfg.arena_half_size);
  let pos = { x: -half, y };
  const target = { x: half, y };

  for (let tick = 1; tick <= cfg.max_ticks; tick += 1) {
    pos = stepToward(pos, target, cfg.attacker_speed);
    if (chebyshevDistance(pos, target) === 0) {
      return { succeeded: true, ticks: tick };
    }
  }
  return { succeeded: false, ticks: null };
}
