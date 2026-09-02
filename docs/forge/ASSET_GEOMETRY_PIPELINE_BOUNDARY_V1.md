# Asset Geometry Pipeline Boundary V1 — frontière Windows / WSL / Godot

> **Date** : 2026-08-06 · **Source** : décision Pierre 2026-08-06, implémentée le même jour
> **Statut** : IMPLEMENTED — `scripts/forge/asset_geometry/`, 32 tests verts
> `claim_verdict: NO_CLAIM_ALLOWED`

Document de référence de la **frontière**. Le design complet (mesures, checks, corpus) vit
dans `ASSET_GEOMETRY_ORACLE_V1_DESIGN.md`.

---

## 1. La règle qui fonde tout

> **Le producteur ne peut pas être son propre juge.**

Ce n'est pas un principe moral, c'est un constat mesuré. Une première campagne de mesure faite
**avec Blender** a rapporté une géométrie parasite (`Icosphere`, 42 sommets) présente dans les
8 assets de référence, et un `min = −1.0` uniforme. Vérification faite : cette géométrie
n'existe dans aucun fichier. Elle est **créée par l'importeur glTF de Blender**, dans une
collection `glTF_not_exported`. L'outil de production avait fabriqué la géométrie qu'il
prétendait mesurer.

Le parseur indépendant, lisant les octets du `.glb`, ne l'a jamais vue.

---

## 1 bis. Le producteur a deux moitiés (ajout 2026-08-06)

La couche productrice n'est pas un bloc : **une intention est traduite avant d'être
fabriquée**. Deux runtimes distincts, donc deux reçus signés — sinon la trace laisserait
croire que Blender a inventé les paramètres.

| runtime | rôle | modèle | résolu par |
|---|---|---|---|
| `asset_spec_author` | demande gameplay → spec paramétrée | `qwen2.5-14b-instruct` (LM Studio) | registry `roles.yaml` |
| `asset_producer` | spec → géométrie | `aucun` (procédural) | registry `roles.yaml` |

Étapes d'audit : `s-asset-spec` puis `s-asset-produce`. Chacune écrit
`spawn_prepared` **avant** exécution et `spawn_executed` après, dans le même
`dispatch_audit.jsonl` HMAC que tout le reste. Vérifiables par `verify_audit_line()`.

**Aucun modèle en dur.** Le modèle vient du registry ; un rôle non résolu **arrête le
run** (`role non resolu par le registry`) au lieu de partir avec `model: null` — panne
constatée le 2026-08-06, dont l'erreur remontée (`HTTP 400`) ne disait rien du vrai défaut.

**Gardes sur la sortie de Qwen** (le modèle propose, les énumérations disposent) :
archétype et catégorie en listes **fermées**, `consumer` non vide, dimensions bornées
à [0,05 ; 20] m, une seule réparation ciblée puis échec explicite.

**Limite mesurée, déclarée dans son contrat de runtime** : aucun mécanisme ne vérifie que
l'archétype choisi correspond *sémantiquement* à la demande. Mesuré : « piédestal » a
produit `archetype: platform` — plausible, mais c'est un jugement humain, pas une
correspondance vérifiée.

## 2. Les trois couches et leurs responsabilités

| couche | où | outil | responsabilité | **jamais** |
|---|---|---|---|---|
| **Producteur** | WSL2 Ubuntu-24.04 | Blender 5.1.1 + Hunyuan3D-2.1 | créer · exporter · déclarer | juger, mesurer pour preuve |
| **Preuve** | Windows | `pygltflib` (`.venv312`) | mesurer · classer · juger | produire, corriger, nettoyer |
| **Runtime** | Windows | Godot 4.6 headless | confirmer l'intégration | servir de mesure de référence |

**Découplage clé** : la couche preuve **ne dépend pas de WSL**. Elle mesure des `.glb` déjà
sur disque. Seul le producteur dépend de WSL. Un poste sans WSL peut valider des assets ; il
ne peut pas en fabriquer.

À l'intérieur même de la couche preuve, la séparation est stricte :
`measure.py` ne juge jamais · `oracle.py` ne mesure jamais. C'est ce qui rend l'oracle
testable sur des measurements écrits à la main, sans aucun asset (7 tests le font).

---

## 3. Formats d'échange

| artefact | producteur | consommateur | statut |
|---|---|---|---|
| `<asset>.glb` | Blender / téléchargement | `measure.py` | matière première |
| `asset_metadata.json` | Blender | `oracle.py` | **DECLARATION** |
| `<asset>.glb.geometry.json` | humain (HumanGate) | `oracle.py` | recensement des rôles, permanent, lié par `sha256` |
| `measurement` (JSON) | `measure.py` | `oracle.py` | **PROOF** |
| `ASSET_GEOMETRY_REPORT` | `oracle.py` | HumanGate / Forge | verdict, schéma `report_schema.json` |
| `GODOT_PROBE\|{...}` | `probe.gd` | tests / HumanGate | **PROOF** runtime |

---

## 4. Preuves acceptées, et ce qui n'en est pas une

**Accepté comme preuve** — une mesure refaite depuis les octets du fichier, par un outil qui
n'a pas produit ce fichier : `measure.py` (glTF brut) et `probe.gd` (instanciation Godot).

**Jamais accepté comme preuve** — toute métadonnée écrite par le producteur. Elle est
classée `DECLARATION`, et n'est pas ignorée pour autant : le check `declaration_mismatch`
la confronte à la mesure. Un écart supérieur à la tolérance est un `FAIL`. La déclaration
gagne ainsi un usage sans jamais gagner d'autorité.

**Accord inter-exécuteurs** — quand les deux exécuteurs mesurent le même asset, ils doivent
concorder. Vérifié sur `Knight.glb` :

| | nœuds mesh | `min_y` | `max_y` |
|---|---|---|---|
| `measure.py` (parseur glTF) | 15 | −0.0000 | 2.4666 |
| `probe.gd` (Godot 4.6) | 15 | −0.0000265 | 2.46655 |

Deux tests figent cet accord. S'ils divergent un jour, c'est que l'un des deux ment — et le
rapport doit cesser d'être cru.

---

## 5. Erreurs bloquantes

| situation | verdict | `reason` |
|---|---|---|
| WSL absent, ou binaire Blender absent | `BLOCKED` | `BLENDER_EXECUTOR_UNAVAILABLE` |
| géométrie présente sans rôle déclaré ni classification MAIN | `BLOCKED` | `SECONDARY_GEOMETRY_WITHOUT_CONTRACT` |
| manifeste dont le `sha256` ne correspond plus à l'asset | `BLOCKED` | `MANIFEST_STALE` |
| déclaration fournie sans le champ attendu | `BLOCKED` | `DECLARATION_MISMATCH` |
| fichier illisible / aucun nœud mesh | `FAIL` | `NO_MEASURABLE_GEOMETRY` |
| défaut géométrique mesuré | `FAIL` | nom du check |

**Jamais `OK` par défaut.** Un exécuteur absent ne produit pas un succès, et ne produit pas
non plus un saut silencieux : il produit un `BLOCKED` nommé.

Vocabulaire fermé `OK` / `FAIL` / `BLOCKED` — `REVIEW_REQUIRED` n'est pas introduit ; la
nuance vit dans `reason` (ratifié Pierre 2026-08-06). Un test fige cette fermeture.

**Priorité d'agrégation** : un défaut **mesuré** (`FAIL`) prime sur une déclaration
**manquante** (`BLOCKED`). Un asset enterré reste `FAIL` même s'il lui manque aussi
son manifeste.

---

## 5 bis. La quatrième frontière : l'écriture durable (ajout 2026-08-06)

Les §2–5 décrivent la frontière **de mesure**. Il en existe une seconde, découverte par
violation : la frontière **d'écriture**.

Le premier lot d'assets a été écrit **directement** dans `knowledge_base/catalog.json`.
C'était une faute : toute mémoire de référence de ce dépôt est *propose-only*
(ADR-002 — « la machine propose et prouve, l'humain tranche et signe »). Le catalogue a
été restauré à l'identique de `HEAD`, et l'écriture directe remplacée.

| geste | qui | outil |
|---|---|---|
| produire | worker `asset_producer` | `build_asset.py` |
| mesurer / juger | oracle indépendant | `oracle.py` |
| **proposer** | machine | `propose_asset.py` → `knowledge_base/proposals/asset.<id>.yaml` |
| **ratifier** | **humain nommé** | `kb_proposal.py --apply <id> --ratifie-par "<humain>"` |

Aucun nouveau système : `propose_asset.py` écrit exactement le même artefact
`kb.proposal.v1` que `kb_proposal.py`, et la promotion passe par la porte existante —
déjà générique (`brick_id or asset_id or role_id`) et déjà testée. `--ratifie-par` est
**requis** : le module ne devine jamais qui a autorisé une écriture.

Deux gardes s'ajoutent :
- `propose_asset.py` **refuse** de proposer un asset dont l'oracle ne rend pas `OK`. Une
  proposition transporte un verdict, elle ne le remplace pas.
- `kb_proposal.apply_proposal` exécute `kb-validate` **après** écriture et **restaure** le
  catalogue si le verdict est négatif. Vérifié en vivo : une provenance mal formée a
  déclenché la restauration.

**Rôles d'écriture, à ne jamais confondre :**

| fichier | écrit par | jamais écrit par |
|---|---|---|
| `<asset>.glb.metadata.json` | le **producteur** (déclaration) | — |
| `<asset>.glb.geometry.json` | le **HumanGate** (recensement) | le producteur |
| `knowledge_base/proposals/*.yaml` | la **machine** (proposition) | — |
| `catalog.json` | **`--apply` + humain nommé** | producteur, oracle, proposeur |

## 5 ter. Où vont les échecs (ajout 2026-08-06)

Un asset qui échoue à l'oracle **n'entre pas** dans la bibliothèque — et ne se jette pas
non plus : c'est la pièce à conviction qui justifie une leçon. Il est archivé dans

```
knowledge_base/assets/_failed_cases/<asset_id>/
    <asset>.glb + .metadata.json + .spec.json + .generation_report.json
    oracle_report.json     rapport figé au moment de l'archivage
    lesson.json            copie de la leçon dérivée
    CAUSE.md               pourquoi il a échoué, et ce que ça a appris
```

Cette séparation garde l'invariant : `knowledge_base/assets/props3d/` ne contient **que**
des assets dont l'oracle rend `OK` — vérifié après archivage (7/7).

## 6. Ce que cette frontière ne garantit pas

- La mesure est en **pose de liaison**, pas skin-évaluée (`skin_evaluated: false` dans chaque
  rapport). Exacte pour `min_y` sur le corpus de référence ; divergence ≤ 9 % sur `max_y`.
- `all_meshes_declared` détecte la géométrie **non déclarée**, jamais la géométrie **mal
  déclarée** : écrire `role: collider` sur une sphère décorative passe. Le manifeste engage
  un humain, il ne le vérifie pas.
- Aucun jugement esthétique, par construction. Chaque rapport porte un `fog` explicite.
- La cohérence d'échelle **entre** assets d'un même jeu n'est pas évaluée.
