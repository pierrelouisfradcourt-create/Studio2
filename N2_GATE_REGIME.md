# N-2 — RÉGIME DU GATE `knowledge_trace`

*2026-09-02 · **INSTRUCTION UNIQUEMENT** · aucun code, aucun fichier touché dans le dépôt source.
Objet borné : le régime du gate. Ni l'émetteur, ni la jointure, ni Q2/R8.*

## Préflight
```
HEAD dépôt source : feeb29cb (2026-09-01 16:33:44 +0200) · 76 lignes · 0 dérive
```

---

## 0 · La décision était déjà nommée dans le code — verbatim

`scripts/forge/contract.py:303-307`, à propos de l'injection KB :

> *« CE QUE CECI PROUVE / NE PROUVE PAS : l'**EXPOSITION** […], **JAMAIS la CONSOMMATION**. Le
> lecteur de consommation existe déjà et est câblé (`knowledge_trace.mjs --verify`, appelé par
> `forge.verify_run`) ; **lui donner un producteur est un lot SÉPARÉ, et une décision Pierre** —
> `verify_run` traite les problèmes de knowledge_trace comme **BLOQUANTS**. »*

⇒ **N-2 n'est pas une décision neuve.** C'est une décision que le code avait explicitement
**différée et étiquetée**, pour exactement la raison que tu viens de donner : donner un producteur
(= l'émetteur) à un lecteur bloquant est un lot séparé. Le couplage émetteur↔gate était connu et
laissé ouvert.

*Note : la même ligne rejoue la distinction du sas 1 — exposition ≠ consommation.*

## 1 · Surface exacte du gate — mesurée

| élément | mesure |
|---|---|
| producteur du blocage | `verify_run._check_knowledge_trace` → `knowledge_trace_problems` |
| **consommateurs bloquants** | **1** — `driver.py:4667` `blocking += …` → étape `BLOCKED` |
| `/gate`, `gate.py`, skills | **0 référence** |
| armement | **implicite** : présence du fichier `<run_dir>/knowledge_trace.json` |
| population armée | **1 / 89** run_dirs — `lab/forge_runs/card_engine/` |
| tests figeant la sévérité dure | **2** sur 5 (`…theatrale_ref_introuvable_rejetee`, `…corrompue_rejetee`) |

**Le gate tient en une ligne, un appelant.** Ce n'est pas un chantier ; c'est une décision.

## 2 · Les quatre issues

### (ii) ratifier le gate dur maintenant — **impossible sans se contredire**
Le précédent ratifié 2026-07-26 exige *« advisory […] gate dur, si l'adoption le justifie,
décision Pierre distincte et ultérieure »*. Or :

```
mesurer l'adoption  ⟵ exige des traces émises
traces émises       ⟵ exige l'émetteur
l'émetteur          ⟵ bloqué derrière N-2
```
> **Verrou circulaire.** (ii) ratifierait un gate dur *précisément* sans la mesure d'adoption que le
> précédent impose. C'est la faute qu'on vient de nommer, refaite dans l'autre sens.

### (iii) laisser en l'état — **revient à ne jamais brancher l'émetteur**
Stable tant que rien n'émet. Dès l'émetteur : 1/89 → quasi-totalité, systémique. (iii) n'est donc
pas « ne rien faire » : c'est **abandonner le sujet 1 du sas 2**.

### (i) rétrograder en advisory — **le chemin déjà ratifié**
`knowledge_trace_problems` → `knowledge_trace_warnings`. La vérification **continue de tourner et
de rapporter** ; elle cesse de bloquer.

| coût | mesure |
|---|---|
| code | **1 fichier, 1 fonction** (`verify_run._check_knowledge_trace`) — `driver.py` inchangé, il n'agrège qu'une liste devenue vide |
| tests | **2 assertions à inverser** (le comportement testé change, le test reste) |
| doc | `contract.py:307` devient faux (« traite […] comme BLOQUANTS ») → à corriger |
| perte | l'anti-théâtre **dur** sur `card_engine`, seul run armé — le signal survit en avertissement |

### (iv) armement explicite — garder le gate dur, le découpler de l'émetteur
Le défaut de fond n'est pas la sévérité : c'est que **l'armement est un effet de bord de la
présence d'un fichier**. Une capacité qui se met à émettre s'arme sans l'avoir décidé. (iv) rend
l'armement **déclaré** — le gate ne mord que là où quelqu'un l'a demandé.

> Convergence à noter : une déclaration lue par `verify_run` **après** production est exactement la
> définition de la couche `verification` ratifiée ce matin (D-P3). (iv) n'ajoute aucun composant —
> il change une condition d'armement. La règle anti-couches C2 n'est pas heurtée.

Mais (iv) **présuppose que la destination est un gate dur**, avant toute mesure d'adoption. Il
tranche d'avance ce que le précédent veut décider avec des données.

## 3 · DÉCISION — ratifiée Pierre 2026-09-02 : **(i)**

> *« le hard gate actuel n'a pas encore la mesure d'adoption qui conditionne sa ratification, et
> l'émetteur ne doit pas transformer artificiellement ce défaut de séquence en gate massif. »*

**(iv) est renvoyé à la décision ultérieure sur le gate — pas une précondition.**
**Non exécutée** — voir `DECISIONS_TO_EXECUTE.md`.

## 3-bis · Ce que je recommandais (retenu)

> **(i) maintenant · (iv) comme forme de la décision ultérieure.**

```
rétrograder en advisory        → l'émetteur peut être branché sans rien rendre systémique
l'émetteur émet                → les traces s'accumulent
consumption_status() mesure    → l'adoption devient un chiffre, pas une intuition
décision Pierre ultérieure     → et si elle rearme un gate dur, sous la forme (iv) :
                                 armement DÉCLARÉ par capacité, jamais par présence de fichier
```

C'est le chemin du 2026-07-26, appliqué sans le raccourci qu'il interdit. Et il place la seule
perte — l'anti-théâtre dur sur 1 run — en face du seul gain qui la justifie : pouvoir enfin
mesurer, sur une population réelle, si la trace est consommée.

**Ce que (i) ne fait pas** : il ne supprime pas `knowledge_trace.mjs`, ne touche pas `verifyTrace`,
ne modifie pas la sonde. Il déplace une liste. La capacité anti-théâtre reste entière et câblée —
elle cesse seulement d'exercer une autorité que la ratification d'hier lui refuse (N-2).

```
status_by_surface:
  preflight_head:            TESTED   # feeb29cb, 0 dérive
  decision_already_deferred: TESTED   # contract.py:303-307, verbatim
  gate_surface:              TESTED   # 1 producteur, 1 consommateur bloquant, 0 dans /gate
  armed_population:          TESTED   # 1/89 — lab/forge_runs/card_engine/
  test_blast_radius:         TESTED   # 2 assertions sur 5
  option_ii_circularity:     TESTED   # adoption ⟵ traces ⟵ émetteur ⟵ N-2
  n2_decision:               RECORDED # (i) ratifiée Pierre 2026-09-02
  implementation:            BLOCKED
```
`software_verdict: OK` (instruction) · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`
