# Lot 8 — Nettoyer le journal d'erreurs de sa pollution de test

*Spec du 2026-09-04. V2 `C:\Users\Studio-Dev\Desktop\Studio2`, HEAD `3f457fa`. Option A retenue par
Pierre, avec vérification du pré-mortem avant/après. NO_CLAIM_ALLOWED.*

## 1. Ce que contient réellement le journal

`EVIDENCE/reports/error_journal/html.jsonl`, arbre de travail : **326 lignes, dont 13 réelles**.

| projet | lignes | run sur disque | brief | dossier `GAMES/` |
|---|---:|:---:|:---:|:---:|
| `jeu` (run_ids `jeu-1`, `p3_alpha-1`) | 313 | non | non | non |
| `runm_breakout` (`runm-breakout-20260902`) | 13 | oui | oui | oui |

**Le problème est antérieur à V2.** Le commit de migration `2769dc8` apportait déjà 117 lignes, toutes
de projet `jeu`. Le fichier versionné au HEAD en compte 247, dont 234 de test. Les sessions des Lots 5
à 7 ont ajouté à un tas préexistant, elles ne l'ont pas créé.

## 2. Le dommage réel, mesuré — et ce qu'il n'est pas

`studio_link.premortem` **filtre par projet**. Mesure du 2026-09-04, avant nettoyage :

| projet | lignes de pré-mortem |
|---|---:|
| `runm_breakout` | 5 (les siennes) |
| `v2_breakout_slice` | 0 |
| `jeu` | 5 |

Le canal transversal `_global_.jsonl` est **absent**, donc vide. **Aucun prompt de projet réel n'est
pollué aujourd'hui.** Il faut le dire clairement plutôt que de gonfler la justification du lot.

Le dommage est ailleurs, et il est réel :
- le journal est un **registre d'historique faux à 96 %** — il ne dit rien de l'activité du Studio ;
- `INDEX.generated.md` **annonce 326 entrées** pour le domaine `html`, chiffre qui ne mesure rien ;
- un futur projet réel qui porterait le nom `jeu` hériterait de 313 fausses leçons ;
- la règle posée par Pierre le 2026-09-04 : données de test et historique réel ne se mélangent pas.

## 3. Périmètre : un seul fichier, et c'est mesuré

Les autres artefacts de preuve ont été vérifiés et sont **propres** :

| artefact | état |
|---|---|
| `EVIDENCE/bundles/dispatch_audit.jsonl` | 227 lignes, **0 sans `run_id`** — les 1048 orphelines documentées en V1 n'ont pas migré |
| `forge_builder_runs.jsonl`, `forge_telemetry.jsonl`, `repair_results.jsonl` | hors du constat de pollution |
| `knowledge_base/learning_curve.jsonl` | 19 lignes, isolé depuis le 2026-07-26 |
| autres journaux de domaine (`_global_`, `forge`, `godot`, `playtest`, `python`, `rust`) | **absents** |

Le lot ne touche donc que `html.jsonl` et son index dérivé.

## 4. Critère de tri : mécanique, jamais un jugement sur les noms

> Est de **test** toute entrée dont le `project` n'a **ni run** sous `EVIDENCE/runs/`, **ni brief** sous
> `EVIDENCE/briefs/`, **ni dossier** sous `GAMES/`.

Appliqué au fichier actuel, ce critère sépare 313 contre 13 sans ambiguïté. Il est reproductible : le
plan le réexécute et compare ses comptes à ceux de cette spec.

**Limite déclarée** : le critère décrit l'état présent du dépôt. Un projet réel dont tous les artefacts
auraient été supprimés serait classé « test » à tort. Ici le cas ne se pose pas — `jeu` est le nom de
fixture d'une vingtaine de fichiers de test du driver — mais la limite est nommée plutôt que masquée.

## 5. Le geste : option A

**Réécrire `html.jsonl` en ne conservant que les entrées réelles**, puis régénérer `INDEX.generated.md`
par le mécanisme de production (`studio_link.write_journal_index`), jamais à la main.

Rien n'est perdu : les 313 lignes restent récupérables à `3f457fa:EVIDENCE/reports/error_journal/html.jsonl`,
et le message de commit nomme ce commit et ce chemin. Git **est** le mécanisme de conservation ; ajouter
un fichier de quarantaine (option B) créerait un artefact sans lecteur qu'il faudrait expliquer à chaque
lecture. La commande de réécriture est citée verbatim dans le plan et dans le message de commit :
l'opération est auditable et rejouable.

**Un seul geste, aucun mécanisme neuf.** Pas de script versionné : la cause a été supprimée au Lot 7
(fixture d'isolation), la pollution ne peut plus se reformer, un outil de nettoyage permanent n'aurait
aucun usage futur.

## 6. Preuve exigée

1. **Non-régression du pré-mortem, avant/après.** Empreinte capturée avant le geste :

   | projet | lignes | sha256 |
   |---|---:|---|
   | `runm_breakout` | 5 | `15cb8ceb5c126467d304d546b779b00b…` |
   | `v2_breakout_slice` | 0 | `e3b0c44298fc1c149afbf4c8996fb924…` (vide) |
   | `jeu` | 5 | `86b9a05755ae725489205adc9b71effb…` |

   Après nettoyage, `runm_breakout` et `v2_breakout_slice` doivent rendre **exactement les mêmes
   empreintes**. `jeu` doit tomber à 0 : c'est le seul changement attendu, et il est voulu.
2. **Comptes** : 326 → 13 lignes ; l'index annonce 13 entrées pour `html` au lieu de 326.
3. **Aucune entrée réelle perdue** : les 13 lignes conservées sont identiques, octet pour octet, aux 13
   lignes `runm_breakout` du fichier d'origine.
4. **T0 inchangé** : 2549 verts / 42 échecs, population comparée à celle du Lot 7. La suite lit ce
   journal (pré-mortem) ; un test qui rougirait après nettoyage dépendrait de données de test, ce qui
   serait un défaut à part entière.
5. **Récupérabilité vérifiée** : `git show 3f457fa:…/html.jsonl | wc -l` rend bien 247.

## 7. Ce que ce lot ne prouve pas

- Que le journal soit désormais *utile* : 13 lignes d'un seul run ne font pas un historique de studio.
- Que la pollution ne reviendra pas par un autre chemin que celui fermé au Lot 7 : seule la destination
  mesurée est isolée, toute nouvelle destination devra l'être à son tour, après mesure.
- Que les 13 lignes conservées soient de bonnes leçons : le lot trie sur la provenance, jamais sur la
  valeur.

```
software_verdict: OK · evidence_verdict: MECHANICAL_VALIDATION_ONLY · claim_verdict: NO_CLAIM_ALLOWED
```
