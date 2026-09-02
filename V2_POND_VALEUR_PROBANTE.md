# V-2 — VALEUR PROBANTE RÉELLE DU VOLET 3c, MESURÉE SUR `pong`

*2026-09-02 · **LECTURE SEULE SUR LE DÉPÔT** · aucun fichier du dépôt modifié, aucun code livré.
HEAD `feeb29cb`. `games/pong` : **intact** (`git status` vide).*

## Méthode — et pourquoi elle ne pouvait pas être « exécuter en place »

`capture_browser.mjs` **écrit deux PNG** dans `.../presentation/shots/`, et ces fichiers sont
**suivis par git**. L'exécuter dans le dépôt aurait modifié des fichiers versionnés — au-delà du
mandat read-only.

> **Mesure faite dans un bac à sable** : copie de `games/pong` (2,1 Mo) dans le scratchpad de
> session, exécutions et mutations **uniquement sur la copie**. Le dépôt n'a jamais été écrit.

---

## 1 · Le volet tourne, et rend un signal réel

```json
{ "adapter": "browser", "passed": true, "differ": true,
  "colorsA": 4, "colorsB": 4, "monochromeA": false, "monochromeB": false }
```
Déterministe (seed fixe), reproductible (4 exécutions, résultat identique), non-LLM.
**Le volet navigateur est fonctionnel.**

## 2 · Falsification — l'enveloppe exacte de ce qu'il détecte

Trois mutations appliquées **à la copie**, volet ré-exécuté après chacune, retour au baseline vérifié :

| mutation | effet visuel | `differ` | `colors` | verdict du volet |
|---|---|---|---|---|
| — baseline | jeu normal | true | 4 / 4 | **passed** |
| **M1'** — `render(b)` = `render(a)` | rendu **figé** | **false** | 4 / 4 | **DÉTECTÉ (rouge)** |
| **M2** — `drawState` ne peint que le fond | rendu **mort** | false | **1 / 1**, monochrome | **DÉTECTÉ (rouge)** |
| **M3** — 45 ticks → **1 tick** | rendu **quasi figé** | true | 4 / 4 | **NON DÉTECTÉ (vert)** |

> **Le critère détecte la mort totale, pas la dégradation.** Un rendu qui bouge d'un pixel passe
> aussi bien qu'un jeu qui tourne. C'est un **détecteur de plancher**, pas une mesure de qualité
> visuelle — et il est exactement aussi bon que ce que son nom promet (« deux captures différentes,
> aucune monochrome »), ni plus, ni moins.

*Correction de méthode, consignée : ma première tentative de M1 modifiait la valeur par défaut
`ticks = 45` alors que l'appel réel passe `midGameState(1, 45)` **explicitement**. La mutation
n'était pas appliquée et j'ai failli conclure « non détecté ». Vérifiée au site d'appel, puis
refaite. **Une mutation qui n'atteint pas le code testé mesure le test, pas le sujet.***

---

## 3 · La limite structurelle, et elle est décisive pour les 68 attentes web

```python
if   not browser_measured : NOT_MEASURED
elif not browser_ok       : FAIL
elif godot_blocked or not godot.ran or godot.json is None : NOT_MEASURED
elif not godot_ok         : FAIL
else                      : OK
passed = (status == "OK")
```

> **`passed` exige que les DEUX volets soient mesurés et verts.** Sur un jeu **purement web** — donc
> sur les **68 des 79** attentes `visual` — le volet Godot ne peut jamais être mesuré, le statut
> retombe sur `NOT_MEASURED`, et **`passed` est `False` même avec une capture navigateur
> parfaitement verte.**

Ce n'est pas malhonnête : `NOT_MEASURED` est explicite, `not_measured` est exposé, et le détail
`browser.json.passed` reste lisible. Mais **tel quel, `check_visual_capture.passed` n'est pas
utilisable comme source de preuve `visual` pour un jeu web.** Un consommateur devrait lire le volet
navigateur seul — ce qu'aucun consommateur ne fait aujourd'hui.

### Ce que je n'ai PAS mesuré
Le volet **Godot**. Dans le bac à sable il est ressorti `blocked` parce que `godot_bin.mjs` se
résout relativement à l'emplacement du jeu — **artefact de ma copie, pas un fait sur ce poste**.
`scripts/forge/godot.config.json` désigne bien un binaire Godot 4.6.3. **Statut : NON MESURÉ**, et
je ne le déduis pas.

---

## 4 · Réponse à la question de V-2

> *« Le consommateur branché produit-il une observation suffisamment déterministe/exploitable pour
> qu'il vaille la peine de fabriquer son producteur partout ? »*

**Oui pour le déterminisme. Partiellement pour l'exploitabilité. Non en l'état pour le web.**

| | |
|---|---|
| déterministe, reproductible, non-LLM | **oui** |
| détecte un rendu mort ou figé | **oui**, prouvé par falsification |
| détecte une dégradation visuelle | **non** — M3 passe |
| utilisable tel quel comme preuve `visual` sur un jeu web | **non** — `passed` exige le volet Godot |

### Trois décisions

| # | question | mon avis |
|---|---|---|
| **W-1** | **Fabriquer `capture_browser.mjs` dans les 8 jeux ?** | **pas avant W-2.** Le producteur est utile — mais son consommateur rendrait `passed=False` sur les 7 jeux web quoi qu'il arrive. On fabriquerait 8 producteurs pour un verdict structurellement rouge |
| **W-2** | **Découpler le statut par moteur** dans `check_visual_capture` (un jeu web est vert si le volet navigateur est vert ; le volet Godot reste `NOT_MEASURED` sans emporter le statut) | **oui — et c'est le préalable.** Correction d'une conjonction trop forte, dans un volet **déjà advisory**, sans nouvelle famille ni nouveau composant. C'est le plus petit changement qui rend les 68 attentes honorables |
| **W-3** | **Que promet-on à `kind: visual` ?** | **le plancher, et le dire.** Le volet prouve « ça rend, et ça bouge ». Il ne prouve pas que ça rend *correctement*. Inscrire cette limite là où le `kind` est déclaré évite qu'un futur vert se lise comme une preuve visuelle |

```
status_by_surface:
  sandbox_isolation:        TESTED   # copie scratchpad ; games/pong intact (git status vide)
  volet_browser_functional: TESTED   # differ true, 4 couleurs, reproductible
  falsification_M1_M2:      TESTED   # rendu figé et rendu mort : DÉTECTÉS
  falsification_M3:         TESTED   # dégradation (1 tick) : NON détectée
  passed_requires_both:     TESTED   # product_oracle.py, conjonction browser AND godot
  godot_volet:              NOT_MEASURED # blocage observé = artefact de bac à sable
  W1_W2_W3:                 BLOCKED  # arbitrage Pierre
  implementation:           BLOCKED
```
`software_verdict: OK` (mesure) · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

**Q2 / R8 : non touchée.** Aucun adaptateur fabriqué, aucun pipeline modifié, `s10d` toujours non branché.
