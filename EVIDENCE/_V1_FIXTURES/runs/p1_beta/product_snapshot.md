# product_snapshot — p1_beta (« forge de lumière »)

*Prisme Produit · étape 1 · run p1_beta-20260830-run1. Ancres : `charter.yaml` (étape 0), `artifacts/s2-worldscan.txt` (s2), `artifacts/s2.6-story-bible.txt` (s2.6), `artifacts/s2.7-gm-worldscan.txt` (s2.7). Le produit fini décrit ci-dessous est un incremental/clicker web où le joueur attise un foyer de lumière jusqu'à un embrasement terminal, puis ascensionne — une boucle FINIE et cloturable, déviation assumée du genre perpétuel (règle de cohérence `story_bible:coherence_rules`).*

## 1. CE QUE LE JOUEUR VOIT

Un écran unique, sombre — un champ cosmique indigo — dominé au centre par **un seul foyer chaud émissif** qui pulse lentement au repos. C'est la seule source chaude et animée : l'œil y va d'emblée, rien d'autre à l'écran ne lui dispute la chaleur. Autour du foyer, des emplacements froids attendent : des **émetteurs** encore verrouillés apparaissent comme des glyphes désaturés, sans halo, chacun portant en clair sa condition (« X lumière requise »).

En haut, **le compteur de lumière** : le plus gros élément textuel de l'écran, chiffres à chasse tabulaire, toujours au-dessus des effets, jamais recouvert par un flash. C'est le score, la progression, la monnaie — tout à la fois. À côté, un **objectif affiché** qui nomme la prochaine cible du joueur (d'abord acheter le premier émetteur, puis en acheter d'autres, puis atteindre l'embrasement à 5000 lumière). Un **bouton d'achat** indique le coût courant d'un émetteur : liseré or quand c'est abordable, désaturé sinon.

À mesure que la lumière monte, une **constellation/jauge froide** se remplit vers le seuil terminal et **le fond noir se réchauffe** globalement, virant de l'indigo vers un violet chaud. Au franchissement de 5000, un **écran d'embrasement** blanc-chaud plein écran s'affiche, portant le libellé « Embrasement complet ». Puis apparaît un **autel d'ascension**, zone froide-dorée distincte, qui propose de tout rallumer plus fort.

## 2. CE QUE LE JOUEUR FAIT

Il **attise le foyer** en le cliquant : chaque clic émet une gerbe d'éclats chauds et fait monter le compteur d'exactement +1 lumière. C'est l'action-cœur, immédiate et répétable. Quand il a assez de lumière, il **achète un émetteur** au bouton d'achat : le coût est retiré du compteur et un nouvel émetteur froid **apparaît physiquement** autour du foyer, démarrant un filet de lumière passive. Le coût du suivant a monté (croissance géométrique ×1,18), ce qui rythme les achats.

À chaque instant il **arbitre** : continuer à attiser à la main, ou réinvestir dans la production passive — deux politiques qui mènent à des quantités de lumière mesurablement différentes sur un même horizon. Il **rejoue** cette séquence (attiser → achat → nouvel émetteur) dans un état à chaque fois plus coûteux, poussant la constellation vers son remplissage. Une fois l'embrasement atteint, il **ascensionne** : la lumière accumulée retombe à zéro, un glow d'ascension permanent est crédité, et **le même attisage rapporte désormais strictement plus qu'avant** — la partie suivante démarre avec un avantage prouvé, pas promis.

## 3. CE QUE LE JOUEUR RESSENT

Au premier clic, **la certitude que son geste compte** : le foyer réagit, le chiffre bouge, exactement d'une unité — un gain comptable, lisible, jamais douteux. Puis, au premier émetteur, **le basculement du faire-soi-même vers le regarder-croître** : un objet neuf est apparu à l'écran, la lumière avance seule ; ce n'est pas un chiffre qui accélère abstraitement, c'est un monde qui se peuple. La montée de chaleur du fond donne une **lecture périphérique de l'avancée** — il sait qu'il approche sans quitter le compteur des yeux.

La tension propre au jeu est celle de l'**arbitrage** : cliquer encore (satisfaction immédiate) ou réinvestir (puissance différée). Et surtout, contre l'ennui du genre, **une fin qui vient** : la constellation se remplit vers un climax visuel maximal, l'embrasement, qui dit sans ambiguïté « c'est fini ». L'ascension referme la boucle sur une promesse tenue et vérifiable — **recommencer plus fort** — au lieu d'un idle infini.

## 4. RÈGLES OBSERVABLES

Chaque règle est testable par une sonde déterministe ou une capture, et ancrée dans `gm_worldscan` (game_master). L'ordre suit la boucle jouée : objectif → attiser → réponse → récompense → décision → déblocage → nouvel objectif → rejeu → ascension → avantage, puis les règles produit hors-boucle.

- **R1 — PLAYER_GOAL** : tant que le seuil n'est pas franchi, le HUD `objectif` affiche en continu un objectif de fin explicite nommant l'embrasement à 5000 lumière (chaîne non vide au tick 0). *[gb_constellation]*
- **R2 — PLAYER_ACTION** : le joueur attise le foyer en cliquant la cible `hearth` ; à chaque clic le compteur `lumiere` augmente strictement. *[core_loop.core_action]*
- **R3 — GAME_RESPONSE** : à chaque attisage, l'état visuel du foyer change (flash chaud bref < 200 ms) de façon détectable image à image. *[core_loop.core_feedback]*
- **R4 — REWARD** : chaque attisage crédite exactement +1 lumière (égalité stricte `lumiere == N`, jamais un `>=` qui masquerait un pas mort). *[core_loop.core_reward]*
- **R5 — DECISION** : un point de décision affiché oppose deux affordances distinctes — attiser `hearth` / acheter `buy_button` — dont deux politiques (idle vs actif) produisent, à 300 frames, deux valeurs de `lumiere` distinctes et non triviales. *[core_loop.core_decision]*
- **R6 — UNLOCK** : le joueur achète un émetteur en cliquant `buy_button` quand la lumière suffit ; un nouvel émetteur apparaît dans le groupe `emetteurs` et un producteur passif démarre (> 0). *[gb_emitter]*
- **R7a — NEXT_GOAL** : après le premier émetteur, le HUD `objectif` affiche un énoncé textuellement nouveau (acheter un second émetteur). *[gb_emitter.next_goal]*
- **R7b — NEXT_GOAL** : la production passive active, le HUD `objectif` affiche un énoncé encore différent des deux précédents, nommant le seuil d'embrasement 5000. *[gb_constellation.next_goal]*
- **R8 — REPEAT** : après un achat, la séquence attiser→réponse→récompense→acheter est rejouable dans l'état courant, le coût du prochain émetteur ayant crû (×1,18). *[economy_loop.economy_action]*
- **R9 — META_LOOP** : le joueur ascensionne en cliquant l'autel `ascension_altar` ; la lumière accumulée retombe visiblement à zéro et un glow d'ascension permanent est crédité. *[gb_ascension_altar]*
- **R10 — ADVANTAGE** : après une ascension, un attisage de `hearth` crédite strictement plus de lumière que le même attisage avant l'ascension (delta comparé, seed identique). *[meta_loop.meta_reward]*
- **R11 — État terminal** : au franchissement de 5000 lumière, un écran d'embrasement plein écran porte le libellé texte « Embrasement complet » et l'interaction de jeu est neutralisée. *[gb_end_screen]*
- **R12 — Verrouillage lisible** : tout émetteur non accessible est rendu désaturé, sans halo, avec un libellé de condition visible, et n'est pas cliquable (aucune fausse affordance). *[gb_locked_glyph]*
- **R13 — Compteur toujours lisible** : le compteur de lumière reste le plus gros élément textuel, à chasse tabulaire, dessiné au-dessus des effets et non recouvert, même pendant un flash. *[gb_light_counter]*
- **R14 — Ambiance de progression** : la couleur de fond se réchauffe continûment de l'indigo vers le violet chaud selon `light/5000` (borné à 1), en parallèle du compteur. *[world_loop.world_feedback]*

---

## RAPPORT FINAL — s1-prisme / p1_beta-20260830-run1

**Ancre (charter).** Le charter est un jeu-sonde incremental/clicker à structure déléguée en aval, portant des contraintes dures citables : isolement Cookie Clicker, grammaire de genre uniquement, **état terminal observable et atteignable** (idle infini interdit). Le product_snapshot ci-dessus respecte ces trois contraintes : boucle finie, seuil terminal 5000 signalé texte + visuel, aucune reprise d'asset/valeur Cookie Clicker.

**Reçu oracle `check_prisme_manifest`.** Oracle déterministe non-LLM **non exécuté par ce worker** (`permissions.run: aucun` — l'exécuteur `run_real.py` le relance et le re-vérifie). Conformité construite **par inspection** du contrat : chaîne `observation → claim → enonce` aux trois maillons DIFFÉRENTS pour chaque exigence ; `source: EXPECTED` avec `reference` = adresse `gm_worldscan:` résolvable ; couverture **1 exigence par rôle** (10 rôles de boucle) + règles par maillon G(×2 new_distinct/objectif), F(observe.appears sur R6), H(replay R2/R3/R4/R6), I(reset visible sur R9), J(increases_more_than:R2 sur R10), DECISION(R5 : 2 options distinctes hearth/buy_button, 2 policies idle/actif, metric `lumiere` déjà observée, horizon 300). Sourçage GM (Lot B/T3) : **11/11 exigences de boucle** citent une adresse `gm_worldscan:game_master.loops.*` ou `grey_blocks.*` — au-dessus de la baseline mesurée run 9 (0/13).

**Exigences classées / références non ancrées.** Aucune exigence n'est laissée sans preuve attendue exploitable (toutes portent `expected_proof.kind ∈ {bot_action, visual, oracle}`). Les 14 références sont des adresses gm/loops confirmées présentes dans `s2.7-gm-worldscan.txt` ; j'ai **volontairement évité** `gb_quest_milestone` (annoncé ajouté en round 2 par le GM dans `design_questions.json` mais non visible dans l'artefact gm fourni — référence non vérifiable de mon poste). Si `check_amont_traversal.mjs` ne résout pas une adresse `.loops.<loop>.<step_id>` (steps est un tableau indexé par `id`), elle sera reportée comme non résolue — limite du format d'adresse imposé par le contrat, hors de mon contrôle.

**Verdicts.**
software_verdict: OK — appuyé par l'ancre non-LLM `gm_worldscan` (adresses citées verbatim) et `charter.yaml` (contraintes terminal/isolement respectées) ; livrable produit et conforme au schéma par inspection.
evidence_verdict: MECHANICAL_VALIDATION_ONLY
claim_verdict: NO_CLAIM_ALLOWED — je n'ai **pas** exécuté `check_prisme_manifest` ni `check_prisme.mjs` (run: aucun) ; « le manifeste passe l'oracle » est un jugement à la charge de l'exécuteur/HumanGate. **fog → Pierre** : (1) confirmer que la matérialisation + les deux oracles rendent `passed:true` ; (2) valider que la résolution des adresses `.loops.<loop>.<step_id>` fonctionne bien sur un `steps[]` indexé par `id`.

**SKIPPED_VALIDATION**
- item : exécution de `check_prisme_manifest.mjs` et `check_prisme.mjs` · périmètre : ce manifeste et cette prose · statut : **non fait** · raison : `permissions.run: aucun` — oracles relancés par l'exécuteur, jamais par ce worker.
- item : résolution effective des adresses `gm_worldscan:` · périmètre : les 14 `reference` · statut : **non fait** · raison : nécessite l'exécution de `check_amont_traversal.mjs` (hors de mes permissions) ; conformité vérifiée par inspection du contrat uniquement.
- item : présence de `gb_quest_milestone` dans le gm_worldscan matérialisé · périmètre : sourçage NEXT_GOAL · statut : **contourné** · raison : référence non visible dans l'artefact fourni ; NEXT_GOAL ré-ancré sur `gb_emitter` et `gb_constellation`, confirmés présents.

**RETURN LINEAGE**
- why_task_existed : { problem: « le run full_content p1_beta doit capturer la vision produit finie (voit/fait/ressent + règles observables) et matérialiser une boucle joueur complète A→J en exigences falsifiables » · oracle : `check_prisme_manifest.mjs` (chaîne observation→claim→exigence→preuve→destination) et `check_prisme.mjs` (conformité markdown 4 sections) · root_cause : activation par la chaîne d'étapes Forge (s0→s2.7 produits, s1-prisme dispatché) — pas un défaut · action_reason : produire product_snapshot.md + prisme.json conformes, dérivés des ancres amont, sans invention }
- result : product_snapshot.md (4 sections, 14 règles observables numérotées R1..R14) + bloc prisme.json (14 exigences, 11 de boucle sourcées GM 11/11, couverture des 10 rôles + règles par maillon) — produits, conformes par inspection.
- proof : lecture des artefacts amont (`s2-worldscan.txt`, `s2.6-story-bible.txt`, `s2.7-gm-worldscan.txt`, `charter.yaml`, `design_questions.json`) ; construction du manifeste contre le contrat SCHEMA. Aucune commande exécutée (run: aucun) — preuve d'exécution déléguée à l'exécuteur.
- learning : le format d'adresse GM `.loops.<loop>.<step_id>` porte un risque de non-résolution si le résolveur n'indexe pas `steps[]` par `id` ; à surveiller au premier reçu réel de `check_amont_traversal`.
- next_reason : la chaîne se poursuit normalement vers s3-decompo (l'exécuteur matérialise + vérifie les oracles) ; escalade HumanGate seulement si un oracle rend FAIL ou si des adresses ne résolvent pas.
