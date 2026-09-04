# product_snapshot.md — runm_breakout (Prisme Produit, s1)

Ancre : `charter.yaml` (Pierre 2026-09-02) — casse-briques web minimal mais COMPLET et jouable, socle N1 (page HTML+JS unique, RNG seedé, logique `.mjs` testable hors navigateur, `window.__game`, déterminisme par hash). Sources d'exigences résolues dans le run_dir : `worldscan.json` (présent, adresses ancrables `games[0].*`). `story_bible.json`, `gm_worldscan.json`, `design/progression_contract.md`, `design/calibration.md` sont **absents du run_dir** — je le signale et ne compense pas (conséquence mesurée plus bas : sourçage GM 0/N, précédence de boucle jouée non fournie).

---

## 1. CE QUE LE JOUEUR VOIT

Une seule page qui tient dans le navigateur, sans défilement. En haut, une ligne d'**objectif** lisible : « Détruis toutes les briques ». Sous elle, l'**aire de jeu** rectangulaire bordée de trois murs (gauche, droite, haut) et ouverte en bas. En haut de l'aire, un **mur de briques** rangé en grille régulière, chaque brique un rectangle plein et distinct. En bas, une **raquette** horizontale posée près du bord ouvert. Une **balle** ronde, seule, se déplace dans l'aire et laisse voir sa trajectoire par son déplacement continu. Un **compteur de briques restantes** est affiché et diminue à vue d'œil. Quand une brique est touchée, elle **disparaît** de la grille au même instant, laissant un trou visible. À la fin, un **panneau d'état** unique s'affiche par-dessus l'aire figée : soit « VICTOIRE », soit « DÉFAITE ». Aucun menu de niveaux, aucun tableau de scores en ligne, aucune boutique cosmétique : l'écran ne montre que ce qui sert la partie en cours.

## 2. CE QUE LE JOUEUR FAIT

Il ouvre la page et joue immédiatement, sans tutoriel. Il **déplace la raquette** vers la gauche ou la droite en maintenant les touches fléchées du clavier — c'est son seul contrôle. Avec ce geste il **place la raquette sous la balle** pour la renvoyer avant qu'elle ne tombe, et il **choisit le point de contact** sur la raquette pour infléchir l'angle du rebond et diriger la balle vers les briques encore debout. Il **répète** ce geste à chaque rebond, tour après tour, en lisant la trajectoire pour anticiper où la balle va revenir. Il **poursuit la partie** jusqu'à ce que le mur soit entièrement vidé (il gagne) ou que la balle échappe au bord bas (il perd). Il n'y a rien d'autre à faire : pas de tir, pas de visée à la souris, pas d'objet à collecter, pas de compétence à débloquer.

## 3. CE QUE LE JOUEUR RESSENT

La prise en main est **immédiate et sans friction** : une touche, une raquette qui répond, une balle qui part. Chaque brique détruite donne une **satisfaction nette et instantanée** — un contact, une disparition, le compteur qui baisse d'un cran, la victoire qui se rapproche visiblement. À mesure que la balle descend vers le bord ouvert monte une **tension courte et physique** : le joueur doit se replacer vite, et une balle presque perdue puis rattrapée procure un soulagement franc. Le plaisir vient de la **maîtrise qui progresse en une même session** : le joueur comprend que « j'ai frappé trop à gauche, la balle est repartie trop raide » et corrige au coup suivant. La partie est **lisible et honnête** : la difficulté vient de la physique, jamais d'un hasard arbitraire ; un échec est toujours attribuable à un geste, ce qui donne envie de recommencer pour mieux faire.

## 4. RÈGLES OBSERVABLES

Chaque règle est formulée pour être vérifiable par un bot, une mutation ou un oracle sur `window.__game` / le module `.mjs`, hors navigateur quand possible.

- **R1 — Objectif affiché** : tant que la partie est en cours, le HUD `objectif` contient un texte non vide décrivant la destruction du mur. (Preuve : lecture du HUD après chargement — `nonempty`.)
- **R2 — Contrôle raquette** : quand le joueur maintient Flèche-Droite, `window.__game.paddle.x` augmente ; quand il maintient Flèche-Gauche, il diminue ; sans touche, il ne change pas. (Preuve : bot presse chaque touche N frames — `changes`.)
- **R3 — Rebond conservatif** : au contact d'un mur ou de la raquette, la composante de vitesse concernée de la balle change de signe et la norme de la vitesse est conservée (aucune perte d'énergie non intentionnelle). (Preuve : oracle `.mjs` à seed fixe — inversion de signe de `vx` ou `vy`.)
- **R4 — Destruction en une frappe** : au contact balle↔brique, la brique disparaît de la grille au même tick et n'est plus jamais collidable ; aucune brique n'exige un second contact. (Preuve : mutation retirant la déduction « 1 frappe » fait échouer le test.)
- **R5 — Progrès mesurable** : à chaque brique détruite, `window.__game.bricksRemaining` décroît d'exactement 1, et le compteur affiché suit. (Preuve : oracle — décrément unitaire.)
- **R6 — Victoire terminale unique** : quand `bricksRemaining` atteint 0, `window.__game.state` vaut `won`, un panneau « VICTOIRE » s'affiche et la simulation se fige (aucun niveau suivant, aucun reset de prestige). (Preuve : bot détruit tout — état `won`.)
- **R7 — Défaite terminale** : quand la balle franchit le bord bas de l'aire sans vie restante, `window.__game.state` vaut `lost`, un panneau « DÉFAITE » s'affiche et la simulation se fige. (Preuve : bot laisse tomber la balle — état `lost`.)
- **R8 — Boucle rejouée** : entre deux briques successives, les mêmes contrôles (R2) produisent le même type de réponse (R3) et `bricksRemaining` décroît de nouveau — la boucle noyau se rejoue à chaque rebond sans état intermédiaire à débloquer. (Preuve : bot enchaîne deux briques — deux décréments.)
- **R9 — Déterminisme par seed** : à seed identique et suite d'entrées identique, deux exécutions du module `.mjs` produisent le même hash d'état final. (Preuve : double exécution hors navigateur — hash égaux.)
- **R10 — État inspectable** : `window.__game` expose à tout instant `paddle.x`, `ball.{x,y,vx,vy}`, `bricksRemaining` et `state ∈ {playing, won, lost}`, indépendamment du rendu DOM. (Preuve : test node importe le `.mjs` et lit ces champs.)

---

## RAPPORT FINAL

**Ancre** : `charter.yaml` (objectif = casse-briques web minimal complet ; socle N1 ; hors_scope = multi-niveaux, scores en ligne, persistance, prestige). **Reçu `check_prisme_manifest`** : NON DISPONIBLE — permission `run: aucun` et exécution shell désactivée dans cette session ; l'oracle déterministe `node forge/check_prisme_manifest.mjs <run_dir>/prisme.json --worldscan <run_dir>/worldscan.json` n'a PAS été exécuté par moi. Aucun claim auto-certifié n'est émis.

**Chaîne Observation → Claim → Exigence** : les 10 exigences portent trois maillons distincts (donnée du World Scan → déduction indépendamment faillible → garantie du jeu). Références EXPECTED ancrées dans `worldscan.json` (adresses `games[0].objectives[0].*`, `games[0].loops.*`, `games[0].architecture_guess`, toutes résolvables) ; deux exigences socle N1 (R9 non couverte par worldscan pour la partie test-hash côté charter, R10 exposition `window.__game`) sont en source `ADDITIONS`, `reference: null` explicite, ancrées en prose dans le charter.

**Exigences classées non actionnables** : aucune. Les 10 portent une `expected_proof` exploitable (bot_action / oracle / mutation / visual). L'étape ne peut donc pas échouer sur le critère « aucune exigence actionnable ».

**Références non ancrées** : aucune vers `worldscan.json` (toutes résolvent). Les références vers `gm_worldscan:` sont **absentes par nécessité** : `gm_worldscan.json` n'est pas dans le run_dir.

**software_verdict** : NON ÉMIS (aucun oracle exécuté). **claim_verdict: NO_CLAIM_ALLOWED**. **evidence_verdict** : non applicable (aucune validation mécanique lancée).

**BESOIN HUMANGATE (fog) — mismatch genre/gabarit, déjà signalé au run précédent (`manifest-a243e3bfb138847f`, GENERATION_DIFFERENTE_A_REEXAMINER)** : le gabarit de boucle V4 est mono-genre (idle/clicker) et exige des maillons que le jeu cible — casse-briques arcade minimal, charter explicite — **ne possède pas** :
- **DECISION** (au sens V4 : `options` 2 affordances, `policies` idle/actif sur `horizon_frames`, `metric`) : le seul choix de runm_breakout est l'angle de renvoi continu de la raquette — il n'existe aucune décision à deux trajectoires discrètes ni politique idle/active. Encoder de faux `policies` serait une fabrication (garde-fou : règle observable, jamais inventée).
- **UNLOCK / `observe.appears`** : mur unique, aucune nouvelle affordance ni contenu débloqué (charter hors_scope : multi-niveaux).
- **NEXT_GOAL ×2 `new_distinct`** : victoire terminale unique, aucun second objectif textuellement distinct (charter hors_scope : multi-niveaux).
- **META_LOOP (reset de prestige visible)** et **ADVANTAGE (`increases_more_than` après prestige)** : aucun prestige, aucune persistance (charter hors_scope explicite).

Fabriquer ces maillons violerait à la fois le charter (`hors_scope`) et le garde-fou (« toute règle DOIT être observable », « n'invente jamais »). Je livre donc une boucle **complète pour son genre** (PLAYER_GOAL → PLAYER_ACTION → GAME_RESPONSE → REWARD → REPEAT, plus victoire/défaite terminales), **incomplète au sens du gabarit V4** — fait mesurable, à trancher par Pierre (gabarit de boucle par genre, ou dérogation actée pour la lignée arcade minimale).

### why_task_existed
- **problem** : le run runm_breakout (migration V1→V2) a besoin de la vision produit finie du casse-briques minimal décomposée en facettes joueur + règles observables, pour alimenter s3-decompo/s4-archi/s5-wiremap/s9-build.
- **oracle** : dispatch `FORGE_DISPATCH:s1-prisme:runm-breakout-20260902:1` ; oracles de forme `forge/prisme/check_prisme.mjs` (4 sections + ≥1 règle `- **Rn`) et de chaîne `forge/check_prisme_manifest.mjs` (Observation→Claim→Exigence→Preuve→Destination, provenance, ancrage World Scan).
- **root_cause** : non transmise comme défaut ; l'activation est une étape normale du pipeline (décision humaine de séquence), pas la réparation d'une panne. Le seul écart structurel connu est le mismatch genre/gabarit V4 hérité du run précédent.
- **action_reason** : produire `product_snapshot.md` + `prisme.json` fidèles au charter et au World Scan, en marquant explicitement les maillons V4 que le genre ne possède pas plutôt que de les fabriquer.

### result
- `product_snapshot.md` : 4 sections remplies (VOIT / FAIT / RESSENT / RÈGLES OBSERVABLES), 10 règles numérotées `R1..R10`, aucun placeholder.
- `prisme.json` : 10 exigences, chaîne à 3 maillons distincts, provenance complète, 8 EXPECTED ancrées `worldscan:` + 2 ADDITIONS `reference: null`, champs V4 (`acteur`, `loop_role`, `observe`, `affordance`, `replay`) renseignés ; rôles couverts PLAYER_GOAL, PLAYER_ACTION, GAME_RESPONSE, REWARD, REPEAT + NONE ; rôles V4 DECISION/UNLOCK/NEXT_GOAL/META_LOOP/ADVANTAGE déclarés genre-absents (voir HumanGate).
- Sourçage GM : 0/6 exigences de boucle (`gm_worldscan.json` absent) — fait mesuré, non gaté avant run 10.

### proof
- Commande d'oracle NON exécutée (permission `run: aucun` ; shell désactivé) : `node forge/check_prisme_manifest.mjs EVIDENCE/runs/runm_breakout/prisme.json --worldscan EVIDENCE/runs/runm_breakout/worldscan.json` — à lancer par l'exécuteur après matérialisation.
- Vérifié par lecture directe : `worldscan.json` présent et adresses citées résolvables ; `charter.yaml` présent et lu ; `gm_worldscan.json` / `story_bible.json` / `design/*` absents (lectures en erreur « File does not exist »).

### learning
Le mismatch genre/gabarit V4 est structurel et reproductible : tant qu'aucun gabarit de boucle par genre n'existe (ou qu'aucun `gm_worldscan.json` arcade n'est fourni), tout run d'un genre non-clicker produira une boucle honnêtement incomplète au sens V4. La bonne réponse d'un worker s1 est de refuser la fabrication et de remonter le fait mesuré à HumanGate, pas de bourrer de faux `policies`/prestige.

### next_reason
Chaîne causale NON fermée sur un point : le mismatch gabarit V4 ↔ genre arcade minimal exige une décision Pierre (gabarit par genre, ou dérogation actée). Pour le reste, la lignée s1 est prête à descendre vers s3-decompo. Le sourçage GM (0/6) reste mesuré, non bloquant avant run 10.

## SKIPPED_VALIDATION
- **Oracle de chaîne** `check_prisme_manifest.mjs` — périmètre : `prisme.json` produit — statut : **non fait** — raison : permission `run: aucun` et exécution shell désactivée ; l'exécuteur doit le lancer après matérialisation.
- **Oracle de forme** `forge/prisme/check_prisme.mjs` — périmètre : `product_snapshot.md` — statut : **non fait** — raison : même contrainte d'exécution ; conformité visée par construction (4 en-têtes exacts, règles `- **Rn`, aucun placeholder).
- **Sonde d'ancrage amont** `check_amont_traversal.mjs` — périmètre : références `worldscan:` — statut : **non fait (partiel manuel)** — raison : non exécutable ; résolution vérifiée à la main par lecture de `worldscan.json`.
- **Sourçage GM** — périmètre : exigences de boucle — statut : **impossible** — raison : `gm_worldscan.json` absent du run_dir (0/6, mesuré, non gaté).
