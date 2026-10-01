// Projectiles (héros et ennemis) et zones de danger télégraphiées.

import { dist2, pointSegDist2 } from '../core/math.mjs';
import { emit, newId } from './state.mjs';
import { damageEnemy, damagePlayer } from './combat.mjs';
import { pointBlocked } from './physics.mjs';

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
        const landed = damagePlayer(game, pr.damage, { kind: pr.kind, id: pr.id, x: pr.x, y: pr.y });
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
  // 'line' : segment partant de (x, y) dans la direction `angle`, sur `length`, épaisseur `width`.
  const ex = h.x + Math.cos(h.angle) * h.length;
  const ey = h.y + Math.sin(h.angle) * h.length;
  const hw = h.width / 2 + r;
  return pointSegDist2(x, y, h.x, h.y, ex, ey) < hw * hw;
}

export function updateHazards(game, dt) {
  const p = game.player;
  for (const h of game.hazards) {
    if (h.done) continue;
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
    h.done = true;
    emit(game, 'hazardFire', { id: h.id, kind: h.kind, shape: h.shape, x: h.x, y: h.y, r: h.r, angle: h.angle, length: h.length, width: h.width });
    if (h.hitsPlayer && p.state !== 'dead' && inHazard(h, p.x, p.y, p.r)) {
      damagePlayer(game, h.damage, { kind: h.kind, id: h.id, x: h.x, y: h.y });
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
