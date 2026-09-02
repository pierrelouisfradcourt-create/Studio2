"""Etalonnage Observer sur une campagne terminee.

Breakout V2 est le run de reference. Ce module extrait, pour chaque tentative,
les metriques que la boucle

    execution reelle -> trace -> reconstruction -> metrique -> signal

doit pouvoir produire, puis pose sur chacune la question qui decide de sa
valeur : **porte-t-elle une information variable ?**

Une metrique vraie mais constante valide le moteur et ne mesure pas ce que son
nom promet. Elle ne peut donc pas servir de signal pour orienter une recherche.
Chaque metrique est donc classee sur DEUX axes independants :

  recuperation : RECUPEREE | PARTIELLE | IMPOSSIBLE
  signal       : VARIANT | INVARIANT | NON_MESURABLE

Lecture seule. Ce module ne touche ni la campagne, ni la Forge, ni le jeu.
"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Callable, Optional

RECUPEREE = "RECUPEREE"
PARTIELLE = "PARTIELLE"
IMPOSSIBLE = "IMPOSSIBLE"

VARIANT = "VARIANT"
INVARIANT = "INVARIANT"
NON_MESURABLE = "NON_MESURABLE"

# Signatures d'echec reperables mecaniquement dans le texte des incidents.
# ATTENTION : une signature n'est pas une cause. Elle dit « ce motif apparait »,
# jamais « voici pourquoi ». L'attribution causale est un jugement humain.
SIGNATURES: tuple[tuple[str, str], ...] = (
    ("timeout_executeur", r"timeout|arbre de process tu"),
    ("oracle_non_enregistre", r"no oracle configured|oracle non enregistr"),
    ("adresse_hors_carte", r"orphelin|hors carte|orphan"),
    ("mutants_survivants", r"survivant|survived|mutation .*(FAIL|echec)"),
    ("code_retour_executeur", r"rc=\d+|returncode"),
    ("gel_absent", r"gel |CV-3"),
)


class Bench:
    """Vue de lecture sur la reconstruction figee."""

    def __init__(self, out_dir: Path) -> None:
        self.data: dict[str, Any] = json.loads(
            (out_dir / "observer_run.json").read_text(encoding="utf-8")
        )
        self.events: list[dict[str, Any]] = [
            json.loads(line)
            for line in (out_dir / "events.jsonl").read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]

    @property
    def attempts(self) -> list[dict[str, Any]]:
        return [r for r in self.data["runs"] if r["role"] == "attempt"]

    def evs(self, kind: str, run_id: str | None = None) -> list[dict[str, Any]]:
        out = [e for e in self.events if e["kind"] == kind]
        if run_id:
            out = [e for e in out if e.get("run_id") == run_id]
        return out

    def src(self, kind: str, run_id: str | None = None, limit: int = 2) -> list[str]:
        out: list[str] = []
        for ev in self.evs(kind, run_id):
            s = ev.get("source", {})
            loc = (f":{s['line']}" if s.get("line") is not None
                   else (f"#{s['field']}" if s.get("field") else ""))
            entry = f"{s.get('path', '?')}{loc}"
            if entry not in out:
                out.append(entry)
            if len(out) >= limit:
                break
        return out


# --------------------------------------------------------------------------- #
# Extracteurs — un par famille de metrique demandee
# --------------------------------------------------------------------------- #


def m_timeline(b: Bench, run: dict) -> Any:
    w = run.get("window") or {}
    return {"debut": w.get("start"), "fin": w.get("end"), "duree_s": w.get("duration_s")}


def m_etapes(b: Bench, run: dict) -> Any:
    execs = b.evs("dispatch.executed", run["run_id"])
    return {"activations": len(execs),
            "etapes_distinctes": sorted({e.get("etape") for e in execs if e.get("etape")})}


def m_agents(b: Bench, run: dict) -> Any:
    sessions = {e["payload"].get("session_id")
                for e in b.evs("agent.session", run["run_id"])
                if e["payload"].get("activity_attributed")}
    return {"sessions_attribuees": len(sessions)}


def m_modeles(b: Bench, run: dict) -> Any:
    declare = Counter()
    for e in b.evs("dispatch.prepared", run["run_id"]):
        m = e["payload"].get("model") or e.get("actor", {}).get("model")
        if m:
            declare[m] += 1
    observe = Counter()
    for e in b.evs("llm.usage", run["run_id"]):
        m = e["payload"].get("model")
        if m and m != "<synthetic>":
            observe[m] += 1
    return {"declares": dict(declare), "observes": dict(observe),
            "concordance": bool(set(declare) & set(observe)) if observe else None}


def m_prompts(b: Bench, run: dict) -> Any:
    mine = [p for p in b.data.get("prompts", []) if p.get("run_id") == run["run_id"]]
    if not mine:
        return None
    return {"activations": len(mine),
            "verification": dict(Counter(p.get("verification") for p in mine)),
            "caracteres": sorted(p.get("chars") for p in mine if p.get("chars"))}


def m_outils(b: Bench, run: dict) -> Any:
    calls = Counter(e["payload"].get("tool_name")
                    for e in b.evs("tool.call", run["run_id"])
                    if e["payload"].get("tool_name"))
    declares: set[str] = set()
    for e in b.evs("dispatch.context_manifest", run["run_id"]):
        t = e["payload"].get("tools_effective")
        if isinstance(t, list):
            declares.update(str(x) for x in t)
    return {"appels": sum(calls.values()), "outils_distincts": len(calls),
            "hors_contrat": sorted(set(calls) - declares) if declares else sorted(calls),
            "detail": dict(calls.most_common())}


def m_fichiers(b: Bench, run: dict) -> Any:
    lus = {e["payload"].get("path") for e in b.evs("file.read", run["run_id"])}
    ecrits = {e["payload"].get("path") for e in b.evs("file.write", run["run_id"])}
    edites = {e["payload"].get("path") for e in b.evs("file.edit", run["run_id"])}
    return {"lus": len(lus - {None}), "ecrits": len(ecrits - {None}),
            "edites": len(edites - {None})}


def m_artefacts(b: Bench, run: dict) -> Any:
    return {
        "rapports_agent": len(b.evs("artifact.self_declared", run["run_id"])),
        "lignes_wiremap": len(b.evs("wiremap.line", run["run_id"])),
        "captures": len(b.evs("capture.visual", run["run_id"])),
    }


def m_effort(b: Bench, run: dict) -> Any:
    return run.get("totals")


def m_verdict(b: Bench, run: dict) -> Any:
    v = run.get("verdict") or {}
    return {"decision": run.get("decision"),
            "software_verdict": v.get("software_verdict"),
            "hmac_present": bool(v.get("hmac")),
            "git_head": (v.get("git_head") or "")[:7] or None}


def m_mutation(b: Bench, run: dict) -> Any:
    for e in b.evs("mutation.result", run["run_id"]):
        p = e["payload"]
        killed, total = p.get("killed"), p.get("total")
        if isinstance(killed, int) and isinstance(total, int) and total:
            return {"tues": killed, "total": total, "taux": round(killed / total, 4)}
    return None


def m_tests(b: Bench, run: dict) -> Any:
    for e in b.evs("test.result", run["run_id"]):
        return {"passed": e["payload"].get("passed"), "failed": e["payload"].get("failed")}
    return None


def m_solvabilite(b: Bench, run: dict) -> Any:
    for e in b.evs("solvability.result", run["run_id"]):
        p = e["payload"]
        return {"gagnees": p.get("won"), "essais": p.get("trials"),
                "verdict": p.get("verdict")}
    return None


def m_reprises(b: Bench, run: dict) -> Any:
    execs = Counter(e.get("etape") for e in b.evs("dispatch.executed", run["run_id"]))
    reprises = {k: v for k, v in execs.items() if v and v > 1}
    pool = sum(1 for e in b.evs("builder.attempt", run["run_id"])
               if e["payload"].get("strategy") == "pool_retry")
    return {"etapes_reprises": reprises, "pool_retry": pool,
            "activations_supplementaires": sum(v - 1 for v in reprises.values())}


def m_failures(b: Bench, run: dict) -> Any:
    evs = b.evs("failure.event", run["run_id"])
    return {"nombre": len(evs),
            "extraits": [str(e["payload"].get("error") or
                             e["payload"].get("message") or "")[:110]
                         for e in evs[:4]]}


def m_signatures(b: Bench, run: dict) -> Any:
    """Signatures d'echec reperables. Ce N'EST PAS une attribution de cause."""
    found: Counter = Counter()
    for e in b.evs("failure.event", run["run_id"]):
        texte = json.dumps(e["payload"], ensure_ascii=False).lower()
        for nom, motif in SIGNATURES:
            if re.search(motif, texte, re.IGNORECASE):
                found[nom] += 1
    return dict(found) or None


METRICS: tuple[tuple[str, str, Callable, str], ...] = (
    ("timeline", "timeline complete du run", m_timeline, "run.declared / step.status"),
    ("etapes", "etapes Forge executees", m_etapes, "dispatch.executed"),
    ("agents", "agents activites", m_agents, "agent.session"),
    ("modeles", "modeles utilises", m_modeles, "dispatch.prepared + llm.usage"),
    ("prompts", "prompts recus et verification SHA", m_prompts, "transcript + manifest"),
    ("outils", "outils appeles", m_outils, "tool.call"),
    ("fichiers", "fichiers lus / modifies", m_fichiers, "file.read/write/edit"),
    ("artefacts", "artefacts produits", m_artefacts, "artifact.self_declared / wiremap"),
    ("effort", "couts / tokens / duree", m_effort, "forge_telemetry + llm.usage"),
    ("verdict", "verdicts", m_verdict, "verdict.json"),
    ("mutation", "mutations", m_mutation, "mutation_*.raw.json"),
    ("tests", "tests", m_tests, "oracle_*.log"),
    ("solvabilite", "solvabilite", m_solvabilite, "oracle_*.log"),
    ("reprises", "echecs et reprises", m_reprises, "dispatch.executed + builder.attempt"),
    ("failures", "failure_events", m_failures, "error_journal + salvage"),
    ("signatures", "signatures d'echec classables", m_signatures, "failure.event"),
)


# --------------------------------------------------------------------------- #
# Variance — le test qui decide si une metrique peut servir de signal
# --------------------------------------------------------------------------- #


def _hashable(value: Any) -> str:
    return json.dumps(value, sort_keys=True, ensure_ascii=False, default=str)


def variance(valeurs: list[Any]) -> tuple[str, int, list[str]]:
    presentes = [v for v in valeurs if v not in (None, {}, [], "")]
    if not presentes:
        return NON_MESURABLE, 0, []
    distinctes = sorted({_hashable(v) for v in presentes})
    if len(distinctes) >= 2:
        return VARIANT, len(distinctes), distinctes[:3]
    return INVARIANT, 1, distinctes


def run_bench(out_dir: Path) -> dict[str, Any]:
    b = Bench(out_dir)
    attempts = b.attempts
    lignes: list[dict[str, Any]] = []

    for key, label, fn, source in METRICS:
        par_run: dict[str, Any] = {}
        for run in attempts:
            try:
                par_run[run["run_id"]] = fn(b, run)
            except Exception as exc:  # noqa: BLE001
                par_run[run["run_id"]] = {"erreur": f"{type(exc).__name__}: {exc}"}

        presentes = sum(1 for v in par_run.values() if v not in (None, {}, [], ""))
        if presentes == 0:
            recuperation = IMPOSSIBLE
        elif presentes < len(attempts):
            recuperation = PARTIELLE
        else:
            recuperation = RECUPEREE

        signal, n_distinctes, echantillon = variance(list(par_run.values()))
        lignes.append({
            "metrique": key, "label": label, "source": source,
            "recuperation": recuperation, "runs_couverts": f"{presentes}/{len(attempts)}",
            "signal": signal, "valeurs_distinctes": n_distinctes,
            "par_run": par_run,
            "provenance": b.src(_kind_for(key), attempts[0]["run_id"] if attempts else None),
            "echantillon_distinct": echantillon,
        })

    return {
        "projet": b.data.get("project"),
        "tentatives": [r["run_id"] for r in attempts],
        "evenements": b.data.get("event_count"),
        "metriques": lignes,
        "resume": {
            "recuperation": dict(Counter(l["recuperation"] for l in lignes)),
            "signal": dict(Counter(l["signal"] for l in lignes)),
        },
        "not_observable": b.data.get("facts_summary", {}).get("not_observable", []),
        "drift": b.data.get("drift", []),
    }


_KIND_BY_METRIC = {
    "timeline": "run.declared", "etapes": "dispatch.executed",
    "agents": "agent.session", "modeles": "dispatch.prepared",
    "prompts": "dispatch.context_manifest", "outils": "tool.call",
    "fichiers": "file.write", "artefacts": "artifact.self_declared",
    "effort": "telemetry.step", "verdict": "verdict.signed",
    "mutation": "mutation.result", "tests": "test.result",
    "solvabilite": "solvability.result", "reprises": "builder.attempt",
    "failures": "failure.event", "signatures": "failure.event",
}


def _kind_for(metric: str) -> str:
    return _KIND_BY_METRIC.get(metric, "run.declared")


def main(argv: list[str] | None = None) -> int:
    import sys

    _here = Path(__file__).resolve().parent
    if str(_here.parent) not in sys.path:  # rend `import observer` possible sans install
        sys.path.insert(0, str(_here.parent))
    from observer.sources import default_repo_root  # noqa: E402

    parser = argparse.ArgumentParser(description="Etalonnage Observer (lecture seule)")
    parser.add_argument(
        "--observer-dir", type=Path,
        default=default_repo_root() / "lab" / "reports" / "observer" / "breakout_v2")
    args = parser.parse_args(argv)

    result = run_bench(args.observer_dir)
    (args.observer_dir / "benchmark.json").write_text(
        json.dumps(result, indent=2, ensure_ascii=False, default=str), encoding="utf-8")

    print(f"projet     : {result['projet']}")
    print(f"tentatives : {len(result['tentatives'])}")
    print(f"recuperation: {result['resume']['recuperation']}")
    print(f"signal      : {result['resume']['signal']}")
    print()
    print(f"{'metrique':14} {'recup':11} {'runs':6} {'signal':14} {'valeurs'}")
    for l in result["metriques"]:
        print(f"  {l['metrique']:12} {l['recuperation']:11} {l['runs_couverts']:6} "
              f"{l['signal']:14} {l['valeurs_distinctes']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
