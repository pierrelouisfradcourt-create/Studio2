# LOTS C ET D — INSTRUCTION AVANT M BIS

*2026-09-02 · **MESURE UNIQUEMENT**, aucun code modifié. V1 intact (`58095ba9`).
Ordre ratifié : B ✅ → **C fallback** → **D preuve Wire Map** → M bis, mêmes conditions.*

---

## C · Le fallback — la docstring promet la visibilité, personne ne l'écrit

```python
# forge/runtime.py:83
def route_step(payload) -> RouteDecision:
    """... dégrade vers un fallback Claude en contexte vierge, avec une `reason`
    explicite (visibilité de la dégradation, JAMAIS SILENCIEUSE)."""
```

**Mesure :** `decision.reason` est produit par `route_step`, puis **écrit nulle part**.

```
grep "decision.reason"  dans driver.py   ->  0 occurrence
grep "route_reason"     dans driver.py   ->  0 occurrence
```

> **La promesse est dans la docstring, le mécanisme n'existe pas.** C'est le motif
> *« déclaré ≠ exécuté »* dans sa forme la plus pure : le code affirme sa propre visibilité.
> Et c'est la **8ᵉ occurrence** du motif « produit mais perdu » — après `join_check` (J-1),
> `repair` (J-2), et les six fermées avant elles.

### Le second défaut : la raison produite est FAUSSE
```python
def qwen_available(adapter=None) -> bool:
    try:  return bool(_make_qwen_adapter().is_available())
    except Exception:  return False          # import ET réseau, indistincts
```
Un `ModuleNotFoundError` et un port fermé rendent **le même `False`**, puis :
```python
reason = "lmstudio :1234 down — reviewer indépendant indisponible"
```
Le 2026-09-02 à 18:01, ce motif a été produit **sur un port ouvert**, pendant que Qwen répondait
en node 3 secondes plus tôt.

### Trois issues
| # | | portée |
|---|---|---|
| **C-1** | **journaliser** `decision.reason` dans le détail de l'étape — même patron additif que les 7 précédentes | 1 recopie ; rend la dégradation lisible, ne change aucun comportement |
| **C-2** | **distinguer** la cause : `qwen_available` rend *pourquoi* (import / réseau / autre), `route_step` la reprend | ~10 lignes ; supprime le motif faux |
| **C-3** | **fail-closed** sur les étapes à indépendance requise (s11) : pas de substitution silencieuse d'un reviewer non indépendant | changement de comportement — **décision de doctrine, pas de code** |

*Mon avis : C-1 + C-2 forment un lot cohérent et sans risque. **C-3 est une décision séparée** —
c'est un gate, et la règle de ce studio est advisory d'abord.*

---

## D · La preuve Wire Map — la boucle optimise une métrique qui exclut le défaut

**Mesure décisive**, et elle explique tout :

```js
check_wiremap_contract  rend QUATRE listes :
    problems · capacites_non_couvertes · couverture_fantome · maillon_non_lie

repair_loop.mjs  ne lit que  resultat.problems      (l.376, 409, 437, 453, 472)
```

Déroulé réel de RUN M :
```
avant réparation   problems = 12   (12 lignes sans `couvre` — violation de FORME)
                   couverture_fantome = 0
la boucle remplit les 12 `couvre` (379 tokens, 12 appels modèle)
après réparation   problems = 0            -> reçu : « PROBLEMS_BEFORE 12 -> AFTER 0 »
                   couverture_fantome = 12  <- NON COMPTÉ par la boucle
oracle relancé maintenant sur le même fichier :
                   VERDICT WIREMAP : FAIL — 0 sur 12 capacités couvertes
```

> **`PROBLEMS_AFTER: 0` est vrai pour la métrique de la boucle, et faux pour le verdict de
> l'oracle.** Le défaut n'a pas été réparé : il a été **déplacé** vers une liste que le réparateur
> ne regarde pas. C'est la **loi du déplacement** ratifiée le 2026-08-04 — appliquée ici non à un
> durcissement, mais à une réparation.

**Et c'est l'étiologie des 6 runs `VOID` mesurés ce matin.** Ce n'est pas l'agent qui remplit
`couvre` de travers ; c'est la boucle, en optimisant la forme.

*Détail qui achève la démonstration : parmi les 12 valeurs écrites figure le placeholder littéral
`requires-capability-id-123` — absent de la sortie de l'agent, présent dans le fichier final.
Le réparateur a recopié l'exemple de son propre prompt.*

### Le défaut adjacent — mon lot J-1
```
run_real.py:3487   join_check = check_wiremap_join(...)     (b-bis)
run_real.py:3495   mesure     = run_repair_step(...)        (c)
```
Le reçu de jointure est pris **avant** la réparation : il a dit `EMPTY_FORM` (l'agent n'avait rien
couvert) pendant que le fichier livré devenait `VOID`. **Les deux constats sont vrais et disent
des choses différentes** — mais un seul est écrit, et son nom ne dit pas lequel.

### Quatre issues
| # | | portée |
|---|---|---|
| **D-1** | la boucle compte **les quatre listes**, pas `problems` seul | ~3 lignes ; supprime le déplacement à la source |
| **D-2** | **deux** reçus de jointure — avant ET après réparation — et nommer l'écart | ~5 lignes ; rend la fabrication visible |
| **D-3** | **interdire** la réparation sur `couvre` : une jointure ne se répare pas, elle se conçoit | changement de politique |
| **D-4** | `quality_not_proven: true` cesse d'être décoratif | gate — **décision séparée** |

*Mon avis : **D-1 + D-2**. D-1 attaque la cause, D-2 rend l'effet observable. D-3 et D-4 sont des
décisions de politique, et D-4 est un gate — advisory d'abord.*

---

## Ce que je ne fais pas

Rien n'est modifié. **M bis n'est pas relancé** — et il ne doit pas l'être avant C et D, sinon il
reproduira exactement le même `VOID` conforme, avec les mêmes 7,59 $.

**Condition de « mêmes conditions » pour M bis** : même commande, même brief, même profil `full`,
même projet `runm_breakout`. ⚠ Le `run_dir` existant contient déjà les artefacts de la première
tentative — **il faudra décider** si M bis repart d'un répertoire vierge (comparable) ou reprend
l'existant (plus rapide, mais plus comparable à rien).

```
status_by_surface:
  reason_jamais_ecrite:      TESTED   # 0 occurrence dans driver.py
  reason_fausse:             TESTED   # import et réseau indistincts
  boucle_compte_1_sur_4:     TESTED   # repair_loop.mjs, 5 sites
  deplacement_mesure:        TESTED   # problems 12->0, fantomes 0->12, oracle FAIL
  join_avant_reparation:     TESTED   # run_real.py:3487 vs 3495
  C_et_D:                    BLOCKED  # arbitrage Pierre
  m_bis:                     BLOCKED  # après C et D
```
`software_verdict: OK` (instruction) · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`
