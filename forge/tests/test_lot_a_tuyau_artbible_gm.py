"""Lot A -- TUYAU World Scan -> Story Bible -> Art Bible -> GM (2026-08-23).

Plan : docs/superpowers/plans/2026-08-23-forge-lot-a-tuyau-worldscan-artbible-gm.md
Audit : docs/audit/2026-08-23-kitten-clicker-worldscan-artbible-gm-pipe.md

Deux preuves distinctes, jamais confondues :
  (1) CHARGEMENT — le manifeste de dispatch (`context_manifest.resolve_dispatch_sources`)
      enregistre les artefacts amont comme sources role=upstream. Déjà câblé par
      construction dès que `_UPSTREAM_BY_STEP` porte la bonne table (T1) ; testé ici
      sur la fixture RÉELLE du run 9 (`EVIDENCE/runs/kitten_clicker/_run9_20260823a/`),
      copiée dans tmp_path.
  (2) CONSOMMATION — `gm_worldscan.json` porte `sources_consumed` et CHAQUE adresse
      qu'il cite résout réellement dans l'artefact source
      (`run_real._validate_gm_worldscan` / `_validate_sources_consumed`, T2).

    PYTHONPATH=scripts .venv312/Scripts/python.exe -m pytest \
        forge/tests/test_lot_a_tuyau_artbible_gm.py -v
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path

import pytest

from forge import context_manifest as cm
from forge import run_real
from forge.contract import load_contract
from forge.dispatch import PROFILES, order_for_profile

REPO_ROOT = Path(__file__).resolve().parents[2]
RUN9 = REPO_ROOT / "EVIDENCE" / "runs" / "kitten_clicker" / "_run9_20260823a"


def _run9_present() -> bool:
    return RUN9.is_dir() and (RUN9 / "worldscan.json").is_file()


pytestmark = pytest.mark.skipif(
    not _run9_present(),
    reason=f"fixture réelle absente : {RUN9}",
)


def _copy_run9_upstream_fixture(dest: Path) -> None:
    """Copie dans `dest` UNIQUEMENT ce que s2.7/s2.5 consomment réellement du run 9 :
    art_bible.md, asset_requests.json, worldscan.json, story_bible.json (adressage
    de sources_consumed) et les artefacts/*.txt injectés par `_UPSTREAM_BY_STEP`."""
    dest.mkdir(parents=True, exist_ok=True)
    for name in ("art_bible.md", "asset_requests.json", "worldscan.json",
                 "story_bible.json", "charter.yaml"):
        src = RUN9 / name
        if src.is_file():
            shutil.copy2(src, dest / name)
    (dest / "artifacts").mkdir(exist_ok=True)
    for name in ("s2-worldscan.txt", "s2.6-story-bible.txt"):
        src = RUN9 / "artifacts" / name
        if src.is_file():
            shutil.copy2(src, dest / "artifacts" / name)


# --- T1 : ordre du profil ------------------------------------------------------

def test_ordre_full_godot_content_s25_avant_s27():
    # Lot F (2026-08-23) : 19 étapes (17 + les 2 alias round 2 de la boucle de
    # complétion mutuelle, s2.5-artbible-r2/s2.7-gm-worldscan-r2, insérés entre
    # s2.7-gm-worldscan et s1-prisme).
    steps = order_for_profile("full_godot_content")
    assert len(steps) == 19
    assert steps.index("s2.6-story-bible") < steps.index("s2.5-artbible")
    assert steps.index("s2.5-artbible") < steps.index("s2.7-gm-worldscan")
    assert steps.index("s2.7-gm-worldscan") < steps.index("s1-prisme")
    assert steps.index("s2.7-gm-worldscan") < steps.index("s2.5-artbible-r2")
    assert steps.index("s2.5-artbible-r2") < steps.index("s2.7-gm-worldscan-r2")
    assert steps.index("s2.7-gm-worldscan-r2") < steps.index("s1-prisme")



# --- T1(c) : preuve de CHARGEMENT (manifeste de dispatch + section amont) ------

def test_s27_recoit_les_4_fichiers_amont_depuis_la_fixture_run9(tmp_path):
    _copy_run9_upstream_fixture(tmp_path)
    section = run_real.upstream_artifacts_section("s2.7-gm-worldscan", tmp_path)
    assert "artifacts/s2-worldscan.txt" in section
    assert "artifacts/s2.6-story-bible.txt" in section
    assert "art_bible.md" in section
    assert "asset_requests.json" in section


def test_s25_recoit_les_3_fichiers_amont_depuis_la_fixture_run9(tmp_path):
    _copy_run9_upstream_fixture(tmp_path)
    section = run_real.upstream_artifacts_section("s2.5-artbible", tmp_path)
    assert "charter.yaml" in section
    assert "artifacts/s2-worldscan.txt" in section
    assert "artifacts/s2.6-story-bible.txt" in section


def test_manifeste_dispatch_s27_porte_4_sources_upstream_exists_true(tmp_path):
    # Lot B T2(b) (2026-08-23) : s2.7 gagne 2 entrées upstream supplémentaires
    # (heritage/art_response.json, heritage/gm_worldscan.json) — absentes au 1er
    # run (aucun dossier heritage/ dans cette fixture), donc exists:False pour
    # elles ; les 4 originales restent présentes et exists:True (comportement
    # inchangé pour les fichiers déjà couverts par le Lot A).
    # Lot D (2026-08-23, GO Pierre, fuite 3) : + 4 entrées design (design_intent.md,
    # design/gameplay_loop_content_contract.md, design/progression_contract.md,
    # design/calibration.md), absentes elles aussi dans cette fixture (design/ non
    # peuplé) => exists:False, même garantie que heritage.
    _copy_run9_upstream_fixture(tmp_path)
    contract = load_contract("s2.7-gm-worldscan")
    sources = cm.resolve_dispatch_sources("s2.7-gm-worldscan", contract, run_dir=tmp_path)
    upstream = [s for s in sources if s["role"] == "upstream"]
    # C.5 (2026-08-25, ratifie Pierre) : + design/content_requirements.md — LA CARTE,
    # injectee aux deux piliers ; absente de cette fixture (design/ non peuple) => exists:False.
    assert len(upstream) == 12
    original = {"s2-worldscan.txt", "s2.6-story-bible.txt", "art_bible.md", "asset_requests.json"}
    heritage = {"art_response.json", "gm_worldscan.json"}
    design = {"design_intent.md", "gameplay_loop_content_contract.md",
              "progression_contract.md", "calibration.md", "content_requirements.md",
              "game_loop_blueprint.md"}
    by_name = {s["path"].split("/")[-1]: s for s in upstream}
    assert set(by_name) == original | heritage | design
    assert all(by_name[name]["exists"] for name in original)
    assert all(not by_name[name]["exists"] for name in heritage)
    assert all(not by_name[name]["exists"] for name in design)


def test_manifeste_dispatch_s25_porte_3_sources_upstream_exists_true(tmp_path):
    # Lot B T2(b) (2026-08-23) : s2.5 gagne 2 entrées upstream (heritage/art_bible.md,
    # heritage/art_response.json), absentes au 1er run — mêmes garanties que ci-dessus.
    # Lot D (2026-08-23, GO Pierre, fuite 3) : + 3 entrées design (design_intent.md,
    # design/gameplay_loop_content_contract.md, design/progression_contract.md),
    # absentes elles aussi dans cette fixture.
    _copy_run9_upstream_fixture(tmp_path)
    contract = load_contract("s2.5-artbible")
    sources = cm.resolve_dispatch_sources("s2.5-artbible", contract, run_dir=tmp_path)
    upstream = [s for s in sources if s["role"] == "upstream"]
    # C.5 (2026-08-25, ratifie Pierre) : + design/content_requirements.md — LA CARTE,
    # injectee aux deux piliers ; absente de cette fixture (design/ non peuple) => exists:False.
    assert len(upstream) == 10
    original = {"charter.yaml", "s2-worldscan.txt", "s2.6-story-bible.txt"}
    heritage = {"art_bible.md", "art_response.json"}
    design = {"design_intent.md", "gameplay_loop_content_contract.md", "progression_contract.md",
              "content_requirements.md", "game_loop_blueprint.md"}
    by_name = {s["path"].split("/")[-1]: s for s in upstream}
    assert set(by_name) == original | heritage | design
    assert all(by_name[name]["exists"] for name in original)
    assert all(not by_name[name]["exists"] for name in design)
    assert all(not by_name[name]["exists"] for name in heritage)


# --- T2(d) : preuve de CONSOMMATION (`sources_consumed`) -----------------------

def test_gm_worldscan_du_run9_reel_refuse_sources_consumed_absent():
    """Le run 9 est ANTÉRIEUR au Lot A : gm_worldscan.json n'a jamais porté
    `sources_consumed`. Refusé, message nommant le champ absent."""
    data = json.loads((RUN9 / "gm_worldscan.json").read_text(encoding="utf-8"))
    assert "sources_consumed" not in data
    reason = run_real._validate_gm_worldscan(data, run_dir=RUN9)
    assert reason
    assert "sources_consumed" in reason


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


def _valid_sources_consumed(story_bible_data: dict) -> dict:
    section_id = story_bible_data["sections"][0]["id"]
    return {
        "worldscan": ["worldscan:games[0].retention_answer"],
        "story_bible": [f"story_bible:{section_id}"],
        "art_bible": ["art_bible:visual_language"],
    }


_GM_GAME_MASTER_VALID_FIXTURE = (
    Path(__file__).resolve().parent / "fixtures" / "gm_game_master_valid.json"
)


def test_gm_worldscan_synthetique_avec_sources_consumed_valides_accepte(tmp_path):
    # Lot B (2026-08-23) : `game_master` est désormais obligatoire APRÈS
    # `sources_consumed` (cf. `_validate_gm_worldscan`) — la fixture valide partagée
    # (`tests/fixtures/gm_game_master_valid.json`, réutilisée par
    # `game_master_schema.test.mjs` et `test_gm_game_master_block.py`) fournit un
    # bloc complet pour que ce test continue de mesurer sources_consumed seul.
    _copy_run9_upstream_fixture(tmp_path)
    (tmp_path / "art_bible.md").write_text(_VALID_ART_BIBLE, encoding="utf-8")
    story_bible_data = json.loads((tmp_path / "story_bible.json").read_text(encoding="utf-8"))
    data = json.loads((RUN9 / "gm_worldscan.json").read_text(encoding="utf-8"))
    data["sources_consumed"] = _valid_sources_consumed(story_bible_data)
    data["game_master"] = json.loads(_GM_GAME_MASTER_VALID_FIXTURE.read_text(encoding="utf-8"))
    reason = run_real._validate_gm_worldscan(data, run_dir=tmp_path)
    assert reason == ""


def test_adresse_worldscan_inexistante_refusee_en_nommant_l_adresse(tmp_path):
    _copy_run9_upstream_fixture(tmp_path)
    (tmp_path / "art_bible.md").write_text(_VALID_ART_BIBLE, encoding="utf-8")
    story_bible_data = json.loads((tmp_path / "story_bible.json").read_text(encoding="utf-8"))
    data = json.loads((RUN9 / "gm_worldscan.json").read_text(encoding="utf-8"))
    sc = _valid_sources_consumed(story_bible_data)
    sc["worldscan"] = ["worldscan:games[99].ne_existe_pas"]
    data["sources_consumed"] = sc
    reason = run_real._validate_gm_worldscan(data, run_dir=tmp_path)
    assert reason
    assert "worldscan:games[99].ne_existe_pas" in reason


def test_adresse_story_bible_inexistante_refusee_en_nommant_l_adresse(tmp_path):
    _copy_run9_upstream_fixture(tmp_path)
    (tmp_path / "art_bible.md").write_text(_VALID_ART_BIBLE, encoding="utf-8")
    story_bible_data = json.loads((tmp_path / "story_bible.json").read_text(encoding="utf-8"))
    data = json.loads((RUN9 / "gm_worldscan.json").read_text(encoding="utf-8"))
    sc = _valid_sources_consumed(story_bible_data)
    sc["story_bible"] = ["story_bible:section_inexistante"]
    data["sources_consumed"] = sc
    reason = run_real._validate_gm_worldscan(data, run_dir=tmp_path)
    assert reason
    assert "story_bible:section_inexistante" in reason


def test_adresse_art_bible_inexistante_refusee_en_nommant_l_adresse(tmp_path):
    _copy_run9_upstream_fixture(tmp_path)
    (tmp_path / "art_bible.md").write_text(_VALID_ART_BIBLE, encoding="utf-8")
    story_bible_data = json.loads((tmp_path / "story_bible.json").read_text(encoding="utf-8"))
    data = json.loads((RUN9 / "gm_worldscan.json").read_text(encoding="utf-8"))
    sc = _valid_sources_consumed(story_bible_data)
    sc["art_bible"] = ["art_bible:section_inexistante"]
    data["sources_consumed"] = sc
    reason = run_real._validate_gm_worldscan(data, run_dir=tmp_path)
    assert reason
    assert "art_bible:section_inexistante" in reason


def test_liste_vide_refusee(tmp_path):
    _copy_run9_upstream_fixture(tmp_path)
    (tmp_path / "art_bible.md").write_text(_VALID_ART_BIBLE, encoding="utf-8")
    story_bible_data = json.loads((tmp_path / "story_bible.json").read_text(encoding="utf-8"))
    data = json.loads((RUN9 / "gm_worldscan.json").read_text(encoding="utf-8"))
    sc = _valid_sources_consumed(story_bible_data)
    sc["art_bible"] = []
    data["sources_consumed"] = sc
    reason = run_real._validate_gm_worldscan(data, run_dir=tmp_path)
    assert reason
    assert "art_bible" in reason


def test_validation_sautee_sans_run_dir_comportement_historique_preserve():
    """`run_dir=None` (comportement historique) : la section sources_consumed est
    sautée, seuls dimensions/games_observed restent gardés — jamais de régression
    pour un appelant qui ne connaît pas de run_dir."""
    data = json.loads((RUN9 / "gm_worldscan.json").read_text(encoding="utf-8"))
    assert "sources_consumed" not in data
    reason = run_real._validate_gm_worldscan(data)
    assert reason == ""


# --- fil rouge : les deux tables amont restent identiques -----------------------

def test_les_deux_copies_de_la_table_amont_restent_identiques():
    assert run_real._UPSTREAM_BY_STEP == cm._UPSTREAM_BY_STEP
