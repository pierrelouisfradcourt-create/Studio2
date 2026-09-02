# J-1 — JOINTURE `expected ↔ actual` BRANCHÉE EN ADVISORY · EXÉCUTION

*2026-09-02 · **PATCH APPLIQUÉ dans le dépôt source**, sur GO explicite Pierre.
Non commité, non poussé. HEAD : `feeb29cb`.*

## Preuve d'exécution
```
.venv312 -m pytest scripts/forge/tests -q -m "not gpu_window"
→ 2543 passed, 1 skipped, 10 deselected   (5:46)     [2535 avant · +8 tests neufs]
```

---

## Ce qui a été branché

`run_real.check_wiremap_join(run_dir)` — exécute `check_wiremap_contract.mjs --featuremap`
à l'instant où `wiremap.json` vient d'être écrit et où `featuremap.json` existe déjà, puis
normalise le résultat en reçu. Le driver le recopie dans `detail.join_check`.

```
s5-wiremap produit wiremap.json
   ↓
check_wiremap_join()  →  res["join_check"]        (run_real)
   ↓
entry["detail"]["join_check"]                      (driver)  →  state.json
```

### Le chemin de recopie n'était pas cosmétique
Le détail d'étape est un **littéral de clés FIXES** dans `driver.py`. Sans la ligne de recopie,
le reçu serait produit puis **perdu** — c'est mot pour mot ce qui est arrivé à `economy_check` et
`design_questions_check`, *« produits par run_real puis PERDUS au littéral detail, jamais recopiés
dans state.json malgré des mois de production réelle »*. **6ᵉ occurrence du même motif, fermée.**

## ADVISORY, à la lettre
Le reçu porte `advisory: true`. Il ne pose **jamais** `res["blocked"]`, ne change aucun statut
d'étape, aucun `software_verdict`. Un test le vérifie explicitement : `exit_code: 1` sur l'oracle,
et **rien** dans le reçu qui puisse emporter une décision.

Le passage en gate dur reste une **décision Pierre distincte et ultérieure**, au vu des chiffres
que ce reçu rend enfin observables — chemin ratifié 2026-07-26, et N-2 vient d'en payer le prix
inverse.

## Honnêteté du reçu — jamais un vert par défaut
```
artefact manquant           → None          (rien à joindre ; ne pas inventer une mesure)
node indisponible           → NOT_MEASURED
outil injoignable / timeout → NOT_MEASURED
sortie sans JSON            → NOT_MEASURED
```
*Détail technique consigné : le script imprime une ligne humaine avant son JSON ; le reçu repart
de la première accolade, et rend `NOT_MEASURED` s'il n'en trouve pas.*

---

## Ce que le branchement rend visible — sur les 12 runs réels

| run | status | couvertes | non couvertes | fantômes | exit |
|---|---|---|---|---|---|
| auto_battler_i1 · i2 · i2_5 · card_engine | NOT_JOINED | 0 | 0 | 0 | 1 |
| chain_probe_v1 | NOT_JOINED | 0 | 19 | 15 | 1 |
| p1_beta | NOT_JOINED | 0 | 20 | 15 | 1 |
| **p1_beta_E1** | **JOINED** | **20** | 0 | 0 | 0 |
| p2_alpha | NOT_JOINED | 0 | 26 | 28 | 1 |
| p2_beta | NOT_JOINED | 0 | 15 | 17 | 1 |
| p3_alpha | NOT_JOINED | 0 | 23 | 22 | 1 |
| **pacman** | **JOINED** | **62** | 0 | 0 | 0 |
| tower_defense_sonde | NOT_JOINED | 0 | 55 | 61 | 1 |

> Les 4 premiers rendent `0 / 0 / 0` : **génération antérieure, aucune capacité identifiée** — il
> n'y a rien à couvrir, donc rien à manquer. `NOT_JOINED` y signifie *« la jointure n'est pas
> établie »*, pas *« des capacités sont orphelines »*. Le reçu porte les trois compteurs
> séparément pour que cette différence reste lisible.

**Aucun run n'a été réparé.** Ce sont les preuves du défaut, et la population sur laquelle mesurer
si le branchement change quelque chose.

## Périmètre
**De mon fait** : `run_real.py` (helper + 1 appel conditionnel sur `s5-wiremap`) ·
`driver.py` (1 recopie conditionnelle, même patron additif que les 5 précédentes) ·
`tests/test_join_advisory.py` (neuf, 8 tests).
**Non touchés** : `check_wiremap_contract.mjs` (l'oracle est inchangé — on lui donne un lecteur,
pas une nouvelle logique), `verify_run.py`, `verdict.py`, `gate.py`, `contract.py`, les 28 YAML,
et les 12 runs mesurés. **Aucun commit, aucun push.**

## Restent ouvertes — sas 3
```
J-2  couvre rempli d'ids fantômes : durcir la vérification, pas la prose
J-3  unité de jointure : la capacité (mon avis, non ratifié)
J-4  kind: visual — 79 attentes, aucune famille d'oracle dans l'ORDER
J-5  maillon (2) : une ligne doit-elle citer le reçu qui l'établit ?
```

```
status_by_surface:
  join_receipt_wired:      TESTED   # run_real -> driver -> state.json
  advisory_no_authority:   TESTED   # advisory:true, exit 1, aucun blocage porté
  never_false_green:       TESTED   # None / NOT_MEASURED sur 4 chemins d'échec
  real_population_visible: TESTED   # 12 runs, 2 JOINED / 10 NOT_JOINED
  oracle_unchanged:        TESTED   # check_wiremap_contract.mjs non modifié
  full_suite:              TESTED   # 2543 passed / 1 skipped / 10 deselected
  hard_gate:               BLOCKED  # décision Pierre ultérieure, sur chiffres
  j2_j5:                   BLOCKED  # arbitrage Pierre
  commit:                  BLOCKED  # gate Pierre
```
`software_verdict: OK` · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

**Q2 / R8 : non touchée.**
