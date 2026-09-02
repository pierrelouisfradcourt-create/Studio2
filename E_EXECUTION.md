# E — ÉMETTEUR · EXÉCUTION

*2026-09-02 · **PATCH APPLIQUÉ dans le dépôt source**, sur GO explicite Pierre.
Non commité, non poussé. HEAD : `feeb29cb`.*

## Preuve d'exécution
```
.venv312 -m pytest scripts/forge/tests -q -m "not gpu_window"
→ 2521 passed, 1 skipped, 10 deselected   (6:10)     [2512 avant · +9 tests neufs]
```

### La boucle complète, mesurée bout en bout
```
notify(message, run_dir)              → journal.jsonl (hors run) + 1 item de trace
knowledge_trace.mjs --verify          → exit=1  AMD-DEMO-1  NOT_FOUND
   ↓  la capacité produit un artefact qui cite la référence
knowledge_trace.mjs --verify          → exit=0  AMD-DEMO-1  FOUND
```
**C'est l'anneau qui manquait** : la sonde avait un lecteur de consommation câblé depuis des mois,
et **aucun producteur**. Elle en a un. *(Démonstration en run temporaire, journal temporaire, tout
nettoyé — aucun résidu, le journal réel n'a pas été créé.)*

> ⚠ **Et le `FOUND` ci-dessus ne prouve pas encore ce qu'il devra prouver** : la référence a été
> trouvée *quelque part* dans le run, pas dans **l'artefact désigné** de la capacité. C'est
> exactement l'écart que `consumption_evidence` (P3) existe pour fermer, et c'est le travail de
> **P1 / M** — pas celui de E.

---

## Fichier neuf : `scripts/forge/emitter.py` · tests : `tests/test_emitter.py` (9)

### Deux écritures, jamais confondues
```
message  →  journal.jsonl        HORS run_dir     ce qui a été décidé
item(s)  →  knowledge_trace.json DANS le run_dir  à qui on l'a opposé
```
Un item par capacité **effectivement convoquée**. Les séparer est ce qui rend l'acquittement
vérifiable ; les confondre fabriquerait un `FOUND` par construction.

## Trois décisions que j'ai dû prendre — explicites, révocables

**1 · `source: "mandatory_read"`.** `ALLOWED_SOURCES` est un enum **fermé** de la sonde
(`premortem` / `knowledge_base` / `mandatory_read` / `packet`) — *« amendment » n'existe pas*.
Plutôt qu'élargir la sonde (hors périmètre de E), l'émetteur emprunte **le canal par lequel une
notification atteint réellement une capacité : son `mandatory_read`** — c'est la résolution Q4 du
sas 1, *« N2 + mandatory_read »*. **Zéro modification de `knowledge_trace.mjs`.** Si un type de
source propre devient nécessaire, c'est une décision de schéma distincte.

**2 · MERGE, jamais écrasement — et ce n'était pas optionnel.**
> Mesure : `writeTrace` fait un `writeFileSync` du fichier **entier**. Une seconde notification
> dans le même run **aurait effacé la première.**

L'émetteur relit donc la trace et écrit **l'union dédupliquée**. La sonde reste inchangée : c'est
l'appelant qui porte la discipline non destructive (C1). Un test le prouve — après deux
notifications, les items de la première sont **toujours là**. Et réémettre à l'identique n'ajoute
rien (`items_added: 0`) : le geste est **idempotent**.

**3 · Ordre journal → trace, et pas de rollback.** Le journal **est** l'entrée, la trace en dérive
(C1, recomputable). Si la trace échoue ensuite, le message **reste** au journal — append-only vaut
aussi quand la suite se passe mal. L'erreur dit alors exactement ce qui a été écrit et ce qui ne
l'a pas été, et `write_trace_items` peut être rappelé seul pour finir le geste, sans risque de
doublon.

## Ce que l'émetteur refuse — avant toute écriture
message invalide · **aucune capacité destinataire** (*« une notification sans destinataire convoqué
n'a rien à prouver »*) · `id` déjà au journal · **trace existante illisible** — l'écriture échoue
au lieu d'écraser une preuve qu'on ne sait pas relire · `node` indisponible, jamais travesti en
écriture réussie.

## Ce qu'il n'est pas
**Aucun déclenchement automatique.** Le module fournit le **geste** ; l'orchestrateur le pose (C3 :
*« hors V1 : toute écriture par l'outillage »*). Aucun daemon, aucun watcher, **aucun appel depuis
`driver.py`** — le driver n'a pas été touché.

## Périmètre
**De mon fait** : `emitter.py` (neuf) · `tests/test_emitter.py` (neuf).
**Non touchés** : `knowledge_trace.mjs`, `verify_run.py`, `driver.py`, `verdict.py`, `gate.py`,
`contract.py`, les 28 contrats YAML. Aucun résidu dans `lab/`. **Aucun commit, aucun push.**
Q2/R8 inchangée, sas 3 fermé.

## Suite
```
N-2 ✅  →  J1 ✅ · P3 ✅  →  E ✅  →  P1 · M  →  G
```
**P1 est débloquée** : elle lit `consumption_evidence` (P3) pour savoir quel artefact fait foi, et
mesure sur la population que E produit désormais.

```
status_by_surface:
  emitter_two_writes:      TESTED   # journal hors run · items dans le run
  end_to_end_ring:         TESTED   # NOT_FOUND → production → FOUND
  merge_non_destructif:    TESTED   # 2 notifications, 0 item perdu
  idempotence:             TESTED   # réémission identique : items_added 0
  refus_avant_ecriture:    TESTED   # message invalide · 0 destinataire · trace illisible
  echec_partiel_honnete:   TESTED   # « ÉCRIT au journal, trace NON écrite »
  full_suite:              TESTED   # 2521 passed / 1 skipped / 10 deselected
  designated_artifact:     BLOCKED  # le FOUND actuel n'est pas encore borné à l'artefact désigné → P1
  commit:                  BLOCKED  # gate Pierre
```
`software_verdict: OK` · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`
