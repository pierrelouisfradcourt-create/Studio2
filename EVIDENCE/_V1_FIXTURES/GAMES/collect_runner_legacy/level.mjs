// Collect Runner — génération de niveau PURE (seedée, déterministe).
// Aucun accès DOM, aucun window, aucune dépendance au moteur de jeu.
// Prend un RNG seedé et une seed en input, retourne la structure brute du niveau.

export function generateLevel(levelNumber, seed) {
  // Initialise un RNG seedé local pour ce niveau
  let rngState = (seed >>> 0) || 1;

  function rand() {
    let x = rngState;
    x ^= x << 13;
    x >>>= 0;
    x ^= x >>> 17;
    x ^= x << 5;
    x >>>= 0;
    rngState = x >>> 0;
    return rngState / 4294967296;
  }

  const coins = [];
  const obstacles = [];

  const COINS_PER_LEVEL = 3;
  const COIN_RADIUS = 6;

  // Génère les pièces du niveau
  for (let i = 0; i < COINS_PER_LEVEL; i++) {
    const coinX = 150 + i * 200 + rand() * 50;
    const coinY = 200 + rand() * 150;
    coins.push({ x: coinX, y: coinY, collected: false });
  }

  // Génère les obstacles (de plus en plus nombreux à chaque niveau)
  for (let i = 0; i < levelNumber; i++) {
    const obsX = 200 + i * 250 + rand() * 60;
    const obsY = 600 - 40 - 20; // GROUND_LEVEL - OBSTACLE_HEIGHT
    obstacles.push({ x: obsX, y: obsY, width: 20, height: 20 });
  }

  return {
    number: levelNumber,
    coins,
    obstacles,
  };
}
