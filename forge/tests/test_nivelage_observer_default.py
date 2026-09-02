"""Oracle du NIVELAGE de l'Observer dans la suite de tests (GO Pierre 2026-08-29).

Contexte MESURÉ (audit du soir) : chaque `ForgeDriver.run()` de test qui atteint
DONE appelle `_trigger_observer_best_effort` (driver.py `run()`), lequel appelle
`self.observer_runner` — qui vaut `_default_observer_runner` dès qu'aucun runner
n'est injecté (driver.py `observer_runner or self._default_observer_runner`). Ce
défaut lance le VRAI `scripts/observer/cli.py` en sous-processus (~30-40 s,
re-parse de ~563 Mo de transcripts). 0/19 fichiers lourds de la suite n'injectait
de runner → ~110 spawns par passe, 92 % des 76 min de la suite.

Ce fichier prouve la fixture `_neutralise_observer_par_defaut` (conftest.py) :

  (a) un déclenchement Observer SANS runner injecté ne lance AUCUN sous-processus
      (aucun appel à `forge.driver.run_oracle`, seul chemin de spawn du défaut) ;
  (b) `state["transition"] == "OK"` reste posé (la neutralisation ne dégrade pas
      la sémantique observable du run) ;
  (c) un driver construit AVEC `observer_runner=...` explicite reçoit SON runner —
      la fixture ne l'écrase jamais (c'est ce qui garde `test_observer_trigger.py`
      valide) ;
  (d) le mécanisme d'opt-out `@pytest.mark.real_observer` rend bien le VRAI
      `_default_observer_runner` (utilisé par `test_observer_integration_real.py`,
      seul test autorisé à lancer l'Observer réel).

NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import subprocess
from pathlib import Path

import pytest

import forge.driver as driver_module
from forge.driver import ForgeDriver

#: Capturé à l'IMPORT du module, donc AVANT que la fixture autouse ne substitue
#: l'attribut de classe : c'est la seule référence stable au runner de PRODUCTION.
_DEFAUT_DE_PRODUCTION = ForgeDriver._default_observer_runner


def _driver(tmp_path: Path, observer_runner=None) -> ForgeDriver:
    return ForgeDriver(
        "proj-nivelage", "proj-nivelage-1", run_dir=tmp_path / "run", profile="micro",
        lessons_path=tmp_path / "lessons.jsonl",
        observer_runner=observer_runner,
    )


# --- (a) + (b) aucun sous-processus, transition OK quand même ----------------------

def test_defaut_ne_spawne_aucun_observer_et_pose_transition_ok(tmp_path, monkeypatch):
    """Le point d'appel RÉEL du chemin DONE (`_trigger_observer_best_effort`) sur un
    driver SANS injection : sous la fixture, aucun spawn, et `transition == "OK"`."""
    appels = []

    def tracer_run_oracle(spec, *args, **kwargs):
        appels.append(spec)
        return subprocess.CompletedProcess(args=["tracer"], returncode=0)

    # `run_oracle` est le SEUL chemin de spawn de `_default_observer_runner`
    # (driver.py : `return run_oracle(spec, ...)`) — le tracer ici prouve l'absence
    # de lancement sans dépendre d'un détail de subprocess.
    monkeypatch.setattr(driver_module, "run_oracle", tracer_run_oracle)

    d = _driver(tmp_path)  # AUCUN observer_runner injecté = chemin de production
    state = {"run_id": "proj-nivelage-1", "run_status": "DONE", "steps": {}}
    d._trigger_observer_best_effort(state)

    assert appels == [], f"un sous-processus Observer a été lancé : {appels}"
    assert state["transition"] == "OK"
    assert state["run_status"] == "DONE"


def test_le_defaut_de_classe_est_substitue_par_la_fixture(tmp_path):
    """La fixture agit sur l'ATTRIBUT DE CLASSE, donc sur tout driver non injecté,
    y compris ceux construits par des tests qui ignorent l'existence de l'Observer."""
    assert ForgeDriver._default_observer_runner is not _DEFAUT_DE_PRODUCTION


# --- (c) l'injection explicite gagne toujours -------------------------------------

def test_un_runner_injecte_n_est_jamais_ecrase_par_la_fixture(tmp_path):
    fake = lambda project: subprocess.CompletedProcess(args=["fake"], returncode=0)
    d = _driver(tmp_path, observer_runner=fake)
    assert d.observer_runner is fake

    appele = []
    d2 = _driver(tmp_path / "b", observer_runner=lambda p: (
        appele.append(p) or subprocess.CompletedProcess(args=["fake"], returncode=0)))
    state = {"run_id": "x", "run_status": "DONE", "steps": {}}
    d2._trigger_observer_best_effort(state)
    assert appele == ["proj-nivelage"]  # SON runner, pas le stub de la fixture


# --- (d) opt-out explicite pour le seul test d'intégration T1 ----------------------

@pytest.mark.real_observer
def test_le_marqueur_real_observer_rend_le_defaut_de_production():
    """`@pytest.mark.real_observer` désactive la fixture : le runner de PRODUCTION
    est de nouveau en place (c'est ce qui rend possible `test_observer_integration_
    real.py`, seul test autorisé à lancer le vrai Observer)."""
    assert ForgeDriver._default_observer_runner is _DEFAUT_DE_PRODUCTION
