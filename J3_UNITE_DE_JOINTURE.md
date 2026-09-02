# J-3 — L'UNITÉ DE JOINTURE

*2026-09-02 · **MESURE UNIQUEMENT** · aucun code, aucun fichier du dépôt source modifié.
HEAD `feeb29cb`. Question unique : **qu'est-ce qu'une unité de jointure ?**
Ni `preuve`, ni `actual_proof`, ni J-4.*

---

## 0 · Réponse courte — l'unité est déjà définie, en un seul endroit

```js
// upstream_schema.mjs:471
collectLeaves(doc)  →  systemes[i].features[j].capacites[k]
```

**La feuille (`leaf`) est l'unité.** Un seul collecteur, partagé par les trois vérificateurs :
`check_decompo.mjs` (l.107, 166), `check_wiremap_contract.mjs` (l.133),
`check_amont_traversal.mjs` (l.139). **Il n'y a pas de définitions concurrentes de la capacité.**

Et `validateLeaf` (l.532) dit ce qu'une feuille doit porter :
```
id · capacite · source_ref · expected_proof
   « une feuille sans exigence d'origine est une invention non declaree »
```

Ce que compte `capacites_couvertes` est donc précis :
```js
// check_wiremap_contract.mjs:134
capaciteIds = collectLeaves(featuremap).filter(leaf.id NON VIDE).map(leaf.id)
```
> **Le dénominateur n'est pas « les feuilles », c'est « les feuilles PORTANT UN ID ».**
> `20 couvertes`, `62 couvertes`, `55 non couvertes` comptent donc des **feuilles adressables**,
> jamais des features, jamais des lignes.

---

## 1 · Les cinq mots, séparés — et ce qu'ils valent en nombre

| niveau | définition mécanique | total (12 runs) | portant un `id` |
|---|---|---|---|
| `systeme` | `featuremap.systemes[]` | 84 | **46** |
| `feature` | `systemes[].features[]` | 189 | **120** |
| **`leaf` = « capacité »** | `features[].capacites[]` | **271** | **240** |
| `ligne de wiremap` | `wiremap.features[]` ou `lines[]` | **360** | — (pas d'id) |
| `preuve` | champ texte d'**une ligne** | 1 par ligne | — |
| `expected_proof` | objet d'**une feuille** | 240 | — |

**Aucune de ces quantités n'est égale à une autre.** 271 feuilles, 360 lignes, 189 features :
toute phrase qui les mélange est fausse par construction.

### Le piège de nom, mesuré : `couvre[]` ne vise pas la même chose selon l'artefact
```
blueprint.couvre[]  →  featureIds(featuremap)     = ids de FEATURE   (check_blueprint_contract.mjs:157)
wiremap.couvre[]    →  collectLeaves(...).leaf.id = ids de FEUILLE   (check_wiremap_contract.mjs:134)
```
> **Même nom de champ, deux unités, un niveau d'écart.** C'est exactement l'équivalence implicite
> à ne pas laisser s'installer. Les deux vérificateurs, eux, ne se trompent pas — ils appellent
> deux fonctions différentes.

---

## 2 · La jointure n'est pas 1:1 — et ne doit pas l'être

Sur les deux seuls runs joints :

```
p1_beta_E1   20 feuilles · 22 lignes · 22 entrées `couvre`
             lignes couvrant 1 feuille : 22
             feuilles couvertes par 1 ligne : 18 · par 2 lignes : 2

pacman       62 feuilles · 67 lignes · 74 entrées `couvre`
             lignes couvrant 1 feuille : 62 · 2 feuilles : 4 · 4 feuilles : 1
             feuilles couvertes par 1 ligne : 51 · par 2 : 10 · par 3 : 1
```

**Relation many-to-many, et légitimement** : une capacité peut être réalisée par plusieurs modules,
un module peut porter plusieurs capacités. `capacites_couvertes` est donc un **compte de feuilles
distinctes**, jamais une somme d'entrées `couvre` — 74 entrées pour 62 feuilles chez pacman.

> Corollaire : **`lignes` n'est pas un dénominateur.** Comparer 55 lignes à 55 feuilles chez
> `tower_defense_sonde` est une coïncidence, pas une correspondance.

---

## 3 · Ce que la mesure corrige dans mon propre travail (J-2)

Mon régime `NOT_APPLICABLE` dit *« la featuremap n'identifie aucune capacité — rien à couvrir »*.
**Il fond deux faits différents :**

```
auto_battler_i1 / i2 / i2_5    0 feuille          → il n'y a réellement rien
card_engine                   31 feuilles, 0 id   → il y a 31 choses à couvrir,
                                                    AUCUNE n'est adressable
```
`card_engine` porte 31 capacités en vocabulaire ancien (`capacite` + `preuve_attendue` + `regle`),
sans `id`, sans `source_ref`, sans `expected_proof`. **Ce n'est pas « rien à couvrir », c'est
« unité présente, non adressable ».**

**Je ne le corrige pas ici** — J-3 mesure et décide l'unité ; changer un régime est une
modification, et elle dépend de la réponse à U-2 ci-dessous.

---

## 4 · Les décisions — trois, et seulement trois

| # | question | mesure à l'appui | mon avis |
|---|---|---|---|
| **U-1** | **La feuille est-elle l'unité canonique de jointure ?** | déjà le cas dans le code, un seul collecteur, trois vérificateurs alignés ; `expected_proof` est portée par la feuille et par rien d'autre | **oui** — c'est une ratification de l'existant, pas un choix neuf. Joindre à la `feature` (189) perdrait 271 attentes de preuve ; joindre à la `ligne` (360) ferait dépendre l'attendu du réel |
| **U-2** | **Une feuille sans `id` compte-t-elle dans le dénominateur ?** | 271 feuilles, **240 adressables** ; les 31 restantes sont un run entier (`card_engine`) | **non — mais elle doit être COMPTÉE À PART.** Aujourd'hui elle disparaît : `capaciteIds` vide ⇒ `NOT_APPLICABLE` ⇒ lisible comme « rien à couvrir ». Une unité présente et non adressable est un **défaut**, pas une absence |
| **U-3** | **`couvre[]` doit-il garder le même nom pour deux unités ?** | `blueprint.couvre` = feature · `wiremap.couvre` = feuille | **à trancher.** Les vérificateurs ne s'y trompent pas ; **les agents, si.** Renommer touche 2 contrats et 2 vérificateurs — ce n'est pas J-3, mais la décision d'unité doit dire si l'ambiguïté est tolérée |

### Ce que J-3 ne fait pas
Ne touche pas `preuve` (J-5) · ne touche pas `expected_proof.kind` (J-4) · ne répare aucun run ·
ne modifie aucun régime · ne transforme aucun advisory en gate.

```
status_by_surface:
  unit_is_the_leaf:          TESTED   # collectLeaves, 1 collecteur, 3 vérificateurs
  leaf_validation_rules:     TESTED   # id · capacite · source_ref · expected_proof
  denominator_is_leaf_id:    TESTED   # check_wiremap_contract.mjs:134
  five_levels_counted:       TESTED   # 84 · 189 · 271 · 360 · 240
  couvre_two_units:          TESTED   # featureIds vs collectLeaves
  join_is_many_to_many:      TESTED   # p1_beta_E1 et pacman, distributions mesurées
  not_applicable_conflates:  TESTED   # 0 feuille vs 31 feuilles sans id
  U1_U2_U3:                  BLOCKED  # arbitrage Pierre
  implementation:            BLOCKED
```
`software_verdict: OK` (mesure) · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

**Q2 / R8 : non touchée.** J-5 reste strictement après J-3.

---

## 5 · DÉCISION J-3 — ratifiée Pierre, 2026-09-02

```
U-1  RATIFIÉ   leaf/capacite = unité canonique de la couverture Wiremap
               capacites_couvertes = feuilles DISTINCTES portant un `id` et effectivement jointes
U-2  RATIFIÉ   feuille sans `id` = NON ADRESSABLE : hors dénominateur, mais comptée explicitement
               0 feuille  -> NOT_APPLICABLE      |  n feuilles, 0 id -> INVALID / UNADDRESSABLE
               compteurs exigés : leaves_total · leaves_addressable · leaves_unaddressable · leaves_covered
U-3  REFUSÉ    un même `couvre[]` ne peut pas mélanger `feature.id` et `leaf.id`
               la différence blueprint/wiremap s'assume explicitement — pas de polymorphisme
```

> *« Il révèle un problème de contrat de vocabulaire, pas un problème de calcul. »*
> Et la piste nommée, non ratifiée : **le vrai problème est probablement le nom** — `couvre` a
> l'air d'un identifiant générique alors que sa sémantique dépend du contrat.

### Ce que la ratification laisse à exécuter — et ce qu'elle ne laisse pas
| | à exécuter |
|---|---|
| **U-1** | **rien** — le code fait déjà exactement cela (`collectLeaves` + `leaf.id`, dédupliqué). Ratification de l'existant |
| **U-2** | **oui** — `UNADDRESSABLE` distinct de `NOT_APPLICABLE`, et les 4 compteurs. `leaves_addressable` existe déjà (`capacites`) ; `leaves_total` et `leaves_unaddressable` **ne sont produits par aucun vérificateur** et devront être lus depuis la featuremap |
| **U-3** | **oui, à terme** — l'interdiction n'a aujourd'hui **aucun mécanisme** : rien ne vérifie qu'un `couvre[]` ne mélange pas les deux unités. Une règle sans vérificateur est une prose |

**Aucun code à ce stade — instruction explicite de Pierre.** Les deux lignes exécutables sont
portées au registre `DECISIONS_TO_EXECUTE.md`.

**Hors chemin critique, non traités** : `salvageable`, `salvage_path`, le commentaire menteur de
`run_real.py:3319`.
