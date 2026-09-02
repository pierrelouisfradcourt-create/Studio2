"""Sonde bot-joueur `player_loop.gd` (Task 5, lot « game loop », 2026-08-22) : le bot
n'a que les entrées d'un joueur (InputEvent + lecture de Label groupe `hud`) — JAMAIS
Economy/api_*/05_SYSTEMS/runtime.gd (garde anti-contournement non négociable, décision
Pierre). Patron de `test_runtime_alive_probe.py` : source statique + `run_player_loop`
piloté par gpu_runner factice.

ÉTAGE UNITAIRE (scission du 2026-08-29, GO Pierre) : AUCUN test de ce fichier ne lance
de process. Les 7 tests qui lançaient un VRAI binaire Godot avec fenêtre GPU (50-180 s
chacun) vivent désormais dans `test_player_loop_probe_gpu.py`, marqués
`@pytest.mark.gpu_window` — déplacés sans aucune modification de logique."""
import json
from pathlib import Path

from forge import product_oracle_godot as pog

REPO = Path(__file__).resolve().parents[2]
PROBE = REPO / "forge" / "godot_probes" / "player_loop.gd"


def _line(ok, fails, data):
    return "FORGE_ORACLE player_loop " + json.dumps({"ok": ok, "fails": list(fails), "data": data})


# --- source statique --------------------------------------------------------


def test_la_sonde_existe_et_est_generique():
    src = PROBE.read_text(encoding="utf-8")
    assert "extends SceneTree" in src
    assert "InputEventMouseButton" in src
    assert 'get_nodes_in_group("affordance")' in src
    assert 'get_nodes_in_group("hud")' in src
    assert "run/main_scene" in src


def test_la_sonde_ne_connait_aucune_connaissance_du_jeu():
    src = PROBE.read_text(encoding="utf-8")
    for token in ("Economy", "api_", "05_SYSTEMS", "runtime.gd"):
        assert token not in src, f"token interdit '{token}' trouvé dans la sonde"


def test_la_sonde_porte_les_nouveaux_predicats():
    src = PROBE.read_text(encoding="utf-8")
    for token in ("new_distinct", "appears", "increases_more_than", "decreases", "resets", "replay"):
        assert token in src, f"predicat/mecanisme '{token}' absent de la sonde"


def test_la_sonde_porte_le_role_decision():
    src = PROBE.read_text(encoding="utf-8")
    for token in ("DECISION", "policies", "_reset_scene", "nondominance"):
        assert token in src, f"token '{token}' absent de la sonde (role DECISION)"


def test_la_sonde_compte_les_frames_par_step_et_porte_target_frames():
    """Lot B T4 (2026-08-23) : chaque step doit porter `frames`, et un step peut
    porter `target_frames` (min/max/ref) qui borne son PASS."""
    src = PROBE.read_text(encoding="utf-8")
    for token in ("target_frames", '"frames"', "_step_frame_start", "_targets"):
        assert token in src, f"token '{token}' absent de la sonde (frames/target_frames)"


# --- run_player_loop : ok / fail / not_measured / muet, via gpu_runner factice ----


def _game_with_loop_json(tmp_path) -> Path:
    game = tmp_path / "game"
    (game / "03_WORLD").mkdir(parents=True)
    (game / "03_WORLD" / "loop.json").write_text('{"steps": []}', encoding="utf-8")
    return game


def test_ok_quand_tous_les_steps_passent(tmp_path):
    game = _game_with_loop_json(tmp_path)
    data = {"steps": [{"role": "PLAYER_GOAL", "ref": "PG1", "pass": True}],
            "reached_role": "META_LOOP", "frames": 500}
    stdout = _line(True, [], data)
    r = pog.run_player_loop(game, binary_resolver=lambda: "godot",
                            gpu_runner=lambda *a, **k: {"returncode": 0, "stdout": stdout, "stderr": ""})
    assert r["status"] == "OK" and r["passed"] is True and r["checked"] is True
    assert r["payload"]["data"]["reached_role"] == "META_LOOP"


def test_fail_quand_un_step_echoue(tmp_path):
    game = _game_with_loop_json(tmp_path)
    data = {"steps": [{"role": "PLAYER_ACTION", "ref": "PA2", "pass": False,
                       "reason": "affordance 'acheter_chaton' introuvable"}],
            "reached_role": "PLAYER_ACTION", "frames": 200}
    stdout = _line(False, ["step PA2 (PLAYER_ACTION) : predicat 'increases' non satisfait"], data)
    r = pog.run_player_loop(game, binary_resolver=lambda: "godot",
                            gpu_runner=lambda *a, **k: {"returncode": 1, "stdout": stdout, "stderr": ""})
    assert r["status"] == "FAIL" and r["passed"] is False
    assert r["payload"]["data"]["reached_role"] == "PLAYER_ACTION"


def test_not_measured_sans_godot(tmp_path):
    game = _game_with_loop_json(tmp_path)
    r = pog.run_player_loop(game, binary_resolver=lambda: None)
    assert r["status"] == "NOT_MEASURED" and r["checked"] is False and r["passed"] is False


def test_fail_sortie_muette(tmp_path):
    game = _game_with_loop_json(tmp_path)
    r = pog.run_player_loop(game, binary_resolver=lambda: "godot",
                            gpu_runner=lambda *a, **k: {"returncode": 1, "stdout": "", "stderr": "crash"})
    assert r["status"] == "FAIL" and r["checked"] is True
    assert "muette" in " ".join(r["fails"])


def test_skipped_sans_loop_json(tmp_path):
    game = tmp_path / "game"
    game.mkdir()
    calls = []
    r = pog.run_player_loop(
        game, binary_resolver=lambda: "godot",
        gpu_runner=lambda *a, **k: calls.append(a) or (_ for _ in ()).throw(AssertionError("jamais appelé")))
    assert calls == []
    assert r["status"] == "SKIPPED" and r["checked"] is False and r["passed"] is False


def test_fail_sans_spawn_quand_sha_altere(tmp_path):
    game = _game_with_loop_json(tmp_path)
    run_dir = tmp_path / "run"
    run_dir.mkdir()
    (run_dir / "loop.json").write_text('{"steps": [1]}', encoding="utf-8")  # sha != celui du jeu
    r = pog.run_player_loop(
        game, run_dir=run_dir, binary_resolver=lambda: "godot",
        gpu_runner=lambda *a, **k: (_ for _ in ()).throw(AssertionError("jamais appelé — sha altéré")))
    assert r["status"] == "FAIL" and r["checked"] is True
    assert "altéré" in " ".join(r["fails"])


def test_pas_de_fail_sha_quand_identique(tmp_path):
    game = _game_with_loop_json(tmp_path)
    run_dir = tmp_path / "run"
    run_dir.mkdir()
    (run_dir / "loop.json").write_text('{"steps": []}', encoding="utf-8")  # même contenu, même sha
    stdout = _line(True, [], {"steps": [], "reached_role": "NONE", "frames": 60})
    r = pog.run_player_loop(
        game, run_dir=run_dir, binary_resolver=lambda: "godot",
        gpu_runner=lambda *a, **k: {"returncode": 0, "stdout": stdout, "stderr": ""})
    assert r["status"] == "OK"





# --- mécanisme REPEAT/deltas au niveau product_oracle_godot, sans Godot ------


def test_run_player_loop_accepte_payload_avec_decision(tmp_path):
    game = _game_with_loop_json(tmp_path)
    data = {
        "steps": [{"role": "DECISION", "ref": "d1", "pass": True, "before": "", "after": "", "reason": ""}],
        "reached_role": "DECISION", "frames": 3000, "deltas": {}, "seen": {},
        "decision": {
            "ref": "d1", "options": ["p_a", "p_b"], "boot_reproducible": True,
            "information": {"A": True, "B": True},
            "states": {
                "p_a": {"hud": {"objectif": "A"}, "affordances": ["p_a"], "objectif": "A"},
                "p_b": {"hud": {"objectif": "B"}, "affordances": ["p_b"], "objectif": "B"},
            },
            "immediate": {"A": True, "B": True}, "future": True,
            "nondominance": {"matrix": {"p_a": {"idle": 1.0}, "p_b": {"idle": 2.0}}, "pass": True},
            "player_goal": True, "pass": True, "reasons": [],
        },
    }
    stdout = _line(True, [], data)
    r = pog.run_player_loop(game, binary_resolver=lambda: "godot",
                            gpu_runner=lambda *a, **k: {"returncode": 0, "stdout": stdout, "stderr": ""})
    assert r["status"] == "OK" and r["passed"] is True
    assert r["payload"]["data"]["decision"] == data["decision"]
    assert r["payload"]["data"]["reached_role"] == "DECISION"


def test_run_player_loop_accepte_payload_avec_replays_et_deltas(tmp_path):
    game = _game_with_loop_json(tmp_path)
    data = {
        "steps": [
            {"role": "REPEAT", "ref": "H1", "pass": True,
             "replays": [{"ref": "B1", "pass": True, "before": "0", "after": "5"}]},
        ],
        "reached_role": "ADVANTAGE", "frames": 900,
        "deltas": {"B1": 5.0, "B1@replay": 7.0, "J1": 9.0},
        "seen": {"objectif": ["a", "b"]},
    }
    stdout = _line(True, [], data)
    r = pog.run_player_loop(game, binary_resolver=lambda: "godot",
                            gpu_runner=lambda *a, **k: {"returncode": 0, "stdout": stdout, "stderr": ""})
    assert r["status"] == "OK" and r["passed"] is True
    assert r["payload"]["data"]["deltas"] == {"B1": 5.0, "B1@replay": 7.0, "J1": 9.0}
    assert r["payload"]["data"]["seen"] == {"objectif": ["a", "b"]}
    assert r["payload"]["data"]["steps"][0]["replays"][0]["ref"] == "B1"


def test_run_player_loop_accepte_payload_avec_targets(tmp_path):
    """Lot B T4 : passthrough pur de `data.targets` (bornes de tolérance des
    steps portant `target_frames`), sans schéma imposé côté product_oracle_godot."""
    game = _game_with_loop_json(tmp_path)
    data = {
        "steps": [{"role": "PLAYER_ACTION", "ref": "b_click", "pass": True,
                   "before": "0", "after": "5", "reason": "", "frames": 42}],
        "reached_role": "PLAYER_ACTION", "frames": 100, "deltas": {}, "seen": {},
        "targets": [{"ref": "b_click", "metric_ref": "gm_worldscan:game_master.progression_metrics.m1",
                     "frames": 42, "min": 0, "max": 100, "pass": True}],
    }
    stdout = _line(True, [], data)
    r = pog.run_player_loop(game, binary_resolver=lambda: "godot",
                            gpu_runner=lambda *a, **k: {"returncode": 0, "stdout": stdout, "stderr": ""})
    assert r["status"] == "OK" and r["passed"] is True
    assert r["payload"]["data"]["targets"] == data["targets"]
    assert r["payload"]["data"]["steps"][0]["frames"] == 42


