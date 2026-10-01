// Règles vérifiées à l'INTÉGRATION des lots V2 (2026-10-01). Fichier créé dans cette passe.
// Lancement : node --test tests/*.test.mjs

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createGame, stepGame, emptyInput } from '../src/sim/game.mjs';
import { createEnemy } from '../src/sim/enemies.mjs';
import { createTuning } from '../src/sim/config.mjs';
import { sanitizeProfile, unlock, selectClass, unlockCost } from '../src/sim/profile.mjs';

/** Salle vide, héros immobile au centre. */
function emptyRoom(seed = 5) {
  const g = createGame({ seed });
  g.spawns.length = 0;
  g.enemies.length = 0;
  g.room.waves = [];
  g.room.cleared = true;
  g.room.interact = null;
  g.room.doors = [];
  g.room.obstacles = [];
  g.player.x = g.room.w / 2;
  g.player.y = g.room.h / 2;
  g.events.length = 0;
  return g;
}

test('diablotin : un héros immobile est attaqué régulièrement (plus d\'orbite hors de portée)', () => {
  const g = emptyRoom();
  createEnemy(g, 'imp', g.player.x + 150, g.player.y + 40, { spawnT: 0 });
  let attacks = 0;
  for (let i = 0; i < 600; i++) {
    stepGame(g, emptyInput());
    attacks += g.events.filter((ev) => ev.type === 'enemyAttack').length;
    g.events.length = 0;
  }
  // 10 s, recharge de 0,9 s + télégraphe + récupération : bien plus d'une attaque.
  assert.ok(attacks >= 3, `attaques en 10 s : ${attacks}`);
});

test('Ville : débloquer une classe donne aussi son kit gratuit (arme, compétence, gadget de coût 0)', () => {
  const t = createTuning();
  const p = sanitizeProfile({ souls: 1000 }, t);
  for (const classId of Object.keys(t.classes)) {
    if (!p.unlocked.classes.includes(classId)) assert.equal(unlock(p, t, 'classes', classId).ok, true);
    const c = t.classes[classId];
    for (const [kind, ids] of [['weapons', c.weapons], ['skills', c.skills], ['gadgets', c.gadgets]]) {
      for (const id of ids) {
        if (unlockCost(t, kind, id) === 0) assert.ok(p.unlocked[kind].includes(id), `${classId} : ${kind}/${id} gratuit mais verrouillé`);
      }
    }
    assert.equal(selectClass(p, t, classId).ok, true);
    assert.ok(p.unlocked.skills.includes(p.loadout.skillId), `${classId} : compétence choisie possédée`);
    assert.ok(p.unlocked.gadgets.includes(p.loadout.gadgetId), `${classId} : gadget choisi possédé`);
  }
});
