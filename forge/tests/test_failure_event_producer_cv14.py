"""CV-14 (lot de dégel 1, 2026-07-30) — producteur automatique de FailureEvent
(la boucle Lessons minimale, côté production).

Défaut mesuré : `EVIDENCE/reports/lessons.jsonl` n'existe pas ; `record_failure_event`
(learning_memory.py) n'avait AUCUN producteur automatique — dormance déclarée
boucle 3 avec déclencheur nommé : « le premier arrêt d'étape réel ».

Doctrine respectée (4 couches Run->FailureEvent->Lesson->Doctrine, écriture JAMAIS
ascendante) : ce chantier branche UNIQUEMENT le producteur de FailureEvent
(couche 1->2, dans `ForgeDriver._halt_step`, le seul point de convergence des
échecs d'étape LLM). AUCUNE Lesson n'est créée automatiquement (2->3 reste une
curation humaine/CLI, un choix de conception).

Ce fichier vérifie : (1) un halt réel enregistre un événement, avec
`etape_detection` posé et `causes_suspectees` VIDE (jamais deviné) ; (2) un run
vert n'enregistre RIEN ; (3) une exception du recorder ne casse jamais le run
(best-effort prouvé, comme `_journal_error`)."""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from forge.driver import ForgeDriver
from forge.learning_memory import read_failure_event_history


def _rows(path: Path) -> list[dict]:
    if not path.exists():
        return []
    return [json.loads(l) for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]


def _driver(tmp_path, *, executor=None, failure_events_path=None):
    return ForgeDriver(
        "proj-cv14", "r1", run_dir=tmp_path / "run", profile="micro",
        key_file=tmp_path / "k.key", audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        journal_path=tmp_path / "journal.jsonl",
        failure_events_path=failure_events_path or (tmp_path / "failure_events.jsonl"),
        executor=executor,
    )


def _state(d):
    return {"steps": {e: {"status": "PENDING", "attempts": 0, "detail": {}}
                      for e in d.order}}


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


# --- 1. un halt réel enregistre un événement ---------------------------------------

def test_halt_reel_enregistre_un_failure_event(tmp_path, offline):
    def failing_executor(payload, decision, context):
        return {"ok": False, "output": "", "reason": "échec fabriqué pour CV-14"}

    events_path = tmp_path / "failure_events.jsonl"
    d = _driver(tmp_path, executor=failing_executor, failure_events_path=events_path)
    etape = d.order[0]
    state = _state(d)
    ok = d._run_llm(state, etape)
    assert ok is False
    assert state["steps"][etape]["status"] == "BLOCKED"

    rows = _rows(events_path)
    assert len(rows) == 1
    row = rows[0]
    assert row["run_id"] == "r1"
    assert row["project"] == "proj-cv14"
    assert row["etape_detection"] == etape
    assert "échec fabriqué pour CV-14" in row["erreur_observee"]
    # règle ratifiée : jamais de causes_suspectees déduites du lieu de détection
    assert row["causes_suspectees"] == []
    assert row["failure_id"].startswith("fail-")


def test_halt_reel_est_relisible_via_read_failure_event_history(tmp_path, offline):
    def failing_executor(payload, decision, context):
        return {"ok": False, "output": "", "reason": "panne relisible"}

    events_path = tmp_path / "failure_events.jsonl"
    d = _driver(tmp_path, executor=failing_executor, failure_events_path=events_path)
    etape = d.order[0]
    state = _state(d)
    d._run_llm(state, etape)

    rows = _rows(events_path)
    assert len(rows) == 1
    from forge.learning_memory import make_failure_id
    fid = make_failure_id("proj-cv14", etape, rows[0]["erreur_observee"])
    history = read_failure_event_history(fid, path=events_path)
    assert len(history) == 1
    assert history[0]["etape_detection"] == etape


def test_halt_sans_executeur_enregistre_aussi(tmp_path, offline):
    """Le cas limite protocole M1 (aucun exécuteur fourni) passe aussi par
    `_halt_step` — même garantie, sans besoin d'un exécuteur qui échoue."""
    events_path = tmp_path / "failure_events.jsonl"
    d = _driver(tmp_path, executor=None, failure_events_path=events_path)
    etape = d.order[0]
    state = _state(d)
    d._run_llm(state, etape)
    rows = _rows(events_path)
    assert len(rows) == 1
    assert rows[0]["etape_detection"] == etape


# --- 2. un run vert n'enregistre rien -----------------------------------------------

def test_run_vert_necrit_aucun_failure_event(tmp_path, offline):
    def ok_executor(payload, decision, context):
        return {"ok": True, "output": "artefact"}

    events_path = tmp_path / "failure_events.jsonl"
    d = _driver(tmp_path, executor=ok_executor, failure_events_path=events_path)
    etape = d.order[0]
    state = _state(d)
    ok = d._run_llm(state, etape)
    assert ok is True
    assert not events_path.exists() or _rows(events_path) == []


# --- 3. best-effort : une exception du recorder ne casse jamais le run -------------

def test_exception_du_recorder_ne_casse_jamais_le_run(tmp_path, offline, monkeypatch):
    import forge.learning_memory as lm

    def boom(*a, **k):
        raise RuntimeError("panne fabriquée du recorder")

    monkeypatch.setattr(lm, "record_failure_event", boom)

    def failing_executor(payload, decision, context):
        return {"ok": False, "output": "", "reason": "échec normal"}

    d = _driver(tmp_path, executor=failing_executor)
    etape = d.order[0]
    state = _state(d)
    # ne doit JAMAIS lever, même avec le recorder cassé
    ok = d._run_llm(state, etape)
    assert ok is False
    assert state["steps"][etape]["status"] == "BLOCKED"


def test_failure_id_stable_meme_projet_meme_etape_meme_erreur(tmp_path, offline):
    """Deux halts indépendants du même problème convergent sur le même
    failure_id (append-only, clé par contenu — doctrine §2.1)."""
    def failing_executor(payload, decision, context):
        return {"ok": False, "output": "", "reason": "erreur identique"}

    events_path = tmp_path / "failure_events.jsonl"
    d1 = _driver(tmp_path, executor=failing_executor, failure_events_path=events_path)
    etape = d1.order[0]
    d1._run_llm(_state(d1), etape)

    d2 = _driver(tmp_path, executor=failing_executor, failure_events_path=events_path)
    d2._run_llm(_state(d2), etape)

    rows = _rows(events_path)
    assert len(rows) == 2
    assert rows[0]["failure_id"] == rows[1]["failure_id"]
