"""Assemble la section `session_transition` de `observer_run.json` (mission P2,
2026-08-08). N'ECRIT RIEN : retourne un `dict` que `cli.py` fusionne dans le
resultat deja construit par `observer.correlate.reconstruct` — jamais un
fichier de sortie separe.

Structure minimale imposee par la mission : `produced` · `proved` · `open` ·
`decisions` · `next_run_input` · `archive_proposals` · `review_required` ·
`lanes`. Chaque valeur vient du comportement REEL d'Observer sur le run
reconstruit (evenements deja produits par les adaptateurs + routage de
`observer.routing`) — jamais d'une constante.

`lanes` est une liste DESCRIPTIVE (etat observe : ready / blocked / proposed /
deferred). Aucun declencheur, aucune pretention d'ordonnanceur : ce module ne
lance rien, ne decide rien, ne modifie rien — HumanGate (Pierre) decide.
"""

from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timezone
from typing import Any, Optional

from observer import routing as routing_mod

SCHEMA_VERSION = "observer.session_transition.v1"

_TERMINAL_STATUSES = {"DONE", "FAILED", "BLOCKED", "HALTED", "ABANDONED"}


def _age_days(window_end_iso: Optional[str], observed_at_iso: str) -> Optional[float]:
    if not window_end_iso:
        return None
    try:
        end_dt = datetime.fromisoformat(window_end_iso)
        now_dt = datetime.fromisoformat(observed_at_iso)
    except ValueError:
        return None
    return (now_dt - end_dt).total_seconds() / 86400.0


def _has_reader(ctx: Any, project: str) -> bool:
    """Proxy OBSERVABLE, pas une preuve de lecture reelle : `games/<project>`
    existant et non vide signale qu'un artefact aval a ete produit a partir de
    ce run — donc qu'il n'est pas orphelin au sens le plus grossier. Nomme
    explicitement comme un proxy dans `archive_proposals[].preuve`, jamais
    presente comme une detection certaine de lecteur."""
    game_dir = ctx.repo_root / "games" / project
    try:
        return game_dir.is_dir() and any(game_dir.iterdir())
    except OSError:
        return False


def _lanes_for_run(
    run: dict[str, Any],
    by_dest: dict[str, list[dict[str, Any]]],
    archive_proposal: Optional[dict[str, Any]],
) -> list[dict[str, Any]]:
    """Etat DESCRIPTIF du run, jamais un declencheur. Chaque entree cite le
    champ observe qui la fonde."""
    lanes: list[dict[str, Any]] = []
    run_status = run.get("run_status")
    decision = (run.get("verdict") or {}).get("decision") if isinstance(run.get("verdict"), dict) else None
    software_verdict = (
        (run.get("verdict") or {}).get("software_verdict") if isinstance(run.get("verdict"), dict) else None
    )

    if decision == "HUMANGATE_READY" and software_verdict == "OK":
        lanes.append(
            {
                "state": "ready",
                "detail": "verdict signe decision=HUMANGATE_READY, software_verdict=OK "
                          "— pret pour revue HumanGate, pas pour merge automatique",
                "field": "verdict.decision, verdict.software_verdict",
            }
        )
    if run_status in ("BLOCKED", "HALTED") or software_verdict == "FAIL":
        lanes.append(
            {
                "state": "blocked",
                "detail": f"run_status={run_status!r}, software_verdict={software_verdict!r}",
                "field": "state.run_status / verdict.software_verdict",
            }
        )
    if archive_proposal is not None:
        lanes.append(
            {
                "state": "proposed",
                "detail": "candidat archive propose (voir archive_proposals) — "
                          "aucune suppression, aucun deplacement effectue",
                "field": "archive_proposals",
            }
        )
    if by_dest.get(routing_mod.REVIEW_REQUIRED):
        lanes.append(
            {
                "state": "deferred",
                "detail": f"{len(by_dest[routing_mod.REVIEW_REQUIRED])} fichier(s) sans "
                          "regle de routage fondee — classification differee a un humain",
                "field": "routing.REVIEW_REQUIRED",
            }
        )
    if run_status is None and not run.get("verdict"):
        lanes.append(
            {
                "state": "deferred",
                "detail": "chaine incomplete : pas de state, pas de verdict",
                "field": "state.json absent, verdict*.json absent",
            }
        )
    return lanes


def build(result: dict[str, Any], event_dicts: list[dict[str, Any]], ctx: Any) -> dict[str, Any]:
    """Construit `session_transition`. `result` est le dict deja produit par
    `reconstruct()` (porte `runs`, `project`) ; `event_dicts` sont les memes
    evenements serialises (`Event.to_dict()`) que ceux ecrits dans
    `events.jsonl` — aucune relecture de fichier ici."""
    repo_root = str(ctx.repo_root)
    project = result["project"]
    observed_at = result.get("observed_at") or datetime.now(timezone.utc).isoformat()

    runs = list(result.get("runs") or [])
    known_run_ids = {r["run_id"] for r in runs}

    # Evenements sans run_id connu (orphelins) : peuvent porter des fichiers du
    # run_dir quand `state.json`/`verdict*.json` sont absents (chaine
    # incomplete, ex. pacman-v6 mesure 2026-08-08). Un pseudo-run `None` est
    # construit pour que ces fichiers recoivent aussi une destination — jamais
    # silencieusement ignores.
    orphan_run_ids = {
        e.get("run_id")
        for e in event_dicts
        if e.get("run_id") is None
        and (e.get("source") or {}).get("path", "").startswith(
            f"lab/forge_runs/{project}"
        )
    }
    pseudo_runs: list[dict[str, Any]] = []
    if any(
        e.get("run_id") is None
        and (e.get("source") or {}).get("path", "").startswith(f"lab/forge_runs/{project}")
        for e in event_dicts
    ):
        pseudo_runs.append({"run_id": None, "run_status": None, "verdict": None, "window": {}})

    all_run_entries = runs + [r for r in pseudo_runs if r["run_id"] not in known_run_ids]

    by_run: dict[str, dict[str, Any]] = {}
    agg_produced: list[str] = []
    agg_proved: list[str] = []
    agg_open: list[str] = []
    agg_decisions: list[str] = []
    agg_next_run_input: list[str] = []
    agg_archive: list[dict[str, Any]] = []
    agg_review: list[dict[str, Any]] = []
    agg_lanes: list[dict[str, Any]] = []

    for run in all_run_entries:
        run_id = run.get("run_id")
        file_routes = routing_mod.route_run_files(event_dicts, run_id, repo_root)
        by_dest: dict[str, list[dict[str, Any]]] = defaultdict(list)
        for r in file_routes:
            by_dest[r["destination"]].append(r)

        open_flags = routing_mod.open_flags_of(run) if run in runs else []
        window = run.get("window") or {}
        archive_proposal = None
        if run in runs:
            archive_proposal = routing_mod.archive_candidate(
                run,
                has_reader=_has_reader(ctx, project),
                age_days=_age_days(window.get("end"), observed_at),
            )

        lanes = _lanes_for_run(run, by_dest, archive_proposal)

        entry = {
            "run_id": run_id,
            "run_status": run.get("run_status"),
            "produced": sorted(r["path"] for r in by_dest.get(routing_mod.PRODUCT, [])),
            "proved": sorted(r["path"] for r in by_dest.get(routing_mod.EVIDENCE, [])),
            "open": open_flags,
            "decisions": sorted(r["path"] for r in by_dest.get(routing_mod.DECISION_INPUT, [])),
            "next_run_input": sorted(
                r["path"] for r in by_dest.get(routing_mod.NEXT_RUN_INPUT, [])
            ),
            "archive_proposals": [archive_proposal] if archive_proposal else [],
            "review_required": [
                {"path": r["path"], "reason": r["rule"]}
                for r in sorted(by_dest.get(routing_mod.REVIEW_REQUIRED, []), key=lambda x: x["path"])
            ],
            "lanes": lanes,
            "routing_coverage": {
                "files_routed": len(file_routes),
                "by_destination": {k: len(v) for k, v in by_dest.items()},
            },
        }
        by_run[str(run_id)] = entry

        agg_produced.extend(entry["produced"])
        agg_proved.extend(entry["proved"])
        agg_open.extend(open_flags)
        agg_decisions.extend(entry["decisions"])
        agg_next_run_input.extend(entry["next_run_input"])
        agg_archive.extend(entry["archive_proposals"])
        agg_review.extend(entry["review_required"])
        agg_lanes.extend(lanes)

    return {
        "schema": SCHEMA_VERSION,
        "project": project,
        "produced": sorted(set(agg_produced)),
        "proved": sorted(set(agg_proved)),
        "open": agg_open,
        "decisions": sorted(set(agg_decisions)),
        "next_run_input": sorted(set(agg_next_run_input)),
        "archive_proposals": agg_archive,
        "review_required": sorted(agg_review, key=lambda x: x["path"]),
        "lanes": agg_lanes,
        "by_run": by_run,
    }
