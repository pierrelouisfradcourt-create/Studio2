"""Oracle du câblage de la Project Bible dans le contexte de s0-contrat.

Ferme le trou « déclaré ≠ exécuté » : contracts/s0-contrat.yaml §2 (mandatory_read)
dit que l'agent s0 doit lire la Project Bible du projet (studio_link.project_bible)
« pour ne pas re-proposer une voie déjà écartée » — mais rien ne l'appelait.

Même patron que le pré-mortem (déjà câblé) : le driver calcule
`studio_link.project_bible(project)` et le pose dans `context["project_bible"]`,
UNIQUEMENT pour s0-contrat (toute autre étape reçoit "" — jamais une invention hors
contrat). L'injection RÉELLE dans le prompt (section '## PROJECT BIBLE') est
vérifiée séparément côté `run_real.claude_executor` (voir
test_run_real_hardening.py-like proof dans ce fichier), avec la garantie qu'une
bible absente NE CHANGE PAS le prompt (pas de section vide, pas de placeholder).
"""
import sys
from pathlib import Path

import pytest

from forge.driver import ForgeDriver
import forge.run_real as rr


class _RecordingExecutor:
    """Trace le context['project_bible'] vu par CHAQUE étape."""

    def __init__(self, run_dir=None):
        self.run_dir = run_dir
        self.bibles = []  # (etape, project_bible)

    def __call__(self, payload, decision, context):
        self.bibles.append((payload.etape, context.get("project_bible")))
        return {"ok": True, "output": f"artefact {payload.etape}"}


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


def _kwargs(tmp_path, run_dir, project="proj", exit_code=0):
    import json
    cfg = tmp_path / "oracles_test.json"
    cfg.write_text(
        json.dumps({project: {
            "cwd": str(tmp_path),
            "command": [sys.executable, "-c", f"import sys; sys.exit({exit_code})"],
        }}),
        encoding="utf-8",
    )
    return dict(
        run_dir=run_dir,
        oracle_config=cfg,
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
        journal_path=tmp_path / "journal.jsonl",
    )


# --- 1) le driver ne peuple project_bible QUE pour s0-contrat --------------------

def test_project_bible_peuple_uniquement_a_s0(tmp_path, offline, monkeypatch):
    """Un profil `patch` (s9/s10a/s11/s12, PAS s0) doit voir project_bible == ''
    à chaque étape (jamais peuplé hors s0)."""
    run_dir = tmp_path / "run"
    ex = _RecordingExecutor(run_dir=run_dir)
    ForgeDriver("proj", "proj-1", profile="patch", executor=ex,
                **_kwargs(tmp_path, run_dir)).run()
    assert ex.bibles, "au moins une étape LLM doit avoir tourné"
    for etape, bible in ex.bibles:
        assert etape != "s0-contrat"
        assert bible == ""


def test_project_bible_peuplee_a_s0_quand_elle_existe(tmp_path, offline, monkeypatch):
    """Profil `full` (contient s0-contrat) + une PROJECT_BIBLE.md réelle sous
    EVIDENCE/runs/<projet>/ -> context['project_bible'] non vide À s0, vide ailleurs."""
    runs_root = tmp_path / "forge_runs"
    (runs_root / "proj").mkdir(parents=True)
    (runs_root / "proj" / "PROJECT_BIBLE.md").write_text(
        "# PROJECT BIBLE\n## Piliers\n- lisibilité\n", encoding="utf-8")
    monkeypatch.setattr("forge.studio_link.FORGE_RUNS", runs_root)

    run_dir = tmp_path / "run"
    ex = _RecordingExecutor(run_dir=run_dir)
    ForgeDriver("proj", "proj-1", profile="full", executor=ex,
                **_kwargs(tmp_path, run_dir)).run()

    s0_bibles = [b for (e, b) in ex.bibles if e == "s0-contrat"]
    assert s0_bibles and s0_bibles[0] != "", "s0-contrat doit voir la Project Bible"
    assert "lisibilité" in s0_bibles[0]
    other_bibles = [b for (e, b) in ex.bibles if e != "s0-contrat"]
    assert all(b == "" for b in other_bibles), "aucune autre étape ne doit voir la bible"


def test_project_bible_absente_vide_partout(tmp_path, offline, monkeypatch):
    """Aucune PROJECT_BIBLE.md sur disque -> "" pour TOUTES les étapes, y compris s0
    (jamais un crash, jamais un placeholder)."""
    runs_root = tmp_path / "forge_runs_vide"
    runs_root.mkdir()
    monkeypatch.setattr("forge.studio_link.FORGE_RUNS", runs_root)

    run_dir = tmp_path / "run"
    ex = _RecordingExecutor(run_dir=run_dir)
    ForgeDriver("proj", "proj-1", profile="full", executor=ex,
                **_kwargs(tmp_path, run_dir)).run()

    assert ex.bibles
    assert all(b == "" for (_, b) in ex.bibles)


def test_lecture_qui_leve_ne_casse_pas_le_run(tmp_path, offline, monkeypatch):
    """project_bible qui lève (best-effort, même garantie que le pré-mortem) ne
    doit jamais faire échouer le run."""
    def _boom(*a, **k):
        raise RuntimeError("lecture HS (simulée)")

    monkeypatch.setattr("forge.driver.project_bible", _boom)
    run_dir = tmp_path / "run"
    ex = _RecordingExecutor(run_dir=run_dir)
    report = ForgeDriver("proj", "proj-1", profile="full", executor=ex,
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["status"] == "DONE"
    s0_bibles = [b for (e, b) in ex.bibles if e == "s0-contrat"]
    assert s0_bibles == [""]


# --- 2) injection réelle dans le prompt (run_real.claude_executor) ---------------

class _FakePayload:
    def __init__(self, etape):
        self.etape = etape
        self.prompt = "CONTRAT S0"
        self.model = "claude-opus-4-8"


class _FakeDecision:
    pass


def test_prompt_s0_contient_la_bible_quand_elle_existe(monkeypatch):
    captured = {}

    def fake_call(prompt, model, *, add_dir, tools=(), timeout_s=0):
        captured["prompt"] = prompt
        return {"ok": True, "output": "x", "tokens": 1, "duration_s": 0.1, "cost_usd": 0.0}

    monkeypatch.setattr(rr, "_claude_call_raw", fake_call)
    executor = rr.claude_executor(add_dir=Path("."), task_by_step={"s0-contrat": "Fait le contrat."})
    ctx = {"run_id": "r1", "project": "proj", "run_dir": ".", "model_override": None,
          "dispatch_marker": "MARK", "attempt": 1, "premortem": [],
          "project_bible": "# PROJECT BIBLE\n- pilier X\n"}
    executor(_FakePayload("s0-contrat"), _FakeDecision(), ctx)
    assert "PROJECT BIBLE" in captured["prompt"]
    assert "pilier X" in captured["prompt"]


def test_prompt_s0_inchange_quand_bible_absente(monkeypatch):
    """Comparaison EXACTE : le prompt sans bible (project_bible='') est
    BYTE-IDENTIQUE au prompt où la clé project_bible est absente du context
    (comportement des étapes non-s0 dans le vrai driver)."""
    captured = []

    def fake_call(prompt, model, *, add_dir, tools=(), timeout_s=0):
        captured.append(prompt)
        return {"ok": True, "output": "x", "tokens": 1, "duration_s": 0.1, "cost_usd": 0.0}

    monkeypatch.setattr(rr, "_claude_call_raw", fake_call)
    executor = rr.claude_executor(add_dir=Path("."), task_by_step={"s0-contrat": "Fait le contrat."})
    base = {"run_id": "r1", "project": "proj", "run_dir": ".", "model_override": None,
           "dispatch_marker": "MARK", "attempt": 1, "premortem": []}

    executor(_FakePayload("s0-contrat"), _FakeDecision(), dict(base, project_bible=""))
    executor(_FakePayload("s0-contrat"), _FakeDecision(), dict(base))

    assert captured[0] == captured[1]
    assert "PROJECT BIBLE" not in captured[0]
