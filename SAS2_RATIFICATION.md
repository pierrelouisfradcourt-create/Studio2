# SAS 2 — RATIFICATION

*2026-09-02 · **ENREGISTREMENT DE DÉCISION** · aucun code, aucun fichier touché dans le dépôt
source. Deux décisions distinctes, prises par Pierre.*

## Préflight
```
HEAD dépôt source : feeb29cb  (2026-09-01 16:33:44 +0200)
git status        : 76 lignes
dérive depuis le snapshot du sas 1 : 0 commit
```

---

## D-P3 · GO — couche `verification`, advisory-first

**Ratifié.** Le schéma d'agent acquiert une **4ᵉ couche `verification`** : un champ dont le lecteur
est `verify_run`, **après** production. Régime **advisory d'abord** — conformément au précédent
ratifié 2026-07-26 (condition 2).

**Ce que cette décision ratifie**
- l'existence de la couche `verification` comme catégorie de schéma ;
- le régime advisory : le champ **ne change aucun `software_verdict`, aucun gate** ;
- l'obligation d'arriver **avec son point de mesure** (condition 1 du précédent) — un champ livré
  sans lecteur est refusé par l'invariant même du code : *« un champ sans consommateur déclaré ne
  doit pas être présenté comme une capacité injectée »*.

**Ce que cette décision ne ratifie pas**
- le passage en gate dur : **décision Pierre distincte et ultérieure**, après mesure d'adoption ;
- l'implémentation : rien n'est écrit, ni dans le schéma, ni dans les contrats, ni dans le code.

**Point résiduel — la forme (a) / (b).** La ratification porte sur la couche et le régime. Les deux
formes exigeaient cette couche, donc la ratification ne les départage pas mécaniquement. Coûts
mesurés, inchangés :

| forme | contrats YAML | code | tests | doc |
|---|---|---|---|---|
| **(a)** restructurer `output_contract` → `{production_outputs, consumption_evidence}` | **23** | 3 | 3 | 1 |
| **(b)** champ `consumption_evidence`, couche `verification`, **optionnel** | **0** | 3 | 3 | 1 |
| (c) prose | — | — | — | **exclue** (règle 2026-07-23) |

> **Point résiduel CLOS le 2026-09-02 — forme (b)** : couche `verification` + champ
> `consumption_evidence`, optionnel. Argument retenu : Ratifier une *couche*
> désigne un champ qui la porte ; (a) devrait en plus déplacer `output_contract` de couche **et**
> réécrire 23 contrats en prose. (b) coûte 0 contrat et s'appuie sur le précédent
> `delegation_context` (RECOMMENDED, obligation levée, 2026-08-02).

---

## D-V1 · GO sous réserve historique explicite

**Ratifié à compter de maintenant.** `KNOWLEDGE_RESOLVER_V1` cesse d'être PROPOSED : le cadre
(rasoir 4 conditions · règle anti-couches · zéro écriture par l'outillage) est la doctrine en
vigueur pour ce qui sera construit.

**Trois négations explicites, portées au registre :**

| # | ce qui **n'est pas** ratifié |
|---|---|
| N-1 | **aucune régularisation rétroactive** de `knowledge_trace` — sa construction reste antérieure à l'autorisation qui devait la précéder |
| N-2 | **aucune ratification implicite du gate dur existant** dans `verify_run` |
| N-3 | par conséquent : le gate dur reste **en production sans autorité ratifiée** — état nommé, non corrigé |

> **N-2 tranché le 2026-09-02 — issue (i)** : rétrograder `knowledge_trace` en advisory, **avant**
> tout branchement de l'émetteur. Instruction : `N2_GATE_REGIME.md`. **Non exécutée** — inscrite au
> registre `DECISIONS_TO_EXECUTE.md`.

---

## Mesure qui borne N-2 — correction d'un point de mon instruction du sas 2

J'écrivais que `knowledge_trace` est *« câblé en gate DUR, même sévérité que la preuve mutation »*.
C'est vrai, mais **conditionnellement**. `verify_run._check_knowledge_trace` mesuré :

```
trace ABSENTE                    → warning NON BLOQUANT      (pas de problems)
trace PRÉSENTE + exit != 0       → problems  → gate DUR      (théâtre / corrompue)
node indisponible                → warning honnête           (jamais un vert usurpé)
```

⇒ **Le gate ne mord que sur un run qui porte déjà une trace.** Sur 89 run_dirs, **1** en porte une.
Le périmètre de ce que Pierre refuse de ratifier est donc étroit : il n'a jamais bloqué un run qui
n'avait pas opté pour la trace.

**Mais cette même mesure crée une contrainte de séquence, et c'est le point important :**

> Le sujet 1 du sas 2 est **l'émetteur**. Un émetteur produit des traces. **Le jour où l'émetteur
> est branché, chaque run notifié se met à porter une trace — et le gate dur non ratifié (N-2)
> commence à mordre**, sur une population qui passe de 1/89 à la quasi-totalité.

Autrement dit : **N-2 est tenable aujourd'hui parce que rien n'émet.** Brancher l'émetteur sans
avoir tranché N-2 remettrait en production un blocage dont l'autorité vient d'être explicitement
refusée. Les deux ne peuvent pas être décidés séparément dans le temps — **l'ordre est : trancher
N-2, puis brancher l'émetteur.**

Trois issues pour N-2, non tranchées, à porter au sas 4 :

| # | issue | nature |
|---|---|---|
| i | **rétrograder** le gate en advisory jusqu'à mesure d'adoption — c'est exactement le chemin ratifié 2026-07-26 | modification de code, gate Pierre |
| ii | **ratifier séparément** le gate dur, avec sa mesure d'adoption | décision de gouvernance |
| iii | **laisser en l'état** et consigner l'anomalie | inscription seule — devient intenable dès l'émetteur |

---

## État du sas 2 après ratification

| # | sujet | état |
|---|---|---|
| 1 | Émetteur — orchestrateur, 2 écritures, C1/C2/C3 satisfaites | **RATIFIÉ** *(spécification ; branchement subordonné à N-2)* |
| 2 | J1 — journal en `EVIDENCE/amendments/`, aucune garde heurtée | **RATIFIÉ** |
| 3 | P1 — advisory + `consumption_status()` à trois états | **RATIFIÉ** *(le régime ; pas le gate)* |
| 4 | P3 — couche `verification`, advisory-first | **RATIFIÉ** — forme (a)/(b) résiduelle |
| 5 | `KNOWLEDGE_RESOLVER_V1` | **RATIFIÉ** sous réserve N-1 · N-2 · N-3 |

*Lecture : « ratifier le Sas 2 en deux décisions distinctes » couvre les cinq sujets, les trois
premiers étant déjà marqués « prêt à ratifier ». Si l'intention était de ne ratifier que 4 et 5, un
mot suffit à corriger cette ligne.*

### Ce que cette ratification n'a pas fait
Aucun code · aucun fichier dans le dépôt source · aucun renommage · **aucune implémentation de
l'émetteur, du journal, de la couche `verification` ni de `consumption_status()`** ·
`knowledge_trace.mjs` **non modifié** · la jointure `expected ↔ actual` reste au sas 3 ·
**Q2 / R8 non touchée**.

```
status_by_surface:
  preflight_head:            TESTED       # feeb29cb, 0 dérive, 76 lignes
  d_p3_ratification:         RECORDED
  d_v1_ratification:         RECORDED     # avec N-1, N-2, N-3
  gate_severity_measured:    TESTED       # absent=warning · présent+théâtre=DUR · 1 trace / 89 runs
  emitter_activates_gate:    TESTED       # conséquence mécanique de la mesure ci-dessus
  p3_form_a_or_b:            BLOCKED      # point résiduel, lecture (b) proposée
  n2_resolution:             BLOCKED      # sas 4, trois issues
  implementation:            BLOCKED
```
`software_verdict: OK` (enregistrement) · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`
