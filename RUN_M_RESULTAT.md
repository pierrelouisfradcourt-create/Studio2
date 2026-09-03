# RUN M — RÉSULTAT

*2026-09-02 · premier run réel du Studio V2 · orchestré par Fable 5.1.
**V1 non modifié** : `58095ba9`, 4 écarts de l'autre session, md5 du diff inchangé.
Toutes les affirmations ci-dessous sont **re-vérifiées par mes soins**, jamais reprises sur parole.*

```
6 étapes exécutées sur 13 · 7,59 $ · 1 631 s · run_status HALTED · decision BLOCKED
```

| étape | | preuve |
|---|---|---|
| s0-contrat | **OK** (att. 2) | `check_charter` PASS, 7 champs — att. 1 refusée : charter en prose, 0 bloc ```yaml |
| s2-worldscan | **OK** | `check_worldscan` 0 problème |
| s1-prisme | **OK** | `check_prisme` PASS · `loop_check` **advisory FAIL** — 5/10 maillons A→J |
| s3-decompo | **OK** | `check_decompo` 0 · featuremap 12 capacités `C01…C12`, **12/12 avec id, source_ref et expected_proof** |
| s4-archi | **OK** | `check_blueprint_contract` 0 · 5 modules, 7 deps interdites isolant `logic` |
| s5-wiremap | **OK** | *voir §3 — le « OK » est le problème* |
| s6-redteam-plan | **BLOCKED** | `claude -p` returncode=1, `unrecognized_model: qwen2.5-14b-instruct` — 0 $, 0 s |

**La conception amont a entièrement fonctionné dans les surfaces V2.** Sept artefacts sur disque,
chacun validé par son oracle. Aucune écriture hors des surfaces V2.

---

## 1 · La cause de l'arrêt — une exclusion déclarée dont le consommateur est resté branché

```python
# forge/runtime.py:64
def _make_qwen_adapter():
    """Construit le QwenAdapter réel (scripts/council.py)."""
    from council import QwenAdapter        # scripts/ est sur sys.path
```
```
council.py en V2 .......... 0 fichier
import council ............ ModuleNotFoundError
qwen_available() .......... False
```

`scripts/council.py` est **déclaré hors périmètre V2** — `ETAPE9_MIGRATION_SURFACES.md` l.80, et
3 tests classés `OUT_OF_SCOPE` sur cette base. **Mais son consommateur, lui, est resté dans un
chemin actif.** J'ai classé l'exclusion sans vérifier qui l'appelait.

> **C'est exactement R8, retourné contre moi** : j'ai cherché les *consommateurs de fichiers*, pas
> les *importateurs de modules*. `council` n'apparaît dans aucun chemin `scripts/…` de mon balayage
> — c'est un `import` nu, invisible à une recherche de chemins.

### Et la panne se déguise en autre chose
```
ModuleNotFoundError  →  avalée par qwen_available() → False
                     →  route_step dégrade lmstudio → RUNNER_CLAUDE_BLIND
                        motif journalisé : « lmstudio :1234 down »          ← FAUX
                     →  payload.model = qwen2.5-14b-instruct passé à `claude -p`
                     →  unrecognized_model → HALT
```
**Le port 1234 était ouvert.** Qwen a répondu en node (`repair_step.mjs`) à 18:01:02, **3 secondes
avant** l'échec Python. Et cette dégradation **n'est journalisée nulle part** : 0 occurrence dans
`run.log`, `state.json` ou les bundles.

> **Un oracle correct qui rend un motif faux.** Si `payload.model` avait porté un nom Claude, s6
> aurait tourné sur un runner **non indépendant** — et rien, dans aucun reçu, ne l'aurait dit. Le
> HALT n'est pas la panne : c'est ce qui a **empêché** la panne silencieuse.

## 2 · La boucle de réparation fabrique la conformité — et je peux le prouver

C'est le résultat le plus lourd du run.

```
sortie de l'AGENT (artifacts/s5-wiremap.txt)   : « couvre » ×5, placeholder littéral ABSENT
wiremap.json APRÈS réparation                  : 12 `couvre` remplis
   ['drawHud','readPaddleIntent','reflectPaddle','breakBricks',
    'requires-capability-id-123',                       ← placeholder LITTÉRAL
    'reflectWalls','checkVictory','checkDefeat','addScore','frame','boot','visual']
```

L'agent avait **honnêtement remonté un fog** et laissé `couvre` vide. **REPAIR_LOOP_V1 (qwen, 379
tokens) l'a rempli** — avec des noms de fonctions et un placeholder de son propre prompt. L'oracle
de forme est passé de 12 problèmes à 0.

```
join_check AU MOMENT DU RUN (avant réparation) : regime EMPTY_FORM · forme_satisfaite false · 0/12
join_check RECALCULÉ sur le fichier actuel     : regime VOID      · forme_satisfaite TRUE  · 0/12
                                                 12 couvertures FANTÔMES
```

> **La réparation a transformé un `EMPTY_FORM` honnête en `VOID` conforme.** La lettre du contrat
> est tenue, la jointure est vide. **C'est le mode dominant des 6 runs V1 que j'ai mesurés ce
> matin — et RUN M en donne la cause : ce n'est pas l'agent qui remplit `couvre` de travers, c'est
> la boucle de réparation.** L'audit avait le symptôme ; le run donne l'étiologie.

Le reçu de réparation porte `quality_not_proven: true`. Il le dit. Personne ne le lit.

## 3 · Un défaut de MON lot J-1, révélé par le run

```
run_real.py:3487   join_check = check_wiremap_join(...)      ← (b-bis)
run_real.py:3495   mesure     = run_repair_step(...)         ← (c)
```

**Le reçu de jointure est pris AVANT la réparation.** Il décrit donc **ce que l'agent a produit**,
jamais **ce que le wiremap contient à la fin**. Sur ce run, l'écart entre les deux est total :
`EMPTY_FORM` au reçu, `VOID` sur disque.

Ce n'est pas faux — c'est **incomplet, et le nom ne le dit pas**. Un lecteur du `state.json` conclut
« l'agent n'a rien couvert » et ignore que le fichier livré porte 12 fantômes.

## 4 · Ce que RUN M a prouvé, et ce qu'il n'a pas prouvé

**Prouvé** — la chaîne migrée s'exécute réellement : 6 étapes, 7 artefacts, 5 oracles amont verts,
les surfaces V2 respectées, `detail.repair` et `join_check` (lots J-1/J-2 de ce matin) **lisibles
dans un run réel**, la clé V2 en place, V1 intact.

**Non prouvé** — aucun jeu : `GAMES/runm_breakout/` n'existe pas, s9 jamais atteint. Aucun verdict
signé, `verify_run` rend « VÉRIFICATION : IMPOSSIBLE ». **JOUABLE : NON MESURÉ.**

**Et rien sur la thèse V2** : ce run a exercé les 13 stations fixes de V1 dans les dossiers de V2.
C'était son objet.

---

## Décisions qui reviennent à Pierre

| # | sujet | nature |
|---|---|---|
| **1** | `forge/runtime.py:64` importe `council` — exclu du périmètre. Requalifier le consommateur, ou rapatrier `council.py` ? | **bloquant pour tout run** |
| **2** | `route_step` étiquette « :1234 down » un échec d'import, **sans journaliser la dégradation**. Un runner non indépendant peut être substitué en silence | **doctrine de preuve** |
| **3** | REPAIR_LOOP_V1 **fabrique** des `couvre` sans référent. Le borner ? l'interdire sur `couvre` ? le rendre bloquant quand `quality_not_proven` ? | **structurel** |
| **4** | `join_check` est pris avant réparation — le déplacer après, ou en prendre **deux** (avant/après) et nommer l'écart | **mon lot, à corriger** |
| **5** | Workspace V2 non *trusted* (`hasTrustDialogAccepted: false`) : 7 `permissions.allow` ignorés à chaque spawn. s0–s5 ont tourné malgré tout | environnement |

**Je n'ai rien corrigé.** Le run est un constat, pas un chantier.

```
status_by_surface:
  chaine_migree_execute:    TESTED   # 6 étapes, 7 artefacts, 5 oracles verts
  cause_arret:              TESTED   # ModuleNotFoundError council, reproduite
  motif_degradation_faux:   TESTED   # port 1234 ouvert, qwen a répondu 3 s avant
  reparation_fabrique:      TESTED   # placeholder absent de la sortie agent, présent dans wiremap.json
  join_avant_reparation:    TESTED   # run_real.py:3487 vs :3495
  jeu_produit:              NOT_FOUND
  verdict_signe:            NOT_FOUND
  v1_intact:                TESTED   # 58095ba9
```
`software_verdict: BLOCKED` · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`
