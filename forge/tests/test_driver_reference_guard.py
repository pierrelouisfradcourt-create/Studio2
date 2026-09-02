"""Câblage driver -> forge.reference_guard (FVL Phase 0.5, chantier `reference_protected`,
docs/fvl/FVL_PHASE_0_5_CHARTER.md §7 point 1). ADVISORY STRICT — même patron de test que
test_driver_learning_hook.py (câblage attesté par monkeypatch du point d'entrée unique,
`reference_guard.advisory_check` — la mesure elle-même est couverte par
test_reference_guard.py, pas ici).

Garanties vérifiées :
  - `advisory_check` est appelé avec phase="open" à l'ouverture d'un run (avant `_load_state`)
    ET phase="close" à sa clôture (`_final_report`, les deux chemins DONE) ;
  - chaque appel est CONSIGNÉ dans `<run_dir>/reference_guard.jsonl`, jamais dans un fichier
    durable du dépôt ;
  - AUCUN gate, AUCUN verdict n'est affecté par le résultat (même un statut DRIFT/ERROR
    simulé laisse un run par ailleurs vert inchangé) ;
  - une exception dans `advisory_check` (qui ne devrait normalement jamais en lever — best-
    effort strict déjà prouvé dans test_reference_guard.py) reste, en PLUS, absorbée par le
    driver lui-même (défense en profondeur, même garantie que `_record_learning_advisory`) ;
  - non-régression : un run SANS reference_guard configuré (défauts production, aucune
    baseline enregistrée dans l'environnement de test) se comporte EXACTEMENT comme avant
    ce câblage — même verdict, même décision.
"""
import json
import sys

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


def _game_dir(tmp_path):
    """Mini-jeu satisfaisant la garde e2e structurelle (check_e2e_harness) — copie du
    fixture éprouvé de test_driver_learning_hook.py."""
    g = tmp_path / "game"
    g.mkdir()
    (g / "logic.mjs").write_text("export const speed = 3;\nexport const win = 1 >= 0;\n",
                                 encoding="utf-8")
    (g / "run-oracle.mjs").write_text(
        'import { spawn } from "node:child_process";\n'
        'spawn("node", ["e2e.mjs"]);\n',
        encoding="utf-8",
    )
    (g / "e2e.mjs").write_text(
        'import { chromium } from "playwright";\n'
        'await page.click("#restart");\n'
        'const s = window.__game;\n'
        'if (window.__game.over) show("#overlay");\n',
        encoding="utf-8",
    )
    (g / "logic.test.mjs").write_text("// suite logique\n", encoding="utf-8")
    (g / "properties.test.mjs").write_text("// suite propriétés\n", encoding="utf-8")
    return g


def _all_killed(source_path, test_argv, *, cwd, **kw):
    return {"total": 4, "killed": 4, "survived": 0, "score": 1.0, "survivors": []}


class StubExecutor:
    def __init__(self):
        self.calls = []

    def __call__(self, payload, decision, context):
        self.calls.append(payload.etape)
        return {"ok": True, "output": f"artefact {payload.etape}"}


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


def _kwargs(tmp_path, run_dir, project="jeu", exit_code=0):
    return dict(
        run_dir=run_dir,
        oracle_config=_oracle_config(tmp_path, project, exit_code),
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
        mutation_baseline_runner=lambda argv, cwd: True,
    )


def _run_green(tmp_path, monkeypatch, offline_fixture=None):
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    # Baseline ISOLÉE dans tmp_path (fichier volontairement inexistant) : sans cette
    # injection, le garde retombe sur DEFAULT_BASELINE_PATH et lit la baseline RÉELLE du
    # dépôt — l'état attendu dépendrait alors de la présence d'un fichier hors du test.
    # Constaté en vivo : ces tests passaient tant que la baseline réelle n'existait pas,
    # et échouaient dès qu'elle a été enregistrée (règle d'usine n°3 — un test vérifie une
    # propriété durable, pas une valeur historique accidentelle).
    driver = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g, game_dir=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         reference_guard_baseline_path=tmp_path / "isolated_baseline.json",
                         **_kwargs(tmp_path, run_dir))
    return driver, driver.run()


# --- câblage : appelé aux deux phases, avec les bons arguments -----------------------

def test_advisory_check_appele_a_louverture_et_a_la_cloture(tmp_path, offline, monkeypatch):
    calls = []
    monkeypatch.setattr(
        "forge.reference_guard.advisory_check",
        lambda phase, **kw: calls.append((phase, kw)) or {
            "schema": "forge.reference_guard.report.v1", "status": "NO_BASELINE",
            "diffs": [], "checked_at": "t", "phase": phase,
        },
    )
    driver, report = _run_green(tmp_path, monkeypatch)
    phases = [c[0] for c in calls]
    assert phases[0] == "open"   # premier appel : ouverture, avant tout le reste
    assert phases[-1] == "close"  # dernier appel : clôture (_final_report)
    assert report["software_verdict"] == "OK"


def test_advisory_check_recoit_les_chemins_injectes(tmp_path, offline, monkeypatch):
    calls = []
    monkeypatch.setattr(
        "forge.reference_guard.advisory_check",
        lambda phase, **kw: calls.append((phase, kw)) or {
            "schema": "forge.reference_guard.report.v1", "status": "NO_BASELINE",
            "diffs": [], "checked_at": "t", "phase": phase,
        },
    )
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    cfg = tmp_path / "reference_protected_custom.yaml"
    baseline = tmp_path / "custom_baseline.json"
    derog = tmp_path / "custom_derogation.json"
    ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
               executor=StubExecutor(), src_root=g, game_dir=g,
               logic_files=["logic.mjs"], mutation_runner=_all_killed,
               reference_guard_config_path=cfg,
               reference_guard_baseline_path=baseline,
               reference_guard_derogation_path=derog,
               **_kwargs(tmp_path, run_dir)).run()
    assert calls, "advisory_check jamais appelé"
    for _phase, kw in calls:
        assert kw["config_path"] == cfg
        assert kw["baseline_path"] == baseline
        assert kw["derogation_path"] == derog


# --- consignation : un fichier append-only sous run_dir, jamais durable ailleurs -----

def test_resultat_consigne_dans_run_dir_jamais_ailleurs(tmp_path, offline, monkeypatch):
    driver, report = _run_green(tmp_path, monkeypatch)
    log_path = driver.run_dir / "reference_guard.jsonl"
    assert log_path.exists()
    lines = [json.loads(l) for l in log_path.read_text(encoding="utf-8").splitlines() if l]
    assert len(lines) >= 2
    phases = [l["phase"] for l in lines]
    assert phases[0] == "open"
    assert phases[-1] == "close"
    for line in lines:
        assert line["run_id"] == "jeu-1"
        assert line["status"] == "NO_BASELINE"  # aucune baseline en environnement de test


# --- aucun gate, aucun verdict affecté ------------------------------------------------

def test_statut_drift_simule_najamais_daffect_le_verdict(tmp_path, offline, monkeypatch):
    """Même un DRIFT simulé (violation détectée) ne doit RIEN changer au verdict du
    run — ce garde est un OBSERVATEUR, jamais un juge (AUCUN gate, AUCUN verdict)."""
    monkeypatch.setattr(
        "forge.reference_guard.advisory_check",
        lambda phase, **kw: {
            "schema": "forge.reference_guard.report.v1", "status": "DRIFT",
            "diffs": [{"path": "GAMES/pong/x.gd", "kind": "MODIFIE", "authorized": False}],
            "checked_at": "t", "phase": phase,
        },
    )
    driver, report = _run_green(tmp_path, monkeypatch)
    assert report["software_verdict"] == "OK"
    assert report["decision"] == "HUMANGATE_READY"


# --- best-effort : défense en profondeur côté driver, en plus du best-effort interne --

def test_exception_dans_advisory_check_najamais_de_run_deja_vert(tmp_path, offline, monkeypatch):
    def _boom(phase, **kw):
        raise RuntimeError("panne simulée du garde de référence")

    monkeypatch.setattr("forge.reference_guard.advisory_check", _boom)
    driver, report = _run_green(tmp_path, monkeypatch)
    assert report["software_verdict"] == "OK"
    assert report["decision"] == "HUMANGATE_READY"
    # l'exception a empêché l'écriture du fichier consigné pour CET appel — mais le
    # run lui-même n'a jamais été interrompu (best-effort strict).


def test_exception_a_lecriture_du_fichier_consigne_najamais_de_run_casse(
    tmp_path, offline, monkeypatch
):
    """Défense en profondeur au niveau du driver LUI-MÊME (pas seulement
    `advisory_check`) : même si l'ÉCRITURE du fichier consigné échoue (ex. `open`
    lève), le run reste vert."""
    monkeypatch.setattr(
        "forge.reference_guard.advisory_check",
        lambda phase, **kw: {"schema": "x", "status": "NO_BASELINE", "diffs": [],
                             "checked_at": "t", "phase": phase},
    )
    real_open = open

    def _boom_open(path, *a, **kw):
        if str(path).endswith("reference_guard.jsonl"):
            raise OSError("disque simulé plein")
        return real_open(path, *a, **kw)

    monkeypatch.setattr("forge.driver.open", _boom_open, raising=False)
    driver, report = _run_green(tmp_path, monkeypatch)
    assert report["software_verdict"] == "OK"


# --- non-régression : comportement identique sans reference_guard configuré ----------

def test_non_regression_verdict_identique_sans_baseline(tmp_path, offline, monkeypatch):
    """Preuve de non-nuisance du câblage (PREUVE EXIGÉE point 5) : SANS monkeypatch
    d'`advisory_check` (donc avec le VRAI module, chemins par défaut PRODUCTION —
    aucune baseline enregistrée dans cet environnement de test), le run atteint le
    MÊME verdict/décision qu'avant ce chantier. Le fichier consigné existe, porte
    NO_BASELINE, et rien d'autre n'a changé."""
    driver, report = _run_green(tmp_path, monkeypatch)
    assert report["software_verdict"] == "OK"
    assert report["decision"] == "HUMANGATE_READY"
    log_path = driver.run_dir / "reference_guard.jsonl"
    assert log_path.exists()
    lines = [json.loads(l) for l in log_path.read_text(encoding="utf-8").splitlines() if l]
    assert all(l["status"] == "NO_BASELINE" for l in lines)


def test_idempotent_reprise_reappelle_ouverture_et_cloture(tmp_path, offline, monkeypatch):
    """Un `run()` idempotent (déjà DONE) redéclenche quand même open+close — c'est le
    point : détecter une modification survenue APRÈS la première clôture, avant une
    relecture ultérieure du même run_dir."""
    driver, first_report = _run_green(tmp_path, monkeypatch)
    log_path = driver.run_dir / "reference_guard.jsonl"
    lines_after_first = log_path.read_text(encoding="utf-8").splitlines()
    assert len(lines_after_first) >= 2

    second_report = driver.run()
    assert second_report["status"] == "DONE"
    lines_after_second = log_path.read_text(encoding="utf-8").splitlines()
    assert len(lines_after_second) > len(lines_after_first)
