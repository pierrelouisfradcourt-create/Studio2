# BREAKOUT V2 — CHARTER DE CAMPAGNE FORGE (PROPOSED)

Date : 2026-07-30. Auteur : session Fable 5 (poste de commande). Statut : **PROPOSED** —
soumis à HumanGate Pierre, aucune écriture hors ce fichier, aucun dispatch d'agent Forge
déclenché par ce document.

Marqueurs : **[M]** fait mesuré directement dans le dépôt · **[H]** jugement/proposition de ce
charter, à ratifier ou amender HumanGate · **[E]** mécanisme déjà existant ailleurs, réutilisé
sans reconception.

---

## 0. Cadrage — ce que ce document tranche, ce qu'il hérite

Cadrage transmis pour cette mission, verbatim Pierre : *« Ne pas reprendre l'ancien essai
Breakout. Le précédent Breakout était une expérience externe, pas une campagne Forge. Créer une
vraie campagne Forge V2. Le jeu doit servir de TEST DE PIPELINE, pas seulement produire un
jeu. »*

Ce cadrage **tranche lui-même** la tension documentée dans `docs/forge/BREAKOUT_V2_CAMPAIGN_PREP.md`
§0 et §2.1 entre deux décisions Pierre datées du même jour (2026-07-30) : la décision « matin »
de `MASTER_SCHEMA_TRUTH_AUDIT_2026-07-30.md` §6.1-6.4 qui écartait Breakout comme cible E7 au
critère « absente de `games/` », et la décision « soir » qui réintroduit Breakout explicitement.
Le cadrage de cette mission **est une troisième confirmation, postérieure aux deux autres**, et
lève l'ambiguïté dans le même sens que la décision « soir » : Breakout, campagne neuve. Il tranche
aussi explicitement l'Option A du prep doc §2.1 (« s0 neuf ») contre l'Option B (« adaptation du
charter web ») — *« ne pas reprendre l'ancien essai »* exclut l'adaptation. Ce charter est donc un
**s0 neuf**, qui lit `lab/forge_runs/breakout/charter.yaml` (2026-07-11) uniquement comme source
des RÈGLES PRODUIT (mécanique du casse-briques), jamais comme base de révision. [M]

Ce que ce document **hérite sans le redoubler** du prep doc (2026-07-30, checklist déjà faite) :
la liste des 4 pré-requis bloquants (§2), le protocole de contamination et sa recommandation
option (a) « assumer et acter » (§3), la table de métriques discrètes vs bruitées (§6), les
risques physique-continue (§7). Ce charter **consomme** ces conclusions ; il ne les réexamine pas.

---

## 1. Objectif de campagne — double

**(a) Produit.** Forger un jeu de casse-briques (Breakout) solo, arcade, JOUABLE et DÉTERMINISTE
(hors seed de disposition des briques), sur MOTEUR GODOT, sous le profil `standard_godot`
(squelette gelé : `scripts/forge/standard/{capabilities,core_requirements,repo_map}.yaml`).

**(b) Pipeline — le vrai objet de cette campagne.** Prouver que la Forge V2 fabrique un jeu
complet de bout en bout avec KB active, nouveaux branchements, validation, oracles, traces et
lessons. Ce que la campagne doit **PROUVER mécaniquement du pipeline**, pas seulement du produit :

| à prouver | preuve mécanique attendue | statut au démarrage |
|---|---|---|
| KB consultée, pas décorative | `knowledge_base/search_log.jsonl` reçoit ≥1 entrée par étape candidate à la réutilisation, avec `matchCount` réel (pas 0/0 systématique — leçon `agent_context_audit_20260725.md` : 5/5 recherches à matchCount:0 constaté sur Snake) | à mesurer run 1 |
| provenance signée par étape | chaque étape (`s0`→`s12`) émet un artefact `context/*.manifest.jsonl` + reçu signé, comme la structure `lab/forge_runs/snake/context/` | [E] mécanisme déjà en place, à exercer |
| `failure_event` émis si halt | un arrêt d'étape (oracle rouge, timeout, budget dépassé) produit un événement structuré exploitable, pas un silence | à exercer — aucune trace connue d'un `failure_event` réellement émis sur Snake, à vérifier au run 1 |
| cache tokens capturés | coût/tokens par run capturés dans `state.json` du driver instrumenté, alimentant `knowledge_base/learning_curve.jsonl` comme pour la calibration Snake (`_run_cal1/2/3_20260730/`) | [E] format connu, à réutiliser tel quel |
| gel de wiremap posé | `09_WIREMAP/wiremap.json` gelé (empreinte) avant le build, comme `wiremap_frozen.json` sur le run web de 2026-07-11 et le gel Snake | [E] |
| verdict signé re-vérifiable | `verdict.json` signé HMAC, re-vérifié par `forge.verify_run` — critère non négociable ADR-002 | [E] |
| lessons alimentables | tout mutant survivant non justifié, tout écart produit/preuve (cf. §6 métriques) alimente `knowledge_base/learning_curve.jsonl` et/ou une entrée de leçon de clôture (format `proof_never_replaces_product_run.md`) | à produire en fin de campagne |

Cette campagne sert de **première exécution complète et instrumentée** de la chaîne
`s9-build-godot-standard → s10a → s10s → s11 → s12` sous le driver instrumenté — Snake en avait
posé la structure et la calibration de bruit (N=3, ~20 %) ; Breakout est le premier jeu qui la
traverse en entier depuis un charter neuf. **Ce run n'est pas E7** (voir §6 du prep doc et §6 du
présent charter) : une seule configuration (Opus, routage actuel) tourne ici, E7 exige au moins
deux configurations comparées. [M]

**Décision de contamination héritée [M] :** option (a) du prep doc §3 retenue par défaut faute
d'arbitrage contraire — `games/breakout/` (implémentation JS complète et déjà verte, 2026-07-11)
reste dans l'arbre, lisible par le builder pendant le run. Conséquence assumée : cette campagne
mesure la fabrication Forge V2 **observable**, pas une capacité de fabrication non assistée par
lecture d'une solution existante. Toute réutilisation de `games/breakout/*.mjs` observée dans la
wiremap doit être typée `CONCEPT`, jamais `CODE` (aucun import JS→GDScript n'a de sens mécanique) —
règle identique à celle qui a gouverné Pong→Snake.

---

## 2. Charter Breakout (le cœur)

```yaml
# Charter Forge — étape 0 (Contrat) — projet : breakout
# schéma : {objectif, hors_scope[], criteres_succes[], actions_interdites[],
#           plateforme_cible, reference_jeu, criteres_demo[]} — format Snake v2
# oracle sortie : forge.static_oracles.check_charter (déterministe, non-LLM)

version: 1   # s0 neuf — ceci N'EST PAS une révision du charter web 2026-07-11

objectif: >-
  Forger de zéro un jeu de casse-briques (Breakout) solo, arcade, JOUABLE et DÉTERMINISTE
  (hors seed de disposition des briques), sur MOTEUR GODOT, sous le profil standard_godot
  (squelette gelé). Ce run a un DOUBLE objectif, de rang égal (cadrage Pierre 2026-07-30,
  verbatim : « Le jeu doit servir de TEST DE PIPELINE, pas seulement produire un jeu ») :
  (a) un Breakout jouable, (b) l'exercice et la mesure du pipeline Forge V2 observable
  (provenance, oracles, verdict signé, lessons — voir §1 du document de campagne associé).
  Produit minimal : une balle, une raquette contrôlée au clavier, N briques en disposition
  SEEDÉE (même seed + index de niveau => même disposition, reproductible), physique de
  rebond réelle (murs latéraux/plafond par inversion de composante de vitesse, raquette
  avec angle de rebond FONCTION DU POINT D'IMPACT, brique détruite au contact avec rebond
  correspondant). Conditions de fin mutuellement exclusives : VICTOIRE quand le compte de
  briques cassables restantes vaut exactement 0, DÉFAITE quand la balle est perdue sous la
  raquette et qu'il ne reste plus de vies. La logique de jeu PURE (état, physique,
  collisions, génération de niveau, conditions de fin) est séparée du rendu et de l'entrée :
  rendu et input consomment l'état, jamais l'inverse — même discipline que Snake et Pong.
  Point dur assumé dès l'objectif (voir §3) : Breakout est une physique CONTINUE, pas une
  grille discrète — le déterminisme se prouve sur un PAS DE TEMPS FIXE, nommé, jamais sur
  l'horloge du moteur. Le jeu doit être prouvé SOLVABLE par un bot qui INTERCEPTE réellement
  la balle selon une stratégie de contrôle déclarée (§3), pas seulement testé mécanique par
  mécanique.

hors_scope:
  - "Multijoueur, réseau, matchmaking, classement en ligne, backend, comptes utilisateurs,
     persistance serveur : aucun serveur de jeu. Persistance LOCALE d'un meilleur score N'EST
     PAS dans le périmètre minimal de ce run — c'est un ajout possible d'une révision
     ultérieure (à la différence de Snake v2, où Pierre l'avait explicitement demandée ; ici
     aucune décision équivalente n'existe, donc absence par défaut, pas par oubli)."
  - "Power-ups, bonus, briques multi-hits, briques indestructibles, thèmes cosmétiques,
     animations avancées : systèmes de contenu hors de la tranche verticale minimale
     (périmètre produit minimal, prep doc §4)."
  - "Effets sonores et musique EN TANT QUE SYSTÈME LIVRÉ DÉCIDÉ : voir question_ouverte_humangate
     — core.audio est une exigence CORE non contournable (not_applicable_allowed: false,
     scripts/forge/standard/core_requirements.yaml) ; ce charter ne peut ni la retirer ni la
     déclarer NOT_APPLICABLE. Précédent EXACT sur Snake : core.audio laissé DEFERRED,
     decider: pierre, jamais omis (games/snake/09_WIREMAP/wiremap.json ligne ~649). Même
     traitement ici — voir question_ouverte_humangate."
  - "Sprites/assets graphiques externes, textures, images téléchargées, polices tierces :
     rendu par primitives du moteur (nodes de dessin/formes Godot), zéro asset importé
     (hors le cas audio ci-dessus, s'il est ratifié)."
  - "Export web / portage navigateur / réécriture canvas : la cible de CE run est le moteur
     Godot. Un export éventuel est un run ultérieur."
  - "Réutilisation par COPIE DE CODE de games/breakout/*.mjs (implémentation JS 2026-07-11,
     verte, laissée dans l'arbre — décision de contamination §3 du document de campagne) :
     réutilisation typée CONCEPT uniquement, jamais CODE — aucun import JS→GDScript n'a de
     sens mécanique."
  - "Décision d'architecture détaillée (découpage scènes/nodes/scripts Godot) : étape 4
     (s4-archi) / wiremap, pas ce charter."
  - "World scan / recherche de références externes sourcées HTTP sur le genre casse-briques :
     PAS ENCORE FAIT pour Breakout à la date de ce charter (à la différence de Snake, dont le
     World Scan précédait le charter v1). La Genre Bible esquissée en §4 ci-dessous est donc
     TRACE_INDIRECTE, jamais HTTP-sourcée — le vrai World Scan reste un prérequis avant
     ratification de cette Genre Bible, pas une option."
  - "Promotion de briques ou de règles vers knowledge_base/ et toute écriture durable (ledger,
     memory/) : propose-only, ratifiée par Pierre, hors de ce run."
  - "Multi-niveaux (progression au niveau suivant après victoire) : le charter web 2026-07-11
     le mentionnait ; le périmètre minimal (prep doc §4) se limite à UN SEUL niveau pour la
     première boucle complète — arbitrage HumanGate explicite requis pour l'étendre, pas
     tranché ici (voir question_ouverte_humangate)."
  - "Toute modification des lanes protégées : src/, tests/, autopilot.py, scripts/studioV2/,
     lab/chains/IMPROVEMENT_LEDGER.yaml, lab/chains/golden_examples.jsonl."
  - "Toute modification de games/pong/ (témoin de régression gelé) ou de games/breakout/
     (implémentation JS 2026-07-11 laissée intacte comme référence lisible, pas comme cible
     d'édition)."

criteres_succes:
  - "SOLVABILITE PROUVEE PAR INTERCEPTION REELLE : un bot déterministe pilote la raquette via
     l'API d'entrée publique et INTERCEPTE réellement la trajectoire de la balle (pas un
     positionnement statique chanceux), atteignant la VICTOIRE (briques cassables restantes
     == 0) sur la seed de référence, sur au moins trials (voir game_contract) essais
     indépendants. L'oracle sort SOLVABLE (code 0) sur le jeu correct, INJOUABLE (code non
     nul) sur une version volontairement cassée. Un bot 'camp au centre' ou 'suit toujours X
     de la balle sans anticipation' doit être testé comme CONTRÔLE NÉGATIF nommé et prouvé
     insuffisant (taux de victoire significativement inférieur au bot d'interception) — sans
     ce contrôle, un taux de victoire élevé ne prouve rien sur la difficulté réelle du niveau
     (leçon oracle_solvability_lesson : oracle vert ≠ jeu bon, déjà vue 2x sur survival_arena
     et collect_runner)."
  - "LOGIQUE SEPAREE DU RENDU : les scripts de logique pure (état de la balle, de la raquette,
     des briques, physique, collisions, conditions de fin) n'héritent d'AUCUN Node Godot,
     n'appellent AUCUNE API de moteur (get_node, Input, InputEvent, Viewport, CanvasItem,
     _draw, _process, _physics_process, move_and_collide, Timer, OS/Time, randi/randf non
     seedé) et n'importent ni scène ni script de présentation. Vérifié par l'oracle
     d'architecture statique déterministe (même oracle que Snake, cible Breakout)."
  - "DETERMINISME SUR PAS DE TEMPS FIXE : à état initial, seed de disposition et séquence
     d'entrées identiques, deux exécutions de la logique pure produisent un état final
     strictement identique. La simulation avance par pas de temps FIXE, nommé (constante de
     parametres_de_design), jamais par le delta-time variable du moteur — aucune dépendance à
     Time/OS/framerate dans la logique pure (point dur §3). Vérifié par un test de replay sur
     une partie assez longue pour inclure plusieurs rebonds raquette et plusieurs briques
     détruites."
  - "PHYSIQUE DE REBOND ASSERTEE PAR VALEURS STRICTES : rebond sur murs latéraux/plafond
     (inversion stricte de la composante de vitesse concernée), rebond sur brique (destruction
     + rebond correspondant), rebond sur raquette avec angle FONCTION DU POINT D'IMPACT testé
     sur AU MOINS 3 points d'échantillonnage nommés (centre, bord gauche, bord droit de la
     raquette), chaque point assertant une valeur d'angle STRICTE attendue — jamais un
     intervalle >=/<=."
  - "CONDITIONS DE FIN ASSERTEES STRICTEMENT : VICTOIRE ssi briques_cassables_restantes == 0 ;
     perte de vie quand la balle franchit la limite basse du terrain sous la raquette ;
     DÉFAITE ssi vies_restantes == 0. Les deux états terminaux sont mutuellement exclusifs et
     exhaustifs avec EN_COURS ; aucun chemin de sortie de boucle sans statut terminal
     (assertion stricte, même famille que le critère Snake CONDITION DE FIN)."
  - "GENERATION DE NIVEAU SEEDEE ET DETERMINISTE : à seed + index de niveau identiques, la
     disposition des briques (position, présence) est strictement identique sur deux
     générations successives. Aucun Math.random()/randi non seedé dans la génération."
  - "CONTRAT DE JOUABILITE RESPECTE : le jeu expose un point d'observation de debug lisible
     par l'oracle (position balle, vitesse balle, position raquette, briques restantes, vies
     restantes, statut en_cours/gagne/perdu), un affichage d'état de fin explicite et une
     commande de relance — tous atteignables depuis le runtime réel du moteur. Vérifié par un
     test end-to-end qui lit ces hooks sur une instance réellement lancée."
  - "PREUVE PAR LECTEUR REEL : chaque critère de démo est exercé par une preuve qui passe par
     le RUNTIME RÉEL du moteur (entrées réelles injectées, lecture de l'état exposé et de
     l'image rendue), jamais uniquement un chemin de test hors-moteur. Contrainte de poste
     connue : --headless rend une texture nulle sur ce poste (fait mesuré 2026-07-22) — la
     capture exige --rendering-driver vulkan, fenêtre positionnée hors écran."
  - "DEMARRAGE ET AFFICHAGE PROUVES HORS CHAINE D'ORACLES : leçon de clôture Snake ratifiée
     Pierre 2026-07-29 (proof_never_replaces_product_run.md) — un projet peut satisfaire tous
     ses oracles et ne pas démarrer. Ce charter DÉCLARE le point d'entrée du jeu (scène
     principale lancée par le moteur) comme un INVARIANT vérifié en ABSENCE comme en présence :
     l'oracle produit doit constater que l'exécutable démarre réellement ET afficher une
     capture non monochrome (core.render), pas seulement que les scripts existent."
  - "PARAMETRES DE JEU ISOLES ET NOMMES : tous les paramètres d'équilibrage (dimensions du
     terrain, dimensions/vitesse de la raquette, vitesse initiale de la balle, pas de temps
     fixe, angle de rebond maximal, disposition de la grille de briques, vies initiales,
     seed de référence) vivent dans UN SEUL bloc de constantes nommées de la logique pure.
     Vérifié mécaniquement : le nombre de littéraux numériques de gameplay hors de ce bloc
     est exactement 0."
  - "TESTS A MUTATION FORTS : les tests de la logique pure tuent les mutants sur les
     invariants critiques (inversion de vitesse aux murs, calcul de l'angle de rebond raquette,
     destruction de brique, décrément de vie, condition de victoire, condition de défaite,
     pas de temps fixe non contournable) ; tout mutant survivant est trié avec justification
     nommée."
  - "REUTILISATION NOMMEE AVANT PRODUCTION : chaque bloc de la wiremap porte REUSED_FROM typé
     CODE:<chemin> / CONCEPT:<chemin> / NEW, posé AVANT le build. Les capacités déjà
     enregistrées play.paddle, play.ball, play.score (scripts/forge/standard/capabilities.yaml,
     apportées par Pong) sont RÉUTILISABLES EN CONCEPT sur cette base — mêmes noms de
     capacité, implémentation Godot neuve. Toute capacité nouvellement nécessaire (briques,
     vies, angle de rebond — voir §5) n'existe PAS encore dans le registre fermé et devra être
     proposée pour gate Pierre avant d'être utilisée dans une ligne de wiremap (le registre est
     une donnée FIGÉE, aucun agent ne l'étend de son propre chef)."
  - "TAUX DE REUTILISATION MESURE ET RAPPORTE : part de blocs CODE / CONCEPT / NEW mesurée
     mécaniquement sur la wiremap réelle, rapportée séparément par type (jamais agrégée en un
     seul chiffre de « réutilisation », même règle que Snake)."
  - "OBSERVABLE PAR LE JOUEUR DES LA WIREMAP : chaque bloc déclare OBSERVABLE_BY_PLAYER dès sa
     rédaction initiale. Vérifié par check_observable_coverage."
  - "PREUVE MECANIQUE FOURNIE : chaque verdict d'étape aval cite un evidence_path. Un reçu sans
     evidence_path est BLOCKED, jamais OK."
  - "VARIANCE PROUVEE AVANT USAGE : toute métrique introduite pour classer/générer/calibrer le
     jeu (difficulté perçue, bande de vitesse, etc.) prouve d'abord qu'elle porte une
     information variable (≥2 valeurs distinctes non triviales), ou est requalifiée sous le
     nom de ce qu'elle mesure réellement."
  - "CHARTER COMPLET : ce charter.yaml parse en YAML valide, aucun champ requis vide/absent/
     placeholder non résolu — vérifié par forge.static_oracles.check_charter."

actions_interdites:
  - "Certifier le jeu OK sans oracle de SOLVABILITÉ vert avec bot d'interception réelle ET son
     contrôle négatif (bot naïf prouvé insuffisant) : un taux de victoire chanceux non
     différencié d'un contrôle négatif est un jeu injouable certifié = interdit."
  - "Écrire un test tautologique (>=, <=, « existe ») là où le comportement observable impose
     une égalité ou une valeur stricte — s'applique en particulier à l'angle de rebond, qui se
     teste par valeur exacte sur des points d'impact nommés, jamais par plage."
  - "Livrer un reçu de code sans evidence_path : BLOCKED, jamais OK."
  - "Forcer/placer l'état de jeu à la main pour faire passer un test de victoire au lieu de
     laisser un bot piloter l'entrée publique."
  - "Mélanger logique et rendu : faire hériter un script de logique pure d'un Node Godot, ou y
     appeler get_node/Input/InputEvent/Viewport/CanvasItem/_draw/_process/_physics_process/
     move_and_collide/Timer/OS/Time."
  - "Faire dépendre la simulation physique du delta-time variable du moteur (_process/
     _physics_process non contrôlé) au lieu du pas de temps fixe nommé — casse le
     déterminisme et le replay (point dur §3, LE risque distinctif de ce jeu vs Snake)."
  - "Introduire de l'aléatoire non seedé dans la génération de niveau ou la physique."
  - "Disperser des valeurs d'équilibrage en dur dans les scènes, scripts de présentation ou
     tests : tout paramètre vit dans le bloc de constantes nommées (critère PARAMETRES DE JEU
     ISOLES ET NOMMES)."
  - "Copier du code .mjs de games/breakout/ dans le jeu Godot pour gonfler la mesure de
     réutilisation : la réutilisation de games/breakout/ est de type CONCEPT, déclarée comme
     telle, jamais maquillée en CODE."
  - "Étendre scripts/forge/standard/capabilities.yaml (registre figé) sans gate Pierre
     explicite : une capacité nouvelle nécessaire (briques, vies, angle de rebond) est
     PROPOSÉE, jamais ajoutée silencieusement par un agent."
  - "Produire une preuve visuelle en mode --headless et la présenter comme preuve de rendu :
     --headless rend une texture nulle sur ce poste (fait mesuré 2026-07-22)."
  - "Confondre le bot de solvabilité (outil de test interne) avec l'expérience du joueur."
  - "Introduire une dépendance externe runtime (plugin tiers, addon, asset store, paquet
     réseau) : cible exécutable hors-ligne, moteur seul."
  - "Modifier games/pong/, games/breakout/ (référence JS laissée intacte) ou toute lane
     protégée."
  - "Écrire dans knowledge_base/, memory/ ou tout registre durable sans ratification Pierre."
  - "git commit / git push sans go explicite de Pierre."
  - "Émettre un claim auto-certifié sans oracle : sans preuve mécanique, remonter en fog
     HumanGate — jamais claim_verdict autre que NO_CLAIM_ALLOWED."
  - "Laisser un champ placeholder non résolu, vide ou évasif dans un livrable de cette
     campagne : se remplit ou remonte en fog, ne passe jamais."

plateforme_cible: >-
  MOTEUR GODOT (4.x), application de bureau exécutable hors-ligne, entrée clavier, rendu par
  primitives du moteur sans asset importé (hors cas audio ratifié, voir question_ouverte_
  humangate). Choix imposé par le cadrage de cette campagne (§0 du document de campagne) —
  cohérent avec le choix Godot déjà exercé par Pierre sur Snake le 2026-07-28 et reconduit
  ici sans nouvelle discussion : la Forge V2 fabrique sur architecture réutilisable, pas
  uniquement des jeux canvas. Contrainte de poste connue : toute preuve visuelle exige une
  fenêtre GPU réelle (--rendering-driver vulkan, fenêtre hors écran) — --headless ne produit
  aucune image (fait mesuré 2026-07-22).

reference_jeu: >-
  Breakout — casse-briques d'arcade solo. Règles produit héritées du charter web
  lab/forge_runs/breakout/charter.yaml (2026-07-11, source produit uniquement, jamais base de
  révision — voir §0) : balle, raquette, murs de briques, rebond avec angle dépendant du
  point d'impact, niveaux seedés, victoire par destruction complète des briques cassables,
  défaite par épuisement des vies. AUCUN World Scan HTTP-sourcé n'a été conduit pour ce run à
  la date de ce charter — à la différence de Snake, dont le World Scan précédait le charter.
  Voir hors_scope et §4 (Genre Bible esquissée, non ratifiable en l'état).

criteres_demo:
  - "DEMARRAGE VISIBLE : à l'ouverture, le joueur voit le terrain, la raquette, la balle et
     les briques, et comprend quoi faire sans explication écrite."
  - "CONTROLE RACQUETTE REACTIF : déplacer la raquette au clavier produit un mouvement
     perceptible immédiatement, borné aux limites du terrain."
  - "REBOND LISIBLE ET VARIABLE : le joueur PERÇOIT que l'angle de rebond change selon
     l'endroit où la balle touche la raquette (pas un rebond toujours identique)."
  - "DESTRUCTION DE BRIQUE OBSERVABLE : au contact, la brique disparaît visiblement et la
     balle rebondit dans la direction attendue, au même instant."
  - "VIES ET SCORE LISIBLES : le nombre de vies restantes est affiché en chiffres ou en
     symboles non ambigus, et se décrémente visiblement à la perte d'une balle."
  - "FIN DE PARTIE LISIBLE : victoire ou défaite arrête visiblement la partie et affiche un
     état final explicite, sans figer l'application ni continuer en silence."
  - "REJOUER EN UN GESTE : depuis l'écran de fin, un seul appui relance une partie neuve
     immédiatement, sans résidu de la partie précédente."
  - "QUITTER OBSERVABLE : la commande de sortie produit un effet visible (arrêt de la boucle +
     état final affiché) ; aucune commande inerte (défaut Pong 2026-07-27)."
  - "PARTIE SOLO COMPLETE SANS OUTIL : une partie entière (démarrage → rebonds → briques
     détruites → victoire OU défaite → écran de fin → rejouer) se joue au clavier par un
     humain, sans passer par le bot de solvabilité ni une console de debug."
  - "DEMARRAGE IMMEDIAT : aucun menu, aucun écran de chargement, aucun appui préalable requis
     avant le premier mouvement jouable de la raquette."
  - "LISIBILITE DU GAMEPLAY : un observateur qui n'a jamais vu le jeu peut dire, sans
     explication, ce que la raquette contrôle, où va la balle et combien de briques restent."
```

---

## 3. Le point dur — physique continue vs grille discrète

Snake vivait sur une grille 20×20 à ticks discrets : position, collision et mouvement étaient
des entiers, testables par égalité stricte trivialement. Breakout est une **physique continue**
(position balle en flottant, vitesse vectorielle, angle de rebond fonction du point d'impact) et
ce charter en tire trois conséquences concrètes, à geler avant toute autre ligne de wiremap.

**1. Le déterminisme du rebond est la surface à geler en premier.** Sur grille discrète, deux
exécutions identiques produisent trivialement le même état. En physique continue, tout pas de
temps non explicitement fixé (delta-time variable du moteur au lieu d'un tick fixe), toute
opération flottante dépendante de l'ordre d'évaluation, casse la reproductibilité — un replay
peut diverger de façon invisible au premier coup d'œil (positions très proches mais pas
identiques) puis diverger fortement après plusieurs rebonds. Conséquence dans ce charter : un
paramètre `tick_dt_fixed_ms` nommé (§ parametres_de_design), aucune dépendance à `Time`/`OS`/
framerate dans la logique pure, et le critère DETERMINISME SUR PAS DE TEMPS FIXE exige un replay
assez long pour inclure plusieurs rebonds — pas un seul segment de trajectoire trivial.

**2. La solvabilité par bot est structurellement plus difficile.** Le bot de Snake résout un
problème de RECHERCHE DE CHEMIN sur grille (BFS/heuristique, brique candidate connue
`sys-grid-nav-m01`). Le bot de Breakout résout un problème de CONTRÔLE : intercepter une balle en
mouvement continu suppose de prédire sa trajectoire (position + rebonds à venir sur les murs) et
de positionner la raquette en conséquence, sous la même contrainte de vitesse maximale que le
joueur humain. Stratégie de bot concrète proposée [H] : simuler par avance la trajectoire de la
balle (réflexion sur les bords, jusqu'au plan de la raquette) à chaque tick, et déplacer la
raquette vers le point d'interception prédit, plafonné à la vitesse maximale de déplacement
déclarée. Condition de victoire prouvable : le bot ainsi défini atteint VICTOIRE sur `trials`
essais indépendants (seed de référence + variations, voir game_contract §5) avec un taux
significativement supérieur à un bot naïf de contrôle négatif (raquette immobile au centre, ou
raquette qui suit bêtement la coordonnée X courante de la balle sans anticipation) — sans ce
contrôle négatif nommé, un taux de victoire élevé ne prouve rien sur la difficulté réelle du
niveau (répétition volontaire du critère criteres_succes correspondant : c'est le point où
`oracle_solvability_lesson.md` s'applique le plus directement à ce jeu).

**3. Le pas de temps fixe est une exigence, pas une préférence.** Deux raisons convergentes : (i)
le déterminisme replay en dépend directement (point 1) ; (ii) l'oracle de mutation gèle un
comportement en le testant sur des invariants exacts (angle de rebond aux points d'échantillon,
inversion de vitesse) — un pas de temps variable rendrait ces assertions non reproductibles
d'une exécution à l'autre, cassant la garantie même que l'oracle de mutation cherche à établir.
Le tick fixe n'est donc pas une contrainte de performance, c'est une **condition de preuve**.

---

## 4. Genre Bible Breakout — esquisse (NON RATIFIABLE EN L'ÉTAT)

**Avertissement explicite [M] :** contrairement à Snake, dont le World Scan (étape 2, sourcé
HTTP) précédait et alimentait la Genre Bible ratifiée, **aucun World Scan sourcé n'a été conduit
pour Breakout** avant ce charter. Ce qui suit est une esquisse structurelle au format mécanique
attendu par `check_genre_coverage` (voir `games/snake/01_DESIGN/genre_bible.json`), construite à
partir de connaissance générale du genre et du charter web 2026-07-11 — TRACE_INDIRECTE, jamais
HTTP-sourcée. Elle sert de gabarit de forme, pas de contenu ratifiable ; un vrai World Scan reste
un prérequis avant qu'un builder puisse la consommer comme source de vérité (`genre_refs[]`
résolus par check_genre_coverage exigeraient alors des règles réellement sourcées).

```json
{
  "schema_version": 1,
  "game_id": "breakout",
  "status": "ESQUISSE_NON_RATIFIEE",
  "source_of_truth": "AUCUNE — World Scan sourcé requis avant ratification",
  "genre_rules": [
    {
      "id": "genre.breakout.continuous_ball_motion",
      "statement": "La balle est en mouvement continu permanent (vitesse constante ou quasi-constante) ; le joueur n'agit jamais directement sur la balle, seulement sur la raquette.",
      "applies_to_wiremap_line": "core.physics"
    },
    {
      "id": "genre.breakout.paddle_only_control",
      "statement": "La seule action du joueur est de déplacer la raquette horizontalement, bornée aux limites du terrain.",
      "applies_to_wiremap_line": "core.input"
    },
    {
      "id": "genre.breakout.impact_point_deflection",
      "statement": "L'angle de rebond de la balle sur la raquette dépend du point d'impact relatif (centre = rebond vertical, bords = déviation croissante) — mécanique distinctive du genre depuis Arkanoid, citée en germe dans le charter web 2026-07-11.",
      "applies_to_wiremap_line": "core.paddle_rebound"
    },
    {
      "id": "genre.breakout.brick_destruction_on_contact",
      "statement": "Une brique touchée par la balle est détruite au contact (V1 : un seul coup par brique, pas de brique multi-hits) et la balle rebondit selon la face touchée.",
      "applies_to_wiremap_line": "core.brick_collision"
    },
    {
      "id": "genre.breakout.wall_reflection",
      "statement": "La balle rebondit sur les murs latéraux et le plafond par inversion de la composante de vitesse perpendiculaire au mur touché.",
      "applies_to_wiremap_line": "core.wall_collision"
    },
    {
      "id": "genre.breakout.life_loss_on_drop",
      "statement": "Une vie est perdue quand la balle franchit la limite basse du terrain sans avoir été interceptée par la raquette ; une nouvelle balle est servie si des vies restent.",
      "applies_to_wiremap_line": "core.life_loss"
    },
    {
      "id": "genre.breakout.victory_condition_all_bricks",
      "statement": "La victoire est atteinte quand toutes les briques cassables du niveau sont détruites.",
      "applies_to_wiremap_line": "core.end"
    },
    {
      "id": "genre.breakout.defeat_condition_zero_lives",
      "statement": "La défaite est atteinte quand le nombre de vies restantes atteint zéro après une perte de balle.",
      "applies_to_wiremap_line": "core.end"
    },
    {
      "id": "genre.breakout.seeded_level_layout",
      "statement": "La disposition des briques d'un niveau est déterminée par une graine, reproductible à seed identique — condition héritée du charter web 2026-07-11, pas observée dans une source de genre externe à ce stade.",
      "applies_to_wiremap_line": "core.level_generation"
    },
    {
      "id": "genre.breakout.session_short_focused",
      "statement": "Une partie individuelle (un niveau, une vie) dure typiquement de l'ordre de la minute — non chiffré par une source HTTP consultée, proposition non ratifiable en l'état.",
      "applies_to_wiremap_line": "session.pacing"
    }
  ]
}
```

10 règles esquissées (dans la fourchette 8-12 demandée). Deux d'entre elles
(`seeded_level_layout`, `session_short_focused`) sont explicitement marquées comme non
sourcées — un vrai World Scan pourrait les confirmer, les préciser ou les contredire.

---

## 5. `game_contract.yaml` esquissé (budget)

```yaml
# BREAKOUT — contrat de jeu (budget). Cible Godot, campagne Forge V2 test-de-pipeline.
# Format : scripts/forge/standard/SCHEMA.md §1 — gabarit games/snake/00_CHARTER/game_contract.yaml

schema_version: 1
game_id: breakout
runtimes: [rules, godot]

budget:
  # reuses: VIDE. Vérifié [M] : la seule brique Godot du catalogue tier=validated ou
  # candidate est sys-grid-nav-m01 (grid_nav.gd, navigation sur grille discrète) — sans
  # application à une physique continue de balle/raquette. games/pong/ (Concept-only,
  # canvas JS) et games/breakout/ (Concept-only, canvas JS) ne sont PAS des bibliothèques
  # Godot validées. Déclarer un reuse ici sans brique réelle en bibliothèque validée ferait
  # échouer le volet budget (même règle que Snake).
  reuses: []
  # adds: VIDE. Ce build ne PROMET aucun dépôt en bibliothèque — cohérent avec Snake (« pas
  # d'extension d'infrastructure » tant qu'aucune brique n'est mesurée en usage réel). Si le
  # forgeron juge qu'un système (ex. calcul d'angle de rebond réutilisable) mérite d'être
  # légué, le budget le BLOQUE et le remonte — comportement voulu, pas un échec.
  adds: []

assets:
  # Aucun asset visuel externe prévu (rendu par primitives du moteur). Le statut de core.audio
  # est NON TRANCHÉ (voir question_ouverte_humangate du charter) — si Pierre ratifie un
  # adaptateur audio, ce bloc devra être révisé avant s9 pour déclarer le plan (cc0 ou
  # generated), jamais laissé en 'none' (refus mécanique du standard).
  plan: cc0   # valable UNIQUEMENT si aucun asset audio n'est ratifié ; à revoir sinon

# =====================================================================================
# DESCRIPTEUR DE PREUVE — contrat docs/forge/CONTRAT_PREUVE_MUTATION_V1.md (FIGÉ).
# =====================================================================================
proof:
  schema_version: 1
  runtime: godot

  mutation:
    # Catégories à confirmer contre la wiremap RÉELLE une fois posée (règle de forme 4 du
    # contrat : une catégorie ni jugée ni exclue est un BLOCKED). Valeurs ci-dessous sont
    # une PROPOSITION calquée sur Snake, à vérifier catégorie par catégorie au moment du gel
    # de wiremap — ne pas les copier aveuglément si la wiremap réelle diffère.
    categories_mutables: [system]
    categories_exclues:
      - system.adapter        # rendu/runtime -> oracle produit, pas mutation (même règle que Snake)
      - test.unit
      - test.oracle
      - godot.project_root
      - godot.project_tests

    command: ["<bin:godot>", "--headless", "--path", ".", "--script", "res://tests/run_tests.gd"]
    cwd: "games/breakout"
    binary_ref: godot
    expects_exit_zero: true

    budget:
      # NON CALIBRÉ — Snake avait mesuré 64 mutants réels à 0,27 s/exécution avant de fixer
      # ces marges. Breakout n'a AUCUNE mesure équivalente : ces valeurs sont un point de
      # départ [H], PAS une valeur ratifiée. À recalibrer sur mesure réelle avant s9, pas
      # après un premier dépassement silencieux.
      max_mutants: 200          # A_CALIBRER — repris de Snake sans mesure Breakout
      timeout_per_mutant_s: 30  # A_CALIBRER
      total_timeout_s: 900      # A_CALIBRER
      cost_class: engine

    seals:
      wrapper: []
      test_scripts: ["tests/run_tests.gd"]

  solvability:
    entry: "solvability.gd"
    # max_ticks : Snake avait mesuré une PARTIE GAGNÉE entre 266 et 417 ticks, et découvert
    # que la valeur par défaut historique (200) produisait un FAUX NÉGATIF (0/50). Breakout
    # n'a AUCUNE mesure équivalente : la valeur ci-dessous est un point de départ large [H],
    # à ne jamais présenter comme calibrée avant une mesure réelle sur le bot d'interception
    # défini en §3.
    max_ticks: 10000            # A_CALIBRER — pas de mesure Breakout, marge large volontaire
    trials: 50                  # repris de Snake par cohérence de méthode, pas par mesure
    trial_timeout_ms: 60000
```

---

## 6. Ce que cette campagne ne prouve PAS

- **E7 (comparaison de builders, Opus vs Qwen Coder) reste découplée de cette campagne.** Le run
  1 ici décrit n'a qu'une seule configuration (Opus, routage actuel) ; E7 exige au moins deux
  exécutions comparées sur la même cible, ratifié dans `MASTER_SCHEMA_TRUTH_AUDIT_2026-07-30.md`
  §6.3. Rien dans ce charter ne prépare ou n'anticipe cette comparaison.
- **Une mesure de fabrication « from scratch » non assistée par lecture d'une solution
  existante.** La décision de contamination (§1, héritée du prep doc §3 option a) place
  explicitement cette campagne hors de cette prétention : `games/breakout/` reste lisible par le
  builder. Une mesure « from scratch » propre exigerait une cible vierge ou un mécanisme
  d'exclusion de lecture qui n'existe pas aujourd'hui dans l'outillage.
- **La validité de la Genre Bible esquissée en §4** — non sourcée HTTP, explicitement marquée
  non ratifiable, gabarit de forme uniquement.
- **Les valeurs chiffrées de `parametres_de_design` et du budget de mutation/solvabilité**, qui
  sont toutes marquées `A_EQUILIBRER` ou `A_CALIBRER` faute de mesure réelle sur ce jeu — à la
  différence de Snake, dont plusieurs valeurs (grille, vitesse initiale) portaient une provenance
  `SOURCE_PIERRE_DIRECTE` ou `RATIFIE_PIERRE`. Aucune valeur de ce charter n'a ce statut.

---

## Paramètres de design chiffrés (valeur initiale proposée + provenance + statut)

Champ structuré, jamais un commentaire, même discipline que Snake — mais ici, à la différence de
Snake, **aucune valeur n'est `SOURCE_PIERRE_DIRECTE`** : ce charter n'a pas encore reçu
d'arbitrage chiffré de Pierre. Toutes les valeurs sont `A_EQUILIBRER`, proposées par le
rédacteur de ce contrat, non sourcées HTTP (World Scan non fait, §0/§4).

```yaml
parametres_de_design:
  terrain:
    valeur_initiale: "640 x 480 unités logiques"
    provenance: "PROPOSITION_REDACTEUR — résolution de travail générique, non sourcée HTTP, aucune mesure de genre consultée. À confirmer ou remplacer au World Scan / s4."
    statut: A_EQUILIBRER
  raquette_largeur:
    valeur_initiale: "80 unités (1/8 de la largeur du terrain)"
    provenance: "PROPOSITION_REDACTEUR — ratio arbitraire pour rendre l'angle de rebond observable sur 3 points d'échantillon distincts (critère PHYSIQUE DE REBOND)."
    statut: A_EQUILIBRER
  raquette_vitesse_max:
    valeur_initiale: "600 unités/seconde"
    provenance: "PROPOSITION_REDACTEUR — non chiffré par une source, choisi pour rendre le bot d'interception (§3) capable de suivre une balle à vitesse initiale proposée ci-dessous sans plafond trivialement franchissable."
    statut: A_EQUILIBRER
  balle_vitesse_initiale:
    valeur_initiale: "300 unités/seconde, constante sur toute la partie (pas d'accélération en V1)"
    provenance: "PROPOSITION_REDACTEUR. Périmètre minimal (prep doc §4) ne mentionne pas d'accélération progressive — à la différence de Snake, où Pierre l'avait explicitement demandée (D3) ; ici, absence par défaut faute de décision équivalente."
    statut: A_EQUILIBRER
  tick_dt_fixed_ms:
    valeur_initiale: "16 ms (~62,5 Hz), pas de temps FIXE de la simulation physique pure"
    provenance: "PROPOSITION_REDACTEUR — convention généraliste de simulation à pas fixe, non sourcée HTTP. C'est le paramètre le plus critique du charter (§3, point dur) : sa valeur exacte importe moins que le fait qu'il soit FIXE et nommé."
    statut: A_EQUILIBRER
  angle_rebond_max_deg:
    valeur_initiale: "60 degrés de déviation maximale par rapport à la verticale, aux bords de la raquette"
    provenance: "PROPOSITION_REDACTEUR — convention connue du genre (Arkanoid-like), non vérifiée par World Scan HTTP à ce stade."
    statut: A_EQUILIBRER
  grille_briques:
    valeur_initiale: "6 rangées x 10 colonnes = 60 briques cassables au niveau 1"
    provenance: "PROPOSITION_REDACTEUR — non sourcée HTTP. Le charter web 2026-07-11 ne chiffrait pas la grille. À vérifier/remplacer au World Scan."
    statut: A_EQUILIBRER
  vies_initiales:
    valeur_initiale: "3 vies"
    provenance: "PROPOSITION_REDACTEUR — convention généraliste du genre, non chiffrée par une source HTTP consultée à ce stade."
    statut: A_EQUILIBRER
  seed_reference:
    valeur_initiale: "breakout-ref-01 (chaîne de seed de travail, à fixer précisément au s4)"
    provenance: "PROPOSITION_REDACTEUR — aucune seed de référence n'existe encore, contrairement à Snake où la seed de solvabilité était déjà en usage au moment du charter."
    statut: A_EQUILIBRER
```

---

## `revisions`

```yaml
revisions:
  - version: 1
    date: "2026-07-30"
    resume: >-
      Charter initial (s0 neuf, PAS une révision du charter web breakout-20260711).
      Aucune valeur chiffrée n'a de statut RATIFIE_PIERRE — toutes A_EQUILIBRER. Deux
      questions ouvertes explicites en question_ouverte_humangate : statut de core.audio
      et périmètre multi-niveaux. Genre Bible esquissée marquée NON RATIFIABLE en l'absence
      de World Scan sourcé.
```

---

## `provenance`

```yaml
provenance:
  reference_jeu:
    valeur: "Breakout, casse-briques d'arcade solo"
    source: "Cadrage Pierre 2026-07-30 (« créer une vraie campagne Forge V2 [pour] Breakout ») + règles produit du charter web lab/forge_runs/breakout/charter.yaml (2026-07-11, source produit uniquement)."
    type: SOURCE_PIERRE_DIRECTE
    fog_humangate: false
  plateforme_cible:
    valeur: "Moteur Godot 4.x, application de bureau hors-ligne"
    source: "Cadrage de campagne (§0) — reconduit du choix Godot déjà exercé par Pierre sur Snake le 2026-07-28, sans nouvelle discussion explicite pour Breakout à ce jour."
    type: DECISION_DE_CADRAGE_TRACEE
    fog_humangate: false
  perimetre_produit_minimal:
    valeur: "Un niveau, physique de rebond réelle, disposition seedée, victoire/défaite mutuellement exclusives"
    source: "docs/forge/BREAKOUT_V2_CAMPAIGN_PREP.md §4, préparation validée cette nuit, consommée sans redouble."
    type: DECISION_DE_CADRAGE_TRACEE
    fog_humangate: false
  parametres_chiffres:
    valeur: "8 paramètres, tous A_EQUILIBRER"
    source: "Aucune — proposition du rédacteur de ce contrat, non sourcée HTTP, aucun World Scan conduit."
    type: PROPOSITION_REDACTEUR
    fog_humangate: true
  genre_bible_esquisse:
    valeur: "10 genre_rules, gabarit de forme"
    source: "Connaissance générale du genre + charter web 2026-07-11 ; aucune source HTTP consultée."
    type: TRACE_INDIRECTE
    fog_humangate: true
```

---

## `question_ouverte_humangate`

```yaml
question_ouverte_humangate:
  - sujet: "Statut de core.audio (exigence CORE non contournable)"
    etat: >-
      Précédent EXACT et mesuré sur Snake : core.audio laissé DEFERRED, decider: pierre,
      jamais retiré ni déclaré NOT_APPLICABLE (games/snake/09_WIREMAP/wiremap.json). Ce
      charter Breakout hérite du même conflit non résolu : core_requirements.yaml impose
      un retour sonore (proof_kind artifact, not_applicable_allowed: false) ; hors_scope
      de ce charter mentionne l'audio comme NON TRANCHÉ, pas comme exclu.
    question_a_pierre: >-
      Ratifies-tu un adaptateur audio minimal pour Breakout (même patron que
      games/pong/06_RUNTIME/adapters/presentation/audio.mjs, porté en concept Godot), ou
      préfères-tu que la ligne CORE reste DEFERRED jusqu'à l'arbitrage explicite avant
      build — comme pour Snake ?
  - sujet: "Périmètre multi-niveaux"
    etat: >-
      Le charter web 2026-07-11 mentionnait une progression multi-niveaux (victoire au
      dernier niveau). Le périmètre minimal proposé ici (prep doc §4, repris tel quel) se
      limite à UN SEUL niveau pour la première boucle complète."
    question_a_pierre: >-
      Confirmes-tu le périmètre à un seul niveau pour ce run 1, la progression
      multi-niveaux étant reportée à une révision ultérieure du charter ?
  - sujet: "Valeurs chiffrées non sourcées (terrain, grille de briques, vies, angle max)"
    etat: >-
      Toutes proposées par le rédacteur de ce contrat, non vérifiées par World Scan HTTP,
      statut A_EQUILIBRER — le charter n'a donc aucun champ en suspens, mais aucune valeur
      n'a le statut RATIFIE_PIERRE dont Snake bénéficiait pour sa grille et sa vitesse
      initiale.
    question_a_pierre: >-
      Ces valeurs de départ te conviennent-elles pour le premier build (conçues pour être
      ajustées au playtest sans toucher la logique), ou souhaites-tu un World Scan sourcé
      avant de les figer — sachant que cela retarderait le début de la campagne ?
```
