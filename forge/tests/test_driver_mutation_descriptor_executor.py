"""CONTRAT_PREUVE_MUTATION_V1.md (FIGÉ, ratifié Pierre 2026-07-28) -- PHASE ③
ÉTAPE 4, go Pierre 2026-07-28 : « brancher s10a sur l'exécuteur du régime
descripteur ». Périmètre fermé et étroit : UNIQUEMENT le câblage bout-en-bout
`ForgeDriver._run_mutation_descriptor_regime` -> `run_mutation_from_descriptor`
-> `emit_descriptor_mutation_receipt` -> `verify_descriptor_mutation_receipt`
(déjà branché en s12 avant cette mission). Aucune écriture sous `GAMES/**`
(tout vit en `tmp_path`), ce fichier ne touche NI `test_driver_mutation_regime_
routing.py` NI `test_mutation_regime_coexistence.py` (zones protégées).

claim_verdict: NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

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


def _game_dir(tmp_path, name="game"):
    """Même fixture minimale que les autres suites mutation (satisfait la garde
    e2e structurelle) -- dupliquée pour ne pas coupler ce fichier à un autre."""
    g = tmp_path / name
    g.mkdir()
    (g / "logic.mjs").write_text(
        "export const speed = 3;\nexport const win = 1 >= 0;\n", encoding="utf-8")
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


def _wiremap_une_categorie_system(g):
    (g / "09_WIREMAP").mkdir()
    (g / "09_WIREMAP" / "wiremap.json").write_text(
        json.dumps({"lines": [
            {"fichiers": [{"path": "logic.mjs", "category": "system"}]},
        ]}),
        encoding="utf-8",
    )


def _contrat_avec_proof(g, categories_mutables, categories_exclues=None):
    (g / "00_CHARTER").mkdir()
    proof = {
        "schema_version": 1,
        "runtime": "rules",
        "mutation": {
            "categories_mutables": categories_mutables,
            "categories_exclues": categories_exclues or [],
            "command": ["node", "--test", "logic.test.mjs"],
            "cwd": "GAMES/jeu",
            "binary_ref": "node",
            "expects_exit_zero": True,
            "seals": {"wrapper": [], "test_scripts": ["logic.test.mjs"]},
        },
    }
    contract = {"schema_version": 1, "game_id": "jeu", "runtimes": ["rules"],
                "proof": proof}
    (g / "00_CHARTER" / "game_contract.yaml").write_text(
        json.dumps(contract), encoding="utf-8")  # JSON est un YAML valide


def _all_killed(source_path, test_argv, *, cwd, **kw):
    return {"total": 4, "killed": 4, "survived": 0, "score": 1.0, "survivors": []}


class StubExecutor:
    def __call__(self, payload, decision, context):
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


def _s10a_detail(run_dir):
    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    return state["steps"]["s10a-oracle-code"]["detail"]


def _run_descripteur_ok(tmp_path):
    """Produit un run vert de bout en bout via le VRAI driver, régime
    descripteur, résolveur/runner injectés (aucun binaire réel invoqué)."""
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    _wiremap_une_categorie_system(g)
    _contrat_avec_proof(g, categories_mutables=["system"],
                        categories_exclues=["system.adapter"])
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g, game_dir=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         **_kwargs(tmp_path, run_dir)).run()
    return report, run_dir, g


def test_s10a_descripteur_execute_et_emet_un_recu_signe_exploitable_par_s12(
        tmp_path, offline):
    """Cas nominal : catégorie `system` déclarée mutable ET réellement présente
    dans la wiremap -> forme OK -> EXÉCUTION réelle (`run_mutation_from_descriptor`,
    runner/baseline injectés) -> reçu signé (`emit_descriptor_mutation_receipt`)
    posé dans `detail["mutation"]["receipt"]`/`["signature"]`, MÊME FORME que le
    régime historique -- et s12 (`ForgeDriver._receipt`, non modifié par cette
    mission, déjà branché ÉTAPE 3) le RE-vérifie avec succès : software_verdict
    final OK, bout en bout."""
    report, run_dir, g = _run_descripteur_ok(tmp_path)

    assert report["status"] == "DONE"
    assert report["software_verdict"] == "OK"

    detail = _s10a_detail(run_dir)
    assert detail["regime_preuve"] == "descripteur"
    assert detail["mutation"]["regime"] == "descripteur"
    assert detail["mutation"]["evaluation_forme"]["status"] == "OK"
    # le reçu signé EXISTE désormais (c'était l'absence documentée avant cette
    # mission -- cf. test_driver_mutation_regime_routing.py, ambiguïté remontée
    # dans le rapport) et il est vert.
    receipt = detail["mutation"]["receipt"]
    assert receipt["status"] == "OK"
    assert receipt["detail"]["regime_preuve"] == "descripteur"
    assert receipt["detail"]["code_sha256"]["logic.mjs"]
    assert receipt["detail"]["proof_chain"]["command_declaree"] == \
        ["node", "--test", "logic.test.mjs"]
    assert detail["mutation"]["signature"]

    # s12 re-vérifie CE MÊME reçu (verify_descriptor_mutation_receipt, déjà
    # branché en s12 avant cette mission) -- verdict.json final le confirme.
    verdict = json.loads((run_dir / "verdict.json").read_text(encoding="utf-8"))
    assert verdict["oracles"]["code"]["status"] == "OK"
    assert "mutation_verification" not in verdict["oracles"]["code"]["detail"]


def test_s10a_descripteur_gate_rouge_si_survivant(tmp_path, offline):
    """Un mutant SURVIVANT (mutation_runner non-mocké-tout-tué) fait échouer le
    gate mutation (`check_mutation_gate`, juge inchangé, réutilisé tel quel par
    `emit_descriptor_mutation_receipt`) -> reçu `status: FAIL` -> s10a FAIL
    (alimente l'escalade), jamais un vert silencieux."""
    def _survivor(source_path, test_argv, *, cwd, **kw):
        return {"total": 1, "killed": 0, "survived": 1, "score": 0.0,
                "survivors": [{"name": "ge->gt", "line": 2}]}

    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    _wiremap_une_categorie_system(g)
    _contrat_avec_proof(g, categories_mutables=["system"],
                        categories_exclues=["system.adapter"])
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g, game_dir=g,
                         logic_files=["logic.mjs"], mutation_runner=_survivor,
                         **_kwargs(tmp_path, run_dir)).run()

    detail = _s10a_detail(run_dir)
    assert detail["regime_preuve"] == "descripteur"
    assert detail["mutation"]["receipt"]["status"] == "FAIL"
    assert report["software_verdict"] in ("FAIL", "BLOCKED")


def test_verify_run_accepte_un_recu_descripteur_valide(tmp_path, offline):
    """(f) verify_run doit ACCEPTER un reçu mutation (régime descripteur) valide
    -- même invariant que le régime historique (test_verify_run_mutation.py),
    étendu (PHASE ③ ÉTAPE 4) au nouveau chemin."""
    from forge.verify_run import verify_run

    report, run_dir, g = _run_descripteur_ok(tmp_path)
    assert report["software_verdict"] == "OK"  # préalable
    res = verify_run(run_dir / "verdict.json", key_file=tmp_path / "forge_test.key")
    assert res["overall"] is True
    assert res["mutation_integrity_problems"] == []


def test_verify_run_rejette_un_recu_descripteur_falsifie(tmp_path, offline):
    """(f) le code du jeu change APRÈS le verdict signé (régime descripteur) --
    verify_run doit REJETER (preuve périmée), pas dire AUTHENTIQUE. Même classe
    de garde que `test_code_modifie_apres_verdict_rejete_au_gate` (régime
    historique), désormais couverte pour le nouveau régime via
    `verify_descriptor_mutation_receipt`."""
    from forge.verify_run import verify_run

    report, run_dir, g = _run_descripteur_ok(tmp_path)
    assert report["software_verdict"] == "OK"  # préalable
    (g / "logic.mjs").write_text("export const speed = 999;\n", encoding="utf-8")

    res = verify_run(run_dir / "verdict.json", key_file=tmp_path / "forge_test.key")
    assert res["overall"] is False
    assert any("divergent" in p for p in res["mutation_integrity_problems"])


def test_verify_run_inchange_sur_un_recu_historique(tmp_path, offline):
    """(f) non-régression : un verdict de jeu du régime HISTORIQUE (aucune clé
    `proof`, comme Pong) continue d'emprunter EXACTEMENT `verify_mutation_receipt`
    -- le nouveau routage (`regime_preuve`) ne doit rien changer à ce chemin."""
    from forge.verify_run import verify_run

    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g, game_dir=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["software_verdict"] == "OK"
    detail = _s10a_detail(run_dir)
    assert detail["regime_preuve"] == "historique"  # jamais touché par cette mission

    res = verify_run(run_dir / "verdict.json", key_file=tmp_path / "forge_test.key")
    assert res["overall"] is True
    assert res["mutation_ok"] is True
