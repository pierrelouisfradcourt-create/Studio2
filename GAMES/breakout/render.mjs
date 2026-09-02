// Breakout — RENDU uniquement. Lit l'état produit par game.mjs et le dessine.
// AUCUNE règle de jeu ici : pas de calcul de collisions, de rebonds — juste du dessin
// et de la mise à jour d'éléments DOM en lecture de l'état.

const COLOR_BG = "#101018";
const COLOR_WALL = "#2a2a3c";
const COLOR_PADDLE = "#4fc3f7";
const COLOR_PADDLE_RING = "#e1f5fe";
const COLOR_BALL = "#ffd700";
const COLOR_BALL_RING = "#ffed4e";
const COLOR_BRICK_BREAKABLE = "#ff5252";
const COLOR_BRICK_INDESTRUCTIBLE = "#505060";

// Dessine une frame complète de l'état `state` sur `ctx`
export function draw(ctx, state) {
  const { width, height, paddle, ball, bricks } = state;

  // Fond
  ctx.fillStyle = COLOR_BG;
  ctx.fillRect(0, 0, width, height);

  // Murs latéraux
  ctx.fillStyle = COLOR_WALL;
  ctx.fillRect(0, 0, 8, height);
  ctx.fillRect(width - 8, 0, 8, height);

  // Plafond
  ctx.fillRect(0, 0, width, 8);

  // Ligne du bas (repère de perte)
  ctx.strokeStyle = "#3a3a4a";
  ctx.lineWidth = 1;
  ctx.setLineDash([4, 4]);
  ctx.beginPath();
  ctx.moveTo(0, height - 5);
  ctx.lineTo(width, height - 5);
  ctx.stroke();
  ctx.setLineDash([]);

  // Briques (R5, R8)
  for (const brick of bricks) {
    if (brick.health > 0) {
      ctx.fillStyle = COLOR_BRICK_BREAKABLE;
    } else {
      ctx.fillStyle = COLOR_BRICK_INDESTRUCTIBLE;
      ctx.globalAlpha = 0.3; // Indestructibles semi-transparentes
    }
    ctx.fillRect(brick.x, brick.y, brick.width, brick.height);
    ctx.globalAlpha = 1;

    // Bordure brique
    ctx.strokeStyle = "rgba(255, 82, 82, 0.5)";
    ctx.lineWidth = 0.5;
    ctx.strokeRect(brick.x, brick.y, brick.width, brick.height);
  }

  // Raquette (R6, R7)
  ctx.fillStyle = COLOR_PADDLE;
  ctx.fillRect(paddle.x, paddle.y, paddle.width, paddle.height);
  ctx.strokeStyle = COLOR_PADDLE_RING;
  ctx.lineWidth = 1;
  ctx.strokeRect(paddle.x, paddle.y, paddle.width, paddle.height);

  // Balle (R1, R2, R3, R4, R5)
  ctx.fillStyle = COLOR_BALL;
  ctx.beginPath();
  ctx.arc(ball.x, ball.y, 5, 0, Math.PI * 2);
  ctx.fill();
  ctx.strokeStyle = COLOR_BALL_RING;
  ctx.lineWidth = 1;
  ctx.stroke();
}

// Met à jour le HUD (vies, score, niveau) — lecture seule de l'état
export function updateHud(state, els) {
  if (!els) return;
  if (els.lives) els.lives.textContent = String(state.lives);
  if (els.score) els.score.textContent = String(state.score);
  if (els.level) els.level.textContent = String(state.levelIndex + 1);
  if (els.brickCount) {
    const count = state.bricks.filter(b => b.health > 0).length;
    els.brickCount.textContent = String(count);
  }
}

// Met à jour l'overlay (état de fin/pause) — R16
export function drawOverlay(state, els) {
  if (!els || !els.overlay) return;

  if (state.status === 'ACTIVE') {
    els.overlay.classList.add('hidden');
  } else {
    els.overlay.classList.remove('hidden');
    let title = '';
    let message = '';

    if (state.status === 'LOST') {
      title = 'DÉFAITE';
      message = `Vous avez perdu ! Score: ${state.score}`;
    } else if (state.status === 'WON') {
      title = 'VICTOIRE';
      message = `Bravo ! Score final: ${state.score}`;
    } else if (state.status === 'PAUSE') {
      title = 'PAUSE';
      message = 'Appuyez sur P pour reprendre';
    }

    if (els.overlayTitle) els.overlayTitle.textContent = title;
    if (els.overlayMessage) els.overlayMessage.textContent = message;
  }
}
