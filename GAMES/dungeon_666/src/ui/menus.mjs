// Menus DOM par-dessus le canvas : écran titre, choix (bénédiction, butin, marchand, autel),
// mort et reprise au checkpoint, pause et réglages, panneau de tuning du feel.
// AUCUNE règle de jeu ici : chaque bouton émet une commande que la simulation valide.

const SLOT_LABELS = { attack: 'Attaque', dash: 'Dash', skill: 'Lance', passive: 'Passif', super: 'Super' };
const ARM_MS = 350; // un panneau ne répond qu'après ce délai : jamais de choix « à l'aveugle »
const REFIRE_MS = 300; // anti double déclenchement (pointerup puis click)

// Instant d'ouverture du panneau courant (armement), partagé par tous ses boutons.
const arming = { shownAt: 0, noDelay: false };

function armed() {
  return arming.noDelay || performance.now() - arming.shownAt >= ARM_MS;
}

function el(tag, cls, text) {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text !== undefined) n.textContent = text;
  return n;
}

/**
 * Activation robuste au doigt : au POINTERUP du même doigt que le pointerdown, à l'intérieur
 * de l'élément. Chromium/Android n'émettent pas `click` pour un 2e doigt (le pouce gauche
 * resté sur le joystick) ; `click` ne sert plus qu'au clavier (detail === 0).
 */
function onActivate(node, fn) {
  let pid = null;
  let last = 0;
  const fire = () => {
    const now = performance.now();
    if (node.disabled || now - last < REFIRE_MS) return;
    last = now;
    fn();
  };
  node.addEventListener('pointerdown', (ev) => {
    pid = armed() ? ev.pointerId : null;
  });
  node.addEventListener('pointerup', (ev) => {
    if (pid === null || pid !== ev.pointerId) return;
    pid = null;
    const r = node.getBoundingClientRect();
    if (ev.clientX < r.left || ev.clientX > r.right || ev.clientY < r.top || ev.clientY > r.bottom) return;
    ev.preventDefault();
    fire();
  });
  node.addEventListener('pointercancel', () => {
    pid = null;
  });
  node.addEventListener('click', (ev) => {
    ev.stopPropagation();
    if (ev.detail === 0 && armed()) fire();
  });
}

function button(label, cls, onClick, disabled = false) {
  const b = el('button', `btn ${cls ?? ''}`, label);
  b.type = 'button';
  b.disabled = disabled;
  onActivate(b, onClick);
  return b;
}

function itemCard(item, title) {
  const card = el('div', 'card item');
  card.appendChild(el('div', 'card-kicker', title));
  if (!item) {
    card.appendChild(el('div', 'card-title dim', 'Emplacement vide'));
    return card;
  }
  const name = el('div', 'card-title', item.name);
  name.style.color = item.color;
  card.appendChild(name);
  card.appendChild(el('div', 'card-sub', `${item.rarityName} · ${item.slotName} · niv. ${item.level}`));
  const ul = el('ul', 'affixes');
  for (const line of item.lines) ul.appendChild(el('li', '', line));
  if (item.power) {
    const li = el('li', 'power', item.power);
    ul.appendChild(li);
  }
  card.appendChild(ul);
  return card;
}

export function createUI(root, handlers) {
  // #overlay / .hidden / #restart : vocabulaire du PLAYABLE_CONTRACT du studio.
  const panel = el('div', 'panel hidden');
  panel.id = 'overlay';
  panel.hidden = true;
  root.appendChild(panel);
  let shownKey = '';
  let shownKind = '';

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
    arming.noDelay = key.startsWith('title') || key.startsWith('pause') || key === 'tuning' || refresh;
    arming.shownAt = performance.now();
    if (!arming.noDelay) {
      panel.classList.add('arming');
      setTimeout(() => panel.classList.remove('arming'), ARM_MS);
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
    p.appendChild(el('p', 'lede', '666 étages. Un Gardien tous les six. Chaque Gardien vaincu devient un point de reprise.'));
    const row = el('div', 'row');
    const cps = meta.checkpoints.slice().sort((a, b) => b - a);
    row.appendChild(button(cps[0] > 1 ? `Reprendre · étage ${cps[0]}` : 'Descendre', 'primary', () => handlers.start(cps[0])));
    if (cps[0] > 1) row.appendChild(button('Recommencer · étage 1', '', () => handlers.start(1)));
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
    const cols = el('div', 'cards two');
    cols.appendChild(itemCard(ch.item, 'Trouvé'));
    cols.appendChild(itemCard(ch.equipped, 'Équipé'));
    p.appendChild(cols);
    const row = el('div', 'row');
    row.appendChild(button('Équiper', 'primary', () => handlers.command({ type: 'equip' })));
    row.appendChild(button(`Récupérer · +${ch.salvage} or`, '', () => handlers.command({ type: 'salvage' })));
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
    p.appendChild(el('p', 'dim', 'Vous reprenez au checkpoint avec le build que vous aviez en battant son Gardien. Votre équipement vous suit toujours.'));
    const col = el('div', 'col');
    if (game.sandbox) {
      const b = button('Recommencer l\'arène', 'primary', () => handlers.command({ type: 'respawn', floor: 1 }));
      b.id = 'restart';
      col.appendChild(b);
      p.appendChild(col);
      return;
    }
    const retry = handlers.canRetryBoss(game);
    if (retry) {
      const b = button(`Réessayer le Gardien · étage ${game.run.floor}`, 'primary', () => handlers.command({ type: 'retryBoss' }));
      b.id = 'restart';
      col.appendChild(b);
    }
    const cps = game.meta.checkpoints.slice().sort((a, b) => b - a).slice(0, 4);
    cps.forEach((f, i) => {
      const first = i === 0 && !retry;
      const b = button(`Reprendre · étage ${f}`, first ? 'primary' : '', () => handlers.command({ type: 'respawn', floor: f }));
      if (first) b.id = 'restart';
      col.appendChild(b);
    });
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
    col.appendChild(button('Réglages du feel', '', () => handlers.openTuning()));
    col.appendChild(button('Retour au titre', 'ghost', () => handlers.quit()));
    p.appendChild(col);
  }

  // -------------------------------------------------------------- synchronisation

  /** Appelée à chaque image : affiche le bon panneau selon l'état. */
  function sync(game, app) {
    if (app.screen === 'title') return show((p) => buildTitle(p, app.meta), `title:${app.meta.bestFloor}:${app.meta.checkpoints.length}`);
    if (app.screen === 'tuning') return show((p) => handlers.buildTuning(p), 'tuning');
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
