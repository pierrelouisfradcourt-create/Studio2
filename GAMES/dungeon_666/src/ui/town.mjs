// LA VILLE (hub) — Dité, dernière cité avant la descente. Écran DOM, pensé pour le pouce.
//
// Elle ne contient AUCUNE règle : chaque bouton appelle une action de `actions` (main.mjs), qui
// applique l'opération pure correspondante du profil (src/sim/profile.mjs) puis sauvegarde.
// Tout ce qui s'achète ou se choisit ici est PERMANENT ; les bénédictions du donjon, elles,
// meurent avec le run.

import { el, button, itemCard } from './dom.mjs';
import { floorInfo, guardianFor } from '../sim/floors.mjs';
import { unlockCost, upgradeCost, salvageSouls } from '../sim/profile.mjs';
import { describeItem } from '../sim/run.mjs';
import { LAB_AXES } from '../sim/lab.mjs';

export const TOWN_TABS = [
  { id: 'portail', label: 'Portail' },
  { id: 'classe', label: 'Classe' },
  { id: 'armurerie', label: 'Armurerie' },
  { id: 'equipement', label: 'Coffre' },
  { id: 'grimoire', label: 'Grimoire' },
  { id: 'sanctuaire', label: 'Sanctuaire' },
  { id: 'labo', label: 'Labo du feel' },
];

/**
 * view    : { profile, tuning (registre du contenu), tab, lab (choix D5/D8/D9), touch }
 * actions : { setTab, depart(floor), arena(), practice(kind), selectClass, unlock(kind, id),
 *             selectSkill, selectGadget, equip(uid), salvage(uid), buyUpgrade(id), setLab(axis, c) }
 */
export function buildTown(p, view, actions) {
  p.className = 'panel town';
  const { profile, tuning } = view;
  const head = el('div', 'town-head');
  head.appendChild(el('div', 'kicker', 'Dité · la cité des damnés'));
  const cls = tuning.classes[profile.loadout.classId];
  const wallet = el('div', 'town-wallet');
  wallet.appendChild(el('span', 'souls', `◆ ${profile.souls} Âmes`));
  wallet.appendChild(el('span', 'gold', `● ${profile.gold} or`));
  wallet.appendChild(el('span', 'dim', `${cls?.name ?? '?'} · record étage ${profile.bestFloor}`));
  head.appendChild(wallet);
  p.appendChild(head);

  const tabs = el('div', 'tabs');
  for (const t of TOWN_TABS) {
    const b = button(t.label, `small tab${t.id === view.tab ? ' on' : ''}`, () => actions.setTab(t.id));
    b.dataset.tab = t.id;
    tabs.appendChild(b);
  }
  p.appendChild(tabs);
  const body = el('div', 'town-body');
  (TAB_BUILDERS[view.tab] ?? TAB_BUILDERS.portail)(body, view, actions);
  p.appendChild(body);
}

function note(body, text) {
  body.appendChild(el('p', 'dim small', text));
}

function statusButton({ owned, selected, cost, souls }, onSelect, onUnlock) {
  if (selected) return button('Équipé', 'small', () => {}, true);
  if (owned) return button('Choisir', 'small primary', onSelect);
  return button(`Débloquer · ◆ ${cost}`, 'small', onUnlock, souls < cost);
}

const TAB_BUILDERS = {
  portail(body, view, actions) {
    const { profile, tuning } = view;
    note(body, 'Repartez du dernier checkpoint, ou de n\'importe quel point de téléportation déjà ouvert. Les bénédictions repartent de zéro à chaque descente.');
    const list = el('div', 'cards');
    const cps = profile.checkpoints.slice().sort((a, b) => b - a);
    cps.forEach((f, i) => {
      const info = floorInfo(tuning, f);
      const card = el('div', 'card');
      card.appendChild(el('div', 'card-kicker', i === 0 ? 'Dernier checkpoint' : 'Téléportation'));
      card.appendChild(el('div', 'card-title', `Étage ${f}`));
      card.appendChild(el('div', 'card-sub', `${info.circleName} · section ${info.section} / ${info.sectionCount}`));
      const g = tuning.boss[guardianFor(tuning, info.section)];
      card.appendChild(el('div', 'card-text', `Gardien de la section : ${g?.name ?? '?'} (étage ${info.section * tuning.floors.sectionLength})`));
      const b = button(i === 0 ? 'Descendre' : 'Se téléporter', i === 0 ? 'primary' : '', () => actions.depart(f));
      if (i === 0) b.id = 'depart';
      card.appendChild(b);
      list.appendChild(card);
    });
    body.appendChild(list);
    const row = el('div', 'row');
    row.appendChild(button('Arène d\'essai', '', () => actions.arena()));
    body.appendChild(row);
    // Entraînement : rejouer un Gardien déjà rencontré, sans récompense ni risque.
    const met = Object.keys(tuning.boss).filter((k) => (profile.guardians[k] ?? 0) > 0 || view.allGuardians);
    if (met.length) {
      body.appendChild(el('h3', '', 'Entraînement · Gardiens'));
      const r2 = el('div', 'row wrap');
      for (const k of met) r2.appendChild(button(`Défier ${tuning.boss[k].name}`, 'small', () => actions.practice(k)));
      body.appendChild(r2);
    }
  },

  classe(body, view, actions) {
    const { profile, tuning } = view;
    note(body, 'La classe fixe les armes, compétences et gadgets disponibles, et son Super. Changer de classe est gratuit une fois débloquée.');
    const list = el('div', 'cards');
    for (const [id, c] of Object.entries(tuning.classes)) {
      const card = el('div', 'card');
      card.appendChild(el('div', 'card-kicker', `Super : ${tuning.supers[c.super]?.name ?? '?'}`));
      card.appendChild(el('div', 'card-title', c.name));
      card.appendChild(el('div', 'card-text', c.text));
      const owned = profile.unlocked.classes.includes(id);
      card.appendChild(statusButton(
        { owned, selected: profile.loadout.classId === id, cost: unlockCost(tuning, 'classes', id), souls: profile.souls },
        () => actions.selectClass(id),
        () => actions.unlock('classes', id),
      ));
      list.appendChild(card);
    }
    body.appendChild(list);
  },

  armurerie(body, view, actions) {
    const { profile, tuning } = view;
    const c = tuning.classes[profile.loadout.classId];
    note(body, `Armes du ${c.name}. Débloquer un type d'arme forge un exemplaire commun (rangé au coffre) et l'ajoute au butin du donjon.`);
    const list = el('div', 'cards');
    for (const wt of c.weapons) {
      const w = tuning.weapons[wt];
      if (!w) continue;
      const card = el('div', 'card');
      card.appendChild(el('div', 'card-kicker', w.kind === 'ranged' ? 'Arme à distance' : 'Arme de mêlée'));
      card.appendChild(el('div', 'card-title', w.name));
      card.appendChild(el('div', 'card-text', w.text ?? ''));
      const owned = profile.unlocked.weapons.includes(wt);
      const worn = (profile.equipment.arme?.weaponType ?? 'lame') === wt;
      if (owned) {
        const best = profile.stash.filter((it) => it.slot === 'arme' && (it.weaponType ?? 'lame') === wt).sort((a, b) => (b.score ?? 0) - (a.score ?? 0))[0];
        card.appendChild(worn ? button('Portée', 'small', () => {}, true) : button('Prendre la meilleure', 'small primary', () => actions.equip(best?.uid), !best));
      } else {
        const cost = unlockCost(tuning, 'weapons', wt);
        card.appendChild(button(`Forger · ◆ ${cost}`, 'small', () => actions.unlock('weapons', wt), profile.souls < cost));
      }
      list.appendChild(card);
    }
    body.appendChild(list);
    const worn = describeItem(profile.equipment.arme);
    if (worn) {
      body.appendChild(el('h3', '', 'Arme portée'));
      const cards = el('div', 'cards two');
      cards.appendChild(itemCard(worn, 'Portée'));
      body.appendChild(cards);
    }
  },

  equipement(body, view, actions) {
    const { profile, tuning } = view;
    note(body, 'Tout objet trouvé en donjon est conservé : équipé, ou rangé ici. Recycler rend des Âmes.');
    const worn = el('div', 'cards');
    for (const slot of ['arme', 'armure', 'talisman']) worn.appendChild(itemCard(describeItem(profile.equipment[slot]), `Porté · ${slot}`));
    body.appendChild(worn);
    body.appendChild(el('h3', '', `Coffre (${profile.stash.length})`));
    if (!profile.stash.length) note(body, 'Vide. Les trésors du donjon arrivent ici.');
    const c = tuning.classes[profile.loadout.classId];
    const list = el('div', 'cards');
    for (const it of profile.stash.slice().sort((a, b) => (b.score ?? 0) - (a.score ?? 0))) {
      const card = itemCard(describeItem(it), it.slot === 'arme' ? `Arme · ${tuning.weapons[it.weaponType ?? 'lame']?.name ?? '?'}` : 'Coffre');
      const row = el('div', 'row');
      const wield = it.slot !== 'arme' || c.weapons.includes(it.weaponType ?? 'lame');
      row.appendChild(button(wield ? 'Équiper' : 'Autre classe', 'small primary', () => actions.equip(it.uid), !wield));
      row.appendChild(button(`Recycler · ◆ ${salvageSouls(tuning, it)}`, 'small', () => actions.salvage(it.uid)));
      card.appendChild(row);
      list.appendChild(card);
    }
    body.appendChild(list);
  },

  grimoire(body, view, actions) {
    const { profile, tuning } = view;
    const c = tuning.classes[profile.loadout.classId];
    note(body, `Compétence (bouton Lance) et gadget (charges par section) du ${c.name}. Super : ${tuning.supers[c.super]?.name ?? '?'} — ${tuning.supers[c.super]?.text ?? ''}`);
    for (const [kind, title, ids, current, select] of [
      ['skills', 'Compétences', c.skills, profile.loadout.skillId, actions.selectSkill],
      ['gadgets', 'Gadgets', c.gadgets, profile.loadout.gadgetId, actions.selectGadget],
    ]) {
      body.appendChild(el('h3', '', title));
      const list = el('div', 'cards');
      for (const id of ids) {
        const d = tuning[kind][id];
        if (!d) continue;
        const card = el('div', 'card');
        card.appendChild(el('div', 'card-title', d.name));
        card.appendChild(el('div', 'card-text', d.text ?? ''));
        card.appendChild(statusButton(
          { owned: profile.unlocked[kind].includes(id), selected: current === id, cost: unlockCost(tuning, kind, id), souls: profile.souls },
          () => select(id),
          () => actions.unlock(kind, id),
        ));
        list.appendChild(card);
      }
      body.appendChild(list);
    }
  },

  sanctuaire(body, view, actions) {
    const { profile, tuning } = view;
    note(body, 'Améliorations permanentes, payées en Âmes. Elles s\'appliquent à toutes les classes.');
    const list = el('div', 'cards');
    for (const [id, up] of Object.entries(tuning.town.upgrades)) {
      const lv = profile.upgrades[id] ?? 0;
      const cost = upgradeCost(tuning, id, lv);
      const card = el('div', 'card');
      card.appendChild(el('div', 'card-kicker', `Niveau ${lv} / ${up.max}`));
      card.appendChild(el('div', 'card-title', up.name));
      card.appendChild(el('div', 'card-text', up.text));
      card.appendChild(cost === null ? button('Maximum', 'small', () => {}, true) : button(`Améliorer · ◆ ${cost}`, 'small primary', () => actions.buyUpgrade(id), profile.souls < cost));
      list.appendChild(card);
    }
    body.appendChild(list);
  },

  labo(body, view, actions) {
    note(body, 'D5, D8 et D9 restent ouvertes : comparez les variantes en jouant (arène d\'essai conseillée). Le choix vaut pour toutes les parties, et se change aussi en pause.');
    buildLabControls(body, view.lab, actions.setLab);
  },
};

/** Boutons des trois axes du labo (aussi utilisés par le panneau de pause). */
export function buildLabControls(body, lab, setLab) {
  for (const [axis, def] of Object.entries(LAB_AXES)) {
    body.appendChild(el('h3', '', def.label));
    const row = el('div', 'row wrap');
    for (const [id, opt] of Object.entries(def.options)) {
      const on = lab[axis] === id;
      const b = button(opt.label, `small${on ? ' primary' : ''}`, () => setLab(axis, id));
      b.dataset.lab = `${axis}:${id}`;
      row.appendChild(b);
    }
    body.appendChild(row);
    body.appendChild(el('p', 'dim small', def.options[lab[axis]]?.text ?? ''));
  }
}
