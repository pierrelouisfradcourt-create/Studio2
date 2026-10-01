// DONNÉES des archétypes d'ennemis AJOUTÉS (tuning), fusionnées dans tuning.enemies par
// config.mjs, et leur place dans les vagues (ROSTER de room.mjs).
//
// EXTRA_ENEMIES : { kind: { name, radius, hp, speed, mass, damage, …, gold: [lo, hi] } }
// EXTRA_ROSTER  : [{ kind, cost, minIndex, weight }] — coût en budget de vague, index minimal
//                 dans la 1re section (les sections suivantes ont tout le bestiaire), poids.
// EXTRA_ELITE_KINDS : archétypes pouvant recevoir un modificateur d'élite.

export const EXTRA_ENEMIES = {};
export const EXTRA_ROSTER = [];
export const EXTRA_ELITE_KINDS = [];
