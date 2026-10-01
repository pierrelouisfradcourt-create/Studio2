// TUNING — tous les nombres du jeu, au même endroit. Aucune règle de la simulation ne porte
// de valeur en dur : elle lit `game.tuning`, une COPIE de DEFAULT_TUNING faite à la création
// de la partie (le panneau de réglage modifie la copie en direct, jamais les défauts).
//
// Unités : 1 u = 1 px à l'échelle de référence (caméra ~ 960 × 540 u en paysage).
// Temps en secondes, angles en degrés dans ce fichier (convertis à l'usage), simulation à 60 Hz.

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
  // Combo de 3 coups. arc en degrés. lunge = petit déplacement vers l'avant au début de l'actif.
  combo: [
    { startup: 0.05, active: 0.07, recovery: 0.12, range: 84, arc: 140, damage: 10, knockback: 240, lunge: 36, hitstop: 0.04, shake: 0.2 },
    { startup: 0.05, active: 0.07, recovery: 0.12, range: 84, arc: 140, damage: 11, knockback: 240, lunge: 36, hitstop: 0.04, shake: 0.2 },
    { startup: 0.09, active: 0.09, recovery: 0.24, range: 104, arc: 220, damage: 22, knockback: 560, lunge: 64, hitstop: 0.085, shake: 0.45 },
  ],
  comboResetTime: 0.32, // au-delà, le prochain coup repart du coup 1
  // Fraction de la récupération à jouer avant que le coup suivant puisse partir (le dash, lui,
  // annule tout). Le finisher (coup 3) engage davantage ; le dash reste la sortie rapide.
  comboCancelFrom: { hits: [0.3, 0.3, 0.6], strike: 0.3 },
  dashStrike: { startup: 0.04, active: 0.08, recovery: 0.16, range: 96, arc: 120, damage: 18, knockback: 420, lunge: 90, hitstop: 0.06, shake: 0.35 },
  wallSlam: { minSpeed: 380, damage: 8, stun: 0.45, hitstop: 0.05 },
  // Visée assistée : la mêlée ne se tourne que vers ce qu'elle peut atteindre ; la Lance voit loin.
  autoAim: { range: 160, skillRange: 520, coneDeg: 80, movePreference: 0.35 },

  // Compétence : Lance infernale — projectile perforant, visée glissée ou auto.
  skill: { cooldown: 4.0, damage: 30, speed: 900, radius: 12, range: 540, pierce: 3, knockback: 300, hitstop: 0.05, castTime: 0.08 },
  // Gadget (charges, façon Brawl Stars) : Nova de cendres — onde qui repousse et étourdit.
  gadget: { chargesPerSection: 3, chargeOnEliteKill: 1, radius: 150, damage: 20, knockback: 900, stun: 0.9, iframes: 0.25, hitstop: 0.07, shake: 0.4 },
  // Super : Colère — se remplit en infligeant des dégâts ; tourbillon invulnérable.
  super: { startCharge: 0.4, chargeDamage: 900, duration: 1.4, tickInterval: 0.12, radius: 130, damagePerTick: 9, knockback: 260, speedMult: 0.85, shakePerTick: 0.1 },

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

  // Structure des 666 étages : sections de 6 (le 6e = boss checkpoint) ; 9 Cercles de
  // 72 étages (12 sections) = 648, puis la finale de 18 étages (3 sections) = 666.
  floors: {
    total: 666,
    sectionLength: 6,
    circleLength: 72,
    circleNames: ['Limbes', 'Luxure', 'Gourmandise', 'Avarice', 'Colère', 'Hérésie', 'Violence', 'Fraude', 'Trahison'],
    finaleName: 'L\'Abîme',
    // Scaling (spec §5.5) : L = niveau d'objet, B = saturation du build, C = dérive, D = dégâts.
    itemGrowth: 0.05, buildCap: 2, buildScale: 100, driftAt666: 0.5, dmgCurve: 0.6, dmgScale: 150,
  },

  economy: {
    goldPerRoom: [8, 14], shopHealPrice: 40, shopBoonPrice: 70, shopItemPrice: [60, 140],
    deathGoldKeep: 0.5,
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
