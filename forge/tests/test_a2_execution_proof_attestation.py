"""A2 (Paquet A, décision 2 — ratifiée Pierre 2026-08-28) — le VERDICT signé dit
explicitement de quel RÉGIME DE PREUVE vient l'exécution de ses spawns.

INVARIANT RATIFIÉ : « une preuve doit provenir du mécanisme qui a réalisé l'action,
sinon elle est explicitement AUTO_ATTESTED ».

Défaut mesuré : sur le chemin headless (`run_real._claude_call_raw` = sous-processus,
hors hook PreToolUse), `spawn_authorized`/`spawn_executed` sont écrits par le driver
LUI-MÊME (`ForgeDriver._record_spawn_executed`, dont la docstring l'assume). R2-OBS P4
l'a rendu lisible ligne à ligne (`spawn_links.jsonl`, `attestation: "self"`) — mais
l'AGRÉGAT SIGNÉ, le seul artefact que HumanGate lit, n'en disait rien : il se
présentait exactement comme si un tiers avait observé les spawns.

Ce lot pose le marquage DANS LE CORPS SIGNÉ (donc couvert par le HMAC) :
`execution_proof_attestation` + sa note. Jamais silencieux, jamais bloquant
(software_verdict/decision/humangate_flags INCHANGÉS), rétro-compatible (un verdict
historique sans le champ reste vérifiable tel quel).
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from forge.driver import ForgeDriver
from forge.verdict import (
    ATTESTATION_SELF,
    EXECUTION_PROOF_SELF_NOTE,
    _sign_mapping,
    _verify_mapping,
    build_aggregate_verdict,
    make_signed_receipt,
    signed_aggregate_record,
)
from forge.verify_run import verify_run

RUN_ID = "a2-1"


# --- harnais ------------------------------------------------------------------

def _receipts(tmp_path, key):
    """Trois reçus OK signés, avec une évidence réelle pour le reçu `code`."""
    ev = tmp_path / "oracle.log"
    ev.write_text("tests ok\n", encoding="utf-8")
    code = make_signed_receipt("code", RUN_ID, "OK", {"returncode": 0},
                               evidence_path=str(ev), key_file=key)
    archi = make_signed_receipt("archi", RUN_ID, "OK", {"passed": True}, key_file=key)
    wire = make_signed_receipt("wiremap", RUN_ID, "OK", {"passed": True}, key_file=key)
    return code, archi, wire


def _agg(tmp_path, key, **kw):
    code, archi, wire = _receipts(tmp_path, key)
    return build_aggregate_verdict(
        "proj", RUN_ID, code, archi, wire, "claude-blind",
        redteam_ran=True, key_file=key, **kw)


# --- (a) le champ existe, il est SIGNÉ, et il ne juge rien --------------------

def test_le_regime_dexecution_est_dans_le_corps_signe(tmp_path):
    key = tmp_path / "k.key"
    agg = _agg(tmp_path, key, execution_proof_attestation=ATTESTATION_SELF)

    assert agg.execution_proof_attestation == ATTESTATION_SELF
    assert "auto-attest" in agg.execution_proof_note.lower()

    record = signed_aggregate_record(agg, key_file=key)
    assert record["execution_proof_attestation"] == ATTESTATION_SELF
    body = {k: v for k, v in record.items() if k != "hmac"}
    assert _verify_mapping(body, record["hmac"], key) is True

    # ALTÉRATION du champ => signature invalide (il est bien COUVERT par le HMAC).
    falsifie = dict(body, execution_proof_attestation="observed")
    assert _verify_mapping(falsifie, record["hmac"], key) is False


def test_le_marquage_ne_change_ni_le_verdict_ni_la_decision(tmp_path):
    """Jamais bloquant : marquer le régime de preuve ne dégrade AUCUN jugement."""
    key = tmp_path / "k.key"
    sans = _agg(tmp_path, key)
    avec = _agg(tmp_path, key, execution_proof_attestation=ATTESTATION_SELF)
    assert sans.software_verdict == avec.software_verdict == "OK"
    assert sans.decision == avec.decision
    assert sans.humangate_flags == avec.humangate_flags


def test_absence_de_marquage_reste_le_defaut_honnete(tmp_path):
    """Un producteur qui ne déclare rien ne se voit PAS attribuer un régime."""
    key = tmp_path / "k.key"
    agg = _agg(tmp_path, key)
    assert agg.execution_proof_attestation is None
    assert agg.execution_proof_note == ""


def test_valeur_de_regime_inconnue_refusee(tmp_path):
    """Vocabulaire FERMÉ (même patron que `scope`) : pas de régime inventé."""
    key = tmp_path / "k.key"
    with pytest.raises(ValueError):
        _agg(tmp_path, key, execution_proof_attestation="peer-observed")


# --- (b) rétro-compatibilité : un verdict historique n'a pas ce champ ---------

def test_ancien_verdict_sans_le_champ_reste_verifiable(tmp_path):
    """`verify_run` re-signe le corps STOCKÉ : un verdict antérieur à ce lot
    (aucune clé `execution_proof_*`) garde un HMAC valide — le champ absent est un
    ancien verdict, jamais une erreur."""
    key = tmp_path / "k.key"
    body = {
        "project": "proj", "run_id": RUN_ID, "software_verdict": "OK",
        "evidence_verdict": "MECHANICAL_VALIDATION_ONLY",
        "claim_verdict": "NO_CLAIM_ALLOWED", "decision": "HUMANGATE_READY",
        "oracles": {}, "redteam_reviewer": "claude-blind", "redteam_ran": True,
        "provenance_ok": True, "git_head": "", "nonce": "n", "ts": 0.0,
        "redteam_advisory": [], "humangate_flags": [], "scope": "FULL",
        "is_game": False,
    }
    path = tmp_path / "verdict.json"
    path.write_text(json.dumps({**body, "hmac": _sign_mapping(body, key)},
                               ensure_ascii=False, sort_keys=True), encoding="utf-8")

    res = verify_run(path, key_file=key)
    assert res["hmac_ok"] is True


# --- (c) le producteur RÉEL : le driver headless déclare son régime -----------

class _Stub:
    def __init__(self, run_dir):
        self.run_dir = run_dir

    def __call__(self, payload, decision, context):
        return {"ok": True, "output": f"artefact {payload.etape}"}


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


def _oracle_config(tmp_path, project="proj"):
    import sys
    cfg = tmp_path / "oracles_test.json"
    cfg.write_text(json.dumps({project: {
        "cwd": str(tmp_path),
        "command": [sys.executable, "-c", "import sys; sys.exit(0)"],
    }}), encoding="utf-8")
    return cfg


def test_le_driver_declare_self_dans_le_verdict_et_le_rapport(tmp_path, offline):
    """Le driver EST le chemin B (headless) : il écrit lui-même ses
    `spawn_authorized`/`spawn_executed`. Son verdict signé le DIT, et le rapport
    final le remonte à Pierre."""
    run_dir = tmp_path / "run"
    report = ForgeDriver(
        "proj", "proj-a2", profile="micro", executor=_Stub(run_dir),
        run_dir=run_dir, oracle_config=_oracle_config(tmp_path),
        key_file=tmp_path / "k.key", audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
    ).run()

    assert report["software_verdict"] == "OK"
    record = json.loads((run_dir / "verdict.json").read_text(encoding="utf-8"))
    assert record["execution_proof_attestation"] == ATTESTATION_SELF
    assert record["execution_proof_note"] == EXECUTION_PROOF_SELF_NOTE
    # Le HMAC couvre bien ce verdict-là (re-vérification par verify_run).
    assert verify_run(run_dir / "verdict.json", key_file=tmp_path / "k.key")["hmac_ok"] is True
    # Visible dans le rapport final — jamais un fait enterré dans un fichier.
    assert report["execution_proof_attestation"] == ATTESTATION_SELF
    assert "auto-attest" in report["execution_proof_note"].lower()
