# P1 — POINT DE MESURE DE L'ACQUITTEMENT · EXÉCUTION

*2026-09-02 · **PATCH APPLIQUÉ dans le dépôt source**, sur GO explicite Pierre.
Non commité, non poussé. HEAD : `feeb29cb`.*

## Preuve d'exécution
```
.venv312 -m pytest scripts/forge/tests -q -m "not gpu_window"
→ 2535 passed, 1 skipped, 10 deselected   (5:49)     [2521 avant · +14 tests neufs]
```

**Fichier neuf** : `scripts/forge/consumption.py` · **tests** : `tests/test_consumption.py` (14).

---

## Ce que P1 apporte, et que `--verify` ne pouvait pas faire

Démonstration bout en bout, même run, deux instants :

```
                                      --verify        consumption_status
message SERVI, non repris             FOUND    ← faux positif F-2
                                                      not_consumed
la capacité reprend la référence
dans SON artefact désigné             FOUND           consumed   (found_in: blueprint.md)
```

> **`--verify` dit FOUND dans les deux cas.** Il balaie le run_dir entier, et la référence y est —
> dans `context/prompt_s4-archi_a0.txt`, **parce qu'on la lui a servie**. Un `FOUND` prouve que le
> message a été **distribué**, jamais qu'il a été **incorporé**.

P1 ne regarde que **l'artefact désigné** par la capacité (`consumption_evidence`, P3). C'est la
règle d'acquittement du sas 1, et c'est **la seule chose que la sonde ne peut pas faire seule** —
d'où F-2, que J1 ne fermait pas.

Deux exclusions dures, testées : le prompt n'est **jamais** retenu comme preuve, **même s'il est
explicitement désigné** ; la trace non plus — elle contient la référence parce que l'émetteur l'y a
écrite.

## Les trois états — vocabulaire ratifié, rien de plus
```
consumed              la référence est dans l'artefact DÉSIGNÉ
not_consumed          la capacité a un artefact désigné, la référence n'y est pas
no_evidence_declared  la capacité n'a pas déclaré quel artefact fait foi
```
ADVISORY à la lettre du garde-fou 2026-07-26 : aucun verdict lu ou écrit, **jamais d'exception** —
contrat introuvable, YAML illisible, run_dir absent : le pire résultat reste un statut.

### Un angle mort du vocabulaire, rendu visible plutôt qu'inventé
`not_consumed` recouvre **deux situations différentes** : *« a produit son artefact sans reprendre
la référence »* et *« n'a jamais produit l'artefact qu'elle avait désigné »*. Le vocabulaire ratifié
à trois états ne les distingue pas.

**Je n'ai pas ajouté un 4ᵉ état.** `consumption_detail()` expose `artifacts_missing` : la
distinction est lisible, sans forcer une décision de vocabulaire que personne n'a prise. **À
trancher au vu des chiffres**, si les chiffres montrent que ça compte.

---

## ⚠ M ne peut pas encore être mesurée — et c'est le résultat le plus important

```
journal réel       lab/forge_evidence/amendments/journal.jsonl  → N'EXISTE PAS · 0 message
consumption_evidence  filled 0 · declared_empty 0 · absent 28   → 0 contrat sur 28 déclare
runs portant une trace                                          → 1 sur 89 (card_engine,
                                                                   refs pré-mortem, pas des messages)
```

> **Le point de mesure existe ; la population, non.** `consumption_adoption()` rendrait aujourd'hui
> `pairs: 0` — et un `0/0` ne justifie aucun gate.

C'est exactement la situation que le précédent du 2026-07-26 anticipe : **advisory d'abord,
chiffres ensuite, gate en décision séparée.** Deux conditions doivent être remplies avant que M ait
un sens, et **aucune n'est une décision d'architecture** :

1. **au moins une capacité déclare son `consumption_evidence`** — sinon tout couple mesuré rend
   `no_evidence_declared`, ce qui mesure l'absence de déclaration, pas l'acquittement ;
2. **au moins un message est réellement émis** par l'orchestrateur sur un run réel — E fournit le
   geste, elle ne le pose pas.

**Aucune de ces deux choses ne doit être fabriquée pour faire un chiffre.** Un run de démonstration
monté pour produire une statistique mesurerait la démonstration, pas l'adoption.

## Périmètre
**De mon fait** : `consumption.py` (neuf) · `tests/test_consumption.py` (neuf).
**Non touchés** : `knowledge_trace.mjs`, `verify_run.py`, `driver.py`, `verdict.py`, `gate.py`,
`contract.py`, `emitter.py`, les 28 contrats YAML. Aucun résidu dans `lab/` — le journal réel n'a
pas été créé. **Aucun commit, aucun push.** Q2/R8 inchangée, sas 3 fermé.

## Suite
```
N-2 ✅  →  J1 ✅ · P3 ✅  →  E ✅  →  P1 ✅ · M ⚠ population vide  →  G
```
Le registre des décisions ratifiées est **vide de lignes exécutables** : tout ce qui pouvait être
construit sans usage réel l'est. **La suite n'est plus du code — c'est un usage**, ou une décision.

```
status_by_surface:
  designated_artifact_rule:  TESTED   # prompt et trace exclus, même désignés
  f2_closed_by_p1:           TESTED   # --verify FOUND vs consumption_status not_consumed
  three_states:              TESTED   # vocabulaire ratifié, aucun 4e état inventé
  never_raises:              TESTED   # contrat absent, YAML illisible, run_dir absent
  full_suite:                TESTED   # 2535 passed / 1 skipped / 10 deselected
  m_population:              NOT_FOUND # 0 message · 0 déclaration · 1 trace non pertinente
  g_decision:                BLOCKED   # exige M
  commit:                    BLOCKED   # gate Pierre
```
`software_verdict: OK` · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`
