I have what I need. Confirmed run_dir state: `charter.yaml` ✅ and `worldscan.json` ✅ present (worldscan resolves as JSON — references anchorable); `gm_worldscan.json`, `story_bible.json`, `design/progression_contract.md`, `design/calibration.md` all ABSENT. My response below **is** `product_snapshot.md` (prose) + the terminal `prisme.json` block.

# Product Snapshot — runm_breakout

Le produit fini, tel que le joueur le vit : un casse-briques web minimal, chargé dans un onglet de navigateur, jouable immédiatement au clavier, avec une partie qui commence, se gagne ou se perd, et s'arrête. Ce document décrit ce jeu terminé, pas le chemin pour l'obtenir. Ancre : `charter.yaml` (s0) — objectif « casse-briques web minimal et jouable », `criteres_demo` et `criteres_succes` ; source de comparables : `worldscan.json` (s2, Breakout/Arkanoid/Peglin).

## 1. CE QUE LE JOUEUR VOIT

À l'ouverture de la page, le joueur voit une aire de jeu rectangulaire bordée de trois murs (gauche, droite, haut). En bas, une **raquette** horizontale. Au centre-haut, un mur de **briques** rangées en grille. Une **balle** unique, visible, se déplace en continu et rebondit sur les murs latéraux, le mur du haut et la raquette. En surimpression (HUD), trois informations lisibles en permanence : un **objectif** en clair (texte « Vider l'écran 1 »), un **score** numérique, et un **compteur de vies** initialisé à 3. Quand une brique est touchée, elle disparaît de la grille et le score s'incrémente dans la même frame. Quand tout un écran est vidé, un **second écran** de briques apparaît et le texte d'objectif change en « Vider l'écran 2 ». En fin de partie, un **écran de victoire** (toutes briques détruites) ou un **écran de game over** (vies épuisées) s'affiche et le mouvement s'arrête.

## 2. CE QUE LE JOUEUR FAIT

Le joueur déplace la raquette horizontalement au clavier : la cible `raquette_gauche` la pousse à gauche, `raquette_droite` la pousse à droite, en réponse visible et immédiate à chaque pression. Il place la raquette sous la balle pour la renvoyer, et **choisit le point de contact** — bord gauche ou bord droit de la raquette — pour orienter le renvoi et viser la zone de briques qu'il veut atteindre ensuite. Il enchaîne les rebonds pour casser les briques une à une, gère ses 3 vies en évitant que la balle passe sous la raquette, vide le premier écran, puis **rejoue les mêmes gestes** sur le second écran qui vient d'apparaître. La partie est entièrement pilotable via des actions DOM-only (clavier), ce qui la rend rejouable par un bot déterministe hors interaction humaine.

## 3. CE QUE LE JOUEUR RESSENT

Le joueur ressent d'abord le **contrôle direct** : la raquette obéit sans latence, le rebond est attribuable à son geste, la casse d'une brique est une cause-effet propre et satisfaisante (impact → disparition → point). Vient ensuite la **tension** : chaque descente de balle sous la raquette coûte une vie visible, et le compteur qui tombe crée un enjeu croissant. La maîtrise du point de contact procure un sentiment de **compétence** (viser, prédire l'angle). Vider un écran donne une **récompense de progression** franche — un écran neuf apparaît, l'objectif se renomme, la boucle repart identique mais dans un état plus avancé. La partie est courte, lisible, et se clôt nettement : la victoire ou la défaite est sans ambiguïté, ce qui invite au retry.

## 4. RÈGLES OBSERVABLES

- **R1** — Le HUD affiche en permanence un objectif non vide (« Vider l'écran 1 ») lisible à tout instant.
- **R2** — Presser `raquette_gauche` / `raquette_droite` déplace visiblement la raquette dans la direction correspondante (la position `raquette_x` change).
- **R3** — Une brique touchée par la balle disparaît de l'écran et le compteur de briques restantes diminue.
- **R4** — À chaque brique détruite, le score affiché augmente d'une valeur strictement positive dans la même frame.
- **R5** — Une balle visible se déplace en continu et rebondit sur les murs latéraux, le mur haut et la raquette.
- **R6** — Le point de contact raquette/balle (gauche vs droite) modifie l'angle de renvoi ; sur un horizon de 300 frames, la politique de jeu choisie fait varier le score.
- **R7** — Quand la dernière brique de l'écran 1 est détruite, un second écran de briques apparaît.
- **R8** — Après l'apparition de l'écran 2, le texte d'objectif du HUD devient « Vider l'écran 2 », textuellement distinct de « Vider l'écran 1 ».
- **R9** — Sur l'écran 2, les mêmes gestes rejouent leurs effets et le nombre de briques restantes repasse d'un état vidé à un état rempli.
- **R10** — Le HUD affiche un compteur de vies initialisé à 3, décrémenté de 1 chaque fois que la balle passe sous la raquette.
- **R11** — Toutes les briques détruites → un écran de victoire s'affiche et la partie s'arrête.
- **R12** — Vies épuisées (3e passage sous la raquette) → un écran de game over s'affiche et la partie s'arrête.
- **R13** — À seed fixe et suite d'inputs fixe, la logique métier (module `.mjs` hors navigateur) produit un état final identique, reproductible par hash (socle N1).

---

## RAPPORT FINAL

**Ancre charter** : objectif s0 « casse-briques web minimal et jouable », `criteres_demo` (balle visible, raquette clavier, brique qui disparaît, score qui monte, victoire/défaite observables) et `plateforme_cible` (RNG seedé, logique `.mjs` testable hors navigateur, actions DOM-only, reproductible par hash). Toutes les Règles observables R1–R13 sont dérivées de ces critères ou du World Scan Breakout.

**Reçu oracle** : `node forge/check_prisme_manifest.mjs <run_dir>/prisme.json --worldscan <run_dir>/worldscan.json` — **NON EXÉCUTÉ par le producteur** (permission `run: aucun`). Je ne peux donc pas produire de `software_verdict` mesuré ; l'oracle s'exécute après matérialisation. `claim_verdict: NO_CLAIM_ALLOWED`. `software_verdict: BLOCKED` (oracle non lancé, faute de droit d'exécution — pas un échec du manifeste).

**Provenance des références** : `worldscan.json` présent et résoluble → 14 exigences sur 15 portent une adresse `worldscan:games[0].…` qui résout (objectives, loops). 1 exigence (`R14_determinism`) est `ADDITIONS` avec `reference: null` (contrainte socle N1, non présente dans le World Scan).

**Exigences classées non actionnables** : aucune. Les 15 exigences portent un `expected_proof` exploitable (`bot_action`, `visual`, `oracle`).

**Références non ancrées** : aucune adresse `worldscan:` émise ne pointe hors de la structure réelle de `worldscan.json` (indices `games[0]`, `objectives[0]`, `loops.*` tous présents).

**GM sourcing (mesure advisory)** : `gm_worldscan.json` **ABSENT** du run_dir → `exigences_sourcees_gm = 0 / 10` (exigences de boucle). Advisory, non gaté avant run 10 (verrou GO Pierre). Je ne compense pas : les exigences de boucle sont sourcées sur `worldscan:` faute de Game Master.

**why_task_existed** :
- `problem:` non transmis explicitement — activation par dispatch s1-prisme (`FORGE_DISPATCH:s1-prisme:runm-breakout-20260902:1`) pour produire le snapshot produit + prisme.json du run de migration V1→V2.
- `oracle:` aucun (activation par le pipeline Forge, décision de séquencement).
- `root_cause:` non établie (pas de panne amont ; étape normale de la chaîne).
- `action_reason:` s1 doit capturer la vision produit finie et émettre les exigences falsifiables consommées par s3/s4/s5/s9.
- `result:` product_snapshot.md (4 sections, 13 règles observables) + prisme.json (15 exigences, chaîne observation→claim→énoncé distincte, 14/15 ancrées worldscan). Boucle couverte sur 8 rôles /10 : PLAYER_GOAL, PLAYER_ACTION, GAME_RESPONSE, REWARD, DECISION, UNLOCK, NEXT_GOAL (×2 `new_distinct`), REPEAT. META_LOOP et ADVANTAGE **volontairement absents** (voir next_reason).
- `proof:` commande `check_prisme_manifest` non exécutée (run: aucun) ; preuve mécanique déléguée à l'exécuteur post-matérialisation.
- `learning:` le gabarit de boucle V4 comporte deux maillons — META_LOOP (prestige avec reset visible) et ADVANTAGE (`increases_more_than` après prestige) — propres au genre idle/clicker ; le genre cible (arcade skill-loop borné WIN/LOSE) ne les possède pas, et le charter les met explicitement `hors_scope` (« Méta-progression, prestige, … : au-delà du V1 minimal ») avec interdiction d'inventer un design-intent sans source Pierre. Les fabriquer serait un faux-vert (action interdite). Confirmé cohérent avec le pré-mortem `manifest-a243e3bfb138847f`.
- `next_reason:` **escalade fog HumanGate** — deux causes non résolues persistent, non réparables au niveau s1 : (1) le gabarit V4 mono-genre exige META_LOOP+ADVANTAGE inapplicables à un arcade borné ; un gabarit de boucle *par genre* est nécessaire, décision Pierre. (2) `gm_worldscan.json` absent → sourçage GM des exigences de boucle impossible (0/10), à trancher (produire un GM pour ce genre, ou acter que l'arcade minimal s'en passe).

**SKIPPED_VALIDATION** :
- item: exécution de `check_prisme_manifest.mjs` ; périmètre: prisme.json émis ; statut: non fait ; raison: permission `run: aucun` — le producteur n'exécute pas l'oracle, il est lancé après matérialisation.
- item: exécution de `forge/prisme/check_prisme.mjs` (conformité markdown) ; périmètre: product_snapshot.md ; statut: non fait ; raison: idem `run: aucun`.
- item: couverture des rôles de boucle META_LOOP et ADVANTAGE ; périmètre: prisme.json ; statut: non couvert, décision assumée ; raison: charter `hors_scope` (méta/prestige) + interdiction d'inventer un design-intent sans source Pierre → escaladé en fog.
- item: sourçage GM des exigences de boucle ; périmètre: 10 exigences de boucle ; statut: 0/10 ; raison: `gm_worldscan.json` absent du run_dir.
