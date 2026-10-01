// Registre du DESSIN des archétypes d'ennemis et des Gardiens ajoutés (un module par famille :
// art_foes.mjs, art_bosses.mjs). Signature : (ctx, r, face, body, e, time), contexte déjà centré
// sur l'ennemi et tourné/écrasé comme les autres. Couleurs de corps : EXTRA_BODY[kind].

import { FOE_ART, FOE_BODY } from './art_foes.mjs';
import { BOSS_ART, BOSS_BODY } from './art_bosses.mjs';

export const EXTRA_ART = { ...FOE_ART, ...BOSS_ART };
export const EXTRA_BODY = { ...FOE_BODY, ...BOSS_BODY };
