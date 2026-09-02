#!/usr/bin/env python
"""Passage du runtime `asset_producer` par la porte de dispatch, et sa trace Observer.

POURQUOI CE MODULE EXISTE — le producteur d'assets tournait reellement (6 assets produits)
mais il etait invoque A LA MAIN. Le runtime etait declare dans `roles.yaml`, teste dans sa
declaration, et invisible a l'execution : aucun recu signe, rien que l'Observer puisse
reconstruire. Un runtime declare et jamais dispatche est exactement l'ecart que cette lane
cherche a supprimer (« declare != execute »).

Meme patron que `forge/repair_dispatch.py`, meme fichier d'audit signe, meme
resolution par le registry. AUCUN nouveau systeme d'evenements.

CE QUE CE MODULE NE FAIT PAS :
  * il ne produit pas de geometrie — `build_asset.py` est inchange ;
  * il ne juge pas — il REJOUE l'oracle et recopie son verdict, sans jamais le fixer ;
  * il n'ecrit pas le catalogue — il s'arrete a la proposition (propose-only) ;
  * il n'ecrit jamais `<asset>.glb.geometry.json` (parole du HumanGate).

CHAINE REELLE EXECUTEE ICI :
    Task (spec.json)
      -> announce()        recu signe `spawn_prepared`   (AVANT execution)
      -> Blender WSL       forge/asset_producer/build_asset.py
      -> oracle            forge/asset_geometry/oracle.py   (independant)
      -> proposal          forge/asset_producer/propose_asset.py (si OK)
      -> record()          recu signe `spawn_executed` + ligne asset.result

Usage :
  python -m scripts.forge.asset_producer.asset_dispatch <spec.json> [--dest DIR]
                                                        [--run-id ID] [--no-propose]
Exit 0 = asset produit ET oracle OK · 1 = produit mais BLOCKED · 2 = FAIL · 3 = echec
d'execution (Blender injoignable, spec invalide).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

REPO_ROOT = Path(__file__).resolve().parents[2]
FORGE_ROLES = REPO_ROOT / "forge" / "contracts" / "roles.yaml"
RESULTS_PATH = REPO_ROOT / "EVIDENCE" / "bundles" / "asset_results.jsonl"

RUNTIME_ID = "asset_producer"
ENTRYPOINT = "forge/asset_producer/build_asset.py"
from forge.blender_bin import BlenderNonConfigure, resolve_blender

ETAPE = "s-asset-produce"

# Runtime AMONT, distinct : il traduit une demande gameplay en spec. Deux runtimes,
# deux recus — sinon la trace laisserait croire que Blender a invente les parametres.
SPEC_RUNTIME_ID = "asset_spec_author"
ETAPE_SPEC = "s-asset-spec"

# Binaire Blender : RESOLU, jamais code en dur. Le chemin contient le nom d'utilisateur
# du poste — il partait au depot public (preflight de publication 2026-08-19) et enfermait
# le code sur une seule machine. Meme chaine que `godot_bin.mjs` :
# env `BLENDER_BIN` -> `forge/blender.config.json` -> erreur explicite.
# Resolution PARESSEUSE (dans les fonctions, pas ici) : un poste non configure doit encore
# pouvoir IMPORTER ce module — sinon toute la suite de tests tomberait a l'import.


# --------------------------------------------------------------------- utilitaires

def _ensure_import_paths() -> None:
    """`control_plane` et `forge` doivent etre importables quel que soit le cwd.

    Sans ceci, la resolution de role echouait quand ce module etait appele depuis un
    script hors du depot — et le role tombait a `None`, ce qui se lisait « registry
    casse » alors que seul le sys.path manquait (constate 2026-08-06).
    """
    for p in (str(REPO_ROOT), str(REPO_ROOT)):
        if p not in sys.path:
            sys.path.insert(0, p)


def resolve_role(role: str) -> tuple[str, str]:
    """(modele, provider) d'un role via le registry. Jamais de modele en dur."""
    try:
        _ensure_import_paths()
        from control_plane.registry import get_model_for_role, get_provider_for_role
        return (get_model_for_role(role, FORGE_ROLES) or "",
                get_provider_for_role(role, FORGE_ROLES) or "")
    except Exception:
        logger.warning("asset_dispatch : role %r non resolu (advisory)", role, exc_info=True)
        return ("", "")


def author_spec(demande: str, run_id: str, dest: Path,
                attempt: int = 0) -> tuple[Path | None, dict[str, Any]]:
    """Runtime AMONT : Qwen traduit une demande gameplay en spec, avec recus signes.

    La spec est ecrite dans `dest`, pas dans le depot : c'est un artefact de run.
    Retourne (chemin_spec | None, trace).
    """
    modele, provider = resolve_role(SPEC_RUNTIME_ID)
    if not modele:
        # Un role non resolu ne part JAMAIS avec un modele nul : l'appel echouerait
        # plus loin avec une erreur opaque (constate 2026-08-06, HTTP 400 apres que
        # roles.yaml fut rendu illisible). Echec nomme, ici, tout de suite.
        return None, {"error": f"role {SPEC_RUNTIME_ID!r} non resolu par le registry "
                               f"({FORGE_ROLES}) — aucun modele en dur en repli",
                      "model": ""}

    try:
        from forge.audit import EVENT_PREPARED, append_spawn_event
        append_spawn_event(EVENT_PREPARED, etape=ETAPE_SPEC, run_id=run_id,
                           attempt=attempt, capability_role=SPEC_RUNTIME_ID,
                           model=modele, provider=provider, allowed_tools=())
    except Exception:
        logger.warning("asset_dispatch : recu spec 'prepared' non ecrit", exc_info=True)

    from forge.asset_producer.qwen_spec import QwenError, generate_spec
    try:
        spec, trace = generate_spec(demande, model=modele or None)
    except TypeError:
        spec, trace = generate_spec(demande)
    except QwenError as exc:
        return None, {"error": str(exc), "model": modele}

    dest.mkdir(parents=True, exist_ok=True)
    spec_path = dest / f"{spec['asset_id']}.spec.json"
    spec_path.write_text(json.dumps(spec, indent=2, ensure_ascii=False) + "\n",
                         encoding="utf-8")

    try:
        from forge.audit import EVENT_EXECUTED, append_spawn_event
        append_spawn_event(EVENT_EXECUTED, etape=ETAPE_SPEC, run_id=run_id,
                           attempt=attempt, capability_role=SPEC_RUNTIME_ID,
                           model=modele, provider=provider, allowed_tools=())
    except Exception:
        logger.warning("asset_dispatch : recu spec 'executed' non ecrit", exc_info=True)

    return spec_path, {**trace, "spec_ref": repo_relative(spec_path)}


def resolve_runtime() -> tuple[str, str]:
    """(modele, provider) du role `asset_producer` via le registry. Jamais en dur.

    Ce runtime n'utilise aucun modele (geometrie procedurale) : le registry rend donc
    `aucun`/`blender`. On le LIT quand meme plutot que de l'ecrire ici — une valeur
    devinee dans une trace vaut moins qu'une valeur lue.
    """
    try:
        _ensure_import_paths()
        from control_plane.registry import get_model_for_role, get_provider_for_role
        return (get_model_for_role(RUNTIME_ID, FORGE_ROLES) or "",
                get_provider_for_role(RUNTIME_ID, FORGE_ROLES) or "")
    except Exception:
        logger.warning("asset_dispatch : runtime non resolu (advisory)", exc_info=True)
        return ("", "")


def repo_relative(path: Path | str) -> str:
    try:
        return Path(path).resolve().relative_to(REPO_ROOT).as_posix()
    except Exception:
        return str(path).replace("\\", "/")


def file_sha256(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except Exception:
        return ""


def _to_wsl(p: Path) -> str:
    """C:\\x -> /mnt/c/x. Le producteur vit en WSL, le dispatcher sous Windows."""
    s = Path(p).resolve().as_posix()
    if len(s) > 1 and s[1] == ":":
        return f"/mnt/{s[0].lower()}{s[2:]}"
    return s


def announce(run_id: str, attempt: int = 0, audit_path: Path | None = None) -> bool:
    """Recu signe `spawn_prepared` : la production VA tourner.

    Ecrit AVANT l'execution : sinon une production qui plante ne laisserait aucune
    trace de son intention, et l'absence se lirait « rien n'a ete tente ».
    """
    modele, provider = resolve_runtime()
    try:
        from forge.audit import EVENT_PREPARED, append_spawn_event
        return append_spawn_event(
            EVENT_PREPARED, etape=ETAPE, run_id=run_id, attempt=attempt,
            capability_role=RUNTIME_ID, model=modele, provider=provider,
            allowed_tools=(), audit_path=audit_path,
        )
    except Exception:
        logger.warning("asset_dispatch : recu 'prepared' non ecrit (advisory)", exc_info=True)
        return False


# --------------------------------------------------------------------- executeur

def producer_available() -> tuple[bool, str]:
    """Le producteur est-il joignable ? Absent => BLOCKED, jamais un OK par defaut."""
    exe = shutil.which("wsl.exe") or shutil.which("wsl")
    if not exe:
        return False, "wsl introuvable sur ce poste"
    try:
        blender = resolve_blender()
    except BlenderNonConfigure as exc:
        # Configuration absente => producteur INJOIGNABLE, pas produit defaillant.
        return False, f"Blender non configure sur ce poste: {exc}"
    try:
        r = subprocess.run([exe, "-d", blender.distro, "--", "test", "-x", blender.binaire],
                           capture_output=True, timeout=120)
    except Exception as exc:  # noqa: BLE001
        return False, f"appel wsl impossible: {exc}"
    if r.returncode != 0:
        return False, f"binaire Blender absent dans {blender.distro}"
    return True, "Blender 5.1.1 joignable"


def run_producer(spec_path: Path, dest: Path) -> tuple[bool, str]:
    """Invoque le VRAI producteur. Retourne (ok, sortie brute)."""
    exe = shutil.which("wsl.exe") or shutil.which("wsl")
    blender = resolve_blender()
    cmd = [exe, "-d", blender.distro, "--", blender.binaire, "-b", "--python",
           _to_wsl(REPO_ROOT / ENTRYPOINT), "--", _to_wsl(spec_path), _to_wsl(dest)]
    r = subprocess.run(cmd, capture_output=True, text=True,
                       encoding="utf-8", errors="replace", timeout=900)
    out = ((r.stdout or "") + (r.stderr or "")).strip()
    return ("PRODUCED|" in out), out


# --------------------------------------------------------------------- trace

def build_result(run_id: str, *, spec: dict, asset_path: Path, report,
                 proposal_id: str | None, input_hash: str,
                 producer_out: str) -> dict[str, Any]:
    """Enregistrement `asset.result`. Pur : aucun effet de bord, aucun jugement propre.

    `oracle_verdict` est RECOPIE du rapport de l'oracle, jamais decide ici.
    """
    modele, _ = resolve_runtime()
    return {
        "run_id": run_id,
        "etape": ETAPE,
        "runtime_id": RUNTIME_ID,
        "entrypoint": ENTRYPOINT,
        "model_id": modele,
        "asset_id": spec.get("asset_id", ""),
        "archetype": spec.get("archetype", ""),
        "category": spec.get("category", ""),
        "consumer": list(spec.get("consumer") or []),
        "input_hash": input_hash,
        "output_hash": file_sha256(asset_path),
        "asset_ref": repo_relative(asset_path),
        "generation_report_ref": repo_relative(
            asset_path.parent / f"{spec.get('asset_id','')}.generation_report.json"),
        # Verdict de l'oracle INDEPENDANT, recopie tel quel.
        "oracle": "forge/asset_geometry/oracle.py",
        "oracle_verdict": getattr(report, "verdict", ""),
        "oracle_reason": getattr(report, "reason", None),
        "oracle_checks": {c["name"]: c["verdict"] for c in getattr(report, "checks", [])},
        "measurement_space": getattr(report, "measurement_space", ""),
        "skin_evaluated": getattr(report, "skin_evaluated", False),
        # propose-only : le dispatcher s'arrete a la proposition.
        "proposal_id": proposal_id,
        "catalog_written": False,
        "manifest_written_by_producer": False,
        "producer_stdout_tail": producer_out[-400:],
        # L'oracle atteste la geometrie, jamais la qualite artistique.
        "quality_not_proven": True,
        "ts": time.time(),
    }


def record(run_id: str, enreg: dict[str, Any], *, attempt: int = 0,
           audit_path: Path | None = None,
           results_path: Path | None = None) -> dict[str, Any] | None:
    """Recu signe `spawn_executed` + ligne `asset.result`. Best-effort : ne leve jamais."""
    modele, provider = resolve_runtime()
    try:
        from forge.audit import EVENT_EXECUTED, append_spawn_event
        append_spawn_event(
            EVENT_EXECUTED, etape=ETAPE, run_id=run_id, attempt=attempt,
            capability_role=RUNTIME_ID, model=modele, provider=provider,
            allowed_tools=(), audit_path=audit_path,
        )
    except Exception:
        logger.warning("asset_dispatch : recu 'executed' non ecrit (advisory)", exc_info=True)

    try:
        path = results_path or RESULTS_PATH
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(enreg, ensure_ascii=False, sort_keys=True) + "\n")
        return enreg
    except Exception:
        logger.warning("asset_dispatch : trace asset.result non ecrite (advisory)", exc_info=True)
        return None


# --------------------------------------------------------------------- contraintes de lot

def check_batch_constraints(spec: dict) -> str:
    """Applique les contraintes derivees des lecons VALIDEES. "" = spec conforme.

    Lecture seule, best-effort : si le fichier de contraintes est absent ou illisible,
    aucune contrainte ne s'applique — l'amelioration ne doit jamais devenir un point
    de panne de la production.
    """
    try:
        from forge.asset_producer.analyze_batch import load_constraints
        c = load_constraints()
    except Exception:
        logger.warning("asset_dispatch : contraintes de lot illisibles (advisory)", exc_info=True)
        return ""

    arch = spec.get("archetype", "")
    if arch in (c.get("archetypes_blocked") or []):
        return (f"archetype '{arch}' bloque par une lecon validee "
                "(defaut non corrige au lot precedent)")
    if arch in (c.get("require_variants_declared") or []) and not spec.get("variants"):
        return (f"archetype '{arch}' exige `variants` declarees dans la spec "
                "(lecon validee : ce type a exige un manifeste HumanGate au lot precedent)")
    return ""


# --------------------------------------------------------------------- chaine

def dispatch(spec_path: str | Path, dest: str | Path, *, run_id: str,
             propose: bool = True, audit_path: Path | None = None,
             results_path: Path | None = None) -> tuple[int, dict[str, Any]]:
    """Task -> Dispatcher -> Worker -> Blender -> Oracle -> Proposal. Chaine reelle.

    `audit_path` / `results_path` — ISOLATION DE LA PREUVE (2026-08-19). `announce` et
    `record` acceptaient deja ces destinations ; `dispatch` ne les exposait pas, donc les
    SIX points d'emission retombaient sur `forge.audit.DEFAULT_AUDIT` — le vrai fichier.
    Mesure : `pytest test_asset_loop.py` ajoutait 2 lignes a `dispatch_audit.jsonl` et 1 a
    `asset_results.jsonl`. `None` conserve le comportement de production.
    """
    sys.path.insert(0, str(REPO_ROOT))
    from forge.asset_geometry import oracle as O

    spec_path, dest = Path(spec_path), Path(dest)
    spec = json.loads(spec_path.read_text(encoding="utf-8"))
    input_hash = file_sha256(spec_path)

    # --- BOUCLE D'AMELIORATION : les lecons VALIDEES du lot precedent s'appliquent ICI,
    # avant toute production. C'est ce qui rend le lot n+1 different du lot n : sans ce
    # gate, `analyze_batch` n'ecrirait que des fichiers que personne ne lit.
    viol = check_batch_constraints(spec)
    if viol:
        announce(run_id, audit_path=audit_path)
        enreg = {"run_id": run_id, "etape": ETAPE, "runtime_id": RUNTIME_ID,
                 "status": "BLOCKED", "reason": "SPEC_VIOLATES_BATCH_CONSTRAINT",
                 "detail": viol, "asset_id": spec.get("asset_id", ""),
                 "archetype": spec.get("archetype", ""),
                 "catalog_written": False, "produced": False, "ts": time.time()}
        record(run_id, enreg, audit_path=audit_path, results_path=results_path)
        return 1, enreg

    dispo, detail = producer_available()
    announce(run_id, audit_path=audit_path)
    if not dispo:
        enreg = {"run_id": run_id, "etape": ETAPE, "runtime_id": RUNTIME_ID,
                 "status": "BLOCKED", "reason": "BLENDER_EXECUTOR_UNAVAILABLE",
                 "detail": detail, "catalog_written": False, "ts": time.time()}
        record(run_id, enreg, audit_path=audit_path, results_path=results_path)
        return 3, enreg

    ok, out = run_producer(spec_path, dest)
    asset_path = dest / f"{spec['asset_id']}.glb"
    if not ok or not asset_path.is_file():
        enreg = {"run_id": run_id, "etape": ETAPE, "runtime_id": RUNTIME_ID,
                 "status": "FAIL", "reason": "PRODUCER_FAILED",
                 "detail": out[-400:], "catalog_written": False, "ts": time.time()}
        record(run_id, enreg, audit_path=audit_path, results_path=results_path)
        return 3, enreg

    # L'oracle est REJOUE par le dispatcher : le producteur ne fournit jamais son verdict.
    report = O.run(asset_path)

    proposal_id = None
    if propose and report.verdict == "OK":
        from forge.asset_producer import propose_asset as P
        res = P.propose([str(asset_path)], force=True)
        proposal_id = res["proposes"][0] if res["proposes"] else None

    enreg = build_result(run_id, spec=spec, asset_path=asset_path, report=report,
                         proposal_id=proposal_id, input_hash=input_hash, producer_out=out)
    record(run_id, enreg, audit_path=audit_path, results_path=results_path)
    return {"OK": 0, "BLOCKED": 1, "FAIL": 2}.get(report.verdict, 2), enreg


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("spec", nargs="?", help="chemin de la spec JSON (la Task)")
    ap.add_argument("--from-request", default=None,
                    help="demande gameplay en langage naturel : Qwen ecrit la spec")
    ap.add_argument("--dest", default=str(REPO_ROOT / "knowledge_base" / "assets" / "props3d"))
    ap.add_argument("--run-id", default=None)
    ap.add_argument("--no-propose", action="store_true")
    ns = ap.parse_args(argv)

    run_id = ns.run_id or f"asset-{int(time.time())}"

    spec_path = ns.spec
    if ns.from_request:
        sys.path.insert(0, str(REPO_ROOT))
        chemin, trace = author_spec(ns.from_request, run_id, Path(ns.dest))
        if chemin is None:
            print(f"SPEC_AUTHOR_FAIL  {trace.get('error')}", file=sys.stderr)
            return 3
        print(f"spec (Qwen)     {trace.get('model')} "
              f"tentatives={trace.get('attempts')} reparee={trace.get('repaired')}")
        print(f"                -> {trace.get('spec_ref')}")
        spec_path = str(chemin)
    if not spec_path:
        ap.error("fournir une spec, ou --from-request \"<demande>\"")

    code, enreg = dispatch(spec_path, ns.dest, run_id=run_id, propose=not ns.no_propose)

    print(f"RUN_ID          {run_id}")
    print(f"runtime         {enreg.get('runtime_id')} ({enreg.get('model_id') or 'aucun modele'})")
    print(f"asset           {enreg.get('asset_id', '-')}  -> {enreg.get('asset_ref', '-')}")
    print(f"oracle          {enreg.get('oracle_verdict', enreg.get('status'))}"
          f"  {enreg.get('oracle_reason') or enreg.get('reason') or ''}")
    print(f"proposition     {enreg.get('proposal_id') or '(aucune)'}")
    print(f"catalogue ecrit {enreg.get('catalog_written')}")
    print(f"trace           {repo_relative(RESULTS_PATH)}")
    return code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
