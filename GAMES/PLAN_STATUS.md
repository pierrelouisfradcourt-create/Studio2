# GAMES — statut : **BLOCKED**, aucun jeu importé

Règle appliquée (§8 de la mission) : *le catalogue des jeux V2 doit repartir du planning de
développement des jeux*, pas d'un inventaire du repo. J'ai cherché ce planning. **Il n'existe
pas sous forme ratifiée.** `unknown_policy: UNKNOWN => BLOCKED` → aucun jeu n'a été copié.

## Ce qui a été cherché, et trouvé

| candidat | chemin | statut réel | preuve |
|---|---|---|---|
| Curriculum de jeux | `docs/forge/CURRICULUM_JEUX_v1.md` (2026-07-22) | **PROPOSED, jamais ratifié** | son propre en-tête : « Statut : PROPOSED — à ratifier par Pierre ». `grep -ci curriculum studio_brain/decisions/decision-log.md` → **0** : aucune entrée de ratification en 1 300 lignes de decision-log |
| Registre de planning | `studio_brain/planning/planning.yaml` (2026-08-03) | **RATIFIÉ Pierre 2026-08-02** — mais ce n'est **pas** un planning de jeux | c'est le plan de *réparation de la Forge* : P0 boucle lessons→KB, P1 planning, P2 verrou contrat→prompt, P3 fiches agents, P4 doctrine vs réalité, P5 jeu-test |
| Le seul item « jeu » du planning ratifié | `planning.yaml` → `P5-jeu-test-apprentissage` | **`etat: BLOQUE`** | `decision_attendue: "choix du jeu + go campagne (gate Pierre)"` ; `depends_on: [P0, P2, P4]` — les trois sont `EN_COURS` ou `EN_ATTENTE` |
| Roadmaps diverses | `00_STUDIO_CONTROL/00_MASTER_DOCS/01_ROADMAP.md`, `docs/roadmap/PLAN_100_ACTIONS_2026-06-27.md`, `docs/studio_v2/04_ROADMAPS.md` | roadmap_docs_only, mai–juin 2026 | antérieures à la Forge actuelle |
| Plannings générés par l'Observer | `lab/reports/observer/{pong,tetris,breakout_v2,p5_gridnav}/planning_PROPOSED.yaml` | PROPOSED, par jeu, non ratifiés | sorties d'outil, pas un plan de studio |

## CONFLICT DETECTED — le curriculum contredit le réel, et c'est écrit dans un doc ratifié

```
A = docs/forge/CURRICULUM_JEUX_v1.md : ordre 0..10 (grid_nav_probe, PAC-MAZE, MATCH-3,
    PLATFORMER, RUN&GUN, TACTICAL RPG, CARD RPG, ACTION RPG, MERGE/IDLE, ARENA, OPEN WORLD 3D)
B = planning.yaml P4-doctrine-vs-realite (RATIFIÉ 2026-08-02), verbatim :
    « PONG en desaccord entre les deux docs, 5 projets traces absents du curriculum,
      grid_nav_probe FAIT sans traces » — 7 drifts roadmap + 5 drifts documentation
C = réalité mesurée : les jeux construits APRÈS le curriculum sont breakout_v2, tetris,
    snake, bomberman_3d, kitten_clicker, tower_defense_sonde, p1/p2/p3 (bras d'expérience).
    Sur 11 rangs du curriculum, un seul a été honoré : rang 01 PAC-MAZE -> games/pacman/.
status = le curriculum est un document PROPOSED que le studio a mesuré comme divergent,
         et dont la résorption (P4) est elle-même EN_ATTENTE.
         => PAS de planning canonique. GAMES = BLOCKED.
```

## Les seuls jeux à rôle **ratifié** (decision-log, pas inventaire)

Ce ne sont pas un plan — ce sont des décisions passées. Elles disent à quoi sert un jeu, pas
lequel construire ensuite.

| jeu | décision ratifiée | date | rôle assigné |
|---|---|---|---|
| `pacman` | `PACMAN_V5_VALIDATED_V1` | 2026-08-06 | **jeu de référence Forge** |
| `breakout_v2` | `BREAKOUT_V2_FREEZE_V1` | 2026-08-03 | **baseline gelée** |
| `pong` | `PONG_FROZEN_HUMAN_V1` | 2026-08-03 | **gelé, run jamais terminé** — benchmark de régression |
| `snake` | clôture enregistrée au registre canonique | 2026-08-03 | clos |
| `kitten_clicker` | `KITTEN_HUMANGATE_BASELINE_V1` | 2026-08-23 | **BASELINE PRODUIT après FAIL « jeu complet »** — et son dossier `games/kitten_clicker/` **n'existe pas** (le code vit en `lab/prototypes/kitten_noyau_sonde/`) |
| `bomberman_3d` | zone protégée `tests/` ratifiée | 2026-08-12 | en cours |

## Ce qu'il manque pour débloquer

Une seule décision, et elle appartient à Pierre :

> **Quel est le plan de développement des jeux du Studio V2 ?**

Trois formes possibles, par coût croissant :
1. **Ratifier le curriculum** tel quel (et accepter ses 7 drifts mesurés), ou l'amender.
2. **Débloquer `P5-jeu-test-apprentissage`** : désigner UN jeu + go campagne. Le V2 démarre
   alors avec un seul jeu, ce qui est cohérent avec « on migre ce qui doit continuer à vivre ».
3. **Écrire un nouveau plan** à partir des rôles ratifiés ci-dessus.

Tant que cette décision n'est pas prise, importer un jeu reviendrait à décider à la place de
Pierre à partir d'un inventaire — exactement ce que la mission interdit.

## Fiche type à remplir, une fois le plan connu (§9)

```
GAME
├── identity          nom · genre · référence commerciale · rang dans le plan
├── runtime           games/<jeu>/ : moteur, entrée, boucle
├── systems           briques KB consommées (catalog.json : brick_id)
├── tests             suite locale + harness e2e
├── forge_contracts   étapes s0..s12 réellement exercées + profil driver
├── wiremap           09_WIREMAP/ (gel) et wiremap après build
├── assets            asset_resolution.json + déclarations
├── required_kb       entrées catalogue + rôles + patterns
└── required_tools    Playwright · Godot · claude CLI · LM Studio
```
Attention (mesuré) : un jeu vit dans **3 emplacements** du repo source —
`games/<jeu>/` (produit), `lab/forge_runs/<jeu>/` (état + preuve), `lab/forge_evidence/…`
(évidence). Copier `games/<jeu>/` seul produit une unité incomplète.

---
`claim_verdict: NO_CLAIM_ALLOWED`
