// core.restart (VOLET WIRING, partiel -> la ligne reste BLOCKED). Prouve le CABLAGE de
// la relance offerte au joueur : controller.replay() (declenche par le bouton "Rejouer"
// ou la touche R) ramene a un etat initial PROPRE, identique au premier boot, et
// reprend la boucle. NE PROUVE PAS un clic navigateur REEL (volet browser_restart_click
// absent du recu produit, aucun outil d'automatisation navigateur sur ce poste) :
// c'est le residu remonte en fog / BLOCKED dans le rapport.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createController } from '../../06_RUNTIME/adapters/presentation/browser/main.mjs';
import { boot } from '../../05_SYSTEMS/game_loop/loop.mjs';

test('core.restart : replay() ramene a l etat initial propre (aucun residu)', () => {
  const c = createController(1);
  for (let i = 0; i < 60; i += 1) c.tick({ p1: { down: true }, p2: {} }); // fait evoluer l'etat
  assert.notDeepEqual(c.state, boot(1), 'l etat a bien evolue avant la relance');
  c.replay();
  assert.deepEqual(c.state, boot(1), 'relance -> etat identique au premier demarrage');
  assert.equal(c.running, true);
});

test('core.restart : replay() relance meme apres une sortie (running repasse a true)', () => {
  const c = createController(1);
  c.stop();
  assert.equal(c.running, false);
  c.replay();
  assert.equal(c.running, true);
  assert.deepEqual(c.state, boot(1));
});
