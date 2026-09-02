# CONTRAT DES JONCTIONS — entrée et sortie de la Forge

*2026-09-01 · **rien n'a été construit, aucun chemin n'a été modifié.** Ce document établit ce que
sont les jonctions aujourd'hui, mesuré, et pose les décisions à prendre avant tout premier run.*

## Règle V2 verrouillée

> **Aucun premier run n'est autorisé à créer une nouvelle surface du Studio.**
> Si `forge.driver` veut écrire dans `lab/…`, alors soit `EVIDENCE/…` est officiellement son
> nouveau contrat, soit le run est `BLOCKED`.

C'est ce qui empêche le nouveau Studio de redevenir le vieux labyrinthe : une surface naît d'une
décision, jamais du comportement par défaut d'un module.

---

# JONCTION 0 — la Forge ne se trouve plus elle-même *(découverte, non demandée)*

Avant de pouvoir répondre « quel chemin canonique V2 » pour A et B, il faut constater ceci :
**la Forge du V2 ne peut pas charger un seul contrat.** Mesuré en exécutant, dans `FORGE/` :

| constante | chemin résolu dans le V2 | existe |
|---|---|---|
| `contract.REPO_ROOT` | `…\Studio` | ✔ |
| `contract.KB_CATALOG` | `…\Studio\knowledge_base\catalog.json` | ✔ |
| `contract.KB_PROPOSALS_DIR` | `…\Studio\knowledge_base\proposals` | ✔ |
| `contract.CONTRACTS_DIR` | `…\Studio\scripts\forge\contracts` | ✘ **les 28 contrats** |
| `oracle.DEFAULT_CONFIG` | `…\Studio\scripts\forge\oracles.json` | ✘ **registre d'oracles** |
| `driver._STANDARD_DIR` | `…\Studio\scripts\forge\standard` | ✘ **squelette gelé** |
| `verdict.DEFAULT_KEY_FILE` | `…\Studio\scripts\forge\.forge_key` | ✘ **clé de signature HMAC** |

**Cause unique.** `REPO_ROOT` joue deux rôles à la fois dans le code : localiser les **surfaces
voisines** (`knowledge_base/`, `lab/`, `games/`) *et* localiser les **fichiers frères du paquet**
(`scripts/forge/contracts`, `…/oracles.json`, `…/standard`, `…/.forge_key`). Dans le repo source
les deux coïncident. Dans le V2 non : le paquet vit en `FORGE/forge/`, pas en `scripts/forge/`.
Les 3 chemins qui marchent sont exactement les 3 qui visent une **surface voisine**.

Un module qui adresse ses propres fichiers frères *en passant par la racine du dépôt* est un
couplage bancal — le V2 le révèle, il ne le crée pas.

### La clé de signature : un cas à part
`.forge_key` (32 octets) existe dans le repo source, **n'est pas versionnée**, et n'a donc pas été
copiée. C'est heureux : **le V2 ne doit jamais recevoir la clé du repo source.** Deux studios qui
signent avec la même clé produisent des verdicts indistinguables — la signature ne prouverait plus
qui a mesuré. Le V2 doit **générer la sienne**, une fois, et ne jamais la versionner.

### Options — coût mesuré, aucune retenue
| # | option | coût | conséquence |
|---|---|---|---|
| 0-a | placer le paquet en `Studio/scripts/forge/` (miroir de la source) | **0 ligne de code** | réintroduit `scripts/` comme surface ; contredit le nommage `FORGE/` |
| 0-b | redériver les **9 occurrences** (6 fichiers) : frères adressés par `Path(__file__).parent`, surfaces par `REPO_ROOT` | modification de code → **gate + tests + non-régression** | corrige le couplage à la racine ; **doit être fait dans le repo SOURCE d'abord**, sinon on forke la Forge |
| 0-c | jonction NTFS `Studio/scripts/forge` → `FORGE/forge` | ~0 | **ÉCARTÉE (Pierre)** — ferait marcher la copie sans corriger l'architecture ; `scripts/forge` deviendrait un fantôme technique |
| 0-d | ne pas toucher les constantes : **injecter la racine au point d'entrée**, en exploitant les **49 paramètres de surcharge déjà présents** (`contracts_dir=`, `config_path=`, `key_file=`, `caps_path=`) | faible, localisé | ne corrige pas la confusion de fond ; déplace la responsabilité vers l'appelant |

### Le principe retenu (Pierre, 2026-09-01)
```
ressources internes de la Forge  →  relatives au PAQUET Forge
surfaces du Studio               →  relatives à la RACINE du Studio
```
L'ancien repo confondait les deux parce que tout vivait sous la même racine. Le V2 ne crée pas
ce défaut, il le rend visible.

> **Formulation exacte de l'état** : le défaut d'auto-localisation est **identifié et mesuré**.
> La **stratégie de correction doit être validée** avant toute modification de la Forge canonique.
> Ce document ne décide pas du patch — il en établit la surface et les risques (§0-bis).

---

# JONCTION 0-bis — `Path(__file__).parent` est-il compatible ? *(vérification demandée)*

**Réponse mesurée : compatible avec les formes d'import — incompatible avec la stratégie
d'isolation des tests.** C'est là qu'est le vrai coût, pas dans le patch.

### Ce qui est compatible
- **L'idiome est déjà employé dans le paquet.** `forge/runtime.py:31` fait
  `SCRIPTS_DIR = Path(__file__).resolve().parent.parent`. Il n'y a rien à inventer.
- **Aucune forme d'installation exotique** : pas d'archive zip, pas de paquet figé, pas
  d'installation éditable. Le paquet est importé depuis le disque, `__file__` est toujours défini.
- **Le côté Node fait déjà bien** : 131 `fileURLToPath` + 91 `import.meta.url` — les `.mjs` se
  localisent par l'URL de leur module, l'idiome correct.
- **L'API est déjà prête** : **49 paramètres de surcharge** (`contracts_dir=`, `config_path=`,
  `key_file=`, `caps_path=`) existent déjà sur les fonctions publiques. Les constantes de module ne
  sont que des **défauts** — le patch est localisé à leur calcul, pas aux appelants.

### Ce qui est incompatible — le risque réel
Les tests s'isolent en **surchargeant `REPO_ROOT`** et en fabriquant une fausse arborescence :

| mesure | valeur |
|---|---:|
| fichiers de test référençant `REPO_ROOT` | **43** |
| fichiers de test fabriquant un `scripts/forge/…` factice | **68** |
| constructions littérales `"scripts" / "forge"` dans les tests | 25 |

Si les ressources internes cessent de dériver de `REPO_ROOT`, ces tests **continueront de passer
au vert en lisant les VRAIS contrats et le VRAI `oracles.json`** au lieu de leurs fixtures. Vert,
mais par le mauvais chemin causal — un mode de panne déjà catalogué dans la KB du studio
(`pat-forge-test_green_via_wrong_causal_path`).

> **Conclusion de la vérification** : le patch n'est pas « quelques constantes ». C'est
> **9 occurrences dans 6 fichiers + 51 `.mjs` + une refonte de l'isolation des tests**,
> sinon la suite ment.

### Surface totale mesurée du patch
| élément | compte |
|---|---:|
| occurrences `REPO_ROOT / "scripts" / …` hors tests | **9**, dans **6 fichiers** |
| dont insertions `sys.path` (`asset_dispatch.py`) | 3 |
| fichiers `.mjs` citant `scripts/forge` | **51** |
| `forge/oracles.json` → `-m pytest scripts/forge/tests/ -q` | 1 commande, dépendante du cwd |
| hooks `.claude/` calculant `parents[2]` | 2 |

*Correction : j'avais annoncé 5 constantes dans 8 fichiers. Le compte ne portait que sur
`forge/*.py` et ratait le sous-paquet `asset_producer/`. Chiffre exact : **9 occurrences,
6 fichiers**, dont 3 manipulations de `sys.path` — pas seulement des constantes de chemin.*

### Deux constats annexes, mesurés
1. **Le paquet n'est pas importable seul.** `import forge.contract` depuis `Studio/` échoue
   (`ModuleNotFoundError`). Il faut que l'appelant place `FORGE/` sur `sys.path`. Mon test d'import
   antérieur était valide, mais son succès venait **de mon `sys.path`**, pas du paquet.
2. **Le bootstrap interne est inerte dans le V2.** `contract.py:74` insère `REPO_ROOT` dans
   `sys.path` pour importer `control_plane` → vise `Studio/control_plane`, **qui n'existe pas**.
   `control_plane` se résout en fait depuis `FORGE/control_plane`, uniquement grâce au `sys.path`
   de l'appelant. Sans effet néfaste aujourd'hui, mais ce n'est pas le mécanisme annoncé.

---

# JONCTION 0-ter — `control_plane` appartient-il à la Forge ?

**Réponse mesurée : non. C'est une capacité du Studio que la Forge consomme.** Et la mesure
invalide au passage une de mes preuves antérieures.

### Le mécanisme est générique, la donnée ne l'est pas
`control_plane/registry.py` — ~35 lignes — répond à *« quel modèle / provider pour ce rôle,
d'après CE fichier yaml »*. Le fichier est fourni **par l'appelant**. Rien dans ce module ne
connaît la Forge. Il a des consommateurs hors Forge (`autopilot.py:30`, lane STUDIO gelée).

### La donnée de rôles de la Forge vit DANS la Forge
`forge/contracts/roles.yaml`, verbatim de son en-tête :
> « Portée : Forge **UNIQUEMENT**. […] Ce fichier-ci est **la seule source de résolution de rôle
> de la Forge** : `contract.resolve_runtime` passe **toujours** `caps_path=FORGE_ROLES`. Le chemin
> openclaw n'est que le **DÉFAUT du module partagé** `control_plane/registry.py:15`, consommé par
> la lane STUDIO, elle-même gelée. »

Vérifié sur les **8 sites d'appel** de `get_model_for_role` / `get_provider_for_role` dans la
Forge : **tous passent un chemin explicite** (`caps_path or FORGE_ROLES`, ou `FORGE_ROLES` en
positionnel). **Aucun n'emprunte le défaut openclaw.**

Et les rôles sont disjoints. Les 15 `capability_role` réellement déclarés par les contrats
d'étape — `game_forger`, `builder`, `architect`, `art_director`, `worldscan`, `wiremap`,
`game_master`, `prisme`, `redteam_code`, `deterministic`, … — n'apparaissent nulle part dans
`openclaw/capabilities.yaml`, qui déclare `director`, `charter_generation`, `kaizen_autoloop`,
`ceo_brief`, `coordinator` : des rôles de la **lane STUDIO gelée**.

```
résolution par le chemin RÉEL (contracts/roles.yaml)
  game_forger   -> claude-opus-4-8              [claude-local]
  builder       -> claude-haiku-4-5-20251001    [claude-local]
  architect     -> claude-opus-4-8              [claude-local]
résolution par le DÉFAUT openclaw (chemin que la Forge ne prend JAMAIS)
  director      -> qwen2.5-14b-instruct
  game_forger   -> None
```

### ⚠ Correction d'une preuve antérieure
J'ai présenté `get_model_for_role('director') → qwen2.5-14b-instruct` comme la preuve que le
registre du V2 fonctionnait. **Cette mesure empruntait le défaut openclaw — un chemin que la Forge
ne prend jamais.** Elle prouvait que la résolution *de la lane gelée* fonctionne, pas celle de la
Forge. Oracle correct, mesure fausse. La bonne preuve est le bloc ci-dessus, via `contracts/roles.yaml`.

**Conséquence directe : `FORGE/openclaw/` est du poids mort dans le V2.** Ces deux fichiers ont été
copiés sur la foi de cette mesure erronée. Ils ne sont lus par aucun chemin d'exécution de la Forge.

### Options — à trancher, non tranchées
| # | option | conséquence |
|---|---|---|
| CP-1 | `control_plane` → **`TOOLS/control_plane/`** | cohérent avec la preuve : capacité du Studio, consommée par la Forge. Casse `from control_plane.registry import …` tant que `TOOLS/` n'est pas sur le `sys.path` — conséquence de packaging à traiter avec le patch de frontière |
| CP-2 | `control_plane` reste dans `FORGE/` | fait marcher l'import aujourd'hui, mais **fige une relation fausse** dans la carte |
| CP-3 | absorber les ~35 lignes dans `forge/` | supprime un module partagé qui a d'autres consommateurs → forke un mécanisme |
| — | `FORGE/openclaw/` | **RETIRÉ du V2 le 2026-09-01** (décision Pierre) : jamais lu par la Forge |

> Je ne tranche pas. La réponse change la carte : `TOOLS/control_plane/` (CP-1) contre
> `FORGE/control_plane/` (CP-2) n'est pas du rangement, c'est une relation architecturale.

---

# JONCTION A — l'entrée de la Forge

## Où vit le `project_brief` ?
`lab/forge_briefs/<projet>/project_brief.yaml` — **chemin RATIFIÉ** (Pierre, 2026-08-29,
`FORGE_PROJECT_INPUT_V0` §1 et §5 : « emplacement `lab/forge_briefs/<projet>/` GO »).
Le code le déclare **seule entrée, jamais dupliquée en une seconde constante** (`run_real.py:3060`).

Fichiers frères observés dans un dossier de brief : `structure_imposee_v2.yaml` (grammaire imposée
des bras d'expérience dirigés), et des documents de pré-enregistrement de paires.

## Qui le crée ?
**Un humain en est la source normative ; un agent peut le rédiger.** Verbatim d'un brief réel :
> « Rédaction du fichier par l'agent (Claude Sonnet 5), contenu normatif sourcé Pierre 2026-08-30
> (voir bloc `provenance` pour la source champ par champ — aucune source n'est fabriquée ; ce qui
> n'est pas tracé est marqué comme tel, jamais inventé). »

Le champ `provenance` porte la source **champ par champ**. Une source absente = `FAIL`.

## Quel est son format ?
10 champs de premier niveau, mesurés sur un brief réel :
```yaml
projet:                 # slug
intention:              # ce qu'on cherche à obtenir ou apprendre
contraintes:            # normative_refs (CITÉES, jamais recopiées) + project_specific
cible:                  # web/HTML, godot, …
references_autorisees:  # chacune avec sa source
criteres_sortie:
libertes_deleguees:     # ce que la chaîne décide
non_delegue:            # ce que l'humain garde
principe:
provenance:             # source par champ — absente ⇒ FAIL
```
Le **profil de chaîne** (`full_content`, `standard`, …) n'est **pas** un champ du Brief : c'est un
paramètre de lancement. `project_input + profile → RUN`.

## Qui le consomme ?
| module | usage | nb de références |
|---|---|---|
| `run_real.py` | pré-vol fail-closed + injection **entière** dans le prompt s0, sha256 au manifest | 23 |
| `context_manifest.py` | empreinte du Brief dans le manifeste d'exécution | 4 |
| `static_oracles.py` | `check_project_brief` — oracle déterministe non-LLM | 4 |
| `driver.py` | lit le champ `mesure` | 2 |

**Enforcement, déjà mécanique** : pour tout profil dont l'ordre contient `s0-contrat`, le Brief doit
exister ET passer `check_project_brief` **avant toute dépense LLM** — sinon `exit 1`.

**Entrées alternatives INTERDITES** (table honnête de la spec, qui distingue ce qui est mécanisé de
ce qui reste doctrinal) : prose de conversation comme spec · `--task-*` portant du design-intent ·
fichier `design/` non listé dans `references_autorisees` · charter pré-existant (le charter est une
**sortie** de s0) · artefacts résiduels d'un run précédent.

## Quel chemin canonique V2 ?
**Non décidé.** Trois options, et une seule évite de créer une surface :

| # | chemin V2 | crée une surface ? | conséquence |
|---|---|---|---|
| A-1 | `lab/forge_briefs/<projet>/` (inchangé) | **oui — `lab/`** | viole la règle V2 verrouillée |
| A-2 | `GAMES/<projet>/brief/project_brief.yaml` | non | le Brief devient une pièce de la fiche du nœud ; cohérent avec « un jeu est une unité » ; **contredit un chemin ratifié → re-ratification requise** |
| A-3 | `EVIDENCE/briefs/<projet>/` | non | range une **entrée** dans une surface de **sortie** — incohérent |

Recommandation : **A-2**. Le Brief est la déclaration d'intention d'un nœud du rail ; il appartient
au nœud. Mais c'est une re-ratification explicite d'une décision du 2026-08-29, pas un détail.

---

# JONCTION B — la sortie de la Forge

## Où vit un run ?
`lab/forge_runs/<projet>/`. Contenu réel mesuré sur `chain_probe_v1` :
```
state.json · run.log · context/ · evidence/ · artifacts/ · design/ · heritage/
charter.yaml · blueprint.json · featuremap.json · loop.json · economy.json
art_bible.md · design_intent.md · design_questions.json · design_state.json
gm_worldscan.json · prisme.json · product_snapshot.md · reference_guard.jsonl
CLOSURE_RUN1_20260830.md
```

## Où vit son verdict ?
`verdict.json` **dans le run_dir**, signé HMAC avec `.forge_key`, re-vérifié par `verify_run`
(rend `AUTHENTIQUE` ou refuse). Le `software_verdict` ne provient QUE de reçus d'oracle vérifiés.

## Où vit l'évidence ?
Deux natures distinctes, et le code les sépare déjà :
- **bundles** : `lab/forge_evidence/<ID_EXPERIENCE>/` — un dossier par expérience, contenu figé une
  fois l'expérience close ;
- **flux d'exploitation** à la racine, append-only et sans fin : `dispatch_audit.jsonl`,
  `runtime_drift.jsonl`, `repair_results.jsonl`, `asset_results.jsonl`, `dispatch_dryrun.jsonl`,
  `reference_baseline.json`, `forge_telemetry.jsonl`, `oracle_*.log`.

## Où vont les lessons / failure events ?
`lab/reports/` — `lessons.jsonl` · `failure_events.jsonl` · `error_journal/<domaine>.jsonl`
(+ `INDEX.generated.md`, **régénéré**, donc jamais une source).
Plus le registre `lab/forge_runs/RUN_INDEX.md`, **déclaré append-only le 2026-07-26** ; le driver
refuse explicitement d'y écrire hors du registre réel.

## Quel est le contrat de rétention ?
**Déjà ratifié** — « Option C appliquée », 2026-08-04, résultat mesuré :
```gitignore
lab/forge_evidence/*
!lab/forge_evidence/*/
```
> **bundles de preuve → versionnés · flux d'exploitation → ignorés.**

Résultat vérifié à l'époque : commit de 122 fichiers / ~480 Ko, **aucun `.jsonl` ni `.log` de flux
n'est entré**. Et la preuve que la politique servait à quelque chose : sur un export du commit,
les mutations exécutables passent de **0/13 à 4/13**, `evidence_missing` de **13 à 0**.

État actuel du repo source : `lab/forge_runs/` = **2 766 fichiers suivis pour 4 566 présents**
(39 % hors dépôt). Le contrat de rétention existe donc, mais il n'est pas uniforme sur `forge_runs/`.

## Quel chemin canonique V2 ?
**Non décidé.** Le contrat de rétention, lui, se transpose sans discussion : il est ratifié et
indépendant de l'emplacement.

| # | chemin V2 | conséquence |
|---|---|---|
| B-1 | `EVIDENCE/runs/<projet>/` · `EVIDENCE/bundles/<id>/` · `EVIDENCE/reports/` · `EVIDENCE/RUN_INDEX.md` | surface **assumée**, nommée par une décision ; 4 constantes de plus à corriger (même geste que 0-b) |
| B-2 | `lab/…` inchangé | crée `lab/` par défaut de comportement → **viole la règle V2** |
| B-3 | run_dir sous `GAMES/<projet>/runs/` | mélange produit et preuve ; casse le registre append-only global |

Recommandation : **B-1**, avec la rétention Option C transposée telle quelle.

---

# Décisions ratifiées (Pierre, 2026-09-01)

## D1 — FORGE BOUNDARY *(figée)*
```
La Forge V2 doit être auto-contenue pour ses ressources internes et référencer
explicitement les surfaces du Studio pour ses entrées/sorties.

Aucune jonction NTFS.
Aucun miroir scripts/forge.
Aucune dépendance implicite à la disposition du repo source.

Toute modification de cette frontière doit être validée avec une suite de tests
ISOLÉE DES RESSOURCES RÉELLES.
```
Ce n'est pas un problème de chemins : c'est un **problème de frontière de paquet**. Une partie du
code raisonne encore comme si `Studio/scripts/forge/` et `Studio/control_plane/` existaient.
**Question ouverte rattachée** : `control_plane` est-il intrinsèque à la Forge ou une capacité du
Studio consommée par elle ? Mesure en §0-ter, options CP-1/CP-2/CP-3 — **non tranchée**.

| # | décision | statut |
|---|---|---|
| D2 | **Identité V2** : clé de signature propre au V2 (clé B ≠ clé A), **jamais versionnée**. | ✔ ratifié |
| D3 | **Entrée** : `GAMES/<game>/brief/project_brief.yaml`. *Le Brief décrit le projet de jeu, pas la Forge : la Forge le consomme, elle ne le possède pas.* | ✔ ratifié |
| D4 | **Sortie** : `EVIDENCE/{runs,bundles,reports}` + `RUN_INDEX.md`, rétention **Option C** (bundles versionnés, flux ignorés). | ✔ ratifié |
| D5 | **Aucune migration de `lab/`.** Les 4 566 sorties existantes ne suivent pas. `EVIDENCE/` démarre avec sa structure canonique et **zéro run**. | ✔ ratifié |
| D6 | **Un run ne crée jamais une surface architecturale.** Écriture hors contrat ⇒ `BLOCKED`. | ✔ ratifié |
| D7 | **Le patch n'est pas appliqué au V2.** Corriger la copie seule fabriquerait une variante de Forge. La Forge canonique est corrigée **une fois**, puis réimportée. | ✔ ratifié |
| D8 | **La source est TOUJOURS le HEAD observé au moment de l'import** — jamais un hash figé dans un document. Le repo source bouge en continu (`d6c2510c` → `6740d971` → `feeb29cb` pendant cette seule session). Toute importation Forge re-mesure son HEAD et l'inscrit dans `PROVENANCE.md` ; l'entrée existante reste l'historique du V2 actuel. | ✔ ratifié |

## Critère de sortie du chantier « test isolation »
Le vert seul ne suffit pas. Il faut les trois :
```
pytest vert
+ les tests utilisent réellement leurs fixtures
+ aucun test ne dépend accidentellement du contenu de la Forge réelle
```

# Ordre figé

```
0. FORGE SELF-LOCATION   comprendre · décider · tester   ← §0 fait · §0-bis fait · décision ouverte
       ↓
1. V2 IDENTITY           nouvelle clé de signature
       ↓
2. GAME INPUT            GAMES/<game>/brief/
       ↓
3. EVIDENCE CONTRACT     EVIDENCE/{runs,bundles,reports}
       ↓
4. FORGE PATH PATCH      dans le repo source
       ↓
5. nouvelle copie Forge → V2
       ↓
6. validation V2
       ↓
7. seulement ensuite : premier jeu
```

**Aucun jeu n'est importé, et aucun ne le sera avant l'étape 7.** Ce que ce document ferme, c'est
la question « où vivent l'entrée et la sortie ». Ce qu'il laisse ouvert, c'est **comment** corriger
l'auto-localisation — la seule décision encore sans réponse, et la seule qui touche le socle.

## Statuts

```
MASTER_SCHEMA V2 ........... IMPLEMENTED
RAIL_REGISTER .............. IMPLEMENTED
knowledge_base ............. IMPLEMENTED
FORGE (paquet) ............. IMPLEMENTED   importable si l'appelant place FORGE/ sur sys.path
TOOLS ...................... IMPLEMENTED
FORGE boundary (D1) ........ BLOCKED       9 occurrences / 6 fichiers ; strategie a valider
FORGE test isolation ....... BLOCKED       43 tests sur REPO_ROOT, 68 sur scripts/forge factice
control_plane placement .... BLOCKED       CP-1 / CP-2 / CP-3 non tranche (§0-ter)
V2 signature ............... BLOCKED       cle B a generer (ne jamais copier la cle A)
game input ................. BLOCKED       chemin ratifie D3, aucun brief materialise
EVIDENCE contract .......... BLOCKED       chemin ratifie D4, structure non creee
first V2 run ............... BLOCKED       regle D6
```

Pas de verdict global. `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED`.
