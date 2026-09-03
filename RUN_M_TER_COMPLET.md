# RUN M ter — COMPLET

*2026-09-03 · **premier run intégral du Studio V2** · reprise détachée, aucune modification.
**V1 non modifié** : `58095ba9`.*

```
run_status DONE · 13 / 13 étapes OK · verdict.json SIGNÉ
verify_run  ->  INTÉGRITÉ : AUTHENTIQUE
16,43 $ cumulés
```

## La question architecturale est tranchée

> **Le pipeline V2 transplanté sait aller jusqu'au verdict signé.** Trois runs pour l'établir ;
> celui-ci le fait.

```
VERDICT LOGICIEL : OK / HUMANGATE_READY
HMAC             : OK          (clé DEFAULT_KEY_FILE = forge/.forge_key, la clé V2)
évidence intacte : OK
preuve mutation  : OK          gate vert
knowledge_trace  : OK          (absent = avertissement non bloquant — régime N-2)
INTÉGRITÉ        : AUTHENTIQUE

oracles : archi OK · code OK · wiremap OK · standard SKIPPED
software_verdict OK · evidence_verdict MECHANICAL_VALIDATION_ONLY · claim_verdict NO_CLAIM_ALLOWED
git_head 2769dc8  (le commit V2)
```

*Note de méthode : ma recomputation manuelle du HMAC rend `False` — c'est **ma** sérialisation
ad-hoc qui est fausse, pas la signature. L'autorité est `verify_run`, qui recalcule avec le format
réel et rend `HMAC : OK`. Je le signale plutôt que de laisser traîner un chiffre contradictoire.*

## Ce que la chaîne a dû payer pour y arriver

```
s9-build            att = 6      escalade #1 haiku -> sonnet, #2 sonnet -> opus
s10a-oracle-code    att = 5      le gate mutation a REFUSÉ quatre fois
s10b · s10c         att = 5
s11 · s12           att = 1
```

**Le gate mutation n'a rien laissé passer.** Baseline rouge, puis 17/70 mutants tués, puis
plusieurs itérations — il n'a rendu `OK` que lorsque la suite tuait réellement ses mutants.
**Six tentatives de builder pour obtenir une preuve de robustesse.** C'est cher, et c'est
exactement ce qu'on attend d'une porte de preuve sérieuse.

---

## ⚠ Le finding de ce run : l'escalade détruit l'indépendance du red-team

```
run_real.py:3329   model = context.get("model_override") or payload.model
                   ^ appliqué à TOUTES les étapes, model_override est de portée RUN

s11-redteam-code   capability_role: redteam_code   (reviewer indépendant, ADR-002 gate 4)
   runner   claude
   reviewer claude-opus-4-8        <- le modèle d'ESCALADE, pas le reviewer indépendant
   qwen_ok  False
verdict : redteam_ran = False · « red-team dégradé: reviewer indépendant n'a pas tourné »
```

> **Une escalade destinée à renforcer le BUILDER a silencieusement remplacé le REVIEWER
> INDÉPENDANT par un modèle Claude.** Les deux sont couplés par un unique `model_override` de
> portée run. Plus le build est difficile, moins sa revue est indépendante — exactement à
> l'envers de ce qu'on veut.

**Le verdict le signale** (`humangate_flags`), donc le défaut n'est pas silencieux. Mais **rien ne
dit que la CAUSE est l'escalade** : un lecteur conclut « qwen indisponible », alors que qwen
tournait très bien à s6 dans le même run.

### Et mon lot C-1 ne l'a pas capturé — à raison
`route_degradation` est **ABSENT** sur s11. Ce n'est pas un défaut de C-1 : ce n'était pas une
dégradation de **routage**. `route_step` a rendu `RUNNER_CLAUDE` sans `reason`, parce que le
contrat s11 route bien vers Claude ; c'est le `model_override` qui, en aval, a écrasé le modèle.
**Deux mécanismes distincts, deux surfaces distinctes — celui qui devait parler a parlé.**

---

## Ce qui reste ouvert, inchangé

| | |
|---|---|
| **D-1** | toujours contourné — troncature `repair_step.mjs:237`. **Non touché pendant la reprise, comme convenu.** |
| **escalade ↔ indépendance** | nouveau, ci-dessus |
| **le jeu se gagne sans joueur** | mesuré à M ter première portion — variance nulle de l'oracle de solvabilité |
| **s6 : 0 finding par construction** | hérité V1 |
| **convention `logic.test.mjs`** | non documentée ; coût mesuré : plusieurs tentatives de builder |
| **fuite de leçons inter-projets** | `premortem_lessons` sans filtre projet |
| `standard` SKIPPED | déclaré dans les flags, profil `full` |

```
status_by_surface:
  run_complet:          TESTED   # 13/13, run_status DONE
  verdict_signe:        TESTED   # verify_run -> AUTHENTIQUE, clé V2
  gate_mutation_severe: TESTED   # 4 refus avant OK, 6 tentatives de build
  escalade_appliquee:   TESTED   # 2 escalades, model_executed tracé
  independance_s11:     FAIL     # reviewer = modèle d'escalade, redteam_ran False
  C1_hors_perimetre:    TESTED   # pas une dégradation de routage
  D1:                   BLOCKED  # inchangé, par décision
  v1_intact:            TESTED   # 58095ba9
```
`software_verdict: OK` (le run) · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

**Le verdict est `HUMANGATE_READY`. Il attend Pierre — pas moi.**
