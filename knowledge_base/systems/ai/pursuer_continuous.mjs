// sys-pursuer-continuous — poursuite VECTORIELLE continue, PURE, déterministe.
// Comble une limite réelle de sys-pursuer-mobile découverte par un test indépendant
// (2026-07-13, games/chase_prototype/ — cf. knowledge_base/roles/RESULTS_pursuer_mobile.md
// §6) : sys-pursuer-mobile avance un axe à la fois (grille/tour-par-tour, distance de
// Chebyshev), ce qui produit une trajectoire en "L" inadaptée à un jeu temps réel à
// mouvement continu. Ce module comble ce trou : direction normalisée, les deux axes
// bougent SIMULTANÉMENT, vitesse en unités/seconde × delta-temps (dt), comme
// games/chase_prototype/game.mjs#_moveEnemy — mais écrit ici comme une pièce PURE et
// réutilisable (aucune dépendance à un moteur de jeu précis), pas répliqué depuis lui.
//
// Inspiré du concept classique "seek" des steering behaviors (Craig Reynolds, 1999,
// technique algorithmique de domaine public — aucun code source ni licence logicielle
// associée à citer, donc pas de pat-* : provenance déclarée via le marqueur ORIGINAL,
// cf. kb-validate.mjs R3 amendé).

const ORIGINAL_MARKER_NOTE =
  'ORIGINAL — aucune inspiration externe citee — mouvement de recherche (seek) inspire du concept classique "steering behaviors" (Craig Reynolds, 1999, domaine algorithmique general, aucun code source ni licence logicielle associee a citer)';
export const PROVENANCE_NOTE = ORIGINAL_MARKER_NOTE; // exposé pour traçabilité, pas consommé par le moteur

/**
 * Avance `pos` vers `targetPos` en ligne DROITE (direction normalisée, les deux axes
 * bougent simultanément — pas d'axe priorisé), à `speed` unités/seconde, sur `dt`
 * secondes écoulées. Ne dépasse JAMAIS la cible (clampé à la distance restante) — utile
 * aussi bien pour une cible mobile (rappelé chaque tick) qu'un point de passage fixe.
 * Pur : ne mute rien.
 * @param {{x:number,y:number}} pos position actuelle
 * @param {{x:number,y:number}} targetPos position visée
 * @param {number} speed unités par seconde, >= 0
 * @param {number} dt secondes écoulées ce tick, >= 0
 * @returns {{x:number,y:number}} nouvelle position
 */
export function seekToward(pos, targetPos, speed, dt) {
  if (!Number.isFinite(speed) || speed < 0) throw new RangeError('speed doit etre >= 0');
  if (!Number.isFinite(dt) || dt < 0) throw new RangeError('dt doit etre >= 0');

  const dx = targetPos.x - pos.x;
  const dy = targetPos.y - pos.y;
  const distance = Math.hypot(dx, dy);
  if (distance === 0 || speed === 0 || dt === 0) return { x: pos.x, y: pos.y };

  const step = Math.min(distance, speed * dt);
  return {
    x: pos.x + (dx / distance) * step,
    y: pos.y + (dy / distance) * step,
  };
}

/**
 * Distance euclidienne entre deux positions — utilitaire compagnon de seekToward
 * (mouvement continu = distance continue, pas Chebyshev/grille).
 * @param {{x:number,y:number}} a
 * @param {{x:number,y:number}} b
 * @returns {number}
 */
export function euclideanDistance(a, b) {
  return Math.hypot(a.x - b.x, a.y - b.y);
}
