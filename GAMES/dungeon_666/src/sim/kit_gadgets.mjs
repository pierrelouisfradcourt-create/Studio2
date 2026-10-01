// GADGETS autres que la Nova de cendres, joués selon `kind` (charges par section, comme la Nova) :
//   bombe — lancée sur l'ennemi visé (ou devant soi), explose après une courte mèche
//   piege — posé aux pieds ; se referme sur le premier ennemi qui passe (maxActive au plus)
//   totem — posé aux pieds ; impulsions qui blessent et ralentissent
//   cri   — hurlement autour du héros : étourdit et rend vulnérable, sans repousser
// player.mjs vérifie que le gadget est utilisable (ni mort, ni Super, une charge au moins).

import { dist2 } from '../core/math.mjs';
import { emit } from './state.mjs';
import { computeAim } from './aim.mjs';
import { spawnZone, zonesOf } from './kit_zones.mjs';
import { hitCircle, throwPoint } from './kit_common.mjs';

const point = { x: 0, y: 0 };

export function useKitGadget(game, g) {
  const p = game.player;
  p.gadgetCharges--;
  if (g.iframes) p.iframes = Math.max(p.iframes, g.iframes);
  switch (g.kind) {
    case 'bombe': {
      // Visée : manuelle si le joueur vise, sinon l'ennemi pertinent à portée.
      const aim = computeAim(game, p.manualAimX, p.manualAimY, g.range);
      const target = throwPoint(game, aim.x, aim.y, aim.targetId, g.range, g.throwDist, point);
      spawnZone(game, {
        kind: 'bombe', phase: 'flight', x: p.x, y: p.y, x0: p.x, y0: p.y, tx: target.x, ty: target.y, flight: g.flight, lift: 0,
        fuse: g.fuse, r: g.radius, damage: g.damage, knockback: g.knockback, stun: g.stun, hitstop: g.hitstop, shake: g.shake,
      });
      break;
    }
    case 'piege': {
      // Au-delà de maxActive pièges posés, le plus ancien se désarme.
      const traps = zonesOf(game, 'piege');
      for (let i = 0; i <= traps.length - g.maxActive; i++) traps[i].dead = true;
      spawnZone(game, {
        kind: 'piege', x: p.x, y: p.y, r: g.radius, blastRadius: g.blastRadius, armTime: g.armTime, life: g.life, armed: false,
        damage: g.damage, stun: g.stun, knockback: g.knockback, hitstop: g.hitstop, shake: g.shake,
      });
      break;
    }
    case 'cri':
      roar(game, g);
      break;
    case 'totem':
      spawnZone(game, {
        kind: 'totem', x: p.x, y: p.y, r: g.radius, life: g.life, pulse: g.pulse, pulseT: 0, damage: g.damage,
        chill: g.chill, chillMult: g.chillMult,
      });
      break;
    default:
      break;
  }
  game.telemetry.gadgetUses++;
  emit(game, 'gadget', { x: p.x, y: p.y, r: g.radius, charges: p.gadgetCharges, gadget: g.kind });
  return true;
}

/** Cri du bourreau : étourdit (l'attaque en préparation est abandonnée) et rend vulnérable. */
function roar(game, g) {
  const p = game.player;
  hitCircle(game, p.x, p.y, g.radius, { kind: 'gadget', amount: g.damage, knockback: g.knockback, stun: g.stun, hitstop: g.hitstop, canCrit: false, shake: g.shake });
  for (const e of game.enemies) {
    if (e.dead || e.spawnT > 0) continue;
    const rr = g.radius + e.r;
    if (dist2(p.x, p.y, e.x, e.y) >= rr * rr) continue;
    e.vuln = Math.max(e.vuln, g.vuln);
    e.vulnMult = Math.max(e.vulnMult, g.vulnMult);
  }
}
