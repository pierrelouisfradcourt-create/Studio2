# P3 2026-08-15 — fermeture du motif « mesuré → perdu » (4e/5e occurrences).
#
# Défaut mesuré (code review 2026-08-15) : `tools_used` (Expérience C) et
# `findings_note` étaient produits par run_real puis perdus — absents du tuple
# TELEMETRY_MEASURED_FIELDS ET du littéral `detail` du driver (le même motif que
# markdown_check/M3'a et yaml_check/M4'). Chaîne exigée :
# PRODUCER -> PERSISTENCE -> CONSUMER -> EVIDENCE.
#   tools_used   : persisté (state.json + télémétrie) ; consommateur décisionnel
#                  ABSENT à ce jour -> PASSIVE DÉCLARÉ (capteur M5, gate ouverte).
#   findings_note: consommé par _redteam_facts -> humangate_flags du verdict signé.
# Ce test prouve la persistance sur un run() réel (exécuteur stub) et fige la
# consommation de findings_note ; il prouve AUSSI (P2) qu'un profil sans s12
# produit verdict.partial.json sur le chemin run() de bout en bout.
from __future__ import annotations

import json
import sys

import pytest

from forge.driver import ForgeDriver
from forge import studio_link


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


def _oracle_config(tmp_path, project="proj", exit_code=0):
    script = f"import sys; sys.exit({exit_code})"
    cfg = tmp_path / "oracles.json"
    cfg.write_text(
        json.dumps({project: {"cwd": str(tmp_path),
                              "command": [sys.executable, "-c", script]}}),
        encoding="utf-8")
    return cfg


def _kwargs(tmp_path, run_dir):
    return dict(
        run_dir=run_dir,
        oracle_config=_oracle_config(tmp_path),
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
    )


class MeasuringStub:
    """Exécuteur factice qui rend les champs MESURÉS (Expérience C + note)."""

    def __call__(self, payload, decision, context):
        return {
            "ok": True,
            "output": f"artefact {payload.etape}",
            "tools_used": {"Read": 3, "Bash": 1},
            "findings_note": "extraction partielle (bloc FINDINGS malformé)",
            "findings": ["F1: preuve du cœur absente"],
        }


def test_tools_used_et_findings_note_persistes_dans_state(tmp_path, offline):
    run_dir = tmp_path / "run"
    report = ForgeDriver("proj", "proj-1", profile="review",
                         executor=MeasuringStub(), **_kwargs(tmp_path, run_dir)).run()
    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    detail = state["steps"]["s6-redteam-plan"]["detail"]
    # PERSISTENCE : les deux mesures atteignent state.json.
    assert detail["tools_used"] == {"Read": 3, "Bash": 1}
    assert detail["findings_note"] == "extraction partielle (bloc FINDINGS malformé)"
    # P2, chemin run() réel : le profil `review` (sans s12) sort avec un verdict
    # PARTIEL signé, jamais le BLOCKED « sans verdict signé exploitable ».
    assert report["status"] == "DONE"
    assert report.get("scope") == "PARTIAL"
    partial = json.loads((run_dir / "verdict.partial.json").read_text(encoding="utf-8"))
    assert partial["scope"] == "PARTIAL"
    assert partial["hmac"]
    # CONSUMER (findings_note) : la note qualifie les findings advisory du
    # verdict signé — visible HumanGate, jamais tue.
    advisory = " | ".join(partial.get("redteam_advisory", ()))
    assert "note d'extraction" in advisory


def test_tools_used_dans_la_ligne_telemetrie(tmp_path):
    # Le canal G1-G2 retient désormais tools_used ({} = zéro invocation mesuré).
    assert "tools_used" in studio_link.TELEMETRY_MEASURED_FIELDS
    studio_link.stage_telemetry_extra("r-1", "s6-redteam-plan",
                                      {"tools_used": {"Read": 2}})
    tpath = tmp_path / "telemetry.jsonl"
    studio_link.record_telemetry("r-1", "s6-redteam-plan", "modele-x", 10, 1.0,
                                 telemetry_path=tpath)
    line = json.loads(tpath.read_text(encoding="utf-8").strip().splitlines()[-1])
    assert line["tools_used"] == {"Read": 2}


def test_zero_invocation_reste_une_mesure(tmp_path):
    # {} (mesuré : aucun outil) doit survivre — seul None signifie « non mesuré ».
    studio_link.stage_telemetry_extra("r-2", "s6-redteam-plan", {"tools_used": {}})
    tpath = tmp_path / "telemetry.jsonl"
    studio_link.record_telemetry("r-2", "s6-redteam-plan", "modele-x", 10, 1.0,
                                 telemetry_path=tpath)
    line = json.loads(tpath.read_text(encoding="utf-8").strip().splitlines()[-1])
    assert line["tools_used"] == {}
