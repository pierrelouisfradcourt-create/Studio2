// LABORATOIRE DU FEEL — D5, D8, D9 restent OUVERTES : le prototype permet de les comparer.
//
//   D5  lab.dashStrike    : quand une attaque devient FRAPPE DE DASH
//         fin        — attaquer dans la fin du dash (dernier 45 %) coupe la ruée, ou juste après
//         toutDash   — attaquer à N'IMPORTE QUEL moment du dash coupe la ruée en frappe
//         apresDash  — la ruée va toujours au bout ; seule une attaque juste APRÈS devient frappe
//   D8  lab.hitstop       : gel d'impact
//         global     — toute la scène se fige (projectiles, autres ennemis compris)
//         local      — seuls l'attaquant et la ou les cibles se figent ; le reste du monde continue
//   D9  lab.comboMobility : mobilité pendant le combo
//         ancre      — 20 % de la vitesse, annulations tardives : chaque coup engage
//         mobile     — 50 %, annulations actuelles (réglage de référence)
//         fluide     — 75 %, annulations très tôt : on danse en frappant
//
// Chaque variante écrit des clés ordinaires du tuning de la partie : le code de combat ne
// connaît pas le labo. La variante par défaut de chaque axe redonne EXACTEMENT les valeurs
// de config.mjs (aucun test ni réglage existant ne bouge tant qu'on ne choisit rien).

export const LAB_AXES = {
  dashStrike: {
    label: 'D5 · Frappe de dash',
    options: {
      fin: { label: 'Fin du dash', text: 'Attaquer dans le dernier 45 % du dash ou juste après.', set: { 'dash.strikeCancelFrom': 0.45, 'dash.strikeWindow': 0.3 } },
      toutDash: { label: 'Tout le dash', text: 'Attaquer à n\'importe quel moment du dash le coupe en frappe.', set: { 'dash.strikeCancelFrom': 1, 'dash.strikeWindow': 0.3 } },
      apresDash: { label: 'Après le dash', text: 'Le dash va au bout ; une attaque juste après devient frappe.', set: { 'dash.strikeCancelFrom': 0, 'dash.strikeWindow': 0.3 } },
    },
  },
  hitstop: {
    label: 'D8 · Gel d\'impact',
    options: {
      global: { label: 'Global', text: 'Toute la scène se fige à l\'impact.', set: { hitstopMode: 'global' } },
      local: { label: 'Local', text: 'Seuls le héros et ses cibles se figent ; le reste continue.', set: { hitstopMode: 'local' } },
    },
  },
  comboMobility: {
    label: 'D9 · Mobilité du combo',
    options: {
      ancre: { label: 'Ancré', text: '20 % de vitesse, annulations tardives.', set: { 'player.attackMoveMult': 0.2, 'player.cancelMult': 1.6 } },
      mobile: { label: 'Mobile', text: '50 % de vitesse, annulations de référence.', set: { 'player.attackMoveMult': 0.5, 'player.cancelMult': 1 } },
      fluide: { label: 'Fluide', text: '75 % de vitesse, annulations très tôt.', set: { 'player.attackMoveMult': 0.75, 'player.cancelMult': 0.35 } },
    },
  },
};

function setPath(obj, path, value) {
  const keys = path.split('.');
  const last = keys.pop();
  let o = obj;
  for (const k of keys) o = o[k];
  o[last] = value;
}

/** Applique les variantes choisies (tuning.lab) au tuning de la partie. Idempotent. */
export function applyLab(tuning) {
  for (const [axis, def] of Object.entries(LAB_AXES)) {
    const choice = tuning.lab?.[axis];
    const opt = def.options[choice] ?? def.options[Object.keys(def.options)[0]];
    for (const [path, v] of Object.entries(opt.set)) setPath(tuning, path, v);
  }
  return tuning;
}

/** Change une variante en cours de partie (pause → Labo) ; rend false si inconnue. */
export function setLab(tuning, axis, choice) {
  if (!LAB_AXES[axis]?.options[choice]) return false;
  tuning.lab[axis] = choice;
  applyLab(tuning);
  return true;
}

export function labSummary(tuning) {
  return Object.entries(LAB_AXES).map(([axis, def]) => ({ axis, label: def.label, choice: tuning.lab[axis], choiceLabel: def.options[tuning.lab[axis]]?.label ?? '?' }));
}
