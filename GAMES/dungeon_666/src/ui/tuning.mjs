// Panneau de réglage du feel, pour le playtest : chaque curseur modifie `game.tuning` en
// direct (la copie de la partie, jamais les valeurs par défaut). Les réglages sont gardés
// dans le navigateur du testeur, et un bouton les copie au format JSON pour les rapporter.

export const TUNABLES = [
  { path: 'player.speed', label: 'Vitesse de course', min: 180, max: 460, step: 10 },
  { path: 'player.accelTime', label: 'Temps d\'accélération (s)', min: 0, max: 0.2, step: 0.01 },
  { path: 'dash.distance', label: 'Distance du dash', min: 80, max: 300, step: 5 },
  { path: 'dash.duration', label: 'Durée du dash (s)', min: 0.08, max: 0.3, step: 0.01 },
  { path: 'dash.iframes', label: 'Invulnérabilité du dash (s)', min: 0, max: 0.4, step: 0.01 },
  { path: 'dash.recharge', label: 'Recharge d\'une charge (s)', min: 0.2, max: 2.5, step: 0.05 },
  { path: 'dash.charges', label: 'Charges de dash', min: 1, max: 4, step: 1 },
  { path: 'combo.0.damage', label: 'Dégâts coup 1', min: 4, max: 30, step: 1 },
  { path: 'combo.2.damage', label: 'Dégâts coup 3', min: 8, max: 60, step: 1 },
  { path: 'combo.2.hitstop', label: 'Gel d\'impact coup 3 (s)', min: 0, max: 0.2, step: 0.005 },
  { path: 'combo.0.hitstop', label: 'Gel d\'impact coups 1-2 (s)', min: 0, max: 0.12, step: 0.005, also: ['combo.1.hitstop'] },
  { path: 'autoAim.range', label: 'Portée de la visée auto', min: 120, max: 500, step: 10 },
  { path: 'super.chargeDamage', label: 'Dégâts pour remplir le Super', min: 100, max: 1500, step: 20 },
  { path: 'combat.maxAttackers', label: 'Ennemis attaquant ensemble', min: 1, max: 6, step: 1 },
  { path: 'enemies.imp.windup', label: 'Télégraphe diablotin (s)', min: 0.2, max: 0.9, step: 0.02 },
  { path: 'enemies.archer.windup', label: 'Télégraphe archer (s)', min: 0.3, max: 1.2, step: 0.02 },
  { path: 'enemies.imp.speed', label: 'Vitesse diablotin', min: 80, max: 300, step: 5 },
];

const STORE_KEY = 'dungeon666.tuning.v1';

function getPath(obj, path) {
  return path.split('.').reduce((o, k) => (o == null ? undefined : o[k]), obj);
}

function setPath(obj, path, value) {
  const keys = path.split('.');
  const last = keys.pop();
  const target = keys.reduce((o, k) => o[k], obj);
  target[last] = value;
}

export function loadTuningOverrides() {
  try {
    const raw = localStorage.getItem(STORE_KEY);
    return raw ? JSON.parse(raw) : {};
  } catch {
    return {};
  }
}

function saveOverrides(o) {
  try {
    localStorage.setItem(STORE_KEY, JSON.stringify(o));
  } catch {
    // stockage indisponible : les réglages restent pour cette session
  }
}

/** Applique des surcharges {path: value} sur un objet tuning. */
export function applyOverrides(tuning, overrides) {
  for (const [path, v] of Object.entries(overrides)) {
    if (getPath(tuning, path) === undefined) continue;
    setPath(tuning, path, v);
    const def = TUNABLES.find((t) => t.path === path);
    for (const extra of def?.also ?? []) setPath(tuning, extra, v);
  }
}

export function buildTuningPanel(p, { getTuning, defaults, onClose }) {
  p.className = 'panel tuning';
  const h = document.createElement('h2');
  h.textContent = 'Réglages du feel';
  p.appendChild(h);
  const overrides = loadTuningOverrides();
  const list = document.createElement('div');
  list.className = 'sliders';
  for (const t of TUNABLES) {
    const row = document.createElement('label');
    row.className = 'slider';
    const name = document.createElement('span');
    name.textContent = t.label;
    const val = document.createElement('output');
    const input = document.createElement('input');
    input.type = 'range';
    input.id = `tune-${t.path.replace(/\./g, '-')}`;
    input.min = String(t.min);
    input.max = String(t.max);
    input.step = String(t.step);
    const cur = getPath(getTuning(), t.path);
    input.value = String(cur);
    val.textContent = String(cur);
    const isDefault = () => Number(input.value) === getPath(defaults, t.path);
    row.classList.toggle('changed', !isDefault());
    input.addEventListener('input', () => {
      const v = Number(input.value);
      applyOverrides(getTuning(), { [t.path]: v });
      val.textContent = String(v);
      overrides[t.path] = v;
      if (isDefault()) delete overrides[t.path];
      row.classList.toggle('changed', !isDefault());
      saveOverrides(overrides);
    });
    row.append(name, val, input);
    list.appendChild(row);
  }
  p.appendChild(list);
  const actions = document.createElement('div');
  actions.className = 'row';
  const copy = document.createElement('button');
  copy.type = 'button';
  copy.className = 'btn';
  copy.textContent = 'Copier les réglages';
  copy.addEventListener('click', async () => {
    const json = JSON.stringify(loadTuningOverrides(), null, 1);
    try {
      await navigator.clipboard.writeText(json);
      copy.textContent = 'Copié';
    } catch {
      copy.textContent = json.length > 2 ? json : 'Aucun changement';
    }
  });
  const reset = document.createElement('button');
  reset.type = 'button';
  reset.className = 'btn';
  reset.textContent = 'Valeurs par défaut';
  reset.addEventListener('click', () => {
    saveOverrides({});
    for (const t of TUNABLES) {
      applyOverrides(getTuning(), { [t.path]: getPath(defaults, t.path) });
      const input = p.querySelector(`#tune-${t.path.replace(/\./g, '-')}`);
      if (input) {
        input.value = String(getPath(defaults, t.path));
        input.dispatchEvent(new Event('input'));
      }
    }
  });
  const close = document.createElement('button');
  close.type = 'button';
  close.className = 'btn primary';
  close.textContent = 'Fermer';
  close.addEventListener('click', onClose);
  actions.append(close, copy, reset);
  p.appendChild(actions);
}
