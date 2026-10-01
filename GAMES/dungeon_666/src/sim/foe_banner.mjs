// SOUTIEN — « Porte-étendard » (kind 'banner'). Données : tuning.enemies.banner (foe_data.mjs).
//
// Il n'attaque JAMAIS. Tant qu'il est debout (ni mort, ni étourdi), les autres ennemis à moins de
// `auraRadius` de lui ne prennent que `wardMult` des dégâts (foe_defense.wardOf, lu par
// combat.damageEnemy). L'aura se voit : alerte INOFFENSIVE permanente (e.tele harmless: true, de
// rayon auraRadius) ; elle disparaît dès qu'il est étourdi (enemies.mjs efface e.tele), et la
// protection avec elle.
//
// Un seul état, chase : il suit la mêlée à distance (keepDistance : se rapproche au-delà de
// preferredDist + approachSlack, recule sous fleeDist, sinon tourne lentement autour du héros).
// Contre-jeu : traverser la mêlée pour le tuer d'abord (dash), ou entraîner le combat hors de
// l'aura — il est lent. Aucun dégât de contact, aucun dégât du tout.

import { lineOfSight } from './physics.mjs';
import { setState, toPlayer, speedOf, keepDistance } from './ai_common.mjs';

function bannerAI(game, e, def) {
  const p = game.player;
  if (e.state !== 'chase') setState(e, 'chase');
  e.tele = { shape: 'circle', r: def.auraRadius, progress: 1, harmless: true };
  const tp = toPlayer(game, e);
  keepDistance(game, e, def, tp, lineOfSight(game.room, e.x, e.y, p.x, p.y), speedOf(game, e, def));
}

export const BANNER = { kind: 'banner', ai: bannerAI };
