"""RUN 2 V1 — point A7 du protocole (docs/forge/RUN2_PROTOCOLE_V1_PROPOSED.md) :
« Acquis du moteur repris comme prérequis de paire ». Les gardes corrigées au
sas R3/freeze (C1 cible déclarée, C2 micro-re-déclaration, C3
`modification_locus`/`aucune_requise`, commit 6e5e7da) doivent être des
PRÉREQUIS MÉCANIQUEMENT BLOCANTS de toute paire 2 — pas seulement une ligne
dans un document.

Ce module ne fait AUCUNE inférence LM et ne lance AUCUN run/paire. Il vérifie
la PRÉSENCE RÉELLE dans le code des trois gardes du sas R3/freeze, plus,
optionnellement (`--run-tests`), l'exécution fraîche de leurs suites de tests
dédiées. Doctrine : un contrôle indisponible ou dont l'introspection échoue
est `ok: False` avec une raison nommée -- jamais un vert par défaut.

C1 : `forge.driver.ForgeDriver._answer_modification_locus` (méthode de classe
     qui lit `answer.modification_locus.type` plutôt que de deviner la cible
     depuis le loop_id) + `forge/tests/test_r3_locus.py` présent.
C2 : `forge.driver.ForgeDriver._maybe_run_micro_redeclarations` (méthode
     d'instance qui déclenche la micro-re-déclaration réelle) +
     `forge/tests/test_micro_redeclaration.py` présent.
C3 : `forge.run_real._MODIFICATION_LOCUS_TYPES` (constante qui borne les
     valeurs acceptées/refusées de `modification_locus.type` au canal).
"""
from __future__ import annotations

import argparse
import importlib
import inspect
import subprocess
import sys
from pathlib import Path
from typing import Any

REPO_ROOT_DEFAULT = Path(__file__).resolve().parents[1]

_TEST_R3_LOCUS = "test_r3_locus.py"
_TEST_MICRO_REDECLARATION = "test_micro_redeclaration.py"
# Registre de non-régression de paire (pré-enregistrement P4, 2026-09-01) : les
# fixtures des findings des paires passées gardent la gate — paire 2 (finding 7 :
# charter bloquant ; finding 8 : tick de mesure) et paire 3 (P3-2 : chemins
# wiremap repo-relatifs + crash→HALT). Une suite absente = préflight FAIL.
_TESTS_PAIR_FIXTURES = (
    "test_charter_gate.py",
    "test_measure_tick.py",
    "test_mutation_path_repo_relative.py",
)


def _check_c1(repo_root: Path) -> dict[str, Any]:
    """C1 : cible déclarée -- `ForgeDriver._answer_modification_locus` existe
    réellement (introspection de l'attribut, pas un grep de claim) ET le
    fichier de test dédié est présent sur disque."""
    check_id = "C1_target_declared"
    try:
        driver_mod = importlib.import_module("forge.driver")
        driver_cls = getattr(driver_mod, "ForgeDriver")
    except Exception as exc:  # import cassé = prérequis non prouvable
        return {"id": check_id, "ok": False, "detail": f"import forge.driver impossible : {exc!r}"}

    method = getattr(driver_cls, "_answer_modification_locus", None)
    if method is None or not callable(method):
        return {
            "id": check_id,
            "ok": False,
            "detail": "ForgeDriver._answer_modification_locus absente (méthode C1 non trouvée)",
        }

    test_path = repo_root / "forge" / "tests" / _TEST_R3_LOCUS
    if not test_path.is_file():
        return {
            "id": check_id,
            "ok": False,
            "detail": f"méthode présente mais {test_path} absent",
        }

    return {
        "id": check_id,
        "ok": True,
        "detail": "ForgeDriver._answer_modification_locus présente + test_r3_locus.py présent",
    }


def _check_c2(repo_root: Path) -> dict[str, Any]:
    """C2 : micro-re-déclaration réelle -- `ForgeDriver._maybe_run_micro_redeclarations`
    existe réellement ET le fichier de test dédié est présent."""
    check_id = "C2_micro_redeclaration"
    try:
        driver_mod = importlib.import_module("forge.driver")
        driver_cls = getattr(driver_mod, "ForgeDriver")
    except Exception as exc:
        return {"id": check_id, "ok": False, "detail": f"import forge.driver impossible : {exc!r}"}

    method = getattr(driver_cls, "_maybe_run_micro_redeclarations", None)
    if method is None or not callable(method):
        return {
            "id": check_id,
            "ok": False,
            "detail": "ForgeDriver._maybe_run_micro_redeclarations absente (méthode C2 non trouvée)",
        }

    test_path = repo_root / "forge" / "tests" / _TEST_MICRO_REDECLARATION
    if not test_path.is_file():
        return {
            "id": check_id,
            "ok": False,
            "detail": f"méthode présente mais {test_path} absent",
        }

    return {
        "id": check_id,
        "ok": True,
        "detail": "ForgeDriver._maybe_run_micro_redeclarations présente + test_micro_redeclaration.py présent",
    }


def _check_c3(repo_root: Path) -> dict[str, Any]:
    """C3 : validation canal `modification_locus` -- `run_real._MODIFICATION_LOCUS_TYPES`
    existe réellement et borne au moins les 3 valeurs attendues du sas."""
    check_id = "C3_modification_locus_channel"
    try:
        run_real_mod = importlib.import_module("forge.run_real")
    except Exception as exc:
        return {"id": check_id, "ok": False, "detail": f"import forge.run_real impossible : {exc!r}"}

    types = getattr(run_real_mod, "_MODIFICATION_LOCUS_TYPES", None)
    if types is None:
        return {
            "id": check_id,
            "ok": False,
            "detail": "run_real._MODIFICATION_LOCUS_TYPES absente (constante C3 non trouvée)",
        }
    if not isinstance(types, (tuple, list, set, frozenset)) or len(types) == 0:
        return {
            "id": check_id,
            "ok": False,
            "detail": f"run_real._MODIFICATION_LOCUS_TYPES présente mais vide/mal typée : {types!r}",
        }

    expected = {"gm_worldscan", "art_bible", "aucune_requise"}
    missing = expected - set(types)
    if missing:
        return {
            "id": check_id,
            "ok": False,
            "detail": f"run_real._MODIFICATION_LOCUS_TYPES incomplète, manque : {sorted(missing)}",
        }

    return {
        "id": check_id,
        "ok": True,
        "detail": f"run_real._MODIFICATION_LOCUS_TYPES = {tuple(types)!r}",
    }


def _run_dedicated_tests(repo_root: Path) -> dict[str, Any]:
    """Exécute en subprocess les deux suites de tests dédiées C1/C2, marqueur
    `not gpu_window` (aucun test GPU dans ce périmètre). C'est la preuve
    d'exécution FRAÎCHE -- sans cette option, pair_preflight ne fait qu'un
    contrôle de présence (voir detail honnête dans le check appelant)."""
    test_dir = repo_root / "forge" / "tests"
    targets = [
        str(test_dir / _TEST_R3_LOCUS),
        str(test_dir / _TEST_MICRO_REDECLARATION),
        *(str(test_dir / name) for name in _TESTS_PAIR_FIXTURES),
    ]
    missing = [t for t in targets if not Path(t).is_file()]
    if missing:
        return {
            "ok": False,
            "detail": f"suite(s) de non-régression absente(s) : {missing}",
        }
    cmd = [
        sys.executable,
        "-m",
        "pytest",
        *targets,
        "-m",
        "not gpu_window",
        "-q",
    ]
    try:
        proc = subprocess.run(
            cmd,
            cwd=str(repo_root),
            capture_output=True,
            text=True,
            timeout=600,
        )
    except Exception as exc:
        return {
            "id": "run_tests_subprocess",
            "ok": False,
            "detail": f"échec de lancement subprocess pytest : {exc!r}",
        }

    ok = proc.returncode == 0
    tail = "\n".join((proc.stdout or "").splitlines()[-15:])
    return {
        "id": "run_tests_subprocess",
        "ok": ok,
        "detail": f"pytest exit={proc.returncode} (cmd={' '.join(targets)}) -- tail:\n{tail}",
    }


def check_pair_prerequisites(repo_root: Path | str | None = None, run_tests: bool = False) -> dict[str, Any]:
    """Point d'entrée A7. Retourne {ok, checks: [...], raisons: [...]}.

    `ok` global est True SEULEMENT si les 3 gardes C1/C2/C3 sont présentes
    (et, si `run_tests=True`, si leurs suites dédiées passent réellement).
    Aucune exception n'est avalée en un vert par défaut : toute erreur
    d'introspection se traduit par un check `ok: False` nommé.
    """
    root = Path(repo_root) if repo_root is not None else REPO_ROOT_DEFAULT
    root = root.resolve()

    # Import depuis `forge.*` suppose que `scripts/` est sur PYTHONPATH (comme
    # les tests existants, ex. test_r3_locus.py). On l'ajoute défensivement le
    # temps de l'introspection si absent, sans modifier sys.path durablement
    # au-delà de cet appel.
    scripts_dir = str(root)
    added_to_path = False
    if scripts_dir not in sys.path:
        sys.path.insert(0, scripts_dir)
        added_to_path = True

    try:
        checks = [_check_c1(root), _check_c2(root), _check_c3(root)]

        ran_tests_detail: dict[str, Any] | None = None
        if run_tests:
            ran_tests_detail = _run_dedicated_tests(root)
            checks.append(ran_tests_detail)
        else:
            checks.append(
                {
                    "id": "run_tests_subprocess",
                    "ok": True,
                    "detail": (
                        "--run-tests non demandé : contrôle de PRÉSENCE seul, "
                        "PAS de preuve d'exécution fraîche des tests C1/C2"
                    ),
                    "advisory": True,
                }
            )
    finally:
        if added_to_path and scripts_dir in sys.path:
            sys.path.remove(scripts_dir)

    raisons = [c["detail"] for c in checks if not c["ok"]]
    # Le check "run_tests_subprocess" en mode non-demandé est toujours ok:True
    # (c'est un statut informatif, pas un blocage), donc `ok` global ignore
    # les entrées marquées advisory pour le calcul, elles restent listées.
    blocking_checks = [c for c in checks if not c.get("advisory", False)]
    ok = all(c["ok"] for c in blocking_checks)

    return {"ok": ok, "checks": checks, "raisons": raisons}


def _main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="forge.pair_preflight",
        description="Prérequis de paire bloquants RUN 2 V1 (A7) -- vérifie C1/C2/C3 mécaniquement.",
    )
    parser.add_argument(
        "--run-tests",
        action="store_true",
        help="exécute en plus test_r3_locus.py + test_micro_redeclaration.py (-m 'not gpu_window') et exige le vert",
    )
    parser.add_argument(
        "--repo-root",
        default=None,
        help="racine du repo (défaut : détectée depuis ce fichier)",
    )
    args = parser.parse_args(argv)

    result = check_pair_prerequisites(repo_root=args.repo_root, run_tests=args.run_tests)

    for c in result["checks"]:
        status = "OK" if c["ok"] else "FAIL"
        print(f"[{status}] {c['id']}: {c['detail']}")

    if result["ok"]:
        print("PAIR_PREFLIGHT: OK -- prérequis de paire satisfaits")
        return 0

    print("PAIR_PREFLIGHT: FAIL -- raisons :")
    for r in result["raisons"]:
        print(f"  - {r}")
    return 1


if __name__ == "__main__":
    raise SystemExit(_main())
