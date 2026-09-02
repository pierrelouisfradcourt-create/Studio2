# P3 — pourquoi le 18ᵉ champ avait été refusé

*2026-09-01 · DOCUMENTED_ONLY · aucun code. Dépôt source `feeb29cb`, non touché.*
*Note bornée : elle instruit **P3** (sas 2). Elle ne décide rien.*

---

## Le refus, verbatim

`SCHEMA.md`, section `SKIPPED_VALIDATION[]` — *ratification Pierre 2026-07-26* :

> *« Ce n'est **pas** un 18e champ du contrat d'entrée — il ne s'ajoute ni à Critique, ni à
> Important, ni à Recommandé, et **ne touche pas** le compte des 17 champs ci-dessus. C'est une
> exigence sur ce que l'agent **produit** dans son `final_report`, au même titre que le vocabulaire
> de verdict unique. »*

## Ce que le refus disait réellement

**Ce n'était pas « pas de nouveau champ ».** C'était une **classification** : entrée vs sortie.

`SKIPPED_VALIDATION` est une **exigence de SORTIE** — ce que l'agent *produit*. Elle n'a donc rien
à faire dans le **contrat d'entrée**, qui déclare ce qu'on donne *à* l'agent. Et le studio avait
un chemin moins cher : injection verbatim par `contract.RESTITUTION_RULE`,
> *« donc dans les 21 prompts, **sans éditer les 21 YAML** »*.

## Pourquoi le précédent ne s'applique pas à `consumption_evidence`

| | `SKIPPED_VALIDATION` | `consumption_evidence` |
|---|---|---|
| qui le produit | **l'agent**, dans son `final_report` | **l'auteur du contrat** — l'agent ne l'écrit jamais |
| qui le lit | un humain / la mesure d'adoption | **`verify_run`**, machine |
| varie-t-il par capacité ? | **non** — identique pour les 21 | **oui** — `s2.5-artbible` produit `art_bible.md` · `asset_requests.json` · `gm_worldscan.json` ; lequel fait foi ? |
| injectable par `RESTITUTION_RULE` ? | **oui** — c'est ce qui a été fait | **non** — une règle uniforme ne peut pas exprimer une valeur qui diffère par contrat |
| nature | exigence de sortie | **déclaration d'entrée *portant sur* la sortie** |

> Le précédent **ne bloque pas** `consumption_evidence` — il le **classe de l'autre côté**. Le
> chemin bon marché qui avait permis d'éviter un 18ᵉ champ en 2026-07 (injection uniforme) est
> mécaniquement indisponible ici, précisément parce que la valeur varie par capacité.

## Mais le précédent impose deux conditions — et elles sont plus contraignantes que le refus

**Condition 1 — arriver avec son point de mesure.** Verbatim :
> *« Le garde-fou de la ratification (**le corpus Codex est mort d'avoir été déclaratif sans
> lecteur**) impose que la primitive arrive avec **son point de mesure** :
> `forge.skipped_validation.skipped_validation_status(agent_output)` classe la sortie en trois
> états — `filled` / `declared_empty` / `absent` — pour mesurer l'adoption réelle. »*

⇒ `consumption_evidence` ne peut pas entrer seul. Il entre **avec la fonction qui le lit et
classe son adoption**. Sinon : déclaratif sans lecteur — exactement `reference_guard`, exactement
le corpus Codex.

**Condition 2 — advisory d'abord, gate ensuite, par décision séparée.** Verbatim :
> *« **ADVISORY UNIQUEMENT** : ceci ne bloque rien, ne change aucun `software_verdict`, aucun gate.
> […] Le passage en gate dur, si l'adoption le justifie, est une **décision Pierre distincte et
> ultérieure**. »*

## Conséquence directe sur P1 — le précédent le recadre aussi

P1 proposait `trace absente → BLOCKED` d'emblée. Le précédent ratifié dit l'inverse de la méthode :
**advisory + point de mesure d'abord, gate dur ensuite comme décision séparée.**

```
chemin ratifié 2026-07-26        proposition P1 initiale
  advisory                          gate dur immédiat
  + point de mesure d'adoption      —
  gate dur = décision ULTÉRIEURE    —
```

⇒ **P1 devrait suivre le même chemin** : mesurer d'abord combien de capacités notifiées citent
effectivement la ref, puis décider du blocage. Ce n'est pas un ralentissement inutile : c'est la
règle que ce studio s'est donnée après avoir vu mourir un corpus déclaratif sans lecteur.

## Ce que P3 devient au sas 2

La question n'est plus *« a-t-on le droit d'un 18ᵉ champ ? »* mais :

> **`consumption_evidence` est-il une déclaration d'entrée portant sur la sortie — et si oui,
> arrive-t-il avec son point de mesure et en régime advisory d'abord ?**

Les trois formes restent (a) structurer `output_contract` · (b) 18ᵉ champ liste · (c) prose —
**(c) toujours exclue** (règle 2026-07-23 : aucune donnée gouvernant un comportement dans un
commentaire). Le précédent n'élimine ni (a) ni (b) ; **il ajoute deux conditions d'entrée aux
deux.**

```
status_by_surface:
  precedent_18e_champ:      TESTED   # SCHEMA.md lu, section complète, ratification 2026-07-26
  p3_reclassification:      DOCUMENTED_ONLY
  p1_method_correction:     DOCUMENTED_ONLY
  decision:                 BLOCKED  # arbitrage Pierre, sas 2
```
`software_verdict: OK` · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED` · `no_global_ready_verdict: true`

---

# P3(b) — compatibilité du schéma et coût de migration, mesurés

## Compatibilité : le validateur est **permissif**
```
load_contract  → itère sur CRITICAL (14) · IMPORTANT (2) · RECOMMENDED (1) = 17
                 valide la PRÉSENCE des champs connus
gardes contre un champ INCONNU : 0        (aucun `set(data) - known`, aucun rejet)
```
⇒ **ajouter `consumption_evidence` à un contrat YAML est silencieusement accepté aujourd'hui.**
Il ne casserait rien — et ne ferait rien non plus, tant qu'aucun lecteur ne l'ouvre. C'est
exactement la condition 1 du précédent, formulée par le code lui-même.

## Le schéma a déjà été amendé — il existe une procédure
> `SCHEMA.md` §79 : **« Amendement layer — ratifié Pierre 2026-08-02 »**
> *« Conséquences mécaniques de cet amendement (implémentées le même jour, mêmes fichiers) »*

Cet amendement a introduit la **couche par champ** et levé l'obligation sur `delegation_context`.
**Le précédent d'amendement existe donc, avec sa méthode : ratification + conséquences mécaniques
implémentées le même jour, dans les mêmes fichiers.**

## ⚠ Mais l'amendement de 2026-08-02 crée une contrainte que P3(b) doit satisfaire
Le code porte l'invariant, verbatim :
> *« Un champ sans consommateur déclaré ne doit pas être présenté comme une capacité injectée
> (**invariant Pierre, verbatim dans SCHEMA.md**). »*

Tout champ doit déclarer sa **couche**. Les trois existantes :
| couche | définition | `consumption_evidence` y entre-t-il ? |
|---|---|---|
| `prompt` | rendu comme section de texte par `_render_prompt` | **non** — l'agent n'a pas à le lire |
| `dispatch` | consommé pour construire le payload (modèle/provider/outils) | **non** — ne touche pas le payload |
| `documentation` | traçabilité humaine, **aucun consommateur d'exécution** | **non** — il a justement un consommateur machine |

> **`consumption_evidence` n'entre dans aucune des trois couches.** Son lecteur est `verify_run`,
> après production. Il exigerait une **4ᵉ couche** — `verification` — c'est-à-dire un amendement
> du même ordre que celui du 2026-08-02, pas un simple ajout de champ.

## Coût de migration — rayon d'impact mesuré
| élément | compte | note |
|---|---|---|
| fichiers de **code** énumérant les champs (hors tests) | **3** | `contract.py` (CRITICAL + LAYER_*) · `agent_context_map.mjs` · `context_check.mjs` |
| fichiers de **test** touchant le compte/les listes | **3** | dont un qui affirme explicitement « des 17 champs » |
| **contrats YAML** à modifier | **0** | si le champ est optionnel — précédent `delegation_context` (RECOMMENDED, obligation levée) |
| **documentation** | 1 | `SCHEMA.md` |
| invariant `_verify_prompt_layer_rendered` | à ne pas casser | fige « tout champ `prompt` rempli est rendu » — une 4ᵉ couche doit rester hors de cette liste |

## Ce que P3(b) implique réellement
Ce n'est pas *« ajouter une ligne à une liste »*. C'est :
1. un **amendement de couche** (4ᵉ couche `verification`), du même ordre que celui ratifié le
   2026-08-02 ;
2. avec son **lecteur livré le même jour** (invariant du code + condition 1 du précédent) ;
3. en **régime advisory d'abord**, gate ensuite par décision séparée (condition 2) ;
4. **0 contrat YAML touché** si le champ est optionnel.

**Ni bloquant, ni trivial.** Le coût est concentré dans 3 fichiers de code, 3 de test, 1 doc — et
dans une décision de schéma qui a déjà son précédent de procédure.

```
status_by_surface:
  validator_permissiveness:  TESTED   # 0 garde contre un champ inconnu
  schema_amendment_precedent:TESTED   # SCHEMA.md §79, ratifié 2026-08-02
  layer_gap:                 TESTED   # aucune des 3 couches n'accueille consumption_evidence
  migration_blast_radius:    TESTED   # 3 code · 3 tests · 1 doc · 0 YAML
  p3b_decision:              BLOCKED  # arbitrage Pierre, sas 2
```
