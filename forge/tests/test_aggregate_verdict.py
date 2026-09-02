"""Oracle du verdict agrégé signé (A3 + provenance, étape 2).

`build_aggregate_verdict` plie des REÇUS D'ORACLE SIGNÉS (code/archi/wiremap) + le
red-team en un verdict signé HMAC. Invariants vérifiés ici :

  - PROVENANCE : un reçu absent/altéré/discordant (run_id) => software BLOCKED.
    Impossible de prononcer OK sans reçus valides prouvant l'exécution des oracles.
  - `software_verdict` vient UNIQUEMENT des reçus vérifiés (pas du red-team).
  - le red-team est ADVISORY : il lève des flags, il n'inverse jamais software.
  - identité RÉELLE du reviewer (A2) signée ; honnêteté via `redteam_ran` STRUCTURÉ.
  - anti-rejeu : run_id/nonce/ts/git_head signés.
"""
import tempfile
from dataclasses import asdict
from pathlib import Path

from forge.verdict import (
    build_aggregate_verdict,
    is_clean_pass,
    make_signed_receipt,
    sign_aggregate,
    signed_aggregate_record,
    verify_aggregate,
)

# Clé de test partagée (signe les reçus ET l'agrégat). Isolée du .forge_key réel.
KEY = Path(tempfile.mkdtemp()) / "test_key"


def _rcpt(oracle_id, status, run_id="R", detail=None, key=KEY):
    return make_signed_receipt(oracle_id, run_id, status, detail or {}, key_file=key)


def _code_receipt(status="OK", run_id="R", key=KEY):
    """Reçu CODE avec un vrai fichier d'évidence (l'oracle code = commande externe)."""
    ev = Path(tempfile.mkdtemp()) / "oracle.log"
    ev.write_text("$ oracle\n--- stdout ---\nok\n", encoding="utf-8")
    return make_signed_receipt("code", run_id, status, {"returncode": 0 if status == "OK" else 1},
                               evidence_path=str(ev), key_file=key)


def _agg(code="OK", archi="OK", wiremap="OK", run_id="R",
         reviewer="qwen2.5-14b-instruct", redteam_ran=True,
         redteam_findings=(), redteam_blocked=False,
         archi_detail=None, wiremap_detail=None, nonce="n1", key=KEY,
         code_rcpt=None, archi_rcpt=None, wiremap_rcpt=None):
    return build_aggregate_verdict(
        "demo", run_id,
        code_rcpt or _code_receipt(code, run_id, key),
        archi_rcpt or _rcpt("archi", archi, run_id, archi_detail, key=key),
        wiremap_rcpt or _rcpt("wiremap", wiremap, run_id, wiremap_detail, key=key),
        reviewer, redteam_ran=redteam_ran, redteam_findings=redteam_findings,
        redteam_blocked=redteam_blocked, nonce=nonce, key_file=key,
    )


# --- software_verdict = reçus d'oracle VÉRIFIÉS seuls -------------------------

def test_all_green_is_ok_and_humangate_ready():
    v = _agg()
    assert v.software_verdict == "OK"
    assert v.decision == "HUMANGATE_READY"
    assert v.provenance_ok is True
    assert v.claim_verdict == "NO_CLAIM_ALLOWED"
    assert v.evidence_verdict == "MECHANICAL_VALIDATION_ONLY"


def test_code_fail_makes_software_fail_and_blocks():
    v = _agg(code="FAIL")
    assert v.software_verdict == "FAIL"
    assert v.decision == "BLOCKED"


def test_code_blocked_makes_software_blocked():
    v = _agg(code="BLOCKED")
    assert v.software_verdict == "BLOCKED"
    assert v.decision == "BLOCKED"


def test_archi_fail_makes_software_fail_even_if_code_ok():
    v = _agg(archi="FAIL", archi_detail={"deps_interdites_violées": [["ui", "engine"]]})
    assert v.software_verdict == "FAIL"
    assert any("archi rouge" in f for f in v.humangate_flags)


def test_wiremap_fail_makes_software_fail_even_if_code_ok():
    v = _agg(wiremap="FAIL", wiremap_detail={"features_manquantes": ["login"]})
    assert v.software_verdict == "FAIL"


# --- profil réduit (patch) : oracles non applicables = SKIPPED, honnêtement ----

def test_patch_profile_skips_archi_wiremap_but_stays_ok_with_flag():
    """Profil patch : code prouvé, archi/wiremap non applicables (SKIPPED signé).

    software=OK reste légitime, mais chaque oracle sauté lève un flag visible pour
    Pierre — jamais un 'OK' silencieux qui prétend avoir tout vérifié.
    """
    v = _agg(code="OK", archi="SKIPPED", wiremap="SKIPPED")
    assert v.software_verdict == "OK"
    assert sum("non vérifiée" in f for f in v.humangate_flags) == 2


def test_skipped_code_cannot_be_ok():
    """Si l'oracle CODE lui-même est sauté, rien de substantiel n'est prouvé -> BLOCKED."""
    v = _agg(code="SKIPPED", archi="OK", wiremap="OK")
    assert v.software_verdict == "BLOCKED"


# --- PROVENANCE : sans reçu valide, pas de verdict ---------------------------

def test_tampered_receipt_breaks_provenance_and_blocks():
    other_key = Path(tempfile.mkdtemp()) / "other"
    # reçu code signé avec une AUTRE clé -> vérif échoue sous KEY -> provenance rompue
    bad_code = _rcpt("code", "OK", key=other_key)
    v = _agg(code_rcpt=bad_code)
    assert v.provenance_ok is False
    assert v.software_verdict == "BLOCKED"
    assert any("provenance rompue" in f for f in v.humangate_flags)


def test_run_id_mismatch_breaks_provenance_and_blocks():
    # reçu wiremap d'un AUTRE run -> discordance -> provenance rompue
    stray = _rcpt("wiremap", "OK", run_id="AUTRE-RUN")
    v = _agg(wiremap_rcpt=stray)
    assert v.provenance_ok is False
    assert v.software_verdict == "BLOCKED"


def test_code_receipt_without_evidence_is_blocked():
    """Ferme l'exploit red-team : un reçu code 'OK' fabriqué SANS évidence => BLOCKED."""
    fabricated = _rcpt("code", "OK")   # pas d'evidence_path -> non prouvable
    v = _agg(code_rcpt=fabricated)
    assert v.provenance_ok is False
    assert v.software_verdict == "BLOCKED"
    assert any("sans évidence" in f for f in v.humangate_flags)


def test_tampered_evidence_file_breaks_provenance(tmp_path):
    """Scellé d'évidence non décoratif : altérer le log après signature => BLOCKED."""
    from forge.verdict import make_signed_receipt
    ev = tmp_path / "oracle_demo.log"
    ev.write_text("sortie réelle de l'oracle (returncode 0)", encoding="utf-8")
    code_rcpt = make_signed_receipt("code", "R", "OK", {"returncode": 0},
                                    evidence_path=str(ev), key_file=KEY)
    ev.write_text("évidence trafiquée après coup", encoding="utf-8")   # altération
    v = _agg(code_rcpt=code_rcpt)
    assert v.provenance_ok is False
    assert v.software_verdict == "BLOCKED"
    assert any("évidence" in f and "code" in f for f in v.humangate_flags)


# --- red-team = advisory, jamais juge ----------------------------------------

def test_redteam_blocked_does_not_flip_software_but_raises_flag():
    v = _agg(redteam_blocked=True, redteam_findings=("câblage incohérent",))
    assert v.software_verdict == "OK"                    # reçus verts -> reste OK
    assert v.redteam_advisory == ("câblage incohérent",)
    assert any("red-team" in f.lower() for f in v.humangate_flags)


def test_redteam_blocked_surfaces_objection_in_decision():
    """#3 : oracles verts + red-team qui bloque => décision AVEC OBJECTION (visible à Pierre)."""
    v = _agg(redteam_blocked=True, redteam_findings=("mécanique cœur non testée",))
    assert v.software_verdict == "OK"
    assert v.decision == "HUMANGATE_READY_WITH_OBJECTION"


def test_no_objection_decision_when_redteam_clean():
    v = _agg(redteam_blocked=False)
    assert v.decision == "HUMANGATE_READY"


def test_redteam_findings_non_vides_sans_blocage_ne_change_ni_decision_ni_clean_pass():
    """(n1-findings-redteam-audibles) TEST DE NON-RÉGRESSION DE PROMOTION — le
    piège explicitement désigné par le chantier : rendre les findings AUDIBLES
    (redteam_advisory non vide) ne doit JAMAIS, à lui seul, faire basculer
    `decision` ni `is_clean_pass`. Seul `redteam_blocked` (piloté par le
    red-team lui-même, pas par la présence de findings) est le canal
    d'objection — cf. verdict.py l.391 `elif redteam_blocked or
    triage_exception or extra_advisory` : `redteam_findings` seul n'y figure
    PAS, et la construction des flags (l.413) ne lit QUE `redteam_blocked`,
    jamais `redteam_findings`.

    Un run réel avec 6 findings advisory (comme pong_r2, cf.
    rapport_redteam_code.md) et redteam_blocked=False doit rester
    is_clean_pass()==True — exactement comme un run à 0 finding."""
    findings_reels = (
        "[HIGH] collision balayée — point fantôme au mauvais camp (repro: node repro_f1.mjs)",
        "[MEDIUM] test-coverage — assertion incomplète (repro: lire loop.test.mjs L80-89)",
        "[MEDIUM] rebond vertical — état hors-domaine possible (repro: isValidState(ns) === false)",
        "[LOW] interpolation — imprécision non exploitée (repro: aucun contre-exemple construit)",
        "[LOW] zone morte — serveVx inerte (repro: mutation littérale L114-115)",
        "[LOW] preuve tautologique — core.exit toujours vrai (repro: process.exit(0) inconditionnel)",
    )
    v_avec_findings = _agg(redteam_blocked=False, redteam_findings=findings_reels)
    v_sans_findings = _agg(redteam_blocked=False, redteam_findings=())

    assert v_avec_findings.redteam_advisory == findings_reels  # les findings SONT audibles
    assert v_avec_findings.software_verdict == v_sans_findings.software_verdict == "OK"
    assert v_avec_findings.decision == v_sans_findings.decision == "HUMANGATE_READY"
    assert v_avec_findings.humangate_flags == v_sans_findings.humangate_flags == ()

    assert is_clean_pass(asdict(v_sans_findings)) is True
    assert is_clean_pass(asdict(v_avec_findings)) is True  # <- le prédicat protégé


# --- extra_advisory (Tier 2.5 étape 3, panel Prisme) : contrôle qualité, jamais juge --

def _agg_with_extra(extra_advisory=(), code="OK", archi="OK", wiremap="OK", run_id="R", key=KEY):
    return build_aggregate_verdict(
        "demo", run_id,
        _code_receipt(code, run_id, key),
        _rcpt("archi", archi, run_id, key=key),
        _rcpt("wiremap", wiremap, run_id, key=key),
        "qwen2.5-14b-instruct", redteam_ran=True, extra_advisory=extra_advisory,
        nonce="n1", key_file=key,
    )


def test_extra_advisory_ne_change_jamais_software_verdict():
    """Le panel Prisme (s1) DÉTECTE, il ne DÉCIDE jamais — même architecture que le
    red-team. Un finding Prisme sur des oracles verts reste software_verdict OK."""
    v = _agg_with_extra(extra_advisory=("Prisme (s1, contrôle qualité — jamais un juge): "
                                        "section manquante: ressent",))
    assert v.software_verdict == "OK"


def test_extra_advisory_pousse_objection_et_est_visible_dans_humangate_flags():
    v = _agg_with_extra(extra_advisory=("Prisme (s1, contrôle qualité — jamais un juge): "
                                        "section manquante: ressent",))
    assert v.decision == "HUMANGATE_READY_WITH_OBJECTION"
    assert any("Prisme" in f for f in v.humangate_flags)


def test_extra_advisory_vide_ne_pousse_pas_objection():
    v = _agg_with_extra(extra_advisory=())
    assert v.decision == "HUMANGATE_READY"


def test_extra_advisory_et_redteam_blocked_cumulent_sans_se_marcher_dessus():
    """Deux contrôles qualité indépendants (Prisme + red-team) peuvent chacun
    signaler — les deux flags survivent, aucun n'écrase l'autre."""
    v = build_aggregate_verdict(
        "demo", "R",
        _code_receipt("OK", "R", KEY), _rcpt("archi", "OK", "R", key=KEY),
        _rcpt("wiremap", "OK", "R", key=KEY), "qwen2.5-14b-instruct",
        redteam_ran=True, redteam_blocked=True, redteam_findings=("câblage incohérent",),
        extra_advisory=("Prisme (s1, contrôle qualité — jamais un juge): section manquante",),
        nonce="n1", key_file=KEY,
    )
    assert v.software_verdict == "OK"
    assert v.decision == "HUMANGATE_READY_WITH_OBJECTION"
    assert any("red-team" in f.lower() for f in v.humangate_flags)
    assert any("Prisme" in f for f in v.humangate_flags)


# --- honnêteté du reviewer (A2 -> A3), désormais STRUCTURÉE -------------------

def test_real_reviewer_is_recorded():
    v = _agg(reviewer="qwen2.5-14b-instruct", redteam_ran=True)
    assert v.redteam_reviewer == "qwen2.5-14b-instruct"
    assert v.redteam_ran is True


def test_redteam_not_run_raises_degraded_flag():
    v = _agg(reviewer="claude-blind (fallback)", redteam_ran=False)
    assert v.redteam_ran is False
    assert any("dégradé" in f.lower() or "fallback" in f.lower() for f in v.humangate_flags)


# --- signature + anti-rejeu --------------------------------------------------

def test_signature_roundtrips():
    v = _agg()
    sig = sign_aggregate(v, key_file=KEY)
    assert verify_aggregate(v, sig, key_file=KEY) is True


def test_tampered_software_verdict_fails_verification():
    v = _agg()
    sig = sign_aggregate(v, key_file=KEY)
    forged = _agg(code="FAIL")            # software devient FAIL
    assert verify_aggregate(forged, sig, key_file=KEY) is False


def test_reviewer_is_signed_in_not_forgeable():
    """Un fallback (redteam_ran=False) ne peut pas se faire signer comme Qwen actif."""
    honest = _agg(reviewer="claude-blind (fallback)", redteam_ran=False)
    sig = sign_aggregate(honest, key_file=KEY)
    lie = _agg(reviewer="qwen2.5-14b-instruct", redteam_ran=True)
    assert verify_aggregate(lie, sig, key_file=KEY) is False


def test_verify_aggregate_without_key_refuses_and_does_not_generate():
    absent = Path(tempfile.mkdtemp()) / "absent_key"
    v = _agg()
    assert verify_aggregate(v, "deadbeef", key_file=absent) is False
    assert not absent.exists()


def test_nonce_makes_two_verdicts_non_replayable():
    v1 = _agg(nonce="n1")
    v2 = _agg(nonce="n2")
    s1 = signed_aggregate_record(v1, key_file=KEY)["hmac"]
    s2 = signed_aggregate_record(v2, key_file=KEY)["hmac"]
    assert s1 != s2               # deux runs ne partagent plus la même signature
