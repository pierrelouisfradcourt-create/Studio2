// Breakout — génération de niveau PURE (seedée, déterministe).
// Aucun accès DOM, window, ou dépendance au moteur de jeu.
// Prend une seed et un index de niveau, retourne la structure brute des briques.

// RNG xorshift32 — déterministe, aucune dépendance à Math.random()
function xorshift32(seed) {
  let x = (seed >>> 0) || 1;

  function rand() {
    let state = x;
    state ^= state << 13;
    state >>>= 0;
    state ^= state >>> 17;
    state ^= state << 5;
    state >>>= 0;
    x = state >>> 0;
    return x / 4294967296;
  }

  return { rand };
}

export function generateLevel(seed, levelIndex) {
  const rng = xorshift32(seed + levelIndex * 1000);
  const bricks = [];

  // Dimensions et layout
  const BRICK_WIDTH = 60;
  const BRICK_HEIGHT = 16;
  const BRICK_GAP = 4;
  const GAME_WIDTH = 800;
  const START_X = 40;
  const START_Y = 40;

  // Nombre de lignes et briques dépend du niveau
  const rows = 3 + levelIndex; // Niveau 0: 3 lignes, Niveau 1: 4, Niveau 2: 5
  const cols = Math.floor((GAME_WIDTH - START_X * 2) / (BRICK_WIDTH + BRICK_GAP));

  let brickValue = 10; // Points par brique

  // Génère la grille de briques
  for (let row = 0; row < rows; row++) {
    for (let col = 0; col < cols; col++) {
      const x = START_X + col * (BRICK_WIDTH + BRICK_GAP);
      const y = START_Y + row * (BRICK_HEIGHT + BRICK_GAP);

      // Certaines briques sont indestructibles (selon la seed du niveau)
      const isBreakable = rng.rand() > 0.15; // 85% destructibles

      bricks.push({
        x,
        y,
        width: BRICK_WIDTH,
        height: BRICK_HEIGHT,
        health: isBreakable ? 1 : 0, // 0 = indestructible, 1 = destructible
        value: brickValue,
        breakable: isBreakable,
      });
    }
  }

  return {
    levelIndex,
    bricks,
    seed,
  };
}
