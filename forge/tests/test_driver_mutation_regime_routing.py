"""Intégration driver du CONTRAT_PREUVE_MUTATION_V1.md (FIGÉ, ratifié Pierre
2026-07-28) — mission ÉTAPE 2, périmètre fermé et étroit : UNIQUEMENT le
routage de `ForgeDriver._run_code_oracle` entre régime historique et nouveau
régime (`proof.mutation`). Aucun de ces tests n'écrit sous `GAMES/**` (tout
vit en `tmp_path`) et aucun ne touche `test_mutation_regime_coexistence.py`
(zone protégée, non modifiée).

Le moteur `forge.mutation_proof.evaluate_proof_descriptor` n'est PAS
réimplémenté ici : ces tests vérifient uniquement QUE le driver le consulte
et QUE le chemin choisi est tracé (`detail["regime_preuve"]`), conformément
au cahier des charges de la mission.

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
    """Mini-jeu satisfaisant la garde e2e structurelle (check_e2e_harness) --
    même fixture que test_driver_mutation.py (_game_dir), dupliquée ici pour
    ne pas coupler ce fichier nouveau à un autre fichier de test existant."""
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
        mutation_baseline_runner=lambda argv, cwd: True,
    )


def _s10a_detail(run_dir):
    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    return state["steps"]["s10a-oracle-code"]["detail"]


# =====================================================================================
# 1. Jeu SANS descripteur -> régime historique, périmètre IDENTIQUE à aujourd'hui.
# =====================================================================================

def test_jeu_sans_descripteur_regime_historique_perimetre_inchange(tmp_path, offline):
    """Aucun `00_CHARTER/game_contract.yaml` du tout (cas le plus courant du parc
    actuel, dont Pong) : le driver doit produire EXACTEMENT ce qu'il produisait
    avant cette mission -- un reçu mutation signé via `emit_mutation_receipt`,
    software_verdict OK -- avec en plus la traçabilité `regime_preuve`."""
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g, game_dir=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["status"] == "DONE"
    assert report["software_verdict"] == "OK"

    detail = _s10a_detail(run_dir)
    assert detail["regime_preuve"] == "historique"
    # périmètre historique inchangé : reçu signé emit_mutation_receipt présent
    assert detail["mutation"]["receipt"]["status"] == "OK"
    assert detail["mutation"]["receipt"]["detail"]["code_sha256"]["logic.mjs"]
    assert detail["mutation"]["signature"]


def test_jeu_avec_contrat_sans_cle_proof_regime_historique(tmp_path, offline):
    """`game_contract.yaml` PRÉSENT mais sans clé `proof` (contrat lisible,
    descripteur absent) : même critère que Pong -- régime historique."""
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    (g / "00_CHARTER").mkdir()
    (g / "00_CHARTER" / "game_contract.yaml").write_text(
        "schema_version: 1\ngame_id: jeu\nruntimes: [browser]\n", encoding="utf-8")
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g, game_dir=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["software_verdict"] == "OK"
    detail = _s10a_detail(run_dir)
    assert detail["regime_preuve"] == "historique"
    assert detail["mutation"]["receipt"]["status"] == "OK"


# =====================================================================================
# 2. Jeu AVEC descripteur `proof:` -> moteur evaluate_proof_descriptor consulté,
#    regime_preuve tracé "descripteur". Aucun exécuteur du descripteur n'existe
#    dans ce périmètre (mission ÉTAPE 2) : BLOCKED nommé attendu quand la forme
#    est correcte et qu'une mesure réelle resterait à faire.
# =====================================================================================

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


def test_jeu_avec_descripteur_moteur_consulte_regime_trace(tmp_path, offline):
    """Cas nominal du nouveau régime : catégorie `system` déclarée mutable ET
    réellement présente dans la wiremap -> forme correcte, l'exécuteur du
    descripteur MESURE réellement, et un reçu signé exploitable par s12 est
    émis. Le moteur `evaluate_proof_descriptor` est bien consulté (trace dans
    detail.mutation.evaluation_forme).

    MISE À JOUR ÉTAPE 4 (gate Pierre 2026-07-28) : les deux attentes portant sur
    l'ABSENCE d'exécuteur (`software_verdict == "BLOCKED"` et `"reason" in
    detail`) figeaient un état transitoire de l'implémentation, pas une propriété
    du système — règle d'usine n°3 (« un test vérifie une propriété durable, pas
    une valeur historique accidentelle »). Le branchement s10a -> exécuteur les a
    rendues fausses par construction. L'INTENTION du test est inchangée : prouver
    que le nouveau régime est bien emprunté et tracé. Les 4 autres assertions
    (régime tracé, régime du reçu, moteur consulté, forme OK) sont intactes."""
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    _wiremap_une_categorie_system(g)
    _contrat_avec_proof(g, categories_mutables=["system"],
                        categories_exclues=["system.adapter"])
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g, game_dir=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["software_verdict"] == "OK"   # l'exécuteur a mesuré (tous mutants tués)
    detail = _s10a_detail(run_dir)
    assert detail["regime_preuve"] == "descripteur"
    assert detail["mutation"]["regime"] == "descripteur"
    forme = detail["mutation"]["evaluation_forme"]
    assert forme["status"] == "OK"          # forme correcte (moteur consulté)
    # Preuve RÉELLEMENT produite : un reçu signé est présent, exploitable par s12.
    assert "receipt" in detail["mutation"]  # plus d'absence de preuve
    # Le reçu est signé et exploitable par s12 : la signature accompagne le reçu.
    assert detail["mutation"].get("signature")


def test_jeu_avec_descripteur_categorie_non_applicable_s10a_ok_mais_s12_blocked(
        tmp_path, offline):
    """§5 cas 1 : catégorie mutable déclarée mais ABSENTE de la wiremap ->
    NON_APPLICABLE, passed=True -- s10a lui-même est OK (rien à mesurer, acquis
    par la carte). MAIS le verdict final agrégé (s12) reste BLOCKED : l'invariant
    de re-vérification `ForgeDriver._receipt` (driver.py, HORS PÉRIMÈTRE de
    cette mission -- non touché) exige un reçu mutation SIGNÉ
    (`verify_mutation_receipt`) pour tout code-OK de jeu, et le nouveau régime
    ne produit aucun reçu signé (aucune exécution n'a eu lieu). Conséquence
    documentée dans le rapport de mission : un jeu du nouveau régime ne peut
    PAS atteindre un software_verdict OK final tant que ce point n'est pas
    tranché par Pierre (hors périmètre ÉTAPE 2)."""
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    _wiremap_une_categorie_system(g)
    # 'entity' déclarée mutable mais absente de la wiremap (seule 'system' y est)
    _contrat_avec_proof(g, categories_mutables=["entity"],
                        categories_exclues=["system", "system.adapter"])
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g, game_dir=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         **_kwargs(tmp_path, run_dir)).run()
    detail = _s10a_detail(run_dir)
    assert detail["regime_preuve"] == "descripteur"
    forme = detail["mutation"]["evaluation_forme"]
    assert forme["status"] == "NON_APPLICABLE"
    assert forme["passed"] is True
    # s10a lui-même a bien produit OK (branchement de cette mission) ...
    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    assert state["steps"]["s10a-oracle-code"]["status"] == "OK"
    # ... mais le verdict AGRÉGÉ dégrade en BLOCKED, hors périmètre de la mission
    assert report["software_verdict"] == "BLOCKED"
    code = json.loads((run_dir / "verdict.json").read_text(encoding="utf-8"))["oracles"]["code"]
    assert code["status"] == "BLOCKED"
    assert "mutation_verification" in code["detail"]


def test_jeu_avec_descripteur_categorie_oubliee_blocked(tmp_path, offline):
    """§2 règle 4 / §5 cas 2 : catégorie PRÉSENTE dans la wiremap mais oubliée
    des deux listes déclarées -> BLOCKED (le moteur pur le tranche, le driver
    applique)."""
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    _wiremap_une_categorie_system(g)
    # ni 'system' ni 'system.adapter' déclarés -> 'system' est oubliée
    _contrat_avec_proof(g, categories_mutables=[], categories_exclues=[])
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g, game_dir=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["software_verdict"] == "BLOCKED"
    detail = _s10a_detail(run_dir)
    assert detail["mutation"]["evaluation_forme"]["status"] == "BLOCKED"
    assert "evaluate_proof_descriptor" in detail["reason"]


# =====================================================================================
# 3. Ambiguïtés explicitement citées par la mission -> BLOCKED nommé, jamais
#    une convention.
# =====================================================================================

def test_descripteur_illisible_proof_pas_un_objet_blocked(tmp_path, offline):
    """`proof:` présent mais sa valeur n'est PAS un objet (ex. chaîne nue) ->
    descripteur illisible -- ambiguïté non tranchée par le contrat -> BLOCKED
    nommé (jamais traité par convention comme historique NI comme un
    descripteur valide)."""
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    (g / "00_CHARTER").mkdir()
    (g / "00_CHARTER" / "game_contract.yaml").write_text(
        "schema_version: 1\ngame_id: jeu\nruntimes: [browser]\nproof: ceci-nest-pas-un-objet\n",
        encoding="utf-8",
    )
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g, game_dir=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["software_verdict"] == "BLOCKED"
    detail = _s10a_detail(run_dir)
    assert detail["regime_preuve"] == "descripteur"
    assert "illisible" in detail["reason"]
    assert "mutation" not in detail  # jamais atteint le moteur : reason posée avant


def test_contrat_mal_forme_yaml_ambigu_blocked(tmp_path, offline):
    """`game_contract.yaml` EXISTE mais son YAML est invalide : impossible de
    savoir s'il portait une clé `proof` -- le contrat V1 est silencieux sur ce
    cas -- BLOCKED nommé, jamais un repli silencieux vers historique."""
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    (g / "00_CHARTER").mkdir()
    (g / "00_CHARTER" / "game_contract.yaml").write_text(
        "schema_version: 1\n  bad indent: [unclosed\n", encoding="utf-8")
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g, game_dir=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["software_verdict"] == "BLOCKED"
    detail = _s10a_detail(run_dir)
    assert detail["regime_preuve"] == "descripteur"
    assert "illisible" in detail["reason"] or "mal formé" in detail["reason"]


def test_descripteur_present_sans_wiremap_blocked(tmp_path, offline):
    """Descripteur `proof:` présent et bien formé, mais AUCUNE wiremap
    (`09_WIREMAP/wiremap.json` absente) -- cas explicitement cité par la
    mission comme ambigu -> BLOCKED nommé, décision Pierre requise."""
    run_dir = tmp_path / "run"
    g = _game_dir(tmp_path)
    # pas de _wiremap_une_categorie_system(g) ici : wiremap absente
    _contrat_avec_proof(g, categories_mutables=["system"],
                        categories_exclues=["system.adapter"])
    report = ForgeDriver("jeu", "jeu-1", profile="micro", is_game=True,
                         executor=StubExecutor(), src_root=g, game_dir=g,
                         logic_files=["logic.mjs"], mutation_runner=_all_killed,
                         **_kwargs(tmp_path, run_dir)).run()
    assert report["software_verdict"] == "BLOCKED"
    detail = _s10a_detail(run_dir)
    assert detail["regime_preuve"] == "descripteur"
    assert "wiremap" in detail["reason"]
    assert "mutation" not in detail  # jamais atteint le moteur : wiremap manquante d'abord
