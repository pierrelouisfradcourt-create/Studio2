# Mesure — clé d'identité des sections (Lot 6, Task 1 step 1)

*2026-09-04 · lecture seule · V2 HEAD `464150e` · aucun code exécuté hors lecture de fichiers.
Répond à la question laissée UNKNOWN par la spec §3.2. NO_CLAIM_ALLOWED.*

## Question

Quelle est la clé d'identité canonique de `wiremap.design` ? La spec interdit de la deviner : soit une
clé constatée, soit `UNKNOWN` motivé.

## Ce que le dépôt montre

**Les trois wiremaps réelles sont en schéma v1.**

| run | `schema_version` | forme | clés d'un item |
|---|---|---|---|
| `runm_breakout` | absent | `features[]` (9) | `couvre, feature, fichiers, fonction, preuve, statut, version` |
| `v2_breakout_slice_r1` | absent | `features[]` (9) | `couvre, feature, fichiers, fonction, preuve` |
| `lot3_director_probe` | absent | `features[]` (9) | `couvre, feature, fichiers, fonction, preuve` |

**Le contrat `s5-wiremap` autorise explicitement les deux formes** (`output_contract`) : `features[…]`
ou le schéma v2 `{systems[], lines[]}` ; dans les deux cas chaque ligne porte `couvre` non vide.

**L'oracle de jointure ne joint jamais l'identité de la ligne.** `check_wiremap_contract.mjs:90-101`
extrait les lignes des deux schémas, puis lit `obj.couvre` (l.149-161) pour la confronter aux ids de
la feature_map. La jointure va donc de `wiremap.*.couvre[]` **vers** `feature_map.…capacites[].id`.
L'identité propre de la ligne n'y intervient pas.

**Mais elle est citée ailleurs, et par un arrêt dur.** `static_oracles.frozen_features_from_wiremap`
(l.904-921) construit `wiremap_frozen.json` à partir de :

- `lines[].id` si `schema_version == 2` ;
- `features[].feature` sinon (branche par défaut, « 17 wiremaps historiques »).

`check_feature_set_frozen` (l.937) compare ensuite le jeu courant à ce gel, et `driver._run_wiremap_oracle`
(l.4331) rend **BLOCKED non escaladable** si le jeu de règles a bougé. Renommer une ligne entre deux
convocations casse donc le gel, pas la jointure.

## Conclusion

L'identité de `wiremap.design` **est mesurée** : c'est l'identité de règle, avec deux formes selon le
schéma, déjà résolues par UNE fonction de production (`frozen_features_from_wiremap`). La déclarer en
dur au registre créerait une seconde vérité qui divergerait le jour où un troisième schéma apparaîtrait
— exactement le défaut que le studio a déjà payé.

Le registre déclare donc un **résolveur nommé**, `@frozen_features_from_wiremap`, au lieu d'un chemin.
Une section garde bien UNE clé canonique (principe de Pierre) : ici, cette clé est *la règle de
production elle-même*, pas deux chemins concurrents.

| section | clé | référencée par |
|---|---|---|
| `feature_map` | `systemes[].features[].capacites[].id` | `wiremap.design` et `wiremap.built` via `features[].couvre[]` |
| `architecture_contract` | `modules[]` | intra-section, `deps_interdites[][]` |
| `wiremap.design` | `@frozen_features_from_wiremap` (v2 `lines[].id`, sinon `features[].feature`) | le gel des règles, `wiremap_frozen.json` → `check_feature_set_frozen` (STOP dur en s10c) |

**Constat annexe, hors périmètre** : `check_feature_set_frozen` traite un doublon d'identité comme une
ancre malformée (`passed: False`). Une re-convocation qui dédoublonnerait des lignes changerait donc un
BLOCKED en PASS sans qu'aucune règle d'identité ne soit en cause. Non traité ici, consigné.

```
software_verdict: OK · evidence_verdict: MECHANICAL_VALIDATION_ONLY · claim_verdict: NO_CLAIM_ALLOWED
```
