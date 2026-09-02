# Contrat de jouabilité — jeux web forgés

Toute UI de jeu produite par la forge DOIT respecter ces conventions, pour qu'un
e2e générique puisse la piloter et que la garde `forge.static_oracles.check_e2e_harness`
la valide.

## Serveur
- `server.mjs` log `interface jouable` sur stdout quand le serveur est prêt à servir.

## État exposé (pilotable par l'e2e)
- `window.__game` : objet d'état lisible. Au minimum les scalaires pilotés par les
  règles (position joueur, compteur/score, `over: bool`, `level: number`).
- `window.__game_debug` : hooks de test déterministes. Au minimum de quoi FORCER une
  fin de partie sans dépendre du timing réel (ex. `hit()` → défaite).

## DOM
- `#overlay` : écran de fin de partie ; classe `hidden` quand caché.
- `#restart` : bouton rejouer (remet l'état à la partie initiale).

## Preuve e2e attendue (cf. games/collect_runner_legacy/e2e.mjs)
Le `e2e.mjs` lance un vrai navigateur (Playwright/chromium), envoie de vraies
touches/clics, observe `window.__game`, force une fin via `window.__game_debug`,
vérifie `#overlay` puis clique `#restart`, et finit par `RESULT: PASS` / `FAIL`.
Il est câblé dans `run-oracle.mjs` (exit 0 seulement si tout passe).
