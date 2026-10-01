// Bénédictions infernales — les 7 péchés capitaux comme familles (équivalent des dieux de
// Hades). Une bénédiction est une DONNÉE : des modificateurs de stats et/ou des procs que
// combat.mjs interprète. Emplacements exclusifs (attack, dash, skill) : une nouvelle
// bénédiction du même emplacement remplace l'ancienne. Les passifs s'empilent.
//
// Rareté : commun ×1, rare ×1,4, épique ×1,8 sur les valeurs.

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
  { id: 'furie', family: 'colere', slot: 'passive', name: 'Furie', text: '+{v} % de dégâts.', value: 12, pct: true, stat: 'damageMult' },
  // Paresse — engourdissement
  { id: 'torpeur', family: 'paresse', slot: 'attack', name: 'Torpeur', text: 'Vos coups ralentissent de {v} % pendant 2 s.', value: 30, pct: true, proc: { on: 'hit', sources: ['melee', 'strike'], effect: 'chill', duration: 2, chance: 1 } },
  { id: 'brume_lente', family: 'paresse', slot: 'dash', name: 'Brume lente', text: 'Votre dash gèle : {v} dégâts et ralentit.', value: 8, proc: { on: 'dash', effect: 'nova', radius: 90, chill: 2 } },
  { id: 'sommeil', family: 'paresse', slot: 'passive', name: 'Sommeil de plomb', text: 'Recharge du dash −{v} %.', value: 15, pct: true, stat: 'dashRechargeMult', negative: true },
  // Avarice — or et critiques
  { id: 'main_avide', family: 'avarice', slot: 'attack', name: 'Main avide', text: '{v} % de chances qu\'un coup rapporte 1 or.', value: 20, pct: true, proc: { on: 'hit', sources: ['melee', 'strike'], effect: 'gold', valueFixed: 1 } },
  { id: 'fortune', family: 'avarice', slot: 'passive', name: 'Fortune', text: '+{v} % de chances de critique.', value: 6, pct: true, stat: 'critChance' },
  { id: 'dime', family: 'avarice', slot: 'passive', name: 'Dîme', text: '+{v} % d\'or trouvé.', value: 35, pct: true, stat: 'goldFindMult' },
  // Gourmandise — soin
  { id: 'festin', family: 'gourmandise', slot: 'passive', name: 'Festin', text: 'Chaque ennemi tué rend {v} PV.', value: 2, proc: { on: 'kill', effect: 'heal' } },
  { id: 'voracite', family: 'gourmandise', slot: 'passive', name: 'Voracité', text: '+{v} PV max.', value: 20, stat: 'maxHpBonus' },
  { id: 'sang_devore', family: 'gourmandise', slot: 'attack', name: 'Sang dévoré', text: 'Vol de vie : {v} % des dégâts infligés.', value: 4, pct: true, stat: 'lifesteal' },
  // Luxure — Super et vulnérabilité
  { id: 'extase', family: 'luxure', slot: 'passive', name: 'Extase', text: 'Le Super se charge {v} % plus vite.', value: 30, pct: true, stat: 'superChargeMult' },
  { id: 'charme', family: 'luxure', slot: 'skill', name: 'Charme fatal', text: 'La Lance rend vulnérable : +{v} % de dégâts subis, 4 s.', value: 30, pct: true, proc: { on: 'hit', sources: ['skill'], effect: 'vuln', duration: 4, chance: 1 } },
  { id: 'envol', family: 'luxure', slot: 'passive', name: 'Envol', text: '+1 charge de dash.', value: 1, stat: 'dashChargesBonus', noScale: true, unique: true },
  // Envie — éclairs en chaîne
  { id: 'jalousie', family: 'envie', slot: 'attack', name: 'Jalousie', text: 'Vos coups ont 25 % de chances de lancer un éclair : {v} dégâts, 2 rebonds.', value: 10, proc: { on: 'hit', sources: ['melee', 'strike'], effect: 'chain', chance: 0.25, bounces: 2, range: 220 } },
  { id: 'convoitise', family: 'envie', slot: 'skill', name: 'Convoitise', text: 'La Lance déclenche un éclair : {v} dégâts, 3 rebonds.', value: 14, proc: { on: 'hit', sources: ['skill'], effect: 'chain', chance: 1, bounces: 3, range: 240 } },
  { id: 'rancoeur', family: 'envie', slot: 'passive', name: 'Rancœur', text: 'Compétence : recharge −{v} %.', value: 20, pct: true, stat: 'skillCooldownMult', negative: true },
  // Orgueil — exécution et pleine santé
  { id: 'superbe', family: 'orgueil', slot: 'passive', name: 'Superbe', text: '+{v} % de dégâts quand vos PV sont pleins.', value: 30, pct: true, proc: { on: 'passive', effect: 'fullHpBonus' } },
  { id: 'coup_de_grace', family: 'orgueil', slot: 'passive', name: 'Coup de grâce', text: '+{v} % de dégâts contre les ennemis sous 30 % de PV.', value: 50, pct: true, proc: { on: 'passive', effect: 'execute', threshold: 0.3 } },
  { id: 'vanite', family: 'orgueil', slot: 'passive', name: 'Vanité', text: '+{v} % de dégâts critiques.', value: 40, pct: true, stat: 'critMult' },
];

// Duos : exigent une bénédiction de chacune des deux familles. Offerts en priorité quand
// ils sont éligibles (synergie visible = build qui prend forme).
export const DUOS = [
  { id: 'choc_thermique', families: ['colere', 'paresse'], slot: 'passive', name: 'Choc thermique', text: 'Les ennemis en feu ET ralentis subissent +{v} % de dégâts.', value: 40, pct: true, proc: { on: 'passive', effect: 'execute', threshold: 1.01, needsBurnChill: true } },
  { id: 'festin_dor', families: ['avarice', 'gourmandise'], slot: 'passive', name: 'Festin d\'or', text: 'Chaque ennemi tué rend {v} PV et 2 or.', value: 3, proc: { on: 'kill', effect: 'heal' }, extraGoldOnKill: 2 },
  { id: 'orage_jaloux', families: ['envie', 'colere'], slot: 'passive', name: 'Orage ardent', text: 'Les éclairs enflamment : {v} dégâts/s.', value: 8, proc: { on: 'hit', sources: ['chainHit'], effect: 'burn', duration: 3, chance: 1 } },
  { id: 'gloire_charnelle', families: ['orgueil', 'luxure'], slot: 'passive', name: 'Gloire charnelle', text: 'Le Super inflige +{v} % de dégâts et dure 0,4 s de plus.', value: 50, pct: true, stat: 'superDamageMult', superDurationBonus: 0.4 },
];

const ALL = [...BOONS, ...DUOS];
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
