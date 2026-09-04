# Lot 7 — Isoler le journal d'erreurs des tests : Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Qu'aucun test de `forge/tests/` n'écrive dans le journal d'erreurs de production, en comblant le trou d'un mécanisme d'isolation qui existe déjà et qui est déjà verrouillé par un test de périmètre.

**Architecture:** Aucun module neuf, aucune API neuve. On étend la fixture `autouse` `_isolate_evidence_writes` (`forge/tests/conftest.py:52`) — qui redirige déjà l'audit de dispatch et deux fichiers de résultats — pour qu'elle redirige aussi le journal d'erreurs et son index. On étend le test de périmètre `test_evidence_isolation_fixture.py` qui verrouille ce mécanisme. Le code de production n'est pas touché.

**Tech Stack:** Python 3.12 (`.venv` de Studio2), pytest, monkeypatch d'attributs de module.

**Spec:** `docs/superpowers/specs/2026-09-04-lot7-isolation-journal-tests-design.md`.

## Global Constraints

- Dépôt : `C:\Users\Studio-Dev\Desktop\Studio2`. V1 en lecture seule. `git -C` nomme toujours son cwd.
- Aucun commit sans GO explicite de Pierre. Aucun push. Un GO = une commande.
- **`tests/**` est zone protégée (CLAUDE.md) : ce lot modifie `forge/tests/conftest.py` et `forge/tests/test_evidence_isolation_fixture.py`. Le GO d'ouverture du Lot 7 vaut pour ces deux fichiers, nommés ici ; tout autre fichier de test demande un GO séparé.**
- **Ne pas toucher au code de production.** Si le correctif semble exiger une modification de `studio_link.py` ou `driver.py`, s'arrêter et le signaler : ce serait changer le comportement réel du Studio pour un problème de test.
- **Ne rien nettoyer.** Les 78 lignes déjà présentes dans `EVIDENCE/reports/error_journal/html.jsonl` restent en place (décision Pierre : lot dédié, après suppression de la cause). Elles ne sont pas commitées.
- Interpréteur : `.venv/Scripts/python.exe`. Tests : `-q -p no:cacheprovider -m "not gpu_window"`.
- `encoding="utf-8"` explicite sur tout accès fichier.

## Mesure de départ (établie, à reproduire à l'identique en fin de lot)

```
test_mutation_path_repo_relative.py   html.jsonl  +537
test_measure_tick.py                  html.jsonl  +2392
suite complète                        html.jsonl  +2929  (= la somme, aucune autre source)
```

Commande de mesure, utilisée telle quelle partout dans ce plan :

```bash
J="EVIDENCE/reports/error_journal/html.jsonl"; b=$(wc -c < "$J")
.venv/Scripts/python.exe -m pytest <cible> -q -p no:cacheprovider >/dev/null 2>&1
echo "delta = $(( $(wc -c < "$J") - b )) octets"
```

---

### Task 1: Verrouiller par le test de périmètre (rouge d'abord)

**Files:**
- Modify: `forge/tests/test_evidence_isolation_fixture.py` (ajouts en fin de fichier)

**Interfaces:**
- Consumes: `forge.studio_link` (importé `SL`), `forge.learning_memory` (à importer `LM`), la fixture `_isolate_evidence_writes` du conftest.
- Produces: quatre tests qui échouent tant que la fixture ne redirige pas le journal.

- [ ] **Step 1: Écrire les tests qui échouent**

Ajouter en fin de `forge/tests/test_evidence_isolation_fixture.py`, avant rien d'autre :

```python
# --- Lot 7 : le JOURNAL D'ERREURS et son index (2026-09-04) ---------------------------------
# MESURE qui a motivé cet ajout — bissection de la suite complète, delta d'octets sur
# `EVIDENCE/reports/error_journal/html.jsonl` : test_measure_tick +2392,
# test_mutation_path_repo_relative +537, somme = le delta de la suite entière (+2929).
#
# LE MÉCANISME, contre-intuitif et c'est pourquoi il est resté invisible : ces deux tests
# monkeypatchent `forge.driver._REPO_ROOT` sur leur tmp_path pour exercer la branche
# « run_dir sous le dépôt ». `ForgeDriver._journal_target()` réussit alors son `relative_to`,
# rend None (« route par domaine »), et `record_error` écrit dans le VRAI journal du Studio.
# Leur passer un `journal_path` supprimerait exactement ce qu'ils mesurent : c'est la
# DESTINATION qu'il faut isoler, pas l'appel.
#
# TROIS substitutions, pas une : `DOMAIN_JOURNAL_DIR` et `DEFAULT_ERROR_JOURNAL` sont des
# constantes calculées À L'IMPORT (patcher `FORGE_REPORTS` ne les atteint pas), tandis que
# `write_journal_index` lit `FORGE_REPORTS` À L'APPEL (`root = reports_dir or FORGE_REPORTS`).

JOURNAL_REEL = SL.FORGE_REPORTS / "error_journal" / "html.jsonl"
INDEX_REEL = SL.FORGE_REPORTS / "error_journal" / "INDEX.generated.md"


def test_la_destination_du_JOURNAL_n_est_pas_le_fichier_reel():
    """`record_error` sans `journal_path` route par domaine : c'est CE chemin qui fuyait."""
    assert SL._domain_journal_path("html") != JOURNAL_REEL, \
        "la fixture ne redirige pas le journal d'erreurs"


def test_les_DEUX_copies_du_chemin_de_journal_sont_patchees_ENSEMBLE():
    """LE test qui vaut ce lot, jumeau de celui des deux `DEFAULT_AUDIT`.
    `forge.learning_memory` fait `from forge.studio_link import DOMAIN_JOURNAL_DIR,
    DEFAULT_ERROR_JOURNAL` — un import PAR VALEUR, qui fige les chemins dans son propre
    espace de noms. N'en patcher qu'un laisse l'autre pointer sur le fichier réel."""
    assert LM.DOMAIN_JOURNAL_DIR == SL.DOMAIN_JOURNAL_DIR, \
        "les deux copies ont divergé : learning_memory lit encore le vrai journal"
    assert LM.DEFAULT_ERROR_JOURNAL == SL.DEFAULT_ERROR_JOURNAL
    assert SL.DOMAIN_JOURNAL_DIR != JOURNAL_REEL.parent


def test_l_INDEX_du_journal_n_est_pas_regenere_dans_la_production():
    """`write_journal_index` lit `FORGE_REPORTS` À L'APPEL : une troisième substitution,
    distincte des deux constantes ci-dessus (que patcher FORGE_REPORTS n'atteindrait pas)."""
    assert SL.write_journal_index() != INDEX_REEL


def test_une_ecriture_de_journal_SANS_injection_n_atteint_PAS_la_production(tmp_path):
    """Le cas exact du résidu : `record_error` appelé sans `journal_path`, comme le fait
    `ForgeDriver._journal_error` quand `_journal_target()` rend None."""
    avant = (_empreinte(JOURNAL_REEL), _empreinte(INDEX_REEL))

    SL.record_error("lot7-1", "s9-build", "fuite de test", "jeu", domain="html")
    SL.write_journal_index()

    assert (_empreinte(JOURNAL_REEL), _empreinte(INDEX_REEL)) == avant, \
        "une écriture non injectée a atteint le journal de production"
    redirige = SL._domain_journal_path("html")
    assert redirige.exists(), "rediriger n'est pas jeter : la preuve doit exister ailleurs"
    ligne = json.loads(redirige.read_text(encoding="utf-8").splitlines()[-1])
    assert ligne["run_id"] == "lot7-1" and ligne["project"] == "jeu"
```

Ajouter l'import manquant en tête du fichier, à côté de `import forge.studio_link as SL` :

```python
import forge.learning_memory as LM
```

- [ ] **Step 2: Les faire échouer**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_evidence_isolation_fixture.py -q -p no:cacheprovider`
Expected: les 4 nouveaux tests ÉCHOUENT (la fixture ne redirige pas encore le journal), les tests préexistants restent verts.

**Vérification indispensable** : `test_une_ecriture_de_journal_SANS_injection...` doit échouer en constatant que le fichier réel a grossi — donc **il aura écrit dans le vrai journal**. C'est attendu et c'est le prix d'un rouge honnête ; ces lignes partiront avec le lot de nettoyage. Noter le nombre de lignes ajoutées pour le rapport final.

---

### Task 2: Étendre la fixture d'isolation

**Files:**
- Modify: `forge/tests/conftest.py` (imports, corps de `_isolate_evidence_writes`)

**Interfaces:**
- Produces: la fixture redirige `DOMAIN_JOURNAL_DIR`, `DEFAULT_ERROR_JOURNAL` (dans `studio_link` **et** `learning_memory`) et `FORGE_REPORTS` (dans `studio_link`) vers le dossier jetable déjà créé.

- [ ] **Step 1: Ajouter les deux imports**

Dans le bloc d'imports de `forge/tests/conftest.py`, sous `import forge.repair_dispatch as _repair_dispatch` :

```python
import forge.learning_memory as _learning_memory  # noqa: E402 — copies PAR VALEUR, cf. fixture
import forge.studio_link as _studio_link  # noqa: E402
```

- [ ] **Step 2: Étendre le corps de la fixture**

Dans `_isolate_evidence_writes`, après `monkeypatch.setattr(_asset_dispatch, "RESULTS_PATH", ...)` :

```python
    # Lot 7 (2026-09-04) : le JOURNAL D'ERREURS. Mesure par bissection de la suite complète —
    # test_measure_tick +2392 octets, test_mutation_path_repo_relative +537, somme = le delta
    # de la suite entière : ces deux-là, et personne d'autre. Ils monkeypatchent
    # `driver._REPO_ROOT` sur leur tmp_path pour exercer la branche « run_dir sous le dépôt » ;
    # `_journal_target()` rend alors None (« route par domaine ») et l'écriture part dans le
    # VRAI journal du Studio. Leur passer un `journal_path` supprimerait ce qu'ils mesurent :
    # c'est la DESTINATION qu'on isole, jamais l'appel.
    #
    # TROIS substitutions, pour trois raisons distinctes :
    #  - `DOMAIN_JOURNAL_DIR` : lu À CHAQUE APPEL par `_domain_journal_path` — c'est la cible
    #    réelle de `record_error` sans `journal_path` ;
    #  - `DEFAULT_ERROR_JOURNAL` : le monolithe historique, relu en repli par `premortem` ;
    #  - `FORGE_REPORTS` : lu À L'APPEL par `write_journal_index` (`root = reports_dir or
    #    FORGE_REPORTS`), donc l'index ne se régénère pas dans la production. Patcher
    #    `FORGE_REPORTS` seul NE SUFFIRAIT PAS : les deux constantes ci-dessus sont calculées
    #    à l'import et ne changeraient pas.
    #
    # ET DANS LES DEUX MODULES, à la MÊME valeur — `forge.learning_memory` fait
    # `from forge.studio_link import DOMAIN_JOURNAL_DIR, DEFAULT_ERROR_JOURNAL`, un import PAR
    # VALEUR qui fige les chemins dans son propre espace de noms. Même piège que les deux
    # `DEFAULT_AUDIT` ci-dessus, et `test_evidence_isolation_fixture` verrouille les deux.
    journal_dir = cible / "error_journal"
    monolithe = cible / "forge_error_journal.jsonl"
    monkeypatch.setattr(_studio_link, "FORGE_REPORTS", cible)
    monkeypatch.setattr(_studio_link, "DOMAIN_JOURNAL_DIR", journal_dir)
    monkeypatch.setattr(_studio_link, "DEFAULT_ERROR_JOURNAL", monolithe)
    monkeypatch.setattr(_learning_memory, "DOMAIN_JOURNAL_DIR", journal_dir)   # MÊME valeur
    monkeypatch.setattr(_learning_memory, "DEFAULT_ERROR_JOURNAL", monolithe)  # MÊME valeur
```

- [ ] **Step 3: Les faire passer**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_evidence_isolation_fixture.py -q -p no:cacheprovider`
Expected: tous verts, y compris les tests préexistants (notamment `test_la_TELEMETRIE_n_est_PAS_redirigee`, qui doit rester vert : `DEFAULT_TELEMETRY` est une constante d'import, patcher `FORGE_REPORTS` ne l'atteint pas).

- [ ] **Step 4: Prouver la fermeture sur les deux fichiers qui fuyaient**

```bash
J="EVIDENCE/reports/error_journal/html.jsonl"
for f in test_measure_tick test_mutation_path_repo_relative; do
  b=$(wc -c < "$J")
  .venv/Scripts/python.exe -m pytest "forge/tests/$f.py" -q -p no:cacheprovider >/dev/null 2>&1
  echo "$f : delta = $(( $(wc -c < "$J") - b )) octets"
done
```

Expected: `delta = 0` pour les deux (mesure de départ : +2392 et +537).

Vérifier aussi l'index : `git -C <V2> diff --numstat -- EVIDENCE/reports/error_journal/INDEX.generated.md` ne doit pas bouger entre avant et après ces deux exécutions.

- [ ] **Step 5: Vérifier que les deux tests mesurent toujours ce qu'ils mesuraient**

Run: `.venv/Scripts/python.exe -m pytest forge/tests/test_measure_tick.py forge/tests/test_mutation_path_repo_relative.py -q -p no:cacheprovider`
Expected: tous verts. Une isolation qui ferait rougir les tests qu'elle protège déplacerait le défaut au lieu de le contenir — c'est exactement la leçon déjà écrite dans la fixture à propos de `tmp_path_factory`.

---

### Task 3: Suite complète, T0, handoff, fiche de commit

**Files:**
- Modify: `00_CURRENT_CONTEXT.md`

- [ ] **Step 1: Delta nul sur la suite complète**

```bash
J="EVIDENCE/reports/error_journal/html.jsonl"; b=$(wc -c < "$J")
.venv/Scripts/python.exe -m pytest forge/tests/ -m "not gpu_window" -q -p no:cacheprovider \
  --deselect forge/tests/test_observer_integration_real.py 2>&1 | tail -3
echo "delta suite complète = $(( $(wc -c < "$J") - b )) octets"
```

Expected: `delta = 0` (mesure de départ : +2929), et la population d'échecs T0 **inchangée**. Comparer la liste des `FAILED` à celle du Lot 6 (42 échecs, population V1 classée au Lot 0) :

```bash
diff <(grep "^FAILED" <sortie_lot6> | sort) <(grep "^FAILED" <sortie_lot7> | sort) && echo IDENTIQUE
```

Un échec neuf, même sur un fichier non touché, arrête le lot : la fixture est `autouse` et atteint toute la suite.

- [ ] **Step 2: Corriger le handoff**

Le bloc « À faire au prochain lot » de `00_CURRENT_CONTEXT.md` désigne cinq fichiers de test choisis sur leur nom et propose de leur passer un `journal_path`. **La mesure a falsifié les deux affirmations** : aucun des cinq ne fuit, et un `journal_path` supprimerait ce que les vrais coupables mesurent. Remplacer ce bloc par l'état réel : cause nommée (deux fichiers, `driver._REPO_ROOT` patché), correctif appliqué (fixture étendue, périmètre verrouillé), et ce qui reste (nettoyage des lignes déjà écrites, lot dédié). Garder le fichier sous 100 lignes, **compte vérifié après édition** (erreur commise au Lot 6 : un chiffre annoncé sans être mesuré).

- [ ] **Step 3: Fiche de commit pour Pierre (aucun commit sans GO)**

Périmètre : `forge/tests/conftest.py`, `forge/tests/test_evidence_isolation_fixture.py`, `00_CURRENT_CONTEXT.md`, `docs/superpowers/specs/2026-09-04-lot7-*.md`, `docs/superpowers/plans/2026-09-04-lot7-*.md`. **Hors périmètre, à ne pas ajouter** : `EVIDENCE/reports/error_journal/html.jsonl` et `INDEX.generated.md` — les lignes de test restent non commitées, y compris celles ajoutées par le rouge de la Task 1.

Message proposé :

```
test(v2): Lot 7 — isoler le journal d'erreurs des tests : la fixture d'isolation couvre enfin le journal et son index (delta mesuré 2929 -> 0 octets)
```

Rapporter : la mesure avant/après, la population T0 comparée, le nombre de lignes que le rouge de la Task 1 a ajoutées au journal réel, et le fait que le nettoyage reste un lot dédié.

---

## Self-review

- **Couverture de la spec** : §1 cause mesurée (rappelée dans les commentaires de code, Tasks 1-2) · §2 mécanisme existant étendu (Task 2) · §3 piège de l'import par valeur (test dédié Task 1, double substitution Task 2) · §4 les trois gestes (Tasks 1-2-3) · §5 ce qui n'est pas prouvé (rappelé dans la fiche de commit).
- **Placeholders** : aucun ; chaque étape porte son code ou sa commande exacte.
- **Cohérence des noms** : `_studio_link`, `_learning_memory`, `SL`, `LM`, `JOURNAL_REEL`, `INDEX_REEL`, `journal_dir`, `monolithe` — identiques entre le conftest, le test de périmètre et le plan.
- **Trois pièges nommés pour ne pas être réintroduits** : (1) patcher `FORGE_REPORTS` seul n'atteint pas les deux constantes calculées à l'import ; (2) patcher `studio_link` seul laisse la copie par valeur de `learning_memory` sur le vrai chemin ; (3) le rouge de la Task 1 écrit réellement dans le journal de production — c'est assumé et compté, jamais masqué.
