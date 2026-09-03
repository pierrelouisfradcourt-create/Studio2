# LOT ESC-1 — PORTÉE DE L'ESCALADE

*2026-09-03 · **décision contractuelle** ratifiée Pierre, pas un correctif de journalisation.
**V1 non modifié** (`58095ba9`). Baseline M ter intacte.*

## La règle posée

> **Une escalade du builder ne modifie JAMAIS le modèle du reviewer indépendant.**
> L'override passe de portée **RUN** à portée **étape** : il porte le nom de l'étape qu'il vise,
> et cette étape seule l'applique.

## Le défaut qu'elle ferme, mesuré sur M ter

```
run_real.py   model = context.get("model_override") or payload.model     ← portée RUN
              appliqué à TOUTES les étapes

s9-build      escalade haiku -> sonnet -> opus     (2 escalades, 6 tentatives)
s11-redteam   reviewer = claude-opus-4-8           ← le modèle d'ESCALADE
              capability_role: redteam_code, qwen_ok = False
verdict       redteam_ran: False · « red-team dégradé »
```

**Plus le build était difficile, moins sa revue était indépendante.** Exactement à l'envers de ce
que ADR-002 gate 4 exige.

Le verdict le signalait — le défaut n'était pas silencieux. **Mais rien ne disait que la CAUSE
était l'escalade** : un lecteur concluait « qwen indisponible », alors que qwen tournait très bien
à s6 **dans le même run**.

## Les deux moitiés du correctif

```python
# driver.py — l'escalade DÉCLARE sa portée
  state["model_override"] = d.next_model
+ state["model_override_scope"] = builder

# driver.py — les 3 sites de contexte la TRANSPORTENT, avec repli
+ "model_override_scope": state.get("model_override_scope") or self._builder_step(),

# run_real.py — l'étape visée SEULE l'applique
- model = context.get("model_override") or payload.model
+ model = _override if (_override and (not _portee or _portee == etape)) else payload.model
```

**Le repli est délibéré** : un `state.json` antérieur au lot n'a pas de portée. Le driver la
reconstruit via `_builder_step()` — l'escalade n'a jamais visé autre chose que le builder, donc
une **reprise** de run reste correcte. Et si la portée manquait malgré tout, l'ancien comportement
subsiste : **une reprise ne doit jamais devenir un no-op silencieux.**

## Les gardes — 7 tests, dont deux anti-divergence

```
le builder escaladé reçoit bien le modèle supérieur          opus
le reviewer indépendant GARDE son routage                    qwen2.5-14b-instruct
aucune autre étape n'est touchée                             s0 · s5 · s6 · s12
sans escalade, rien ne change
state antérieur sans portée : ancien comportement conservé
```

Et **deux gardes structurelles**, parce qu'un test qui recopie une logique mesure sa propre copie —
c'est l'erreur exacte du premier lot D-1 :
- `run_real` doit encore **lire** `model_override_scope` et comparer `_portee == etape` ;
- `driver` doit encore **déclarer** la portée, et la transporter dans **les trois** contextes —
  « sinon un chemin la perd ».

## Non-régression
```
pytest forge/tests   2459 passed · 43 failed   (ligne de base inchangée, +7 tests)
```

```
status_by_surface:
  portee_declaree:      TESTED   # driver, à l'escalade
  portee_transportee:   TESTED   # 3 contextes
  reviewer_protege:     TESTED   # s11 garde son routage
  reprise_compatible:   TESTED   # repli sur _builder_step()
  gardes_anti_divergence: TESTED # la règle testée est celle du code
  non_regression:       TESTED   # 2459 passed / 43 failed
```
`software_verdict: OK` · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED`

**Non vérifié en run réel** : aucun run n'a été relancé. La règle est prouvée sur le point de
décision et par les gardes structurelles ; **sa manifestation dans un run escaladé reste à
observer.**
