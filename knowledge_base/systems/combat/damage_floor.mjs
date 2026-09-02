// sys-damage-floor — dégâts à plancher, fonction PURE, déterministe.
// Réécriture propre inspirée du pattern cité pat-damage-floor (Wesnoth, GPL — concept only).
// Aucun code Wesnoth repris. Licence : MIT (interne).
// Invariant central : un coup inflige toujours au moins `floor` (défaut 1).

/**
 * @param {number} rawDamage  dégât brut (>= 0)
 * @param {number} reduction  réduction/défense (>= 0)
 * @param {number} [floor=1]  plancher minimal (>= 1)
 * @returns {number} dégât effectif, entier >= floor
 */
export function effectiveDamage(rawDamage, reduction, floor = 1) {
  if (!Number.isFinite(rawDamage) || rawDamage < 0) throw new RangeError("rawDamage doit etre >= 0");
  if (!Number.isFinite(reduction) || reduction < 0) throw new RangeError("reduction doit etre >= 0");
  if (!Number.isFinite(floor) || floor < 1) throw new RangeError("floor doit etre >= 1");
  return Math.max(floor, Math.trunc(rawDamage - reduction));
}

/**
 * Applique un coup à un point de vie et renvoie le nouveau hp (borné à 0).
 * @param {number} hp
 * @param {number} rawDamage
 * @param {number} reduction
 * @param {number} [floor=1]
 * @returns {{hp:number, dealt:number}}
 */
export function applyHit(hp, rawDamage, reduction, floor = 1) {
  const dealt = effectiveDamage(rawDamage, reduction, floor);
  return { hp: Math.max(0, hp - dealt), dealt };
}
