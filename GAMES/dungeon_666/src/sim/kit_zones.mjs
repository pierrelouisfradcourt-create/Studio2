// ZONES DU HÉROS — objets posés ou lancés qui agissent dans la durée : pot du Brasier d'âmes
// (vol, puis sol qui brûle), Bombe de soufre (vol, mèche, explosion), Piège à mâchoires
// (armement, déclenchement), Totem de givre (impulsions). Elles ne blessent JAMAIS le héros :
// ce sont ses outils (dessinés dans les teintes froides du héros, jamais en rouge).
//
// Elles vivent dans game.room.kitFx.zones (kit_common.mjs) ; chaque zone copie ses chiffres à
// la pose (un réglage modifié ensuite ne change pas un objet déjà posé).
//
// zone : {id, kind, x, y, r, t, dead, ...} — kind : pot | brasier | bombe | piege | totem.
// Les objets lancés (pot, bombe) portent x0, y0, tx, ty, flight et leur hauteur `lift` (0..1).

import { dist2 } from '../core/math.mjs';
import { emit, newId } from './state.mjs';
import { damageEnemy } from './combat.mjs';
import { compact, destroyEnemyProjectilesInCircle } from './projectiles.mjs';
import { kitStore, hitCircle } from './kit_common.mjs';

export function spawnZone(game, z) {
  const zone = { id: newId(game), t: 0, dead: false, ...z };
  kitStore(game).zones.push(zone);
  return zone;
}

/** Zones actives d'un type (pièges posés…), dans l'ordre de pose. */
export function zonesOf(game, kind) {
  const store = game.room.kitFx;
  return store ? store.zones.filter((z) => z.kind === kind && !z.dead) : [];
}

export function updateZones(game, dt) {
  const store = game.room.kitFx;
  if (!store || store.zones.length === 0) return;
  for (const z of store.zones) {
    if (z.dead) continue;
    z.t += dt;
    ZONES[z.kind]?.(game, z, dt);
  }
  compact(store.zones);
}

/** Objet lancé en cloche : rend true à l'atterrissage (position posée sur la cible). */
function fly(z) {
  const k = Math.min(1, z.t / Math.max(1e-6, z.flight));
  z.x = z.x0 + (z.tx - z.x0) * k;
  z.y = z.y0 + (z.ty - z.y0) * k;
  z.lift = 4 * k * (1 - k); // hauteur de la cloche (rendu) : 0 au départ et à l'arrivée
  return k >= 1;
}

const ZONES = {
  // Pot du Brasier d'âmes : impact à l'atterrissage, puis il devient un sol qui brûle.
  pot(game, z) {
    if (!fly(z)) return;
    hitCircle(game, z.x, z.y, z.r, { kind: 'skill', amount: z.damage, knockback: z.knockback, hitstop: z.hitstop, canCrit: true });
    emit(game, 'explode', { x: z.x, y: z.y, r: z.r, hero: true, kind: 'brasier' });
    z.kind = 'brasier';
    z.t = 0;
    z.tickT = 0;
  },
  // Sol qui brûle : rafraîchit la brûlure (statut des ennemis) de ceux qui s'y tiennent.
  brasier(game, z, dt) {
    if (z.t >= z.duration) {
      z.dead = true;
      return;
    }
    z.tickT -= dt;
    if (z.tickT > 0) return;
    z.tickT += z.tick;
    for (const e of game.enemies) {
      if (e.dead || e.spawnT > 0) continue;
      const rr = z.r + e.r;
      if (dist2(z.x, z.y, e.x, e.y) >= rr * rr) continue;
      e.burn = Math.max(e.burn, z.burnRefresh);
      e.burnDps = Math.max(e.burnDps, z.burnDps);
    }
  },
  // Bombe : vol, mèche, explosion (étourdit, efface les projectiles ennemis du souffle).
  bombe(game, z) {
    if (z.phase === 'flight') {
      if (!fly(z)) return;
      z.phase = 'fuse';
      z.t = 0;
      return;
    }
    if (z.t < z.fuse) return;
    hitCircle(game, z.x, z.y, z.r, { kind: 'gadget', amount: z.damage, knockback: z.knockback, stun: z.stun, hitstop: z.hitstop, canCrit: false, shake: z.shake });
    destroyEnemyProjectilesInCircle(game, z.x, z.y, z.r);
    emit(game, 'explode', { x: z.x, y: z.y, r: z.r, hero: true, kind: 'bombe' });
    z.dead = true;
  },
  // Piège : s'arme, puis se referme sur le premier ennemi qui entre (immobilise : étourdi).
  piege(game, z) {
    if (z.t >= z.life) {
      z.dead = true;
      return;
    }
    if (z.t < z.armTime) return;
    z.armed = true;
    for (const e of game.enemies) {
      if (e.dead || e.spawnT > 0) continue;
      const rr = z.r + e.r;
      if (dist2(z.x, z.y, e.x, e.y) >= rr * rr) continue;
      hitCircle(game, z.x, z.y, z.blastRadius, { kind: 'gadget', amount: z.damage, knockback: z.knockback, stun: z.stun, hitstop: z.hitstop, canCrit: false, shake: z.shake });
      emit(game, 'explode', { x: z.x, y: z.y, r: z.blastRadius, hero: true, kind: 'piege' });
      z.dead = true;
      return;
    }
  },
  // Totem : impulsions qui blessent et ralentissent tout ce qui est à portée.
  totem(game, z, dt) {
    if (z.t >= z.life) {
      z.dead = true;
      return;
    }
    z.pulseT -= dt;
    if (z.pulseT > 0) return;
    z.pulseT += z.pulse;
    const minChill = game.tuning.combat.minChillMult;
    for (const e of game.enemies) {
      if (e.dead || e.spawnT > 0) continue;
      const rr = z.r + e.r;
      if (dist2(z.x, z.y, e.x, e.y) >= rr * rr) continue;
      damageEnemy(game, e, { kind: 'gadget', amount: z.damage, dirX: 0, dirY: 0, canCrit: false });
      if (e.dead) continue;
      e.chill = Math.max(e.chill, z.chill);
      e.chillMult = Math.min(e.chillMult || 1, Math.max(minChill, z.chillMult));
    }
    emit(game, 'kitPulse', { x: z.x, y: z.y, r: z.r, kind: 'totem' });
  },
};
