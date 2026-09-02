# P4 2026-08-15 — Activation Lineage : le DÉCLENCHEUR mécanique est transmis.
#
# Défaut mesuré (code review 2026-08-15, runs charte_probe2/gmws_probe) : la
# lignée Activation était un canal typé mais VIDE — {"status": "NOT_TRANSMITTED",
# "action": ...} sur tous les dispatches d'enchaînement mécanique, alors que le
# driver CONNAÎT la cause d'ordonnancement (profil, position, prédécesseur
# terminé). Correctif ADDITIF dans `_activation_reason` : `status` reste
# NOT_TRANSMITTED (aucun PROBLÈME mesuré — point ratifié 2026-08-06, figé par
# test_dispatch_p5_reason_field, intouché), mais un champ `declencheur` porte
# désormais les faits d'ordonnancement mesurés. Jamais de problem/oracle/
# root_cause fabriqués. Chaîne observable :
#   cause (ordre du profil) -> activation reason -> manifest kind:dispatch.
from __future__ import annotations

import json
import sys

import pytest

from forge.driver import ForgeDriver


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


class StubExecutor:
    def __call__(self, payload, decision, context):
        return {"ok": True, "output": f"artefact {payload.etape}"}


def _oracle_config(tmp_path, project="proj", exit_code=0):
    cfg = tmp_path / "oracles.json"
    cfg.write_text(
        json.dumps({project: {"cwd": str(tmp_path),
                              "command": [sys.executable, "-c", f"import sys; sys.exit({exit_code})"]}}),
        encoding="utf-8")
    return cfg


def _reason(run_dir, etape):
    from forge import context_manifest as cm
    lines = cm.manifest_path(run_dir, etape).read_text(encoding="utf-8").strip().splitlines()
    for line in lines:
        rec = json.loads(line)
        if rec.get("kind") == "dispatch":
            return rec["reason"]
    raise AssertionError(f"aucune ligne dispatch pour {etape}")


def test_declencheur_mecanique_transmis_au_manifeste(tmp_path, offline):
    run_dir = tmp_path / "run"
    ForgeDriver("proj", "proj-1", profile="micro", executor=StubExecutor(),
                run_dir=run_dir, oracle_config=_oracle_config(tmp_path),
                key_file=tmp_path / "k.key", audit_path=tmp_path / "audit.jsonl",
                telemetry_path=tmp_path / "telemetry.jsonl",
                builder_runs_path=tmp_path / "builder_runs.jsonl").run()

    # première étape du profil : déclenchée par le démarrage du run.
    c1 = _reason(run_dir, "s9-build")
    assert c1["status"] == "NOT_TRANSMITTED"          # invariant ratifié conservé
    assert c1["declencheur"]["cause"] == "ordre_de_profil"
    assert c1["declencheur"]["profile"] == "micro"
    assert c1["declencheur"]["position"] == 1
    assert c1["declencheur"]["predecesseur"] == "demarrage_du_run"

    # étape suivante : déclenchée par la terminaison mesurée du prédécesseur.
    c2 = _reason(run_dir, "s10a-oracle-code")
    assert c2["declencheur"]["position"] == 2
    assert c2["declencheur"]["predecesseur"] == {"etape": "s9-build", "status": "OK"}

    # jamais de cause fabriquée sur le chemin mécanique (même clause que le
    # test protégé, re-affirmée ici sur les champs additifs).
    for invente in ("problem", "oracle", "root_cause"):
        assert invente not in c1 and invente not in c2
