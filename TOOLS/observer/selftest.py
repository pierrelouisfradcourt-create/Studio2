"""Banc de test par adaptateur de Forge Observer V0.

Ce module teste chaque adaptateur (`forge_run`, `forge_evidence`,
`transcripts`) EN ISOLATION, avec un `ObserverContext` frais par adaptateur,
et rend compte — pour chacun — de ce qu'il extrait, de ce qu'il perd, et de
ce qui reste ambigu. Il n'implemente AUCUNE extraction lui-meme : il appelle
uniquement `collect(ctx)` et mesure ce qui en ressort.

Invocation :

    python scripts/observer/selftest.py --project breakout_v2

Le banc est LECTURE SEULE comme le reste d'Observer : il n'ecrit rien dans le
depot, seulement dans `--out` (par defaut un dossier hors depot). Il ne
rattrape jamais `BlindnessViolation` : une tentative de lecture hors des
racines autorisees doit faire echouer le banc entier, pas seulement
l'adaptateur en cause.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

_HERE = Path(__file__).resolve().parent
if str(_HERE.parent) not in sys.path:  # rend `import observer` possible sans install
    sys.path.insert(0, str(_HERE.parent))

from observer.adapters import load_adapters  # noqa: E402
from observer.events import KINDS, Event  # noqa: E402
from observer.sources import (  # noqa: E402
    BlindnessViolation,
    ObserverContext,
    default_repo_root,
    default_transcripts_root,
)

LOG = logging.getLogger("observer.selftest")

SCHEMA_VERSION = "observer.selftest.v0"

# Defauts derives (source unique : observer.sources). L'ancien DEFAULT_OUT
# pointait vers un scratchpad de session Claude Code deja expire — repare vers
# une sortie stable sous le depot.
DEFAULT_REPO = default_repo_root()
DEFAULT_TRANSCRIPTS = default_transcripts_root(DEFAULT_REPO)
DEFAULT_OUT = DEFAULT_REPO / "EVIDENCE" / "reports" / "observer" / "_selftest"

_TOP_NOTES_LIMIT = 15
_DUPLICATE_EXAMPLES_LIMIT = 3
_DENIED_EXAMPLES_LIMIT = 5
_MISSING_SOURCE_LINE_EXAMPLES_LIMIT = 10


# --------------------------------------------------------------------------- #
# Aides de chemin
# --------------------------------------------------------------------------- #


def _abs_path(ctx: ObserverContext, path_str: str) -> Path:
    """Reconstruit un chemin absolu a partir d'une entree de `ctx.read_paths`
    (relative au repo si possible, absolue sinon — cf. `ObserverContext.rel`)."""
    candidate = Path(path_str)
    if candidate.is_absolute():
        return candidate
    return ctx.repo_root / candidate


def _looks_like_jsonl(path_str: str) -> bool:
    return path_str.lower().endswith(".jsonl")


# --------------------------------------------------------------------------- #
# 1. Sources lues par CET adaptateur (diff read_paths avant/apres)
# --------------------------------------------------------------------------- #


def _sources_report(
    ctx: ObserverContext, touched_paths: list[str], events: list[Event]
) -> tuple[list[dict[str, Any]], dict[str, int]]:
    """Pour chaque fichier lu par l'adaptateur : chemin, taille, nb d'evenements
    qui en proviennent. `touched_paths` est deja la portion propre a CET
    adaptateur (diff avant/apres l'appel de collect)."""
    unique_paths = list(dict.fromkeys(touched_paths))

    events_by_path: dict[str, int] = Counter(e.source.path for e in events)

    sources: list[dict[str, Any]] = []
    for p in unique_paths:
        try:
            size = ctx.stat_size(_abs_path(ctx, p))
        except BlindnessViolation:
            raise
        except OSError as exc:
            LOG.warning("taille illisible pour %s: %s", p, exc)
            size = None
        sources.append(
            {
                "path": p,
                "bytes": size,
                "event_count": events_by_path.get(p, 0),
            }
        )

    return sources, dict(events_by_path)


# --------------------------------------------------------------------------- #
# 2. Champs extraits — union des cles de payload par kind
# --------------------------------------------------------------------------- #


def _fields_report(events: list[Event]) -> dict[str, Any]:
    by_kind: dict[str, dict[str, Any]] = {}
    kinds_seen: dict[str, int] = Counter(e.kind for e in events)
    for kind, total in kinds_seen.items():
        field_counts: Counter[str] = Counter()
        for e in events:
            if e.kind != kind:
                continue
            for key in e.payload.keys():
                field_counts[key] += 1
        by_kind[kind] = {
            "total_events": total,
            "fields": dict(field_counts.most_common()),
        }
    return by_kind


# --------------------------------------------------------------------------- #
# 3. Provenance — numero de ligne present ou non, par kind / par format
# --------------------------------------------------------------------------- #


def _provenance_report(events: list[Event]) -> dict[str, Any]:
    with_line = sum(1 for e in events if e.source.line is not None)
    without_line = len(events) - with_line

    by_kind: dict[str, dict[str, int]] = {}
    by_format: dict[str, dict[str, int]] = {}
    jsonl_missing_line: list[dict[str, Any]] = []

    for e in events:
        has_line = e.source.line is not None

        bucket_kind = by_kind.setdefault(e.kind, {"with_line": 0, "without_line": 0})
        bucket_kind["with_line" if has_line else "without_line"] += 1

        bucket_fmt = by_format.setdefault(e.source.fmt, {"with_line": 0, "without_line": 0})
        bucket_fmt["with_line" if has_line else "without_line"] += 1

        if e.source.fmt == "jsonl" and not has_line:
            jsonl_missing_line.append(
                {
                    "event_id": e.event_id,
                    "kind": e.kind,
                    "source_path": e.source.path,
                }
            )

    return {
        "with_line": with_line,
        "without_line": without_line,
        "by_kind": by_kind,
        "by_format": by_format,
        "jsonl_missing_line_defect_count": len(jsonl_missing_line),
        "jsonl_missing_line_defect_examples": jsonl_missing_line[
            :_MISSING_SOURCE_LINE_EXAMPLES_LIMIT
        ],
    }


# --------------------------------------------------------------------------- #
# 4. Pertes d'information — lignes/objets disponibles vs evenements produits
# --------------------------------------------------------------------------- #


def _pertes_report(
    ctx: ObserverContext,
    unique_paths: list[str],
    events_by_path: dict[str, int],
) -> dict[str, Any]:
    per_source: list[dict[str, Any]] = []
    zero_event_sources: list[str] = []
    ratio_below_1_sources: list[dict[str, Any]] = []

    for p in unique_paths:
        produced = events_by_path.get(p, 0)
        entry: dict[str, Any] = {"path": p, "events_produced": produced}

        if _looks_like_jsonl(p):
            available = sum(1 for _lineno, _obj in ctx.read_jsonl(_abs_path(ctx, p)))
            entry["lines_available"] = available
            ratio = (produced / available) if available else None
            entry["ratio_events_per_line"] = ratio
            if available > 0 and ratio is not None and ratio < 1:
                ratio_below_1_sources.append(
                    {"path": p, "lines_available": available, "events_produced": produced, "ratio": ratio}
                )

        if produced == 0:
            zero_event_sources.append(p)

        per_source.append(entry)

    return {
        "per_source": per_source,
        "sources_lues_pour_rien": zero_event_sources,
        "sources_ratio_below_1": ratio_below_1_sources,
    }


# --------------------------------------------------------------------------- #
# 5. Ambiguites
# --------------------------------------------------------------------------- #


def _ambiguites_report(events: list[Event]) -> dict[str, Any]:
    link_distribution: Counter[str] = Counter(e.link for e in events)
    non_direct_total = sum(c for level, c in link_distribution.items() if level != "DIRECT")

    undated_count = sum(1 for e in events if e.ts is None)

    naive_formats = ("iso_naive", "log_naive")
    naive_counts = Counter(e.ts_format for e in events if e.ts_format in naive_formats)

    notes = Counter(e.note for e in events if e.note)
    top_notes = [{"note": note, "count": count} for note, count in notes.most_common(_TOP_NOTES_LIMIT)]

    attempt_field_values = Counter(e.attempt_field for e in events)

    return {
        "link_distribution": dict(link_distribution),
        "non_direct_total": non_direct_total,
        "undated_count": undated_count,
        "naive_ts_format_counts": dict(naive_counts),
        "distinct_notes_count": len(notes),
        "top_notes": top_notes,
        "attempt_field_values": {
            (k if k is not None else "(absent)"): v for k, v in attempt_field_values.items()
        },
    }


# --------------------------------------------------------------------------- #
# 6. Mapping kind -> fichier(s) source
# --------------------------------------------------------------------------- #


def _mapping_report(events: list[Event]) -> dict[str, dict[str, int]]:
    mapping: dict[str, Counter[str]] = {}
    for e in events:
        mapping.setdefault(e.kind, Counter())[e.source.path] += 1
    return {kind: dict(counter.most_common()) for kind, counter in mapping.items()}


# --------------------------------------------------------------------------- #
# 7. Invariants — verifies et rapportes PASS/FAIL, jamais leves
# --------------------------------------------------------------------------- #


def _invariants_report(ctx: ObserverContext, events: list[Event]) -> dict[str, Any]:
    invalid_kinds = sorted({e.kind for e in events if e.kind not in KINDS})
    kinds_valid = {
        "status": "PASS" if not invalid_kinds else "FAIL",
        "invalid_kinds": invalid_kinds,
    }

    id_counts: Counter[str] = Counter(e.event_id for e in events)
    duplicate_ids = [eid for eid, c in id_counts.items() if c > 1]
    dup_examples: list[dict[str, Any]] = []
    for eid in duplicate_ids[:_DUPLICATE_EXAMPLES_LIMIT]:
        occurrences = [
            {"kind": e.kind, "source_path": e.source.path, "source_line": e.source.line}
            for e in events
            if e.event_id == eid
        ]
        dup_examples.append({"event_id": eid, "occurrences": occurrences})
    no_duplicate_event_id = {
        "status": "PASS" if not duplicate_ids else "FAIL",
        "duplicate_count": len(duplicate_ids),
        "examples": dup_examples,
    }

    denied = list(ctx.denied_attempts)
    denied_attempts_empty = {
        "status": "PASS" if not denied else "FAIL",
        "count": len(denied),
        "examples": denied[:_DENIED_EXAMPLES_LIMIT],
    }

    missing_path_events = [e for e in events if not e.source.path]
    source_path_nonempty = {
        "status": "PASS" if not missing_path_events else "FAIL",
        "missing_count": len(missing_path_events),
        "examples": [
            {"event_id": e.event_id, "kind": e.kind} for e in missing_path_events[:_DUPLICATE_EXAMPLES_LIMIT]
        ],
    }

    return {
        "kinds_valid": kinds_valid,
        "no_duplicate_event_id": no_duplicate_event_id,
        "denied_attempts_empty": denied_attempts_empty,
        "source_path_nonempty": source_path_nonempty,
    }


# --------------------------------------------------------------------------- #
# Un adaptateur, teste en isolation avec un ObserverContext FRAIS
# --------------------------------------------------------------------------- #


def _test_adapter(module: Any, base_ctx: ObserverContext) -> dict[str, Any]:
    name = getattr(module, "NAME", module.__name__)

    # Contexte frais : sinon read_paths/denied_attempts sont pollues par
    # l'adaptateur precedent (regle explicite de la mission).
    ctx = ObserverContext.build(base_ctx.repo_root, base_ctx.project, base_ctx.transcripts_root)

    before = list(ctx.read_paths)  # instantane avant — vide sur un ctx frais,
    # conserve quand meme pour rester correct si `collect` est un jour appele
    # plusieurs fois sur le meme ctx.
    try:
        events = module.collect(ctx)
    except BlindnessViolation:
        raise
    except Exception as exc:  # noqa: BLE001 - on veut le detail, pas un crash muet
        LOG.error("adaptateur %s en echec: %s", name, exc, exc_info=True)
        return {
            "adapter": name,
            "status": "FAILED",
            "error_type": type(exc).__name__,
            "error_message": str(exc),
        }
    after = list(ctx.read_paths)
    touched_paths = after[len(before):]
    unique_paths = list(dict.fromkeys(touched_paths))

    sources, events_by_path = _sources_report(ctx, touched_paths, events)

    # Non tenus par `ctx.read_paths` (ex : `git log` / `git show` du sous-module
    # forge_evidence — un evenement, aucun fichier lu). Rendu visible plutot
    # que silencieusement absent de "sources".
    event_source_paths = {e.source.path for e in events}
    non_file_sources = sorted(event_source_paths - set(unique_paths))

    report: dict[str, Any] = {
        "adapter": name,
        "status": "OK",
        "event_count": len(events),
        "sources": sources,
        "non_read_path_sources": non_file_sources,
        "champs_extraits": _fields_report(events),
        "provenance": _provenance_report(events),
        "pertes_information": _pertes_report(ctx, unique_paths, events_by_path),
        "ambiguites": _ambiguites_report(events),
        "mapping": _mapping_report(events),
        "invariants": _invariants_report(ctx, events),
    }
    return report


# --------------------------------------------------------------------------- #
# Point d'entree impose
# --------------------------------------------------------------------------- #


def selftest(ctx: ObserverContext) -> dict[str, Any]:
    """Teste chaque adaptateur disponible en isolation.

    `ctx` sert uniquement de gabarit (repo_root / project / transcripts_root) :
    chaque adaptateur est reellement execute contre son PROPRE `ObserverContext`
    frais, pour que `read_paths` et `denied_attempts` ne soient jamais partages
    entre deux adaptateurs.
    """
    adapters_report: dict[str, Any] = {}
    for module in load_adapters():
        name = getattr(module, "NAME", module.__name__)
        adapters_report[name] = _test_adapter(module, ctx)

    return {
        "schema": SCHEMA_VERSION,
        "project": ctx.project,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "adapters": adapters_report,
    }


# --------------------------------------------------------------------------- #
# Rendu Markdown
# --------------------------------------------------------------------------- #


def _render_markdown(result: dict[str, Any]) -> str:
    lines: list[str] = []
    add = lines.append

    add(f"# Banc de test des adaptateurs Observer — {result['project']}")
    add("")
    add(f"- schema : `{result['schema']}`")
    add(f"- genere : {result['generated_at']}")
    add("")

    for name, rep in result["adapters"].items():
        add(f"## Adaptateur `{name}`")
        add("")
        if rep["status"] != "OK":
            add(f"**STATUT : FAILED** — `{rep['error_type']}`: {rep['error_message']}")
            add("")
            continue

        add(f"- statut : OK")
        add(f"- evenements produits : **{rep['event_count']}**")
        add("")

        add("### Sources lues")
        add("")
        add("| fichier | octets | evenements issus |")
        add("|---|---:|---:|")
        for s in rep["sources"]:
            add(f"| `{s['path']}` | {s['bytes'] if s['bytes'] is not None else '—'} | {s['event_count']} |")
        add("")
        if rep["non_read_path_sources"]:
            add("Sources d'evenements NON tracees par `ctx.read_paths` (ex : commandes git) :")
            add("")
            for p in rep["non_read_path_sources"]:
                add(f"- `{p}`")
            add("")

        add("### Champs extraits (union par kind)")
        add("")
        for kind, info in rep["champs_extraits"].items():
            add(f"- `{kind}` ({info['total_events']} evenements) :")
            for field, count in info["fields"].items():
                add(f"  - `{field}` : {count}/{info['total_events']}")
        add("")

        prov = rep["provenance"]
        add("### Provenance (numero de ligne)")
        add("")
        add(f"- avec ligne : {prov['with_line']} · sans ligne : {prov['without_line']}")
        add(f"- par kind : {prov['by_kind']}")
        add(f"- par format : {prov['by_format']}")
        if prov["jsonl_missing_line_defect_count"]:
            add(
                f"- **DEFAUT** : {prov['jsonl_missing_line_defect_count']} evenement(s) "
                "issus d'un .jsonl sans numero de ligne"
            )
            for ex in prov["jsonl_missing_line_defect_examples"]:
                add(f"  - `{ex['event_id']}` ({ex['kind']}) — `{ex['source_path']}`")
        add("")

        pertes = rep["pertes_information"]
        add("### Pertes d'information")
        add("")
        if pertes["sources_lues_pour_rien"]:
            add("Sources lues dont AUCUN evenement n'est issu :")
            for p in pertes["sources_lues_pour_rien"]:
                add(f"- `{p}`")
        else:
            add("Aucune source lue pour rien.")
        add("")
        if pertes["sources_ratio_below_1"]:
            add("Sources `.jsonl` dont le ratio evenements/lignes est < 1 (des lignes ignorees) :")
            add("")
            add("| fichier | lignes disponibles | evenements | ratio |")
            add("|---|---:|---:|---:|")
            for item in pertes["sources_ratio_below_1"]:
                add(
                    f"| `{item['path']}` | {item['lines_available']} | "
                    f"{item['events_produced']} | {item['ratio']:.2f} |"
                )
        add("")

        amb = rep["ambiguites"]
        add("### Ambiguites")
        add("")
        add(f"- repartition `link` : {amb['link_distribution']} (non-DIRECT : {amb['non_direct_total']})")
        add(f"- evenements sans date (`ts is None`) : {amb['undated_count']}")
        add(f"- formats de temps sans fuseau : {amb['naive_ts_format_counts']}")
        add(f"- valeurs distinctes de `attempt_field` : {amb['attempt_field_values']}")
        if amb["top_notes"]:
            add(f"- notes les plus frequentes (sur {amb['distinct_notes_count']} distinctes) :")
            for item in amb["top_notes"]:
                add(f"  - ({item['count']}x) {item['note']}")
        add("")

        add("### Mapping kind -> source")
        add("")
        for kind, sources_map in rep["mapping"].items():
            add(f"- `{kind}` : {sources_map}")
        add("")

        inv = rep["invariants"]
        add("### Invariants")
        add("")
        add(f"- kinds valides : **{inv['kinds_valid']['status']}**"
            + (f" — invalides: {inv['kinds_valid']['invalid_kinds']}" if inv["kinds_valid"]["invalid_kinds"] else ""))
        add(f"- pas de doublon `event_id` : **{inv['no_duplicate_event_id']['status']}**"
            + (f" — {inv['no_duplicate_event_id']['duplicate_count']} doublon(s)" if inv["no_duplicate_event_id"]["duplicate_count"] else ""))
        for ex in inv["no_duplicate_event_id"]["examples"]:
            add(f"  - `{ex['event_id']}` : {ex['occurrences']}")
        add(f"- `denied_attempts` vide : **{inv['denied_attempts_empty']['status']}**"
            + (f" — {inv['denied_attempts_empty']['examples']}" if inv["denied_attempts_empty"]["count"] else ""))
        add(f"- `source.path` toujours non vide : **{inv['source_path_nonempty']['status']}**"
            + (f" — {inv['source_path_nonempty']['missing_count']} manquant(s)" if inv["source_path_nonempty"]["missing_count"] else ""))
        add("")

    add("---")
    add("")
    add("software_verdict: voir le detail par adaptateur ci-dessus — ce banc ne juge pas le jeu.")
    add("evidence_verdict: MECHANICAL_VALIDATION_ONLY")
    add("claim_verdict: NO_CLAIM_ALLOWED")
    return "\n".join(lines)


# --------------------------------------------------------------------------- #
# CLI
# --------------------------------------------------------------------------- #


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Banc de test par adaptateur de Forge Observer V0 (lecture seule)"
    )
    parser.add_argument("--project", default="breakout_v2")
    parser.add_argument("--repo", type=Path, default=DEFAULT_REPO)
    parser.add_argument("--transcripts", type=Path, default=DEFAULT_TRANSCRIPTS)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.INFO if args.verbose else logging.WARNING,
        format="%(levelname)s %(name)s: %(message)s",
    )

    ctx = ObserverContext.build(args.repo, args.project, args.transcripts)
    result = selftest(ctx)

    out_dir = args.out
    out_dir.mkdir(parents=True, exist_ok=True)

    json_path = out_dir / "selftest.json"
    json_path.write_text(
        json.dumps(result, indent=2, ensure_ascii=False, default=str),
        encoding="utf-8",
    )

    md_path = out_dir / "SELFTEST.md"
    md_path.write_text(_render_markdown(result), encoding="utf-8")

    print(f"projet       : {result['project']}")
    for name, rep in result["adapters"].items():
        if rep["status"] == "OK":
            print(
                f"adaptateur {name:14s}: OK — {rep['event_count']} evenements, "
                f"{len(rep['sources'])} sources"
            )
        else:
            print(f"adaptateur {name:14s}: FAILED — {rep['error_type']}: {rep['error_message']}")
    print(f"sortie       : {json_path}")
    print(f"               {md_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
