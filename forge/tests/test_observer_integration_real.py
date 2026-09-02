"""Étage T1 — LE SEUL test autorisé à lancer le VRAI Observer (GO Pierre 2026-08-29).

Toute la suite `forge/tests/` est neutralisée par la fixture autouse
`_neutralise_observer_par_defaut` (conftest.py) : plus aucun test ne lance
`scripts/observer/cli.py` en sous-processus. Une neutralisation sans contre-partie
supprimerait la seule preuve que le branchement Driver -> Observer existe encore.
CE fichier est cette contre-partie, et il est le seul : un unique test, marqué
`real_observer` (opt-out de la fixture) + `t1_integration` (étage lent), qui laisse
partir le VRAI `_default_observer_runner` de production.

Ce qu'il prouve, par exécution et non par existence :
  - `ForgeDriver._default_observer_runner` lance réellement
    `<python> scripts/observer/cli.py --project <projet>` et obtient returncode 0 ;
  - le chemin de fin de run (`_trigger_observer_best_effort`) pose bien
    `state["transition"] == "OK"` à partir de ce sous-processus RÉEL ;
  - l'Observer a bien écrit son rapport (`observer_run.json` + `RECONSTRUCTION.md`)
    sous `EVIDENCE/reports/observer/<projet>/`.

BUDGET : ~30-60 s. C'est son étage, et c'est la raison pour laquelle il est SEUL.

DESTINATION / NETTOYAGE : `scripts/observer/cli.py` accepte bien un `--out`, mais
`_default_observer_runner` (driver.py) ne le passe pas — le rediriger ici
reviendrait à tester un runner que la production n'utilise pas, donc à ne plus
rien prouver du branchement réel. La sortie va donc à sa destination RÉELLE,
`EVIDENCE/reports/observer/<projet>/`, sous un nom de projet-fixture dédié, et le
`finally` la supprime intégralement : aucun répertoire parasite ne survit au test
(leçon `dont_clean_before_the_cause` / répertoires parasites de l'Observer).

NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import shutil
from pathlib import Path

import pytest

from forge.driver import ForgeDriver

#: forge/tests/ -> parents[3] == racine du dépôt
_REPO_ROOT = Path(__file__).resolve().parents[2]

#: Nom de PROJET-FIXTURE dédié à ce test — jamais un projet réel du dépôt, pour que
#: le nettoyage `finally` ne puisse jamais emporter une sortie d'Observer légitime.
_PROJET_FIXTURE = "forge_t1_observer_integration"


@pytest.mark.t1_integration
@pytest.mark.real_observer
def test_le_driver_lance_reellement_l_observer(tmp_path):
    sortie = _REPO_ROOT / "EVIDENCE" / "reports" / "observer" / _PROJET_FIXTURE
    assert not sortie.exists(), (
        f"{sortie} existe avant le test : un run précédent n'a pas nettoyé, "
        "ou le nom de projet-fixture entre en collision avec un projet réel."
    )

    driver = ForgeDriver(
        _PROJET_FIXTURE, f"{_PROJET_FIXTURE}-1",
        run_dir=tmp_path / "run", profile="micro",
        lessons_path=tmp_path / "lessons.jsonl",
        # AUCUN observer_runner injecté : c'est tout l'objet du test.
    )
    # La fixture d'opt-out doit avoir rendu le défaut de PRODUCTION.
    assert driver.observer_runner == driver._default_observer_runner

    state = {"run_id": f"{_PROJET_FIXTURE}-1", "run_status": "DONE", "steps": {}}
    try:
        driver._trigger_observer_best_effort(state)

        # `_trigger_observer_best_effort` est best-effort : il n'a PAS le droit de
        # lever. Un échec du sous-processus se lit dans `transition`, et c'est
        # exactement ce que ce test doit refuser silencieusement d'accepter.
        assert state["transition"] == "OK", (
            f"le vrai Observer n'a pas abouti : transition={state['transition']!r}"
        )
        assert state["run_status"] == "DONE"  # jamais invalidé par l'Observer

        # Preuve d'EXÉCUTION, pas d'existence : les artefacts que seul un vrai
        # sous-processus Observer peut avoir écrits.
        assert (sortie / "observer_run.json").is_file()
        assert (sortie / "RECONSTRUCTION.md").is_file()
    finally:
        shutil.rmtree(sortie, ignore_errors=True)
