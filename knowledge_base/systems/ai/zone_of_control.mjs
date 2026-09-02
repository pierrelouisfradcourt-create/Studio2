// sys-guardian-zoc — zone de contrôle statique, PURE, déterministe. Réécriture propre
// inspirée du pattern cité pat-zone-of-control (Wesnoth, GPL — concept only, zéro code
// repris). Écrit pour fulfill le ROLE knowledge_base/roles/guardian-static.yaml.
//
// Contrat (repris du pattern cité) : « une unite projette une zone de controle ; l'ennemi
// qui y entre stoppe son deplacement » — implémenté ici comme : le mouvement d'un tick
// s'arrête à la première case NOUVELLEMENT entrée dans la zone (si on y était déjà au
// début du tick, pas de troncature ce tick-ci — la ZoC surprend, elle n'emprisonne pas :
// "deplacement penetrant une case controlee est tronque a cette case", pat-zone-of-control).
import { chebyshevDistance } from './pursuer.mjs';

/**
 * Une position est-elle dans la zone de contrôle d'un gardien ?
 * @param {{x:number,y:number}} pos
 * @param {{x:number,y:number}} guardianPos
 * @param {number} zocRadius rayon de la zone (distance de Chebyshev), >= 0
 * @returns {boolean}
 */
export function isInZone(pos, guardianPos, zocRadius) {
  return chebyshevDistance(pos, guardianPos) <= zocRadius;
}

/**
 * Déplace `pos` de `speed` pas au maximum vers `targetPos` (même mécanique gloutonne que
 * pursuer.mjs#stepToward, un axe à la fois), mais le mouvement s'ARRÊTE dès qu'il entre
 * FRAÎCHEMENT dans la zone de contrôle du gardien (si `pos` de départ n'y était pas déjà).
 * Pur : ne mute rien.
 * @param {{x:number,y:number}} pos position actuelle
 * @param {{x:number,y:number}} targetPos position visée
 * @param {number} speed pas maximum par tick (entier >= 0)
 * @param {{x:number,y:number}} guardianPos position du gardien (statique)
 * @param {number} zocRadius rayon de la zone de contrôle
 * @returns {{x:number,y:number}} nouvelle position
 */
export function stepTowardWithZoC(pos, targetPos, speed, guardianPos, zocRadius) {
  if (!Number.isFinite(speed) || speed < 0) throw new RangeError('speed doit etre >= 0');
  const startedInZone = isInZone(pos, guardianPos, zocRadius);

  let x = pos.x;
  let y = pos.y;
  let remaining = Math.trunc(speed);

  while (remaining > 0 && (x !== targetPos.x || y !== targetPos.y)) {
    if (x !== targetPos.x) {
      x += x < targetPos.x ? 1 : -1;
    } else if (y !== targetPos.y) {
      y += y < targetPos.y ? 1 : -1;
    }
    remaining -= 1;

    if (!startedInZone && isInZone({ x, y }, guardianPos, zocRadius)) {
      break; // entrée fraîche dans la zone : le reste du budget de vitesse est perdu ce tick
    }
  }

  return { x, y };
}
