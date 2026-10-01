// PLAN DE SECTION — aucun des 666 étages n'est écrit à la main. Une section (18 étages) est
// décrite par une fonction PURE et déterministe de (tuning, graine, numéro de section), qui
// assemble des BRIQUES réutilisables :
//   - le RYTHME (tuning.section.rhythms) : l'emplacement de chaque index — combat court (1 vague),
//     normal (2) ou assaut (3), halte, antichambre du Gardien, Gardien ;
//   - les PORTES : imposées (halte, antichambre, Gardien) ou tirées (tuning.section.doorWeights ×
//     thème du Cercle), avec une épreuve d'élite et une chambre forte GARANTIES dans la section ;
//   - le COMBAT : vagues, budget de menace, dispositions permises (room.mjs), bestiaire pondéré
//     (ROSTER de room.mjs + archétypes ajoutés par foe_data.mjs) ;
//   - le THÈME du Cercle (tuning.circles) : pondérations du bestiaire par COÛT, jamais par nom
//     (un archétype ajouté entre dans le tirage sans être nommé), archétypes « vedettes » tirés
//     par section, dispositions et portes favorites ;
//   - le GARDIEN de la section (floors.guardianFor).
// Le run (run.mjs) COMPOSE ensuite chaque étage : plan de l'index + porte choisie (composeFloor).
//
// Graine : celle de la partie. Le plan a son propre flux (hashSeed) : le calculer ne consomme
// jamais les flux de la partie, et la même partie revoit le même plan après une mort.

import { createRng, hashSeed, rand, weightedPick, shuffle } from '../core/rng.mjs';
import { floorInfo, floorScaling, guardianFor, sectionBounds } from './floors.mjs';
import { ROSTER, LAYOUT_IDS } from './room.mjs';

const PLAN_SALT = 0x5ec7;

/** Type d'étage qu'ouvre chaque récompense de porte (le reste : combat qui rend cette récompense). */
export const FLOOR_TYPE_OF_REWARD = Object.freeze({
  elite: 'elite',
  shop: 'shop',
  event: 'event',
  treasure: 'treasure',
  rest: 'rest',
  boss: 'boss',
});

/** Récompense d'une salle de combat (porte « boon », « loot », « gold », « heal »). */
const COMBAT_REWARDS = ['boon', 'loot', 'gold', 'heal'];

const NEUTRAL_THEME = { id: 'neutre', costBias: 0, featured: 0, featuredMult: 1, budgetMult: 1, strayEliteMult: 1, layouts: null, doors: {} };

export function sectionCount(tuning) {
  return Math.ceil(tuning.floors.total / tuning.floors.sectionLength);
}

/** Thème du Cercle `circle` (1..10) : données de tuning.circles complétées par le thème neutre. */
export function circleTheme(tuning, circle) {
  const list = tuning.circles ?? [];
  const c = list.length ? list[Math.min(list.length, Math.max(1, circle)) - 1] : null;
  return { ...NEUTRAL_THEME, ...c, circle };
}

/**
 * Plan complet de la section `section` (1..37) : 18 entrées (index 1..18), chacune décrivant
 * l'emplacement, le rythme, les portes qui y MÈNENT, et la composition d'un combat à cet index.
 */
export function sectionPlan(tuning, seed, section) {
  const sec = tuning.section;
  const len = tuning.floors.sectionLength;
  const s = Math.max(1, Math.min(sectionCount(tuning), Math.floor(section)));
  const rng = createRng(hashSeed(seed >>> 0, PLAN_SALT, s));
  const bounds = sectionBounds(tuning, s);
  const head = floorInfo(tuning, bounds.first);
  const theme = circleTheme(tuning, head.circle);
  // Tirages du plan, toujours dans le même ordre (déterminisme).
  const rhythmId = s === 1 || sec.rhythms.length === 1 ? 0 : Math.floor(rand(rng) * sec.rhythms.length);
  const rhythm = sec.rhythms[rhythmId];
  const featured = drawFeatured(rng, tuning, theme);
  const halteDoors = drawDistinct(rng, sec.halte.pool, sec.halte.doors);
  const treasureAt = drawTreasureIndex(rng, sec, rhythm);
  const guardian = guardianFor(tuning, s);
  const doorWeights = doorWeightsFor(tuning, theme);
  const floors = [];
  for (let index = 1; index <= len; index++) {
    const floor = bounds.first + index - 1;
    const slot = index === len ? 'gardien' : rhythm[index - 1];
    floors.push(planEntry(tuning, { s, index, floor, slot, theme, featured, halteDoors, treasureAt, guardian, doorWeights }));
  }
  return {
    section: s,
    first: bounds.first,
    guardianFloor: bounds.guardian,
    checkpoint: bounds.checkpoint,
    circle: head.circle,
    circleName: head.circleName,
    theme: { id: theme.id, circle: head.circle, name: head.circleName, costBias: theme.costBias, featured, featuredMult: theme.featuredMult },
    rhythmId,
    guardian,
    treasureAt,
    floors,
  };
}

function planEntry(tuning, ctx) {
  const { s, index, floor, slot, theme, featured, halteDoors, treasureAt, guardian, doorWeights } = ctx;
  const sec = tuning.section;
  const enc = tuning.encounter;
  const paceName = sec.paces[slot] ? slot : sec.calmPace;
  const pace = sec.paces[paceName];
  let doors = null;
  if (slot === 'gardien') doors = ['boss'];
  else if (slot === 'halte') doors = halteDoors.slice();
  else if (slot === 'antichambre') doors = sec.antichambre.slice();
  let guarantee = null;
  if (!doors && sec.eliteAt.includes(index)) guarantee = 'elite';
  else if (!doors && index === treasureAt) guarantee = 'treasure';
  const offers = doors ?? [...new Set([...doorWeights.filter((d) => d.weight > 0).map((d) => d.reward), ...(guarantee ? [guarantee] : [])])];
  const scale = floorScaling(tuning, floor);
  return {
    index,
    floor,
    slot, // court | normal | assaut | halte | antichambre | gardien
    pace: paceName, // rythme d'un combat joué à cet index
    doors, // portes IMPOSÉES qui mènent à cet étage (sinon tirées)
    guarantee, // récompense garantie parmi les portes tirées (élite, chambre forte)
    doorWeights: doors ? null : doorWeights,
    offers, // récompenses possibles des portes qui mènent ici
    types: [...new Set(offers.map((r) => FLOOR_TYPE_OF_REWARD[r] ?? 'combat'))], // types d'étage possibles
    waves: pace.waves,
    budget: (enc.baseBudget + enc.perIndex * index) * pace.budgetMult * theme.budgetMult * scale.density,
    layouts: layoutsFor(tuning, theme, floor),
    roster: rosterFor(tuning, theme, featured, s, index),
    strayEliteChance: floor >= enc.strayEliteFrom ? enc.strayEliteChance * theme.strayEliteMult : 0,
    guardian: slot === 'gardien' ? guardian : null,
  };
}

/** Entrée du plan pour l'étage `floor` (1..666). */
export function floorSlot(tuning, seed, floor) {
  const info = floorInfo(tuning, floor);
  return sectionPlan(tuning, seed, info.section).floors[info.indexInSection - 1];
}

/**
 * COMPOSE l'étage `floor` à partir de son entrée de plan et de la porte qui y mène : c'est le
 * plan de salle que buildRoom (room.mjs) et enterFloor (run.mjs) consomment. Fonction pure.
 *   kind   : combat | elite | boss | shop | event | treasure | rest
 *   reward : récompense de fin de salle (combat : celle de la porte ; élite : butin)
 */
export function composeFloor(tuning, seed, floor, door) {
  const info = floorInfo(tuning, floor);
  const entry = sectionPlan(tuning, seed, info.section).floors[info.indexInSection - 1];
  const asked = info.isBoss ? 'boss' : door?.reward ?? 'boon';
  const kind = FLOOR_TYPE_OF_REWARD[asked] ?? 'combat';
  const reward = kind === 'elite' ? 'loot' : kind === 'combat' ? (COMBAT_REWARDS.includes(asked) ? asked : 'boon') : kind;
  return {
    kind,
    reward,
    family: door?.family,
    elite: kind === 'elite',
    floor: info.floor,
    section: info.section,
    index: entry.index,
    slot: entry.slot,
    pace: entry.pace,
    waves: entry.waves,
    budget: entry.budget,
    layouts: entry.layouts,
    roster: entry.roster,
    strayEliteChance: entry.strayEliteChance,
    guardian: kind === 'boss' ? guardianFor(tuning, info.section) : null,
    theme: circleTheme(tuning, info.circle).id,
  };
}

// ---------------------------------------------------------------- briques du plan

/** Dispositions permises à l'étage : le tout premier étage est ouvert (apprentissage). */
function layoutsFor(tuning, theme, floor) {
  if (floor === 1) return [{ id: 'open', weight: 1 }];
  const table = theme.layouts ?? Object.fromEntries(LAYOUT_IDS.map((id) => [id, 1]));
  return Object.entries(table).filter(([id, w]) => LAYOUT_IDS.includes(id) && w > 0).map(([id, weight]) => ({ id, weight }));
}

/**
 * Bestiaire pondéré de l'étage : dans la 1re section, les archétypes entrent progressivement
 * (minIndex) ; ensuite tous sont là. Poids × (coût / costRef)^costBias × vedette.
 */
function rosterFor(tuning, theme, featured, section, index) {
  const reach = section > 1 ? tuning.floors.sectionLength : index;
  const ref = tuning.encounter.costRef;
  return ROSTER.filter((r) => r.minIndex <= reach && tuning.enemies[r.kind]).map((r) => ({
    kind: r.kind,
    cost: r.cost,
    weight: r.weight * Math.pow(r.cost / ref, theme.costBias) * (featured.includes(r.kind) ? theme.featuredMult : 1),
  }));
}

/** Archétypes vedettes de la section : tirés dans TOUT le bestiaire présent (aucun nom codé). */
function drawFeatured(rng, tuning, theme) {
  const kinds = [...new Set(ROSTER.filter((r) => tuning.enemies[r.kind]).map((r) => r.kind))];
  return shuffle(rng, kinds).slice(0, Math.max(0, theme.featured));
}

/** Poids des portes tirées : base × multiplicateur du thème. */
function doorWeightsFor(tuning, theme) {
  return Object.entries(tuning.section.doorWeights).map(([reward, w]) => ({ reward, weight: w * (theme.doors?.[reward] ?? 1) }));
}

/** `n` récompenses distinctes tirées dans un tableau de poids {récompense: poids}. */
function drawDistinct(rng, pool, n) {
  const left = Object.entries(pool).filter(([, w]) => w > 0).map(([reward, weight]) => ({ reward, weight }));
  const out = [];
  while (out.length < n && left.length) {
    const it = weightedPick(rng, left, (d) => d.weight);
    out.push(it.reward);
    left.splice(left.indexOf(it), 1);
  }
  return out;
}

/** Index où une porte de chambre forte est garantie : un combat tiré, hors élites imposées. */
function drawTreasureIndex(rng, sec, rhythm) {
  const { from, to } = sec.treasure;
  const ok = (i) => sec.paces[rhythm[i - 1]] && !sec.eliteAt.includes(i);
  const candidates = [];
  for (let i = from; i <= to; i++) if (ok(i)) candidates.push(i);
  return candidates.length ? candidates[Math.floor(rand(rng) * candidates.length)] : null;
}
