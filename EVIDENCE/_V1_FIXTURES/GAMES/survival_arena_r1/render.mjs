// render.mjs -- Canvas rendering ONLY. No game logic lives here.
// Draws a view() snapshot produced by game.mjs onto a 2D canvas context.

/**
 * @param {CanvasRenderingContext2D} ctx
 * @param {object} view snapshot returned by SurvivalGame#view()
 */
export function render(ctx, view) {
  const { arenaWidth, arenaHeight, player, enemies, bullets, hp, maxHp, score, over } = view;

  // background
  ctx.fillStyle = '#10121a';
  ctx.fillRect(0, 0, arenaWidth, arenaHeight);

  // arena border
  ctx.strokeStyle = '#3a3f52';
  ctx.lineWidth = 2;
  ctx.strokeRect(1, 1, arenaWidth - 2, arenaHeight - 2);

  // bullets
  ctx.fillStyle = '#ffe066';
  for (const b of bullets) {
    ctx.beginPath();
    ctx.arc(b.x, b.y, 4, 0, Math.PI * 2);
    ctx.fill();
  }

  // enemies
  ctx.fillStyle = '#ff5c5c';
  for (const e of enemies) {
    ctx.beginPath();
    ctx.arc(e.x, e.y, 10, 0, Math.PI * 2);
    ctx.fill();
  }

  // player
  ctx.fillStyle = '#5ce1ff';
  ctx.beginPath();
  ctx.arc(player.x, player.y, 12, 0, Math.PI * 2);
  ctx.fill();

  // HUD
  ctx.fillStyle = '#e8e8e8';
  ctx.font = '16px monospace';
  ctx.textBaseline = 'top';
  ctx.fillText(`Score: ${score}`, 10, 10);

  const barWidth = 160;
  const barHeight = 14;
  const hpRatio = Math.max(0, Math.min(1, hp / maxHp));
  ctx.fillStyle = '#402020';
  ctx.fillRect(arenaWidth - barWidth - 10, 10, barWidth, barHeight);
  ctx.fillStyle = hpRatio > 0.3 ? '#5cff8a' : '#ff5c5c';
  ctx.fillRect(arenaWidth - barWidth - 10, 10, barWidth * hpRatio, barHeight);
  ctx.strokeStyle = '#888';
  ctx.strokeRect(arenaWidth - barWidth - 10, 10, barWidth, barHeight);
  ctx.fillStyle = '#e8e8e8';
  ctx.fillText(`HP: ${Math.ceil(hp)}/${maxHp}`, arenaWidth - barWidth - 10, 28);

  if (over) {
    ctx.fillStyle = 'rgba(0,0,0,0.6)';
    ctx.fillRect(0, 0, arenaWidth, arenaHeight);
    ctx.fillStyle = '#ff5c5c';
    ctx.font = 'bold 40px monospace';
    ctx.textAlign = 'center';
    ctx.fillText('GAME OVER', arenaWidth / 2, arenaHeight / 2 - 40);
    ctx.fillStyle = '#e8e8e8';
    ctx.font = '20px monospace';
    ctx.fillText(`Score final: ${score}`, arenaWidth / 2, arenaHeight / 2 + 10);
    ctx.font = '16px monospace';
    ctx.fillText('Appuie sur R ou clique Rejouer', arenaWidth / 2, arenaHeight / 2 + 45);
    ctx.textAlign = 'left';
  }
}
