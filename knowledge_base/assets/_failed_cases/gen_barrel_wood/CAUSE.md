# Cas d'echec — gen_barrel_wood

> Archive le 2026-08-06 · verdict oracle : **FAIL** (VARIANTS_MATCH_GEOMETRY)
> `claim_verdict: NO_CLAIM_ALLOWED`

## Pourquoi cet asset est conserve

Il n'entre pas dans la bibliotheque : il echoue a l'oracle. Il est conserve parce qu'il
est la **piece a conviction** d'une lecon — sans lui, la lecon
`asset.barrel_variants_match_geometry` ne serait qu'une affirmation.

## Ce qui a echoue

Checks en echec : variants_match_geometry

- **variants_match_geometry** : variante(s) declaree(s) sans mesh correspondant: ['intact', 'broken'] (meshes presents: ['gen_barrel_wood'])

## Cause racine

Le worker `asset_spec_author` (Qwen) a declare des variantes qui n'existent pas dans la
geometrie produite. Ce n'est pas une erreur de comprehension du modele : c'est
l'**absence de vocabulaire partage** entre l'auteur de spec et le producteur.

- Qwen nomme les variantes librement, dans la langue de la demande.
- `build_asset.py` nomme ses meshes en dur, selon l'archetype.
- Rien ne declare la correspondance entre les deux.

Consequence mesuree : une demande correctement comprise produit un asset qui echoue.

## Statut

Classe **V1 LIMITATION -> V1.1 CANDIDATE** (`variant_contract`). Non corrige dans V1.

## Fichiers

- `gen_barrel_wood.glb` (deplace depuis props3d/)
- `gen_barrel_wood.glb.metadata.json` (deplace depuis props3d/)
- `gen_barrel_wood.spec.json` (deplace depuis props3d/)
- `gen_barrel_wood.generation_report.json` (deplace depuis props3d/)
- `oracle_report.json` — rapport fige a l'archivage
- `lesson.json` — copie de la lecon derivee (source vivante : `lab/forge_evidence/asset_lessons/`)
