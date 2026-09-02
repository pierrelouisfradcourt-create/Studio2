# FORGE_PIPELINE_TARGET_V1 — cible de workflow figée (P0)

**Date** : 2026-08-13 · **Statut** : PROPOSED — cible ratifiée par Pierre en conversation, aucune
écriture de code, aucun contrat créé, aucun commit.
`software_verdict: voir §3` · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` · `claim_verdict: NO_CLAIM_ALLOWED`

**Convention de marquage** : `[M]` mesuré contre le dépôt (fichier:ligne) · `[H]` hypothèse ·
`[D]` décision de Pierre.

**Ce document ne décrit pas l'état du dépôt.** Il fige la CIBLE, et donne pour chaque flèche
l'écart mesuré avec le réel. Il ne remplace aucun document existant : `MASTER_SCHEMA_V2_PROPOSAL`
traite de la représentation, `PLAN_CONVERGENCE_FORGE_V1` de la convergence, `FORGE_STATE_V2_0`
d'un snapshot d'état. Aucun ne fige un pipeline de production.

---

## 1. La cible `[D]`

```
                          JEU(X) DE RÉFÉRENCE
                                  │
NIVEAU 1 — QUEL MONDE ?    AGENT ARTISTIQUE
   (matière créative)              │
                              WORLD SCAN
                                  │
                    ┌─────────────┴─────────────┐
                    v                           v
               STORY BIBLE                  ART BIBLE
                    │                           │
          ┌─────────┴─────────┐                 │
          v                   v                 │
    QUEST BIBLE       CHARACTER BIBLE           │
          └─────────┬─────────┴─────────────────┘
                    v
NIVEAU 2 —      GAME MASTER   (consomme les 4 bibles)
QUEL JEU DANS       │
CE MONDE ?     WORLD SCAN GM / GENRE SCAN
                    │  (mesure comparative du genre → variables de calibration)
       ┌────────────┼────────────┐
       v            v            v
  MÉTRIQUES    STRUCTURE     RÉFÉRENCES
   GENRE          JEU
       └────────────┼────────────┘
                    v
            MATRICES DE DESIGN
       ┌────────────┼────────────┐
       v            v            v
 Construction     Meta       Economy
       └────────────┼────────────┘
                    v
               GREY BLOCK   (systèmes · métagame · gameplay)
                    v
            UNIVERS + GAME DESIGN
                    v
            QUEST ↔ MAP ↔ SYSTEMS
       (chaque quête rattachée aux espaces, personnages,
        objets, systèmes et conditions conçus)
                    v
            GM VALIDATION SCAN
       (métriques · matrices · progression · RNG ·
        solvabilité · anti-méta · cohérence narrative)
                    │
NIVEAU 3 —          v
COMMENT LE   DÉCOMPOSITION → ARCHITECTURE / KB → BUILD PLAN
CONSTRUIRE ?        │
NIVEAU 4 —          v
RELIER           WIREMAP
                    │
NIVEAU 5 —          v
FABRIQUER    BUILDER / GODOT
                    │
NIVEAU 6 —          v
VÉRIFIER     ORACLES → PLAYTEST → LESSONS → MUTATION ──→ KB / Forge
```

**Frontières de rôle** `[D]` :
`AGENT ARTISTIQUE` = quel monde ? · `GAME MASTER` = quel jeu dans ce monde ? ·
`ARCHITECTE` = comment le construire ? — **possède Architecture/KB, Build Plan ET WireMap** ·
`BUILDER` = comment le fabriquer ? · `ORACLES / PLAYTEST` = ce qui existe correspond-il au prévu ?

**La WireMap est le contrat de traduction de l'Architecte** `[D]` — pas un fichier jeté entre deux
agents. L'Architecte la produit à partir du Grey Block, des matrices, des bibles, des contraintes
du GM, de l'architecture/KB et — en cas de recyclage — du jeu précédent et de sa WireMap. Elle
reste le blackboard permanent consultable du projet.

**Propriété de la WireMap : unification sans coût** `[M]` — `s4-archi` porte
`capability_role: architect`, `s5-wiremap` porte `capability_role: wiremap`, et **les deux
résolvent au même modèle** (`claude-opus-4-8`). Les réunir sous un rôle `architect` unique est un
renommage, pas un changement de routage.

**Architecte-constructeur : décision ouverte, PAS une réparation** `[M]` — la rupture visée
(« un autre agent devine ce que la WireMap voulait dire ») **n'existe pas sur le chemin driver** :
`_UPSTREAM_BY_STEP["s9-build"] = ("blueprint.json", "wiremap.json")`, injectés **en contenu**
(`run_real.py:996-1008`). Le builder reçoit le blueprint et la WireMap, il ne les devine pas.
Fusionner Architecte et Builder ferait passer la construction de `claude-haiku-4-5` à
`claude-opus-4-8` — arbitrage coût/qualité assumé, à trancher séparément. Voir §7.4.

**Art Bible ≠ bible visuelle** `[D]` : c'est le **paquet de contexte créatif complet** transmis au
GM — identité visuelle *plus* monde, lieux, objets, personnages, relations, contraintes
narratives. Le GM ne fabrique pas un système générique auquel il colle une histoire ensuite ; il
part de `UNIVERS + RÉFÉRENCES GENRE + MÉTRIQUES OBSERVÉES`.

**Deux World Scans distincts** `[D]` : celui de l'agent artistique observe le monde et les
références ; celui du GM est une **mesure comparative du genre** produisant les variables de
calibration des matrices. Ne pas les fusionner.

**Invariant de position** `[D]` : la WireMap n'invente pas le jeu. Elle arrive **après**
Architecture/KB et Build Plan, et réconcilie intention ludique ↔ architecture ↔ implémentation.
Elle est un blackboard permanent, versionné, consultable, réutilisable d'un projet au suivant.

### 1.1 Le World Scan du GM est une station NEUVE `[M]`

Mesuré sur `contracts/s2-worldscan.yaml` (`output_contract` intégral) — le schéma structuré est :
`games[{game, sources[], loops{minute_1,minute_10,hour_5,endgame}, objectives[{mode,
has_win_state, victory_condition, has_defeat_state, defeat_condition, player_goal}],
retention_answer}], advisory: true`.

Le contrat pose explicitement que *« l'analyse qualitative (mécaniques, progression, économie,
UX, architecture supposée) vit dans le TEXTE de la réponse, pas dans des fichiers »*.

Sur les 11 dimensions de calibration demandées :

| déjà structuré (3) | non structuré (8) |
|---|---|
| joueurs / modes (`objectives[].mode`) | combat (vitesse projectile, cadence, dégâts) |
| solvabilité (`victory_condition` / `defeat_condition`) | progression chiffrée · économie |
| boucles (`loops` 4 horizons) | RNG (fréquence, amplitude, distribution) |
| | rareté (tiers, % de drop) · bonus |
| | métagame (synergies, counters, compositions) |
| | construction (coûts, dépendances, power budget) |

Conclusion : le GM Scan n'est **pas** une seconde passe de `s2` — la partie quantitative dont il
a besoin est délibérément hors du schéma. Réserve à lever : `worldscan.json` porte
`advisory: true` ; un artefact advisory ne peut pas faire **autorité de calibration** pour les
matrices sans changement de statut explicite. `[H]`

---

## 2. Question tranchée : `s3-decompo` / `s4-archi` — pas d'inversion `[M]`

Posée comme « faut-il inverser Build Plan et Architecture ». La mesure dissout la question :

- `s4-archi` **consomme** la featuremap — `contracts/s4-archi.yaml:24` (`mandatory_read`) et
  critère d'acceptation `:57` « chaque feature de la featuremap couverte par ≥1 module ».
  L'architecture ne PEUT pas précéder la décomposition : la dépendance est gardée par le contrat.
- Donc `s3-decompo` **n'est pas le Build Plan**. C'est la décomposition fonctionnelle
  (Système→Feature→capacité, chaque feuille portant son `expected_proof`) — un artefact de
  conception, en amont de l'architecture.
- Le **Build Plan** au sens « ordre de construction » existe déjà partiellement, ailleurs :
  le champ `write_order` des lignes de WireMap, avec oracle falsifiant
  (`standard_oracles.py:1320-1346` — FAIL si ≥2 lignes fournissent une capacité sans ordre).

**Décision figée** : ordre `DÉCOMPO → ARCHITECTURE → BUILD PLAN → WIREMAP`, conforme à
l'`ORDER` existant. **Aucun changement d'`ORDER` n'est requis pour le Niveau 3.**

---

## 3. Écart mesuré, flèche par flèche `[M]`

Statuts : `IMPLEMENTED` · `TESTED` · `DOCUMENTED_ONLY` · `PASSIVE` · `BLOCKED` · `NOT_FOUND` · `UNKNOWN`.
« PASSIVE » = l'étape existe et produit, mais **aucun consommateur déclaré** ne lit sa sortie.

| station cible | étape réelle | artefact | consommateurs | oracle | statut |
|---|---|---|---|---|---|
| WORLD SCAN | `s2-worldscan` | `worldscan.json` | 2 (`s1`,`s3`) | `check_prisme_manifest.mjs` | **IMPLEMENTED** |
| ART BIBLE | `s2.5-artbible` | `art_bible.md` | **0** | `check_artbible.mjs` | **PASSIVE** |
| STORY BIBLE | — | — | — | — | **NOT_FOUND** |
| QUEST BIBLE | — | — | — | — | **NOT_FOUND** |
| CHARACTER BIBLE | — | — | — | — | **NOT_FOUND** |
| GAME MASTER | — | — | — | — | **NOT_FOUND** |
| GREY BLOCK | — | — | — | — | **NOT_FOUND** |
| CONSTRUCTION MATRIX | — | — | — | — | **NOT_FOUND** |
| GM VALIDATION SCAN | — | — | — | — | **NOT_FOUND** |
| 10 matrices | — | — | — | — | **NOT_FOUND** (10/10) |
| — dont surface advisory | `/balance-check` | verdict texte | 0 | aucun | **DOCUMENTED_ONLY** |
| DÉCOMPO FONCTIONNELLE | `s3-decompo` | `featuremap.json` | 2 | aucun | **IMPLEMENTED** |
| ARCHITECTURE / KB | `s4-archi` | `blueprint.json` | 5 | `check_architecture` | **IMPLEMENTED** |
| BUILD PLAN | `write_order` (champ) | dans wiremap | `check_collisions` | ✓ | **PASSIVE** |
| WIREMAP | `s5-wiremap` | `wiremap.json` | 7 | `check_wiremap` + 8 | **IMPLEMENTED** |
| BUILDER / GODOT | `s9-build-godot-standard` | code | — | — | **IMPLEMENTED** |
| ORACLES | `s10a/b/c/s` | reçus signés | — | — | **TESTED** |
| PLAYTEST / LESSONS | `premortem(domain=…)` | journal | driver | aucun | **PASSIVE** |
| MUTATION | `mutation_proof` | reçu | driver | ✓ | **IMPLEMENTED** |

### Les DEUX mécanismes de transmission — ne pas les confondre `[M]`

Erreur d'audit commise puis corrigée le 2026-08-13 : mesurer `mandatory_read` seul et conclure
à l'absence de consommateur. Il existe deux mécanismes distincts, et seul le second transmet.

| mécanisme | ce qu'il fait | code |
|---|---|---|
| `mandatory_read` | **déclare** — colle une liste de chemins sous « À LIRE OBLIGATOIREMENT » | `contract.py:451` |
| `_UPSTREAM_BY_STEP` | **transmet** — lit le fichier, tronque, injecte le CONTENU sous « ARTEFACTS AMONT » | `run_real.py:996-1008` |

`_UPSTREAM_BY_STEP` est dupliqué dans `run_real.py:972` et `context_manifest.py:61`, avec un test
d'égalité stricte (`test_context_manifest.py`) — une divergence casse le test, jamais un oubli
silencieux. **Chaîne réellement transmise** : `s1←s2` · `s3←charter,s1,s2` · `s4←charter,s3` ·
`s5←charter,s3,blueprint` · `s6←charter,s3,s4,s5` · `s9←blueprint,wiremap` · `s11←wiremap`.

Corollaire : citer un artefact dans un `mandatory_read` produit `CITED`, jamais `USED`. Tout
câblage neuf doit passer par `_UPSTREAM_BY_STEP`.

### Artefacts orphelins mesurés — 2

Absents des DEUX mécanismes :

1. `art_bible.md` / `asset_requests.json` — `s2.5-artbible` n'a aucune entrée dans
   `_UPSTREAM_BY_STEP`, ni comme consommateur ni comme source amont d'un autre pas.
2. `parametres_de_design_source` — champ déclaré par le wiremap de Bomberman
   (`05_SYSTEMS/params/params.gd`), **0 consommateur** dans tout le dépôt.

`worldscan.json` **n'est PAS orphelin** : consommé par injection depuis FORGE_PRISME_V2
(Pierre, 2026-08-03). Il porte déjà `loops{minute_1,minute_10,hour_5,endgame}`,
`objectives[{mode,has_win_state,victory_condition}]` et `sources[{url,type,timestamp}]` —
les quatre sorties de Niveau 1, produites, transmises et falsifiables.

---

## 4. Invariant des matrices `[D]`

> Une matrice n'est pas un tableau décoratif. Elle doit avoir un **producteur**, un
> **consommateur** et un **oracle capable de falsifier** au moins une partie de ses affirmations.

Test appliqué aux 5 artefacts structurés existants (`run_real._ARTIFACT_BY_STEP`) `[M]` :

| artefact | producteur | consommateur | falsificateur | conforme |
|---|---|---|---|---|
| `worldscan.json` | ✓ | ✓ (`s1`,`s3` par injection) | `check_prisme_manifest.mjs` | **oui** |
| `product_snapshot` | ✓ | ✓ (`s3` par injection) | `check_prisme.mjs` (markdown) | partiel |
| `featuremap.json` | ✓ | ✓ (`s4`,`s5`,`s6` par injection) | ✗ | **non** |
| `blueprint.json` | ✓ | ✓ (`s5`,`s9` + 3) | `check_architecture` | **oui** |
| `wiremap.json` | ✓ | ✓ (`s6`,`s9`,`s11` + 4) | `check_wiremap` +8 | **oui** |

**3 / 5 pleinement conformes.** Le seul manquant net est `featuremap.json` : transmis à trois
consommateurs, mais **aucun oracle ne le falsifie** — c'est le maillon le plus faible du Niveau 3.

Conséquence de cadrage : une matrice coûte **trois câblages** — (1) artefact structuré dans
`_ARTIFACT_BY_STEP`, (2) entrée dans `_UPSTREAM_BY_STEP` (les DEUX copies), (3) fonction
`check_*` déterministe. **Dix matrices = trente câblages** `[E]`. Deux des trois sont du Python,
**pas** du contrat — ce qui déplace la porte : voir §7.3.

Matrices retenues, chacune soumise à l'invariant : `GAME_DESIGN_METRICS` · `PROGRESSION_MATRIX` ·
`RNG_MATRIX` · `RARITY_MATRIX` · `UNIT_COST_MATRIX` · `POWER_MATRIX` · `COUNTER_MATRIX` ·
`SYNERGY_MATRIX` · `META_RISK_MATRIX` · `CONSTRUCTION_MATRIX`.

---

## 5. Bomberman = fixture de falsification, pas produit `[D]`

Bomberman 3D **n'est ni reforgé ni refait**. Il sert à tester :
`ancien artefact → nouvelle chaîne → réconciliation → nouveaux oracles`,
et à vérifier l'invariant « ne pas refaire from scratch ce qui peut être réconcilié ».

État mesuré `[M]` — `lab/forge_runs/bomberman_3d/state.json`, run
`bomberman3d-replay-oracleonly-20260813`, profil `oracle_only`, `spawn 1/1/1` :

- WireMap : 60 lignes, 30 systèmes — plus riche que tetris (22/14), mais **dialecte non standard**.
- `observable_by_player` **0/60** · `expected_proof` **absent** · `genre_refs` **0/60** ·
  `provides` 10/60 · `write_order` renseigné **0/60** · champ `couvre` **absent**.
- `genre_coverage` = **FAIL** (`genre_bible: null`) ; étape néanmoins `status: OK` — `genre_coverage`
  n'appartient pas à `_CORE_FACETS` (`driver.py:2321`). **Divergence doc↔code** : la docstring
  `driver.py:2166` annonce « FAIL si UN SEUL des six oracles échoue ». Constatée, non corrigée.
- 0 nouvelle proposition de capacité (236 → 236), contre 190 pour pacman et 42 pour tetris.

Lecture : les oracles ne sont pas cassés, ils sont **non alimentés**. Un WireMap écrit hors driver
n'a jamais eu à remplir les champs qui rendent les oracles discriminants.

---

## 5bis. NIVEAU 6 — la boucle apprenante (ratifié Pierre, 2026-08-13) `[D]`

```
Observation → Erreur/écart → CAUSE RACINE → NIVEAU RESPONSABLE
   → Hypothèse isolée → Mutation → Expérience → Oracle + Playtest
   → Lesson → KB / génome → Mutation suivante  ↺
```

### Taxonomie ratifiée

| cause racine | niveau de mutation | layer existante `[M]` |
|---|---|---|
| erreur de **connaissance** | World Scan | `s2-worldscan` ✓ |
| erreur de **mémoire** | KB | `knowledge` ✓ |
| erreur de **transmission** | contrat / livrable | `s4-archi-contract`, `s5-wiremap-contract` (partiel) |
| erreur **systémique** | WireMap / architecture | `s4-archi-contract`, `s5-wiremap-contract` ✓ |
| erreur de **conception** | Architect / GM | `s1-prisme`, `s3-decompo` — **GM absent** |
| erreur d'**exécution** | Builder / Worker | `build`, `repair` ✓ |

**Règle centrale** `[D]` : *l'erreur observée ne détermine pas automatiquement le composant à
modifier.* Le diagnostic passe par un arbre explicite — information absente → World Scan ·
présente mais mal conservée → KB · présente mais non transmise → contrat · workflow
structurellement incapable → architecture/WireMap · mauvaise décision de design → GM/Architect ·
bonne décision mal implémentée → Worker.

**Règle anti-usine-à-gaz** `[D]` : une erreur ne justifie **jamais automatiquement** une nouvelle
couche.

```
Erreur → classification → couche responsable déjà existante ?
           ├── oui → mutation ciblée
           └── non → seulement alors proposer une nouvelle capacité
```

Ce qui empêche la dérive `bug → nouvel agent → nouvelle règle → nouvelle couche → nouvelle
exception`. La Forge doit d'abord apprendre **où** elle s'est trompée, pas ajouter quelque chose.

### Schéma d'une Lesson `[D]`

Une Lesson conserve sa causalité et répond à : `WHAT` (quelle erreur) · `WHY` · `ROOT_CAUSE`
(quelle classe) · `TARGET` (quel niveau doit muter) · `HYPOTHESIS` · `EXPERIMENT` (comment la
falsifier) · `EVIDENCE` · `OUTCOME` (amélioration / régression / neutre) · `NEXT_MUTATION`.
Raccorde le Niveau 6 aux quatre lignées de `FORGE_CAUSAL_LINEAGE_V2` (Intent, Activation, Return,
Persistence).

### État mesuré — la machinerie existe, la taxonomie manque `[M]`

| brique | état |
|---|---|
| `scripts/forge/layers.json` — 13 layers, source unique du vocabulaire | **IMPLEMENTED** |
| `scripts/forge/root_problems.json` — `id`, **`layer`**, `lesson_ids`, `metrics`, `reward_contract`, `forbidden_aggregation` | **IMPLEMENTED** — 4 entrées |
| `learning_memory.py` — `record_failure_event`, `record_lesson_event`, `fold_lessons`, `evidence_count` monotone, génération/génome | **IMPLEMENTED** |
| `root_cause` dans le driver (`last_root_cause`, `_receipt_root_cause`, promu depuis manifestes HMAC) | **IMPLEMENTED** |
| **taxonomie des 6 classes de cause** | **NOT_FOUND** |
| Playtest · Lessons comme ÉTAPES avec artefact + consommateur | **PASSIVE** |

Lecture : le champ `layer` de `root_problems.json` **est** le « niveau responsable » de la
taxonomie, et `layers.json` en porte le vocabulaire. Les 4 entrées existantes sont des problèmes
d'usine spécifiques (`ORACLE_FALSE_NEGATIVE`, `DEFECT_DISPLACEMENT`, `PROMPT_FIELD_OMISSION`,
`REPAIR_NON_CONVERGENCE`), **pas** les 6 classes génériques. Le travail de P-taxonomie est donc
un dépôt d'entrées dans une structure qui les attend — **pas un nouveau sous-système**. `[H]`

Seule cible sans layer : le **GM** — cohérent, la station est `NOT_FOUND` (§3).

## 6. Ordre de travail figé `[D]`

Séquence ratifiée par Pierre le 2026-08-13. **La porte des contrats (§7.2/§7.3) s'intercale
entre P0 et P1 et bloque tout ce qui suit** — y compris P1, dont le câblage exige d'éditer un
`mandatory_read`. Aucune station de P2 à P10 ne démarre avant que P1 ait validé le patron.

```
P0 ──> [ HUMAN GATE contrats ] ──> P1 ──> P2 ──> … ──> P10
```

| # | objet | état |
|---|---|---|
| P0 | figer le workflow cible — pas de code | **ce document** |
| — | **HUMAN GATE contrats** — §7.2 + §7.3 | **ouvert, bloquant** |
| P1 | **prouver que l'injection `s2 → s1` transmet RÉELLEMENT** — profil `amont_only` | **TESTED — voir 6.1** |
| P2 | Bibles (Art / Story / Quest / Character) | bloqué par P1 |
| P3 | Game Master | bloqué par P1 |
| P4 | Grey Block + Construction Matrix | bloqué par P1 |
| P5 | GM Validation Scan | bloqué par P1 |
| P6 | Architecture / KB | bloqué par P1 |
| P7 | WireMap — réconciliation finale avant construction | bloqué par P1 |
| P8 | Build (Builder Godot) | bloqué par P1 **et** par le gate §7.1 (identité de production) |
| P9 | Oracles / Playtest | bloqué par P1 |
| P10 | Lessons / Mutation → KB | bloqué par P1 |

**Règle de séquence** `[D]` : on ne crée pas les 7 stations et les 10 matrices en parallèle.
P1 est une expérience de validation du patron `producteur → artefact → consommateur → oracle` ;
tant qu'elle n'a pas tenu sur UN artefact, elle n'est pas généralisée aux trente câblages.

**Règle de conversion** `[D]` : on ne transforme pas une doctrine en code parce qu'elle est
convaincante. Ce document reste `DOCUMENTED_ONLY` par construction — il ne devient exécutable
qu'étape par étape, chacune adossée à une preuve.

### 6.1 P1 — résultat : la flèche `s2 → s1` est PROUVÉE `[M]`

Run `p1-injection-20260813`, projet sonde `p1_worldscan_injection`, profil `amont_only`,
2 appels LLM · 26 769 tokens · 431 s. `s2-worldscan` OK · `s1-prisme` OK.

**Preuve mécanique (transmission)** — la section amont recalculée depuis le `run_dir` vaut
15 152 chars sur un `final_prompt_chars` mesuré de 25 260 : **60 % du prompt du Prisme est le
World Scan**. Prompt contractuel 6 161 chars ; résidu 3 947 chars = section pré-mortem
(`premortem_sha256` présent au manifeste) + section tâche.

**Preuve sémantique (usage, pas seulement transmission)** —
`check_prisme_manifest.mjs prisme.json --worldscan worldscan.json` :
`VERDICT PRISME: OK`, 5 exigences / 5 actionnables / **4 sur 4 références ancrées** dans le World
Scan, 0 référence non ancrée. Le Prisme ne cite pas le World Scan : ses exigences y sont
**vérifiablement ancrées**. C'est `USED`, pas `CITED`.

**Falsification préalable du mécanisme, à coût nul** — `upstream_artifacts_section` testée avec
contrôles négatifs : étape déclarée → contenu reçu · étape NON déclarée (`s12-verdict`) → section
vide, aucune fuite · artefact absent → section vide sans exception.

**Défaut mesuré, NON corrigé — perte à la transmission** : l'artefact `s2-worldscan.txt` fait
23 726 octets ; `UPSTREAM_MAX_CHARS = 15 000`. **37 % du World Scan n'atteint jamais le Prisme**,
avec mention `[tronqué]` honnête. La borne est déclarée, pas silencieuse — mais elle mordra plus
fort à mesure que le GM Scan ajoutera des matrices quantitatives à l'amont. À traiter avant P5.

**Écart de comptage observé** : `spawn` = `prepared 4 · prepared_distinct 2 · authorized 2 ·
executed 4 · unproven []`. Cohérent avec le défaut déjà consigné du panel Prisme (plusieurs
process pour une ligne d'audit). Constaté, non corrigé, hors périmètre.

### 6.2 Découverte de P1 — `_STEP_TOOLS` vide n'est PAS une borne `[M]`

La sortie de `s1-prisme` rapporte des valeurs exactes de `state.json` (`is_game: false`,
`profile: "amont_only"`) — introuvables dans son prompt : vérifié absentes du prompt contractuel
(6 161 ch.), de la section amont (15 152 ch.) et du pré-mortem (491 ch.).

Cause mesurée : `_STEP_TOOLS` n'a **aucune entrée** pour `s1-prisme`, donc
`--permission-mode manual` **sans** `--allowedTools` (`run_real.py:540-546`).

**Hypothèse d'héritage — FALSIFIÉE, 2026-08-13** `[M]`. Première explication avancée puis
retirée : « le subprocess hérite des 496 entrées d'allow de `.claude/settings.local.json` ».
C'est faux. Mesuré : ce fichier n'autorise `Read` que sur **3 chemins** (`//mnt/c/**`,
`//root/**`, `//c/Users/<utilisateur>/**`) — le dépôt est `/c/TACTICAL_CHESS_STUDIO`, qui n'en
match **aucun** — et `Glob`/`Grep` y ont **0 entrée**, comme dans `settings.json`.

=> Cause réelle : **`--permission-mode manual` ne filtre pas les outils de lecture.** Aucune
allow-list n'est nécessaire pour que `Read`/`Glob` passent. Le seul levier effectif est le
**deny-list** (`--disallowedTools`). **Constaté, non corrigé.**

**Caveat imposé à 6.1** : l'agent ayant un accès disque, l'ancrage 4/4 prouve la **consommation**
du World Scan, mais ne sépare pas « lu depuis le prompt injecté » de « lu depuis
`worldscan.json` sur disque ». L'injection elle-même reste prouvée par l'arithmétique du prompt
(15 152 ch. mesurés) et par la falsification à contrôles négatifs de
`upstream_artifacts_section`. Une séparation stricte exigerait un run à lecture refusée. `[H]`

**Portée de P1, révisée (Pierre 2026-08-13)** `[D]` :

| surface | statut |
|---|---|
| construction de la section upstream | **TESTED** |
| injection dans le prompt final | **TESTED** |
| absence de fuite vers étape non déclarée | **TESTED** |
| utilisation du World Scan | **TESTED** |
| causalité exclusive « usage via injection » | **UNKNOWN** |
| zéro-outil réellement borné | **BLOCKED** |

### 6.3 P1.1 — déclaré ≠ autorisé ≠ utilisé `[M]`

Trois niveaux à prouver séparément. Mesure du 2026-08-13 sur les 17 étapes des profils :

| niveau | état |
|---|---|
| **déclaré** (`_STEP_TOOLS`) | mesurable — 5 étapes avec allow-list, 12 vides |
| **autorisé** (effectif) | pour les 12 vides : `--permission-mode manual` **sans** allow-list ⇒ héritage de `.claude/settings.local.json`, **496 entrées** |
| **utilisé** | **NOT_MEASURED** — `tool_observability` rend `loaded.status: NOT_MEASURED`, `tools: []` |

Sur les 12 déclarations vides, 5 sont des étapes **déterministes** (`s10a/b/c`, `s10s`, `s12`) qui
ne lancent aucun sous-processus : sans objet. Restent **7 étapes LLM sans borne de capacité** —
`s0-contrat`, `s1-prisme`, `s2-worldscan`, `s3-decompo`, `s4-archi`, `s5-wiremap`,
`s6-redteam-plan`. C'est **toute la chaîne de conception**.

Les 5 étapes avec allow-list explicite (`s2.5-artbible`, `s9-build`, `s9-build-standard`,
`s9-build-godot-standard`, `s11-redteam-code`) sont exactement celles qui écrivent du code.
=> **Le dépôt borne ce qui construit, pas ce qui conçoit.**

Couverture du deny-list : `Read` refusé sur **un seul chemin**
(`Read(lab/workflow_lab/**/control/**)`) ; `Glob` et `Grep` **pas refusés du tout**.

**Exigence `[D]`** : `NO_TOOLS` doit signifier `Read`/`Write`/`Edit`/`Bash`… **interdits**, pas
« aucune allow-list locale → héritage permissif ».

#### GO-2 — falsification exécutée, 2026-08-13 : la frontière n'existe pas en LECTURE `[M]`

Test via le **vrai chemin de code** (`_claude_call_raw(..., tools=())`, mêmes flags que la
production : `--permission-mode manual`, `--disallowedTools _STEP_DISALLOWED`,
`--strict-mcp-config`, `--add-dir REPO_ROOT`), modèle `claude-haiku-4-5-20251001`.

| capacité | réponse | falsification indépendante | verdict |
|---|---|---|---|
| `Read` | `JETON_ZEROTOOL_7q4x9m2v8k3d` | jeton non devinable, écrit juste avant le test | **DISPONIBLE** |
| `Glob` | `51` | 51 = nombre EXACT de fichiers de `scripts/forge/contracts/` (49 `.yaml` + 2 `.md`) — non produisible par hasard ; filtre approximatif, outil réellement exécuté | **DISPONIBLE** |
| `Write` | `NO_WRITE` | fichier sonde vérifié **absent** sur disque | **BLOQUÉ** |

L'agent a déclaré lui-même `TOOLS=Read,Glob`.

=> **Réponse à GO-2 : NON.** Une étape déclarée sans outil n'est PAS bornée : elle lit et
parcourt tout le dépôt. Seule l'écriture est fermée. La déclaration `_STEP_TOOLS = ()` est une
borne d'**écriture**, jamais une borne de **capacité**.

Portée : les **7 étapes LLM de conception** (`s0-contrat`, `s1-prisme`, `s2-worldscan`,
`s3-decompo`, `s4-archi`, `s5-wiremap`, `s6-redteam-plan`). Problème **transversal**, pas local.

Conséquence sur P1 (§6.1/6.2) : la réserve est **confirmée, pas levée**. `s1-prisme` disposait
réellement de `Read` ; « consommé exclusivement depuis l'injection » reste **UNKNOWN**, et le
restera pour toute flèche prouvée dans ces conditions. Une isolation causale stricte exige un
run à lecture effectivement refusée — ce qui n'existe pas aujourd'hui.

Surface **BLOCKED** maintenue : la sémantique zéro-outil est désormais **démontrée fausse**,
pas seulement non démontrée.

#### P1.2 — spécification du levier, MESURÉE en 3 essais `[M]`

Diagnostic avant réparation. Trois appels `claude -f haiku` via `_claude_call_raw(tools=())`,
`_STEP_DISALLOWED` étendu **en mémoire uniquement** — aucun fichier du dépôt modifié.

| essai | deny appliqué | `READ` | `SEARCH` | frontière |
|---|---|---|---|---|
| 1 | `_STEP_DISALLOWED` actuel | jeton exact | 51 (exact) | **ouverte** |
| 2 | + `Read`, `Glob`, `Grep` | `NO_READ` | **51 (exact)** via `Bash` | **ouverte** |
| 3 | + `Bash`, `PowerShell`, `ToolSearch`, `Task`, `Agent` | `NO_READ` | `NO_SEARCH` | **TIENT** |

**L'essai 2 est le résultat le plus instructif** : refuser `Read`/`Glob`/`Grep` ne ferme rien —
`Bash` reste un passe-partout (`ls`, `cat`, `grep`) et n'est refusé que sur `Bash(git:*)`.
Application directe de la loi du déplacement déjà consignée par le studio : durcir un axe pousse
le défaut sur l'axe non mesuré. Observée ici en un seul essai.

=> **Un `NO_TOOLS` réel exige de refuser l'ensemble
`{Read, Glob, Grep, Bash, PowerShell, ToolSearch, Task, Agent}`**, pas seulement les outils de
lecture. Spécification obtenue par mesure, non par supposition. **Non implémentée — en attente
d'un GO.**

Réserve de portée `[H]` : l'ensemble ci-dessus est validé contre les capacités observées lors de
ces essais. Tout outil futur du harnais capable de lire (ou tout MCP) rouvrirait la frontière —
c'est pourquoi la réparation durable est une **borne positive** (allow-list exhaustive) plutôt
qu'une énumération de dénis, qui restera toujours en retard d'un outil.

#### P1.2 — RÉPARATION IMPLÉMENTÉE (GO Pierre 2026-08-13) `[M]`

**Mesure qui a fixé la forme** : `--allowedTools Write` seul (sans `Read`/`Glob`/`Bash`) laisse
TOUJOURS lire le jeton et compter les fichiers. => **une allow-list PRÉ-APPROUVE, elle ne
RESTREINT pas.** Une « borne positive » appliquée par `--allowedTools` est donc impossible : le
seul organe d'application est `--disallowedTools`.

**Forme retenue** — positive en DÉCLARATION, dérivée en APPLICATION :
`_TOOL_UNIVERSE` (13 outils) · `_tool_base()` · `_derive_disallowed(allowed)` =
dénis de chemin existants **+ complément de la déclaration**, dédoublonné.
Une étape sans entrée `_STEP_TOOLS` devient **totalement bornée (fail-safe)** au lieu de
totalement ouverte (fail-open).

`Glob`/`Grep` **déclarés explicitement** sur les 5 étapes outillées : déclaration d'une capacité
qu'elles possédaient déjà de fait, pas un octroi. `[H]` à requalifier quand le niveau 3
(outil effectivement utilisé) sera mesuré.

**Falsification contre le harnais réel, même sonde qu'avant/après** :

| cas | avant | après |
|---|---|---|
| `tools=()` | jeton exact · `SEARCH=51` | `READ=NO_READ` · `SEARCH=NO_SEARCH` · « aucun outil invocable » |
| `tools=("Write",)` | jeton exact · `SEARCH=51` | `READ=NO_READ` · `SEARCH=NO_SEARCH` |

**Limite déclarée, non refermable ici** : `_TOOL_UNIVERSE` est une énumération. Un outil natif
futur absent de la liste rouvrirait la frontière sans qu'aucun test ne le voie —
`--strict-mcp-config` ferme le vecteur MCP, le vecteur « nouvel outil natif » demande un capteur
de dérive du vocabulaire d'outil : le **même capteur manquant** que celui qui a laissé passer
`Task` → `Agent` sur le `PostToolUse`. Un seul capteur fermerait les deux failles.

**Hypothèse falsifiée par le dépôt — `Glob`/`Grep` sur les 5 étapes outillées** `[M]` :
ajoutés d'abord (motif : capacité possédée DE FAIT, que le complément allait retirer), puis
**retirés** après régression — **7 tests** les ont refusés, dont
`test_s9_build_a_les_outils_du_contrat_ratifie`,
`test_s9_build_standard_allowlist_matches_what_was_measured` et
`test_s2_5_artbible_outils_bornes`. Ces gardes encodent des jeux d'outils **ratifiés** : les
élargir demande une gate Pierre, pas une hypothèse d'exécutant. Table laissée inchangée.
=> Conséquence assumée : les forgerons **perdent réellement** `Glob`/`Grep`, le complément
appliquant désormais exactement le jeu ratifié. Aucun test ne couvre un build réel et le
niveau 3 est `NOT_MEASURED` : **impossible de savoir si un forgeron s'en servait** sans lancer
un build. Risque ouvert.

**Régression finale** `[M]` : `pytest scripts/forge/tests/` = **2 failed / 1672 passed /
1 skipped** (32 min 07) — **identique à la baseline**, mêmes deux échecs pré-existants
(`test_repo_map_reel_…`, `test_full_profile_is_untouched_…`). **Zéro régression introduite.**

Reste absent : **aucun test unitaire ne couvre `_derive_disallowed`** — `scripts/forge/tests/`
relève de la zone protégée (`.claude/rules/tests.md`), son ajout demande une gate Pierre. La
borne est donc prouvée par falsification en vivo, pas gardée contre une régression future.

#### P1.2 — RÉGRESSION DE PRODUCTION, révélée par P1.3 `[M]`

**La suite verte n'a rien vu. Le premier run réel a cassé.**

Run `p1-3-exclusivity-20260813` (profil `amont_only`) : **HALTED à `s2-worldscan`**, jamais
parvenu à `s1-prisme`. Motif : *« artefact worldscan.json non matérialisable — aucun bloc
```json``` valide (0 bloc fenced inspecté) »*. La même étape avait réussi en P1.

Cause mesurée : `s2-worldscan` n'a **aucune entrée** dans `_STEP_TOOLS`. Depuis P1.2, le
complément lui refuse donc les 13 outils de `_TOOL_UNIVERSE` — **`WebSearch` et `WebFetch`
inclus**. Or son `output_contract` exige `sources[{url, type: screenshot|video|article|wiki}]`
et son objectif est *« produire une OBSERVATION sur ≥2 jeux comparables »*. **Sans accès web,
l'étape ne peut pas remplir son contrat** : elle a répondu en prose, sans JSON.

Trois enseignements, dans l'ordre d'importance :

1. **Le fail-safe de P1.2 est un fail-safe correct qui rend visible une déclaration manquante.**
   `s2-worldscan` avait besoin du web et ne l'avait jamais déclaré — il en disposait par le
   fail-open. La borne n'a pas créé le défaut, elle l'a exposé.
2. **La suite de tests est aveugle à cette classe de panne** : 1672 tests verts, aucun n'exécute
   un `s2-worldscan` réel. Application directe de « les tests verts ne suffisent pas comme
   critère de fin ».
3. **P1.3 n'a mesuré aucun de ses trois axes** — TRANSMISSION, EXCLUSIVITÉ, SUFFISANCE restent
   `NOT_MEASURED`. L'expérience a été interrompue par une cause étrangère à sa question.

État de l'arbre : **une exécution réelle de la Forge échouerait aujourd'hui à `s2-worldscan`.**
Correction non appliquée — déclarer `WebSearch`/`WebFetch` pour cette étape élargit une
allow-list, ce qui demande une gate (leçon du retrait `Glob`/`Grep`). **HUMAN_REQUIRED.**

#### M1 — IMPLÉMENTÉ (GO Pierre 2026-08-13) : `contract.permissions` source de la déclaration `[M]`

Audit préalable : `CAPABILITY_AUDIT_P13_20260813/CAPABILITY_MATRIX.md` — le champ `permissions`
des contrats (grammaire verbale régulière **24/24**) n'était consommé par aucun code ; deux
tables indépendantes, divergentes 7/7 sur la conception.

**Mécanisme** (`run_real.py`) : `_tools_from_permissions()` (dérivation déterministe) +
`_effective_step_tools()` — priorité : **ratification `_STEP_TOOLS`** (gardée par 7 tests) →
**dérivation du contrat** → **`()` fail-safe**. Politique étroite : `read:` ≠ aucun → `Read` ;
`run:` citant un nom de `_TOOL_UNIVERSE` → ce nom ; `write:`/`create:`/`Edit`/`Glob`/`Grep`
**jamais dérivés** (patron matérialisation + leçon Glob/Grep). Vérifié sur les 24 étapes :
5 ratifiées intactes · 7 étapes de conception → `('Read',)` · `s2-worldscan` →
`('Read','WebFetch','WebSearch')` · étape illisible → `()`.

**Falsification en vivo** — run `p1-3b-m1-20260813` (`amont_only`, sonde neuve) :
`s2-worldscan` **OK** (HALTED avant M1) · `s1-prisme` **OK**. La Forge amont est
**ré-exécutable**, avec des capacités qui viennent du contrat.

**P1.3 — axes mesurés sur ce run :**

| axe | résultat |
|---|---|
| TRANSMISSION | **TESTED** — 6 157 + 15 138 = 21 295 vs 25 220 mesurés (60 % du prompt = World Scan ; résidu = pré-mortem + tâche, même structure que P1) |
| SUFFISANCE | **TESTED** — `VERDICT PRISME: OK`, 8 exigences / 8 actionnables / **7/7 références ancrées** (P1 : 5/5, 4/4) — qualité maintenue |
| EXCLUSIVITÉ | **UNKNOWN — non mesurable désormais PAR CONTRAT** : `s1-prisme` exige `read: repo`, M1 le lui rend légitimement ; un run « s1 sans lecture » contredirait son contrat. La mesurer exige une modification de contrat = gate. |

**Défaut persistant** : troncature — artefact s2 = 24 998 octets, section amont plafonnée
15 138 (`[tronqué]` présent). **~39 % du World Scan perdu**, cohérent avec P1 (37 %). Toujours
à traiter après P2 (décision Pierre : mesurer le volume réel de la chaîne amont d'abord).

`humangate_flags: []` et `BLOCKED` de fin de run = absence normale de `s12` en `amont_only`.

**Régression M1** `[M]` : **3 failed / 1671 passed / 1 skipped** (33 min 05). Deux échecs
pré-existants inchangés + **un nouveau, attendu et expliqué** :
`test_context_manifest_p4_p7_execution_fields.py:88` encode l'ancienne sémantique « étape absente
de `_STEP_TOOLS` → tuple vide » et vérifie `s6-redteam-plan → []` ; M1 (ratifié) rend désormais
`('Read',)` par dérivation du contrat. **Le test est périmé par la ratification, pas cassé** —
mais il vit en zone protégée (`.claude/rules/tests.md`) : son amendement demande une gate Pierre
explicite. **HUMAN_REQUIRED — GATE-TEST-M1** : aligner l'attendu du test sur la sémantique M1
(`tools_effective == ['Read']` pour s6, ou assertion sur `_effective_step_tools`). Jusque-là, la
suite porte UN rouge documenté de plus que la baseline.

### 6.4 P2a — le véhicule ratifié ne peut pas porter la charge `[M]`

Voie retenue par Pierre : matérialiser `product_snapshot.md` depuis la sortie existante de
`s1-prisme` via `_ARTIFACT_BY_STEP`. **Non implémentable tel quel**, pour deux raisons de forme :

1. `_materialize_artifact` (`run_real.py:871+`) appelle `extract_json_payload` puis
   `_ARTIFACT_VALIDATORS[artefact]` — chaîne **strictement JSON**. Un `.md` y déclencherait une
   extraction JSON sur du markdown, puis un `KeyError` de validateur.
2. `_ARTIFACT_BY_STEP` est un dict **une étape → UN fichier**, et l'entrée `s1-prisme` est déjà
   prise par `prisme.json`. Un second artefact par étape n'y est pas exprimable.

Forme implémentable équivalente, **même intention, même périmètre runtime** `[H]` : un mécanisme
jumeau (ex. `_MARKDOWN_BY_STEP`) écrivant la portion NON-JSON de la réponse de `s1-prisme`, validée
par `check_prisme.mjs` (le validateur existe déjà et attend exactement ce fichier). Aucune station
neuve, aucun contrat touché. **Non implémenté — le véhicule n'est plus celui qui a été ratifié.**

**Qwen reste hors périmètre de toute cette phase** `[D]`. Le routage économique ne se traite
qu'après l'existence d'une frontière réelle `CONSEILLER ≠ PRODUCTEUR`.

---

### 6.5 Actes en attente de GO explicite — état au 2026-08-13 `[D]`

Deux sujets **distincts**, à ne pas fusionner : l'un est une matérialisation d'artefact, l'autre
une frontière d'outillage.

| # | acte | portée | état |
|---|---|---|---|
| **GO-1** | P2a — mécanisme texte (`_MARKDOWN_BY_STEP` ou équivalent) écrivant `product_snapshot.md` depuis la réponse de `s1-prisme`, preuve par `check_prisme.mjs` | runtime seul · **aucune station neuve** · **aucun contrat touché** | **en attente** |
| **GO-2** | falsification zéro-outil — un appel `claude -p` de contrôle, `--permission-mode manual` sans allow-list, sur une lecture ciblée | **aucune modification du dépôt** | **en attente** |

Contraintes ratifiées attachées :
- `product_snapshot.md` est un **artefact TEXTE**. Ne pas le forcer dans `_ARTIFACT_BY_STEP`
  (chaîne JSON, une entrée par étape, déjà occupée par `prisme.json`).
- Ne PAS remplacer `product_snapshot.md` par `prisme.json` dans les contrats aval : ce serait
  contourner le problème au lieu de réparer le producteur attendu.
- Principe directeur : **ne pas ajouter une station quand une station existe déjà — réparer la
  flèche qui l'alimente.**

Chantier transversal identifié, non planifié : faire correspondre les permissions **déclarées**
aux permissions **effectives**, plutôt que de tenir `_STEP_TOOLS` pour une preuve suffisante.

## 6ter. R1' + M3 — implémentés sous GO Pierre 2026-08-13, validés `[M]`

**R1' — lignée Return structurée.** Clause `RETURN_REASON` dans `RESTITUTION_RULE`
(`contract.py`, source unique rendue dans tous les prompts) · extraction déterministe 3 états
(`run_real._extract_return_reason`, falsifiée 6/6 dont collision-artefact et
DISCOVERED-sans-problem) · enregistrement `kind: "return"` signé HMAC dans le fichier jumeau
`<etape>.return.manifest.jsonl` (`context_manifest.append_return_manifest`) — découvert par le
glob de `promote_manifest_lessons` et `verify_run` sans câblage, structure du manifeste
historique intacte (3 tests de garde avaient refusé l'append au même fichier). **En vivo, run
`p2a-return-snapshot-20260813`** : `s2 → NOT_DISCOVERED` honnête · `s1 → DISCOVERED` avec
problème réel (« charter.yaml absent du run_dir ») et cause racine exacte. Le canal Return
produit — première fois dans l'histoire du dépôt.

**M3 — matérialiseur texte `product_snapshot.md`.** `_MARKDOWN_BY_STEP` +
`_materialize_markdown` (réponse moins blocs JSON moins marqueur Return) + reçu
`check_prisme.mjs` joint au retour (`res["markdown_check"]`, advisory). **TESTED sur la sortie
réelle historique P1** : 11 349 chars écrits, JSON retiré, checker exécuté, verdict **FAIL
honnête** (la tâche de la sonde ne demandait pas le format). Bout-en-bout in-vivo :
`BLOCKED_BEFORE_TARGET` (run p2a arrêté à la matérialisation JSON de s1).

**GATE-TEST-M1** : attendu du test amendé sous gate (`[] → ['Read']` + assertion de cohérence
avec `_effective_step_tools`), gate consignée dans la docstring du test.

**Suites** : après gate-test **2/1672** (baseline) · après R1'+M3 **2/1672** (baseline) —
zéro régression sur les trois GO. Tests ciblés : 144/144 et 70/70.

### R1'' — rupture suivante de la même lignée, découverte par la validation — HUMAN_REQUIRED

`_promote_manifest_lessons_best_effort` n'est appelée que sur le chemin **DONE**
(`driver.py:407`). Un run qui échoue ne promeut jamais son WHY — or le run p2a l'a prouvé en
vivo : la première lesson Return du dépôt (charter manquant, cause exacte) est signée dans son
manifeste et **non promue** parce que le run a fini HALTED. Les leçons des échecs — les plus
précieuses — sont structurellement perdues. Correctif esquissé : appeler la promotion aussi sur
le chemin HALTED (~3 lignes, mais changement de comportement du driver). **Non implémenté —
distinct de R1', conformément à la règle « ne pas masquer une surface sous une autre ».**

#### R1'' — IMPLÉMENTÉ (GO Pierre 2026-08-13, option a) `[M]`

**Mutation minimale** : un point d'appel `_promote_manifest_lessons_best_effort()` ajouté au seul
point de sortie HALTED de la boucle de `driver.run()`, symétrique du chemin DONE.
`promote_manifest_lessons` et ses critères **intouchés**.

| preuve | résultat |
|---|---|
| falsification stricte du pont | DISCOVERED → **1 CANDIDATE** · NOT_DISCOVERED → **0** · double appel → **0 doublon** |
| reprise réelle de p2a (option a) | `s1` OK à la tentative 2 → run **DONE** · **3 lessons promues** dans `lab/reports/lessons.jsonl` (23→26 lignes), dont LA `DISCOVERED` signée du premier échec (charter absent, cause exacte) |
| chemin HALTED in vivo | **non parcouru** (le run a fini DONE — variance du worker, hors contrôle) |
| point d'appel HALTED | **TESTED par harnais déterministe** : ForgeDriver + stub reproduisant la séquence réelle p2a-t1 (return DISCOVERED écrit puis échec) → run HALTED → **1 lesson candidate promue sur le chemin HALTED**, run_dir hors repo |
| suite complète | **2 failed / 1672 passed / 1 skipped** (33 min 37) — baseline exacte, mêmes 2 pré-existants. **Zéro régression R1''.** |

**Bonus mesuré à la reprise** : le canal d'activation (R1, retry machine) a AUSSI produit sa
lesson (« échec de la tentative 1 à s1-prisme ») — les deux lignées (Activation + Return)
alimentent désormais `lessons.jsonl` sur un même run réel. La lignée est fermée :
`Worker → Return WHY → manifeste signé → DONE ou HALTED → promotion → Lesson`.

## 7. Décisions humaines ouvertes

### 7.1 Identité structurelle du Producteur — HUMAN_REQUIRED

Mesuré `[M]` sur 196 transcrits : **563 spawns, 100 % nommés `Agent`, 0 `Task`** ;
`subagent_type` présent 562/563 ; **492/563 en `general-purpose`**. Les 17 types du dépôt sont des
rôles de conseil (15 en `disallowedTools: Write, Edit`) ; les 2 seuls capables d'écrire
(`economy-designer`, `ui-programmer`) **ne sont pas résolus par le harnais**.

Acquis nouveau `[M]` : **l'identité de production existe déjà — sur le chemin driver.**
`run_real._claude_call_raw` construit l'appel enfant avec `--model` (résolu par `roles.yaml`),
`--allowedTools` (`_STEP_TOOLS[etape]`), `--disallowedTools`, `--strict-mcp-config`. Ce sont des
flags du **parent** : l'enfant ne peut pas les omettre. Le routage y est déjà non-Opus
(`s9-build → haiku`, `s6-redteam-plan → qwen2.5-14b-instruct`).

Le trou n'est donc pas « aucune identité producteur » mais **deux chemins de création, dont un
seul est typé — et la production réelle a emprunté l'autre.**

Défaut jumeau, re-mesuré, non corrigé : `PostToolUse` matche `Task` (`settings.json`) alors que la
production émet `Agent` → l'organe de preuve ne s'exécute jamais. **NOT_WIRED.**

### 7.2 Création des stations amont — HUMAN_REQUIRED
7 stations `NOT_FOUND` (Story/Quest/Character Bible, GM, Grey Block, Construction Matrix,
GM Validation Scan) + 10 matrices. Créer un contrat touche un invariant : le dépôt pose que
« le contrat est intouchable sans gate Pierre explicite » (`run_real.py:256`, `:1254`).

### 7.3 Réparation des 2 orphelins — portée RÉDUITE après correction
Affirmation précédente, **fausse et retirée** : « aucun chemin de réparation ne contourne la porte
des contrats ». Elle reposait sur l'idée que le câblage se fait dans `mandatory_read`.

Réalité mesurée : le câblage se fait dans **`_UPSTREAM_BY_STEP`** — du Python (`run_real.py:972`
et `context_manifest.py:61`), pas un contrat YAML. Brancher l'Art Bible ou
`parametres_de_design_source` est donc une modification de code ordinaire, protégée par un test
d'égalité stricte, **hors du gate contrat**.

Ce qui reste derrière la porte §7.2 : créer une ÉTAPE (contrat neuf), pas connecter un artefact
existant. La distinction change l'ordre de travail : P1 devient exécutable immédiatement.

---

### 7.4 Architecte-constructeur — orientation Pierre 2026-08-13, faisabilité mesurée

**Orientation `[D]`** : l'Architecte (palier Opus) possède la WireMap **et** est responsable de la
réalisation du jeu ; il délègue les tâches mécaniques à des workers Qwen, récupère les résultats,
vérifie les preuves, et **c'est lui qui décide** du retry ou de l'escalade — jamais le worker.
Escalade visée : Qwen → retry → Sonnet après 2 échecs. Le `builder` disparaît comme rôle
conceptuel, les capacités de build restant dans le dépôt.

**Ce qui existe déjà `[M]`** — le rôle est largement présent sous un autre nom :
`roles.yaml` porte **`game_forger`** au palier Opus (gate Pierre 2026-07-22), câblé à
`s9-build-godot-standard`, décrit comme *« forge un JEU ENTIER depuis un squelette gelé […]
raisonnement soutenu sous contrainte, pas exécution mécanique — `builder` (haiku) reste juste
pour ce à quoi il était calibré : une brique isolée »*. La distinction Architecte-constructeur /
builder-de-brique est donc **déjà ratifiée et câblée**.

**Ce qui n'existe pas `[M]` — deux blocages structurels, pas des réglages :**

1. **Qwen ne peut pas écrire.** `runtime.py:114-130` — `run_qwen_step` appelle
   `ad.complete(payload.prompt)` et rend `{ok, reviewer, output: <texte>}`. Aucun outil, aucun
   `Write`, aucun accès disque. Un worker Qwen ne peut pas produire de fichier : sa sortie devrait
   être écrite par l'Architecte. « Déléguer la construction à Qwen » signifie aujourd'hui
   « demander du texte à Qwen et l'écrire soi-même ».
2. **L'échelle d'escalade ignore Qwen.** `escalate.py:19` — `LADDER = ("haiku","sonnet","opus")`,
   une échelle de familles Claude. `tier_of(<id qwen>)` rend `None`, donc `next_tier` rend `None`.
   La règle « Qwen ×2 échecs → Sonnet » n'est pas exprimable dans le mécanisme actuel.

**Écarts de registre `[M]`** : `claude-opus-5` **n'est pas** dans `roles.yaml` (le registre porte
`fable-5`, `opus-4-8`, `sonnet-5`, `haiku-4-5`, `qwen2.5-14b`). `sonnet-5` y est présent mais ne
résout qu'un seul rôle, `forge_toolsmith`. Les rôles Qwen déclarés sont `redteam_reviewer`,
`repair_runtime`, `asset_spec_author` — **aucun rôle de construction**.

**Conséquence de séquencement `[H]`** : cette orientation n'est pas bloquée par la porte des
contrats (§7.2) mais par deux chantiers de runtime — donner une capacité d'écriture à un worker
Qwen, et étendre l'échelle d'escalade à un tier non-Claude.

### 7.4.1 Cible ratifiée — Pierre, 2026-08-13 `[D]`

1. **`game_forger` / Architecte = propriétaire de la WireMap et constructeur du jeu.**
   **Aucun rôle `architect-builder` n'est créé** — `game_forger` est déjà le bon concept.
2. **Opus 5** = modèle cible de ce rôle.
3. **Qwen = worker spécialisé outillé** — pas un second cerveau constructeur. Il produit des
   modifications locales ; il doit devenir réellement capable de modifier des fichiers.
4. **Deux échecs consécutifs sur le même travail → escalade Sonnet.**
5. **L'escalade doit être une règle générique de runtime**, pas une exception codée pour Qwen.
6. Le builder générique `haiku` **reste disponible** pour les petites briques qui ne nécessitent
   pas le Game Forger.
7. **Aucun changement de code maintenant** — la chaîne cible se fige d'abord entièrement.

```
Opus 5 / game_forger  ──  possède WireMap · architecture · build plan · construction
        │                 conserve le WHY, les invariants, la décision d'intégration
        ├── tâche A → Qwen ─┐
        ├── tâche B → Qwen ─┼── production spécialisée, modifications LOCALES
        ├── tâche C → Qwen ─┘
        └── intégration + jugement
                 ├── OK    → continue
                 └── FAIL ×2 → Sonnet
```

Un seul propriétaire de la construction, plusieurs mains d'exécution — conforme à
`FORGE_CAUSAL_LINEAGE_V2`.

### 7.4.2 Statut par surface de cette cible `[M]`

| surface | statut |
|---|---|
| `game_forger` comme responsable du jeu entier | **IMPLEMENTED** |
| Architecte propriétaire de la WireMap | **DOCUMENTED_ONLY** — à appliquer au routage |
| `claude-opus-5` dans le registre | **NOT_FOUND** — registre sur `opus-4-8` |
| Qwen worker avec capacité d'écriture | **BLOCKED** — `runtime.py:114-130`, texte seul |
| Qwen → Sonnet après 2 échecs | **NOT_FOUND** — `LADDER` = familles Claude |
| escalade comme règle générique | **PARTIEL** — voir 7.4.3 |
| builder `haiku` pour petites briques | **IMPLEMENTED** — conservé |
| Oracles → Playtest → Lessons | **IMPLEMENTED** / **PASSIVE** selon la surface (§3) |

### 7.4.3 Le point 5 est moins coûteux qu'il n'en a l'air `[M]`

`escalate.py` est **déjà générique dans sa forme** : `tier_of(model, ladder=LADDER)` et
`next_tier(model, ladder=LADDER)` prennent l'échelle **en paramètre**, avec `LADDER =
("haiku","sonnet","opus")` pour seul défaut. Rendre l'escalade générique au sens du point 5 est
donc un changement de **donnée** (l'échelle injectée, ex. `("qwen","sonnet","opus")`) et de son
lieu de déclaration — pas une réécriture du mécanisme. Le blocage réel du point 4 reste le
point 3 : sans capacité d'écriture, un worker Qwen n'a pas d'échec de construction à compter.

Réserve déjà consignée dans `roles.yaml` et toujours non implémentée : *« l'orchestrateur ne doit
pas consommer le tier maximal en permanence » — aucun mécanisme ne porte cette règle,
`escalate.py` ne couvre que les builders.* La cible 7.4.1 place `game_forger` au tier maximal sur
l'étape la plus longue de la chaîne : cette réserve devra être assumée explicitement, pas
redécouverte.

## 8. Risques connus au moment du gel `[M]`

- `test_full_profile_is_untouched_by_the_standard_addition` **rouge à HEAD** : `ORDER[1]` vaut
  `s2-worldscan`, le test attend `s1-prisme`. L'`ORDER` a déjà bougé une fois sans son garde.
- `test_repo_map_reel_tous_les_gabarits_test_et_asset_portent_un_id` rouge.
- Baseline re-mesurée ce jour : **2 failed / 1672 passed / 1 skipped** (31 min 34 s).
- Working tree : 40 M / 2 D / 67 ?? non commités, 47 commits d'avance sur `origin/master`.
  Toute création de contrat coexisterait avec du travail non commité d'une autre lignée.

`NO_GLOBAL_READY_VERDICT: true`
