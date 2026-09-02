from pathlib import Path

from forge.verdict import build_verdict, sign_verdict, verify_verdict


def test_green_verdict_is_ok_but_never_claims(tmp_path):
    v = build_verdict("demo", passed=True, returncode=0, evidence_path=Path("ev.log"))
    assert v.software_verdict == "OK"
    assert v.claim_verdict == "NO_CLAIM_ALLOWED"
    assert v.evidence_verdict == "MECHANICAL_VALIDATION_ONLY"


def test_red_verdict_is_fail(tmp_path):
    v = build_verdict("demo", passed=False, returncode=1, evidence_path=Path("ev.log"))
    assert v.software_verdict == "FAIL"
    assert v.claim_verdict == "NO_CLAIM_ALLOWED"


def test_signature_roundtrips(tmp_path):
    key = tmp_path / "k"
    v = build_verdict("demo", passed=True, returncode=0, evidence_path=Path("ev.log"))
    sig = sign_verdict(v, key_file=key)
    assert verify_verdict(v, sig, key_file=key) is True


def test_tampered_verdict_fails_verification(tmp_path):
    key = tmp_path / "k"
    v = build_verdict("demo", passed=True, returncode=0, evidence_path=Path("ev.log"))
    sig = sign_verdict(v, key_file=key)
    forged = build_verdict("demo", passed=False, returncode=1, evidence_path=Path("ev.log"))
    assert verify_verdict(forged, sig, key_file=key) is False


def test_verify_without_key_refuses_and_does_not_generate(tmp_path):
    """Clé absente à la vérif => refus (False), et AUCUNE clé n'est créée.

    Sinon : supprimer .forge_key puis re-signer des verdicts forgés les rendrait
    tous valides sous la nouvelle clé.
    """
    key = tmp_path / "absent_key"
    v = build_verdict("demo", passed=True, returncode=0, evidence_path=Path("ev.log"))
    assert verify_verdict(v, "deadbeef", key_file=key) is False
    assert not key.exists()
