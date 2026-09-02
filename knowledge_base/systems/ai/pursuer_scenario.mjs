// pursuer_scenario.mjs — scénario de simulation pour role-pursuer-mobile, EXTRAIT de
// role_sim.mjs lors de sa généralisation (2026-07-13, 2e rôle : test de généralisation
// du mécanisme Role-Sim). Logique de trial INCHANGÉE — même comportement qu'avant le
// refactor (vérifié : mêmes médianes mesurées sur les mêmes seeds après extraction).
//
// Contrat exigé par role_sim.mjs : export runTrial(seed, cfg) -> {succeeded, ticks}.
import { stepToward, chebyshevDistance } from './pursuer.mjs';
import { stepAway } from './evader.mjs';

// PRNG déterministe (mulberry32 — même famille que les autres oracles du studio).
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
 * Simule UNE poursuite (un seed = une configuration de départ), jusqu'à capture ou
 * max_ticks. Pur : RNG créé et consommé localement, seedé.
 * @param {number} seed
 * @param {object} cfg simulation_config du rôle (arena_half_size, catch_radius,
 *   pursuer_speed, evader_speed, max_ticks)
 * @returns {{succeeded:boolean, ticks:(number|null)}}
 */
export function runTrial(seed, cfg) {
  const rng = mulberry32(seed);
  const half = cfg.arena_half_size;
  const randCoord = () => Math.round((rng() * 2 - 1) * half);

  let pursuer = { x: randCoord(), y: randCoord() };
  let evader = { x: randCoord(), y: randCoord() };
  // Évite un départ déjà capturé (dégénéré) — retirage déterministe borné.
  let guard = 0;
  while (chebyshevDistance(pursuer, evader) <= cfg.catch_radius && guard < 50) {
    evader = { x: randCoord(), y: randCoord() };
    guard += 1;
  }

  for (let tick = 1; tick <= cfg.max_ticks; tick += 1) {
    evader = stepAway(evader, pursuer, cfg.evader_speed);
    pursuer = stepToward(pursuer, evader, cfg.pursuer_speed);
    if (chebyshevDistance(pursuer, evader) <= cfg.catch_radius) {
      return { succeeded: true, ticks: tick };
    }
  }
  return { succeeded: false, ticks: null };
}
