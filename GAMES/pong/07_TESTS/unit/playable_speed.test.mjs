// play.playable_speed (preuve `test`) : le temps de traversee de service derive des
// constantes (BALL_VX/TICK_HZ/SERVE_CROSS_DIST) doit tomber dans la BANDE JOUABLE
// declaree par la Genre Bible Pong. Une vitesse hors bande FAIT ECHOUER ce test —
// c'est un FAIL, pas un reglage (playtest-2026-07-27).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  ballCrossingTimeSeconds, TICK_HZ, SERVE_CROSS_DIST,
} from '../../05_SYSTEMS/game_loop/loop.mjs';
import { BALL_VX } from '../../05_SYSTEMS/game_state/state.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const bible = JSON.parse(
  readFileSync(join(HERE, '..', '..', '01_DESIGN', 'genre_bible.json'), 'utf-8'));
const rule = bible.genre_rules.find((r) => r.id === 'genre.pong.playable_speed_range');

// Bande LUE de la Genre Bible (couplage mecanique : si la bible change la bande, ce
// test la suit). Statement : "... ball_crossing_time entre 1.0s et 1.5s ...".
const m = /entre\s+([\d.]+)\s*s\s+et\s+([\d.]+)\s*s/i.exec(rule?.statement ?? '');
const MIN_S = m ? parseFloat(m[1]) : NaN;
const MAX_S = m ? parseFloat(m[2]) : NaN;

test('play.playable_speed : la Genre Bible declare une bande jouable exploitable', () => {
  assert.ok(rule, 'regle genre.pong.playable_speed_range presente dans la Genre Bible');
  assert.ok(MIN_S > 0 && MAX_S > MIN_S, `bande lue coherente: [${MIN_S}, ${MAX_S}]`);
});

test('play.playable_speed : la vitesse de service EST dans la bande jouable', () => {
  const t = ballCrossingTimeSeconds();   // derive PUREMENT des constantes
  assert.ok(t >= MIN_S, `crossing ${t.toFixed(3)}s doit etre >= ${MIN_S}s (trop rapide sinon)`);
  assert.ok(t <= MAX_S, `crossing ${t.toFixed(3)}s doit etre <= ${MAX_S}s (trop lent sinon)`);
});

// NON-TAUTOLOGIE : la bande DISCRIMINE. L'ancienne vitesse (BALL_VX=3, playtest
// "~0.52 s, aucun temps de reaction") est HORS bande -> ce test l'aurait rejetee.
// Une bande qui accepte tout ne prouverait rien.
test('play.playable_speed : l ancienne vitesse (3) est HORS bande (la bande discrimine)', () => {
  const old = ballCrossingTimeSeconds(3, TICK_HZ);
  assert.ok(old < MIN_S, `ancienne vitesse crossing ${old.toFixed(3)}s doit etre < ${MIN_S}s (rejetee)`);
});

test('play.playable_speed : crossing = SERVE_CROSS_DIST / (BALL_VX * TICK_HZ) (pur)', () => {
  assert.equal(ballCrossingTimeSeconds(), SERVE_CROSS_DIST / (BALL_VX * TICK_HZ));
});
