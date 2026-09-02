// PONG — code de DESSIN partage (ADAPTATEUR, jamais importe par la logique).
// drawState() decrit l'image d'un etat via une interface de surface minimale
// {clear, fillRect} — implementee par un <canvas> (navigateur) OU par la Surface
// logicielle (capture headless). Un seul code de rendu, deux backends.
//
// LISIBILITE DE L'ETAT DECISIF (playtest-2026-07-27, play.score + core.end_condition) :
//   - le score est rendu en CHIFFRES (police pixel ci-dessous), plus en pips ;
//   - un ECRAN DE FIN EXPLICITE (qui gagne + score final) s'affiche quand la partie
//     est terminee. Le rendu est deterministe et decodable pixel-a-pixel, ce qui
//     permet a 07_TESTS/unit/{score_readout,end_screen}.test.mjs de prouver
//     MECANIQUEMENT que l'affiche correspond a l'etat interne.
import {
  FIELD_W, FIELD_H, PADDLE_W, PADDLE_H, BALL_R, P1_X, P2_X, STATUS,
} from '../../../05_SYSTEMS/game_state/state.mjs';

export const SCALE = 4;
export const VIEW_W = FIELD_W * SCALE;   // 800
export const VIEW_H = FIELD_H * SCALE;   // 480

const BG = [12, 14, 20];
const FG = [235, 238, 245];
const MID = [40, 46, 60];
const ACCENT = [90, 200, 160];
const PANEL = [6, 8, 12];
const WIN = [120, 220, 175];

// --- Police PIXEL 3x5 (chiffres + P/R/-/espace). Chaque glyphe = 5 lignes de 3 bits.
// Exportee pour que les tests de lisibilite decodent l'affiche et la comparent a l'etat.
export const GLYPH_W = 3;
export const GLYPH_H = 5;
export const GLYPHS = {
  '0': ['111', '101', '101', '101', '111'],
  '1': ['010', '110', '010', '010', '111'],
  '2': ['111', '001', '111', '100', '111'],
  '3': ['111', '001', '111', '001', '111'],
  '4': ['101', '101', '111', '001', '001'],
  '5': ['111', '100', '111', '001', '111'],
  '6': ['111', '100', '111', '101', '111'],
  '7': ['111', '001', '010', '010', '010'],
  '8': ['111', '101', '111', '101', '111'],
  '9': ['111', '101', '111', '001', '111'],
  'P': ['111', '101', '111', '100', '100'],
  'R': ['111', '101', '111', '110', '101'],
  '-': ['000', '000', '111', '000', '000'],
  ' ': ['000', '000', '000', '000', '000'],
};

// Largeur pixel d'un texte rendu a l'echelle `px` (avance = (GLYPH_W+1)*px par char).
export function textWidth(text, px) {
  return text.length * (GLYPH_W + 1) * px - px;
}

// Dessine un glyphe unique en haut-gauche (gx,gy), chaque bit occupant px*px.
function drawGlyph(surface, ch, gx, gy, px, color) {
  const rows = GLYPHS[ch] || GLYPHS[' '];
  for (let r = 0; r < GLYPH_H; r += 1) {
    for (let c = 0; c < GLYPH_W; c += 1) {
      if (rows[r][c] === '1') {
        surface.fillRect(gx + c * px, gy + r * px, px, px, ...color);
      }
    }
  }
}

// Dessine un texte a partir de (x,y). Caracteres inconnus -> espace (jamais un crash).
export function drawText(surface, text, x, y, px, color) {
  let cx = x;
  for (const ch of String(text)) {
    drawGlyph(surface, ch, cx, y, px, color);
    cx += (GLYPH_W + 1) * px;
  }
}

// Position/echelle des CHIFFRES de score (exportees : les tests lisent la ces pixels).
export const SCORE_PX = SCALE * 2;                 // 8 -> chiffre 24x40 px
export const SCORE_Y = SCALE * 4;                  // 16
export const SCORE_P1_X = VIEW_W / 2 - SCALE * 24; // gauche du centre
export const SCORE_P2_X = VIEW_W / 2 + SCALE * 16; // droite du centre

// Dessine l'etat courant. `surface` expose clear(r,g,b) et fillRect(x,y,w,h,r,g,b).
export function drawState(state, surface) {
  surface.clear(...BG);

  // ligne mediane pointillee
  for (let y = 0; y < VIEW_H; y += SCALE * 6) {
    surface.fillRect(VIEW_W / 2 - SCALE / 2, y, SCALE, SCALE * 3, ...MID);
  }

  // raquettes (gauche = P1_X est le PLAN de collision -> face droite de la raquette).
  // Le vainqueur (fin de partie) est surligne en couleur WIN pour renforcer la lecture.
  const p1Color = state.status === STATUS.P1_WIN ? WIN : FG;
  const p2Color = state.status === STATUS.P2_WIN ? WIN : FG;
  surface.fillRect((P1_X - PADDLE_W) * SCALE, state.p1.y * SCALE, PADDLE_W * SCALE, PADDLE_H * SCALE, ...p1Color);
  surface.fillRect(P2_X * SCALE, state.p2.y * SCALE, PADDLE_W * SCALE, PADDLE_H * SCALE, ...p2Color);

  // balle
  surface.fillRect((state.ball.x - BALL_R) * SCALE, (state.ball.y - BALL_R) * SCALE,
    BALL_R * 2 * SCALE, BALL_R * 2 * SCALE, ...FG);

  // score EN CHIFFRES (play.score : plus de pips). Le rendu correspond exactement a
  // l'etat interne : chiffre de score[p1] a gauche, score[p2] a droite.
  drawText(surface, String(state.score.p1), SCORE_P1_X, SCORE_Y, SCORE_PX, ACCENT);
  drawText(surface, String(state.score.p2), SCORE_P2_X, SCORE_Y, SCORE_PX, ACCENT);

  // ECRAN DE FIN EXPLICITE (core.end_condition) : panneau centre, vainqueur en toutes
  // lettres (P1/P2) + score final. Affiche uniquement quand la partie est terminee.
  if (state.status !== STATUS.PLAYING) {
    drawEndScreen(state, surface);
  }
}

// Position/echelle de l'ecran de fin (exportees pour les tests de lisibilite).
export const END_LABEL_PX = SCALE * 4;             // 16 -> "P1"/"P2" tres lisible
export const END_SCORE_PX = SCALE * 2;             // 8
export const END_HINT_PX = SCALE;                  // 4
export const END_PANEL = { w: VIEW_W * 0.6, h: VIEW_H * 0.55 };

function drawEndScreen(state, surface) {
  const pw = END_PANEL.w;
  const ph = END_PANEL.h;
  const px0 = (VIEW_W - pw) / 2;
  const py0 = (VIEW_H - ph) / 2;
  surface.fillRect(px0, py0, pw, ph, ...PANEL);

  const winner = state.status === STATUS.P1_WIN ? 'P1' : 'P2';
  const label = winner;
  const lx = (VIEW_W - textWidth(label, END_LABEL_PX)) / 2;
  const ly = py0 + ph * 0.16;
  drawText(surface, label, lx, ly, END_LABEL_PX, WIN);

  const scoreText = `${state.score.p1}-${state.score.p2}`;
  const sx = (VIEW_W - textWidth(scoreText, END_SCORE_PX)) / 2;
  const sy = ly + GLYPH_H * END_LABEL_PX + SCALE * 6;
  drawText(surface, scoreText, sx, sy, END_SCORE_PX, FG);

  // affordance de relance sur le canvas (le bouton HTML "Rejouer" existe aussi).
  const hint = 'R';
  const hx = (VIEW_W - textWidth(hint, END_HINT_PX)) / 2;
  const hy = sy + GLYPH_H * END_SCORE_PX + SCALE * 6;
  drawText(surface, hint, hx, hy, END_HINT_PX, ACCENT);
}

export { drawEndScreen, BG, FG, ACCENT, WIN, PANEL };
