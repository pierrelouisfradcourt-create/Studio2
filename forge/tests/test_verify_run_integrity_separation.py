"""V1 — sépare mécaniquement DEUX registres dans `verify_run` : (A) authenticité/
intégrité du run (HMAC, signatures, empreintes, évidence, cohérence des preuves)
— seul registre qui décide le REJET/exit code — et (B) verdict logiciel
(OK/FAIL/BLOCKED) — rapporté, jamais cause de rejet.

Contexte (run réel pong_r2, 2026-07-26) : verify_run rendait « REJET / exit 2 »
sur un verdict FAIL/BLOCKED parfaitement authentique (HMAC OK, évidence OK,
knowledge_trace OK, provenance_ok=true), pour l'unique motif « gate mutation
non vert (status=FAIL) » — un FAIT DE VERDICT, pas un fait d'intégrité. Cette
suite prouve : (1) un FAIL/BLOCKED honnête devient AUTHENTIQUE (exit 0) ;
(2) un verdict qui PRÉTEND OK alors que le gate mutation embarqué est rouge
reste REJETÉ (exit 2) — c'est le seul cas où un gate mutation rouge doit
encore bloquer (design imposé pt.3, COHÉRENCE = GATE DUR) ; (3) le gate
mutation DUR du driver (verify_mutation_receipt à require_green=True par
défaut) reste inchangé. NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
import time
from dataclasses import asdict
from pathlib import Path

import pytest

from forge.mutation_proof import (
    emit_mutation_receipt,
    run_mutation_for_game,
    verify_mutation_receipt,
)
from forge.verdict import (
    build_aggregate_verdict,
    make_signed_receipt,
    new_nonce,
    signed_aggregate_record,
)
from forge.verify_run import verify_run


def _game(tmp_path):
    g = tmp_path / "game"
    g.mkdir()
    (g / "logic.mjs").write_text("export const win = 1 >= 0;\n", encoding="utf-8")
    (g / "logic.test.mjs").write_text("// suite\n", encoding="utf-8")
    return g


def _all_killed(source_path, test_argv, *, cwd, **kw):
    return {"total": 4, "killed": 4, "survived": 0, "score": 1.0, "survivors": []}


def _one_survivor(source_path, test_argv, *, cwd, **kw):
    return {"total": 4, "killed": 3, "survived": 1, "score": 0.75,
            "survivors": [{"name": "ge->gt", "line": 1}]}


def _baseline_ok(argv, cwd):
    return True


# --- (1) mutation_proof.verify_mutation_receipt : require_green -------------------

def test_require_green_defaut_true_comportement_inchange(tmp_path):
    """Le défaut préserve EXACTEMENT le comportement actuel : un reçu FAIL est
    refusé sans passer `require_green` — c'est le gate DUR du driver (l.846),
    jamais affaibli par cette mission."""
    g = _game(tmp_path)
    key = tmp_path / "key"
    result = run_mutation_for_game(g, ["logic.mjs"], runner=_one_survivor,
                                   baseline_runner=_baseline_ok)
    sr = emit_mutation_receipt("run-1", g, ["logic.mjs"], result, key_file=key,
                               evidence_dir=tmp_path / "evidence")
    assert sr.receipt.status == "FAIL"
    check = verify_mutation_receipt(asdict(sr.receipt), sr.signature, "run-1", g,
                                    key_file=key)  # PAS de require_green -> défaut
    assert check["passed"] is False
    assert any("gate mutation non vert" in r for r in check["raisons"])


def test_require_green_false_omet_la_raison_de_verdict(tmp_path):
    """require_green=False : la raison « gate mutation non vert » n'est PAS
    ajoutée — mais toutes les AUTRES raisons (intégrité) restent actives."""
    g = _game(tmp_path)
    key = tmp_path / "key"
    result = run_mutation_for_game(g, ["logic.mjs"], runner=_one_survivor,
                                   baseline_runner=_baseline_ok)
    sr = emit_mutation_receipt("run-1", g, ["logic.mjs"], result, key_file=key,
                               evidence_dir=tmp_path / "evidence")
    assert sr.receipt.status == "FAIL"
    check = verify_mutation_receipt(asdict(sr.receipt), sr.signature, "run-1", g,
                                    key_file=key, require_green=False)
    assert not any("gate mutation non vert" in r for r in check["raisons"])
    assert check["passed"] is True, check["raisons"]  # rien d'autre à reprocher ici


def test_require_green_false_garde_les_raisons_dintegrite(tmp_path):
    """require_green=False n'ouvre PAS la porte à un code périmé : le hash
    divergent reste un refus, greenness ou pas."""
    g = _game(tmp_path)
    key = tmp_path / "key"
    result = run_mutation_for_game(g, ["logic.mjs"], runner=_all_killed,
                                   baseline_runner=_baseline_ok)
    sr = emit_mutation_receipt("run-1", g, ["logic.mjs"], result, key_file=key,
                               evidence_dir=tmp_path / "evidence")
    assert sr.receipt.status == "OK"
    (g / "logic.mjs").write_text("export const win = false;\n", encoding="utf-8")
    check = verify_mutation_receipt(asdict(sr.receipt), sr.signature, "run-1", g,
                                    key_file=key, require_green=False)
    assert check["passed"] is False
    assert any("divergent" in r for r in check["raisons"])


@pytest.mark.parametrize("require_green", [True, False])
def test_status_toujours_present_sur_reponse_valide(tmp_path, require_green):
    """(design pt.1) Le retour rend TOUJOURS une clé `status` — aucun appelant
    ne parse une chaîne française pour connaître le statut."""
    g = _game(tmp_path)
    key = tmp_path / "key"
    result = run_mutation_for_game(g, ["logic.mjs"], runner=_all_killed,
                                   baseline_runner=_baseline_ok)
    sr = emit_mutation_receipt("run-1", g, ["logic.mjs"], result, key_file=key,
                               evidence_dir=tmp_path / "evidence")
    check = verify_mutation_receipt(asdict(sr.receipt), sr.signature, "run-1", g,
                                    key_file=key, require_green=require_green)
    assert check["status"] == "OK"


def test_status_present_meme_sur_recu_absent():
    check = verify_mutation_receipt(None, "", "run-1", "peu-importe")
    assert "status" in check
    assert check["passed"] is False


# --- (2) verify_run : un FAIL/BLOCKED honnête devient AUTHENTIQUE -----------------

def _game_with_gate(tmp_path, runner):
    g = _game(tmp_path)
    (g / "run-oracle.mjs").write_text("// harnais e2e (marqueur game-ness)\n",
                                      encoding="utf-8")
    key = tmp_path / "key"
    result = run_mutation_for_game(g, ["logic.mjs"], runner=runner,
                                   baseline_runner=_baseline_ok)
    mr = emit_mutation_receipt("run-1", g, ["logic.mjs"], result, key_file=key,
                               evidence_dir=tmp_path / "evidence")
    return g, key, mr


def test_verdict_fail_honnete_avec_gate_mutation_rouge_est_authentique(tmp_path):
    """LE cas pong_r2 reconstitué : software_verdict=FAIL, reçu mutation rouge
    mais authentique (signature/hash/triage intacts) -> exit 0, overall True."""
    g, key, mr = _game_with_gate(tmp_path, _one_survivor)
    evidence = tmp_path / "oracle.log"
    evidence.write_text("log\n", encoding="utf-8")
    code = make_signed_receipt(
        "code", "run-1", "FAIL",
        {"returncode": 1, "e2e": {"passed": True, "raisons": []},
         "mutation": {"receipt": asdict(mr.receipt), "signature": mr.signature}},
        evidence_path=str(evidence), ts=time.time(), key_file=key)
    archi = make_signed_receipt("archi", "run-1", "SKIPPED", {"reason": "profil"},
                                ts=time.time(), key_file=key)
    wire = make_signed_receipt("wiremap", "run-1", "SKIPPED", {"reason": "profil"},
                               ts=time.time(), key_file=key)
    agg = build_aggregate_verdict(
        "jeu", "run-1", code, archi, wire, "aucun",
        redteam_ran=False, nonce=new_nonce(), ts=time.time(), key_file=key)
    assert agg.software_verdict == "FAIL"  # préalable : verdict honnêtement rouge
    verdict_path = tmp_path / "verdict.json"
    verdict_path.write_text(
        json.dumps(signed_aggregate_record(agg, key_file=key), ensure_ascii=False),
        encoding="utf-8")

    res = verify_run(verdict_path, key_file=key)
    assert res["overall"] is True, res  # AUTHENTIQUE malgré le gate mutation rouge
    assert res.get("coherence_problems") == []
    assert res.get("mutation_status") == "FAIL"
    assert res.get("mutation_gate_green") is False
    assert res.get("mutation_integrity_problems") == []


# --- (3) NON-RÉGRESSION DE SÉCURITÉ : un OK affiché sur gate rouge reste rejeté ---

def test_verdict_pretendant_ok_avec_gate_mutation_rouge_reste_rejete(tmp_path):
    """Le seul cas où un gate mutation rouge doit ENCORE bloquer (design imposé
    pt.3) : software_verdict=OK affiché alors que le reçu mutation embarqué,
    authentique, est rouge — un producteur malhonnête (ou un bug d'agrégation)
    qui affiche un vert non prouvé. NE DOIT JAMAIS devenir AUTHENTIQUE, avant
    comme après le passage à require_green=False pour le cas honnête."""
    g, key, mr = _game_with_gate(tmp_path, _one_survivor)
    evidence = tmp_path / "oracle.log"
    evidence.write_text("log\n", encoding="utf-8")
    # Le reçu CODE ment : il affiche OK alors que la preuve mutation qu'il
    # embarque lui-même est rouge (authentique, signée, juste pas verte).
    code = make_signed_receipt(
        "code", "run-1", "OK",
        {"returncode": 0, "e2e": {"passed": True, "raisons": []},
         "mutation": {"receipt": asdict(mr.receipt), "signature": mr.signature}},
        evidence_path=str(evidence), ts=time.time(), key_file=key)
    archi = make_signed_receipt("archi", "run-1", "SKIPPED", {"reason": "profil"},
                                ts=time.time(), key_file=key)
    wire = make_signed_receipt("wiremap", "run-1", "SKIPPED", {"reason": "profil"},
                               ts=time.time(), key_file=key)
    agg = build_aggregate_verdict(
        "jeu", "run-1", code, archi, wire, "aucun",
        redteam_ran=False, nonce=new_nonce(), ts=time.time(), key_file=key)
    assert agg.software_verdict == "OK"  # le mensonge PASSE l'agrégation seule
    verdict_path = tmp_path / "verdict.json"
    verdict_path.write_text(
        json.dumps(signed_aggregate_record(agg, key_file=key), ensure_ascii=False),
        encoding="utf-8")

    res = verify_run(verdict_path, key_file=key)
    assert res["overall"] is False, (
        "un OK affiché sur un gate mutation rouge doit rester REJETÉ "
        "(cohérence = gate dur, design imposé pt.3)")
    assert res.get("coherence_problems"), res
    assert any("vert" in p or "OK" in p or "FAIL" in p
              for p in res["coherence_problems"])


def test_verdict_ok_authentique_gate_vert_reste_authentique(tmp_path):
    """Non-régression du chemin heureux : software_verdict=OK + gate mutation
    RÉELLEMENT vert -> toujours AUTHENTIQUE (aucune coherence_problems)."""
    g, key, mr = _game_with_gate(tmp_path, _all_killed)
    assert mr.receipt.status == "OK"
    evidence = tmp_path / "oracle.log"
    evidence.write_text("log\n", encoding="utf-8")
    code = make_signed_receipt(
        "code", "run-1", "OK",
        {"returncode": 0, "e2e": {"passed": True, "raisons": []},
         "mutation": {"receipt": asdict(mr.receipt), "signature": mr.signature}},
        evidence_path=str(evidence), ts=time.time(), key_file=key)
    archi = make_signed_receipt("archi", "run-1", "SKIPPED", {"reason": "profil"},
                                ts=time.time(), key_file=key)
    wire = make_signed_receipt("wiremap", "run-1", "SKIPPED", {"reason": "profil"},
                               ts=time.time(), key_file=key)
    agg = build_aggregate_verdict(
        "jeu", "run-1", code, archi, wire, "aucun",
        redteam_ran=False, nonce=new_nonce(), ts=time.time(), key_file=key)
    assert agg.software_verdict == "OK"
    verdict_path = tmp_path / "verdict.json"
    verdict_path.write_text(
        json.dumps(signed_aggregate_record(agg, key_file=key), ensure_ascii=False),
        encoding="utf-8")

    res = verify_run(verdict_path, key_file=key)
    assert res["overall"] is True, res
    assert res.get("coherence_problems") == []
    assert res.get("mutation_gate_green") is True


# --- (4) CLI : deux lignes distinctes -----------------------------------------

def test_cli_separe_integrite_et_verdict_logiciel(monkeypatch, capsys):
    """CLI (design pt.5) : deux lignes distinctes, jamais fusionnées.

    `main()` n'a pas d'option `--key-file` (limitation pré-existante, hors
    périmètre V1) : il appelle toujours `verify_run(path)` avec la clé forge
    par défaut. Comme les tests d'encodage existants (test_verify_run_encoding.py),
    on isole donc le formatage CLI de la signature réelle via monkeypatch de
    `vr.verify_run`, avec un résultat représentatif du cas pong_r2 (FAIL/BLOCKED
    authentique)."""
    from forge import verify_run as vr

    fake_res = {
        "overall": True, "integrity_ok": True,
        "hmac_ok": True, "evidence_ok": True, "evidence_problems": [],
        "mutation_ok": False,
        "mutation_problems": ["gate mutation non vert (status=FAIL)"],
        "mutation_integrity_problems": [],
        "mutation_gate_green": False, "mutation_status": "FAIL",
        "coherence_problems": [],
        "git_ok": True, "git_stored": "", "git_current": "x" * 40,
        "knowledge_trace_ok": True, "knowledge_trace_problems": [],
        "knowledge_trace_warnings": [],
        "software_verdict": "FAIL", "decision": "BLOCKED",
    }
    monkeypatch.setattr(vr, "verify_run", lambda p: fake_res)

    code_exit = vr.main(["peu/importe/verdict.json"])
    out = capsys.readouterr().out
    assert code_exit == 0
    assert "INTÉGRITÉ" in out and "AUTHENTIQUE" in out
    assert "VERDICT LOGICIEL" in out and "FAIL" in out and "BLOCKED" in out
