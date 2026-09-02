"""Oracle du branchement `propose_brick` dans le driver (contrat
v4-brancher-propose-brick, 2026-07-27) — ferme le maillon mesuré par
docs/audit/ANALYSE_DEPOT_GAME_LOOP_2026-07-26.md : `studio_link.propose_brick`
(studio_link.py:563) existe, testé, exposé en CLI, mais n'avait AUCUN appelant
automatique dans driver.py (`grep -c propose_brick forge/driver.py`
rendait 0 avant ce correctif ; `EVIDENCE/reports/forge_brick_proposals.jsonl`
n'existait jamais).

Prédicat du dépôt (docs/audit/ANALYSE_DEPOT_GAME_LOOP_2026-07-26.md §4a) :
une proposition n'est écrite QUE si le reçu de l'oracle code (re-vérifié par
verify_run) est OK — jamais sur FAIL/BLOCKED. PROPOSE-ONLY strict : jamais
d'écriture dans knowledge_base/. Best-effort strict : une exception à
l'écriture n'altère ni le statut de l'étape ni celui du run. NO_CLAIM_ALLOWED.
"""
import json
import sys
from pathlib import Path

import pytest

from forge.driver import ForgeDriver


# --- utilitaires (autonomes, même convention que test_driver_mutation.py) ---------

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
    """Mini-jeu (src_root) satisfaisant la garde e2e structurelle
    (check_e2e_harness) — même patron ET MÊME NOM que
    test_driver_mutation.py::_game_dir : conftest.py::_complete_game_fixture_solvability
    (fixture autouse) ne complète le harnais de solvabilité QUE pour un helper
    de module nommé EXACTEMENT `_game_dir` (getattr(request.module, "_game_dir")) —
    un autre nom (ex. `_game_src`) laisse la garde solvability rouge et fait
    tomber tout run en FAIL, indépendamment de propose_brick."""
    g = tmp_path / "game_src"
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


def _charter_dir(tmp_path, brick_id="game_loop"):
    """00_CHARTER/game_contract.yaml (`budget.adds`) + 09_WIREMAP/wiremap.json
    (`lines[].system_parent`/`address`) — la source RÉELLE du brick_id et du
    chemin proposé, même structure que GAMES/pong/00_CHARTER/game_contract.yaml
    et GAMES/pong/09_WIREMAP/wiremap.json. C'est la valeur passée au paramètre
    `game_dir=` du driver — DISTINCTE de `src_root` (`_game_dir` ci-dessus)."""
    gd = tmp_path / "charter_dir"
    (gd / "00_CHARTER").mkdir(parents=True)
    (gd / "09_WIREMAP").mkdir(parents=True)
    (gd / "00_CHARTER" / "game_contract.yaml").write_text(
        f"schema_version: 1\ngame_id: jeu\nbudget:\n  reuses: []\n  adds: [{brick_id}]\n",
        encoding="utf-8",
    )
    (gd / "09_WIREMAP" / "wiremap.json").write_text(
        json.dumps({
            "systems": [{"id": brick_id, "category": "system", "allowed_deps": []}],
            "lines": [
                {"id": "core.main_loop", "system_parent": brick_id,
                 "address": f"05_SYSTEMS/{brick_id}/",
                 "fichiers": [{"path": f"05_SYSTEMS/{brick_id}/loop.mjs"}]},
            ],
        }),
        encoding="utf-8",
    )
    return gd


def _all_killed(source_path, test_argv, *, cwd, **kw):
    return {"total": 4, "killed": 4, "survived": 0, "score": 1.0, "survivors": []}


def _one_survivor(source_path, test_argv, *, cwd, **kw):
    return {"total": 4, "killed": 3, "survived": 1, "score": 0.75,
            "survivors": [{"name": "ge->gt", "line": 2}]}


class StubExecutor:
    def __init__(self):
        self.calls = []

    def __call__(self, payload, decision, context):
        self.calls.append((payload.etape, context.get("model_override")))
        return {"ok": True, "output": f"artefact {payload.etape}"}


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


def _kwargs(tmp_path, run_dir, game_dir, brick_proposals_path, exit_code=0):
    return dict(
        run_dir=run_dir,
        oracle_config=_oracle_config(tmp_path, "jeu", exit_code),
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
        mutation_baseline_runner=lambda argv, cwd: True,  # baseline verte stubée
        game_dir=game_dir,
        brick_proposals_path=brick_proposals_path,
    )


def _rows(path: Path) -> list[dict]:
    if not path.exists():
        return []
    return [json.loads(l) for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]


# --- (a) run vert, adds:[X] -> exactement une proposition pour X ------------------

def test_run_vert_avec_adds_depose_une_proposition_de_brique(tmp_path, offline):
    run_dir = tmp_path / "run"
    src = _game_dir(tmp_path)
    game_dir = _charter_dir(tmp_path, brick_id="game_loop")
    props = tmp_path / "brick_prop.jsonl"

    report = ForgeDriver(
        "jeu", "jeu-1", profile="micro", is_game=True, executor=StubExecutor(),
        src_root=src, logic_files=["logic.mjs"], mutation_runner=_all_killed,
        **_kwargs(tmp_path, run_dir, game_dir, props),
    ).run()

    assert report["status"] == "DONE"
    assert report["software_verdict"] == "OK"
    code = json.loads((run_dir / "verdict.json").read_text(encoding="utf-8"))["oracles"]["code"]
    assert code["status"] == "OK"

    rows = _rows(props)
    assert len(rows) == 1, f"attendu exactement 1 proposition, obtenu {rows!r}"
    row = rows[0]
    assert row["type"] == "brick"
    assert row["brick_id"] == "game_loop"
    assert row["project"] == "jeu"
    assert row["run_id"] == "jeu-1"
    assert row["status"] == "PROPOSED"
    assert row["kind"] == "system"
    assert "game_loop" in row["path"]

    # PROPOSE-ONLY : jamais d'écriture dans knowledge_base/ ni de catalogue local
    assert not (tmp_path / "catalog.json").exists()
    assert not (tmp_path / "knowledge_base").exists()


# --- (b) run avec reçu code FAIL/BLOCKED -> AUCUNE proposition --------------------

def test_run_code_fail_survivant_non_trie_ne_depose_aucune_proposition(tmp_path, offline):
    """Cas réel pong_r2 : survivant mutation non trié -> reçu code FAIL après
    escalade bornée (même scénario que
    test_driver_mutation.py::test_survivant_non_justifie_fail_et_escalade_bornee).
    Le prédicat interdit toute proposition sur un code non prouvé."""
    run_dir = tmp_path / "run"
    src = _game_dir(tmp_path)
    game_dir = _charter_dir(tmp_path, brick_id="game_loop")
    props = tmp_path / "brick_prop.jsonl"

    report = ForgeDriver(
        "jeu", "jeu-1", profile="micro", is_game=True, executor=StubExecutor(),
        src_root=src, logic_files=["logic.mjs"], mutation_runner=_one_survivor,
        **_kwargs(tmp_path, run_dir, game_dir, props),
    ).run()

    assert report["status"] == "DONE"
    assert report["software_verdict"] == "FAIL"
    code = json.loads((run_dir / "verdict.json").read_text(encoding="utf-8"))["oracles"]["code"]
    assert code["status"] == "FAIL"

    assert not props.exists(), "aucune proposition ne doit être écrite sur un code FAIL"


def test_run_code_blocked_ne_depose_aucune_proposition(tmp_path, offline):
    """Preuve mutation impossible (ni logic_files ni wiremap connu du fichier de
    jeu source) -> reçu code BLOCKED -> aucune proposition, même discipline que
    FAIL (le prédicat porte sur `!= OK`, pas seulement `== FAIL`)."""
    run_dir = tmp_path / "run"
    src = _game_dir(tmp_path)
    game_dir = _charter_dir(tmp_path, brick_id="game_loop")
    props = tmp_path / "brick_prop.jsonl"

    report = ForgeDriver(
        "jeu", "jeu-1", profile="micro", is_game=True, executor=StubExecutor(),
        src_root=src, mutation_runner=_all_killed,  # logic_files OMIS exprès
        **_kwargs(tmp_path, run_dir, game_dir, props),
    ).run()

    assert report["software_verdict"] == "BLOCKED"
    assert not props.exists()


# --- (c) robustesse : une écriture qui casse reste best-effort --------------------

def test_ecriture_proposition_qui_leve_reste_best_effort(tmp_path, offline, monkeypatch):
    """Simule un `propose_brick` qui lève (ex. disque plein) — le statut de
    l'étape s12-verdict et le software_verdict du run restent IDENTIQUES à la
    version verte, même garantie que record_telemetry/_journal_error."""
    run_dir = tmp_path / "run"
    src = _game_dir(tmp_path)
    game_dir = _charter_dir(tmp_path, brick_id="game_loop")
    props = tmp_path / "brick_prop.jsonl"

    import forge.driver as driver_mod

    def _boom(*a, **kw):
        raise OSError("disque plein (simulé)")

    monkeypatch.setattr(driver_mod, "propose_brick", _boom)

    report = ForgeDriver(
        "jeu", "jeu-1", profile="micro", is_game=True, executor=StubExecutor(),
        src_root=src, logic_files=["logic.mjs"], mutation_runner=_all_killed,
        **_kwargs(tmp_path, run_dir, game_dir, props),
    ).run()

    assert report["status"] == "DONE"
    assert report["software_verdict"] == "OK"  # inchangé malgré l'échec d'écriture
    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    assert state["steps"]["s12-verdict"]["status"] == "OK"
    assert not props.exists()  # l'écriture simulée a échoué, rien n'est resté sur disque
