// Palette par RÔLE (lisibilité avant tout) : le héros est froid (cyan/blanc), tout ce qui
// fait mal est chaud (rouge/orange/magenta) et cerné de sombre, le butin parle la langue
// de Diablo (blanc, bleu, jaune, orange).

export const PAL = {
  void: '#07040a',
  floorA: '#1b1116',
  floorB: '#22151b',
  floorLine: '#2e1d24',
  crack: '#120a0e',
  lava: '#ff5a1f',
  lavaDim: '#7a1f0a',
  wall: '#2a1a20',
  wallTop: '#3b252d',
  wallEdge: '#5a3a44',
  pillarTop: '#47303a',
  pillarSide: '#24161c',
  shadow: 'rgba(0, 0, 0, 0.45)',

  hero: '#eaf7ff',
  heroCape: '#2fc7ff',
  heroGlow: 'rgba(80, 210, 255, 0.35)',
  heroHurt: '#ff4a4a',
  slash: '#dff8ff',
  slashStrike: '#7fe8ff',
  lance: '#9ff4ff',

  danger: '#ff3b3b',
  dangerFill: 'rgba(255, 45, 45, 0.16)',
  dangerFillHot: 'rgba(255, 60, 40, 0.42)',
  enemyOutline: '#140507',
  enemyFlash: '#ffc9b0', // flash d'impact : chaud, jamais le blanc froid du héros
  impactRing: '#ffd2a8',
  summon: '#b48cff', // alertes sans danger (invocation)
  arrow: '#ff8a2a',
  bossOrb: '#ff3cbe',

  imp: '#e2483b',
  archer: '#d9cdb8',
  brute: '#9a3030',
  charger: '#c8732e',
  exploder: '#ff9c2a',
  boss: '#6a1428',
  bossTrim: '#ffcf5a',

  eliteRapide: '#4fd1ff',
  eliteBlinde: '#c9c9d6',
  eliteArdent: '#ff6a1a',
  eliteVampirique: '#ff3d7f', // rouge-rose : le drain se lit comme du sang
  eliteBouclier: '#ffe9a8', // or pâle : la bulle d'immunité
  eliteInvocateur: '#b48cff', // violet : la couleur des invocations (alerte inoffensive)

  gold: '#ffd23c',
  heal: '#6dff8a',
  text: '#f3e9e4',
  textDim: '#a8949a',
  crit: '#ffe14a',
  hpBar: '#e23a3a',
  hpBack: '#2a1216',
  superBar: '#ffb02e',
  dashPip: '#7fe8ff',
};

export const ELITE_COLORS = {
  rapide: PAL.eliteRapide, blinde: PAL.eliteBlinde, ardent: PAL.eliteArdent,
  vampirique: PAL.eliteVampirique, bouclier: PAL.eliteBouclier, invocateur: PAL.eliteInvocateur,
};
export const ELITE_NAMES = {
  rapide: 'Rapide', blinde: 'Blindé', ardent: 'Ardent',
  vampirique: 'Vampirique', bouclier: 'Bouclier', invocateur: 'Invocateur',
};

// Teinte de chaque Cercle (sols, lueurs) — le biome se lit d'un coup d'œil.
export const CIRCLE_TINTS = ['#ff5a1f', '#ff3c8c', '#9be03c', '#ffc83c', '#ff2a2a', '#b98cff', '#ff7a3c', '#3ce0b4', '#7ab8ff', '#ffffff'];

export const REWARD_COLORS = {
  boon: '#ff8ae0',
  loot: '#ffd23c',
  gold: '#ffd23c',
  elite: '#ff6a1a',
  heal: '#6dff8a',
  shop: '#7fe8ff',
  event: '#b98cff',
  boss: '#ff3b3b',
  town: '#9ff4ff', // portail vers la Ville (après un Gardien)
};
