"""Importeur déterministe run_dir → GAME_BLUEPRINT v0 (Lot 1, plan V2 2026-09-03, GO Pierre).

PREMIER PRODUCTEUR du Blueprint — sans lui, `forge.blueprint` serait un validateur sans
producteur (règle ratifiée 2026-07-30). Il lit les artefacts RÉELS d'un run terminé et les range en
sections, chacune avec le sha256 exact de son fichier source. Aucun LLM, aucune interprétation :
un fichier absent devient une section déclarée ABSENT, jamais inventée.

Ce qu'il apprend sur la baseline M ter, et que le Blueprint est fait pour rendre visible :
la wiremap existe en DEUX versions dans un même run — celle de design (artefact agent s5, avant
build) et celle construite (wiremap.json, réécrite en place par s9). La version « après réparation »
mesurée par `join_check_apres_reparation` (VOID, 9 fantômes) n'existe plus sur disque : s9 l'a
écrasée. Le reçu signé est importé comme évidence NON RECALCULABLE. NO_CLAIM_ALLOWED.

Usage :
    python -m forge.blueprint_import --run-dir EVIDENCE/runs/<run> --brief EVIDENCE/briefs/<p>/project_brief.yaml
                                     --project <p> --out <chemin GAME_BLUEPRINT.json>
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import yaml

from forge import blueprint as bp

REPO_ROOT = Path(__file__).resolve().parents[1]
_FENCED_JSON = re.compile(r"```json\s*(.*?)```", re.S)


def _rel(path: Path) -> str:
    try:
        return str(Path(path).resolve().relative_to(REPO_ROOT)).replace("\\", "/")
    except ValueError:
        return str(path)


def _source(path: Path | None, run_id: str, status: str = "FILE") -> dict:
    if path is None or not Path(path).exists():
        return {"path": None if path is None else _rel(path), "sha256": None,
                "status": "ABSENT", "run_id": run_id}
    return {"path": _rel(path), "sha256": bp.file_sha256(path), "status": status, "run_id": run_id}


def _read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _read_yaml(path: Path):
    return yaml.safe_load(path.read_text(encoding="utf-8"))


def _last_fenced_json(text: str):
    blocks = _FENCED_JSON.findall(text)
    return json.loads(blocks[-1]) if blocks else None


def _entry(path: Path, run_id: str, loader):
    """Sous-entrée d'une section composite : {source, content} ; ABSENT si le fichier manque."""
    if not path.exists():
        return {"source": _source(path, run_id), "content": None}
    return {"source": _source(path, run_id), "content": loader(path)}


def import_run_dir(run_dir: Path, *, brief_path: Path | None, project: str) -> dict:
    run_dir = Path(run_dir)
    state_path = run_dir / "state.json"
    if not state_path.exists():
        raise bp.BlueprintError(f"run_dir sans state.json : {run_dir} — rien à importer")
    state = _read_json(state_path)
    run_id = str(state.get("run_id") or run_dir.name)
    verdict = _read_json(run_dir / "verdict.json") if (run_dir / "verdict.json").exists() else None

    b = bp.new_blueprint(project)
    W = bp.IMPORTER

    # --- Brief (entrée ratifiée) -> identity · vision · constraints (propriétaire : Pierre)
    if brief_path is not None and Path(brief_path).exists():
        brief = _read_yaml(Path(brief_path)) or {}
        src = _source(Path(brief_path), run_id, status="BRIEF")
        bp.write_section(b, "identity", {
            "projet": brief.get("projet"), "cible": brief.get("cible"),
            "references_autorisees": brief.get("references_autorisees"),
        }, writer=W, source=src)
        bp.write_section(b, "vision", {
            "intention": brief.get("intention"), "principe": brief.get("principe"),
            "provenance": brief.get("provenance"),
        }, writer=W, source=src)
        bp.write_section(b, "constraints", {
            "contraintes": brief.get("contraintes"),
            "criteres_sortie": brief.get("criteres_sortie"),
            "libertes_deleguees": brief.get("libertes_deleguees"),
            "non_delegue": brief.get("non_delegue"),
        }, writer=W, source=src)

    # --- artefacts de run -> sections simples
    simple = {
        "gameplay": (run_dir / "charter.yaml", _read_yaml),
        "feature_map": (run_dir / "featuremap.json", _read_json),
        "architecture_contract": (run_dir / "blueprint.json", _read_json),   # = ARCHITECTURE_CONTRACT
    }
    for section, (path, loader) in simple.items():
        if path.exists():
            bp.write_section(b, section, loader(path), writer=W, source=_source(path, run_id))

    # --- understanding : composite (chaque entrée porte son propre sha)
    bp.write_section(b, "understanding", {
        "worldscan": _entry(run_dir / "worldscan.json", run_id, _read_json),
        "prisme": _entry(run_dir / "prisme.json", run_id, _read_json),
        "product_snapshot": _entry(run_dir / "product_snapshot.md", run_id,
                                   lambda p: p.read_text(encoding="utf-8")),
    }, writer=W, source={"path": None, "sha256": None, "status": "COMPOSITE", "run_id": run_id})

    # --- wiremap : DEUX versions d'un même run, plus les noms gelés
    s5_artifact = run_dir / "artifacts" / "s5-wiremap.txt"
    design = {"source": _source(s5_artifact, run_id, status="AGENT_ARTIFACT"), "content": None}
    if s5_artifact.exists():
        design["content"] = _last_fenced_json(s5_artifact.read_text(encoding="utf-8"))
    bp.write_section(b, "wiremap", {
        "design": design,                                                    # s5, avant build
        "built": _entry(run_dir / "wiremap.json", run_id, _read_json),      # après s9 (réécrite en place)
        "frozen_names": _entry(run_dir / "wiremap_frozen.json", run_id, _read_json),
    }, writer=W, source={"path": None, "sha256": None, "status": "COMPOSITE", "run_id": run_id})

    # --- questions : design_questions.json (absent dans la baseline -> liste vide DÉCLARÉE)
    dq = run_dir / "design_questions.json"
    if dq.exists():
        data = _read_json(dq)
        questions = data.get("questions") if isinstance(data, dict) else data
        bp.write_section(b, "questions", list(questions or []), writer=W, source=_source(dq, run_id))
    else:
        b["sections"]["questions"]["source"] = _source(dq, run_id)   # ABSENT, dit

    # --- decisions : l'import lui-même est la première décision, structurée (K6)
    bp.write_section(b, "decisions", [{
        "id": f"import-{run_id}", "by": W, "kind": "import",
        "signal": "run terminé", "measure": {"run_status": state.get("run_status"),
                                             "steps": {k: v.get("status") for k, v in (state.get("steps") or {}).items()}},
        "refs": [_rel(state_path)],
    }], writer=W, source=_source(state_path, run_id))

    # --- provenance : reçus signés de jointure, verdict, HEAD du run
    s5 = ((state.get("steps") or {}).get("s5-wiremap") or {}).get("detail") or {}
    bp.write_section(b, "provenance", {
        "run_id": run_id,
        "run_dir": _rel(run_dir),
        "profile": state.get("profile"),
        "git_head": (verdict or {}).get("git_head"),
        "verdict": {k: (verdict or {}).get(k) for k in
                    ("software_verdict", "evidence_verdict", "claim_verdict", "hmac", "ts")},
        "join_receipts": {
            "join_check": s5.get("join_check"),
            "join_check_apres_reparation": s5.get("join_check_apres_reparation"),
            # la wiremap réparée a été écrasée en place par s9 : son reçu ne se recalcule plus
            "recomputable": {"join_check": True, "join_check_apres_reparation": False},
            "note": "join_check = artefact agent s5 (recalculable) · apres_reparation = fichier "
                    "écrasé par s9, reçu signé seul",
        },
    }, writer=W, source=_source(state_path, run_id))

    bp.stamp_imported(b)
    problems = bp.validate(b)
    if problems:
        raise bp.BlueprintError("import invalide : " + " ; ".join(problems))
    return b


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Import déterministe run_dir -> GAME_BLUEPRINT v0")
    p.add_argument("--run-dir", required=True)
    p.add_argument("--brief", default=None)
    p.add_argument("--project", required=True)
    p.add_argument("--out", required=True)
    a = p.parse_args(argv)
    try:
        b = import_run_dir(REPO_ROOT / a.run_dir, brief_path=(REPO_ROOT / a.brief) if a.brief else None,
                           project=a.project)
    except bp.BlueprintError as exc:
        print(f"IMPORT REFUSÉ : {exc}", file=sys.stderr)
        return 1
    out = bp.save(b, REPO_ROOT / a.out)
    print(json.dumps({
        "out": _rel(out), "project": b["project"],
        "sections": {s: {"version": m["version"], "source": m["source"].get("path"),
                         "sha256": m["source"].get("sha256")} for s, m in b["sections"].items()},
    }, ensure_ascii=False, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
