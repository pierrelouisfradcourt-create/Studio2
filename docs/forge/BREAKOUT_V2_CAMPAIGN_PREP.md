# Préparation de la campagne Breakout — Forge V2 observable

Date : 2026-07-30. Auteur : session Fable 5 (poste de commande), sous-agent Sonnet pour la
collecte de faits. Statut : **PROPOSED** — checklist et arbitrages soumis à HumanGate Pierre,
aucune écriture hors ce fichier.

Décision d'origine : *« la prochaine campagne Forge V2 est Breakout — construit avec la Forge V2
depuis zéro sous le profil `standard_godot`, via le driver instrumenté »* (Pierre, 2026-07-30,
soir).

**Tension à signaler explicitement avant tout le reste** : `docs/forge/MASTER_SCHEMA_TRUTH_AUDIT_2026-07-30.md`
§6.1-6.4, daté du même jour mais visiblement plus tôt (« Ratifié Pierre 2026-07-30 »), documente
une décision antérieure qui **écarte Breakout** comme cible E7 (« non par contamination, mais
parce que la décision est de repartir sur un jeu neuf ») et pose comme critère de cible
« absente de `games/` ». La décision « soir » transmise pour cette mission **réintroduit Breakout
explicitement**, alors que `games/breakout/` existe déjà (15 fichiers, voir §2.1) — donc **ne
respecte pas le critère « absente de games/ » posé quelques heures plus tôt**. Ce document
n'arbitre pas entre les deux décisions : il **assume la décision la plus récente** transmise
(Breakout) et traite honnêtement la conséquence que l'audit avait justement voulu éviter — la
contamination possible (§3). Le HumanGate doit trancher explicitement laquelle des deux
décisions du 2026-07-30 fait foi avant le run 1. [M]

---

## 1. Objectif de campagne

Faire de Breakout le **premier jeu construit intégralement sous Forge V2 observable** :
provenance complète (charter → wiremap → build → oracles → verdict signé), `state.json` +
`verdict.json` du driver instrumenté à chaque run, et alimentation de la boucle d'apprentissage
(`knowledge_base/learning_curve.jsonl`). Cette campagne sert de **référence pré-E7** — la mesure
de coût/durée/itérations sur la configuration actuelle (Opus) qui servira de point de comparaison
quand la doctrine de routage V2 (`docs/forge/INFERENCE_ORCHESTRATOR_V2_PROPOSAL.md`) sera
mesurée sur `game_forger` face à Qwen Coder. **Le run 1 de cette campagne n'est pas encore E7** —
il n'a qu'une seule configuration ; E7 exige au moins deux exécutions comparées (Opus vs Qwen
Coder), ratifié dans l'audit §6.3. [M]

---

## 2. Pré-requis bloquants

Checklist vérifiée contre l'état réel du dépôt au 2026-07-30, chemin par chemin. Rien de cette
section n'est une intention — chaque ligne cite ce qui existe ou n'existe pas.

### 2.1 Charter Godot — DEUX options, choix HumanGate

État vérifié :
- `lab/forge_runs/breakout/charter.yaml` **existe** (`run_id: breakout-20260711`, 2026-07-11) —
  mais c'est un charter **navigateur** : `plateforme_cible` = « HTML5 canvas + JavaScript
  vanilla », `hors_scope` exclut explicitement « portage moteur » (pas Godot). Aucun `state.json`
  ni `verdict.json` associé dans `lab/forge_runs/breakout/` — confirmé par
  `MASTER_SCHEMA_TRUTH_AUDIT_2026-07-30.md` §6.1 : cet essai n'est jamais passé par le driver
  instrumenté, donc **hors protocole Forge** au sens de la doctrine ratifiée le même jour.
- Aucun `charter.yaml` visant Godot n'existe pour Breakout.

**Option A — s0 neuf.** Relancer l'étape 0 (contrat) sur Breakout avec `plateforme_cible: Godot`,
en s'inspirant du gabarit le plus récent et le plus complet du studio :
`lab/forge_runs/snake/charter.yaml` v2 (paramètres isolés en champ structuré `parametres_de_design`,
`provenance` par champ, `revisions` versionnées, `question_ouverte_humangate` — voir §7 pour le
risque physique-continue spécifique à Breakout que Snake, sur grille discrète, n'avait pas à
couvrir).

**Option B — adaptation ratifiée du charter web 2026-07-11.** Réviser
`lab/forge_runs/breakout/charter.yaml` en v2 Godot (même mécanique que la révision v1→v2 de
Snake) : `plateforme_cible` bascule vers Godot, `hors_scope` inverse la clause portage-moteur,
`criteres_succes` sont retranspostés en équivalents moteur (comme `s9-build-godot-standard.yaml`
l'a fait pour la clause « API DOM » → « API moteur Godot » de Snake). Avantage : conserve la
provenance déjà tracée (objectif produit, pré-mortem PILOU cité dans le charter d'origine) plutôt
que de la reconstruire. Risque propre à cette option : réviser un charter qui décrivait une cible
JS en gardant son texte source à portée immédiate est la même situation de contamination
documentaire que celle décrite en §3 — le rédacteur du charter lira `lab/forge_runs/breakout/`
en le révisant, ce qui est **différent** du risque §3 (celui-là touche le builder du code, pas le
rédacteur d'intention) mais mérite d'être nommé.

**Recommandation [H] :** Option A (s0 neuf) est plus propre au regard de la leçon d'audit
elle-même (« repartir sur un jeu neuf construit depuis zéro ») ; Option B est plus rapide et
réutilise un travail de cadrage produit humain (product_snapshot.md, redteam_plan.md existent déjà
— voir §2.1bis). **Choix HumanGate**, pas tranché ici.

### 2.1bis Artefacts de design 2026-07-11 déjà présents (à consommer, pas à recréer)

`lab/forge_runs/breakout/` contient : `blueprint.yaml`, `decompo.md`, `product_snapshot.md`,
`redteam_plan.md`, `worldscan.json`, `wiremap.json`, `wiremap_frozen.json` (tous du run
`breakout-20260711`, navigateur). Que l'option A ou B soit retenue, ces artefacts sont une source
d'intention produit consultable (le fond du jeu — balle, raquette, briques, niveaux seedés — ne
change pas avec le moteur), mais la `wiremap.json` existante est **JS/DOM et inutilisable telle
quelle** pour Godot : elle doit être régénérée (§2.3), pas réutilisée.

### 2.2 Genre Bible Breakout — n'existe pas

État vérifié : `docs/forge/GENRE_BIBLE_SNAKE_V1_PROPOSED.md` (.md, RATIFIÉE) et
`games/snake/01_DESIGN/genre_bible.json` (JSON mécanique, 12 `genre_rules`, consommé par
`check_genre_coverage`) existent pour Snake. **Aucun équivalent Breakout n'existe** —
`docs/forge/GENRE_BIBLE_PONG_V1_PROPOSED.md` existe pour Pong, mais rien pour Breakout. Gabarit
Snake à répliquer : world scan sourcé (références historiques du genre casse-briques — Breakout
Atari 1976, Arkanoid comme référence d'angle de rebond selon point d'impact, déjà cité en germe
dans le charter web 2026-07-11 ligne 9-22) compressé en règles JSON citables par id, plus la
version `.md` narrative. **Bloquant avant wiremap** : `check_genre_coverage` (comme pour Snake)
exige des `genre_refs[]` résolus contre ce bloc JSON.

### 2.3 Contrat `wm1-wiremap-breakout` — n'existe pas, calqué sur `wm1-wiremap-snake`

État vérifié : `scripts/forge/contracts/wm1-wiremap-snake.yaml` existe (mission M-G, rôle
`wiremap`, produit `lab/forge_runs/snake/wiremap.json` schéma v2 : `systems[]` / `lines[]` /
`discarded[]`, chaque ligne typée `reused_from {type: CODE|CONCEPT|NEW}`, `observable_by_player`
booléen strict, `genre_refs[]` résolus). Le régime STANDARD (`s9 → s10a → s10s → s11 → s12`) n'a
**pas d'étape wiremap native** — Snake y a répondu par un contrat ad hoc hors profil
(`allow_unprofiled` assumé, cf. en-tête du contrat). **À répliquer à l'identique pour Breakout** :
`wm1-wiremap-breakout.yaml`, même schéma, mêmes gardes (§ garde-fou 3 : `reused_from.source`
pointe un chemin réel vérifié — **c'est le point d'attention direct pour la contamination**, voir
§3 : si le rédacteur de cette wiremap type une ligne `CODE:games/breakout/game.mjs`, c'est une
réutilisation JS→GDScript qui n'a pas de sens mécanique — la garde-fou existante empêcherait au
moins un `CODE_COPIE` halluciné, mais pas un `CONCEPT:games/breakout/game.mjs` légitimement
inspiré du JS existant).

### 2.4 `game_contract.yaml` (budget) — n'existe pas

État vérifié : `games/snake/00_CHARTER/game_contract.yaml` et `games/pong/00_CHARTER/game_contract.yaml`
existent ; aucun `games/breakout/00_CHARTER/` n'existe (le dossier `games/breakout/` actuel est
plat, sans arborescence `00_CHARTER/01_DESIGN/09_WIREMAP/` — c'est une structure d'un régime
antérieur, pas le squelette standard). Gabarit à suivre : `reuses: []` / `adds: []` par défaut
(budget conservateur, comme Snake — « pas d'extension d'infrastructure » tant qu'aucune brique
Godot validée en bibliothèque tier `validated` n'existe pour la physique de rebond continue), plus
un bloc `proof:` conforme à `docs/forge/CONTRAT_PREUVE_MUTATION_V1.md` (catégories mutables/exclues
par catégorie structurée, jamais par extension — Snake exclut `system.adapter`,
`godot.project_root`, `godot.project_tests` de la mutation).

### 2.5 Décision contamination — voir §3, bloquante avant run 1

### Récapitulatif pré-requis

| pré-requis | état réel | bloquant avant |
|---|---|---|
| Charter Godot Breakout | **N'existe pas** — 2 options en §2.1 | s0/s4 |
| Genre Bible Breakout (.md + .json) | **N'existe pas** | wiremap (s5-équivalent) |
| Contrat `wm1-wiremap-breakout.yaml` | **N'existe pas** | wiremap |
| `game_contract.yaml` budget | **N'existe pas** | s9 (build) — la garde mutation (`proof:`) le lit |
| Décision contamination | **Non tranchée** | run 1 |
| Squelette `standard_godot` (capabilities/core_requirements/repo_map) | **Existe**, gelé, `scripts/forge/standard/` | rien — déjà prêt |
| Contrat `s9-build-godot-standard.yaml` | **Existe**, statut PROPOSED | s9 |

---

## 3. Protocole contamination

**Fait vérifié, pas une hypothèse :** `scripts/forge/contracts/s9-build-godot-standard.yaml`
déclare `permissions: read: dépôt entier`. `games/breakout/` (15 fichiers : `game.mjs`,
`logic.test.mjs`, `properties.test.mjs`, `solvability.mjs`, `run-oracle.mjs`, `render.mjs`,
`input.mjs`, `level.mjs`, `server.mjs`, `e2e.mjs`, `mutation_triage.json`, screenshots) est une
implémentation **complète et déjà verte** (tests unitaires, e2e Playwright, solvabilité, mutation
triée) de exactement le jeu visé. Un `game_forger` lançé sur la cible Godot **peut lire cette
implémentation** avant ou pendant l'écriture du code Godot.

**Vérification faite : `games/breakout/**` n'est PAS dans la liste protégée du seul mécanisme de
détection existant.** `scripts/forge/reference_protected.yaml` couvre `games/pong/**` (témoin de
régression), `tests/**`, `scripts/forge/**`, `control_plane/registry.py`, `.claude/hooks/**`,
`CLAUDE.md` — **pas `games/breakout/**`**. Et ce mécanisme (`scripts/forge/reference_guard.py`)
est de toute façon un détecteur de **modification** (empreinte disque avant/après), pas un
mécanisme d'exclusion de **lecture** : même ajouté à la liste protégée, il ne changerait rien à la
capacité du builder à *lire* `games/breakout/` — il ne ferait qu'alerter si le builder l'avait
*modifié*, ce qui n'est pas le geste attendu ici.

**Trois options, arbitrage Pierre :**

**(a) Assumer la contamination possible et l'ACTER.** La campagne mesure la **fabrication Forge
V2 observable** (provenance, gates, driver instrumenté, verdict signé) — PAS une mesure E7
propre de `game_forger` from-scratch. Si E7 (Opus vs Qwen Coder) doit un jour comparer une
capacité de fabrication non assistée par lecture d'une solution existante, **il lui faudra une
autre cible vierge**, ou un mécanisme d'exclusion de lecture qui n'existe pas aujourd'hui (ajout à
`reference_protected.yaml` ne suffit pas, voir ci-dessus — il faudrait un filtre au niveau outil,
absent). Coût : zéro changement d'arbre, zéro risque de casser autre chose. Perte : cette campagne
Breakout ne peut PAS servir telle quelle de baseline E7 « from scratch » — seulement de baseline
« Forge V2 observable, tel que le studio l'opère réellement aujourd'hui, lecture du dépôt
comprise ».

**(b) Déplacer temporairement `games/breakout/` + `lab/forge_runs/breakout/` hors dépôt pendant
les runs.** Rend la lecture impossible par construction (le fichier n'existe plus dans l'arbre
pendant l'exécution), au prix de modifier l'arbre pendant la mesure elle-même — contraire à la
discipline « garde CLEAN avant/pendant/après un run » que le studio applique déjà avec
`reference_guard.py` pour Pong. Risque opérationnel : oubli de restauration, ou un test/outil
studio qui référence `games/breakout/` en arrière-plan (aucun grep de dépendance croisée fait ici
— à faire avant d'exercer cette option). Coût en propreté explicite et non négligeable.

**(c) `actions_interdites` déclaratives dans le charter/contrat (« ne pas lire
`games/breakout/` »).** Confirmé **faible** : c'est la même nature de garde que celle déjà jugée
insuffisante dans l'audit du 2026-07-30 (« une interdiction posée en `actions_interdites` est
déclarative, non applicable — c'est un commentaire, pas une garde », §6.2). Le hook
`pretool_forge_guard` bloque le *dispatch sans contrat*, pas la *lecture d'un chemin précis dans
un contrat validé* — aucun mécanisme ne vérifie mécaniquement qu'un agent n'a pas ouvert
`games/breakout/game.mjs`.

**Recommandation [H] : (a).** Rationale : (b) coûte une opération risquée pour un bénéfice
mesuré nul tant qu'aucun mécanisme d'exclusion de lecture n'existe côté outillage — même arbre
vidé, rien n'empêche un `game_forger` de connaître Breakout de son entraînement général (LLM),
donc (b) ferme une seule des deux fuites possibles et donne un faux sentiment d'étanchéité. (c)
est déjà démontrée inopérante. (a) est la seule option honnête : elle **découple explicitement**
cette campagne de la mesure E7 « from scratch », et laisse E7 exiger sa propre cible vierge (ou
un futur mécanisme d'exclusion, hors périmètre de cette préparation) quand le moment viendra. Le
gain de cette campagne reste réel et non négligeable : c'est la première fois que la chaîne
`standard_godot` complète (s9→s10a→s10s→s11→s12) tourne sous driver instrumenté avec provenance,
indépendamment de la question E7.

---

## 4. Périmètre produit minimal

Réduit depuis l'objectif du charter web 2026-07-11 (`lab/forge_runs/breakout/charter.yaml`
lignes 9-22) à la boucle complète, strictement :

- Une balle, une raquette contrôlée au clavier.
- Murs de briques à disposition **seedée** (même seed + index de niveau ⇒ même disposition,
  reproductible).
- Physique de rebond réelle : murs latéraux/plafond (inversion de composante de vitesse),
  raquette avec **angle de rebond fonction du point d'impact**, brique détruite au contact avec
  rebond correspondant.
- Conditions de fin explicites et mutuellement exclusives : **VICTOIRE** (briques cassables
  restantes == 0, avec progression multi-niveaux si retenue) et **DÉFAITE** (vies épuisées).
- Logique pure séparée du rendu/entrée (aucune référence Node Godot dans la logique — même
  discipline que `s9-build-godot-standard.yaml` exige pour Snake : pas de `get_node`, `Input`,
  `_draw`, `_process`, `Timer`, `OS`/`Time`, aléa non seedé).
- Déterminisme prouvé par replay (comme Snake §critère DETERMINISME PROUVE PAR REPLAY).
- Solvabilité prouvée par un bot qui **intercepte réellement la balle** (pas seulement un test
  mécanique isolé — voir §7, c'est le point dur spécifique à Breakout).

**Hors scope confirmé** (repris du charter web, cohérent avec la doctrine de cible vierge) :
multijoueur, réseau, classement en ligne, persistance serveur, power-ups/bonus, assets externes,
export/portage (l'export Godot n'est pas requis par la chaîne, comme pour Snake).

---

## 5. Déroulé de campagne

**Phase 0 — pré-vol.**
- Empreinte de référence : si l'option (b) de §3 n'est pas retenue, documenter explicitement
  dans le charter/game_contract que `games/breakout/**` reste présent et lisible (pas de
  garde CLEAN dessus).
- Vérifier `scripts/forge/reference_protected.yaml` : aucun changement requis pour Breakout
  (le témoin protégé reste Pong, `tests/`, le tronc Forge — Breakout n'entre pas dans ce
  périmètre par nature, c'est une cible de fabrication, pas un témoin).
- Poser les 4 artefacts bloquants de §2 (charter Godot, Genre Bible, contrat wiremap,
  game_contract) — chacun avec go HumanGate explicite avant de passer à l'étape suivante,
  comme la chaîne Snake l'a fait (charter v1→v2, panel/review, wiremap gelée avant build).
- Tasks file / suivi de run : même dispositif que les runs de calibration Snake
  (`lab/forge_runs/snake/_run_cal{1,2,3}_20260730/{artifacts,context,evidence}` +
  `state.json` + `verdict.json` à la racine du run).

**Phase 1 — run 1 de référence.** Config actuelle (Opus, routage tel qu'il est aujourd'hui — la
doctrine de routage V2 ratifiée le 2026-07-30 ne change la matrice qu'après mesure sur tâche
réelle, pas avant). Chaîne complète `s9-build-godot-standard → s10a → s10s → s11 → s12` via le
driver instrumenté. Sortie attendue par run : `state.json` (plan vivant, écrit par le driver) +
`verdict.json` signé HMAC, re-vérifiable par `forge.verify_run`.

**Phase 2 — gel des résultats.** Une fois le run 1 clos (vert ou non), figer son évidence
(`lab/forge_runs/breakout/<run_id>/evidence/`) avant tout run 2 — même discipline que la
calibration Snake (3 runs distincts `_run_cal1/2/3_20260730`, chacun isolé).

**Phase 3 — décisions mutation/routing.** Le run 1 seul ne suffit ni à N≥5 (bruit coût/durée,
§6) ni à un comparatif E7 (il faut au moins Opus + Qwen Coder). Il sert de première donnée
d'une série, pas de verdict de routage.

**Critère de campagne Forge (non négociable) :** `state.json` + `verdict.json` signés à chaque
run — l'absence de ces deux fichiers est le signal mécanique, mesuré dans l'audit du
2026-07-30, qui distingue une vraie campagne Forge d'un essai hors protocole (exactement ce
qu'était le run breakout-20260711).

---

## 6. Métriques et seuils

Repris de la calibration N=3 réalisée sur Snake (`lab/forge_runs/snake/_run_cal1/2/3_20260730/`,
bande de bruit établie ~20 %, citée dans `docs/forge/MASTER_SCHEMA_TRUTH_AUDIT_2026-07-30.md`
§ligne 245).

**Métriques discrètes, hors bande de bruit (une seule mesure suffit à affirmer) :**
- build atteint (binaire : le projet Godot compile et s'ouvre).
- 6 oracles du squelette `standard_godot` s10s (`line_states`, `placement`, `collisions`,
  `index`, `contract_completeness`, `budget`) — chacun vert/rouge.
- score de mutation (Godot, `run_tests.gd` en headless, catégorie `system` uniquement — les
  adaptateurs de présentation et de physique-rendu ne sont pas mutés en aveugle, même
  discipline que Snake §`proof.mutation.categories_exclues`).
- solvabilité (binaire : SOLVABLE / INJOUABLE, code retour de l'oracle).
- itérations jusqu'au vert.

**Métriques soumises au bruit ~20 % (N≥5 requis avant toute affirmation) :**
- coût (tokens/appels LLM par run).
- durée (temps mur du run).

**Critère produit non négociable [M]** (leçon Snake ratifiée 2026-07-29, `proof_never_replaces_
product_run.md`) : un projet peut satisfaire tous ses oracles et ne pas démarrer. Le jeu **doit
démarrer et afficher**, vérifié **hors chaîne d'oracles** — capture avec fenêtre GPU réelle
(`--rendering-driver vulkan --position -3000,-3000`), jamais `--headless` qui rend une texture
nulle (fait mesuré 2026-07-22, repris dans le contrat `s9-build-godot-standard.yaml` mémoire et
garde-fou (f)). Le charter Breakout doit déclarer ce point d'entrée comme **invariant vérifié en
ABSENCE comme en présence** (deuxième leçon de clôture Snake, même source).

---

## 7. Risques propres à Breakout

**Physique continue vs grille discrète — LE risque architectural distinctif.** Snake vit sur une
grille 20×20 à ticks discrets : position, collision et mouvement sont des entiers, testables par
égalité stricte trivialement. Breakout est une physique **continue** (position balle en flottant,
vitesse vectorielle, angle de rebond fonction du point d'impact) — le déterminisme (réplication
bit-exacte d'un replay) est **beaucoup plus difficile à garantir** : tout pas de temps non
explicitement fixé (delta-time variable au lieu d'un tick fixe), toute opération flottante
dépendante de l'ordre d'évaluation, casse la reproductibilité. **C'est la surface à geler en
premier**, avant toute autre ligne de wiremap : un pas de simulation fixe et nommé (comme
`periode_plancher_ms` l'est pour Snake), aucune dépendance à `Time`/`OS`/framerate variable dans
la logique pure.

**Solvabilité par bot — nettement plus dure que Snake.** Le bot de Snake suit un chemin sur
grille (BFS/heuristique déjà présent dans `knowledge_base` comme `sys-grid-nav-m01`, tier
`candidate`). Le bot de Breakout doit **intercepter une balle en mouvement continu** — un
problème de contrôle (prédiction de trajectoire + positionnement raquette), pas un problème de
recherche de chemin. Risque concret : un bot « collé au bord » ou « suit toujours la balle en X »
peut sembler gagner par chance sur une seed favorable sans réellement résoudre le jeu — même
piège que la leçon `oracle_solvability_lesson.md` (oracle vert ≠ jeu bon, testé 2× déjà sur
survival_arena et collect_runner). Le charter doit fixer un nombre d'essais minimal (`trials`,
comme `solvability.trials: 50` pour Snake) et une seed de référence documentée, pas un essai
unique chanceux.

**Angle de rebond dépendant du point d'impact — surface à tester par valeurs strictes.** Le
charter web 2026-07-11 l'exige déjà (« angle dépendant du point d'impact »). C'est une fonction
continue (position d'impact → angle), donc les tests de mutation doivent viser des points
d'échantillonnage nommés (centre, bord gauche, bord droit de la raquette) avec assertion stricte,
pas une plage `>=`/`<=` — même interdiction que Snake pour les seuils d'accélération.

**Multi-niveaux si retenus.** Le charter web mentionne une progression multi-niveaux (victoire au
dernier niveau). Le périmètre minimal (§4) peut se limiter à un seul niveau pour la première
boucle complète — arbitrage HumanGate à trancher en s0/s4, pas ici.

---

## Sources citées

- `lab/forge_runs/snake/charter.yaml` (v2, 318 lignes) — gabarit charter le plus récent.
- `scripts/forge/contracts/wm1-wiremap-snake.yaml` — gabarit contrat wiremap ad hoc hors profil.
- `scripts/forge/contracts/s9-build-godot-standard.yaml` (PROPOSED, 2026-07-28) — contrat builder,
  confirme `permissions: read: dépôt entier`.
- `games/snake/00_CHARTER/game_contract.yaml` — gabarit budget/proof.
- `lab/forge_runs/breakout/charter.yaml` (run_id breakout-20260711) — charter web existant.
- `games/breakout/` — 15 fichiers vérifiés (`game.mjs`, `logic.test.mjs`, `properties.test.mjs`,
  `solvability.mjs`, `run-oracle.mjs`, `render.mjs`, `input.mjs`, `level.mjs`, `server.mjs`,
  `e2e.mjs`, `mutation_triage.json`, `e2e-shots/*.png`), aucun `state.json`/`verdict.json`.
- `scripts/forge/reference_protected.yaml` + `scripts/forge/reference_guard.py` — mécanisme de
  détection vérifié : ne couvre pas `games/breakout/**`, et est un détecteur de modification, pas
  d'exclusion de lecture.
- `docs/forge/MASTER_SCHEMA_TRUTH_AUDIT_2026-07-30.md` §6.1-6.4, §244-247 — décision antérieure
  « cible vierge », bande de bruit ~20 % (calibration N=3), critères discret/bruité.
- `knowledge_base/learning_curve.jsonl` — traces calibration Snake (`reuse_ratio`,
  `oracle_iterations`), dernières entrées 2026-07-30.
- `lab/forge_runs/snake/_run_cal1_20260730/` (+ cal2, cal3) — structure de run instrumenté
  (`state.json`, `verdict.json`, `artifacts/`, `context/`, `evidence/`, `rapport_redteam_code.md`).
- Mémoire studio : `proof_never_replaces_product_run.md`, `oracle_solvability_lesson.md`,
  `forge_metric_variance_rule.md`.

Marqueurs : [M] fait mesuré directement dans le dépôt · [H] jugement/recommandation de cette
préparation, à valider HumanGate · [E] mécanisme déjà existant ailleurs, réutilisable sans
reconception.
