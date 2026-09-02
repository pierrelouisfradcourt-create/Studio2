import json, re, shutil
from pathlib import Path
import pytest
from forge import product_oracle_godot as pog

REPO = Path(__file__).resolve().parents[2]
PROBE = REPO / "forge/godot_probes/runtime_alive.gd"

def _line(data, ok=True, fails=()):
    return "FORGE_ORACLE runtime_alive " + json.dumps({"ok": ok, "fails": list(fails), "data": data})

def test_la_sonde_existe_et_charge_la_vraie_scene():
    src = PROBE.read_text(encoding="utf-8")
    assert "extends SceneTree" in src
    assert 'load("res://main.tscn")' in src or "run/main_scene" in src
    assert "InputEventMouseButton" in src          # le clic est injecté, pas simulé par un appel direct
    assert "get_image()" in src                     # capture réelle

def test_ok_quand_la_scene_vit(tmp_path):
    stdout = _line({"scene": "res://main.tscn", "loaded": True, "root_children": 1, "nodes_total": 9,
                    "scripted_nodes": 5, "system_scripts": 4, "nonmonochrome": True,
                    "changed_after_click": True, "frames": 120})
    r = pog.run_runtime_alive(tmp_path, binary_resolver=lambda: "godot",
                              gpu_runner=lambda *a, **k: {"returncode": 0, "stdout": stdout, "stderr": ""})
    assert r["passed"] is True and r["status"] == "OK" and r["mode_execution"] == "gpu_window"
    assert r["payload"]["data"]["changed_after_click"] is True

def test_fail_quand_l_ecran_ne_change_pas_apres_le_clic(tmp_path):
    stdout = _line({"scene": "res://main.tscn", "loaded": True, "root_children": 1, "nodes_total": 2,
                    "scripted_nodes": 1, "system_scripts": 0, "nonmonochrome": True,
                    "changed_after_click": False, "frames": 120}, ok=False,
                   fails=["aucun changement d'image apres le clic"])
    r = pog.run_runtime_alive(tmp_path, binary_resolver=lambda: "godot",
                              gpu_runner=lambda *a, **k: {"returncode": 1, "stdout": stdout, "stderr": ""})
    assert r["passed"] is False and "clic" in " ".join(r["fails"])

def test_not_measured_sans_godot(tmp_path):
    r = pog.run_runtime_alive(tmp_path, binary_resolver=lambda: None)
    assert r["checked"] is False and r["status"] == "NOT_MEASURED" and r["passed"] is False

def test_sortie_sans_marqueur_est_un_fail_honnete(tmp_path):
    r = pog.run_runtime_alive(tmp_path, binary_resolver=lambda: "godot",
                              gpu_runner=lambda *a, **k: {"returncode": 0, "stdout": "Godot Engine v4\n", "stderr": ""})
    assert r["passed"] is False and r["checked"] is True

@pytest.mark.skipif(not (REPO / "forge/godot.config.json").exists(), reason="binaire Godot absent sur ce poste")
def test_fixture_reelle_run5_le_jeu_est_statique():
    """Le build du run 5 (archivé) est LA fixture du défaut : scène chargée, rien ne change au clic."""
    # La fixture du DÉFAUT est l'archive du run 5 (jeu statique) ; `GAMES/kitten_clicker/` porte
    # le build courant (run 6+, vivant) et ne vaut plus comme fixture de ce test.
    for cand in (REPO / "EVIDENCE/runs/kitten_clicker/_run5_20260821e/game_build5", REPO / "GAMES/kitten_clicker"):
        if (cand / "project.godot").exists():
            r = pog.run_runtime_alive(cand)
            assert r["checked"] is True
            assert r["payload"]["data"]["loaded"] is True
            assert r["passed"] is False and r["payload"]["data"]["changed_after_click"] is False
            return
    pytest.skip("build du run 5 introuvable")
