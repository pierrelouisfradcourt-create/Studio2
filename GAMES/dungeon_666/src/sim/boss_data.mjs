// DONNÉES des modèles de Gardien AJOUTÉS (tuning), fusionnées dans tuning.boss par config.mjs.
// Chaque entrée suit la forme de tuning.boss.gardien (Charon) : name, radius, hp, speed, mass,
// damage, hitstopCap, phase2At, phase3At, transition, reinforcements, phaseHealOrb, restBetween,
// restMultByPhase, speedMultByPhase, puis les paramètres de SES patterns.
//
// Règles communes (testées, tests/v2_guardians.test.mjs) :
//   - tout télégraphe (windup, delay, step…) dure au moins GUARDIAN_MIN_TELE s ;
//   - les phases changent le NOMBRE de coups, les pauses et la vitesse, JAMAIS la durée d'un
//     télégraphe ; la profondeur (floorScaling) ne touche qu'aux PV et aux dégâts ;
//   - les frappes qu'on doit TRAVERSER (bandes, ondes, poings) restent plus étroites que la
//     portée du dash (165 u) ; les autres se quittent à pied (cercles posés sous le héros, sceau).
//   Unités : u, secondes, degrés ; *ByPhase = valeurs des phases 1, 2, 3.
//
// GUARDIAN_ROTATION : ordre des modèles sur les 37 sections (section 1 = premier de la liste).

export const GUARDIAN_MIN_TELE = 0.5;

export const EXTRA_BOSSES = {
  // Bête rapide : bonds, souffles séquentiels, morsures ; rôde au repos ; frénésie en phase 3.
  cerbere: {
    name: 'Cerbère, le Chien des trois gueules',
    radius: 34, hp: 1650, speed: 175, mass: 10, damage: 18,
    hitstopCap: 0.075,
    phase2At: 0.66,
    phase3At: 0.33,
    transition: 1.4,
    reinforcements: { 2: [], 3: ['exploder', 'exploder'] },
    phaseHealOrb: 15,
    restBetween: [0.55, 0.95],
    restMultByPhase: [1, 0.8, 0.5], // frénésie : presque plus de pauses en phase 3…
    speedMultByPhase: [1, 1.1, 1.3], // … et il rôde plus vite ; ses télégraphes, eux, restent
    prowl: { dist: 250, radialGain: 1.4 }, // repos : tourne autour du héros à cette distance
    // Bond : cercle d'atterrissage posé sous le héros, télégraphié `windup` s ; envol pendant les
    // `air` dernières s. Dès shockFromPhase, le dernier bond d'une série libère un anneau (onde).
    bond: {
      windup: 0.75, air: 0.42, radius: 115, damage: 18, leapsByPhase: [1, 2, 3], interval: 0.15,
      recover: 1.1, exposedMult: 0.5, shockFromPhase: 2, shockWidth: 110, shockDelay: 0.35, shockDamage: 14,
    },
    // Souffle : `jets` lignes de flammes en éventail, l'une après l'autre (pas `step`).
    souffle: { windup: 0.75, step: 0.25, jets: 3, spreadDeg: 32, length: 430, width: 90, damage: 16, volleysByPhase: [1, 2, 2], volleyGap: 0.35 },
    // Morsures : ruées en cône (comme le diablotin, en plus fort), re-visées entre deux.
    morsures: {
      windup: 0.55, lockAt: 0.7, bites: 3, strikeSpeed: 640, strikeTime: 0.18, recover: 0.28, finalRecover: 0.9,
      damage: 14, arcDeg: 60, exposedMult: 0.5, engageFrac: 0.8, approachMult: 1.5, approachMax: 1.2,
    },
    // Hurlement (phase 3) : couronne de flammes autour du héros, brèche de `gaps` flammes, puis
    // bond au centre (cercle du bond) à `leapDelay` s.
    hurlement: { flames: 10, gaps: 2, ringRadius: 170, flameRadius: 62, delay: 1.1, leapDelay: 1.4, damage: 16 },
  },

  // Juge : contrôle de l'arène (bandes, damier, fouet à 360°, téléportation) ; ne poursuit jamais.
  minos: {
    name: 'Minos, le Juge des damnés',
    radius: 38, hp: 1650, speed: 70, mass: 14, damage: 18,
    hitstopCap: 0.075,
    phase2At: 0.66,
    phase3At: 0.33,
    transition: 1.5,
    reinforcements: { 2: ['archer', 'archer'], 3: ['imp', 'imp', 'imp'] },
    phaseHealOrb: 15,
    restBetween: [0.7, 1.2],
    restMultByPhase: [1, 0.85, 0.7],
    speedMultByPhase: [1, 1, 1.1],
    throne: { fx: 0.5, fy: 0.3, settle: 12 }, // repos : regagne ce point (fractions de la salle)
    chantPad: 22, // u : rayon de l'alerte INOFFENSIVE quand il incante (au-delà de son corps)
    // Sentence : bandes jointives (6 horizontales de 139 u, ou 9 verticales de 150 u), une brèche chacune.
    sentence: {
      delay: 0.9, step: 0.25, bandsH: 6, bandsV: 9, breach: 190, breachReach: 260, damage: 18,
      ownBreachFromPhase: 2, crossFromPhase: 3, crossGap: 0.3,
    },
    // Jugement : damier de cercles (rayon = spacing × radiusMult) dans `reach` cases du héros ;
    // gap = delay : une seule vague affichée à la fois (la suivante naît quand la précédente frappe).
    jugement: { delay: 1.0, gap: 1.0, spacing: 170, radiusMult: 0.62, reach: 2, damage: 16, wavesByPhase: [2, 2, 3] },
    // Fouet : secteur de 360° − breachDeg ; second coup dès doubleFromPhase (télégraphe propre).
    fouet: { windup: 0.9, secondWindup: 0.6, range: 250, breachDeg: 70, minOffsetDeg: 100, damage: 20, recover: 0.9, exposedMult: 0.5, doubleFromPhase: 2 },
    // Sceau : couronne (anneau inner..outer) autour du point d'arrivée, sur le héros.
    sceau: { delay: 0.95, inner: 95, outer: 300, damage: 20, whipFromPhase: 3 },
  },

  // Colosse : lent et massif ; poings en ligne (point faible exposé), ondes, éboulis et braises
  // persistantes, geôliers qui le rendent invulnérable tant qu'ils vivent.
  colosse: {
    name: 'Éphialte, le Colosse enchaîné',
    radius: 52, hp: 1700, speed: 62, mass: 30, damage: 22,
    hitstopCap: 0.075,
    phase2At: 0.66,
    phase3At: 0.33,
    transition: 1.6,
    reinforcements: { 2: [], 3: [] }, // ses renforts passent par les geôliers (pattern, bouclier)
    phaseHealOrb: 15,
    restBetween: [0.8, 1.3],
    restMultByPhase: [1, 0.85, 0.7],
    speedMultByPhase: [1, 1.1, 1.2],
    poing: { windup: 1.0, fistGap: 0.4, length: 480, width: 150, damage: 24, fistsByPhase: [1, 2, 3], stuck: 1.5, exposedMult: 0.75 },
    seisme: { delay: 0.85, step: 0.3, band: 135, ringsByPhase: [4, 5, 6], damage: 16 },
    eboulis: {
      delayMin: 0.8, delayMax: 1.6, rocksByPhase: [6, 8, 10], radius: 68, spread: 320, damage: 16,
      poolFromPhase: 2, poolLife: 8, poolPulse: 1.0, poolRadius: 70, poolDamage: 10, poolMax: 8,
    },
    geoliers: {
      windup: 0.9, telePad: 30, kind: 'archer', countByPhase: [0, 2, 3], minR: 120, maxR: 340, minPlayerDist: 160,
      shieldMax: 12, shieldHold: 0.1,
    },
  },
};

// Section 1 : Charon ; puis Cerbère (36), Minos (54), Éphialte (72, fin du 1er Cercle), etc.
export const GUARDIAN_ROTATION = ['gardien', 'cerbere', 'minos', 'colosse'];
