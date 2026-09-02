// Scenario du role role-grid-navigator. Delegue a Godot headless via l adaptateur :
// le contrat de role reste moteur-agnostique, le couplage vit ICI (spec etape 0 §4).
// Substituabilite certifiee : un futur backend fournira son propre scenario, mesure
// avec LA MEME simulation_config et LES MEMES seeds. Si la bande retombe dans la
// bande declaree, la substitution est PROUVEE, pas affirmee.
export { runTrial } from '../adapters/godot_trial.mjs';
