"""Lot B -- bloc `game_master` de gm_worldscan.json (2026-08-23).

Plan : docs/superpowers/plans/2026-08-23-forge-lot-b-game-master.md (T1).

`run_real._validate_gm_worldscan` exige désormais, APRÈS `sources_consumed`
(Lot A), le bloc `game_master` -- délégué à `node game_master_schema.mjs
--json` (`run_real._validate_game_master_block`). Ce fichier mesure ce
branchement sur 3 cas : le run 9 réel (antérieur au Lot B, game_master absent),
la fixture synthétique valide partagée avec `game_master_schema.test.mjs`
(`tests/fixtures/gm_game_master_valid.json`), et un refus nommé sur une étape
sans `proof_ref`.

    PYTHONPATH=scripts .venv312/Scripts/python.exe -m pytest \
        forge/tests/test_gm_game_master_block.py -v
"""
from __future__ import annotations

import copy
import json
import shutil
from pathlib import Path

import pytest

from forge import run_real

REPO_ROOT = Path(__file__).resolve().parents[2]
RUN9 = REPO_ROOT / "EVIDENCE" / "runs" / "kitten_clicker" / "_run9_20260823a"
FIXTURE_VALID = Path(__file__).resolve().parent / "fixtures" / "gm_game_master_valid.json"


def _run9_present() -> bool:
    return RUN9.is_dir() and (RUN9 / "gm_worldscan.json").is_file()


pytestmark = pytest.mark.skipif(
    not _run9_present(),
    reason=f"fixture réelle absente : {RUN9}",
)

_VALID_ART_BIBLE = """---
styles: ["cozy", "flat"]
mood_keywords: ["mignon", "chaleureux"]
---

## heritage_worldscan
Cite worldscan:games[0].retention_answer.

## heritage_story_bible
Cite story_bible:context.

## visual_language
Palette pastel.

## affordance_rules
Boutons ronds.

## character_states
Idle / happy / sad.

## ui_readability
Contraste AA.

## world_constraints
Refuge unique au depart.

## asset_rules
32px grille.
"""


def _copy_run9_upstream_fixture(dest: Path) -> None:
    dest.mkdir(parents=True, exist_ok=True)
    for name in ("worldscan.json", "story_bible.json"):
        src = RUN9 / name
        if src.is_file():
            shutil.copy2(src, dest / name)
    (dest / "art_bible.md").write_text(_VALID_ART_BIBLE, encoding="utf-8")


def _valid_sources_consumed(story_bible_data: dict) -> dict:
    section_id = story_bible_data["sections"][0]["id"]
    return {
        "worldscan": ["worldscan:games[0].retention_answer"],
        "story_bible": [f"story_bible:{section_id}"],
        "art_bible": ["art_bible:visual_language"],
    }


def _base_data(tmp_path: Path) -> dict:
    """gm_worldscan du run 9 + sources_consumed VALIDES (mesure le bloc
    game_master isolément, indépendamment de la preuve de consommation déjà
    couverte par test_lot_a_tuyau_artbible_gm.py)."""
    _copy_run9_upstream_fixture(tmp_path)
    story_bible_data = json.loads((tmp_path / "story_bible.json").read_text(encoding="utf-8"))
    data = json.loads((RUN9 / "gm_worldscan.json").read_text(encoding="utf-8"))
    data["sources_consumed"] = _valid_sources_consumed(story_bible_data)
    return data


def _valid_game_master() -> dict:
    return json.loads(FIXTURE_VALID.read_text(encoding="utf-8"))


# --- game_master absent (run 9 réel, sources_consumed complétées) --------------

def test_run9_sources_consumed_valides_mais_game_master_absent():
    """Le run 9 est antérieur au Lot B : gm_worldscan.json n'a jamais porté
    `game_master`. Une fois sources_consumed ajouté (valide), le refus doit
    nommer PRÉCISÉMENT le bloc `game_master`, pas sources_consumed."""
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        data = _base_data(tmp_path)
        assert "game_master" not in data
        reason = run_real._validate_gm_worldscan(data, run_dir=tmp_path)
        assert reason
        assert "game_master" in reason
        assert "absent" in reason


# --- fixture synthétique valide (partagée avec game_master_schema.test.mjs) ---

def test_fixture_game_master_valide_acceptee():
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        data = _base_data(tmp_path)
        data["game_master"] = _valid_game_master()
        reason = run_real._validate_gm_worldscan(data, run_dir=tmp_path)
        assert reason == ""


# --- étape sans proof_ref : refus nommé ----------------------------------------

def test_etape_sans_proof_ref_refusee_en_nommant_le_champ():
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        data = _base_data(tmp_path)
        gm = copy.deepcopy(_valid_game_master())
        del gm["loops"]["core_loop"]["steps"][0]["proof_ref"]
        data["game_master"] = gm
        reason = run_real._validate_gm_worldscan(data, run_dir=tmp_path)
        assert reason
        assert "proof_ref" in reason
