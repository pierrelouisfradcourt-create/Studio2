// render.mjs — UI only. Draws a `view()` snapshot to a 2D canvas context. No game rules here.

const GROUND_SCREEN_Y_RATIO = 0.75; // ground line sits at 75% of canvas height
const CAMERA_OFFSET = 160; // px, player stays this far from the left edge of the viewport
const PLAYER_SIZE = 20;
const COIN_RADIUS = 8;

export function renderFrame(ctx, view, meta = {}) {
  const { width, height } = ctx.canvas;
  const groundScreenY = height * GROUND_SCREEN_Y_RATIO;
  const cameraX = Math.max(0, view.x - CAMERA_OFFSET);

  // Background
  ctx.fillStyle = '#1b1f2a';
  ctx.fillRect(0, 0, width, height);

  // Ground
  ctx.strokeStyle = '#4caf50';
  ctx.lineWidth = 3;
  ctx.beginPath();
  ctx.moveTo(0, groundScreenY);
  ctx.lineTo(width, groundScreenY);
  ctx.stroke();

  // Level end marker
  const endScreenX = view.levelLength - cameraX;
  if (endScreenX >= -50 && endScreenX <= width + 50) {
    ctx.strokeStyle = '#ffeb3b';
    ctx.lineWidth = 3;
    ctx.setLineDash([8, 6]);
    ctx.beginPath();
    ctx.moveTo(endScreenX, groundScreenY - 200);
    ctx.lineTo(endScreenX, groundScreenY);
    ctx.stroke();
    ctx.setLineDash([]);
  }

  // Obstacles
  ctx.fillStyle = '#c0392b';
  for (const obs of view.obstaclesOnLevel) {
    const screenX = obs.x - cameraX;
    if (screenX < -50 || screenX > width + 50) continue;
    const left = screenX - obs.width / 2;
    const top = groundScreenY - obs.height;
    ctx.fillRect(left, top, obs.width, obs.height);
  }

  // Coins
  for (const coin of view.coinsOnLevel) {
    if (coin.collected) continue;
    const screenX = coin.x - cameraX;
    if (screenX < -50 || screenX > width + 50) continue;
    const screenY = groundScreenY + coin.y; // coin.y is <= 0 (above ground)
    ctx.fillStyle = '#ffd54f';
    ctx.beginPath();
    ctx.arc(screenX, screenY, COIN_RADIUS, 0, Math.PI * 2);
    ctx.fill();
    ctx.strokeStyle = '#b8860b';
    ctx.lineWidth = 2;
    ctx.stroke();
  }

  // Player
  const playerScreenX = view.x - cameraX;
  const playerScreenY = groundScreenY + view.y - PLAYER_SIZE; // view.y <= 0
  ctx.fillStyle = view.over && !view.won ? '#e74c3c' : '#42a5f5';
  ctx.fillRect(playerScreenX - PLAYER_SIZE / 2, playerScreenY, PLAYER_SIZE, PLAYER_SIZE);

  // HUD
  ctx.fillStyle = '#ffffff';
  ctx.font = '16px monospace';
  ctx.textAlign = 'left';
  const totalLevels = meta.totalLevels || 3;
  ctx.fillText(`Coins: ${view.coins}${meta.totalCoins ? ' / ' + meta.totalCoins : ''}`, 12, 24);
  ctx.fillText(`Level: ${view.level + 1} / ${totalLevels}`, 12, 44);
  ctx.fillText(`Dist: ${Math.floor(view.x)} / ${Math.floor(view.levelLength)}`, 12, 64);

  // Overlays
  if (view.over) {
    ctx.fillStyle = 'rgba(0,0,0,0.6)';
    ctx.fillRect(0, 0, width, height);
    ctx.textAlign = 'center';
    ctx.font = 'bold 40px monospace';
    ctx.fillStyle = view.won ? '#8bc34a' : '#e74c3c';
    ctx.fillText(view.won ? 'VICTOIRE !' : 'PERDU', width / 2, height / 2 - 10);
    ctx.font = '18px monospace';
    ctx.fillStyle = '#ffffff';
    ctx.fillText(`Coins: ${view.coins}${meta.totalCoins ? ' / ' + meta.totalCoins : ''} — appuie sur R pour rejouer`, width / 2, height / 2 + 30);
    ctx.textAlign = 'left';
  }
}
