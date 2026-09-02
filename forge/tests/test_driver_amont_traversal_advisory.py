"""La sonde check_amont_traversal.mjs est attachée au reçu s10c en ADVISORY :
elle n'altère jamais le statut, et son absence/échec donne NOT_MEASURED, pas un
vert ni un rouge."""
import json
import subprocess
from pathlib import Path

import pytest

from forge.driver import ForgeDriver


def _driver_minimal(tmp_path: Path) -> ForgeDriver:
    d = ForgeDriver.__new__(ForgeDriver)   # pas de __init__ : on ne teste que la méthode
    d.run_dir = tmp_path
    d.game_dir = tmp_path / "game"
    return d


def test_la_sonde_est_attachee_en_advisory_quand_node_repond(tmp_path, monkeypatch):
    payload = {"facts": {"progression": {"reached": "PRISME"}}, "verdict": "ADVISORY"}

    def faux_run(cmd, **kw):
        assert "check_amont_traversal.mjs" in " ".join(map(str, cmd))
        assert "--json" in cmd and str(tmp_path) in map(str, cmd)
        return subprocess.CompletedProcess(cmd, 0, stdout=json.dumps(payload), stderr="")

    monkeypatch.setattr(subprocess, "run", faux_run)
    r = _driver_minimal(tmp_path)._amont_traversal_advisory()
    assert r == payload


@pytest.mark.parametrize("panne", [
    OSError("node introuvable"),
    subprocess.TimeoutExpired(cmd="node", timeout=60),
])
def test_une_panne_de_la_sonde_donne_NOT_MEASURED_jamais_une_exception(tmp_path, monkeypatch, panne):
    def faux_run(cmd, **kw):
        raise panne
    monkeypatch.setattr(subprocess, "run", faux_run)
    r = _driver_minimal(tmp_path)._amont_traversal_advisory()
    assert r["status"] == "NOT_MEASURED"
    assert r["reason"]


def test_un_exit_non_nul_ou_une_sortie_non_json_donne_NOT_MEASURED(tmp_path, monkeypatch):
    monkeypatch.setattr(subprocess, "run", lambda cmd, **kw: subprocess.CompletedProcess(cmd, 0, stdout="pas du json", stderr=""))
    assert _driver_minimal(tmp_path)._amont_traversal_advisory()["status"] == "NOT_MEASURED"
    monkeypatch.setattr(subprocess, "run", lambda cmd, **kw: subprocess.CompletedProcess(cmd, 1, stdout="", stderr="boom"))
    r = _driver_minimal(tmp_path)._amont_traversal_advisory()
    assert r["status"] == "NOT_MEASURED" and "boom" in r["reason"]


def test_le_recu_s10c_porte_amont_traversal_sans_changer_le_statut(tmp_path, monkeypatch):
    """_run_wiremap_oracle : statut = check_wiremap seul ; amont_traversal = détail."""
    from forge import driver as drv
    (tmp_path / "wiremap.json").write_text(json.dumps({"features": []}), encoding="utf-8")
    d = _driver_minimal(tmp_path)
    d.src_root = tmp_path
    monkeypatch.setattr(drv, "check_feature_set_frozen", lambda w, f: {"passed": True, "checked": True})
    monkeypatch.setattr(drv, "load_frozen_features", lambda run_dir: [])
    monkeypatch.setattr(drv, "check_wiremap", lambda w, s: {"passed": False, "features_manquantes": ["x"]})
    monkeypatch.setattr(ForgeDriver, "_amont_traversal_advisory", lambda self: {"verdict": "ADVISORY"})
    captured = {}
    monkeypatch.setattr(ForgeDriver, "_finish_step", lambda self, state, entry, status, detail: captured.update(status=status, detail=detail))
    d._run_wiremap_oracle({}, {})
    assert captured["status"] == "FAIL"
    assert captured["detail"]["amont_traversal"] == {"verdict": "ADVISORY"}
    assert captured["detail"]["features_manquantes"] == ["x"]
