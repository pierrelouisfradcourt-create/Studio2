// core.exit (VOLET WIRING, partiel -> la ligne reste BLOCKED). Prouve le CABLAGE de la
// sortie navigateur : requestExit('browser') NE se fie PLUS a window.close() (inerte,
// playtest "Quitter inerte") ; elle retourne un signal {stopped:true} et l'arret de la
// boucle (controller.stop) est un effet OBSERVABLE : tick() devient un no-op, l'etat
// fige. NE PROUVE PAS un clic navigateur REEL (volet browser_exit_click absent du recu
// produit, aucun outil d'automatisation navigateur sur ce poste) : residu en fog/BLOCKED.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createController } from '../../06_RUNTIME/adapters/presentation/browser/main.mjs';
import { requestExit } from '../../06_RUNTIME/adapters/presentation/exit.mjs';

test('core.exit : requestExit(browser) retourne un signal stopped (pas window.close)', () => {
  const r = requestExit('browser');   // pas de window ici -> ne ferme rien, retourne le signal
  assert.equal(r.stopped, true);
  assert.equal(r.code, 0);
  assert.equal(r.host, 'browser');
});

test('core.exit : stop() arrete la boucle -> tick() est un no-op, l etat fige', () => {
  const c = createController(1);
  c.tick({ p1: { down: true }, p2: {} });
  const before = c.state;
  c.stop();
  assert.equal(c.running, false);
  const events = c.tick({ p1: { down: true }, p2: {} });
  assert.deepEqual(c.state, before, 'l etat ne bouge plus apres l arret');
  assert.deepEqual(events, [], 'aucun evenement apres l arret');
});
