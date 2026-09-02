// play.score (volet observable) : le score est rendu EN CHIFFRES et l'affiche
// correspond EXACTEMENT a l'etat interne. Ce test rend l'etat sur la Surface logicielle
// (le MEME drawState que le <canvas> reel), puis DECODE les pixels du score en chiffre
// et le compare a l'etat -- preuve mecanique de "l'affiche == l'etat", pas une simple
// existence de rendu.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Surface } from '../../06_RUNTIME/adapters/presentation/raster.mjs';
import {
  drawState, GLYPHS, GLYPH_W, GLYPH_H, VIEW_W, VIEW_H,
  SCORE_P1_X, SCORE_P2_X, SCORE_Y, SCORE_PX,
} from '../../06_RUNTIME/adapters/presentation/draw.mjs';

function playing(a, b) {
  return {
    status: 'PLAYING', p1: { y: 48 }, p2: { y: 48 },
    ball: { x: 100, y: 60, vx: 1, vy: 1 }, score: { p1: a, p2: b },
  };
}
function render(state) {
  const s = new Surface(VIEW_W, VIEW_H);
  drawState(state, s);
  return s;
}
// "on" = pixel proche de ACCENT (90,200,160) : g haut, r bas. Distingue des chiffres
// (ACCENT) du fond BG et des raquettes/balle FG (r haut).
function sampleOn(surf, x, y) {
  const i = (Math.floor(y) * surf.w + Math.floor(x)) * 4;
  return surf.buf[i + 1] > 150 && surf.buf[i] < 160;
}
function readDigit(surf, x0, y0, px) {
  let bits = '';
  for (let r = 0; r < GLYPH_H; r += 1) {
    for (let c = 0; c < GLYPH_W; c += 1) {
      bits += sampleOn(surf, x0 + c * px + px / 2, y0 + r * px + px / 2) ? '1' : '0';
    }
  }
  for (let d = 0; d <= 9; d += 1) {
    if (GLYPHS[String(d)].join('') === bits) return d;
  }
  return null;
}

test('play.score : le score affiche en CHIFFRES correspond exactement a l etat', () => {
  for (const [a, b] of [[0, 0], [1, 0], [2, 1], [3, 2], [0, 3]]) {
    const surf = render(playing(a, b));
    assert.equal(readDigit(surf, SCORE_P1_X, SCORE_Y, SCORE_PX), a, `p1 doit afficher ${a}`);
    assert.equal(readDigit(surf, SCORE_P2_X, SCORE_Y, SCORE_PX), b, `p2 doit afficher ${b}`);
  }
});

test('play.score : l affiche SUIT le score (deux scores -> deux chiffres distincts)', () => {
  const d1 = readDigit(render(playing(1, 0)), SCORE_P1_X, SCORE_Y, SCORE_PX);
  const d3 = readDigit(render(playing(3, 0)), SCORE_P1_X, SCORE_Y, SCORE_PX);
  assert.equal(d1, 1);
  assert.equal(d3, 3);
  assert.notEqual(d1, d3);
});
