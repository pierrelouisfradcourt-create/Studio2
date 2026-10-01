// MOTEUR DES GARDIENS (boss de fin de section, tous les 18 étages).
// Commun à tous les modèles : trois phases (seuils de PV en tuning), transitions invulnérables
// (projectiles effacés, renforts, orbe de soin), repos entre deux patterns (fenêtre de
// punition), patterns jamais répétés deux fois de suite, télégraphes JAMAIS raccourcis.
// Chaque modèle (src/sim/boss_<modèle>.mjs) fournit ses patterns et leur ordre par phase.

import { randRange, pick } from '../core/rng.mjs';
import { emit } from './state.mjs';
import { spawnPickup } from './combat.mjs';
import { queueSpawn, findSpawnPoint } from './spawns.mjs';
import { bossDef, toPlayer, setState } from './boss_common.mjs';
import { CHARON } from './boss_charon.mjs';
import { EXTRA_BOSS_MODELS } from './boss_models.mjs';

// Registre des modèles de Gardien : { byPhase: {1: [...], 2: [...], 3: [...]}, patterns: {nom: fn},
// rest?(game, e, d, dt, speed), tick?(game, e, d, dt), available?(game, e, d, nom) }.
// La clé est le `kind` de l'ennemi (= clé de tuning.boss).
//   tick      — appelé à chaque pas, quel que soit le pattern (zones persistantes, bouclier) ;
//   available — filtre les patterns utilisables maintenant (ex. pas de nouveaux renforts tant que
//               les précédents vivent). Un modèle sans ces crochets (Charon) n'en voit aucun effet.
export const BOSS_MODELS = {
  gardien: CHARON,
  ...EXTRA_BOSS_MODELS,
};

function modelOf(e) {
  return BOSS_MODELS[e.kind] ?? CHARON;
}

function nextPattern(game, e) {
  const model = modelOf(e);
  let list = model.byPhase[e.phase];
  if (model.available) {
    const d = bossDef(game, e);
    const usable = list.filter((name) => model.available(game, e, d, name));
    if (usable.length) list = usable;
  }
  let choice = pick(game.rng.ai, list);
  // Jamais deux fois de suite le même pattern.
  for (let i = 0; i < 4 && choice === e.pattern; i++) choice = pick(game.rng.ai, list);
  e.pattern = choice;
  e.secondCharge = false;
  setState(e, choice);
}

/** Changement de phase : invulnérable un instant, projectiles effacés, renforts, orbe de soin. */
function enterPhase(game, e, d) {
  e.phase++;
  e.tele = null;
  e.invuln = d.transition;
  for (const pr of game.projectiles) if (pr.owner === 'enemy') pr.dead = true;
  for (const h of game.hazards) if (h.hitsPlayer) h.done = true;
  for (const kind of d.reinforcements[e.phase] ?? []) {
    const pt = findSpawnPoint(game, 14, 180, { x: e.x, y: e.y, minR: e.r + 60, maxR: e.r + 260 });
    if (pt) queueSpawn(game, kind, pt.x, pt.y, { summoned: true });
  }
  spawnPickup(game, 'heal', e.x, e.y + e.r + 30, d.phaseHealOrb);
  emit(game, 'bossPhase', { id: e.id, x: e.x, y: e.y, phase: e.phase });
  setState(e, 'roar');
  e.restFor = d.transition;
}

export function updateBoss(game, e, dt) {
  const d = bossDef(game, e);
  const model = modelOf(e);
  e.invuln = Math.max(0, (e.invuln ?? 0) - dt);
  if (model.tick) model.tick(game, e, d, dt);
  const threshold = e.phase === 1 ? d.phase2At : e.phase === 2 ? d.phase3At : -1;
  if (threshold > 0 && e.hp <= e.maxHp * threshold) {
    enterPhase(game, e, d);
    return;
  }
  const speed = d.speed * d.speedMultByPhase[e.phase - 1];
  switch (e.state) {
    case 'roar':
      if (e.stateTime >= e.restFor) {
        e.restFor = undefined;
        nextPattern(game, e);
      }
      break;
    case 'chase':
    case 'rest': {
      if (e.restFor === undefined) e.restFor = randRange(game.rng.ai, d.restBetween[0], d.restBetween[1]) * d.restMultByPhase[e.phase - 1];
      if (model.rest) model.rest(game, e, d, dt, speed);
      else {
        const tp = toPlayer(game, e);
        if (tp.d > 160) {
          e.vx = tp.dx * speed;
          e.vy = tp.dy * speed;
        }
      }
      if (e.stateTime >= e.restFor) {
        e.restFor = undefined;
        nextPattern(game, e);
      }
      break;
    }
    case 'stunned':
      break;
    default: {
      const fn = model.patterns[e.state];
      if (fn) fn(game, e, d, dt, speed);
      else setState(e, 'rest');
    }
  }
}
