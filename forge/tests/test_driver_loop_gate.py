"""Gate s10a `player_loop` (Task 5, lot « game loop », 2026-08-22) — GATE depuis
Task 4 (plan `2026-08-22-kitten-clicker-gameplay-contract.md` §T4, décision run 7
« variance d'abord » supersédée) : `detail["loop_dead"]` entre dans la condition
`final == "FAIL"` des trois points d'agrégation, exactement comme `runtime_dead`.
Patron strict de `test_driver_runtime_alive_gate.py` (`ForgeDriver.__new__`, jamais
de vrai binaire Godot ni de vrai process) pour (a)/(b)/(c) ; (d) recopie
`res["loop_check"]` dans `entry["detail"]` pour s1-prisme, patron de
`test_measured_fields_persisted.py` (M3'a/M4') — un run() réel avec un exécuteur
stub."""
import json
import sys
from pathlib import Path

import pytest

from forge.driver import ForgeDriver


def _driver_minimal(game_dir: Path) -> ForgeDriver:
    d = ForgeDriver.__new__(ForgeDriver)  # pas de __init__ : on ne teste que la méthode
    d.run_id = "r1"
    d.game_dir = game_dir
    d.run_dir = game_dir.parent / "run"
    return d


# --- (a) runner FAIL -> loop_dead True, final == "FAIL" (gate, Task 4) -----------


def _aggregate(status, e2e_ok, solvability_passed, harness_flags_passed, runtime_alive,
               player_loop, *, receipt_status="OK"):
    """Reproduit la structure des 3 blocs d'agrégation de `_run_code_oracle` — même
    patron que `test_driver_runtime_alive_gate.py::_aggregate`, étendu à
    `loop_dead` (gate depuis Task 4, dans la condition `final` comme `runtime_dead`)."""
    detail = {"runtime_alive": runtime_alive, "player_loop": player_loop}
    runtime_dead = ForgeDriver._code_oracle_runtime_dead(detail)
    detail["loop_dead"] = ForgeDriver._code_oracle_loop_dead(detail)
    if status == "BLOCKED":
        final = "BLOCKED"
    elif (status == "FAIL" or not e2e_ok or not solvability_passed
            or not harness_flags_passed or receipt_status != "OK"
            or runtime_dead or detail["loop_dead"]):
        final = "FAIL"
    else:
        final = "OK"
    return final, detail


def test_loop_dead_true_fait_echouer_le_gate():
    final, detail = _aggregate(
        "OK", True, True, True,
        {"status": "OK", "checked": True, "passed": True},
        {"status": "FAIL", "checked": True, "passed": False, "fails": ["affordance 'acheter_chaton' introuvable"]},
    )
    assert detail["loop_dead"] is True
    assert final == "FAIL"  # gate depuis Task 4 : loop_dead fait échouer


def test_loop_dead_false_quand_passed():
    final, detail = _aggregate(
        "OK", True, True, True,
        {"status": "OK", "checked": True, "passed": True},
        {"status": "OK", "checked": True, "passed": True},
    )
    assert detail["loop_dead"] is False
    assert final == "OK"


def test_loop_dead_false_quand_not_measured():
    final, detail = _aggregate(
        "OK", True, True, True,
        {"status": "OK", "checked": True, "passed": True},
        {"status": "NOT_MEASURED", "checked": False, "passed": False},
    )
    assert detail["loop_dead"] is False
    assert final == "OK"


def test_loop_dead_false_quand_skipped():
    final, detail = _aggregate(
        "OK", True, True, True,
        {"status": "OK", "checked": True, "passed": True},
        {"status": "SKIPPED", "checked": False, "passed": False},
    )
    assert detail["loop_dead"] is False
    assert final == "OK"


def test_runtime_dead_seul_fait_toujours_echouer_meme_avec_loop_ok():
    final, detail = _aggregate(
        "OK", True, True, True,
        {"status": "FAIL", "checked": True, "passed": False},
        {"status": "OK", "checked": True, "passed": True},
    )
    assert final == "FAIL"  # runtime_dead reste GATANT (Task 2, inchangé)
    assert detail["loop_dead"] is False


# --- _code_oracle_loop_dead, pure -------------------------------------------


def test_code_oracle_loop_dead_true_checked_et_non_passed():
    assert ForgeDriver._code_oracle_loop_dead(
        {"player_loop": {"status": "FAIL", "checked": True, "passed": False}}) is True


def test_code_oracle_loop_dead_false_quand_absent_du_detail():
    assert ForgeDriver._code_oracle_loop_dead({}) is False


# --- (b) _player_loop_detail : pass-through (SKIPPED / OK / FAIL) -----------


def test_player_loop_detail_pass_through_skipped_sans_loop_amont(tmp_path):
    """SKIPPED reste SKIPPED tel quel quand `<run_dir>/loop.json` n'existe PAS —
    pas de contrat amont à trahir (pass-through inchangé)."""
    game = tmp_path / "game"
    game.mkdir()
    d = _driver_minimal(game)
    payload = {"status": "SKIPPED", "checked": False, "passed": False,
               "reason": "pas de 03_WORLD/loop.json"}
    calls = []
    d.player_loop_runner = lambda gd, run_dir=None: calls.append((gd, run_dir)) or payload
    r = d._player_loop_detail()
    assert r == payload
    assert calls == [(game, d.run_dir)]


def test_player_loop_detail_skipped_avec_loop_amont_devient_fail_checked(tmp_path):
    """Task 4 : SKIPPED alors que `<run_dir>/loop.json` EXISTE (contrat déposé en
    amont) devient un FAIL checked=True — le jeu n'a pas matérialisé un contrat
    que le run possède, jamais un silence."""
    game = tmp_path / "game"
    game.mkdir()
    d = _driver_minimal(game)
    d.run_dir.mkdir(parents=True, exist_ok=True)
    (d.run_dir / "loop.json").write_text("{}", encoding="utf-8")
    payload = {"status": "SKIPPED", "checked": False, "passed": False,
               "reason": "pas de 03_WORLD/loop.json"}
    d.player_loop_runner = lambda gd, run_dir=None: payload
    r = d._player_loop_detail()
    assert r["status"] == "FAIL"
    assert r["checked"] is True
    assert r["passed"] is False
    assert r["fails"]
    assert ForgeDriver._code_oracle_loop_dead({"player_loop": r}) is True


def test_player_loop_detail_pass_through_ok(tmp_path):
    game = tmp_path / "game"
    game.mkdir()
    d = _driver_minimal(game)
    payload = {"status": "OK", "checked": True, "passed": True, "fails": [], "payload": {}}
    d.player_loop_runner = lambda gd, run_dir=None: payload
    assert d._player_loop_detail() == payload


# --- (c) exception -> NOT_MEASURED, jamais une exception qui remonte --------


def test_player_loop_detail_exception_devient_not_measured(tmp_path):
    game = tmp_path / "game"
    game.mkdir()
    d = _driver_minimal(game)

    def boom(gd, run_dir=None):
        raise RuntimeError("panne fabriquée")

    d.player_loop_runner = boom
    r = d._player_loop_detail()  # ne doit jamais lever
    assert r["status"] == "NOT_MEASURED"
    assert r["checked"] is False and r["passed"] is False
    assert r["reason"]


# --- (d) res["loop_check"] recopié dans entry["detail"] pour s1-prisme -------
# Patron M3'a/M4' (test_measured_fields_persisted.py) : run() réel, exécuteur stub.


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


def _oracle_config(tmp_path, project="proj", exit_code=0):
    script = f"import sys; sys.exit({exit_code})"
    cfg = tmp_path / "oracles.json"
    cfg.write_text(
        json.dumps({project: {"cwd": str(tmp_path),
                              "command": [sys.executable, "-c", script]}}),
        encoding="utf-8")
    return cfg


def _kwargs(tmp_path, run_dir):
    return dict(
        run_dir=run_dir,
        oracle_config=_oracle_config(tmp_path),
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
    )


class _LoopCheckStub:
    """Exécuteur factice qui rend un reçu `loop_check` (matérialisation loop.json,
    même patron que markdown_check/M3'a)."""

    def __call__(self, payload, decision, context):
        return {
            "ok": True,
            "output": f"artefact {payload.etape}",
            "loop_check": {"ok": False, "problems": ["0 PLAYER_ACTION avec affordance"]},
        }


def test_loop_check_persiste_dans_state_pour_une_etape_llm(tmp_path, offline):
    run_dir = tmp_path / "run"
    ForgeDriver("proj", "proj-1", profile="review",
               executor=_LoopCheckStub(), **_kwargs(tmp_path, run_dir)).run()
    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    # première étape LLM du profil review — le report n'est pas etape-spécifique
    # (même généralité que markdown_check/yaml_check, non gatés sur le nom d'étape).
    first_llm_step = next(
        etape for etape, entry in state["steps"].items()
        if isinstance(entry.get("detail"), dict) and "loop_check" in entry["detail"])
    detail = state["steps"][first_llm_step]["detail"]
    assert detail["loop_check"] == {"ok": False, "problems": ["0 PLAYER_ACTION avec affordance"]}
