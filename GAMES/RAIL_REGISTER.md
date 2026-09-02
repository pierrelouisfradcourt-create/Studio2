# GAME RAIL — registre du portefeuille

Source d'autorité : `MASTER_SCHEMA.html` **Détail H · LE CURRICULUM** (arbre de compétences) +
**Détail H-bis** (file d'attente calibrée) + **Détail J** (« le calendrier des jeux produits EST
le calendrier studio global », décision Pierre 2026-07-26).

Loi affichée en tête du Détail H, vérifiable mécaniquement :
> **nouveau jeu = compétences acquises + 1 seul delta** ; un système hors budget = `FAIL`.

Statuts du schéma, **verbatim** : `● FAIT` (nœud 0, tier candidate, promotion en attente) ·
`⏸ FROZEN_HUMAN` (Pong) · `⚠ CLOSED_WITH_OBJECTION` (Snake) · `✓ CLOSED` (Breakout V2, gelé) ·
`◇ CIBLE` (tout le reste — rien de codé).
Source déclarée : note de Pierre 2026-07-22, **statuts vérifiés 2026-08-03** (decision-log).

> **Le statut est une donnée.** `CLOSED_WITH_OBJECTION` n'est pas `DONE`. `FROZEN_HUMAN` n'est pas
> `TODO`. `FAIT + promotion pending` n'est pas une brique promue. Aucune normalisation en DONE/TODO.

## Règles de lecture (ratifiées Pierre, 2026-09-01)

**Le repo ment par accumulation. Le document ment par obsolescence. Aucun des deux n'est la
vérité à lui seul.** D'où la boucle, et la place de ce registre dedans :

```
MASTER_SCHEMA  ──état déclaré──▶  EVIDENCE (code · runs · verdicts · tests)
                                        │
                                   état observé
                                        ▼
                                  RAIL_REGISTER  ── comparaison déclaré / mesuré
                                        │
                                   HUMAN GATE  (Pierre)
                                        ▼
                                  MASTER_SCHEMA  ── état actualisé
```

**Règle dure — un état déclaré ne devient JAMAIS automatiquement un état réel.**
```
Master Schema : TETRIS = CIBLE          Master Schema : TOWER DEFENSE = CIBLE
Repo          : 62 fichiers, 5 runs     Preuve        : verdict signé
=> déclaration = CIBLE                  Décision      : clos par Pierre 08-29
   activité observée = OUI               => la divergence reste VISIBLE
   ⚠ jamais « TETRIS = DONE »               jamais corrigée en silence
```

**Le rail est une architecture de progression, pas un inventaire de fichiers.** Les 25 nœuds
restent au registre même si une minorité seulement devient physiquement présente dans `GAMES/`.

**Règle d'import du V2 — le rôle, jamais l'âge.** La question n'est pas « ce fichier est-il
vieux ? » (subjectif) mais « quel rôle joue-t-il dans le Studio V2 ? », avec sept réponses
possibles : `MASTER_SCHEMA` · `FORGE` · `KB` · `GAME` · `TOOL` · `EVIDENCE_REQUIRED` ·
`NOT_REQUIRED`. **Si aucune n'est démontrable → ne pas importer.**

---

## Le rail complet — 25 nœuds

| # | nœud | compétence déposée | statut schéma | réalité mesurée 2026-09-01 |
|--:|---|---|---|---|
| 0 | **GRID NAVIGATION** | grid navigation (M01) | `● FAIT` — tier candidate, promotion en attente | cohérent |
| 1 | **PONG** | GAME LOOP / TEMPS RÉEL | `⏸ FROZEN_HUMAN` | cohérent |
| 2 | **SNAKE** | ENTITY SYSTEM | `⚠ CLOSED_WITH_OBJECTION` | cohérent |
| 3 | **BREAKOUT** | COLLISION SYSTEM | `✓ CLOSED` (gelé) | cohérent |
| 4 | **TETRIS** | STATE MACHINE | `◇ CIBLE` | ⚠ **62 fichiers, 24 tests, 38 Godot — le code existe** |
| 5 | **COOKIE CLICKER** | DATA MODEL | `◇ CIBLE` | ⚠ **chantier réel sous d'autres noms** (§C) |
| 6 | **PAC-MAN** | SIMPLE AI | `◇ CIBLE` | ⚠ **239 fichiers + verdict signé + ratifié 08-06** |
| 7 | **BOMBERMAN** | GRID SYSTEM | `◇ CIBLE` | ⚠ **88 fichiers, 46 Godot, zone tests ratifiée 08-12** |
| 8 | IDLE GAME | TIMER SYSTEM | `◇ CIBLE` | aucun code |
| 9 | TOWER DEFENSE | PATHFINDING | `◇ CIBLE` | ⚠ **59 fichiers + verdict signé, run clos 08-29** |
| 10 | CANDY CRUSH | RULE RESOLUTION | `◇ CIBLE` | aucun code |
| 11 | HEARTHSTONE MINI | EVENT SYSTEM | `◇ CIBLE` | aucun code (convergence) |
| 12 | VAMPIRE SURVIVORS | COMBAT SYSTEM | `◇ CIBLE` | `games/survival_arena*`, `snake_survivor` — parenté à statuer |
| 13 | POKEMON BATTLE | STATS SYSTEM | `◇ CIBLE` | aucun code |
| 14 | CARD GAME | CARD SYSTEM | `◇ CIBLE` | ⚠ **`card_engine` : verdict signé, ACCEPTÉ Pierre 07-20** |
| 15 | ZELDA MINI | INVENTORY SYSTEM | `◇ CIBLE` | aucun code |
| 16 | SLAY THE SPIRE | DECK BUILDING | `◇ CIBLE` | aucun code |
| 17 | DIABLO MINI | LOOT | `◇ CIBLE` | aucun code (convergence) |
| 18 | RPG MOBILE MINI | QUEST | `◇ CIBLE` | aucun code |
| 19 | AFK ARENA MINI | OFFLINE PROGRESSION | `◇ CIBLE` | aucun code |
| 20 | CLASH OF CLANS MINI | BASE BUILDING | `◇ CIBLE` | aucun code |
| 21 | CLASH ROYALE MINI | NETWORK SYNC | `◇ CIBLE` | aucun code |
| 22 | BRAWL STARS MINI | MATCHMAKING | `◇ CIBLE` | aucun code |
| 23 | MINECRAFT MINI | PROCEDURAL WORLD | `◇ CIBLE` | aucun code |
| 24 | STARDEW MINI | PERSISTENT WORLD | `◇ CIBLE` | aucun code |
| 25 | GENSHIN SLICE | 3D STREAMING WORLD | `◇ CIBLE` | aucun code (convergence finale) |

---

## ⚠ CONFLICT — le rail dit `◇ CIBLE · aucun code` pour 5 nœuds qui ont du code

```
A = MASTER_SCHEMA Détail H, verbatim : « Les ◇ restants : aucun code, roadmap. »
    statuts déclarés « vérifiés 2026-08-03 »
B = réalité mesurée (git ls-files, lab/forge_runs/*/verdict.json) :
      PAC-MAN        239 fichiers · verdict.json signé · PACMAN_V5_VALIDATED_V1 (2026-08-06)
      BOMBERMAN       88 fichiers · zone tests ratifiée (2026-08-12)
      TETRIS          62 fichiers · 5 run_dirs
      TOWER DEFENSE   59 fichiers · verdict.json signé · run clos par Pierre (2026-08-29)
      CARD GAME       30 fichiers · verdict.json signé · ACCEPTÉ Pierre (2026-07-20)
status = la colonne statut du rail est PÉRIMÉE de ~4 semaines sur 5 nœuds.
         Le rail n'est pas faux comme ARBRE (l'ordre des compétences tient) ;
         il est faux comme ÉTAT.
```
Ce n'est pas une surprise : `planning.yaml` P4 (ratifié 2026-08-02) l'annonçait déjà —
« 5 projets tracés absents du curriculum », 7 drifts roadmap, `etat: EN_ATTENTE`.
**Ne pas corriger le rail ici** : la résorption d'un drift est un arbitrage Pierre (P4).

---

# Fiches — les 10 nœuds qui ont une réalité

## 0 · GRID NAVIGATION
```
identity      : grid_nav_probe — nœud 0, « preuve de chaîne, PAS un jeu au sens du curriculum »
position      : 0 (racine du rail)
type          : probe / brique
status        : ● FAIT — tier candidate, PROMOTION EN ATTENTE (⛔ Pierre)
evidence      : brique KB `sys-grid-nav-m01`, catalogue V2 -> tier: "candidate" (vérifié)
                rôle `role-grid-navigator` ; jalon 0 du Détail H-bis : « promouvoir / laisser
                candidate » ; tautologie R9 corrigée (bb6ea2fa), is_clean_pass = FALSE
dependencies  : aucune (racine)
forge_req     : chaîne complète s0..s12 ; profil Godot
kb_req        : knowledge_base/roles/grid-navigator.yaml · systems/navigation/grid_nav.gd
                systems/navigation/grid_nav_scenario.mjs · run_tests.gd
tools_req     : Godot (fenêtre GPU obligatoire) · Node
sources       : games/grid_nav_probe/ (6 f.) · games/p5_gridnav/ (4 f. + verdict.json)
migration     : ⚠ la BRIQUE est déjà dans le V2 (knowledge_base/) ; le probe lui-même est
                dispensable — c'est une preuve de chaîne, pas un produit
```

## 1 · PONG — `⏸ FROZEN_HUMAN`
```
identity      : pong — GAME LOOP / TEMPS RÉEL
position      : 1
type          : jeu
status        : ⏸ FROZEN_HUMAN — « ni réussi ni échoué : arrêté par décision humaine »
evidence      : PONG_FROZEN_HUMAN_V1 (decision-log 2026-08-03) ·
                4 étapes toujours PENDING : s10a-oracle-code · s10s-oracle-standard ·
                s11-redteam-code · s12-verdict ·
                « AUCUN verdict signé n'a jamais existé » · pong_r2_ref = FAIL/BLOCKED
                mémoire : « Pong gelé = benchmark de régression, ne plus enrichir »
dependencies  : jalon 0 (M1 télémétrie) — le Détail H-bis dit « le rail ne démarre pas sans »
forge_req     : les 4 contrats PENDING existent : s10a, s10s, s11, s12 (copiés dans FORGE/)
kb_req        : aucune brique déposée (le nœud n'a jamais fermé)
tools_req     : Node · Playwright
sources       : games/pong/ (39 f., 22 .mjs, 11 tests, 3 Godot) · 4 run_dirs
migration     : ◐ CANDIDAT — valeur = témoin de régression, PAS produit.
                Copier fige un état inachevé : décision Pierre.
```

## 2 · SNAKE — `⚠ CLOSED_WITH_OBJECTION`
```
identity      : snake — ENTITY SYSTEM
position      : 2
type          : jeu
status        : ⚠ CLOSED_WITH_OBJECTION — clôturé au decision-log le 2026-08-03
evidence      : 5/10 runs software_verdict: OK / HUMANGATE_READY_WITH_OBJECTION
                (_run_final2/runtime/solv_20260729 · _run_cal1/2/3_20260730)
                OBJECTION NON RÉSOLUE : aucun `wiremap_frozen.json` ;
                RATIFICATION_WIREMAP_SNAKE.md toujours PROPOSED
dependencies  : Pong (leçons Pong -> Snake, Détail H-bis)
forge_req     : s5-wiremap (gel) — c'est précisément le maillon manquant
kb_req        : lignée pursuer/evader ; briques KB validated réutilisables
tools_req     : Godot · Node
sources       : games/snake/ (73 f., 37 tests, 69 Godot) · games/snake_survivor/ (107 f.)
                games/snake_genesis/ (2 f.) · 4 run_dirs
migration     : ◐ CANDIDAT SOUS RÉSERVE — copier un nœud dont l'objection est ouverte
                importe l'objection. 3 dossiers `snake*` : lequel est LE nœud ? à trancher.
```

## 3 · BREAKOUT — `✓ CLOSED`
```
identity      : breakout_v2 — COLLISION SYSTEM
position      : 3
type          : jeu
status        : ✓ CLOSED — ratifié ET gelé le 2026-08-03
evidence      : BREAKOUT_V2_FREEZE_V1, verbatim Pierre « Je ratifie les trois points Breakout »
                intégrité re-vérifiée AUTHENTIQUE · verdict.json signé présent
                3 humangate_flags ACCEPTÉS EN L'ÉTAT (archi + wiremap SKIPPED par le profil,
                red-team dégradé) — « clôture assumée, pas parfaite »
                devient témoin de régression gelé, comme Pong
dependencies  : Snake
forge_req     : contrat wm1-wiremap-breakout.yaml (conservé, consommé par l'observer)
kb_req        : à extraire — la brique COLLISION SYSTEM n'apparaît pas au catalogue
tools_req     : Godot · Node · Playwright
sources       : games/breakout_v2/ (92 f., 52 tests, 89 Godot) + verdict.json · 5 run_dirs
                games/breakout/ (15 f.) = V1 supersédée
migration     : ✓ **LE PLUS SOLIDE DU RAIL** — seul nœud CLOSED sans objection ouverte
```

## 4 · TETRIS — `◇ CIBLE` **contredit**
```
identity      : tetris — STATE MACHINE
position      : 4 — PROCHAIN NŒUD du rail
type          : jeu cible
status        : ◇ CIBLE au schéma / ⚠ code existant, aucun verdict signé
evidence      : 62 fichiers · 24 tests · 38 Godot · 5 run_dirs · 1 dossier forge_evidence
                contrat wm1-wiremap-tetris.yaml CONSERVÉ (exigence 10 lignes CORE)
                docs/forge/TETRIS_RUN_REPORT.md · aucun verdict.json
dependencies  : Breakout (le seul CLOSED propre en amont)
forge_req     : s5-wiremap · s9-build-godot · s10s · s12-verdict
kb_req        : STATE MACHINE à déposer (delta du nœud)
tools_req     : Godot · Node · Playwright
sources       : games/tetris/ · lab/forge_runs/tetris* (5)
migration     : ◐ CANDIDAT FORT — c'est le nœud actif du rail. Statut réel à établir avant copie.
```

## 5 · COOKIE CLICKER — `◇ CIBLE` **et c'est le chantier le plus actif du studio**
```
identity      : COOKIE CLICKER — DATA MODEL
position      : 5
type          : jeu cible
status        : ◇ CIBLE au schéma / ⚠ chantier réel massif sous d'AUTRES NOMS
evidence      : (a) KITTEN CLICKER — « réf. Cookie Clicker + Neko Atsume », 11 runs 08-21->25,
                    4 paliers d'autonomie ratifiés (KITTEN_PALIERS_V1_V4, 2026-08-21/22),
                    HumanGate 08-23 : FAIL « jeu complet » -> BASELINE PRODUIT
                    (KITTEN_HUMANGATE_BASELINE_V1). ⚠ games/kitten_clicker/ N'EXISTE PAS ;
                    la référence produit ratifiée est lab/prototypes/kitten_noyau_sonde/
                (b) BRAS D'EXPÉRIENCE p1/p2/p3 — économie de clicker : `gain_clic`,
                    `economy.mjs`, structure_imposee_v2.yaml ; p2_beta finding #6 :
                    « économie = canon Cookie Clicker (interdit du Brief violé) »
                    6 verdict.json signés (p1_beta, p2_alpha, p2_beta, p1_beta_E1, …)
                ⚠ LE LIEN EST UNE INFÉRENCE, PAS UNE VÉRITÉ DÉCLARÉE :
                      declared_identity : Cookie Clicker        (MASTER_SCHEMA, nœud 5)
                      observed_activity : Kitten Clicker + bras p1/p2/p3
                      basis             : référence commerciale + modèle économique (gain_clic)
                      relationship      : INFERENCE
                      claim             : BLOCKED               (gate Pierre)
                  Le schéma ne déclare nulle part que Kitten Clicker EST le nœud 5.
dependencies  : Tetris (position 4)
forge_req     : chaîne complète ; protocole paires L/D (RUN2_PROTOCOLE_V1, ratifié)
kb_req        : DATA MODEL à déposer
tools_req     : Node · Playwright · claude CLI · LM Studio (red-team s11 indépendante)
sources       : lab/prototypes/kitten_noyau_sonde/ · games/p1_beta/ p2_alpha/ p2_beta/
                p1_beta_E1/ (NON SUIVI) · games/p3_alpha/ (RUN EN COURS, autre session)
migration     : ⛔ BLOCKED — 3 lignées concurrentes (sonde · bras d'expérience · run vivant).
                Copier maintenant, c'est copier un chantier en mouvement.
```

## 6 · PAC-MAN — `◇ CIBLE` **contredit le plus fortement**
```
identity      : pacman — SIMPLE AI
position      : 6
type          : jeu cible au schéma / jeu de référence en réalité
status        : ◇ CIBLE au schéma / ✓ VALIDÉ — PACMAN_V5_VALIDATED_V1 (decision-log 2026-08-06)
evidence      : 239 fichiers (le plus gros du repo) · 167 tests · 234 Godot · verdict.json signé
                8 run_dirs · ratifié « jeu de référence Forge »
                ⚠ 00_CHARTER/ et 09_WIREMAP/ NON SUIVIS (git status)
                post-mortem : forge_postmortem_pacman_20260807 (boucle apprentissage cassée)
dependencies  : Bomberman/Tetris selon la lignée grille
forge_req     : chaîne complète, profil Godot
kb_req        : SIMPLE AI à déposer ; lignée pursuer-mobile déjà `validated` au catalogue
tools_req     : Godot (GPU) · Node · Playwright
sources       : games/pacman/ · lab/forge_runs/pacman* (8)
migration     : ◐ CANDIDAT FORT — statut ratifié « référence », mais le rail l'ignore.
                Le drift à trancher AVANT copie : est-il position 6, ou hors rail ?
```

## 7 · BOMBERMAN — `◇ CIBLE` **contredit**
```
identity      : bomberman_3d — GRID SYSTEM
position      : 7
type          : jeu cible
status        : ◇ CIBLE au schéma / ⚠ code + décision ratifiée, aucun verdict signé
evidence      : 88 fichiers · 16 tests · 46 Godot · 6 run_dirs
                2 dossiers forge_evidence (BOMBERMAN_3D_L0_20260810, L1_L8_20260810) NON SUIVIS
                decision-log 2026-08-12 : zone protégée `tests/` de bomberman_3d RATIFIÉE
                docs/forge/BOMBERMAN_3D_L0_CONTRACT.md · BOMBERMAN_3D_CAMPAIGN_PREP.md
dependencies  : grid navigation (nœud 0) + Pac-Man
forge_req     : s9-build-godot · chaîne 3D
kb_req        : GRID SYSTEM à déposer ; réutilise M01
tools_req     : Godot 3D (GPU) · pipeline asset 3D · Blender (asset_geometry)
sources       : games/bomberman_3d/ · lab/forge_evidence/BOMBERMAN_3D_* (non suivis)
migration     : ◐ CANDIDAT — évidence partiellement NON VERSIONNÉE (un `git clean` l'emporte)
```

## 9 · TOWER DEFENSE — `◇ CIBLE` **contredit**
```
identity      : tower_defense_sonde — PATHFINDING
position      : 9
type          : sonde d'expérience (pas un produit)
status        : ◇ CIBLE au schéma / ⚠ CLOS PAR PIERRE 2026-08-29, 4 objections MAINTENUES
evidence      : verdict.json signé · verify_run exit 0 AUTHENTIQUE ·
                software_verdict OK / HUMANGATE_READY_WITH_OBJECTION
                4 objections non levées : 5 survivants mutation triés par le producteur ·
                red-team fallback (Qwen n'a pas tourné) · prisme_control.md FAIL structurel ·
                oracle standard sauté par profil
                mesuré : oracle 6 volets PASS · E2E 34/34 Chromium réel · panel 5 bots
                CLOSURE_20260829.md — « AUCUNE reconstruction »
dependencies  : lignée grille
forge_req     : chaîne complète profil `full`
kb_req        : PATHFINDING à déposer
tools_req     : Node · Playwright (jonction NTFS vers llm-lego/node_modules !)
sources       : games/tower_defense_sonde/ (59 f., 50 .mjs, 23 tests) · 1 run_dir
migration     : ◐ CANDIDAT SOUS RÉSERVE — c'est une SONDE close avec objections,
                pas un jeu du portefeuille. Valeur = évidence méthodologique.
```

## 14 · CARD GAME — `◇ CIBLE` **contredit**
```
identity      : card_engine — CARD SYSTEM
position      : 14
type          : jeu cible
status        : ◇ CIBLE au schéma / ✓ ACCEPTÉ Pierre 2026-07-20, commité 8b1cdd9
evidence      : verdict signé VÉRIFIÉ (HMAC/évidence/mutation authentiques) · 2e jeu forgé accepté
                07_CURRENT_STATE.md : « verify_run HMAC/évidence/mutation authentiques »
dependencies  : Hearthstone Mini / event system en aval
forge_req     : chaîne V0 (Run A) — antérieure au FORGE STANDARD
kb_req        : CARD SYSTEM ; le curriculum v1 le classait « surtout un PORTAGE Godot »
tools_req     : Node
sources       : games/card_engine/ (30 f., 25 .mjs) + verdict.json · 1 run_dir
migration     : ◐ CANDIDAT — accepté mais ère HTML/JS, avant le standard. Portage = travail neuf.
```

---

## Ce que ce registre établit

1. **`GAMES/` = portefeuille avec états, pas « les jeux terminés ».** Un seul nœud est
   `✓ CLOSED` sans objection ouverte : **Breakout V2**. Ne copier que lui appauvrirait le rail.
2. **Un seul nœud est vraiment bloquant en amont** : le **jalon 0** du Détail H-bis
   (M1 télémétrie · s10s→driver · promotion decision-log · promotion M01). Trois `⛔ Pierre`.
   « Le rail ne démarre pas sans le jalon 0 » — verbatim.
3. **La promotion de GRID NAVIGATION est mécaniquement mesurable** : c'est le passage de
   `sys-grid-nav-m01` de `tier: candidate` à `validated` dans `knowledge_base/catalog.json`.
   Vérifié dans le V2 : il est toujours `candidate`. 7 entrées sur 50 sont `validated`.
4. **Le rail est juste comme ARBRE, périmé comme ÉTAT.** L'ordre des compétences tient ;
   la colonne statut a 4 semaines de retard sur 5 nœuds. C'est le drift P4, non résorbé.

## Aucun jeu n'a été copié

Conformément à la séparation posée : `MASTER_SCHEMA` = vérité du workflow + état du rail ·
`GAMES/` = matérialisation des jeux **réellement retenus**. La rétention se décide sur ce
registre, pas sur le contenu du repo. Trois décisions ouvertes :

- **le drift** : les 5 nœuds `◇ CIBLE` qui ont du code — on met à jour le rail, ou on requalifie ?
- **le périmètre d'un nœud** : Snake a 3 dossiers, Cookie Clicker en a 3 lignées. Lequel EST le nœud ?
- **le jalon 0** : trois gestes Pierre, sans lesquels le rail ne démarre pas.

---
`claim_verdict: NO_CLAIM_ALLOWED` — ce registre reporte des statuts déclarés et des mesures.
Il ne prouve la qualité d'aucun jeu.
