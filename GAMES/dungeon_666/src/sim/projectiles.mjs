// Projectiles (héros et ennemis) et zones de danger télégraphiées.

import { dist2, pointSegDist2, pointBandDist2 } from '../core/math.mjs';
import { emit, newId } from './state.mjs';
import { damageEnemy, damagePlayer } from './combat.mjs';
import { pointBlocked } from './physics.mjs';
import { foeDealt } from './foe_elites.mjs';

/** Source vivante d'une attaque (id d'ennemi), ou null. */
function sourceOf(game, id) {
  if (!id) return null;
  for (const e of game.enemies) if (e.id === id && !e.dead) return e;
  return null;
}

/** Blesse le héros au nom d'un ennemi (élite vampirique : se soigne de ce qui a porté). */
function hurtPlayerFor(game, sourceId, amount, src) {
  const p = game.player;
  const hp0 = p.hp;
  const landed = damagePlayer(game, amount, src);
  if (landed && sourceId) foeDealt(game, sourceOf(game, sourceId), hp0 - p.hp);
  return landed;
}

/**
 * p : {owner: 'player'|'enemy', kind, x, y, vx, vy, r, damage, range, pierce, knockback,
 *      hitstop, sourceId}
 */
export function spawnProjectile(game, p) {
  const pr = { id: newId(game), hitIds: [], traveled: 0, pierce: 0, knockback: 0, hitstop: 0, sourceId: 0, ...p };
  game.projectiles.push(pr);
  return pr;
}

/** Détruit les projectiles ennemis dans un cercle (nova, Super) ; rend leur nombre. */
export function destroyEnemyProjectilesInCircle(game, x, y, r) {
  let n = 0;
  for (const pr of game.projectiles) {
    if (pr.owner !== 'enemy' || pr.dead) continue;
    const rr = r + pr.r;
    if (dist2(x, y, pr.x, pr.y) < rr * rr) {
      pr.dead = true;
      n++;
      emit(game, 'deflect', { x: pr.x, y: pr.y });
    }
  }
  return n;
}

export function updateProjectiles(game, dt) {
  const room = game.room;
  const p = game.player;
  for (const pr of game.projectiles) {
    if (pr.dead) continue;
    const ox = pr.x;
    const oy = pr.y;
    pr.x += pr.vx * dt;
    pr.y += pr.vy * dt;
    pr.traveled += Math.sqrt(pr.vx * pr.vx + pr.vy * pr.vy) * dt;
    if (pr.traveled > pr.range || pointBlocked(room, pr.x, pr.y, 0)) {
      pr.dead = true;
      emit(game, 'projectileEnd', { x: pr.x, y: pr.y, owner: pr.owner, kind: pr.kind });
      continue;
    }
    if (pr.owner === 'enemy') {
      if (p.state === 'dead') continue;
      const rr = pr.r + p.r;
      // Test sur le segment parcouru : pas de traversée à grande vitesse.
      if (pointSegDist2(p.x, p.y, ox, oy, pr.x, pr.y) < rr * rr) {
        const landed = hurtPlayerFor(game, pr.sourceId, pr.damage, { kind: pr.kind, id: pr.id, x: pr.x, y: pr.y });
        if (landed) pr.dead = true;
      }
    } else {
      for (const e of game.enemies) {
        if (e.dead || e.spawnT > 0 || pr.hitIds.includes(e.id)) continue;
        const rr = pr.r + e.r;
        if (pointSegDist2(e.x, e.y, ox, oy, pr.x, pr.y) < rr * rr) {
          pr.hitIds.push(e.id);
          const l = Math.max(1e-6, Math.sqrt(pr.vx * pr.vx + pr.vy * pr.vy));
          damageEnemy(game, e, {
            kind: 'skill', amount: pr.damage, dirX: pr.vx / l, dirY: pr.vy / l,
            knockback: pr.knockback, hitstop: pr.hitstop, canCrit: true,
          });
          if (pr.hitIds.length > pr.pierce) {
            pr.dead = true;
            break;
          }
        }
      }
    }
  }
  compact(game.projectiles);
}

function inHazard(h, x, y, r) {
  if (h.shape === 'circle') {
    const rr = h.r + r;
    return dist2(x, y, h.x, h.y) < rr * rr;
  }
  if (h.shape === 'ring') {
    const d = Math.sqrt(dist2(x, y, h.x, h.y));
    return d < h.r + r && d > h.inner - r;
  }
  // 'line' : RECTANGLE partant de (x, y) dans la direction `angle`, long de `length`, large de
  // `width` — exactement ce que dessine le rendu (render.mjs drawLine). Un corps de rayon r est
  // touché s'il mord sur ce rectangle, pas au-delà : le bord dessiné est le bord qui touche
  // (une brèche dessinée est une vraie brèche, le dos d'une frappe en ligne est sûr).
  const d2 = pointBandDist2(x, y, h.x, h.y, h.angle, h.length, h.width);
  return d2 === 0 || d2 < r * r;
}

/**
 * Zone PERSISTANTE (h.linger > 0, ex. flamme de la Pyromancienne) : une fois allumée — donc
 * TOUJOURS après son télégraphe —, elle brûle `linger` s et blesse le héros de `tickDamage`
 * toutes les `tickEvery` s, SEULEMENT s'il est à l'intérieur. Sa source peut mourir : la flaque
 * reste (elle est au sol). Elle s'éteint quand la salle est nettoyée. Les i-frames (dash, coup
 * reçu) protègent sans compter d'esquive : traverser une flaque n'est pas une esquive parfaite.
 */
function burnHazard(game, h, dt) {
  const p = game.player;
  h.burnT += dt;
  if (h.burnT >= h.linger || game.room.cleared) {
    h.done = true;
    return;
  }
  h.tickT += dt;
  if (h.tickT < h.tickEvery) return;
  h.tickT -= h.tickEvery;
  if (!h.hitsPlayer || p.state === 'dead' || p.iframes > 0 || !inHazard(h, p.x, p.y, p.r)) return;
  hurtPlayerFor(game, h.sourceId, h.tickDamage, { kind: h.kind, id: h.id, x: h.x, y: h.y });
}

export function updateHazards(game, dt) {
  const p = game.player;
  for (const h of game.hazards) {
    if (h.done) continue;
    if (h.burning) {
      burnHazard(game, h, dt);
      continue;
    }
    // Source morte ou étourdie pendant le télégraphe : l'attaque est annulée (punition récompensée).
    if (h.sourceId) {
      const src = game.enemies.find((e) => e.id === h.sourceId);
      if (!src || src.dead || src.stun > 0) {
        h.done = true;
        emit(game, 'hazardCancel', { id: h.id, x: h.x, y: h.y });
        continue;
      }
    }
    h.t += dt;
    if (h.t < h.delay) continue;
    if (h.linger > 0) {
      // Allumage d'une zone persistante : elle frappe comme les autres, puis reste au sol.
      h.burning = true;
      h.burnT = 0;
      h.tickT = 0;
    } else {
      h.done = true;
    }
    emit(game, 'hazardFire', { id: h.id, kind: h.kind, shape: h.shape, x: h.x, y: h.y, r: h.r, angle: h.angle, length: h.length, width: h.width });
    if (h.hitsPlayer && p.state !== 'dead' && inHazard(h, p.x, p.y, p.r)) {
      hurtPlayerFor(game, h.sourceId, h.damage, { kind: h.kind, id: h.id, x: h.x, y: h.y });
    }
    if (h.hitsEnemies) {
      for (const e of game.enemies) {
        if (e.dead || e.spawnT > 0 || e.id === h.ownerId) continue;
        if (inHazard(h, e.x, e.y, e.r)) {
          const dx = e.x - h.x;
          const dy = e.y - h.y;
          const l = Math.max(1e-6, Math.sqrt(dx * dx + dy * dy));
          // Une explosion d'ENNEMI (Possédé) ne profite ni de l'arme ni des bonus du héros.
          damageEnemy(game, e, { kind: h.ownerId ? 'enemyBlast' : 'blast', amount: h.damage, dirX: dx / l, dirY: dy / l, knockback: 260, canCrit: false });
        }
      }
    }
  }
  compactDone(game.hazards);
}

/** Retire en place les éléments `dead` (pas d'allocation). */
export function compact(arr) {
  let w = 0;
  for (let i = 0; i < arr.length; i++) if (!arr[i].dead) arr[w++] = arr[i];
  arr.length = w;
}

function compactDone(arr) {
  let w = 0;
  for (let i = 0; i < arr.length; i++) if (!arr[i].done) arr[w++] = arr[i];
  arr.length = w;
}

/** Progression 0..1 du télégraphe d'une zone (pour le rendu). */
export function hazardProgress(h) {
  return h.delay > 0 ? Math.min(1, h.t / h.delay) : 1;
}

/**
 * Part 0..1 de vie restante d'une zone persistante allumée (1 = vient de s'allumer, 0 =
 * éteinte). Le rendu la DESSINE (la flaque se résorbe) : c'est ce que lit l'œil du joueur.
 */
export function lingerLeft(h) {
  return h.burning && h.linger > 0 ? Math.max(0, 1 - h.burnT / h.linger) : 0;
}
