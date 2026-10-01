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

/** Multiplicateurs de difficulté de l'étage (croissance linéaire, définie jusqu'à 666). */
export function floorScaling(tuning, floor) {
  const f = tuning.floors;
  const k = Math.max(0, floor - 1);
  return {
    hp: 1 + f.hpGrowth * k,
    damage: 1 + f.dmgGrowth * k,
    density: 1 + f.densityGrowth * k,
  };
}
