"""Oracle de `forge.verify_run` — la vérification MÉCANIQUE d'un verdict.json.

C'est ce que `/gate` doit appeler au lieu de demander à un agent de *dire* « HMAC OK ».
Re-signe le corps + re-lit l'évidence + compare git_head.
"""
import json
import tempfile
from pathlib import Path

from forge.verdict import build_aggregate_verdict, make_signed_receipt, signed_aggregate_record
from forge.verify_run import verify_run

KEY = Path(tempfile.mkdtemp()) / "k"


def _write_verdict(tmp_path, evidence="$ pytest\nok\n", key=KEY):
    ev = tmp_path / "oracle_demo.log"
    ev.write_text(evidence, encoding="utf-8")
    rid = "demo-run"
    code = make_signed_receipt("code", rid, "OK", {"returncode": 0},
                               evidence_path=str(ev), key_file=key)
    archi = make_signed_receipt("archi", rid, "SKIPPED", {}, key_file=key)
    wire = make_signed_receipt("wiremap", rid, "SKIPPED", {}, key_file=key)
    agg = build_aggregate_verdict("demo", rid, code, archi, wire, "qwen2.5-14b-instruct",
                                  redteam_ran=True, nonce="n1", key_file=key)
    rec = signed_aggregate_record(agg, key_file=key)
    vpath = tmp_path / "verdict.json"
    vpath.write_text(json.dumps(rec, ensure_ascii=False, indent=2), encoding="utf-8")
    return vpath, ev


def test_authentic_verdict_verifies(tmp_path):
    vpath, _ = _write_verdict(tmp_path)
    res = verify_run(vpath, key_file=KEY)
    assert res["overall"] is True
    assert res["hmac_ok"] is True
    assert res["evidence_ok"] is True


def test_altered_evidence_is_caught(tmp_path):
    vpath, ev = _write_verdict(tmp_path)
    ev.write_text("log truqué après signature", encoding="utf-8")   # altère l'évidence
    res = verify_run(vpath, key_file=KEY)
    assert res["evidence_ok"] is False
    assert res["overall"] is False
    assert res["evidence_problems"]


def test_tampered_body_breaks_hmac(tmp_path):
    vpath, _ = _write_verdict(tmp_path)
    data = json.loads(vpath.read_text(encoding="utf-8"))
    data["decision"] = "MERGE_NOW"                    # falsification du corps
    vpath.write_text(json.dumps(data), encoding="utf-8")
    res = verify_run(vpath, key_file=KEY)
    assert res["hmac_ok"] is False
    assert res["overall"] is False


def test_wrong_key_rejects(tmp_path):
    vpath, _ = _write_verdict(tmp_path)
    other = Path(tempfile.mkdtemp()) / "other"
    res = verify_run(vpath, key_file=other)
    assert res["overall"] is False


def test_missing_verdict_file_is_rejected():
    res = verify_run(Path(tempfile.mkdtemp()) / "absent.json", key_file=KEY)
    assert res["overall"] is False


def test_missing_verdict_is_honest_not_accusatory():
    """Absent != falsifié : le dict a toutes les clés que main() lit (pas de
    KeyError) et le marqueur `unreadable` distingue « rien à vérifier » d'une
    falsification détectée sur un contenu réellement signé."""
    res = verify_run(Path(tempfile.mkdtemp()) / "absent.json", key_file=KEY)
    assert res.get("unreadable") is True
    for key in ("mutation_ok", "knowledge_trace_ok", "evidence_ok", "hmac_ok",
                "git_ok", "evidence_problems", "mutation_problems",
                "knowledge_trace_problems", "knowledge_trace_warnings",
                "software_verdict", "decision"):
        assert key in res, f"clé manquante: {key} (main() y accèderait sans garde)"


def test_missing_verdict_cli_exit_code_is_distinct_from_authentic_and_falsified():
    """Le CLI ne doit ni crasher (ancien KeyError) ni prétendre AUTHENTIQUE (0)
    ni accuser de falsification (2) sur un fichier absent : code dédié."""
    import io
    import sys

    from forge import verify_run as vr

    out = io.StringIO()
    old_stdout = sys.stdout
    sys.stdout = out
    try:
        code = vr.main([str(Path(tempfile.mkdtemp()) / "absent.json")])
    finally:
        sys.stdout = old_stdout
    assert code not in (0, 2)
    texte = out.getvalue()
    assert "FALSIFIÉ" not in texte
    assert "ALTÉRÉE" not in texte
