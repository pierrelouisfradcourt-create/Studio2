"""Doctrine P0.3 du triage mutation (ratifiée Pierre 2026-07-11).

Un mutant survivant ne peut JAMAIS produire un verdict OK *propre*. Le triage
reste autorisé mais devient une EXCEPTION TRACÉE (pas une preuve d'équivalence) :
survivant trié + justif => software_verdict OK MAIS decision
HUMANGATE_READY_WITH_OBJECTION + flag obligatoire (HumanGate avant tout claim
positif). Survivant non trié => FAIL. 100% tués => OK propre. NO_CLAIM_ALLOWED.
"""
import json
import sys
from dataclasses import asdict
from pathlib import Path

import pytest

from forge.mutation_proof import emit_mutation_receipt, run_mutation_for_game
from forge.static_oracles import check_mutation_gate
from forge.verdict import (
    DECISION_READY,
    DECISION_READY_OBJECTION,
    build_aggregate_verdict,
    make_signed_receipt,
    new_nonce,
)


# --- 1. le gate distingue l'exception de triage du 100% propre --------------------

def test_gate_100pct_sans_exception():
    r = {"total": 3, "killed": 3, "survived": 0, "survivors": []}
    g = check_mutation_gate(r, [])
    assert g["passed"] is True
    assert g["exception"] is False
    assert g["triaged_survivors"] == []


def test_gate_survivant_trie_est_une_exception():
    r = {"total": 3, "killed": 2, "survived": 1,
         "survivors": [{"name": "ge->gt", "line": 4}]}
    triage = [{"name": "ge->gt", "line": 4, "justification": "borne inatteignable"}]
    g = check_mutation_gate(r, triage)
    assert g["passed"] is True          # le triage reste autorisé (gate franchi)
    assert g["exception"] is True       # MAIS c'est une exception tracée
    assert g["triaged_survivors"] == ["ge->gt@L4"]


def test_gate_survivant_non_trie_reste_fail():
    r = {"total": 3, "killed": 2, "survived": 1,
         "survivors": [{"name": "ge->gt", "line": 4}]}
    g = check_mutation_gate(r, [])
    assert g["passed"] is False
    assert g["exception"] is False      # un FAIL n'est jamais une exception


# --- 2. le reçu mutation porte le marqueur d'exception ----------------------------

def _game(tmp_path):
    d = tmp_path / "game"
    d.mkdir()
    (d / "logic.mjs").write_text("export const win = 1 >= 0;\n", encoding="utf-8")
    (d / "logic.test.mjs").write_text("// suite\n", encoding="utf-8")
    return d


def _survivor_runner(sp, argv, *, cwd, **k):
    return {"total": 3, "killed": 2, "survived": 1, "score": 0.667,
            "survivors": [{"name": "ge->gt", "line": 1}]}


def test_recu_mutation_survivant_trie_est_ok_avec_exception(tmp_path):
    d = _game(tmp_path)
    (d / "mutation_triage.json").write_text(
        json.dumps([{"name": "ge->gt", "line": 1, "justification": "équivalent prouvé"}]),
        encoding="utf-8")
    result = run_mutation_for_game(d, ["logic.mjs"], runner=_survivor_runner,
                                   baseline_runner=lambda argv, cwd: True)
    sr = emit_mutation_receipt("run-1", d, ["logic.mjs"], result,
                               key_file=tmp_path / "key", evidence_dir=tmp_path / "ev")
    assert sr.receipt.status == "OK"                       # gate franchi (triage)
    assert sr.receipt.detail["mutation_exception"] is True  # mais tracé exception
    assert sr.receipt.detail["triaged_survivors"] == ["ge->gt@L1"]


def test_recu_mutation_100pct_sans_exception(tmp_path):
    d = _game(tmp_path)

    def _all_killed(sp, argv, *, cwd, **k):
        return {"total": 3, "killed": 3, "survived": 0, "score": 1.0, "survivors": []}

    result = run_mutation_for_game(d, ["logic.mjs"], runner=_all_killed,
                                   baseline_runner=lambda argv, cwd: True)
    sr = emit_mutation_receipt("run-1", d, ["logic.mjs"], result,
                               key_file=tmp_path / "key", evidence_dir=tmp_path / "ev")
    assert sr.receipt.status == "OK"
    assert sr.receipt.detail["mutation_exception"] is False


# --- 3. le verdict agrégé refuse un OK propre sur exception de triage -------------

def _code_receipt_with_mutation(tmp_path, run_id, exception, key):
    ev = tmp_path / "mut_ev.json"
    ev.write_text("{}", encoding="utf-8")
    mut = make_signed_receipt(
        "mutation", run_id, "OK",
        {"mutation_exception": exception,
         "triaged_survivors": ["ge->gt@L1"] if exception else [],
         "code_sha256": {"logic.mjs": "x"}, "test_files_scelles": ["logic.test.mjs"],
         "baseline_ok": True, "triage_sha256": ""},
        evidence_path=str(ev), key_file=key)
    code_ev = tmp_path / "oracle.log"
    code_ev.write_text("log\n", encoding="utf-8")
    return make_signed_receipt(
        "code", run_id, "OK",
        {"returncode": 0, "e2e": {"passed": True, "raisons": []},
         "mutation": {"receipt": asdict(mut.receipt), "signature": mut.signature}},
        evidence_path=str(code_ev), key_file=key)


def test_verdict_exception_triage_est_with_objection(tmp_path):
    key = tmp_path / "key"
    code = _code_receipt_with_mutation(tmp_path, "run-1", exception=True, key=key)
    archi = make_signed_receipt("archi", "run-1", "SKIPPED", {"reason": "p"}, key_file=key)
    wire = make_signed_receipt("wiremap", "run-1", "SKIPPED", {"reason": "p"}, key_file=key)
    agg = build_aggregate_verdict("jeu", "run-1", code, archi, wire, "aucun",
                                  redteam_ran=True, nonce=new_nonce(), key_file=key)
    assert agg.software_verdict == "OK"                 # vocabulaire préservé
    assert agg.decision == DECISION_READY_OBJECTION     # JAMAIS un OK propre
    assert any("survivant" in f for f in agg.humangate_flags)


def test_verdict_100pct_reste_ok_propre(tmp_path):
    key = tmp_path / "key"
    code = _code_receipt_with_mutation(tmp_path, "run-1", exception=False, key=key)
    archi = make_signed_receipt("archi", "run-1", "SKIPPED", {"reason": "p"}, key_file=key)
    wire = make_signed_receipt("wiremap", "run-1", "SKIPPED", {"reason": "p"}, key_file=key)
    agg = build_aggregate_verdict("jeu", "run-1", code, archi, wire, "aucun",
                                  redteam_ran=True, nonce=new_nonce(), key_file=key)
    assert agg.software_verdict == "OK"
    assert agg.decision == DECISION_READY               # 100% => OK propre autorisé
    assert not any("survivant" in f for f in agg.humangate_flags)
