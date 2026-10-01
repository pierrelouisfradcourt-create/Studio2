// Recettes sonores de Dungeon 666 — la « fiche de sound design » du prototype.
//
// Chaque son est d'abord une TABLE de couches (données, en tête de fichier), puis une petite
// fonction qui choisit les couches et leur intensité d'après l'événement. Les fréquences sont
// en Hz, les durées en secondes, les gains relatifs (le niveau de mixage par son est dans
// sfx.mjs). Rien ici ne lit la simulation : seulement les champs de l'événement reçu.
//
// Signature commune : recipe(voice, p) avec p = { ev, pitch, gain, heavy }
//   ev    : l'événement représentatif du groupe (champs de sim, lecture seule)
//   pitch : multiplicateur de hauteur (variation aléatoire légère déjà appliquée)
//   gain  : multiplicateur d'intensité (regroupement de plusieurs événements identiques)
//   heavy : coup lourd (3e coup du combo ou frappe de dash) — calculé par sfx.mjs

import { clamp, lerp } from '../core/math.mjs';
import { perc, adsr, playLayers, finite } from './synth.mjs';

// ---------------------------------------------------------------- outillage des tables

/** Couche tonale (forme d'onde `type`, glissando freq -> to ; to = null : hauteur fixe). */
function osc(type, freq, to, env, gain, more) {
  return { src: 'tone', type, freq, to, env, gain, ...more };
}

/** Couche de bruit filtré (`filter` : lowpass | highpass | bandpass). */
function hiss(filter, freq, to, q, env, gain, more) {
  return { src: 'noise', type: filter, freq, to, q, env, gain, ...more };
}

/**
 * Lecture d'une table par un champ d'événement, PROPRE seulement : un champ valant
 * 'constructor', 'toString'… ne doit jamais remonter le prototype d'Object.
 */
function lookup(table, key, fallback) {
  return Object.prototype.hasOwnProperty.call(table, key) ? table[key] : fallback;
}

const SEMITONES_PER_OCTAVE = 12;
const semis = (f, n) => f * 2 ** (n / SEMITONES_PER_OCTAVE);

// Notes de référence (Hz).
const NOTE = {
  G2: 98.0, C3: 130.81, E3: 164.81, G3: 196.0, C4: 261.63, A4: 440.0,
  C5: 523.25, E5: 659.26, G5: 783.99, B5: 987.77, C6: 1046.5, E6: 1318.51, A6: 1760.0,
};

/** Accord arpégé : une couche par intervalle (demi-tons au-dessus de `root`), décalées de `step`. */
function chord(type, root, intervals, step, env, gain, more) {
  return intervals.map((n, i) => osc(type, semis(root, n), null, env, gain, { at: i * step, ...more }));
}

/** Cloche : partiels inharmoniques d'une même fondamentale, extinctions décroissantes. */
function bell(root, partials, at, release, gain) {
  return partials.map(([ratio, g]) => osc('sine', root * ratio, null, perc(0.002, release / Math.sqrt(ratio)), gain * g, { at }));
}

const MAJOR = [0, 4, 7, 12];
const MAJOR_TRIAD = [0, 4, 7];
const FIFTH = [0, 7];
const MINOR_TRIAD = [0, 3, 7];
const BELL_PARTIALS = [[1, 1], [2, 0.5], [2.4, 0.3], [3, 0.2], [4.2, 0.12]];
const METAL_PARTIALS = [[1, 1], [2.32, 0.45], [4.25, 0.25]];

// ---------------------------------------------------------------- combat du héros

// Index de combo 0 et 1 : coups vifs en miroir ; 2 : coup final ample et grave.
const SWING_COMBO = [
  [hiss('bandpass', 900, 2600, 1.2, perc(0.012, 0.11), 0.55)],
  [hiss('bandpass', 1150, 3000, 1.2, perc(0.012, 0.1), 0.55)],
  [
    hiss('bandpass', 480, 2000, 0.9, perc(0.02, 0.2), 0.8),
    osc('sine', 150, 60, perc(0.005, 0.14), 0.45),
  ],
];
// Frappe de dash : souffle plus long + lame qui chante.
const SWING_STRIKE = [
  hiss('bandpass', 700, 3400, 1.6, perc(0.015, 0.16), 0.75),
  osc('triangle', 1500, 900, perc(0.004, 0.18), 0.12),
];

// Impact : coup sourd + clic. Les variantes s'AJOUTENT au corps.
const HIT_BODY = [
  osc('sine', 165, 55, perc(0.002, 0.11), 0.9),
  hiss('highpass', 3500, null, 0.7, perc(0.001, 0.02), 0.45),
  hiss('bandpass', 900, 400, 1.2, perc(0.002, 0.05), 0.35),
];
const HIT_HEAVY = [
  osc('sine', 95, 38, perc(0.003, 0.2), 0.8),
  hiss('lowpass', 600, 150, 0.8, perc(0.003, 0.12), 0.5),
];
// Critique : partiels aigus cristallins, hauteur indépendante de la force du coup.
const HIT_CRIT = [
  osc('sine', 2637, null, perc(0.001, 0.22), 0.2),
  osc('sine', 3951, null, perc(0.001, 0.15), 0.12),
  osc('triangle', 5274, null, perc(0.001, 0.08), 0.06),
];
const HIT_LIGHT_AMOUNT = 8; // dégâts d'un coup « léger » (aigu, discret)
const HIT_HEAVY_AMOUNT = 40; // dégâts d'un coup « énorme » (grave, fort)
const HIT_PITCH_RANGE = [1.15, 0.72]; // léger -> énorme
const HIT_GAIN_RANGE = [0.6, 1.25];
// Timbre de la cible : les grosses bêtes sonnent plus grave. Les événements hit / kill portent
// le TYPE réel de l'ennemi (e.kind) : le boss y vaut 'gardien' (config.boss), jamais 'boss'.
const BOSS_PITCH = 0.7;
const ENEMY_PITCH = { imp: 1.1, archer: 1.05, exploder: 1.15, charger: 0.92, brute: 0.8, gardien: BOSS_PITCH, boss: BOSS_PITCH };

const KILL_BASE = [
  hiss('bandpass', 2200, null, 1.4, perc(0.001, 0.06), 1.4),
  osc('square', 260, 70, perc(0.002, 0.09), 0.45, { filter: { type: 'lowpass', freq: 1500 } }),
  hiss('lowpass', 900, 200, 0.8, perc(0.003, 0.18), 1),
];
const KILL_ELITE = [
  osc('sine', 80, 40, perc(0.005, 0.35), 0.7),
  hiss('bandpass', 1200, 300, 1, perc(0.005, 0.3), 0.35),
];
const KILL_BOSS = [
  osc('sine', 60, 25, perc(0.01, 1.4), 1),
  hiss('lowpass', 1200, 80, 0.7, perc(0.01, 1.6), 0.8),
  osc('sawtooth', 110, 40, perc(0.02, 1.2), 0.25, { drive: true, filter: { type: 'lowpass', freq: 700, to: 200 } }),
];

const BURN = [hiss('highpass', 2500, 4000, 0.7, perc(0.002, 0.04), 0.4)];

const DASH = [
  hiss('bandpass', 350, 2600, 0.9, adsr(0.03, 0.05, 0.6, 0.04, 0.09), 0.65),
  osc('sine', 180, 420, perc(0.02, 0.12), 0.12),
];

// Esquive « parfaite » : arpège très aigu + poussière d'étoiles.
const DODGE = [
  osc('sine', NOTE.A6, null, perc(0.002, 0.12), 0.22),
  osc('sine', semis(NOTE.A6, 5), null, perc(0.002, 0.12), 0.2, { at: 0.03 }),
  osc('sine', semis(NOTE.A6, 10), null, perc(0.002, 0.18), 0.18, { at: 0.06 }),
  hiss('highpass', 7000, null, 0.7, perc(0.005, 0.12), 0.12),
];

// Lance infernale : sifflement montant + air + poussée de flamme.
const SKILL = [
  osc('sine', 900, 2400, adsr(0.01, 0.05, 0.7, 0.06, 0.12), 0.22, { glide: 0.18, vibrato: { rate: 18, cents: 25 } }),
  osc('sine', 1800, 4800, perc(0.01, 0.15), 0.05, { glide: 0.18 }),
  hiss('bandpass', 2500, 6000, 2, perc(0.01, 0.2), 0.35),
  hiss('lowpass', 600, null, 0.8, perc(0.005, 0.12), 0.3),
];

// Nova de cendres : onde grave + souffle qui retombe.
const GADGET = [
  osc('sine', 85, 42, perc(0.005, 0.5), 1),
  hiss('bandpass', 1600, 250, 0.8, adsr(0.02, 0.1, 0.5, 0.1, 0.3), 0.6),
  osc('triangle', 170, 85, perc(0.005, 0.25), 0.25),
];
const DASH_NOVA_PITCH = 1.2; // la nova de dash (bénédiction) : petite sœur du gadget
const DASH_NOVA_GAIN = 0.55;

// Super « Colère » : impact immédiat (aucune latence) puis montée puissante.
const SUPER = [
  osc('sine', 90, 40, perc(0.003, 0.4), 0.9),
  hiss('lowpass', 900, null, 0.8, perc(0.003, 0.35), 0.6),
  osc('sawtooth', 110, 440, adsr(0.05, 0.2, 0.8, 0.25, 0.4), 0.22, { glide: 0.55, drive: true, filter: { type: 'lowpass', freq: 300, to: 3200 } }),
  osc('sawtooth', 165, 660, adsr(0.05, 0.2, 0.8, 0.25, 0.4), 0.14, { glide: 0.55, detune: 8, filter: { type: 'lowpass', freq: 300, to: 3200 } }),
  osc('sine', 55, null, adsr(0.3, 0.2, 0.8, 0.2, 0.5), 0.6),
  hiss('highpass', 400, 4000, 0.7, adsr(0.3, 0.05, 0.6, 0.1, 0.3), 0.25),
];
const SUPER_TICK = [hiss('bandpass', 900, 1600, 1.5, perc(0.01, 0.07), 0.5)];
const SUPER_END = [
  hiss('bandpass', 1600, 400, 1, perc(0.01, 0.25), 0.3),
  osc('sine', 220, 110, perc(0.01, 0.2), 0.1),
];
const SUPER_READY = [
  ...chord('triangle', NOTE.A4, MAJOR, 0.025, perc(0.005, 0.35), 0.16),
  osc('sine', semis(NOTE.A6, 12), null, perc(0.002, 0.2), 0.05, { at: 0.08 }),
];

// ---------------------------------------------------------------- kits (classes, armes, aptitudes)
// Mêmes événements que le kit d'origine (swing, skill, gadget, super, superTick, explode) :
// le champ ajouté par la sim (ranged / weapon, skill, gadget, super, kind) choisit le timbre.

// Arc : corde pincée + souffle bref ; arbalète (et trait lourd) : déclic sec et plus grave.
const SHOOT_BOW = [
  osc('triangle', 520, 190, perc(0.002, 0.09), 0.35),
  hiss('bandpass', 2400, 5200, 2, perc(0.004, 0.07), 0.45),
];
const SHOOT_HEAVY = [
  osc('square', 210, 90, perc(0.002, 0.07), 0.3, { filter: { type: 'lowpass', freq: 1600 } }),
  hiss('bandpass', 1500, 4200, 1.6, perc(0.003, 0.1), 0.6),
  hiss('highpass', 4000, null, 0.7, perc(0.001, 0.02), 0.35),
];
const HEAVY_WEAPONS = { arbalete: true };

const SKILL_STYLES = {
  // Chaîne d'Enfer : cliquetis de maillons qui file.
  chain: [
    hiss('bandpass', 3200, 1800, 3, perc(0.003, 0.18), 0.5),
    ...bell(880, METAL_PARTIALS, 0, 0.18, 0.12),
    osc('square', 300, 520, perc(0.004, 0.12), 0.08, { filter: { type: 'lowpass', freq: 2200 } }),
  ],
  // Bond : élan grave qui monte.
  bond: [
    hiss('bandpass', 300, 1400, 0.8, adsr(0.02, 0.05, 0.6, 0.08, 0.2), 0.7),
    osc('sine', 120, 260, perc(0.01, 0.2), 0.25),
  ],
  // Brasier d'âmes : pot qui siffle en l'air.
  brasier: [
    osc('sine', 700, 1500, adsr(0.01, 0.05, 0.6, 0.05, 0.2), 0.15, { glide: 0.3 }),
    hiss('bandpass', 1200, 2600, 1.4, perc(0.01, 0.2), 0.35),
  ],
  // Volée d'épines : rafale de souffles aigus.
  volee: [
    hiss('bandpass', 2600, 5800, 2, perc(0.004, 0.08), 0.45),
    hiss('bandpass', 2200, 5000, 2, perc(0.004, 0.08), 0.35, { at: 0.025 }),
    hiss('bandpass', 3000, 6200, 2, perc(0.004, 0.08), 0.3, { at: 0.05 }),
  ],
};

const GADGET_STYLES = {
  // Bombe : lancer (souffle) — l'explosion vient avec `explode`.
  bombe: [hiss('bandpass', 600, 1800, 1, perc(0.01, 0.16), 0.5), osc('sine', 220, 140, perc(0.005, 0.12), 0.15)],
  // Piège : déclic métallique d'armement.
  piege: [...bell(1240, METAL_PARTIALS, 0, 0.16, 0.2), hiss('highpass', 4500, null, 0.7, perc(0.001, 0.02), 0.3)],
  // Cri du bourreau : rugissement grave, saturé.
  cri: [
    osc('sawtooth', 110, 70, adsr(0.02, 0.1, 0.7, 0.15, 0.35), 0.3, { drive: true, filter: { type: 'lowpass', freq: 900, to: 300 } }),
    hiss('bandpass', 500, 250, 0.9, adsr(0.02, 0.1, 0.6, 0.15, 0.3), 0.5),
  ],
  // Totem de givre : carillon cristallin.
  totem: [...bell(NOTE.E6, BELL_PARTIALS, 0, 0.5, 0.12), osc('sine', NOTE.B5, null, perc(0.005, 0.4), 0.08, { at: 0.05 })],
};

const SUPER_STYLES = {
  // Sentence : coup de gong grave, puis la lame qui se lève.
  sentence: [
    ...bell(NOTE.G2, BELL_PARTIALS, 0, 1.4, 0.5),
    osc('sawtooth', 70, 140, adsr(0.05, 0.2, 0.7, 0.3, 0.5), 0.2, { drive: true, filter: { type: 'lowpass', freq: 400, to: 1800 } }),
  ],
  // Nuée : montée scintillante.
  nuee: [
    ...chord('triangle', NOTE.E5, MAJOR, 0.03, perc(0.005, 0.4), 0.1),
    hiss('highpass', 3000, 7000, 0.7, adsr(0.1, 0.1, 0.6, 0.2, 0.4), 0.2),
  ],
};
const SUPER_TICK_STYLES = {
  // Exécution de la Sentence : choc lourd.
  sentence: [osc('sine', 85, 35, perc(0.003, 0.35), 0.9), hiss('lowpass', 1200, 200, 0.8, perc(0.003, 0.25), 0.6)],
  // Trait de la Nuée : pincement bref.
  nuee: [osc('triangle', 900, 400, perc(0.002, 0.05), 0.2), hiss('bandpass', 3500, null, 2, perc(0.002, 0.04), 0.25)],
};

const DEFLECT = [
  ...bell(1480, METAL_PARTIALS, 0, 0.3, 0.25),
  hiss('highpass', 5000, null, 0.7, perc(0.001, 0.015), 0.25),
];

const CHAIN_BUZZ = [
  osc('sawtooth', 90, null, perc(0.002, 0.09), 0.15, { filter: { type: 'bandpass', freq: 2500, q: 2 } }),
  osc('square', 1800, 600, perc(0.001, 0.05), 0.05),
];
const CHAIN_SPARK = hiss('highpass', 3000, null, 0.7, perc(0.0005, 0.012), 1);
const CHAIN_SPARKS = 5; // crépitements par éclair, à instants aléatoires
const CHAIN_SPARK_WINDOW = 0.08; // s
const CHAIN_SPARK_GAIN = [0.25, 0.55];

// ---------------------------------------------------------------- héros touché

const HURT = [
  osc('sine', 120, 55, perc(0.003, 0.25), 0.9),
  osc('sawtooth', 200, 90, perc(0.003, 0.18), 0.35, { drive: true, filter: { type: 'lowpass', freq: 1400 } }),
  hiss('lowpass', 1000, null, 0.8, perc(0.001, 0.08), 0.5),
];
const HURT_REF_AMOUNT = 30; // dégâts d'un coup qui fait vraiment mal
const HURT_GAIN_RANGE = [0.8, 1.2];

const DEATH = [
  osc('sawtooth', 220, 38, adsr(0.01, 0.2, 0.7, 0.4, 0.9), 0.35, { glide: 1.4, drive: true, filter: { type: 'lowpass', freq: 2200, to: 180 } }),
  osc('sine', 70, 28, perc(0.005, 1.3), 0.9),
  hiss('lowpass', 1500, 100, 0.7, perc(0.01, 1.2), 0.5),
  osc('triangle', 440, 110, perc(0.02, 0.9), 0.12, { at: 0.15 }),
];

// ---------------------------------------------------------------- ennemis et dangers

// Télégraphes : petits cris discrets, un timbre par type d'ennemi.
const ENEMY_ATTACK = {
  imp: [osc('square', 650, 1050, perc(0.005, 0.08), 0.45, { filter: { type: 'lowpass', freq: 2000 } })],
  archer: [
    osc('triangle', 330, 620, perc(0.004, 0.12), 0.6),
    hiss('bandpass', 1800, null, 3, perc(0.002, 0.04), 0.3),
  ],
  brute: [
    osc('sawtooth', 95, 70, adsr(0.04, 0.1, 0.6, 0.1, 0.15), 0.4, { drive: true, filter: { type: 'lowpass', freq: 450 } }),
    hiss('lowpass', 350, null, 0.8, perc(0.05, 0.25), 0.3),
  ],
  charger: [
    hiss('bandpass', 600, 300, 2, perc(0.02, 0.2), 0.7),
    osc('sawtooth', 150, 110, perc(0.02, 0.18), 0.3, { filter: { type: 'lowpass', freq: 700 } }),
  ],
  boss: [
    osc('sawtooth', 75, 58, adsr(0.05, 0.1, 0.7, 0.15, 0.25), 0.5, { drive: true, filter: { type: 'lowpass', freq: 520 } }),
    hiss('lowpass', 400, null, 0.8, perc(0.05, 0.4), 0.35),
  ],
  bossRing: [
    osc('sine', 280, 900, adsr(0.08, 0.1, 0.8, 0.1, 0.15), 0.15, { glide: 0.35 }),
    osc('triangle', 560, 1800, adsr(0.08, 0.1, 0.8, 0.1, 0.15), 0.06, { glide: 0.35 }),
  ],
  // Gardiens ajoutés (champ `enemy` de enemyAttack) : un timbre par modèle.
  cerbere: [ // aboiement rauque : bruit grave + carré qui chute
    hiss('bandpass', 700, 260, 2.5, perc(0.01, 0.22), 0.7),
    osc('square', 210, 120, perc(0.01, 0.2), 0.3, { filter: { type: 'lowpass', freq: 900 } }),
  ],
  minos: [ // coup de marteau du Juge : cloche sombre
    ...bell(NOTE.G2, BELL_PARTIALS, 0, 0.6, 0.35),
    hiss('bandpass', 1500, null, 2, perc(0.001, 0.04), 0.2),
  ],
  colosse: [ // grondement d'effort : très grave, saturé
    osc('sawtooth', 55, 42, adsr(0.06, 0.12, 0.7, 0.2, 0.3), 0.55, { drive: true, filter: { type: 'lowpass', freq: 380 } }),
    hiss('lowpass', 300, null, 0.8, perc(0.06, 0.45), 0.4),
  ],
  default: [osc('square', 500, 700, perc(0.005, 0.06), 0.1, { filter: { type: 'lowpass', freq: 1500 } })],
};

// Explosion / zone qui frappe : boum basse fréquence + craquement.
const BOOM = [
  osc('sine', 95, 32, perc(0.004, 0.45), 1),
  hiss('lowpass', 1100, 120, 0.7, perc(0.003, 0.4), 0.7),
  hiss('bandpass', 2500, null, 1, perc(0.001, 0.03), 0.3),
];
const BOOM_FIRE = [hiss('highpass', 1800, 3500, 0.7, adsr(0.01, 0.05, 0.4, 0.1, 0.25), 0.25)];
const BOOM_REF_RADIUS = 100; // u : rayon d'une explosion « standard »
const BOOM_SIZE_RANGE = [0.6, 1.6];
// Style par type de zone (hazard.kind) : hauteur, gain, couche de feu.
const HAZARD_STYLE = {
  brute: { pitch: 0.9, gain: 0.9, fire: false },
  bossSlam: { pitch: 0.75, gain: 1.15, fire: false },
  fireBlast: { pitch: 1, gain: 1, fire: true },
  sinBlast: { pitch: 1.3, gain: 0.6, fire: true },
  exploder: { pitch: 1, gain: 1, fire: true },
  // Gardiens ajoutés : nombreuses zones à la fois, donc plus discrètes une à une (le mixage
  // de sfx.mjs regroupe les impacts d'une même image).
  cerbereLand: { pitch: 0.85, gain: 1, fire: false },
  cerbereShock: { pitch: 0.95, gain: 0.8, fire: false },
  cerbereFlame: { pitch: 1.15, gain: 0.7, fire: true },
  cerbereFire: { pitch: 1.2, gain: 0.6, fire: true },
  minosSentence: { pitch: 1.3, gain: 0.55, fire: false },
  minosTile: { pitch: 1.4, gain: 0.5, fire: false },
  minosSeal: { pitch: 0.9, gain: 0.9, fire: false },
  colosseFist: { pitch: 0.7, gain: 1.2, fire: false },
  colosseQuake: { pitch: 0.65, gain: 0.9, fire: false },
  colosseRock: { pitch: 0.8, gain: 0.8, fire: false },
  colosseEmber: { pitch: 1.3, gain: 0.35, fire: true },
  // Zones du héros (explode{hero, kind}) : sans crépitement de feu (le feu = les ennemis).
  bombe: { pitch: 0.85, gain: 1.1, fire: false },
  piege: { pitch: 1.4, gain: 0.6, fire: false },
  bond: { pitch: 0.7, gain: 1.1, fire: false },
  brasier: { pitch: 1.2, gain: 0.55, fire: false },
};

const HAZARD_CANCEL = [
  hiss('highpass', 2000, 800, 0.7, perc(0.005, 0.15), 0.2),
  osc('sine', 600, 300, perc(0.005, 0.12), 0.05),
];

// Projeté contre un mur / bélier qui s'écrase : choc lourd.
const SLAM = [
  osc('sine', 75, 32, perc(0.003, 0.3), 1),
  hiss('lowpass', 600, 150, 0.8, perc(0.002, 0.18), 0.7),
  hiss('bandpass', 1800, null, 1, perc(0.001, 0.025), 0.35),
];
const SLAM_BOSS_PITCH = 0.8;
const SLAM_BOSS_GAIN = 1.2;

const SPAWN_WARN = [
  osc('sine', 330, 520, adsr(0.08, 0.05, 0.6, 0.05, 0.15), 0.5),
  hiss('bandpass', 1200, null, 4, adsr(0.08, 0.05, 0.6, 0.05, 0.15), 0.4),
];
const SPAWN_ELITE_PITCH = 0.8;
const SPAWN_ELITE_GAIN = 1.4;

const BOSS_ROAR = [
  osc('sawtooth', 85, 62, adsr(0.08, 0.15, 0.8, 0.5, 0.45), 0.45, { glide: 1, drive: true, tremolo: { rate: 28, depth: 0.3 }, filter: { type: 'lowpass', freq: 700, to: 400 } }),
  osc('sawtooth', 86.5, 63, adsr(0.08, 0.15, 0.8, 0.5, 0.45), 0.35, { glide: 1, filter: { type: 'lowpass', freq: 700, to: 400 } }),
  hiss('lowpass', 500, null, 0.8, adsr(0.1, 0.2, 0.7, 0.4, 0.5), 0.5),
  osc('sine', 45, null, perc(0.01, 1.2), 0.8),
];
const BOSS_SUMMON = [
  osc('sawtooth', 140, 100, adsr(0.05, 0.1, 0.6, 0.15, 0.25), 0.3, { drive: true, filter: { type: 'lowpass', freq: 800 } }),
  hiss('bandpass', 800, 300, 1, perc(0.03, 0.35), 0.3),
];

// ---------------------------------------------------------------- butin et progression

// Pièce : deux notes aiguës (mi puis la).
const COIN = [
  osc('triangle', NOTE.E6, null, perc(0.002, 0.07), 0.25),
  osc('square', NOTE.E6, null, perc(0.002, 0.05), 0.04),
  osc('triangle', NOTE.A6, null, perc(0.002, 0.18), 0.25, { at: 0.06 }),
  osc('square', NOTE.A6, null, perc(0.002, 0.1), 0.04, { at: 0.06 }),
];
const COIN_BUY = [osc('triangle', NOTE.B5, null, perc(0.002, 0.25), 0.2, { at: 0.12 })];

const HEAL = [
  ...chord('sine', NOTE.C5, MAJOR_TRIAD, 0.06, adsr(0.03, 0.05, 0.6, 0.05, 0.25), 0.14, { vibrato: { rate: 6, cents: 8 } }),
  hiss('highpass', 6000, null, 0.7, adsr(0.05, 0.1, 0.5, 0.1, 0.2), 0.05),
];

// Bénédiction : accord majeur lumineux ; la rareté monte la tonalité et enrichit l'accord.
const BOON_ENV = adsr(0.01, 0.15, 0.5, 0.2, 0.6);
const BOON_STEP = 0.02; // s entre deux notes de l'accord
const BOON_NOTE_GAIN = 0.13;
const BOON_RARITY = {
  commun: { shift: 0, intervals: MAJOR },
  rare: { shift: 2, intervals: [...MAJOR, 16] },
  epique: { shift: 5, intervals: [...MAJOR, 14, 16, 19, 24] },
};
const BOON_CHORDS = Object.fromEntries(Object.entries(BOON_RARITY).map(([id, r]) => [
  id, chord('triangle', semis(NOTE.C5, r.shift), r.intervals, BOON_STEP, BOON_ENV, BOON_NOTE_GAIN),
]));
const BOON_SPARKLE = [
  osc('sine', semis(NOTE.C6, 12), null, perc(0.002, 0.4), 0.05, { at: 0.1 }),
  osc('sine', semis(NOTE.C6, 19), null, perc(0.002, 0.4), 0.04, { at: 0.14 }),
];

// Équipement : cliquetis métallique + cuir ; étincelles selon la rareté de l'objet.
const EQUIP = [
  hiss('bandpass', 2800, null, 3, perc(0.001, 0.06), 1),
  osc('square', 320, 260, perc(0.002, 0.08), 0.3, { filter: { type: 'lowpass', freq: 1800 } }),
  osc('triangle', 960, null, perc(0.002, 0.2), 0.25),
  hiss('lowpass', 500, null, 0.8, perc(0.01, 0.1), 0.6),
];
const EQUIP_SPARKLES = { commun: 0, magique: 1, rare: 2, legendaire: 3 };
const EQUIP_SPARKLE_NOTES = [NOTE.E6, NOTE.A6, semis(NOTE.A6, 4)];
const EQUIP_SPARKLE_START = 0.08; // s : après le cliquetis
const EQUIP_SPARKLE_STEP = 0.05;
const EQUIP_SPARKLE = osc('sine', NOTE.E6, null, perc(0.002, 0.3), 0.15);

// Salle nettoyée : cloche grave + accord ; boss : une quarte plus bas et plus long.
const ROOM_CLEAR_CHORD = chord('triangle', NOTE.C4, MAJOR_TRIAD, 0.04, adsr(0.02, 0.2, 0.5, 0.2, 0.6), 0.1, { at: 0.08 });
const ROOM_CLEAR_BELL = { root: NOTE.C3, release: 1.6, gain: 0.5 };
const ROOM_CLEAR_BOSS_BELL = { root: NOTE.G2, release: 2.6, gain: 0.6 };

const DOORS = [
  hiss('lowpass', 250, 700, 1, adsr(0.08, 0.1, 0.7, 0.25, 0.25), 0.5),
  osc('sine', 55, 50, adsr(0.05, 0.1, 0.8, 0.3, 0.3), 0.4),
  hiss('bandpass', 400, null, 1, perc(0.003, 0.1), 0.4, { at: 0.6 }),
];

const FLOOR_ENTER = [
  hiss('bandpass', 2000, 250, 0.7, adsr(0.05, 0.1, 0.6, 0.15, 0.3), 0.4),
  osc('sine', NOTE.G3, NOTE.G3 / 2, adsr(0.02, 0.1, 0.6, 0.2, 0.5), 0.25),
];
// Étage de boss : bourdon grave qui bat (deux saw désaccordées).
const FLOOR_BOSS_DRONE = [
  osc('sawtooth', 55, null, adsr(0.3, 0.2, 0.7, 0.6, 0.8), 0.18, { filter: { type: 'lowpass', freq: 300 } }),
  osc('sawtooth', 58.3, null, adsr(0.3, 0.2, 0.7, 0.6, 0.8), 0.18, { filter: { type: 'lowpass', freq: 300 } }),
];

const CHECKPOINT_STEP = 0.12;
const CHECKPOINT_NOTES = [NOTE.E5, NOTE.B5, semis(NOTE.E5, 12)];
const CHECKPOINT_BELL = { release: 1.4, gain: 0.18 };
const CHECKPOINT_PAD = [osc('sine', NOTE.E3, null, adsr(0.1, 0.3, 0.6, 0.5, 1), 0.2)];
const RESPAWN_GAIN = 0.7;

const GAME_OVER = [
  ...bell(NOTE.G2, BELL_PARTIALS, 0, 2.5, 0.6),
  ...chord('triangle', NOTE.G3, MINOR_TRIAD, 0.08, adsr(0.3, 0.3, 0.6, 0.6, 1.5), 0.06),
];

const DASH_READY = [osc('sine', 2200, null, perc(0.001, 0.03), 0.5)];
const CHOICE_OPEN = chord('triangle', NOTE.G5, FIFTH, 0.04, perc(0.005, 0.4), 0.08);

// ---------------------------------------------------------------- recettes

function swing(v, p) {
  const ev = p.ev;
  if (ev.ranged) {
    playLayers(v, ev.strike || lookup(HEAVY_WEAPONS, ev.weapon, false) ? SHOOT_HEAVY : SHOOT_BOW, p.pitch, p.gain);
    return;
  }
  const index = clamp(Math.round(finite(ev.index, 0)), 0, SWING_COMBO.length - 1);
  playLayers(v, ev.strike ? SWING_STRIKE : SWING_COMBO[index], p.pitch, p.gain);
}

function hit(v, p) {
  const ev = p.ev;
  const amount = finite(ev.amount, HIT_LIGHT_AMOUNT);
  const norm = clamp((amount - HIT_LIGHT_AMOUNT) / (HIT_HEAVY_AMOUNT - HIT_LIGHT_AMOUNT), 0, 1);
  const body = p.pitch * lerp(HIT_PITCH_RANGE[0], HIT_PITCH_RANGE[1], norm) * lookup(ENEMY_PITCH, ev.enemy, 1);
  const g = p.gain * lerp(HIT_GAIN_RANGE[0], HIT_GAIN_RANGE[1], norm);
  playLayers(v, HIT_BODY, body, g);
  if (p.heavy) playLayers(v, HIT_HEAVY, body, g);
  if (ev.crit) playLayers(v, HIT_CRIT, p.pitch, p.gain);
}

function burn(v, p) {
  playLayers(v, BURN, p.pitch, p.gain);
}

function kill(v, p) {
  playLayers(v, KILL_BASE, p.pitch * lookup(ENEMY_PITCH, p.ev.enemy, 1), p.gain);
  if (p.ev.elite) playLayers(v, KILL_ELITE, p.pitch, p.gain);
  if (p.ev.boss) playLayers(v, KILL_BOSS, p.pitch, p.gain);
}

function chain(v, p) {
  playLayers(v, CHAIN_BUZZ, p.pitch, p.gain);
  const rnd = v.eng.random;
  for (let i = 0; i < CHAIN_SPARKS; i++) {
    const spark = { ...CHAIN_SPARK, at: rnd() * CHAIN_SPARK_WINDOW, gain: lerp(CHAIN_SPARK_GAIN[0], CHAIN_SPARK_GAIN[1], rnd()) };
    playLayers(v, [spark], p.pitch, p.gain);
  }
}

function hurt(v, p) {
  const g = lerp(HURT_GAIN_RANGE[0], HURT_GAIN_RANGE[1], clamp(finite(p.ev.amount, 0) / HURT_REF_AMOUNT, 0, 1));
  playLayers(v, HURT, p.pitch, p.gain * g);
}

function enemyAttack(v, p) {
  playLayers(v, lookup(ENEMY_ATTACK, p.ev.enemy, ENEMY_ATTACK.default), p.pitch, p.gain);
}

/** Explosion (explode) ou zone qui frappe (hazardFire) : la taille règle hauteur et force. */
function boom(v, p) {
  const ev = p.ev;
  const style = lookup(HAZARD_STYLE, ev.kind, HAZARD_STYLE.exploder);
  const size = clamp(finite(ev.r, BOOM_REF_RADIUS) / BOOM_REF_RADIUS, BOOM_SIZE_RANGE[0], BOOM_SIZE_RANGE[1]);
  const k = (p.pitch * style.pitch) / Math.sqrt(size);
  const g = p.gain * style.gain * Math.sqrt(size);
  playLayers(v, BOOM, k, g);
  if (style.fire) playLayers(v, BOOM_FIRE, p.pitch, g);
}

function slam(v, p) {
  const boss = !!p.ev.boss;
  playLayers(v, SLAM, p.pitch * (boss ? SLAM_BOSS_PITCH : 1), p.gain * (boss ? SLAM_BOSS_GAIN : 1));
}

function spawnWarn(v, p) {
  const elite = !!p.ev.elite;
  playLayers(v, SPAWN_WARN, p.pitch * (elite ? SPAWN_ELITE_PITCH : 1), p.gain * (elite ? SPAWN_ELITE_GAIN : 1));
}

function dashNova(v, p) {
  playLayers(v, GADGET, p.pitch * DASH_NOVA_PITCH, p.gain * DASH_NOVA_GAIN);
}

function coin(v, p) {
  playLayers(v, COIN, p.pitch, p.gain);
  if (p.ev.type === 'buy') playLayers(v, COIN_BUY, p.pitch, p.gain);
}

function boonGain(v, p) {
  playLayers(v, lookup(BOON_CHORDS, p.ev.rarity, BOON_CHORDS.commun), p.pitch, p.gain);
  playLayers(v, BOON_SPARKLE, p.pitch, p.gain);
}

function equip(v, p) {
  playLayers(v, EQUIP, p.pitch, p.gain);
  const notes = EQUIP_SPARKLE_NOTES.slice(0, lookup(EQUIP_SPARKLES, p.ev.rarity, 0));
  const sparkles = notes.map((freq, i) => ({ ...EQUIP_SPARKLE, freq, at: EQUIP_SPARKLE_START + i * EQUIP_SPARKLE_STEP }));
  playLayers(v, sparkles, p.pitch, p.gain);
}

function roomClear(v, p) {
  const b = p.ev.boss ? ROOM_CLEAR_BOSS_BELL : ROOM_CLEAR_BELL;
  playLayers(v, bell(b.root, BELL_PARTIALS, 0, b.release, b.gain), p.pitch, p.gain);
  playLayers(v, ROOM_CLEAR_CHORD, p.pitch * (p.ev.boss ? b.root / ROOM_CLEAR_BELL.root : 1), p.gain);
}

function floorEnter(v, p) {
  playLayers(v, FLOOR_ENTER, p.pitch, p.gain);
  if (p.ev.isBoss) playLayers(v, FLOOR_BOSS_DRONE, 1, p.gain);
}

function checkpoint(v, p) {
  const g = p.gain * (p.ev.type === 'respawn' ? RESPAWN_GAIN : 1);
  CHECKPOINT_NOTES.forEach((f, i) => {
    playLayers(v, bell(f, METAL_PARTIALS, i * CHECKPOINT_STEP, CHECKPOINT_BELL.release, CHECKPOINT_BELL.gain), p.pitch, g);
  });
  playLayers(v, CHECKPOINT_PAD, p.pitch, g);
}

function victory(v, p) {
  roomClear(v, { ...p, ev: { boss: true } });
  boonGain(v, { ...p, ev: { rarity: 'epique' } });
}

/** Recette « à plat » : une table de couches jouée telle quelle. */
const flat = (layers) => (v, p) => playLayers(v, layers, p.pitch, p.gain);

/** Clé de son -> recette. Les clés sont attribuées aux événements par sfx.mjs. */
export const RECIPES = {
  swing, hit, burn, kill, chain, playerHurt: hurt, enemyAttack, boom, slam, spawnWarn,
  dashNova, coin, boonGain, equip, roomClear, floorEnter, checkpoint, victory,
  dash: flat(DASH),
  dodge: flat(DODGE),
  playerDeath: flat(DEATH),
  deflect: flat(DEFLECT),
  skill: (v, p) => playLayers(v, lookup(SKILL_STYLES, p.ev.skill, SKILL), p.pitch, p.gain),
  gadget: (v, p) => playLayers(v, lookup(GADGET_STYLES, p.ev.gadget, GADGET), p.pitch, p.gain),
  super: (v, p) => playLayers(v, lookup(SUPER_STYLES, p.ev.super, SUPER), p.pitch, p.gain),
  superTick: (v, p) => playLayers(v, lookup(SUPER_TICK_STYLES, p.ev.super, SUPER_TICK), p.pitch, p.gain),
  superEnd: flat(SUPER_END),
  superReady: flat(SUPER_READY),
  heal: flat(HEAL),
  doorsOpen: flat(DOORS),
  bossPhase: flat(BOSS_ROAR),
  bossSummon: flat(BOSS_SUMMON),
  hazardCancel: flat(HAZARD_CANCEL),
  gameOver: flat(GAME_OVER),
  dashReady: flat(DASH_READY),
  choiceOpen: flat(CHOICE_OPEN),
};
