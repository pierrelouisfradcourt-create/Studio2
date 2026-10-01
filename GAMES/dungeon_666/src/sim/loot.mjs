// Butin façon Diablo : raretés colorées, préfixes/suffixes, objets légendaires à pouvoir.
// Trois emplacements dans le prototype : arme, armure, talisman. L'équipement SURVIT à la
// mort (progression persistante) ; les bénédictions, elles, sont perdues.

import { rand, randInt, pick, shuffle, weightedPick } from '../core/rng.mjs';
import { newId } from './state.mjs';

// baseMult : multiplicateur de la valeur de base (dégâts d'arme, PV d'armure) par rareté.
export const ITEM_RARITIES = [
  { id: 'commun', name: 'Commun', color: '#d8d4cc', affixes: 1, baseMult: 1 },
  { id: 'magique', name: 'Magique', color: '#5a8cff', affixes: 2, baseMult: 1.08 },
  { id: 'rare', name: 'Rare', color: '#ffd23c', affixes: 3, baseMult: 1.16 },
  { id: 'legendaire', name: 'Légendaire', color: '#ff8a1e', affixes: 3, baseMult: 1.25 },
];
const ITEM_LEVEL_GROWTH = 0.05; // valeur de base +5 % par étage (niveau d'objet = étage)

export const SLOTS = ['arme', 'armure', 'talisman'];
export const SLOT_NAMES = { arme: 'Arme', armure: 'Armure', talisman: 'Talisman' };

const BASES = {
  arme: ['Lame', 'Hache', 'Fauchon', 'Glaive'],
  armure: ['Cuirasse', 'Haubert', 'Brigandine', 'Robe'],
  talisman: ['Amulette', 'Anneau', 'Sceau', 'Relique'],
};

// [stat, min, max, préfixe, suffixe, format] — valeurs de l'étage 1, mises à l'échelle.
// format : 'pct' (affiché en %), 'pctNeg' (réduction affichée en %), 'flat'.
const AFFIXES = {
  arme: [
    ['damageMult', 0.05, 0.12, 'cruel', 'du Carnage', 'pct'],
    ['attackSpeedMult', 0.06, 0.14, 'vif', 'de la Hâte', 'pct'],
    ['critChance', 0.03, 0.07, 'acéré', 'de Précision', 'pct'],
    ['critMult', 0.15, 0.4, 'sanglant', 'du Bourreau', 'pct'],
    ['skillDamageMult', 0.1, 0.25, 'runique', 'de la Lance', 'pct'],
    ['knockbackMult', 0.1, 0.3, 'lourd', 'du Bélier', 'pct'],
  ],
  armure: [
    ['maxHpBonus', 10, 25, 'robuste', 'du Colosse', 'flat'],
    ['armor', 0.04, 0.09, 'clouté', 'du Rempart', 'pct'],
    ['moveSpeedMult', 0.04, 0.08, 'léger', 'du Vent', 'pct'],
    ['healOnKill', 1, 2, 'vorace', 'du Charognard', 'flat'],
  ],
  talisman: [
    ['dashRechargeMult', -0.18, -0.08, 'fuyant', 'de l\'Ombre', 'pctNeg'],
    ['skillCooldownMult', -0.18, -0.08, 'savant', 'de l\'Érudit', 'pctNeg'],
    ['superChargeMult', 0.1, 0.25, 'furieux', 'de la Rage', 'pct'],
    ['goldFindMult', 0.15, 0.35, 'doré', 'de Mammon', 'pct'],
    ['lifesteal', 0.01, 0.03, 'vampirique', 'du Sang', 'pct'],
    ['critChance', 0.02, 0.05, 'chanceux', 'du Destin', 'pct'],
  ],
};

export const STAT_LABELS = {
  damageMult: 'dégâts',
  attackSpeedMult: 'vitesse d\'attaque',
  critChance: 'chances de critique',
  critMult: 'dégâts critiques',
  skillDamageMult: 'dégâts de la Lance',
  knockbackMult: 'recul infligé',
  maxHpBonus: 'PV max',
  armor: 'réduction des dégâts',
  moveSpeedMult: 'vitesse de course',
  healOnKill: 'PV par ennemi tué',
  dashRechargeMult: 'recharge du dash',
  skillCooldownMult: 'recharge de la Lance',
  superChargeMult: 'charge du Super',
  goldFindMult: 'or trouvé',
  lifesteal: 'vol de vie',
};

// Pouvoirs légendaires : un effet qui change la façon de jouer, pas juste un chiffre.
export const LEGENDARY_POWERS = [
  { id: 'ailes_mephisto', name: 'des Ailes de Méphisto', text: '+1 charge de dash', stats: { dashChargesBonus: 1 } },
  { id: 'coeur_braise', name: 'du Cœur de braise', text: 'Le dash explose en flammes (14 dégâts)', procs: [{ on: 'dash', effect: 'nova', radius: 85, value: 14 }] },
  { id: 'couronne_vorace', name: 'de la Couronne vorace', text: 'Chaque ennemi tué rend 3 PV', stats: { healOnKill: 3 } },
  { id: 'lame_azazel', name: 'd\'Azazel', text: '30 % de chances d\'éclair en chaîne (12 dégâts)', procs: [{ on: 'hit', sources: ['melee', 'strike'], effect: 'chain', chance: 0.3, value: 12, bounces: 2, range: 220 }] },
];

const FLOOR_SCALE = 0.012;

function roundStat(v, format) {
  return format === 'flat' ? Math.round(v) : Math.round(v * 1000) / 1000;
}

/** Tire une rareté ; `bonus` > 1 favorise les raretés hautes (élites, boss). */
export function rollRarity(game, bonus = 1) {
  const w = game.tuning.loot.rarityWeights;
  const r = weightedPick(game.rng.gen, ITEM_RARITIES, (x) => (x.id === 'commun' ? w[x.id] : w[x.id] * bonus));
  return r.id;
}

export function generateItem(game, { slot, rarity, floor } = {}) {
  const s = slot ?? pick(game.rng.gen, SLOTS);
  const rar = rarity ?? rollRarity(game);
  const rdef = ITEM_RARITIES.find((r) => r.id === rar);
  const lvl = floor ?? game.run.floor;
  const scale = 1 + FLOOR_SCALE * (lvl - 1);
  const pool = shuffle(game.rng.gen, AFFIXES[s].slice());
  const affixes = pool.slice(0, rdef.affixes).map(([stat, lo, hi, prefix, suffix, format]) => {
    const raw = lo + rand(game.rng.gen) * (hi - lo);
    const value = roundStat(format === 'flat' ? raw * scale : raw * Math.sqrt(scale), format);
    return { stat, value, prefix, suffix, format };
  });
  const base = pick(game.rng.gen, BASES[s]);
  let name = base;
  if (affixes[0]) name = `${base} ${affixes[0].prefix}`;
  if (affixes[1]) name = `${name} ${affixes[1].suffix}`;
  let power = null;
  if (rar === 'legendaire') {
    power = pick(game.rng.gen, LEGENDARY_POWERS).id;
    name = `${base} ${LEGENDARY_POWERS.find((p) => p.id === power).name}`;
  }
  const item = { id: newId(game), slot: s, rarity: rar, name, level: lvl, affixes, power, base: baseValues(game, s, lvl, rdef.baseMult) };
  item.score = itemScore(item);
  return item;
}

function baseValues(game, slot, level, mult) {
  const growth = 1 + ITEM_LEVEL_GROWTH * (level - 1);
  if (slot === 'arme') return { damage: Math.round(game.tuning.weaponBase * growth * mult * 10) / 10 };
  if (slot === 'armure') return { hp: Math.round(game.tuning.armorBase * growth * mult) };
  return {};
}

/** Équipement de départ : arme et armure communes, sans affixe. */
export function starterItems(game) {
  return {
    arme: { id: newId(game), slot: 'arme', rarity: 'commun', name: 'Épée rouillée', level: 1, affixes: [], power: null, base: { damage: game.tuning.weaponBase }, score: 0 },
    armure: { id: newId(game), slot: 'armure', rarity: 'commun', name: 'Haillons de pèlerin', level: 1, affixes: [], power: null, base: { hp: game.tuning.armorBase }, score: 0 },
    talisman: null,
  };
}

/** Score grossier de puissance (comparaison « mieux / moins bien » dans l'interface). */
export function itemScore(item) {
  let s = 0;
  if (item.base?.damage) s += item.base.damage / 2;
  if (item.base?.hp) s += item.base.hp / 12;
  for (const a of item.affixes) s += a.format === 'flat' ? a.value / 25 : Math.abs(a.value) * 8;
  if (item.power) s += 2;
  return Math.round(s * 100) / 100;
}

export function salvageValue(item) {
  const idx = ITEM_RARITIES.findIndex((r) => r.id === item.rarity);
  return 5 + idx * 10 + Math.floor(item.level / 3);
}

export function baseText(item) {
  if (item.base?.damage) return `Dégâts de l'arme : ${item.base.damage}`;
  if (item.base?.hp) return `PV de l'armure : ${item.base.hp}`;
  return null;
}

export function affixText(a) {
  const label = STAT_LABELS[a.stat] ?? a.stat;
  if (a.format === 'flat') return `+${a.value} ${label}`;
  if (a.format === 'pctNeg') return `${Math.round(a.value * 100)} % ${label}`;
  return `+${Math.round(a.value * 1000) / 10} % ${label}`;
}

export function randomShopItem(game) {
  const rarity = rand(game.rng.gen) < 0.25 ? 'rare' : 'magique';
  return generateItem(game, { rarity });
}

export function priceOf(game, item) {
  const [lo, hi] = game.tuning.economy.shopItemPrice;
  const idx = ITEM_RARITIES.findIndex((r) => r.id === item.rarity);
  return Math.round(lo + ((hi - lo) * idx) / (ITEM_RARITIES.length - 1)) + randInt(game.rng.gen, 0, 9);
}
