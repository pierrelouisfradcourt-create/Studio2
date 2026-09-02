"""Oracle du déclenchement automatique de l'Observer en fin de run (P1, mission
2026-08-08 — commande de fabrication, base commit 284df4c).

Contexte mesuré (post-mortem pacman 2026-08-07) : le driver termine un run avec
un verdict signé mais n'appelle JAMAIS l'Observer — l'analyse post-run reste un
geste manuel, jamais garanti. Ce fichier prouve `ForgeDriver._trigger_observer_
best_effort` :

  (a) run terminé avec succès -> le déclencheur est appelé avec le bon projet
      (mock/injection, AUCUN vrai sous-processus Observer) ;
  (b) sous-processus en échec (returncode != 0) -> warning journalisé,
      `run_status` INCHANGÉ, `state.json["transition"]` commence par
      "INCOMPLETE" ;
  (c) timeout -> même traitement, pas d'exception qui remonte ;
  (d) succès -> `state.json["transition"] == "OK"` ;
  (e) le déclencheur n'est PAS appelé si le run n'atteint pas la fin (halt) —
      vérifié en forçant `_run_llm` à retourner False (comportement RÉEL du
      chemin de fin de run, cf. `ForgeDriver.run()` : le retour halted sort de
      la boucle avant `state["run_status"] = "DONE"` / avant l'appel du
      déclencheur).

Fichier NOUVEAU : ne touche à aucun test existant, ne modifie rien sous
scripts/observer/. Toute écriture est isolée sous tmp_path (jamais de vrai
sous-processus Observer, jamais EVIDENCE/reports/lessons.jsonl réel). NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
import logging
import subprocess
from pathlib import Path

import pytest

from forge.driver import ForgeDriver


def _completed(returncode: int) -> subprocess.CompletedProcess:
    return subprocess.CompletedProcess(
        args=["python", "scripts/observer/cli.py"], returncode=returncode,
        stdout="", stderr="",
    )


def _driver(tmp_path: Path, observer_runner=None, profile: str = "micro") -> ForgeDriver:
    return ForgeDriver(
        "proj", "proj-1", run_dir=tmp_path / "run", profile=profile,
        lessons_path=tmp_path / "lessons.jsonl",
        observer_runner=observer_runner,
    )


# --- (a) appelé avec le bon projet, aucun vrai sous-processus ----------------------

def test_trigger_calls_observer_runner_with_project(tmp_path):
    calls = []

    def fake_runner(project):
        calls.append(project)
        return _completed(0)

    d = _driver(tmp_path, observer_runner=fake_runner)
    state = {"run_id": "proj-1", "run_status": "DONE"}
    d._trigger_observer_best_effort(state)

    assert calls == ["proj"]  # self.project, jamais un autre nom


# --- (d) succès -> transition == "OK", persisté dans state.json --------------------

def test_trigger_success_sets_transition_ok_and_persists(tmp_path):
    d = _driver(tmp_path, observer_runner=lambda project: _completed(0))
    state = {"run_id": "proj-1", "run_status": "DONE", "steps": {}}
    d._trigger_observer_best_effort(state)

    assert state["transition"] == "OK"
    on_disk = json.loads(d.state_path.read_text(encoding="utf-8"))
    assert on_disk["transition"] == "OK"
    assert on_disk["run_status"] == "DONE"  # inchangé


# --- (b) returncode != 0 -> warning + run_status inchangé + transition INCOMPLETE --

def test_trigger_nonzero_returncode_logs_warning_and_marks_incomplete(tmp_path, caplog):
    d = _driver(tmp_path, observer_runner=lambda project: _completed(3))
    state = {"run_id": "proj-1", "run_status": "DONE", "steps": {}}

    with caplog.at_level(logging.WARNING, logger="forge.driver"):
        d._trigger_observer_best_effort(state)  # ne lève jamais

    assert state["run_status"] == "DONE"  # jamais invalidé par un échec Observer
    assert state["transition"].startswith("INCOMPLETE")
    assert any(r.exc_info for r in caplog.records if r.levelno == logging.WARNING)
    assert any("Observer" in r.message for r in caplog.records)

    on_disk = json.loads(d.state_path.read_text(encoding="utf-8"))
    assert on_disk["transition"].startswith("INCOMPLETE")
    assert on_disk["run_status"] == "DONE"


# --- (c) timeout -> même traitement, pas d'exception qui remonte -------------------

def test_trigger_timeout_does_not_raise_and_marks_incomplete(tmp_path, caplog):
    def timing_out(project):
        raise subprocess.TimeoutExpired(cmd="observer cli.py", timeout=300)

    d = _driver(tmp_path, observer_runner=timing_out)
    state = {"run_id": "proj-1", "run_status": "DONE", "steps": {}}

    with caplog.at_level(logging.WARNING, logger="forge.driver"):
        d._trigger_observer_best_effort(state)  # ne lève jamais malgré le TimeoutExpired

    assert state["run_status"] == "DONE"
    # Le déclencheur ne distingue pas TimeoutExpired des autres pannes d'un
    # `observer_runner` injecté (un seul `except Exception`, cf. driver.py) —
    # seul le préfixe INCOMPLETE est contractuel, pas le libellé exact.
    assert state["transition"].startswith("INCOMPLETE")
    assert any(r.exc_info for r in caplog.records if r.levelno == logging.WARNING)

    on_disk = json.loads(d.state_path.read_text(encoding="utf-8"))
    assert on_disk["transition"].startswith("INCOMPLETE")


def test_trigger_arbitrary_exception_does_not_raise(tmp_path, caplog):
    """Toute autre exception (pas seulement TimeoutExpired) reste best-effort."""
    def boom(project):
        raise OSError("observer cli.py introuvable (simulé)")

    d = _driver(tmp_path, observer_runner=boom)
    state = {"run_id": "proj-1", "run_status": "DONE", "steps": {}}

    with caplog.at_level(logging.WARNING, logger="forge.driver"):
        d._trigger_observer_best_effort(state)  # ne lève jamais

    assert state["run_status"] == "DONE"
    assert state["transition"].startswith("INCOMPLETE")


# --- (e) pas appelé si le run n'atteint pas la fin (halt) --------------------------

def test_trigger_not_called_when_run_halts_before_completion(tmp_path, monkeypatch):
    """`ForgeDriver.run()` sort par `_halted_report` AVANT `state["run_status"] =
    "DONE"` / avant l'appel du déclencheur (cf. driver.py : `elif not self._run_llm(
    state, etape): return self._halted_report(...)`) — reproduit ce chemin RÉEL en
    forçant `_run_llm` à retourner False (exécuteur en échec/absent), sans mocker le
    reste de la machine à états."""
    calls = []

    def fake_runner(project):
        calls.append(project)
        return _completed(0)

    d = _driver(tmp_path, observer_runner=fake_runner)
    monkeypatch.setattr(ForgeDriver, "_run_llm", lambda self, state, etape: False)

    report = d.run()

    assert report["status"] == "HALTED"
    assert calls == []  # le déclencheur Observer n'a jamais tourné
    # `_run_llm` est ici entièrement remplacé (pas de `self._save` intermédiaire
    # côté fake) : le seul fait vérifiable de façon stable est que la méthode
    # d'Observer n'a jamais tourné et que le rapport porte bien HALTED — pas de
    # supposition sur un state.json que ce double de test ne persiste pas lui-même.


# --- traçabilité : une ligne d'entrée ET de sortie dans run.log --------------------

def test_trigger_logs_entry_and_exit(tmp_path, caplog):
    d = _driver(tmp_path, observer_runner=lambda project: _completed(0))
    state = {"run_id": "proj-1", "run_status": "DONE", "steps": {}}

    with caplog.at_level(logging.INFO, logger="forge.driver"):
        d._trigger_observer_best_effort(state)

    messages = [r.message for r in caplog.records]
    assert any("déclenchement" in m for m in messages)  # entrée : projet, début
    assert any("terminé" in m for m in messages)  # sortie : durée, returncode


# --- injection : le runner par défaut n'est jamais utilisé par les tests -----------

def test_default_observer_runner_not_invoked_when_injected(tmp_path):
    """Le paramètre constructeur `observer_runner` prime toujours sur le runner de
    PRODUCTION (`_default_observer_runner`, sous-processus réel) — vérifie l'objet
    stocké sur l'instance."""
    fake = lambda project: _completed(0)
    d = _driver(tmp_path, observer_runner=fake)
    assert d.observer_runner is fake
    assert d.observer_runner is not d._default_observer_runner


def test_default_observer_runner_used_when_not_injected(tmp_path):
    """Défaut = comportement de production : aucun `observer_runner` fourni ->
    `self.observer_runner` retombe sur `_default_observer_runner` (jamais None,
    jamais silencieusement désactivé)."""
    d = _driver(tmp_path, observer_runner=None)
    assert d.observer_runner == d._default_observer_runner
