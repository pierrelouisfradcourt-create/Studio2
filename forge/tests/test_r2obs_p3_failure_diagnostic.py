"""R2-OBS · P3 — un échec d'exécuteur persiste son diagnostic, jamais un moignon.

Défaut mesuré (run kitten_clicker-20260825a) : `state.json` ne portait que
`{"reason": "exécuteur LLM en échec à s0-contrat: claude -p returncode=1: "}`.
Le returncode était noyé dans une phrase, le `process_state` (déjà CALCULÉ par
`run_real.classify_process_state`) et la durée n'étaient nulle part, et un stderr
vide se lisait comme un stderr absent. Post-mortem impossible sans relancer.

Ce que P3 fige : `entry["detail"]["executor_diagnostic"]` est TOUJOURS présent sur
un halt, avec des champs STRUCTURÉS (jamais une prose à re-parser — règle « aucune
décision dans un commentaire »), et « mesuré vide » se distingue de « non mesuré » :
`(vide)` vs `(non mesuré)`. Le stderr n'est PAS retronqué par le driver — la borne
2000 caractères de `_claude_call_raw` est la seule.

LIMITE DÉCLARÉE (non fermée ici) : `EVIDENCE/reports/failure_events.jsonl` ne reçoit pas
ces champs. Son producteur (`ForgeDriver._record_failure_event` ->
`forge.learning_memory.record_failure_event`) n'accepte qu'un `erreur_observee`
textuel, et son `make_failure_id` HACHE cette chaîne : y injecter une durée ou un
returncode variable fragmenterait l'identité de panne d'un run à l'autre — le
regroupement des FailureEvents casserait. Étendre le schéma exige de toucher
`learning_memory.py`, hors périmètre de ce lot.
"""
from __future__ import annotations

import pytest

from forge.driver import ForgeDriver


def _driver(tmp_path, executor=None):
    return ForgeDriver(
        "proj-r2obs3", "r1", run_dir=tmp_path / "run", profile="micro",
        key_file=tmp_path / "k.key", audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        journal_path=tmp_path / "journal.jsonl",
        failure_events_path=tmp_path / "failure_events.jsonl",
        executor=executor,
    )


def _state(d):
    return {"steps": {e: {"status": "PENDING", "attempts": 0, "detail": {}}
                      for e in d.order}}


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


def _halt(tmp_path, offline_, res):
    d = _driver(tmp_path, executor=lambda p, dec, ctx: res)
    etape = d.order[0]
    state = _state(d)
    assert d._run_llm(state, etape) is False
    return state["steps"][etape]["detail"]


# --- (a) la signature muette du run 25a devient lisible ---------------------

def test_un_echec_muet_porte_tous_les_champs(tmp_path, offline):
    detail = _halt(tmp_path, offline, {
        "ok": False, "reason": "claude -p returncode=1: ",
        "returncode": 1, "stderr_tail": "", "process_state": "PROCESS_EXIT_NONZERO",
        "duration_s": 2.13,
    })
    diag = detail["executor_diagnostic"]
    assert diag["measured"] is True
    assert diag["returncode"] == 1
    assert diag["process_state"] == "PROCESS_EXIT_NONZERO"
    assert diag["stderr_tail"] == "(vide)"      # mesuré vide, jamais « absent »
    assert diag["duration_s"] == pytest.approx(2.13)
    assert diag["transient_retries_count"] == 0
    assert diag["timeout"] is False


# --- (b) le stderr n'est jamais retronqué par le driver ---------------------

def test_le_stderr_n_est_pas_retronque(tmp_path, offline):
    long_stderr = "E" * 2000
    detail = _halt(tmp_path, offline, {
        "ok": False, "reason": "claude -p returncode=1: " + long_stderr,
        "returncode": 1, "stderr_tail": long_stderr,
        "process_state": "PROCESS_EXIT_NONZERO", "duration_s": 1.0,
    })
    assert detail["executor_diagnostic"]["stderr_tail"] == long_stderr


# --- (c) champ absent du retour : « non mesuré », jamais « vide » -----------

def test_un_champ_absent_se_lit_non_mesure(tmp_path, offline):
    detail = _halt(tmp_path, offline, {"ok": False, "reason": "retour minimal"})
    diag = detail["executor_diagnostic"]
    assert diag["measured"] is True           # l'exécuteur a bien tourné
    assert diag["returncode"] is None
    assert diag["process_state"] == "(non mesuré)"
    assert diag["stderr_tail"] == "(non mesuré)"


# --- (d) aucun exécuteur : le diagnostic existe quand même ------------------

def test_sans_executeur_le_diagnostic_existe_et_se_declare_non_mesure(tmp_path, offline):
    d = _driver(tmp_path, executor=None)
    etape = d.order[0]
    state = _state(d)
    assert d._run_llm(state, etape) is False
    diag = state["steps"][etape]["detail"]["executor_diagnostic"]
    assert diag["measured"] is False


# --- (e) le compte de retries P1 atteint le diagnostic ---------------------

def test_le_compte_de_retries_transitoires_est_persiste(tmp_path, offline):
    recus = [{"try": 1, "returncode": 1, "process_state": "PROCESS_EXIT_NONZERO",
              "stderr_tail": "(vide)", "duration_s": 2.0},
             {"try": 2, "returncode": 1, "process_state": "PROCESS_EXIT_NONZERO",
              "stderr_tail": "(vide)", "duration_s": 2.0},
             {"try": 3, "returncode": 1, "process_state": "PROCESS_EXIT_NONZERO",
              "stderr_tail": "(vide)", "duration_s": 2.0}]
    detail = _halt(tmp_path, offline, {
        "ok": False, "reason": "claude -p returncode=1: ", "returncode": 1,
        "stderr_tail": "", "process_state": "PROCESS_EXIT_NONZERO",
        "duration_s": 2.0, "transient_retries": recus,
    })
    diag = detail["executor_diagnostic"]
    assert diag["transient_retries_count"] == 3
    assert diag["transient_retries"] == recus


# --- (f) non-régression : `reason` reste EXACTEMENT ce qu'il était ---------

def test_le_texte_de_reason_est_inchange(tmp_path, offline):
    d = _driver(tmp_path, executor=lambda p, dec, ctx: {
        "ok": False, "reason": "claude -p returncode=1: "})
    etape = d.order[0]
    state = _state(d)
    d._run_llm(state, etape)
    assert state["reason"] == (
        f"exécuteur LLM en échec à {etape}: claude -p returncode=1: ")
    assert state["steps"][etape]["detail"]["reason"] == state["reason"]


# --- (g) un timeout est signalé comme tel --------------------------------

def test_un_timeout_est_signale(tmp_path, offline):
    detail = _halt(tmp_path, offline, {
        "ok": False, "timeout": True, "reason": "claude -p timeout (900s)",
        "returncode": None, "stderr_tail": "", "process_state": "MODEL_NOT_REACHED",
        "duration_s": 900.0,
    })
    assert detail["executor_diagnostic"]["timeout"] is True
