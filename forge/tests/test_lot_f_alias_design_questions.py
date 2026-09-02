"""Lot F -- boucle de completion mutuelle Art <-> GM (2026-08-23).

Plan : docs/superpowers/plans/2026-08-23-forge-lot-f-boucle-completion-mutuelle.md

Couvre T1 (alias d'etape) et T2 (design_questions.json) :
  - forge.contract.base_step/step_round (fonctions pures) ;
  - le manifeste genere pour un alias cite le contrat de la BASE (contract_sha256
    compris) ;
  - egalite des deux copies de _UPSTREAM_BY_STEP apres ajout des nouvelles entrees ;
  - forge.run_real._validate_design_questions (forme figee, resolution about/ref,
    regle ready_for_freeze, regle append-only) ;
  - la tolerance PARTIAL round 1 de forge.run_real._validate_game_master_block.

Fixtures REELLES utilisees (run 9, kitten_clicker) pour la resolution d'adresses ;
art_bible.md SYNTHETIQUE ad hoc quand le run 9 n'a pas les sections necessaires
(il est ANTERIEUR au Lot A/B -- pas de sections heritage_*/game_master) -- jamais
ecrit dans le run archive, uniquement dans tmp_path.

    PYTHONPATH=scripts .venv312/Scripts/python.exe -m pytest \
        forge/tests/test_lot_f_alias_design_questions.py -v
"""
from __future__ import annotations

import copy
import json
from pathlib import Path

import pytest

from forge import context_manifest as cm
from forge import run_real
from forge.contract import base_step, load_contract, step_round
from forge.dispatch import PROFILES, order_for_profile

REPO_ROOT = Path(__file__).resolve().parents[2]
RUN9 = REPO_ROOT / "EVIDENCE" / "runs" / "kitten_clicker" / "_run9_20260823a"
GM_VALID_FIXTURE = Path(__file__).resolve().parent / "fixtures" / "gm_game_master_valid.json"


def _run9_present() -> bool:
    return RUN9.is_dir() and (RUN9 / "gm_worldscan.json").is_file()


_SYNTH_ART_BIBLE = """---
styles: ["cozy", "flat"]
mood_keywords: ["mignon", "chaleureux"]
---

## visual_language
Palette pastel, formes rondes.

## character_states
Idle / happy / sad, silhouettes lisibles.
"""


def _valid_game_master() -> dict:
    return json.loads(GM_VALID_FIXTURE.read_text(encoding="utf-8"))


def _write_fixtures(run_dir: Path, game_master: dict) -> None:
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "art_bible.md").write_text(_SYNTH_ART_BIBLE, encoding="utf-8")
    (run_dir / "gm_worldscan.json").write_text(
        json.dumps({"game_master": game_master}), encoding="utf-8")


# =======================================================================================
# T1 -- alias d'etape
# =======================================================================================

def test_base_step_et_step_round():
    assert base_step("s2.7-gm-worldscan-r2") == "s2.7-gm-worldscan"
    assert base_step("s2.5-artbible-r2") == "s2.5-artbible"
    assert base_step("s2.7-gm-worldscan") == "s2.7-gm-worldscan"  # inchange
    assert step_round("s2.7-gm-worldscan-r2") == 2
    assert step_round("s2.7-gm-worldscan") == 1  # defaut


def test_profil_19_etapes_ordre_exact():
    attendu = [
        "s0-contrat", "s2-worldscan", "s2.6-story-bible", "s2.5-artbible",
        "s2.7-gm-worldscan", "s2.5-artbible-r2", "s2.7-gm-worldscan-r2",
        "s1-prisme", "s3-decompo", "s4-archi", "s5-wiremap", "s6-redteam-plan",
        "s9-build-godot-standard", "s10a-oracle-code", "s10b-oracle-archi",
        "s10c-oracle-wiremap", "s10s-oracle-standard", "s11-redteam-code",
        "s12-verdict",
    ]
    assert list(PROFILES["full_godot_content"]) == attendu
    assert order_for_profile("full_godot_content") == attendu


def test_le_manifeste_d_un_alias_cite_le_contrat_de_la_base(tmp_path):
    contract = load_contract("s2.7-gm-worldscan-r2")
    assert contract == load_contract("s2.7-gm-worldscan")
    record = cm.build_dispatch_manifest_record(
        "s2.7-gm-worldscan-r2", "run1",
        type("P", (), {"model": "x", "prompt": "y", "provider": ""})(),
        contract, run_dir=tmp_path,
    )
    contract_source = [s for s in record["sources"] if s["role"] == "contract"][0]
    assert contract_source["path"] == "forge/contracts/s2.7-gm-worldscan.yaml"
    import hashlib
    base_path = REPO_ROOT / "forge" / "contracts" / "s2.7-gm-worldscan.yaml"
    assert record["contract_sha256"] == hashlib.sha256(base_path.read_bytes()).hexdigest()


def test_egalite_upstream_by_step_apres_ajout_alias():
    assert run_real._UPSTREAM_BY_STEP == cm._UPSTREAM_BY_STEP
    assert "s2.5-artbible-r2" in run_real._UPSTREAM_BY_STEP
    assert "s2.7-gm-worldscan-r2" in run_real._UPSTREAM_BY_STEP
    assert "design_questions.json" in run_real._UPSTREAM_BY_STEP["s1-prisme"]


# =======================================================================================
# T2 -- design_questions.json
# =======================================================================================

def _dq_round1_partial(blocking: bool = True) -> dict:
    return {
        "schema_version": 1, "round": 1,
        "questions": [
            {"id": "q_gm_001", "from": "GM", "to": "ART", "round": 1,
             "about": "grey_blocks.garden", "loop_id": "world_loop",
             "missing": ["etats visuels LOCKED/AVAILABLE/ACTIVE/FULL"],
             "why": "le joueur doit comprendre pourquoi il ne peut pas encore entrer",
             "blocking": blocking, "answer": None},
        ],
        "declarations": {
            "ART": {"round": 1, "ready_for_freeze": False, "open_to_gm": 0},
            "GM": {"round": 1, "ready_for_freeze": False, "open_to_art": 1},
        },
    }


def test_fixture_r1_gm_partial_avec_question_bloquante_acceptee(tmp_path):
    """R1 : game_master INCOMPLET (world_interpretation tronque) + >=1 question
    GM->ART blocking:true -> tolere par _validate_game_master_block ET la fixture
    design_questions elle-meme est acceptee par _validate_design_questions."""
    gm = copy.deepcopy(_valid_game_master())
    gm["world_interpretation"] = gm["world_interpretation"][:1]  # casse le schema (>=3 exiges)
    _write_fixtures(tmp_path, gm)
    dq = _dq_round1_partial(blocking=True)

    reason_dq = run_real._validate_design_questions(dq, tmp_path)
    assert reason_dq == "", reason_dq

    data = {"game_master": gm}
    output = "```design_questions\n" + json.dumps(dq) + "\n```"
    reason_gm = run_real._validate_game_master_block(
        data, tmp_path, output=output, etape="s2.7-gm-worldscan")
    assert reason_gm == "", reason_gm

    # sans la question bloquante : le meme game_master incomplet est refuse (round 1)
    reason_gm_sans_question = run_real._validate_game_master_block(
        data, tmp_path, output="", etape="s2.7-gm-worldscan")
    assert reason_gm_sans_question != ""

    # round 2 (alias) : jamais tolere, meme avec une question bloquante
    reason_gm_r2 = run_real._validate_game_master_block(
        data, tmp_path, output=output, etape="s2.7-gm-worldscan-r2")
    assert reason_gm_r2 != ""


def test_r2_ready_for_freeze_true_mais_question_recue_sans_reponse_refusee(tmp_path):
    _write_fixtures(tmp_path, _valid_game_master())
    dq = {
        "schema_version": 1, "round": 2,
        "questions": [
            {"id": "q_gm_001", "from": "GM", "to": "ART", "round": 1,
             "about": "grey_blocks.garden", "loop_id": "world_loop", "missing": ["x"], "why": "y",
             "blocking": True, "answer": None},
        ],
        "declarations": {
            "ART": {"round": 2, "ready_for_freeze": True, "open_to_gm": 0},
            "GM": {"round": 2, "ready_for_freeze": False, "open_to_art": 1},
        },
    }
    reason = run_real._validate_design_questions(dq, tmp_path)
    assert reason != ""
    assert "q_gm_001" in reason
    assert "ready_for_freeze" in reason


def test_question_round1_disparue_en_round2_refusee(tmp_path):
    _write_fixtures(tmp_path, _valid_game_master())
    round1 = _dq_round1_partial(blocking=True)
    (tmp_path / "design_questions.json").write_text(json.dumps(round1), encoding="utf-8")

    round2_sans_q = {
        "schema_version": 1, "round": 2,
        "questions": [],
        "declarations": {
            "ART": {"round": 2, "ready_for_freeze": True, "open_to_gm": 0},
            "GM": {"round": 2, "ready_for_freeze": True, "open_to_art": 0},
        },
    }
    reason = run_real._validate_design_questions(round2_sans_q, tmp_path)
    assert reason != ""
    assert "q_gm_001" in reason
    assert "disparue" in reason


def test_about_ne_resout_pas_dans_l_artefact_du_demandeur_refusee(tmp_path):
    _write_fixtures(tmp_path, _valid_game_master())
    dq = _dq_round1_partial(blocking=True)
    dq["questions"][0]["about"] = "grey_blocks.section_inexistante"
    reason = run_real._validate_design_questions(dq, tmp_path)
    assert reason != ""
    assert "about" in reason
    assert "grey_blocks.section_inexistante" in reason


def test_fixture_convergee_round2_acceptee(tmp_path):
    _write_fixtures(tmp_path, _valid_game_master())
    round1 = _dq_round1_partial(blocking=True)
    (tmp_path / "design_questions.json").write_text(json.dumps(round1), encoding="utf-8")

    dq = {
        "schema_version": 1, "round": 2,
        "questions": [
            {"id": "q_gm_001", "from": "GM", "to": "ART", "round": 1,
             "about": "grey_blocks.garden", "loop_id": "world_loop",
             "missing": ["etats visuels LOCKED/AVAILABLE/ACTIVE/FULL"],
             "why": "le joueur doit comprendre pourquoi il ne peut pas encore entrer",
             "blocking": True,
             "answer": {"round": 2, "by": "ART", "ref": "art_bible:character_states",
                        "text": "etats idle/happy/sad, badge de verrouillage visible"}},
        ],
        "declarations": {
            "ART": {"round": 2, "ready_for_freeze": True, "open_to_gm": 0},
            "GM": {"round": 2, "ready_for_freeze": True, "open_to_art": 0},
        },
    }
    reason = run_real._validate_design_questions(dq, tmp_path)
    assert reason == "", reason


# --- resolution d'adresses contre les fixtures REELLES du run 9 ------------------
# (run 9 est ANTERIEUR au Lot A/B : art_bible.md n'a pas les sections heritage_*/
# game_master -- art_bible SYNTHETIQUE ad hoc ci-dessus, jamais le run archive modifie ;
# le principe de resolution (segment par segment / section markdown) est le meme).

def test_resolution_game_master_path_grey_block_par_id():
    gm = _valid_game_master()
    assert run_real._resolve_game_master_path(gm, "grey_blocks.garden") is True
    assert run_real._resolve_game_master_path(gm, "grey_blocks.n_existe_pas") is False
    assert run_real._resolve_game_master_path(gm, "loops.core_loop") is True


def test_resolution_art_bible_section_synthetique(tmp_path):
    _write_fixtures(tmp_path, _valid_game_master())
    assert run_real._resolve_design_question_address(
        "ART", "art_bible:character_states", tmp_path) is True
    assert run_real._resolve_design_question_address(
        "ART", "character_states", tmp_path) is True  # prefixe optionnel
    assert run_real._resolve_design_question_address(
        "ART", "art_bible:character_states#garden", tmp_path) is True  # fragment tolere
    assert run_real._resolve_design_question_address(
        "ART", "section_inexistante", tmp_path) is False


# --- _materialize_design_questions : tolerance R1 / echec R2 -----------------------

# Rupture 11 (2026-08-23) : le fence est desormais OBLIGATOIRE DES LE ROUND 1
# (mesure run 10c : la tolerance round 1 masquait un agent qui ne s'exprime
# JAMAIS via le canal structure) -- l'ancienne tolerance "written: False" a
# disparu, absent est desormais un ECHEC quel que soit le round.

def test_materialize_absent_echoue_en_round1(tmp_path):
    r = run_real._materialize_design_questions("s2.7-gm-worldscan", tmp_path, "rien ici")
    assert r is not None and r.get("ok") is False
    assert "non materialisable" in r["reason"]
    assert "aucun fence" in r["reason"]
    assert "ATTENDU" in r["reason"]
    assert not (tmp_path / "design_questions.json").exists()


def test_materialize_absent_echoue_en_round2(tmp_path):
    r = run_real._materialize_design_questions("s2.7-gm-worldscan-r2", tmp_path, "rien ici")
    assert r is not None and r.get("ok") is False
    assert "non materialisable" in r["reason"]


def test_materialize_etape_hors_boucle_retourne_none(tmp_path):
    assert run_real._materialize_design_questions("s0-contrat", tmp_path, "peu importe") is None


def test_materialize_ecrit_le_fichier_quand_valide(tmp_path):
    _write_fixtures(tmp_path, _valid_game_master())
    dq = _dq_round1_partial(blocking=True)
    output = "```design_questions\n" + json.dumps(dq) + "\n```"
    r = run_real._materialize_design_questions("s2.7-gm-worldscan", tmp_path, output)
    assert r == {"written": True, "path": str(tmp_path / "design_questions.json"),
                 "round": 1, "questions": 1}
    assert json.loads((tmp_path / "design_questions.json").read_text(encoding="utf-8")) == dq


# --- archivage round1 avant ecrasement ----------------------------------------------

def test_archive_round1_avant_overwrite(tmp_path):
    (tmp_path / "gm_worldscan.json").write_text('{"a": 1}', encoding="utf-8")
    run_real._archive_round1_before_overwrite(tmp_path, "gm_worldscan.json")
    archived = tmp_path / "artifacts" / "gm_worldscan-r1.json"
    assert archived.is_file()
    assert archived.read_text(encoding="utf-8") == '{"a": 1}'
    # idempotent : un 2e appel apres modif de la source ne re-ecrase pas l'archive
    (tmp_path / "gm_worldscan.json").write_text('{"a": 2}', encoding="utf-8")
    run_real._archive_round1_before_overwrite(tmp_path, "gm_worldscan.json")
    assert archived.read_text(encoding="utf-8") == '{"a": 1}'
