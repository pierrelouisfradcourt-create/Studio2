// sys-pursuer-mobile — déplacement de poursuite PUR, déterministe. Aucune dépendance,
// aucun Math.random(). Écrit pour fulfill le ROLE knowledge_base/roles/pursuer-mobile.yaml
// (requires.movement = "steps toward a target position, bounded by speed, per axis").

/**
 * Déplace `pos` de `speed` pas au maximum vers `targetPos`, un axe à la fois (glouton,
 * pas de diagonale accélérée — la distance de Chebyshev parcourue par tick est bornée
 * par `speed`, jamais dépassée). Pur : ne mute ni `pos` ni `targetPos`.
 * @param {{x:number,y:number}} pos position actuelle
 * @param {{x:number,y:number}} targetPos position visée
 * @param {number} speed pas maximum par tick (entier >= 0)
 * @returns {{x:number,y:number}} nouvelle position
 */
export function stepToward(pos, targetPos, speed) {
  if (!Number.isFinite(speed) || speed < 0) throw new RangeError('speed doit etre >= 0');
  let { x, y } = pos;
  let remaining = Math.trunc(speed);

  while (remaining > 0 && (x !== targetPos.x || y !== targetPos.y)) {
    if (x !== targetPos.x) {
      x += x < targetPos.x ? 1 : -1;
    } else if (y !== targetPos.y) {
      y += y < targetPos.y ? 1 : -1;
    }
    remaining -= 1;
  }

  return { x, y };
}

/**
 * Distance de Chebyshev (déplacement 8-directions) entre deux positions.
 * @param {{x:number,y:number}} a
 * @param {{x:number,y:number}} b
 * @returns {number}
 */
export function chebyshevDistance(a, b) {
  return Math.max(Math.abs(a.x - b.x), Math.abs(a.y - b.y));
}
