# ADJUDICATION V2 — passe finale, **sans modification**

*2026-09-01. Un seul geste appliqué : `FORGE/openclaw/` supprimé (décision Pierre). Tout le reste
de ce document est une **proposition adossée à une mesure**, rien n'est retiré.*

## La règle appliquée

> **Si un fichier n'a pas de consommateur démontré dans V2, il n'entre pas dans V2.**

Quatre canaux de consommation ont été cherchés, pas seulement l'import :
`import` Python · invocation CLI / sous-processus · référence depuis `.mjs` · référence depuis
`.claude/` ou `TOOLS/`. Un fichier n'est déclaré `NOT_CONSUMED` que si les **quatre** sont vides.

### Piège rencontré, et évité
Une recherche par sous-chaîne donnait `execution_proof` « cité par 2 modules de la chaîne ».
Vérification : ce sont les champs `execution_proof_attestation` / `execution_proof_note` du
**verdict**, pas un appel au module `execution_proof.mjs`. Idem `search_usage`, cité dans une
docstring de `contract.py:323` à titre de comparaison. **Un consommateur ne se trouve pas par la
forme du nom** — les deux faux positifs sont écartés, et l'île redevient sans appelant, cette fois
pour la bonne raison.

---

# 1 · GARDÉ — unités et leur justification

## `MASTER_SCHEMA.html`
```
IDENTITY      carte déclarative du Studio V2 (source canonique)
OWNER         Studio
CONSUMER      humain ; référencé par RAIL_REGISTER et IO_CONTRACT
INPUT         ancien schéma (matière première) + mesures des surfaces V2
OUTPUT        —
DEPENDENCIES  aucune (page autonome, 0 référence externe)
SOURCE        construction neuve, derived_from dans PROVENANCE.md
STATUS        IMPLEMENTED
```

## `FORGE/forge/` — la chaîne canonique · **27 modules Python**
```
IDENTITY      chaîne de fabrication : run_real → driver → dispatch → contract → runtime
              → oracles → verdict → verify_run
OWNER         Forge
CONSUMER      opérateur via run_real ; la porte .claude/hooks/pretool_forge_guard
INPUT         project_brief.yaml (D3) · contrats d'étape · catalogue KB
OUTPUT        run_dir · verdict.json signé · lessons · propositions KB
DEPENDENCIES  control_plane.registry (placement BLOCKED) · PyYAML · claude CLI · Node
SOURCE        scripts/forge/ @ d6c2510c
STATUS        IMPLEMENTED — atteignable par import depuis les 5 points d'entrée
```
Mesure : **55 modules `.py` hors tests, 27 atteignables** depuis
`run_real · driver · hook_guard · verify_run · gate`.

## `FORGE/forge/` — les 21 modules atteints par un autre canal
`anonymize_session_paths` (importé par `TOOLS/observer/cli.py`) · `asset_geometry/*` et
`asset_producer/*` (chaîne asset, 7 modules) · `blender_bin` · `commit_scope_guard` ·
`contract_sync` (lu par `FORGE_SYSTEM_CONTRACT.yaml` + `studio_selfaudit.mjs`) · `git_guard` ·
`kb_proposal` (**le seul écrivain du catalogue KB**) · `learning_hook` · `reference_guard` ·
`repair_dispatch` · `runtime_inventory_oracle` · `skipped_validation` ·
`solvability_budget_audit`.
```
STATUS        IMPLEMENTED — consommateur prouvé hors graphe d'import
```

## `FORGE/forge/` — les données internes
```
IDENTITY      contracts/ (28 yaml + SCHEMA.md + PLAYABLE_CONTRACT.md) · standard/ (5) ·
              oracles.json · roles.yaml · mutation_registry.json · capabilities.json · layers.json
OWNER         Forge — ressources internes au sens de D1
CONSUMER      contract.load_contract · driver._STANDARD_DIR · oracle.resolve_oracle
INPUT/OUTPUT  —
DEPENDENCIES  résolues via REPO_ROOT → cassé dans V2 (voir IO_CONTRACT §0)
SOURCE        scripts/forge/ @ d6c2510c
STATUS        BLOCKED par la frontière D1, pas par l'utilité
```

## `FORGE/forge/tests/` — 220 fichiers
```
CONSUMER      pytest, via forge/oracles.json
STATUS        BLOCKED — l'isolation est cassée (43 tests sur REPO_ROOT, 68 sur un
              scripts/forge factice). Gardés : ils sont l'objet du chantier, pas son déchet.
```

## `FORGE/control_plane/` — 2 fichiers
```
IDENTITY      mécanisme générique rôle → modèle/provider (~35 lignes)
OWNER         **Studio**, pas Forge (preuve : IO_CONTRACT §0-ter)
CONSUMER      Forge (8 sites, tous avec chemin explicite) + autopilot.py (lane gelée, hors V2)
INPUT         un fichier yaml fourni PAR L'APPELANT
DEPENDENCIES  PyYAML
STATUS        BLOCKED — placement CP-1 / CP-2 / CP-3 non tranché
```

## `knowledge_base/` — 129 fichiers
```
IDENTITY      magasin ratifié : catalog.json (50 entrées, 7 validated) · proposals/ (26) ·
              patterns/ · systems/ · roles/ · assets/ · proofs/
OWNER         Studio
CONSUMER      contract.py (injection contrôlée) · kb_proposal.py (écriture propose-only) ·
              driver.py · preflight.py · search_usage.mjs · TOOLS/observer
INPUT         propositions issues des leçons          OUTPUT  briques servies aux agents
STATUS        IMPLEMENTED — catalogue lu et parsé dans V2
```

## `GAMES/` — 3 fichiers, 0 jeu
```
IDENTITY      RAIL_REGISTER.md (25 nœuds, déclaré vs observé) · PLAN_STATUS.md · (brief à venir, D3)
CONSUMER      humain — point de décision avant toute migration physique
STATUS        IMPLEMENTED pour le registre · BLOCKED pour les jeux
```

## `TOOLS/observer/` — 40 fichiers
```
IDENTITY      mesure du workflow réel (événements, faits, vues, drifts, fiches agents)
OWNER         Studio
CONSUMER      humain ; lien Forge prouvé (`from forge.anonymize_session_paths import …`)
INPUT         run_dirs, rapports, catalogue KB     OUTPUT  lab/reports/observer/**
STATUS        IMPLEMENTED — mais ses sorties visent `lab/`, à réancrer sur EVIDENCE (D4)
```

## `.claude/` — 28 fichiers
```
IDENTITY      la porte + le pilotage : settings.json · 5 hooks · skill forge · 17 agents · 4 règles
OWNER         Studio (exception mécanique : Claude Code n'y lit qu'ici)
CONSUMER      le runtime Claude Code
STATUS        UNKNOWN — câblage hooks → FORGE/forge non testé
```

---

# 2 · PROPOSÉ AU RETRAIT — `NOT_CONSUMED`

**Rien n'est retiré par ce document** (sauf `openclaw/`, déjà décidé). Chaque ligne est une
proposition mesurée, à ratifier.

## Déjà retiré ✔
```
FORGE/openclaw/{capabilities,providers}.yaml        2 fichiers   NOT_CONSUMED
  preuve : les 8 sites d'appel de la Forge passent tous un chemin explicite ;
           get_model_for_role('game_forger') via openclaw → None.
           Copiés sur la foi d'une mesure erronée de ma part (IO_CONTRACT §0-ter).
```

## Île de décision V2 — **17 fichiers**
```
candidate_selector · execution_binding · mcts_selector · agent_factory · execution_proof
agent_genome · search_usage   (.mjs + .test.mjs)
root_problems.json · agent_recipes.json · root_problem.schema.json · agent_recipe.schema.json

CONSUMER      0 sur les 8 modules de la chaîne canonique, après élimination de 2 faux positifs
STATUS        NOT_CONSUMED — gel ratifié Pierre 2026-08-28 (Paquet A #5), figés depuis 08-04
NOTE          PASSIVE ≠ DEAD : le gel dit « ne pas brancher », pas « ne pas exister ».
              Le retirer de V2 ne le supprime pas du repo source.
```

## Panel Prisme multi-lentilles — **8 fichiers**
```
panel.py · prisme/{check_prisme,check_gameplay_review,merge_prisme}.mjs (+ tests)
          · prisme/design_review_checklist.yaml

CONSUMER      flag --charter jamais passé par le driver ; lenses contractualisées jamais
              consommées par panel.LENSES
STATUS        NOT_CONSUMED — gel ratifié Pierre 2026-08-28 (Paquet A #6)
RÉSERVE       l'étape s1-prisme standard (1 agent) reste ACTIVE et son contrat est gardé.
```

## Orphelin `.mjs` — **2 fichiers**
```
wiremap_nav.mjs + wiremap_nav.test.mjs
CONSUMER      0, tous canaux confondus
STATUS        NOT_CONSUMED
```

## Sept CLI sans consommateur **dans V2** — 7 modules + 4 tests
```
check_playtest_report · check_prerun · check_runtime_truth · component_design
m7_masking · pair_preflight · run_identity

CONSUMER      0 dans V2. MAIS 6 sur 7 sont des points d'entrée CLI (argparse/__main__)
              invoqués par un OPÉRATEUR HUMAIN au protocole — et les protocoles
              (RUN2_PROTOCOLE_V1, qui rend `forge.pair_preflight --run-tests` BLOQUANT)
              ne sont pas importés dans V2.
STATUS        ⚠ AMBIGU — la règle mécanique dit NOT_CONSUMED ; la réalité dit
              « consommateur = l'humain, via un protocole absent ».
DÉCISION      à trancher explicitement. Retirer supprime une capacité ; garder viole la règle.
              Troisième voie possible : importer les protocoles qui les appellent, ce qui
              rend le consommateur démontrable.
```

## Bilan si les trois blocs non ambigus sont retirés
```
île V2        17
panel Prisme   8
orphelins      2
openclaw       2  (fait)
              ──
              29 fichiers        671 → 642
```
Le gain en nombre est modeste. **Le gain réel est ailleurs** : ces 29 fichiers sont exactement
ceux qui feraient croire à un lecteur du V2 que le studio dispose d'un moteur de décision MCTS et
d'un panel multi-lentilles. Les retirer ne réduit pas le poids, il **supprime une promesse fausse**.

---

# 3 · Ce que l'adjudication n'a PAS trouvé

Honnêteté sur la portée : je m'attendais, comme toi, à un gain bien supérieur aux 8,7 % actuels.
**Il n'y est pas, et c'est un résultat.**

- **220 tests + 51 `.test.mjs`** = **40 % du V2**. Aucun n'est orphelin : ils sont l'objet du
  chantier d'isolation. Les retirer serait retirer la preuve.
- **47 `.mjs` de code**, 2 orphelins seulement.
- **55 modules `.py`**, 7 ambigus, 0 franchement mort.

La copie de `scripts/forge/` était donc **déjà dense**. Le bruit du repo source n'était pas dans la
Forge — il était dans `lab/` (3 779 fichiers), `docs/` (535), `00_STUDIO_CONTROL/` (289), tous déjà
écartés à l'étape 1. **Le tri du gros bruit a déjà eu lieu ; celui-ci est un tri de précision.**

---

# 4 · TOOLS ne doit pas devenir un `misc/`

Trois niveaux, à ne pas confondre — et une fiche obligatoire par outil.

| niveau | exemple | règle |
|---|---|---|
| **1. données Forge** | `contracts/roles.yaml` · `oracles.json` · `standard/` | vivent DANS le paquet Forge |
| **2. moteurs génériques** | `control_plane/registry.py` | outil du Studio, consommé par la Forge → `TOOLS/` (CP-1, **non tranché**) |
| **3. intégrations externes** | claude CLI · Playwright · Qwen/LM Studio · Godot · Node | **binaires et services** — préconditions d'exécution, jamais des fichiers à migrer |

Gabarit obligatoire pour toute entrée de `TOOLS/` :
```
outil : <nom>
  consommateur      : qui l'appelle, fichier:ligne
  interface         : CLI · import · HTTP · sous-processus
  fichiers requis   : ce qui doit être présent dans V2 (souvent : rien, pour le niveau 3)
  statut            : IMPLEMENTED | BLOCKED | UNKNOWN
```
Sans les quatre champs, l'outil n'entre pas. C'est la même règle que pour les fichiers, appliquée
aux capacités.

---

# 5 · Statuts

```
MASTER_SCHEMA V2 ........... IMPLEMENTED
RAIL_REGISTER .............. IMPLEMENTED
knowledge_base ............. IMPLEMENTED
FORGE (chaîne, 27 modules) . IMPLEMENTED
FORGE (données internes) ... BLOCKED    frontière D1
FORGE test isolation ....... BLOCKED    43 / 68
control_plane placement .... BLOCKED    CP-1 / CP-2 / CP-3
TOOLS/observer ............. IMPLEMENTED  sorties à réancrer sur EVIDENCE
.claude (la porte) ......... UNKNOWN    câblage non testé
retrait des 27 fichiers .... PROPOSED   île V2 · panel Prisme · orphelins
7 CLI ambigus .............. UNKNOWN    consommateur = humain, protocole absent
V2 signature ............... BLOCKED
game input ................. BLOCKED
EVIDENCE contract .......... BLOCKED
first V2 run ............... BLOCKED
```

Pas de verdict global. `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED`.
