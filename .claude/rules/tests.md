---
path: "**/tests/**"
---
SURFACES DE TEST PROTÉGÉES — régime ratifié Pierre 2026-09-04.

La liste fait foi dans `forge/test_surfaces.yaml`, jamais ici : `forge/tests/**`,
`GAMES/*/tests/**`, `GAMES/*/07_TESTS/**`. Le `tests/` racine visé jusqu'ici n'existe pas
en V2 — mesuré, 0 fichier.

RÉGIME `create_allowed_modify_denied` :
- CRÉER un test est PERMIS. C'est un livrable normal — le builder Forge produit
  `logic.test.mjs`, et l'oracle Godot exige `GAMES/<jeu>/tests/run_tests.gd`.
- MODIFIER un test qui préexiste à ta passe est INTERDIT sans gate Pierre explicite.
  Le geste visé est « rendre vert en réécrivant l'oracle », jamais l'écriture d'un test.

APPLICATION, dite franchement : les étapes Forge sont bornées mécaniquement
(`run_real._STEP_DISALLOWED`, dérivé de la déclaration). Les sessions et sous-agents ne le
sont PAS — décision Pierre 2026-09-04. Cette règle est donc, pour eux, une consigne sur
l'honneur dont le seul témoin est l'empreinte `forge.reference_guard`, qui détecte sans
bloquer.

LIMITE DE CE FICHIER : le scope `path:` ci-dessus ne couvre pas la convention `07_TESTS/`.
La déclaration reste la source, ce scope n'est qu'un déclencheur d'affichage.
