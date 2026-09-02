// sys-evader-basic — fuite PURE, déterministe. Opposant minimal utilisé par
// knowledge_base/role_sim.mjs pour mesurer la bande de difficulté du ROLE
// pursuer-mobile — PAS lui-même un ROLE (pas de contrat), juste l'adversaire de test.

/**
 * Déplace `pos` de `speed` pas au maximum, DIRECTEMENT à l'opposé de `threatPos`
 * (fuite en ligne droite, un axe à la fois — même mécanique de pas que stepToward,
 * signe inversé). Pur : ne mute rien.
 * @param {{x:number,y:number}} pos
 * @param {{x:number,y:number}} threatPos position dont on s'éloigne
 * @param {number} speed pas maximum par tick (entier >= 0)
 * @returns {{x:number,y:number}} nouvelle position
 */
export function stepAway(pos, threatPos, speed) {
  if (!Number.isFinite(speed) || speed < 0) throw new RangeError('speed doit etre >= 0');
  let { x, y } = pos;
  let remaining = Math.trunc(speed);

  while (remaining > 0) {
    const dx = x - threatPos.x;
    const dy = y - threatPos.y;
    if (dx === 0 && dy === 0) {
      // Menace exactement sur la même case (dégénéré) : fuite arbitraire mais
      // déterministe (+x), pour ne jamais rester bloqué.
      x += 1;
    } else {
      if (Math.abs(dx) >= Math.abs(dy)) {
        x += dx >= 0 ? 1 : -1;
      } else {
        y += dy >= 0 ? 1 : -1;
      }
    }
    remaining -= 1;
  }

  return { x, y };
}
