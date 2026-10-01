// TUNING — tous les nombres du jeu, au même endroit. Aucune règle de la simulation ne porte
// de valeur en dur : elle lit `game.tuning`, une COPIE de DEFAULT_TUNING faite à la création
// de la partie (le panneau de réglage modifie la copie en direct, jamais les défauts).
//
// Unités : 1 u = 1 px à l'échelle de référence (caméra ~ 960 × 540 u en paysage).
// Temps en secondes, angles en degrés dans ce fichier (convertis à l'usage), simulation à 60 Hz.

import { WEAPONS, SKILLS, GADGETS, SUPERS, CLASSES } from './kits.mjs';
import { UPGRADES, SALVAGE_SOULS } from './town_data.mjs';
import { EXTRA_ENEMIES } from './foe_data.mjs';
import { EXTRA_BOSSES, GUARDIAN_ROTATION } from './boss_data.mjs';

export const SIM_HZ = 60;
export const DT = 1 / SIM_HZ;

export const DEFAULT_TUNING = {
  player: {
    radius: 16,
    maxHp: 100,
    speed: 300, // u/s
    accelTime: 0.083, // s pour atteindre la vitesse max depuis l'arrêt (5 images)
    decelTime: 0.05, // s pour s'arrêter (3 images) : l'arrêt net fait la nervosité
    // Vitesse pendant une attaque. Sur tactile on MAINTIENT l'attaque : à 0,2 le héros devenait
    // plus lent qu'un diablotin (critique « fun »). 0,5 garde le combo mobile ; l'oracle de
    // solvabilité mesure que le dash reste décisif (×4,5 de dégâts reçus sans lui).
    attackMoveMult: 0.5,
    hurtIframes: 0.6, // invulnérabilité après un coup reçu
    hurtHitstop: 0.083, // gel global quand le héros est touché : il DOIT le sentir
    cancelMult: 1, // D9 : multiplie la part de récupération à jouer avant le coup suivant
    inputBuffer: 0.15, // une action pressée trop tôt reste en mémoire
    // Attaque et Lance tapées pendant un coup engagé : le finisher verrouille 0,32 s, un tampon
    // de 0,15 s y perdait un tap sur trois (revue « feel »). Dash et Super gardent 0,15 s.
    attackBuffer: 0.35,
    innateHp: 45, // PV sans armure ; l'armure de départ en apporte 55
  },
  // Arme : les dégâts du combo sont donnés pour une arme de base `weaponBase`, puis mis à
  // l'échelle de l'arme portée (façon Diablo : une meilleure arme frappe plus fort).
  weaponBase: 10,
  armorBase: 55,
  // Gel d'impact plafonné : au plus `bank` secondes de gel, rechargées à `refill` par seconde.
  // Sans plafond, une mêlée de 6 ennemis transforme le combat en diaporama.
  hitstopBank: { max: 0.22, refill: 0.22 },
  hitstopMode: 'global', // D8 : global | local (écrit par lab.mjs selon lab.hitstop)
  killHitstop: { elite: 0.1, boss: 0.2, lastEnemy: 0.13 },
  dash: {
    distance: 165,
    duration: 0.15,
    iframes: 0.18, // depuis le début du dash (dépasse sa fin d'une image : marge tactile)
    charges: 2,
    recharge: 0.9, // s par charge, rechargées l'une après l'autre
    strikeWindow: 0.3, // une attaque lancée dans cette fenêtre après un dash = frappe de dash (le pouce doit avoir le temps)
    strikeCancelFrom: 0.45, // attaquer quand il reste < 45 % du dash le coupe en frappe de dash
    cancelsHitstop: true, // presser dash pendant un gel d'impact l'interrompt (réactivité)
    // Esquive parfaite (un coup évité grâce aux i-frames) : récompense immédiate.
    perfectDodgeSuper: 0.06, // fraction de jauge de Super
    perfectDodgeRefund: 0.5, // s retirées à la recharge en cours
  },
  // Combo ACTIF (arc en degrés ; lunge = petit déplacement vers l'avant au début de l'actif).
  // Référence vers l'arme équipée (kits.mjs) : par défaut la Lame du Revenant.
  combo: WEAPONS.lame.combo,
  comboResetTime: 0.32, // au-delà, le prochain coup repart du coup 1
  // Fraction de la récupération à jouer avant que le coup suivant puisse partir (le dash, lui,
  // annule tout). Le finisher (coup 3) engage davantage ; le dash reste la sortie rapide.
  comboCancelFrom: { hits: [0.3, 0.3, 0.6], strike: 0.3 },
  dashStrike: WEAPONS.lame.dashStrike, // frappe de dash de l'arme équipée
  wallSlam: { minSpeed: 380, damage: 8, stun: 0.45, hitstop: 0.05 },
  // Visée assistée : la mêlée ne se tourne que vers ce qu'elle peut atteindre ; la Lance voit loin.
  autoAim: { range: 160, skillRange: 520, coneDeg: 80, movePreference: 0.35 },

  // Kit ACTIF (références vers le kit équipé, résolu par loadout.mjs) : compétence (bouton
  // Lance), gadget (charges par section, façon Brawl Stars), Super (jauge remplie en frappant).
  skill: SKILLS.lance,
  gadget: GADGETS.nova,
  super: SUPERS.colere,
  // Tous les kits disponibles (classes, armes, compétences, gadgets, Supers).
  classes: CLASSES,
  weapons: WEAPONS,
  skills: SKILLS,
  gadgets: GADGETS,
  supers: SUPERS,

  // LABORATOIRE DU FEEL (D5 / D8 / D9) : variantes à comparer en jouant, jamais tranchées ici.
  // Chaque variante est appliquée par lab.mjs sur la copie de tuning de la partie.
  lab: {
    dashStrike: 'fin', // D5 : fin | toutDash | apresDash — quand une attaque devient frappe de dash
    hitstop: 'global', // D8 : global | local — gel de toute la scène, ou seulement des belligérants
    comboMobility: 'mobile', // D9 : ancre | mobile | fluide — vitesse et annulations pendant le combo
  },

  enemies: {
    imp: {
      name: 'Diablotin', radius: 13, hp: 22, speed: 150, mass: 1, damage: 8,
      attackRange: 52, windup: 0.42, strikeTime: 0.14, strikeSpeed: 520, recover: 0.65, cooldown: 0.9,
      gold: [1, 3],
    },
    archer: {
      name: 'Archer squelette', radius: 14, hp: 20, speed: 135, mass: 1, damage: 10,
      preferredDist: 260, fleeDist: 170, windup: 0.62, lockAt: 0.75, recover: 0.35, cooldown: 1.7,
      projSpeed: 380, projRadius: 7, projRange: 700, teleLength: 560, // ligne de visée jusqu'au héros (p90 des tirs)
      gold: [1, 3],
    },
    brute: {
      name: 'Brute', radius: 26, hp: 95, speed: 92, mass: 4, damage: 18,
      attackRange: 110, windup: 0.7, slamRadius: 105, recover: 0.95, cooldown: 1.2,
      gold: [3, 6],
    },
    charger: {
      name: 'Bélier', radius: 18, hp: 52, speed: 115, mass: 2, damage: 14,
      attackRange: 420, windup: 0.7, chargeSpeed: 720, chargeMaxTime: 0.75, wallStun: 1.4, recover: 0.6, cooldown: 1.6,
      gold: [2, 4],
    },
    exploder: {
      name: 'Possédé', radius: 12, hp: 10, speed: 210, mass: 0.7, damage: 16,
      triggerRange: 70, windup: 0.6, blastRadius: 90, blastHurtsEnemies: true,
      gold: [1, 2],
    },
    ...EXTRA_ENEMIES, // archétypes ajoutés (foe_data.mjs)
  },
  elite: {
    hpMult: 1.8, damageMult: 1.25, sizeMult: 1.25, goldMult: 3,
    // Modificateurs façon champions Diablo : un seul par élite dans le prototype.
    mods: {
      // Les télégraphes ne sont JAMAIS raccourcis (équité) : « rapide » accélère le déplacement.
      rapide: { speedMult: 1.45, windupMult: 1 },
      blinde: { damageTakenMult: 0.8, knockbackMult: 0.25 }, // le recul ×0,25 fait son identité, pas un sac à PV
      ardent: { deathBlastRadius: 110, deathBlastDelay: 0.7, deathBlastDamage: 18 },
    },
  },
  boss: {
    gardien: {
      name: 'Charon, le Passeur', radius: 40, hp: 1700, speed: 105, mass: 12, damage: 20,
      hitstopCap: 0.075, // gel max d'un coup sur le Gardien : le finisher (0,085) garde son poids
      phase2At: 0.66,
      phase3At: 0.33,
      transition: 1.5, // s d'invulnérabilité au changement de phase (rugissement, projectiles effacés)
      reinforcements: { 2: ['imp', 'imp', 'imp', 'imp'], 3: ['archer', 'archer', 'exploder', 'exploder'] },
      phaseHealOrb: 15,
      slam: { windup: 0.75, radius: 120, count: 3, interval: 0.45, damage: 20 },
      charge: { windup: 0.8, speed: 820, maxTime: 1.0, damage: 22, wallStun: 1.6, width: 88 }, // ≥ 2 × (rayon + 4) : le bord dessiné est le bord qui touche
      // teleRadius : cercle d'alerte, affiché aussi ENTRE les vagues tant que la salve continue.
      ring: { windup: 0.7, bullets: 18, gapCount: 3, speed: 260, radius: 9, damage: 12, waves: 2, waveInterval: 0.5, teleRadius: 90 },
      summon: { windup: 0.9, count: 3, kind: 'imp' },
      restBetween: [0.6, 1.1],
      restMultByPhase: [1, 0.8, 0.6], // pauses plus courtes à chaque phase…
      speedMultByPhase: [1, 1.05, 1.15], // … et plus de vitesse ; les télégraphes, eux, ne raccourcissent JAMAIS
      secondChargeWindup: 0.6, // phase 3 : seconde charge enchaînée (télégraphe propre ≥ 0,5 s)
    },
    ...EXTRA_BOSSES, // modèles de Gardien ajoutés (boss_data.mjs)
  },

  combat: {
    critChance: 0.05, critMult: 1.75,
    enemyFriction: 11, // décroissance exponentielle du knockback (1/s)
    enemySeparation: 0.6, // force de séparation entre ennemis
    maxAttackers: 2, // ennemis de mêlée autorisés à lancer une attaque en même temps (lisibilité)
    maxShooters: 2, // archers autorisés à viser en même temps
    stunDamageTakenMult: 1.5,
    minChillMult: 0.35, // plancher du ralentissement cumulé
  },

  room: {
    width: 1400, height: 880,
    wallPad: 24,
    spawnWarn: 0.75, // cercle d'invocation visible avant l'apparition
    spawnMinPlayerDist: 220,
    pickupMagnetRange: 120, pickupMagnetSpeed: 700,
    healOrbAmount: 12,
  },

  // Structure des 666 étages : sections de 18 (le 18e = Gardien, checkpoint et téléportation) ;
  // 9 Cercles de 72 étages (4 sections) = 648, puis la finale de 18 étages (1 section) = 666.
  // 37 sections, donc 37 Gardiens (rotation des modèles : bosses.mjs).
  floors: {
    total: 666,
    sectionLength: 18,
    circleLength: 72,
    circleNames: ['Limbes', 'Luxure', 'Gourmandise', 'Avarice', 'Colère', 'Hérésie', 'Violence', 'Fraude', 'Trahison'],
    finaleName: 'L\'Abîme',
    // Scaling (floors.mjs floorScaling) : L = niveau d'objet ; Bp = progression permanente ;
    // Bs = build temporaire depuis le checkpoint (dents de scie : 1 en début de section) ;
    // C = dérive ; H·D = dégâts (part des PV d'un héros équipé à niveau) ; densité des vagues.
    // Calés pour que la section 1 garde les valeurs d'avant (PV ×2,46 et dégâts ×1,97 au Gardien).
    itemGrowth: 0.05,
    permBuildCap: 0.35, permBuildScale: 150,
    sectionBuildCap: 0.265,
    driftAt666: 0.5,
    dmgCurve: 0.85, dmgScale: 33,
    densityCurve: 0.6, densityScale: 150,
    // Début de section ABORDABLE (tests/v2_floors.test.mjs) : face au seul équipement permanent,
    // temps pour tuer et part des PV par coup au plus ces multiples de l'étage 1.
    sectionStartMax: { toughness: 2.2, lethality: 2 },
  },

  // PLAN D'UNE SECTION (18 étages), composé à partir de types d'étages réutilisables
  // (sections.mjs sectionPlan). Les portes de sortie annoncent la récompense de l'étage suivant
  // (façon Hades) ; certains index de la section imposent leurs portes.
  section: {
    // Rythme : emplacement de chaque index 1..18. Combat court (1 vague), normal (2), assaut (3),
    // halte (portes imposées tirées dans `halte`), antichambre (portes `antichambre`), Gardien.
    // La section 1 joue toujours le premier rythme ; les suivantes en tirent un (graine).
    rhythms: [
      ['court', 'court', 'normal', 'normal', 'court', 'normal', 'normal', 'assaut', 'halte', 'court', 'normal', 'normal', 'normal', 'assaut', 'normal', 'assaut', 'antichambre', 'gardien'],
      ['court', 'normal', 'court', 'normal', 'normal', 'normal', 'court', 'assaut', 'halte', 'normal', 'court', 'normal', 'assaut', 'normal', 'court', 'assaut', 'antichambre', 'gardien'],
      ['court', 'court', 'normal', 'court', 'normal', 'normal', 'assaut', 'normal', 'halte', 'court', 'normal', 'normal', 'normal', 'assaut', 'court', 'assaut', 'antichambre', 'gardien'],
    ],
    paces: {
      court: { waves: 1, budgetMult: 1.1 },
      normal: { waves: 2, budgetMult: 1 },
      assaut: { waves: 3, budgetMult: 0.95 },
    },
    calmPace: 'court', // une halte ou une antichambre jouée en combat (reprise, départ à cet étage)
    eliteAt: [6, 12], // une des deux portes mène forcément à une épreuve d'élite
    halte: { doors: 2, pool: { shop: 3, event: 3, rest: 2, treasure: 2 } }, // portes distinctes tirées par section
    antichambre: ['shop', 'rest'], // avant le Gardien : marchand ou fontaine de repos
    treasure: { from: 3, to: 15 }, // une porte de chambre forte garantie à un index de cet intervalle
    // Poids des portes tirées (multipliés par le thème du Cercle, tuning.circles[].doors).
    doorWeights: { boon: 40, loot: 24, gold: 14, elite: 12, heal: 10, treasure: 2, rest: 0 },
    gadgetRefillEvery: 6, // charges de gadget rendues aux étages 1, 7 et 13 de la section
    sandbox: { floor: 4, eliteChance: 0.35 }, // arène d'essai : vagues d'un étage de début de section
    // Session mobile visée : une section en 10-14 min au plus. Estimation à partir du bot
    // (tests/v2_floors.test.mjs) : temps de sim × humanPace + menus × menuSeconds.
    session: { maxMinutes: 14, humanPace: 1.5, menuSeconds: 6 },
  },
  // Budget de menace d'une vague : (base + perIndex × index) × rythme × thème × densité de l'étage.
  // costRef : coût de référence du biais de coût des thèmes (poids × (coût / costRef)^costBias).
  // strayEliteFrom : premier étage où un élite égaré peut se glisser dans un combat ordinaire.
  encounter: { baseBudget: 5, perIndex: 0.45, lastWaveMult: 1.2, strayEliteChance: 0.15, strayEliteFrom: 3, costRef: 1.5 },
  // THÈMES des Cercles (index = Cercle − 1, le 10e = finale). Jamais de nom d'archétype : le
  // bestiaire est pondéré par COÛT (costBias > 0 : lourds ; < 0 : nuées) et `featured`
  // archétypes tirés par section dans tout le bestiaire présent sont multipliés par featuredMult.
  // layouts : dispositions permises et poids ; doors : multiplicateurs des poids de portes.
  circles: [
    { id: 'limbes', costBias: 0, featured: 0, featuredMult: 1, budgetMult: 1, strayEliteMult: 1, layouts: { open: 1, pillars: 1, center: 1, lanes: 1, bastions: 1, scatter: 1 }, doors: {} },
    { id: 'luxure', costBias: -0.5, featured: 1, featuredMult: 2, budgetMult: 1, strayEliteMult: 1, layouts: { open: 2, pillars: 1, center: 1, lanes: 1, bastions: 0.5, scatter: 2, ring: 2 }, doors: { boon: 1.2 } },
    { id: 'gourmandise', costBias: -0.3, featured: 1, featuredMult: 2, budgetMult: 1.05, strayEliteMult: 1, layouts: { open: 1, pillars: 1, center: 2, lanes: 1, bastions: 1, scatter: 1, cross: 2 }, doors: { heal: 1.5 } },
    { id: 'avarice', costBias: 0, featured: 1, featuredMult: 2, budgetMult: 1, strayEliteMult: 1, layouts: { open: 1, pillars: 1, center: 1, lanes: 1, bastions: 2, scatter: 1, alcoves: 2 }, doors: { gold: 1.6, treasure: 3 } },
    { id: 'colere', costBias: 0.6, featured: 2, featuredMult: 1.8, budgetMult: 1, strayEliteMult: 1.2, layouts: { open: 2, pillars: 1, center: 1, lanes: 2, bastions: 1, scatter: 1, cross: 1, ring: 1 }, doors: { elite: 1.3 } },
    { id: 'heresie', costBias: 0.2, featured: 2, featuredMult: 1.8, budgetMult: 1, strayEliteMult: 1.2, layouts: { open: 1, pillars: 2, center: 1, lanes: 1, bastions: 1, scatter: 1, ring: 1, alcoves: 2 }, doors: { loot: 1.2 } },
    { id: 'violence', costBias: 0.8, featured: 2, featuredMult: 1.8, budgetMult: 1, strayEliteMult: 1.4, layouts: { open: 1, pillars: 1, center: 1, lanes: 1, bastions: 1, scatter: 1, cross: 2, ring: 1 }, doors: { elite: 1.5 } },
    { id: 'fraude', costBias: 0, featured: 2, featuredMult: 2, budgetMult: 1, strayEliteMult: 1.4, layouts: { open: 1, pillars: 1, center: 1, lanes: 1, bastions: 1, scatter: 2, ring: 2, alcoves: 2 }, doors: { loot: 1.3, treasure: 2 } },
    { id: 'trahison', costBias: 0.4, featured: 2, featuredMult: 2, budgetMult: 1, strayEliteMult: 2, layouts: { open: 1, pillars: 1, center: 1, lanes: 1, bastions: 1, scatter: 1, cross: 1, ring: 1, alcoves: 1 }, doors: { elite: 1.6 } },
    { id: 'abime', costBias: 0.3, featured: 3, featuredMult: 1.8, budgetMult: 1, strayEliteMult: 2, layouts: { open: 1, pillars: 1, center: 1, lanes: 1, bastions: 1, scatter: 1, cross: 1, ring: 1, alcoves: 1 }, doors: {} },
  ],
  // Rotation des Gardiens sur les 37 sections (le 1er de la liste garde la section 1).
  guardians: { rotation: GUARDIAN_ROTATION },

  // PROGRESSION PERMANENTE (profil) : Âmes gagnées pendant la descente, jamais perdues.
  progression: {
    souls: { kill: 1, elite: 6, guardian: 60, guardianPerSection: 15 },
  },
  // VILLE : améliorations du Sanctuaire et recyclage du coffre (town_data.mjs).
  town: { upgrades: UPGRADES, salvageSouls: SALVAGE_SOULS },

  economy: {
    goldPerRoom: [8, 14], shopHealPrice: 40, shopBoonPrice: 70, shopItemPrice: [60, 140],
    deathGoldKeep: 0.5,
    // Salles calmes (calm_rooms.mjs). Chambre forte : un choix parmi objet, bourse, relique.
    treasure: { gold: [45, 70], rarityBonus: 2, minRarity: 'magique', goldPickups: 8 },
    // Fontaine de repos : un choix parmi boire (soin), méditer (+1 niveau), fioles (pouvoirs).
    rest: { heal: 0.5, superCharge: 0.5 },
  },

  loot: {
    rarityWeights: { commun: 60, magique: 28, rare: 10, legendaire: 2 },
    eliteRarityBonus: 1.8,
    bossGuaranteedRare: true,
  },
};

/** Copie profonde des défauts : la partie la possède et peut la modifier. */
export function createTuning(overrides) {
  const t = structuredClone(DEFAULT_TUNING);
  if (overrides) deepMerge(t, overrides);
  return t;
}

function deepMerge(target, src) {
  for (const [k, v] of Object.entries(src)) {
    if (v && typeof v === 'object' && !Array.isArray(v) && target[k] && typeof target[k] === 'object') {
      deepMerge(target[k], v);
    } else {
      target[k] = v;
    }
  }
}

export const DEG = Math.PI / 180;
