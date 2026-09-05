// Collect Runner — RENDU uniquement. Lit l'état produit par game.mjs et le dessine.
// AUCUNE règle de jeu ici : pas de calcul de pièces, de collisions, de sauts — juste du dessin
// et de la mise à jour d'éléments DOM en lecture de l'état.

const COLOR_BG = "#101018";
const COLOR_GRID = "#1c1c2a";
const COLOR_PLAYER = "#4fc3f7";
const COLOR_PLAYER_RING = "#e1f5fe";
const COLOR_COIN = "#ffd700";
const COLOR_COIN_RING = "#ffed4e";
const COLOR_OBSTACLE = "#ff5252";

// Dessine une frame complète de l'état `state` (retour de CollectRunnerGame#view()) sur `ctx`.
export function draw(ctx, state) {
  const { width, height } = state;

  // Fond
  ctx.fillStyle = COLOR_BG;
  ctx.fillRect(0, 0, width, height);

  // Grille
  ctx.strokeStyle = COLOR_GRID;
  ctx.lineWidth = 1;
  const step = 40;
  for (let x = 0; x <= width; x += step) {
    ctx.beginPath();
    ctx.moveTo(x, 0);
    ctx.lineTo(x, height);
    ctx.stroke();
  }
  for (let y = 0; y <= height; y += step) {
    ctx.beginPath();
    ctx.moveTo(0, y);
    ctx.lineTo(width, y);
    ctx.stroke();
  }

  // Ligne du sol
  ctx.strokeStyle = "#3a3a4a";
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(0, height - 40);
  ctx.lineTo(width, height - 40);
  ctx.stroke();

  // Pièces
  for (const coin of state.coinsOnLevel) {
    if (!coin.collected) {
      ctx.fillStyle = COLOR_COIN;
      ctx.beginPath();
      ctx.arc(coin.x, coin.y, 6, 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = COLOR_COIN_RING;
      ctx.lineWidth = 2;
      ctx.stroke();
    }
  }

  // Obstacles
  ctx.fillStyle = COLOR_OBSTACLE;
  for (const obs of state.obstaclesOnLevel) {
    ctx.fillRect(obs.x, obs.y, obs.width, obs.height);
  }

  // Joueur
  ctx.fillStyle = COLOR_PLAYER;
  ctx.fillRect(state.player.x, state.player.y, state.player.width, state.player.height);
  ctx.strokeStyle = COLOR_PLAYER_RING;
  ctx.lineWidth = 2;
  ctx.strokeRect(state.player.x, state.player.y, state.player.width, state.player.height);
}

// Met à jour le HUD (pièces, niveau) — lecture seule de l'état, aucune règle.
export function updateHud(state, els) {
  if (!els) return;
  if (els.coins) els.coins.textContent = String(state.coins);
  if (els.level) els.level.textContent = String(state.level);
  if (els.levelCoins) els.levelCoins.textContent = String(state.levelCoins);
}

// Affiche/masque l'overlay de défaite ou victoire selon l'état — pure lecture, aucune règle.
export function updateOverlay(state, els) {
  if (!els) return;

  if (state.won) {
    if (els.overlay) els.overlay.classList.remove("hidden");
    if (els.overlayTitle) els.overlayTitle.textContent = "VICTOIRE !";
    if (els.overlayTitle) els.overlayTitle.style.color = "#66bb6a";
    if (els.finalCoins) els.finalCoins.textContent = String(state.coins);
    if (els.finalLevel) els.finalLevel.textContent = String(state.level);
  } else if (state.over) {
    if (els.overlay) els.overlay.classList.remove("hidden");
    if (els.overlayTitle) els.overlayTitle.textContent = "DÉFAITE";
    if (els.overlayTitle) els.overlayTitle.style.color = "#ff5252";
    if (els.finalCoins) els.finalCoins.textContent = String(state.coins);
    if (els.finalLevel) els.finalLevel.textContent = String(state.level);
  } else {
    if (els.overlay) els.overlay.classList.add("hidden");
  }
}
