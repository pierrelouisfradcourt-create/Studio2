# J-2 — DURCIR LA VÉRIFICATION DE LA JOINTURE (+ `repair` rendu visible) · EXÉCUTION

*2026-09-02 · **PATCH APPLIQUÉ dans le dépôt source**, sur GO explicite Pierre.
Non commité, non poussé. HEAD : `feeb29cb`.*

## Preuve d'exécution
```
.venv312 -m pytest scripts/forge/tests -q -m "not gpu_window"
→ 2552 passed, 1 skipped, 10 deselected   (5:44)     [2543 avant · +9 tests neufs]
```

---

## 1 · Ce qui manquait n'était pas une détection, c'était un verdict non lisible comme conformité

L'oracle voyait déjà tout. Le binaire `JOINED / NOT_JOINED` **fondait deux faits opposés** :

```
6 runs   `couvre` REMPLI, 0 capacité résolue   → la lettre du contrat est TENUE, la jointure est VIDE
4 runs   0 capacité identifiée                 → il n'y a RIEN à couvrir
```
Les deux rendaient `NOT_JOINED`. **Fondre les deux, c'est perdre le seul qui accuse.**

**Cinq régimes, exclusifs et déterministes**, calculés sur les compteurs que l'oracle produit déjà —
**aucune modification de `check_wiremap_contract.mjs`** (réutiliser l'oracle existant, ta consigne) :

| régime | signification |
|---|---|
| `NOT_APPLICABLE` | la featuremap n'identifie aucune capacité — rien à couvrir |
| `EMPTY_FORM` | aucune ligne ne porte `couvre` — la **lettre** du contrat est violée |
| **`VOID`** | **`couvre` rempli, 0 capacité résolue — forme tenue, jointure vide** |
| `PARTIAL` | couverture incomplète, ou au moins un `couvre` fantôme |
| `JOINED` | toutes les capacités couvertes, aucun fantôme |

Et un booléen qui nomme la contradiction au lieu de la laisser se déduire de deux compteurs :

```
forme_satisfaite : True   ← ce que le contrat exige LITTÉRALEMENT est tenu
regime           : VOID   ← et la jointure est vide
```

### Les 12 runs, reclassés
```
run                   regime            forme  couv. non c.  fant.
auto_battler_i1/i2/i2_5, card_engine   NOT_APPLICABLE  False   0     0     0
chain_probe_v1        VOID               True      0     19     15
p1_beta               VOID               True      0     20     15
p1_beta_E1            JOINED             True     20      0      0
p2_alpha              VOID               True      0     26     28
p2_beta               VOID               True      0     15     17
p3_alpha              VOID               True      0     23     22
pacman                JOINED             True     62      0      0
tower_defense_sonde   VOID               True      0     55     61
```

> **6 VOID, tous avec `forme_satisfaite: True`.** La population de référence est désormais
> **étiquetée d'un mot**. Si une modification ultérieure ne fait pas sortir un seul run de `VOID`,
> on saura immédiatement que le maillon n'est pas branché.

---

## 2 · `repair` — 7ᵉ occurrence du motif, et la plus lourde

`run_real` pose `res["repair"]` sur **chaque étape réparable** depuis le branchement de la boucle
de réparation. Mesuré : **0 consommateur dans tout `scripts/forge`.**

> **On ne pouvait pas savoir si la réparation avait tourné, ni ce qu'elle avait changé — sur les
> runs mêmes où la jointure est vide et où c'est ELLE qui aurait dû corriger le `couvre`.**
> Un mécanisme d'auto-correction dont personne ne voit le reçu ne se distingue pas d'un mécanisme
> absent.

`detail.repair` porte désormais `STATUS`, `PROBLEMS_BEFORE`, `PROBLEMS_AFTER`, `TOKENS`,
`FIELDS_CHANGED`, `TRACE` (`runtime_id`, empreintes entrée/sortie).

**Correction d'une phrase que j'ai écrite au sas 3** : j'y disais *« la mesure n'a même pas été
consignée »*. C'était une inférence. Le fait mesuré est plus étroit : **rien ne recopiait le
résultat**. Savoir si la réparation a tourné sur ces runs reste une **inconnue** — que ce
branchement lève pour les runs à venir, pas rétroactivement.

**ADVISORY** : recopie seule. La boucle reste *« capteur, pas juge »* — aucun statut d'étape,
aucun verdict modifié.

---

## Périmètre
**De mon fait** : `run_real.py` (`JOIN_REGIMES`, `_join_regime`, régime + `forme_satisfaite` dans
le reçu) · `driver.py` (1 recopie conditionnelle de `repair`) · `tests/test_join_advisory.py`
(+9 tests).
**Non touchés** : `check_wiremap_contract.mjs`, `repair_step.mjs`, `verify_run.py`, `verdict.py`,
`gate.py`, `contract.py`, les 28 YAML, **et les 12 runs**. **Aucun commit, aucun push.**

## Reste du motif « produit mais perdu »
```
fermées 10   … + join_check (J-1) + repair (J-2)
ouvertes  2   salvageable/salvage_path (0 consommateur ; une note en prose survit dans `reason`)
              task_id (atteint la télémétrie ; seul le commentaire run_real.py:3319 ment)
```
*Ni l'une ni l'autre n'est sur le chemin de J-3/J-5. Je ne les traite pas sans décision.*

## Suite
```
J-2 ✅  →  J-3  →  J-5  →  J-4  →  STOP AUDIT  →  construction V2
```

```
status_by_surface:
  five_regimes:            TESTED   # exclusifs, tous atteignables, ne lèvent jamais
  void_named:              TESTED   # forme_satisfaite True + regime VOID
  not_applicable_separated:TESTED   # ancienne génération distincte de VOID
  oracle_unchanged:        TESTED   # check_wiremap_contract.mjs non modifié
  repair_visible:          TESTED   # detail.repair recopié — 7e occurrence fermée
  real_population:         TESTED   # 4 NOT_APPLICABLE · 6 VOID · 2 JOINED
  full_suite:              TESTED   # 2552 passed / 1 skipped / 10 deselected
  hard_gate:               BLOCKED  # décision Pierre ultérieure
  repair_ran_on_old_runs:  UNKNOWN  # non rétroactif — inconnue assumée
  commit:                  BLOCKED  # gate Pierre
```
`software_verdict: OK` · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

**Q2 / R8 : non touchée.** Aucun run réparé, advisory non transformé en gate.
