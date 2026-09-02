"""SAS CORRECTIF R3/freeze (C1+C3, ratifié Pierre 2026-08-30, findings pilote L/D
RUN2) — fixtures OBLIGATOIRES depuis les artefacts RÉELS commités
`EVIDENCE/runs/p1_alpha/` (D1, bras dirigé, HALT théâtre historique) et
`EVIDENCE/runs/p1_beta/` (L1, bras libre).

C1 : `driver.ForgeDriver._compute_loop_design_state` ne diffuse plus aveuglément
gm_worldscan[loop_id] pour juger « théâtre de questions » — elle lit
`answer.modification_locus.type` et diffe la cible QUE LA RÉPONSE déclare avoir
modifiée (gm_worldscan / art_bible), ou ne diffe rien du tout (aucune_requise,
jugée ailleurs au canal — C3).

C3 : `run_real._validate_design_questions` valide la forme et la recevabilité de
`answer.modification_locus` — fail-closed sur `aucune_requise` sans preuve amont
(Brief projet) ou sans justification.
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path

import pytest

from forge import run_real
from forge.driver import ForgeDriver

REPO_ROOT = Path(__file__).resolve().parents[2]
P1_ALPHA = REPO_ROOT / "EVIDENCE" / "runs" / "p1_alpha"
P1_BETA = REPO_ROOT / "EVIDENCE" / "runs" / "p1_beta"


def _copy_run(tmp_path: Path, src: Path, name: str) -> Path:
    dst = tmp_path / name
    shutil.copytree(src, dst)
    return dst


def _driver_for(run_dir: Path) -> ForgeDriver:
    d = ForgeDriver.__new__(ForgeDriver)  # méthodes pures seulement (patron établi)
    d.run_id = "r1"
    d.project = run_dir.name
    d.profile = "full_content"
    d.run_dir = run_dir
    d.order = ["s2.7-gm-worldscan-r2", "s1-prisme"]  # arme _design_loop_active
    d.state_path = run_dir / "state.json"
    return d


def _load_dq(run_dir: Path) -> dict:
    return json.loads((run_dir / "design_questions.json").read_text(encoding="utf-8"))


def _save_dq(run_dir: Path, data: dict) -> None:
    (run_dir / "design_questions.json").write_text(
        json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")


# --- (1) LE test central du sas : p1_alpha, locus art_bible/aucune_requise ---
# gm_worldscan.core_loop reste IMMUABLE (bras dirigé, structure normative) — le
# freeze ne doit PLUS forcer une modification interdite.

def test_p1_alpha_locus_art_bible_desamorce_le_theatre_core_loop(tmp_path):
    run_dir = _copy_run(tmp_path, P1_ALPHA, "p1_alpha")
    dq = _load_dq(run_dir)
    q_art_001 = next(q for q in dq["questions"] if q["id"] == "q_art_001")
    assert q_art_001["loop_id"] == "core_loop"
    # Fait mesuré (PILOT_STOP_20260830.md) : art_bible.md a RÉELLEMENT changé
    # entre round 1 et le disque actuel (v0.2, thème intégré) — un VRAI diff,
    # jamais fabriqué pour ce test.
    art_now = (run_dir / "art_bible.md").read_text(encoding="utf-8")
    art_r1 = (run_dir / "artifacts" / "art_bible-r1.md").read_text(encoding="utf-8")
    assert art_now != art_r1
    q_art_001["answer"]["modification_locus"] = {
        "type": "art_bible",
        "justification": "Le theme est integre en art_bible.md v0.2 ; "
                          "core_loop est normatif, aucune mecanique n'a change.",
    }
    _save_dq(run_dir, dq)

    d = _driver_for(run_dir)
    loop_state = d._compute_loop_design_state()
    assert "core_loop" not in loop_state["theatre_loops"]
    assert loop_state["loops"]["core_loop"]["status"] != "OPEN(réponse sans modification)"

    state = {"steps": {"s1-prisme": {"status": "PENDING"}}}
    report = d._design_freeze_gate(state)
    # La raison HALTED (si le run reste bloqué pour d'AUTRES motifs, R1 étendu
    # ou boucles PROPOSED) ne doit PLUS jamais nommer un théâtre sur core_loop.
    if report is not None:
        assert "théâtre" not in report["reason"] or "core_loop" not in report["reason"]


def test_p1_alpha_locus_aucune_requise_desamorce_aussi_le_theatre(tmp_path):
    run_dir = _copy_run(tmp_path, P1_ALPHA, "p1_alpha")
    dq = _load_dq(run_dir)
    q_art_001 = next(q for q in dq["questions"] if q["id"] == "q_art_001")
    q_art_001["answer"]["modification_locus"] = {
        "type": "aucune_requise",
        "justification": "core_loop est normatif (structure imposee du bras D), "
                          "aucune modification mecanique n'est requise ici.",
    }
    _save_dq(run_dir, dq)

    d = _driver_for(run_dir)
    loop_state = d._compute_loop_design_state()
    assert "core_loop" not in loop_state["theatre_loops"]


# --- (2) la garde garde ses dents : locus gm_worldscan, bloc inchangé -> théâtre TOUJOURS ---

def test_locus_gm_worldscan_bloc_inchange_declenche_toujours_le_theatre(tmp_path):
    run_dir = _copy_run(tmp_path, P1_ALPHA, "p1_alpha")
    dq = _load_dq(run_dir)
    q_art_001 = next(q for q in dq["questions"] if q["id"] == "q_art_001")
    q_art_001["answer"]["modification_locus"] = {"type": "gm_worldscan"}
    _save_dq(run_dir, dq)

    d = _driver_for(run_dir)
    loop_state = d._compute_loop_design_state()
    assert "core_loop" in loop_state["theatre_loops"]
    assert loop_state["loops"]["core_loop"]["status"] == "OPEN(réponse sans modification)"


# --- (3) rétrocompat : réponse SANS locus sur p1_alpha historique -> HALT reproduit ---

def test_p1_alpha_sans_locus_reproduit_le_halt_historique(tmp_path):
    run_dir = _copy_run(tmp_path, P1_ALPHA, "p1_alpha")
    # AUCUNE modification du design_questions.json committé — comportement
    # historique exact (réponse thématique SANS modification_locus).
    d = _driver_for(run_dir)
    loop_state = d._compute_loop_design_state()
    assert "core_loop" in loop_state["theatre_loops"]

    state = {"steps": {"s1-prisme": {"status": "PENDING"}}}
    report = d._design_freeze_gate(state)
    assert report is not None
    assert report["status"] == "HALTED"
    assert "core_loop" in report["reason"]
    assert "théâtre" in report["reason"] or "réponse sans modification" in report["reason"]


# --- (4) locus art_bible : diff réel -> pas de théâtre ; identique -> théâtre ---

def test_locus_art_bible_diff_reel_pas_de_theatre(tmp_path):
    run_dir = _copy_run(tmp_path, P1_BETA, "p1_beta")
    dq = _load_dq(run_dir)
    q = next(q for q in dq["questions"] if q["id"] == "q_art_001")
    assert q["loop_id"] == "core_loop"
    art_now = (run_dir / "art_bible.md").read_text(encoding="utf-8")
    art_r1 = (run_dir / "artifacts" / "art_bible-r1.md").read_text(encoding="utf-8")
    assert art_now != art_r1  # fait mesuré, réel, jamais fabriqué
    q["answer"]["modification_locus"] = {"type": "art_bible"}
    _save_dq(run_dir, dq)

    d = _driver_for(run_dir)
    loop_state = d._compute_loop_design_state()
    assert "core_loop" not in loop_state["theatre_loops"]


def test_locus_art_bible_identique_declenche_le_theatre(tmp_path):
    run_dir = _copy_run(tmp_path, P1_BETA, "p1_beta")
    # Simule une réponse théâtre côté ART : art_bible.md redevient
    # BYTE-IDENTIQUE à son archive round 1 (aucune modification réelle).
    r1_text = (run_dir / "artifacts" / "art_bible-r1.md").read_text(encoding="utf-8")
    (run_dir / "art_bible.md").write_text(r1_text, encoding="utf-8")
    dq = _load_dq(run_dir)
    q = next(q for q in dq["questions"] if q["id"] == "q_art_001")
    q["answer"]["modification_locus"] = {"type": "art_bible"}
    _save_dq(run_dir, dq)

    d = _driver_for(run_dir)
    loop_state = d._compute_loop_design_state()
    assert "core_loop" in loop_state["theatre_loops"]


# =====================================================================================
# C3 — canal : `_validate_design_questions` (run_real.py), `answer.modification_locus`
# =====================================================================================

def _minimal_answered_question(**overrides) -> dict:
    q = {
        "id": "q1", "from": "ART", "to": "GM", "round": 1,
        "about": "art_bible:visual_language", "loop_id": "core_loop",
        "missing": ["x"], "why": "y", "blocking": True,
        "answer": {"round": 1, "by": "GM", "ref": "gm_worldscan:game_master.core_loop",
                   "text": "reponse"},
    }
    q.update(overrides)
    return q


def _minimal_doc(question: dict) -> dict:
    return {
        "schema_version": 1, "round": 1, "questions": [question],
        "declarations": {
            "ART": {"round": 1, "ready_for_freeze": True, "open_to_gm": 0},
            "GM": {"round": 1, "ready_for_freeze": True, "open_to_art": 0},
        },
    }


def test_c3_aucune_requise_sans_brief_normatif_refuse():
    # run_dir=None : jamais un `run_dir` réel n'entre en jeu pour CE test, la
    # cible est la règle `aucune_requise` elle-même (about/ref non résolus,
    # comportement historique documenté quand run_dir est absent).
    q = _minimal_answered_question()
    q["answer"]["modification_locus"] = {
        "type": "aucune_requise", "justification": "motif quelconque",
    }
    reason = run_real._validate_design_questions(_minimal_doc(q), None)
    assert reason != ""
    assert "aucune_requise" in reason


def test_c3_aucune_requise_sans_justification_refuse(monkeypatch):
    monkeypatch.setattr(run_real, "_project_declares_normative_structure",
                         lambda run_dir=None: True)
    q = _minimal_answered_question()
    q["answer"]["modification_locus"] = {"type": "aucune_requise"}
    reason = run_real._validate_design_questions(_minimal_doc(q), None)
    assert reason != ""
    assert "justification" in reason


def test_c3_aucune_requise_avec_brief_normatif_et_justification_accepte(monkeypatch):
    monkeypatch.setattr(run_real, "_project_declares_normative_structure",
                         lambda run_dir=None: True)
    q = _minimal_answered_question()
    q["answer"]["modification_locus"] = {
        "type": "aucune_requise", "justification": "objet declare normatif au brief",
    }
    reason = run_real._validate_design_questions(_minimal_doc(q), None)
    assert reason == "", reason


def test_c3_locus_type_invalide_refuse():
    q = _minimal_answered_question()
    q["answer"]["modification_locus"] = {"type": "un_type_inconnu"}
    reason = run_real._validate_design_questions(_minimal_doc(q), None)
    assert reason != ""
    assert "modification_locus.type" in reason


def test_c3_aucune_requise_end_to_end_p1_alpha_reel(tmp_path):
    """Bout-en-bout SANS monkeypatch, sur le Brief RÉEL de p1_alpha (porte le
    marqueur normatif) — la fixture obligatoire du sas, chemin complet."""
    run_dir = _copy_run(tmp_path, P1_ALPHA, "p1_alpha")
    dq = _load_dq(run_dir)
    q_art_001 = next(q for q in dq["questions"] if q["id"] == "q_art_001")
    q_art_001["answer"]["modification_locus"] = {
        "type": "aucune_requise",
        "justification": "core_loop est normatif (structure_imposee.yaml du bras D).",
    }
    reason = run_real._validate_design_questions(dq, run_dir)
    assert reason == "", reason


def test_c3_aucune_requise_end_to_end_p1_beta_refuse_sans_marqueur(tmp_path):
    """Même mécanisme, bras LIBRE (p1_beta, aucun marqueur normatif au Brief)
    -- REFUSÉ, même avec une justification fournie."""
    run_dir = _copy_run(tmp_path, P1_BETA, "p1_beta")
    dq = _load_dq(run_dir)
    q = next(q for q in dq["questions"] if q["id"] == "q_art_001")
    q["answer"]["modification_locus"] = {
        "type": "aucune_requise", "justification": "motif quelconque",
    }
    reason = run_real._validate_design_questions(dq, run_dir)
    assert reason != ""
    assert "aucune_requise" in reason


def test_c3_sans_locus_reste_valide_retrocompat():
    q = _minimal_answered_question()  # aucun modification_locus
    reason = run_real._validate_design_questions(_minimal_doc(q), None)
    assert reason == "", reason


def test_c3_locus_gm_worldscan_sans_justification_accepte():
    """`gm_worldscan`/`art_bible` n'exigent PAS de justification (seule
    `aucune_requise` la requiert, C3 verbatim)."""
    q = _minimal_answered_question()
    q["answer"]["modification_locus"] = {"type": "gm_worldscan"}
    reason = run_real._validate_design_questions(_minimal_doc(q), None)
    assert reason == "", reason


# --- détection normative amont (marqueur littéral, documentée) --------------

def test_project_declares_normative_structure_detecte_p1_alpha():
    # p1_alpha porte reellement le marqueur (project_specific.techniques).
    assert run_real._project_declares_normative_structure(P1_ALPHA) is True


def test_project_declares_normative_structure_absent_pour_p1_beta():
    # p1_beta est le bras LIBRE — aucune structure imposée.
    assert run_real._project_declares_normative_structure(P1_BETA) is False


def test_project_declares_normative_structure_run_dir_none():
    assert run_real._project_declares_normative_structure(None) is False
