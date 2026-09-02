"""Oracle des reçus d'oracle signés (provenance, étape 2).

Un reçu prouve qu'un oracle a réellement tourné sur un run donné. La signature
HMAC + le run_id sont la chaîne de provenance que l'agrégat vérifie.
"""
import tempfile
from pathlib import Path

from forge.verdict import (
    make_signed_receipt,
    sha256_file,
    sign_receipt,
    status_from_passed,
    verify_receipt,
)

KEY = Path(tempfile.mkdtemp()) / "k"


def test_receipt_roundtrips():
    sr = make_signed_receipt("archi", "run1", "OK", {"passed": True}, key_file=KEY)
    assert verify_receipt(sr.receipt, sr.signature, key_file=KEY) is True


def test_tampered_receipt_fails_verification():
    sr = make_signed_receipt("code", "run1", "OK", {"returncode": 0}, key_file=KEY)
    # falsifie le statut après signature
    from dataclasses import replace
    forged = replace(sr.receipt, status="FAIL")
    assert verify_receipt(forged, sr.signature, key_file=KEY) is False


def test_receipt_signed_with_other_key_fails():
    other = Path(tempfile.mkdtemp()) / "other"
    sr = make_signed_receipt("wiremap", "run1", "OK", {}, key_file=other)
    assert verify_receipt(sr.receipt, sr.signature, key_file=KEY) is False


def test_verify_receipt_without_key_refuses():
    absent = Path(tempfile.mkdtemp()) / "absent"
    sr = make_signed_receipt("archi", "run1", "OK", {}, key_file=KEY)
    assert verify_receipt(sr.receipt, sr.signature, key_file=absent) is False
    assert not absent.exists()


def test_invalid_status_rejected():
    import pytest
    with pytest.raises(ValueError):
        make_signed_receipt("code", "run1", "PROBABLEMENT_OK", {}, key_file=KEY)


def test_status_from_passed():
    assert status_from_passed(True) == "OK"
    assert status_from_passed(False) == "FAIL"


def test_receipt_with_evidence_path_roundtrips(tmp_path):
    ev = tmp_path / "oracle.log"
    ev.write_text("sortie oracle", encoding="utf-8")
    sr = make_signed_receipt("code", "r1", "OK", {"returncode": 0},
                             evidence_path=str(ev), key_file=KEY)
    assert sr.receipt.evidence_path == str(ev)
    assert sr.receipt.evidence_sha256 == sha256_file(ev)   # calculé si non fourni
    assert verify_receipt(sr.receipt, sr.signature, key_file=KEY) is True


def test_sha256_file_seals_content(tmp_path):
    p = tmp_path / "ev.log"
    p.write_text("preuve", encoding="utf-8")
    h1 = sha256_file(p)
    p.write_text("preuve altérée", encoding="utf-8")
    assert sha256_file(p) != h1          # un changement de contenu change le hash
    assert sha256_file(tmp_path / "absent.log") == ""   # illisible -> '' (pas de crash)
