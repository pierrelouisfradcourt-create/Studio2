// core.end_condition (volet observable) : un ETAT FINAL EXPLICITE, lisible par un
// joueur (qui gagne, qui perd), est affiche a l'ecran quand la partie est terminee.
// Ce test rend l'etat de fin sur la Surface logicielle (meme drawState que le canvas),
// DECODE le label vainqueur ("P1"/"P2") et verifie qu'aucun ecran de fin n'apparait
// tant que la partie est en cours.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Surface } from '../../06_RUNTIME/adapters/presentation/raster.mjs';
import {
  drawState, GLYPHS, GLYPH_W, GLYPH_H, VIEW_W, VIEW_H,
  textWidth, END_LABEL_PX, END_PANEL,
} from '../../06_RUNTIME/adapters/presentation/draw.mjs';

function state(status, a, b) {
  return {
    status, p1: { y: 48 }, p2: { y: 48 },
    ball: { x: 100, y: 60, vx: 1, vy: 1 }, score: { p1: a, p2: b },
  };
}
function render(s) { const sf = new Surface(VIEW_W, VIEW_H); drawState(s, sf); return sf; }

// "on" = pixel proche de WIN (120,220,175) : g tres haut, r bas. Le label vainqueur
// est peint en WIN par-dessus le panneau sombre PANEL.
function sampleWin(surf, x, y) {
  const i = (Math.floor(y) * surf.w + Math.floor(x)) * 4;
  return surf.buf[i + 1] > 180 && surf.buf[i] < 170;
}
function readGlyphWin(surf, x0, y0, px) {
  let bits = '';
  for (let r = 0; r < GLYPH_H; r += 1) {
    for (let c = 0; c < GLYPH_W; c += 1) {
      bits += sampleWin(surf, x0 + c * px + px / 2, y0 + r * px + px / 2) ? '1' : '0';
    }
  }
  for (const [ch, rows] of Object.entries(GLYPHS)) {
    if (rows.join('') === bits) return ch;
  }
  return null;
}
function labelPos(text) {
  const lx = (VIEW_W - textWidth(text, END_LABEL_PX)) / 2;
  const py0 = (VIEW_H - END_PANEL.h) / 2;
  const ly = py0 + END_PANEL.h * 0.16;
  return { lx, ly };
}

test('core.end_condition : P1_WIN affiche "P1" lisible a l ecran', () => {
  const surf = render(state('P1_WIN', 3, 1));
  const { lx, ly } = labelPos('P1');
  assert.equal(readGlyphWin(surf, lx, ly, END_LABEL_PX), 'P');
  assert.equal(readGlyphWin(surf, lx + (GLYPH_W + 1) * END_LABEL_PX, ly, END_LABEL_PX), '1');
});

test('core.end_condition : P2_WIN affiche "P2" lisible a l ecran', () => {
  const surf = render(state('P2_WIN', 1, 3));
  const { lx, ly } = labelPos('P2');
  assert.equal(readGlyphWin(surf, lx, ly, END_LABEL_PX), 'P');
  assert.equal(readGlyphWin(surf, lx + (GLYPH_W + 1) * END_LABEL_PX, ly, END_LABEL_PX), '2');
});

test('core.end_condition : l ecran de fin DIFFERE de l ecran de jeu et n est pas monochrome', () => {
  const playing = render(state('PLAYING', 3, 1));
  const ended = render(state('P1_WIN', 3, 1));
  assert.notEqual(Buffer.compare(Buffer.from(playing.buf), Buffer.from(ended.buf)), 0);
  assert.ok(ended.distinctColors() >= 2);
});

test('core.end_condition : AUCUN ecran de fin tant que la partie est en cours', () => {
  const surf = render(state('PLAYING', 2, 2));
  const { lx, ly } = labelPos('P1');
  let anyWin = false;
  for (let r = 0; r < GLYPH_H; r += 1) {
    for (let c = 0; c < GLYPH_W; c += 1) {
      if (sampleWin(surf, lx + c * END_LABEL_PX + END_LABEL_PX / 2,
        ly + r * END_LABEL_PX + END_LABEL_PX / 2)) anyWin = true;
    }
  }
  assert.equal(anyWin, false, 'aucun label vainqueur ne doit apparaitre en cours de partie');
});
