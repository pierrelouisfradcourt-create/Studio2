# Asset Contract V0 — schéma de demande d'asset

> **Date** : 2026-07-13 (v0) · **mises à jour 2026-07-14 (v0.1)** · **2026-08-06 (v0.2)**
> **Statut** : DESIGN + IMPLEMENTED (résolveur `scripts/forge/asset_request.mjs` +
> oracle `scripts/forge/check_artbible.mjs`, testés).
> **Périmètre** : Tier 3 #7. v0 = étape 1 (schéma + résolveur). v0.1 = durcissement
> post-gate-4 (couverture besoin<->requête). v0.2 = politique géométrique (cf. §"Changelog
> v0.2" ci-dessous).
> `claim_verdict: NO_CLAIM_ALLOWED` — ce document décrit un mécanisme et ses limites, il ne
> certifie pas qu'il couvre tous les besoins d'asset futurs du studio.

## Changelog v0.2 (2026-08-06) — politique géométrique

**Pourquoi** : le contrat v0/v0.1 vérifie la licence, le style (tag), le format/runtime et la
couverture besoin↔requête. Il est **entièrement aveugle à la géométrie** : une requête peut
résoudre `OK` sur un asset enterré de moitié sous le sol. Mesuré sur le corpus réel — la
sortie générative brute du pipeline `~/3d-pipeline` a `min_y = −0.9993` (normalisée dans un
cube unité centré sur l'origine, donc à moitié sous le plan zéro), et rien dans le contrat ne
pouvait le voir. Détail complet : `docs/forge/ASSET_GEOMETRY_ORACLE_V1_DESIGN.md`.

**Ajout additif** (v0 et v0.1 restent valides, rien n'est supprimé, les runs existants
continuent de passer) — bloc `geometry` **optionnel** sur `asset_request` :

```yaml
asset_request:
  geometry:                        # bloc OPTIONNEL (absent = politique par défaut du studio)
    origin_rule:                   # base_center | centroid | declared — convention de pivot
    ground_rule:                   # {plane: 0.0, float_tolerance: 0.01, buried_tolerance: 0.01}
    allowed_negative_y: false      # la géométrie peut-elle descendre sous le plan ?
    secondary_mesh_policy:         # declaration_required | allow_undeclared
    declaration_required: true     # une géométrie UNKNOWN bloque-t-elle le run ?
  # ... + les champs v0 et v0.1 inchangés
```

**Séparation d'autorité — le point important.** Ce bloc porte la **politique du run**
(qu'est-ce qui est acceptable ici), **jamais le recensement** (quelle géométrie existe dans
l'asset). Le recensement est une propriété de l'**offre**, pas de la **demande** — même
séparation que celle déjà ratifiée §"Ancrage architectural". Il vit donc en sidecar permanent
à côté de l'asset :

```
Knight.glb
Knight.glb.geometry.json     ← recensement : {sha256, up_axis, origin_rule, meshes:[{name, role}]}
```

Le `sha256` lie le manifeste à l'octet près : un `.glb` modifié invalide son manifeste
(`manifest_stale`) plutôt que de laisser une déclaration périmée faire autorité.

**Chaîne des seuils, sans ambiguïté** :
`scripts/forge/asset_geometry/rules.yaml` (défaut du studio) ← `asset_request.geometry`
(override explicite du run). Aucun seuil n'est implicite ; chaque check du rapport cite sa
`threshold_source`. Le manifeste de l'asset ne porte **jamais** de tolérance : il déclare ce
qui existe, pas ce qui est acceptable.

**Axe vertical** : glTF est **Y-up** par spécification, comme Godot. Blender affiche du Z-up
parce que son importeur convertit. Toute règle géométrique de ce contrat est exprimée en **Y**.

**Consommateur** : `scripts/forge/asset_geometry/oracle.py` (checks `ground_contact`,
`no_buried_geometry`, `pivot_at_base`, `scale_within_band`, `all_meshes_declared`,
`declaration_mismatch`, `manifest_stale`, `producer_environment`). Tests :
`scripts/forge/tests/test_asset_geometry.py`.

**Non couvert par v0.2, avec raison nommée** : `collision_alignment`. Aucun asset du corpus ne
contient de collision et aucune scène n'en déclare une — un check sans source de vérité serait
un check décoratif.

### Amendements du 2026-08-06 (même version v0.2)

**L'asymétrie de la déclaration.** Le sidecar `<asset>.glb.metadata.json` est écrit par le
producteur et reste une `DECLARATION`. Elle est désormais *utilisée*, sous une règle stricte :

> une déclaration peut seulement rendre l'oracle **plus strict**, jamais plus permissif.

Concrètement, annoncer des `variants` **retire** à ces meshes le droit d'être classés `MAIN`
automatiquement — ils devront être déclarés au manifeste. Un producteur ne peut donc jamais
s'auto-absoudre par sa propre déclaration ; il ne peut que s'auto-contraindre.

**Le HumanGate écrit le recensement, jamais le producteur.** `<asset>.glb.geometry.json`
n'est produit ni par Blender ni par un agent : si le producteur l'écrivait, il déclarerait sa
propre géométrie légitime et l'oracle serait contourné. La règle est portée par le code
(`build_asset.py` inscrit `manifest_written: false` dans son rapport) et par le contrat de
runtime (`roles.yaml#runtime_contracts.asset_producer`, contrainte `no_manifest`).

**Une variante déclarée doit exister géométriquement.** Depuis le 2026-08-06, le check
`variants_match_geometry` exige que chaque nom de `variants` corresponde à un nœud mesh
réel. Déclarer des variantes reste un durcissement — mais on ne peut plus durcir « en
l'air » : une déclaration verbale sans géométrie correspondante est un `FAIL`. Trouvé sur
une sortie réelle du worker Qwen (variantes annoncées pour un asset à mesh unique).

**L'entrée au catalogue est propose-only.** Un asset validé n'est pas ingéré : il est
**proposé** (`scripts/forge/asset_producer/propose_asset.py` → `knowledge_base/proposals/`,
schéma `kb.proposal.v1`), puis promu par un geste humain explicite
(`kb_proposal.py --apply <id> --ratifie-par "<humain>"`). Le proposeur refuse tout asset dont
l'oracle ne rend pas `OK`. Détail : `ASSET_GEOMETRY_PIPELINE_BOUNDARY_V1.md` §5 bis.

## Changelog v0.1 (2026-07-14) — couverture besoin<->requête

**Pourquoi** : une sonde adversariale contrôlée (`docs/forge/S2_5_ARTBIBLE_DECEPTIVE_PROBE_NOTE.md`,
agent explicitement instruit à tromper l'oracle) a produit une art_bible affirmant en prose
« personnage/pièces/obstacles/décor couverts » avec seulement 2 `asset_request` génériques —
l'obstacle, pourtant central au gameplay, n'avait aucune requête. `check_artbible.mjs` v0
passait quand même (`pass:true`) car **rien ne rapprochait mécaniquement les besoins visuels
déclarés des requêtes produites**. v0.1 ferme ce vecteur, **additivement** (v0 reste valide,
rien n'est supprimé, cf. `scripts/forge/contracts/redteam-artdirector.yaml` "ne pas supprimer
les validations existantes").

**Nouveaux champs sur `asset_request`** (en plus des 6 champs v0 ci-dessous) :

```yaml
asset_request:
  id:            # identifiant court, non vide — traçabilité (Critique)
  entity_role:   # enum fermée : player | enemy | npc | boss | item | collectible |
                 # obstacle | environment | terrain | effect | ui | icon | other (Critique)
  purpose:       # enum fermée : gameplay | navigation | decoration | ui | feedback |
                 # animation (Critique — capturé en forme, PAS ENCORE consommé par un
                 # oracle : honnête, un champ validé n'est pas forcément un champ vérifié)
  # ... + les 6 champs v0 (type, style, references, constraints, acceptance_tests) inchangés
```

**Nouvelle section obligatoire dans `art_bible.md`** — `## 3. BESOINS VISUELS`, un bloc
` ```json ` contenant `{visual_requirements: [{id, entity_role, required, description}]}` :
chaque besoin visuel identifié à partir du product_snapshot, avec son `entity_role` et si sa
couverture est `required` (bool explicite, jamais implicite).

**Nouvelle vérification mécanique** (`checkCoverage`, `scripts/forge/check_artbible.mjs`) :
pour chaque `visual_requirements[i]` avec `required:true`, il doit exister **au moins une**
`asset_request` du même `entity_role`. Sinon → verdict **`BLOCKED`**, raison
`MISSING_ASSET_COVERAGE`. **La prose du RATIONALE n'est jamais lue** par cette vérification —
c'est précisément ce qui ferme le vecteur : affirmer une couverture en texte libre ne suffit
plus, seule la donnée structurée compte. `no_assets_needed: true` court-circuite entièrement
la vérification (cf. §"Cas à préserver").

**`check_artbible.mjs` gagne un vrai `verdict` (`OK`/`FAIL`/`BLOCKED`)**, plus rigoureux que le
`pass` booléen v0 (conservé, `pass = verdict === 'OK'`, pas de rupture pour les appelants
existants) : `FAIL` = artefact malformé (comme avant) ; `BLOCKED` = bien formé mais couverture
manquante (nouveau) ; `OK` = conforme et couvert. Ceci est **indépendant** des
`resolution_stats` (OK/BLOCKED de résolution contre le catalogue), qui restent advisory et
inchangés — un asset non résolu dans le catalogue n'est jamais une erreur de contrat ; seule
l'ABSENCE de toute requête pour un besoin `required:true` en est une.

**Cas préservés** (vérifiés par test, cf. `scripts/forge/check_artbible.test.mjs`) :
- `no_assets_needed: true` → couverture non vérifiée, `OK` (jeu sans asset externe).
- Un besoin `required: false` sans requête correspondante → pas un manque.
- Un asset absent du catalogue (`resolution_stats.blocked`) reste **advisory**, jamais
  transformé en erreur de contrat — distinct de `MISSING_ASSET_COVERAGE`.

**Preuve de correction** : `lab/forge_runs/artbible_adversarial/probe_deceptive_builder/
v0_1_retrofit_*` reconstruit la MÊME tentative de dissimulation (2 requêtes génériques,
rationale affirmant une couverture complète) au format v0.1 → `verdict: BLOCKED`,
`coverage.missing` cite explicitement `obstacle` (l'entité que l'agent avait réussi à
cacher). Les 6 runs réels antérieurs à v0.1 échouent désormais (`FAIL`, section/champs v0.1
absents) — **régression attendue et documentée**, pas un bug (ils n'ont jamais visé v0.1).

## Pourquoi ce document existe

Constat de Pierre (2026-07-13, avant cette session) : si on crée un rôle "Art Director" avant
d'avoir un contrat d'asset structuré, ce rôle n'est **qu'un prompt de plus** — sans ancrage
mécanique, à l'opposé de la doctrine `NO_CLAIM_ALLOWED` / oracle non-LLM du studio (cf.
`scripts/forge/contracts/SCHEMA.md`). Ce document pose la **porte d'entrée mécanique** que
l'étape 2 devra utiliser comme oracle, plutôt que de laisser un LLM juger "est-ce que c'est
beau" (jugement esthétique = jamais un oracle, cf. §"Ce que ce contrat ne fait jamais").

## Ancrage architectural (décision Pierre, 2026-07-13)

Un `asset_request` est de la **DEMANDE** (ce qu'un build a besoin, pour CE jeu, à CE moment) —
pas de l'**OFFRE** (`knowledge_base/catalog.json` indexe l'offre : assets réels, permanents,
avec `sha256`/`path` réels). Trois options ont été posées à Pierre ; il a choisi :

> **Artefact par-run, hors `catalog.json`.** `asset_request` vit comme un artefact de run Forge
> (au même titre que `blueprint.yaml`/la WireMap — cf. `scripts/forge/contracts/s9-build.yaml`),
> pas comme un `entry_type` de plus dans le catalogue. `kb-validate.mjs` (R1..R14) et
> `ASSET_SPEC`/ catalog schema restent **inchangés**. Le résolveur (`asset_request.mjs`) **lit**
> `catalog.json` (offre) et `search.mjs` (recherche) mais n'y **écrit jamais**.

Raison : mélanger offre (permanente, réutilisable entre jeux) et demande (éphémère, spécifique
à un build) aurait fait grossir `catalog.json` d'entrées non réutilisables et aurait cassé
l'invariant "catalogue = mémoire de production, pas un journal de requêtes".

## Le schéma (6 champs)

```yaml
asset_request:
  type:              # enum fermée : sprite | tileset | portrait | icon | vfx | audio | model3d
  style:              # tag court (ex. "flat-top-down", "lowpoly", "pixel-art") — comparé
                      # MOT-À-MOT au champ `style` du catalogue (égalité normalisée, jamais
                      # une évaluation "est-ce que ça ressemble" — cf. limites)
  references: []      # optionnel : liste d'asset_id du catalogue OU URLs — ADVISORY,
                      # jamais vérifié mécaniquement (cf. §"Ce que ce contrat ne fait jamais")
  constraints:
    format:            # "2D" | "3D"
    runtime:           # "html" | "godot"
    license_allowed: []  # sous-ensemble de ASSET_LICENSES (kb-validate.mjs) ; défaut si
                          # absent = ASSET_LICENSES entier (CC0-1.0, MIT, CC-BY-4.0, CC-BY-3.0)
    genre: []          # tags genre attendus (ex. ["tactical","rpg"]) — au moins un doit
                        # apparaître dans genre/genre_compatible de l'entrée résolue
    max_size_kb:       # optionnel, nombre ; "aucun" = pas de plafond (déclaré explicitement)
  acceptance_tests: [] # liste de checks mécaniques exécutés sur l'entrée RÉSOLUE — voir
                        # §"Les acceptance_tests disponibles" ; jamais du texte libre non
                        # exécutable (contrairement à `tests_oracles` prose des contrats
                        # d'AGENT — ceci est un contrat de DONNÉE, entièrement structuré)
```

### Règle des 3 états (héritée de `SCHEMA.md`)

Comme pour un contrat d'agent : un champ **absent** = oubli → requête rejetée
(`ASSET_REQUEST_INCOMPLETE`). Un champ **déclaré vide** (`null`, `[]`, ou `"aucun"` selon le
type) = décision assumée (« pas de contrainte de licence au-delà du défaut », « pas de
références »). `type`, `style`, `constraints.format`, `constraints.runtime` et
`acceptance_tests` sont **Critiques** (jamais vides) ; `references`, `constraints.genre`,
`constraints.license_allowed`, `constraints.max_size_kb` sont **Important** (`[]`/`null`
autorisé, jamais absent).

## Les `acceptance_tests` disponibles (mécaniques, non-LLM)

Chaque check est `{check: <nom fermé>, ...params}`. Liste fermée (v0) — un check hors liste
→ requête rejetée (`UNKNOWN_CHECK`), pas d'exécution silencieuse d'un check inconnu :

| check | Vérifie mécaniquement |
|---|---|
| `resolved` | Au moins une entrée du catalogue passe TOUS les filtres de `constraints` (format/runtime/genre/license/taille/style). Sinon → `BLOCKED`, pas `FAIL` (cf. §"BLOCKED vs FAIL"). |
| `license_in_allowlist` | `entry.license` ∈ `constraints.license_allowed` (ou `ASSET_LICENSES` par défaut). |
| `format_runtime_match` | `entry.format === constraints.format` ET `entry.runtime === constraints.runtime`. |
| `style_tag_match` | `entry.style` normalisé égal à `asset_request.style` normalisé (comparaison exacte post-normalisation — jamais un score de similarité flou). |
| `on_disk` | Si `entry.ingested === true` : le fichier existe réellement, `sha256` déclaré == réel (délègue à la même garde que `kb-validate.mjs`). Si `entry.ingested === false` (3D manifest-only) : ce check est automatiquement satisfait *à condition que* `constraints.format === "3D"` (cohérence manifest-only, pas un contournement). |
| `usage_referenced` | `entry.tier === "validated"` ET `entry.usage_examples` non vide (le studio a déjà PROUVÉ cet asset dans un jeu). Utile quand la demande exige un asset déjà éprouvé, pas juste candidat. |

## Ce que ce contrat ne fait **jamais**

- **Ne juge jamais si un asset est "beau" ou "dans le bon style" au sens esthétique.**
  `style_tag_match` compare des **tags de métadonnées** (chaînes), pas des pixels. Un asset
  peut passer `style_tag_match` et être esthétiquement décevant — c'est un **fog** explicite :
  la sortie du résolveur porte toujours `fog: "conformité esthétique non évaluée — jugement
  Pierre requis"` quand `resolved` réussit, pour rappeler que la résolution mécanique n'est
  **pas** un satisfecit visuel.
- **Ne vérifie jamais `references`** (asset_id cités ou URLs) — c'est de l'inspiration
  advisory, jamais un critère mesurable ("ressemble à X" n'est pas mécanique).
- **N'écrit jamais dans `catalog.json`** — lecture seule. Si aucun asset ne convient
  (`resolved` échoue), le résolveur ne fabrique rien : il retourne `BLOCKED` avec le détail
  des filtres non satisfaits → HumanGate décide (ingérer un nouvel asset, assouplir la
  requête, ou trancher que le style demandé n'existe pas encore dans le catalogue).

## BLOCKED vs FAIL (vocabulaire `OK`/`FAIL`/`BLOCKED` du studio)

- **`FAIL`** : la requête elle-même est malformée (champ Critique absent, check inconnu,
  `constraints.format`/`runtime` hors énumération). Erreur de forme, corrigible par l'auteur
  de la requête.
- **`BLOCKED`** : la requête est bien formée mais **aucune** entrée du catalogue ne satisfait
  `constraints` + `acceptance_tests`. Pas une erreur — un fait : le catalogue n'a pas
  (encore) ce qu'il faut. Remonte `fog` → HumanGate (sourcer un nouvel asset ou revoir la
  demande), jamais une auto-résolution "au plus proche".
- **`OK`** : au moins une entrée résout tous les checks. Le résolveur retourne l'entrée
  choisie (meilleur score `search.mjs`, puis tier `validated` avant `candidate`, puis id —
  même tri déterministe que `search.mjs`) + la liste des checks individuellement satisfaits.

## Implémentation

- `scripts/forge/asset_request.mjs` : `validateRequestShape()` (règle des 3 états + checks
  fermés + v0.1 id/entity_role/purpose), `ENTITY_ROLES`/`PURPOSES` (enums fermées, exportées,
  réutilisées par `check_artbible.mjs` — zéro duplication), `resolveRequest(request, catalog)`
  (filtre + réutilise `search.search()` pour le tri déterministe), `runAcceptanceTests(request,
  entry)` (exécute chaque check du tableau `acceptance_tests` un par un, retourne
  `{check, ok, detail}[]`). CLI : `node scripts/forge/asset_request.mjs <request.json>
  [--catalog <path>] [--json]`.
- `scripts/forge/check_artbible.mjs` (v0.1) : `extractVisualRequirements(sectionBody)` (parse
  le bloc ```json de BESOINS VISUELS — zéro dépendance YAML, ce studio n'utilise que
  `JSON.parse` pour les artefacts structurés), `validateVisualRequirement(vr, i)`,
  `checkCoverage(visualRequirements, requests, noAssetsNeeded)` (fonction pure, testée
  isolément). `checkArtBible()` retourne désormais `{pass, verdict, findings, coverage,
  resolution_stats}`.
- `scripts/forge/asset_request.test.mjs` : couvre requête valide résolue (asset Kenney
  existant), requête `BLOCKED` (contrainte insatisfiable), requête `FAIL` (champ Critique
  absent, check inconnu), distinction absent/`null` déclaré, v0.1 id/entity_role/purpose.
- `scripts/forge/check_artbible.test.mjs` : couvre les 4 scénarios de couverture (besoins
  tous couverts → OK ; couverture manquante → BLOCKED ; déclaration mensongère en prose sans
  requête correspondante → BLOCKED quand même ; `no_assets_needed` → OK sans vérification).

## Limites connues

- **v0** : `style_tag_match` est une égalité de chaîne normalisée — deux stylistes différents
  peuvent utiliser des tags différents pour un style visuellement proche (ex. "flat-top-down"
  vs "top-down-flat"). Pas de thésaurus : une requête qui ne matche aucun tag existant produit
  `BLOCKED`, pas un "plus proche possible" — c'est voulu (pas de résolution floue silencieuse).
- **v0** : `references` et le jugement esthétique final restent **hors du mécanique** par
  construction — c'est la limite structurelle documentée plus haut, pas un oubli.
- **v0** : pas de génération d'asset (aucun appel à un générateur d'image) — ce contrat
  **résout dans l'existant du catalogue** uniquement.
- **v0.1, NON corrigée (déjà connue, hors scope)** : `style_tag_match` compare des chaînes,
  jamais une sémantique de viewpoint — un style `flat-top-down` (vue de dessus) peut être
  déclaré pour un jeu à défilement latéral et résoudre `OK` sans que rien ne le détecte (cf.
  Défaut 1 de `S2_5_ARTBIBLE_DECEPTIVE_PROBE_NOTE.md`). Corriger ceci exigerait un champ
  `viewpoint` structuré sur le catalogue ET le schéma de requête — pas fait ici, car un
  jugement d'adéquation visuelle reste proche du jugement esthétique interdit. La couverture
  v0.1 ferme le vecteur de **complétude** (est-ce qu'un besoin a une requête), pas celui
  d'**adéquation** (est-ce que le style de la requête a un sens visuel réel) — deux questions
  distinctes, la seconde reste un fog HumanGate assumé.
- **v0.1** : `purpose` est validé en FORME (Critique, jamais absent) mais n'est consommé par
  AUCUN oracle aujourd'hui — capturé pour un rapprochement futur plus fin, pas un mensonge de
  conformité (un champ qui passe la validation de forme n'est pas forcément un champ dont la
  valeur est mécaniquement exploitée, cf. `PURPOSES` dans `asset_request.mjs`).
