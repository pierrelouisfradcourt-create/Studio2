// MODÈLE d'oracle de SOLVABILITÉ pour un jeu forgé (Forge / s9-build).
// Copie ce fichier dans GAMES/<jeu>/solvability.mjs et remplis les 3 TODO.
//
// POURQUOI : les tests de mécanique EN ISOLATION (« collectCoin marche SI on place
// le joueur sur la pièce ») peuvent être 100% verts alors que le jeu est INJOUABLE
// (objectifs inatteignables, niveau incomplétable). Prouvé 2× dans le studio. Cet
// oracle joue vraiment : il n'affirme SOLVABLE que si un bot ATTEINT la victoire.
//
// LE PATTERN EN 3 TEMPS (générique, à instancier par jeu) :
//   1. mesurer l'ENVELOPPE D'ACTION RÉELLE du moteur (pas de constante hardcodée) —
//      ex. hauteur de saut : on saute et on mesure. Interroge le moteur, ne suppose rien.
//   2. vérifier que chaque OBJECTIF REQUIS est DANS cette enveloppe (diagnostic clair
//      quand ça ne l'est pas : « pièce à 350px > portée saut 100px »).
//   3. faire JOUER un bot déterministe (balayage de politique) ; SOLVABLE ssi il GAGNE.
//
// Câble-le comme 3e volet de run-oracle.mjs (après logic tests + e2e). Exit 0 = SOLVABLE.
// claim_verdict: NO_CLAIM_ALLOWED — c'est un oracle mécanique, il ne juge pas le « fun ».

import { /* TODO: ta classe de jeu */ } from "./game.mjs";

const DT = 16; // ms/frame simulée (fixe = déterministe)

// --- (1) Enveloppe d'action réelle -------------------------------------------
// TODO : exécute l'action-clé du moteur et MESURE sa capacité (ne hardcode pas les
// constantes du jeu — mesure-les). Exemple runner/plateforme : la hauteur de saut.
function measureEnvelope(seed = 1) {
  // const g = new Game({ seed });
  // const groundY = g.player.y; g.jump();
  // let apexY = g.player.y;
  // for (let i = 0; i < 600; i++) { g.applyGravity(DT); apexY = Math.min(apexY, g.player.y); if (g.onGround && i > 0) break; }
  // return { groundY, apexY, reach: groundY - apexY };
  throw new Error("TODO measureEnvelope");
}

// --- (2) Objectifs requis dans l'enveloppe -----------------------------------
// TODO : retourne la liste des objectifs HORS d'atteinte (vide = tout atteignable).
// Un objectif = ce qu'il FAUT accomplir pour gagner (pièces à ramasser, sortie, cible).
function unreachableObjectives(env, seed = 1) {
  // const g = new Game({ seed });
  // return g.view().coinsOnLevel.filter(c => c.y < env.apexY - TOL)
  //   .map(c => ({ what: `pièce (${Math.round(c.x)},${Math.round(c.y)})`, need: Math.round(env.groundY - c.y), have: Math.round(env.reach) }));
  throw new Error("TODO unreachableObjectives");
}

// --- (3) Bot qui joue et doit GAGNER -----------------------------------------
// TODO : une politique paramétrée (ex. « saute à distance `p` de l'objectif ») ;
// on balaie `p` et on déclare SOLVABLE ssi une valeur gagne. Le bot doit être
// RAISONNABLE (viser l'objectif, éviter les pièges), sinon faux INJOUABLE.
function playWithPolicy(seed, p) {
  // const g = new Game({ seed });
  // for (let s = 0; s < 6000 && !g.over && !g.won; s++) { const input = decide(g.view(), p); g.step(DT, input); }
  // return { won: g.won, progress: /* métrique de progression */ 0, over: g.over };
  throw new Error("TODO playWithPolicy");
}

function searchWinningPlan(seed) {
  let best = { won: false, progress: -1 };
  for (let p = 0; p <= 320; p += 8) {           // TODO : plage de balayage selon ta politique
    const r = playWithPolicy(seed, p);
    if (r.progress > best.progress) best = { ...r, p };
    if (r.won) return { solvable: true, best: { ...r, p } };
  }
  return { solvable: false, best };
}

// --- Point d'entrée -----------------------------------------------------------
function main() {
  const seed = 1;
  const env = measureEnvelope(seed);
  const unreachable = unreachableObjectives(env, seed);
  const plan = searchWinningPlan(seed);

  console.log("=== ORACLE DE SOLVABILITÉ ===");
  console.log("enveloppe:", JSON.stringify(env));
  for (const u of unreachable) console.log(`   ✗ ${u.what} : besoin ${u.need} > capacité ${u.have}`);
  console.log(`plan gagnant : ${plan.solvable ? "TROUVÉ" : "AUCUN"} (meilleur: ${JSON.stringify(plan.best)})`);

  const ok = plan.solvable && unreachable.length === 0;
  console.log(`\nVERDICT SOLVABILITÉ : ${ok ? "SOLVABLE (un bot gagne)" : "INJOUABLE"}`);
  if (!ok) {
    console.log("RAISON : " +
      (unreachable.length ? `${unreachable.length} objectif(s) hors d'atteinte ; ` : "") +
      (!plan.solvable ? "aucune politique n'atteint la victoire." : ""));
  }
  process.exit(ok ? 0 : 1);
}

main();
