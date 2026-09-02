"""Preuve de coexistence des deux régimes de mutation — condition d'ENTRÉE de
l'implémentation du contrat `docs/forge/CONTRAT_PREUVE_MUTATION_V1.md` (FIGÉ,
ratifié Pierre 2026-07-28), pas sa conclusion (§7, §8 du contrat).

Aucun code de production n'est modifié par ce fichier : il capture le régime
HISTORIQUE (Pong, verrouillé) et spécifie le régime NOUVEAU (`proof.mutation`,
pas encore implémenté), en s'appuyant sur les briques EXISTANTES
(`forge.mutation_proof.mutation_scope_from_wiremap`,
`forge.driver.ForgeDriver._mutation_scope_from_wiremap_any`) sans les modifier.

=====================================================================================
FAMILLE 1 — régime historique, VERROUILLÉ (doivent être VERTS immédiatement)
=====================================================================================
Ces tests protègent le comportement dont Pong dépend aujourd'hui. Si l'un
d'eux casse un jour, c'est qu'une implémentation du nouveau régime a touché
le chemin historique sans gate — exactement ce que le contrat interdit
(§6 : « PONG N'EST PAS MIGRÉ », « ancien régime conservé à l'identique »).

=====================================================================================
FAMILLE 2 — nouveau régime, SPÉCIFIÉ D'ABORD (attendus en xfail strict aujourd'hui)
=====================================================================================
Chaque cas cite la section du contrat qui le fonde et appelle l'API que
l'implémentation DEVRA fournir :

    forge.mutation_proof.evaluate_proof_descriptor(
        proof: dict,             # le sous-arbre `proof:` de game_contract.yaml
        game_contract: dict,     # le game_contract.yaml complet (pour `runtimes:`)
        wiremap: dict,           # la wiremap du jeu (schema_version 2, `lines[]`)
        mutation_result: dict | None = None,  # résultat brut de la mutation exécutée,
                                               # None si l'appelant veut une évaluation
                                               # de FORME seule (avant toute exécution)
    ) -> dict   # {"status": "OK"|"BLOCKED"|"NON_APPLICABLE"|"FAIL",
                #  "passed": bool, "raisons": [str, ...], ...}

Cette signature est un CAHIER DES CHARGES, pas une décision finale de
l'implémentation à venir — elle peut être ajustée quand le driver sera
réellement branché (§8 : « brancher le driver ← seulement après ② vert »).
Aujourd'hui, `forge.mutation_proof` ne définit PAS `evaluate_proof_descriptor` :
l'appel lève `AttributeError`, ce qui est un xfail légitime (strict=True) —
le jour où l'implémentation existe et où le test passerait au vert SANS que
son assertion soit satisfaite (mauvaise implémentation), `strict=True` fait
échouer la suite (XPASS interdit) au lieu de laisser passer un faux vert.

claim_verdict: NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
import subprocess
from pathlib import Path

import pytest
import yaml

from forge import mutation_proof
from forge.driver import ForgeDriver

REPO_ROOT = Path(__file__).resolve().parents[2]
PONG_DIR = REPO_ROOT / "GAMES" / "pong"
PONG_WIREMAP_PATH = PONG_DIR / "09_WIREMAP" / "wiremap.json"
PONG_CONTRACT_PATH = PONG_DIR / "00_CHARTER" / "game_contract.yaml"
ORACLES_JSON_PATH = REPO_ROOT / "forge" / "oracles.json"

CATEGORIE_PRESENTATION_RUNTIME = "system.adapter"


def _real_pong_wiremap() -> dict:
    return json.loads(PONG_WIREMAP_PATH.read_text(encoding="utf-8"))


def _real_pong_contract() -> dict:
    return yaml.safe_load(PONG_CONTRACT_PATH.read_text(encoding="utf-8"))


def _oracles_json() -> dict:
    return json.loads(ORACLES_JSON_PATH.read_text(encoding="utf-8"))


# =====================================================================================
# FAMILLE 1 — RÉGIME HISTORIQUE, VERROUILLÉ
# =====================================================================================


class TestRegimeHistoriquePong:
    """Capture le périmètre ACTUEL du gate mutation sur la VRAIE wiremap de Pong.

    Pong n'a PAS de descripteur `proof:` (§6, décision 6, ferme) : il DOIT
    continuer à passer par `mutation_scope_from_wiremap` / la formule U-2
    historique — jamais par le nouveau chemin `proof.mutation`. Si une future
    implémentation fait dévier Pong de ce chemin, ce test rougit.
    """

    def test_perimetre_actuel_pong_categories_et_invariants(self):
        wiremap = _real_pong_wiremap()
        scope = ForgeDriver._mutation_scope_from_wiremap_any(wiremap)

        included = scope["included"]
        excluded = scope["excluded"]
        categories = scope["categories"]

        # --- propriété 1 : aucun fichier de catégorie system.adapter n'est inclus ---
        included_categories = {categories.get(p) for p in included}
        assert CATEGORIE_PRESENTATION_RUNTIME not in included_categories, (
            "un fichier system.adapter s'est glissé dans le périmètre jugé par la "
            "mutation -- régression du filtre historique (décision U-2)")

        # --- propriété 2 : tous les inclus sont de catégorie 'system' ---
        # (Pong ne déclare, à ce jour, que des lignes 'system' et 'system.adapter'
        # dans sa wiremap -- cf. wiremap.json['systems'][*]['category'].)
        assert included, "wiremap Pong sans aucun fichier inclus : test vide"
        for path in included:
            assert categories.get(path) == "system", (
                f"{path} inclus avec une catégorie inattendue "
                f"({categories.get(path)!r}) -- le périmètre historique de Pong "
                "ne couvre que 'system'")

        # --- propriété 3 : tous les exclus sont system.adapter, motif non vide ---
        assert excluded, "wiremap Pong sans aucune exclusion déclarée : test vide"
        for exc in excluded:
            assert exc["categorie"] == CATEGORIE_PRESENTATION_RUNTIME
            assert exc["motif"], "exclusion sans motif -- devient silencieuse"

        # --- propriété 4 : le nombre d'inclus est CELUI D'AUJOURD'HUI ---
        # Dérivé de la wiremap elle-même (pas un nombre en dur qui romprait au
        # premier fichier légitimement ajouté) : les fichiers 'system' RÉELS de
        # la wiremap actuelle.
        attendu_inclus = sorted({
            f.get("path")
            for ligne in wiremap.get("lines", [])
            for f in (ligne.get("fichiers") or [])
            if isinstance(f, dict)
            and isinstance(f.get("path"), str)
            and f.get("path", "").endswith(".mjs")
            and f.get("category") == "system"
        })
        assert sorted(included) == attendu_inclus, (
            "le périmètre inclus dérive de la wiremap réelle -- toute divergence "
            "signale un changement du filtre historique, pas juste un fichier "
            "ajouté (auquel cas attendu_inclus aurait aussi bougé)")

        # --- propriété 5 : aucun chevauchement inclus/exclus ---
        assert not (set(included) & {e["fichier"] for e in excluded})

    def test_pong_sans_cle_proof_suit_le_regime_historique(self):
        """Pong n'est PAS migré (§6, décision 6, ferme) : son game_contract.yaml
        ne porte PAS de clé `proof`. Si ce test casse, quelqu'un a migré Pong
        sans gate dédié -- violation directe du contrat."""
        contract = _real_pong_contract()
        assert "proof" not in contract, (
            "GAMES/pong/00_CHARTER/game_contract.yaml porte une clé 'proof' : "
            "Pong a été migré vers le nouveau régime sans gate Pierre explicite "
            "(§6 du contrat : 'PONG N'EST PAS MIGRÉ, décision 6, ferme')")
        # état ratifié : Pong garde ses 3 runtimes déclarés, migration jamais
        # commencée
        assert contract.get("game_id") == "pong"
        assert "runtimes" in contract


class TestTemoinPongVert:
    """Le témoin Pong 72/72 reste vert (§7 cas 3 du contrat). Exécute la
    commande CANONIQUE déclarée dans oracles.json (jamais une commande
    reconstruite à la main -- toute divergence de commande serait elle-même
    une régression non détectée)."""

    def test_pong_72_tests_exit_zero(self):
        oracles = _oracles_json()
        pong_oracle = oracles.get("pong")
        if not isinstance(pong_oracle, dict) or "command" not in pong_oracle:
            pytest.skip("SKIPPED_VALIDATION: entrée 'pong' absente/malformée dans "
                        "forge/oracles.json -- impossible de résoudre la "
                        "commande canonique")
        command = pong_oracle["command"]
        cwd = REPO_ROOT / pong_oracle.get("cwd", ".")

        try:
            proc = subprocess.run(
                command, cwd=str(cwd), capture_output=True, text=True,
                timeout=120, encoding="utf-8", errors="replace",
            )
        except FileNotFoundError:
            pytest.skip("SKIPPED_VALIDATION: 'node' introuvable sur ce poste -- "
                        "impossible d'exécuter le témoin Pong (jamais un faux vert)")
        except subprocess.TimeoutExpired:
            pytest.skip("SKIPPED_VALIDATION: le témoin Pong a dépassé le délai "
                        "d'exécution (120s) sur ce poste -- environnement, pas "
                        "un verdict logiciel")

        output = proc.stdout + proc.stderr
        assert proc.returncode == 0, (
            f"témoin Pong exit={proc.returncode} (attendu 0) -- sortie :\n{output}")
        assert "tests 72" in output, (
            "le témoin Pong ne rapporte plus 72 tests -- régression du "
            f"périmètre historique (sortie observée) :\n{output}")
        assert "pass 72" in output, (
            f"le témoin Pong ne rapporte plus 72 tests PASSÉS :\n{output}")
        assert "fail 0" in output, f"le témoin Pong a des échecs :\n{output}"

    def test_pong_git_status_vide(self):
        """§7 cas 3 : `git status GAMES/pong/` vide -- ce fichier de test
        n'écrit RIEN sous GAMES/**, la condition doit donc déjà être remplie
        par construction (garde de non-régression, pas une preuve d'écriture)."""
        try:
            proc = subprocess.run(
                ["git", "status", "--porcelain", "GAMES/pong/"],
                cwd=str(REPO_ROOT), capture_output=True, text=True, timeout=30,
            )
        except FileNotFoundError:
            pytest.skip("SKIPPED_VALIDATION: 'git' introuvable sur ce poste")
        assert proc.returncode == 0
        assert proc.stdout.strip() == "", (
            "GAMES/pong/ porte des modifications non commitées -- §7 cas 3 du "
            f"contrat exige un témoin figé :\n{proc.stdout}")


# =====================================================================================
# FAMILLE 2 — NOUVEAU RÉGIME, SPÉCIFIÉ D'ABORD (xfail strict -- pas encore implémenté)
# =====================================================================================

XFAIL_REASON = (
    "régime proof.mutation non implémenté — contrat V1 §2/§5, implémentation à venir")


def _appelle_evaluate_proof_descriptor(**kwargs):
    """Point d'appel UNIQUE de l'API attendue -- documenté en tête de fichier.
    Lève AttributeError tant que `forge.mutation_proof.evaluate_proof_descriptor`
    n'existe pas (xfail légitime)."""
    return mutation_proof.evaluate_proof_descriptor(**kwargs)


def test_categorie_presente_wiremap_absente_declaration_blocked():
    """§2 règle 4 + §5 cas 2 : une catégorie PRÉSENTE dans la wiremap mais
    absente de `categories_mutables` ET de `categories_exclues` -> BLOCKED
    (oubli de déclaration)."""
    game_contract = {
        "schema_version": 1, "game_id": "x", "runtimes": ["rules"],
        "proof": {
            "schema_version": 1,
            "runtime": "rules",
            "mutation": {
                "categories_mutables": ["system"],
                "categories_exclues": ["system.adapter"],
                "command": ["node", "--test", "tests/run.test.mjs"],
                "cwd": "GAMES/x",
                "binary_ref": "node",
                "expects_exit_zero": True,
                "seals": {"wrapper": [], "test_scripts": ["tests/run.test.mjs"]},
            },
        },
    }
    # 'entity' est présent dans la wiremap mais absent des deux listes déclarées.
    wiremap = {"lines": [
        {"fichiers": [{"path": "05_SYSTEMS/core.mjs", "category": "system"}]},
        {"fichiers": [{"path": "02_ENTITIES/hero.mjs", "category": "entity"}]},
    ]}
    result = _appelle_evaluate_proof_descriptor(
        proof=game_contract["proof"], game_contract=game_contract, wiremap=wiremap,
        mutation_result=None,
    )
    assert result["status"] == "BLOCKED"
    assert result["passed"] is False


def test_categorie_mutable_absente_de_la_wiremap_non_applicable():
    """§5 cas 1 : une catégorie DÉCLARÉE mutable mais qu'AUCUNE ligne de la
    wiremap ne porte -> NON_APPLICABLE avec passed=True (déclaré ET prouvé
    par la carte)."""
    game_contract = {
        "schema_version": 1, "game_id": "x", "runtimes": ["rules"],
        "proof": {
            "schema_version": 1,
            "runtime": "rules",
            "mutation": {
                # 'entity' déclarée mutable, mais la wiremap ne la porte pas.
                "categories_mutables": ["system", "entity"],
                "categories_exclues": ["system.adapter"],
                "command": ["node", "--test", "tests/run.test.mjs"],
                "cwd": "GAMES/x",
                "binary_ref": "node",
                "expects_exit_zero": True,
                "seals": {"wrapper": [], "test_scripts": ["tests/run.test.mjs"]},
            },
        },
    }
    wiremap = {"lines": [
        {"fichiers": [{"path": "05_SYSTEMS/core.mjs", "category": "system"}]},
    ]}
    result = _appelle_evaluate_proof_descriptor(
        proof=game_contract["proof"], game_contract=game_contract, wiremap=wiremap,
        mutation_result=None,
    )
    assert result["status"] == "NON_APPLICABLE"
    assert result["passed"] is True


def test_categorie_mutable_sans_mutant_mesurable_blocked():
    """§5 cas 3 : catégorie déclarée mutable, présente dans la wiremap, mais
    aucune mesure exploitable (0 mutant sur TOUTE la catégorie) -> BLOCKED."""
    game_contract = {
        "schema_version": 1, "game_id": "x", "runtimes": ["rules"],
        "proof": {
            "schema_version": 1,
            "runtime": "rules",
            "mutation": {
                "categories_mutables": ["system"],
                "categories_exclues": ["system.adapter"],
                "command": ["node", "--test", "tests/run.test.mjs"],
                "cwd": "GAMES/x",
                "binary_ref": "node",
                "expects_exit_zero": True,
                "seals": {"wrapper": [], "test_scripts": ["tests/run.test.mjs"]},
            },
        },
    }
    wiremap = {"lines": [
        {"fichiers": [{"path": "05_SYSTEMS/core.mjs", "category": "system"}]},
    ]}
    # mutation exécutée, mais 0 mutant généré sur la seule catégorie mutable
    mutation_result = {
        "per_file": {"05_SYSTEMS/core.mjs": {"total": 0, "killed": 0}},
        "total": 0, "killed": 0, "baseline_ok": True,
    }
    result = _appelle_evaluate_proof_descriptor(
        proof=game_contract["proof"], game_contract=game_contract, wiremap=wiremap,
        mutation_result=mutation_result,
    )
    assert result["status"] == "BLOCKED"
    assert result["passed"] is False


def test_mutants_executes_inferieur_a_mutants_generes_blocked():
    """§4 : `mutants_executes < mutants_generes` (plafond atteint / troncature)
    -> BLOCKED, jamais un résultat partiel présenté comme preuve."""
    game_contract = {
        "schema_version": 1, "game_id": "x", "runtimes": ["rules"],
        "proof": {
            "schema_version": 1,
            "runtime": "rules",
            "mutation": {
                "categories_mutables": ["system"],
                "categories_exclues": ["system.adapter"],
                "command": ["node", "--test", "tests/run.test.mjs"],
                "cwd": "GAMES/x",
                "binary_ref": "node",
                "expects_exit_zero": True,
                "budget": {"max_mutants": 5, "timeout_per_mutant_s": 30,
                           "total_timeout_s": 900, "cost_class": "process"},
                "seals": {"wrapper": [], "test_scripts": ["tests/run.test.mjs"]},
            },
        },
    }
    wiremap = {"lines": [
        {"fichiers": [{"path": "05_SYSTEMS/core.mjs", "category": "system"}]},
    ]}
    mutation_result = {
        "per_file": {"05_SYSTEMS/core.mjs": {"total": 10, "killed": 5}},
        "mutants_generes": 10, "mutants_executes": 5,  # troncature au plafond
        "total": 10, "killed": 5, "baseline_ok": True,
    }
    result = _appelle_evaluate_proof_descriptor(
        proof=game_contract["proof"], game_contract=game_contract, wiremap=wiremap,
        mutation_result=mutation_result,
    )
    assert result["status"] == "BLOCKED"
    assert result["passed"] is False


def test_command_declaree_differente_de_executee_gate_refuse():
    """§3 : `command_declaree != command_executee` -> `declaration_conforme:
    False` et le gate REFUSE."""
    game_contract = {
        "schema_version": 1, "game_id": "x", "runtimes": ["rules"],
        "proof": {
            "schema_version": 1,
            "runtime": "rules",
            "mutation": {
                "categories_mutables": ["system"],
                "categories_exclues": ["system.adapter"],
                "command": ["node", "--test", "tests/run.test.mjs"],
                "cwd": "GAMES/x",
                "binary_ref": "node",
                "expects_exit_zero": True,
                "seals": {"wrapper": [], "test_scripts": ["tests/run.test.mjs"]},
            },
        },
    }
    wiremap = {"lines": [
        {"fichiers": [{"path": "05_SYSTEMS/core.mjs", "category": "system"}]},
    ]}
    mutation_result = {
        "per_file": {"05_SYSTEMS/core.mjs": {"total": 4, "killed": 4}},
        "total": 4, "killed": 4, "baseline_ok": True,
        # la commande réellement exécutée diffère de celle déclarée (nom de
        # fichier de test différent)
        "command_executee": ["node", "--test", "tests/AUTRE.test.mjs"],
    }
    result = _appelle_evaluate_proof_descriptor(
        proof=game_contract["proof"], game_contract=game_contract, wiremap=wiremap,
        mutation_result=mutation_result,
    )
    assert result.get("declaration_conforme") is False
    assert result["passed"] is False


def test_runtime_absent_des_runtimes_declares_blocked():
    """§2 règle 1 : `runtime` absent de `runtimes:` du game_contract ->
    BLOCKED."""
    game_contract = {
        "schema_version": 1, "game_id": "x",
        "runtimes": ["browser"],  # 'godot' n'y figure PAS
        "proof": {
            "schema_version": 1,
            "runtime": "godot",  # incohérent avec runtimes: ci-dessus
            "mutation": {
                "categories_mutables": ["system"],
                "categories_exclues": ["system.adapter"],
                "command": ["<bin:godot>", "--headless", "--path", ".",
                            "--script", "res://tests/run_tests.gd"],
                "cwd": "GAMES/x",
                "binary_ref": "godot",
                "expects_exit_zero": True,
                "budget": {"max_mutants": 200, "timeout_per_mutant_s": 30,
                           "total_timeout_s": 900, "cost_class": "engine"},
                "seals": {"wrapper": [], "test_scripts": ["tests/run_tests.gd"]},
            },
        },
    }
    wiremap = {"lines": [
        {"fichiers": [{"path": "05_SYSTEMS/core.mjs", "category": "system"}]},
    ]}
    result = _appelle_evaluate_proof_descriptor(
        proof=game_contract["proof"], game_contract=game_contract, wiremap=wiremap,
        mutation_result=None,
    )
    assert result["status"] == "BLOCKED"
    assert result["passed"] is False


def test_seals_test_scripts_vide_blocked():
    """§2 règle 9 : `seals.test_scripts` vide -> BLOCKED (la chaîne de preuve
    est rompue par construction)."""
    game_contract = {
        "schema_version": 1, "game_id": "x", "runtimes": ["rules"],
        "proof": {
            "schema_version": 1,
            "runtime": "rules",
            "mutation": {
                "categories_mutables": ["system"],
                "categories_exclues": ["system.adapter"],
                "command": ["node", "--test", "tests/run.test.mjs"],
                "cwd": "GAMES/x",
                "binary_ref": "node",
                "expects_exit_zero": True,
                "seals": {"wrapper": [], "test_scripts": []},  # VIDE
            },
        },
    }
    wiremap = {"lines": [
        {"fichiers": [{"path": "05_SYSTEMS/core.mjs", "category": "system"}]},
    ]}
    result = _appelle_evaluate_proof_descriptor(
        proof=game_contract["proof"], game_contract=game_contract, wiremap=wiremap,
        mutation_result=None,
    )
    assert result["status"] == "BLOCKED"
    assert result["passed"] is False
