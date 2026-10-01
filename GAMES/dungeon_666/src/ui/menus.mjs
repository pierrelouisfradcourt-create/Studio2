// Menus DOM par-dessus le canvas : écran titre, choix (bénédiction, butin, marchand, autel),
// mort et reprise au checkpoint, pause et réglages, panneau de tuning du feel.
// AUCUNE règle de jeu ici : chaque bouton émet une commande que la simulation valide.

import { el, button, onActivate, itemCard, arming, armed, ARM_MS, ARM_CHOICE_MS } from './dom.mjs';
import { buildTown, buildLabControls } from './town.mjs';

const SLOT_LABELS = { attack: 'Attaque', dash: 'Dash', skill: 'Compétence', passive: 'Passif', super: 'Super' };
export function createUI(root, handlers) {
  // #overlay / .hidden / #restart : vocabulaire du PLAYABLE_CONTRACT du studio.
  const panel = el('div', 'panel hidden');
  panel.id = 'overlay';
  panel.hidden = true;
  root.appendChild(panel);
  let shownKey = '';
  let shownKind = '';
  let armTimer = 0;

  function startArming() {
    arming.shownAt = performance.now();
    panel.classList.add('arming');
    clearTimeout(armTimer);
    armTimer = setTimeout(() => panel.classList.remove('arming'), arming.ms);
  }

  // Anti-martelage : tout appui pendant l'armement le prolonge (capture, avant les boutons).
  panel.addEventListener('pointerdown', () => {
    if (!armed()) startArming();
  }, true);

  function show(builder, key) {
    if (key === shownKey) return;
    shownKey = key;
    panel.replaceChildren();
    builder(panel);
    panel.hidden = false;
    panel.classList.remove('hidden');
    // Armement : l'écran titre et les rafraîchissements du marchand répondent tout de suite.
    const refresh = key.startsWith('choice:shop') && shownKind === 'shop';
    shownKind = key.split(':')[1] ?? key;
    arming.noDelay = key.startsWith('title') || key.startsWith('pause') || key.startsWith('town') || key.startsWith('lab') || key === 'tuning' || refresh;
    arming.ms = key.startsWith('choice') ? ARM_CHOICE_MS : ARM_MS;
    arming.shownAt = performance.now();
    if (!arming.noDelay) startArming();
    else {
      clearTimeout(armTimer);
      panel.classList.remove('arming');
    }
    const first = panel.querySelector('button:not([disabled])');
    if (first && !handlers.isTouch()) first.focus({ preventScroll: true });
  }

  function hide() {
    if (!shownKey) return;
    shownKey = '';
    shownKind = '';
    panel.hidden = true;
    panel.classList.add('hidden');
    panel.replaceChildren();
  }

  // -------------------------------------------------------------- écrans

  function buildTitle(p, meta) {
    p.className = 'panel title-screen';
    p.appendChild(el('div', 'kicker', 'Descente vers l\'Enfer'));
    p.appendChild(el('h1', 'logo', 'DUNGEON 666'));
    p.appendChild(el('p', 'lede', '666 étages. Un Gardien tous les dix-huit. Chaque Gardien vaincu ouvre un checkpoint et un portail vers la Ville.'));
    const row = el('div', 'row');
    const cps = meta.checkpoints.slice().sort((a, b) => b - a);
    const go = button('Entrer dans Dité', 'primary', () => handlers.openTown());
    go.id = 'enter-town';
    row.appendChild(go);
    row.appendChild(button(`Descendre · étage ${cps[0]}`, '', () => handlers.start(cps[0])));
    row.appendChild(button('Arène d\'essai', '', () => handlers.start(1, true)));
    p.appendChild(row);
    const help = el('div', 'help');
    help.appendChild(el('p', '', handlers.isTouch()
      ? 'Pouce gauche : se déplacer. Pouce droit : attaquer (tapez = visée auto, glissez = visée manuelle). Le gros bouton à gauche de l\'attaque : DASH — invulnérable pendant la ruée.'
      : 'ZQSD / WASD : se déplacer · Souris : viser · Clic gauche : attaquer · Espace : DASH (invulnérable) · Clic droit : Lance · E : Nova · F : Colère · Échap : pause'));
    help.appendChild(el('p', 'dim', `Meilleur étage : ${meta.bestFloor}. Paysage conseillé sur téléphone.`));
    p.appendChild(help);
  }

  function buildBoon(p, ch) {
    p.className = 'panel choice';
    const h = el('h2', '', `Bénédiction · ${ch.familyName}`);
    h.style.color = ch.color;
    p.appendChild(h);
    p.appendChild(el('p', 'lede', 'Choisissez un don du péché. Il disparaîtra à votre mort.'));
    const list = el('div', 'cards');
    ch.options.forEach((o, i) => {
      const card = el('button', `card boon rarity-${o.rarity}`);
      card.type = 'button';
      card.style.setProperty('--accent', o.color);
      card.appendChild(el('div', 'card-kicker', `${o.duo ? 'DUO · ' : ''}${SLOT_LABELS[o.slot] ?? o.slot} · ${o.rarityName}${o.level > 1 ? ` · niv. ${o.level}` : ''}`));
      card.appendChild(el('div', 'card-title', o.name));
      card.appendChild(el('div', 'card-text', o.text));
      onActivate(card, () => handlers.command({ type: 'choose', index: i }));
      list.appendChild(card);
    });
    p.appendChild(list);
  }

  function buildLoot(p, ch) {
    p.className = 'panel choice';
    p.appendChild(el('h2', '', 'Trésor'));
    p.appendChild(el('p', 'dim small', 'Équipement PERMANENT : l\'objet remplacé, ou celui que vous gardez, part au coffre de la Ville.'));
    const cols = el('div', 'cards two');
    cols.appendChild(itemCard(ch.item, 'Trouvé'));
    cols.appendChild(itemCard(ch.equipped, 'Porté'));
    p.appendChild(cols);
    const row = el('div', 'row');
    row.appendChild(button(ch.wieldable === false ? 'Arme d\'une autre classe' : 'Équiper', 'primary', () => handlers.command({ type: 'equip' }), ch.wieldable === false));
    row.appendChild(button('Garder au coffre', '', () => handlers.command({ type: 'stash' })));
    row.appendChild(button(`Vendre · +${ch.salvage} or`, '', () => handlers.command({ type: 'salvage' })));
    p.appendChild(row);
  }

  function buildShop(p, ch) {
    p.className = 'panel choice';
    p.appendChild(el('h2', '', 'Marchand des âmes'));
    p.appendChild(el('p', 'lede gold', `Votre or : ${ch.gold}`));
    const list = el('div', 'cards');
    ch.offers.forEach((o, i) => {
      const card = el('div', 'card shop');
      if (o.color) card.style.setProperty('--accent', o.color);
      card.appendChild(el('div', 'card-title', o.label));
      if (o.item) {
        card.querySelector('.card-title').style.color = o.item.color;
        card.appendChild(el('div', 'card-sub', `${o.item.rarityName} · ${o.item.slotName}`));
        card.appendChild(el('div', 'card-text', [...o.item.lines, o.item.power].filter(Boolean).join(' · ')));
      } else {
        card.appendChild(el('div', 'card-text', o.text));
      }
      card.appendChild(button(o.sold ? 'Vendu' : `Acheter · ${o.price} or`, 'small', () => handlers.command({ type: 'choose', index: i }), o.sold || ch.gold < o.price));
      list.appendChild(card);
    });
    p.appendChild(list);
    p.appendChild(button('Partir', '', () => handlers.command({ type: 'close' })));
  }

  function buildEvent(p, ch) {
    p.className = 'panel choice';
    p.appendChild(el('h2', '', ch.title));
    p.appendChild(el('p', 'lede', ch.text));
    const col = el('div', 'col');
    ch.options.forEach((o, i) => col.appendChild(button(o.label, i === 0 ? 'primary' : '', () => handlers.command({ type: 'choose', index: i }), o.disabled)));
    p.appendChild(col);
  }

  function buildDeath(p, game) {
    p.className = 'panel death';
    p.appendChild(el('h1', 'logo red', 'VOUS ÊTES MORT'));
    const t = game.telemetry;
    p.appendChild(el('p', 'lede', `Étage ${game.run.floor} · ${t.kills} démons abattus · ${t.dodges} esquives au dash`));
    const col = el('div', 'col');
    if (game.sandbox || game.practice) {
      const b = button(game.practice ? 'Réessayer le Gardien' : 'Recommencer l\'arène', 'primary', () => handlers.command({ type: 'respawn', floor: game.run.floor }));
      b.id = 'restart';
      col.appendChild(b);
      col.appendChild(button('Retour à la Ville', '', () => handlers.command({ type: 'returnToTown' })));
      p.appendChild(col);
      return;
    }
    // Récapitulatif : la boucle de reset doit se LIRE.
    const r = game.run.deathRecap ?? { boonsLost: 0, boonNames: [], goldLost: 0, souls: game.meta.souls, soulsEarned: 0, checkpoint: 1 };
    const recap = el('div', 'cards two recap');
    const lost = el('div', 'card');
    lost.style.setProperty('--accent', '#c0304a');
    lost.appendChild(el('div', 'card-kicker', 'Perdu · temporaire'));
    lost.appendChild(el('div', 'card-title', `${r.boonsLost} bénédiction${r.boonsLost > 1 ? 's' : ''}`));
    if (r.boonNames.length) lost.appendChild(el('div', 'card-text', r.boonNames.join(' · ')));
    lost.appendChild(el('div', 'card-text', `Charon a prélevé ${r.goldLost} or.`));
    const kept = el('div', 'card');
    kept.style.setProperty('--accent', '#2fc7ff');
    kept.appendChild(el('div', 'card-kicker', 'Gardé · permanent'));
    kept.appendChild(el('div', 'card-title', `◆ ${r.souls} Âmes (+${r.soulsEarned})`));
    kept.appendChild(el('div', 'card-text', 'Classe, armes, équipement et coffre, compétences, améliorations de la Ville, checkpoints.'));
    recap.append(lost, kept);
    p.appendChild(recap);
    const b = button(`Repartir du checkpoint · étage ${r.checkpoint}`, 'primary', () => handlers.command({ type: 'respawn', floor: r.checkpoint }));
    b.id = 'restart';
    col.appendChild(b);
    const town = button('Retour à la Ville', '', () => handlers.command({ type: 'returnToTown' }));
    town.id = 'to-town';
    col.appendChild(town);
    p.appendChild(col);
  }

  function buildVictory(p) {
    p.className = 'panel death';
    p.appendChild(el('h1', 'logo', 'LE TRÔNE EST VIDE'));
    p.appendChild(el('p', 'lede', 'Vous avez atteint le 666e étage.'));
  }

  function buildPause(p, settings) {
    p.className = 'panel pause';
    p.appendChild(el('h2', '', 'Pause'));
    const col = el('div', 'col');
    col.appendChild(button('Reprendre', 'primary', () => handlers.resume()));
    col.appendChild(button(`Son : ${settings.sound ? 'oui' : 'non'}`, '', () => handlers.setSetting('sound', !settings.sound)));
    col.appendChild(button(`Vibrations : ${settings.haptics ? 'oui' : 'non'}`, '', () => handlers.setSetting('haptics', !settings.haptics)));
    col.appendChild(button(`Tremblement : ${Math.round(settings.shake * 100)} %`, '', () => handlers.setSetting('shake', settings.shake >= 1 ? 0.5 : settings.shake > 0 ? 0 : 1)));
    col.appendChild(button('Labo du feel (D5 · D8 · D9)', '', () => handlers.openLab()));
    col.appendChild(button('Réglages du feel', '', () => handlers.openTuning()));
    col.appendChild(button('Abandonner · retour à la Ville', 'ghost', () => handlers.abandon()));
    p.appendChild(col);
  }

  function buildLabPanel(p, lab) {
    p.className = 'panel pause lab';
    p.appendChild(el('h2', '', 'Labo du feel'));
    p.appendChild(el('p', 'dim small', 'Change la variante tout de suite, dans cette partie et les suivantes.'));
    buildLabControls(p, lab, handlers.setLab);
    p.appendChild(button('Retour', 'primary', () => handlers.closeLab()));
  }

  // -------------------------------------------------------------- synchronisation

  /** Appelée à chaque image : affiche le bon panneau selon l'état. */
  function sync(game, app) {
    if (app.screen === 'title') return show((p) => buildTitle(p, app.profile), `title:${app.profile.bestFloor}:${app.profile.checkpoints.length}`);
    if (app.screen === 'town') {
      const view = handlers.townView();
      return show((p) => buildTown(p, view, handlers.townActions), `town:${view.tab}:${view.rev}`);
    }
    if (app.screen === 'tuning') return show((p) => handlers.buildTuning(p), 'tuning');
    if (app.screen === 'lab') return show((p) => buildLabPanel(p, app.settings.lab), `lab:${JSON.stringify(app.settings.lab)}`);
    if (app.paused) return show((p) => buildPause(p, app.settings), `pause:${JSON.stringify(app.settings)}`);
    if (!game) return hide();
    if (game.mode === 'choice' && game.choice) {
      const ch = game.choice;
      const key = `choice:${ch.kind}:${game.room.interact?.x}:${game.run.gold}:${ch.offers?.map((o) => o.sold).join()}:${game.tick}`;
      const builders = { boon: buildBoon, loot: buildLoot, shop: buildShop, event: buildEvent };
      return show((p) => builders[ch.kind](p, ch), ch.kind === 'shop' ? key : `choice:${ch.kind}:${game.tick}`);
    }
    if (game.mode === 'dead') return show((p) => buildDeath(p, game), `dead:${game.tick}`);
    if (game.mode === 'victory') return show(buildVictory, 'victory');
    return hide();
  }

  return { sync, hide, get visible() { return !panel.hidden; } };
}
