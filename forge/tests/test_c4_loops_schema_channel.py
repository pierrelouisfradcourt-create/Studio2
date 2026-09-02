"""Lot C.4-code (2026-08-24) -- la Forge devient incapable de declarer un jeu
complet sans boucles fermees.

Plan : docs/superpowers/plans/2026-08-24-forge-lot-c4-code-boucles.md (Agent A).
Contrats de design (references normatives) :
  studio_brain/gamedesign/kitten_clicker_game_loop_architecture_v1.md (C.3)
  studio_brain/gamedesign/kitten_clicker_mutual_completion_contract_v1.md (C.4)

CRITERE DE REUSSITE DU LOT (verbatim du plan) : le `gm_worldscan.json` du run 10h
-- aujourd'hui « valide » (6 boucles, Lot B) -- est REFUSE par le nouveau schema
9-boucles, avec des raisons NOMMEES (boucles manquantes, metric_propre absents).
Un design honnetement partiel (via `game_master_schema.mjs` directement) ou une
fixture 9-boucles complete doit continuer a passer.

Fixtures REELLES : `tests/fixtures/run10h_gm_worldscan.json` (copie du run 10h,
JAMAIS le run archive lui-meme modifie), `tests/fixtures/gm_game_master_valid.json`
(fixture synthetique 9-boucles partagee avec game_master_schema.test.mjs).

    PYTHONPATH=scripts .venv312/Scripts/python.exe -m pytest \
        forge/tests/test_c4_loops_schema_channel.py -v
"""
from __future__ import annotations

import copy
import json
from pathlib import Path

import pytest

from forge import run_real

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURES = Path(__file__).resolve().parent / "fixtures"
RUN10H_GM_WORLDSCAN = FIXTURES / "run10h_gm_worldscan.json"
GM_VALID_FIXTURE = FIXTURES / "gm_game_master_valid.json"


def _valid_game_master() -> dict:
    return json.loads(GM_VALID_FIXTURE.read_text(encoding="utf-8"))


def _run10h_game_master() -> dict:
    data = json.loads(RUN10H_GM_WORLDSCAN.read_text(encoding="utf-8"))
    return data["game_master"]


# =======================================================================================
# 1. Critere de reussite du lot : le gm du run 10h est REFUSE, raisons nommees
# =======================================================================================

def test_gm_du_run_10h_refuse_par_le_nouveau_schema_9_boucles():
    """Le run 10h est ANTERIEUR au Lot C.4-code : ses 6 boucles (core, progression,
    player, content, meta, economy -- Lot B) ne correspondent plus au vocabulaire
    figé 9-boucles (`player_loop` absorbe par `gameplay_loop`), et ses boucles sont
    de simples LISTES d'etapes, jamais des objets {steps, produces, consumes,
    unlocks, transformation_perceptible, metric_propre}. C'EST LE BUT DU LOT :
    un gm valide hier doit etre refuse aujourd'hui, avec des raisons NOMMEES."""
    gm = _run10h_game_master()
    data = {"game_master": gm}
    reason = run_real._validate_game_master_block(data, Path("."), output="", etape="")
    assert reason != "", "le gm du run 10h doit etre REFUSE par le nouveau schema"
    print("VERBATIM refus gm du run 10h :", reason)
    # boucles manquantes nommees (gameplay_loop absorbe player_loop, plus
    # skill_loop/world_loop/quest_loop entierement absents du run 10h)
    for missing_loop in ("gameplay_loop", "skill_loop", "world_loop", "quest_loop"):
        assert missing_loop in reason, f"'{missing_loop}' doit etre nomme dans le refus"
    # metric_propre absent de TOUTES les boucles du run 10h (format Lot B, listes
    # d'etapes brutes -- aucun champ metric_propre n'existe encore)
    assert "metric_propre" in reason


# =======================================================================================
# 2. fixture 9-boucles valide -> acceptee
# =======================================================================================

def test_fixture_9_boucles_valide_acceptee():
    gm = _valid_game_master()
    data = {"game_master": gm}
    reason = run_real._validate_game_master_block(data, Path("."), output="", etape="")
    assert reason == "", reason


# =======================================================================================
# 3. 1 cas rouge nomme par regle C.4, via le MEME canal de production
#    (_validate_game_master_block -- pas une redite des tests unitaires JS)
# =======================================================================================

def test_r2a_boucle_orpheline_refusee():
    gm = copy.deepcopy(_valid_game_master())
    gm["loops"]["gameplay_loop"]["consumes"] = [
        c for c in gm["loops"]["gameplay_loop"]["consumes"] if c != "core_loop"
    ]
    data = {"game_master": gm}
    reason = run_real._validate_game_master_block(data, Path("."), output="", etape="")
    assert reason != ""
    assert "core_loop" in reason and "orpheline" in reason


def test_r2b_transformation_perceptible_humangate_seul_refusee():
    gm = copy.deepcopy(_valid_game_master())
    gm["proof_model"].append({
        "id": "proof_humangate_only", "measures": "core_reactions_per_caress",
        "how": "humangate", "expected": "avis HumanGate seul",
    })
    gm["loops"]["core_loop"]["transformation_perceptible"]["proof_ref"] = "proof_humangate_only"
    data = {"game_master": gm}
    reason = run_real._validate_game_master_block(data, Path("."), output="", etape="")
    assert reason != ""
    assert "humangate" in reason


def test_metric_propre_partagee_refusee():
    gm = copy.deepcopy(_valid_game_master())
    gm["loops"]["gameplay_loop"]["metric_propre"] = gm["loops"]["core_loop"]["metric_propre"]
    data = {"game_master": gm}
    reason = run_real._validate_game_master_block(data, Path("."), output="", etape="")
    assert reason != ""
    assert "metric_propre" in reason and "partagee" in reason


def test_consumes_nom_de_boucle_inconnu_refuse():
    gm = copy.deepcopy(_valid_game_master())
    gm["loops"]["core_loop"]["consumes"] = ["boucle_inventee"]
    data = {"game_master": gm}
    reason = run_real._validate_game_master_block(data, Path("."), output="", etape="")
    assert reason != ""
    assert "loops.core_loop.consumes" in reason


# =======================================================================================
# 4. design_questions : loop_id obligatoire
# =======================================================================================

def _dq(question_overrides: dict, *, ready_art=False, ready_gm=False) -> dict:
    q = {
        "id": "q_gm_001", "from": "GM", "to": "ART", "round": 1,
        "about": "grey_blocks.garden",
        "missing": ["etats visuels"], "why": "le joueur doit comprendre",
        "blocking": True, "answer": None,
    }
    q.update(question_overrides)
    return {
        "schema_version": 1, "round": 1,
        "questions": [q],
        "declarations": {
            "ART": {"round": 1, "ready_for_freeze": ready_art, "open_to_gm": 0},
            "GM": {"round": 1, "ready_for_freeze": ready_gm, "open_to_art": 1},
        },
    }


def test_question_sans_loop_id_refusee():
    dq = _dq({})  # pas de 'loop_id'
    reason = run_real._validate_design_questions(dq)
    assert reason != ""
    assert "loop_id" in reason and "q_gm_001" in reason


def test_question_loop_id_inconnu_refusee():
    dq = _dq({"loop_id": "boucle_qui_nexiste_pas"})
    reason = run_real._validate_design_questions(dq)
    assert reason != ""
    assert "loop_id" in reason and "q_gm_001" in reason


def test_question_loop_id_art_gm_acceptee():
    dq = _dq({"loop_id": "art_gm"})
    reason = run_real._validate_design_questions(dq)
    assert reason == "", reason


def test_question_loop_id_boucle_valide_acceptee():
    dq = _dq({"loop_id": "world_loop"})
    reason = run_real._validate_design_questions(dq)
    assert reason == "", reason


# =======================================================================================
# 5. R1 etendu : question bloquante EMISE (pas seulement recue) non fermee + ready
# =======================================================================================

def test_r1_etendu_question_bloquante_emise_non_fermee_refuse_le_declarant():
    """Le pilier GM EMET lui-meme une question bloquante (from=GM) restee sans
    reponse, et se declare quand meme ready_for_freeze=true -- l'extension R1 du
    Lot C.4-code (C.4 §"Les deux regles dures") refuse ce cas, en nommant l'id,
    meme si GM n'a RECU aucune question (ART n'a rien a lui reprocher)."""
    dq = _dq({"loop_id": "world_loop"}, ready_gm=True)
    reason = run_real._validate_design_questions(dq)
    assert reason != ""
    assert "q_gm_001" in reason
    assert "EMISES" in reason or "emises" in reason.lower()


def test_r1_etendu_question_bloquante_emise_fermee_permet_le_freeze():
    """Meme scenario, mais la question EMISE porte desormais une reponse -- le
    declarant n'est plus bloque par sa PROPRE question (R1 etendu ne bloque QUE
    tant que la question reste ouverte)."""
    q = {
        "id": "q_gm_001", "from": "GM", "to": "ART", "round": 1,
        "about": "grey_blocks.garden", "loop_id": "world_loop",
        "missing": ["etats visuels"], "why": "le joueur doit comprendre",
        "blocking": True,
        "answer": {"round": 1, "by": "ART", "ref": "grey_blocks.garden",
                   "text": "etats decrits dans la bible"},
    }
    dq = {
        "schema_version": 1, "round": 1,
        "questions": [q],
        "declarations": {
            "ART": {"round": 1, "ready_for_freeze": False, "open_to_gm": 0},
            "GM": {"round": 1, "ready_for_freeze": True, "open_to_art": 0},
        },
    }
    reason = run_real._validate_design_questions(dq)
    assert reason == "", reason


def test_r1_etendu_question_non_bloquante_emise_ne_bloque_pas_le_freeze():
    """Une question EMISE non-bloquante (blocking=false) restee sans reponse ne
    doit PAS bloquer le freeze de son emetteur -- seule une question BLOQUANTE
    emise et non fermee compte (cf. docstring _validate_design_questions)."""
    dq = _dq({"loop_id": "world_loop", "blocking": False}, ready_gm=True)
    reason = run_real._validate_design_questions(dq)
    assert reason == "", reason
