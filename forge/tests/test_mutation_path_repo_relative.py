"""SAS MOTEUR MINIMAL — finding P3-2 (GO Pierre 2026-09-01).

Défaut réel, run p3_alpha, étape s10a (volet mutation) :
`EVIDENCE/runs/p3_alpha/wiremap.json` cite ses fichiers en chemins
REPO-RELATIFS (`GAMES/p3_alpha/economy.mjs`) alors que
`driver.py::_run_code_oracle` joint `self.src_root / f` — avec
`self.src_root` déjà pointé sur `GAMES/p3_alpha`, le join DOUBLE le préfixe
(`GAMES/p3_alpha/GAMES/p3_alpha/economy.mjs`) => `FileNotFoundError` non
gérée => process mort exit 1 => `state.json` reste `RUNNING` (état menteur,
aucun process ne tourne plus).

Deux correctifs couverts ici :
  (1) normalisation du préfixe repo-relatif de `self.src_root` au volet
      mutation de `_run_code_oracle`, tracée dans le detail signé
      (`logic_files_normalized`) et répercutée dans le `scope` du reçu ;
      fichier toujours introuvable après normalisation => BLOCKED nommé,
      jamais une exception (cas (a)/(b) ci-dessous) ; noms nus déjà valides
      (convention paire 2) inchangés (cas (c)).
  (2) toute exception non gérée levée DANS une étape déterministe (le point
      d'appel `self._run_deterministic(state, etape)`, driver.py ~l.553) est
      convertie en HALT propre — `run_status=HALTED` persisté + raison
      consignée, jamais un `state.json` laissé RUNNING sans process (cas (d)).

`_WIREMAP_P3_ALPHA_EXCERPT` ci-dessous est une COPIE VERBATIM (une seule
feature, R1, suffisante pour prouver le défaut) de
`EVIDENCE/runs/p3_alpha/wiremap.json` (dossier de preuve INTOUCHABLE —
jamais modifié ni relu au runtime par ce test, seule la copie locale sert
d'entrée). Le driver est appelé avec `_REPO_ROOT` monkeypatché sur `tmp_path`
et `src_root` posé sur `<tmp_path>/GAMES/p3_alpha` : le préfixe repo-relatif
recalculé par le driver (`GAMES/p3_alpha/`) est alors EXACTEMENT celui que
porte la fixture réelle, sans qu'un seul caractère de la fixture n'ait été
adapté au test.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

from forge.driver import ForgeDriver


# --- fixture réelle p3_alpha (copie verbatim, feature R1 seule) --------------------

_WIREMAP_P3_ALPHA_EXCERPT = {
    "features": [
        {
            "feature": "R1 Gain au clic (economie)",
            "fonction": "clickGain",
            "fichiers": [
                "GAMES/p3_alpha/state.mjs",
                "GAMES/p3_alpha/economy.mjs"
            ],
            "preuve": "logic.test.mjs: bot clique N fois ; solde_mR augmente d'EXACTEMENT N x gain_clic x 1000 (test R1-clickGain-*, assertions ===). e2e.mjs (test R1_click_gain_exact_no_listener_leak): 5 VRAIS clics souris espaces de 150ms sur le canvas reel -> gain EXACTEMENT 5000 mR — couvre la regression du listener {once:true} reenregistre a chaque frame (corrigee, cf. index.html) qui aurait sur-compte le gain.",
            "couvre": [
                "clickGain"
            ],
            "version": "v1",
            "statut": "construit"
        }
    ]
}


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


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


def _kwargs(tmp_path, run_dir, exit_code=0):
    return dict(
        run_dir=run_dir,
        oracle_config=_oracle_config(tmp_path, "jeu", exit_code),
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
        mutation_baseline_runner=lambda argv, cwd: True,  # baseline verte stubée
    )


def _wire_solvability(g):
    """Complète un mini-jeu avec un harnais de solvabilité câblé (gate s10a
    check_solvability_wired) — même contenu que le shim `_complete_game_
    fixture_solvability` de conftest.py, qui ne couvre QUE les helpers nommés
    `_game_dir` (nom volontairement différent ici, cf. sa docstring)."""
    (g / "solvability.mjs").write_text(
        "const moves = [1];\nconst bot = { won: moves.length > 0 };\n"
        "if (!bot.won) process.exit(1);\n",
        encoding="utf-8")
    runner = g / "run-oracle.mjs"
    runner.write_text(
        runner.read_text(encoding="utf-8") + 'spawn("node", ["solvability.mjs"]);\n',
        encoding="utf-8")
    return g


def _game_dir_repo_relative(tmp_path, *, with_economy=True):
    """Mini-jeu sous <tmp_path>/GAMES/p3_alpha — même segmentation que le run
    réel (self.src_root == GAMES/p3_alpha), suffisant pour check_e2e_harness."""
    g = tmp_path / "GAMES" / "p3_alpha"
    g.mkdir(parents=True)
    (g / "state.mjs").write_text("export const solde_mR = 0;\n", encoding="utf-8")
    if with_economy:
        (g / "economy.mjs").write_text("export const gain_clic = 1;\n", encoding="utf-8")
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
    return _wire_solvability(g)


def _game_dir_bare(tmp_path):
    """Mini-jeu à plat sous <tmp_path>/game — fichiers logiques déjà NUS
    (convention paire 2), aucun préfixe repo-relatif à normaliser. Même
    gabarit que `_game_dir` de test_driver_mutation.py (fichiers de tests
    nommés par DEFAULT_TEST_ARGV, suite scellable)."""
    g = tmp_path / "game"
    g.mkdir()
    (g / "economy.mjs").write_text("export const gain_clic = 1;\n", encoding="utf-8")
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
    return _wire_solvability(g)


class StubExecutor:
    def __init__(self):
        self.calls = []

    def __call__(self, payload, decision, context):
        self.calls.append(payload.etape)
        return {"ok": True, "output": f"artefact {payload.etape}"}


def _write_wiremap(run_dir, data):
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "wiremap.json").write_text(json.dumps(data), encoding="utf-8")


def _s10a_detail(run_dir):
    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    return state, state["steps"]["s10a-oracle-code"]


# --- (a) chemins repo-relatifs normalisés, mutation appelée avec les BONS chemins --

def test_wiremap_repo_relative_normalisee_mutation_recoit_bons_chemins(
        tmp_path, offline, monkeypatch):
    import forge.driver as driver_mod
    monkeypatch.setattr(driver_mod, "_REPO_ROOT", tmp_path)

    g = _game_dir_repo_relative(tmp_path)
    run_dir = tmp_path / "run"
    _write_wiremap(run_dir, _WIREMAP_P3_ALPHA_EXCERPT)

    captured: list[Path] = []

    def _capture_runner(source_path, test_argv, *, cwd, **kw):
        captured.append(Path(source_path))
        return {"total": 1, "killed": 1, "survived": 0, "score": 1.0, "survivors": []}

    report = ForgeDriver("jeu", "p3_alpha-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g,
                         mutation_runner=_capture_runner,
                         **_kwargs(tmp_path, run_dir)).run()

    assert report["status"] == "DONE", report
    assert captured, "le runner mutation n'a jamais été appelé"
    for p in captured:
        # AVANT le correctif : chemin doublé (GAMES/p3_alpha/GAMES/p3_alpha/...),
        # jamais présent sur disque -- c'est exactement le FileNotFoundError du run réel.
        assert p.exists(), f"chemin encore doublé, introuvable sur disque : {p}"

    _state, s10a = _s10a_detail(run_dir)
    normalized = s10a["detail"].get("logic_files_normalized", {})
    assert normalized == {
        "GAMES/p3_alpha/state.mjs": "state.mjs",
        "GAMES/p3_alpha/economy.mjs": "economy.mjs",
    }, normalized

    # cohérence reçu/exécution : le scope signé reflète les chemins NORMALISÉS
    scope_included = s10a["detail"]["mutation"]["receipt"]["detail"]["logic_files"]
    assert set(scope_included) == {"state.mjs", "economy.mjs"}, scope_included


# --- (b) fichier introuvable après normalisation => BLOCKED nommé, jamais d'exception --

def test_fichier_introuvable_apres_normalisation_blocked_sans_exception(
        tmp_path, offline, monkeypatch):
    import forge.driver as driver_mod
    monkeypatch.setattr(driver_mod, "_REPO_ROOT", tmp_path)

    # economy.mjs volontairement ABSENT du disque : même après normalisation
    # du préfixe, le fichier reste introuvable.
    g = _game_dir_repo_relative(tmp_path, with_economy=False)
    run_dir = tmp_path / "run"
    _write_wiremap(run_dir, _WIREMAP_P3_ALPHA_EXCERPT)

    report = ForgeDriver("jeu", "p3_alpha-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g,
                         **_kwargs(tmp_path, run_dir)).run()

    # AUCUNE exception ne doit remonter (test lui-même n'aurait pas atteint ce
    # point) -- comportement fail-closed, régime BLOCKED motivé.
    assert report["status"] == "DONE", report
    assert report["software_verdict"] == "BLOCKED"
    _state, s10a = _s10a_detail(run_dir)
    assert s10a["status"] == "BLOCKED"
    reason = s10a["detail"]["reason"]
    assert "economy.mjs" in reason, reason
    assert "introuvable" in reason.lower(), reason
    # state.mjs, lui, EST normalisable -- la trace le montre malgré le BLOCKED
    assert s10a["detail"].get("logic_files_normalized", {}).get(
        "GAMES/p3_alpha/state.mjs") == "state.mjs"


# --- (c) non-régression : noms nus (convention paire 2) inchangés ------------------

def test_noms_nus_convention_paire2_inchanges(tmp_path, offline, monkeypatch):
    import forge.driver as driver_mod
    monkeypatch.setattr(driver_mod, "_REPO_ROOT", tmp_path)

    g = _game_dir_bare(tmp_path)
    run_dir = tmp_path / "run"

    captured: list[Path] = []

    def _capture_runner(source_path, test_argv, *, cwd, **kw):
        captured.append(Path(source_path))
        return {"total": 1, "killed": 1, "survived": 0, "score": 1.0, "survivors": []}

    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g,
                         logic_files=["economy.mjs"], mutation_runner=_capture_runner,
                         **_kwargs(tmp_path, run_dir)).run()

    assert report["status"] == "DONE", report
    assert report["software_verdict"] == "OK", report
    assert [p.name for p in captured] == ["economy.mjs"]
    _state, s10a = _s10a_detail(run_dir)
    # aucune réécriture n'a eu lieu -- clé absente, jamais un dict vide bruyant
    assert "logic_files_normalized" not in s10a["detail"]


# --- (d) exception non gérée dans une étape déterministe => HALT propre ------------

def test_exception_non_geree_etape_deterministe_devient_halt_propre(
        tmp_path, offline, monkeypatch):
    import forge.driver as driver_mod

    def _boom(*_a, **_kw):
        raise FileNotFoundError(
            "simulation : panne non gérée à l'intérieur d'une étape déterministe")

    monkeypatch.setattr(driver_mod, "run_mutation_for_game", _boom)

    g = _game_dir_bare(tmp_path)
    run_dir = tmp_path / "run"

    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g,
                         logic_files=["economy.mjs"],
                         **_kwargs(tmp_path, run_dir)).run()

    # le process N'A PAS crashé (aucune exception n'a traversé .run()) et le
    # rapport reflète honnêtement un HALT, jamais un DONE ni un crash silencieux.
    assert report["status"] == "HALTED", report
    assert "exception non gérée" in report.get("reason", ""), report
    assert "s10a-oracle-code" in report["reason"]

    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    assert state["run_status"] == "HALTED", state.get("run_status")
    assert "exception non gérée" in state.get("reason", ""), state.get("reason")
    assert state["steps"]["s10a-oracle-code"]["status"] == "BLOCKED"
    assert "reason" in state["steps"]["s10a-oracle-code"]["detail"]
