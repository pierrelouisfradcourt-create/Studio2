// Registre des MODÈLES de Gardien ajoutés (un fichier par modèle : src/sim/boss_<modèle>.mjs).
// Chaque modèle : { byPhase: {1: [...], 2: [...], 3: [...]}, patterns: {nom: fn(game, e, d, dt, speed)},
// rest?(game, e, d, dt, speed), tick?(game, e, d, dt), available?(game, e, d, nom) }.
// La clé = kind de l'ennemi = clé de tuning.boss (boss_data.mjs).

import { CERBERE } from './boss_cerbere.mjs';
import { MINOS } from './boss_minos.mjs';
import { COLOSSE } from './boss_colosse.mjs';

export const EXTRA_BOSS_MODELS = {
  cerbere: CERBERE,
  minos: MINOS,
  colosse: COLOSSE,
};
