# Asset Geometry Oracle V1 — design

> **Date** : 2026-08-06
> **Source** : session Opus « Asset Grounding Forge V1 » (audit Phase 0 + mesures Blender en direct)
> **Statut** : DESIGN — ratifié Pierre sur les 5 décisions listées §12. Aucune ligne implémentée.
> **Périmètre** : lane FORGE. `claim_verdict: NO_CLAIM_ALLOWED` — ce document décrit un mécanisme
> et ses limites ; il ne certifie pas qu'il couvre tous les défauts géométriques possibles.

---

## 1. Pourquoi ce chantier existe

Le prompt d'origine visait le flottement : « objets flottants, pivots mal placés, modèles sous
le sol ». L'audit a mesuré le corpus réel et a trouvé **deux problèmes de nature différente** :

1. **Ancrage** — les 8 assets de référence sont ancrés exactement à zéro (`min_y = −0.0000`) ;
   la sortie générée, elle, est enterrée de moitié (`min_y = −0.9993`), et systématiquement.
2. **Géométrie non réclamée** — `Knight.glb` embarque 7 variantes d'arme/bouclier dans son
   graphe de scène, que le consommateur (`games/chess_tcg/ui/game3d.gd:146`) ne masque jamais.

Le second n'est pas un problème d'ancrage, et aucun check de flottement ne l'attraperait.

La question utile n'est donc pas « est-ce que ça flotte », c'est :

> **Chaque morceau de géométrie de ce fichier est-il réclamé par quelqu'un ?**

C'est le problème de lignée causale appliqué aux assets : le mesh principal a une provenance,
la géométrie secondaire doit avoir une raison, sinon elle devient une zone morte.

---

## 2. Preuves d'audit (mesurées, pas supposées)

Environnement de mesure : Blender 5.1.1 (WSL2 Ubuntu-24.04,
`~/3d-pipeline/blender/blender-5.1.1-linux-x64/blender`), exécuté en direct le 2026-08-06.
Pipeline monté hors dépôt le 2026-07-14 (session « 3D asset generation workstation setup »).

**Convention d'axe — à ne jamais confondre :**

| espace | axe haut |
|---|---|
| fichier `.glb` / `.gltf` (spec glTF) | **+Y** |
| Blender après import (l'importeur convertit) | **+Z** |
| Godot 4.6 (runtime consommateur) | **+Y** |

Les tableaux ci-dessous sont en **espace Blender (Z)**. L'oracle lira le glTF **brut** et
mesurera donc **`min_y`**. `min_z = −1.0` ici ≡ `min_y = −1.0` dans le fichier.

### 2.1 — Mesure du corpus par le parseur indépendant (glTF brut, axe Y)

| asset | `min_y` | `max_y` | nœuds mesh | sans matériau | skinnés |
|---|---|---|---|---|---|
| Barbarian | **−0.0000** | 2.3978 | 13 | 0 | 6 |
| Knight | **−0.0000** | 2.4666 | **15** | 0 | 6 |
| Mage | **−0.0000** | 3.0028 | 12 | 0 | 6 |
| Rogue | **−0.0000** | 2.1870 | 12 | 0 | 6 |
| Skeleton_Mage | **−0.0000** | 2.6302 | 9 | 0 | 8 |
| Skeleton_Minion | **−0.0000** | 2.1661 | 9 | 0 | 9 |
| Skeleton_Rogue | **−0.0000** | 2.3079 | 10 | 0 | 8 |
| Skeleton_Warrior | **−0.0000** | 2.5904 | 10 | 0 | 9 |
| `demo_generated.glb` | **−0.9993** | 0.9940 | 1 | **1** | 0 |

Les 8 KayKit sont ancrés **exactement** au plan zéro. Le généré est enterré de moitié.

### 2.2 — Falsification d'une mesure côté producteur (incident, conservé exprès)

Une première campagne de mesure **faite avec Blender** avait rapporté `min = −1.0000` de façon
identique sur les 8 fichiers, attribuée à une `Icosphere` orpheline de 42 sommets présente
dans chaque asset. Cette conclusion était **fausse**, et l'erreur est instructive :

- le fichier `Skeleton_Warrior.glb` déclare **10 meshes**, tous des parties du corps ;
- `extensionsUsed` / `extensionsRequired` : `None` ; aucun nœud hors graphe de scène ;
- l'`Icosphere` est créée par **l'importeur glTF de Blender**, dans une collection nommée
  `glTF_not_exported` — vérifié par delta d'objets avant/après import sur une scène vide ;
- la sonde de mesure itérait `bpy.data.objects` **sans filtrer cette collection**.

Autrement dit : l'outil de production a fabriqué la géométrie qu'il prétendait mesurer.
Le parseur indépendant, lisant les octets du `.glb`, ne l'a jamais vue.

**C'est la justification empirique de la règle d'autorité du §3** : le producteur ne peut pas
être son propre juge, non par principe moral mais parce qu'il mesure son propre environnement
en croyant mesurer l'asset. L'incident est conservé dans ce document plutôt que corrigé en
silence — il documente pourquoi l'architecture est en couches.

### 2.3 — Le défaut réel de géométrie non réclamée : `Knight.glb`

15 nœuds mesh, dont **8 parties du corps** et **7 variantes d'arme/bouclier** —
`1H_Sword`, `1H_Sword_Offhand`, `2H_Sword`, `Badge_Shield`, `Rectangle_Shield`,
`Round_Shield`, `Spike_Shield` — toutes présentes dans le graphe de scène, toutes
instanciables. Pack modulaire dont le consommateur est censé masquer les variantes non
portées ; `games/chess_tcg/ui/game3d.gd:146` charge le `.glb` entier sans rien masquer.

C'est **le** cas qui justifie `all_meshes_declared` : ces meshes existent bel et bien dans le
fichier, et rien ne dit lesquels sont réclamés.

### 2.4 — L'asset généré : enterré par construction

| fichier | `min_y` | hauteur | sommets | matériaux |
|---|---|---|---|---|
| `demo_generated.glb` (Hunyuan3D-2.1) | **−0.9993** | 1,993 | 366 962 | **0** |

Normalisé dans un cube unité centré sur l'origine → **la moitié de l'objet est sous le sol**.
Ce n'est pas un accident : c'est l'état par défaut de toute sortie Hunyuan3D.

Le seul contrôle existant aujourd'hui (`~/3d-pipeline/test_blender_import_generated.py`)
n'affirme que `vertices > 0` et `polygons > 0`, puis réexporte sous le nom
`demo_generated_validated.glb`. **Le mot « validated » dans ce nom de fichier ne recouvre
aucune validation géométrique.**

### 2.5 — Variance (règle ratifiée 2026-07-21)

`min_y` mesuré par le parseur indépendant ∈ **[−0,9993 … −0,0000]** sur le corpus réel. Deux
valeurs distinctes non triviales, obtenues avant d'écrire une ligne d'oracle. La métrique
porte bien de l'information.

Second axe de variance, sur le recensement : de **1** nœud mesh (`demo_generated`) à **15**
(`Knight`), et la part de nœuds sans matériau va de 0/15 à 1/1.

---

## 3. Architecture en couches

```
COUCHE PRODUCTEUR (WSL)      COUCHE PREUVE (Windows)        COUCHE RUNTIME (Windows)
Blender 5.1.1 + Hunyuan3D  → parseur glTF indépendant   →   Godot 4.6 headless
crée · exporte · déclare     mesure · classe · juge          confirme l'intégration
      DECLARATION                    PROOF                        PROOF
```

**Règle d'autorité (ratifiée Pierre) :** une information venant de Blender
(`asset_metadata.json`) est classée `DECLARATION`, jamais `PROOF`. L'oracle **re-mesure de
façon indépendante** et ne lit jamais la déclaration comme mesure.

La déclaration n'est pas inutile pour autant : l'écart déclaration↔mesure devient lui-même un
check (`declaration_mismatch`). C'est `declared_vs_executed` appliqué à la géométrie — la
déclaration gagne un usage sans gagner d'autorité.

**Découplage important :** la couche preuve ne dépend **pas** de WSL. Seul le producteur en
dépend. L'oracle mesure des `.glb` déjà sur disque, depuis Windows, sans Blender.

**Absence d'environnement producteur** → `BLOCKED`, `reason: BLENDER_EXECUTOR_UNAVAILABLE`.
Jamais `OK`, jamais un skip silencieux.

---

## 4. Exécuteur de mesure et sa limite

`pygltflib` dans `.venv312` (Windows) — indépendant de Blender, comme exigé.

Lit : hiérarchie de nœuds · `min`/`max` de l'accesseur `POSITION` (**obligatoires par la spec
glTF**, donc toujours présents) · transformes locales composées → bbox monde **par nœud**.

**Limite déclarée, pas cachée :** c'est de la géométrie *bind-pose*, pas *skin-évaluée*.
Mesurée sur ce corpus : `min_z` identique à 4 décimales sur les 8 fichiers ; `max_z` divergeant
de ≤ 0,30 (≤ 9 %). **Pour le contact au sol — la mesure critique — la bind-pose est exacte.**
Le rapport de l'oracle porte ce champ :
`measurement_space: "gltf_bind_pose"`, `skin_evaluated: false`.

Si un jour un asset skinné rend cette approximation fausse, la couche 3 (Godot) tranche.

---

## 5. Recensement et classification

Pour chaque nœud mesh : `name` · `vertices` · `pct_of_total` · bbox monde · `min_y`/`max_y` ·
`has_material` · `is_skinned` · `parent`.

Classification **mécanique** (jamais esthétique) :

| classe | critère |
|---|---|
| `MAIN` | porteur d'un matériau **et** (skinné **ou** parenté à un rig **ou** `pct_of_total ≥ main_share_threshold`) |
| `SECONDARY` | présent dans le manifeste de l'asset avec un `role` déclaré |
| `UNKNOWN` | tout le reste → **force l'explication** |

`role` — énumération fermée : `collider` · `socket` · `variant` · `lod` · `fx` · `decor`.

La troisième branche de `MAIN` existe pour les assets **statiques** — les 100 props futurs
n'ont ni rig ni skinning. Sans elle, tout prop généré serait `UNKNOWN` à vie et l'oracle
serait inopérant sur son cas d'usage principal.

**Sur quelle géométrie portent les checks d'ancrage** — règle explicite, car elle décide de
tout : `ground_contact` / `no_buried_geometry` / `pivot_at_base` / `scale_within_band` sont
calculés sur `MAIN ∪ SECONDARY(role ≠ collider)`. Les colliders sont exclus **de la mesure
d'ancrage** parce qu'ils débordent légitimement le visuel — mais ils restent recensés et
rapportés.

**Cas dégradé, jamais silencieux** : si **aucun** `MAIN` n'est identifié (ex.
`demo_generated.glb`, 0 matériau), les checks retombent sur l'union de **tous** les meshes et
le rapport porte `main_geometry_undetermined: true`. Conséquence voulue : `demo_generated.glb`
est tout de même mesuré et rend `FAIL no_buried_geometry` (`min_y = −0.9993`) au lieu de
s'échapper par une classification vide.

**L'oracle ne nettoie jamais, ne supprime jamais, n'exclut jamais en silence.** Une règle
d'exclusion silencieuse serait un trou où un vrai défaut pourrait se cacher.

---

## 6. Où vit le contrat (ratifié Pierre : côté asset, permanent)

Le recensement est une propriété de l'**asset** (offre), pas de la **demande** d'un run —
séparation déjà ratifiée dans `ASSET_CONTRACT_V0.md`. Il vit donc en **sidecar** :

```
games/chess_tcg/assets/characters/adventurers/Knight.glb
games/chess_tcg/assets/characters/adventurers/Knight.glb.geometry.json   ← nouveau
```

```json
{
  "schema_version": "1.0",
  "asset_file": "Knight.glb",
  "sha256": "<hash du .glb — le manifeste devient caduc si l'asset change>",
  "up_axis": "Y",
  "ground_plane": 0.0,
  "origin_rule": "base_center",
  "meshes": [
    { "name": "Knight_Body",  "role": "main" },
    { "name": "Knight_Helmet","role": "main" },
    { "name": "1H_Sword",     "role": "variant" },
    { "name": "Icosphere",    "role": null, "note": "non expliquée — bloque" }
  ]
}
```

`sha256` lie le manifeste à l'octet près : un `.glb` modifié invalide son manifeste
(`manifest_stale`) plutôt que de laisser une déclaration périmée faire autorité.

**Extension de `ASSET_CONTRACT_V0` → v0.2**, additive comme l'a été v0.1 (rien de supprimé,
les runs existants continuent de passer). Bloc `geometry` **optionnel** sur `asset_request`,
portant la *politique* du run (tolérances, bande d'échelle attendue) — jamais le recensement.

**Autorité des seuils — une seule chaîne, sans ambiguïté :**

```
rules.yaml (défauts du studio)  ←  asset_request.geometry (override du run, si présent)
```

`rules.yaml` porte toujours une valeur pour chaque seuil : il n'existe aucun seuil implicite.
Un run peut le surcharger explicitement ; le rapport de l'oracle cite **la valeur effective et
sa provenance** (`threshold_source: "rules.yaml" | "asset_request"`) pour chaque check. Le
manifeste de l'asset, lui, ne porte **jamais** de tolérance — il déclare ce qui existe, pas ce
qui est acceptable.

---

## 7. Checks

| check | attrape | preuve dans le corpus |
|---|---|---|
| `ground_contact` | flottement (`min_y > tolérance`) | fixture synthétique |
| `no_buried_geometry` | enterrement | `demo_generated.glb` : `min_y = −0.9993` |
| `pivot_at_base` | origine au centre au lieu de la base | fixture synthétique |
| `scale_within_band` | échelle aberrante | fixture ×100 |
| `all_meshes_declared` | géométrie inexpliquée | 7 variantes d'arme du `Knight.glb` |
| `declaration_mismatch` | Blender a menti sur sa propre sortie | à construire |
| `manifest_stale` | `sha256` du manifeste ≠ `.glb` réel | à construire |

**Hors périmètre V1, avec raison nommée :** `collision_alignment`. Aucun de ces `.glb` ne
contient de collision, et aucune scène n'en déclare une. Un check sans source de vérité serait
un check décoratif — exactement ce que ce studio appelle une preuve sans exécuteur.

---

## 8. Verdicts (vocabulaire ratifié OK/FAIL/BLOCKED — pas de 4e valeur)

| verdict | sens |
|---|---|
| `OK` | tous les checks déclarés passent |
| `FAIL` | défaut géométrique mesuré (enterré, flottant, pivot faux, échelle aberrante) ou fichier illisible |
| `BLOCKED` | bien formé, mais aucune décision automatique possible → HumanGate |

`REVIEW_REQUIRED` **n'est pas introduit** : `BLOCKED` porte déjà ce sens dans le studio, et la
nuance vit dans `reason` (`secondary_geometry_without_contract`, `manifest_absent`,
`BLENDER_EXECUTOR_UNAVAILABLE`). Zéro nouveau vocabulaire à apprendre pour les consommateurs
de verdict.

---

## 9. Corpus de falsification

| entrée | attendu | rôle |
|---|---|---|
| 8× KayKit | `OK` sur l'ancrage · `BLOCKED` sur `all_meshes_declared` tant qu'aucun manifeste n'existe | **garde-fou** : l'oracle ne doit pas recaler la référence |
| `demo_generated.glb` | `FAIL no_buried_geometry` | vrai positif **réel**, pas synthétique |
| cube posé (`min_y = 0`) | `OK` | négatif de contrôle |
| cube flottant `+0.10` | `FAIL ground_contact` | |
| cube enterré `−0.10` | `FAIL no_buried_geometry` | |
| cube pivot au centre | `FAIL pivot_at_base` | |
| cube ×100 | `FAIL scale_within_band` | |

Les 5 fixtures sont générées par script Blender, minuscules, et **commitées** — reproductibles
sans WSL. Chaque check possède ainsi au moins un négatif prouvé : `FAIL détecté ≠ opinion`.

---

## 10. Fichiers

```
scripts/forge/asset_geometry/
  measure.py            # parseur glTF indépendant → measurement JSON (aucun jugement)
  oracle.py             # applique rules.yaml au measurement → verdict (aucune mesure)
  rules.yaml            # tolérances, bandes d'échelle, seuils de classification
  report_schema.json
  godot_probe/probe.gd  # couche 3 : import + recensement de nodes + AABB runtime
  tests/
    test_measure.py
    test_oracle.py
    fixtures/*.glb + build_fixtures.py

docs/forge/ASSET_GEOMETRY_PIPELINE_BOUNDARY_V1.md   # la frontière (livrable demandé)
docs/forge/ASSET_CONTRACT_V0.md                      # → v0.2, additif
```

Séparation stricte **mesure / jugement** : `measure.py` ne juge jamais, `oracle.py` ne mesure
jamais. C'est ce qui rend l'oracle testable sur des measurements figés, sans aucun `.glb`.

---

## 11. Couche 3 — sonde Godot (V1, périmètre minimal)

`probe.gd` en `--headless` : import réussi ? · recensement des nodes réellement instanciés ·
AABB runtime. Rien d'autre.

Elle répond à la seule question que l'intake **ne peut pas** trancher : *l'Icosphere s'affiche-
t-elle réellement dans `chess_tcg` ?* Aujourd'hui la réponse est « mécaniquement attendue, non
prouvée » — la sonde la transforme en fait.

Rappel de contrainte connue (mémoire `godot_capture_requires_gpu_window`) : `--headless` ne
rend **aucune** image. Cette sonde ne capture rien — elle lit une scène en mémoire, ce qui
fonctionne bien sans GPU.

---

## 12. Décisions ratifiées Pierre (2026-08-06)

1. **Cible V1** = intake `.glb`, corpus mixte référence + généré.
2. **Modèle de preuve** : Blender = `DECLARATION` ; preuve = parseur indépendant + Godot.
3. **Verdicts** : `REVIEW_REQUIRED` → mappé sur `BLOCKED` + `reason`.
4. **Manifeste** : côté asset, permanent (sidecar `.geometry.json`).
5. **Couche Godot** : dans V1, périmètre minimal.

---

## 12 bis. Amendements du 2026-08-06 (Asset Library V1)

Trois règles ajoutées **après** la rédaction initiale, chacune née d'un défaut mesuré —
l'historique ci-dessus n'est pas réécrit, ces amendements s'y ajoutent.

### A. Asymétrie de la déclaration

> **Une déclaration du producteur peut seulement rendre l'oracle PLUS strict, jamais plus
> permissif.**

Constaté sur `gen_chest_01` : la branche « part de sommets ≥ 10 % » du §5 — ajoutée pour
que les props statiques ne soient pas `UNKNOWN` à vie — classait automatiquement `MAIN` les
deux états exclusifs d'un couvercle, à 33 % des sommets chacun. La question de la variante
disparaissait en silence. Les armes du `Knight` n'étaient attrapées que parce qu'elles
pesaient chacune moins de 10 %.

Correction : un mesh listé dans `metadata.json → variants` **perd le droit** au classement
`MAIN` automatique et doit être déclaré au manifeste. La déclaration du producteur devient
donc utilisable **sans** devenir une autorité : elle ne peut qu'ajouter de la contrainte.

Faiblesse résiduelle déclarée : la règle repose sur la franchise du producteur. Un
producteur qui n'annonce pas ses variantes retombe sur le seuil de part de sommets.

### B. `origin_rule` est une énumération fermée

Écrire une valeur plausible mais inconnue (`"feet_on_ground"`) **désactivait silencieusement**
`pivot_at_base` — un trou d'échappement. Une valeur hors
`pivot.allowed_origin_rules` produit désormais `BLOCKED`, jamais un check muet.

### C. Toute géométrie `UNKNOWN` porte une raison obligatoire

`census[].unknown_reason` est renseigné pour chaque nœud non expliqué. Un blocage muet est
un blocage inexploitable : l'opérateur doit savoir quoi corriger.

### E. Une variante déclarée doit exister géométriquement

`variants_match_geometry` : chaque nom listé dans `metadata.json → variants` doit
correspondre à un nœud mesh réel du fichier. Sinon → `FAIL`.

Né d'une sortie réelle du worker Qwen (2026-08-06) : il a déclaré
`variants: ["intact", "broken"]` pour un tonneau dont l'archétype ne produit **qu'un
seul mesh**. L'oracle rendait `OK`. Une déclaration de variante purement verbale
passait — et pire, la contrainte de lot fondée sur ces déclarations (`ASSET_LEARNING_LOOP`)
devenait décorative.

Le sens de l'asymétrie (§A) est préservé : déclarer des variantes ne peut toujours que
**durcir**. Ici, déclarer crée une **obligation de correspondance**. Un asset qui ne
déclare rien n'est pas concerné par ce check.

Limite : le check vérifie l'**existence** d'un mesh par variante, pas que ces meshes
soient réellement des états *mutuellement exclusifs*. Cette seconde question reste
humaine (manifeste).

### D. Le sidecar du producteur est réellement lu

`load_declaration()` charge `<asset>.glb.metadata.json`. Avant cet amendement,
`declaration_mismatch` existait et était testé, mais **rien ne chargeait le fichier** —
un validateur sans producteur.

## 12 ter. État au gel V1 (2026-08-06)

**Preuves disponibles sur le périmètre testé** — jamais « prêt production ».

| | |
|---|---|
| assets produits | 9 (7 en bibliothèque, 1 archivé en cas d'échec, 1 hors dépôt) |
| nature | primitives paramétrées — la chaîne est prouvée, **pas** la qualité artistique |
| checks | 8, dont 3 nés de défauts réels rencontrés en cours de chantier |
| assets ingérés au catalogue | **0** — 8 propositions attendent une signature humaine |

Les trois défauts fermés viennent tous d'**exécutions réelles**, aucun d'une relecture :
`variants` avalées par le seuil de part de sommets · `origin_rule` désactivant le check
de pivot en silence · variantes déclarées sans géométrie correspondante.

Limite non fermée, classée **V1.1** : aucun vocabulaire partagé pour nommer les variantes
entre l'auteur de spec et le producteur (`variant_contract`, cf.
`ASSET_LEARNING_LOOP_V1_SPEC.md`).

## 13. Limites connues

- Mesure **bind-pose**, pas skin-évaluée (§4) — exacte pour le contact au sol sur ce corpus,
  non garantie pour un asset skinné exotique.
- `all_meshes_declared` détecte la géométrie **non déclarée**, jamais la géométrie **mal
  déclarée** : écrire `role: collider` sur une sphère décorative passe. Le manifeste engage
  un humain, il ne le vérifie pas.
- Aucun jugement esthétique, par construction (héritage `ASSET_CONTRACT_V0`).
- L'oracle valide un `.glb` **isolé**. Il ne dit rien de la cohérence d'échelle *entre* assets
  d'un même jeu — question réelle, hors V1.
- `pivot_at_base` suppose la convention `base_center`. Un asset volant ou suspendu (lanterne,
  plateforme) la viole légitimement : le manifeste devra pouvoir déclarer `origin_rule`
  autrement, sinon l'oracle produira des faux positifs sur cette famille.

---

## 14. Constats annexes — hors périmètre, à trancher séparément

Trouvés pendant l'audit, **non traités par ce chantier** :

1. `Knight.glb` : 7 variantes d'arme/bouclier présentes dans le graphe de scène, aucun
   masquage dans `game3d.gd`. Les autres personnages du corpus ont un nombre de nœuds
   compatible avec leurs seules parties de corps.
2. `games/chess_tcg/ui/game3d.gd` compense l'ancrage à la main (`ground.position.y = −0.36`,
   `base −0.28`, tuiles `−0.07`) alors que les assets sont ancrés exactement à zéro (§2.1).
   La compensation ne corrige donc pas un défaut d'asset — dette antérieure à ce chantier.

Ces deux points appartiennent au jeu `chess_tcg`, pas à la Forge. HumanGate décide s'ils
deviennent un chantier.

**Retiré de cette liste après falsification** : « l'Icosphere est rendue par Godot ». Cette
géométrie n'existe pas dans les assets (§2.2) — il n'y a rien à rendre.

---

## 15. Lignée causale

### Activation

```yaml
reason:
  problem: >
    La géométrie des assets 3D n'est pas ancrée physiquement, et aucune géométrie n'est
    tenue de s'expliquer. Mesuré : sortie générée enterrée à 50 % (min_y = −0.9993) ;
    8 assets de référence porteurs d'une géométrie orpheline non déclarée.
  root_cause: >
    Absence de contrat géométrique. Le seul contrôle existant vérifie vertices > 0 et
    réexporte sous le nom « validated ».
  oracle: asset_geometry_oracle
  action_reason: >
    Empêcher qu'un asset invalide entre dans la KB future, et rendre mécanique un défaut
    aujourd'hui détectable seulement à l'œil.
  expected_proof: >
    demo_generated.glb → FAIL no_buried_geometry ; 8 KayKit → OK sur l'ancrage ;
    5 fixtures → 1 OK / 4 FAIL.
```

### Return (gabarit obligatoire de fin de chantier)

```yaml
why_task_existed:
problem:
oracle:
root_cause:
action_reason:
result:
proof:
tests:
learning:
next_reason:
```

---

## 16. Ce que ce chantier ne fait pas

Création des 100 assets · direction artistique · génération Blender massive · remplacement des
assets existants · nettoyage automatique de la géométrie · installation de Blender (déjà
présent, §2) · jugement esthétique.
