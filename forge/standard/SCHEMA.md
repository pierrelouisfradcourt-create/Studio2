# STANDARD — formats (v1, tranche minimale)

> Date : 2026-07-22 · Source : `docs/forge/FORGE_STANDARD_v1.md` (note de Pierre) + décisions
> de session 2026-07-22. `claim_verdict: NO_CLAIM_ALLOWED`.

## Ce qui est écrit, et ce qui ne l'est pas

On n'écrit que ce que le jeu en cours exige (§9 : éviter l'explosion de contexte, et ne pas
poser de couche sans lecteur). Pong exige un `game_contract` et un `system_contract`.

| Format | État | Écrit quand |
|---|---|---|
| `game_contract` | **écrit** | maintenant (Pong) |
| `system_contract` | **écrit** | maintenant (Pong) |
| `entity_contract` | non écrit | quand Snake aura besoin d'entités |
| `level_contract` | non écrit | quand un jeu aura des niveaux |

Ces formats sont une famille **distincte** des contrats d'agent (`forge/contracts/s0…s12.yaml`),
qui répondent à une autre question — « comment piloter un agent » vs « qu'est-ce qu'une brique
de jeu complète ». Deux vocabulaires, deux noms, aucune fusion : `agent_contract` / `brick_contract`.

---

## 1. `game_contract` — le budget du jeu

```yaml
schema_version: 1
game_id: pong
node: 1                      # position dans le curriculum
runtimes: [rules, browser, godot]

budget:
  reuses: []                 # briques déjà en bibliothèque, tier `validated` obligatoire
  adds:   [game_loop]        # UN seul système neuf déposé — loi d'empilement §7

assets:
  plan: cc0                  # cc0 (plan A) | generated (plan B si aucun CC0 ne convient)
```

**Ce que `adds` compte** : les **briques déposées en bibliothèque**, pas les lignes de code.
Pong écrit de quoi faire rebondir une balle, mais ne dépose pas de « système de collision » —
ce code est collé à Pong, personne ne le réutilisera. Breakout, lui, a besoin d'une collision
générale : il la dépose, et c'est **elle** qui consomme un delta. C'est la règle de catégorie
du §1 (un objet reste une entité tant qu'il n'est pas partagé).

Vérifié mécaniquement : `len(adds) <= 1` · tout `reuses[i]` existe en bibliothèque au tier
`validated` · toute brique déposée par le run appartient à `reuses ∪ adds`.

---

## 2. `system_contract` — une brique

```yaml
schema_version: 1
id: game_loop
category: system             # fixée À LA CRÉATION, jamais réévaluée après coup
provides: [game.loop]        # identifiants du registre de capacités — vocabulaire fermé
requires: [game.state]
owner: true                  # un seul fournisseur par capacité (§ collisions)
dependencies: []             # autres briques, vérifiées à l'import (jamais silencieux)
tests: [07_TESTS/unit/game_loop.test.mjs]
```

`category` détermine l'emplacement via `repo_map.yaml` — le builder ne choisit jamais où poser
un fichier. Une catégorie absente de la table est un `FAIL`, jamais un placement par défaut.

---

## 3. `wiremap` v2 — la carte indexée

JSON (comme l'existant, pour ne pas casser `check_wiremap`). Le déclencheur de la normalisation
est `schema_version: 2` : les wiremaps antérieures, qui emploient quatre mots libres pour l'état
(`fait`, `construit`, `DONE`, `PLANNED`), restent lues par l'ancien oracle et ne sont pas
réécrites — ce sont des preuves de runs passés.

La carte a **deux passes**, comme au §3 de la note : la liste des systèmes du jeu (passe 1,
gel dur — la casser rouvre le plan), puis les lignes qui les meublent (passe 2, gel au fil de
l'eau). `system_parent` fait le lien, et il est vérifié aux deux bouts.

Ne pas confondre `systems` et le budget : `systems` liste **les systèmes de ce jeu**, `adds`
liste **ceux qu'on dépose en bibliothèque pour être réutilisés**. Pong a plusieurs systèmes
(`game_loop`, `input`, `game_state`) mais n'en dépose qu'un.

```jsonc
{
  "schema_version": 2,
  "game_id": "pong",

  // passe 1 — les pièces du plan. system_parent doit désigner l'une d'elles.
  "systems": [
    {"id": "game_loop",  "category": "system",         "allowed_deps": ["game_state"]},
    {"id": "input",      "category": "system",         "allowed_deps": ["game_state"]},
    {"id": "game_state", "category": "system",         "allowed_deps": []},
    {"id": "presentation","category": "system.adapter","allowed_deps": ["game_state"]}
  ],

  // passe 2 — le meublage
  "lines": [
    {
      "id": "core.restart",
      "source": "CORE",            // CORE | EXPECTED | ADDITIONS | DERIVED
      "source_role": null,         // qui l'a proposée (obligatoire si EXPECTED/ADDITIONS)
      "reference": null,           // obligatoire si EXPECTED : la source externe nommée
      "provides": ["game.restart"],
      "requires": ["game.state"],
      "owner": true,
      "system_parent": "game_state",        // le système qui héberge cette ligne
      "address": "05_SYSTEMS/game_state/",  // posé par la réconciliation, pas par le builder
      "expected_proof": {
        "kind": "bot_action",
        "statement": "Après une fin de partie, relance → état identique au premier démarrage."
      },
      "state": "UNKNOWN",          // IMPLEMENTED | NOT_APPLICABLE | DEFERRED | BLOCKED | UNKNOWN
      "reason": null,              // obligatoire si NOT_APPLICABLE
      "until": null, "decider": null,        // obligatoires si DEFERRED
      "write_order": null,         // obligatoire si plusieurs écrivains d'un même état

      // "fichiers" liste les fichiers RÉELS déposés par cette ligne. Chaque entrée
      // déclare sa propre catégorie — jamais déduite après coup du nom de fichier
      // (§1, même règle que `category` sur system_contract : fixée À LA CRÉATION).
      // Une entrée restée une chaîne nue est une violation `categorie_fichier_non_declaree`.
      "fichiers": [
        {"path": "05_SYSTEMS/game_loop/loop.mjs", "category": "system"},
        {"path": "07_TESTS/unit/game_loop.test.mjs", "category": "test.unit"}
      ],
      "fonction": "", "preuve": "", "statut": ""   // champs v1 conservés
    }
  ],

  // Ce qu'on a écarté — JAMAIS supprimé (correction Pierre 2026-07-22).
  // Le juge d'un rôle n'est pas le vote des autres, c'est le jeu fini : une idée
  // portée par un seul rôle, écartée ici puis rajoutée pendant le build, prouve que
  // le rôle avait raison et que la fusion a eu tort. Jeté, ce signal est perdu.
  "discarded": [
    { "id": "", "source_role": "", "proposal": "", "discard_reason": "",
      "ended_up_in_game": null }   // rempli à la clôture du jeu, jamais avant
  ]
}
```

### Les états

### `system_parent` — plusieurs lignes par système

Une ligne n'a pas son propre dossier : elle vit **dans un système**. `core.game_state`,
`core.end_condition` et `core.restart` sont trois exigences distinctes hébergées par le même
système `game_state`. L'adresse se dérive donc de `category` + `system_parent`, jamais de
l'identifiant de la ligne.

C'est le champ prévu au §3 (passe 2) de la note de Pierre : `system_parent` **doit** désigner
un système réel, sinon `FAIL` — c'est ce qui empêche un meuble d'exister dans une pièce que le
plan n'a jamais posée.

### `fichiers` — la catégorie déclarée, jamais déduite

Une `address` de ligne cohérente ne dit rien de l'endroit où les fichiers **réels** ont
atterri : `check_placement` vérifiait l'`address`, jamais où le builder pose le code qu'elle
décrit. En `schema_version: 2`, chaque entrée de `fichiers[]` déclare donc sa propre
`category`, avec les mêmes règles que l'`address` d'une ligne :

- l'entrée est un objet `{path, category}` — une chaîne nue (ancien format) est une violation
  `categorie_fichier_non_declaree`, jamais acceptée en silence.
- `category` doit exister dans `repo_map["mapping"]`, sinon `categorie_fichier_non_mappee`
  (jamais de placement par défaut).
- `path` doit être cohérent avec le gabarit `mapping[category]` (même substitution `{id}`
  que pour l'`address` d'une ligne — dérivée de `system_parent` s'il y en a un valide, sinon
  de l'identifiant de la ligne), sinon `fichier_adresse_incoherente`.

La catégorie est **déclarée à la création**, jamais inférée du nom de fichier (`*.test.mjs`
→ test) : une heuristique de nommage est fausse dès qu'un fichier est mal nommé, et c'est
précisément la garantie que ce format retire au builder.

`fichiers[]` liste ce que la ligne **dépose**, jamais ce qu'elle consomme. Ce qu'une ligne
lit ou importe passe par `requires` / `allowed_deps` — ce sont deux questions distinctes, et
les confondre est exactement ce qui a fait déclarer un même fichier de preuve par six lignes.

#### Identité des gabarits d'artefacts nommés (`REPO_MAP_TEMPLATE_IDENTITY_V1`)

> Règle (verbatim, ratifiée Pierre 2026-07-23) : « Un gabarit qui revendique un artefact
> concret doit porter un identifiant stable permettant une correspondance univoque. Les
> motifs génériques sont réservés aux catégories, pas aux preuves d'existence. »

```yaml
rule:
  named_artifact_templates: { require_id: true, require_unique_binding: true }
scope: [test.*, asset.*]
validation:
  duplicate_claims:
    same_target_multiple_ids: FAIL
    same_id_multiple_targets: FAIL
```

`repo_map.yaml` porte donc deux formes de gabarit, distinguées par leur terminaison — c'est
la **table** qui déclare la forme, aucun code ne liste `test.*`/`asset.*` en dur :

| Forme | Terminaison | `{id}` vaut | Contrôle du chemin |
|---|---|---|---|
| dossier (motif de **catégorie**) | `/` final | le contenant (`system_parent`, sinon l'id de la ligne) | préfixe |
| artefact **nommé** | pas de `/` final, `{id}` obligatoire | le **nom du fichier** | égalité exacte |

Conséquence assumée : un artefact nommé vit **directement** dans le dossier de sa catégorie
(`07_TESTS/oracle/solvability.mjs`, `04_ASSETS/audio/bounce.wav`) — pas de sous-dossier, car
deux `player.png` dans deux sous-dossiers rouvriraient l'ambiguïté que la règle ferme.
L'extension n'est pas figée dans le gabarit : c'est le nom qui identifie, pas le format.

`check_placement` en tire deux volets, appliqués aux seuls gabarits d'artefact nommé :

- `revendications_multiples` (`same_target_multiple_ids`) — un même fichier revendiqué par
  plusieurs identités déposantes (ligne + catégorie). Un artefact nommé a **un** déposant.
- `identite_ambigue` (`same_id_multiple_targets`) — un même identifiant (catégorie + nom)
  désignant plusieurs fichiers distincts : le nom ne désigne plus rien d'univoque.

Les deux **énumèrent** le conflit ; il n'existe aucune résolution par « première
correspondance » — choisir un revendiquant au hasard cacherait le problème au lieu de le
montrer. Deux catégories peuvent partager un dossier (`test.oracle` / `test.solvability`) :
depuis que l'identité est le nom du fichier, ce partage n'est plus ambigu, et le cas
pathologique (les deux revendiquant le même fichier) tombe dans `revendications_multiples`.

Les wiremaps antérieures (`schema_version` absent, ou `1`) ne sont **pas concernées** :
`check_placement` ne touche à leur `fichiers[]` sous aucune forme — ce sont des preuves de
runs passés, pas des cibles de la normalisation.

`check_index` complète cette fermeture côté disque : tout dossier de premier niveau du jeu
qui n'appartient pas aux `roots` de `repo_map.yaml` est une violation
(`dossiers_hors_structure`) — ça attrape un builder qui crée `src/` ou `lib/` en dehors de
la structure figée.

### Les états

| État | Sens | Contrainte |
|---|---|---|
| `REQUIRED` | décidé, à faire, pas encore fait | l'état normal d'une ligne au moment du gel |
| `IMPLEMENTED` | fait et prouvé | un reçu d'oracle existe |
| `NOT_APPLICABLE` | ne s'applique pas à ce jeu | `reason` obligatoire · **interdit sur une ligne CORE** · incohérent avec le budget = `FAIL` |
| `DEFERRED` | reporté | `until` + `decider` obligatoires (sinon « jamais » avec une étiquette) |
| `BLOCKED` | empêché | motif obligatoire |
| `UNKNOWN` | pas encore décidé | **interdit au gel** — un squelette gelé avec un `UNKNOWN` est un `FAIL` |

Règle : *tout élément connu du squelette porte une décision explicite — pas forcément une
implémentation.* C'est ce qui supprime l'omission silencieuse.

**Deux moments, deux vérifications** — la même wiremap n'est pas jugée pareil avant et après :

| Moment | Interdits |
|---|---|
| **au gel** (avant build) | `UNKNOWN` (rien ne doit rester indécis) et `IMPLEMENTED` (rien n'est encore fait) |
| **après build** | `REQUIRED` (tout ce qui était à faire doit être devenu `IMPLEMENTED` ou `BLOCKED`) |

C'est ce qui rend le delta *attendu vs réel* calculable : au gel on connaît la promesse, après
build on connaît la livraison, et la soustraction est mécanique.

### Preuve attendue ≠ reçu

`expected_proof` est une **exigence**, posée avant le build. Le **reçu** est produit par
l'exécution des oracles, en aval. Les confondre ferait noter sa propre copie à celui qui
planifie — c'est la séparation qui rend `UNKNOWN` et `IMPLEMENTED` distincts.

### `lifecycle` — étage 1 ratifié Pierre 2026-08-02

Bloc **OPTIONNEL** par ligne de wiremap v2. Une ligne **sans** `lifecycle` reste valide
telle quelle — toutes les wiremaps existantes passent inchangées (« Ne pas casser
l'existant. »). `"lifecycle": null` vaut absence, comme les autres champs optionnels
d'une ligne (`reason`, `until`, …).

```jsonc
"lifecycle": {
  "state": "tested",                      // required | implemented | tested — enum FERMÉ
  "evidence": [                           // des REÇUS, jamais des déclarations d'agent
    {"kind": "oracle",                    // file_write | oracle | mutation | visual
     "ref": "lab/forge_runs/<run>/verdict.json",
     "sha256": "…"}                       // optionnel
  ],
  "last_verified": "2026-08-02T00:00:00+00:00",          // ISO8601 parsable
  "verified_by": "s10s-oracle-standard:breakout_v2-…"    // <oracle_id|run_id> — un reçu
}
```

**Invariants (verbatim, ratifiés Pierre 2026-08-02) :**

- « **implemented sans evidence = invalide** » — idem `tested`. Un état revendiqué sans
  reçu est exactement l'omission que ce bloc existe pour fermer.
- « **Le stampage reste oracle uniquement** » — `verified_by` n'est **jamais un agent
  LLM** : c'est un reçu (identifiant d'oracle ou de run). Un builder ne se déclare pas
  lui-même construit.
- « **L'overlay Observer reste obligatoire comme contre-pouvoir** » —
  `scripts/observer/wiremap_living.py` continue de confronter la carte aux transcripts
  et aux reçus, stampage ou pas ; la vue dérivée n'est pas remplacée par ce bloc.
- « **Ne pas casser l'existant.** »

**Règles mécaniques** (portées par `check_line_states`, `forge/standard_oracles.py`) :

- schéma **FERMÉ** : toute clé inconnue dans `lifecycle` (ou dans une entrée
  d'`evidence`) = `FAIL` — régime du studio, aucun champ toléré en silence ;
- `state` ∈ {`required`, `implemented`, `tested`}, obligatoire ;
- `evidence[]` : chaque entrée est un objet `{kind, ref, sha256?}` — `kind` ∈
  {`file_write`, `oracle`, `mutation`, `visual`}, `ref` non vide, `sha256` optionnel ;
- `implemented` ou `tested` **sans `evidence` non vide** = `FAIL` ;
- `tested` exige **au moins un** `evidence.kind` ∈ {`oracle`, `mutation`} — un fichier
  écrit ou une capture ne prouvent pas un test ;
- `implemented`/`tested` : `last_verified` (ISO8601 parsable) et `verified_by`
  (non vide) **obligatoires** ; en `required`, ces deux champs sont optionnels — rien
  n'a encore été vérifié, exiger un reçu forcerait à en fabriquer un — mais s'ils sont
  présents ils sont validés (jamais un contenu invalide accepté en silence).

**Étage 2 NON ratifié** : le **producteur** de ce bloc (stampage par l'oracle s10s en
passe post-verdict) n'est **pas** ratifié — conditionné **P1-G4** (capteurs fichiers).
À ce jour, PERSONNE n'écrit `lifecycle` : le schéma l'accepte, le validateur le vérifie,
aucun writer n'existe. C'est l'étage 1 tel que ratifié — un « validateur sans
producteur » assumé et daté (cf. règle ratifiée 2026-07-30), pas un oubli.

### `FORGE_ORACLE` — convention de sortie stdout des oracles Godot (ratifié Pierre 2026-08-02)

Section posée en réponse à la leçon `forge.forge_oracle_convention_undocumented` :
« la convention FORGE_ORACLE ne vit que dans le code Snake et le runner — aucun
document du standard ne la déclare ». Ce qui suit est relevé du code (le parseur et un
oracle réel), pas inventé.

**Forme littérale** — un oracle `.gd` (`SceneTree` autonome sous
`<jeu>/07_TESTS/oracle/*.gd`) émet sur stdout UNE ligne :

```
FORGE_ORACLE <nom_volet> {"ok": <bool>, "fails": [...], ...}
```

Regex de référence côté collecteur Forge : `product_oracle_godot.py:43`
(`_FORGE_ORACLE_LINE = re.compile(r"^FORGE_ORACLE\s+(\S+)\s+(\{.*\})\s*$")`). Exemple
réel : `games/breakout_v2/07_TESTS/oracle/demo_brick_destruction.gd:47`
(`print("FORGE_ORACLE demo_brick_destruction " + JSON.stringify({"ok": ok, "fails":
fails, "data": {...}}))`).

**Découverte** — `discover_oracle_files` (`product_oracle_godot.py:73-92`) liste, triés
(ordre déterministe), les `.gd` sous `<game_dir>/07_TESTS/oracle/` dont le texte
contient le marqueur `FORGE_ORACLE` (`_ORACLE_MARKER`, `product_oracle_godot.py:49`) —
lecture statique du fichier, jamais une exécution.

**Champs du JSON réellement consommés** (`product_oracle_godot.py:268-283`) :
- `ok` (bool, obligatoire) — absent ou non booléen ⇒ `NOT_MEASURED` motivé
  (`product_oracle_godot.py:270-274`), jamais un `FAIL` fabriqué ;
- `fails` (liste, `payload.get("fails", [])`) — défaut `[]` si absent.

Les autres champs observés côté jeu (`data`, `code`, …) sont conservés tels quels dans
`payload` (le dict JSON entier, réattaché au résultat — `product_oracle_godot.py:283`)
mais **non interprétés individuellement** par le collecteur ; s'ils portent un contrat
au-delà de ça, ce n'est pas déterminé par ce module.

**Dernière ligne conforme retenue** — `_parse_forge_oracle_line`
(`product_oracle_godot.py:159-176`) relit toute la sortie stdout et garde la DERNIÈRE
ligne qui matche la regex (des logs avant elle sont tolérés, le contrat ne les exclut
pas).

**Code de sortie** — convention observée côté jeu : `quit(0 if ok else 1)`
(`games/breakout_v2/07_TESTS/oracle/demo_brick_destruction.gd:48`). Le collecteur ne
s'en sert PAS pour trancher `OK`/`FAIL` : `returncode` n'est lu que pour motiver un
`NOT_MEASURED` (sortie illisible, timeout, erreur de spawn —
`product_oracle_godot.py:243-266`) ; la décision `OK`/`FAIL` vient uniquement du champ
`ok` du JSON.

**Discipline `NOT_MEASURED != OK`** — invariant déjà énoncé en tête du module
(`product_oracle_godot.py:21-24`) : binaire Godot introuvable, sortie illisible, JSON
invalide, oracle absent, timeout ⇒ `NOT_MEASURED` motivé, jamais une exception, jamais
un vert ni un rouge fabriqué.

**Mode d'exécution (MAJ lot L0b, 2026-08-10)** — la liste de noms de volets en dur
`GPU_WINDOW_REQUIRED_VOLETS` (qui rendait `core_render_frame` *toujours* `NOT_MEASURED`,
sans jamais l'exécuter) a été **retirée**. Le mode est désormais décidé par une
**directive statique** portée par la source du volet :

```gdscript
# forge:run_mode = gpu_window
```

Le collecteur la lit AVANT exécution et lance alors Godot en fenêtre GPU hors écran
(`GPU_WINDOW_FLAGS`) au lieu de `--headless`. Chaque volet exécuté porte
`mode_execution` ∈ {`gpu_window`, `headless`} dans son résultat. Le marqueur de payload
`requires_gpu_window: true` reste, lui, une déclaration d'EXÉCUTION (« je n'ai rien pu
mesurer ») et rend `NOT_MEASURED` dans les deux modes — il ne décide jamais du mode,
puisqu'il n'est lisible qu'après coup. Dépendance de poste inchangée et assumée :
`--headless` rend une texture nulle, la preuve pixel Godot est liée à une machine
équipée.

**Ce que le runner en fait** — `run_godot_product_oracle`
(`product_oracle_godot.py:179-285`) rend un mapping plat `{nom_volet: {"status":
"OK"|"FAIL"|"NOT_MEASURED", "passed": bool, "checked": bool, "fails": [...],
"fichier": ..., "payload": ...}}`, même contrat que `product_oracle.run_product_oracle`
— consommé par `check_observable_coverage`/`_volet_status` (`standard_oracles.py`, non
modifiés par ce module). Activation côté driver conditionnée par deux constats tracés,
jamais une heuristique de nom de jeu : descripteur `proof:` bien formé ET au moins un
fichier `FORGE_ORACLE` présent sur disque (`driver.py:1180-1222`).

---

## 4. Réconciliation — ce qui transforme les 4 sources en squelette gelé

1. **Dédoublonner en gardant la provenance** — une exigence portée par le CORE *et* par une
   brique reste une ligne, mais garde ses deux origines (retirer la brique ne doit pas
   effacer l'exigence).
2. **Détecter les conflits au lieu de les fondre** — brique exigeant une capacité absente du
   budget → `FAIL` (adapter ou refuser, jamais d'import silencieux).
3. **Placer** via `repo_map.yaml`.
4. **Indexer dans les deux sens** — fichier sans ligne = code non demandé ; ligne sans adresse
   = exigence sans emplacement.
5. **Auditer les collisions** sur le registre de capacités : deux `provides` identiques =
   collision · un `requires` sans fournisseur = trou · deux `owner` = double propriétaire ·
   plusieurs écrivains d'un même état sans `write_order` = `FAIL`.

Sortie : le squelette gelé. Le builder ne reçoit pas « fais un Pong » — il reçoit une carte où
chaque case a une adresse, un état attendu et une preuve attendue.
