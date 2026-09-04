# Lot 7 — Isoler le journal d'erreurs des tests

*Spec du 2026-09-04. V2 `C:\Users\Studio-Dev\Desktop\Studio2`, HEAD `ba2d046`. Décision Pierre du
2026-09-04 : les lignes de test ne se commitent pas comme preuves ; on isole la cause, on nettoie
plus tard dans un lot dédié. NO_CLAIM_ALLOWED.*

## 1. La cause, mesurée et non supposée

**Deux fichiers de test écrivent dans le journal de production `EVIDENCE/reports/error_journal/html.jsonl`**,
et ce sont les seuls. Mesure par bissection de la suite complète (4 passes, delta d'octets sur le
journal après chaque exécution) :

| ensemble | delta |
|---|---|
| moitié 1 (116 fichiers) | 0 |
| moitié 2 (117 fichiers) | +2928 |
| quart bas (58) | +2929 |
| quart haut (59) | 0 |
| huitième bas (29) | +2928 |
| **`test_mutation_path_repo_relative.py` seul** | **+537** |
| **`test_measure_tick.py` seul** | **+2392** |

La somme des deux (2929) restitue le delta de l'ensemble : il n'y a pas d'autre source.

**Le mécanisme est contre-intuitif, et c'est ce qui l'a rendu invisible.** Les deux tests
monkeypatchent `forge.driver._REPO_ROOT` sur leur `tmp_path`, pour exercer la branche « run_dir sous
le dépôt ». Or `ForgeDriver._journal_target()` (driver.py:2718-2734) décide ainsi :

```python
if self.journal_path is not None:      # injecté -> ce fichier exact
    return self.journal_path
try:
    self.run_dir.resolve().relative_to(_REPO_ROOT)
    return None                        # sous le repo -> journaux studio PAR DOMAINE
except ValueError:
    return self.run_dir / "error_journal.jsonl"   # hors repo -> local au run
```

En temps normal un `run_dir` sous `tmp_path` tombe dans la branche `ValueError` et le journal reste
local au run — c'est pourquoi la quasi-totalité de la suite est propre. Mais dès que `_REPO_ROOT` vaut
`tmp_path`, le `relative_to` réussit, la fonction rend `None`, et `studio_link.record_error` route vers
`DOMAIN_JOURNAL_DIR / "<domaine>.jsonl"` — le vrai fichier du Studio.

**Conséquence pour le choix de correctif** : ces deux tests exercent délibérément la branche
repo-relative. Leur passer un `journal_path` explicite supprimerait précisément ce qu'ils mesurent.
Le seul correctif qui n'abîme pas le test est d'isoler la **destination**.

**Ce que la fuite contient** (26 lignes au HEAD, 78 après l'investigation de ce jour) : `run_id` `jeu-1`
et `p3_alpha-1`, projet `jeu`, étapes `s9-build` et `s10a-oracle-code`. Des données de test dans
l'historique réel du Studio, que le pré-mortem relit ensuite comme des leçons de production.

## 2. Le mécanisme d'isolation existe déjà — il est incomplet

`forge/tests/conftest.py` porte une fixture `autouse`, `_isolate_evidence_writes` (l.52), qui redirige
déjà les destinations de preuve par défaut vers un dossier jetable : `forge.audit.DEFAULT_AUDIT`,
`forge.dispatch.DEFAULT_AUDIT`, `repair_dispatch.RESULTS_PATH`, `asset_dispatch.RESULTS_PATH`. Elle est
verrouillée par `forge/tests/test_evidence_isolation_fixture.py`, qui vérifie que la redirection est
**effective** et non seulement installée. Un second précédent ratifié existe pour
`knowledge_base/learning_curve.jsonl` (`_isolate_learning_curve_writes`, 2026-07-26).

Le journal d'erreurs n'a jamais été ajouté à ce périmètre. Le Lot 7 l'y ajoute : ce n'est pas un
mécanisme neuf, c'est un trou dans un mécanisme ratifié.

## 3. Le piège à ne pas répéter

`forge/learning_memory.py:53` fait `from forge.studio_link import DEFAULT_ERROR_JOURNAL,
DOMAIN_JOURNAL_DIR, GLOBAL_SCOPE` — un import **par valeur**, qui fige les chemins dans le module au
moment de l'import. Patcher `studio_link.DOMAIN_JOURNAL_DIR` seul laisserait la copie de
`learning_memory` pointer sur le fichier réel.

C'est exactement le défaut déjà documenté pour `DEFAULT_AUDIT`, où la fixture doit poser **les deux**
constantes à la **même** valeur, et où le test de périmètre existe précisément pour verrouiller ce
couplage. Le Lot 7 applique la même discipline : les deux modules, la même valeur, un test qui l'exige.

`studio_link.record_error` lit `DOMAIN_JOURNAL_DIR` **à chaque appel** (via `_domain_journal_path`,
l.330-332) et non à la définition : la substitution d'attribut de module est donc effective, comme
pour `RESULTS_PATH` et `_DEFAULT_LEARNING_CURVE_PATH`.

## 4. Ce que le Lot 7 fait

1. **Étendre `_isolate_evidence_writes`** : rediriger `DOMAIN_JOURNAL_DIR` et `DEFAULT_ERROR_JOURNAL`
   vers le dossier jetable déjà créé par la fixture, dans `studio_link` **et** `learning_memory`, à la
   même valeur. Le commentaire de la fixture nomme la mesure qui l'a motivée, comme les précédents.
2. **Étendre le test de périmètre** `test_evidence_isolation_fixture.py` : la destination effective
   d'un `record_error` sans `journal_path` n'est pas le fichier réel ; les copies des deux modules sont
   égales ; et une écriture réelle laisse le fichier de production **inchangé en octets**.
3. **Prouver par la mesure**, pas par la lecture : delta d'octets nul sur `html.jsonl` après
   `test_mutation_path_repo_relative.py` et `test_measure_tick.py` isolément, puis après la suite
   complète — les deux mêmes commandes qui ont servi à établir la cause.

**Hors périmètre, décidé par Pierre** : le nettoyage des lignes déjà écrites, qui se fera dans un lot
dédié une fois la cause supprimée. On ne nettoie jamais avant d'avoir retiré la cause — sans quoi la
trace repousse à la prochaine suite et l'on ne saurait pas si le correctif a tenu.

**Hors périmètre, non décidé** : `DEFAULT_TELEMETRY` reste volontairement hors du périmètre de la
fixture (delta mesuré nul, cf. commentaire existant) ; l'élargir « par symétrie » remplacerait une
mesure par une hypothèse.

## 5. Ce que ce lot ne prouve pas

- Que plus aucun test n'écrira jamais ailleurs : la garde ne couvre que les destinations mesurées, et
  c'est délibéré. Toute nouvelle destination devra être mesurée puis ajoutée, jamais présumée.
- Que les 78 lignes déjà présentes sont inoffensives : elles restent lues par le pré-mortem jusqu'au
  lot de nettoyage.
- Que le défaut structurel disparaît. Comme le dit déjà le test de périmètre : c'est un **confinement**,
  pas une guérison. Une fonction de haut niveau qui appelle un émetteur injectable sans exposer
  l'injection reste ce qu'elle est ; seule sa conséquence sur les artefacts durables disparaît.

```
software_verdict: OK · evidence_verdict: MECHANICAL_VALIDATION_ONLY · claim_verdict: NO_CLAIM_ALLOWED
```
