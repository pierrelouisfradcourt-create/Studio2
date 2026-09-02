"""CV-3 (lot de dégel 1, 2026-07-30) — gel des règles compatible schéma v2.

Défaut mesuré : `frozen_features_from_wiremap` ne lisait que `features[]` (v1).
Un wiremap v2 (`schema_version: 2`, `lines[]`, identité = `lines[].id`) rendait
toujours `[]`, quel que soit le nombre réel de règles — un gel VIDE en silence.

Ce fichier couvre :
1. v1 INCHANGÉ (rétro-compat stricte des 17 wiremaps historiques).
2. v2 rend les identités de `lines[].id`.
3. gel vide sur v2 n'arrive plus dès qu'il y a des lignes.
4. la garde d'absence ADVISORY (`ForgeDriver._check_wiremap_frozen_presence`,
   câblée dans `_run_code_oracle`, s10a) — émise seulement quand un wiremap.json
   existe dans le run_dir sans son gel, jamais un gate.
"""
import json

from forge.driver import ForgeDriver
from forge.static_oracles import check_feature_set_frozen, frozen_features_from_wiremap

WM_V1 = {
    "features": [
        {"feature": "R1 avance auto", "fonction": "step"},
        {"feature": "R2 saut", "fonction": "jump"},
    ]
}

WM_V2 = {
    "schema_version": 2,
    "lines": [
        {"id": "params.bloc_unique", "category": "system"},
        {"id": "core.game_state", "category": "system"},
        {"id": "core.input", "category": "system"},
    ],
}


# --- 1. v1 inchangé -----------------------------------------------------------------

def test_v1_inchange_features():
    assert frozen_features_from_wiremap(WM_V1) == ["R1 avance auto", "R2 saut"]


def test_v1_check_feature_set_frozen_inchange():
    res = check_feature_set_frozen(WM_V1, ["R1 avance auto", "R2 saut"])
    assert res["passed"] is True
    assert res["checked"] is True


# --- 2. v2 : identité = lines[].id ---------------------------------------------------

def test_v2_extraction_lines_id():
    assert frozen_features_from_wiremap(WM_V2) == [
        "params.bloc_unique", "core.game_state", "core.input",
    ]


def test_v2_44_lignes_toutes_extraites():
    """Fixture réduite représentative du wiremap Snake réel (44 `lines[]`) —
    ici une fixture à 44 identités synthétiques pour prouver qu'aucune n'est
    perdue en route (pas de troncature, pas de déduplication accidentelle)."""
    wm = {"schema_version": 2, "lines": [{"id": f"rule.{i:02d}"} for i in range(44)]}
    ids = frozen_features_from_wiremap(wm)
    assert len(ids) == 44
    assert ids == [f"rule.{i:02d}" for i in range(44)]


def test_v2_lines_vide_rend_liste_vide_legitime():
    wm = {"schema_version": 2, "lines": []}
    assert frozen_features_from_wiremap(wm) == []


def test_v2_lines_absent_rend_liste_vide():
    wm = {"schema_version": 2}
    assert frozen_features_from_wiremap(wm) == []


def test_v2_gel_non_vide_quand_lignes_presentes():
    """Le défaut mesuré : avant le correctif, un wiremap v2 avec 3 lignes
    produisait un gel VIDE (lecture de `features`, absente en v2)."""
    ids = frozen_features_from_wiremap(WM_V2)
    assert ids != []
    assert len(ids) == 3


def test_v2_check_feature_set_frozen_fonctionne():
    frozen = frozen_features_from_wiremap(WM_V2)
    res = check_feature_set_frozen(WM_V2, frozen)
    assert res["passed"] is True
    assert res["checked"] is True


def test_v2_regle_ajoutee_detectee():
    frozen = frozen_features_from_wiremap(WM_V2)
    wm2 = {"schema_version": 2, "lines": WM_V2["lines"] + [{"id": "rule.triche"}]}
    res = check_feature_set_frozen(wm2, frozen)
    assert res["passed"] is False
    assert res["ajoutees"] == ["rule.triche"]


def test_v2_regle_supprimee_detectee():
    frozen = frozen_features_from_wiremap(WM_V2)
    wm2 = {"schema_version": 2, "lines": WM_V2["lines"][:2]}
    res = check_feature_set_frozen(wm2, frozen)
    assert res["passed"] is False
    assert res["supprimees"] == ["core.input"]


# --- 3. garde d'absence ADVISORY (driver, s10a) --------------------------------------

def _driver(tmp_path, run_dir_name="run"):
    return ForgeDriver(
        "g", "r1", run_dir=tmp_path / run_dir_name, profile="micro",
        key_file=tmp_path / "k.key", audit_path=tmp_path / "audit.jsonl",
    )


def _state(d):
    return {"steps": {e: {"status": "PENDING", "attempts": 0, "detail": {}}
                      for e in d.order}}


def test_flag_emis_quand_wiremap_present_sans_gel(tmp_path):
    d = _driver(tmp_path)
    d.run_dir.mkdir(parents=True)
    (d.run_dir / "wiremap.json").write_text(json.dumps(WM_V2), encoding="utf-8")
    state = _state(d)
    d._check_wiremap_frozen_presence(state)
    assert "gel des règles absent (wiremap présent non gelé)" in state.get("humangate_notes", [])


def test_flag_absent_quand_gel_present(tmp_path):
    d = _driver(tmp_path)
    d.run_dir.mkdir(parents=True)
    (d.run_dir / "wiremap.json").write_text(json.dumps(WM_V2), encoding="utf-8")
    (d.run_dir / "wiremap_frozen.json").write_text(
        json.dumps({"features": frozen_features_from_wiremap(WM_V2)}), encoding="utf-8")
    state = _state(d)
    d._check_wiremap_frozen_presence(state)
    assert state.get("humangate_notes", []) == []


def test_flag_absent_quand_aucun_wiremap(tmp_path):
    d = _driver(tmp_path)
    d.run_dir.mkdir(parents=True)
    state = _state(d)
    d._check_wiremap_frozen_presence(state)
    assert state.get("humangate_notes", []) == []


def test_flag_deduplique_sur_appels_repetes(tmp_path):
    d = _driver(tmp_path)
    d.run_dir.mkdir(parents=True)
    (d.run_dir / "wiremap.json").write_text(json.dumps(WM_V2), encoding="utf-8")
    state = _state(d)
    d._check_wiremap_frozen_presence(state)
    d._check_wiremap_frozen_presence(state)
    assert state["humangate_notes"].count(
        "gel des règles absent (wiremap présent non gelé)") == 1


def test_flag_advisory_ne_change_jamais_software_verdict(tmp_path):
    """L'appel de la garde seule, isolée de `_run_code_oracle`, ne fabrique/ne
    consomme aucun champ de verdict — elle ne touche QUE `humangate_notes`."""
    d = _driver(tmp_path)
    d.run_dir.mkdir(parents=True)
    (d.run_dir / "wiremap.json").write_text(json.dumps(WM_V2), encoding="utf-8")
    state = _state(d)
    ignored = ("humangate_notes", "updated_ts")
    before = json.dumps({k: v for k, v in state.items() if k not in ignored},
                        sort_keys=True)
    d._check_wiremap_frozen_presence(state)
    after = json.dumps({k: v for k, v in state.items() if k not in ignored},
                       sort_keys=True)
    assert before == after
