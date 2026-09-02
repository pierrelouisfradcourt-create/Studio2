# W-2 — DÉCOUPLAGE DU VOLET VISUEL PAR MOTEUR · EXÉCUTION

*2026-09-02 · **PATCH APPLIQUÉ dans le dépôt source**, sur GO explicite Pierre.
Non commité, non poussé. HEAD : `feeb29cb`. `games/pong` : **intact**.*

## Preuve d'exécution
```
.venv312 -m pytest scripts/forge/tests -q -m "not gpu_window"
→ 2555 passed, 1 skipped, 10 deselected   (5:47)     [2552 avant · +4 tests, 1 réécrit]
```

---

## Le changement, en une phrase
`check_visual_capture.passed` cesse d'exiger **tous** les moteurs et n'exige plus que les volets
**applicables et mesurés**.

```
AVANT   passed = browser mesuré vert  ET  godot mesuré vert
        ⇒ un jeu purement web — 68 des 79 attentes `visual` — ne pouvait JAMAIS être vert

APRÈS   script ABSENT            → ce moteur n'existe pas pour ce jeu, hors agrégat
        script PRÉSENT non mesuré → reste NOT_MEASURED, LISTÉ, n'emporte plus le statut
        aucun volet mesuré        → NOT_MEASURED  (INCHANGÉ)
        au moins un volet mesuré rouge → FAIL     (INCHANGÉ)
```

**`passed` signifie désormais « tout volet applicable ET mesuré est vert », jamais « tout a été
mesuré ».** C'est pourquoi `not_measured_volets` est exposé et documenté : *moins d'autorité
conjonctive, même capacité de détection, absence toujours visible.*

## Les deux gardes qui empêchent que ce soit un relâchement

| garde | test |
|---|---|
| **aucun vert par vacuité** — un jeu sans aucun script de capture reste `NOT_MEASURED` ; W-2 ne fabrique **pas** de preuve là où il n'y a pas de producteur (état actuel des 8 jeux portant des attentes `visual`) | `test_3c_aucun_volet_mesure_ne_gagne_aucun_vert` |
| **rien de relâché sur le mesuré** — un volet applicable, mesuré et rouge rend `FAIL`, jamais dilué par un autre volet vert | `test_3c_rouge_mesure_reste_rouge` |

Et la moitié qui rend le découplage honnête : un script **présent mais non mesurable** figure dans
`not_measured_volets` — il ne bloque plus, il ne disparaît pas
(`test_3c_moteur_present_mais_non_mesurable_reste_visible_et_nemporte_pas_le_statut`).

## Un test a changé de politique — c'est le cœur de la décision
`test_3c_not_measured_jamais_ok_quand_godot_absent` affirmait : *« le statut global ne doit JAMAIS
être OK quand godot n'a pas tourné du tout »*. C'était exactement la conjonction que W-2 lève.
Réécrit en `test_3c_moteur_absent_nentre_pas_dans_l_agregat`, avec le motif inscrit dans son
docstring. **Aucune assertion n'a été supprimée sans être remplacée par la politique ratifiée.**

## Correction d'un point de mon rapport V-2
J'y écrivais que le volet Godot restait **non mesuré** sur ce poste. La suite contient
`test_3c_vert_sur_pong_reel`, qui appelle les **vraies** captures de Pong et dont le docstring
atteste : *« sur CE poste, un binaire Godot est configuré et une fenêtre GPU réelle est disponible
(RTX 5080, Vulkan) — donc mesuré »*. Il passe. **Le blocage que j'avais observé était bien un
artefact de mon bac à sable**, et je le tenais pour « non mesuré » : c'est corrigé, la mesure
existait dans la suite.

## Périmètre
**De mon fait** : `product_oracle.py` (`check_visual_capture` : agrégat par volet, `volets`,
`measured_volets`, `not_measured_volets`, docstring et `limites` mises à jour) ·
`tests/test_product_oracle.py` (1 test réécrit, 3 neufs, docstring de module).
**Non touchés** : `capture_browser.mjs` / `capture_godot.mjs` (les captures ne sont **jamais**
réimplémentées), `games/**`, `s10d` / `quality_sensor` (toujours non branchés), `driver.py`,
`verify_run.py`, les 28 YAML. **Aucun commit, aucun push.**

## Ce que W-2 débloque, et ce qu'il ne prouve pas
**W-1 devient exécutable** : fabriquer `capture_browser.mjs` dans les jeux qui portent des attentes
`visual` produira désormais un verdict atteignable, au lieu d'un rouge structurel.
**Mais le volet reste un détecteur de plancher** (falsification V-2 : mort et gel détectés,
dégradation non détectée). **W-3 — l'inscrire là où `kind: visual` est déclaré — reste à prendre.**

```
status_by_surface:
  decouplage_par_moteur:     TESTED   # 4 tests : absent · présent-non-mesuré · aucun · rouge
  pas_de_vert_par_vacuite:   TESTED   # 0 volet mesuré => NOT_MEASURED
  rouge_non_dilue:           TESTED   # FAIL conservé
  absence_toujours_visible:  TESTED   # not_measured_volets
  captures_non_touchees:     TESTED   # aucun .mjs de jeu modifié
  full_suite:                TESTED   # 2555 passed / 1 skipped / 10 deselected
  W1:                        BLOCKED  # débloquée, non prise
  W3:                        BLOCKED  # non prise
  commit:                    BLOCKED  # gate Pierre
```
`software_verdict: OK` · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

**Q2 / R8 : non touchée.**
