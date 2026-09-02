// play.solo_opponent (renfort mutation + distinctness) : l'IA solo (05_SYSTEMS/input/
// ai.mjs) est un adversaire JOUABLE, distinct du bot de solvabilite a latence nulle.
// Assertions STRICTES qui tuent les mutants eq->neq de ai.mjs et prouvent la latence
// (reaction seulement quand la balle vient) + la deadzone (imperfection).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { soloAiDir, soloAction, AI_DEADZONE } from '../../05_SYSTEMS/input/ai.mjs';
import { PADDLE_H, FIELD_H } from '../../05_SYSTEMS/game_state/state.mjs';

const MID = PADDLE_H / 2;

// side==='p2' : la balle ARRIVE (vx>0) bien AU-DESSUS du centre -> l'IA monte ('up').
// Tue eq->neq sur `side === 'p2'` : mutee, 'p2' serait vu "s'eloigne" et l'IA
// recentrerait au lieu de suivre.
test('soloAiDir p2 : balle qui arrive au-dessus -> up (tue side===p2)', () => {
  assert.equal(soloAiDir('p2', 50, { y: 8, vx: 3, vy: 0 }), 'up');
});

test('soloAiDir p2 : balle qui arrive en dessous -> down', () => {
  assert.equal(soloAiDir('p2', 50, { y: FIELD_H - 4, vx: 3, vy: 0 }), 'down');
});

// Balle qui S'ELOIGNE de p2 (vx<0) : l'IA RECENTRE (ne suit pas la balle). C'est la
// latence non nulle qui la distingue du tracker parfait de solvabilite.
test('soloAiDir p2 : balle qui s eloigne -> recentre, PAS suivre (distinct du tracker)', () => {
  // raquette tout en haut, balle en haut aussi mais qui part (vx<0) : un tracker
  // parfait resterait immobile (deja aligne) ; l'IA solo descend vers le centre.
  assert.equal(soloAiDir('p2', 0, { y: 2, vx: -3, vy: 0 }), 'down');
});

// soloAction : humanSide='p1' -> l'IA prend p2, le joueur garde p1. Tue eq->neq sur
// `humanSide === 'p1'` : mutee, l'IA volerait la raquette du joueur.
test('soloAction humanSide=p1 : l IA tient p2, le joueur garde p1 (tue humanSide===p1)', () => {
  const state = { p1: { y: 30 }, p2: { y: 60 }, ball: { y: 8, vx: 3, vy: 0 } };
  const act = soloAction('p1', 'down', state);
  assert.equal(act.p1, 'down', 'p1 = entree du joueur (inchangee)');
  assert.equal(act.p2, 'up', 'p2 = IA (balle en haut, arrive) -> up');
});

test('soloAction humanSide=p2 : l IA tient p1', () => {
  const state = { p1: { y: 60 }, p2: { y: 30 }, ball: { y: 8, vx: -3, vy: 0 } };
  const act = soloAction('p2', 'up', state);
  assert.equal(act.p2, 'up', 'p2 = entree du joueur');
  assert.equal(act.p1, 'up', 'p1 = IA (balle en haut, vx<0 arrive vers p1) -> up');
});

// deadzone : balle quasi alignee (dans AI_DEADZONE) -> immobile (null) : l'imperfection
// qui laisse une fenetre au joueur.
test('soloAiDir : dans la deadzone -> immobile (null)', () => {
  const center = 50 + MID;
  assert.equal(soloAiDir('p2', 50, { y: center + AI_DEADZONE - 0.5, vx: 3, vy: 0 }), null);
  assert.equal(soloAiDir('p2', 50, { y: center - AI_DEADZONE + 0.5, vx: 3, vy: 0 }), null);
});
