// KITS DU HÉROS — classes, armes, compétences, gadgets, Supers (données de tuning).
//
// Le kit ÉQUIPÉ est « résolu » à la création de la partie (loadout.mjs) : les blocs
// actifs de la copie de tuning de la partie (`combo`, `dashStrike`, `skill`, `gadget`, `super`)
// deviennent des RÉFÉRENCES vers l'entrée choisie ici. Toute la simulation (et les tests)
// continue de lire `tuning.combo`, `tuning.skill`… : le Revenant armé de la Lame, avec la Lance,
// la Nova et la Colère, reproduit EXACTEMENT le kit d'avant les classes.
//
// Unités : comme config.mjs (u, s, degrés). `kind` choisit le code qui joue l'entrée :
//   armes      melee (balayage en secteur) | ranged (projectiles, champ `shot` de chaque coup)
//   compétences lance | chain | bond | brasier | volee        (player.mjs, kit_skills.mjs)
//   gadgets    nova | bombe | piege | totem | cri             (player.mjs, kit_gadgets.mjs)
//   Supers     colere | sentence | nuee                       (player.mjs, kit_supers.mjs)
// `cost` : prix de déblocage en Âmes (Ville) ; 0 = possédé d'office (départ de la classe).
// `icon` : pictogramme du bouton (hud.mjs) ; absent = pictogramme historique du bouton.
// Données PURES (aucune fonction) : le tuning est cloné par structuredClone.

// ---------------------------------------------------------------- armes (jeux de coups)

// Lame du Revenant : le combo historique (valeurs inchangées).
const LAME_COMBO = [
  { startup: 0.05, active: 0.07, recovery: 0.12, range: 84, arc: 140, damage: 10, knockback: 240, lunge: 36, hitstop: 0.04, shake: 0.2 },
  { startup: 0.05, active: 0.07, recovery: 0.12, range: 84, arc: 140, damage: 11, knockback: 240, lunge: 36, hitstop: 0.04, shake: 0.2 },
  { startup: 0.09, active: 0.09, recovery: 0.24, range: 104, arc: 220, damage: 22, knockback: 560, lunge: 64, hitstop: 0.085, shake: 0.45 },
];
const LAME_STRIKE = { startup: 0.04, active: 0.08, recovery: 0.16, range: 96, arc: 120, damage: 18, knockback: 420, lunge: 90, hitstop: 0.06, shake: 0.35 };

// Dagues jumelles : 4 coups vifs et étroits ; on danse en frappant (moveMult), le 4e croise.
const DAGUES_COMBO = [
  { startup: 0.035, active: 0.05, recovery: 0.08, range: 72, arc: 90, damage: 7, knockback: 120, lunge: 30, hitstop: 0.025, shake: 0.1, cancelFrom: 0.25 },
  { startup: 0.035, active: 0.05, recovery: 0.08, range: 72, arc: 90, damage: 7, knockback: 120, lunge: 30, hitstop: 0.025, shake: 0.1, cancelFrom: 0.25 },
  { startup: 0.035, active: 0.05, recovery: 0.08, range: 72, arc: 90, damage: 8, knockback: 140, lunge: 30, hitstop: 0.03, shake: 0.12, cancelFrom: 0.25 },
  { startup: 0.07, active: 0.07, recovery: 0.2, range: 88, arc: 160, damage: 18, knockback: 380, lunge: 56, hitstop: 0.07, shake: 0.35, cancelFrom: 0.55 },
];
// Fente : longue estocade de dash, étroite, qui traverse la garde.
const DAGUES_STRIKE = { startup: 0.03, active: 0.08, recovery: 0.14, range: 104, arc: 60, damage: 22, knockback: 300, lunge: 120, hitstop: 0.06, shake: 0.3 };

// Hache du bourreau : lente, large, le 3e coup étourdit (stun, ennemis ordinaires).
const HACHE_COMBO = [
  { startup: 0.12, active: 0.1, recovery: 0.22, range: 100, arc: 150, damage: 18, knockback: 420, lunge: 40, hitstop: 0.07, shake: 0.35, cancelFrom: 0.35 },
  { startup: 0.12, active: 0.1, recovery: 0.22, range: 100, arc: 150, damage: 20, knockback: 420, lunge: 40, hitstop: 0.07, shake: 0.35, cancelFrom: 0.35 },
  { startup: 0.2, active: 0.12, recovery: 0.38, range: 125, arc: 240, damage: 42, knockback: 820, lunge: 70, hitstop: 0.11, shake: 0.7, stun: 0.5, cancelFrom: 0.6 },
];
const HACHE_STRIKE = { startup: 0.06, active: 0.1, recovery: 0.24, range: 110, arc: 160, damage: 32, knockback: 600, lunge: 100, hitstop: 0.09, shake: 0.5 };

// Maillet des damnés : deux temps ; le second écrase le sol tout autour (360°) et étourdit.
const MARTEAU_COMBO = [
  { startup: 0.16, active: 0.1, recovery: 0.26, range: 95, arc: 120, damage: 26, knockback: 520, lunge: 30, hitstop: 0.08, shake: 0.4, cancelFrom: 0.4 },
  { startup: 0.26, active: 0.1, recovery: 0.42, range: 135, arc: 360, damage: 48, knockback: 700, lunge: 0, hitstop: 0.12, shake: 0.8, stun: 0.7, cancelFrom: 0.6 },
];
const MARTEAU_STRIKE = { startup: 0.05, active: 0.12, recovery: 0.26, range: 100, arc: 140, damage: 34, knockback: 900, lunge: 120, hitstop: 0.1, shake: 0.55 };

// Arc d'os : attaque principale à projectiles. range = portée du trait ; arc = éventail (degrés) ;
// lunge négatif = léger recul ; shot = projectile tiré au début de l'actif.
const ARC_COMBO = [
  { startup: 0.08, active: 0.04, recovery: 0.16, range: 480, arc: 0, damage: 7, knockback: 140, lunge: -8, hitstop: 0.025, shake: 0.08, cancelFrom: 0.3, shot: { kind: 'arrow', speed: 980, radius: 6, pierce: 0, count: 1 } },
  { startup: 0.08, active: 0.04, recovery: 0.16, range: 480, arc: 0, damage: 7, knockback: 140, lunge: -8, hitstop: 0.025, shake: 0.08, cancelFrom: 0.3, shot: { kind: 'arrow', speed: 980, radius: 6, pierce: 0, count: 1 } },
  { startup: 0.14, active: 0.05, recovery: 0.26, range: 560, arc: 0, damage: 18, knockback: 420, lunge: -24, hitstop: 0.06, shake: 0.25, cancelFrom: 0.5, shot: { kind: 'arrow', speed: 1250, radius: 8, pierce: 2, count: 1, heavy: true } },
];
// Tir roulé : trois flèches à bout portant en sortie de dash.
const ARC_STRIKE = { startup: 0.03, active: 0.04, recovery: 0.14, range: 380, arc: 24, damage: 12, knockback: 300, lunge: 0, hitstop: 0.05, shake: 0.25, shot: { kind: 'arrow', speed: 1100, radius: 7, pierce: 1, count: 3, heavy: true } };

// Arbalète des limbes : carreaux lents et perforants ; le 2e coup tire en éventail.
const ARBALETE_COMBO = [
  { startup: 0.1, active: 0.04, recovery: 0.2, range: 640, arc: 0, damage: 18, knockback: 520, lunge: -30, hitstop: 0.06, shake: 0.28, cancelFrom: 0.35, shot: { kind: 'bolt', speed: 1400, radius: 9, pierce: 3, count: 1 } },
  { startup: 0.14, active: 0.05, recovery: 0.3, range: 560, arc: 18, damage: 12, knockback: 380, lunge: -36, hitstop: 0.06, shake: 0.3, cancelFrom: 0.55, shot: { kind: 'bolt', speed: 1250, radius: 8, pierce: 1, count: 3, heavy: true } },
];
const ARBALETE_STRIKE = { startup: 0.04, active: 0.05, recovery: 0.2, range: 640, arc: 0, damage: 30, knockback: 700, lunge: 0, hitstop: 0.08, shake: 0.4, shot: { kind: 'bolt', speed: 1500, radius: 10, pierce: 4, count: 1, heavy: true } };

export const WEAPONS = {
  lame: {
    name: 'Lame du Revenant', kind: 'melee', className: 'revenant', cost: 0,
    text: 'Combo de 3 coups équilibré ; le 3e balaie large.',
    starterName: 'Épée rouillée', // exemplaire de départ / forgé en Ville
    bases: ['Lame', 'Fauchon', 'Glaive', 'Épée'], // noms des armes de ce type trouvées en donjon
    baseMult: 1, // dégâts de base W de ce type d'arme (× tuning.weaponBase)
    combo: LAME_COMBO,
    dashStrike: LAME_STRIKE,
  },
  dagues: {
    name: 'Dagues jumelles', kind: 'melee', className: 'revenant', cost: 40, icon: 'daggers',
    text: '4 coups vifs et étroits, très mobiles (75 % de vitesse en frappant). Frappe de dash : une longue fente.',
    starterName: 'Dagues ébréchées',
    bases: ['Dagues', 'Stylets', 'Crocs', 'Miséricordes'],
    baseMult: 1,
    moveMult: 1.5, // × player.attackMoveMult (D9) : vitesse pendant le combo
    combo: DAGUES_COMBO,
    dashStrike: DAGUES_STRIKE,
  },
  hache: {
    name: 'Hache du bourreau', kind: 'melee', className: 'bourreau', cost: 0, icon: 'axe',
    text: '3 coups lents et massifs ; le 3e balaie à 240° et étourdit.',
    starterName: 'Hache de billot',
    bases: ['Hache', 'Couperet', 'Fendoir', 'Francisque'],
    baseMult: 1,
    moveMult: 0.7,
    combo: HACHE_COMBO,
    dashStrike: HACHE_STRIKE,
  },
  marteau: {
    name: 'Maillet des damnés', kind: 'melee', className: 'bourreau', cost: 60, icon: 'hammer',
    text: '2 temps : un coup lourd, puis un fracas au sol tout autour qui étourdit.',
    starterName: 'Maillet fendu',
    bases: ['Maillet', 'Masse', 'Marteau', 'Étoile du matin'],
    baseMult: 1,
    moveMult: 0.55,
    combo: MARTEAU_COMBO,
    dashStrike: MARTEAU_STRIKE,
  },
  arc: {
    name: 'Arc d\'os', kind: 'ranged', className: 'chasseresse', cost: 0, icon: 'bow',
    text: 'Traits à distance : 2 rapides puis un trait perçant. Visée auto à 400 u, ou glissée.',
    starterName: 'Arc de côtes',
    bases: ['Arc', 'Arc long', 'Arc court', 'Arc de corne'],
    baseMult: 1,
    moveMult: 1.1, // on tire en marchant (55 % de vitesse au réglage D9 « mobile ») : le dash reste la fuite
    aimRange: 400, // visée assistée : portée de recherche de cible
    combo: ARC_COMBO,
    dashStrike: ARC_STRIKE,
  },
  arbalete: {
    name: 'Arbalète des limbes', kind: 'ranged', className: 'chasseresse', cost: 60, icon: 'crossbow',
    text: 'Carreaux lourds qui transpercent 3 ennemis ; le 2e tir part en éventail.',
    starterName: 'Arbalète vermoulue',
    bases: ['Arbalète', 'Baliste', 'Arbalète lourde', 'Cranequin'],
    baseMult: 1,
    moveMult: 0.8,
    aimRange: 500,
    combo: ARBALETE_COMBO,
    dashStrike: ARBALETE_STRIKE,
  },
};

// ---------------------------------------------------------------- compétences (bouton Lance)

// range / radius : portée et largeur utiles (lues par la visée tactile et par les bots).
export const SKILLS = {
  // Lance infernale — projectile perforant, visée glissée ou auto (valeurs inchangées).
  lance: {
    name: 'Lance infernale', kind: 'lance', text: 'Projectile qui transperce 3 ennemis.', cost: 0,
    cooldown: 4.0, damage: 30, speed: 900, radius: 12, range: 540, pierce: 3, knockback: 300, hitstop: 0.05, castTime: 0.08,
  },
  // Chaîne d'Enfer — crochet qui harponne le premier ennemi et le TIRE au contact du héros.
  chaine: {
    name: 'Chaîne d\'Enfer', kind: 'chain', icon: 'chain', cost: 35,
    text: 'Crochet qui harponne le premier ennemi touché, l\'étourdit et le tire contre vous.',
    cooldown: 5.0, castTime: 0.08, damage: 16, speed: 1150, radius: 12, range: 430, knockback: 0, hitstop: 0.06, stun: 0.7,
    pullGap: 14, // u laissées entre le héros et l'ennemi tiré
    pullMass: 2.5, // au-delà de cette masse, la traction faiblit (brutes, élites)
    recoil: 60,
  },
  // Bond du bourreau — saut invulnérable vers la cible ; l'atterrissage écrase la zone.
  bond: {
    name: 'Bond du bourreau', kind: 'bond', icon: 'leap', cost: 0,
    text: 'Saut invulnérable jusqu\'à 260 u ; l\'atterrissage écrase tout à 120 u et étourdit.',
    cooldown: 6.0, castTime: 0, range: 260, minRange: 60, leapTime: 0.3, iframesGrace: 0.08,
    radius: 120, damage: 34, knockback: 620, stun: 0.5, hitstop: 0.09, shake: 0.7,
  },
  // Brasier d'âmes — pot lancé (atterrit sur la cible visée) : impact, puis sol qui brûle.
  brasier: {
    name: 'Brasier d\'âmes', kind: 'brasier', icon: 'fire', cost: 40,
    text: 'Pot d\'âmes lancé jusqu\'à 380 u : impact de 20, puis le sol brûle 4 s (12 dégâts/s).',
    cooldown: 7.0, castTime: 0.1, range: 380, throwDist: 240, flight: 0.35,
    radius: 95, damage: 20, knockback: 160, hitstop: 0.04,
    duration: 4.0, tick: 0.25, burnDps: 12, burnRefresh: 0.6, // brûlure (statut) rafraîchie dans la zone
  },
  // Volée d'épines — éventail de 5 traits courts.
  volee: {
    name: 'Volée d\'épines', kind: 'volee', icon: 'fan', cost: 0,
    text: 'Éventail de 5 épines (14 dégâts chacune) ; à bout portant, tout touche.',
    cooldown: 3.5, castTime: 0.06, count: 5, spread: 50, speed: 1000, radius: 7, range: 460, pierce: 1,
    damage: 14, knockback: 260, hitstop: 0.04, recoil: 80,
  },
};

// ---------------------------------------------------------------- gadgets (charges par section)

// radius : zone utile (lue par les bots pour décider du moment).
export const GADGETS = {
  // Nova de cendres — onde qui repousse et étourdit (valeurs inchangées).
  nova: {
    name: 'Nova de cendres', kind: 'nova', text: 'Onde qui repousse, étourdit et efface les projectiles.', cost: 0,
    chargesPerSection: 3, chargeOnEliteKill: 1, radius: 150, damage: 20, knockback: 900, stun: 0.9, iframes: 0.25, hitstop: 0.07, shake: 0.4,
  },
  // Bombe de soufre — lancée sur l'ennemi visé, elle explose après une courte mèche.
  bombe: {
    name: 'Bombe de soufre', kind: 'bombe', icon: 'bomb', cost: 35,
    text: 'Lancée sur la cible : explose 0,25 s après l\'impact (45 dégâts à 120 u, étourdit).',
    chargesPerSection: 3, chargeOnEliteKill: 1, range: 320, throwDist: 220, flight: 0.4, fuse: 0.25,
    radius: 120, damage: 45, knockback: 700, stun: 0.6, hitstop: 0.08, shake: 0.55,
  },
  // Piège à mâchoires — posé aux pieds ; se referme sur le premier ennemi qui passe.
  piege: {
    name: 'Piège à mâchoires', kind: 'piege', icon: 'trap', cost: 0,
    text: 'Posé à vos pieds (3 au plus) : immobilise 1,6 s et inflige 30 dégâts au premier qui passe.',
    chargesPerSection: 4, chargeOnEliteKill: 1, radius: 44, blastRadius: 70, armTime: 0.3, life: 14, maxActive: 3,
    damage: 30, stun: 1.6, knockback: 0, hitstop: 0.06, shake: 0.25,
  },
  // Cri du bourreau — hurlement qui terrifie : étourdit et rend vulnérable, sans repousser
  // (les ennemis restent à portée de la hache). Un ennemi étourdi abandonne son attaque.
  cri: {
    name: 'Cri du bourreau', kind: 'cri', icon: 'roar', cost: 0,
    text: 'Hurlement à 200 u : étourdit 1,2 s et rend vulnérable (+30 % de dégâts subis, 4 s). Ne repousse pas.',
    chargesPerSection: 3, chargeOnEliteKill: 1, radius: 200, damage: 6, stun: 1.2, vuln: 4, vulnMult: 0.3,
    knockback: 0, iframes: 0.2, hitstop: 0.05, shake: 0.35,
  },
  // Totem de givre — posé aux pieds ; ralentit et blesse par impulsions.
  totem: {
    name: 'Totem de givre', kind: 'totem', icon: 'totem', cost: 45,
    text: 'Totem de 6 s : à 150 u, ralentit de 50 % et inflige 7 dégâts toutes les 0,5 s.',
    chargesPerSection: 3, chargeOnEliteKill: 1, radius: 150, life: 6, pulse: 0.5, damage: 7,
    chill: 0.7, chillMult: 0.5, knockback: 0, hitstop: 0,
  },
};

// ---------------------------------------------------------------- Supers (jauge remplie en frappant)

// Pendant tout Super, le héros est invulnérable (état 'super'). radius : portée utile (bots).
export const SUPERS = {
  // Colère — tourbillon invulnérable (valeurs inchangées).
  colere: {
    name: 'Colère', kind: 'colere', text: 'Tourbillon invulnérable de 1,4 s.',
    startCharge: 0.4, chargeDamage: 900, duration: 1.4, tickInterval: 0.12, radius: 130, damagePerTick: 9, knockback: 260, speedMult: 0.85, shakePerTick: 0.1,
  },
  // Sentence — trois exécutions auto-visées : deux taillades, puis un fracas à 360° qui étourdit.
  sentence: {
    name: 'Sentence', kind: 'sentence', icon: 'sentence',
    text: 'Invulnérable 1,5 s : deux taillades de 40, puis un fracas de 70 tout autour qui étourdit.',
    startCharge: 0.4, chargeDamage: 1000, duration: 1.5, speedMult: 0.6, radius: 160, aimRange: 220,
    strikes: [
      { at: 0.2, range: 160, arc: 200, damage: 40, knockback: 700, hitstop: 0.1, shake: 0.6 },
      { at: 0.6, range: 160, arc: 200, damage: 40, knockback: 700, hitstop: 0.1, shake: 0.6 },
      { at: 1.05, range: 190, arc: 360, damage: 70, knockback: 1000, stun: 0.8, hitstop: 0.14, shake: 1 },
    ],
  },
  // Nuée de traits — invulnérable et rapide, la Chasseresse arrose les ennemis proches.
  nuee: {
    name: 'Nuée de traits', kind: 'nuee', icon: 'rain',
    text: 'Invulnérable 1,6 s en courant (+15 % de vitesse) : un trait toutes les 0,09 s sur les 3 ennemis les plus proches.',
    startCharge: 0.4, chargeDamage: 1000, duration: 1.6, speedMult: 1.15, radius: 420,
    interval: 0.09, targets: 3, damage: 8, speed: 1300, shotRadius: 6, range: 560, pierce: 1, knockback: 150, hitstop: 0,
  },
};

// ---------------------------------------------------------------- classes

// stats : bonus permanents de la classe, ajoutés aux statistiques du héros (stats.mjs) ;
//   les clés en …Mult s'ajoutent au multiplicateur (moveSpeedMult -0.06 => ×0,94).
// passive : ce que le joueur lit en Ville (nom + effet chiffré, identique aux stats).
// weapons / skills / gadgets : ce que la classe peut équiper (le 1er = celui de départ).
export const CLASSES = {
  revenant: {
    name: 'Revenant', text: 'Damné en fuite. Lame équilibrée, dash vif : le kit de référence du feel.', cost: 0,
    passive: { name: 'Étalon', text: 'Aucun bonus : 100 PV, dash de 165 u, vitesse 300. Les autres classes se lisent par rapport à lui.' },
    stats: {},
    weapons: ['lame', 'dagues'],
    skills: ['lance', 'chaine'],
    gadgets: ['nova', 'bombe'],
    super: 'colere',
  },
  bourreau: {
    name: 'Bourreau', text: 'Exécuteur des Cercles. Coups lents et massifs, carcasse épaisse, dash court.', cost: 120,
    passive: { name: 'Carcasse de fer', text: '+40 PV max, 10 % d\'armure, recul infligé +25 % ; dash −20 % de distance, vitesse −6 %.' },
    stats: { maxHpBonus: 40, armor: 0.1, knockbackMult: 0.25, dashDistanceMult: -0.2, moveSpeedMult: -0.06 },
    weapons: ['hache', 'marteau'],
    skills: ['bond', 'chaine'],
    gadgets: ['cri', 'bombe'],
    super: 'sentence',
  },
  chasseresse: {
    name: 'Chasseresse', text: 'Traqueuse des Limbes. Elle tire à distance en se déplaçant et dashe loin ; fragile.', cost: 120,
    passive: { name: 'Pied léger', text: 'Dash +30 % de distance, vitesse +8 %, critique +5 % ; −20 PV max.' },
    stats: { dashDistanceMult: 0.3, moveSpeedMult: 0.08, critChance: 0.05, maxHpBonus: -20 },
    weapons: ['arc', 'arbalete'],
    skills: ['volee', 'brasier'],
    gadgets: ['piege', 'totem'],
    super: 'nuee',
  },
};

export const DEFAULT_LOADOUT = { classId: 'revenant', skillId: 'lance', gadgetId: 'nova' };
