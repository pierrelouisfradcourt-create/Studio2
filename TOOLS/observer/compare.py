"""Comparaison automatique : rapport humain vs reconstruction Observer.

Cette etape n'a le droit d'exister qu'APRES que la reconstruction a ete figee
sur disque. Elle lit le rapport humain — que la garde de cecite interdisait
jusque-la — et confronte chaque affirmation mecaniquement verifiable a ce
qu'Observer a trouve dans les seules traces.

Les affirmations sont extraites du rapport PAR REGEX sur le fichier reel, jamais
recopiees a la main : sinon on comparerait Observer a la lecture qu'en fait son
auteur, ce qui ne prouverait rien.

Quatre classes de resultat :
  RETROUVE       — Observer a trouve la meme valeur dans les traces.
  CONTRADICTOIRE — Observer a trouve une valeur differente.
  NON_RETROUVE   — l'affirmation est dans le rapport, aucune trace ne la porte.
  INCONNU        — l'affirmation n'est pas mecaniquement verifiable (jugement
                   humain, intention, appreciation) ou son motif est absent du
                   rapport.
"""

from __future__ import annotations

import argparse
import json
import re
from collections import Counter
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Optional

RECONSTRUIT = "RECONSTRUIT"
PARTIEL = "PARTIEL"
CONTRADICTOIRE = "CONTRADICTOIRE"
NOT_OBSERVABLE = "NOT_OBSERVABLE"
MANQUANT = "MANQUANT"

STATUSES = (RECONSTRUIT, PARTIEL, CONTRADICTOIRE, NOT_OBSERVABLE, MANQUANT)

# Provenance a citer pour chaque affirmation : quels types d'evenements ont servi
# a l'etablir, et sur quel run. Sans cette table, la comparaison affirmerait sans
# pouvoir montrer ou lire.
EVIDENCE_MAP: dict[str, tuple[tuple[str, ...], Optional[str]]] = {
    "nb_runs": (("run.declared",), None),
    "run1_decision": (("verdict.signed",), "082705"),
    "run2_decision": (("verdict.signed",), "101252"),
    "run3_decision": (("verdict.signed",), "111149"),
    "mutation_finale": (("mutation.result",), "111149"),
    "mutation_run1": (("mutation.result",), "082705"),
    "assertions": (("test.result",), None),
    "tests_echoues": (("test.result",), None),
    "solvabilite": (("solvability.result",), None),
    "git_ancre": (("verdict.signed",), "111149"),
    "software_verdict": (("verdict.signed",), "111149"),
    "claim_verdict": (("verdict.signed",), "111149"),
    "timeout_s9": (("failure.event",), "082705"),
    "captures": (("capture.visual",), None),
    "modele_builder": (("llm.usage",), None),
    "pool_retry": (("builder.attempt",), None),
    "escalades": (("run.status",), None),
    "etapes_par_run": (("dispatch.executed",), None),
    "redteam_meme_famille": (("dispatch.prepared",), None),
    "feel_jouable": (("capture.visual",), None),
}

# Affirmations dont le support est une INFERENCE (rattachement au niveau du
# fichier de session, pas du run) : etablies, mais pas au meme titre qu'une
# trace portant elle-meme le run_id.
DEGRADED_CLAIMS = frozenset({"modele_builder"})


# --------------------------------------------------------------------------- #
# Acces a la reconstruction
# --------------------------------------------------------------------------- #


class Reconstruction:
    """Vue de lecture sur la sortie d'Observer."""

    def __init__(self, run_json: Path, events_jsonl: Path) -> None:
        self.data: dict[str, Any] = json.loads(run_json.read_text(encoding="utf-8"))
        self.events: list[dict[str, Any]] = [
            json.loads(line)
            for line in events_jsonl.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]

    # -- selecteurs ------------------------------------------------------- #

    def attempts(self) -> list[dict[str, Any]]:
        return [r for r in self.data["runs"] if r["role"] == "attempt"]

    def run_by_suffix(self, suffix: str) -> Optional[dict[str, Any]]:
        for run in self.data["runs"]:
            if suffix in run["run_id"]:
                return run
        return None

    def evs(self, kind: str, suffix: str | None = None) -> list[dict[str, Any]]:
        out = [e for e in self.events if e["kind"] == kind]
        if suffix:
            out = [e for e in out if suffix in (e.get("run_id") or "")]
        return out

    def drift_of(self, drift_type: str) -> list[dict[str, Any]]:
        return [d for d in self.data["drift"] if d["type"] == drift_type]

    def provenance(self, claim_id: str, limit: int = 3) -> list[str]:
        """Ou lire, a la main, ce qui fonde cette affirmation."""
        kinds, suffix = EVIDENCE_MAP.get(claim_id, ((), None))
        out: list[str] = []
        for kind in kinds:
            for ev in self.evs(kind, suffix):
                src = ev.get("source", {})
                path = src.get("path", "?")
                if src.get("line") is not None:
                    loc = f"ligne {src['line']}"
                elif src.get("field"):
                    loc = f"champ {src['field']}"
                else:
                    loc = "document entier"
                entry = f"{path} ({loc})"
                if entry not in out:
                    out.append(entry)
                if len(out) >= limit:
                    return out
        return out


# --------------------------------------------------------------------------- #
# Affirmations
# --------------------------------------------------------------------------- #


@dataclass
class Claim:
    """Une affirmation du rapport humain, et comment la confronter aux traces."""

    id: str
    label: str
    pattern: Optional[str]                       # None => affirmation non extraite
    extract: Callable[[re.Match], Any]           # match -> valeur affirmee
    observe: Callable[[Reconstruction], Any]     # reconstruction -> valeur observee
    mechanical: bool = True
    note: str = ""


def _int(idx: int = 1) -> Callable[[re.Match], Any]:
    return lambda m: int(m.group(idx))


def _pair(a: int = 1, b: int = 2) -> Callable[[re.Match], Any]:
    return lambda m: (int(m.group(a)), int(m.group(b)))


def _text(idx: int = 1) -> Callable[[re.Match], Any]:
    return lambda m: m.group(idx).strip()


def _mutation(rec: Reconstruction, suffix: str) -> Optional[tuple[int, int]]:
    for ev in rec.evs("mutation.result", suffix):
        killed, total = ev["payload"].get("killed"), ev["payload"].get("total")
        if isinstance(killed, int) and isinstance(total, int):
            return killed, total
    return None


CLAIMS: tuple[Claim, ...] = (
    Claim(
        id="nb_runs",
        label="la campagne compte 3 runs",
        pattern=r"##\s*2\.\s*Les\s*(\d+)\s*runs",
        extract=_int(),
        observe=lambda rec: len(rec.attempts()),
    ),
    Claim(
        id="run1_decision",
        label="run 1 aboutit a un verdict signe BLOCKED",
        pattern=r"run 1 \(`-(\d+)`\).*?verdict signé \*\*(BLOCKED)\*\*",
        extract=lambda m: (m.group(1), m.group(2)),
        observe=lambda rec: (
            "082705",
            (rec.run_by_suffix("082705") or {}).get("decision"),
        ),
    ),
    Claim(
        id="run2_decision",
        label="run 2 aboutit a OK/HUMANGATE_READY",
        pattern=r"run 2 \(`-(\d+)`\).*?verdict (OK/HUMANGATE_READY)",
        extract=lambda m: (m.group(1), "HUMANGATE_READY"),
        observe=lambda rec: (
            "101252",
            (rec.run_by_suffix("101252") or {}).get("decision"),
        ),
    ),
    Claim(
        id="run3_decision",
        label="run 3 aboutit a OK/HUMANGATE_READY",
        pattern=r"run 3 \(`-(\d+)`\).*?verdict final \*\*(OK/HUMANGATE_READY)\*\*",
        extract=lambda m: (m.group(1), "HUMANGATE_READY"),
        observe=lambda rec: (
            "111149",
            (rec.run_by_suffix("111149") or {}).get("decision"),
        ),
    ),
    Claim(
        id="mutation_finale",
        label="mutation finale : 73/73 mutants tues",
        pattern=r"\*\*(\d+)/(\d+) mutants tués\*\*",
        extract=_pair(),
        observe=lambda rec: _mutation(rec, "111149"),
    ),
    Claim(
        id="mutation_run1",
        label="mutation run 1 : 59/73",
        pattern=r"run 1\s*:\s*(\d+)/(\d+)\s*→\s*corrigé",
        extract=_pair(),
        observe=lambda rec: _mutation(rec, "082705"),
    ),
    Claim(
        id="assertions",
        label="305 assertions vertes",
        pattern=r"(\d+) assertions vertes",
        extract=_int(),
        observe=lambda rec: next(
            (e["payload"].get("passed") for e in rec.evs("test.result")), None
        ),
    ),
    Claim(
        id="tests_echoues",
        label="aucun test en echec",
        pattern=None,
        extract=lambda m: 0,
        observe=lambda rec: next(
            (e["payload"].get("failed") for e in rec.evs("test.result")), None
        ),
        note="affirmation implicite du rapport (« ALL CHECKS PASSED »)",
    ),
    Claim(
        id="solvabilite",
        label="solvabilite R9 : 50/50 parties gagnees",
        pattern=r"\*\*(\d+)/(\d+) parties gagnées\*\*",
        extract=_pair(),
        observe=lambda rec: next(
            (
                (e["payload"].get("won"), e["payload"].get("trials"))
                for e in rec.evs("solvability.result")
            ),
            None,
        ),
    ),
    Claim(
        id="git_ancre",
        label="verdict ancre sur le commit 2b38702",
        pattern=r"git ancré `(\w+)`",
        extract=_text(),
        observe=lambda rec: (
            ((rec.run_by_suffix("111149") or {}).get("verdict") or {}).get("git_head")
            or ""
        )[:7],
    ),
    Claim(
        id="software_verdict",
        label="software_verdict : OK",
        pattern=r"software_verdict\s*:\s*(\w+)",
        extract=_text(),
        observe=lambda rec: ((rec.run_by_suffix("111149") or {}).get("verdict") or {}).get(
            "software_verdict"
        ),
    ),
    Claim(
        id="claim_verdict",
        label="claim_verdict : NO_CLAIM_ALLOWED",
        pattern=r"claim_verdict\s*:\s*(\w+)",
        extract=_text(),
        observe=lambda rec: ((rec.run_by_suffix("111149") or {}).get("verdict") or {}).get(
            "claim_verdict"
        ),
    ),
    Claim(
        id="timeout_s9",
        label="run 1 : s9 en timeout a 1800 s",
        pattern=r"s9 timeout (\d+)\s*s",
        extract=_int(),
        observe=lambda rec: next(
            (
                int(m.group(1))
                for e in rec.evs("failure.event", "082705")
                for m in [re.search(r"timeout \((\d+)s\)", str(e["payload"]))]
                if m
            ),
            None,
        ),
    ),
    Claim(
        id="captures",
        label="2 captures d'ecran differentes",
        pattern=r"(\d+)\s+captures\s+écran",
        extract=_int(),
        observe=lambda rec: next(
            (
                sum(
                    1
                    for key in ("boot_png", "midgame_png")
                    if e["payload"].get(key)
                )
                for e in rec.evs("capture.visual")
            ),
            None,
        ),
    ),
    Claim(
        id="modele_builder",
        label="builder et red-team tournent sur opus-4-8",
        pattern=r"builder/red-team = ([\w.\-]+)",
        extract=_text(),
        observe=lambda rec: sorted(
            {
                e["payload"].get("model")
                for e in rec.evs("llm.usage")
                if (e.get("etape") or "").startswith(("s9", "s11"))
                and e["payload"].get("model")
                and e["payload"].get("model") != "<synthetic>"
            }
        ),
    ),
    Claim(
        id="pool_retry",
        label="1 pool retry sur la campagne",
        pattern=r"(\d+) pool retry",
        extract=_int(),
        observe=lambda rec: sum(
            1
            for e in rec.evs("builder.attempt")
            if (e["payload"].get("strategy") == "pool_retry")
        ),
    ),
    Claim(
        id="escalades",
        label="0 escalade de tier",
        pattern=r"(\d+) escalade de tier",
        extract=_int(),
        observe=lambda rec: sum(
            int(e["payload"].get("escalations") or 0)
            for e in rec.evs("run.status")
        ),
    ),
    Claim(
        id="etapes_par_run",
        label="9+5+6 etapes executees sur les 3 runs",
        pattern=r"3 runs, (\d+)\+(\d+)\+(\d+) étapes exécutées",
        extract=lambda m: (int(m.group(1)), int(m.group(2)), int(m.group(3))),
        # « etape executee » se compte en ACTIVATIONS d'agent (une etape reprise
        # compte deux fois), pas en etapes distinctes du pipeline. Le nombre de
        # `dispatch.executed` est la mesure mecanique de cette notion.
        observe=lambda rec: tuple(
            len(rec.evs("dispatch.executed", suffix))
            for suffix in ("082705", "101252", "111149")
        ),
        note="compte les activations d'agent (dispatch.executed), pas les etapes "
             "distinctes du pipeline — le rapport et Observer doivent parler de "
             "la meme unite avant de se contredire.",
    ),
    Claim(
        id="wiremap_divergee",
        label="la copie wiremap du run_dir a diverge puis ete preservee",
        pattern=r"`_run2_20260731/(wiremap_rundir_constats_stale\.json)`",
        extract=_text(),
        observe=lambda rec: next(
            (
                p
                for p in rec.data.get("sources_read", [])
                if "wiremap_rundir_constats_stale" in str(p)
            ),
            None,
        ),
        note="ANGLE MORT D'OBSERVER, pas une erreur du rapport : l'adaptateur V0 "
             "ne lit pas ce fichier (hors de sa table de sources). Le fichier "
             "existe bien sur disque.",
    ),
    Claim(
        id="redteam_meme_famille",
        label="red-team non independant (meme famille que le builder)",
        pattern=r"s11 déclare `provider=([\w\-]+)`",
        extract=_text(),
        observe=lambda rec: sorted(
            {
                e["payload"].get("provider")
                for e in rec.evs("dispatch.prepared")
                if (e.get("etape") or "").startswith("s11") and e["payload"].get("provider")
            }
        ),
    ),
    # --- affirmations non mecanisables, declarees comme telles ------------- #
    Claim(
        id="feel_jouable",
        label="le jeu « se joue a l'ecran », HUD lisible, briques detruites",
        pattern=r"jeu Godot complet, DÉMARRE, se joue à l'écran",
        extract=lambda m: "affirmation visuelle",
        observe=lambda rec: "capture PNG presente, contenu non analyse",
        mechanical=False,
        note="Observer constate l'existence de captures, pas ce qu'elles montrent. "
             "Lire une image releve d'un capteur visuel, pas d'un correlateur de traces.",
    ),
    Claim(
        id="causes_classees",
        label="les causes d'echec sont classees (harnais / enregistrement / carte)",
        pattern=r"timeout = \*\*(harnais)\*\*",
        extract=_text(),
        observe=lambda rec: "non mecanisable",
        mechanical=False,
        note="une CAUSE est une interpretation ; les traces portent l'evenement, "
             "pas son explication.",
    ),
    Claim(
        id="lecons",
        label="5 lecons L1-L5 proposees",
        pattern=r"\*\*L(\d)\s*\(protocole\)\*\*",
        extract=lambda m: int(m.group(1)),
        observe=lambda rec: "non mecanisable",
        mechanical=False,
        note="une lecon est un jugement porte sur l'experience ; aucune trace ne "
             "l'atteste ni ne l'infirme.",
    ),
)


# --------------------------------------------------------------------------- #
# Comparaison
# --------------------------------------------------------------------------- #


def _equivalent(claimed: Any, observed: Any) -> bool:
    if claimed == observed:
        return True
    if isinstance(claimed, str) and isinstance(observed, list):
        return any(claimed in str(item) for item in observed)
    if isinstance(claimed, str) and isinstance(observed, str):
        return claimed.lower() in observed.lower() or observed.lower() in claimed.lower()
    if isinstance(claimed, tuple) and isinstance(observed, tuple):
        return len(claimed) == len(observed) and all(
            _equivalent(a, b) for a, b in zip(claimed, observed)
        )
    return False


def compare(report_text: str, rec: Reconstruction) -> list[dict[str, Any]]:
    results: list[dict[str, Any]] = []
    for claim in CLAIMS:
        entry: dict[str, Any] = {"id": claim.id, "label": claim.label}
        if claim.note:
            entry["note"] = claim.note

        entry["provenance"] = rec.provenance(claim.id)

        claimed: Any = None
        if claim.pattern:
            match = re.search(claim.pattern, report_text, re.DOTALL)
            if not match:
                entry.update(
                    status=MANQUANT,
                    why="le motif de cette affirmation est introuvable dans le rapport "
                        "— formulation differente, ou affirmation absente",
                )
                results.append(entry)
                continue
            claimed = claim.extract(match)
        else:
            claimed = claim.extract(None)  # type: ignore[arg-type]

        try:
            observed = claim.observe(rec)
        except Exception as exc:  # noqa: BLE001
            entry.update(status=MANQUANT, claimed=claimed,
                         why=f"lecture de la reconstruction impossible: {exc}")
            results.append(entry)
            continue

        entry["claimed"] = claimed
        entry["observed"] = observed

        # Une affirmation de jugement (ressenti, cause, lecon) n'est ni vraie ni
        # fausse au regard des traces : elle est hors de ce qu'un correlateur
        # peut etablir. La classer autrement serait une interpretation.
        if not claim.mechanical:
            entry["status"] = NOT_OBSERVABLE
            results.append(entry)
            continue

        if observed is None or observed == [] or observed == ():
            entry["status"] = MANQUANT
            entry["why"] = entry.get("why") or "aucune trace lue ne porte cette donnee"
        elif _equivalent(claimed, observed):
            entry["status"] = PARTIEL if claim.id in DEGRADED_CLAIMS else RECONSTRUIT
            if claim.id in DEGRADED_CLAIMS:
                entry["why"] = (
                    "valeur concordante, mais etablie par inference de portee de "
                    "session : le run_id n'est pas porte par chaque message"
                )
        else:
            entry["status"] = CONTRADICTOIRE
        results.append(entry)
    return results


def render(results: list[dict[str, Any]], rec: Reconstruction, report_path: Path) -> str:
    counts = Counter(r["status"] for r in results)
    lines: list[str] = []
    add = lines.append

    add("# Comparaison — rapport humain vs reconstruction Observer")
    add("")
    add(f"- rapport humain : `{report_path}`")
    add(f"- reconstruction : {rec.data['event_count']} evenements, "
        f"{len(rec.data['runs'])} runs, {len(rec.data['drift'])} ecarts")
    add("")
    add("La reconstruction a ete produite AVANT toute lecture de ce rapport : la garde")
    add("de cecite d'Observer rend `docs/` structurellement illisible pendant la phase")
    add("de collecte. Cette comparaison est donc un test, pas une relecture.")
    add("")
    add("| classe | n |")
    add("|---|---:|")
    for status in STATUSES:
        add(f"| {status} | {counts.get(status, 0)} |")
    add("")
    add("| affirmation | classe | affirme | observe | provenance |")
    add("|---|---|---|---|---|")
    for res in results:
        prov = res.get("provenance") or []
        prov_txt = "<br>".join(f"`{p}`" for p in prov) if prov else "—"
        add(
            f"| {res['label']} | **{res['status']}** | "
            f"`{res.get('claimed', '—')}` | `{res.get('observed', '—')}` | {prov_txt} |"
        )
    add("")
    add("## Remarques")
    add("")
    for res in results:
        if res.get("why") or res.get("note"):
            add(f"- **{res['label']}** — {res.get('why') or ''} {res.get('note') or ''}".strip())
    add("")
    add("## Ce qu'Observer a vu et que le rapport ne dit pas")
    add("")
    for item in rec.data["drift"]:
        if item["severity"] == "high":
            add(f"- `{item['type']}` — run `{item.get('run_id')}` etape "
                f"`{item.get('etape')}` : {item.get('detail', '')}")
    add("")
    add("claim_verdict: NO_CLAIM_ALLOWED")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    import sys

    _here = Path(__file__).resolve().parent
    if str(_here.parent) not in sys.path:  # rend `import observer` possible sans install
        sys.path.insert(0, str(_here.parent))
    from observer.sources import default_repo_root  # noqa: E402

    parser = argparse.ArgumentParser(description="Comparaison rapport humain / Observer")
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument(
        "--observer-dir",
        type=Path,
        default=default_repo_root() / "EVIDENCE" / "reports" / "observer" / "breakout_v2",
    )
    args = parser.parse_args(argv)

    rec = Reconstruction(
        args.observer_dir / "observer_run.json", args.observer_dir / "events.jsonl"
    )
    report_text = args.report.read_text(encoding="utf-8")
    results = compare(report_text, rec)

    out = args.observer_dir / "COMPARAISON.md"
    out.write_text(render(results, rec, args.report), encoding="utf-8")

    (args.observer_dir / "comparaison.json").write_text(
        json.dumps(results, indent=2, ensure_ascii=False, default=str), encoding="utf-8"
    )

    counts = Counter(r["status"] for r in results)
    for status in STATUSES:
        print(f"{status:16} {counts.get(status, 0)}")
    sans_prov = [
        r["id"] for r in results
        if r["status"] in (RECONSTRUIT, PARTIEL) and not r.get("provenance")
    ]
    print(f"{'sans provenance':16} {len(sans_prov)} {sans_prov if sans_prov else ''}")
    print(f"sortie          {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
