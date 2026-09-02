---
name: asset-generator
description: "Transforme une demande gameplay en asset 3D exploitable : spec -> Blender -> GLB + declaration -> Asset Geometry Oracle -> KB. Le producteur ne juge jamais sa production. Utiliser quand un jeu a besoin d'un prop/decor 3D reutilisable."
argument-hint: "\"<demande gameplay>\" [--dest knowledge_base/assets/props3d] [--no-ingest]"
user-invocable: true
allowed-tools: Read, Write, Bash, PowerShell, Glob, Grep
model: sonnet
---

# Asset Generator — de la demande gameplay a l'asset prouve

Chaine **non negociable** (cf. `docs/forge/ASSET_GEOMETRY_PIPELINE_BOUNDARY_V1.md`) :

```
demande gameplay
   -> spec.json           (toi : traduction, aucune geometrie)
   -> build_asset.py      (Blender WSL : PRODUIT)
   -> .glb + .metadata.json + .generation_report.json
   -> oracle.py           (Windows : MESURE et JUGE, independamment)
   -> HumanGate           (si BLOCKED : manifeste de recensement)
   -> catalog.json        (ingestion conditionnee au verdict)
```

**Regle qui prime sur tout le reste** : le producteur ne juge jamais sa production.
Tu n'ecris JAMAIS `<asset>.glb.geometry.json` — ce manifeste est la parole du HumanGate.
Si tu l'ecrivais, l'asset declarerait sa propre geometrie legitime et l'oracle serait
contourne.

## Etape 1 — traduire la demande en spec

Ecris un `spec.json` dans le scratchpad. Champs obligatoires (absent = refus du builder) :

```json
{
  "asset_id": "gen_crate_wood_01",
  "archetype": "crate",
  "category": "prop",
  "style": "lowpoly",
  "size": { "w": 0.8, "d": 0.8, "h": 0.8 },
  "color": [0.55, 0.40, 0.25, 1.0],
  "variants": [],
  "consumer": ["obstacle destructible", "decor de niveau"]
}
```

- `archetype` — enumeration FERMEE : `crate` `door` `platform` `barrel` `pillar` `button`
  `chest`. Un archetype inconnu est une erreur, jamais un cube par defaut.
- `category` — enumeration fermee de `knowledge_base/kb-validate.mjs` (`ASSET_CATEGORIES`).
- `size` — en **metres**. Un humain fait ~1,8 ; une caisse ~0,8 ; un pilier ~3.
- `consumer` — **non vide, obligatoire**. Un asset sans consommateur n'entre pas dans la
  bibliotheque. Si la demande ne dit pas a quoi il sert, demande-le : ne l'invente pas.
- `variants` — etats mutuellement exclusifs livres dans le meme fichier (ex. couvercle
  ouvert/ferme). Les declarer rend l'oracle **plus strict**, jamais plus permissif :
  ces meshes ne pourront pas etre classes MAIN automatiquement.

## Etape 2 — produire (Blender, WSL)

```bash
wsl.exe -d $WSL_DISTRO -- bash -lc "$BLENDER_BIN -b --python /mnt/c/TACTICAL_CHESS_STUDIO/scripts/forge/asset_producer/build_asset.py -- <spec.json> <dest_dir>"
```

Sortie : `<asset_id>.glb`, `<asset_id>.glb.metadata.json` (DECLARATION),
`<asset_id>.generation_report.json`.

Si WSL ou Blender est absent : **arrete-toi** et rapporte
`BLOCKED · BLENDER_EXECUTOR_UNAVAILABLE`. Ne produis jamais un asset « approximatif »
par un autre moyen.

### WSL / Git-Bash

Blender is executed from WSL.

PowerShell can invoke the documented command directly.

When invoking `wsl.exe` from Git-Bash/MSYS, MSYS path conversion can corrupt Linux paths
such as `/home/...` and can produce a false "Blender unavailable" diagnostic.

Use:

```
MSYS_NO_PATHCONV=1
```

When running from Git-Bash, use literal Linux paths and avoid relying on shell variables
for WSL paths when invoking the Blender executor.

Canonical Blender path:

```
$BLENDER_BIN
```

## Etape 3 — faire juger (jamais par toi)

```bash
.venv312/Scripts/python.exe -m scripts.forge.asset_geometry.oracle <asset.glb>
```

Exit 0 = `OK` · 1 = `BLOCKED` · 2 = `FAIL`.

- **`FAIL`** — defaut geometrique mesure. Corrige la **spec** et reproduis. Ne retouche
  jamais le `.glb` a la main, et ne desserre jamais `rules.yaml` pour faire passer un
  asset : le seuil protege tous les assets, pas seulement le tien.
- **`BLOCKED`** — geometrie presente non expliquee. Lis `unknown_reason` de chaque noeud
  du recensement. Si ce sont de vraies variantes, **remonte a Pierre** pour qu'il ecrive
  le manifeste. Tu ne l'ecris pas toi-meme.
- **`OK`** — passe a l'etape 4.

## Etape 4 — confirmer au runtime

```bash
<godot_bin> --headless --script scripts/forge/asset_geometry/godot_probe/probe.gd -- <asset.glb>
```

Verifie que `mesh_instances` correspond au recensement de l'oracle et que `aabb_min_y`
est coherent. Une divergence entre les deux exécuteurs signifie que l'un des deux ment :
rapporte-la, ne la lisse pas.

## Etape 5 — ingerer dans la KB

Ajoute une entree `entry_type: "asset"` dans `knowledge_base/catalog.json` avec
`geometry_status` = le verdict **reellement obtenu** a l'etape 3, `consumer` non vide,
`geometry_manifest` si l'asset porte des variantes, `source` commencant par
`ORIGINAL — aucune inspiration externe citee` et `provenance_url: null`.

Puis, obligatoirement :

```bash
node knowledge_base/kb-validate.mjs
```

`kb-validate` refuse toute entree 3D ingeree dont `geometry_status != "OK"` : recopier un
verdict flatteur ne sert a rien, la garde est mecanique.

## Interdits

- Ecrire `<asset>.glb.geometry.json` (c'est le HumanGate).
- Traiter `metadata.json` comme une preuve — c'est une declaration.
- Considerer qu'un `.glb` present est un asset valide.
- Ingerer un asset sans `consumer`.
- Modifier `rules.yaml` ou un test pour obtenir un vert.
- Produire les 100 assets d'un coup : par lots, chaque lot prouve avant le suivant.

## Rapport de fin

```
STATUS:            OK | BLOCKED | FAIL
ASSETS_PRODUITS:   <ids>
VERDICTS_ORACLE:   <id> -> <verdict> (<reason>)
RUNTIME_GODOT:     <id> -> mesh_instances, aabb_min_y
KB:                <entrees ajoutees> · kb-validate: PASS|FAIL
BLOQUES:           <id> -> <unknown_reason>, en attente de HumanGate
```
