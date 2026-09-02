"""Correctif B — la sortie brute d'un exécuteur en échec (`ok: False`) ne doit
jamais être perdue.

Défaut mesuré (run kitten_clicker-20260821-1312, 2026-08-21) : quand
l'exécuteur rend `ok: False` (ex. `_materialize_artifact` refuse
`worldscan.json` car `games` vide), `ForgeDriver._run_llm` halte SANS écrire
`artifacts/<etape>.txt` (l.1082 n'est atteinte que sur succès) — la sortie
brute d'une étape coûteuse en échec est perdue, forensique impossible.

(a) `ForgeDriver._run_llm` : un exécuteur injecté qui rend `output` non vide
    même en échec fait écrire `artifacts/<etape>.failed.txt` (nom DISTINCT de
    `<etape>.txt` — jamais faire passer une sortie refusée pour un artefact
    validé), et le statut de l'étape reste celui du halt (BLOCKED).
(b) `run_real.claude_executor` : quand `_materialize_artifact` refuse,
    le dict rendu porte `output`.
"""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import pytest

import forge.run_real as run_real
from forge.driver import ForgeDriver


# --- (a) driver.py : artifacts/<etape>.failed.txt écrit sur échec exécuteur --------

def _driver(tmp_path, *, executor=None):
    return ForgeDriver(
        "proj-b", "r1", run_dir=tmp_path / "run", profile="micro",
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


def test_sortie_brute_persistee_en_failed_txt_sur_echec_executeur(tmp_path, offline):
    def failing_executor(payload, decision, context):
        return {"ok": False, "reason": "x", "output": "SORTIE BRUTE"}

    d = _driver(tmp_path, executor=failing_executor)
    etape = d.order[0]
    state = _state(d)
    ok = d._run_llm(state, etape)

    assert ok is False
    assert state["steps"][etape]["status"] == "BLOCKED"

    failed_path = d.run_dir / "artifacts" / f"{etape}.failed.txt"
    assert failed_path.exists(), "artifacts/<etape>.failed.txt non écrit"
    assert failed_path.read_text(encoding="utf-8") == "SORTIE BRUTE"

    # nom DISTINCT de l'artefact validé : jamais une sortie refusée passée pour OK
    ok_path = d.run_dir / "artifacts" / f"{etape}.txt"
    assert not ok_path.exists()


def test_sortie_vide_sur_echec_necrit_aucun_fichier_failed(tmp_path, offline):
    """Une sortie vide (ou absente) n'a rien à persister — aucun fichier
    fantôme créé."""
    def failing_executor(payload, decision, context):
        return {"ok": False, "reason": "x"}

    d = _driver(tmp_path, executor=failing_executor)
    etape = d.order[0]
    state = _state(d)
    d._run_llm(state, etape)

    failed_path = d.run_dir / "artifacts" / f"{etape}.failed.txt"
    assert not failed_path.exists()


def test_aucun_executeur_fourni_necrit_aucun_fichier_failed(tmp_path, offline):
    """Cas limite protocole M1 (executor=None) : `res` n'est jamais un dict,
    rien à persister — pas de crash."""
    d = _driver(tmp_path, executor=None)
    etape = d.order[0]
    state = _state(d)
    ok = d._run_llm(state, etape)
    assert ok is False
    failed_path = d.run_dir / "artifacts" / f"{etape}.failed.txt"
    assert not failed_path.exists()


def test_driver_ne_spawn_toujours_pas_directement():
    """Garde-fou : ce correctif ne doit introduire aucun spawn direct dans
    driver.py (même invariant que test_driver_ne_spawn_pas_directement)."""
    src = (run_real.REPO_ROOT / "forge" / "driver.py").read_text(
        encoding="utf-8")
    for mot in ("subprocess", "Popen", "os.system", "anthropic"):
        assert mot not in src, f"mot interdit trouvé dans driver.py : {mot}"


# --- (b) run_real.py : le dict d'échec de _materialize_artifact porte 'output' -----

@dataclass
class FakePayload:
    etape: str
    model: str = "haiku"
    prompt: str = "PROMPT CONTRAT"


def _context(run_dir, **extra):
    ctx = {
        "run_id": "run-1",
        "project": "proj",
        "run_dir": str(run_dir),
        "model_override": None,
        "dispatch_marker": "FORGE_DISPATCH:x:run-1",
        "attempt": 1,
        "premortem": [],
    }
    ctx.update(extra)
    return ctx


def test_executor_transmet_output_quand_materialize_artifact_refuse(tmp_path, monkeypatch):
    def fake_claude_call(prompt, model, **kwargs):
        return {"ok": True, "output": "SORTIE LLM CONNUE",
                "tokens": 42, "duration_s": 1.5, "cost_usd": 0.01}

    monkeypatch.setattr(run_real, "_claude_call_raw", fake_claude_call)
    monkeypatch.setattr(
        run_real, "_materialize_artifact",
        lambda etape, output, run_dir: {"ok": False, "reason": "refusé pour le test"},
    )

    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={})
    res = ex(FakePayload("s2-worldscan"), None, _context(tmp_path / "run"))

    assert res["ok"] is False
    assert res["output"] == "SORTIE LLM CONNUE"
    assert res["tokens"] == 42
