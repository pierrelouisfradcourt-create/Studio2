// Structure des 666 étages — fonctions pures sur le numéro d'étage (1..666). Aucun étage n'est
// écrit à la main : chaque étage est COMPOSÉ à la volée à partir de briques réutilisables
// (plan de section → type d'étage et portes, run.mjs ; disposition et vagues, room.mjs ;
// archétypes et élites, enemies.mjs ; Gardien de la section, ci-dessous et bosses).
//
//   section  = 18 étages (tuning.floors.sectionLength) ; le 18e est un GARDIEN : le battre
//              ouvre un checkpoint et un point de téléportation (l'étage suivant).
//   Cercle   = 72 étages (4 sections) — 9 Cercles de l'Enfer = 648 étages,
//   finale   = 18 étages (1 section) « L'Abîme » = 666. Soit 37 sections, 37 Gardiens.

export function floorInfo(tuning, floor) {
  const f = tuning.floors;
  const n = Math.max(1, Math.min(f.total, Math.floor(floor)));
  const section = Math.ceil(n / f.sectionLength); // 1..111
  const indexInSection = n - (section - 1) * f.sectionLength; // 1..6
  const circleCount = f.circleNames.length;
  const inFinale = n > circleCount * f.circleLength;
  const circle = inFinale ? circleCount + 1 : Math.ceil(n / f.circleLength); // 1..10
  const circleName = inFinale ? f.finaleName : f.circleNames[circle - 1];
  const isBoss = indexInSection === f.sectionLength;
  const isCircleBoss = isBoss && (inFinale ? n === f.total : n % f.circleLength === 0);
  return {
    floor: n,
    section,
    sectionCount: Math.ceil(f.total / f.sectionLength),
    indexInSection,
    circle,
    circleName,
    inFinale,
    isBoss,
    isCircleBoss,
    isFinal: n === f.total,
  };
}

/** Premier étage de la section qui suit le boss de l'étage `bossFloor` : le point de reprise. */
export function checkpointAfterBoss(tuning, bossFloor) {
  return Math.min(tuning.floors.total, bossFloor + 1);
}

/**
 * Multiplicateurs de difficulté de l'étage, définis jusqu'à 666 (spec §5.5) :
 *   L = 1 + 0,05·(f−1)            niveau d'objet (les armes trouvées suivent la même pente)
 *   B = 1 + 2·(1 − e^(−(f−1)/100)) saturation du build
 *   C = 1 + 0,5·(f−1)/665          dérive de difficulté
 *   D = 1 + 0,6·(1 − e^(−(f−1)/150))
 *   PV = L·B·C · dégâts = L·D · densité = D. Les télégraphes, eux, ne changent jamais.
 */
export function floorScaling(tuning, floor) {
  const f = tuning.floors;
  const k = Math.max(0, floor - 1);
  const L = 1 + f.itemGrowth * k;
  const B = 1 + f.buildCap * (1 - Math.exp(-k / f.buildScale));
  const C = 1 + (f.driftAt666 * k) / (f.total - 1);
  const D = 1 + f.dmgCurve * (1 - Math.exp(-k / f.dmgScale));
  return { hp: L * B * C, damage: L * D, density: D };
}

/**
 * Modèle de Gardien qui garde la section `section` (1..37) : rotation des modèles connus
 * (tuning.guardians.rotation). Un même modèle revient plus loin, plus coriace (floorScaling).
 */
export function guardianFor(tuning, section) {
  const rot = tuning.guardians.rotation.filter((k) => tuning.boss[k]);
  if (rot.length === 0) return Object.keys(tuning.boss)[0];
  return rot[(Math.max(1, section) - 1) % rot.length];
}

/** Étage du Gardien de la section, et checkpoint qu'il ouvre. */
export function sectionBounds(tuning, section) {
  const len = tuning.floors.sectionLength;
  const last = Math.min(tuning.floors.total, section * len);
  return { first: (section - 1) * len + 1, guardian: last, checkpoint: checkpointAfterBoss(tuning, last) };
}
