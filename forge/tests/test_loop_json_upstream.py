"""V4 GAME LOOP (2026-08-22, GO Pierre) — `loop.json` comme artefact AMONT.

`loop.json` est la projection déterministe du Prisme (matérialisée par run_real
après prisme.json, cf. Task 1). Il doit atteindre s3-decompo, s5-wiremap et
s9-build-godot-standard comme ENTRÉE à lire (jamais une source de vérité) : ce
test vérifie que `_UPSTREAM_BY_STEP` le porte bien pour ces 3 étapes, que les
deux copies (context_manifest.py / run_real.py) restent identiques (déjà couvert
par test_context_manifest.py::test_upstream_table_matches_run_real_exactly, mais
redondant ici pour ce champ précis), et que `upstream_artifacts_section` l'injecte
réellement quand le fichier existe dans le run_dir.

    PYTHONPATH=scripts .venv312/Scripts/python.exe -m pytest \
        forge/tests/test_loop_json_upstream.py -v
"""
from forge import context_manifest as cm
from forge import run_real


_ETAPES_ATTENDUES = ("s3-decompo", "s5-wiremap", "s9-build-godot-standard")


def test_loop_json_present_dans_les_trois_etapes_run_real():
    for etape in _ETAPES_ATTENDUES:
        assert "loop.json" in run_real._UPSTREAM_BY_STEP[etape], (
            f"{etape} doit recevoir loop.json (forge.run_real._UPSTREAM_BY_STEP)"
        )


def test_loop_json_present_dans_les_trois_etapes_context_manifest():
    for etape in _ETAPES_ATTENDUES:
        assert "loop.json" in cm._UPSTREAM_BY_STEP[etape], (
            f"{etape} doit recevoir loop.json (forge.context_manifest._UPSTREAM_BY_STEP)"
        )


def test_les_deux_copies_restent_identiques():
    """Duplication déclarée anti-import-circulaire (cf. docstring de
    context_manifest.py) : toute divergence future doit casser ce test."""
    assert cm._UPSTREAM_BY_STEP == run_real._UPSTREAM_BY_STEP


def test_upstream_artifacts_section_injecte_loop_json_quand_present(tmp_path):
    (tmp_path / "loop.json").write_text(
        '{"schema_version": 1, "game_id": "kitten_clicker", "steps": []}',
        encoding="utf-8",
    )
    section = run_real.upstream_artifacts_section("s3-decompo", tmp_path)
    assert "loop.json" in section
    assert "kitten_clicker" in section


def test_upstream_artifacts_section_omet_loop_json_absent(tmp_path):
    """Comportement existant préservé : fichier absent => omis, jamais bloquant.
    D'autres artefacts amont présents pour que la section ne soit pas vide."""
    (tmp_path / "charter.yaml").write_text("game_id: kitten_clicker\n", encoding="utf-8")
    section = run_real.upstream_artifacts_section("s3-decompo", tmp_path)
    assert "charter.yaml" in section
    assert "loop.json" not in section
