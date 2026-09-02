"""runtime_inventory_oracle — compare DÉCLARÉ / OBSERVÉ / CODE. Lecture seule.

Une seule responsabilité : produire les trois listes d'écart. Il ne corrige rien, ne
supprime rien, ne crée aucun rôle, et ne calcule **aucun score** — un rôle rare n'est pas
un rôle mort, et un chiffre unique détruirait la seule information qui compte : lesquels.

TROIS CATÉGORIES QUI NE DOIVENT JAMAIS FUSIONNER
  déclaré              `roles.yaml` (+ `runtime_contracts`), `capabilities.json`, `agent_recipes.json`
  observé (événement)  un `capability_role` vu dans `EVIDENCE/reports/observer/*/events.jsonl`
                       => ça A TOURNÉ
  présent dans le code un fichier de `scripts/` qui appelle un modèle
                       => ça PEUT tourner. Présence n'est pas exécution.

La distinction code_possible ≠ execution_observed est la raison d'être de ce module.
Les fusionner ferait mentir l'audit dans les deux sens : croire mort ce qui n'a pas été
regardé, et croire absent ce qui n'émet pas de trace.

FENÊTRE D'OBSERVATION — voir `docs/forge/OBSERVATION_WINDOW_CONTRACT_V1.md`. Sans elle,
« jamais observé » veut dire « jamais cherché ». Preuve vécue : `repair_runtime` était
« jamais observé » trois heures avant de l'être.

claim_posture: NO_CLAIM_ALLOWED
"""
from __future__ import annotations

import glob
import json
import re
import subprocess
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
ROLES_YAML = Path(__file__).resolve().parent / "contracts" / "roles.yaml"
OBSERVER_GLOB = "EVIDENCE/reports/observer/*/events.jsonl"
CODE_GLOBS = ("scripts/**/*.py", "scripts/**/*.mjs", "scripts/**/*.js")

#: Champs bannis dans toute sortie de ce module (invariant de lane).
FORBIDDEN_KEYS = ("score", "reward", "ranking", "rank", "fitness", "health", "danger")

# --- détection de code -------------------------------------------------------------
# DEUX NIVEAUX, jamais confondus. La mention d'un modèle n'est pas un appel : l'audit du
# 2026-08-04 a mesuré 9 faux positifs sur 14 candidats en ne regardant que les mentions
# (une table de ports, un classifieur de chaînes, un nom de provider...).
_MENTION = re.compile(
    r"localhost:1234|/v1/chat/completions|lm_?studio|ollama|api\.anthropic\.com|"
    r"generativelanguage\.googleapis|\bclaude\b", re.I)
_ENDPOINT = re.compile(
    r"/v1/chat/completions|api\.anthropic\.com|generativelanguage\.googleapis")
_HTTP = re.compile(r"requests\.post\(|urllib\.request\.urlopen\(|httpx\.|fetch\(")
_BINAIRE = re.compile(r"which\(\s*[\"']claude[\"']\s*\)|claude\s+--print|[\"']claude[\"']\s*,")
_PROC = re.compile(r"subprocess\.(run|Popen|check_output)\(|child_process|spawn\(|execFile")
_IMPORT = re.compile(r"^\s*(?:from\s+(\w+)\s+import|import\s+(\w+))", re.M)

CALLS_MODEL = "CALLS_MODEL"
MENTIONS_MODEL = "MENTIONS_MODEL"


@dataclass
class ObservationWindow:
    """Fenêtre d'observation. `days=None` = tout l'historique disponible."""

    days: int | None = None
    projects: list[str] = field(default_factory=list)   # [] = tous
    sources: list[str] = field(default_factory=lambda: [OBSERVER_GLOB])

    def as_dict(self) -> dict[str, Any]:
        return asdict(self)


def declared_runtimes(roles_path: Path | None = None) -> dict[str, dict[str, Any]]:
    """Rôles déclarés : modèle, provider, entrypoint/adapter/kill_switch si présents."""
    import yaml
    data = yaml.safe_load((roles_path or ROLES_YAML).read_text(encoding="utf-8")) or {}
    out: dict[str, dict[str, Any]] = {}
    for m in data.get("models", []):
        for r in m.get("roles", []):
            out[r] = {"model": m.get("id"), "provider": m.get("provider"),
                      "entrypoint": None, "adapter": None, "kill_switch": None}
    for r, c in (data.get("runtime_contracts") or {}).items():
        impl = c.get("implementation") or {}
        out.setdefault(r, {"model": None, "provider": None})
        out[r].update({"entrypoint": impl.get("entrypoint"), "adapter": impl.get("adapter"),
                       "kill_switch": impl.get("kill_switch")})
    return out


def observed_by_event(window: ObservationWindow,
                      repo_root: Path | None = None) -> dict[str, dict[str, Any]]:
    """Rôles vus dans les événements Observer. `ts` en epoch, `None` si non daté."""
    root = repo_root or REPO_ROOT
    borne = None
    if window.days is not None:
        import time
        borne = time.time() - window.days * 86400
    vus: dict[str, dict[str, Any]] = {}
    for p in glob.glob(str(root / OBSERVER_GLOB)):
        projet = Path(p).parent.name
        if window.projects and projet not in window.projects:
            continue
        with open(p, encoding="utf-8") as fh:
            for line in fh:
                try:
                    e = json.loads(line)
                except json.JSONDecodeError:
                    continue
                a, pl = e.get("actor") or {}, e.get("payload") or {}
                ts = e.get("ts")
                for role in {a.get("capability_role"), pl.get("capability_role")} - {None}:
                    cur = vus.setdefault(role, {"events": 0, "last_ts": None,
                                                "projects": set(), "in_window": 0})
                    cur["events"] += 1
                    cur["projects"].add(projet)
                    if isinstance(ts, (int, float)):
                        if cur["last_ts"] is None or ts > cur["last_ts"]:
                            cur["last_ts"] = ts
                        if borne is None or ts >= borne:
                            cur["in_window"] += 1
                    elif borne is None:
                        cur["in_window"] += 1  # non daté : compté seulement hors fenêtre
    for v in vus.values():
        v["projects"] = sorted(v["projects"])
    return vus


def classify_file(texte: str) -> str | None:
    """`CALLS_MODEL`, `MENTIONS_MODEL`, ou None. Deux niveaux, jamais fusionnés."""
    if not _MENTION.search(texte):
        return None
    if _ENDPOINT.search(texte) and _HTTP.search(texte):
        return CALLS_MODEL
    if _BINAIRE.search(texte) and _PROC.search(texte):
        return CALLS_MODEL
    return MENTIONS_MODEL


def observed_in_code(repo_root: Path | None = None) -> list[dict[str, Any]]:
    """Fichiers de `scripts/` qui appellent un modèle. Tests exclus."""
    root = repo_root or REPO_ROOT
    resultats: list[dict[str, Any]] = []
    for motif in CODE_GLOBS:
        for p in glob.glob(str(root / motif), recursive=True):
            rel = Path(p).relative_to(root).as_posix()
            if "__pycache__" in rel or "/tests/" in rel or ".test." in rel \
                    or re.search(r"(^|/)(test_|phase\d_tests/)", rel):
                continue
            texte = Path(p).read_text(encoding="utf-8", errors="replace")
            niveau = classify_file(texte)
            if niveau != CALLS_MODEL:
                continue
            resultats.append({"entrypoint": rel, "level": niveau,
                              "endpoint": bool(_ENDPOINT.search(texte)),
                              "binary": bool(_BINAIRE.search(texte))})
    return sorted(resultats, key=lambda x: x["entrypoint"])


def importers_of(module: str, repo_root: Path | None = None) -> list[str]:
    """Qui importe ce module ? Un fichier « hors périmètre » importé par la Forge n'est
    pas hors périmètre — c'est une dépendance non déclarée."""
    root = repo_root or REPO_ROOT
    nom = Path(module).stem
    out = []
    for p in glob.glob(str(root / "scripts/**/*.py"), recursive=True):
        rel = Path(p).relative_to(root).as_posix()
        if rel == module or "__pycache__" in rel or "/tests/" in rel:
            continue
        for m in _IMPORT.finditer(Path(p).read_text(encoding="utf-8", errors="replace")):
            if nom in (m.group(1), m.group(2)):
                out.append(rel)
                break
    return sorted(out)


def declared_at(role: str, repo_root: Path | None = None) -> str | None:
    """Date du commit qui a introduit ce rôle dans roles.yaml. `None` = non commité.

    « Déclaré aujourd'hui, jamais observé » ne se lit pas comme « déclaré depuis six mois,
    jamais observé ». Sans cette date, les deux se confondent.
    """
    root = repo_root or REPO_ROOT
    try:
        out = subprocess.run(
            ["git", "log", "-1", "--format=%aI", "-S", role, "--",
             "forge/contracts/roles.yaml"],
            cwd=root, capture_output=True, text=True, timeout=30, encoding="utf-8")
        return (out.stdout or "").strip() or None
    except (OSError, subprocess.SubprocessError):
        return None


def compare(window: ObservationWindow | None = None,
            repo_root: Path | None = None) -> dict[str, Any]:
    """Les trois listes d'écart. Aucun score, aucun jugement, aucune décision."""
    win = window or ObservationWindow()
    declares = declared_runtimes()
    vus = observed_by_event(win, repo_root)
    code = observed_in_code(repo_root)
    entrypoints_declares = {d.get("entrypoint") for d in declares.values() if d.get("entrypoint")}

    declared_not_observed = []
    for role in sorted(declares):
        v = vus.get(role)
        if v and v["in_window"]:
            continue
        declared_not_observed.append({
            "capability_role": role,
            "model": declares[role].get("model"),
            "declared_at": declared_at(role, repo_root),
            "events_total": (v or {}).get("events", 0),
            # observé HORS fenêtre n'est pas « jamais observé » : deux états distincts.
            "status": "observed_outside_window" if v else "never_observed",
            "requires_observation_window": True,
        })

    observed_not_declared_event = [
        {"capability_role": r, "events": v["events"], "projects": v["projects"]}
        for r, v in sorted(vus.items()) if r not in declares
    ]

    observed_code_not_declared = [
        {"entrypoint": c["entrypoint"], "level": c["level"],
         "imported_by": importers_of(c["entrypoint"], repo_root),
         "note": "code_possible — presence n est pas execution"}
        for c in code if c["entrypoint"] not in entrypoints_declares
    ]

    return {
        "schema": "forge.runtime_inventory.v1",
        "observation_window": win.as_dict(),
        "declared_total": len(declares),
        "observed_event_total": len(vus),
        "code_calls_model_total": len(code),
        "declared_and_observed": sorted(r for r in declares if vus.get(r, {}).get("in_window")),
        "declared_not_observed": declared_not_observed,
        "observed_not_declared_event": observed_not_declared_event,
        "observed_code_not_declared": observed_code_not_declared,
        "requires_observation_window": True,
    }


# --- signal de dérive (destination : `drift.detected` de l'Observer) ----------------
DRIFT_PATH = REPO_ROOT / "EVIDENCE" / "bundles" / "runtime_drift.jsonl"

#: Trois cas SÉPARÉS. Les mélanger reviendrait à traiter « pas encore regardé » comme
#: « anomalie », et l'alerte deviendrait du bruit qu'on apprend à ignorer.
DRIFT_KINDS = {
    "declared_not_observed": "INFORMATION",
    "observed_not_declared_event": "ALERTE",
    "observed_code_not_declared": "ALERTE_CODE",
}


def drift_records(rapport: dict[str, Any]) -> list[dict[str, Any]]:
    """Transforme le rapport en lignes `drift.detected`. Pur, sans effet de bord."""
    import time
    lignes = []
    for cle, severite in DRIFT_KINDS.items():
        for item in rapport.get(cle, []):
            lignes.append({
                "schema": "forge.runtime_drift.v1",
                "drift_kind": cle,
                "severity": severite,
                "subject": item.get("capability_role") or item.get("entrypoint"),
                "detail": item,
                "observation_window": rapport["observation_window"],
                "ts": time.time(),
            })
    return lignes


def emit_drift(rapport: dict[str, Any], path: Path | None = None) -> int:
    """Écrit les lignes de dérive. Propose-only : aucun gel, aucune suppression."""
    lignes = drift_records(rapport)
    cible = path or DRIFT_PATH
    cible.parent.mkdir(parents=True, exist_ok=True)
    with open(cible, "a", encoding="utf-8") as fh:
        for x in lignes:
            fh.write(json.dumps(x, ensure_ascii=False, sort_keys=True) + "\n")
    return len(lignes)


def main(argv: list[str] | None = None) -> int:
    import argparse
    ap = argparse.ArgumentParser(description="Runtime Inventory Oracle (lecture seule)")
    ap.add_argument("--days", type=int, default=None, help="fenêtre en jours (défaut : tout)")
    ap.add_argument("--project", action="append", default=[], help="restreindre à un projet")
    ap.add_argument("--emit", action="store_true", help="écrire runtime_drift.jsonl")
    a = ap.parse_args(argv)

    rapport = compare(ObservationWindow(days=a.days, projects=a.project))
    print(json.dumps(rapport, ensure_ascii=False, indent=1))
    if a.emit:
        n = emit_drift(rapport)
        print(f"\n{n} ligne(s) de dérive écrite(s) dans {DRIFT_PATH}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
