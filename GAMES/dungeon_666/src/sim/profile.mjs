// PROFIL PERMANENT — tout ce que la mort ne reprend JAMAIS.
//
//   PERMANENT (ce fichier)            TEMPORAIRE (game.run, remis à zéro à la mort)
//   classe, armes, équipement,        bénédictions (bonus, pouvoirs, améliorations,
//   coffre, compétences, gadgets,     synergies de build), PV, charges, étage courant
//   déblocages de la Ville, Âmes,
//   checkpoints / points de TP
//
// L'or est la bourse du héros : elle le suit d'un run à l'autre, mais Charon prélève sa part
// à chaque mort (economy.deathGoldKeep). Les Âmes, elles, ne se perdent jamais.
//
// Fonctions PURES sur des objets JSON (aucun DOM) : la Ville (src/ui/town.mjs) appelle ces
// opérations, main.mjs sauvegarde le résultat. Chaque opération rend { ok, reason? }.

import { floorInfo } from './floors.mjs';

export const PROFILE_SCHEMA = 3;
export const STASH_MAX = 24;
export const EQUIP_SLOTS = ['arme', 'armure', 'talisman'];

/** Profil d'un nouveau joueur. `tuning` : pour connaître le kit de départ. */
export function createProfile(tuning) {
  const start = startingKit(tuning);
  return {
    schema: PROFILE_SCHEMA,
    checkpoints: [1], // étages où l'on peut (re)partir : 1, puis l'étage qui suit chaque Gardien
    bestFloor: 1,
    souls: 0, // Âmes : monnaie permanente de la Ville
    gold: 0, // bourse (taxée à la mort)
    unlocked: {
      classes: [start.classId],
      weapons: [start.weaponType],
      skills: [start.skillId],
      gadgets: [start.gadgetId],
    },
    upgrades: {}, // id du Sanctuaire -> niveau
    loadout: { classId: start.classId, skillId: start.skillId, gadgetId: start.gadgetId },
    equipment: { arme: null, armure: null, talisman: null }, // rempli par starterItems à la 1re partie
    stash: [],
    itemSeq: 1,
    guardians: {}, // modèle de Gardien -> victoires
    stats: { runs: 0, deaths: 0, kills: 0, guardianKills: 0 },
  };
}

function startingKit(tuning) {
  const classId = Object.keys(tuning.classes)[0];
  const c = tuning.classes[classId];
  return { classId, weaponType: c.weapons[0], skillId: c.skills[0], gadgetId: c.gadgets[0] };
}

const isObj = (v) => !!v && typeof v === 'object' && !Array.isArray(v);
const intIn = (v, lo, hi) => Number.isInteger(v) && v >= lo && v <= hi;
const idList = (v, known) => (Array.isArray(v) ? [...new Set(v.filter((id) => typeof id === 'string' && known.includes(id)))] : []);

/** Objet d'équipement lisible (forme minimale ; la forme évolue pendant le prototype). */
export function isItem(it) {
  return isObj(it) && EQUIP_SLOTS.includes(it.slot) && Array.isArray(it.affixes) && typeof it.name === 'string' && isObj(it.base);
}

/**
 * Profil validé champ par champ : une sauvegarde ancienne (schéma 1-2 : {checkpoints,
 * bestFloor, items, snapshots}) ou corrompue retombe sur des défauts au lieu de bloquer.
 * Les « instantanés de build » des anciennes versions sont abandonnés : le temporaire ne
 * survit plus à la mort.
 */
export function sanitizeProfile(raw, tuning) {
  const def = createProfile(tuning);
  if (!isObj(raw)) return def;
  const total = tuning.floors.total;
  const out = def;
  // Un checkpoint est le 1er étage d'une section (l'étage qui suit un Gardien). Ceux d'avant la
  // V2 (Gardien tous les 6 étages : 7, 13…) ne sont plus des points de reprise et sont écartés.
  const cps = Array.isArray(raw.checkpoints) ? raw.checkpoints.filter((f) => intIn(f, 1, total) && floorInfo(tuning, f).indexInSection === 1) : [];
  out.checkpoints = [...new Set([1, ...cps])].sort((a, b) => a - b);
  out.bestFloor = intIn(raw.bestFloor, 1, total) ? raw.bestFloor : 1;
  out.souls = Number.isFinite(raw.souls) && raw.souls >= 0 ? Math.floor(raw.souls) : 0;
  out.gold = Number.isFinite(raw.gold) && raw.gold >= 0 ? Math.floor(raw.gold) : 0;
  const u = isObj(raw.unlocked) ? raw.unlocked : {};
  const known = {
    classes: Object.keys(tuning.classes),
    weapons: Object.keys(tuning.weapons),
    skills: Object.keys(tuning.skills),
    gadgets: Object.keys(tuning.gadgets),
  };
  for (const k of Object.keys(known)) out.unlocked[k] = [...new Set([...def.unlocked[k], ...idList(u[k], known[k])])];
  for (const id of out.unlocked.classes) grantStarterKit(out, tuning, id);
  if (isObj(raw.upgrades)) {
    for (const [id, lv] of Object.entries(raw.upgrades)) {
      const up = tuning.town?.upgrades?.[id];
      if (up && intIn(lv, 0, up.max)) out.upgrades[id] = lv;
    }
  }
  if (isObj(raw.loadout)) {
    const l = raw.loadout;
    if (out.unlocked.classes.includes(l.classId)) out.loadout.classId = l.classId;
    if (out.unlocked.skills.includes(l.skillId)) out.loadout.skillId = l.skillId;
    if (out.unlocked.gadgets.includes(l.gadgetId)) out.loadout.gadgetId = l.gadgetId;
  }
  // Ancien schéma : l'équipement vivait dans `items`.
  const eq = isObj(raw.equipment) ? raw.equipment : isObj(raw.items) ? raw.items : {};
  for (const s of EQUIP_SLOTS) out.equipment[s] = isItem(eq[s]) && eq[s].slot === s ? eq[s] : null;
  out.stash = Array.isArray(raw.stash) ? raw.stash.filter(isItem).slice(0, STASH_MAX) : [];
  out.itemSeq = intIn(raw.itemSeq, 1, 1e9) ? raw.itemSeq : 1;
  for (const it of [...Object.values(out.equipment), ...out.stash]) if (it) ensureUid(out, it);
  if (isObj(raw.guardians)) {
    for (const [k, n] of Object.entries(raw.guardians)) if (tuning.boss[k] && intIn(n, 0, 1e6)) out.guardians[k] = n;
  }
  if (isObj(raw.stats)) for (const k of Object.keys(out.stats)) if (intIn(raw.stats[k], 0, 1e9)) out.stats[k] = raw.stats[k];
  fixLoadout(out, tuning);
  return out;
}

/** Identifiant stable d'un objet dans le profil (les `id` de partie se recyclent). */
export function ensureUid(profile, item) {
  if (!item.uid) item.uid = `i${profile.itemSeq++}`;
  return item.uid;
}

/** La compétence, le gadget et l'arme équipés doivent appartenir à la classe choisie. */
export function fixLoadout(profile, tuning) {
  const c = tuning.classes[profile.loadout.classId] ?? tuning.classes[Object.keys(tuning.classes)[0]];
  const l = profile.loadout;
  const firstOwned = (list, owned) => list.find((id) => owned.includes(id)) ?? list[0];
  if (!c.skills.includes(l.skillId) || !profile.unlocked.skills.includes(l.skillId)) l.skillId = firstOwned(c.skills, profile.unlocked.skills);
  if (!c.gadgets.includes(l.gadgetId) || !profile.unlocked.gadgets.includes(l.gadgetId)) l.gadgetId = firstOwned(c.gadgets, profile.unlocked.gadgets);
  const w = profile.equipment.arme;
  if (w && !c.weapons.includes(w.weaponType ?? 'lame')) {
    // Arme d'une autre classe : elle retourne au coffre, la meilleure arme compatible la remplace.
    stashPush(profile, w);
    profile.equipment.arme = takeBestFromStash(profile, 'arme', (it) => c.weapons.includes(it.weaponType ?? 'lame'));
  }
}

function stashPush(profile, item) {
  ensureUid(profile, item);
  profile.stash.push(item);
  // Coffre plein : le moins bon part (jamais l'objet qu'on vient d'y ranger).
  while (profile.stash.length > STASH_MAX) {
    let worst = 0;
    for (let i = 1; i < profile.stash.length - 1; i++) if ((profile.stash[i].score ?? 0) < (profile.stash[worst].score ?? 0)) worst = i;
    profile.stash.splice(worst, 1);
  }
}

function takeBestFromStash(profile, slot, ok = () => true) {
  let best = -1;
  for (let i = 0; i < profile.stash.length; i++) {
    const it = profile.stash[i];
    if (it.slot !== slot || !ok(it)) continue;
    if (best < 0 || (it.score ?? 0) > (profile.stash[best].score ?? 0)) best = i;
  }
  return best < 0 ? null : profile.stash.splice(best, 1)[0];
}

// ---------------------------------------------------------------- opérations de la Ville

/** Prix de déblocage d'une entrée de contenu (0 = possédée d'office). */
export function unlockCost(tuning, kind, id) {
  const table = { classes: tuning.classes, weapons: tuning.weapons, skills: tuning.skills, gadgets: tuning.gadgets }[kind];
  return table?.[id]?.cost ?? 0;
}

export function unlock(profile, tuning, kind, id) {
  const table = { classes: tuning.classes, weapons: tuning.weapons, skills: tuning.skills, gadgets: tuning.gadgets }[kind];
  if (!table?.[id]) return { ok: false, reason: 'inconnu' };
  if (profile.unlocked[kind].includes(id)) return { ok: false, reason: 'déjà débloqué' };
  const cost = unlockCost(tuning, kind, id);
  if (profile.souls < cost) return { ok: false, reason: 'Âmes insuffisantes' };
  profile.souls -= cost;
  profile.unlocked[kind].push(id);
  if (kind === 'classes') grantStarterKit(profile, tuning, id);
  if (kind === 'weapons') {
    // Une arme débloquée est forgée aussitôt en exemplaire commun, rangé au coffre.
    stashPush(profile, starterWeapon(tuning, id));
  }
  return { ok: true };
}

/**
 * Kit de départ d'une classe (1re arme, 1re compétence, 1er gadget) : possédé dès que la classe
 * l'est. Sans cela, la classe choisie équipait une compétence encore « à débloquer » au Grimoire.
 */
function grantStarterKit(profile, tuning, classId) {
  const c = tuning.classes[classId];
  if (!c) return;
  for (const [kind, list] of [['weapons', c.weapons], ['skills', c.skills], ['gadgets', c.gadgets]]) {
    const id = list?.[0];
    if (id && !profile.unlocked[kind].includes(id)) profile.unlocked[kind].push(id);
  }
}

/** Exemplaire commun d'un type d'arme (sans affixe), pour la Forge et le départ. */
export function starterWeapon(tuning, weaponType) {
  const w = tuning.weapons[weaponType];
  return {
    slot: 'arme', weaponType, rarity: 'commun', name: w.starterName ?? w.name, level: 1,
    affixes: [], power: null, base: { damage: tuning.weaponBase * (w.baseMult ?? 1) }, score: 0,
  };
}

export function upgradeCost(tuning, id, level) {
  const up = tuning.town?.upgrades?.[id];
  if (!up || level >= up.max) return null;
  return up.costs[level] ?? null;
}

export function buyUpgrade(profile, tuning, id) {
  const lv = profile.upgrades[id] ?? 0;
  const cost = upgradeCost(tuning, id, lv);
  if (cost === null) return { ok: false, reason: 'niveau maximal' };
  if (profile.souls < cost) return { ok: false, reason: 'Âmes insuffisantes' };
  profile.souls -= cost;
  profile.upgrades[id] = lv + 1;
  return { ok: true };
}

export function selectClass(profile, tuning, classId) {
  if (!profile.unlocked.classes.includes(classId)) return { ok: false, reason: 'classe verrouillée' };
  profile.loadout.classId = classId;
  const c = tuning.classes[classId];
  if (!c.weapons.includes(profile.equipment.arme?.weaponType ?? 'lame')) {
    if (profile.equipment.arme) stashPush(profile, profile.equipment.arme);
    profile.equipment.arme = takeBestFromStash(profile, 'arme', (it) => c.weapons.includes(it.weaponType ?? 'lame'));
    // Aucune arme de la classe au coffre : on forge l'arme de départ (toujours disponible).
    if (!profile.equipment.arme) {
      const wt = c.weapons.find((w) => profile.unlocked.weapons.includes(w)) ?? c.weapons[0];
      if (!profile.unlocked.weapons.includes(wt)) profile.unlocked.weapons.push(wt);
      profile.equipment.arme = starterWeapon(tuning, wt);
      ensureUid(profile, profile.equipment.arme);
    }
  }
  fixLoadout(profile, tuning);
  return { ok: true };
}

export function selectSkill(profile, tuning, skillId) {
  const c = tuning.classes[profile.loadout.classId];
  if (!profile.unlocked.skills.includes(skillId) || !c.skills.includes(skillId)) return { ok: false, reason: 'indisponible' };
  profile.loadout.skillId = skillId;
  return { ok: true };
}

export function selectGadget(profile, tuning, gadgetId) {
  const c = tuning.classes[profile.loadout.classId];
  if (!profile.unlocked.gadgets.includes(gadgetId) || !c.gadgets.includes(gadgetId)) return { ok: false, reason: 'indisponible' };
  profile.loadout.gadgetId = gadgetId;
  return { ok: true };
}

/** Équipe un objet du coffre ; l'objet porté prend sa place au coffre. */
export function equipFromStash(profile, tuning, uid) {
  const i = profile.stash.findIndex((it) => it.uid === uid);
  if (i < 0) return { ok: false, reason: 'objet introuvable' };
  const item = profile.stash[i];
  if (item.slot === 'arme') {
    const c = tuning.classes[profile.loadout.classId];
    if (!c.weapons.includes(item.weaponType ?? 'lame')) return { ok: false, reason: `arme réservée à une autre classe` };
  }
  profile.stash.splice(i, 1);
  const cur = profile.equipment[item.slot];
  profile.equipment[item.slot] = item;
  if (cur) stashPush(profile, cur);
  return { ok: true };
}

/** Recycle un objet du coffre en Âmes. */
export function salvageFromStash(profile, tuning, uid) {
  const i = profile.stash.findIndex((it) => it.uid === uid);
  if (i < 0) return { ok: false, reason: 'objet introuvable' };
  const [item] = profile.stash.splice(i, 1);
  profile.souls += salvageSouls(tuning, item);
  return { ok: true };
}

export function salvageSouls(tuning, item) {
  const table = tuning.town?.salvageSouls ?? { commun: 1, magique: 3, rare: 8, legendaire: 20 };
  return table[item.rarity] ?? 1;
}

/** Un objet trouvé en donjon qu'on ne porte pas file au coffre (il n'est jamais perdu). */
export function stashLoot(profile, item) {
  stashPush(profile, item);
}
