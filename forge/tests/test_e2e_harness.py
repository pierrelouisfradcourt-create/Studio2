"""Garde structurelle e2e (C3) — rejette un e2e absent / non câblé / coquille."""
from pathlib import Path

from forge.static_oracles import check_e2e_harness

REPO_ROOT = Path(__file__).resolve().parents[2]


def _write(d: Path, name: str, txt: str) -> None:
    (d / name).write_text(txt, encoding="utf-8")


def test_legacy_harness_reel_passe():
    # Le jeu legacy a un vrai e2e Playwright câblé dans run-oracle -> PASS.
    res = check_e2e_harness(REPO_ROOT / "GAMES" / "collect_runner_legacy")
    assert res["passed"] is True, res["raisons"]


def test_reforge_sans_e2e_rejetee():
    # Les re-forges fraîches n'ont pas d'e2e.mjs -> REJET (la régression mesurée).
    res = check_e2e_harness(REPO_ROOT / "GAMES" / "collect_runner_r1")
    assert res["passed"] is False
    assert any("e2e.mjs absent" in r for r in res["raisons"])


def test_stub_e2e_rejetee(tmp_path):
    # e2e.mjs coquille : imprime PASS sans lancer de navigateur ni piloter -> REJET.
    _write(tmp_path, "run-oracle.mjs", 'import "./e2e.mjs";\n')
    _write(tmp_path, "e2e.mjs", 'console.log("RESULT: PASS");\n')
    res = check_e2e_harness(tmp_path)
    assert res["passed"] is False
    assert any("navigateur" in r for r in res["raisons"])
    assert any("entrée" in r for r in res["raisons"])
    assert any("état" in r for r in res["raisons"])


def test_e2e_present_mais_non_cable_rejete(tmp_path):
    # Un vrai e2e existe mais run-oracle ne l'appelle jamais -> le gate ne le lance pas.
    _write(tmp_path, "run-oracle.mjs", 'import "./logic.test.mjs";\n')
    _write(
        tmp_path,
        "e2e.mjs",
        'import { chromium } from "playwright";\n'
        'await page.keyboard.down("ArrowRight");\n'
        'if (window.__game.x < 0) throw new Error("x");\n'
        'if (!document.querySelector("#overlay")) throw new Error("o");\n'
        'if (!document.querySelector("#restart")) throw new Error("r");\n',
    )
    res = check_e2e_harness(tmp_path)
    assert res["passed"] is False
    assert any("n'invoque pas e2e.mjs" in r for r in res["raisons"])


def test_e2e_reel_minimal_passe(tmp_path):
    # e2e câblé, navigateur, entrée, >=3 observations d'état -> PASS.
    _write(tmp_path, "run-oracle.mjs", 'import "./e2e.mjs";\n')
    _write(
        tmp_path,
        "e2e.mjs",
        'import { chromium } from "playwright";\n'
        'await page.keyboard.press("Space");\n'
        'if (window.__game.over) throw new Error("a");\n'
        'if (window.__game.coins < 0) throw new Error("b");\n'
        'await page.click("#restart");\n',
    )
    res = check_e2e_harness(tmp_path)
    assert res["passed"] is True, res["raisons"]


def test_run_oracle_via_helper_run_cable_ok(tmp_path):
    # Câblage réel via un helper run("label", "e2e.mjs") — comme le legacy.
    _write(tmp_path, "run-oracle.mjs", 'const r = await run("e2e Playwright", "e2e.mjs", {});\n')
    _write(
        tmp_path,
        "e2e.mjs",
        'import { chromium } from "playwright";\n'
        'await page.keyboard.down("ArrowRight");\n'
        'const s = await page.evaluate(() => window.__game);\n'
        'if (!document.querySelector("#overlay")) throw new Error("o");\n'
        'await page.click("#restart");\n',
    )
    res = check_e2e_harness(tmp_path)
    assert res["passed"] is True, res["raisons"]


def test_wiring_en_commentaire_rejete(tmp_path):
    # e2e.mjs mentionné SEULEMENT en commentaire/log dans run-oracle -> non câblé.
    _write(
        tmp_path,
        "run-oracle.mjs",
        '// TODO: run("e2e.mjs") — désactivé, à lancer à la main\n'
        'console.log("(b) e2e Playwright: e2e.mjs");\n'
        'await run("logic", "logic.test.mjs");\n',
    )
    _write(
        tmp_path,
        "e2e.mjs",
        'import { chromium } from "playwright";\n'
        'await page.keyboard.press("Space");\n'
        'if (window.__game.over) throw new Error("a");\n'
        'if (window.__game.coins < 0) throw new Error("b");\n'
        'await page.click("#restart");\n',
    )
    res = check_e2e_harness(tmp_path)
    assert res["passed"] is False
    assert any("n'invoque pas e2e.mjs" in r for r in res["raisons"])


def test_tokens_en_commentaire_rejetes(tmp_path):
    # e2e.mjs dont les tokens navigateur/entrée/état ne vivent QUE dans des
    # commentaires -> après strip, coquille détectée (anti-gaming #2).
    _write(tmp_path, "run-oracle.mjs", 'import "./e2e.mjs";\n')
    _write(
        tmp_path,
        "e2e.mjs",
        '// chromium playwright — faux e2e\n'
        '// page.keyboard.press("Space")\n'
        '/* window.__game #overlay #restart */\n'
        'console.log("RESULT: PASS");\n',
    )
    res = check_e2e_harness(tmp_path)
    assert res["passed"] is False
    assert any("navigateur" in r for r in res["raisons"])
    assert any("état" in r for r in res["raisons"])


def test_borne_deux_observations_rejete(tmp_path):
    # Exactement 2 observations d'état (K-1) -> REJET (garde l'off-by-one honnête).
    _write(tmp_path, "run-oracle.mjs", 'import "./e2e.mjs";\n')
    _write(
        tmp_path,
        "e2e.mjs",
        'import { chromium } from "playwright";\n'
        'await page.keyboard.press("Space");\n'
        'if (window.__game.over) throw new Error("a");\n'
        'await page.click("#restart");\n',
    )
    res = check_e2e_harness(tmp_path)
    assert res["passed"] is False
    assert any("n'observe pas assez" in r for r in res["raisons"])


def test_e2e_vide_rejete(tmp_path):
    # e2e.mjs présent mais vide -> REJET explicite "vide ou illisible".
    _write(tmp_path, "run-oracle.mjs", 'import "./e2e.mjs";\n')
    _write(tmp_path, "e2e.mjs", "   \n")
    res = check_e2e_harness(tmp_path)
    assert res["passed"] is False
    assert any("vide ou illisible" in r for r in res["raisons"])
