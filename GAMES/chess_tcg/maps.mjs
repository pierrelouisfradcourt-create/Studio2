// Cartes du champ de bataille — 3 gabarits dessinés à la main, symétriques par rotation 180°
// (équité : chaque camp voit exactement le même terrain depuis sa tour).
// Le terrain a des EFFETS (engine.mjs) : forêt = armure, rocher = infranchissable,
// marais = stoppe le déplacement, brasier = brûle en fin de tour, fontaine = +1 mana.

export const COLS = 7;
export const ROWS = 8;

export const TERRAIN = Object.freeze({
  PLAINE: 'plaine',
  FORET: 'foret',
  ROCHER: 'rocher',
  MARAIS: 'marais',
  BRASIER: 'brasier',
  FONTAINE: 'fontaine',
});

export const LEGEND = Object.freeze({
  '.': TERRAIN.PLAINE,
  f: TERRAIN.FORET,
  '#': TERRAIN.ROCHER,
  '~': TERRAIN.MARAIS,
  L: TERRAIN.BRASIER,
  '*': TERRAIN.FONTAINE,
  T: TERRAIN.PLAINE, // la tour occupe la case ; le terrain dessous est une plaine
});

/** Ligne 0 = camp du haut (joueur 2), ligne 7 = camp du bas (joueur 1). */
export const MAP_TEMPLATES = Object.freeze([
  {
    name: 'La Vallée',
    rows: [
      '...T...',
      '.f...f.',
      '#.....#',
      '.~.*.~.',
      '.~.*.~.',
      '#.....#',
      '.f...f.',
      '...T...',
    ],
  },
  {
    name: 'Le Col de Lave',
    rows: [
      '...T...',
      '..f.f..',
      '.#...#.',
      'L..*..L',
      'L..*..L',
      '.#...#.',
      '..f.f..',
      '...T...',
    ],
  },
  {
    name: 'Les Marais Jumeaux',
    rows: [
      '...T...',
      'f.....f',
      '..~.~..',
      '*..#...',
      '...#..*',
      '..~.~..',
      'f.....f',
      '...T...',
    ],
  },
]);

export const TOWER_COL = 3;

/**
 * Construit la grille de cellules d'un gabarit : cells[y][x] = { terrain, base, ttl }.
 * `base` est le terrain permanent ; `ttl` > 0 signale un terrain temporaire (sort) qui
 * reviendra à `base` à expiration.
 */
export function buildBoard(templateIndex) {
  const template = MAP_TEMPLATES[templateIndex % MAP_TEMPLATES.length];
  if (template.rows.length !== ROWS) throw new Error(`gabarit ${template.name} : ${ROWS} lignes attendues`);
  return template.rows.map((row, y) => {
    if (row.length !== COLS) throw new Error(`gabarit ${template.name} ligne ${y} : ${COLS} colonnes attendues`);
    return [...row].map((ch) => {
      const terrain = LEGEND[ch];
      if (!terrain) throw new Error(`gabarit ${template.name} : symbole inconnu "${ch}"`);
      return { terrain, base: terrain, ttl: 0 };
    });
  });
}

export function templateName(templateIndex) {
  return MAP_TEMPLATES[templateIndex % MAP_TEMPLATES.length].name;
}

/** Vrai si le gabarit est invariant par rotation 180° (équité des deux camps). */
export function isRotationSymmetric(template) {
  const rows = template.rows;
  for (let y = 0; y < ROWS; y++) {
    for (let x = 0; x < COLS; x++) {
      if (rows[y][x] !== rows[ROWS - 1 - y][COLS - 1 - x]) return false;
    }
  }
  return true;
}
