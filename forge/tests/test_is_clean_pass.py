"""Garde-fou canonique `is_clean_pass` (footgun decision, 2026-07-11).

`HUMANGATE_READY` est un PRÉFIXE de `HUMANGATE_READY_WITH_OBJECTION` : un
consommateur naïf pourrait promouvoir un OK-avec-objection. Le seul prédicat
autorisé pour décider une promotion est `is_clean_pass` — égalité STRICTE, jamais
software_verdict seul. Objectif unique : un OK technique porteur d'une objection
(ou d'un flag) n'est JAMAIS promouvable automatiquement. NO_CLAIM_ALLOWED.
"""
import json
from pathlib import Path

from forge import studio_link as sl
from forge.verdict import is_clean_pass


def _v(software="OK", decision="HUMANGATE_READY", flags=()):
    return {"software_verdict": software, "decision": decision,
            "humangate_flags": list(flags), "claim_verdict": "NO_CLAIM_ALLOWED",
            "evidence_verdict": "MECHANICAL_VALIDATION_ONLY"}


# --- les 3 cas exigés -------------------------------------------------------------

def test_ok_ready_sans_flag_est_clean_pass():
    assert is_clean_pass(_v("OK", "HUMANGATE_READY", ())) is True


def test_ok_with_objection_jamais_clean_pass():
    assert is_clean_pass(_v("OK", "HUMANGATE_READY_WITH_OBJECTION", ())) is False


def test_ok_avec_flag_jamais_clean_pass():
    assert is_clean_pass(_v("OK", "HUMANGATE_READY", ("red-team dégradé",))) is False


# --- le footgun exact : préfixe / égalité stricte ---------------------------------

def test_egalite_stricte_pas_de_prefixe():
    """La cause racine : WITH_OBJECTION commence par HUMANGATE_READY. Un helper
    correct utilise l'égalité stricte, jamais startswith/in."""
    v = _v("OK", "HUMANGATE_READY_WITH_OBJECTION", ())
    assert v["decision"].startswith("HUMANGATE_READY")   # le piège existe bien
    assert is_clean_pass(v) is False                     # mais le helper ne tombe pas dedans


# --- non-OK et entrées défensives -------------------------------------------------

def test_fail_ou_blocked_jamais_clean_pass():
    assert is_clean_pass(_v("FAIL", "BLOCKED", ())) is False
    assert is_clean_pass(_v("BLOCKED", "BLOCKED", ())) is False


def test_entrees_degradees_jamais_clean_pass():
    assert is_clean_pass(None) is False
    assert is_clean_pass({}) is False
    assert is_clean_pass({"software_verdict": "OK"}) is False        # decision absente
    assert is_clean_pass({"decision": "HUMANGATE_READY"}) is False   # software absent


# --- le point de promotion consomme le helper -------------------------------------

def test_proposition_ledger_porte_clean_pass_false_sur_objection(tmp_path):
    """La proposition de promotion transporte le signal canonique, PAS seulement
    software_verdict : un survivant trié (OK + WITH_OBJECTION) => clean_pass False."""
    p = tmp_path / "prop.jsonl"
    rec = sl.propose_ledger_entry(
        "run-1", "jeu", _v("OK", "HUMANGATE_READY_WITH_OBJECTION", ("mutation: 1 survivant trié",)),
        proposals_path=p)
    assert rec["software_verdict"] == "OK"    # inchangé (vocabulaire préservé)
    assert rec["clean_pass"] is False         # mais la promotion sait que ce n'est pas propre
    assert rec["lane"] == "AUDIT_REQUIRED"    # propose-only inchangé


def test_proposition_ledger_clean_pass_true_sur_ok_propre(tmp_path):
    p = tmp_path / "prop.jsonl"
    rec = sl.propose_ledger_entry("run-1", "jeu", _v("OK", "HUMANGATE_READY", ()),
                                  proposals_path=p)
    assert rec["clean_pass"] is True
