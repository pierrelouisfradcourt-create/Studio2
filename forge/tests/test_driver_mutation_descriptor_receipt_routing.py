"""PHASE ③ ÉTAPE 3 (go Pierre 2026-07-28) — CONTRAT_PREUVE_MUTATION_V1.md
§7/§8, pièce D : le routage de `ForgeDriver._receipt` (s12) sur
`detail["regime_preuve"]`, LES QUATRE CAS exigés par Pierre, chacun distinct
et nommé :

    1. historique                -> verify_mutation_receipt (INCHANGÉ)
    2. descripteur, reçu présent -> verify_descriptor_mutation_receipt
    3. descripteur, reçu ABSENT -> BLOCKED nommé (jamais confondu avec 4)
    4. descripteur, reçu INVALIDE -> BLOCKED avec les raisons du vérificateur

Aucun jeu réel n'emprunte aujourd'hui le chemin descripteur avec exécution
(Snake n'est pas migré, hors périmètre de cette mission) : ces tests appellent
`ForgeDriver._receipt` DIRECTEMENT avec un `state` construit à la main --
même stratégie que la mission ÉTAPE 2 (`test_driver_mutation_regime_routing.py`,
qui passe par `.run()`) mais ici on cible spécifiquement la ré-vérification
s12, qu'aucun run complet ne peut exercer tant que `_run_mutation_descriptor_
regime` (s10a) ne produit pas encore de reçu réel (hors périmètre déclaré de
cette mission : seul le routage s12 est demandé, pas le branchement s10a).

Aucune écriture sous `GAMES/**`. `test_mutation_regime_coexistence.py` (zone
protégée) n'est ni modifié ni importé ici.

claim_verdict: NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
from dataclasses import asdict

from forge.driver import ForgeDriver
from forge.mutation_proof import (
    emit_descriptor_mutation_receipt,
    emit_mutation_receipt,
    run_mutation_for_game,
    run_mutation_from_descriptor,
)

_SOURCE = "export const ok = (1 >= 0) && (2 <= 3);\n"


def _game(tmp_path):
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
    (g / "00_CHARTER").mkdir()
    return g


def _wiremap(g):
    return json.loads((g / "09_WIREMAP" / "wiremap.json").read_text(encoding="utf-8"))


def _proof(max_mutants=200):
    return {
        "schema_version": 1,
        "runtime": "rules",
        "mutation": {
            "categories_mutables": ["system"],
            "categories_exclues": ["system.adapter"],
            "command": ["node", "--test", "logic.test.mjs"],
            "cwd": "GAMES/jeu",
            "binary_ref": "node",
            "expects_exit_zero": True,
            "budget": {"max_mutants": max_mutants, "timeout_per_mutant_s": 30,
                       "total_timeout_s": 900},
            "seals": {"wrapper": [], "test_scripts": ["logic.test.mjs"]},
        },
    }


def _write_contract(g, proof):
    contract = {"schema_version": 1, "game_id": "jeu", "runtimes": ["rules"], "proof": proof}
    (g / "00_CHARTER" / "game_contract.yaml").write_text(
        json.dumps(contract), encoding="utf-8")  # JSON est un YAML valide
    return contract


def _all_killed_runner(source_path, argv, *, cwd, timeout=None, **kw):
    return {"total": 3, "killed": 3, "survived": 0, "survivors": []}


def _driver(tmp_path, g):
    return ForgeDriver(
        "jeu", "jeu-1", run_dir=tmp_path / "run", profile="micro",
        src_root=g, game_dir=g, is_game=True, key_file=tmp_path / "key",
    )


def _state_with(detail):
    return {"steps": {"s10a-oracle-code": {"status": "OK", "detail": detail, "ts": 0.0}}}


# =====================================================================================
# 1. Régime historique -- INCHANGÉ (même appel, même comportement qu'avant la
#    mission : verify_mutation_receipt).
# =====================================================================================

def test_cas_1_historique_recu_valide_reste_ok(tmp_path):
    g = _game(tmp_path)
    result = run_mutation_for_game(g, ["logic.mjs"], runner=_all_killed_runner,
                                   baseline_runner=lambda argv, cwd: True)
    sr = emit_mutation_receipt("jeu-1", g, ["logic.mjs"], result,
                               key_file=tmp_path / "key",
                               evidence_dir=tmp_path / "evidence")
    detail = {"regime_preuve": "historique",
              "mutation": {"receipt": asdict(sr.receipt), "signature": sr.signature}}
    driver = _driver(tmp_path, g)
    out = driver._receipt(_state_with(detail), "code", "s10a-oracle-code")
    assert out.receipt.status == "OK"
    assert "mutation_verification" not in out.receipt.detail


def test_cas_1_historique_recu_invalide_degrade_blocked(tmp_path):
    """Toujours le cas 1, mais reçu falsifié -- verify_mutation_receipt (le
    vérificateur HISTORIQUE, pas le nouveau) doit continuer à le refuser."""
    g = _game(tmp_path)
    result = run_mutation_for_game(g, ["logic.mjs"], runner=_all_killed_runner,
                                   baseline_runner=lambda argv, cwd: True)
    sr = emit_mutation_receipt("jeu-1", g, ["logic.mjs"], result,
                               key_file=tmp_path / "key",
                               evidence_dir=tmp_path / "evidence")
    tampered = dict(asdict(sr.receipt))
    tampered["detail"] = dict(tampered["detail"], total=999)
    detail = {"regime_preuve": "historique",
              "mutation": {"receipt": tampered, "signature": sr.signature}}
    driver = _driver(tmp_path, g)
    out = driver._receipt(_state_with(detail), "code", "s10a-oracle-code")
    assert out.receipt.status == "BLOCKED"
    assert "mutation_verification" in out.receipt.detail


# =====================================================================================
# 2. Descripteur, reçu PRÉSENT et VALIDE -- verify_descriptor_mutation_receipt,
#    le reçu reste OK.
# =====================================================================================

def test_cas_2_descripteur_recu_valide_reste_ok(tmp_path):
    g = _game(tmp_path)
    proof = _proof()
    contract = _write_contract(g, proof)
    wiremap = _wiremap(g)
    execution = run_mutation_from_descriptor(
        g, proof, wiremap, mutant_runner=_all_killed_runner,
        baseline_runner=lambda argv, cwd: True,
    )
    sr = emit_descriptor_mutation_receipt(
        "jeu-1", g, proof, contract, wiremap, execution,
        key_file=tmp_path / "key", evidence_dir=tmp_path / "evidence",
    )
    assert sr.receipt.status == "OK"   # préalable : l'émission elle-même est verte
    detail = {"regime_preuve": "descripteur",
              "mutation": {"receipt": asdict(sr.receipt), "signature": sr.signature}}
    driver = _driver(tmp_path, g)
    out = driver._receipt(_state_with(detail), "code", "s10a-oracle-code")
    assert out.receipt.status == "OK"
    assert "mutation_verification" not in out.receipt.detail


# =====================================================================================
# 3. Descripteur, reçu ABSENT -- BLOCKED nommé, jamais confondu avec le cas 4.
# =====================================================================================

def test_cas_3_descripteur_sans_recu_blocked_nomme(tmp_path):
    g = _game(tmp_path)
    _write_contract(g, _proof())
    detail = {"regime_preuve": "descripteur",
              "mutation": {"regime": "descripteur", "evaluation_forme": {"status": "OK"}}}
    driver = _driver(tmp_path, g)
    out = driver._receipt(_state_with(detail), "code", "s10a-oracle-code")
    assert out.receipt.status == "BLOCKED"
    check = out.receipt.detail["mutation_verification"]
    assert not check["passed"]
    assert any("absence" in r for r in check["raisons"])


def test_cas_3_descripteur_mutation_absente_du_detail_blocked_nomme(tmp_path):
    """Variante : la clé `mutation` elle-même est absente du detail (pas
    seulement `receipt` à l'intérieur) -- même case 3, même traitement."""
    g = _game(tmp_path)
    _write_contract(g, _proof())
    detail = {"regime_preuve": "descripteur"}
    driver = _driver(tmp_path, g)
    out = driver._receipt(_state_with(detail), "code", "s10a-oracle-code")
    assert out.receipt.status == "BLOCKED"
    assert any("absence" in r for r in out.receipt.detail["mutation_verification"]["raisons"])


# =====================================================================================
# 4. Descripteur, reçu PRÉSENT mais INVALIDE -- BLOCKED avec les raisons du
#    vérificateur dédié (distinct du cas 3 : un reçu EXISTE, il est rejeté).
# =====================================================================================

def test_cas_4_descripteur_recu_invalide_blocked_avec_raisons(tmp_path):
    g = _game(tmp_path)
    proof = _proof()
    contract = _write_contract(g, proof)
    wiremap = _wiremap(g)
    execution = run_mutation_from_descriptor(
        g, proof, wiremap, mutant_runner=_all_killed_runner,
        baseline_runner=lambda argv, cwd: True,
    )
    sr = emit_descriptor_mutation_receipt(
        "jeu-1", g, proof, contract, wiremap, execution,
        key_file=tmp_path / "key", evidence_dir=tmp_path / "evidence",
    )
    # Reçu présent mais falsifié APRÈS coup (code modifié après la preuve).
    (g / "logic.mjs").write_text("export const ok = (1 > 0) || (2 < 3);\n", encoding="utf-8")
    detail = {"regime_preuve": "descripteur",
              "mutation": {"receipt": asdict(sr.receipt), "signature": sr.signature}}
    driver = _driver(tmp_path, g)
    out = driver._receipt(_state_with(detail), "code", "s10a-oracle-code")
    assert out.receipt.status == "BLOCKED"
    check = out.receipt.detail["mutation_verification"]
    assert not check["passed"]
    assert any("divergent" in r for r in check["raisons"])


def test_cas_4_descripteur_signature_invalide_blocked(tmp_path):
    g = _game(tmp_path)
    proof = _proof()
    contract = _write_contract(g, proof)
    wiremap = _wiremap(g)
    execution = run_mutation_from_descriptor(
        g, proof, wiremap, mutant_runner=_all_killed_runner,
        baseline_runner=lambda argv, cwd: True,
    )
    sr = emit_descriptor_mutation_receipt(
        "jeu-1", g, proof, contract, wiremap, execution,
        key_file=tmp_path / "key", evidence_dir=tmp_path / "evidence",
    )
    detail = {"regime_preuve": "descripteur",
              "mutation": {"receipt": asdict(sr.receipt), "signature": "signature-forgee"}}
    driver = _driver(tmp_path, g)
    out = driver._receipt(_state_with(detail), "code", "s10a-oracle-code")
    assert out.receipt.status == "BLOCKED"
    assert any("provenance" in r
              for r in out.receipt.detail["mutation_verification"]["raisons"])


# =====================================================================================
# regime_preuve absent (reprise antérieure à cette mission) -> traité comme
# historique, jamais un cas nouveau inventé par convention.
# =====================================================================================

def test_regime_preuve_absent_traite_comme_historique(tmp_path):
    g = _game(tmp_path)
    result = run_mutation_for_game(g, ["logic.mjs"], runner=_all_killed_runner,
                                   baseline_runner=lambda argv, cwd: True)
    sr = emit_mutation_receipt("jeu-1", g, ["logic.mjs"], result,
                               key_file=tmp_path / "key",
                               evidence_dir=tmp_path / "evidence")
    detail = {"mutation": {"receipt": asdict(sr.receipt), "signature": sr.signature}}
    driver = _driver(tmp_path, g)
    out = driver._receipt(_state_with(detail), "code", "s10a-oracle-code")
    assert out.receipt.status == "OK"
