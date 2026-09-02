"""Intégration : un vrai run_mutation_test alimente check_mutation_gate de bout en bout."""
import shutil

import pytest

from forge.mutation import run_mutation_test
from forge.static_oracles import check_mutation_gate

pytestmark = pytest.mark.skipif(shutil.which("node") is None, reason="node absent")


def _mini_jeu(tmp_path):
    # Source mutable (a >= b) + test FAIBLE (n'assère rien) => tous les mutants survivent.
    (tmp_path / "game.mjs").write_text(
        "export function cmp(a, b) { return a >= b; }\n", encoding="utf-8"
    )
    (tmp_path / "weak.test.mjs").write_text(
        'import { test } from "node:test";\ntest("noop", () => {});\n', encoding="utf-8"
    )


def test_tests_faibles_laissent_survivre_puis_gate_rouge(tmp_path):
    _mini_jeu(tmp_path)
    res = run_mutation_test(tmp_path / "game.mjs", ["node", "--test", "weak.test.mjs"],
                            cwd=tmp_path, timeout=30)
    assert res["total"] >= 1, "le mutateur doit produire au moins un mutant sur '>='"
    assert res["survived"] >= 1, "un test faible ne tue aucun mutant"
    out = check_mutation_gate(res, None)
    assert out["checked"] is True
    assert out["passed"] is False
    assert out["survivants_non_tries"], "les survivants réels doivent remonter dans le gate"


def test_meme_survivants_tries_font_passer_le_gate(tmp_path):
    # Réconciliation : on TRIE les survivants réels du run précédent => gate PASS.
    _mini_jeu(tmp_path)
    res = run_mutation_test(tmp_path / "game.mjs", ["node", "--test", "weak.test.mjs"],
                            cwd=tmp_path, timeout=30)
    triage = [{"name": s["name"], "line": s["line"], "justification": "équivalent (test factice)"}
              for s in res["survivors"]]
    out = check_mutation_gate(res, triage)
    assert out["passed"] is True
    assert out["survivants_non_tries"] == []


def test_test_fort_tue_le_mutant_gate_vert_par_kill(tmp_path):
    # Chemin « 100% tué » RÉEL (pas via triage) : un test fort tue l'unique mutant '>=' -> '>'.
    (tmp_path / "game.mjs").write_text(
        "export function cmp(a, b) { return a >= b; }\n", encoding="utf-8"
    )
    (tmp_path / "strong.test.mjs").write_text(
        'import { test } from "node:test";\nimport assert from "node:assert";\n'
        'import { cmp } from "./game.mjs";\n'
        'test("borne inclusive", () => { assert.strictEqual(cmp(1, 1), true); });\n',
        encoding="utf-8",
    )
    res = run_mutation_test(tmp_path / "game.mjs", ["node", "--test", "strong.test.mjs"],
                            cwd=tmp_path, timeout=30)
    assert res["total"] >= 1 and res["survived"] == 0, res
    out = check_mutation_gate(res, None)   # aucun triage nécessaire : tout est tué
    assert out["passed"] is True and out["checked"] is True
