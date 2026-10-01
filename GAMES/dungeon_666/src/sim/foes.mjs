// Registre des archétypes d'ennemis AJOUTÉS hors de enemies.mjs (un fichier par archétype :
// src/sim/foe_<archétype>.mjs — src/sim reste À PLAT, un test protégé lit ce dossier sans récursion).
// Chaque entrée : { kind, ai(game, e, def, dt), melee?: bool, shooter?: bool }.
// Les données (PV, vitesses, télégraphes…) vivent dans tuning.enemies[kind] (config.mjs).

export const EXTRA_FOES = [];
