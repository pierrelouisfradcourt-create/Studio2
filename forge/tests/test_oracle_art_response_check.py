"""`oracle.run_art_response_check` — sonde `check_art_response.mjs` attachée au
gate produit du driver (Lot B, T3, 2026-08-23). Patron strict de
`test_driver_amont_traversal_advisory.py` : le spawn de process est ICI, dans
oracle.py, jamais dans driver.py (invariant `test_driver_ne_spawn_pas_directement`).
"""
import json
import subprocess
from pathlib import Path

import pytest

from forge.oracle import run_art_response_check


def test_ok_quand_le_script_repond_ok(tmp_path, monkeypatch):
    payload = {"ok": True, "problems": [], "stats": {"requirements": 0, "reponses": 0, "completes": 0}}

    def faux_run(cmd, **kw):
        assert "check_art_response.mjs" in " ".join(map(str, cmd))
        assert "--json" in cmd and str(tmp_path) in map(str, cmd)
        return subprocess.CompletedProcess(cmd, 0, stdout=json.dumps(payload), stderr="")

    monkeypatch.setattr(subprocess, "run", faux_run)
    r = run_art_response_check(tmp_path, None)
    assert r["status"] == "OK"
    assert r["checked"] is True
    assert r["passed"] is True
    assert r["stats"] == payload["stats"]


def test_fail_avec_exit_1_reste_une_mesure_pas_un_not_measured(tmp_path, monkeypatch):
    payload = {"ok": False, "problems": ["requirement_sans_reponse"], "stats": {"requirements": 1, "reponses": 0, "completes": 0}}

    def faux_run(cmd, **kw):
        return subprocess.CompletedProcess(cmd, 1, stdout=json.dumps(payload), stderr="")

    monkeypatch.setattr(subprocess, "run", faux_run)
    r = run_art_response_check(tmp_path, None)
    assert r["status"] == "FAIL"
    assert r["checked"] is True
    assert r["passed"] is False
    assert r["problems"] == ["requirement_sans_reponse"]


def test_gm_path_transmis_quand_le_fichier_existe(tmp_path, monkeypatch):
    gm_path = tmp_path / "gm_worldscan.json"
    gm_path.write_text("{}", encoding="utf-8")
    seen = {}

    def faux_run(cmd, **kw):
        seen["cmd"] = cmd
        return subprocess.CompletedProcess(cmd, 0, stdout=json.dumps({"ok": True, "problems": [], "stats": {}}), stderr="")

    monkeypatch.setattr(subprocess, "run", faux_run)
    run_art_response_check(tmp_path, gm_path)
    assert "--gm" in seen["cmd"]
    assert str(gm_path) in seen["cmd"]


def test_gm_path_absent_du_disque_nest_pas_transmis(tmp_path, monkeypatch):
    seen = {}

    def faux_run(cmd, **kw):
        seen["cmd"] = cmd
        return subprocess.CompletedProcess(cmd, 0, stdout=json.dumps({"ok": True, "problems": [], "stats": {}}), stderr="")

    monkeypatch.setattr(subprocess, "run", faux_run)
    run_art_response_check(tmp_path, tmp_path / "inexistant.json")
    assert "--gm" not in seen["cmd"]


@pytest.mark.parametrize("panne", [
    OSError("node introuvable"),
    subprocess.TimeoutExpired(cmd="node", timeout=60),
])
def test_une_panne_de_la_sonde_donne_not_measured_jamais_une_exception(tmp_path, monkeypatch, panne):
    def faux_run(cmd, **kw):
        raise panne
    monkeypatch.setattr(subprocess, "run", faux_run)
    r = run_art_response_check(tmp_path, None)
    assert r["status"] == "NOT_MEASURED"
    assert r["reason"]


def test_exit_code_inattendu_donne_not_measured(tmp_path, monkeypatch):
    monkeypatch.setattr(subprocess, "run", lambda cmd, **kw: subprocess.CompletedProcess(cmd, 2, stdout="", stderr="usage"))
    r = run_art_response_check(tmp_path, None)
    assert r["status"] == "NOT_MEASURED"
    assert "usage" in r["reason"]


def test_sortie_non_json_donne_not_measured(tmp_path, monkeypatch):
    monkeypatch.setattr(subprocess, "run", lambda cmd, **kw: subprocess.CompletedProcess(cmd, 0, stdout="pas du json", stderr=""))
    r = run_art_response_check(tmp_path, None)
    assert r["status"] == "NOT_MEASURED"


def test_reel_sur_le_run_9_gm_sans_game_master_rend_ok(tmp_path):
    """Bout-en-bout (spawn RÉEL de node), même discipline que
    test_check_loop_bypass_sur_run6_mesure_les_violations_connues : mesure la
    fixture archivée si elle existe sur ce poste, skip proprement sinon."""
    repo_root = Path(__file__).resolve().parents[2]
    game_dir = repo_root / "EVIDENCE/runs/kitten_clicker/_run9_20260823a/game_build9"
    gm_path = repo_root / "EVIDENCE/runs/kitten_clicker/_run9_20260823a/gm_worldscan.json"
    if not game_dir.is_dir() or not gm_path.is_file():
        pytest.skip("fixture run 9 introuvable sur ce poste")
    r = run_art_response_check(game_dir, gm_path, timeout=30)
    assert r["status"] == "OK"
    assert r["stats"]["requirements"] == 0
