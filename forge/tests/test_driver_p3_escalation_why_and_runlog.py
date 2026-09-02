"""Oracle P3 (lot dégel 2, docs/forge/FORGE_CONTEXT_COMPACT_V1.md §07) :

  (a) le WHY d'une escalade RÉUSSIE survit désormais dans `state.json`
      (`humangate_notes`, même patron que l'escalade REFUSÉE) — avant ce lot,
      seul `logger.info` le portait, perdu dès que le process disparaissait ;
  (b) un `FileHandler` best-effort persiste les logs de CE run sous
      `<run_dir>/run.log` (encodage utf-8), attaché/détaché autour de
      `ForgeDriver.run()` — une exception à l'ouverture ne casse jamais le run.

Réutilise le patron déjà prouvé par `test_pool_size_un_desactive_le_pool_
escalade_directe` (test_driver.py) : `pool_size=1` sur un oracle qui échoue
systématiquement force UNE escalade par tentative de s9-build (None ->
sonnet -> opus), cap MAX_ESCALATIONS=2 (forge.escalate).

Fichier NEUF (forge/tests/**, régime studio normal) — n'altère aucun
test existant. NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
import logging
import sys
from pathlib import Path

import pytest

from forge.driver import ForgeDriver


def _oracle_config(tmp_path, project, exit_code=0):
    cfg = tmp_path / "oracles_test.json"
    cfg.write_text(
        json.dumps({project: {
            "cwd": str(tmp_path),
            "command": [sys.executable, "-c", f"import sys; sys.exit({exit_code})"],
        }}),
        encoding="utf-8",
    )
    return cfg


class StubExecutor:
    def __init__(self):
        self.calls = []

    def __call__(self, payload, decision, context):
        self.calls.append((payload.etape, context.get("model_override")))
        return {"ok": True, "output": f"artefact {payload.etape}"}


def _kwargs(tmp_path, run_dir, project="proj", exit_code=0):
    return dict(
        run_dir=run_dir,
        oracle_config=_oracle_config(tmp_path, project, exit_code),
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
        journal_path=tmp_path / "journal.jsonl",
    )


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


# --- (a) WHY d'escalade RÉUSSIE persisté ------------------------------------------

def test_escalade_reussie_ecrit_son_motif_dans_state_json(tmp_path, offline):
    run_dir = tmp_path / "run"
    ex = StubExecutor()
    report = ForgeDriver("proj", "proj-1", profile="micro", executor=ex, pool_size=1,
                         **_kwargs(tmp_path, run_dir, exit_code=1)).run()
    assert report["software_verdict"] == "FAIL"  # cap MAX_ESCALATIONS atteint, jamais masqué

    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    assert state["escalations"] == 2
    notes = state.get("humangate_notes", [])
    assert any(n.startswith("escalade #1:") for n in notes), notes
    assert any(n.startswith("escalade #2:") for n in notes), notes


def test_escalade_reussie_motif_present_apres_rechargement_disque(tmp_path, offline):
    """Le motif est bien PERSISTÉ (pas seulement en mémoire) : une relecture
    indépendante du fichier state.json le retrouve à l'identique."""
    run_dir = tmp_path / "run"
    ex = StubExecutor()
    ForgeDriver("proj", "proj-1", profile="micro", executor=ex, pool_size=1,
               **_kwargs(tmp_path, run_dir, exit_code=1)).run()

    reloaded = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    notes = reloaded.get("humangate_notes", [])
    assert len(notes) == len(set(notes)), "chaque motif doit être dédupliqué, jamais répété"
    assert any("escalade #1:" in n for n in notes)


# --- (b) run.log persisté ----------------------------------------------------------

def test_run_log_cree_et_non_vide_apres_un_run_simule(tmp_path, offline):
    run_dir = tmp_path / "run"
    ex = StubExecutor()
    report = ForgeDriver("proj", "proj-1", profile="micro", executor=ex,
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["status"] == "DONE"

    run_log = run_dir / "run.log"
    assert run_log.exists(), "run.log doit être créé pendant run()"
    assert run_log.stat().st_size > 0, "run.log ne doit pas être vide"
    content = run_log.read_text(encoding="utf-8")
    assert "proj-1" in content  # au moins la ligne d'ouverture porte le run_id


def test_run_log_handler_est_detache_apres_le_run(tmp_path, offline):
    """Le handler ne doit jamais rester accroché au logger `forge` après la fin
    du run — sinon les runs suivants (même process, ex. suite de tests)
    accumuleraient des FileHandler sur des run_dir déjà fermés."""
    run_dir = tmp_path / "run"
    ex = StubExecutor()
    forge_logger = logging.getLogger("forge")
    before = list(forge_logger.handlers)
    ForgeDriver("proj", "proj-1", profile="micro", executor=ex,
               **_kwargs(tmp_path, run_dir)).run()
    after = list(forge_logger.handlers)
    assert after == before, "le FileHandler de run.log doit être retiré en fin de run()"


def test_exception_du_filehandler_ne_casse_pas_le_run(tmp_path, offline, monkeypatch):
    """Une ouverture de FileHandler qui lève (disque, permission...) est avalée
    — best-effort strict — et le run va au bout normalement."""
    def _boom(*a, **k):
        raise OSError("disque plein (simulé)")

    monkeypatch.setattr(logging, "FileHandler", _boom)
    run_dir = tmp_path / "run"
    ex = StubExecutor()
    report = ForgeDriver("proj", "proj-1", profile="micro", executor=ex,
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["status"] == "DONE"
    assert not (run_dir / "run.log").exists()
