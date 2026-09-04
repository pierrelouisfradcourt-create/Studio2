// Rendu — présentation seule, aucune règle de jeu ici.
// Lit un état (fourni par l'appelant) et peint ; ne dépend NI de input, NI de main
// (architecture_contract). Les libellés d'état viennent du vocabulaire du moteur.

import { STATE_WON, STATE_LOST } from './engine.mjs';

export const OBJECTIVE_TEXT = 'Objectif : detruire toutes les briques';
export const WIN_TEXT = 'VICTOIRE';
export const LOSE_TEXT = 'DEFAITE';

const BACKGROUND_COLOR = '#101418';
const BRICK_COLOR = '#4caf50';
const PADDLE_COLOR = '#2196f3';
const BALL_COLOR = '#ffc107';
const HUD_COLOR = '#ffffff';
const OVERLAY_COLOR = 'rgba(0, 0, 0, 0.72)';
const HUD_FONT = '16px Arial, sans-serif';
const OVERLAY_FONT = 'bold 48px Arial, sans-serif';
const HUD_X = 20;
const HUD_Y = 28;
const BALL_DRAW_RADIUS = 5;

/**
 * Libellé de fin de partie pour un état donné — fonction PURE, partagée par le
 * canvas et par le panneau DOM (#overlayText) : un seul texte, une seule source.
 */
export function overlayTextFor(state) {
  if (state.state === STATE_WON) return WIN_TEXT;
  if (state.state === STATE_LOST) return LOSE_TEXT;
  return '';
}

/** Texte d'objectif affiché en permanence dans le HUD (R1). */
export function objectiveTextFor(state) {
  return `${OBJECTIVE_TEXT} — restantes : ${state.bricksRemaining}`;
}

export class Renderer {
  constructor(canvas) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
  }

  render(state) {
    this.ctx.fillStyle = BACKGROUND_COLOR;
    this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
    this.renderBricks(state.bricks);
    this.renderPaddle(state.paddle);
    this.renderBall(state.ball);
    this.renderObjective(state);
  }

  renderBricks(bricks) {
    this.ctx.fillStyle = BRICK_COLOR;
    for (const brick of bricks) {
      if (brick.destroyed === false) {
        this.ctx.fillRect(brick.x, brick.y, brick.width, brick.height);
      }
    }
  }

  renderPaddle(paddle) {
    this.ctx.fillStyle = PADDLE_COLOR;
    this.ctx.fillRect(paddle.x, paddle.y, paddle.width, paddle.height);
  }

  renderBall(ball) {
    this.ctx.fillStyle = BALL_COLOR;
    this.ctx.beginPath();
    this.ctx.arc(ball.x, ball.y, BALL_DRAW_RADIUS, 0, Math.PI * 2);
    this.ctx.fill();
  }

  /** R1 — l'objectif du joueur est écrit à l'écran tant que la partie tourne. */
  renderObjective(state) {
    this.ctx.fillStyle = HUD_COLOR;
    this.ctx.font = HUD_FONT;
    this.ctx.fillText(objectiveTextFor(state), HUD_X, HUD_Y);
  }

  /** R6/R7 — panneau de fin de partie peint par-dessus la scène. */
  renderOverlay(state) {
    this.ctx.fillStyle = OVERLAY_COLOR;
    this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
    this.ctx.fillStyle = HUD_COLOR;
    this.ctx.font = OVERLAY_FONT;
    this.ctx.fillText(overlayTextFor(state), this.canvas.width / 2, this.canvas.height / 2);
  }
}
