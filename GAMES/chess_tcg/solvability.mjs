#!/usr/bin/env node
// Oracle de SOLVABILITÉ — un bot JOUE et doit GAGNER réellement, avec les seules actions
// qu'un joueur a sous la main (cartes, déplacements, attaques, capacités).
//
// Deux volets, tous deux bloquants :
//   (a) objectif atteignable : le bot (J1) contre un adversaire PASSIF (qui ne fait que passer
//       son tour, mais dont la tour tire et dont la fatigue s'applique) doit gagner 100 % des
//       seeds, en moins de MAX_PLIES demi-tours ;
//   (b) pas d'impasse : bot contre bot, la partie se termine TOUJOURS avec un vainqueur.
//       Le taux de victoire de J1 est rapporté comme MESURE (l'avantage du trait), pas jugé.
//
// Usage : node solvability.mjs [max_plies] [nb_essais]

import { Engine, STATE_WON } from './engine.mjs';
import { playTurn } from './ai.mjs';

const MAX_PLIES = Number.parseInt(process.argv[2] ?? '200', 10);
const TRIALS = Number.parseInt(process.argv[3] ?? '12', 10);

function passiveTurn(engine, me) {
  const res = engine.apply({ type: 'end' });
  if (!res.ok) throw new Error(`fin de tour refusée pour J${me + 1} : ${res.error}`);
}

function playGame(seed, turnFor) {
  const engine = new Engine({ seed });
  let plies = 0;
  while (!engine.over && plies < MAX_PLIES) {
    turnFor[engine.current](engine, engine.current);
    plies++;
  }
  return {
    seed,
    map: engine.mapName,
    plies,
    state: engine.state,
    winner: engine.winner,
    towers: engine.towers.map((t) => t.hp),
    won: engine.state === STATE_WON,
    over: engine.over,
  };
}

function summarize(label, trials, predicate) {
  const passes = trials.filter(predicate).length;
  const worst = trials.reduce((m, t) => Math.max(m, t.plies), 0);
  const receipt = {
    label,
    passes,
    total_trials: trials.length,
    pass_rate: Number(((passes / trials.length) * 100).toFixed(1)),
    worst_plies: worst,
    max_plies: MAX_PLIES,
  };
  console.log(`FORGE_ORACLE solvability ${JSON.stringify(receipt, null, 2)}`);
  for (const t of trials) {
    console.log(`  seed=${t.seed} map="${t.map}" state=${t.state} winner=${t.winner === null ? '-' : `J${t.winner + 1}`} plies=${t.plies} tours=${t.towers.join('/')}`);
  }
  return passes === trials.length;
}

function main() {
  const seeds = Array.from({ length: TRIALS }, (_, i) => i + 1);

  console.log('(a) bot J1 contre adversaire passif — doit gagner 100 %');
  const vsPassive = seeds.map((seed) => playGame(seed, [playTurn, passiveTurn]));
  const aOk = summarize('bot_vs_passive', vsPassive, (t) => t.won);

  console.log('\n(b) bot contre bot — doit toujours se terminer avec un vainqueur');
  const vsBot = seeds.map((seed) => playGame(seed, [playTurn, playTurn]));
  const bOk = summarize('bot_vs_bot_terminates', vsBot, (t) => t.over);
  const p1Wins = vsBot.filter((t) => t.winner === 0).length;
  console.log(`  MESURE (non bloquante) : J1 gagne ${p1Wins}/${vsBot.length} parties bot contre bot`);

  if (aOk && bOk) {
    console.log('SOLVABILITY: PASS');
    process.exit(0);
  }
  console.error('SOLVABILITY: FAIL');
  process.exit(1);
}

main();
