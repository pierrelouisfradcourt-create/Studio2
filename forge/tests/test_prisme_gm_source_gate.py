"""Lot B (2026-08-23) — GATE « le Prisme cite le Game Master ».

Quand `<run_dir>/gm_worldscan.json` porte un bloc `game_master`, toute exigence de
BOUCLE du Prisme (acteur PLAYER, ou loop_role ≠ NONE) doit citer une adresse
`gm_worldscan:game_master.loops.<loop>.<step_id>` ou
`gm_worldscan:game_master.grey_blocks.<id>` QUI RÉSOUT. Sinon `prisme.json` n'est
pas matérialisable (même régime que `advisory` / `sources_consumed`). Sans bloc
`game_master` (runs antérieurs au Lot B) : comportement strictement inchangé.

Mesuré : le run 9 (`_run9_20260823a`) a 13 exigences de boucle, 0 sourcée GM — mais
son gm_worldscan.json n'a pas de `game_master`, donc il reste accepté (régime ancien).
"""
import json
from pathlib import Path

import pytest

from forge import run_real

REPO = Path(__file__).resolve().parents[2]
RUN9 = REPO / "EVIDENCE/runs/kitten_clicker/_run9_20260823a"
GM_FIXTURE = REPO / "forge/tests/fixtures/gm_game_master_valid.json"


def _gm_with_block():
    gm = json.loads((RUN9 / "gm_worldscan.json").read_text(encoding="utf-8"))
    gm["game_master"] = json.loads(GM_FIXTURE.read_text(encoding="utf-8"))
    return gm


def _first_loop_step_address(gm):
    loops = gm["game_master"]["loops"]
    loop_name = next(iter(loops))
    return f"gm_worldscan:game_master.loops.{loop_name}.{loops[loop_name]['steps'][0]['id']}"


def _prisme_min(reference):
    return {"exigences": [
        {"id": "b_click", "source": "EXPECTED", "acteur": "PLAYER", "loop_role": "PLAYER_ACTION",
         "affordance": "pelote", "reference": reference,
         "observe": {"hud": "ronrons", "predicate": "increases"}},
        {"id": "content_x", "source": "EXPECTED", "reference": "story_bible:whatever"},
    ]}


@pytest.mark.skipif(not (RUN9 / "prisme.json").exists(), reason="archive run 9 absente")
def test_run9_sans_game_master_reste_accepte(tmp_path):
    (tmp_path / "gm_worldscan.json").write_text(
        (RUN9 / "gm_worldscan.json").read_text(encoding="utf-8"), encoding="utf-8")
    prisme = json.loads((RUN9 / "prisme.json").read_text(encoding="utf-8"))
    assert run_real._validate_prisme(prisme, run_dir=tmp_path) == ""


@pytest.mark.skipif(not GM_FIXTURE.exists(), reason="fixture game_master absente")
def test_avec_game_master_une_exigence_de_boucle_sans_source_gm_est_refusee(tmp_path):
    (tmp_path / "gm_worldscan.json").write_text(json.dumps(_gm_with_block()), encoding="utf-8")
    raison = run_real._validate_prisme(_prisme_min("worldscan:games[0].loops.minute_1"), run_dir=tmp_path)
    assert "b_click" in raison and "game_master" in raison


@pytest.mark.skipif(not GM_FIXTURE.exists(), reason="fixture game_master absente")
def test_avec_game_master_adresse_gm_qui_resout_est_acceptee(tmp_path):
    gm = _gm_with_block()
    (tmp_path / "gm_worldscan.json").write_text(json.dumps(gm), encoding="utf-8")
    assert run_real._validate_prisme(_prisme_min(_first_loop_step_address(gm)), run_dir=tmp_path) == ""


@pytest.mark.skipif(not GM_FIXTURE.exists(), reason="fixture game_master absente")
def test_avec_game_master_adresse_gm_qui_ne_resout_pas_est_refusee(tmp_path):
    (tmp_path / "gm_worldscan.json").write_text(json.dumps(_gm_with_block()), encoding="utf-8")
    raison = run_real._validate_prisme(
        _prisme_min("gm_worldscan:game_master.loops.core_loop.etape_inventee"), run_dir=tmp_path)
    assert "etape_inventee" in raison


def test_sans_run_dir_comportement_inchange():
    assert run_real._validate_prisme(_prisme_min("worldscan:games[0].loops.minute_1")) == ""
