// Briques DOM partagées par les menus, la Ville et le panneau de réglages : création
// d'éléments, activation robuste au doigt (pointerup du même doigt), armement anti-martelage.

export const ARM_MS = 350; // un panneau ne répond qu'après ce délai : jamais de choix « à l'aveugle »
// Panneaux de choix (bénédiction, butin, autel, marchand) : plus long, et chaque tap reçu pendant
// l'armement le relance. Un dash martelé à 3-4 Hz qui ouvre le panneau ne choisit donc rien.
export const ARM_CHOICE_MS = 600;
const REFIRE_MS = 300; // anti double déclenchement (pointerup puis click)

// Instant d'ouverture du panneau courant (armement), partagé par tous ses boutons.
export const arming = { shownAt: 0, noDelay: false, ms: ARM_MS };

export function armed() {
  return arming.noDelay || performance.now() - arming.shownAt >= arming.ms;
}

export function el(tag, cls, text) {
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
export function onActivate(node, fn) {
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

export function button(label, cls, onClick, disabled = false) {
  const b = el('button', `btn ${cls ?? ''}`, label);
  b.type = 'button';
  b.disabled = disabled;
  onActivate(b, onClick);
  return b;
}

export function itemCard(item, title) {
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

