// Structure des 666 étages — fonctions pures sur le numéro d'étage (1..666).
//
//   section  = 6 étages ; le 6e est un BOSS, et le battre ouvre un checkpoint (téléportation).
//   Cercle   = 72 étages (12 sections) — 9 Cercles de l'Enfer = 648 étages,
//   finale   = 18 étages (3 sections) « Le Trône » = 666.

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
