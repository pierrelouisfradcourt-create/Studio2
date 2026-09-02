"""Oracle anti-théâtre des harnais (R1, FORGE_V2_CONSOLIDATION.md §4-A).

Pattern bi-projet constaté (audit P1) : un harnais/oracle qui ÉCRIT son statut de
succès en LITTÉRAL (`passed: true`) au lieu de le CALCULER est un théâtre d'oracle.
Miroir structurel de check_e2e_harness/check_solvability_wired : {passed, raisons[]},
jamais d'exception sur entrée malformée. NO_CLAIM_ALLOWED.
"""
from forge.static_oracles import check_harness_no_hardcoded_flags


def _write(root, rel, code):
    p = root / rel
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(code, encoding="utf-8")


# --- rouge : fixture théâtrale (flag codé en dur) ----------------------------------

def test_flag_hardcode_object_literal_rejete(tmp_path):
    _write(tmp_path, "run-oracle.mjs",
           "const result = { allMovesLegal: true, passed: true };\n"
           "console.log(JSON.stringify(result));\n")
    rep = check_harness_no_hardcoded_flags(tmp_path)
    assert rep["passed"] is False
    assert any("allMovesLegal" in r for r in rep["raisons"])
    assert any("passed" in r for r in rep["raisons"])


def test_flag_hardcode_assignment_rejete(tmp_path):
    _write(tmp_path, "solvability.mjs", "let ok;\nok = true;\nif (!ok) process.exit(1);\n")
    rep = check_harness_no_hardcoded_flags(tmp_path)
    assert rep["passed"] is False
    assert any("ok" in r for r in rep["raisons"])


def test_flag_hardcode_dans_harness_dir_rejete(tmp_path):
    _write(tmp_path, "harness/check.mjs", "export const won = true;\n")
    rep = check_harness_no_hardcoded_flags(tmp_path)
    assert rep["passed"] is False
    assert any("won" in r for r in rep["raisons"])
    assert any("harness" in r for r in rep["raisons"])


# --- vert : harnais sain (expression calculée) -------------------------------------

def test_flag_calcule_accepte(tmp_path):
    _write(tmp_path, "run-oracle.mjs",
           "const allMovesLegal = moves.every(isLegal);\n"
           "const result = { allMovesLegal, passed: allMovesLegal && bot.won };\n"
           "console.log(JSON.stringify(result));\n")
    rep = check_harness_no_hardcoded_flags(tmp_path)
    assert rep["passed"] is True
    assert rep["raisons"] == []


def test_comparaison_stricte_nest_pas_confondue_avec_affectation(tmp_path):
    # `ok === true` est une COMPARAISON (calcul), pas une affectation en dur.
    _write(tmp_path, "solvability.mjs",
           "const ok = bot.moves.length > 0;\nif (ok === true) { report(ok); }\n")
    rep = check_harness_no_hardcoded_flags(tmp_path)
    assert rep["passed"] is True
    assert rep["raisons"] == []


# --- commentaires ignorés -----------------------------------------------------------

def test_commentaires_ignores(tmp_path):
    _write(tmp_path, "solvability.mjs",
           "// ancien flag de debug: passed: true (retiré)\n"
           "/* legacy: ok: true */\n"
           "const passed = bot.won;\nif (!passed) process.exit(1);\n")
    rep = check_harness_no_hardcoded_flags(tmp_path)
    assert rep["passed"] is True
    assert rep["raisons"] == []


# --- aucun harnais présent : PASS vacueux (rôle des gardes soeurs) ------------------

def test_aucun_harnais_present_pass_vacueux(tmp_path):
    rep = check_harness_no_hardcoded_flags(tmp_path)
    assert rep["passed"] is True
    assert rep["raisons"] == []
