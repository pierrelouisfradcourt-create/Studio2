"""Maillon 5 (trace, exploitable) — forge.tool_observability
.append_tool_observability_record / read_tool_observability_records /
verify_tool_observability_record.

Même mécanisme de signature que forge.verdict/forge.context_manifest (HMAC sur
mapping trié), dans SON PROPRE fichier — jamais context_manifest.py, jamais
audit.py.
"""
from __future__ import annotations

import json
import tempfile
from pathlib import Path

from forge import tool_observability as obs
from forge.contract import load_contract

KEY = Path(tempfile.mkdtemp()) / "k"


def test_append_signe_et_verifiable(tmp_path):
    contract = load_contract("s4-archi")
    rec = obs.append_tool_observability_record(
        "s4-archi", "test-run", contract, run_dir=tmp_path, key_file=KEY,
    )
    assert rec["schema"] == obs.SCHEMA
    assert rec["claim_verdict"] == "NO_CLAIM_ALLOWED"
    assert obs.verify_tool_observability_record(rec, key_file=KEY) is True


def test_contenu_combine_maillon1_et_maillon2(tmp_path):
    contract = load_contract("s4-archi")
    rec = obs.append_tool_observability_record(
        "s4-archi", "test-run", contract, run_dir=tmp_path, key_file=KEY,
    )
    declared = {f["field"]: f for f in rec["declared"]}
    assert declared["plugin"]["kind"] == obs.DECLARATION_KIND_PROSE  # maillon 1
    assert rec["loaded"]["status"] in (
        obs.LOADING_STATUS_LOADED, obs.LOADING_STATUS_EMPTY, obs.LOADING_STATUS_NOT_MEASURED,
    )  # maillon 2, présent et typé


def test_ecrit_sur_disque_au_bon_chemin(tmp_path):
    contract = load_contract("s9-build")
    obs.append_tool_observability_record(
        "s9-build", "run-x", contract, run_dir=tmp_path, key_file=KEY,
    )
    path = obs.tool_observability_manifest_path(tmp_path, "s9-build")
    assert path.exists()
    line = path.read_text(encoding="utf-8").strip()
    on_disk = json.loads(line)
    assert on_disk["etape"] == "s9-build"


def test_lecteur_relit_ce_que_append_a_ecrit(tmp_path):
    """LE lecteur du maillon 5 : sans lui, le fichier serait un connecteur
    dormant de plus (leçon explicite de la mission)."""
    contract = load_contract("s9-build")
    obs.append_tool_observability_record(
        "s9-build", "run-a", contract, run_dir=tmp_path, key_file=KEY,
    )
    obs.append_tool_observability_record(
        "s9-build", "run-b", contract, run_dir=tmp_path, key_file=KEY,
    )
    recs = obs.read_tool_observability_records(tmp_path, "s9-build")
    assert len(recs) == 2
    assert {r["run_id"] for r in recs} == {"run-a", "run-b"}
    assert all(obs.verify_tool_observability_record(r, key_file=KEY) for r in recs)


def test_lecteur_sur_fichier_absent_rend_tuple_vide_jamais_une_exception(tmp_path):
    assert obs.read_tool_observability_records(tmp_path, "etape-jamais-dispatchee") == ()


def test_manipulation_est_detectee_par_le_hmac(tmp_path):
    """Négatif du maillon 5 : une ligne modifiée après coup (falsification) ne
    doit PLUS vérifier — sans quoi la trace ne serait pas une preuve."""
    contract = load_contract("s9-build")
    obs.append_tool_observability_record(
        "s9-build", "run-tamper", contract, run_dir=tmp_path, key_file=KEY,
    )
    path = obs.tool_observability_manifest_path(tmp_path, "s9-build")
    rec = json.loads(path.read_text(encoding="utf-8").strip())
    rec["run_id"] = "run-tampered"  # falsification après signature
    assert obs.verify_tool_observability_record(rec, key_file=KEY) is False


def test_verify_sans_hmac_est_faux():
    assert obs.verify_tool_observability_record({"schema": obs.SCHEMA}, key_file=KEY) is False


def test_verify_sur_non_dict_est_faux():
    assert obs.verify_tool_observability_record(None, key_file=KEY) is False  # type: ignore[arg-type]


def test_deux_etapes_distinctes_ont_des_fichiers_distincts(tmp_path):
    c4 = load_contract("s4-archi")
    c9 = load_contract("s9-build")
    obs.append_tool_observability_record("s4-archi", "run-a", c4, run_dir=tmp_path, key_file=KEY)
    obs.append_tool_observability_record("s9-build", "run-a", c9, run_dir=tmp_path, key_file=KEY)
    assert obs.tool_observability_manifest_path(tmp_path, "s4-archi") != (
        obs.tool_observability_manifest_path(tmp_path, "s9-build")
    )
    assert len(obs.read_tool_observability_records(tmp_path, "s4-archi")) == 1
    assert len(obs.read_tool_observability_records(tmp_path, "s9-build")) == 1
