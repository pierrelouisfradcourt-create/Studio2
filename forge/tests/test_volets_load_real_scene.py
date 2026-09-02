"""Garde statique (Task 3, lot V3 assemblage runtime, décision Pierre 2026-08-22) :
un volet `07_TESTS/oracle/*.gd` qui n'atteste pas charger `res://main.tscn` (dans sa
SOURCE, hors commentaires) prouve un jeu qu'il a lui-même construit, pas le jeu réel.
Ce volet est rejeté STATIQUEMENT — le runner Godot n'est même pas invoqué."""
from pathlib import Path

from forge import product_oracle_godot as pog

REPO = Path(__file__).resolve().parents[2]


def _write_oracle(tmp_path: Path, name: str, source: str) -> Path:
    oracle_dir = tmp_path / "07_TESTS" / "oracle"
    oracle_dir.mkdir(parents=True, exist_ok=True)
    path = oracle_dir / name
    path.write_text(source, encoding="utf-8")
    return path


def _never_called(*_a, **_k):
    raise AssertionError("le runner ne doit pas être appelé pour un volet rejeté statiquement")


def test_volet_sans_chargement_de_main_tscn_est_rejete_statiquement(tmp_path):
    _write_oracle(tmp_path, "core_fake.gd", (
        "extends SceneTree\n"
        "# FORGE_ORACLE\n"
        "func _init():\n"
        "    var hud = load(\"res://05_SYSTEMS/hud.gd\").new()\n"
        "    print('FORGE_ORACLE core_fake {\"ok\": true, \"fails\": []}')\n"
        "    quit(0)\n"
    ))
    result = pog.run_godot_product_oracle(
        tmp_path, binary_resolver=lambda: "godot", runner=_never_called, gpu_runner=_never_called)
    r = result["core_fake"]
    assert r["status"] == "FAIL"
    assert r["checked"] is True
    assert r["mode_execution"] == "static_guard"
    assert any("res://main.tscn" in f for f in r["fails"])


def test_volet_avec_load_main_tscn_appelle_le_runner(tmp_path):
    _write_oracle(tmp_path, "core_real.gd", (
        "extends SceneTree\n"
        "# FORGE_ORACLE\n"
        "func _init():\n"
        "    var s = load(\"res://main.tscn\")\n"
        "    print('FORGE_ORACLE core_real {\"ok\": true, \"fails\": []}')\n"
        "    quit(0)\n"
    ))
    called = {"n": 0}

    def runner(binary, game_dir, script_res_path, *, timeout_s):
        called["n"] += 1
        return {"returncode": 0, "stdout": 'FORGE_ORACLE core_real {"ok": true, "fails": []}', "stderr": ""}

    result = pog.run_godot_product_oracle(
        tmp_path, binary_resolver=lambda: "godot", runner=runner)
    assert called["n"] == 1
    assert result["core_real"]["status"] == "OK"


def test_mention_uniquement_en_commentaire_est_rejetee(tmp_path):
    _write_oracle(tmp_path, "core_commented.gd", (
        "extends SceneTree\n"
        "# FORGE_ORACLE\n"
        "# load(\"res://main.tscn\") -- juste un commentaire, pas du vrai code\n"
        "func _init():\n"
        "    print('FORGE_ORACLE core_commented {\"ok\": true, \"fails\": []}')\n"
        "    quit(0)\n"
    ))
    result = pog.run_godot_product_oracle(
        tmp_path, binary_resolver=lambda: "godot", runner=_never_called, gpu_runner=_never_called)
    r = result["core_commented"]
    assert r["status"] == "FAIL"
    assert r["mode_execution"] == "static_guard"


def test_fixture_reelle_kitten_clicker_3_volets_fail_statique():
    # Fixture du DÉFAUT = archive du run 5 (volets qui assemblent leur propre scène) ;
    # `GAMES/kitten_clicker/` = build courant (run 7+, volets conformes), plus une fixture de ce test.
    for cand in (REPO / "EVIDENCE/runs/kitten_clicker/_run5_20260821e/game_build5",):
        oracle_dir = cand / "07_TESTS" / "oracle"
        if oracle_dir.is_dir() and list(oracle_dir.glob("*.gd")):
            result = pog.run_godot_product_oracle(
                cand, binary_resolver=lambda: "godot", runner=_never_called, gpu_runner=_never_called)
            assert result, "aucun volet découvert sur la fixture réelle"
            for name, r in result.items():
                assert r["status"] == "FAIL", f"{name} n'est pas rejeté statiquement : {r}"
                assert r["mode_execution"] == "static_guard", f"{name} : {r}"
            return
    import pytest
    pytest.skip("fixture kitten_clicker introuvable")
