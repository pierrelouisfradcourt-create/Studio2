"""Oracle du câblage AUTOMATIQUE de l'index des journaux d'erreurs, en fin de run.

Ferme le trou « déclaré ≠ exécuté » : `studio_link.list_journals` /
`generate_journal_index` / `write_journal_index` existaient (+ CLI `--write`) mais
n'avaient jamais tourné — `EVIDENCE/reports/error_journal/INDEX.generated.md` n'existait
nulle part. Le journal d'erreurs n'était donc lisible que par un LLM (via le
pré-mortem injecté dans un prompt), jamais par un humain.

Garanties testées :
  - un run RÉEL (run_dir SOUS le dépôt) régénère l'index à la fin — au même point
    que `_final_report` (complétion normale ET reprise idempotente d'un run DONE) ;
  - un run de TEST (run_dir HORS du dépôt, `journal_index_dir` non injecté) N'ÉCRIT
    JAMAIS dans le dépôt réel — sans quoi toute la suite de tests polluerait
    EVIDENCE/reports/error_journal/ à chaque exécution de pytest ;
  - une écriture qui échoue (OSError) NE CASSE JAMAIS le run (best-effort, même
    garantie que la télémétrie/journal d'erreurs) ;
  - l'entrée CLI existante (`studio_link.main --write`) reste inchangée.
"""
import json
import sys
from pathlib import Path

import pytest

import forge.driver as drv
from forge import studio_link as sl
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
    def __call__(self, payload, decision, context):
        return {"ok": True, "output": f"artefact {payload.etape}"}


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


def _kwargs(tmp_path, run_dir, project="proj", exit_code=0, **extra):
    kw = dict(
        run_dir=run_dir,
        oracle_config=_oracle_config(tmp_path, project, exit_code),
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
        journal_path=tmp_path / "journal.jsonl",
    )
    kw.update(extra)
    return kw


# --- 1) run réel (journal_index_dir injecté) : index produit --------------------

def test_run_complet_regenere_l_index_avec_journal_index_dir_injecte(tmp_path, offline):
    run_dir = tmp_path / "run"
    reports_dir = tmp_path / "reports"
    report = ForgeDriver("proj", "proj-1", profile="micro", executor=StubExecutor(),
                         **_kwargs(tmp_path, run_dir, journal_index_dir=reports_dir)).run()
    assert report["status"] == "DONE"
    index_path = reports_dir / "error_journal" / "INDEX.generated.md"
    assert index_path.exists()
    text = index_path.read_text(encoding="utf-8")
    assert "Journaux d'erreurs Forge par domaine" in text
    assert "forge" in text  # domaine par défaut listé


def test_reprise_idempotente_regenere_aussi_l_index(tmp_path, offline):
    """Le 2e appel à .run() sur un state déjà DONE (chemin idempotent de _final_report)
    régénère aussi l'index — même point de câblage que la complétion normale."""
    run_dir = tmp_path / "run"
    reports_dir = tmp_path / "reports"
    kw = _kwargs(tmp_path, run_dir, journal_index_dir=reports_dir)
    ForgeDriver("proj", "proj-1", profile="micro", executor=StubExecutor(), **kw).run()
    index_path = reports_dir / "error_journal" / "INDEX.generated.md"
    assert index_path.exists()
    index_path.unlink()  # simule un index effacé entre deux runs
    report2 = ForgeDriver("proj", "proj-1", profile="micro", executor=StubExecutor(), **kw).run()
    assert report2["status"] == "DONE"
    assert index_path.exists(), "le chemin idempotent (state déjà DONE) doit aussi régénérer"


# --- 2) run de test (hors dépôt, pas d'injection) : AUCUNE écriture réelle ------

def test_run_hors_depot_sans_injection_n_ecrit_jamais_dans_le_depot_reel(tmp_path, offline, monkeypatch):
    """Sans `journal_index_dir`, write_journal_index() écrirait par défaut sous
    EVIDENCE/reports/ du dépôt RÉEL — inacceptable pour un run de test. On le prouve en
    remplaçant write_journal_index par une sentinelle qui explose si appelée."""
    calls = []
    monkeypatch.setattr(drv, "write_journal_index",
                        lambda reports_dir=None: calls.append(reports_dir) or (_ for _ in ()).throw(
                            AssertionError("ne doit JAMAIS être appelée pour un run hors dépôt")))
    run_dir = tmp_path / "run"  # tmp_path est HORS du dépôt (_REPO_ROOT)
    report = ForgeDriver("proj", "proj-1", profile="micro", executor=StubExecutor(),
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["status"] == "DONE"
    assert calls == [], "write_journal_index ne doit pas être invoquée pour un run de test"


# --- 3) une écriture qui échoue ne casse jamais le run --------------------------

def test_echec_ecriture_index_ne_casse_pas_le_run(tmp_path, offline, monkeypatch):
    def _boom(reports_dir=None):
        raise OSError("disque HS (simulé)")

    monkeypatch.setattr(drv, "write_journal_index", _boom)
    run_dir = tmp_path / "run"
    reports_dir = tmp_path / "reports"
    report = ForgeDriver("proj", "proj-1", profile="micro", executor=StubExecutor(),
                         **_kwargs(tmp_path, run_dir, journal_index_dir=reports_dir)).run()
    assert report["status"] == "DONE"
    assert report["software_verdict"] == "OK"


# --- 4) contenu déterministe + entrée CLI inchangée ------------------------------

def test_generation_deterministe_meme_reports_dir(tmp_path):
    """Deux générations SUR LE MÊME reports_dir (mêmes journaux, aucun horodatage
    d'exécution) rendent des octets IDENTIQUES."""
    reports_dir = tmp_path / "reports"
    p1 = sl.write_journal_index(reports_dir=reports_dir)
    b1 = p1.read_bytes()
    p2 = sl.write_journal_index(reports_dir=reports_dir)
    b2 = p2.read_bytes()
    assert b1 == b2


def test_cli_write_reste_fonctionnel(tmp_path, monkeypatch):
    """L'entrée CLI existante (`python -m forge.studio_link --write`) reste
    inchangée : elle écrit toujours sous le reports_dir PAR DÉFAUT du module
    (aucun paramètre reports_dir sur le CLI — comportement identique à avant ce
    chantier, on vérifie seulement que main() ne lève pas et rend 0)."""
    monkeypatch.setattr(sl, "FORGE_REPORTS", tmp_path / "reports_cli")
    rc = sl.main(["--write"])
    assert rc == 0
    assert (tmp_path / "reports_cli" / "error_journal" / "INDEX.generated.md").exists()
