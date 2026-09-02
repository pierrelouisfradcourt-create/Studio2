# -*- coding: utf-8 -*-
"""ADR-003 lot 1 — tests des 5 P0, un bloc par sous-lot, causalement attribués.

Source : docs/adr/ADR-003-forge-workflow-coherence-audit.md (GO Pierre 2026-08-15).
Nouveau fichier : n'altère aucun test existant (zone protégée respectée).
"""
from __future__ import annotations

from pathlib import Path
# ---------------------------------------------------------------------------
# P0-2 — la game-ness est un champ SIGNÉ du verdict, plus une inférence seule.
# Avant : verify_run dérivait « jeu » des clés FACULTATIVES e2e/mutation/
# solvability du detail du reçu code ; une recette minimale ({"returncode"}) se
# faisait classer non-jeu → verdict AUTHENTIQUE sans preuve mutation vérifiée.
# ---------------------------------------------------------------------------

import json

from forge.verdict import (build_aggregate_verdict, make_signed_receipt,
                           new_nonce, signed_aggregate_record, status_from_passed)
from forge.verify_run import verify_run


def _verdict_minimal(tmp_path: Path, *, is_game) -> Path:
    """Verdict complet signé dont le reçu code suit la recette MINIMALE de
    l'ancien skill ({"returncode": 0}, sans e2e/mutation/solvability)."""
    evidence = tmp_path / "oracle.log"
    evidence.write_text("returncode=0\n", encoding="utf-8")
    run_id = "run-adr003-p02"
    code_r = make_signed_receipt("code", run_id, "OK", {"returncode": 0},
                                 evidence_path=str(evidence))
    archi_r = make_signed_receipt("archi", run_id, status_from_passed(True), {"passed": True})
    wire_r = make_signed_receipt("wiremap", run_id, status_from_passed(True), {"passed": True})
    agg = build_aggregate_verdict(
        "adr003", run_id, code_r, archi_r, wire_r, "aucun",
        redteam_ran=False, nonce=new_nonce(), is_game=is_game,
    )
    out = tmp_path / "verdict.json"
    out.write_text(json.dumps(signed_aggregate_record(agg), ensure_ascii=False,
                              sort_keys=True, indent=1), encoding="utf-8")
    return out


def test_p0_2_jeu_declare_sans_preuve_mutation_est_rejete(tmp_path: Path):
    """Scénario exact du P0, côté fermé : is_game=True signé + reçu code minimal
    → verify_run doit refuser l'intégrité (jeu sans preuve mutation embarquée)."""
    res = verify_run(_verdict_minimal(tmp_path, is_game=True))
    assert res["hmac_ok"], "le verdict avec champ is_game doit rester signable/vérifiable"
    assert res["mutation_integrity_problems"], (
        "un verdict déclaré is_game=True sans preuve mutation doit porter un problème"
    )
    assert any("is_game=True" in p for p in res["mutation_integrity_problems"])
    assert not res["overall"], "l'intégrité ne doit pas passer sans preuve mutation"


def test_p0_2_contraste_trou_historique_documente(tmp_path: Path):
    """Le même verdict SANS déclaration (is_game=None) reste classé non-jeu par
    l'inférence (filet rétro-compat) : c'était le trou — ce test documente le
    contraste et protège le comportement des verdicts historiques non-jeu."""
    res = verify_run(_verdict_minimal(tmp_path, is_game=None))
    assert res["hmac_ok"]
    assert res["mutation_integrity_problems"] == [], (
        "un verdict non déclaré et sans marqueur de jeu reste un non-jeu (rétro-compat)"
    )




def test_p0_2_hmac_retrocompatible_sans_champ_is_game(tmp_path: Path):
    """Un verdict.json HISTORIQUE (mapping stocké SANS la clé is_game) doit
    toujours se vérifier : verify_run re-signe le mapping stocké, jamais une
    reconstruction par dataclass."""
    path = _verdict_minimal(tmp_path, is_game=None)
    data = json.loads(path.read_text(encoding="utf-8"))
    hmac_stored = data.pop("hmac")
    data.pop("is_game")  # simule un verdict d'avant le champ
    from forge.verdict import _sign_mapping
    data["hmac"] = _sign_mapping(data, None)
    assert data["hmac"], "re-signature du mapping historique impossible"
    path.write_text(json.dumps(data, ensure_ascii=False, sort_keys=True, indent=1),
                    encoding="utf-8")
    res = verify_run(path)
    assert res["hmac_ok"], "un verdict sans la clé is_game doit rester vérifiable"
