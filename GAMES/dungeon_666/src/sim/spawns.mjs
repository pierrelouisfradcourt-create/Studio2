// File d'apparitions télégraphiées : un cercle d'invocation est visible `warn` secondes
// avant que l'ennemi n'apparaisse — jamais d'apparition injuste sous les pieds du héros.
// Module feuille (aucun import de sim) : utilisable par la salle comme par le boss.

import * as TRIG from '../core/trig.mjs'; // sinus, cosinus… déterministes : jamais Math.sin & co dans la simulation
import { rand } from '../core/rng.mjs';
import { dist2 } from '../core/math.mjs';
import { emit, newId } from './state.mjs';
import { pointBlocked } from './physics.mjs';

const PLACEMENT_TRIES = 40;

export function queueSpawn(game, kind, x, y, opts = {}) {
  const s = { id: newId(game), kind, x, y, t: opts.warn ?? game.tuning.room.spawnWarn, warn: opts.warn ?? game.tuning.room.spawnWarn, elite: opts.elite ?? null, summoned: !!opts.summoned };
  game.spawns.push(s);
  emit(game, 'spawnWarn', { id: s.id, x, y, enemy: kind, elite: !!s.elite });
  return s;
}

/** Cherche un point libre, loin du héros et des autres apparitions. null si introuvable. */
export function findSpawnPoint(game, r, minPlayerDist, near) {
  const room = game.room;
  const p = game.player;
  for (let i = 0; i < PLACEMENT_TRIES; i++) {
    let x;
    let y;
    if (near) {
      const a = rand(game.rng.gen) * Math.PI * 2;
      const d = near.minR + rand(game.rng.gen) * (near.maxR - near.minR);
      x = near.x + TRIG.cos(a) * d;
      y = near.y + TRIG.sin(a) * d;
    } else {
      x = room.pad + r + rand(game.rng.gen) * (room.w - 2 * (room.pad + r));
      y = room.pad + r + rand(game.rng.gen) * (room.h - 2 * (room.pad + r));
    }
    if (pointBlocked(room, x, y, r + 6)) continue;
    // La distance minimale au héros se relâche au fil des essais (salle encombrée).
    const relax = 1 - i / PLACEMENT_TRIES;
    if (dist2(x, y, p.x, p.y) < (minPlayerDist * relax) ** 2) continue;
    let crowded = false;
    for (const s of game.spawns) if (dist2(x, y, s.x, s.y) < 50 * 50) crowded = true;
    if (crowded) continue;
    return { x, y };
  }
  return null;
}
