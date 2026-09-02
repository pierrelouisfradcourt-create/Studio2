"""PHASE ③ ÉTAPE 3 (go Pierre 2026-07-28) — le CHEMIN D'EXÉCUTION du régime
DESCRIPTEUR du CONTRAT_PREUVE_MUTATION_V1.md (FIGÉ). `evaluate_proof_descriptor`
(déjà livré, moteur PUR) ne fait aucune exécution ; ce fichier couvre les
briques qui EXÉCUTENT réellement (`run_mutation_from_descriptor`), ÉMETTENT
(`emit_descriptor_mutation_receipt`) et VÉRIFIENT (`verify_descriptor_mutation_
receipt`) une preuve mutation par descripteur — pendant DÉDIÉ du régime
historique (`run_mutation_for_game`/`emit_mutation_receipt`/
`verify_mutation_receipt`), jamais une fusion des deux (décision Pierre
2026-07-28).

Aucune écriture sous `GAMES/**` : tout vit en `tmp_path`. `test_mutation_
regime_coexistence.py` (zone protégée) n'est ni modifié ni importé ici.

claim_verdict: NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
from dataclasses import asdict

from forge.mutation_proof import (
    emit_descriptor_mutation_receipt,
    run_mutation_from_descriptor,
    verify_descriptor_mutation_receipt,
)

# Contenu source portant EXACTEMENT 3 mutants réels (mesurables par
# `forge.mutation.generate_mutants`, indépendamment de tout stub) :
# ">=" (1), "&&" (1), "<=" (1) -- aucun chevauchement avec les _WORD_RULES.
_SOURCE = "export const ok = (1 >= 0) && (2 <= 3);\n"


def _game(tmp_path, *, n_mutants_survive=0):
    g = tmp_path / "game"
    g.mkdir()
    (g / "logic.mjs").write_text(_SOURCE, encoding="utf-8")
    (g / "logic.test.mjs").write_text("// suite\n", encoding="utf-8")
    (g / "09_WIREMAP").mkdir()
    (g / "09_WIREMAP" / "wiremap.json").write_text(
        json.dumps({"lines": [
            {"fichiers": [{"path": "logic.mjs", "category": "system"}]},
        ]}),
        encoding="utf-8",
    )
    return g


def _wiremap(g):
    return json.loads((g / "09_WIREMAP" / "wiremap.json").read_text(encoding="utf-8"))


def _proof(command=None, *, binary_ref="node", max_mutants=200, total_timeout_s=900):
    return {
        "schema_version": 1,
        "runtime": "rules",
        "mutation": {
            "categories_mutables": ["system"],
            "categories_exclues": ["system.adapter"],
            "command": command or ["node", "--test", "logic.test.mjs"],
            "cwd": "GAMES/jeu",
            "binary_ref": binary_ref,
            "expects_exit_zero": True,
            "budget": {"max_mutants": max_mutants, "timeout_per_mutant_s": 30,
                       "total_timeout_s": total_timeout_s},
            "seals": {"wrapper": [], "test_scripts": ["logic.test.mjs"]},
        },
    }


def _contract(proof):
    return {"schema_version": 1, "game_id": "jeu", "runtimes": ["rules"], "proof": proof}


def _all_killed_runner(source_path, argv, *, cwd, timeout=None, **kw):
    return {"total": 3, "killed": 3, "survived": 0, "survivors": []}


def _one_survivor_runner(source_path, argv, *, cwd, timeout=None, **kw):
    return {"total": 3, "killed": 2, "survived": 1,
            "survivors": [{"name": "ge->gt", "line": 1}]}


def _true_baseline(argv, cwd):
    return True


def _false_baseline(argv, cwd):
    return False


# =====================================================================================
# 1. Exécuteur pur (run_mutation_from_descriptor) -- vecteurs de base.
# =====================================================================================

def test_executeur_mesure_les_vrais_mutants_et_execute(tmp_path):
    g = _game(tmp_path)
    proof = _proof()
    result = run_mutation_from_descriptor(
        g, proof, _wiremap(g), mutant_runner=_all_killed_runner,
        baseline_runner=_true_baseline,
    )
    assert result["baseline_ok"] is True
    assert result["mutants_generes"] == 3   # généré par generate_mutants, pas par le stub
    assert result["mutants_executes"] == 3
    assert result["killed"] == 3
    assert result["budget_exceeded"] is False
    assert result["command_executee"] == ["node", "--test", "logic.test.mjs"]
    assert result["fichiers_sans_mutant"] == []


def test_executeur_baseline_rouge_mutation_non_lancee(tmp_path):
    g = _game(tmp_path)
    proof = _proof()
    result = run_mutation_from_descriptor(
        g, proof, _wiremap(g), mutant_runner=_all_killed_runner,
        baseline_runner=_false_baseline,
    )
    assert result["baseline_ok"] is False
    assert result["mutants_generes"] == 0
    assert result["mutants_executes"] == 0


def test_executeur_budget_depasse_rien_execute(tmp_path):
    """§4 : dépassement -> RIEN n'est exécuté (jamais une troncature silencieuse)."""
    g = _game(tmp_path)
    proof = _proof(max_mutants=1)   # 3 mutants réels > budget de 1
    result = run_mutation_from_descriptor(
        g, proof, _wiremap(g), mutant_runner=_all_killed_runner,
        baseline_runner=_true_baseline,
    )
    assert result["budget_exceeded"] is True
    assert result["mutants_generes"] == 3
    assert result["mutants_executes"] == 0


def test_executeur_substitution_bin_resout_le_symbole(tmp_path):
    g = _game(tmp_path)
    proof = _proof(command=["<bin:node>", "--test", "logic.test.mjs"], binary_ref="node")

    def _resolver(ref):
        assert ref == "node"
        return {"path": "C:/fake/node.exe", "version": "20.0.0-fake"}

    result = run_mutation_from_descriptor(
        g, proof, _wiremap(g), mutant_runner=_all_killed_runner,
        baseline_runner=_true_baseline, binary_resolver=_resolver,
    )
    assert result["command_declaree"] == ["<bin:node>", "--test", "logic.test.mjs"]
    assert result["command_executee"] == ["C:/fake/node.exe", "--test", "logic.test.mjs"]
    assert result["binaire"] == {"path": "C:/fake/node.exe", "version": "20.0.0-fake"}


def test_executeur_total_timeout_arrete_en_cours_de_route(tmp_path):
    """Deuxième fichier logique mutable -> l'horloge injectée simule un
    dépassement de `total_timeout_s` APRÈS le premier fichier : le second
    fichier compte dans mutants_generes mais pas dans mutants_executes."""
    g = _game(tmp_path)
    (g / "logic2.mjs").write_text(_SOURCE, encoding="utf-8")
    wiremap = {"lines": [{"fichiers": [
        {"path": "logic.mjs", "category": "system"},
        {"path": "logic2.mjs", "category": "system"},
    ]}]}
    proof = _proof(total_timeout_s=10)
    clock = iter([0.0, 0.0, 11.0, 11.0, 11.0])   # dépassé dès la 2e vérification

    def _now():
        return next(clock, 999.0)

    result = run_mutation_from_descriptor(
        g, proof, wiremap, mutant_runner=_all_killed_runner,
        baseline_runner=_true_baseline, now_fn=_now,
    )
    assert result["budget_exceeded"] is True
    assert result["mutants_generes"] == 6          # 3 + 3, comptés indépendamment
    assert result["mutants_executes"] == 3          # un seul fichier exécuté


# =====================================================================================
# 2. Émission + vérification -- reçu compatible s12.
# =====================================================================================

def _emit(tmp_path, g, proof=None, *, runner=_all_killed_runner, baseline=_true_baseline,
         run_id="run-1"):
    proof = proof or _proof()
    contract = _contract(proof)
    wiremap = _wiremap(g)
    execution = run_mutation_from_descriptor(
        g, proof, wiremap, mutant_runner=runner, baseline_runner=baseline)
    sr = emit_descriptor_mutation_receipt(
        run_id, g, proof, contract, wiremap, execution,
        key_file=tmp_path / "key", evidence_dir=tmp_path / "evidence",
    )
    return sr, contract, wiremap


def test_recu_descripteur_valide_accepte(tmp_path):
    g = _game(tmp_path)
    sr, contract, wiremap = _emit(tmp_path, g)
    assert sr.receipt.status == "OK"
    assert sr.receipt.detail["proof_chain"]["command_declaree"]
    assert sr.receipt.detail["proof_chain"]["resultat_brut_sha256"]
    check = verify_descriptor_mutation_receipt(
        asdict(sr.receipt), sr.signature, "run-1", g, contract, wiremap,
        key_file=tmp_path / "key",
    )
    assert check["passed"], check["raisons"]
    assert check["status"] == "OK"


def test_recu_survivant_non_trie_donne_fail(tmp_path):
    g = _game(tmp_path)
    sr, contract, wiremap = _emit(tmp_path, g, runner=_one_survivor_runner)
    assert sr.receipt.status == "FAIL"
    check = verify_descriptor_mutation_receipt(
        asdict(sr.receipt), sr.signature, "run-1", g, contract, wiremap,
        key_file=tmp_path / "key",
    )
    assert not check["passed"]


def test_refus_signature_alteree(tmp_path):
    g = _game(tmp_path)
    sr, contract, wiremap = _emit(tmp_path, g)
    d = asdict(sr.receipt)
    d["detail"] = dict(d["detail"], total=999)   # falsification du contenu
    check = verify_descriptor_mutation_receipt(
        d, sr.signature, "run-1", g, contract, wiremap, key_file=tmp_path / "key",
    )
    assert not check["passed"]
    assert any("provenance" in r for r in check["raisons"])


def test_refus_code_sha256_divergent(tmp_path):
    g = _game(tmp_path)
    sr, contract, wiremap = _emit(tmp_path, g)
    (g / "logic.mjs").write_text("export const ok = (1 > 0) || (2 < 3);\n", encoding="utf-8")
    check = verify_descriptor_mutation_receipt(
        asdict(sr.receipt), sr.signature, "run-1", g, contract, wiremap,
        key_file=tmp_path / "key",
    )
    assert not check["passed"]
    assert any("divergent" in r for r in check["raisons"])


def test_refus_seals_vide(tmp_path):
    g = _game(tmp_path)
    proof = _proof()
    proof["mutation"]["seals"]["test_scripts"] = []
    sr, contract, wiremap = _emit(tmp_path, g, proof=proof)
    # forme rejetée dès l'évaluation (règle §2.9) -> jamais un vert.
    assert sr.receipt.status == "BLOCKED"
    check = verify_descriptor_mutation_receipt(
        asdict(sr.receipt), sr.signature, "run-1", g, contract, wiremap,
        key_file=tmp_path / "key",
    )
    assert not check["passed"]
    assert any("scellé" in r or "scelle" in r for r in check["raisons"])


def test_refus_baseline_rouge(tmp_path):
    """Baseline rouge -> mutation non lancée -> 0 mutant mesurable sur la seule
    catégorie mutable déclarée ('system') -> BLOCKED via §5 cas 3
    (`evaluate_proof_descriptor`, réutilisé tel quel -- jamais un vert)."""
    g = _game(tmp_path)
    sr, contract, wiremap = _emit(tmp_path, g, baseline=_false_baseline)
    assert sr.receipt.status == "BLOCKED"
    assert sr.receipt.detail["baseline_ok"] is False
    check = verify_descriptor_mutation_receipt(
        asdict(sr.receipt), sr.signature, "run-1", g, contract, wiremap,
        key_file=tmp_path / "key",
    )
    assert not check["passed"]
    assert any("baseline" in r for r in check["raisons"])


def test_divergence_declare_execute_hors_bin_refusee(tmp_path):
    """§3.1 : SEULE la substitution du token <bin:name> est tolérée -- tout
    autre écart (ici un argument supplémentaire dans command_executee) reste
    un rejet, même si le reste de la preuve (hash, seals, baseline) est propre."""
    g = _game(tmp_path)
    proof = _proof()
    contract = _contract(proof)
    wiremap = _wiremap(g)
    execution = run_mutation_from_descriptor(
        g, proof, wiremap, mutant_runner=_all_killed_runner, baseline_runner=_true_baseline)
    # Divergence fabriquée : un argument en plus par rapport à la déclaration.
    execution = dict(execution, command_executee=list(execution["command_executee"]) + ["--extra"])
    sr = emit_descriptor_mutation_receipt(
        "run-1", g, proof, contract, wiremap, execution,
        key_file=tmp_path / "key", evidence_dir=tmp_path / "evidence",
    )
    assert sr.receipt.status == "BLOCKED"
    assert sr.receipt.detail["declaration_conforme"] is False
    check = verify_descriptor_mutation_receipt(
        asdict(sr.receipt), sr.signature, "run-1", g, contract, wiremap,
        key_file=tmp_path / "key",
    )
    assert not check["passed"]
    assert any("divergence" in r for r in check["raisons"])


def test_substitution_bin_legitime_acceptee(tmp_path):
    g = _game(tmp_path)
    proof = _proof(command=["<bin:node>", "--test", "logic.test.mjs"], binary_ref="node")
    contract = _contract(proof)
    wiremap = _wiremap(g)

    def _resolver(ref):
        return {"path": "C:/fake/node.exe", "version": "20.0.0-fake"}

    execution = run_mutation_from_descriptor(
        g, proof, wiremap, mutant_runner=_all_killed_runner,
        baseline_runner=_true_baseline, binary_resolver=_resolver,
    )
    sr = emit_descriptor_mutation_receipt(
        "run-1", g, proof, contract, wiremap, execution,
        key_file=tmp_path / "key", evidence_dir=tmp_path / "evidence",
    )
    assert sr.receipt.status == "OK"
    assert sr.receipt.detail["declaration_conforme"] is True
    check = verify_descriptor_mutation_receipt(
        asdict(sr.receipt), sr.signature, "run-1", g, contract, wiremap,
        key_file=tmp_path / "key",
    )
    assert check["passed"], check["raisons"]


def test_budget_depasse_recu_blocked(tmp_path):
    g = _game(tmp_path)
    proof = _proof(max_mutants=1)
    sr, contract, wiremap = _emit(tmp_path, g, proof=proof)
    assert sr.receipt.status == "BLOCKED"
    assert sr.receipt.detail["mutants_executes"] < sr.receipt.detail["mutants_generes"]
    check = verify_descriptor_mutation_receipt(
        asdict(sr.receipt), sr.signature, "run-1", g, contract, wiremap,
        key_file=tmp_path / "key",
    )
    assert not check["passed"]


def test_runtime_incoherent_avec_game_contract_refuse(tmp_path):
    """A : cohérence avec game_contract.yaml -- un reçu dont le `runtime`
    diffère du descripteur du jeu (contrat modifié/rejoué contre un autre
    contrat) est refusé, même si tout le reste de la preuve est intact."""
    g = _game(tmp_path)
    sr, contract, wiremap = _emit(tmp_path, g)
    autre_contract = dict(contract, proof=dict(contract["proof"], runtime="godot"))
    check = verify_descriptor_mutation_receipt(
        asdict(sr.receipt), sr.signature, "run-1", g, autre_contract, wiremap,
        key_file=tmp_path / "key",
    )
    assert not check["passed"]
    assert any("runtime" in r for r in check["raisons"])


def test_refus_preuve_absente():
    check = verify_descriptor_mutation_receipt(
        None, "", "run-1", ".", {}, {},
    )
    assert not check["passed"]


def test_refus_run_id_incoherent(tmp_path):
    g = _game(tmp_path)
    sr, contract, wiremap = _emit(tmp_path, g)
    check = verify_descriptor_mutation_receipt(
        asdict(sr.receipt), sr.signature, "AUTRE-run", g, contract, wiremap,
        key_file=tmp_path / "key",
    )
    assert not check["passed"]
    assert any("run_id" in r for r in check["raisons"])
