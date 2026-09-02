# CAPABILITY MAP — cible × ancien Studio

*2026-09-01 · **DOCUMENTED_ONLY** · aucun code, aucun déplacement, aucune suppression, aucun test
exécuté. Dépôt source à `feeb29cb`, non touché.*

`TARGET CAPABILITY MODEL` → `OLD STUDIO HARVEST` → **`MAPPING`** (ce document).
Critère : **optimal ≠ minimal**. Une capacité peut rester complexe si cette complexité apporte
vitesse, qualité, fiabilité ou réutilisation.

---

## ⚠ Collision de nom à trancher AVANT de propager le vocabulaire

`blueprint.json` **existe déjà** dans le studio — produit par `s4-archi`, il contient :
```
modules · deps_interdites · ownership · responsabilites
  ex. modules: ["economy","render","input","main","solvability"]
      deps_interdites: [["economy","render"], ["render","input"], …]
```
C'est le **contrat d'architecture logicielle**, vérifié par `s10b-oracle-archi`. Ce n'est **pas**
le `GAME_BLUEPRINT` de la cible.

**Deux objets, deux noms** — proposition : `GAME_BLUEPRINT` (l'objet central de conception) et
`ARCHITECTURE_CONTRACT` (l'actuel `blueprint.json`). Laisser deux « blueprint » cohabiter
fabriquerait exactement le genre d'ambiguïté qu'on passe la session à retirer.

---

## Le modèle — les flèches sont des **relations**, pas des étapes

```
                          VISION HUMAINE
                                │
                                ▼
                         GAME_BLUEPRINT ◄──────────────┐
                                ▲                      │
                                │  tous amendent       │
                         FABLE / DIRECTOR              │
                                │                      │
              ┌─────────────────┼─────────────────┐    │
              ↕                 ↕                 ↕    │
           DESIGN             ART              TECH    │
        gameplay·systems    direction      architecture│
        economy·progr·UX        ↕                 ↕    │
              └─────────────────┴─────────────────┘    │
                                ↕                      │
                        GAME IMPLEMENTATION            │
                                │                      │
                    ┌───────────┴───────────┐          │
                    ↕                       ↕          │
                   QA                   OBSERVER       │
                    └───────────┬───────────┘          │
                                ▼                      │
                            EVIDENCE ──── rework ──────┘
                                │                (via Fable, jamais « l'étape 7 »)
                                ▼
                            HUMAN GATE
```
Relations réelles : `Design ↔ Tech` · `Art ↔ Tech` · `QA ↔ Design` · `Architect ↔ Builder` ·
`QA ↔ Architect`. **Toute capacité peut être rappelée quand une information nouvelle apparaît.**

## La chaîne que le Blueprint doit porter de bout en bout

```
VISION → REQUIREMENTS → FEATURES → DESIGN → METRICS → IMPLEMENTATION INTENT
                                                    → EXPECTED PROOF → ACTUAL PROOF
```
> **Chaque intention importante doit pouvoir être suivie jusqu'à ce que le jeu réel la réalise —
> ou démontre qu'il ne la réalise pas.** C'est plus important que de conserver `s1`, `s2`, `s3`.

---

# Les cartes

**Légende des verdicts** : `REUSE` tel quel · `ADAPT` bonne capacité, mauvaise interface ·
`MERGE` doublon/réparti · `REBUILD` idée valable, implémentation absente ou inutilisable ·
`RETIRE` relique · `UNKNOWN` preuve insuffisante.

---

### C1 · GAME_BLUEPRINT — l'objet central
| | |
|---|---|
| **rôle** | porte la chaîne complète VISION→ACTUAL PROOF ; tous les spécialistes l'amendent |
| **ancien composant** | `FORGE_PROJECT_INPUT_V0` (Brief, 10 champs) + `FORGE_DESIGN_FREEDOM_SPEC_V0` (N1–N9) + `static_oracles::check_project_brief` + `context_manifest` (empreinte sha256) |
| **on récupère** | l'**entrée unique** ratifiée · le pré-vol **fail-closed avant toute dépense LLM** · `provenance` par champ (source absente = FAIL) · les entrées alternatives **interdites** |
| **on adapte** | le Brief devient les sections `identity/vision/constraints` ; il devient **vivant** (amendable) au lieu d'être figé à l'entrée |
| **on fusionne** | `charter.yaml` · `art_bible.md` · `prisme.json` · `gm_worldscan.json` · `featuremap.json` · `wiremap.json` · `loop.json` · `economy.json` · `design_questions.json` deviennent des **sections**, plus des artefacts d'étapes |
| **on reconstruit** | `research` · `understanding` · `design_metrics` · `ux` · `technical` — absents du Brief |
| **on abandonne** | rien |
| **interface Fable/Blueprint** | Fable lit tout, n'écrit que `decisions` ; Pierre seul écrit `vision`, `must_not_have`, `scope`, et pose les **cibles** de `design_metrics` |
| **verdict** | **ADAPT** |

### C2 · FABLE — Game Director
| | |
|---|---|
| **rôle** | maintient la cohérence de la vision · décide quelles capacités interviennent · arbitre · autorise le build |
| **ancien composant** | `contracts/orchestrator.yaml` · `contracts/roles.yaml` · `driver.py` (boucle, renvois, agrégation) · `escalate.py` (haiku→sonnet→opus) |
| **on récupère** | la séparation déjà gravée *« Pierre → session Claude à contexte propre → agent orchestrateur → workers »* · la boucle du driver · l'escalade · l'agrégation d'oracles · **29 tests `driver`** |
| **on adapte** | `self.order = order_for_profile(profile)` → composition pilotée par le Blueprint |
| **on fusionne** | les 19 `PROFILES` : les 5 mono-capacité deviennent des appels de capacité, les composés disparaissent |
| **on reconstruit** | la **composition** elle-même — aujourd'hui c'est un humain qui choisit un profil en ligne de commande |
| **on abandonne** | `dispatch.ORDER` (13 étapes) — le workflow imposé |
| **interface Fable/Blueprint** | lit le Blueprint entier · écrit `decisions` (quoi · pourquoi · quand) · n'écrit jamais dans une section de spécialiste |
| **verdict** | **ADAPT** |

### C3 · RESEARCH — connaissance du genre
| | |
|---|---|
| **rôle** | *« qu'est-ce que les joueurs et la presse disent de ce genre ? »* — et surtout **pourquoi ils abandonnent** |
| **ancien composant** | `contracts/s2-worldscan.yaml` (déclare `run: WebSearch, WebFetch` · `skill: world-scan`) · `check_worldscan.mjs` |
| **on récupère** | la capacité web **déjà contractualisée** · l'oracle de conformité · le worker Qwen calibré |
| **on adapte** | déclenchement : **condition de connaissance**, pas position dans une file. *La capacité est obligatoire quand la connaissance nécessaire n'existe pas — pas l'étape* |
| **on fusionne** | avec la KB : le résultat se **capitalise** au lieu de rester dans le run_dir |
| **on reconstruit** | l'axe *frustrations / flops / abandons* et *conventions du genre* — le contrat actuel vise le marché, pas le rejet |
| **on abandonne** | son statut d'étape `s2` |
| **interface Fable/Blueprint** | Fable l'appelle si la KB est insuffisante → écrit `research` → capitalisé en KB |
| **verdict** | **REUSE + ADAPT** · ⚠ **verrou actif Pierre** : *« World Scan hors périmètre »* + *« R8 BLOQUÉ »* |

### C4 · PRISME — rétro-ingénierie
| | |
|---|---|
| **rôle** | *« comment les jeux du genre fonctionnent-ils réellement ? »* + **détecteur d'angles morts** |
| **ancien composant** | `contracts/s1-prisme.yaml` · `prisme.json` · `check_prisme.mjs` · `check_prisme_manifest.mjs` |
| **on récupère** | l'agent (1, actif) · les oracles de conformité · **le rôle de source des exigences traçables** |
| **on adapte** | appelé à la demande, quand Fable veut comprendre les références en profondeur |
| **on fusionne** | avec Research : *« les joueurs détestent X »* + *« X vient de la mécanique Y »* → **décision de design** |
| **on reconstruit** | rien |
| **on abandonne** | le **panel multi-lentilles** (`panel.py`, `prisme/merge_prisme.mjs`, 8 fichiers) — `--charter` jamais passé, `panel.LENSES` jamais alimenté |
| **interface Fable/Blueprint** | écrit `understanding` ; ses exigences deviennent les ancres `source_ref` de C7 |
| **verdict** | **REUSE** (panel : **RETIRE**) |

### C5 · DESIGN — gameplay · systems · economy · progression
| | |
|---|---|
| **rôle** | une **seule** capacité aux responsabilités multiples, pas quatre étapes |
| **ancien composant** | `s0-contrat` → `charter.yaml` · `loop_spec.mjs` (`prisme.json`→`loop.json`, **fonction PURE**) · `game_master_schema.mjs` (`gm_worldscan.json`→`economy.json`, **fonction PURE**) |
| **on récupère** | le charter · et surtout le **verrou absolu** (GO Pierre 2026-08-22) : *« aucun LLM n'écrit jamais `loop.json` ; si un agent tentait de l'écrire, ce serait IGNORÉ »* + vérification sha256 contre `03_WORLD/*.json` du build |
| **on adapte** | le charter devient la section `gameplay` ; les projections restent déterministes |
| **on fusionne** | **System Design n'est pas une nouvelle étape** — economy/progression sont des responsabilités de la conception, alimentant le même Blueprint |
| **on reconstruit** | le **chaînon manquant** : les `design_metrics` (cibles de Pierre) n'entrent nulle part dans les projections. Aujourd'hui `prisme→loop` et `gm→economy` existent ; `metrics→paramètres` n'existe pas |
| **on abandonne** | rien |
| **interface Fable/Blueprint** | écrit `gameplay`, `systems` ; **lit** `design_metrics` (ne les écrit jamais) |
| **verdict** | **REUSE** (projections) + **REBUILD** (chaînon métriques) |

### C6 · UX — capacité de première classe, **absente**
| | |
|---|---|
| **rôle** | le joueur comprend-il ce qu'il voit, ce qu'il peut faire, ce qui vient de se passer ? |
| **ancien composant** | **aucun.** Recherche par mot entier : `\bUX\b` = **2 contrats**, et uniquement comme *chose à observer chez les concurrents* (`s2-worldscan` : « flux UX » des références). `\bux\b` · « expérience utilisateur » · « user experience » · `ergonomie` · `onboarding` : **0 contrat** |
| **on récupère** | rien |
| **on adapte** | rien |
| **on fusionne** | rien |
| **on reconstruit** | **tout** : rôle · contrat 17 champs · sortie · oracle de lisibilité |
| **on abandonne** | rien |
| **interface Fable/Blueprint** | écrit `ux` ; ses exigences descendent en features (C7) et en `design_metrics` de lisibilité |
| **verdict** | **REBUILD** — la seule capacité entièrement neuve |

### C7 · DESIGN BREAKDOWN / FEATURE DEFINITION *(ex-« Décomposition »)*
| | |
|---|---|
| **rôle** | transformer une intention complexe en **unités de design vérifiables** |
| **ancien composant** | `contracts/s3-decompo.yaml` → `featuremap.json` · `check_decompo.mjs` |
| **on récupère** | **l'invariant, sans négociation** : *« `source_ref` cite l'`id` EXACT d'une exigence de `prisme.json` — une feuille qui n'en cite aucune est une **invention non déclarée**, une exigence que nulle feuille ne porte est une **omission silencieuse** »* · le champ `expected_proof {kind, statement}` |
| **on adapte** | **renommée** : « décomposition » est un mauvais nom. Devient Design Breakdown, produisant `FEATURE { requirement · design intent · constraints · expected behavior · metric · expected proof }` |
| **on fusionne** | cesse d'être une étape ; devient une fonction du Director + Design ; sa sortie **est** la section `feature_map` |
| **on reconstruit** | les champs `design intent` · `constraints` · `metric` (le contrat actuel porte `capacite` + `source_ref` + `expected_proof` seulement) |
| **on abandonne** | son statut de station `s3` |
| **interface Fable/Blueprint** | écrit `feature_map` ; son invariant devient un **invariant du Blueprint** |
| **verdict** | **MERGE + ADAPT** |

### C8 · ART DIRECTION
| | |
|---|---|
| **rôle** | identité visuelle, mood, composition, UI |
| **ancien composant** | `s2.5-artbible.yaml` (profil mono-étape `artbible`) · `redteam-artdirector.yaml` · `check_artbible.mjs` · `check_art_response.mjs` |
| **on récupère** | l'agent · **sa red-team dédiée déjà écrite** · 2 tests `.py` + 2 oracles `.mjs` · l'injection de `art_bible.md` au builder |
| **on adapte** | appelée à la demande ; dialogue `Art ↔ Tech` pendant le build |
| **on fusionne / reconstruit / abandonne** | — |
| **interface Fable/Blueprint** | écrit `art` ; produit `asset_requests.json` |
| **verdict** | **REUSE** |

### C9 · NARRATION / GAME MASTER
| | |
|---|---|
| **rôle** | monde, voix, cohérence narrative |
| **ancien composant** | `s2.6-story-bible.yaml` · `s2.7-gm-worldscan.yaml` (2 profils mono-étape) |
| **on récupère** | les deux agents · `gm_worldscan.json` **alimente la projection `economy.json`** |
| **on adapte** | optionnelle selon le jeu |
| **interface Fable/Blueprint** | écrit `understanding.gm` ; source de la projection économique |
| **verdict** | **REUSE** |

### C10 · TECHNICAL ARCHITECTURE
| | |
|---|---|
| **rôle** | structure du jeu réel — modules, dépendances autorisées/interdites, ownership |
| **ancien composant** | `s4-archi.yaml` → `blueprint.json` (**= `ARCHITECTURE_CONTRACT`**, cf. collision) · vérifié par `s10b-oracle-archi` |
| **on récupère** | l'objet lui-même : `modules` · `deps_interdites` · `ownership` · `responsabilites` · son oracle |
| **on adapte** | **déplacement de moment** : n'est plus une étape générale en amont ; apparaît quand Fable a assez de matière et transmet au Build Orchestrator |
| **on fusionne** | rien |
| **on reconstruit** | **le droit de remonter** : si l'architecture révèle *« cette mécanique demande une décision de design »*, elle **ne l'invente pas pour continuer** — elle remonte vers Fable |
| **on abandonne** | son statut d'étape fixe |
| **interface Fable/Blueprint** | lit `technical` + `feature_map` ; écrit `ARCHITECTURE_CONTRACT` ; `Architect ↔ Gameplay`, `↔ Art`, `↔ Builder` |
| **verdict** | **ADAPT** |

### C11 · WIREMAP — la réalité construite
| | |
|---|---|
| **rôle** | *« où et comment le jeu réel contient-il cela ? »* — fonction · fichiers · preuve réelle · statut |
| **ancien composant** | `s5-wiremap.yaml` · `09_WIREMAP/` · `check_wiremap_contract.mjs` · `wm1-wiremap-breakout/tetris.yaml` |
| **on récupère** | la structure mesurée : `feature · fonction · fichiers · preuve · couvre · statut · version · implemented_at` · 4 tests `.py` · consommée par `s10c` et `s10s` |
| **on adapte** | devient la section `wiremap` du Blueprint |
| **on fusionne** | **rien — surtout pas avec la Feature Map** : 26 ids d'un côté, 25 de l'autre, **intersection 0** (mesuré sur `p2_alpha`, `card_engine`, `chain_probe_v1`). Deux questions différentes |
| **on reconstruit** | rien ici — la jointure est C12 |
| **dette connue** | `TRANSITION_INTEGRITY NOT_FOUND` : rien ne garantit la conservation des ids gel→build |
| **verdict** | **REUSE + ADAPT** |

### C12 · **JOINTURE `expected_proof ↔ actual_proof`** — la pièce manquante
| | |
|---|---|
| **rôle** | rendre chaque intention traçable jusqu'à sa réalisation, **ou jusqu'à la preuve qu'elle n'a pas eu lieu** |
| **ancien composant** | **aucun** |
| **preuve du manque** | `featuremap.json` 26 ids · `wiremap.json` 25 entrées · **0 identifiant partagé** |
| **conséquence mesurée** | finding PAIRE 2 : *« économie = canon Cookie Clicker, interdit du Brief violé, **non gardé par oracle** »* — le `must_not_have` n'est jamais devenu une feature, donc jamais une preuve attendue, donc jamais un oracle |
| **on récupère** | les deux moitiés, déjà testées |
| **on reconstruit** | **l'anneau** : `requirement → feature → implementation → expected_proof → actual_proof`, et le **rapport de couverture** qui le rend visible |
| **interface Fable/Blueprint** | devient la **porte de suffisance** du build (C13) et la **condition 1 du critère de sortie** |
| **verdict** | **REBUILD** — la capacité manquante la plus rentable |

### C13 · BUILD ORCHESTRATOR + WORKERS
| | |
|---|---|
| **rôle** | choisir les workers selon `technical`, déclencher l'architecture, construire **le vrai jeu** |
| **ancien composant** | `s9-build` ×4 (html · standard · godot · godot-standard) · `forge/standard/` (squelette gelé : `repo_map.yaml`, `core_requirements.yaml`, `capabilities.yaml`, `factory_capabilities.yaml`) |
| **on récupère** | les 4 builders · le squelette gelé · les **deux registres distincts** (produit vs usine) · le contexte injecté (charter + art_bible + loop.json + economy.json + asset_requests) |
| **on adapte** | le choix du worker vient du Blueprint, plus d'un nom de profil |
| **on reconstruit** | la **porte de suffisance** : toute exigence portée par une feature, toute feature portant un `expected_proof` — la règle dure de C7 promue en condition d'entrée du build |
| **on abandonne** | rien |
| **verdict** | **REUSE + ADAPT** · **le premier build est le vrai jeu** |

### C14 · QA — mécanique · visuelle · design
| | |
|---|---|
| **rôle** | dire **ce que le jeu fait réellement** — jamais s'il est bon |
| **ancien composant** | `oracle.py` (284 l.) · `static_oracles.py` (1818 l.) · `standard_oracles.py` (1854 l.) · `product_oracle.py` (800 l.) · `product_oracle_godot.py` (1056 l., capture GPU) · `mutation.py` (*« le MÉTA-oracle : tes tests attrapent-ils vraiment un bug ? »*) · `mutation_proof.py` (reçu signé) |
| **on récupère** | **≈5 800 lignes d'oracles déterministes non-LLM**, couvertes par **14 tests `oracle` + 13 tests `mutation`** |
| **on adapte** | appelés selon le Blueprint (pas de capture GPU pour un jeu web) |
| **on reconstruit** | **QA design** : mesurer la conformité aux `design_metrics`. N'existe pas — les métriques non plus |
| **on abandonne** | rien |
| **interface Fable/Blueprint** | lit `design_metrics` + `feature_map` ; écrit dans EVIDENCE ; `QA ↔ Design`, `QA ↔ Architect` |
| **verdict** | **REUSE** + **REBUILD** (volet design) |

### C15 · RED TEAM
| | |
|---|---|
| **rôle** | contredire — **advisory, jamais juge du code** (ADR-002) |
| **ancien composant** | `s6-redteam-plan.yaml` (profil `review`) · `s11-redteam-code.yaml` · `redteam-artdirector.yaml` |
| **on récupère** | les trois agents · leur posture advisory |
| **on adapte** | appelée quand Fable veut une contradiction, pas systématiquement |
| **on abandonne** | la dépendance `council`/Qwen (hors V2) |
| **⚠** | **indépendance BLOCKED** — le fallback `claude-blind` est **visible, jamais silencieux**. Une red-team indépendante redevient une capacité à concevoir si un profil l'exige |
| **verdict** | **REUSE** (indépendance : **UNKNOWN**) |

### C16 · EVIDENCE
| | |
|---|---|
| **rôle** | mémoire des faits observés, signée et re-vérifiable |
| **ancien composant** | `verdict.py` (HMAC) · `verify_run.py` · `studio_link.py` · `RUN_INDEX.md` append-only |
| **on récupère** | la signature HMAC · la re-vérification `AUTHENTIQUE` · **4 tests `verdict` + 5 `verify` + 2 `studio_link`** · 12 `verdict.json` signés · l'invariant *« une preuve provient du mécanisme qui a agi, sinon `AUTO_ATTESTED` »* |
| **on adapte** | destination `EVIDENCE/{runs,bundles,reports}` + rétention Option C (déjà ratifiée) |
| **on reconstruit** | `.forge_key` — **à générer pour le V2, jamais copier celle de la source** |
| **verdict** | **REUSE + ADAPT** |

### C17 · OBSERVER
| | |
|---|---|
| **rôle** | observer le run réel et en rapatrier les résultats — **jamais un Control Plane** |
| **ancien composant** | `TOOLS/observer/` (40 fichiers) · lien Forge prouvé `from forge.anonymize_session_paths import …` |
| **on récupère** | l'interface réelle · les vues · les drifts · les fiches agents |
| **on adapte** | sorties réancrées de `lab/reports/observer/` vers `EVIDENCE/reports/` |
| **verdict** | **ADAPT** |

### C18 · KB
| | |
|---|---|
| **rôle** | mémoire de ce qui a été appris **et ratifié** |
| **ancien composant** | `knowledge_base/` (129 f. ; catalogue 50 entrées, **7 `validated`**, 26 propositions) · `kb_proposal.py` · `search.mjs` · `kb-validate.mjs` |
| **on récupère** | la règle de service, verbatim : *« une proposition sous `proposals/` n'est **jamais** servie ; servir son contenu court-circuiterait le HumanGate »* · l'appariement de sous-chaîne exacte (*« un contrat qui ne cite rien reçoit rien »*) |
| **on adapte** | devient aussi le **magasin de la connaissance de genre** (C3) |
| **on reconstruit** | l'indexation par **genre**, pour que le 2ᵉ tower defense consulte au lieu de re-chercher |
| **verdict** | **REUSE + ADAPT** |

### C19 · BOUCLE D'APPRENTISSAGE
| | |
|---|---|
| **rôle** | observation → leçon → HumanGate → connaissance ratifiée → injection contrôlée |
| **ancien composant** | `learning_hook.py` · `learning_memory.py` (`lesson.v2` : `cause` est un **champ**) · `kb_proposal.py` propose-only |
| **on récupère** | **la seule boucle du système qui tourne vraiment** · 3 tests `learning` |
| **mesure** | **18 leçons ratifiées sur 326** — le goulot est humain, pas technique |
| **verdict** | **REUSE** |

### C20 · HUMAN GATE
| | |
|---|---|
| **rôle** | seul producteur de vérité de valeur |
| **ancien composant** | `gate.py` (*« the FORCER brick »* : oracle vert ⇒ verdict OK signé ; rouge/absent/injouable ⇒ FAIL/BLOCKED ; *« l'appelant NE DOIT PAS poursuivre au-delà d'une porte non-OK »*) · `kb_proposal --apply --ratifie-par` |
| **on récupère** | la porte · les objections conservées (`HUMANGATE_READY_WITH_OBJECTION`) · le vocabulaire unique `OK/FAIL/BLOCKED` |
| **on reconstruit** | **la destination des décisions** : `decision-log.md` est absent du V2 — le gate peut produire un verdict, il n'a pas où inscrire la décision |
| **verdict** | **REUSE + REBUILD (destination)** |

### C21 · PORTE DE SPAWN *(infrastructure)*
| | |
|---|---|
| **rôle** | aucun sous-agent sans dispatch enregistré — fail-closed |
| **ancien composant** | `.claude/hooks/pretool_forge_guard.py` · `forge/hook_guard.py` · `dispatch.prepare_dispatch` |
| **invariant mesuré** | ne lit **aucun fichier de contrat** : marqueur `FORGE_DISPATCH:<etape>:<run_id>` confronté au journal d'audit — `count==1` allow · `0` refus · `≥2` refus (rejeu) |
| **on récupère** | tout — **7 tests `guard` + 4 `spawn` + 6 `dispatch` + 11 `contract`** |
| **conséquence** | **compatible nativement avec la composition dynamique** : un rôle composé par Fable passe s'il remplit les 13 champs Critiques, passe par `prepare_dispatch` et est spawné une fois |
| **⚠** | déduction **lue**, non exécutée sur un contrat composé à la volée |
| **verdict** | **REUSE** |

### C22 · BOUCLE DES MÉTRIQUES
| | |
|---|---|
| **rôle** | `VISION → DESIGN → METRICS → BUILD → MEASURE → COMPARE → REWORK` — **le rework retourne à Fable**, jamais à « l'étape 7 » |
| **ancien composant** | aucune boucle ; les métriques existantes servent à auditer le pipeline, pas à concevoir |
| **on récupère** | la **règle de variance déjà ratifiée** : *toute métrique qui classe, génère ou calibre doit prouver qu'elle porte une information variable* |
| **on reconstruit** | la boucle entière : cibles dans le Blueprint → paramètres des projections → mesure QA → comparaison → retour Fable |
| **⚠** | sans la règle de variance, on refabrique `ticks == plus-court-chemin` — une métrique qui validait le moteur sans mesurer ce que son nom promettait |
| **verdict** | **REBUILD** |

---

## Ce qui sort — reliques du workflow

| élément | preuve | verdict |
|---|---|---|
| `dispatch.ORDER` (13 étapes) | le workflow imposé lui-même | RETIRE |
| `dispatch.PROFILES` (19) | 5 mono-capacité déjà = appels de capacité | MERGE |
| panel Prisme multi-lentilles (8 f.) | `--charter` jamais passé · `LENSES` jamais alimenté | RETIRE |
| île MCTS / candidate_selector (17 f.) | **0 appelant** sur les 8 modules de la chaîne | RETIRE |
| `wiremap_nav` (2 f.) | 0 consommateur, tous canaux | RETIRE |
| 7 CLI de protocole de paires | servaient l'**expérience sur le workflow**, pas la fabrication | RETIRE |
| `control_plane` · `council` · `openclaw` | 3 fn/9 · import paresseux · legacy | hors V2 |

## UNKNOWN

`reference_guard` (349 diffs/run, DRIFT sans effet sur aucune décision) · chaîne asset (hors du
fermé transitif de `run_real`) · rail des 25 nœuds (plan ou carte de compétences ?) ·
`s10d-oracle-visual` (part réellement exercée non mesurée) · indépendance red-team.

---

## Synthèse

```
22 capacités cible
  REUSE tel quel .......... 9    Prisme · Art · Narration · QA-oracles · Red Team
                                 apprentissage · porte de spawn · KB(service) · projections
  ADAPT ................... 8    Blueprint · Director · Research · Breakdown · Architecture
                                 Wiremap · Build · Evidence · Observer
  MERGE ................... 2    Décomposition→Feature Map · PROFILES→composition
  REBUILD ................. 4    UX · jointure expected↔actual · chaînon design_metrics
                                 · boucle des métriques
  RETIRE .................. 6
  UNKNOWN ................. 5
```

**Rien de neuf n'est un framework.** Les quatre reconstructions sont : **un rôle** (UX), **un
anneau** (la jointure), **un chaînon** (métriques→projections), **une boucle** (mesure→rework).
Tout le reste existe, est testé, et changeait seulement de place.

> Ce qui était mal placé, ce n'étaient pas les capacités — c'était **la file qui les obligeait à se
> suivre**.

```
status_by_surface:
  capability_map:              DOCUMENTED_ONLY
  target_model:                DOCUMENTED_ONLY
  implementation:              BLOCKED
  runtime_validation:          BLOCKED
  blueprint_name_collision:    TESTED     # blueprint.json = ARCHITECTURE_CONTRACT, mesuré
  contract_output_artifacts:   TESTED     # 23 contrats, artefacts déclarés relevés
  ux_absence:                  TESTED
  featuremap_wiremap_overlap:  TESTED     # 0 id partagé
  expected_proof_join:         NOT_FOUND
  design_metrics_loop:         NOT_FOUND
  ux_capability:               NOT_FOUND
```
`software_verdict: OK` (document) · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`
