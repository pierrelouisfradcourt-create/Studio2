"""Per-project oracle resolution and execution.

The oracle is the deterministic, non-LLM verification command for a project.
Nothing here calls an LLM. Each project has its own oracle — no project inherits
another's — resolved from a data-driven config so we never touch studio_meta.py.
"""
from __future__ import annotations

import json
import logging
import os
import subprocess
from dataclasses import dataclass
from pathlib import Path

logger = logging.getLogger(__name__)

# forge/oracle.py -> parents[2] == repo root
REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = REPO_ROOT / "forge" / "oracles.json"


class OracleNotFound(Exception):
    """Raised when a project has no oracle configured."""


@dataclass(frozen=True)
class OracleSpec:
    project: str
    cwd: Path
    command: list[str]


def resolve_oracle(project: str, config_path: Path | None = None) -> OracleSpec:
    """Return the oracle command for ``project`` from the config file."""
    path = config_path or DEFAULT_CONFIG
    with open(path, encoding="utf-8") as fh:
        config = json.load(fh)
    if project not in config:
        raise OracleNotFound(f"no oracle configured for project {project!r}")
    entry = config[project]
    # Windows CreateProcess (no shell) fails to resolve a relative executable
    # path that uses forward slashes (e.g. ".venv312/Scripts/python.exe"),
    # even though the identical path works from a shell. Normalize only the
    # executable (argv[0]); os.path.normpath is a no-op for bare names like
    # "npm" that must still be resolved via PATH.
    command = list(entry["command"])
    if command:
        command[0] = os.path.normpath(command[0])
    return OracleSpec(
        project=project,
        cwd=(REPO_ROOT / entry["cwd"]).resolve(),
        command=command,
    )


_SUMMARY_PREFIX = "FORGE_ORACLE_SUMMARY "


def extract_summary(stdout: object) -> dict | None:
    """Résumé structuré émis par `godot_oracle.mjs`, extrait d'un flux BRUITÉ.

    BEST-EFFORT STRICT : `None` si absent, illisible, ou si ce n'est pas un mapping — jamais
    une exception. Un oracle qui n'émet pas de résumé (jeu non-Godot, version antérieure)
    ne doit pas devenir un échec de parsing. Le DERNIER résumé gagne : un run peut relancer
    une étape, c'est l'état final qui fait foi.
    """
    if not isinstance(stdout, str) or _SUMMARY_PREFIX not in stdout:
        return None
    trouve = None
    for ligne in stdout.splitlines():
        if not ligne.startswith(_SUMMARY_PREFIX):
            continue
        try:
            obj = json.loads(ligne[len(_SUMMARY_PREFIX):])
        except ValueError:
            continue
        if isinstance(obj, dict):
            trouve = obj
    return trouve


@dataclass(frozen=True)
class OracleResult:
    spec: OracleSpec
    passed: bool
    returncode: int
    evidence_path: Path
    # Le processus a-t-il été TUÉ avant de conclure ? `passed=False` recouvrait deux
    # situations OPPOSÉES — « l'oracle a jugé et condamné » et « l'oracle est mort sans
    # juger » — et seul `returncode == -2`, un nombre magique, les distinguait. Rien
    # n'obligeait l'aval à l'interpréter, et il ne l'interprétait pas : `verdict.py`
    # rendait FAIL dans les deux cas. Le fait devient un champ NOMMÉ (règle studio
    # « aucune décision dans un commentaire », et pas davantage dans un code magique).
    # `OracleResult` n'est PAS signé : l'ajouter ici est sans effet sur les signatures.
    timed_out: bool = False
    # RÉSUMÉ STRUCTURÉ de l'oracle (frontière 2, 2026-08-18). La mesure existait déjà —
    # `FORGE_ORACLE_SUMMARY` depuis abd0504 — mais elle mourait dans `evidence/*.log`,
    # exclu par `.gitignore:81`, et le driver ne gardait que `returncode` +
    # `evidence_path`. Le studio conservait des verdicts SANS les mesures qui les
    # fondent, donc ne pouvait pas ré-instruire ses propres décisions.
    # On ne recopie JAMAIS le stdout brut : c'est le résumé STRUCTURÉ qui voyage, sinon
    # bannière moteur et warnings entreraient dans un `detail` SIGNÉ.
    summary: dict | None = None


def run_oracle(
    spec: OracleSpec,
    evidence_dir: Path | None = None,
    timeout: float | None = 300,
) -> OracleResult:
    """Run the oracle command, capture raw stdout/stderr as evidence, return the result.

    A hung oracle process must never hang the gate forever (CLAUDE.md: "un
    process lance -> timeout actif"). On timeout, the process's partial output
    (if any) is still captured as evidence and the result is reported as failed.
    """
    evidence_dir = evidence_dir or (REPO_ROOT / "EVIDENCE" / "bundles")
    evidence_dir.mkdir(parents=True, exist_ok=True)
    evidence_path = evidence_dir / f"oracle_{spec.project}.log"
    try:
        completed = subprocess.run(
            spec.command,
            cwd=str(spec.cwd),
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        # `newline=""` : voir `mutation_proof` — le CRLF de Windows casserait le sceau
        # `evidence_sha256` des le commit, sans qu'aucune donnee soit alteree.
        with open(evidence_path, "w", encoding="utf-8", newline="") as fh:
            fh.write(f"$ {' '.join(spec.command)}\n(cwd={spec.cwd})\n\n")
            fh.write(f"--- TIMEOUT after {timeout}s ---\n")
            fh.write("--- stdout (partial) ---\n")
            fh.write(exc.stdout or "")
            fh.write("\n--- stderr (partial) ---\n")
            fh.write(exc.stderr or "")
        logger.warning("oracle %s timed out after %ss", spec.project, timeout)
        return OracleResult(
            spec=spec,
            timed_out=True,   # le fait est POSÉ ici, là où il est connu — jamais deviné en aval
            passed=False,
            returncode=-2,
            evidence_path=evidence_path,
            # Meme sur TIMEOUT : la sortie partielle peut deja porter un resume (la
            # mecanique a pu conclure avant que la solvabilite ne soit tuee). Le jeter
            # perdrait la seule information exploitable d'un run interrompu.
            summary=extract_summary(exc.stdout),
        )
    with open(evidence_path, "w", encoding="utf-8", newline="") as fh:
        fh.write(f"$ {' '.join(spec.command)}\n(cwd={spec.cwd})\n\n")
        fh.write("--- stdout ---\n")
        fh.write(completed.stdout)
        fh.write("\n--- stderr ---\n")
        fh.write(completed.stderr)
    logger.info("oracle %s returncode=%s", spec.project, completed.returncode)
    return OracleResult(
        spec=spec,
        passed=completed.returncode == 0,
        returncode=completed.returncode,
        evidence_path=evidence_path,
        summary=extract_summary(completed.stdout),
    )


def run_amont_traversal_probe(run_dir: Path, game_dir: Path | None = None,
                               *, timeout: float = 60) -> dict:
    """Sonde déterministe `check_amont_traversal.mjs` (Node, --json), ADVISORY,
    attachée par le driver au reçu s10c (choix (b) Pierre 2026-08-21). Le spawn de
    process vit ICI, dans oracle.py — jamais dans driver.py, qui doit rester une
    machine à états pure et offline-capable (invariant
    `test_driver_ne_spawn_pas_directement`, forge/tests/test_driver.py).
    Toute panne (node absent, timeout, exit != 0, sortie non-JSON) rend
    {"status": "NOT_MEASURED", "reason"} — jamais une exception, jamais un statut
    d'étape modifié. `game_dir` est passé s'il existe (étage BUILD), sinon la sonde
    rend `files_present=null` (non mesuré, non inventé)."""
    script = Path(__file__).resolve().parent / "check_amont_traversal.mjs"
    cmd = ["node", str(script), str(run_dir), "--json"]
    if game_dir and Path(game_dir).is_dir():
        cmd += ["--game-dir", str(game_dir)]
    try:
        cp = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                            errors="replace", timeout=timeout)
    except (OSError, subprocess.SubprocessError) as exc:
        return {"status": "NOT_MEASURED", "reason": f"sonde injoignable: {exc}"}
    if cp.returncode != 0:
        return {"status": "NOT_MEASURED",
                "reason": f"exit {cp.returncode}: {(cp.stderr or '')[-400:]}"}
    try:
        return json.loads(cp.stdout)
    except (json.JSONDecodeError, ValueError) as exc:
        return {"status": "NOT_MEASURED", "reason": f"sortie non JSON: {exc}"}


def run_art_response_check(game_dir: Path, gm_path: Path | str | None,
                            *, timeout: float = 60) -> dict:
    """Sonde déterministe `check_art_response.mjs` (Node, --json) — contrat de
    retour GM ↔ Artiste (Lot B, T3, plan `2026-08-23-forge-lot-b-game-master.md`,
    contrat s9 règle (15)). Le spawn de process vit ICI, dans oracle.py — jamais
    dans driver.py, qui doit rester une machine à états pure et offline-capable
    (invariant `test_driver_ne_spawn_pas_directement`), même patron que
    `run_amont_traversal_probe` ci-dessus. Toute panne (node absent, timeout,
    exit != 0, sortie non-JSON) rend {"status": "NOT_MEASURED", "reason"} —
    jamais une exception, jamais un statut d'étape modifié directement ici (le
    driver décide du gate à partir de ce reçu). `gm_path` absent -> la sonde
    tourne quand même : `check_art_response` rend alors 0 artist_requirements
    (aucun `--gm` transmis), donc OK sans lire le disque du jeu."""
    script = Path(__file__).resolve().parent / "check_art_response.mjs"
    cmd = ["node", str(script), str(game_dir), "--json"]
    if gm_path and Path(gm_path).is_file():
        cmd += ["--gm", str(gm_path)]
    try:
        cp = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                            errors="replace", timeout=timeout)
    except (OSError, subprocess.SubprocessError) as exc:
        return {"status": "NOT_MEASURED", "reason": f"sonde injoignable: {exc}"}
    # `check_art_response.mjs` sort 1 sur FAIL (verdict métier, pas une panne de
    # sonde) : contrairement à `run_amont_traversal_probe` (ADVISORY pur), un
    # exit 1 avec sortie JSON valide reste une MESURE, pas un NOT_MEASURED.
    if cp.returncode not in (0, 1):
        return {"status": "NOT_MEASURED",
                "reason": f"exit {cp.returncode}: {(cp.stderr or '')[-400:]}"}
    try:
        payload = json.loads(cp.stdout)
    except (json.JSONDecodeError, ValueError) as exc:
        return {"status": "NOT_MEASURED", "reason": f"sortie non JSON: {exc}"}
    if not isinstance(payload, dict):
        return {"status": "NOT_MEASURED", "reason": "sortie JSON non exploitable (pas un objet)"}
    return {
        "status": "OK" if payload.get("ok") else "FAIL",
        "checked": True,
        "passed": bool(payload.get("ok")),
        "problems": payload.get("problems", []),
        "stats": payload.get("stats", {}),
    }


def run_check_artbible(
    art_bible_path: Path, asset_requests_path: Path, *, timeout: float = 120,
) -> dict:
    """Sonde déterministe `check_artbible.mjs` (Node, --json) — fiche 3 (sas
    ratifié Pierre 2026-08-30) : exécutée PAR LE DRIVER après une étape
    `s2.5-artbible`/`-r2` rendue verte par l'exécuteur, plus jamais par
    l'agent producteur lui-même (défaut mesuré aux runs kitten_clicker 8/9 :
    c'était l'agent qui lançait le check via `Bash(node:*)`, et son reçu
    atterrissait à un emplacement différent d'un run à l'autre — « le
    producteur ne juge jamais sa production »). Même patron que
    `run_art_response_check`/`run_amont_traversal_probe` ci-dessus : le spawn
    de process vit ICI, dans oracle.py — jamais dans driver.py (invariant
    `test_driver_ne_spawn_pas_directement`).

    Vocabulaire du script lui-même (`check_artbible.mjs`) : exit 0 = `verdict`
    "OK", exit 1 = "BLOCKED" (structure valide, couverture besoin<->requête
    manquante), exit 2 = "FAIL" (forme invalide) OU usage/illisible — les
    TROIS verdicts (OK/BLOCKED/FAIL) sont des MESURES réelles rendues comme
    JSON exploitable ; SEUL un usage/illisible qui ne rend AUCUN JSON tombe
    dans le cas panne ci-dessous. Toute panne (node absent, timeout, sortie
    non-JSON, exit inattendu) rend `{"status": "NOT_MEASURED", "reason"}` —
    jamais une exception, jamais un statut d'étape modifié directement ici
    (le driver décide seul du gate à partir de ce reçu, voir
    `ForgeDriver._run_artbible_check`)."""
    script = Path(__file__).resolve().parent / "check_artbible.mjs"
    cmd = ["node", str(script), str(art_bible_path), str(asset_requests_path), "--json"]
    try:
        cp = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                            errors="replace", timeout=timeout)
    except (OSError, subprocess.SubprocessError) as exc:
        return {"status": "NOT_MEASURED", "reason": f"sonde injoignable: {exc}"}
    if cp.returncode not in (0, 1, 2):
        return {"status": "NOT_MEASURED",
                "reason": f"exit {cp.returncode} inattendu: {(cp.stderr or '')[-400:]}"}
    try:
        payload = json.loads(cp.stdout)
    except (json.JSONDecodeError, ValueError) as exc:
        return {"status": "NOT_MEASURED",
                "reason": f"sortie non JSON (exit {cp.returncode}): {exc} — "
                          f"stderr: {(cp.stderr or '')[-400:]}"}
    if not isinstance(payload, dict) or "verdict" not in payload:
        return {"status": "NOT_MEASURED",
                "reason": "sortie JSON non exploitable (champ verdict absent)"}
    result = dict(payload)
    result["status"] = "MEASURED"
    return result
