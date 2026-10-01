// ENNEMI DE ZONE — « Pyromancienne » (kind 'pyromancer'). Données : tuning.enemies.pyromancer
// (foe_data.mjs).
//
// Machine d'états :
//   chase   — garde ses distances (fuit, se rapproche, tourne autour : keepDistance) ;
//             incante quand elle voit le héros, à portée, et qu'un jeton de TIR est libre.
//   windup  — bâton levé (castTime, lisible sur elle), puis pose `pyre.count` cercles de feu
//             TÉLÉGRAPHIÉS (rouge = ça fait mal) : un sur le héros, les autres répartis autour.
//             Elle tient le sort jusqu'à l'allumage du dernier cercle (le jeton de tir reste
//             pris) : la tuer ou l'étourdir avant ANNULE les cercles (sourceId, projectiles.mjs).
//   recover — souffle, puis repart en chase (temps de recharge).
// Chaque cercle allumé laisse une FLAQUE brûlante persistante et visible (`linger` s) qui ne
// blesse qu'à l'intérieur, par ticks (projectiles.mjs, updateHazards). Aucun dégât de contact.

import * as TRIG from '../core/trig.mjs'; // sinus, cosinus… déterministes : jamais Math.sin & co dans la simulation
import { rand, randRange } from '../core/rng.mjs';
import { clamp } from '../core/math.mjs';
import { lineOfSight } from './physics.mjs';
import { spawnHazard } from './combat.mjs';
import { emit, setState, toPlayer, speedOf, windupOf, activeShooters, keepDistance } from './ai_common.mjs';

const TAU = Math.PI * 2;

/** Fin du sort : le dernier cercle s'allume `pyreSpan` s après son apparition. */
export function pyreSpan(def) {
  return def.pyre.delay + (def.pyre.count - 1) * def.pyre.stagger;
}

/**
 * Pose UN cercle de feu télégraphié (`delay` s) qui laisse une flaque brûlante. Le centre reste
 * dans la salle, à au moins un demi-rayon des murs (la flaque se voit sur le sol, pas dans le
 * mur). `source` : l'ennemi qui l'a lancé (sa mort ou son étourdissement l'annulent pendant le
 * télégraphe), ou null.
 */
export function spawnPyre(game, x, y, def, source, delay) {
  const room = game.room;
  const pyre = def.pyre;
  const scale = source ? source.dmgScale : 1;
  const lo = room.pad + pyre.radius * pyre.wallInset;
  return spawnHazard(game, {
    shape: 'circle',
    x: clamp(x, lo, room.w - lo),
    y: clamp(y, lo, room.h - lo),
    r: pyre.radius,
    delay,
    damage: def.damage * scale,
    kind: 'pyre',
    sourceId: source ? source.id : 0,
    linger: pyre.linger,
    tickEvery: pyre.tickEvery,
    tickDamage: pyre.tickDamage * scale,
  });
}

/** Un cercle sur le héros, les satellites répartis régulièrement autour (angle de départ tiré). */
function castPyres(game, e, def) {
  const p = game.player;
  const pyre = def.pyre;
  spawnPyre(game, p.x, p.y, def, e, pyre.delay);
  const sats = pyre.count - 1;
  const a0 = rand(game.rng.ai) * TAU;
  for (let i = 0; i < sats; i++) {
    const a = a0 + (i / sats) * TAU;
    spawnPyre(game, p.x + TRIG.cos(a) * pyre.spread, p.y + TRIG.sin(a) * pyre.spread, def, e, pyre.delay + (i + 1) * pyre.stagger);
  }
}

function pyromancerAI(game, e, def) {
  const p = game.player;
  const tp = toPlayer(game, e);
  switch (e.state) {
    case 'chase': {
      const sees = lineOfSight(game.room, e.x, e.y, p.x, p.y);
      if (e.cooldown <= 0 && sees && tp.d < def.castRange && activeShooters(game) < game.tuning.combat.maxShooters) {
        setState(e, 'windup');
        e.castDone = false;
        break;
      }
      keepDistance(game, e, def, tp, sees, speedOf(game, e, def));
      break;
    }
    case 'windup': {
      const cast = windupOf(game, e, def.castTime);
      if (!e.castDone && e.stateTime >= cast) {
        e.castDone = true;
        castPyres(game, e, def);
        emit(game, 'enemyAttack', { id: e.id, x: e.x, y: e.y, enemy: e.kind });
      }
      if (e.castDone && e.stateTime >= cast + pyreSpan(def)) setState(e, 'recover');
      break;
    }
    case 'recover':
      if (e.stateTime >= def.recover) {
        setState(e, 'chase');
        // Le temps de recharge varie (def.cooldownJitter) : pas de métronome.
        e.cooldown = def.cooldown * randRange(game.rng.ai, def.cooldownJitter[0], def.cooldownJitter[1]);
      }
      break;
    default:
      setState(e, 'chase');
  }
}

export const PYROMANCER = { kind: 'pyromancer', ai: pyromancerAI, shooter: true };
