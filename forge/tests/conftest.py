import sys
from pathlib import Path

import pytest

# forge/tests/conftest.py -> parents[2] == scripts/  (so `forge` is importable)
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

import subprocess  # noqa: E402

from forge import learning_hook  # noqa: E402 — après sys.path.insert, volontairement
from forge import driver as _driver_module  # noqa: E402
from forge.driver import ForgeDriver  # noqa: E402

# `forge.dispatch` est importé ICI, volontairement, et pas seulement patché s'il est déjà
# chargé : `audit._resolve_audit_path` lit `sys.modules.get("forge.dispatch")` À CHAQUE
# APPEL. Un module chargé APRÈS la fixture réintroduirait son ré-export NON patché (le vrai
# chemin), qui reprendrait la main sur la redirection. Sans effet sur
# `test_hook_guard_stdlib_only` : ce test mesure `sys.modules` dans un SOUS-PROCESSUS frais.
import forge.audit as _audit  # noqa: E402
import forge.dispatch as _dispatch  # noqa: E402
import forge.learning_memory as _learning_memory  # noqa: E402 — copies PAR VALEUR, cf. fixture
import forge.repair_dispatch as _repair_dispatch  # noqa: E402
import forge.studio_link as _studio_link  # noqa: E402
from forge.asset_producer import asset_dispatch as _asset_dispatch  # noqa: E402


#: Modules AUTORISÉS à observer les artefacts de preuve RÉELS — l'isolation ci-dessous ne
#: s'y applique pas. Un seul aujourd'hui, et c'est une condition de VALIDITÉ, pas une
#: commodité : `test_evidence_isolation` prouve qu'un appel INJECTÉ n'atteint pas la
#: production. Sous isolation, ce test resterait vert même si la transmission d'`audit_path`
#: était retirée — la garde masquerait exactement la régression qu'il existe pour détecter.
MODULES_OBSERVANT_LA_PREUVE_REELLE = frozenset({"test_evidence_isolation"})


# --- garde générique : aucune écriture de test dans un artefact de preuve RÉEL (2026-08-19) ---
# MESURE qui a motivé cette garde — suite COMPLÈTE, deltas d'octets sur `EVIDENCE/bundles/` :
# `dispatch_audit.jsonl` +4524, `repair_results.jsonl` +8590. Tout le résidu vient de 9 modules
# qui pilotent `run_real` DE BOUT EN BOUT : ils passent par le site d'appel INTERNE (dans
# l'exécuteur), qui n'a aucune destination à transmettre — et qui NE DOIT PAS en avoir, car en
# production ces écritures doivent atteindre le vrai fichier. Exposer `audit_path` plus haut
# (2d418b3) ne pouvait donc pas les atteindre : c'est un CONFINEMENT, pas une guérison.
#
# PIÈGE PROUVÉ PAR EXÉCUTION — patcher `forge.audit.DEFAULT_AUDIT` SEUL est DÉFAIT :
# `_resolve_audit_path` privilégie la surcharge `forge.dispatch` SI ELLE DIFFÈRE, et le
# ré-export la fait différer. Les DEUX sont donc posées à la MÊME valeur : la branche
# `override != DEFAULT_AUDIT` devient fausse et le résolveur retombe sur la valeur redirigée,
# que `forge.dispatch` soit chargé ou non.
#
# Les deux `RESULTS_PATH` sont relues à chaque appel (`path = results_path or RESULTS_PATH`),
# donc substituables de la même façon. `studio_link.DEFAULT_TELEMETRY` est VOLONTAIREMENT
# absente : son delta mesuré est ZÉRO — l'ajouter « par symétrie » élargirait la garde sur une
# hypothèse au lieu d'une mesure (test_evidence_isolation_fixture verrouille ce périmètre).
@pytest.fixture(autouse=True)
def _isolate_evidence_writes(request, tmp_path_factory, monkeypatch):
    """Redirige les destinations de preuve par défaut vers un dossier jetable, pour tout
    test de forge/tests/ — même ceux qui ignorent qu'ils écrivent.

    `tmp_path_factory`, PAS `tmp_path` : la destination doit être un FRÈRE du répertoire de
    travail du test, jamais un enfant. Première version mesurée — un `tmp_path/_isolated_
    evidence` faisait rougir 4 tests de `test_standard_oracles` qui SCANNENT leur propre
    `tmp_path` et exigent qu'il soit vide. Une garde qui pollue l'espace qu'elle protège
    déplace le défaut au lieu de le contenir.
    """
    if request.module.__name__.rsplit(".", 1)[-1] in MODULES_OBSERVANT_LA_PREUVE_REELLE:
        return
    cible = tmp_path_factory.mktemp("preuve_isolee")
    audit = cible / "dispatch_audit.jsonl"
    monkeypatch.setattr(_audit, "DEFAULT_AUDIT", audit)
    monkeypatch.setattr(_dispatch, "DEFAULT_AUDIT", audit)  # MÊME valeur, cf. piège ci-dessus
    monkeypatch.setattr(_repair_dispatch, "RESULTS_PATH", cible / "repair_results.jsonl")
    monkeypatch.setattr(_asset_dispatch, "RESULTS_PATH", cible / "asset_results.jsonl")
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



# --- garde générique : aucun sous-processus Observer RÉEL par défaut (2026-08-29) -------
# MESURE qui a motivé cette garde (audit du soir 2026-08-28, GO Pierre 2026-08-29) : chaque
# `ForgeDriver.run()` de test qui atteint DONE appelle `_trigger_observer_best_effort`, qui
# appelle `self.observer_runner` — lequel vaut `_default_observer_runner` DÈS QU'AUCUN runner
# n'est injecté (driver.py : `observer_runner or self._default_observer_runner`). Ce défaut
# lance le VRAI `scripts/observer/cli.py` en sous-processus (~30-40 s, re-parse de ~563 Mo de
# transcripts). 0/19 fichiers lourds de la suite n'injectait de runner : ~110 spawns par
# passe, 92 % des 76 min de la suite complète. La docstring de `_trigger_observer_best_effort`
# affirmait le contraire (« les tests fournissent un runner factice ») — elle décrit désormais
# le mécanisme réel, c'est-à-dire CETTE fixture.
#
# La substitution porte sur l'ATTRIBUT DE CLASSE `ForgeDriver._default_observer_runner`, pas
# sur les instances : elle atteint donc TOUT driver de la suite, y compris ceux construits par
# des tests qui ignorent l'existence de l'Observer — et elle laisse INTACT le `or` du
# constructeur, donc un `observer_runner=` explicite continue de primer. C'est ce qui garde
# `test_observer_trigger.py` (le fichier dédié au branchement, qui injecte TOUJOURS son
# runner) valide et vert sans la moindre modification.
#
# Le stub rend la forme MINIMALE consommée par `_trigger_observer_best_effort` : un objet
# porteur de `.returncode` (un `CompletedProcess` réel, comme celui que `run_oracle` rend en
# production), returncode=0 — donc `state["transition"] = "OK"` reste posé exactement comme
# avant. Aucune sémantique observable du run n'est dégradée, seul le sous-processus disparaît.
#
# OPT-OUT : `@pytest.mark.real_observer` — un test marqué retrouve le runner de PRODUCTION.
# Un SEUL test l'utilise (`test_observer_integration_real.py`, marqué aussi `t1_integration`),
# et c'est l'étage T1 qui prouve que le branchement Driver -> vrai Observer existe réellement.
@pytest.fixture(autouse=True)
def _neutralise_observer_par_defaut(request, monkeypatch):
    """Neutralise le lancement du VRAI Observer pour tout test de forge/tests/ qui
    n'injecte pas son propre `observer_runner` — sauf `@pytest.mark.real_observer`."""
    if request.node.get_closest_marker("real_observer") is not None:
        return

    def _stub_observer_runner(self, project):
        return subprocess.CompletedProcess(
            args=["stub", "observer", "--project", str(project)], returncode=0,
            stdout="", stderr="",
        )

    monkeypatch.setattr(ForgeDriver, "_default_observer_runner", _stub_observer_runner)


# --- garde générique : aucun sous-processus Node `check_artbible.mjs` RÉEL par défaut
# (fiche 3, sas ratifié Pierre 2026-08-30) -----------------------------------------------
# MESURE : depuis la fiche 3, `ForgeDriver._run_llm_gated` appelle `self.artbible_check_runner`
# (défaut `oracle.run_check_artbible`, un VRAI spawn Node) après CHAQUE étape s2.5-artbible/-r2
# rendue verte. Tout test PRÉEXISTANT qui atteint s2.5-artbible avec un exécuteur factice — qui
# n'écrit jamais de VRAI art_bible.md/asset_requests.json sur disque, ces fichiers étant produits
# par l'AGENT via Write en production, jamais par le driver ni son exécuteur de test — ferait
# échouer la nouvelle gate sur un défaut hors du périmètre de ce que le test mesure (node absent
# du poste CI, ou fichiers illisibles). Même patron que `_neutralise_observer_par_defaut` :
# substitution du NOM DE MODULE `forge.driver.run_check_artbible` (résolu par `__init__` à
# CHAQUE construction via `artbible_check_runner or run_check_artbible` — jamais figé à
# l'import), donc atteint tout driver construit après cette fixture, et laisse INTACT le `or`
# du constructeur : un `artbible_check_runner=` explicite (test_artbible_check.py, le fichier
# dédié au branchement) continue de primer.
@pytest.fixture(autouse=True)
def _neutralise_artbible_check_par_defaut(monkeypatch):
    """Neutralise le VRAI spawn Node `check_artbible.mjs` pour tout test qui n'injecte pas
    son propre `artbible_check_runner` — rend un PASS structurel neutre (MEASURED/OK)."""
    def _stub_artbible_check_runner(art_bible_path, asset_requests_path, timeout=120):
        return {
            "status": "MEASURED", "pass": True, "verdict": "OK", "findings": [],
            "coverage": {"checked": False, "missing": [], "satisfied": []},
            "resolution_stats": {"ok": 0, "blocked": 0, "total": 0},
        }
    monkeypatch.setattr(_driver_module, "run_check_artbible", _stub_artbible_check_runner)


def pytest_configure(config):
    """Enregistre les marqueurs de la suite Forge (le dépôt n'a pas de pytest.ini/pyproject :
    sans cet enregistrement, chaque marqueur émettrait un PytestUnknownMarkWarning)."""
    config.addinivalue_line(
        "markers",
        "real_observer: laisse le VRAI scripts/observer/cli.py être lancé "
        "(désactive la fixture _neutralise_observer_par_defaut)",
    )
    config.addinivalue_line(
        "markers",
        "t1_integration: test d'intégration lent (sous-processus réel) — étage T1",
    )
    config.addinivalue_line(
        "markers",
        "gpu_window: exige un binaire Godot et une fenêtre GPU réelle",
    )


# --- garde générique : aucune écriture durable sur learning_curve.jsonl (2026-07-26) ---
# Régression détectée par vérification indépendante : driver.py (_record_learning_advisory)
# appelle `learning_hook.record_learning_for_subject` SANS jamais passer `target_path`. Tout
# test PRÉEXISTANT qui construit un ForgeDriver réel (is_game=True, game_dir réel) et laisse
# s10a-oracle-code atteindre OK — sans rien savoir de l'existence de ce hook — déclenchait
# donc une écriture RÉELLE sur knowledge_base/learning_curve.jsonl (fichier durable,
# versionné) à chaque exécution de la suite (ex. test_standard_wiring_corrections.py,
# +1 ligne `{"subject":{"type":"game","id":"g"},...}` par run pytest).
#
# `_DEFAULT_LEARNING_CURVE_PATH` (forge/learning_hook.py) est un ATTRIBUT DE MODULE
# relu à chaque appel de `record_learning_for_subject` (jamais une valeur de paramètre figée
# à la définition) précisément pour rester monkeypatchable ici, GÉNÉRIQUEMENT — cette fixture
# `autouse=True` protège TOUTE la suite forge/tests/, qu'un test connaisse ou non
# l'existence du hook, sans neutraliser le mécanisme lui-même (record_learning_for_subject
# continue de mesurer réellement reuse_ratio et d'écrire un JSONL valide — seule LA CIBLE
# change, vers un fichier jetable propre à chaque test). L'écriture réelle en production
# (driver.py hors pytest, backfill_learning_curve.mjs) n'est pas affectée : seul l'attribut
# de module est substitué, et seulement le temps de la suite de tests.
@pytest.fixture(autouse=True)
def _isolate_learning_curve_writes(tmp_path, monkeypatch):
    """Redirige le défaut d'écriture de la courbe d'apprentissage vers un fichier jetable,
    pour tout test de forge/tests/ — même ceux qui ignorent l'existence du hook."""
    monkeypatch.setattr(
        learning_hook, "_DEFAULT_LEARNING_CURVE_PATH",
        tmp_path / "_isolated_learning_curve.jsonl",
    )


# --- ajout minimal de fixture (P2 solvabilité, 2026-07-14) -------------------------
# La garde check_solvability_wired (gating s10a pour un JEU, miroir de la garde e2e)
# exige solvability.mjs câblé dans run-oracle.mjs. Les mini-jeux fabriqués par les
# helpers `_game_dir` des tests driver ANTÉRIEURS (test_driver_mutation.py,
# test_verify_run_mutation.py) n'en avaient pas — comme les fixtures des jeux réels
# (GAMES/breakout, collect_runner) en ont un, ce complément aligne les mini-jeux de
# test sur la réalité SANS toucher aucune assertion existante (exception fixture
# déclarée). Les nouveaux tests qui veulent un jeu SANS solvabilité utilisent leurs
# propres helpers (nom différent de `_game_dir`), jamais couverts par ce shim.


@pytest.fixture(autouse=True)
def _complete_game_fixture_solvability(request, monkeypatch):
    """Complète les helpers `_game_dir` hérités avec un harnais de solvabilité câblé."""
    original = getattr(request.module, "_game_dir", None)
    if original is None:
        return

    def _avec_solvabilite(tmp_path):
        g = original(tmp_path)
        solv = g / "solvability.mjs"
        if not solv.exists():
            # `won` CALCULÉ (pas un littéral) : depuis le renfort R1
            # (check_harness_no_hardcoded_flags, câblé au driver s10a), un flag de
            # succès écrit en dur rougirait ce fixture lui-même — même exigence
            # qu'un vrai harnais.
            solv.write_text(
                "const moves = [1];\nconst bot = { won: moves.length > 0 };\n"
                "if (!bot.won) process.exit(1);\n",
                encoding="utf-8")
            runner = g / "run-oracle.mjs"
            if runner.exists():
                runner.write_text(
                    runner.read_text(encoding="utf-8")
                    + 'spawn("node", ["solvability.mjs"]);\n',
                    encoding="utf-8")
        return g

    monkeypatch.setattr(request.module, "_game_dir", _avec_solvabilite)
