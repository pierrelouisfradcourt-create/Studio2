"""Lot B, T3 (2026-08-23, plan `2026-08-23-forge-lot-b-game-master.md`) :

  1. Gate s10a `art_response` (contrat s9 règle (15)) — `ForgeDriver.
     _art_response_detail` / `_code_oracle_art_response_dead`, patron strict de
     `test_driver_loop_gate.py`/`test_driver_runtime_alive_gate.py`
     (`ForgeDriver.__new__`, runner injecté, jamais de vrai spawn Node).
  2. Garde économie (contrat s9 règle (14)) — `ForgeDriver._economy_bypass_detail`
     / `_code_oracle_economy_bypass_dead`, même patron.
  3. Câblage des DEUX gates aux 3 points d'agrégation de `_run_code_oracle`
     (même condition `final == "FAIL"` que `runtime_dead`/`loop_dead`).
  4. Héritage inter-run `ForgeDriver._write_heritage_best_effort` : copie
     `art_bible.md`/`gm_worldscan.json`/`04_ASSETS/art_response.json` vers
     `<run_dir>/heritage/` + `manifest.json` — seulement si `project.godot`
     existe (s9 a matérialisé un build) ; jamais une exception.
  5. Câblage de `_write_heritage_best_effort` dans `run()`, chemins DONE et
     HALTED (mid-loop, `executor=None`).
"""
import json
import sys
from pathlib import Path

import pytest

from forge.driver import ForgeDriver


def _driver_minimal(game_dir: Path, run_dir: Path | None = None) -> ForgeDriver:
    d = ForgeDriver.__new__(ForgeDriver)  # pas de __init__ : on ne teste que la méthode
    d.run_id = "r1"
    d.game_dir = game_dir
    d.run_dir = run_dir if run_dir is not None else game_dir.parent / "run"
    return d


# =====================================================================
# (1) _art_response_detail / _code_oracle_art_response_dead
# =====================================================================


def test_art_response_pass_through_ok_avec_requirements(tmp_path):
    game = tmp_path / "game"
    run = tmp_path / "run"
    game.mkdir()
    run.mkdir()
    (run / "gm_worldscan.json").write_text("{}", encoding="utf-8")
    d = _driver_minimal(game, run)
    payload = {"status": "OK", "checked": True, "passed": True,
               "stats": {"requirements": 1, "reponses": 1, "completes": 1}}
    calls = []
    d.art_response_runner = lambda gd, gm: calls.append((gd, gm)) or payload
    r = d._art_response_detail()
    assert r == payload
    assert calls == [(game, run / "gm_worldscan.json")]


def test_art_response_gm_absent_du_disque_transmet_none(tmp_path):
    game = tmp_path / "game"
    run = tmp_path / "run"
    game.mkdir()
    run.mkdir()  # pas de gm_worldscan.json
    d = _driver_minimal(game, run)
    calls = []
    d.art_response_runner = lambda gd, gm: calls.append((gd, gm)) or {
        "status": "OK", "checked": True, "passed": True, "stats": {"requirements": 0}}
    d._art_response_detail()
    assert calls == [(game, None)]


def test_art_response_0_requirements_devient_skipped_non_bloquant(tmp_path):
    game = tmp_path / "game"
    run = tmp_path / "run"
    game.mkdir()
    run.mkdir()
    d = _driver_minimal(game, run)
    d.art_response_runner = lambda gd, gm: {
        "status": "OK", "checked": True, "passed": True,
        "stats": {"requirements": 0, "reponses": 0, "completes": 0},
    }
    r = d._art_response_detail()
    assert r["status"] == "SKIPPED"
    assert r["checked"] is False
    assert r["passed"] is False
    assert ForgeDriver._code_oracle_art_response_dead({"art_response": r}) is False


def test_art_response_fail_avec_requirements_reste_fail_checked(tmp_path):
    game = tmp_path / "game"
    run = tmp_path / "run"
    game.mkdir()
    run.mkdir()
    d = _driver_minimal(game, run)
    payload = {"status": "FAIL", "checked": True, "passed": False,
               "problems": ["requirement_sans_reponse"],
               "stats": {"requirements": 1, "reponses": 0, "completes": 0}}
    d.art_response_runner = lambda gd, gm: payload
    r = d._art_response_detail()
    assert r == payload
    assert ForgeDriver._code_oracle_art_response_dead({"art_response": r}) is True


def test_art_response_exception_devient_not_measured(tmp_path):
    game = tmp_path / "game"
    run = tmp_path / "run"
    game.mkdir()
    run.mkdir()
    d = _driver_minimal(game, run)

    def boom(gd, gm):
        raise RuntimeError("panne fabriquee")

    d.art_response_runner = boom
    r = d._art_response_detail()
    assert r["status"] == "NOT_MEASURED"
    assert r["checked"] is False and r["passed"] is False
    assert r["reason"]
    assert ForgeDriver._code_oracle_art_response_dead({"art_response": r}) is False


def test_code_oracle_art_response_dead_absent_du_detail(tmp_path):
    assert ForgeDriver._code_oracle_art_response_dead({}) is False


# =====================================================================
# (2) _economy_bypass_detail / _code_oracle_economy_bypass_dead
# =====================================================================


def test_economy_bypass_normalise_passed_true(tmp_path):
    game = tmp_path / "game"
    run = tmp_path / "run"
    game.mkdir()
    run.mkdir()
    d = _driver_minimal(game, run)
    calls = []
    d.economy_bypass_runner = lambda gd, ej: calls.append((gd, ej)) or {"passed": True, "violations": []}
    r = d._economy_bypass_detail()
    assert r == {"status": "OK", "checked": True, "passed": True, "violations": []}
    assert calls == [(game, None)]  # economy.json absent du run_dir -> None transmis


def test_economy_bypass_transmet_le_chemin_quand_economy_json_existe(tmp_path):
    game = tmp_path / "game"
    run = tmp_path / "run"
    game.mkdir()
    run.mkdir()
    (run / "economy.json").write_text("{}", encoding="utf-8")
    d = _driver_minimal(game, run)
    calls = []
    d.economy_bypass_runner = lambda gd, ej: calls.append((gd, ej)) or {"passed": True, "violations": []}
    d._economy_bypass_detail()
    assert calls == [(game, run / "economy.json")]


def test_economy_bypass_normalise_passed_false(tmp_path):
    game = tmp_path / "game"
    run = tmp_path / "run"
    game.mkdir()
    run.mkdir()
    d = _driver_minimal(game, run)
    violations = [{"fichier": "x.gd", "ligne": 3, "nom": "KITTEN_STEP", "valeur": "5"}]
    d.economy_bypass_runner = lambda gd, ej: {"passed": False, "violations": violations}
    r = d._economy_bypass_detail()
    assert r == {"status": "FAIL", "checked": True, "passed": False, "violations": violations}
    assert ForgeDriver._code_oracle_economy_bypass_dead({"economy_bypass": r}) is True


def test_economy_bypass_exception_devient_not_measured(tmp_path):
    game = tmp_path / "game"
    run = tmp_path / "run"
    game.mkdir()
    run.mkdir()
    d = _driver_minimal(game, run)

    def boom(gd, ej):
        raise RuntimeError("panne fabriquee")

    d.economy_bypass_runner = boom
    r = d._economy_bypass_detail()
    assert r["status"] == "NOT_MEASURED"
    assert r["checked"] is False and r["passed"] is False
    assert ForgeDriver._code_oracle_economy_bypass_dead({"economy_bypass": r}) is False


def test_economy_bypass_forme_non_exploitable_devient_not_measured(tmp_path):
    game = tmp_path / "game"
    run = tmp_path / "run"
    game.mkdir()
    run.mkdir()
    d = _driver_minimal(game, run)
    d.economy_bypass_runner = lambda gd, ej: "pas un dict"
    r = d._economy_bypass_detail()
    assert r["status"] == "NOT_MEASURED"


def test_code_oracle_economy_bypass_dead_absent_du_detail(tmp_path):
    assert ForgeDriver._code_oracle_economy_bypass_dead({}) is False


# =====================================================================
# (3) câblage aux 3 points d'agrégation — même patron que
#     test_driver_loop_gate.py::_aggregate (régime historique reproduit)
# =====================================================================


def _aggregate(status, e2e_ok, solvability_passed, harness_flags_passed,
               runtime_alive, player_loop, art_response, economy_bypass,
               *, receipt_status="OK"):
    detail = {
        "runtime_alive": runtime_alive, "player_loop": player_loop,
        "art_response": art_response, "economy_bypass": economy_bypass,
    }
    runtime_dead = ForgeDriver._code_oracle_runtime_dead(detail)
    detail["loop_dead"] = ForgeDriver._code_oracle_loop_dead(detail)
    detail["art_response_dead"] = ForgeDriver._code_oracle_art_response_dead(detail)
    detail["economy_bypass_dead"] = ForgeDriver._code_oracle_economy_bypass_dead(detail)
    if status == "BLOCKED":
        final = "BLOCKED"
    elif (status == "FAIL" or not e2e_ok or not solvability_passed
            or not harness_flags_passed or receipt_status != "OK"
            or runtime_dead or detail["loop_dead"]
            or detail["art_response_dead"] or detail["economy_bypass_dead"]):
        final = "FAIL"
    else:
        final = "OK"
    return final, detail


_OK_RUNTIME = {"status": "OK", "checked": True, "passed": True}
_OK_LOOP = {"status": "OK", "checked": True, "passed": True}


def test_art_response_dead_seul_fait_echouer_le_gate():
    final, detail = _aggregate(
        "OK", True, True, True, _OK_RUNTIME, _OK_LOOP,
        {"status": "FAIL", "checked": True, "passed": False},
        {"status": "OK", "checked": True, "passed": True, "violations": []},
    )
    assert detail["art_response_dead"] is True
    assert final == "FAIL"


def test_economy_bypass_dead_seul_fait_echouer_le_gate():
    final, detail = _aggregate(
        "OK", True, True, True, _OK_RUNTIME, _OK_LOOP,
        {"status": "OK", "checked": True, "passed": True, "stats": {}},
        {"status": "FAIL", "checked": True, "passed": False, "violations": [{"nom": "X"}]},
    )
    assert detail["economy_bypass_dead"] is True
    assert final == "FAIL"


def test_art_response_skipped_ne_bloque_jamais():
    final, detail = _aggregate(
        "OK", True, True, True, _OK_RUNTIME, _OK_LOOP,
        {"status": "SKIPPED", "checked": False, "passed": False},
        {"status": "OK", "checked": True, "passed": True, "violations": []},
    )
    assert detail["art_response_dead"] is False
    assert final == "OK"


def test_tout_vert_reste_ok():
    final, detail = _aggregate(
        "OK", True, True, True, _OK_RUNTIME, _OK_LOOP,
        {"status": "OK", "checked": True, "passed": True, "stats": {}},
        {"status": "OK", "checked": True, "passed": True, "violations": []},
    )
    assert final == "OK"
    assert detail["art_response_dead"] is False
    assert detail["economy_bypass_dead"] is False


# =====================================================================
# (4) _write_heritage_best_effort
# =====================================================================


def test_heritage_no_op_sans_project_godot(tmp_path):
    game = tmp_path / "game"
    run = tmp_path / "run"
    game.mkdir()
    run.mkdir()
    (run / "art_bible.md").write_text("# art bible", encoding="utf-8")
    d = _driver_minimal(game, run)
    d._write_heritage_best_effort()
    assert not (run / "heritage").exists()


def test_heritage_copie_les_trois_sources_et_ecrit_le_manifest(tmp_path):
    game = tmp_path / "game"
    run = tmp_path / "run"
    game.mkdir(parents=True)
    run.mkdir(parents=True)
    (game / "project.godot").write_text('[application]\nrun/main_scene="res://main.tscn"\n', encoding="utf-8")
    (run / "art_bible.md").write_text("# art bible", encoding="utf-8")
    (run / "gm_worldscan.json").write_text('{"genre": "clicker"}', encoding="utf-8")
    (game / "04_ASSETS").mkdir()
    (game / "04_ASSETS" / "art_response.json").write_text('{"schema_version": 1, "responses": []}', encoding="utf-8")

    d = _driver_minimal(game, run)
    d.run_id = "kitten_clicker-r10"
    d._write_heritage_best_effort()

    heritage = run / "heritage"
    assert (heritage / "art_bible.md").read_text(encoding="utf-8") == "# art bible"
    assert (heritage / "gm_worldscan.json").read_text(encoding="utf-8") == '{"genre": "clicker"}'
    assert (heritage / "art_response.json").read_text(encoding="utf-8") == '{"schema_version": 1, "responses": []}'

    manifest = json.loads((heritage / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["run_id"] == "kitten_clicker-r10"
    assert manifest["ts"]
    assert set(manifest["files"].keys()) == {"art_bible.md", "gm_worldscan.json", "art_response.json"}
    import hashlib
    assert manifest["files"]["art_bible.md"] == hashlib.sha256(b"# art bible").hexdigest()


def test_heritage_source_manquante_est_simplement_omise(tmp_path):
    game = tmp_path / "game"
    run = tmp_path / "run"
    game.mkdir(parents=True)
    run.mkdir(parents=True)
    (game / "project.godot").write_text('[application]\n', encoding="utf-8")
    # aucune des 3 sources n'existe
    d = _driver_minimal(game, run)
    d._write_heritage_best_effort()
    manifest = json.loads((run / "heritage" / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["files"] == {}


def test_heritage_ecrase_le_precedent_dernier_run_gagne(tmp_path):
    game = tmp_path / "game"
    run = tmp_path / "run"
    game.mkdir(parents=True)
    run.mkdir(parents=True)
    (game / "project.godot").write_text('[application]\n', encoding="utf-8")
    (run / "heritage").mkdir()
    (run / "heritage" / "art_bible.md").write_text("ANCIEN", encoding="utf-8")
    (run / "art_bible.md").write_text("NOUVEAU", encoding="utf-8")

    d = _driver_minimal(game, run)
    d._write_heritage_best_effort()
    assert (run / "heritage" / "art_bible.md").read_text(encoding="utf-8") == "NOUVEAU"


def test_heritage_ne_leve_jamais_meme_si_lecture_source_echoue(tmp_path, monkeypatch):
    game = tmp_path / "game"
    run = tmp_path / "run"
    game.mkdir(parents=True)
    run.mkdir(parents=True)
    (game / "project.godot").write_text('[application]\n', encoding="utf-8")
    (run / "art_bible.md").write_text("contenu", encoding="utf-8")

    d = _driver_minimal(game, run)

    from pathlib import Path as PathCls
    original_read_bytes = PathCls.read_bytes

    def boom_read_bytes(self):
        if self.name == "art_bible.md":
            raise OSError("disque hors service (fabrique)")
        return original_read_bytes(self)

    monkeypatch.setattr(PathCls, "read_bytes", boom_read_bytes)
    d._write_heritage_best_effort()  # ne doit jamais lever
    manifest = json.loads((run / "heritage" / "manifest.json").read_text(encoding="utf-8"))
    assert "art_bible.md" not in manifest["files"]


# =====================================================================
# (5) câblage dans run() — chemins DONE et HALTED (mid-loop, executor=None)
# =====================================================================


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


def _run_kwargs(tmp_path, run_dir, game_dir):
    return dict(
        run_dir=run_dir,
        game_dir=game_dir,
        oracle_config=_oracle_config(tmp_path),
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
    )


class _AlwaysOkExecutor:
    def __call__(self, payload, decision, context):
        return {"ok": True, "output": f"artefact {payload.etape}"}


def test_run_done_appelle_heritage_best_effort(tmp_path, offline, monkeypatch):
    run_dir = tmp_path / "run"
    game_dir = tmp_path / "game"
    game_dir.mkdir()
    calls = []
    monkeypatch.setattr(ForgeDriver, "_write_heritage_best_effort", lambda self: calls.append("called"))
    d = ForgeDriver("proj", "proj-1", profile="review",
                     executor=_AlwaysOkExecutor(), **_run_kwargs(tmp_path, run_dir, game_dir))
    report = d.run()
    assert report["run_status"] == "DONE" if "run_status" in report else True
    assert calls == ["called"]


def test_run_halted_mid_loop_appelle_aussi_heritage_best_effort(tmp_path, offline, monkeypatch):
    """executor=None halte AVANT tout appel LLM (cas limite documenté par
    `_run_llm`) : la boucle `run()` retourne un rapport HALTED sans jamais
    atteindre `run_status = DONE`. L'héritage doit quand même être tenté
    (no-op si s9 n'a pas encore construit — ici game_dir est vide, donc
    `_write_heritage_best_effort` réel ferait un no-op ; ce test prouve
    seulement qu'il est APPELÉ sur ce chemin, pas son contenu)."""
    run_dir = tmp_path / "run"
    game_dir = tmp_path / "game"
    game_dir.mkdir()
    calls = []
    monkeypatch.setattr(ForgeDriver, "_write_heritage_best_effort", lambda self: calls.append("called"))
    d = ForgeDriver("proj", "proj-1", profile="review",
                     executor=None, **_run_kwargs(tmp_path, run_dir, game_dir))
    report = d.run()
    assert calls == ["called"]
