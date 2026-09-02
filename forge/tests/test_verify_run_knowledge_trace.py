"""Oracle verify_run <-> knowledge_trace (R3, FORGE_V2_CONSOLIDATION.md §4-A, ferme AM1).

Avant R3, le lineage de lecture (knowledge_trace.json : quels items pré-mortem/
knowledge_base/mandatory_read/packet ont été servis à un run) n'était jamais recoupé
par verify_run — un run pouvait déclarer avoir consommé un item sans que quiconque
vérifie que la référence apparaît RÉELLEMENT dans un artefact du run (auto-attesté,
AM1). Ces tests prouvent : trace ABSENTE -> avertissement non bloquant (OK global) ;
trace VALIDE (ref trouvée dans un artefact) -> OK ; trace THÉÂTRALE (ref introuvable)
-> constat FAUX rapporté, mais NON BLOQUANT.

RÉGIME ADVISORY — décision N-2, ratifiée Pierre 2026-09-02. Le contrôle mesure et
rapporte ; il ne décide plus. Ces tests figent donc les DEUX moitiés de la décision :
(1) le constat reste VRAI et visible — `knowledge_trace_ok is False` sur théâtre et sur
corruption, jamais un faux vert ; (2) il n'a plus d'autorité — `overall` reste True et
`knowledge_trace_problems` reste vide (la liste que le driver agrège pour bloquer).
Un test qui re-verrait `overall is False` ici signalerait un ré-armement non ratifié.
NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
import shutil
import tempfile
from pathlib import Path

import pytest

from forge.verdict import build_aggregate_verdict, make_signed_receipt, signed_aggregate_record
from forge.verify_run import verify_run

KEY = Path(tempfile.mkdtemp()) / "k"
_NODE_ABSENT = shutil.which("node") is None


def _write_verdict(run_dir: Path, key: Path = KEY) -> Path:
    """Verdict NON-jeu (aucun marqueur e2e/mutation/solvability dans le detail du
    reçu code) : isole le check knowledge_trace des autres gardes (mutation_ok
    trivialement True, même helper que test_verify_run.py)."""
    ev = run_dir / "oracle_demo.log"
    ev.write_text("$ pytest\nok\n", encoding="utf-8")
    rid = "demo-run"
    code = make_signed_receipt("code", rid, "OK", {"returncode": 0},
                               evidence_path=str(ev), key_file=key)
    archi = make_signed_receipt("archi", rid, "SKIPPED", {}, key_file=key)
    wire = make_signed_receipt("wiremap", rid, "SKIPPED", {}, key_file=key)
    agg = build_aggregate_verdict("demo", rid, code, archi, wire, "qwen2.5-14b-instruct",
                                  redteam_ran=True, nonce="n1", key_file=key)
    rec = signed_aggregate_record(agg, key_file=key)
    vpath = run_dir / "verdict.json"
    vpath.write_text(json.dumps(rec, ensure_ascii=False, indent=2), encoding="utf-8")
    return vpath


def _write_trace(run_dir: Path, items: list[dict]) -> None:
    trace = {
        "run_id": "demo-run", "created": "2026-07-20T00:00:00.000Z",
        "schema_version": 1, "items": items,
    }
    (run_dir / "knowledge_trace.json").write_text(
        json.dumps(trace, ensure_ascii=False, indent=2), encoding="utf-8")


# --- trace absente : avertissement non bloquant ------------------------------------

def test_trace_absente_avertissement_non_bloquant(tmp_path):
    vpath = _write_verdict(tmp_path)
    res = verify_run(vpath, key_file=KEY)
    assert res["knowledge_trace_ok"] is True
    assert res["overall"] is True
    assert res["knowledge_trace_problems"] == []
    assert any("absent" in w for w in res["knowledge_trace_warnings"])


# --- trace valide : ref réellement consommée par un artefact du run ---------------

@pytest.mark.skipif(_NODE_ABSENT, reason="node indisponible")
def test_trace_valide_ref_trouvee_ok(tmp_path):
    vpath = _write_verdict(tmp_path)
    artifacts = tmp_path / "artifacts"
    artifacts.mkdir()
    (artifacts / "s3-decompo.txt").write_text(
        "Décision citée telle quelle : DECISION-42 appliquée.", encoding="utf-8")
    _write_trace(tmp_path, [{
        "source": "premortem", "ref": "DECISION-42", "provenance": "VERIFIED",
        "valid_as_of": "2026-07-20T00:00:00Z", "reason": "test R3",
    }])
    res = verify_run(vpath, key_file=KEY)
    assert res["knowledge_trace_ok"] is True
    assert res["overall"] is True
    assert res["knowledge_trace_problems"] == []


# --- trace théâtrale : ref introuvable -> constat FAUX, ADVISORY (N-2) -------------

@pytest.mark.skipif(_NODE_ABSENT, reason="node indisponible")
def test_trace_theatrale_ref_introuvable_rapportee_sans_bloquer(tmp_path):
    vpath = _write_verdict(tmp_path)
    _write_trace(tmp_path, [{
        "source": "knowledge_base", "ref": "REF-INTROUVABLE-XYZ-999", "provenance": "ADVISORY",
        "valid_as_of": "2026-07-20T00:00:00Z", "reason": "test R3 théâtre",
    }])
    res = verify_run(vpath, key_file=KEY)
    # le constat reste VRAI : le théâtre est détecté et nommé
    assert res["knowledge_trace_ok"] is False
    assert any("échoué" in w for w in res["knowledge_trace_warnings"])
    # ... et il n'a plus d'autorité (N-2) : ni gate driver, ni code de sortie CLI
    assert res["knowledge_trace_problems"] == []
    assert res["overall"] is True


# --- trace corrompue -> constat FAUX (pas un vert par défaut), ADVISORY ------------

@pytest.mark.skipif(_NODE_ABSENT, reason="node indisponible")
def test_trace_corrompue_rapportee_sans_bloquer(tmp_path):
    vpath = _write_verdict(tmp_path)
    (tmp_path / "knowledge_trace.json").write_text("{ceci n'est pas du JSON", encoding="utf-8")
    res = verify_run(vpath, key_file=KEY)
    assert res["knowledge_trace_ok"] is False   # jamais un vert par défaut
    assert res["knowledge_trace_problems"] == []
    assert res["overall"] is True


# --- node indisponible : avertissement honnête, jamais un faux vert ---------------

def test_node_indisponible_avertissement_honnete(tmp_path, monkeypatch):
    vpath = _write_verdict(tmp_path)
    _write_trace(tmp_path, [{
        "source": "packet", "ref": "peu importe", "provenance": "DERIVED",
        "valid_as_of": "2026-07-20T00:00:00Z", "reason": "test",
    }])
    monkeypatch.setattr("forge.verify_run.shutil.which", lambda *_a, **_k: None)

    def _raise(*_a, **_k):
        raise FileNotFoundError("node introuvable (simulé)")
    monkeypatch.setattr("forge.verify_run.subprocess.run", _raise)

    res = verify_run(vpath, key_file=KEY)
    assert res["knowledge_trace_problems"] == []  # jamais un échec dur sur outil absent
    assert any("indisponible" in w for w in res["knowledge_trace_warnings"])
    assert res["knowledge_trace_ok"] is True  # avertissement seul, pas un blocage
    assert res["overall"] is True
