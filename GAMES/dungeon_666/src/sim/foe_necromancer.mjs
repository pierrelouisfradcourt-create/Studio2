// INVOCATEUR — « Nécromancien » (kind 'necromancer'). Données : tuning.enemies.necromancer
// (foe_data.mjs).
//
// Machine d'états :
//   chase   — garde ses distances et FUIT le héros (plus vite quand il est talonné) ; canalise
//             quand le héros est assez loin et qu'il reste de la place sous le plafond
//             d'invocations de la salle (ai_common.summonRoom).
//   channel — immobile, alerte violette INOFFENSIVE autour de lui (e.tele harmless: true) ;
//             à la fin, ouvre des cercles d'invocation (queueSpawn) d'où sortent des diablotins
//             (invocations : ni or ni Âmes). Le tuer ou l'étourdir pendant la canalisation
//             l'annule : aucun cercle ne s'ouvre.
//   recover — souffle, puis repart (temps de recharge).
// Il n'attaque jamais lui-même : peu de PV, cible prioritaire. Aucun dégât de contact.

import { randRange } from '../core/rng.mjs';
import { lineOfSight } from './physics.mjs';
import { emit, setState, toPlayer, speedOf, windupOf, keepDistance, summonRoom, summonAround } from './ai_common.mjs';

function necromancerAI(game, e, def) {
  const p = game.player;
  const tp = toPlayer(game, e);
  switch (e.state) {
    case 'chase': {
      if (e.cooldown <= 0 && tp.d > def.fleeDist && summonRoom(game) > 0) {
        setState(e, 'channel');
        e.tele = { shape: 'circle', r: def.channelRadius, progress: 0, harmless: true }; // visible dès la 1re image
        emit(game, 'enemyAttack', { id: e.id, x: e.x, y: e.y, enemy: e.kind });
        break;
      }
      const sees = lineOfSight(game.room, e.x, e.y, p.x, p.y);
      const flee = tp.d < def.fleeDist ? def.fleeSpeedMult : 1;
      keepDistance(game, e, def, tp, sees, speedOf(game, e, def) * flee);
      break;
    }
    case 'channel': {
      const ch = windupOf(game, e, def.channel);
      e.tele = { shape: 'circle', r: def.channelRadius, progress: e.stateTime / ch, harmless: true };
      if (e.stateTime >= ch) {
        e.tele = null;
        const n = Math.min(def.count, summonRoom(game));
        summonAround(game, e, def.minionKind, n, def.summonMinR, def.summonMaxR, def.summonMinPlayerDist);
        setState(e, 'recover');
      }
      break;
    }
    case 'recover':
      if (e.stateTime >= def.recover) {
        setState(e, 'chase');
        e.cooldown = def.cooldown * randRange(game.rng.ai, def.cooldownJitter[0], def.cooldownJitter[1]);
      }
      break;
    default:
      setState(e, 'chase');
  }
}

export const NECROMANCER = { kind: 'necromancer', ai: necromancerAI };
