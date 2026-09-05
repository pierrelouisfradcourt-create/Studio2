// Survival Arena — RENDU uniquement. Lit l'état produit par game.mjs et le dessine.
// AUCUNE règle de jeu ici : pas de calcul de dégâts, de spawn, de score — juste du dessin
// et de la mise à jour d'éléments DOM en lecture de l'état.

const COLOR_BG = "#101018";
const COLOR_GRID = "#1c1c2a";
const COLOR_PLAYER = "#4fc3f7";
const COLOR_PLAYER_RING = "#e1f5fe";
const COLOR_ENEMY = "#ff5252";
const COLOR_ENEMY_LOW_HP = "#ffb74d";
const COLOR_BULLET = "#ffee58";

// Dessine une frame complète de l'état `state` (retour de SurvivalGame#view()) sur `ctx`.
export function draw(ctx, state) {
  const { width, height } = state;

  ctx.fillStyle = COLOR_BG;
  ctx.fillRect(0, 0, width, height);

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

  // balles
  ctx.fillStyle = COLOR_BULLET;
  for (const b of state.bullets) {
    ctx.beginPath();
    ctx.arc(b.x, b.y, b.r, 0, Math.PI * 2);
    ctx.fill();
  }

  // ennemis
  for (const e of state.enemies) {
    ctx.fillStyle = e.hp <= 1 ? COLOR_ENEMY_LOW_HP : COLOR_ENEMY;
    ctx.beginPath();
    ctx.arc(e.x, e.y, e.r, 0, Math.PI * 2);
    ctx.fill();
  }

  // joueur
  ctx.fillStyle = COLOR_PLAYER;
  ctx.beginPath();
  ctx.arc(state.player.x, state.player.y, state.player.r, 0, Math.PI * 2);
  ctx.fill();
  ctx.strokeStyle = COLOR_PLAYER_RING;
  ctx.lineWidth = 2;
  ctx.stroke();
}

// Met à jour le HUD (PV, score, temps) — lecture seule de l'état, aucune règle.
export function updateHud(state, els) {
  if (!els) return;
  if (els.hp) els.hp.textContent = `${Math.max(0, Math.round(state.hp))} / ${state.maxHp}`;
  if (els.score) els.score.textContent = String(state.score);
  if (els.time) els.time.textContent = (state.timeAlive / 1000).toFixed(1) + "s";
  if (els.hpBar) {
    const pct = state.maxHp > 0 ? Math.max(0, state.hp / state.maxHp) : 0;
    els.hpBar.style.width = `${(pct * 100).toFixed(1)}%`;
  }
}

// Affiche/masque l'overlay de défaite selon l'état — pure lecture, aucune règle.
export function updateOverlay(state, els) {
  if (!els || !els.overlay) return;
  if (state.over) {
    els.overlay.classList.remove("hidden");
    if (els.finalScore) els.finalScore.textContent = String(state.score);
    if (els.finalTime) els.finalTime.textContent = (state.timeAlive / 1000).toFixed(1) + "s";
  } else {
    els.overlay.classList.add("hidden");
  }
}
