// TIRS DU HÉROS (hors Lance) — traits d'arc, carreaux, épines, crochet de la Chaîne, traits
// de la Nuée. Ils vivent dans game.room.kitFx.shots (kit_common.mjs) et portent la SOURCE de
// leurs dégâts : 'melee' / 'strike' pour l'arme (les bénédictions d'attaque s'y appliquent),
// 'skill' pour une compétence, 'super' pour un Super. La Lance, elle, reste un projectile de
// game.projectiles (projectiles.mjs), à l'identique.
//
// shot : {id, kind, x, y, vx, vy, r, range, traveled, pierce, hitIds, damage, source,
//         knockback, hitstop, shake, stun, pull?: {stopGap, mass}, heavy, dead}

import { DEG } from './config.mjs';
import { pointSegDist2 } from '../core/math.mjs';
import { emit, newId } from './state.mjs';
import { damageEnemy } from './combat.mjs';
import { pointBlocked } from './physics.mjs';
import { compact } from './projectiles.mjs';
import { kitStore, pullToward } from './kit_common.mjs';

const MUZZLE = 0.5; // × rayon du héros : point de départ d'un tir (à bout portant, ça touche)

/** Ajoute un tir du héros dans la salle. */
export function spawnShot(game, s) {
  const shot = {
    id: newId(game), kind: 'arrow', traveled: 0, pierce: 0, hitIds: [], knockback: 0, hitstop: 0, shake: 0,
    stun: 0, pull: null, heavy: false, dead: false, ...s,
  };
  kitStore(game).shots.push(shot);
  return shot;
}

/**
 * Tirs d'un coup d'arme à distance (champ `shot` du coup) : `count` projectiles en éventail
 * sur `arc` degrés autour de l'angle du coup. Source 'strike' pour la frappe de dash.
 */
export function fireWeaponShots(game, a) {
  const p = game.player;
  const def = a.def;
  const sh = def.shot;
  const count = Math.max(1, sh.count ?? 1);
  const spread = (def.arc ?? 0) * DEG;
  for (let i = 0; i < count; i++) {
    const ang = a.angle + (count > 1 ? (i / (count - 1) - 0.5) * spread : 0);
    const cx = Math.cos(ang);
    const cy = Math.sin(ang);
    spawnShot(game, {
      kind: sh.kind ?? 'arrow',
      x: p.x + cx * p.r * MUZZLE,
      y: p.y + cy * p.r * MUZZLE,
      vx: cx * sh.speed,
      vy: cy * sh.speed,
      r: sh.radius,
      range: def.range,
      pierce: sh.pierce ?? 0,
      damage: def.damage,
      source: a.strike ? 'strike' : 'melee',
      knockback: def.knockback,
      hitstop: def.hitstop,
      shake: def.shake,
      stun: def.stun ?? 0,
      heavy: !!sh.heavy || a.strike,
    });
  }
}

/** Tirs en éventail (compétence Volée, etc.) depuis le héros. */
export function fireFan(game, angle, count, spreadDeg, spec) {
  const p = game.player;
  const spread = spreadDeg * DEG;
  for (let i = 0; i < count; i++) {
    const ang = angle + (count > 1 ? (i / (count - 1) - 0.5) * spread : 0);
    const cx = Math.cos(ang);
    const cy = Math.sin(ang);
    spawnShot(game, {
      ...spec,
      x: p.x + cx * p.r * MUZZLE,
      y: p.y + cy * p.r * MUZZLE,
      vx: cx * spec.speed,
      vy: cy * spec.speed,
    });
  }
}

export function updateShots(game, dt) {
  const store = game.room.kitFx;
  if (!store || store.shots.length === 0) return;
  const room = game.room;
  for (const s of store.shots) {
    if (s.dead) continue;
    const ox = s.x;
    const oy = s.y;
    const speed = Math.max(1e-6, Math.sqrt(s.vx * s.vx + s.vy * s.vy));
    s.x += s.vx * dt;
    s.y += s.vy * dt;
    s.traveled += speed * dt;
    if (s.traveled > s.range || pointBlocked(room, s.x, s.y, 0)) {
      s.dead = true;
      continue;
    }
    for (const e of game.enemies) {
      if (e.dead || e.spawnT > 0 || s.hitIds.includes(e.id)) continue;
      const rr = s.r + e.r;
      // Test sur le segment parcouru : pas de traversée à grande vitesse.
      if (pointSegDist2(e.x, e.y, ox, oy, s.x, s.y) >= rr * rr) continue;
      s.hitIds.push(e.id);
      damageEnemy(game, e, {
        kind: s.source, amount: s.damage, dirX: s.vx / speed, dirY: s.vy / speed,
        knockback: s.knockback, hitstop: s.hitstop, canCrit: true, shake: s.shake, stun: s.stun,
      });
      if (s.pull) hook(game, s, e);
      if (s.hitIds.length > s.pierce) {
        s.dead = true;
        break;
      }
    }
  }
  compact(store.shots);
}

/** Crochet de la Chaîne d'Enfer : l'ennemi harponné est tiré contre le héros. */
function hook(game, s, e) {
  const p = game.player;
  emit(game, 'hook', { x0: p.x, y0: p.y, x1: e.x, y1: e.y, boss: !!e.boss });
  if (e.dead) return;
  pullToward(game, e, p.x, p.y, p.r + e.r + s.pull.stopGap, s.pull.mass);
}
