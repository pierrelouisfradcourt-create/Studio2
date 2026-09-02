"""Oracle du câblage AUTOMATIQUE du journal d'erreurs dans le driver Forge.

Ferme la boucle d'apprentissage EN CODE (plomberie déterministe, zéro LLM) :

  - un échec d'étape (BLOCKED via `_halt_step`, FAIL/BLOCKED via `_finish_step`)
    ÉCRIT au journal, best-effort (connecteur 6, `studio_link.record_error`) ;
  - une étape qui PASSE après un échec précédent (`attempts > 1`) écrit la
    RÉPARATION (`record_fix`, 2e colonne du journal) ;
  - une NOUVELLE tentative RE-LIT le pré-mortem À JOUR (cache invalidé au retry),
    y compris l'échec qu'on vient d'écrire ;
  - une écriture de journal qui LÈVE ne casse JAMAIS le run (comme la télémétrie).

Le journal est redirigé vers un fichier tmp injecté (`journal_path`) — zéro
écriture dans le repo. NO_CLAIM_ALLOWED : ces tests prouvent la PLOMBERIE
(écriture/relecture), jamais une quelconque qualité des leçons.
"""
import json
import sys
from pathlib import Path

import pytest

from forge.driver import ForgeDriver


# --- utilitaires (autonomes : ne dépendent d'aucun autre fichier de test) ---------

def _oracle_config(tmp_path, project, exit_code=0):
    """Config oracle témoin : une commande python qui sort avec exit_code."""
    cfg = tmp_path / "oracles_test.json"
    cfg.write_text(
        json.dumps({project: {
            "cwd": str(tmp_path),
            "command": [sys.executable, "-c", f"import sys; sys.exit({exit_code})"],
        }}),
        encoding="utf-8",
    )
    return cfg


def _kwargs(tmp_path, run_dir, project="proj", exit_code=0):
    """Paramètres communs — tout est redirigé sous tmp_path (zéro pollution repo).

    `journal_path` est INJECTÉ : le journal d'erreurs va dans un tmp isolé, jamais
    dans EVIDENCE/reports/error_journal.
    """
    return dict(
        run_dir=run_dir,
        oracle_config=_oracle_config(tmp_path, project, exit_code),
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
        journal_path=tmp_path / "journal.jsonl",
    )


def _journal(tmp_path):
    """Entrées du journal tmp injecté (liste de dicts), [] si absent."""
    path = tmp_path / "journal.jsonl"
    if not path.exists():
        return []
    return [json.loads(l) for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]


class StubExecutor:
    """Exécuteur LLM factice : trace (etape, model_override, premortem) par appel."""

    def __init__(self, run_dir=None, raise_on=()):
        self.calls = []          # (etape, model_override)
        self.premortems = []     # (etape, premortem list vue à cet appel)
        self.run_dir = run_dir
        self.raise_on = set(raise_on)

    def __call__(self, payload, decision, context):
        self.calls.append((payload.etape, context.get("model_override")))
        self.premortems.append((payload.etape, list(context.get("premortem", []))))
        if payload.etape in self.raise_on:
            raise RuntimeError(f"interruption simulée à {payload.etape}")
        return {"ok": True, "output": f"artefact {payload.etape}"}


@pytest.fixture
def offline(monkeypatch):
    """Offline strict : aucune sonde LM Studio pendant ces tests."""
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


# --- 1) résolveur de domaine -------------------------------------------------------

def test_domaine_html_pour_un_jeu_forge_sinon(tmp_path):
    run_dir = tmp_path / "run"
    d_forge = ForgeDriver("proj", "proj-1", profile="micro", run_dir=run_dir)
    assert d_forge._domain() == "forge"
    d_game = ForgeDriver("proj", "proj-1", profile="micro", run_dir=run_dir, is_game=True)
    assert d_game._domain() == "html"


# --- 2) écriture sur échec (_halt_step BLOCKED) -----------------------------------

def test_halt_step_ecrit_l_echec_au_journal(tmp_path, offline):
    """Sans exécuteur, s9-build HALTE en BLOCKED -> une entrée journal ouverte."""
    run_dir = tmp_path / "run"
    report = ForgeDriver("proj", "proj-1", profile="micro", executor=None,
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["status"] == "HALTED"

    entries = _journal(tmp_path)
    s9 = [e for e in entries if e["etape"] == "s9-build"]
    assert s9, "l'échec de s9-build doit être consigné au journal"
    assert s9[0]["project"] == "proj"
    assert s9[0]["status"] == "open"          # échec non réparé
    assert "exécuteur" in s9[0]["error"]


# --- 2bis) écriture sur échec (_finish_step FAIL d'oracle) ------------------------

def test_finish_step_ecrit_l_oracle_rouge_au_journal(tmp_path, offline):
    """Oracle rouge (exit 1) -> s10a-oracle-code FAIL -> entrée(s) au journal."""
    run_dir = tmp_path / "run"
    ex = StubExecutor(run_dir=run_dir)
    report = ForgeDriver("proj", "proj-1", profile="micro", executor=ex, pool_size=1,
                         **_kwargs(tmp_path, run_dir, exit_code=1)).run()
    assert report["software_verdict"] == "FAIL"

    entries = _journal(tmp_path)
    oracle = [e for e in entries if e["etape"] == "s10a-oracle-code"]
    assert oracle, "un FAIL d'oracle déterministe doit être consigné au journal"
    assert any("returncode=1" in e["error"] for e in oracle)


# --- 3) écriture de la RÉPARATION (attempts > 1 sur le chemin succès) --------------

def test_record_fix_sur_reprise_apres_interruption(tmp_path, offline):
    """s11 interrompue puis rejouée (attempts=2) : la réussite écrit la réparation."""
    run_dir = tmp_path / "run"
    kw = _kwargs(tmp_path, run_dir)

    with pytest.raises(RuntimeError):
        ForgeDriver("proj", "proj-1", profile="patch",
                    executor=StubExecutor(run_dir=run_dir, raise_on={"s11-redteam-code"}),
                    **kw).run()

    report = ForgeDriver("proj", "proj-1", profile="patch",
                         executor=StubExecutor(run_dir=run_dir), **kw).run()
    assert report["status"] == "DONE"

    fixes = [e for e in _journal(tmp_path)
             if e["etape"] == "s11-redteam-code" and e["status"] == "fixed"]
    assert fixes, "la reprise réussie doit consigner une réparation (2e colonne)"
    assert fixes[-1]["resolution"] and "tentative 2" in fixes[-1]["resolution"]


def test_record_fix_sur_reprise_apres_escalade(tmp_path, offline):
    """s9-build rejoué au fil de l'escalade (attempts>1) écrit aussi une réparation."""
    run_dir = tmp_path / "run"
    ex = StubExecutor(run_dir=run_dir)
    ForgeDriver("proj", "proj-1", profile="micro", executor=ex,
                **_kwargs(tmp_path, run_dir, exit_code=1)).run()

    fixes = [e for e in _journal(tmp_path)
             if e["etape"] == "s9-build" and e["status"] == "fixed"]
    assert fixes, "un s9-build re-tenté (attempts>1) qui passe doit écrire une réparation"


# --- 4) re-lecture du pré-mortem au retry (cache invalidé) -------------------------

def test_le_retry_relit_le_journal_a_jour(tmp_path, offline):
    """CŒUR de la boucle : la 1re tentative de s9-build voit un pré-mortem vide ;
    après un oracle rouge (journalisé) + escalade/pool, la tentative SUIVANTE voit
    l'échec qu'on vient d'écrire — preuve que le cache est invalidé et le journal relu."""
    run_dir = tmp_path / "run"
    ex = StubExecutor(run_dir=run_dir)
    ForgeDriver("proj", "proj-1", profile="micro", executor=ex,
                **_kwargs(tmp_path, run_dir, exit_code=1)).run()

    s9_premortems = [pm for (etape, pm) in ex.premortems if etape == "s9-build"]
    assert len(s9_premortems) >= 2, "l'escalade doit rejouer s9-build au moins 2 fois"
    assert s9_premortems[0] == []                      # 1er build : journal vide
    later = s9_premortems[1]
    assert any("s10a-oracle-code" in line for line in later), (
        "la tentative suivante doit voir l'échec d'oracle fraîchement journalisé")


# --- 5) caractère NON bloquant (une écriture qui lève ne casse pas le run) ---------

def test_ecriture_journal_qui_leve_ne_casse_pas_le_run(tmp_path, offline, monkeypatch):
    """record_error ET record_fix qui LÈVENT n'échouent jamais le run (best-effort,
    même garantie que la télémétrie). Le verdict reste identique au run sans panne."""
    def _boom(*a, **k):
        raise RuntimeError("journal HS (simulé)")

    monkeypatch.setattr("forge.driver.record_error", _boom)
    monkeypatch.setattr("forge.driver.record_fix", _boom)

    run_dir = tmp_path / "run"
    ex = StubExecutor(run_dir=run_dir)
    # Scénario riche en écritures (FAIL d'oracle répétés + réparations sur retry).
    report = ForgeDriver("proj", "proj-1", profile="micro", executor=ex,
                         **_kwargs(tmp_path, run_dir, exit_code=1)).run()

    assert report["status"] == "DONE"                  # le run va au bout malgré la panne
    assert report["software_verdict"] == "FAIL"        # verdict inchangé (rouge signé)
    assert not _journal(tmp_path)                       # rien écrit (chaque write a levé)
