// BUDGET TOTAL DE LA SOLVABILITE (GO Pierre 2026-08-17).
//
// DEFAUT MESURE. La preuve par MUTATION declare `budget.total_timeout_s` et ce champ est LU
// (`mutation_proof.py:707`, applique l.761) : un depassement produit `budget_exceeded`, un
// ARRET MOTIVE. Le budget de SOLVABILITE, lui, ne declare aucun total — `max_ticks`,
// `trials`, `trial_timeout_ms`, et rien qui borne l'ensemble. Face a cela l'appelant impose
// 300 s EN DUR (`oracle.py:76`, `driver.py:613`) sans jamais consulter ce que le jeu a
// declare. Leur rencontre se resout par une MORT DE PROCESSUS.
//
// Cas reel : bomberman_3d, run `proof4` — `--- TIMEOUT after 300s ---`, alors que la seule
// mesure aboutie etait verte (691 assertions, 0 echec). Depuis e48801c le driver rend
// BLOCKED et non plus FAIL : la panne ne ment plus, mais elle reste une mort brutale sans
// resultat partiel. Ce lot lui donne un arret MOTIVE, decide par le budget du jeu.
//
// LE DEFAUT N'EST PAS « la limite est trop courte » : c'est qu'un budget declare et une
// limite imposee coexistent sans se parler. On ne touche donc PAS aux 300 s ici — on donne
// au jeu le moyen de s'arreter AVANT, proprement.
//
// BLOCKED ET JAMAIS FAIL : un budget epuise est une preuve IMPOSSIBLE, pas une preuve
// NEGATIVE (regle ratifiee 2026-08-17, corollaire « preuve impossible != FAIL »). La
// fonction rend deja BLOCKED motive pour ses autres impossibilites (trials <= 0, exception
// d'essai) — ce lot rejoint ce vocabulaire, il n'en cree pas.
//
// HORLOGE INJECTABLE : meme patron que `mutation_proof.now_fn` (l.671). Sans injection, un
// test du depassement dependrait du temps reel — donc du poste, donc de rien.
import assert from 'node:assert/strict';
import test from 'node:test';

import { runSolvability, cfgFromArgv } from './solvability_godot.mjs';
import { resolveSolvabilityConfig, buildSolvabilityArgv } from './godot_oracle.mjs';
import { writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

/** Horloge deterministe : avance de `pas` ms a chaque appel. */
function horloge(pas) {
  let t = 0;
  return () => { const v = t; t += pas; return v; };
}

const gagne = () => ({ succeeded: true, ticks: 10 });

test('SANS total_timeout_s : comportement STRICTEMENT inchange', () => {
  // Retrocompatibilite : aucun jeu ne declare ce champ aujourd'hui. Tous doivent garder
  // exactement leur comportement actuel.
  const r = runSolvability({ trials: 3 }, gagne, horloge(10_000));
  assert.equal(r.verdict, 'OK');
  assert.equal(r.won, 3);
  assert.equal(r.reason, undefined);
});

test('budget EPUISE : BLOCKED motive, JAMAIS FAIL', () => {
  // LE CAS QUI FALSIFIE. 2 s de budget, des essais de 10 s : le 2e essai ne doit pas partir.
  const r = runSolvability({ trials: 50, total_timeout_s: 2 }, gagne, horloge(10_000));
  assert.equal(r.verdict, 'BLOCKED', 'un budget epuise n est pas une preuve negative');
  assert.match(r.reason, /budget/i);
});

test('le resultat PARTIEL est conserve, jamais jete', () => {
  // Un arret motive doit dire ce qui a ete mesure AVANT : c'est toute la difference avec
  // une mort de processus, qui ne rend rien.
  const r = runSolvability({ trials: 50, total_timeout_s: 25 }, gagne, horloge(10_000));
  assert.ok(r.won > 0, 'les essais deja gagnes doivent survivre a l arret');
  assert.equal(r.won + r.lost, r.trials_executes);
  assert.ok(r.trials_executes < 50, 'l arret doit avoir eu lieu avant la fin');
  assert.equal(r.trials, 50, 'le budget DECLARE reste visible a cote du realise');
});

test('un budget SUFFISANT laisse le verdict normal se rendre', () => {
  // Contre-epreuve : le garde-fou ne doit pas bloquer ce qui tient dans son budget.
  const r = runSolvability({ trials: 3, total_timeout_s: 3600 }, gagne, horloge(10_000));
  assert.equal(r.verdict, 'OK');
  assert.equal(r.won, 3);
});

test('un budget epuise n efface pas un ECHEC deja mesure', () => {
  // Si des essais ont DEJA echoue, le BLOCKED ne doit pas les blanchir : ils restent
  // visibles dans `failed_seeds`. « Non mesure » ne recouvre pas « mesure et rouge ».
  const perd = () => ({ succeeded: false, ticks: 1 });
  const r = runSolvability({ trials: 50, total_timeout_s: 25 }, perd, horloge(10_000));
  assert.equal(r.verdict, 'BLOCKED');
  assert.ok(r.failed_seeds.length > 0, 'les echecs mesures restent visibles');
});

test('total_timeout_s invalide est IGNORE, jamais interprete', () => {
  // Une valeur absurde ne doit ni bloquer ni etre prise pour zero — meme discipline que
  // `Number.isFinite` dans `resolveSolvabilityConfig`.
  for (const mauvais of [0, -5, 'beaucoup', null, NaN]) {
    const r = runSolvability({ trials: 2, total_timeout_s: mauvais }, gagne, horloge(10_000));
    assert.equal(r.verdict, 'OK', `total_timeout_s=${String(mauvais)} ne doit rien bloquer`);
  }
});

test('resolveSolvabilityConfig REMONTE le champ depuis oracles.json', () => {
  // Cablage : un champ que le resolveur ne lit pas n arriverait jamais a la boucle.
  const d = join(tmpdir(), `solvbudget_${process.pid}`);
  mkdirSync(d, { recursive: true });
  const cfg = join(d, 'oracles.json');
  writeFileSync(cfg, JSON.stringify({ j: { solvability: { trials: 7, total_timeout_s: 42 } } }));
  const r = resolveSolvabilityConfig('GAMES/j', cfg);
  assert.equal(r.totalTimeoutS, 42);
  assert.equal(r.trials, 7);
});

test('resolveSolvabilityConfig : champ ABSENT => null, jamais une valeur inventee', () => {
  const d = join(tmpdir(), `solvbudget2_${process.pid}`);
  mkdirSync(d, { recursive: true });
  const cfg = join(d, 'oracles.json');
  writeFileSync(cfg, JSON.stringify({ j: { solvability: { trials: 7 } } }));
  assert.equal(resolveSolvabilityConfig('GAMES/j', cfg).totalTimeoutS, null);
});

// --- LE PONT CLI : c'est ici que le premier jet etait INERTE -------------------------
//
// Defaut mesure avant ces tests : `totalTimeoutS` etait bien resolu depuis `oracles.json`
// et bien lu par `runSolvability` — mais `godot_oracle.mjs` ne le DESTRUCTURAIT pas et ne le
// PASSAIT pas au sous-processus. Les 8 tests ci-dessus etaient VERTS et le mecanisme ne
// pouvait pas s'armer en production : « producteur sans consommateur », avec des tests
// unitaires pour le garantir. Les deux extremites sont donc pures et confrontees ici.

test('PONT : le budget SURVIT a l aller-retour argv', () => {
  const cfg = { trials: 20, seedStart: 1, maxTicks: 12000, trialTimeoutMs: 60000,
                totalTimeoutS: 240 };
  const argv = buildSolvabilityArgv('/s.mjs', 'GAMES/j', cfg);
  // argv[0] est le script node lui-meme : l'aval lit a partir du projet.
  const relu = cfgFromArgv(argv.slice(1));
  assert.equal(relu.total_timeout_s, 240, 'le budget doit traverser les deux processus');
  assert.equal(relu.trials, 20);
  assert.equal(relu.maxTicks, 12000);
});

test('PONT : sans budget declare, la 7e position est OMISE et l aval reste inchange', () => {
  const cfg = { trials: 50, seedStart: 1, maxTicks: 200, trialTimeoutMs: 10000,
                totalTimeoutS: null };
  const argv = buildSolvabilityArgv('/s.mjs', 'GAMES/j', cfg);
  assert.equal(argv.length, 7, 'aucun argument surnumeraire quand rien n est declare');
  const relu = cfgFromArgv(argv.slice(1));
  assert.equal(relu.total_timeout_s, undefined);
});

test('PONT : le budget traverse jusqu au COMPORTEMENT, pas seulement jusqu au champ', () => {
  // Bout en bout logique : resolveur -> argv -> cfg -> boucle. Un champ transmis mais
  // inoperant serait un cablage en trompe-l oeil.
  const d = join(tmpdir(), `solvbudget3_${process.pid}`);
  mkdirSync(d, { recursive: true });
  const cfgPath = join(d, 'oracles.json');
  writeFileSync(cfgPath, JSON.stringify(
    { j: { solvability: { trials: 50, total_timeout_s: 2 } } }));
  const resolu = resolveSolvabilityConfig('GAMES/j', cfgPath);
  const relu = cfgFromArgv(buildSolvabilityArgv('/s.mjs', 'GAMES/j', resolu).slice(1));
  const r = runSolvability({ trials: relu.trials, total_timeout_s: relu.total_timeout_s },
                           gagne, horloge(10_000));
  assert.equal(r.verdict, 'BLOCKED', 'le budget declare doit REELLEMENT arreter la boucle');
  assert.match(r.reason, /budget/i);
});
