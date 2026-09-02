"""Reçu mutation signé (P0.2) — ferme les trous I1/I2 du chemin critique.

I1 : le gate mutation vivait HORS de l'oracle (`run-oracle.mjs` ne le câble pas,
skill.md le pilotait en prose) — un vert s10a était possible sans mutation.
I2 : un `mutation_triage.json` périmé (écrit pour un ancien code) n'était jamais
invalidé — breakout prétendait 100% quand le run réel disait 21%.

Ce module NE réimplémente NI ne déplace la logique mutation :
  - l'exécution reste `forge.mutation.run_mutation_test` (appelée, pas copiée) ;
  - le juge reste `forge.static_oracles.check_mutation_gate` (100%-ou-triage) ;
  - la signature reste `forge.verdict.make_signed_receipt` (HMAC commun).

Il AJOUTE la liaison de preuve : le reçu scelle (run_id, statut du gate, sha256
des fichiers logiques ET des fichiers de tests, sha256 du triage, évidence).
`verify_mutation_receipt` refuse : preuve absente, signature invalide, run_id
incohérent, statut non vert, hash code/tests divergent (fraîcheur), triage
modifié après la preuve, évidence altérée. Hypothèse inconnue => refus.
claim_verdict: NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
import logging
import time
from pathlib import Path

from forge.mutation import comment_prefixes_for, generate_mutants, run_mutation_test
from forge.static_oracles import check_mutation_gate, load_mutation_triage
from forge.verdict import (
    OracleReceipt,
    SignedReceipt,
    make_signed_receipt,
    sha256_file,
    verify_receipt,
    sha256_evidence,
)

logger = logging.getLogger(__name__)

# Commande de test par défaut d'un jeu forge (skill.md, gate mutation) —
# surchargée par étape via `test_argv` quand le jeu déclare d'autres suites.
DEFAULT_TEST_ARGV = ("node", "--test", "logic.test.mjs", "properties.test.mjs")

TRIAGE_FILENAME = "mutation_triage.json"


# --- périmètre du gate mutation PAR CATÉGORIE (décision U-2, ratifiée Pierre
# 2026-07-27 : « la mutation ne doit pas essayer de juger ce qu'elle ne peut
# pas atteindre. logique testable -> mutation ; rendu/runtime -> oracle produit.
# Sinon on fabrique un faux indicateur. ») ---------------------------------------

# Catégorie (table figée `standard/repo_map.yaml`) structurellement hors de
# portée du gate mutation : présentation/runtime (06_RUNTIME/adapters/{id}/).
# Preuve mesurée (run pong_r2, évidence signée `mutation_pong_r2.json`) : les 7
# fichiers `system.adapter` de Pong sont 0/65 tués -- la suite scellée
# (07_TESTS/unit/*.test.mjs + 07_TESTS/oracle/solvability.mjs) n'importe AUCUN
# fichier d'adaptateur (vérifié par grep des imports). Les muter mesure un 0%
# GARANTI par construction, jamais un défaut de test -- ce n'est pas une
# métrique, c'est un artefact de topologie.
CATEGORIE_PRESENTATION_RUNTIME = "system.adapter"

MOTIF_EXCLUSION_PRESENTATION_RUNTIME = (
    "catégorie system.adapter (présentation/runtime, 06_RUNTIME/adapters/) : "
    "jamais importée par la suite scellée (07_TESTS/unit/*.test.mjs + "
    "07_TESTS/oracle/solvability.mjs) -- structurellement intuable par mutation "
    "(mesuré pong_r2 : 0/65 tués) -- à couvrir par l'oracle produit ; le juge "
    "change, la couche n'est pas abandonnée"
)


def mutation_scope_from_wiremap(wiremap: dict) -> dict:
    """Périmètre du gate mutation, dérivé de la WireMap -- formule UNIQUE
    (décision U-2), non dupliquée ailleurs (driver.py normalise la FORME,
    jamais la règle).

    Sépare les fichiers `.mjs` non-test cités dans `features[*].fichiers` en :
      - `included`  : jugés par la mutation (catégorie absente -- wiremap
        LEGACY, formule historique inchangée -- ou toute catégorie autre que
        `system.adapter` : `system`, `entity*`, `level`, `world.rules`...) ;
      - `excluded`   : catégorie `system.adapter`, présentation/runtime,
        DÉCLARÉE avec fichier/catégorie/motif -- jamais silencieuse (garde-fou
        2 du contrat n2-perimetre-mutation-categorie) ;
      - `categories` : {fichier inclus: catégorie}, pour les compteurs aval
        (`categorized_mutation_counts`).

    `test.*` reste filtré EN AMONT (c'est de la PREUVE, jamais du code à
    muter -- comportement historique inchangé, cf. commentaire déjà présent
    dans driver.py sur l'échec de l'heuristique de nom en topologie STANDARD).
    """
    included: list[str] = []
    excluded: list[dict] = []
    categories: dict[str, str] = {}
    seen: set[str] = set()
    for feat in (wiremap.get("features", []) if isinstance(wiremap, dict) else []):
        if not isinstance(feat, dict):
            continue
        for f in (feat.get("fichiers") or []):
            if isinstance(f, dict):
                path, category = f.get("path"), f.get("category")
            else:
                path, category = f, None
            if not isinstance(path, str):
                continue
            if isinstance(category, str) and category.startswith("test."):
                continue  # preuve, pas du code -- filtre inchangé
            if not (path.endswith(".mjs") and "test" not in path):
                continue
            if path in seen:
                continue
            seen.add(path)
            if category:
                categories[path] = category
            if category == CATEGORIE_PRESENTATION_RUNTIME:
                excluded.append({"fichier": path, "categorie": category,
                                  "motif": MOTIF_EXCLUSION_PRESENTATION_RUNTIME})
            else:
                included.append(path)
    return {
        "included": sorted(included),
        "excluded": sorted(excluded, key=lambda e: e["fichier"]),
        "categories": categories,
    }


def categorized_mutation_counts(mutation_result: dict, scope: dict) -> dict:
    """Compteurs de mutation PAR CATÉGORIE (décision U-2) : pour chaque
    catégorie JUGÉE (fichiers de `scope["included"]`), agrège killed/total
    depuis `mutation_result["per_file"]` ; pour chaque catégorie EXCLUE
    (`scope["excluded"]`), ne rapporte QUE le nombre de fichiers -- jamais un
    killed/total forgé pour une catégorie non jugée (ce serait exactement le
    faux indicateur que la décision U-2 interdit : une catégorie qu'on n'a
    pas mesurée n'a pas de score, point).
    """
    per_file = mutation_result.get("per_file") or {}
    categories = scope.get("categories") or {}
    counts: dict[str, dict] = {}
    for path in scope.get("included", []):
        cat = categories.get(path, "sans_categorie")
        entry = counts.setdefault(
            cat, {"jugee": True, "fichiers": 0, "killed": 0, "total": 0})
        entry["fichiers"] += 1
        pf = per_file.get(path) or {}
        entry["killed"] += int(pf.get("killed", 0))
        entry["total"] += int(pf.get("total", 0))
    for exc in scope.get("excluded", []):
        cat = exc.get("categorie", "sans_categorie")
        entry = counts.setdefault(cat, {"jugee": False, "fichiers": 0})
        entry["fichiers"] += 1
    return counts


def logic_files_from_wiremap(wiremap: dict) -> list[str]:
    """Fichiers logiques à muter (rétro-compat : signature historique).
    Délègue à `mutation_scope_from_wiremap` -- formule UNIQUE, non dupliquée --
    et ne retourne que les fichiers INCLUS (jugés)."""
    return mutation_scope_from_wiremap(wiremap)["included"]


def fingerprint(game_dir: Path | str, files: list[str]) -> dict[str, str]:
    """{fichier relatif: sha256 du contenu}. '' si illisible (=> divergence à la vérif)."""
    game_dir = Path(game_dir)
    return {f: sha256_file(game_dir / f) for f in sorted(set(files))}


def _default_baseline_runner(test_argv: list[str], cwd: Path | str,
                             timeout: int = 120) -> bool:
    """La suite passe-t-elle sur le code NON muté ? Même résolution d'exécutable
    que forge.mutation (Windows : `node` -> node.exe via which)."""
    import shutil
    import subprocess
    exe = shutil.which(test_argv[0]) or test_argv[0]
    try:
        proc = subprocess.run([exe, *test_argv[1:]], cwd=str(Path(cwd).resolve()),
                              capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return False  # suite inexécutable = baseline non prouvée, jamais un vert
    return proc.returncode == 0


def run_mutation_for_game(
    game_dir: Path | str,
    logic_files: list[str],
    test_argv: list[str] | tuple[str, ...] | None = None,
    runner=None,
    baseline_runner=None,
) -> dict:
    """Agrège la mutation sur tous les fichiers logiques (même agrégat que skill.md).

    `runner` est injectable pour les tests ; par défaut c'est le VRAI
    `forge.mutation.run_mutation_test` — jamais une réimplémentation.

    P0.3 — baseline verte OBLIGATOIRE : une suite déjà rouge sur le code non muté
    « tue » tout mutant artificiellement (returncode != 0 partout) — 100% de
    score sans rien prouver. `baseline_ok` est mesuré AVANT la mutation et scellé
    dans le reçu ; baseline rouge => la mutation n'est même pas lancée.
    """
    game_dir = Path(game_dir)
    argv = list(test_argv or DEFAULT_TEST_ARGV)
    baseline = baseline_runner or _default_baseline_runner
    baseline_ok = bool(baseline(argv, game_dir))
    survivors: list[dict] = []
    total = killed = 0
    per_file: dict[str, dict] = {}
    if baseline_ok:
        run = runner or run_mutation_test
        for f in logic_files:
            r = run(game_dir / f, argv, cwd=game_dir)
            survivors += list(r.get("survivors", []))
            total += int(r.get("total", 0))
            killed += int(r.get("killed", 0))
            per_file[f] = {"total": int(r.get("total", 0)),
                           "killed": int(r.get("killed", 0))}
    else:
        logger.warning("baseline ROUGE sur code non muté — mutation non lancée "
                       "(le score serait un artefact)")
    return {
        "total": total,
        "killed": killed,
        "survived": len(survivors),
        "survivors": survivors,
        "per_file": per_file,
        "test_argv": argv,
        "baseline_ok": baseline_ok,
    }


def emit_mutation_receipt(
    run_id: str,
    game_dir: Path | str,
    logic_files: list[str],
    mutation_result: dict,
    *,
    key_file: Path | None = None,
    evidence_dir: Path | str | None = None,
    mutation_scope: dict | None = None,
) -> SignedReceipt:
    """Juge (check_mutation_gate, inchangé) puis scelle la preuve dans un reçu signé.

    Le sceau couvre le code mutable ET les fichiers de tests présents dans la
    commande de test : affaiblir la suite après la preuve invalide la preuve.

    `mutation_scope` (décision U-2, optionnel -- absent pour les appelants
    historiques qui passent un `logic_files` explicite sans wiremap) : le
    reçu porte alors les exclusions de catégorie DÉCLARÉES (fichier,
    catégorie, motif -- jamais silencieuses) et des compteurs par catégorie.
    Sans scope, la structure reste stable (categories_exclues=[], une seule
    catégorie "sans_categorie") -- le reçu ne dépend pas du chemin d'appel.
    """
    game_dir = Path(game_dir)
    scope = mutation_scope or {"included": list(logic_files), "excluded": [],
                                "categories": {}}
    gate = check_mutation_gate(mutation_result, load_mutation_triage(game_dir))
    # P0.3 : sans baseline verte MESURÉE (True explicite — un résultat sans le
    # champ n'est pas une preuve), le gate ne peut pas être vert.
    baseline_ok = mutation_result.get("baseline_ok") is True
    status = "OK" if (gate["passed"] and baseline_ok) else "FAIL"
    argv = list(mutation_result.get("test_argv") or DEFAULT_TEST_ARGV)
    test_files = [a for a in argv if (game_dir / a).exists()]
    # Le harnais e2e fait partie du code jugé : présent, il est scellé (l'échanger
    # après la preuve invalide la preuve, même classe de menace que les tests).
    harness_files = [f for f in ("run-oracle.mjs", "e2e.mjs") if (game_dir / f).exists()]
    detail = {
        "game_dir": str(game_dir),
        "logic_files": sorted(set(logic_files)),
        "test_argv": argv,
        "test_files_scelles": sorted(test_files),
        "baseline_ok": baseline_ok,
        "total": int(mutation_result.get("total", 0)),
        "killed": int(mutation_result.get("killed", 0)),
        "survived": int(mutation_result.get("survived", 0)),
        "survivants_non_tries": gate["survivants_non_tries"],
        "gate_checked": gate["checked"],
        # Doctrine P0.3 : un survivant trié franchit le gate mais reste une exception
        # tracée — propagée au verdict, qui refuse alors un OK propre (HumanGate).
        "mutation_exception": gate.get("exception", False),
        "triaged_survivors": gate.get("triaged_survivors", []),
        "code_sha256": fingerprint(game_dir,
                                   list(logic_files) + test_files + harness_files),
        "triage_sha256": sha256_file(game_dir / TRIAGE_FILENAME),
        # décision U-2 : le périmètre restreint est DÉCLARÉ, jamais silencieux.
        "categories_exclues": scope.get("excluded", []),
        "compteurs_par_categorie": categorized_mutation_counts(mutation_result, scope),
    }
    evidence_path = ""
    if evidence_dir is not None:
        evidence_dir = Path(evidence_dir)
        evidence_dir.mkdir(parents=True, exist_ok=True)
        evidence = evidence_dir / f"mutation_{run_id}.json"
        # `newline=""` : sans lui, le mode TEXTE ecrit du CRLF sous Windows, que git
        # renormalise en LF au commit — et `evidence_sha256` hache les OCTETS. Le sceau
        # serait donc INVALIDE des le commit, sans qu'aucune donnee soit alteree.
        evidence.write_text(
            json.dumps({"mutation_result": mutation_result, "gate": gate,
                        "detail": detail},
                       ensure_ascii=False, sort_keys=True, indent=1),
            encoding="utf-8", newline="",
        )
        evidence_path = str(evidence)
    logger.info("reçu mutation %s: %s (%s/%s tués)", run_id, status,
                detail["killed"], detail["total"])
    return make_signed_receipt(
        "mutation", run_id, status, detail,
        evidence_path=evidence_path, ts=time.time(), key_file=key_file,
    )


def verify_mutation_receipt(
    receipt_dict: dict | None,
    signature: str,
    run_id: str,
    game_dir: Path | str,
    *,
    key_file: Path | None = None,
    require_green: bool = True,
) -> dict:
    """Vérifie une preuve mutation CONTRE l'état PRÉSENT du jeu.

    Retourne {passed, raisons[], status}. `status` (valeur brute de
    ``receipt.status``, "" quand aucun reçu n'a pu être construit) est TOUJOURS
    présent : aucun appelant ne doit parser une chaîne française pour connaître
    le statut (V1, design imposé pt.1).

    Refus si : preuve absente/malformée, signature invalide (provenance), run_id
    incohérent, empreinte absente, hash code/tests divergent, triage modifié
    après la preuve, évidence altérée — INCONDITIONNEL, quel que soit
    `require_green`.

    `require_green` (KEYWORD-ONLY, défaut True = comportement historique
    inchangé — c'est le gate mutation DUR du driver, driver.py:846, qui ne
    passe jamais ce paramètre) : quand True, un statut différent de "OK" est
    AUSSI un refus ("gate mutation non vert"). Quand False (utilisé par
    `verify_run` pour distinguer authenticité et verdict logiciel, V1), cette
    seule raison est omise — un reçu mutation FAIL authentique et à jour reste
    `passed=True` (il ne ment sur rien), seul le statut rapporté (`status`)
    dit que le gate est rouge.
    """
    if not isinstance(receipt_dict, dict) or not signature:
        return {"passed": False, "raisons": ["preuve mutation absente ou malformée"],
                "status": ""}
    try:
        receipt = OracleReceipt(**receipt_dict)
    except TypeError:
        return {"passed": False, "raisons": ["reçu mutation malformé (champs inattendus)"],
                "status": ""}
    if not verify_receipt(receipt, signature, key_file):
        # Contenu non fiable : inutile (et trompeur) d'énumérer d'autres raisons.
        return {"passed": False,
                "raisons": ["provenance rompue: signature du reçu mutation invalide"],
                "status": receipt.status}

    raisons: list[str] = []
    if receipt.oracle_id != "mutation":
        raisons.append(f"oracle_id inattendu ({receipt.oracle_id!r} != 'mutation')")
    if receipt.run_id != run_id:
        raisons.append(f"run_id incohérent ({receipt.run_id!r} != {run_id!r})")
    if require_green and receipt.status != "OK":
        raisons.append(f"gate mutation non vert (status={receipt.status})")

    detail = receipt.detail or {}
    game_dir = Path(game_dir)
    prints = detail.get("code_sha256") or {}
    if not prints:
        raisons.append("empreinte code absente du reçu mutation")
    if not detail.get("test_files_scelles"):
        raisons.append(
            "aucun fichier de test scellé (commande de test indirecte ?) — "
            "fraîcheur de la suite non prouvable ; nommer les fichiers de test "
            "dans test_argv")
    if detail.get("baseline_ok") is not True:
        raisons.append(
            "baseline verte non prouvée (suite rouge sur code non muté, ou reçu "
            "sans mesure de baseline) — le score de mutation est un artefact")
    for f, expected in sorted(prints.items()):
        if not expected:
            raisons.append(
                f"empreinte illisible/absente au moment de la preuve: {f} "
                "(fichier inexistant scellé '' — jamais un vert)")
        elif sha256_file(game_dir / f) != expected:
            raisons.append(
                f"hash code divergent: {f} (le code testé n'est plus le code présent)")
    if sha256_file(game_dir / TRIAGE_FILENAME) != detail.get("triage_sha256", ""):
        raisons.append(
            "triage modifié après la preuve mutation (mutation_triage.json divergent)")
    # sceau VIDE = rien promis (flux non scellable) : ne pas inventer une rupture.
    if (receipt.evidence_path and receipt.evidence_sha256
            and sha256_evidence(receipt.evidence_path) != receipt.evidence_sha256):
        raisons.append(f"évidence mutation altérée/absente ({receipt.evidence_path})")

    return {"passed": not raisons, "raisons": raisons, "status": receipt.status}


# =====================================================================================
# CONTRAT DE PREUVE DE MUTATION V1 (docs/forge/CONTRAT_PREUVE_MUTATION_V1.md, FIGÉ,
# ratifié Pierre 2026-07-28) — moteur PUR, sans effet de bord.
#
# COEXISTENCE (§6, §7) : ce moteur ne remplace RIEN du régime historique ci-dessus
# (`mutation_scope_from_wiremap`, `emit_mutation_receipt`, le filtre `.mjs`) — Pong
# reste sur l'ancien chemin, intégralement inchangé. `evaluate_proof_descriptor` est
# le NOUVEAU chemin, utilisé uniquement quand un jeu déclare `proof:` dans son
# `game_contract.yaml` (Snake, à ce jour). L'intégration driver (quel appelant
# invoque cette fonction, quand) est HORS PÉRIMÈTRE de cette phase (§8 : « brancher
# le driver ← seulement après ② vert ») — voir forge/tests/
# test_mutation_regime_coexistence.py pour le cahier des charges complet de la
# signature.
# =====================================================================================


def _wiremap_file_categories(wiremap: dict) -> dict[str, str]:
    """{chemin: catégorie} pour toutes les entrées `fichiers[]` de forme objet
    ({path, category}) présentes dans `wiremap['lines']` (schema_version 2,
    STANDARD) OU `wiremap['features']` (LEGACY) — les deux clés sont consultées,
    jamais une seule, pour ne pas dépendre du schéma de wiremap d'un jeu donné.
    Les entrées de forme chaîne nue (pas de catégorie connue) sont ignorées : une
    catégorie absente ne peut pas entrer dans une déclaration `categories_*`."""
    result: dict[str, str] = {}
    if not isinstance(wiremap, dict):
        return result
    for key in ("lines", "features"):
        for item in (wiremap.get(key) or []):
            if not isinstance(item, dict):
                continue
            for f in (item.get("fichiers") or []):
                if isinstance(f, dict):
                    path, category = f.get("path"), f.get("category")
                    if isinstance(path, str) and isinstance(category, str):
                        result[path] = category
    return result


def _commands_conformes(command_declaree, command_executee) -> bool:
    """§3 : `command_declaree` vs `command_executee`. Le contrat prévoit
    EXPLICITEMENT que le premier token puisse être un placeholder résolu à
    l'exécution (`<bin:godot>` -> chemin réel du binaire, cf. l'exemple scellé
    du contrat §3 où `declaration_conforme: true` malgré cette substitution) --
    seule cette substitution précise est légitime ; toute autre divergence
    (nom de fichier de test échangé, argument supplémentaire...) est une vraie
    divergence de preuve, jamais tolérée."""
    if not isinstance(command_declaree, list) or not isinstance(command_executee, list):
        return command_declaree == command_executee
    if len(command_declaree) != len(command_executee):
        return False
    for i, (declare, execute) in enumerate(zip(command_declaree, command_executee)):
        if (i == 0 and isinstance(declare, str)
                and declare.startswith("<bin:") and declare.endswith(">")):
            continue  # binaire résolu à l'exécution -- substitution légitime (§3)
        if declare != execute:
            return False
    return True


def evaluate_proof_descriptor(
    proof: dict,
    game_contract: dict,
    wiremap: dict,
    mutation_result: dict | None = None,
) -> dict:
    """Évalue un descripteur `proof.mutation` (game_contract.yaml, §2) contre une
    wiremap et, si fourni, un résultat de mutation brut. Moteur PUR : aucune
    exécution, aucune écriture, aucun effet de bord — seulement les règles de
    forme (§2) et les trois cas de `NON_APPLICABLE`/`BLOCKED` (§5).

    `mutation_result=None` => évaluation de FORME seule (avant toute exécution) :
    seules les règles §2 (runtime, seals) et §5 cas 1/2 (catégories) sont
    jugeables. Retourne alors soit `BLOCKED` (oubli de déclaration, §2 règle 4),
    soit `NON_APPLICABLE` (catégorie mutable non portée par la wiremap, §5 cas 1),
    soit `OK` provisoire (forme correcte, aucune mesure encore disponible).

    `mutation_result` fourni => en plus des règles de forme : §3 (conformité de
    la commande exécutée), §4 (troncature mutants_executes < mutants_generes),
    §5 cas 3 (catégorie mutable présente mais 0 mutant mesurable sur TOUTE la
    catégorie -- distinct du `NON_MESURE` par fichier isolé, §4).

    Retour : {"status": "OK"|"BLOCKED"|"NON_APPLICABLE"|"FAIL", "passed": bool,
    "raisons": [str, ...], ...}. `declaration_conforme` est présent dès qu'un
    `mutation_result` est fourni (§3)."""
    mutation = (proof or {}).get("mutation") or {}

    # --- §2 règle 1 : runtime ∈ runtimes: du game_contract -------------------
    runtime = proof.get("runtime") if isinstance(proof, dict) else None
    runtimes_declares = (game_contract or {}).get("runtimes") or []
    if runtime not in runtimes_declares:
        return {
            "status": "BLOCKED", "passed": False,
            "raisons": [
                f"runtime {runtime!r} absent de runtimes: déclarés "
                f"{list(runtimes_declares)!r} (contrat §2 règle 1)"],
        }

    # --- §2 règle 9 : seals.test_scripts non vide ----------------------------
    seals = mutation.get("seals") or {}
    test_scripts = seals.get("test_scripts") or []
    if not test_scripts:
        return {
            "status": "BLOCKED", "passed": False,
            "raisons": [
                "seals.test_scripts vide -- chaîne de preuve rompue par "
                "construction (contrat §2 règle 9)"],
        }

    # --- §2 règle 4 / §5 cas 2 : catégories présentes couvertes --------------
    categories_mutables = set(mutation.get("categories_mutables") or [])
    categories_exclues = set(mutation.get("categories_exclues") or [])
    file_categories = _wiremap_file_categories(wiremap)
    categories_presentes = set(file_categories.values())
    declarees = categories_mutables | categories_exclues
    oubliees = sorted(categories_presentes - declarees)
    if oubliees:
        return {
            "status": "BLOCKED", "passed": False,
            "raisons": [
                f"catégorie(s) présente(s) dans la wiremap absente(s) de "
                f"categories_mutables ET categories_exclues: {oubliees} "
                "(contrat §2 règle 4 / §5 cas 2)"],
            "categories_oubliees": oubliees,
        }

    # --- §5 cas 1 : catégorie déclarée mutable, absente de la wiremap -------
    non_applicables = sorted(c for c in categories_mutables
                              if c not in categories_presentes)

    if mutation_result is None:
        if non_applicables:
            return {
                "status": "NON_APPLICABLE", "passed": True,
                "raisons": [
                    f"catégorie(s) déclarée(s) mutable(s) mais qu'aucune ligne "
                    f"de la wiremap ne porte: {non_applicables} -- déclaré ET "
                    "prouvé par la carte (contrat §5 cas 1)"],
                "categories_non_applicables": non_applicables,
            }
        return {
            "status": "OK", "passed": True,
            "raisons": ["évaluation de forme seule -- aucun mutation_result fourni"],
            "categories_non_applicables": non_applicables,
        }

    # --- §3 : command_declaree vs command_executee ---------------------------
    command_declaree = mutation.get("command")
    command_executee = mutation_result.get("command_executee")
    declaration_conforme = True
    if command_executee is not None:
        declaration_conforme = _commands_conformes(command_declaree, command_executee)
    if not declaration_conforme:
        return {
            "status": "BLOCKED", "passed": False,
            "declaration_conforme": False,
            "raisons": [
                f"command_declaree {command_declaree!r} != command_executee "
                f"{command_executee!r} -- le reçu reflète ce qui a TOURNÉ, pas "
                "ce qui était prévu ; gate REFUSE (contrat §3)"],
        }

    # --- §4 : troncature mutants_executes < mutants_generes ------------------
    mutants_generes = mutation_result.get("mutants_generes")
    mutants_executes = mutation_result.get("mutants_executes")
    if (mutants_generes is not None and mutants_executes is not None
            and mutants_executes < mutants_generes):
        return {
            "status": "BLOCKED", "passed": False,
            "declaration_conforme": declaration_conforme,
            "raisons": [
                f"mutants_executes ({mutants_executes}) < mutants_generes "
                f"({mutants_generes}) -- troncature/plafond de budget, jamais "
                "un résultat partiel présenté comme preuve (contrat §4)"],
        }

    # --- §5 cas 3 : catégorie mutable, présente, 0 mutant mesurable ----------
    per_file = mutation_result.get("per_file") or {}
    categories_mesurables = sorted(c for c in categories_mutables
                                    if c in categories_presentes)
    sans_mesure = []
    for cat in categories_mesurables:
        fichiers_cat = [p for p, c in file_categories.items() if c == cat]
        total_cat = sum(int((per_file.get(p) or {}).get("total", 0))
                         for p in fichiers_cat)
        if total_cat == 0:
            sans_mesure.append(cat)
    if sans_mesure:
        return {
            "status": "BLOCKED", "passed": False,
            "declaration_conforme": declaration_conforme,
            "raisons": [
                f"catégorie(s) mutable(s) déclarée(s) et présente(s), mais "
                f"aucune mesure exploitable (0 mutant sur TOUTE la catégorie): "
                f"{sans_mesure} (contrat §5 cas 3, distinct du NON_MESURE par "
                "fichier isolé §4)"],
            "categories_sans_mesure": sans_mesure,
        }

    return {
        "status": "OK", "passed": True,
        "declaration_conforme": declaration_conforme,
        "raisons": [],
        "categories_non_applicables": non_applicables,
    }


# =====================================================================================
# PHASE ③ ÉTAPE 3 (go Pierre 2026-07-28) — le CHEMIN D'EXÉCUTION manquant du
# régime DESCRIPTEUR : `evaluate_proof_descriptor` ci-dessus est un moteur PUR
# (aucune exécution) ; les fonctions ci-dessous RÉSOLVENT le binaire, MESURENT
# la baseline, GÉNÈRENT/EXÉCUTENT les mutants réels dans le budget déclaré, et
# émettent + vérifient un reçu signé compatible s12 -- pendant DÉDIÉ du régime
# historique (`run_mutation_for_game`/`emit_mutation_receipt`/
# `verify_mutation_receipt`), jamais une fusion des deux (décision Pierre
# 2026-07-28, §0 du contrat : « la mutation ne réutilise JAMAIS l'oracle
# complet par défaut »/deux chemins de preuve définitivement séparés).
#
# Ne réimplémente PAS le mutateur : réutilise `forge.mutation.generate_mutants`
# (pur, déjà générique multi-langage via `comment_prefixes_for` -- JS/GDScript/
# Python) et `forge.mutation.run_mutation_test` comme exécuteur PAR DÉFAUT,
# injectable comme `runner=`/`baseline_runner=` de `run_mutation_for_game`.
# =====================================================================================


def _default_binary_resolver(ref: str) -> dict:
    """Résolution PAR DÉFAUT d'une référence symbolique `<bin:ref>` (contrat
    §3.1). `godot` passe par `forge/godot_bin.mjs` (node, binaire hors
    dépôt) ; toute autre référence par `shutil.which`. Best-effort : chemin/
    version '' si non mesurable -- ne lève JAMAIS (un appelant réel doit
    pouvoir injecter son propre résolveur ; ce défaut ne sert que l'usage hors
    tests, jamais exercé par la suite -- cf. SKIPPED_VALIDATION du rapport)."""
    import shutil
    import subprocess
    path = ""
    if ref == "godot":
        script_dir = Path(__file__).resolve().parent
        try:
            proc = subprocess.run(
                ["node", "--input-type=module", "-e",
                 "import('./godot_bin.mjs').then(m => "
                 "process.stdout.write(m.resolveGodotBin()))"],
                cwd=str(script_dir), capture_output=True, text=True, timeout=30,
            )
            if proc.returncode == 0:
                path = proc.stdout.strip()
        except (OSError, subprocess.SubprocessError):
            path = ""
    else:
        path = shutil.which(ref) or ""
    version = ""
    if path:
        try:
            vproc = subprocess.run([path, "--version"], capture_output=True,
                                   text=True, timeout=15)
            out = (vproc.stdout or vproc.stderr or "").strip()
            version = out.splitlines()[0] if out else ""
        except (OSError, subprocess.SubprocessError):
            version = ""
    return {"path": path, "version": version}


def _resolve_command(command_declaree: list, binary_ref: str | None, resolver) -> tuple[list, dict]:
    """`command_executee` depuis `command_declaree` (contrat §3.1) : SEUL le
    premier token, s'il porte la forme `<bin:name>`, est substitué par le
    chemin réel résolu -- tout le reste est recopié tel quel (la tolérance ne
    porte que sur l'indirection de CHEMIN MACHINE, jamais sur ce qui est
    exécuté)."""
    command_executee = list(command_declaree)
    resolved = {"path": "", "version": ""}
    if (command_declaree and isinstance(command_declaree[0], str)
            and command_declaree[0].startswith("<bin:") and command_declaree[0].endswith(">")):
        symbol = command_declaree[0][len("<bin:"):-1]
        resolved = resolver(binary_ref or symbol)
        command_executee[0] = resolved.get("path") or command_declaree[0]
    return command_executee, resolved


def run_mutation_from_descriptor(
    game_dir: Path | str,
    proof: dict,
    wiremap: dict,
    *,
    binary_resolver=None,
    mutant_runner=None,
    baseline_runner=None,
    now_fn=time.monotonic,
) -> dict:
    """EXÉCUTEUR du descripteur `proof.mutation` (contrat V1 §2-§4) -- résout
    `<bin:name>`, mesure la baseline AVANT toute mutation (rouge => mutation
    non lancée, même doctrine P0.3 que le régime historique), puis génère/
    exécute les mutants réels sur les fichiers dont la CATÉGORIE (wiremap) est
    déclarée `categories_mutables`.

    Anti-troncature-silencieuse (§4) : le nombre RÉEL de mutants d'un fichier
    est mesuré par `generate_mutants` (pur, indépendant du `mutant_runner`)
    AVANT toute exécution -- jamais dérivé d'un résultat déjà tronqué. Si la
    somme dépasse `budget.max_mutants`, RIEN n'est exécuté (`mutants_executes
    = 0`, `budget_exceeded = True`) plutôt qu'un sous-ensemble présenté comme
    preuve complète. Un dépassement de `budget.total_timeout_s` en cours de
    route arrête l'exécution au fichier courant : les fichiers restants
    comptent dans `mutants_generes` mais pas dans `mutants_executes` --
    `evaluate_proof_descriptor` refuse déjà tout `mutants_executes <
    mutants_generes` (§4), aucune règle nouvelle à écrire ici.

    Injectable (même patron que `runner=`/`baseline_runner=` de
    `run_mutation_for_game`) : `binary_resolver(ref) -> {"path","version"}`
    (défaut `_default_binary_resolver`), `mutant_runner(source_path, argv, *,
    cwd, timeout) -> {"total","killed","survived","survivors"}` (défaut
    `forge.mutation.run_mutation_test` -- le mutateur homegrown existant,
    jamais réimplémenté), `baseline_runner(argv, cwd) -> bool` (défaut
    `_default_baseline_runner`). `now_fn` : horloge injectable pour tester
    `total_timeout_s` sans attendre un vrai dépassement.
    """
    game_dir = Path(game_dir)
    mutation = (proof or {}).get("mutation") or {}
    command_declaree = list(mutation.get("command") or [])
    cwd_rel = mutation.get("cwd") or "."
    binary_ref = mutation.get("binary_ref")
    budget = mutation.get("budget") or {}
    max_mutants = budget.get("max_mutants")
    timeout_per_mutant = budget.get("timeout_per_mutant_s", 60)
    total_timeout_s = budget.get("total_timeout_s")

    resolver = binary_resolver or _default_binary_resolver
    command_executee, resolved = _resolve_command(command_declaree, binary_ref, resolver)

    categories_mutables = set(mutation.get("categories_mutables") or [])
    file_categories = _wiremap_file_categories(wiremap)
    files = sorted(p for p, c in file_categories.items() if c in categories_mutables)

    base = {
        "command_declaree": command_declaree,
        "command_executee": command_executee,
        "cwd_execute": cwd_rel,
        "binaire": resolved,
        "files": files,
    }

    baseline = baseline_runner or _default_baseline_runner
    baseline_ok = bool(baseline(command_executee, game_dir))
    if not baseline_ok:
        return {
            **base, "baseline_ok": False, "budget_exceeded": False,
            "mutants_generes": 0, "mutants_executes": 0,
            "total": 0, "killed": 0, "survived": 0, "survivors": [],
            "per_file": {}, "fichiers_sans_mutant": [],
        }

    true_counts: dict[str, int] = {}
    for f in files:
        try:
            text = (game_dir / f).read_bytes().decode("utf-8")
        except OSError:
            true_counts[f] = 0
            continue
        true_counts[f] = len(generate_mutants(text, comment_prefixes_for(f)))
    mutants_generes = sum(true_counts.values())
    fichiers_sans_mutant = sorted(f for f, n in true_counts.items() if n == 0)

    per_file: dict[str, dict] = {}
    total = killed = 0
    survivors: list[dict] = []
    mutants_executes = 0
    budget_exceeded = False

    if max_mutants is not None and mutants_generes > max_mutants:
        budget_exceeded = True
        per_file = {
            f: {"total": 0, "killed": 0, "mutants_generes": n, "mutants_executes": 0}
            for f, n in true_counts.items()
        }
    else:
        runner = mutant_runner or run_mutation_test
        start = now_fn()
        for f in files:
            if total_timeout_s is not None and (now_fn() - start) > total_timeout_s:
                budget_exceeded = True
                break
            r = runner(game_dir / f, command_executee, cwd=game_dir,
                      timeout=timeout_per_mutant)
            f_total = int(r.get("total", 0))
            f_killed = int(r.get("killed", 0))
            per_file[f] = {
                "total": f_total, "killed": f_killed,
                "mutants_generes": true_counts.get(f, f_total),
                "mutants_executes": f_total,
            }
            mutants_executes += f_total
            total += f_total
            killed += f_killed
            survivors += list(r.get("survivors", []))
        # Fichiers non exécutés (arrêt anticipé total_timeout_s) : comptés dans
        # mutants_generes, jamais dans mutants_executes -- déclenche déjà le
        # refus troncature d'evaluate_proof_descriptor (§4), rien à dupliquer.
        for f in files:
            per_file.setdefault(f, {"total": 0, "killed": 0,
                                    "mutants_generes": true_counts.get(f, 0),
                                    "mutants_executes": 0})

    return {
        **base,
        "baseline_ok": True,
        "budget_exceeded": budget_exceeded,
        "mutants_generes": mutants_generes,
        "mutants_executes": mutants_executes,
        "total": total, "killed": killed, "survived": len(survivors),
        "survivors": survivors,
        "per_file": per_file,
        "fichiers_sans_mutant": fichiers_sans_mutant,
    }


def emit_descriptor_mutation_receipt(
    run_id: str,
    game_dir: Path | str,
    proof: dict,
    game_contract: dict,
    wiremap: dict,
    mutation_execution: dict,
    *,
    key_file: Path | None = None,
    evidence_dir: Path | str | None = None,
) -> SignedReceipt:
    """Reçu signé COMPATIBLE s12 pour le régime DESCRIPTEUR -- pendant DÉDIÉ de
    `emit_mutation_receipt` (régime historique, jamais fusionné, décision
    Pierre 2026-07-28). Juge : `evaluate_proof_descriptor` (forme + §3/§4/§5)
    PUIS, si la forme l'autorise, `check_mutation_gate` (même juge « 100% ou
    survivant justifié » que le régime historique -- réutilisé, jamais
    réimplémenté). Scelle la `proof_chain` complète (§3) dans le detail."""
    game_dir = Path(game_dir)
    mutation = (proof or {}).get("mutation") or {}
    seals = mutation.get("seals") or {}
    test_scripts = seals.get("test_scripts") or []
    wrapper_scripts = seals.get("wrapper") or []

    forme = evaluate_proof_descriptor(proof, game_contract, wiremap,
                                      mutation_result=mutation_execution)

    baseline_ok = mutation_execution.get("baseline_ok") is True
    gate = {"passed": False, "checked": False, "survivants_non_tries": [],
           "triage_perimes": [], "exception": False, "triaged_survivors": []}
    if forme["status"] != "BLOCKED":
        gate = check_mutation_gate(mutation_execution, load_mutation_triage(game_dir))

    if forme["status"] == "BLOCKED":
        status = "BLOCKED"
    elif not baseline_ok:
        # Même doctrine P0.3 que le régime historique : sans baseline verte
        # MESURÉE, le gate ne peut jamais être vert -- FAIL, jamais BLOCKED
        # (la forme, elle, était correcte).
        status = "FAIL"
    elif forme["status"] == "NON_APPLICABLE":
        status = "OK"
    elif gate["passed"]:
        status = "OK"
    else:
        status = "FAIL"

    code_sha256 = fingerprint(
        game_dir,
        list(mutation_execution.get("files", [])) + list(test_scripts) + list(wrapper_scripts),
    )
    proof_chain = {
        "schema_version": 1,
        "runtime_declare": proof.get("runtime"),
        "command_declaree": mutation_execution.get("command_declaree"),
        "command_executee": mutation_execution.get("command_executee"),
        "declaration_conforme": forme.get("declaration_conforme", True),
        "cwd_execute": mutation_execution.get("cwd_execute", ""),
        "binaire": mutation_execution.get("binaire", {}),
        "wrapper_sha256": fingerprint(game_dir, wrapper_scripts),
        "test_scripts_sha256": fingerprint(game_dir, test_scripts),
        "parametres": mutation.get("budget", {}),
        "resultat_brut_sha256": "",
        "resultat_brut_path": "",
    }

    detail = {
        "game_dir": str(game_dir),
        "regime_preuve": "descripteur",
        "runtime": proof.get("runtime"),
        "files": mutation_execution.get("files", []),
        "test_files_scelles": sorted(test_scripts),
        "baseline_ok": baseline_ok,
        "total": int(mutation_execution.get("total", 0)),
        "killed": int(mutation_execution.get("killed", 0)),
        "survived": int(mutation_execution.get("survived", 0)),
        "mutants_generes": mutation_execution.get("mutants_generes"),
        "mutants_executes": mutation_execution.get("mutants_executes"),
        "budget_exceeded": mutation_execution.get("budget_exceeded", False),
        "fichiers_sans_mutant": mutation_execution.get("fichiers_sans_mutant", []),
        "per_file": mutation_execution.get("per_file", {}),
        "survivants_non_tries": gate.get("survivants_non_tries", []),
        "gate_checked": gate.get("checked", False),
        "mutation_exception": gate.get("exception", False),
        "triaged_survivors": gate.get("triaged_survivors", []),
        "code_sha256": code_sha256,
        "triage_sha256": sha256_file(game_dir / TRIAGE_FILENAME),
        "evaluation_forme": forme,
        "declaration_conforme": forme.get("declaration_conforme", True),
        "proof_chain": proof_chain,
    }

    evidence_path = ""
    if evidence_dir is not None:
        evidence_dir = Path(evidence_dir)
        evidence_dir.mkdir(parents=True, exist_ok=True)
        raw_path = evidence_dir / f"mutation_{run_id}.raw.json"
        # `newline=""` : sans lui, le mode TEXTE ecrit du CRLF sous Windows, que git
        # renormalise en LF au commit — et `evidence_sha256` hache les OCTETS. Le sceau
        # serait donc INVALIDE des le commit, sans qu'aucune donnee soit alteree.
        raw_path.write_text(
            json.dumps({"mutation_execution": mutation_execution, "forme": forme,
                       "gate": gate}, ensure_ascii=False, sort_keys=True, indent=1),
            encoding="utf-8", newline="",
        )
        raw_sha = sha256_file(raw_path)
        proof_chain["resultat_brut_sha256"] = raw_sha
        proof_chain["resultat_brut_path"] = str(raw_path)
        evidence_path = str(raw_path)

    logger.info("reçu mutation (descripteur) %s: %s (%s/%s tués)", run_id, status,
               detail["killed"], detail["total"])
    return make_signed_receipt(
        "mutation", run_id, status, detail,
        evidence_path=evidence_path, ts=time.time(), key_file=key_file,
    )


def verify_descriptor_mutation_receipt(
    receipt_dict: dict | None,
    signature: str,
    run_id: str,
    game_dir: Path | str,
    game_contract: dict,
    wiremap: dict,
    *,
    key_file: Path | None = None,
    require_green: bool = True,
) -> dict:
    """Pendant DÉDIÉ de `verify_mutation_receipt` pour le régime DESCRIPTEUR
    (décision Pierre 2026-07-28 : vérificateur dédié, jamais une branche de
    l'historique -- le comportement historique reste bit-identique, protégé
    par `test_mutation_regime_coexistence.py`). Vérifie : signature/provenance
    · run_id/oracle_id · empreinte code (relative au jeu, re-hachée) · seals ·
    baseline_ok · triage · évidence · `proof_chain` complète (§3) ·
    divergence déclaré/exécuté hors `<bin:name>` (§3.1, refus INCONDITIONNEL,
    indépendant de `require_green`) · cohérence du `runtime` avec
    `game_contract.yaml` (le runtime du reçu correspond au descripteur du
    jeu). Hypothèse inconnue => refus, même doctrine que le régime historique.
    """
    if not isinstance(receipt_dict, dict) or not signature:
        return {"passed": False,
               "raisons": ["preuve mutation (descripteur) absente ou malformée"],
               "status": ""}
    try:
        receipt = OracleReceipt(**receipt_dict)
    except TypeError:
        return {"passed": False,
               "raisons": ["reçu mutation (descripteur) malformé (champs inattendus)"],
               "status": ""}
    if not verify_receipt(receipt, signature, key_file):
        return {"passed": False,
               "raisons": ["provenance rompue: signature du reçu mutation (descripteur) invalide"],
               "status": receipt.status}

    raisons: list[str] = []
    if receipt.oracle_id != "mutation":
        raisons.append(f"oracle_id inattendu ({receipt.oracle_id!r} != 'mutation')")
    if receipt.run_id != run_id:
        raisons.append(f"run_id incohérent ({receipt.run_id!r} != {run_id!r})")
    if require_green and receipt.status != "OK":
        raisons.append(f"gate mutation (descripteur) non vert (status={receipt.status})")

    detail = receipt.detail or {}
    game_dir = Path(game_dir)

    contract_runtime = ((game_contract or {}).get("proof") or {}).get("runtime")
    if detail.get("runtime") != contract_runtime:
        raisons.append(
            f"runtime du reçu ({detail.get('runtime')!r}) incohérent avec "
            f"game_contract.yaml (proof.runtime={contract_runtime!r})")

    prints = detail.get("code_sha256") or {}
    if not prints:
        raisons.append("empreinte code absente du reçu mutation (descripteur)")
    if not detail.get("test_files_scelles"):
        raisons.append(
            "aucun fichier de test scellé (seals.test_scripts vide ?) — "
            "fraîcheur de la suite non prouvable")
    if detail.get("baseline_ok") is not True:
        raisons.append(
            "baseline verte non prouvée (suite rouge sur code non muté, ou "
            "reçu sans mesure de baseline) — le score de mutation est un artefact")
    for f, expected in sorted(prints.items()):
        if not expected:
            raisons.append(
                f"empreinte illisible/absente au moment de la preuve: {f} "
                "(fichier inexistant scellé '' — jamais un vert)")
        elif sha256_file(game_dir / f) != expected:
            raisons.append(
                f"hash code divergent: {f} (le code testé n'est plus le code présent)")
    if sha256_file(game_dir / TRIAGE_FILENAME) != detail.get("triage_sha256", ""):
        raisons.append(
            "triage modifié après la preuve mutation (mutation_triage.json divergent)")
    # sceau VIDE = rien promis (flux non scellable) : ne pas inventer une rupture.
    if (receipt.evidence_path and receipt.evidence_sha256
            and sha256_evidence(receipt.evidence_path) != receipt.evidence_sha256):
        raisons.append(f"évidence mutation altérée/absente ({receipt.evidence_path})")

    proof_chain = detail.get("proof_chain") or {}
    if not proof_chain:
        raisons.append(
            "proof_chain absente du reçu (contrat §3 — scellement de la "
            "chaîne de preuve requis)")
    else:
        for k in ("command_declaree", "command_executee", "binaire", "cwd_execute"):
            if k not in proof_chain:
                raisons.append(f"proof_chain incomplète: champ '{k}' absent (contrat §3)")
    # §3.1 : divergence déclaré/exécuté hors substitution <bin:name> -- refus
    # INCONDITIONNEL (même famille que la signature invalide), indépendant de
    # `require_green` (ce n'est pas un statut de gate, c'est une rupture de
    # provenance : le reçu ne reflète plus ce qui a réellement tourné).
    declaration_conforme = detail.get(
        "declaration_conforme", proof_chain.get("declaration_conforme", True))
    if declaration_conforme is False:
        raisons.append(
            "divergence déclaré/exécuté hors substitution <bin:name> autorisée "
            "(contrat §3.1) — refusé")

    return {"passed": not raisons, "raisons": raisons, "status": receipt.status}
