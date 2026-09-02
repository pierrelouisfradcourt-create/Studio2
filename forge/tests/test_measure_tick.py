"""SAS MOTEUR (GO Pierre 2026-09-01) — C-c : le tick de mesure est gardé par
oracle (finding n°8, paire 2).

Défaut mesuré : p2_alpha déclarait tick_ms=100 (sourcé), p2_beta tournait sur
une boucle `setInterval(16)` NON sourcée — « 72000 ticks » valait ~2h pour l'un,
~19 minutes pour l'autre. Aucun oracle ne gardait cette sémantique.

Trois volets, testés séparément puis en intégration driver :
  (1) check_project_brief : champ `mesure` optionnel, validé s'il est présent.
  (2) check_measure_tick (static_oracles.py) : le jeu déclare-t-il son pas
      logique (TICK_MS/tick_ms) égal à la valeur attendue ?
  (3) driver.py, gate s10a : Brief avec `mesure.tick_ms` -> contribue au
      verdict comme e2e_ok (FAIL -> escalade) ; Brief sans `mesure` -> SKIPPED,
      aucune contribution (non-régression des profils/briefs existants).
"""
from __future__ import annotations

import json
import sys

import pytest
import yaml

from forge.static_oracles import check_measure_tick, check_project_brief


# =====================================================================================
# (1) check_project_brief — champ `mesure` optionnel
# =====================================================================================

def _valid_brief(**overrides) -> dict:
    base = {
        "projet": "kitten_clicker",
        "intention": "apprendre a calibrer un clicker minimal, boucle courte",
        "contraintes": {
            "normative_refs": [
                {"spec": "FORGE_DESIGN_FREEDOM_SPEC_V0", "rules": ["N1", "N2", "N6"]},
            ],
            "project_specific": {
                "techniques": ["web/HTML, aucune dépendance externe"],
                "experimentales": ["boucle de complétion mutuelle art<->gm"],
            },
        },
        "cible": "web/HTML",
        "references_autorisees": [
            {"ref": "Cookie Clicker", "source": "Pierre 2026-08-29"},
        ],
        "criteres_sortie": ["jeu jouable 2 minutes sans crash"],
        "libertes_deleguees": ["choix des couleurs", "nommage des entités"],
        "provenance": {"projet": "Pierre 2026-08-29", "intention": "Pierre 2026-08-29"},
    }
    base.update(overrides)
    return base


def test_brief_sans_mesure_passe_retrocompat():
    rep = check_project_brief(_valid_brief())
    assert rep["passed"] is True
    assert rep["raisons"] == []


def test_brief_avec_mesure_valide_passe():
    rep = check_project_brief(_valid_brief(mesure={"tick_ms": 100, "budget_ticks": 72000}))
    assert rep["passed"] is True
    assert rep["raisons"] == []


def test_brief_avec_mesure_malformee_fail_nomme():
    rep = check_project_brief(_valid_brief(mesure={"tick_ms": 0, "budget_ticks": 72000}))
    assert rep["passed"] is False
    assert any("mesure.tick_ms" in r for r in rep["raisons"])


def test_brief_avec_mesure_budget_ticks_manquant_fail():
    rep = check_project_brief(_valid_brief(mesure={"tick_ms": 100}))
    assert rep["passed"] is False
    assert any("mesure.budget_ticks" in r for r in rep["raisons"])


def test_brief_avec_mesure_pas_un_mapping_fail():
    rep = check_project_brief(_valid_brief(mesure="72000 ticks"))
    assert rep["passed"] is False
    assert any("'mesure'" in r for r in rep["raisons"])


def test_brief_avec_mesure_tick_ms_bool_fail():
    # bool est un sous-type d'int en Python — garde explicite dans l'oracle.
    rep = check_project_brief(_valid_brief(mesure={"tick_ms": True, "budget_ticks": 100}))
    assert rep["passed"] is False
    assert any("mesure.tick_ms" in r for r in rep["raisons"])


# =====================================================================================
# (2) check_measure_tick — déclaration statique du pas logique
# =====================================================================================

def test_faux_src_avec_tick_ms_100_declare_pass(tmp_path):
    (tmp_path / "logic.mjs").write_text(
        "export const TICK_MS = 100;\nexport function tick() {}\n", encoding="utf-8")
    rep = check_measure_tick(tmp_path, 100)
    assert rep["passed"] is True
    assert rep["checked"] is True
    assert rep["raisons"] == []


def test_champ_objet_tick_ms_100_declare_pass(tmp_path):
    (tmp_path / "state.mjs").write_text(
        "window.__game = { score: 0, tick_ms: 100, over: false };\n", encoding="utf-8")
    rep = check_measure_tick(tmp_path, 100)
    assert rep["passed"] is True


def test_setinterval_16_sans_declaration_fail():
    # LE cas p2_beta : une boucle setInterval(16) non sourcée, aucune constante
    # TICK_MS/tick_ms nulle part -> FAIL.
    import tempfile
    from pathlib import Path
    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        (root / "loop.mjs").write_text(
            "setInterval(() => { step(); }, 16);\n", encoding="utf-8")
        rep = check_measure_tick(root, 100)
        assert rep["passed"] is False
        assert rep["checked"] is True
        assert any("aucune déclaration" in r for r in rep["raisons"])


def test_tick_ms_declare_mais_valeur_differente_fail(tmp_path):
    (tmp_path / "logic.mjs").write_text("const TICK_MS = 16;\n", encoding="utf-8")
    rep = check_measure_tick(tmp_path, 100)
    assert rep["passed"] is False
    assert any("différent" in r for r in rep["raisons"])


def test_tick_ms_attendu_invalide_fail_honnete(tmp_path):
    rep = check_measure_tick(tmp_path, 0)
    assert rep["passed"] is False
    assert rep["checked"] is False


def test_tick_ms_attendu_negatif_fail_honnete(tmp_path):
    rep = check_measure_tick(tmp_path, -100)
    assert rep["passed"] is False
    assert rep["checked"] is False


def test_src_root_absent_fail_honnete(tmp_path):
    rep = check_measure_tick(tmp_path / "n_existe_pas", 100)
    assert rep["passed"] is False
    assert rep["checked"] is False


def test_seul_le_mjs_de_bonne_valeur_compte_parmi_plusieurs(tmp_path):
    (tmp_path / "a.mjs").write_text("const TICK_MS = 16;\n", encoding="utf-8")
    (tmp_path / "b.mjs").write_text("const TICK_MS = 100;\n", encoding="utf-8")
    rep = check_measure_tick(tmp_path, 100)
    assert rep["passed"] is True
    assert any("b.mjs" in d for d in rep["declarations"])


# =====================================================================================
# (3) driver.py — gate s10a, intégration
# =====================================================================================

from forge.driver import ForgeDriver  # noqa: E402


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


def _jeu(tmp_path, tick_decl: str | None):
    """Mini-jeu e2e+solvabilité câblés (même patron que
    test_driver_harness_no_hardcoded_flags.py), avec ou sans déclaration TICK_MS."""
    g = tmp_path / "game"
    g.mkdir()
    logic = "export const win = 1 >= 0;\n"
    if tick_decl:
        logic = f"{tick_decl}\n{logic}"
    (g / "logic.mjs").write_text(logic, encoding="utf-8")
    (g / "run-oracle.mjs").write_text(
        'import { spawn } from "node:child_process";\n'
        'spawn("node", ["e2e.mjs"]);\n'
        'spawn("node", ["solvability.mjs"]);\n',
        encoding="utf-8",
    )
    (g / "e2e.mjs").write_text(
        'import { chromium } from "playwright";\n'
        'await page.click("#restart");\n'
        'const s = window.__game;\n'
        'if (window.__game.over) show("#overlay");\n',
        encoding="utf-8",
    )
    (g / "solvability.mjs").write_text(
        "const moves = [1];\n"
        "const result = { passed: moves.length > 0 };\n"
        "console.log(JSON.stringify(result));\n"
        "if (!result.passed) process.exit(1);\n",
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
        self.calls.append((payload.etape, context.get("model_override")))
        return {"ok": True, "output": f"artefact {payload.etape}"}


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


def _kwargs(tmp_path, run_dir, exit_code=0):
    return dict(
        run_dir=run_dir,
        oracle_config=_oracle_config(tmp_path, "jeu", exit_code),
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
        mutation_baseline_runner=lambda argv, cwd: True,
    )


def _write_brief(repo_root, project, mesure=None):
    brief = {
        "projet": project,
        "intention": "sonde de mesure",
        "contraintes": {
            "normative_refs": [],
            "project_specific": {"techniques": [], "experimentales": []},
        },
        "cible": "web/HTML",
        "references_autorisees": [],
        "provenance": {"references_autorisees": "FOG_HUMANGATE test"},
        "criteres_sortie": ["jeu jouable"],
        "libertes_deleguees": ["couleurs"],
    }
    if mesure is not None:
        brief["mesure"] = mesure
    path = repo_root / "EVIDENCE" / "briefs" / project / "project_brief.yaml"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(brief, allow_unicode=True, sort_keys=False), encoding="utf-8")
    return path


def _verdict(run_dir):
    return json.loads((run_dir / "verdict.json").read_text(encoding="utf-8"))


def test_brief_avec_mesure_et_jeu_conforme_contribue_ok(tmp_path, offline, monkeypatch):
    import forge.driver as driver_mod
    monkeypatch.setattr(driver_mod, "_REPO_ROOT", tmp_path)
    _write_brief(tmp_path, "jeu", mesure={"tick_ms": 100, "budget_ticks": 72000})

    run_dir = tmp_path / "run"
    g = _jeu(tmp_path, tick_decl="export const TICK_MS = 100;")
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         **_kwargs(tmp_path, run_dir)).run()

    assert report["software_verdict"] == "OK", report
    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    detail = state["steps"]["s10a-oracle-code"]["detail"]
    assert detail["measure_tick"]["passed"] is True
    assert detail["measure_tick"]["checked"] is True


def test_brief_avec_mesure_et_jeu_non_conforme_fail_et_escalade(tmp_path, offline, monkeypatch):
    """LE test central du volet (3) : un jeu dont la boucle réelle n'est pas au
    tick_ms attendu (aucune déclaration TICK_MS/tick_ms — profil setInterval(16)
    de p2_beta) ne peut plus verdir s10a malgré e2e/solvabilité/mutation verts."""
    import forge.driver as driver_mod
    monkeypatch.setattr(driver_mod, "_REPO_ROOT", tmp_path)
    _write_brief(tmp_path, "jeu", mesure={"tick_ms": 100, "budget_ticks": 72000})

    run_dir = tmp_path / "run"
    g = _jeu(tmp_path, tick_decl=None)  # aucune déclaration TICK_MS/tick_ms
    ex = StubExecutor()
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=ex, src_root=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         **_kwargs(tmp_path, run_dir)).run()

    assert report["software_verdict"] == "FAIL", report
    assert report["decision"] == "BLOCKED"
    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    s10a = state["steps"]["s10a-oracle-code"]
    assert s10a["status"] == "FAIL"
    detail = s10a["detail"]
    assert detail["measure_tick"]["passed"] is False
    # e2e/solvabilité restent verts par ailleurs — c'est BIEN measure_tick qui gate.
    assert detail["e2e"]["passed"] is True
    assert detail["solvability"]["passed"] is True
    # le FAIL alimente l'escalade (comme harness_no_hardcoded_flags)
    s9_calls = [c for c in ex.calls if c[0] == "s9-build"]
    assert len(s9_calls) > 1
    code = _verdict(run_dir)["oracles"]["code"]
    assert code["status"] == "FAIL"
    assert code["detail"]["measure_tick"]["passed"] is False


def test_brief_sans_mesure_skipped_sans_contribution_non_regression(tmp_path, offline, monkeypatch):
    """Brief sans champ `mesure` (ou absent du tout) : volet SKIPPED, jamais de
    contribution — comportement STRICTEMENT inchangé (non-régression des profils/
    briefs existants)."""
    import forge.driver as driver_mod
    monkeypatch.setattr(driver_mod, "_REPO_ROOT", tmp_path)
    _write_brief(tmp_path, "jeu", mesure=None)

    run_dir = tmp_path / "run"
    g = _jeu(tmp_path, tick_decl=None)  # aucune déclaration -- n'a pas d'importance ici
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         **_kwargs(tmp_path, run_dir)).run()

    assert report["software_verdict"] == "OK", report
    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    detail = state["steps"]["s10a-oracle-code"]["detail"]
    assert detail["measure_tick"]["status"] == "SKIPPED"
    assert detail["measure_tick"]["checked"] is False


def test_aucun_brief_du_tout_skipped_sans_contribution(tmp_path, offline, monkeypatch):
    """Aucun EVIDENCE/briefs/<projet>/project_brief.yaml sur disque du tout —
    même garantie de non-régression, sans même créer le dossier."""
    import forge.driver as driver_mod
    monkeypatch.setattr(driver_mod, "_REPO_ROOT", tmp_path)
    # PAS de _write_brief ici.

    run_dir = tmp_path / "run"
    g = _jeu(tmp_path, tick_decl=None)
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         **_kwargs(tmp_path, run_dir)).run()

    assert report["software_verdict"] == "OK", report
    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    detail = state["steps"]["s10a-oracle-code"]["detail"]
    assert detail["measure_tick"]["status"] == "SKIPPED"
