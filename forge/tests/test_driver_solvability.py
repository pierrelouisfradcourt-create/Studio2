"""Oracle du câblage driver de la garde solvabilité (P2) — s10a jeu.

La garde check_solvability_wired contribue au gate s10a AU MÊME TITRE que la
garde e2e : un JEU sans solvability.mjs câblé => reçu code FAIL avec raisons
(alimente l'escalade), jamais un vert. Le résultat est exposé dans le detail du
reçu signé comme e2e l'est. Leçon survival_arena/collect_runner : deux jeux
injouables avaient passé tous les gates verts. NO_CLAIM_ALLOWED.

NB : les helpers de jeu portent des noms ≠ `_game_dir` pour rester HORS du shim
de complétion de fixture du conftest (qui ajoute la solvabilité aux fixtures
héritées) — ici l'ABSENCE de solvabilité est précisément l'objet du test.
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


def _jeu_sans_solvabilite(tmp_path):
    """Mini-jeu satisfaisant la garde e2e (check_e2e_harness) mais SANS solvabilité
    — exactement le profil des deux jeux injouables passés verts."""
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


def _jeu_complet(tmp_path):
    """Mini-jeu complet : e2e câblé ET solvabilité câblée (contrôle positif)."""
    g = _jeu_sans_solvabilite(tmp_path)
    # `won` CALCULÉ (pas un littéral `true`) : depuis R1 (check_harness_no_hardcoded_flags,
    # câblé au driver s10a), un flag de succès écrit en dur rougirait CE contrôle
    # positif lui-même.
    (g / "solvability.mjs").write_text(
        "const moves = [1];\nconst bot = { won: moves.length > 0 };\n"
        "if (!bot.won) process.exit(1);\n",
        encoding="utf-8")
    runner = g / "run-oracle.mjs"
    runner.write_text(
        runner.read_text(encoding="utf-8") + 'spawn("node", ["solvability.mjs"]);\n',
        encoding="utf-8")
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
        mutation_baseline_runner=lambda argv, cwd: True,  # baseline verte stubée
    )


def _verdict(run_dir):
    return json.loads((run_dir / "verdict.json").read_text(encoding="utf-8"))


# --- rouge : jeu sans solvabilité => reçu code FAIL, alimente l'escalade -----------

def test_jeu_sans_solvabilite_fail_et_escalade(tmp_path, offline):
    """LE trou fermé : e2e vert + mutation verte + oracle code vert, mais AUCUN
    harnais de solvabilité => s10a FAIL avec raisons (jamais un vert), et le FAIL
    alimente la boucle d'escalade comme tout rouge mécanique."""
    run_dir = tmp_path / "run"
    g = _jeu_sans_solvabilite(tmp_path)
    ex = StubExecutor()
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=ex, src_root=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["software_verdict"] == "FAIL"
    assert report["decision"] == "BLOCKED"

    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    s10a = state["steps"]["s10a-oracle-code"]
    assert s10a["status"] == "FAIL"
    solv = s10a["detail"]["solvability"]
    assert solv["passed"] is False
    assert any("solvability.mjs absent" in r for r in solv["raisons"])
    # la garde e2e, elle, était verte : c'est BIEN la solvabilité qui gate ici
    assert s10a["detail"]["e2e"]["passed"] is True
    # le FAIL alimente l'escalade (plusieurs tentatives s9-build, comme un rouge e2e)
    s9_calls = [c for c in ex.calls if c[0] == "s9-build"]
    assert len(s9_calls) > 1

    # exposé dans le reçu signé du verdict, comme e2e l'est
    code = _verdict(run_dir)["oracles"]["code"]
    assert code["status"] == "FAIL"
    assert code["detail"]["solvability"]["passed"] is False


def test_jeu_solvabilite_presente_mais_non_cablee_fail(tmp_path, offline):
    """solvability.mjs existe mais run-oracle.mjs ne l'invoque jamais : le volet
    solvabilité est absent du gate => FAIL avec la raison exacte."""
    run_dir = tmp_path / "run"
    g = _jeu_sans_solvabilite(tmp_path)
    (g / "solvability.mjs").write_text(
        "const bot = { won: true };\nif (!bot.won) process.exit(1);\n",
        encoding="utf-8")  # présent, mais run-oracle.mjs ne le lance pas
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["software_verdict"] == "FAIL"
    code = _verdict(run_dir)["oracles"]["code"]
    assert code["status"] == "FAIL"
    assert any("n'invoque pas solvability.mjs" in r
               for r in code["detail"]["solvability"]["raisons"])


# --- vert : contrôle positif (jeu complet inchangé par la nouvelle garde) ----------

def test_jeu_complet_reste_vert_et_expose_la_garde(tmp_path, offline):
    """Un jeu avec e2e ET solvabilité câblés verdit comme avant, et le reçu signé
    expose la garde solvabilité verte (auditable à HumanGate, comme e2e)."""
    run_dir = tmp_path / "run"
    g = _jeu_complet(tmp_path)
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["status"] == "DONE"
    assert report["software_verdict"] == "OK"
    assert report["decision"] == "HUMANGATE_READY"
    code = _verdict(run_dir)["oracles"]["code"]
    assert code["status"] == "OK"
    assert code["detail"]["solvability"] == {"passed": True, "raisons": [], "checked": True}
    assert code["detail"]["e2e"]["passed"] is True
