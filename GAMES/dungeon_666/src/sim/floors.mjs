// Structure des 666 étages — fonctions pures sur le numéro d'étage (1..666). Aucun étage n'est
// écrit à la main : chaque étage est COMPOSÉ à la volée à partir de briques réutilisables
// (plan de section, sections.mjs : type d'étage, portes, vagues, budget, dispositions, thème du
// Cercle ; salle, room.mjs : dispositions et vagues ; archétypes et élites, enemies.mjs ;
// Gardien de la section, ci-dessous et bosses ; salles calmes, calm_rooms.mjs).
//
//   section  = 18 étages (tuning.floors.sectionLength) ; le 18e est un GARDIEN : le battre
//              ouvre un checkpoint et un point de téléportation (l'étage suivant).
//   Cercle   = 72 étages (4 sections) — 9 Cercles de l'Enfer = 648 étages,
//   finale   = 18 étages (1 section) « L'Abîme » = 666. Soit 37 sections, 37 Gardiens.

export function floorInfo(tuning, floor) {
  const f = tuning.floors;
  const n = Math.max(1, Math.min(f.total, Math.floor(floor)));
  const section = Math.ceil(n / f.sectionLength); // 1..37
  const indexInSection = n - (section - 1) * f.sectionLength; // 1..18
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
 * Multiplicateurs de difficulté de l'étage, définis jusqu'à 666 (k = étage − 1, i = index dans
 * la section 1..18). Le jeu sépare le PERMANENT (classe, équipement, Ville) du TEMPORAIRE
 * (bénédictions, effacées à chaque mort, la reprise se faisant au début d'une section) ; la
 * difficulté suit la même séparation :
 *   L  = 1 + itemGrowth·k                          niveau d'objet (l'équipement trouvé suit la même pente)
 *   Bp = 1 + permBuildCap·(1 − e^(−k/permBuildScale))  ce que la progression PERMANENTE apporte en plus
 *                                                  du niveau (raretés, affixes, Sanctuaire)
 *   Bs = 1 + sectionBuildCap·(i − 1)/(longueur − 1)    build TEMPORAIRE réuni depuis le checkpoint :
 *                                                  1 au début de chaque section, maximal au Gardien
 *   C  = 1 + driftAt666·k/665                       dérive de difficulté
 *   H  = (PV innés + armure·L)/(PV innés + armure)  PV d'un héros équipé à niveau (armure, même pente)
 *   D  = 1 + dmgCurve·(1 − e^(−k/dmgScale))         part des PV que pèse un coup, en plus
 *   PV ennemis = L·Bp·Bs·C · dégâts = H·D · densité = 1 + densityCurve·(1 − e^(−k/densityScale)).
 * Les PV montent donc en dents de scie : ils croissent dans une section (jusqu'au Gardien), le
 * début de section redescend au niveau de ce qu'un héros SANS bénédiction peut affronter, et
 * chaque début de section reste plus dur que le précédent. Les télégraphes ne changent jamais.
 */
export function floorScaling(tuning, floor) {
  const f = tuning.floors;
  const n = Math.max(1, Math.min(f.total, Math.floor(floor)));
  const k = n - 1;
  const index = k % f.sectionLength; // 0..17
  const L = 1 + f.itemGrowth * k;
  const Bp = 1 + f.permBuildCap * (1 - Math.exp(-k / f.permBuildScale));
  const Bs = 1 + (f.sectionBuildCap * index) / Math.max(1, f.sectionLength - 1);
  const C = 1 + (f.driftAt666 * k) / Math.max(1, f.total - 1);
  const H = playerHpGrowth(tuning, L);
  const D = 1 + f.dmgCurve * (1 - Math.exp(-k / f.dmgScale));
  const density = 1 + f.densityCurve * (1 - Math.exp(-k / f.densityScale));
  return { hp: L * Bp * Bs * C, damage: H * D, density, level: L, permBuild: Bp, sectionBuild: Bs, drift: C, hpGrowth: H, lethality: D };
}

/** PV d'un héros équipé d'une armure de niveau L, relatifs au niveau 1 (PV innés + armure). */
export function playerHpGrowth(tuning, L) {
  const innate = tuning.player?.innateHp ?? 0;
  const armor = tuning.armorBase ?? 1;
  return (innate + armor * L) / (innate + armor);
}

/**
 * Difficulté au DÉBUT de la section (checkpoint), face à un héros qui n'a que son PERMANENT :
 * équipement trouvé jusqu'au Gardien précédent (niveau d'objet = étage − 1), aucune bénédiction.
 *   toughness = PV ennemis ÷ dégâts de l'arme portée (temps pour tuer, relatif à l'étage 1)
 *   lethality = dégâts ennemis ÷ PV du héros équipé (part des PV par coup, relative à l'étage 1)
 */
export function sectionStartDifficulty(tuning, section) {
  const { first } = sectionBounds(tuning, section);
  const s = floorScaling(tuning, first);
  const gear = floorScaling(tuning, Math.max(1, first - 1));
  return { floor: first, toughness: s.hp / gear.level, lethality: s.damage / gear.hpGrowth };
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
