// DONNÉES des archétypes d'ennemis AJOUTÉS (tuning), fusionnées dans tuning.enemies par
// config.mjs, et leur place dans les vagues (ROSTER de room.mjs).
//
// EXTRA_ENEMIES : { kind: { name, radius, hp, speed, mass, damage, …, gold: [lo, hi] } }
// EXTRA_ROSTER  : [{ kind, cost, minIndex, weight }] — coût en budget de vague, index minimal
//                 dans la 1re section (les sections suivantes ont tout le bestiaire), poids.
// EXTRA_ELITE_KINDS : archétypes pouvant recevoir un modificateur d'élite.
//
// BESTIAIRE (priorité 4 de la demande) — archétype -> kind :
//   mêlée rapide   -> imp (Diablotin)          mêlée lourde -> brute (Brute)
//   distance       -> archer (Archer squelette) chargeur     -> charger (Bélier)
//   kamikaze       -> exploder (Possédé)
//   ZONE           -> pyromancer (Pyromancienne, foe_pyromancer.mjs) — NOUVEAU
//   INVOCATEUR     -> necromancer (Nécromancien, foe_necromancer.mjs) — NOUVEAU
//   GARDE DE FACE  -> pavois (Porte-pavois, foe_pavois.mjs) — 2026-10-01 : on passe DERRIÈRE lui
//   EMBUSCADE      -> stalker (Traqueur, foe_stalker.mjs) — 2026-10-01 : il resurgit dans le dos
//   SOUTIEN        -> banner (Porte-étendard, foe_banner.mjs) — 2026-10-01 : il protège les autres
//   ÉLITE          -> modificateurs façon champions Diablo (config.mjs elite.mods, foe_elites.mjs)
//
// Règles de lisibilité tenues par chaque archétype : aucun dégât de contact ; toute menace est
// télégraphiée (rouge = ça fait mal ; une alerte inoffensive porte harmless: true) ; les durées
// de télégraphe ne dépendent jamais de l'étage.

export const EXTRA_ENEMIES = {
  // ZONE : garde ses distances, pose des cercles de feu télégraphiés sur et autour du héros ;
  // chaque cercle laisse ensuite une FLAQUE brûlante persistante (dégâts par tick, à
  // l'intérieur seulement). Contre-jeu : sortir des cercles, la rattraper (elle est lente et
  // fragile) ; la tuer ou l'étourdir pendant le télégraphe ANNULE ses cercles.
  pyromancer: {
    name: 'Pyromancienne', radius: 14, hp: 30, speed: 125, mass: 1, damage: 12,
    preferredDist: 320, fleeDist: 210, approachSlack: 60, castRange: 560, strafeMult: 0.6, strafeFlip: 0.01,
    castTime: 0.4, // bâton levé (lisible sur elle) avant que les cercles n'apparaissent
    recover: 0.55, cooldown: 3.4, cooldownJitter: [0.85, 1.25],
    pyre: {
      count: 3, // 1 cercle sur le héros + 2 autour
      radius: 64,
      spread: 130, // distance des cercles satellites au héros
      delay: 1.0, // télégraphe du 1er cercle (s) — jamais raccourci
      stagger: 0.2, // les satellites s'allument ensuite, un par un
      linger: 3.2, // durée de la flaque brûlante (s)
      tickEvery: 0.5, // un tick de brûlure toutes les 0,5 s…
      tickDamage: 4, // … seulement si le héros est DANS la flaque
      wallInset: 0.5, // centre d'un cercle à au moins 0,5 rayon du mur
    },
    gold: [2, 4],
  },
  // INVOCATEUR : fuit le héros, canalise visiblement (alerte violette inoffensive), puis ouvre
  // des cercles d'invocation (queueSpawn) d'où sortent des diablotins. Plafond d'invocations
  // vivantes ; peu de PV ; cible prioritaire. Le tuer ou l'étourdir pendant la canalisation
  // l'annule (aucun cercle ne s'ouvre).
  necromancer: {
    name: 'Nécromancien', radius: 15, hp: 26, speed: 118, mass: 1, damage: 0,
    preferredDist: 380, fleeDist: 250, approachSlack: 60, fleeSpeedMult: 1.15, strafeMult: 0.5, strafeFlip: 0.01,
    channel: 1.2, // canalisation visible (s)
    channelRadius: 58, // rayon de l'alerte inoffensive dessinée autour de lui
    recover: 0.5, cooldown: 5, cooldownJitter: [0.9, 1.2],
    minionKind: 'imp', count: 2,
    maxMinions: 4, // invocations VIVANTES (et en attente) qu'il peut entretenir
    summonMinR: 40, summonMaxR: 130, summonMinPlayerDist: 160,
    gold: [2, 5],
  },
  // GARDE DE FACE : un pavois qui arrête, DE FACE, les coups d'arme et la compétence (guardSources)
  // dans un arc de `guardArc` rad autour de `e.face`. Il pivote lentement vers le héros (turnRate) ;
  // sa face est VERROUILLÉE pendant son coup (télégraphe + récupération). Contre-jeu : dasher
  // derrière lui (de dos et de flanc, tout passe), ou le punir après son coup (pavois écarté
  // pendant `recover`), ou l'étourdir (mur, gadget : pavois baissé). Nombres : PV et dégâts du
  // Bélier (52 PV, 14), lenteur et masse entre le Bélier et la Brute, télégraphe entre le
  // Diablotin (0,42 s) et la Brute (0,7 s), récupération de la Brute (0,95 s).
  pavois: {
    name: 'Porte-pavois', radius: 20, hp: 56, speed: 96, mass: 3, damage: 15,
    attackRange: 70, // il arme son coup quand le héros est à moins de attackRange + rayon du héros, DEVANT lui
    windup: 0.6, bashRange: 96, bashArc: 1.5, // coup de pavois : secteur de 86° devant lui, frappe d'un bloc
    recover: 0.9, cooldown: 1.5,
    turnRate: 2, // rad/s (115°/s) : un demi-tour lui prend 1,6 s — un dash le prend de vitesse
    guardArc: 2.2, // rad (126°) de face où le pavois arrête les coups
    guardSources: ['melee', 'strike', 'skill'], // gadget, Super, brûlure, éclairs et murs passent
    gold: [3, 5],
  },
  // EMBUSCADE : rôde à distance, se dissout (fade, visible et vulnérable), disparaît (hiddenTime,
  // intouchable), puis resurgit DANS LE DOS du héros et frappe en cercle autour de lui après un
  // télégraphe rouge (slashWindup). Contre-jeu : lire la disparition, dasher hors du cercle (ou à
  // travers : esquive parfaite), puis le punir pendant sa longue récupération ; le tuer ou
  // l'étourdir pendant la dissolution ou le télégraphe annule le coup. Nombres : PV de la
  // Pyromancienne (30 : un assassin fragile), vitesse du Diablotin (150), dégâts du Bélier (14),
  // télégraphe 0,55 s (au-dessus du seuil de 0,4 s et du Diablotin 0,42 s).
  stalker: {
    name: 'Traqueur', radius: 14, hp: 30, speed: 150, mass: 1, damage: 14,
    preferredDist: 250, fleeDist: 150, approachSlack: 50, strafeMult: 0.7, strafeFlip: 0.01,
    stalkRange: 420, // il ne disparaît que s'il est à cette distance du héros au plus
    fade: 0.35, hiddenTime: 0.5,
    backDist: 62, // distance au héros du point de réapparition (dans son dos)
    backAngles: [0, 0.7, -0.7, 1.4, -1.4, 3.14], // écarts essayés autour du dos si le point est dans un mur
    slashWindup: 0.55, slashRadius: 82,
    recover: 1, cooldown: 3.2, cooldownJitter: [0.85, 1.25],
    gold: [2, 4],
  },
  // SOUTIEN : n'attaque jamais. Tant qu'il est debout (ni mort ni étourdi), les AUTRES ennemis à
  // moins de `auraRadius` de lui ne prennent que `wardMult` des dégâts. Il suit la mêlée à distance
  // et recule quand on le serre. Contre-jeu : traverser la mêlée (dash) pour le tuer d'abord, ou
  // entraîner le combat hors de son aura. Nombres : PV entre l'Archer (20) et le Bélier (52),
  // lenteur d'un porteur chargé (105 < Nécromancien 118), protection plus forte que l'élite
  // blindé (×0,8) mais qui tombe avec lui.
  banner: {
    name: 'Porte-étendard', radius: 17, hp: 46, speed: 105, mass: 2.5, damage: 0,
    preferredDist: 170, fleeDist: 120, approachSlack: 30, strafeMult: 0.4, strafeFlip: 0.01,
    auraRadius: 260, // un allié au contact du héros reste couvert quand il se tient à 200 u
    wardMult: 0.6, // dégâts subis par les alliés sous l'étendard
    gold: [3, 5],
  },
};

export const EXTRA_ROSTER = [
  // Introduction progressive dans la 1re section de 18 étages : la zone à l'étage 5,
  // l'invocateur à l'étage 8 (l'étage 9 est la halte marchand / autel).
  { kind: 'pyromancer', cost: 2, minIndex: 5, weight: 2 },
  { kind: 'necromancer', cost: 2.5, minIndex: 8, weight: 1.5 },
  // Bestiaire du 2026-10-01, après la halte (étage 9) et un par un : le pavois à l'étage 10, le
  // traqueur à l'étage 12, l'étendard à l'étage 14. Coûts : le pavois vaut un Nécromancien (2,5 :
  // 56 PV dont la moitié des coups rebondit), le traqueur une Pyromancienne (2), l'étendard 2
  // (il ne frappe pas, mais il allonge la vie de la vague). Poids modestes : ce sont des épices.
  { kind: 'pavois', cost: 2.5, minIndex: 10, weight: 1.5 },
  { kind: 'stalker', cost: 2, minIndex: 12, weight: 1.5 },
  { kind: 'banner', cost: 2, minIndex: 14, weight: 1.2 },
];

// Le Porte-étendard et le Nécromancien ne sont jamais champions (ils ne frappent pas).
export const EXTRA_ELITE_KINDS = ['pyromancer', 'pavois', 'stalker'];
