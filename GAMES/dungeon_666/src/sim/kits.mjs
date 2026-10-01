// KITS DU HÉROS — classes, armes, compétences, gadgets, Supers (données de tuning).
//
// Le kit ÉQUIPÉ est « résolu » à la création de la partie (loadout.mjs) : les blocs
// actifs de la copie de tuning de la partie (`combo`, `dashStrike`, `skill`, `gadget`, `super`)
// deviennent des RÉFÉRENCES vers l'entrée choisie ici. Toute la simulation (et les tests)
// continue de lire `tuning.combo`, `tuning.skill`… : le Revenant armé de la Lame, avec la Lance,
// la Nova et la Colère, reproduit EXACTEMENT le kit d'avant les classes.
//
// Unités : comme config.mjs (u, s, degrés). `kind` choisit le code qui joue l'entrée.

// ---------------------------------------------------------------- armes (jeux de coups)

// Lame du Revenant : le combo historique (valeurs inchangées).
const LAME_COMBO = [
  { startup: 0.05, active: 0.07, recovery: 0.12, range: 84, arc: 140, damage: 10, knockback: 240, lunge: 36, hitstop: 0.04, shake: 0.2 },
  { startup: 0.05, active: 0.07, recovery: 0.12, range: 84, arc: 140, damage: 11, knockback: 240, lunge: 36, hitstop: 0.04, shake: 0.2 },
  { startup: 0.09, active: 0.09, recovery: 0.24, range: 104, arc: 220, damage: 22, knockback: 560, lunge: 64, hitstop: 0.085, shake: 0.45 },
];
const LAME_STRIKE = { startup: 0.04, active: 0.08, recovery: 0.16, range: 96, arc: 120, damage: 18, knockback: 420, lunge: 90, hitstop: 0.06, shake: 0.35 };

export const WEAPONS = {
  lame: {
    name: 'Lame du Revenant', kind: 'melee', className: 'revenant',
    text: 'Combo de 3 coups équilibré ; le 3e balaie large.',
    starterName: 'Épée rouillée', // exemplaire de départ / forgé en Ville
    bases: ['Lame', 'Fauchon', 'Glaive', 'Épée'], // noms des armes de ce type trouvées en donjon
    baseMult: 1, // dégâts de base W de ce type d'arme (× tuning.weaponBase)
    combo: LAME_COMBO,
    dashStrike: LAME_STRIKE,
  },
};

// ---------------------------------------------------------------- compétences (bouton Lance)

export const SKILLS = {
  // Lance infernale — projectile perforant, visée glissée ou auto (valeurs inchangées).
  lance: {
    name: 'Lance infernale', kind: 'lance', text: 'Projectile qui transperce 3 ennemis.',
    cooldown: 4.0, damage: 30, speed: 900, radius: 12, range: 540, pierce: 3, knockback: 300, hitstop: 0.05, castTime: 0.08,
  },
};

// ---------------------------------------------------------------- gadgets (charges par section)

export const GADGETS = {
  // Nova de cendres — onde qui repousse et étourdit (valeurs inchangées).
  nova: {
    name: 'Nova de cendres', kind: 'nova', text: 'Onde qui repousse, étourdit et efface les projectiles.',
    chargesPerSection: 3, chargeOnEliteKill: 1, radius: 150, damage: 20, knockback: 900, stun: 0.9, iframes: 0.25, hitstop: 0.07, shake: 0.4,
  },
};

// ---------------------------------------------------------------- Supers (jauge remplie en frappant)

export const SUPERS = {
  // Colère — tourbillon invulnérable (valeurs inchangées).
  colere: {
    name: 'Colère', kind: 'colere', text: 'Tourbillon invulnérable de 1,4 s.',
    startCharge: 0.4, chargeDamage: 900, duration: 1.4, tickInterval: 0.12, radius: 130, damagePerTick: 9, knockback: 260, speedMult: 0.85, shakePerTick: 0.1,
  },
};

// ---------------------------------------------------------------- classes

// stats : bonus permanents de la classe, ajoutés aux statistiques du héros (stats.mjs).
// weapons / skills / gadgets : ce que la classe peut équiper (le 1er = celui de départ).
export const CLASSES = {
  revenant: {
    name: 'Revenant', text: 'Damné en fuite. Lame équilibrée, dash vif : le kit de référence du feel.',
    stats: {},
    weapons: ['lame'],
    skills: ['lance'],
    gadgets: ['nova'],
    super: 'colere',
  },
};

export const DEFAULT_LOADOUT = { classId: 'revenant', skillId: 'lance', gadgetId: 'nova' };
