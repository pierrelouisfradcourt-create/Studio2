# LOT D-1-tuyau — EXÉCUTION

*2026-09-03 · GO Pierre. **V1 non modifié** (`58095ba9`). Baseline M ter intacte.*

## Ce qui a été corrigé — le TUYAU, pas le collecteur

```js
// forge/repair_step.mjs — l'enveloppe passée à repair_loop
- return { ok: r.ok, problems: r.problems || [] };          // 3 listes sur 4 JETÉES
+ return { ...r, ok: r.ok, problems: r.problems || [] };    // résultat COMPLET
```
Et les compteurs du reçu comptent désormais **la même chose que la boucle** :
```js
- PROBLEMS_BEFORE: avant.problems.length          // vue tronquée
+ PROBLEMS_BEFORE: tousLesFindings(avant).length  // les 4 listes
```
> Un reçu qui compte autrement que le mécanisme qu'il décrit **est un reçu qui ment sans mentir.**

## La preuve — chemin RÉEL, pas un objet fabriqué

Terrain reconstruit à partir des artefacts **réels** de RUN M (featuremap + wiremap, `couvre`
remis à vide = l'état que l'agent produit), puis `node repair_step.mjs s5-wiremap-contract` :

```
AVANT le lot   PROBLEMS_BEFORE  9 -> AFTER  0     « réparé »  ← faux : 9 fantômes créés
APRÈS le lot   PROBLEMS_BEFORE 25 -> AFTER 25     ESCALADE, CYCLES 0, aucun progrès déclaré
oracle relancé : FAIL, 0 sur 12 capacités couvertes
```

**La boucle ne peut plus déclarer un progrès en déplaçant le défaut.** Le remplissage de `couvre`
par des noms sans référent laisse le compte total inchangé — donc la garde de non-progression tire.

## Le test — et la leçon de méthode qu'il porte

`forge/repair_envelope.test.mjs`, 3 tests, **sur l'oracle RÉEL et des fichiers RÉELS** :
1. l'oracle rend bien quatre listes, et l'enveloppe amputée en perdrait N ;
2. **le déplacement est visible dans le compte** : `couvre` rempli de noms sans référent →
   `problems` tombe à 0, `couverture_fantome` monte, et le total **ne baisse pas** ;
3. `tousLesFindings` ignore `stats` et ne compte que des chaînes.

> **Le premier correctif D-1 était accompagné d'un test qui lui passait un objet fabriqué à la
> main, complet — alors que la production fournissait un objet amputé. Le test validait le
> collecteur sur une entrée que la chaîne ne produit jamais.** C'est pourquoi ce fichier n'utilise
> aucun littéral : il écrit de vrais fichiers et appelle le vrai oracle. La leçon est inscrite en
> tête du fichier.

## Non-régression
```
pytest forge/tests   2452 passed · 43 failed   (ligne de base inchangée)
node --test repair_loop        21 pass · 0 fail
node --test repair_step         0 échec
node --test repair_envelope      3 pass · 0 fail
```
Run_dir de test supprimé. **Baseline `EVIDENCE/runs/runm_breakout/` non touchée.**

```
status_by_surface:
  enveloppe_reparee:    TESTED   # résultat complet transmis
  compteurs_alignes:    TESTED   # 9->0 devient 25->25
  test_chemin_reel:     TESTED   # oracle réel, fichiers réels
  non_regression:       TESTED   # 2452 passed, 43 failed
  ESC-1:                BLOCKED  # prochaine
```
`software_verdict: OK` · `evidence_verdict: MECHANICAL_VALIDATION_ONLY` ·
`claim_verdict: NO_CLAIM_ALLOWED`
