// Bénédictions infernales — les 7 péchés capitaux comme familles (équivalent des dieux de
// Hades). Une bénédiction est une DONNÉE : des modificateurs de stats et/ou des procs que
// combat.mjs interprète. Emplacements exclusifs (attack, dash, skill) : une nouvelle
// bénédiction du même emplacement remplace l'ancienne. Les passifs s'empilent.
//
// Rareté : commun ×1, rare ×1,4, épique ×1,8 sur les valeurs.
//
// Contenu du 2026-10-01 : deux bénédictions de plus par famille, branchées sur les moments du
// combat (esquive parfaite, dernier coup du combo, frappe de dash, mur, Super, salle sans
// blessure) — vocabulaire des procs en tête de combat.mjs —, quatre duos, et les PACTES.

import { rand, shuffle, weightedPick } from '../core/rng.mjs';

export const FAMILIES = {
  colere: { name: 'Colère', color: '#ff5a3c' },
  paresse: { name: 'Paresse', color: '#5ab8ff' },
  avarice: { name: 'Avarice', color: '#ffc83c' },
  gourmandise: { name: 'Gourmandise', color: '#7ee05a' },
  luxure: { name: 'Luxure', color: '#ff6ec7' },
  envie: { name: 'Envie', color: '#3ce0b4' },
  orgueil: { name: 'Orgueil', color: '#b98cff' },
};

export const RARITIES = [
  { id: 'commun', name: 'Commun', mult: 1, weight: 70 },
  { id: 'rare', name: 'Rare', mult: 1.4, weight: 24 },
  { id: 'epique', name: 'Épique', mult: 1.8, weight: 6 },
];

// value : valeur de base (multipliée par la rareté). Les textes utilisent {v} (valeur
// formatée) — le rendu ne recalcule rien.
export const BOONS = [
  // Colère — brûlure
  { id: 'lame_ardente', family: 'colere', slot: 'attack', name: 'Lame ardente', text: 'Vos coups enflamment : {v} dégâts/s pendant 3 s.', value: 6, proc: { on: 'hit', sources: ['melee', 'strike'], effect: 'burn', duration: 3, chance: 1 } },
  { id: 'pas_de_braise', family: 'colere', slot: 'dash', name: 'Pas de braise', text: 'Votre dash explose : {v} dégâts autour de vous.', value: 12, proc: { on: 'dash', effect: 'nova', radius: 80 } },
  { id: 'furie', family: 'colere', slot: 'passive', name: 'Furie', text: '+{v} % de dégâts.', value: 20, pct: true, stat: 'damageMult' },
  { id: 'represailles', family: 'colere', slot: 'passive', name: 'Représailles', text: 'Après une esquive parfaite : +{v} % de dégâts pendant 3 s.', value: 40, pct: true, proc: { on: 'dodge', effect: 'surge', duration: 3 } },
  { id: 'coup_de_sang', family: 'colere', slot: 'attack', name: 'Coup de sang', text: 'Le dernier coup du combo fait exploser la cible : {v} dégâts autour d\'elle.', value: 12, proc: { on: 'hit', sources: ['melee'], when: 'finisher', effect: 'blast', radius: 70 } },
  // Paresse — engourdissement
  { id: 'torpeur', family: 'paresse', slot: 'attack', name: 'Torpeur', text: 'Vos coups ralentissent de {v} % pendant 2 s.', value: 30, pct: true, proc: { on: 'hit', sources: ['melee', 'strike'], effect: 'chill', duration: 2, chance: 1 } },
  { id: 'brume_lente', family: 'paresse', slot: 'dash', name: 'Brume lente', text: 'Votre dash gèle : {v} dégâts et ralentit.', value: 8, proc: { on: 'dash', effect: 'nova', radius: 90, chill: 2 } },
  { id: 'sommeil', family: 'paresse', slot: 'passive', name: 'Sommeil de plomb', text: 'Recharge du dash −{v} %.', value: 25, pct: true, stat: 'dashRechargeMult', negative: true },
  { id: 'baillement', family: 'paresse', slot: 'passive', name: 'Bâillement', text: 'Une esquive parfaite engourdit les alentours : {v} dégâts, ennemis ralentis de 50 % pendant 3 s.', value: 8, proc: { on: 'dodge', effect: 'nova', radius: 150, chill: 3 } },
  { id: 'mur_du_sommeil', family: 'paresse', slot: 'passive', name: 'Mur du sommeil', text: 'Un ennemi projeté contre un mur reste sonné {v} s.', value: 1.2, proc: { on: 'wallSlam', effect: 'stun' } },
  // Avarice — or et critiques
  { id: 'main_avide', family: 'avarice', slot: 'attack', name: 'Main avide', text: '{v} % de chances qu\'un coup rapporte 1 or.', value: 20, pct: true, proc: { on: 'hit', sources: ['melee', 'strike'], effect: 'gold', valueFixed: 1 } },
  { id: 'fortune', family: 'avarice', slot: 'passive', name: 'Fortune', text: '+{v} % de chances de critique.', value: 10, pct: true, stat: 'critChance' },
  { id: 'dime', family: 'avarice', slot: 'passive', name: 'Dîme', text: '+{v} % d\'or trouvé.', value: 35, pct: true, stat: 'goldFindMult' },
  { id: 'prime_de_risque', family: 'avarice', slot: 'passive', name: 'Prime de risque', text: 'Salle nettoyée sans être touché : +{v} or.', value: 10, proc: { on: 'roomClear', when: 'untouched', effect: 'gold' } },
  { id: 'tresor_de_guerre', family: 'avarice', slot: 'passive', name: 'Trésor de guerre', text: '+{v} % de dégâts par tranche de 25 or en bourse (5 tranches au plus).', value: 4, pct: true, proc: { on: 'passive', effect: 'goldPower', per: 25, cap: 5 } },
  // Gourmandise — soin
  { id: 'festin', family: 'gourmandise', slot: 'passive', name: 'Festin', text: 'Chaque ennemi tué rend {v} PV.', value: 2, proc: { on: 'kill', effect: 'heal' } },
  { id: 'voracite', family: 'gourmandise', slot: 'passive', name: 'Voracité', text: '+{v} PV max.', value: 30, stat: 'maxHpBonus' },
  { id: 'sang_devore', family: 'gourmandise', slot: 'attack', name: 'Sang dévoré', text: 'Vol de vie : {v} % des dégâts infligés.', value: 5, pct: true, stat: 'lifesteal' },
  { id: 'bouchee_double', family: 'gourmandise', slot: 'attack', name: 'Bouchée double', text: 'Le dernier coup du combo rend {v} PV par ennemi touché.', value: 1.5, proc: { on: 'hit', sources: ['melee'], when: 'finisher', effect: 'heal' } },
  { id: 'ripaille', family: 'gourmandise', slot: 'passive', name: 'Ripaille', text: 'Lancer votre Super rend {v} PV.', value: 15, proc: { on: 'super', effect: 'heal' } },
  // Luxure — Super et vulnérabilité
  { id: 'extase', family: 'luxure', slot: 'passive', name: 'Extase', text: 'Le Super se charge {v} % plus vite.', value: 30, pct: true, stat: 'superChargeMult' },
  { id: 'charme', family: 'luxure', slot: 'skill', name: 'Charme fatal', text: 'La Lance rend vulnérable : +{v} % de dégâts subis, 4 s.', value: 30, pct: true, proc: { on: 'hit', sources: ['skill'], effect: 'vuln', duration: 4, chance: 1 } },
  { id: 'envol', family: 'luxure', slot: 'passive', name: 'Envol', text: '+1 charge de dash.', value: 1, stat: 'dashChargesBonus', noScale: true, unique: true },
  { id: 'baiser_vole', family: 'luxure', slot: 'dash', name: 'Baiser volé', text: 'Votre frappe de dash rend vulnérable : +{v} % de dégâts subis, 4 s.', value: 25, pct: true, proc: { on: 'hit', sources: ['strike'], effect: 'vuln', duration: 4 } },
  { id: 'ivresse', family: 'luxure', slot: 'passive', name: 'Ivresse', text: 'Une esquive parfaite charge le Super de {v} % en plus.', value: 8, pct: true, proc: { on: 'dodge', effect: 'superCharge' } },
  // Envie — éclairs en chaîne
  { id: 'jalousie', family: 'envie', slot: 'attack', name: 'Jalousie', text: 'Vos coups ont 25 % de chances de lancer un éclair : {v} dégâts, 2 rebonds.', value: 10, proc: { on: 'hit', sources: ['melee', 'strike'], effect: 'chain', chance: 0.25, bounces: 2, range: 220 } },
  { id: 'convoitise', family: 'envie', slot: 'skill', name: 'Convoitise', text: 'La Lance déclenche un éclair : {v} dégâts, 3 rebonds.', value: 14, proc: { on: 'hit', sources: ['skill'], effect: 'chain', chance: 1, bounces: 3, range: 240 } },
  { id: 'rancoeur', family: 'envie', slot: 'passive', name: 'Rancœur', text: 'Compétence : recharge −{v} %.', value: 20, pct: true, stat: 'skillCooldownMult', negative: true },
  { id: 'eclair_de_depit', family: 'envie', slot: 'dash', name: 'Éclair de dépit', text: 'Votre dash lance un éclair : {v} dégâts, jusqu\'à 3 ennemis.', value: 9, proc: { on: 'dash', effect: 'chain', bounces: 3, range: 200 } },
  { id: 'mauvais_oeil', family: 'envie', slot: 'passive', name: 'Mauvais œil', text: 'Chaque ennemi tué lance un éclair : {v} dégâts, 2 rebonds.', value: 8, proc: { on: 'kill', effect: 'chain', bounces: 2, range: 200 } },
  // Orgueil — exécution et pleine santé
  { id: 'superbe', family: 'orgueil', slot: 'passive', name: 'Superbe', text: '+{v} % de dégâts quand vos PV sont pleins.', value: 30, pct: true, proc: { on: 'passive', effect: 'fullHpBonus' } },
  { id: 'coup_de_grace', family: 'orgueil', slot: 'passive', name: 'Coup de grâce', text: '+{v} % de dégâts contre les ennemis sous 30 % de PV.', value: 50, pct: true, proc: { on: 'passive', effect: 'execute', threshold: 0.3 } },
  { id: 'vanite', family: 'orgueil', slot: 'passive', name: 'Vanité', text: '+{v} % de dégâts critiques.', value: 40, pct: true, stat: 'critMult' },
  { id: 'invaincu', family: 'orgueil', slot: 'passive', name: 'Invaincu', text: '+{v} % de dégâts par salle nettoyée sans être touché (5 au plus). Une blessure remet le compte à zéro.', value: 6, pct: true, proc: { on: 'passive', effect: 'streakBonus', cap: 5 } },
  { id: 'mepris', family: 'orgueil', slot: 'passive', name: 'Mépris', text: '+{v} % de chances de critique contre les ennemis sonnés.', value: 50, pct: true, proc: { on: 'passive', effect: 'stunnedCrit' } },
];

// Duos : exigent une bénédiction de chacune des deux familles. Offerts en priorité quand
// ils sont éligibles (synergie visible = build qui prend forme).
export const DUOS = [
  { id: 'choc_thermique', families: ['colere', 'paresse'], slot: 'passive', name: 'Choc thermique', text: 'Les ennemis en feu ET ralentis subissent +{v} % de dégâts.', value: 40, pct: true, proc: { on: 'passive', effect: 'execute', threshold: 1.01, needsBurnChill: true } },
  { id: 'festin_dor', families: ['avarice', 'gourmandise'], slot: 'passive', name: 'Festin d\'or', text: 'Chaque ennemi tué rend {v} PV et 2 or.', value: 3, proc: { on: 'kill', effect: 'heal' }, extraGoldOnKill: 2 },
  { id: 'orage_jaloux', families: ['envie', 'colere'], slot: 'passive', name: 'Orage ardent', text: 'Les éclairs enflamment : {v} dégâts/s.', value: 8, proc: { on: 'hit', sources: ['chainHit'], effect: 'burn', duration: 3, chance: 1 } },
  { id: 'gloire_charnelle', families: ['orgueil', 'luxure'], slot: 'passive', name: 'Gloire charnelle', text: 'Le Super inflige +{v} % de dégâts et dure 0,4 s de plus.', value: 50, pct: true, stat: 'superDamageMult', superDurationBonus: 0.4 },
  { id: 'passion_brulante', families: ['colere', 'luxure'], slot: 'passive', name: 'Passion brûlante', text: 'Lancer le Super enflamme les ennemis proches : {v} dégâts/s pendant 4 s.', value: 10, proc: { on: 'super', effect: 'around', apply: 'burn', radius: 220, duration: 4 } },
  { id: 'faire_les_poches', families: ['paresse', 'avarice'], slot: 'passive', name: 'Faire les poches', text: 'Un ennemi projeté contre un mur lâche {v} or.', value: 2, noScale: true, proc: { on: 'wallSlam', effect: 'gold' } },
  { id: 'trop_plein', families: ['gourmandise', 'orgueil'], slot: 'passive', name: 'Trop-plein', text: 'Chaque PV soigné au-delà du maximum charge le Super de {v} %.', value: 1, pct: true, proc: { on: 'overheal', effect: 'superCharge', perUnit: true } },
  { id: 'foudre_du_dedain', families: ['envie', 'orgueil'], slot: 'passive', name: 'Foudre du dédain', text: 'Vos éclairs achèvent les ennemis sous {v} % de PV (sauf Gardiens).', value: 15, pct: true, proc: { on: 'hit', sources: ['chainHit'], effect: 'cull' } },
];

// PACTES : bénédictions à contrepartie, jamais tirées par une offre — un autel les accorde
// (run.mjs, effet « pact »). TEMPORAIRES comme les autres : la mort les reprend, et l'écran de
// mort les compte. `stats` : contreparties fixes (stats.mjs). Le pacte porte la couleur d'une
// famille (il compte pour ses duos).
export const PACTS = [
  { id: 'reflet_brise', family: 'orgueil', slot: 'passive', name: 'Reflet brisé', text: '+{v} % de dégâts, −20 PV max, jusqu\'à votre mort (pacte du Miroir).', value: 25, pct: true, stat: 'damageMult', stats: { maxHpBonus: -20 }, noScale: true, unique: true, pact: true },
];

const ALL = [...BOONS, ...DUOS, ...PACTS];
export function boonDef(id) {
  return ALL.find((b) => b.id === id) ?? null;
}

export function boonValue(def, rarity) {
  const r = RARITIES.find((x) => x.id === rarity) ?? RARITIES[0];
  return def.noScale ? def.value : Math.round(def.value * r.mult * 10) / 10;
}

export function boonText(def, rarity) {
  return def.text.replace('{v}', String(boonValue(def, rarity)));
}

function ownedFamilies(run) {
  const s = new Set();
  for (const b of run.boons) {
    const d = boonDef(b.id);
    if (d?.family) s.add(d.family);
  }
  return s;
}

/** 3 offres d'une famille (ou un duo éligible en tête). Jamais une bénédiction déjà possédée
 *  marquée `unique`. */
export function rollBoonOffer(game, family) {
  const run = game.run;
  const owned = new Set(run.boons.map((b) => b.id));
  const fams = ownedFamilies(run);
  const candidates = BOONS.filter((b) => b.family === family && !(b.unique && owned.has(b.id)));
  shuffle(game.rng.gen, candidates);
  const picks = candidates.slice(0, 3);
  const duos = DUOS.filter((d) => !owned.has(d.id) && d.families.includes(family) && d.families.every((f) => fams.has(f) || f === family) && d.families.some((f) => fams.has(f) && f !== family));
  if (duos.length > 0 && rand(game.rng.gen) < 0.6) picks[picks.length - 1] = duos[0];
  return picks.map((def) => {
    const rarity = weightedPick(game.rng.gen, RARITIES, (r) => r.weight).id;
    return { id: def.id, rarity, level: (run.boons.find((b) => b.id === def.id)?.level ?? 0) + 1 };
  });
}

/** Ajoute (ou améliore) une bénédiction dans le run. */
export function addBoon(run, offer) {
  const def = boonDef(offer.id);
  if (!def) return;
  const existing = run.boons.find((b) => b.id === offer.id);
  if (existing) {
    existing.level++;
    existing.rarity = rankRarity(existing.rarity) >= rankRarity(offer.rarity) ? existing.rarity : offer.rarity;
    return;
  }
  if (def.slot !== 'passive') {
    run.boons = run.boons.filter((b) => boonDef(b.id)?.slot !== def.slot);
  }
  run.boons.push({ id: offer.id, rarity: offer.rarity, level: 1 });
}

function rankRarity(id) {
  return RARITIES.findIndex((r) => r.id === id);
}

export function randomFamily(game) {
  const keys = Object.keys(FAMILIES);
  return keys[Math.floor(rand(game.rng.gen) * keys.length)];
}
