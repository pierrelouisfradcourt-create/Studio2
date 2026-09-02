"""Tests de `observer.session_transition.build` (mission P2, 2026-08-08).

Fixtures synthetiques : prouvent que l'assemblage lit bien les champs REELS
d'un run reconstruit (jamais une constante). Le rejeu sur `driver_smoke_v4`,
`pacman`, `pacman-v6` et `breakout_v2` est fait via `cli.py`, hors de ce
fichier (voir le rapport de mission).
"""

from __future__ import annotations

from observer import session_transition


class _FakeCtx:
    def __init__(self, repo_root):
        self.repo_root = repo_root


def _ev(kind, path, run_id="r1", proof="MECHANICAL", payload=None):
    return {
        "kind": kind,
        "run_id": run_id,
        "proof": proof,
        "source": {"path": path},
        "payload": payload or {},
    }


def _base_run(**overrides):
    run = {
        "run_id": "r1",
        "run_status": "DONE",
        "window": {"end": "2026-08-01T00:00:00+00:00"},
        "verdict": {
            "decision": "HUMANGATE_READY",
            "software_verdict": "OK",
            "humangate_flags": ["archi non verifiee"],
        },
    }
    run.update(overrides)
    return run


def test_build_has_the_minimal_required_keys(tmp_path):
    ctx = _FakeCtx(tmp_path)
    result = {
        "project": "x",
        "observed_at": "2026-08-08T00:00:00+00:00",
        "runs": [_base_run()],
    }
    events = [
        _ev("verdict.signed", "lab/forge_runs/x/verdict.json",
            payload={"humangate_flags": ["archi non verifiee"]}),
        _ev("run.artifact_present", "lab/forge_runs/x/run.log"),
    ]
    st = session_transition.build(result, events, ctx)
    for key in (
        "produced", "proved", "open", "decisions", "next_run_input",
        "archive_proposals", "review_required", "lanes",
    ):
        assert key in st


def test_build_routes_produced_and_proved_from_real_events(tmp_path):
    ctx = _FakeCtx(tmp_path)
    result = {
        "project": "x",
        "observed_at": "2026-08-08T00:00:00+00:00",
        "runs": [_base_run()],
    }
    events = [
        _ev("oracle.result", "lab/forge_runs/x/verdict.json",
            payload={"evidence_path": str(tmp_path / "lab" / "forge_runs" / "x" / "evidence" / "o.log")}),
        _ev("run.artifact_present", "lab/forge_runs/x/evidence/o.log"),
        _ev("test.result", "lab/forge_runs/x/evidence/o.log", payload={"cwd": "lab/forge_runs/x/src"}),
        _ev("run.artifact_present", "lab/forge_runs/x/src/logic.mjs"),
        _ev("verdict.signed", "lab/forge_runs/x/verdict.json",
            payload={"humangate_flags": ["archi non verifiee"]}),
    ]
    st = session_transition.build(result, events, ctx)
    entry = st["by_run"]["r1"]
    assert "lab/forge_runs/x/evidence/o.log" in entry["proved"]
    assert "lab/forge_runs/x/src/logic.mjs" in entry["produced"]
    assert entry["open"] == ["archi non verifiee"]
    assert "lab/forge_runs/x/verdict.json" in entry["decisions"]


def test_build_marks_lane_ready_for_humangate_ready_verdict(tmp_path):
    ctx = _FakeCtx(tmp_path)
    result = {"project": "x", "observed_at": "2026-08-08T00:00:00+00:00", "runs": [_base_run()]}
    events = [_ev("verdict.signed", "lab/forge_runs/x/verdict.json",
                  payload={"humangate_flags": ["a"]})]
    st = session_transition.build(result, events, ctx)
    states = {lane["state"] for lane in st["by_run"]["r1"]["lanes"]}
    assert "ready" in states


def test_build_marks_lane_blocked_for_failed_run(tmp_path):
    ctx = _FakeCtx(tmp_path)
    run = _base_run(run_status="BLOCKED", verdict={"decision": None, "software_verdict": "FAIL",
                                                     "humangate_flags": []})
    result = {"project": "x", "observed_at": "2026-08-08T00:00:00+00:00", "runs": [run]}
    st = session_transition.build(result, [], ctx)
    states = {lane["state"] for lane in st["by_run"]["r1"]["lanes"]}
    assert "blocked" in states


def test_build_review_required_reflected_in_deferred_lane(tmp_path):
    ctx = _FakeCtx(tmp_path)
    result = {"project": "x", "observed_at": "2026-08-08T00:00:00+00:00", "runs": [_base_run()]}
    events = [_ev("run.artifact_present", "lab/forge_runs/x/run.log")]
    st = session_transition.build(result, events, ctx)
    entry = st["by_run"]["r1"]
    assert any(r["path"] == "lab/forge_runs/x/run.log" for r in entry["review_required"])
    states = {lane["state"] for lane in entry["lanes"]}
    assert "deferred" in states


def test_build_reports_incomplete_chain_when_no_state_and_no_verdict(tmp_path):
    """Cas pacman-v6 reel (mesure 2026-08-08) : le run_dir contient des
    fichiers (`context/*.jsonl`) mais aucun `state.json`, aucun `verdict*.json`
    -> aucun run reconstruit (`result['runs']` vide), mais les fichiers du
    run_dir existent quand meme comme evenements sans run_id. La section doit
    le dire explicitement, pas produire une fausse couverture."""
    ctx = _FakeCtx(tmp_path)
    result = {"project": "pacman-v6", "observed_at": "2026-08-08T00:00:00+00:00", "runs": []}
    events = [
        _ev("run.artifact_present", "lab/forge_runs/pacman-v6/context/s9.manifest.jsonl", run_id=None),
    ]
    st = session_transition.build(result, events, ctx)
    entry = st["by_run"]["None"]
    assert entry["run_status"] is None
    assert any(lane["state"] == "deferred" and "chaine incomplete" in lane["detail"]
               for lane in entry["lanes"])
    # le fichier reste visible (REVIEW_REQUIRED), jamais silencieusement absent
    assert any(r["path"] == "lab/forge_runs/pacman-v6/context/s9.manifest.jsonl"
               for r in entry["review_required"])


def test_build_no_incomplete_chain_entry_when_project_has_no_run_dir_files_at_all(tmp_path):
    ctx = _FakeCtx(tmp_path)
    result = {"project": "y", "observed_at": "2026-08-08T00:00:00+00:00", "runs": []}
    st = session_transition.build(result, [], ctx)
    assert st["by_run"] == {}
