"""Task 4 (lot V3 kitten_clicker) — `preuve` de WireMap doit résoudre un fichier réel.

Défaut mesuré (run 5) : `preuve` cite `core_hud.gd`/`core_economy.gd`/`core_rarity_dist.gd`,
aucun de ces fichiers n'existe dans le dépôt. `check_wiremap` ne le voyait pas (seule règle :
`preuve` non vide). Ce test durcit la règle : tout token `[\\w./-]+\\.gd` présent dans `preuve`
doit exister sous `src_root` (chemin direct, ou recherche récursive si le token n'a pas de `/`).
Une `preuve` sans `.gd` (prose) reste jugée comme avant (non vide suffit).
"""
from pathlib import Path

import pytest

from forge.static_oracles import check_wiremap

REPO = Path(__file__).resolve().parents[2]


def _write(root, rel, code=""):
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(code, encoding="utf-8")


def _wiremap(preuve):
    return {
        "schema_version": 2,
        "lines": [
            {
                "id": "logic.game_state",
                "fonction": "",
                "fichiers": [{"path": "main.gd"}],
                "preuve": preuve,
            }
        ],
    }


def test_preuve_cite_un_gd_absent_fait_echouer(tmp_path):
    _write(tmp_path, "main.gd", "func _ready():\n    pass\n")
    rep = check_wiremap(_wiremap("core_hud.gd"), tmp_path)
    assert rep["passed"] is False
    assert any(
        "core_hud.gd" in m and "absent du dépôt" in m for m in rep["preuves_absentes"]
    )


def test_preuve_cite_un_gd_present_ok(tmp_path):
    _write(tmp_path, "main.gd", "func _ready():\n    pass\n")
    _write(tmp_path, "07_TESTS/oracle/core_hud.gd", "extends Node\n")
    rep = check_wiremap(_wiremap("core_hud.gd"), tmp_path)
    assert rep["passed"] is True
    assert rep["preuves_absentes"] == []


def test_preuve_prose_sans_gd_inchangee(tmp_path):
    _write(tmp_path, "main.gd", "func _ready():\n    pass\n")
    rep = check_wiremap(_wiremap("VERT 73/73, executé manuellement"), tmp_path)
    assert rep["passed"] is True
    assert rep["preuves_absentes"] == []


def test_preuve_chemin_avec_slash_present(tmp_path):
    _write(tmp_path, "main.gd", "func _ready():\n    pass\n")
    _write(tmp_path, "tests/run_tests.gd", "extends Node\n")
    rep = check_wiremap(_wiremap("tests/run_tests.gd VERT 73/73"), tmp_path)
    assert rep["passed"] is True
    assert rep["preuves_absentes"] == []


def test_preuve_chemin_avec_slash_absent(tmp_path):
    _write(tmp_path, "main.gd", "func _ready():\n    pass\n")
    rep = check_wiremap(_wiremap("tests/run_tests.gd VERT 73/73"), tmp_path)
    assert rep["passed"] is False
    assert any(
        "tests/run_tests.gd" in m and "absent du dépôt" in m
        for m in rep["preuves_absentes"]
    )


@pytest.mark.skipif(
    not (REPO / "EVIDENCE/runs/kitten_clicker/_run5_20260821e/game_build5/09_WIREMAP/wiremap.json").exists(),
    reason="fixture wiremap.json du run 5 introuvable",
)
def test_fixture_reelle_run5_preuves_absentes():
    """Le run 5 (défaut mesuré) : preuve cite core_hud.gd/core_economy.gd/core_rarity_dist.gd,
    aucun n'existe sous src_root=GAMES/kitten_clicker."""
    import json

    # La fixture du DÉFAUT est l'archive du run 5 ; `GAMES/kitten_clicker/` porte le build courant
    # (run 7+, preuves résolues) et ne vaut plus comme fixture de ce test.
    build5 = REPO / "EVIDENCE/runs/kitten_clicker/_run5_20260821e/game_build5"
    for wm_path, src_root in ((build5 / "09_WIREMAP/wiremap.json", build5),):
        if not wm_path.exists():
            pytest.skip("archive du run 5 introuvable")
        wiremap = json.loads(wm_path.read_text(encoding="utf-8"))
        rep = check_wiremap(wiremap, src_root)
        joined = " | ".join(rep["preuves_absentes"])
        assert "core_hud.gd" in joined
        assert "core_economy.gd" in joined
        assert "core_rarity_dist.gd" in joined
        return
    pytest.skip("aucune des deux fixtures présente")
