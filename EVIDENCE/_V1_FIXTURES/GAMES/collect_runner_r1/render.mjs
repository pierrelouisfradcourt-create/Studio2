// render.mjs — UI-only canvas rendering. Takes a read-only `view()` snapshot
// from the pure engine and draws it. Never reads or mutates game rules.

const GROUND_Y_PX = 320; // canvas y coordinate of the ground line
const WORLD_TO_PX = 1; // 1 world unit == 1 pixel (kept explicit, not a magic literal at call sites)
const PLAYER_SIZE_PX = 20;
const CAMERA_MARGIN_PX = 160; // player stays this far from the left edge of the viewport

const COLORS = {
  sky: '#0e1b2a',
  ground: '#1e3d59',
  groundLine: '#5fd0ff',
  player: '#ffd23f',
  obstacle: '#e63946',
  coinGround: '#ffd700',
  coinElevated: '#7fffd4',
  hud: '#f1faee',
  overlayBg: 'rgba(0, 0, 0, 0.72)',
  overlayWin: '#7fffd4',
  overlayLose: '#e63946',
};

function worldToScreen(worldX, cameraX) {
  return (worldX - cameraX) * WORLD_TO_PX + CAMERA_MARGIN_PX;
}

/**
 * Draws one frame. `view` is the plain object returned by game.view().
 * `canvas` must be an HTMLCanvasElement with a valid 2D context.
 */
export function renderFrame(canvas, view) {
  const ctx = canvas.getContext('2d');
  if (!ctx) return; // defensive: canvas unsupported — nothing to draw, caller shows fallback text
  const width = canvas.width;
  const height = canvas.height;
  const cameraX = view.x;

  // Sky
  ctx.fillStyle = COLORS.sky;
  ctx.fillRect(0, 0, width, height);

  // Ground
  ctx.fillStyle = COLORS.ground;
  ctx.fillRect(0, GROUND_Y_PX, width, height - GROUND_Y_PX);
  ctx.strokeStyle = COLORS.groundLine;
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(0, GROUND_Y_PX);
  ctx.lineTo(width, GROUND_Y_PX);
  ctx.stroke();

  // Obstacles
  ctx.fillStyle = COLORS.obstacle;
  for (const obstacle of view.obstaclesOnLevel) {
    const sx = worldToScreen(obstacle.x, cameraX);
    if (sx + obstacle.width < 0 || sx > width) continue; // off-screen culling
    ctx.fillRect(sx, GROUND_Y_PX - 30, obstacle.width, 30);
  }

  // Coins
  for (const coin of view.coinsOnLevel) {
    if (coin.collected) continue;
    const sx = worldToScreen(coin.x, cameraX);
    if (sx + coin.width < 0 || sx > width) continue;
    const coinY = coin.elevated ? GROUND_Y_PX - 70 : GROUND_Y_PX - coin.width;
    ctx.fillStyle = coin.elevated ? COLORS.coinElevated : COLORS.coinGround;
    ctx.beginPath();
    ctx.arc(sx + coin.width / 2, coinY, coin.width / 2, 0, Math.PI * 2);
    ctx.fill();
  }

  // Player
  const playerScreenX = worldToScreen(view.x, cameraX);
  const playerScreenY = GROUND_Y_PX - view.y - PLAYER_SIZE_PX;
  ctx.fillStyle = COLORS.player;
  ctx.fillRect(playerScreenX, playerScreenY, PLAYER_SIZE_PX, PLAYER_SIZE_PX);

  // HUD
  ctx.fillStyle = COLORS.hud;
  ctx.font = '16px monospace';
  ctx.textBaseline = 'top';
  ctx.fillText(`Coins: ${view.coins}`, 12, 12);
  ctx.fillText(`Level: ${view.level}/3`, 12, 32);

  // End-of-run overlay
  if (view.over) {
    ctx.fillStyle = COLORS.overlayBg;
    ctx.fillRect(0, 0, width, height);
    ctx.textAlign = 'center';
    ctx.font = 'bold 36px monospace';
    ctx.fillStyle = view.won ? COLORS.overlayWin : COLORS.overlayLose;
    ctx.fillText(view.won ? 'VICTOIRE !' : 'PERDU', width / 2, height / 2 - 30);
    ctx.font = '18px monospace';
    ctx.fillStyle = COLORS.hud;
    ctx.fillText(`Pieces collectees : ${view.coins}`, width / 2, height / 2 + 20);
    ctx.fillText('Rechargez la page pour rejouer', width / 2, height / 2 + 48);
    ctx.textAlign = 'left';
  }
}

/** Renders a fallback message when canvas 2D context is unavailable. */
export function renderUnsupported(container) {
  container.textContent = 'Votre navigateur ne supporte pas <canvas> 2D — impossible d\'afficher le jeu.';
}
