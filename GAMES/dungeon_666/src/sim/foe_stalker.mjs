// EMBUSCADE — « Traqueur » (kind 'stalker'). Données : tuning.enemies.stalker (foe_data.mjs).
//
// Machine d'états :
//   chase   — rôde à distance (keepDistance) ; quand sa recharge est finie, que le héros est à
//             moins de `stalkRange` et qu'un jeton de mêlée est libre, il se dissout.
//   fade    — immobile, il se dissout (`fade` s) : encore visible et VULNÉRABLE. Le tuer ou
//             l'étourdir ici annule l'embuscade.
//   ambush  — disparu `hiddenTime` s : e.hidden = true et e.spawnT > 0 (comme une apparition en
//             attente : ni ciblable, ni touchable, son IA ne tourne pas). À la première image où il
//             revient, il se pose DANS LE DOS du héros (à `backDist`, à l'opposé de player.facing ;
//             si le point est dans un mur, on essaie les écarts `backAngles`), et sa frappe est
//             télégraphiée : cercle rouge de `slashRadius` autour de lui pendant `slashWindup` s.
//   windup  — il tient la pose pendant le télégraphe (zone liée à lui : le tuer ou l'étourdir
//             l'annule, projectiles.mjs), puis la zone frappe.
//   recover — longue récupération (fenêtre de punition), puis recharge et retour en chase.
// Il garde son jeton de mêlée de la dissolution à la frappe (ai_common.activeAttackers).
// Aucun dégât de contact : seul le cercle télégraphié blesse.

import * as TRIG from '../core/trig.mjs'; // sinus, cosinus… déterministes : jamais Math.sin & co dans la simulation
import { randRange } from '../core/rng.mjs';
import { lineOfSight, pointBlocked } from './physics.mjs';
import { spawnHazard } from './combat.mjs';
import { emit, setState, toPlayer, speedOf, windupOf, activeAttackers, keepDistance } from './ai_common.mjs';

const CLEARANCE = 2; // u libres autour du corps au point de réapparition

/** Point de réapparition : dans le dos du héros ; à défaut de place, sur son flanc ; sinon sur place. */
export function ambushPoint(game, e, def) {
  const p = game.player;
  for (const off of def.backAngles) {
    const a = p.facing + Math.PI + off;
    const x = p.x + TRIG.cos(a) * def.backDist;
    const y = p.y + TRIG.sin(a) * def.backDist;
    if (!pointBlocked(game.room, x, y, e.r + CLEARANCE)) return { x, y };
  }
  return { x: e.x, y: e.y };
}

/** Il resurgit et arme sa frappe : cercle rouge télégraphié autour de lui. */
function reappear(game, e, def) {
  const pt = ambushPoint(game, e, def);
  e.x = pt.x;
  e.y = pt.y;
  e.kvx = 0;
  e.kvy = 0;
  e.hidden = false;
  setState(e, 'windup');
  spawnHazard(game, {
    shape: 'circle', x: e.x, y: e.y, r: def.slashRadius * (e.eliteMod ? game.tuning.elite.sizeMult : 1),
    delay: windupOf(game, e, def.slashWindup), damage: def.damage * e.dmgScale, kind: 'stalker', sourceId: e.id,
  });
  emit(game, 'enemyAttack', { id: e.id, x: e.x, y: e.y, enemy: e.kind });
}

function stalkerAI(game, e, def) {
  const p = game.player;
  switch (e.state) {
    case 'chase': {
      const tp = toPlayer(game, e);
      if (e.cooldown <= 0 && tp.d < def.stalkRange && activeAttackers(game) < game.tuning.combat.maxAttackers) {
        setState(e, 'fade');
        break;
      }
      keepDistance(game, e, def, tp, lineOfSight(game.room, e.x, e.y, p.x, p.y), speedOf(game, e, def));
      break;
    }
    case 'fade':
      if (e.stateTime >= def.fade) {
        setState(e, 'ambush');
        e.hidden = true;
        e.spawnT = def.hiddenTime; // disparu : enemies.mjs ne relance son IA qu'à son retour
      }
      break;
    case 'ambush':
      reappear(game, e, def);
      break;
    case 'windup':
      if (e.stateTime >= windupOf(game, e, def.slashWindup)) setState(e, 'recover');
      break;
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

export const STALKER = { kind: 'stalker', ai: stalkerAI, melee: true };
