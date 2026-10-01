// SALLES CALMES réutilisables (sans combat), placées par le plan de section (sections.mjs) :
//   treasure — « Chambre forte » : un coffre scellé, UN choix parmi trois trésors annoncés
//              (un objet d'équipement, une bourse, une relique = bénédiction) ;
//   rest     — « Fontaine du Léthé » : UN choix parmi trois grâces (boire : soin ; méditer : une
//              bénédiction possédée gagne un niveau ; fioles : gadget et Super rechargés).
// Le contenu est tiré à l'ENTRÉE dans la salle (le panneau l'annonce, rien de caché). L'objet
// rejoint l'équipement PERMANENT comme tout butin ; or, bénédiction, soin et niveaux restent
// TEMPORAIRES (la mort les reprend, comme le reste du run).
//
// Contrat avec run.mjs : setupCalmRoom à l'entrée, describeCalm pour le panneau (mode 'choice'),
// applyCalm(index) rend 'close' (choix fait), 'replaced' (l'objet d'interaction est remplacé par
// un butin ou une bénédiction à toucher) ou false (choix refusé).

import { randInt } from '../core/rng.mjs';
import { emit } from './state.mjs';
import { healPlayer, spawnPickup } from './combat.mjs';
import { generateItem, rollRarity, ITEM_RARITIES, SLOT_NAMES } from './loot.mjs';
import { FAMILIES, randomFamily, addBoon, boonDef } from './boons.mjs';
import { recomputeStats } from './stats.mjs';

export const CALM_KINDS = Object.freeze(['treasure', 'rest']);

const TREASURE_COLOR = '#ffb43c';
const REST_COLOR = '#6dd8ff';
const PERCENT = 100;

/** Tire le contenu de l'objet d'interaction `it` d'une salle calme (à l'entrée dans la salle). */
export function setupCalmRoom(game, it) {
  if (it.kind !== 'treasure') return;
  const tr = game.tuning.economy.treasure;
  const minRank = ITEM_RARITIES.findIndex((r) => r.id === tr.minRarity);
  const rolled = rollRarity(game, tr.rarityBonus);
  const rank = Math.max(minRank, ITEM_RARITIES.findIndex((r) => r.id === rolled));
  it.item = generateItem(game, { rarity: ITEM_RARITIES[rank].id });
  it.gold = Math.round(randInt(game.rng.gen, tr.gold[0], tr.gold[1]) * game.player.stats.goldFindMult);
  it.family = randomFamily(game);
}

function gadgetMax(game) {
  return game.tuning.gadget.chargesPerSection + game.player.stats.gadgetChargesBonus;
}

/** Bénédiction que la méditation approfondit : la moins avancée (la première à égalité). */
function meditationTarget(game) {
  let best = null;
  for (const b of game.run.boons) if (!best || b.level < best.level) best = b;
  return best;
}

function treasureOptions(game, it) {
  const rar = ITEM_RARITIES.find((r) => r.id === it.item.rarity);
  const fam = FAMILIES[it.family];
  return [
    { id: 'objet', kicker: `Objet · ${rar.name} · ${SLOT_NAMES[it.item.slot]}`, label: it.item.name, text: 'Équipement PERMANENT : il rejoint votre équipement ou le coffre de la Ville.', color: rar.color, disabled: false },
    { id: 'bourse', kicker: 'Bourse', label: `+${it.gold} or`, text: 'L\'or suit le héros ; Charon en prend sa part à chaque mort.', color: '#ffd23c', disabled: false },
    { id: 'relique', kicker: `Relique · ${fam.name}`, label: 'Bénédiction', text: 'Un don du péché, TEMPORAIRE : perdu à la mort.', color: fam.color, disabled: false },
  ];
}

function restOptions(game) {
  const p = game.player;
  const r = game.tuning.economy.rest;
  const heal = Math.round(p.maxHp * r.heal);
  const target = meditationTarget(game);
  const name = target ? boonDef(target.id)?.name ?? target.id : null;
  const full = p.gadgetCharges >= gadgetMax(game) && p.superCharge >= 1;
  return [
    { id: 'boire', kicker: 'Soin', label: `Boire · +${heal} PV`, text: `Rend ${Math.round(r.heal * PERCENT)} % des PV.`, color: '#6dff8a', disabled: false }, // jamais grisé : un choix reste toujours possible
    { id: 'mediter', kicker: 'Amélioration · temporaire', label: target ? `Méditer · ${name} niv. ${target.level + 1}` : 'Méditer', text: target ? 'Votre bénédiction la moins avancée gagne un niveau.' : 'Aucune bénédiction à approfondir.', color: '#b98cff', disabled: !target },
    { id: 'fioles', kicker: 'Pouvoirs', label: 'Remplir les fioles', text: `Charges de gadget pleines, jauge de Super +${Math.round(r.superCharge * PERCENT)} %.`, color: REST_COLOR, disabled: full },
  ];
}

/** Panneau de choix (game.choice) de l'objet d'interaction `it`. */
export function describeCalm(game, it) {
  if (it.kind === 'treasure') {
    return { kind: 'treasure', title: 'Chambre forte', text: 'Un coffre scellé. Un seul de ses trois trésors vous suivra.', color: TREASURE_COLOR, options: treasureOptions(game, it) };
  }
  if (it.kind === 'rest') {
    return { kind: 'rest', title: 'Fontaine du Léthé', text: 'L\'eau efface la fatigue. Elle n\'accorde qu\'une grâce.', color: REST_COLOR, options: restOptions(game) };
  }
  return null;
}

/** Applique l'option `index` du panneau de l'objet `it`. */
export function applyCalm(game, it, index) {
  const ch = describeCalm(game, it);
  const opt = ch?.options[index];
  if (!opt || opt.disabled) return false;
  const p = game.player;
  const room = game.room;
  switch (opt.id) {
    case 'objet':
      room.interact = { kind: 'loot', x: it.x, y: it.y, r: 30, used: false, item: it.item };
      return 'replaced';
    case 'relique':
      room.interact = { kind: 'boon', x: it.x, y: it.y, r: 30, used: false, family: it.family };
      return 'replaced';
    case 'bourse': {
      const n = game.tuning.economy.treasure.goldPickups;
      const each = Math.max(1, Math.round(it.gold / n));
      for (let i = 0; i < n; i++) spawnPickup(game, 'gold', it.x, it.y, each);
      return 'close';
    }
    case 'boire':
      healPlayer(game, p.maxHp * game.tuning.economy.rest.heal, true);
      return 'close';
    case 'mediter': {
      const target = meditationTarget(game);
      addBoon(game.run, { id: target.id, rarity: target.rarity });
      recomputeStats(game);
      emit(game, 'boonGain', { id: target.id, rarity: target.rarity });
      return 'close';
    }
    case 'fioles':
      p.gadgetCharges = Math.max(p.gadgetCharges, gadgetMax(game));
      p.superCharge = Math.min(1, p.superCharge + game.tuning.economy.rest.superCharge);
      emit(game, 'gadgetCharge', { x: p.x, y: p.y, charges: p.gadgetCharges });
      return 'close';
    default:
      return false;
  }
}
