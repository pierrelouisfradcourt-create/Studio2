# TOPOLOGIE V2 — passe conceptuelle

*2026-09-01 · **PROPOSED**, aucun code touché, aucune copie faite.*
*Ce document décide la **cible**. `MASTER_SCHEMA.html` décrit l'**état mesuré**. Ne pas les
confondre : c'est la distinction déclaré / observé, appliquée à nous-mêmes.*

Objet : définir la topologie **avant** de reconstruire, pour ne pas nettoyer une architecture
qu'on n'a pas encore décidée.

---

## 1 · Les cinq surfaces

Clarification préalable — **`MASTER_SCHEMA` n'est pas une surface** : c'est la *carte* des
surfaces. Le Studio V2 est donc **1 carte + 5 surfaces + 1 exception mécanique**.

| # | surface | définition en une phrase | possède |
|---|---|---|---|
| — | `MASTER_SCHEMA.html` | la carte : ce qu'est le système et comment il circule | rien — il décrit |
| 1 | `forge/` *(minuscules — contrainte d'import mesuree, §5)* | **la fabrique** : transforme une intention en jeu prouve | ses ressources internes (contrats, oracles, squelette, cle, resolution de role) |
| 2 | `knowledge_base/` | **la mémoire ratifiée** : ce que le studio a appris et validé | le catalogue et les propositions |
| 3 | `GAMES/` | **le portefeuille** : le rail, les briefs, les jeux retenus | l'intention de chaque jeu |
| 4 | `EVIDENCE/` | **les preuves produites** : ce qu'un run a réellement montré | runs, bundles, rapports, registre |
| 5 | `TOOLS/` | **les capacités** : moteurs génériques et intégrations externes | rien du métier — que des moyens |
| — | `.claude/` | **exception mécanique** : la porte ne s'exécute que là | les hooks et le pilotage |

**Disposition cible — fermee (Pierre, 2026-09-01)** :
```
Studio/
+-- forge/              package Python importable
+-- knowledge_base/
+-- GAMES/
+-- TOOLS/              dont TOOLS/observer/ (Observer rapatrie)
+-- EVIDENCE/
+-- .claude/            porte d'acces
+-- MASTER_SCHEMA.html  carte, jamais un composant executif
```
**Le mot « launcher » sort du contrat — c'etait une mauvaise abstraction.** Il n'y a pas de
composant a construire : **Claude Code est l'operateur, Python est le runtime, `forge/` est le
paquet.** Claude Code : il lit le contexte, charge les skills, prepare ou selectionne le
Brief, invoque la Forge, recupere les resultats, observe le run, presente les preuves au
HumanGate. La Forge ne devient jamais un daemon, un serveur, un orchestrateur autonome ni un
Control Plane.

```
Claude Code  ->  forge  ->  run  ->  EVIDENCE  ->  Claude Code / HumanGate
```

**Règle de possession** : une surface possède ses données propres. Aucune surface n'écrit dans une
autre sans passer par une **interface nommée** (§2). Une donnée n'a **qu'un seul propriétaire**.

### Ce que cette liste tranche
- **`control_plane` n'est PAS une surface du V2 — il reste dans l'ancien Studio.** Les 6 fonctions
  qui font le Control Plane (registre de providers, sondes de sante, `openclaw/*.yaml`) ont zero
  consommateur Forge. Les 3 fonctions dont la Forge a besoin resolvent **sa propre** `roles.yaml`
  et deviennent une ressource interne du paquet (§5). Aucune version simplifiee n'est recreee.
- **Modele d'execution : Claude Code -> Forge -> jeu.** Claude Code est l'operateur ; aucun composant
  d'orchestration, `main.py`, service ni CLI dedie n'existe dans le V2 (§5).
- **`observer` est retenu** dans `TOOLS/`, avec son interface reelle. Il observe et recupere les
  resultats d'execution ; il ne devient pas un Control Plane.
- Les intégrations externes (claude CLI · LM Studio/Qwen · Playwright · Godot · Node) sont des
  **préconditions d'exécution**, pas des fichiers. `TOOLS/` en porte la *fiche*, jamais le binaire.
- `EVIDENCE/` démarre **vide**. Aucune migration de `lab/` (4 566 fichiers). Le premier run V2
  produit la première preuve V2.

---

## 2 · Les interfaces

Huit, toutes nommées, toutes gardées. **Une flèche sans garde n'existe pas.**

```
        GAMES ──I1──▶ FORGE ──I2──▶ EVIDENCE
          ▲             │  ▲            │
          │             │  │            │
          │            I3  I4          I5
          │             ▼  │            │
          │      knowledge_base         │
          │             ▲               │
          I6            │               │
          │             └──── I7 ───────┘
          │                (HUMAN GATE)
          └───────────────────────────────┘

              TOOLS ──I8──▶ FORGE
```

| # | de → vers | objet transporté | garde |
|---|---|---|---|
| **I1** | GAMES → FORGE | `project_brief.yaml` (contrat `FORGE_PROJECT_INPUT_V0`) | `check_project_brief` **fail-closed avant toute dépense LLM** ; entrées alternatives interdites |
| **I2** | FORGE → EVIDENCE | run_dir · `verdict.json` **signé HMAC** · leçons · flux | `verify_run` re-vérifie et rend `AUTHENTIQUE` ou refuse ; `RUN_INDEX` append-only |
| **I3** | knowledge_base → FORGE | briques du catalogue, injectées au prompt | appariement de sous-chaîne **exacte** ; un contrat qui ne cite rien reçoit **rien** ; les propositions ne sont **jamais** servies |
| **I4** | FORGE → knowledge_base | **proposition** de fiche, jamais une écriture | `kb_proposal --apply --ratifie-par <humain>` — propose-only |
| **I5** | EVIDENCE → GAMES | état **observé** d'un nœud du rail | `RAIL_REGISTER` conserve déclaré **et** mesuré, côte à côte |
| **I6** | GAMES → MASTER_SCHEMA | mise à jour du rail dans la carte | **HumanGate uniquement** |
| **I7** | EVIDENCE → knowledge_base | leçon devenue connaissance | **HumanGate obligatoire — aucune arête directe** |
| **I8** | TOOLS → FORGE | résolution rôle → modèle/provider ; capacités externes | chemin de données **explicite** à chaque appel (jamais le défaut) |

**Trois interdits structurels :**
1. **Pas d'arête EVIDENCE → knowledge_base sans humain.** Une preuve ne devient jamais une
   connaissance toute seule. C'est I7, et c'est un gate, pas un tuyau.
2. **Pas d'arête FORGE → MASTER_SCHEMA.** La fabrique ne réécrit pas sa propre carte.
3. **Pas d'arête GAMES → EVIDENCE.** Un jeu ne fabrique pas sa propre preuve ; il passe par I1.

---

## 3 · Ce qui entre, ce qui sort

| surface | ENTRE | SORT | ne sort jamais |
|---|---|---|---|
| `FORGE/` | brief (I1) · briques KB (I3) · capacités (I8) | run + verdict signé (I2) · propositions KB (I4) | une décision de valeur ; une écriture durable |
| `knowledge_base/` | propositions ratifiées (I4 + gate) | briques servies (I3) | le contenu d'une proposition non ratifiée |
| `GAMES/` | état observé (I5) · décisions humaines | briefs (I1) | une preuve — elle vient d'EVIDENCE |
| `EVIDENCE/` | sorties de run (I2) | état observé (I5) · leçons candidates (I7) | une vérité — seul le gate en produit |
| `TOOLS/` | — | capacités (I8) | de la donnée métier |
| `MASTER_SCHEMA` | mises à jour gatées (I6) | la carte lue par tous | un état non mesuré |

**Structure interne fixée :**
```
GAMES/<game>/brief/project_brief.yaml     entrée canonique d'un jeu       (D3)
EVIDENCE/runs/<projet>/                   run_dir + verdict.json signé
EVIDENCE/bundles/<id>/                    bundles d'expérience — VERSIONNÉS
EVIDENCE/reports/                         lessons.jsonl · failure_events · error_journal
EVIDENCE/runs/RUN_INDEX.md                registre append-only (emplacement ALIGNÉ sur le code
                                          récupéré : driver._run_index_target, 9G 2026-09-02)
```
Rétention = **Option C**, déjà ratifiée (2026-08-04) : bundles versionnés, flux d'exploitation
ignorés. Elle est indépendante de l'emplacement et se transpose telle quelle.

---

## 4 · Les règles de vérité

Dix règles, toutes issues d'un incident réel ou d'une mesure de cette reconstruction.

| # | règle | origine |
|---|---|---|
| R1 | **Un état déclaré ne devient jamais automatiquement un état réel.** Une divergence se rend visible, elle ne se corrige pas en silence. | rail : 5 nœuds `CIBLE` avec du code |
| R2 | **Pas de consommateur démontré dans V2 ⇒ n'entre pas dans V2.** Quatre canaux à vérifier : import · CLI/sous-processus · `.mjs` · `.claude`/`TOOLS`. | adjudication |
| R3 | **Un run ne crée jamais une surface architecturale.** Écriture hors contrat ⇒ `BLOCKED`. | `lab/` naîtrait du défaut d'un module |
| R4 | **Une preuve provient du mécanisme qui a réalisé l'action**, sinon `AUTO_ATTESTED` explicite. | invariant ratifié 2026-08-28 |
| R5 | **Ressources internes → relatives au paquet. Surfaces → relatives à la racine.** | frontière D1 |
| R6 | **La source est toujours le HEAD observé au moment de l'import**, jamais un hash figé dans un document. | 3 HEAD en une session |
| R7 | **Propose-only** : aucune écriture durable sans HumanGate. | ADR-002 |
| R8 | **Un consommateur ne se trouve pas par la forme du nom.** | faux positif `execution_proof` |
| R9 | Vocabulaire de verdict **unique** : `OK` / `FAIL` / `BLOCKED`. `claim_verdict: NO_CLAIM_ALLOWED`. Trois verdicts séparés. | ratifié 2026-07-06 |
| R10 | **Une mesure porte le HEAD qu'elle a mesuré.** Sans lui, une carte se relit comme le présent. | 6 rapports faux en une campagne |
| R11 | **`visual` = preuve de *liveness* / rendu observable, pas preuve de qualité visuelle.** Le volet prouve « ça rend, et ça bouge » ; un rendu dégradé passe. | W-3, falsification V-2 2026-09-02 |

**Règle de sortie des chantiers** — le vert seul ne prouve rien :
```
pytest vert
+ les tests utilisent réellement leurs fixtures
+ aucun test ne dépend accidentellement du contenu de la Forge réelle
```

---

## 5 · Ce que la topologie implique — et ce qu'elle laisse ouvert

### Bonne nouvelle mesurée : la topologie choisie est **déjà correcte pour les surfaces**
`REPO_ROOT = Path(__file__).resolve().parents[2]` depuis `FORGE/forge/x.py` résout sur
`Studio/` — la racine. Rien à corriger de ce côté. Le patch de frontière se réduit à **deux
groupes disjoints**, mesurés hors tests :

| groupe | occurrences | fichiers | geste |
|---|---:|---:|---|
| **A — ressources internes** (`contracts`, `standard`, `oracles.json`, `.forge_key`) | **9** | 6 | passer en relatif au paquet |
| **B — surfaces** (`lab/…`) | **18** | 13 | renommer : 16 → `EVIDENCE/…`, **2 → `GAMES/<game>/brief/`** |
| `knowledge_base/…` | 8 | — | **déjà correct** — le nom V2 correspond |
| `games/…` | 1 | — | **déjà correct** |

**Le patch complet fait 27 occurrences dans ~17 fichiers.** Le coût n'a jamais été le patch : il
est dans l'isolation des tests (**43** tests sur `REPO_ROOT`, **68** sur un `scripts/forge`
factice), qui doit être refaite en même temps sous peine de vert-par-mauvais-chemin.

### Modèle d'exécution retenu — **Claude Code → Forge → jeu**
Claude Code EST l'orchestrateur. **Aucun composant d'orchestration, `main.py`, service ou CLI dedie n'est a creer.**
La seule question technique était : *depuis `Studio/`, quelle invocation charge et exécute la Forge
sans `sys.path` manuel et sans dépendance à l'ancien dépôt ?*

#### Mesure — 3 dispositions × invocation réelle (avec imports internes `from forge.X import Y`)
| disposition | `python -m …` depuis `Studio/` | `pytest` depuis `Studio/` | verdict |
|---|---|---|---|
| **L1** — `Studio/forge/` | ✅ `python -m forge.run_real` | ✅ | **seule à passer les 7 critères** |
| **L2** — `Studio/FORGE/forge/` *(disposition actuelle du V2)* | ❌ `ModuleNotFoundError: No module named 'forge'` | ✅ | **asymétrie** : les tests passent, l'exécution réelle non |
| **L3** — `Studio/FORGE/` = le paquet | ❌ imports internes | ❌ pytest | mort |

> **L2 est la disposition actuelle, et c'est le piège** : `pytest` vert, produit cassé. Exactement
> le mode de panne que ce studio documente. Sans cette mesure, on l'aurait découvert au premier run.
> *(Vérifié au passage : ce poste n'a pas d'import insensible à la casse — `python -m forge.X`
> échoue quand le dossier s'appelle `FORGE`. Aucune magie de casse à exploiter, tant mieux.)*

#### Invocation canonique — **une seule**
```
depuis Studio/ :   python -m forge.<module> [args]
tests          :   python -m pytest forge/tests
```
Même `sys.path` dans les deux cas (le répertoire courant), aucun `PYTHONPATH`, aucun `.pth`,
aucune installation, aucun fichier de lancement. À documenter dans le Master Schema et à tester.

#### Coût mesuré de L1
| geste | volume | note |
|---|---:|---|
| renommer la surface `FORGE/` → **`forge/`** (minuscules) | 1 | seul coût de nommage — la contrainte vient de Python, pas d'un goût |
| décrémenter d'un cran les racines : `parents[2]`→`[1]`, `parents[3]`→`[2]`, `parent.parent` | **32 + 4 + 4** | mécanique, vérifiable module par module |
| groupe A — ressources internes → relatives au paquet | 9 | **l'idiome cible est déjà présent** : `repair_dispatch.py:45` et `runtime_inventory_oracle.py:35` écrivent déjà `Path(__file__).resolve().parent / "contracts" / "roles.yaml"`, pendant que `contract.py:31` passe par `REPO_ROOT / "scripts" / "forge"`. **Deux écritures pour la même ressource** — le patch normalise, il n'invente pas |
| groupe B — surfaces `lab/…` → `EVIDENCE/` (16) et `GAMES/<game>/brief/` (2) | 18 | |

### `control_plane` — hors nouveau Studio, et ce que ça implique exactement
`registry.py` fait 115 lignes / **9 fonctions**. La Forge en utilise **3** :
`get_model_for_role` · `get_provider_for_role` · `get_reasoning_for_model` — **38 lignes**, et
toujours avec un chemin explicite vers **sa propre donnée** `forge/contracts/roles.yaml`.

Les **6 autres** — `load_capabilities`, `load_providers`, `get_provider_status`,
`probe_provider`, `probe_all_providers` — sont le Control Plane proprement dit : registre de
providers, sondes de santé, `openclaw/*.yaml`. **Zéro consommateur Forge.** Elles restent dehors.

> Ce n'est donc **pas** recréer un Control Plane simplifié. C'est la Forge qui résout **sa propre
> ressource interne** — exactement D1. Le Control Plane, lui, n'entre pas.

**Point à trancher** : `reasoning_observability.py:183` lit `REPO_ROOT / "control_plane" /
"registry.py"` **comme un fichier**, pour compter ses lecteurs (introspection d'audit). Sans
`control_plane/`, cette mesure devient impossible — la fonction doit être requalifiée ou retirée.

### `observer` — confirmé retenu
Outil réellement consommé (`from forge.anonymize_session_paths import …`), gardé dans `TOOLS/`
avec son interface réelle. **Il observe et récupère les résultats d'exécution ; il ne devient pas
un Control Plane.** Ses sorties visent aujourd'hui `lab/reports/observer/` → à réancrer sur
`EVIDENCE/reports/` par le même geste que le groupe B.

### Regle d'heritage — ne jamais reparer en important de l'ancien
Si une dependance ancienne apparait : **1)** mesurer son consommateur reel · **2)** determiner si
elle appartient a la nouvelle topologie · **3)** supprimer la dependance si elle est heritee et
sans consommateur · **4)** ne reconstruire une capacite que si la Forge V2 en a reellement besoin.
Le V2 n'est pas une version nettoyee de l'ancien Studio : c'est une topologie neuve batie sur la
verite systeme actuelle.

### Aucune compatibilité rétroactive
Rien de l'ancien Studio n'est importé « au cas où ». Aucun chemin ne remonte vers
`C:\TACTICAL_CHESS_STUDIO`. Ce qui n'a pas de consommateur dans la nouvelle architecture reste
dehors, y compris si cela ferait fonctionner le V2 plus vite.

### Décisions encore ouvertes — à fermer AVANT la reconstruction
| # | question | état |
|---|---|---|
| O1 | Invocation canonique | **FERMÉE** — `python -m forge.<module>` depuis `Studio/`, disposition L1, mesurée |
| O2 | `control_plane` | **FERMÉE** — hors V2. 3 fonctions (38 l.) deviennent une ressource interne de la Forge ; les 6 fonctions de Control Plane restent dehors |
| O3 | Environnement d'exécution | **FERMÉE — E1.** L'environnement fournit Python + PyYAML + Node.js + Claude CLI + Git. Aucune infrastructure créée. **Aucun lien avec l'environnement de l'ancien Studio.** |
| O4 | Les 7 CLI ambigus | **FERMÉE par O4-Forge** — la Forge est autonome sur ses ressources internes ; les CLI restent dans le paquet, leur consommateur (protocole) sera importé s'il est retenu. Aucun retrait opportuniste. |
| O5 | Observer | **FERMÉE** — conservé comme outil rapatrié dans `TOOLS/observer/`, sorties réancrées sur `EVIDENCE/`. |
| O6 | Qwen / `council` | **FERMÉE** — hors périmètre jusqu'à besoin démontré. **Aucun faux remplacement**, aucun import de `council`. |

### Ordre de reconstruction — inchangé, et il commence après O1-O6
```
0. topologie ratifiée (ce document)      ← PROPOSED
1. O1..O6 fermées
2. clé de signature V2
3. patch frontière dans le repo SOURCE (groupes A + B) + isolation des tests
4. re-mesure du HEAD source              (R6)
5. nouvelle copie Forge → V2
6. validation V2 (le triple critère, pas le vert seul)
7. premier jeu — seulement là
```

---

## Statut

```
topologie (5 surfaces + carte + exception) ... PROPOSED   ce document
interfaces I1..I8                            . PROPOSED
règles de vérité R1..R10                     . ratifiées individuellement, consolidées ici
spécification du patch (A: 9 · B: 18)        . MESURÉE, non appliquée
O1..O6                                       . BLOCKED
reconstruction Forge / jeux                  . BLOCKED par O1..O6
```

`evidence_verdict: MECHANICAL_VALIDATION_ONLY` · `claim_verdict: NO_CLAIM_ALLOWED` ·
pas de verdict global.

---

## 5-bis · Le contrat, en cinq lignes

```
CALLER
    Claude Code

ENTRYPOINT
    python -m forge.run_real

PRECONDITION
    L'environnement d'execution fournit Python + PyYAML + Node.js + Claude CLI + Git.
    Godot uniquement lorsqu'un profil en a besoin.

OWNERSHIP
    Claude Code possede l'environnement.
    Forge possede ses ressources internes.
    Forge ne possede ni Control Plane ni environnement global du Studio.

FAIL-CLOSED
    forge.preflight verifie les preconditions avant toute depense LLM.
```

**Il n'existe aucun objet « launcher » dans l'architecture cible.** Claude Code est l'appelant,
`forge.run_real` est le point d'entree de la Forge. Rien entre les deux.

---

## 6 · Matrice des dépendances restantes — **avant patch**

Mesurée sur le paquet `FORGE/forge` du V2, hors tests, le 2026-09-01. Chaque ligne porte son
consommateur réel et sa disposition proposée. **Aucune ligne n'est appliquée.**

### 6.1 Dépendances de code — imports étrangers (ni stdlib, ni `forge`)

| dépendance | consommateurs mesurés | appartient à | disposition proposée | statut |
|---|---|---|---|---|
| `yaml` (PyYAML) | **16 fichiers** — cœur | écosystème Python | **garder** — seule dépendance tierce du cœur | IMPLEMENTED |
| `control_plane` | 4 fichiers · 3 fonctions sur 9 (`get_model_for_role`, `get_provider_for_role`, `get_reasoning_for_model`, 38 l.) | ancien Studio | **supprimer la dépendance.** La résolution de rôle devient une **capacité interne** de la Forge, alimentée par `forge/contracts/roles.yaml`. Les 6 fonctions de Control Plane (providers, sondes, `openclaw`) restent dehors | BLOCKED |
| `council` | 1 fichier — `runtime.py:64 from council import QwenAdapter` | ancien Studio | **décision requise** — voir 6.4 | BLOCKED |
| `numpy` | 1 fichier — `asset_geometry/measure.py` | écosystème Python | garder **si** la chaîne asset entre en V2 | PASSIVE |
| `pygltflib` | 1 fichier — `asset_geometry/measure.py` | écosystème Python | idem | PASSIVE |
| `bpy` | 1 fichier — `asset_producer/build_asset.py` | Blender (exécuté *dans* Blender) | jamais installé par le V2 — précondition externe | PASSIVE |

### 6.2 Dépendances de chemin — pointent hors des surfaces V2

| chemin | occurrences | consommateur | disposition | statut |
|---|---:|---|---|---|
| `REPO_ROOT / "scripts" / "forge" / …` | **9** (6 fichiers) | `contract` · `oracle` · `driver` · `verdict` · `run_real` · `asset_dispatch` | **groupe A** → relatif au paquet | BLOCKED |
| `REPO_ROOT / "lab" / …` | **18** (13 fichiers) | runs, évidences, rapports, briefs | **groupe B** → 16 vers `EVIDENCE/`, 2 vers `GAMES/<game>/brief/` | BLOCKED |
| `sys.path.insert(REPO_ROOT / "scripts")` | 3 | `asset_dispatch` (×2), `pair_preflight` | supprimer — plus de `scripts/` en V2 | BLOCKED |
| `runtime.SCRIPTS_DIR = parent.parent` + `sys.path.insert` | 1 | `runtime.py`, pour importer `council` | supprimer avec 6.4 | BLOCKED |
| `reasoning_observability.py:183` lit `control_plane/registry.py` **comme un fichier** | 1 | introspection d'audit (compte de lecteurs) | requalifier ou retirer — la mesure devient impossible sans `control_plane/` | BLOCKED |
| `.venv312/Scripts/python.exe` | **4** (dont 3 dans `oracles.json`) | registre d'oracles | **pointe l'ancien Studio** — à réécrire avec l'environnement V2 | BLOCKED |
| `oracles.json` → `pytest scripts/forge/tests/` · `games/leviathan` | 2 entrées | `resolve_oracle` | réécrire : `forge/tests`, et retirer les jeux non importés | BLOCKED |
| `parents[2]` · `parents[3]` · `parent.parent` | **32 · 4 · 4** | tout le paquet | décrémenter d'un cran (disposition L1) | BLOCKED |

### 6.3 Dépendances d'environnement — **le V2 n'en a aucun**

| précondition | état mesuré | statut |
|---|---|---|
| Interpréteur Python + PyYAML | **aucun environnement dans `Studio/`.** Toutes mes mesures ont utilisé `C:\TACTICAL_CHESS_STUDIO\.venv312` — une dépendance à l'ancien Studio que je n'avais pas déclarée | **BLOCKED** |
| Node.js | **109 invocations `node`** dans le paquet ; `0 node_modules`, `0 package.json` dans le V2 | BLOCKED |
| `claude` CLI | 13 invocations — exécuteur LLM unique | UNKNOWN (non sondé) |
| Godot | **53 invocations** — builds et capture GPU | UNKNOWN |
| Blender | 5 invocations — chaîne asset | UNKNOWN |
| `git` | 15 invocations — gardes de périmètre | UNKNOWN |
| `.forge_key` | absente — et **ne doit jamais être copiée** depuis l'ancien Studio | BLOCKED |

> **Conséquence** : l'invocation canonique `python -m forge.run_real` n'est pas encore
> déterministe — *quel* `python` n'est pas défini. C'est une décision d'environnement, pas de code.

### 6.4 La seule capacité réellement perdue — red-team Qwen indépendante

```
runtime.py:64   from council import QwenAdapter          (import PARESSEUX)
qwen_available()  -> toute exception = indisponible
route_step()      -> provider lmstudio + Qwen absent = fallback "claude-blind (fallback)"
                     avec une `reason` explicite ; le reviewer RÉEL est toujours restitué
```
Sans `council.py`, **le V2 ne plante pas** : il dégrade, et il le dit — la dégradation est honnête
par construction, jamais silencieuse. Mais **ADR-002 gate 4 (« Qwen = red team indépendant »)
n'est plus satisfiable**. Trois issues, aucune retenue :
1. **reconstruire** un adaptateur LM Studio comme capacité interne de la Forge (la Forge en a un
   besoin démontré : s11 indépendante, World Scan, specs asset) ;
2. **accepter** `claude-blind` et enregistrer que gate 4 n'est pas satisfait en V2 ;
3. **suspendre** les profils qui exigent une red-team indépendante (`full_content`).

### 6.5 Ce que la matrice ne couvre pas

`.mjs` (51 fichiers citant `scripts/forge`), hooks `.claude/` (2 calculs `parents[2]`), et
`TOOLS/observer` (sorties vers `lab/reports/observer/`) portent la même dette de chemin. Mesurés
en §5 et dans `ADJUDICATION.md`, non re-détaillés ici.

---

## 7 · Frontière figée · dépendances runtime de `forge.run_real` · environnement

### 7.1 La frontière — figée

```
ANCIEN STUDIO                                    V2
control_plane · openclaw · council               Claude Code
anciennes interfaces · anciennes lanes                │
architectures expérimentales · legacy                 ▼
                                                   forge/
        ─── aucune copie opportuniste ───▶            ├── contrats Forge
                                                      ├── knowledge_base/
                                                      ├── GAMES/<game>/brief/
                                                      ├── exécution
                                                      ├── observation (TOOLS/observer)
                                                      └── EVIDENCE/
```
**On ne reconstruit pas l'ancien Studio. On reconstruit uniquement le système dont la nouvelle
vérité démontre le besoin.** C'est plus important que de gagner quelques milliers de fichiers.

L'Observer est retenu **parce qu'il a un rôle réel dans cette boucle** — observer le run et en
rapatrier les résultats — pas parce qu'il existait avant.

### 7.2 Architecture ≠ runtime
```
ARCHITECTURE                        RUNTIME
Claude Code → forge → surfaces      Python disponible
  ├── knowledge_base                Node si nécessaire
  ├── GAMES                         dépendances réellement nécessaires
  └── EVIDENCE
```
**L'environnement est une précondition d'exécution, pas une surface du Studio.** Le fait que le V2
n'ait ni `.venv` ni `node_modules` n'ouvre aucun chantier d'infrastructure.

### 7.3 Dépendances réellement nécessaires à `forge.run_real` — mesurées

Fermé transitif de `forge.run_real` : **26 modules**. Imports étrangers analysés en distinguant
**niveau module** (bloquant) et **paresseux** (dans une fonction).

| palier | dépendance | portée mesurée | statut |
|---|---|---|---|
| **T0 — bloque l'import** | **PyYAML** | 4 modules du fermé au niveau module | requis |
| **T0 — bloque l'import** | **`control_plane`** | **1 seul module : `forge/contract.py:76`**, au niveau module | **le seul verrou dur** — à retirer au patch |
| **T1 — tout run réel** | `claude` CLI | `run_real` · `runtime` | requis |
| | `node` | `run_real`(5) · `oracle`(3) · `verify_run` · `product_oracle`(8) · `preflight`(2) · `standard_oracles` · `mutation_proof`(2) | requis |
| | `git` | `verdict`(2) · `run_real`(2) — gardes de périmètre | requis |
| **T2 — selon profil** | `godot` | `driver`(6) · `static_oracles`(3) · `product_oracle` · `mutation_proof` · `studio_link` | profils Godot seulement |
| | `npm` | `oracle`(1) | marginal |
| **T3 — hors fermé** | `numpy` · `pygltflib` · `bpy` (Blender) | `asset_geometry` · `asset_producer` — **absents du fermé** | **non requis** pour `run_real` |
| **dégradé** | `council` / Qwen | `runtime.py`, import **paresseux** | absent ⇒ `claude-blind (fallback)`, visible |

**Deux résultats qui simplifient beaucoup :**
1. **Aucun paquet npm.** Les 47 `.mjs` de la Forge et ceux de `knowledge_base/` n'importent que
   des modules natifs `node:` (`node:fs`, `node:path`, `node:test`, `node:assert/strict`,
   `node:child_process`, `node:crypto`, `node:os`, `node:url`). → **ni `package.json`, ni
   `node_modules`.** Node seul suffit. *(Playwright reste une dépendance du jeu, dans son propre
   dossier, jamais de la Forge.)*
2. **La chaîne asset n'est pas sur le chemin d'un run.** `numpy`, `pygltflib`, `bpy` sont hors du
   fermé transitif : un premier run V2 n'en a aucun besoin.

**Environnement minimal d'un premier run V2 (profil HTML/JS, sans Godot) :**
```
Python 3.12 + PyYAML   ·   Node.js   ·   claude CLI   ·   git
```

### 7.4 Comment Claude Code fournit cet environnement
Aucune infrastructure à concevoir. Trois formes possibles, la plus simple d'abord :

| # | forme | déterminisme | dépendance à l'ancien Studio |
|---|---|---|---|
| **E1** | un interpréteur avec PyYAML, **nommé explicitement dans l'invocation** ; Node, `claude` et `git` depuis le `PATH` | l'invocation porte son interpréteur — rien d'implicite | aucune, dès qu'il ne pointe plus `.venv312` |
| E2 | `.venv` propre au V2, créé une fois à la racine | idem, avec isolation des versions | aucune |
| E3 | interpréteur système | dépend de la machine | aucune, mais non reproductible |

**Le contrôle appartient à un mécanisme qui existe déjà** : `forge/preflight.py` — pré-vol
**mécanique avant le premier dispatch LLM**, qui vérifie déjà qu'un projet est résoluble dans le
registre d'oracles et consomme une leçon KB ratifiée (`pat-forge-preflight_oracle_registration`).
Y ajouter la vérification des préconditions T0/T1 **ne crée aucune surface** : c'est étendre une
garde existante, au bon endroit — avant toute dépense LLM.

> Le trou d'aujourd'hui n'est donc pas architectural : `python -m forge.run_real` n'est pas encore
> déterministe **parce qu'aucun interpréteur n'est nommé**, pas parce qu'il manquerait un composant.
> Mes propres mesures ont utilisé celui de l'ancien Studio — c'est exactement la dépendance à
> supprimer.

### 7.5 Ordre de travail — **corrigé**

L'ordre que j'avais proposé plaçait la re-mesure du HEAD **après** le patch. C'est un défaut :
le dépôt source bouge en continu (3 HEAD pendant cette reconstruction), donc patcher puis
re-mesurer revient à patcher un état déjà dépassé, et à reconstruire le V2 depuis une Forge
périmée pendant le chantier. **La re-mesure vient d'abord.**

```
1. décisions fermées                    O1..O6            ← fait
2. SNAPSHOT / re-mesure du HEAD source  état connu, daté  ← l'ancrage de tout ce qui suit
3. patch DANS LA SOURCE                 groupes A + B + isolation des tests
4. validation DE LA SOURCE              triple critère, sur le HEAD du snapshot
5. import / copie vers V2               depuis cet état validé, HEAD inscrit (R6)
6. validation V2                        invocation canonique + preflight
7. premier jeu
```
Le patch s'applique à un **état identifié**, pas à une cible mouvante. Et les références aux
anciennes surfaces disparaissent à l'étape 3 — **pas avant**.

Sur `council`/Qwen : **rien n'est reconstruit maintenant.** Si un profil exige réellement une
red-team indépendante, un adaptateur minimal sera écrit **dans la nouvelle Forge**, avec une
interface explicite. On n'importe pas `council` parce qu'il existait.

---

## 8 · SNAPSHOT SOURCE — l'ancrage du patch (étape 2)

*Mesuré le 2026-09-01. Ce bloc est l'état identifié auquel le patch s'appliquera. Toute mesure
porte le HEAD qu'elle a mesuré (R10).*

```
dépôt    : C:\TACTICAL_CHESS_STUDIO
branche  : master
HEAD     : feeb29cbd921f6aa663e96be902757e52cd32e84   (feeb29cb)
date     : 2026-09-01 16:33:44 +0200
sujet    : feat(forge): pré-enregistrement PAIRE 4 — 10 items scellés, registre de
           non-régression de paire EXÉCUTÉ, zéro dépense LLM
état     : 76 lignes de status — 14 modifiés, 62 non suivis
```

### 8.1 Dérive depuis `d6c2510c` — le HEAD dont le V2 est la copie
**2 commits**, et ils touchent les surfaces copiées :

| fichier | delta |
|---|---:|
| `scripts/forge/driver.py` | +77 |
| `scripts/forge/oracles.json` | +7 |
| `scripts/forge/pair_preflight.py` | +16 |
| `scripts/forge/tests/test_mutation_path_repo_relative.py` *(nouveau)* | +309 |
| **total** | **408 insertions, 1 suppression, 4 fichiers** |

**La copie Forge du V2 est donc périmée de 2 commits sur 4 fichiers.** C'est exactement ce que
la séquence corrigée évite : on n'importe pas depuis `d6c2510c`, on importera depuis l'état
validé à l'étape 4.

### 8.2 La dérive ne résout pas le problème de frontière
`driver.py` à `feeb29cb` porte **toujours** `A=1` (`REPO_ROOT / "scripts" / "forge" / "standard"`)
et `B=2` (`REPO_ROOT / "lab" / …`). Les groupes A et B restent entiers.

⚠ **Faux ami à ne pas confondre.** Le commit `6740d971` s'intitule « chemins wiremap
repo-relatifs normalisés ». Vocabulaire identique, **sujet différent** : il corrige un
double-préfixe entre `wiremap.json` et `src_root` (`games/p3_alpha/games/p3_alpha/…` →
`FileNotFoundError` → `state.json` menteur resté `RUNNING`). **Rien à voir avec la frontière de
paquet.** Ne pas en conclure que le patch A/B est déjà fait.

### 8.3 ⚠ Précondition de l'étape 3, mesurée : la source est en cours d'édition
```
 M scripts/forge/dispatch.py
 M scripts/forge/oracles.json
 M scripts/forge/tests/test_evidence_isolation_fixture.py
?? scripts/forge/tests/test_micro_sonde_profile.py
```
Une autre session travaille **en ce moment** dans `scripts/forge/`. Le snapshot reste une mesure
valide, mais **l'étape 3 ne peut pas s'appliquer sur un arbre en cours d'édition** : le patch de
frontière et le travail en vol s'entrelaceraient.

**Précondition explicite avant l'étape 3** : arbre de travail `scripts/forge/` propre, ou session
concurrente mise en pause. Ce n'est pas une préférence — deux écritures simultanées sur les mêmes
fichiers produiraient un état dont personne ne pourrait dire ce qu'il contient.

### 8.4 Statut de la séquence
```
1. décisions O1..O6 fermées ......... IMPLEMENTED   (documentaire)
2. snapshot du HEAD source .......... TESTED        feeb29cb, mesuré ci-dessus
3. patch dans la source ............. BLOCKED       arbre en cours d'édition (8.3)
4. validation de la source .......... BLOCKED
5. import / copie vers V2 ........... BLOCKED
6. validation V2 .................... BLOCKED
7. premier jeu ...................... BLOCKED
```
