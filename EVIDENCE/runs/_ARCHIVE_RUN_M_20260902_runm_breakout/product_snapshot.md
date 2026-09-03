I have everything I need. Confirmed state of the run directory:
- **Present**: `charter.yaml`, `worldscan.json` (games[0]=Breakout, games[1]=Arkanoid), `artifacts/s2-worldscan.txt`
- **Absent**: `gm_worldscan.json`, `story_bible.json`, `design/progression_contract.md`, `design/calibration.md`

I've read both gating oracles (`check_prisme_manifest.mjs` + `upstream_schema.mjs` for the structured artifact; `check_prisme.mjs` for the markdown panel form). My response below **is** `product_snapshot.md` (the executor materializes everything outside the terminal JSON block), followed by the terminal `prisme.json` block and the RETURN_REASON line.

---

> **Prisme Produit — runm_breakout** · run `runm-breakout-20260902` · vue réalisateur du produit FINI.
> Ancres amont présentes : `charter.yaml`, `worldscan.json` (Breakout 1976 = `games[0]`, Arkanoid 1986 = `games[1]`).
> Ancres amont ABSENTES du run_dir, signalées et NON compensées : `gm_worldscan.json` (s2.7), `story_bible.json` (s2.6), `design/progression_contract.md`, `design/calibration.md`. Profil non-narratif, cible web minimale : le World Scan est ici la seule source d'exigences EXPECTED, complétée par mes ADDITIONS charter.

## 1. CE QUE LE JOUEUR VOIT

Dans la fenêtre du navigateur, une **aire de jeu bornée** occupe l'écran. En haut, une **grille de briques** rangées et colorées, serrées les unes contre les autres. En bas, une barre horizontale — le **paddle** — que le joueur reconnaît immédiatement comme « à lui ». Entre les deux, une **balle** unique en mouvement. Un **HUD** léger affiche en permanence trois choses lisibles d'un coup d'œil : l'**objectif** (« détruire toutes les briques »), un **compteur** (score et/ou vies) et le **nombre de briques restantes**. Chaque brique touchée **disparaît** de l'écran. Quand la dernière brique tombe, un **message de VICTOIRE** s'affiche et l'action se fige. Quand la balle est perdue une fois de trop, un **message de DÉFAITE (game over)** s'affiche à la place. Aucun menu de progression, aucun niveau au-delà du tableau en cours : ce que le joueur voit est exactement ce qui est jouable.

## 2. CE QUE LE JOUEUR FAIT

Le joueur a **une seule entrée** : déplacer le paddle horizontalement avec les **flèches gauche/droite** du clavier. Tout le reste découle de ce geste. Il **positionne** le paddle sous la balle qui descend, **choisit le point d'impact** (bord pour un angle prononcé, centre pour un renvoi vertical) et **renvoie** la balle vers les briques. Il **répète** ce cycle viser → renvoyer → casser une brique, aller-retour après aller-retour, en gardant la balle en jeu. Il **poursuit** jusqu'à l'une des deux fins qu'il provoque lui-même : vider entièrement la grille (victoire) ou épuiser ses vies en laissant passer la balle (défaite). Il n'achète rien, ne débloque rien, ne choisit aucune branche : le seul levier d'habileté est la **précision du placement du paddle** dans le temps imparti par la balle.

## 3. CE QUE LE JOUEUR RESSENT

Dès la première brique, une **récompense immédiate** : la brique disparaît et le compteur bouge, sans latence perçue — le geste a une conséquence visible instantanée. S'installe un **sentiment de contrôle et de précision** : le joueur comprend vite que l'angle dépend de lui, pas du hasard. À mesure que la grille se vide, monte une **tension propre** : il reste peu de briques, mais chaque balle perdue coûte cher, et l'attention se resserre sur le rebond. La partie offre une **clôture nette** : gagné ou perdu, l'écran le dit franchement, sans ambiguïté ni fin molle. La satisfaction est celle d'une **boucle d'adresse courte et honnête** ; le produit n'invente ni méta-progression ni prestige, et ne prétend pas en offrir.

## 4. RÈGLES OBSERVABLES

- **R1** — Au lancement, le HUD affiche l'objectif « détruire toutes les briques » et un compteur de briques restantes strictement supérieur à zéro.
- **R2** — Le joueur déplace le paddle horizontalement en maintenant les flèches gauche/droite ; la position affichée du paddle change tant qu'une touche est maintenue.
- **R3** — Quand la balle touche le paddle, l'angle de rebond dépend du point d'impact : deux impacts à des endroits différents du paddle produisent deux angles de sortie mesurablement distincts.
- **R4** — Au contact de la balle, la brique touchée disparaît de l'écran et le score affiché augmente dans la même frame.
- **R5** — Tant que la balle est en jeu, le cycle déplacer-le-paddle → renvoyer → détruire une brique se rejoue à chaque aller-retour de la balle, et le nombre de briques restantes décroît.
- **R6** — La balle rebondit sur les trois bords de l'aire (gauche, droite, haut) en conservant sa vitesse ; elle ne sort de l'aire que par le bas, sous le paddle.
- **R7** — Quand la dernière brique est détruite, un message de VICTOIRE s'affiche et la balle s'immobilise.
- **R8** — Quand la balle passe sous le paddle et qu'il ne reste plus de vie, un message de DÉFAITE (game over) s'affiche et la partie s'arrête.
- **R9** — Un compteur observable (score ou vies) est affiché et sa valeur diffère visiblement de sa valeur de départ après quelques briques détruites ou une vie perdue.
- **R10** — Le paddle réagit à l'appui clavier au plus à la frame suivante (aucun lag perçu à 60 fps).
- **R11** — Le jeu se charge et s'exécute dans un navigateur récent sans erreur console de niveau bloquant, et sa boucle de rendu tourne.
- **R12** — La balle, le paddle et au moins une rangée de briques sont rendus visiblement et distinctement dans l'aire de jeu dès le lancement.

## 5. RAPPORT FINAL

**Ancre / charter** : le charter (`objectif`, `criteres_succes`, `criteres_demo`) impose un casse-briques web minimal RÉELLEMENT jouable, avec victoire ET défaite atteignables et affichées, compteur observable, rendu visible — toutes les règles ci-dessus s'y raccordent, complétées par les boucles/objectifs de `worldscan.json:games[0]` (Breakout).

**why_task_existed** :
- `problem:` non transmis par l'amont ; activation par dispatch humain (marqueur `FORGE_DISPATCH:s1-prisme:runm-breakout-20260902:1`) — construire l'artefact d'exigences produit pour la migration V1→V2 du casse-briques.
- `oracle:` aucun (activation par décision de dispatch, pas par mesure rouge).
- `root_cause:` non établie (tâche de production initiale, pas de correction).
- `action_reason:` produire `product_snapshot.md` + `prisme.json` conformes pour ouvrir la chaîne aval (s3→s9).

**result:** deux sorties produites — le présent `product_snapshot.md` (4 sections + 12 règles observables numérotées) et le bloc `prisme.json` terminal (12 exigences : 10 EXPECTED ancrées `worldscan:games[0]`, 2 ADDITIONS `reference:null` ; 5 exigences de boucle PLAYER_GOAL/PLAYER_ACTION/GAME_RESPONSE/REWARD/REPEAT, 7 exigences produit NONE ; toutes actionnables : `expected_proof` + `destination` valides).

**proof:** oracles déclarés = `node forge/check_prisme_manifest.mjs EVIDENCE/runs/runm_breakout/prisme.json --worldscan EVIDENCE/runs/runm_breakout/worldscan.json` et `node forge/prisme/check_prisme.mjs <product_snapshot.md>`. **NON EXÉCUTÉS** dans cet environnement (shell indisponible pour cet agent). Conformité vérifiée statiquement contre le code des oracles (`upstream_schema.mjs::validateChaine/validateProvenance/validateExpectedProof`, `DESTINATIONS`, `referenceAncree`, et `check_prisme.mjs` REQUIRED_SECTIONS/RULE_PATTERN) — mais un contrôle statique n'est pas un reçu d'exécution.

**learning:** le gabarit de boucle V4 (maillons DECISION, UNLOCK/`appears`, NEXT_GOAL×2 `new_distinct`, META_LOOP/prestige `resets`, ADVANTAGE `increases_more_than`) est calibré sur le genre idle/clicker (Kitten Clicker) ; il ne se projette pas sur une boucle d'adresse arcade (Breakout) sans fabriquer des mécaniques de prestige que le charter exclut. La boucle produite est complète POUR SON GENRE (goal→action→réponse→récompense→répétition), incomplète au sens du gabarit V4. Réutilisable : un run inter-genres doit soit relâcher les maillons clicker-spécifiques, soit router vers un gabarit de boucle par genre.

**next_reason:** l'exécuteur DOIT lancer les deux oracles nommés sur les artefacts matérialisés (je n'ai pas pu les exécuter) et arbitrer, en HumanGate, la friction gabarit-V4/genre ci-dessus avant que `loop_spec.mjs` ne projette une boucle jugée incomplète. Sans cet arbitrage humain, une cause non résolue persiste — la chaîne causale n'est PAS fermée ici.

**Verdicts (règle de restitution)** :
- `software_verdict:` BLOCKED — les oracles n'ont pas pu être exécutés (shell indisponible), aucun reçu mécanique produit.
- `claim_verdict:` NO_CLAIM_ALLOWED — je ne certifie pas que l'artefact PASSE ; je l'ai conçu conforme, la preuve d'exécution manque.
- `fog → Pierre / exécuteur:` (1) exécuter `check_prisme_manifest` + `check_prisme` et confirmer OK ; (2) décider si la boucle V4 doit être complète pour un casse-briques ou si le gabarit clicker est relâché pour ce genre.

**SKIPPED_VALIDATION** :
- item: exécution des oracles s1 ; périmètre: `prisme.json` + `product_snapshot.md` ; statut: non fait ; raison: shell indisponible dans cet environnement d'agent — délégué à l'exécuteur.
- item: complétude de boucle V4 (DECISION, UNLOCK avec `appears`, NEXT_GOAL×2, META_LOOP prestige, ADVANTAGE) ; périmètre: `prisme.json` exigences de boucle ; statut: non fait — non applicable ; raison: genre casse-briques arcade minimal (charter : périmètre minimal, pas de prestige/idle/multi-niveaux) — non fabriqué par choix doctrinal anti-invention.
- item: sourçage GM des exigences de boucle (`gm_worldscan:game_master.loops.*`) ; périmètre: 5 exigences de boucle ; statut: non fait ; raison: `gm_worldscan.json` absent du run_dir — stat attendue `exigences_sourcees_gm` = 0/5, non compensé.
- item: consommation de `story_bible.json`/`gm_worldscan.json` comme sources ; périmètre: exigences EXPECTED ; statut: non fait ; raison: artefacts absents (profil non-narratif) — signalé, non compensé.
- item: consommation de `design/progression_contract.md`/`design/calibration.md` (ordre joué des exigences de boucle) ; périmètre: précédence des exigences de boucle ; statut: non fait ; raison: fichiers absents — comportement inchangé, non compensé.
