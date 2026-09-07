"""Câblage s10c/s12 du chantier canal-de-preuve (GO Pierre 2026-09-07, plan
docs/superpowers/plans/2026-09-07-canal-de-preuve-loop.md).

Même patron que test_driver_amont_traversal_advisory.py : `ForgeDriver.__new__`
sans `__init__`, on ne teste que les méthodes ajoutées. Invariant central vérifié
ici : `_player_loop_canal_advisory`/`_player_loop_facts` sont purement ADVISORY —
elles ne changent JAMAIS le statut de s10c (`check_wiremap` seul en décide) et
n'entrent JAMAIS dans `software_verdict` (plié en `extra_advisory` à s12)."""
import json
from pathlib import Path

from forge.driver import ForgeDriver

LOOP_JSON = {"steps": [{"role": "DECISION", "ref": "P05"}]}
FEATUREMAP = {"systemes": [{"features": [{"capacites": [
    {"id": "cap_arbitrage", "source_ref": "P05"},
]}]}]}


def _driver_minimal(tmp_path: Path, project: str = "proj") -> ForgeDriver:
    d = ForgeDriver.__new__(ForgeDriver)
    d.run_dir = tmp_path
    d.game_dir = tmp_path / "game"
    d.project = project
    d.src_root = tmp_path
    return d


def _seed(tmp_path):
    (tmp_path / "featuremap.json").write_text(json.dumps(FEATUREMAP), encoding="utf-8")
    (tmp_path / "loop.json").write_text(json.dumps(LOOP_JSON), encoding="utf-8")


# --- _player_loop_canal_advisory : lit run_dir, jamais d'exception -------------

def test_wiremap_sans_canal_rend_not_measured_en_couverture(tmp_path):
    _seed(tmp_path)
    d = _driver_minimal(tmp_path)
    wiremap = {"features": [
        {"feature": "R9", "couvre": ["cap_arbitrage"], "preuve": "logic.test.mjs::comparerPolitiques"},
    ]}
    r = d._player_loop_canal_advisory(wiremap)
    assert r["couverture"]["status"] == "NOT_MEASURED"
    assert r["forme"]["passed"] is True


def test_white_box_seul_rend_couverture_fail(tmp_path):
    _seed(tmp_path)
    d = _driver_minimal(tmp_path)
    wiremap = {"features": [
        {"feature": "R1", "couvre": ["cap_x"], "canal": "PLAYER_LOOP", "preuve_ref": "P01"},
        {"feature": "R9", "couvre": ["cap_arbitrage"], "canal": "WHITE_BOX"},
    ]}
    r = d._player_loop_canal_advisory(wiremap)
    assert r["couverture"]["status"] == "FAIL"
    assert "P05" in r["couverture"]["roles_manquants"]


def test_featuremap_et_loop_json_absents_ne_crashent_pas(tmp_path):
    """Aucun featuremap.json/loop.json dans run_dir — _read_json rend None,
    remplacé par {} : la fonction reste NOT_MEASURED, jamais une exception."""
    d = _driver_minimal(tmp_path)
    wiremap = {"features": [{"feature": "R1", "canal": "PLAYER_LOOP", "preuve_ref": "P01"}]}
    r = d._player_loop_canal_advisory(wiremap)
    assert r["couverture"]["status"] in ("NOT_MEASURED", "PASS")


def test_preuve_ref_observee_dans_le_journal_reel_du_run_dir(tmp_path):
    _seed(tmp_path)
    d = _driver_minimal(tmp_path, project="chaton_clicker")
    (tmp_path / "evidence").mkdir()
    (tmp_path / "evidence" / "oracle_chaton_clicker.log").write_text(
        "P06 entrée : clic réel sur acheter_producteur_0\n", encoding="utf-8")
    wiremap = {"features": [
        {"feature": "R6", "couvre": ["cap_x"], "canal": "PLAYER_LOOP", "preuve_ref": "P06"},
    ]}
    r = d._player_loop_canal_advisory(wiremap)
    assert r["preuve_execution"]["passed"] is True


def test_preuve_ref_absente_du_journal_echoue(tmp_path):
    _seed(tmp_path)
    d = _driver_minimal(tmp_path, project="chaton_clicker")
    (tmp_path / "evidence").mkdir()
    (tmp_path / "evidence" / "oracle_chaton_clicker.log").write_text(
        "rien à voir ici\n", encoding="utf-8")
    wiremap = {"features": [
        {"feature": "R6", "couvre": ["cap_x"], "canal": "PLAYER_LOOP", "preuve_ref": "P06"},
    ]}
    r = d._player_loop_canal_advisory(wiremap)
    assert r["preuve_execution"]["passed"] is False


# --- _run_wiremap_oracle : le statut de s10c reste celui de check_wiremap seul --

def test_le_recu_s10c_porte_canal_sans_changer_le_statut(tmp_path, monkeypatch):
    from forge import driver as drv
    _seed(tmp_path)
    (tmp_path / "wiremap.json").write_text(json.dumps({"features": [
        {"feature": "R9", "couvre": ["cap_arbitrage"], "canal": "WHITE_BOX",
         "fonction": "f", "fichiers": []},
    ]}), encoding="utf-8")
    d = _driver_minimal(tmp_path)
    monkeypatch.setattr(drv, "check_feature_set_frozen", lambda w, f: {"passed": True, "checked": True})
    monkeypatch.setattr(drv, "check_wiremap", lambda w, s: {"passed": True, "raisons": []})
    d._amont_traversal_advisory = lambda: {"status": "NOT_MEASURED"}
    calls = []
    d._finish_step = lambda state, entry, status, detail: calls.append((status, detail))
    d._run_wiremap_oracle({}, {})
    status, detail = calls[0]
    assert status == "OK"  # check_wiremap seul décide, malgré le canal WHITE_BOX en dessous
    assert detail["canal"]["couverture"]["status"] == "FAIL"  # mesuré, pas caché


# --- _player_loop_facts : advisory pour s12, jamais dans software_verdict ------

def test_player_loop_facts_vide_si_not_measured():
    d = ForgeDriver.__new__(ForgeDriver)
    state = {"steps": {"s10c-oracle-wiremap": {"detail": {
        "canal": {"couverture": {"status": "NOT_MEASURED"}, "forme": {"passed": True},
                 "preuve_execution": {"passed": True}}}}}}
    assert d._player_loop_facts(state) == ()


def test_player_loop_facts_vide_si_aucun_champ_canal():
    """Run antérieur au chantier : detail.canal absent -> rien à signaler (pas
    de pénalité rétroactive, symétrique du 'pas de louange rétroactive')."""
    d = ForgeDriver.__new__(ForgeDriver)
    state = {"steps": {"s10c-oracle-wiremap": {"detail": {}}}}
    assert d._player_loop_facts(state) == ()


def test_player_loop_facts_nomme_les_roles_manquants():
    d = ForgeDriver.__new__(ForgeDriver)
    state = {"steps": {"s10c-oracle-wiremap": {"detail": {
        "canal": {
            "forme": {"passed": True, "raisons": []},
            "couverture": {"status": "FAIL", "roles_manquants": ["P05"], "raisons": []},
            "preuve_execution": {"passed": True, "raisons": []},
        }}}}}
    facts = d._player_loop_facts(state)
    assert len(facts) == 1
    assert "P05" in facts[0]
    assert "canal-de-preuve" in facts[0]
