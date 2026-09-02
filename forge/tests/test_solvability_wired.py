"""Oracle de la garde structurelle solvabilité (P2) — check_solvability_wired.

Trou n°1 des oracles jeu : le contrat s9-build EXIGE la solvabilité en prose
(« solvability.mjs câblé dans run-oracle.mjs », « un bot joue et GAGNE ») mais
aucune garde mécanique ne la vérifiait — deux jeux injouables (survival_arena,
collect_runner) ont passé tous les gates verts. Ces tests prouvent le MIROIR
structurel de check_e2e_harness : absent / non câblé / coquille => rouge ;
présent + câblé => vert. NO_CLAIM_ALLOWED.
"""
from forge.static_oracles import check_solvability_wired


def _write(tmp_path, name, content):
    (tmp_path / name).write_text(content, encoding="utf-8")


def _e2e_ok(tmp_path):
    """Volet e2e câblé (hors sujet ici, présent pour un dossier réaliste)."""
    _write(tmp_path, "e2e.mjs",
           'import { chromium } from "playwright";\n'
           'await page.click("#restart");\n'
           'const s = window.__game;\n'
           'if (window.__game.over) show("#overlay");\n')


# --- rouge : solvability.mjs absent (la régression exacte mesurée) -----------------

def test_solvability_absente_rejetee(tmp_path):
    _e2e_ok(tmp_path)
    _write(tmp_path, "run-oracle.mjs",
           'import { spawn } from "node:child_process";\nspawn("node", ["e2e.mjs"]);\n')
    res = check_solvability_wired(tmp_path)
    assert res["passed"] is False
    assert res["checked"] is True
    assert any("solvability.mjs absent" in r for r in res["raisons"])


def test_run_oracle_absent_rejete(tmp_path):
    _write(tmp_path, "solvability.mjs", "const bot = play();\nif (!bot.won) process.exit(1);\n")
    res = check_solvability_wired(tmp_path)
    assert res["passed"] is False
    assert any("run-oracle.mjs absent" in r for r in res["raisons"])


# --- rouge : présente mais NON câblée dans run-oracle.mjs ---------------------------

def test_solvability_presente_mais_non_cablee_rejetee(tmp_path):
    _write(tmp_path, "run-oracle.mjs", 'import "./logic.test.mjs";\n')
    _write(tmp_path, "solvability.mjs", "const bot = play();\nif (!bot.won) process.exit(1);\n")
    res = check_solvability_wired(tmp_path)
    assert res["passed"] is False
    assert any("n'invoque pas solvability.mjs" in r for r in res["raisons"])


def test_mention_en_commentaire_ou_log_ne_cable_rien(tmp_path):
    # solvability.mjs mentionné SEULEMENT en commentaire/log -> non câblé.
    _write(tmp_path, "run-oracle.mjs",
           '// TODO: run("solvability.mjs") — désactivé, à lancer à la main\n'
           'console.log("(c) solvabilité: solvability.mjs");\n'
           '/* const r = await run("solvabilité", "solvability.mjs"); */\n'
           'import "./logic.test.mjs";\n')
    _write(tmp_path, "solvability.mjs", "const bot = play();\nif (!bot.won) process.exit(1);\n")
    res = check_solvability_wired(tmp_path)
    assert res["passed"] is False
    assert any("n'invoque pas solvability.mjs" in r for r in res["raisons"])


# --- rouge : câblée mais fichier vide (coquille) ------------------------------------

def test_solvability_vide_ou_commentaires_seuls_rejetee(tmp_path):
    _write(tmp_path, "run-oracle.mjs", 'spawn("node", ["solvability.mjs"]);\n')
    _write(tmp_path, "solvability.mjs", "// coquille : rien d'exécutable\n   \n")
    res = check_solvability_wired(tmp_path)
    assert res["passed"] is False
    assert any("vide ou illisible" in r for r in res["raisons"])


# --- vert : présente ET câblée (les deux styles réels du repo) ----------------------

def test_solvability_cablee_via_spawn_acceptee(tmp_path):
    _write(tmp_path, "run-oracle.mjs",
           'import { spawn } from "node:child_process";\n'
           'spawn("node", ["solvability.mjs"]);\n')
    _write(tmp_path, "solvability.mjs", "const bot = play();\nif (!bot.won) process.exit(1);\n")
    res = check_solvability_wired(tmp_path)
    assert res["passed"] is True
    assert res["checked"] is True
    assert res["raisons"] == []


def test_solvability_cablee_via_helper_run_acceptee(tmp_path):
    # Style réel des jeux du repo (GAMES/breakout, collect_runner, kb_tactics).
    _write(tmp_path, "run-oracle.mjs",
           'const solvResult = await run("solvabilité", "solvability.mjs");\n')
    _write(tmp_path, "solvability.mjs", "const bot = play();\nif (!bot.won) process.exit(1);\n")
    res = check_solvability_wired(tmp_path)
    assert res["passed"] is True
    assert res["raisons"] == []


# --- limite connue DOCUMENTÉE (même niveau de strictesse que _E2E_WIRED) ------------

def test_limite_connue_token_dans_chaine_d_execution_acceptee(tmp_path):
    """Assumé (miroir exact de la garde e2e, ni plus ni moins strict) : un token
    dans une chaîne littérale sur une ligne portant un verbe d'exécution reste
    comptable. Ce test FIGE la limite pour qu'un futur durcissement soit un choix
    conscient, pas un accident."""
    _write(tmp_path, "run-oracle.mjs",
           'run(console.log("solvability.mjs"));\n')
    _write(tmp_path, "solvability.mjs", "const bot = play();\nif (!bot.won) process.exit(1);\n")
    res = check_solvability_wired(tmp_path)
    assert res["passed"] is True  # limite assumée — builders non adversariaux + HumanGate
