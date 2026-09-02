# P5 2026-08-15 — garde de non-vacuité wiremap (check_line_states).
#
# Défaut mesuré (code review 2026-08-15) : une wiremap `lines: []` passait
# check_line_states / placement / collisions / genre_coverage par vacuité —
# zéro contrainte vérifiée, PASS affiché (seuls core_omis si core_requirements
# fourni, et le scan disque de check_index, compensaient). Correctif : lignes
# vides => FAIL explicite, sauf `no_lines_waiver {reason, decider}` (même
# convention de traçabilité que DEFERRED), toujours remonté au rapport.
# Le waiver n'excuse QUE la vacuité — jamais une exigence core omise.
from __future__ import annotations

import json
from pathlib import Path

from forge.standard_oracles import check_line_states

REPO = Path(__file__).resolve().parents[2]


def test_lines_vides_sans_waiver_fail():
    rep = check_line_states({"game_id": "g", "lines": []}, {}, frozen="built")
    assert rep["passed"] is False
    assert "vacuité" in rep["raison"]


def test_lines_absentes_sans_waiver_fail():
    rep = check_line_states({"game_id": "g"}, {}, frozen="built")
    assert rep["passed"] is False
    assert "vacuité" in rep["raison"]


def test_waiver_valide_passe_et_reste_trace():
    waiver = {"reason": "module bibliothèque sans ligne observable",
              "decider": "Pierre"}
    rep = check_line_states({"game_id": "g", "lines": [],
                             "no_lines_waiver": waiver}, {}, frozen="built")
    assert rep["passed"] is True
    assert rep["no_lines_waiver"] == waiver     # jamais silencieux


def test_waiver_incomplet_refuse():
    # decider manquant => pas un waiver : la traçabilité est la condition.
    rep = check_line_states(
        {"game_id": "g", "lines": [], "no_lines_waiver": {"reason": "bof"}},
        {}, frozen="built")
    assert rep["passed"] is False
    assert "vacuité" in rep["raison"]


def test_waiver_n_excuse_pas_les_core_omis():
    waiver = {"reason": "carte vide assumée", "decider": "Pierre"}
    core = {"requirements": [{"id": "core.restart"}]}
    rep = check_line_states({"game_id": "g", "lines": [],
                             "no_lines_waiver": waiver}, core, frozen="built")
    assert rep["core_omis"], "une exigence core omise doit rester une violation"
    assert rep["passed"] is False


def test_l_oracle_accepte_l_artefact_de_reference():
    # leçon oracle_must_accept_reference : la wiremap réelle de Tetris (22 lignes)
    # ne doit jamais déclencher la garde de vacuité.
    wm = json.loads((REPO / "GAMES/tetris/09_WIREMAP/wiremap.json")
                    .read_text(encoding="utf-8"))
    rep = check_line_states(wm, {}, frozen="built")
    assert "vacuité" not in rep.get("raison", "")
