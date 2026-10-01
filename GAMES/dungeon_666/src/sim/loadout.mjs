// Résolution du KIT équipé : classe + arme portée + compétence + gadget + Super.
//
// Les blocs actifs de la copie de tuning de la partie deviennent des RÉFÉRENCES vers l'entrée
// choisie (tuning.combo === tuning.weapons[type].combo, etc.). Le reste de la simulation lit
// toujours tuning.combo / tuning.skill / tuning.gadget / tuning.super, sans connaître les classes.

const DEFAULT_WEAPON = 'lame';

export function classOf(game) {
  const t = game.tuning;
  return t.classes[game.meta.loadout?.classId] ?? t.classes[Object.keys(t.classes)[0]];
}

export function classIdOf(game) {
  const t = game.tuning;
  const id = game.meta.loadout?.classId;
  return t.classes[id] ? id : Object.keys(t.classes)[0];
}

/** Type d'arme porté : celui de l'objet d'arme équipé, sinon l'arme de départ de la classe. */
export function weaponTypeOf(game) {
  const t = game.tuning;
  const wt = game.run.items.arme?.weaponType;
  if (wt && t.weapons[wt]) return wt;
  return classOf(game).weapons[0] ?? DEFAULT_WEAPON;
}

/** (Re)branche le kit actif. Appelé à la création de la partie et à chaque changement d'arme. */
export function resolveKit(game) {
  const t = game.tuning;
  const c = classOf(game);
  const l = game.meta.loadout ?? {};
  const w = t.weapons[weaponTypeOf(game)];
  t.combo = w.combo;
  t.dashStrike = w.dashStrike;
  t.weapon = w;
  const skillId = c.skills.includes(l.skillId) && t.skills[l.skillId] ? l.skillId : c.skills[0];
  const gadgetId = c.gadgets.includes(l.gadgetId) && t.gadgets[l.gadgetId] ? l.gadgetId : c.gadgets[0];
  t.skill = t.skills[skillId];
  t.gadget = t.gadgets[gadgetId];
  t.super = t.supers[c.super] ?? t.super;
  game.kit = { classId: classIdOf(game), weaponType: weaponTypeOf(game), skillId, gadgetId, superId: c.super };
  return game.kit;
}
