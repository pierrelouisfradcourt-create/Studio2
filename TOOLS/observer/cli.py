"""Point d'entree de Forge Observer V0.

    python TOOLS/observer/cli.py --project breakout_v2

Observer lit les traces existantes, reconstruit le run et ecrit SON PROPRE
rapport sous `EVIDENCE/reports/observer/<projet>/`. Il n'ecrit jamais ailleurs, et
ne modifie aucune source qu'il a lue.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

_HERE = Path(__file__).resolve().parent
if str(_HERE.parent) not in sys.path:  # rend `import observer` possible sans install
    sys.path.insert(0, str(_HERE.parent))
# V2 (disposition L1, TOPOLOGY §5) : `forge/` vit a la racine du depot, plus a cote de
# l'Observer — la racine est ajoutee pour que `from forge.… import` resolve sans PYTHONPATH.
_REPO_ROOT_V2 = _HERE.parents[1]
if str(_REPO_ROOT_V2) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT_V2))

from observer.adapters import load_adapters  # noqa: E402
from observer.correlate import prompt_drift, reconstruct  # noqa: E402
from observer.events import Event  # noqa: E402
from observer.facts import build_facts, summarize  # noqa: E402
from observer.session_transition import build as build_session_transition  # noqa: E402

# Deracinement des chemins de transcript AU MOMENT DE L'ECRITURE (GO Pierre 2026-08-20).
# Le prefixe `<disque>:/Users/<compte>/.claude` est personnel et NON probatoire : le
# projet et l'identifiant de session survivent, seule la disposition du poste disparâit.
# Ici et pas ailleurs : c'est le SEUL endroit qui ecrit les trois artefacts, donc le seul
# ou le branchement ne peut pas etre contourne par un seconde chemin de production.
from forge.anonymize_session_paths import (  # noqa: E402
    anonymize_deep,
    anonymize_text,
)
from observer.views import build_views  # noqa: E402
from observer.sources import (  # noqa: E402
    BlindnessViolation,
    ObserverContext,
    OutputScopeViolation,
    default_repo_root,
    default_transcripts_root,
    resolve_output_dir,
)

LOG = logging.getLogger("observer.cli")

# Defauts derives (source unique : observer.sources). Conserves comme noms de
# module pour compatibilite (`live.py` les importe), mais plus aucun chemin
# litteral n'est redeclare ici.
DEFAULT_REPO = default_repo_root()
DEFAULT_TRANSCRIPTS = default_transcripts_root(DEFAULT_REPO)


def collect_all(ctx: ObserverContext) -> tuple[list[Event], dict[str, Any]]:
    """Execute chaque adaptateur. Un adaptateur qui casse est signale, pas cache.

    `BlindnessViolation` n'est jamais rattrapee : si un adaptateur tente de lire
    hors des racines autorisees, la reconstruction doit s'arreter net plutot que
    de produire un resultat dont la validite est compromise.
    """
    events: list[Event] = []
    report: dict[str, Any] = {}
    for module in load_adapters():
        name = getattr(module, "NAME", module.__name__)
        try:
            produced = module.collect(ctx)
        except BlindnessViolation:
            raise
        except Exception as exc:  # noqa: BLE001 - on veut le detail, pas un crash muet
            LOG.error("adaptateur %s en echec: %s", name, exc, exc_info=True)
            report[name] = {"status": "FAILED", "error": f"{type(exc).__name__}: {exc}"}
            continue
        events.extend(produced)
        report[name] = {"status": "OK", "events": len(produced)}
        LOG.info("adaptateur %s: %d evenements", name, len(produced))
    return events, report


def render_markdown(result: dict[str, Any], adapters: dict[str, Any]) -> str:
    """Rend la reconstruction lisible par un humain, sans rien y ajouter."""
    lines: list[str] = []
    add = lines.append

    add(f"# Reconstruction Observer — {result['project']}")
    add("")
    add(f"- schema : `{result['schema']}`")
    add(f"- evenements : **{result['event_count']}**")
    add(f"- genere : {datetime.now(timezone.utc).isoformat()}")
    add("")
    add("Reconstruit a partir des seules traces machine. Le rapport humain n'a pas")
    add("ete lu : les racines lisibles excluent structurellement `docs/`.")
    add("")

    add("## Adaptateurs")
    add("")
    add("| adaptateur | statut | evenements |")
    add("|---|---|---:|")
    for name, info in adapters.items():
        add(f"| `{name}` | {info['status']} | {info.get('events', '—')} |")
    add("")

    add("## Nature des preuves")
    add("")
    add("| axe | reparition |")
    add("|---|---|")
    for axis in ("by_proof", "by_link", "by_ts_format"):
        add(f"| `{axis}` | {result['counts'][axis]} |")
    add(f"| evenements sans date | {result['counts']['undated_events']} |")
    add("")

    add("## Runs reconstruits")
    add("")
    add("| run_id | role | debut | duree (s) | statut | decision | evenements |")
    add("|---|---|---|---:|---|---|---:|")
    for run in result["runs"]:
        window = run["window"]
        add(
            f"| `{run['run_id']}` | {run['role']} | {window['start'] or '—'} | "
            f"{window['duration_s'] if window['duration_s'] is not None else '—'} | "
            f"{run['run_status'] or '—'} | {run['decision'] or '—'} | {run['event_count']} |"
        )
    add("")

    for run in result["runs"]:
        add(f"### `{run['run_id']}`")
        add("")
        add(f"- role : {run['role']}")
        add(f"- modeles : {run['actor']['models'] or '—'}")
        add(f"- roles de capacite : {run['actor']['capability_roles'] or '—'}")
        add(f"- totaux : {run['totals']}")
        written = run["files"]["written"]
        edited = run["files"]["edited"]
        add(f"- fichiers ecrits : {len(written)} · edites : {len(edited)} · "
            f"lus : {run['files']['read_count']}")
        if run["files"]["link_levels"]:
            add(f"- niveau de rattachement des fichiers : {run['files']['link_levels']}")
        add("")
        if run["steps"]:
            add("| etape | debut | statut | preuves | outils declares | outils observes |")
            add("|---|---|---|---|---:|---:|")
            for step in run["steps"]:
                add(
                    f"| `{step['etape']}` | {step['window']['start'] or '—'} | "
                    f"{step['status_declared'] or '—'} | {step['proof_mix']} | "
                    f"{len(step['tools']['declared_by_forge'])} | "
                    f"{len(step['tools']['observed_in_transcripts'])} |"
                )
            add("")

    add("## Couverture — ce qu'Observer sait et ce qu'il ignore")
    add("")
    add("| donnee attendue | statut | evenements | remarque |")
    add("|---|---|---:|---|")
    for key, info in result["coverage"].items():
        add(
            f"| {key} | **{info['status']}** | {info['count']} | "
            f"{info.get('why', '')} |"
        )
    add("")

    add("## Drift constate — signale, jamais corrige")
    add("")
    if not result["drift"]:
        add("Aucun ecart detecte par les regles implementees en V0.")
    else:
        add("| type | severite | run | etape | detail |")
        add("|---|---|---|---|---|")
        for item in result["drift"]:
            add(
                f"| `{item['type']}` | {item['severity']} | "
                f"`{item.get('run_id') or '—'}` | `{item.get('etape') or '—'}` | "
                f"{item['detail'] if 'detail' in item else ''} |"
            )
    add("")

    add("## Sources lues")
    add("")
    for path in result["sources_read"]:
        add(f"- `{path}`")
    add("")
    add("---")
    add("")
    add("software_verdict: voir la campagne — Observer n'emet pas de verdict sur le jeu.")
    add("evidence_verdict: MECHANICAL_VALIDATION_ONLY")
    add("claim_verdict: NO_CLAIM_ALLOWED")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Forge Observer V0 (lecture seule)")
    parser.add_argument("--project", default="breakout_v2")
    parser.add_argument("--repo", type=Path, default=DEFAULT_REPO)
    parser.add_argument("--transcripts", type=Path, default=DEFAULT_TRANSCRIPTS)
    parser.add_argument("--out", type=Path, default=None)
    parser.add_argument(
        "--no-events",
        dest="events",
        action="store_false",
        help="n'ecrit PAS events.jsonl (par defaut, il est ecrit)",
    )
    parser.add_argument(
        "--events",
        dest="events",
        action="store_true",
        help="ecrit events.jsonl (comportement par defaut — flag conserve pour compatibilite)",
    )
    parser.set_defaults(events=True)
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.INFO if args.verbose else logging.WARNING,
        format="%(levelname)s %(name)s: %(message)s",
    )

    # Destination resolue AVANT toute reconstruction. Le controle vivait implicitement a
    # la fin, au moment du `mkdir` : un nom invalide faisait donc l'integralite du travail
    # puis ecrivait au mauvais endroit. Refuser ici coute une comparaison de chemin et rend
    # le refus lisible. `--out` donne explicitement reste libre : c'est une destination
    # DECLAREE par l'operateur, pas un nom qui devient silencieusement un chemin.
    try:
        out_dir = args.out or resolve_output_dir(args.repo, args.project)
    except OutputScopeViolation as exc:
        LOG.error("%s", exc)
        return 2

    ctx = ObserverContext.build(args.repo, args.project, args.transcripts)
    events, adapters = collect_all(ctx)
    result = reconstruct(events, args.project, ctx.read_paths)
    result["adapters"] = adapters
    result["observed_at"] = datetime.now(timezone.utc).isoformat()

    # Prompts reellement recus par les agents. Optionnel : Observer doit rester
    # utilisable si ce module est absent.
    prompts: list[dict[str, Any]] = []
    try:
        from observer.prompt import collect_prompts

        prompts = collect_prompts(ctx)
    except BlindnessViolation:
        raise
    except Exception as exc:  # noqa: BLE001
        LOG.warning("prompts indisponibles: %s", exc)
    result["prompts"] = prompts
    result["drift"].extend(prompt_drift(prompts))

    # Table de faits a provenance obligatoire : c'est elle qui porte la regle
    # « aucune affirmation sans preuve localisee ».
    event_dicts = [e.to_dict() for e in events]
    facts = build_facts(event_dicts, result["runs"], prompts)
    result["facts"] = [f.to_dict() for f in facts]
    result["facts_summary"] = summarize(facts)

    # Les vues sont construites ici AUSSI, et pas seulement par le serveur :
    # deux chemins qui produisent des sorties differentes pour le meme run
    # rendraient l'outil invérifiable.
    result["views"] = build_views(result, event_dicts, prompts=prompts, ctx=ctx)

    # Routage P2 (2026-08-08) : classement des artefacts du run_dir selon la
    # loi de routage verrouillee (donnee explicite -> regle citant son champ ->
    # destination ; sinon REVIEW_REQUIRED). Ecrit UNIQUEMENT dans ce meme
    # observer_run.json, jamais un fichier separe.
    result["session_transition"] = build_session_transition(result, event_dicts, ctx)

    out_dir.mkdir(parents=True, exist_ok=True)

    json_path = out_dir / "observer_run.json"
    json_path.write_text(
        json.dumps(anonymize_deep(result), indent=2, ensure_ascii=False, default=str),
        encoding="utf-8",
    )

    md_path = out_dir / "RECONSTRUCTION.md"
    md_path.write_text(anonymize_text(render_markdown(result, adapters)),
                       encoding="utf-8")

    if args.events:
        events_path = out_dir / "events.jsonl"
        with events_path.open("w", encoding="utf-8") as handle:
            for event in sorted(events, key=lambda e: (e.ts or 0.0, e.kind)):
                handle.write(
                    json.dumps(anonymize_deep(event.to_dict()),
                               ensure_ascii=False, default=str) + "\n"
                )

    summary = result["facts_summary"]
    verifs = Counter(p.get("verification") for p in prompts)
    print(f"evenements   : {len(events)}")
    print(f"runs         : {len(result['runs'])}")
    print(f"prompts      : {len(prompts)} {dict(verifs)}")
    print(f"faits        : {summary['total']} {summary['par_statut']}")
    print(f"localisateurs: {summary['localisateurs']}")
    print(f"sans preuve  : {len(summary['faits_sans_provenance'])}")
    print(f"drift        : {len(result['drift'])}")
    print(f"sources lues : {len(result['sources_read'])}")
    st = result["session_transition"]
    st_dest_counts: Counter = Counter()
    for run_entry in st["by_run"].values():
        st_dest_counts.update(run_entry["routing_coverage"]["by_destination"])
    print(f"routage      : {sum(st_dest_counts.values())} fichier(s) {dict(st_dest_counts)}")
    print(f"sortie       : {json_path}")
    print(f"               {md_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
