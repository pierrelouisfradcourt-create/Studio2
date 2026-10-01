// Le run : descente étage par étage, portes à récompense, choix (bénédiction, butin,
// marchand, autel), Gardiens, checkpoints et téléportation, mort et reprise.
//
// PERMANENT vs TEMPORAIRE (demande de Pierre, V2) :
//   - TEMPORAIRE (game.run) : bénédictions — bonus, pouvoirs, améliorations, synergies. La mort
//     les remet TOUJOURS à zéro : aucun instantané de build n'est figé au Gardien.
//   - PERMANENT (game.meta = profil) : classe, armes, équipement (tout objet trouvé est équipé
//     ou rangé au coffre, jamais perdu), compétences, déblocages de la Ville, Âmes, checkpoints.
//   - La bourse (or) suit le héros, mais Charon en prélève une part à chaque mort.
//   - Mort : retour au DERNIER checkpoint (ou en Ville), le temporaire repart de zéro.
//   - Gardien vaincu (tous les 18 étages) : checkpoint + point de téléportation ; deux portes,
//     « section suivante » (le run continue, build conservé) ou « Ville » (fin du run).

import { rand, pick, weightedPick } from '../core/rng.mjs';
import { emit } from './state.mjs';
import { floorInfo, checkpointAfterBoss } from './floors.mjs';
import { buildRoom, playerStart, launchNextWave, spawnBoss, makeDoors, randomGold, rewardSpot } from './room.mjs';
import { spawnPickup, healPlayer, forceHitstop } from './combat.mjs';
import { FAMILIES, rollBoonOffer, addBoon, boonDef, boonText, randomFamily, RARITIES } from './boons.mjs';
import { generateItem, rollRarity, salvageValue, affixText, baseText, LEGENDARY_POWERS, ITEM_RARITIES, randomShopItem, priceOf, SLOT_NAMES } from './loot.mjs';
import { recomputeStats } from './stats.mjs';
import { stashLoot } from './profile.mjs';
import { guardianFor } from './floors.mjs';

export const DOOR_WEIGHTS = [
  { reward: 'boon', weight: 40 },
  { reward: 'loot', weight: 24 },
  { reward: 'gold', weight: 14 },
  { reward: 'elite', weight: 12 },
  { reward: 'heal', weight: 10 },
];

export const REWARD_LABELS = {
  boon: 'Bénédiction',
  loot: 'Trésor',
  gold: 'Or',
  elite: 'Élite',
  heal: 'Soin',
  shop: 'Marchand',
  event: 'Autel',
  boss: 'Gardien',
  town: 'Ville',
};

export const EVENTS = [
  {
    id: 'autel_sang', title: 'Autel de sang',
    text: 'Le sang frais coule encore sur la pierre. L\'autel réclame une offrande.',
    options: [
      { label: 'Offrir 25 % de vos PV — recevoir une bénédiction rare', effect: 'bloodBoon' },
      { label: 'Passer votre chemin', effect: 'none' },
    ],
  },
  {
    id: 'fontaine', title: 'Fontaine des âmes',
    text: 'Une eau noire et tiède murmure des noms oubliés.',
    options: [
      { label: 'Boire — rend 40 % des PV', effect: 'heal40' },
      { label: 'Remplir une fiole — +1 charge de gadget', effect: 'gadget1' },
    ],
  },
  {
    id: 'coffre_maudit', title: 'Coffre maudit',
    text: 'Des runes brûlantes scellent un coffre. Quelque chose y respire.',
    options: [
      { label: 'Forcer le coffre — objet rare, mais perdre 20 PV', effect: 'cursedChest' },
      { label: 'Le laisser dormir', effect: 'none' },
    ],
  },
  {
    id: 'mammon', title: 'Sanctuaire de Mammon',
    text: 'Une statue d\'or tend la main. Elle sait ce que vous portez.',
    options: [
      { label: 'Donner 40 or — bénédiction d\'Avarice', effect: 'mammonBoon', cost: 40 },
      { label: 'Prier — recevoir 25 or', effect: 'gold25' },
    ],
  },
];

export function createRun(startFloor) {
  return {
    floor: startFloor,
    gold: 0,
    boons: [],
    items: { arme: null, armure: null, talisman: null }, // = équipement du PROFIL (game.mjs)
    roomsThisRun: 0,
    startedAt: 0,
    deathRecap: null, // ce que la dernière mort a pris (bénédictions, or) : écran de mort
  };
}

/** La bourse du run est celle du profil : on la recopie à chaque moment clé. */
export function syncPurse(game) {
  game.meta.gold = game.run.gold;
}

/** Plan de la salle d'un étage à partir de la récompense annoncée sur la porte choisie. */
export function planFor(info, door) {
  if (info.isBoss) return { kind: 'boss', reward: 'boss' };
  const reward = door?.reward ?? 'boon';
  if (reward === 'elite') return { kind: 'elite', reward: 'loot', family: door?.family, elite: true };
  if (reward === 'shop') return { kind: 'shop', reward: 'shop' };
  if (reward === 'event') return { kind: 'event', reward: 'event' };
  return { kind: 'combat', reward, family: door?.family };
}

export function enterFloor(game, floor, door) {
  const t = game.tuning;
  const info = floorInfo(t, floor);
  const plan = planFor(info, door);
  game.run.floor = info.floor;
  game.meta.bestFloor = Math.max(game.meta.bestFloor, info.floor);
  syncPurse(game);
  game.enemies.length = 0;
  game.projectiles.length = 0;
  game.hazards.length = 0;
  game.pickups.length = 0;
  game.spawns.length = 0;
  game.room = buildRoom(game, info, plan);
  game.room.plan = plan;
  game.info = info;
  const p = game.player;
  const start = playerStart(game.room);
  p.x = start.x;
  p.y = start.y;
  p.vx = 0;
  p.vy = 0;
  p.attack = null;
  p.state = 'free';
  p.facing = -Math.PI / 2;
  p.buffer.action = null;
  // Gadget : charges rendues toutes les `gadgetRefillEvery` étages de la section.
  if ((info.indexInSection - 1) % (t.section.gadgetRefillEvery ?? t.floors.sectionLength) === 0) {
    p.gadgetCharges = t.gadget.chargesPerSection + p.stats.gadgetChargesBonus;
  }
  game.run.roomsThisRun++;
  emit(game, 'floorEnter', { floor: info.floor, circle: info.circle, circleName: info.circleName, section: info.section, indexInSection: info.indexInSection, kind: plan.kind, reward: plan.reward, isBoss: info.isBoss });

  if (plan.kind === 'boss') {
    spawnBoss(game, guardianFor(t, info.section));
  } else if (plan.kind === 'combat' || plan.kind === 'elite') {
    launchNextWave(game);
  } else {
    // Salle calme : l'objet d'interaction est là d'emblée, les portes aussi.
    game.room.cleared = true;
    const spot = rewardSpot(game.room);
    game.room.interact = { kind: plan.kind, x: spot.x, y: spot.y, r: 34, used: false };
    if (plan.kind === 'shop') game.room.interact.offers = rollShop(game);
    if (plan.kind === 'event') game.room.interact.event = pick(game.rng.gen, EVENTS).id;
    prepareDoors(game, true);
  }
}

/** Fin de combat : récompense, checkpoint, portes. */
export function onRoomClear(game) {
  const room = game.room;
  const t = game.tuning;
  const p = game.player;
  room.cleared = true;
  room.clearedAt = game.time;
  if (room.kind !== 'boss') forceHitstop(game, t.killHitstop.lastEnemy);
  game.telemetry.roomsCleared++;
  game.telemetry.roomTimes.push({ floor: game.run.floor, kind: room.kind, time: game.time - room.enteredAt });
  emit(game, 'roomClear', { floor: game.run.floor, kind: room.kind, boss: room.kind === 'boss' });
  const { x: cx, y: cy } = rewardSpot(room);
  const plan = room.plan;

  if (room.kind === 'boss' && game.practice) {
    // Entraînement : aucune récompense ; une seule porte, retour en Ville.
    healPlayer(game, p.maxHp * 0.5, true);
    emit(game, 'checkpoint', { floor: game.run.floor, practice: true });
    makeDoors(game, [{ reward: 'town' }]);
    emit(game, 'doorsOpen', { count: 1 });
    return;
  }
  if (room.kind === 'boss') {
    // Gardien vaincu : checkpoint + point de téléportation (PERMANENTS), Âmes, soin.
    // Le build TEMPORAIRE n'est PAS figé : il ne survivra pas à la prochaine mort.
    const cp = checkpointAfterBoss(t, game.run.floor);
    const meta = game.meta;
    if (!meta.checkpoints.includes(cp)) meta.checkpoints.push(cp);
    meta.checkpoints.sort((a, b) => a - b);
    const kind = guardianFor(t, game.info.section);
    meta.guardians[kind] = (meta.guardians[kind] ?? 0) + 1;
    meta.stats.guardianKills++;
    const souls = t.progression.souls.guardian + t.progression.souls.guardianPerSection * (game.info.section - 1);
    if (!game.sandbox) {
      meta.souls += souls;
      game.telemetry.soulsEarned += souls;
    }
    healPlayer(game, p.maxHp * 0.5, true);
    syncPurse(game);
    emit(game, 'checkpoint', { floor: cp, guardian: kind, souls });
    if (game.info.isFinal) {
      game.mode = 'victory';
      emit(game, 'victory', { floor: game.run.floor });
      return;
    }
    const rar = rand(game.rng.gen) < 0.2 ? 'legendaire' : 'rare';
    room.interact = { kind: 'loot', x: cx, y: cy, r: 30, used: false, item: generateItem(game, { rarity: rar }) };
    prepareDoors(game, true);
    return;
  }
  switch (plan.reward) {
    case 'boon':
      room.interact = { kind: 'boon', x: cx, y: cy, r: 30, used: false, family: plan.family ?? randomFamily(game) };
      break;
    case 'loot': {
      const bonus = plan.elite ? t.loot.eliteRarityBonus : 1;
      room.interact = { kind: 'loot', x: cx, y: cy, r: 30, used: false, item: generateItem(game, { rarity: rollRarity(game, bonus) }) };
      break;
    }
    case 'gold': {
      const total = Math.round(randomGold(game) * 3 * p.stats.goldFindMult);
      const n = 6;
      for (let i = 0; i < n; i++) spawnPickup(game, 'gold', cx, cy, Math.max(1, Math.round(total / n)));
      break;
    }
    case 'heal':
      spawnPickup(game, 'heal', cx, cy, Math.round(p.maxHp * 0.3));
      break;
    default:
      break;
  }
  prepareDoors(game, !room.interact);
}

/**
 * Portes de sortie, composées par le PLAN DE SECTION (tuning.section) : Gardien au 18e étage,
 * portes imposées à mi-section et dans l'antichambre, épreuve d'élite garantie à certains
 * index, sinon deux récompenses tirées au hasard. Après un Gardien : « section suivante » ou
 * « Ville » (téléportation, fin du run).
 */
function prepareDoors(game, openNow) {
  const t = game.tuning;
  const next = floorInfo(t, game.run.floor + 1);
  const fixed = t.section.fixedDoors[next.indexInSection];
  let rewards;
  if (next.isBoss) {
    rewards = [{ reward: 'boss' }];
  } else if (fixed) {
    rewards = fixed.map((reward) => ({ reward }));
  } else {
    const first = weightedPick(game.rng.gen, DOOR_WEIGHTS, (d) => d.weight).reward;
    let second = first;
    let guard = 0;
    while (second === first && guard++ < 20) second = weightedPick(game.rng.gen, DOOR_WEIGHTS, (d) => d.weight).reward;
    rewards = [{ reward: first }, { reward: second }];
    if (t.section.eliteAt.includes(next.indexInSection) && first !== 'elite' && second !== 'elite') rewards[1] = { reward: 'elite' };
  }
  if (game.room.kind === 'boss' && !game.sandbox) rewards = [rewards[0], { reward: 'town' }];
  for (const r of rewards) if (r.reward === 'boon') r.family = randomFamily(game);
  makeDoors(game, rewards);
  for (const d of game.room.doors) d.open = openNow;
  if (openNow) emit(game, 'doorsOpen', { count: game.room.doors.length });
}

function openDoors(game) {
  if (game.room.doors.every((d) => d.open)) return;
  for (const d of game.room.doors) d.open = true;
  emit(game, 'doorsOpen', { count: game.room.doors.length });
}

// ---------------------------------------------------------------- choix (menus)

/** Ouvre le menu de l'objet d'interaction touché. La simulation se met en pause. */
export function openInteract(game) {
  const it = game.room.interact;
  if (!it || it.used) return;
  const run = game.run;
  let choice = null;
  if (it.kind === 'boon') {
    const offers = it.offers ?? (it.offers = rollBoonOffer(game, it.family));
    choice = { kind: 'boon', family: it.family, familyName: FAMILIES[it.family].name, color: FAMILIES[it.family].color, options: offers.map((o) => describeBoon(o)) };
  } else if (it.kind === 'loot') {
    choice = { kind: 'loot', item: describeItem(it.item), equipped: describeItem(run.items[it.item.slot]), salvage: salvageValue(it.item), wieldable: canWield(game, it.item) };
  } else if (it.kind === 'shop') {
    choice = { kind: 'shop', gold: run.gold, offers: it.offers.map((o) => ({ ...o, item: o.item ? describeItem(o.item) : null, equipped: o.item ? describeItem(run.items[o.item.slot]) : null })) };
  } else if (it.kind === 'event') {
    const ev = EVENTS.find((e) => e.id === it.event);
    const p = game.player;
    const gadgetFull = p.gadgetCharges >= game.tuning.gadget.chargesPerSection + p.stats.gadgetChargesBonus;
    const unusable = (o) => !!(o.cost && run.gold < o.cost) || (o.effect === 'gadget1' && gadgetFull);
    choice = { kind: 'event', title: ev.title, text: ev.text, options: ev.options.map((o) => ({ label: o.label, disabled: unusable(o) })) };
  }
  if (!choice) return;
  game.mode = 'choice';
  game.choice = choice;
  emit(game, 'choiceOpen', { kind: choice.kind });
}

export function describeBoon(o) {
  const def = boonDef(o.id);
  const rar = RARITIES.find((r) => r.id === o.rarity);
  const fam = def.family ? FAMILIES[def.family] : null;
  return {
    id: o.id,
    name: def.name,
    text: boonText(def, o.rarity),
    rarity: o.rarity,
    rarityName: rar.name,
    slot: def.slot,
    level: o.level,
    duo: !!def.families,
    color: fam?.color ?? '#ffffff',
    familyName: fam?.name ?? def.families.map((f) => FAMILIES[f].name).join(' + '),
  };
}

/** Une arme ne se manie que par sa classe (le coffre la garde pour plus tard). */
export function canWield(game, item) {
  if (item.slot !== 'arme') return true;
  const c = game.tuning.classes[game.kit?.classId] ?? game.tuning.classes[Object.keys(game.tuning.classes)[0]];
  return c.weapons.includes(item.weaponType ?? 'lame');
}

export function describeItem(item) {
  if (!item) return null;
  const rar = ITEM_RARITIES.find((r) => r.id === item.rarity);
  const power = item.power ? LEGENDARY_POWERS.find((p) => p.id === item.power) : null;
  return {
    id: item.id,
    slot: item.slot,
    slotName: SLOT_NAMES[item.slot],
    weaponType: item.weaponType ?? null,
    name: item.name,
    rarity: item.rarity,
    rarityName: rar.name,
    color: rar.color,
    level: item.level,
    lines: [baseText(item), ...item.affixes.map(affixText)].filter(Boolean),
    power: power?.text ?? null,
    score: item.score,
  };
}

function rollShop(game) {
  const e = game.tuning.economy;
  const fam = randomFamily(game);
  const item = randomShopItem(game);
  const boon = rollBoonOffer(game, fam)[0];
  const bd = describeBoon(boon);
  return [
    { kind: 'heal', price: e.shopHealPrice, label: 'Élixir de sang', text: 'Rend 40 % des PV.', sold: false },
    { kind: 'boon', price: e.shopBoonPrice, label: bd.name, text: bd.text, boon, color: FAMILIES[fam].color, sold: false },
    { kind: 'item', price: priceOf(game, item), label: item.name, text: '', item, sold: false },
  ];
}

export function applyCommand(game, cmd) {
  if (cmd.type === 'respawn') return respawn(game, cmd.floor);
  if (cmd.type === 'returnToTown') {
    // Depuis l'écran de mort (Charon a déjà pris sa part), ou au portail ouvert après un Gardien.
    // Jamais en plein combat : quitter un run en cours, c'est « abandon » (taxé comme une mort).
    const portal = game.mode === 'play' && game.room.doors.some((d) => d.reward === 'town' && d.open);
    if (game.mode !== 'dead' && !portal) return false;
    return returnToTown(game);
  }
  if (cmd.type === 'abandon') {
    // Abandonner = mourir : Charon prend sa part, le temporaire est perdu, retour en Ville.
    if (game.mode !== 'play' && game.mode !== 'choice') return false;
    onDeath(game);
    game.mode = 'play';
    return returnToTown(game);
  }
  if (game.mode !== 'choice' || !game.choice) return false;
  const it = game.room.interact;
  const ch = game.choice;
  const run = game.run;
  const p = game.player;
  if (ch.kind === 'boon' && cmd.type === 'choose') {
    const offer = it.offers[cmd.index];
    if (!offer) return false;
    addBoon(run, offer);
    recomputeStats(game);
    emit(game, 'boonGain', { id: offer.id, rarity: offer.rarity });
    return closeChoice(game);
  }
  if (ch.kind === 'loot') {
    if (cmd.type === 'equip') {
      if (!canWield(game, it.item)) return false;
      // L'objet porté n'est jamais perdu : il part au coffre (Ville).
      const old = run.items[it.item.slot];
      if (old) stashLoot(game.meta, old);
      run.items[it.item.slot] = it.item;
      recomputeStats(game);
      emit(game, 'equip', { slot: it.item.slot, rarity: it.item.rarity });
      return closeChoice(game);
    }
    if (cmd.type === 'stash') {
      stashLoot(game.meta, it.item);
      emit(game, 'stash', { slot: it.item.slot, rarity: it.item.rarity });
      return closeChoice(game);
    }
    if (cmd.type === 'salvage') {
      run.gold += salvageValue(it.item);
      emit(game, 'gold', { x: p.x, y: p.y, amount: salvageValue(it.item) });
      return closeChoice(game);
    }
    return false;
  }
  if (ch.kind === 'shop') {
    if (cmd.type === 'close') return closeChoice(game);
    if (cmd.type !== 'choose') return false;
    const offer = it.offers[cmd.index];
    if (!offer || offer.sold || run.gold < offer.price) return false;
    run.gold -= offer.price;
    offer.sold = true;
    if (offer.kind === 'heal') healPlayer(game, p.maxHp * 0.4, true);
    if (offer.kind === 'boon') addBoon(run, offer.boon);
    if (offer.kind === 'item') {
      if (canWield(game, offer.item)) {
        const old = run.items[offer.item.slot];
        if (old) stashLoot(game.meta, old);
        run.items[offer.item.slot] = offer.item;
      } else stashLoot(game.meta, offer.item);
    }
    syncPurse(game);
    recomputeStats(game);
    emit(game, 'buy', { kind: offer.kind });
    openShopRefresh(game);
    return true;
  }
  if (ch.kind === 'event' && cmd.type === 'choose') {
    const ev = EVENTS.find((e) => e.id === it.event);
    const opt = ev.options[cmd.index];
    if (!opt) return false;
    if (ch.options[cmd.index]?.disabled) return false;
    if (applyEvent(game, opt)) {
      // Le coffre maudit a posé un butin à ramasser : les portes attendent ce choix-là.
      game.mode = 'play';
      game.choice = null;
      return true;
    }
    return closeChoice(game);
  }
  return false;
}

function openShopRefresh(game) {
  game.mode = 'play';
  game.room.interact.used = false;
  openInteract(game);
}

function applyEvent(game, opt) {
  const run = game.run;
  const p = game.player;
  switch (opt.effect) {
    case 'bloodBoon': {
      p.hp = Math.max(1, Math.round(p.hp - p.maxHp * 0.25));
      const fam = randomFamily(game);
      const offer = rollBoonOffer(game, fam)[0];
      offer.rarity = 'rare';
      addBoon(run, offer);
      emit(game, 'boonGain', { id: offer.id, rarity: offer.rarity });
      break;
    }
    case 'heal40':
      healPlayer(game, p.maxHp * 0.4, true);
      break;
    case 'gadget1':
      p.gadgetCharges++;
      break;
    case 'cursedChest': {
      p.hp = Math.max(1, p.hp - 20);
      const item = generateItem(game, { rarity: 'rare' });
      const spot = rewardSpot(game.room);
      game.room.interact = { kind: 'loot', x: spot.x, y: spot.y, r: 30, used: false, item };
      recomputeStats(game);
      return true;
    }
    case 'mammonBoon': {
      run.gold -= opt.cost;
      const offer = rollBoonOffer(game, 'avarice')[0];
      addBoon(run, offer);
      emit(game, 'boonGain', { id: offer.id, rarity: offer.rarity });
      break;
    }
    case 'gold25':
      run.gold += 25;
      emit(game, 'gold', { x: p.x, y: p.y, amount: 25 });
      break;
    default:
      break;
  }
  recomputeStats(game);
  return false;
}

function closeChoice(game) {
  game.mode = 'play';
  game.choice = null;
  if (game.room.interact) game.room.interact.used = true;
  openDoors(game);
  emit(game, 'choiceClose');
  return true;
}

// ---------------------------------------------------------------- mort, reprise, Ville

/**
 * Mort du héros (appelé une fois, quand l'écran de mort s'ouvre) : Charon prélève sa part de
 * la bourse, le récapitulatif dit ce qui est PERDU (temporaire) et ce qui est GARDÉ (permanent).
 */
export function onDeath(game) {
  const run = game.run;
  const meta = game.meta;
  const keep = Math.min(1, game.tuning.economy.deathGoldKeep + (game.player.stats.deathGoldKeepBonus ?? 0));
  const before = run.gold;
  if (!game.sandbox && !game.practice) {
    run.gold = Math.floor(run.gold * keep);
    meta.stats.deaths++;
  }
  run.deathRecap = {
    floor: run.floor,
    boonsLost: run.boons.length,
    boonNames: run.boons.map((b) => boonDef(b.id)?.name ?? b.id),
    goldLost: before - run.gold,
    gold: run.gold,
    souls: meta.souls,
    soulsEarned: game.telemetry.soulsEarned,
    checkpoint: lastCheckpoint(game),
  };
  syncPurse(game);
}

/** Dernier checkpoint débloqué (point de reprise par défaut). */
export function lastCheckpoint(game) {
  const cps = game.meta.checkpoints;
  return cps[cps.length - 1] ?? 1;
}

function revive(game) {
  const p = game.player;
  const t = game.tuning;
  recomputeStats(game);
  p.hp = p.maxHp;
  p.superCharge = t.super.startCharge ?? 0;
  p.dashCharges = t.dash.charges + p.stats.dashChargesBonus;
  p.gadgetCharges = t.gadget.chargesPerSection + p.stats.gadgetChargesBonus;
  p.skillCd = 0;
  p.iframes = 1.0;
  p.freeze = 0;
  p.state = 'free';
  game.mode = 'play';
  game.choice = null;
  game.deathT = 0;
}

/**
 * Reprise après la mort : au checkpoint demandé (s'il est débloqué), sinon au DERNIER.
 * Le TEMPORAIRE repart de zéro (bénédictions vidées) ; le PERMANENT reste (équipement, classe,
 * kit, Âmes, déblocages). La bourse a déjà payé Charon (onDeath).
 */
export function respawn(game, floor) {
  if (game.mode !== 'dead') return false;
  const cps = game.meta.checkpoints;
  const target = cps.includes(floor) ? floor : lastCheckpoint(game);
  const run = game.run;
  if (game.sandbox) {
    // Arène d'essai : on recommence l'arène, jamais un checkpoint profond.
    revive(game);
    emit(game, 'respawn', { floor: 1 });
    enterFloor(game, 1, { reward: 'boon' });
    return true;
  }
  if (game.practice) {
    // Entraînement : le même Gardien, aussitôt.
    run.boons = [];
    revive(game);
    emit(game, 'respawn', { floor: run.floor });
    enterFloor(game, run.floor, null);
    return true;
  }
  run.boons = [];
  revive(game);
  emit(game, 'respawn', { floor: target, boonsLost: run.deathRecap?.boonsLost ?? 0 });
  enterFloor(game, target, { reward: 'boon', family: randomFamily(game) });
  return true;
}

/**
 * Fin du run et retour en Ville : depuis l'écran de mort, ou par le portail qui suit un
 * Gardien. Le temporaire est abandonné avec la partie ; main sauvegarde le profil.
 */
export function returnToTown(game) {
  if (game.mode !== 'dead' && game.mode !== 'play') return false;
  syncPurse(game);
  game.mode = 'town';
  game.choice = null;
  emit(game, 'returnTown', { floor: game.run.floor, checkpoint: lastCheckpoint(game) });
  return true;
}
