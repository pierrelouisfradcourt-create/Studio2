# -*- coding: utf-8 -*-
"""ADR-003 lot 1 — tests des 5 P0, un bloc par sous-lot, causalement attribués.

Source : docs/adr/ADR-003-forge-workflow-coherence-audit.md (GO Pierre 2026-08-15).
Nouveau fichier : n'altère aucun test existant (zone protégée respectée).
"""
from __future__ import annotations

from pathlib import Path

from forge.verdict import (build_aggregate_verdict, make_signed_receipt,
                           new_nonce, signed_aggregate_record, status_from_passed)
# ---------------------------------------------------------------------------
# P0-3 — observable_coverage cesse d'être calculé puis jeté : OBJECTION SIGNÉE.
# Avant (breakout_v2) : observable_coverage BLOCKED + 3 volets pixel rouges,
# s10s=OK (hors _CORE_FACETS) et verdict signé HUMANGATE_READY sans un mot.
# Après : le rouge produit pousse decision → HUMANGATE_READY_WITH_OBJECTION et
# apparaît dans humangate_flags. PAS un gate dur (décision E non prise).
# ---------------------------------------------------------------------------

def _state_breakout_like(passed: bool) -> dict:
    """State minimal de la forme réelle de EVIDENCE/runs/breakout_v2/state.json."""
    cov = {"verdict": "OK" if passed else "BLOCKED", "passed": passed}
    if not passed:
        cov["volets_en_echec"] = ["render.field_visible:demo_start_visible",
                                  "render.brick_destruction:demo_brick_destruction"]
    return {"steps": {"s10s-oracle-standard": {"status": "OK",
                                               "detail": {"observable_coverage": cov}}}}


def test_p0_3_rouge_produit_produit_une_objection():
    from forge.driver import ForgeDriver
    facts = ForgeDriver._observable_facts(None, _state_breakout_like(passed=False))
    assert len(facts) == 1
    assert "observable_coverage BLOCKED" in facts[0]
    assert "demo_brick_destruction" in facts[0], "les volets rouges doivent être cités"


def test_p0_3_vert_ou_absent_aucune_objection():
    from forge.driver import ForgeDriver
    assert ForgeDriver._observable_facts(None, _state_breakout_like(passed=True)) == ()
    assert ForgeDriver._observable_facts(None, {"steps": {}}) == ()  # profil sans s10s


def test_p0_3_objection_signee_dans_le_verdict(tmp_path: Path):
    """Bout-en-bout : oracles verts + objection observable → software_verdict
    reste OK (jamais un juge) mais decision = WITH_OBJECTION et le flag est
    visible ET signé (il fait partie du mapping HMAC)."""
    from forge.driver import ForgeDriver
    from forge.verdict import DECISION_READY_OBJECTION, is_clean_pass

    evidence = tmp_path / "oracle.log"
    evidence.write_text("ok\n", encoding="utf-8")
    run_id = "run-adr003-p03"
    code_r = make_signed_receipt("code", run_id, "OK", {"returncode": 0},
                                 evidence_path=str(evidence))
    archi_r = make_signed_receipt("archi", run_id, "OK", {"passed": True})
    wire_r = make_signed_receipt("wiremap", run_id, "OK", {"passed": True})
    facts = ForgeDriver._observable_facts(None, _state_breakout_like(passed=False))
    agg = build_aggregate_verdict(
        "adr003", run_id, code_r, archi_r, wire_r, "aucun",
        redteam_ran=True, nonce=new_nonce(), extra_advisory=facts,
    )
    assert agg.software_verdict == "OK", "l'objection ne juge jamais le code"
    assert agg.decision == DECISION_READY_OBJECTION, (
        "un rouge produit ne peut plus sortir en HUMANGATE_READY silencieux"
    )
    assert any("observable_coverage" in f for f in agg.humangate_flags)
    assert not is_clean_pass(signed_aggregate_record(agg)), (
        "jamais un passage propre avec une objection produit"
    )


