"""forge/reasoning_observability.py — Étape 5 du charter V2
(RAISONNEMENT, docs/fvl/FVL_PHASE_0_5_CHARTER.md §4 : « 5. RAISONNEMENT — d'abord
tracer le paramètre, ensuite rendre le mécanisme effectif »).

PÉRIMÈTRE STRICT — observer, jamais activer (charter §4.0 ; doctrine §6.2) :
  - `reasoning` n'est PAS rendu effectif ici : aucune valeur choisie, AUCUN
    `--effort` n'est ajouté à la commande réelle construite par
    `forge.run_real._claude_call_raw` (fichier non modifié, format de sortie
    inchangé).
  - `forge/contracts/roles.yaml` n'est pas modifié.
  - Toute donnée neuve est additive, dans SON PROPRE fichier — précédents
    exacts : `model_executed` dans `forge.context_manifest`, le bloc
    `tool_observability` dans `forge.dispatch.prepare_dispatch`.
  - Aucun changement de verdict/gate/oracle/décision. Advisory strict.

Fait qui motive ce module (doctrine §3, « Observé ≠ déclaré ») : `reasoning` est
déclaré par modèle dans `roles.yaml` (`high` / `low` / `false`) et AUCUN lecteur
n'existe dans `scripts/` ni `control_plane/` — muté avant d'être lu, ce champ
serait un générateur parfait de faux positifs (l'empreinte déclarée changerait,
l'exécution non, et l'écart de métrique serait imputé à l'hypothèse).

Quatre maillons, un lecteur chacun, AUCUN verdict global (mission explicite) :

  1. déclaré              — `read_declared_reasoning` : valeur par modèle/rôle
                             dans `roles.yaml`, TYPÉE contre le vocabulaire
                             RÉELLEMENT accepté par l'exécutant (`claude -p
                             --effort <level>`, mesuré via `claude --help`).
  2. effectivement lu     — `scan_reasoning_readers` : recherche MÉCANIQUE
                             (regex, aucun LLM) d'un accès au champ `reasoning`
                             dans les modules Forge réellement dispatchables +
                             le registry partagé (`control_plane/registry.py`).
  3. réellement exécuté   — question de CAPACITÉ, en deux temps :
                             (a) `effort_flag_documented` : le binaire invoqué
                             par `_claude_call_raw` (`claude -p ...`)
                             accepte-t-il un réglage d'effort ? PURE, appliquée
                             à un texte d'aide déjà capturé (fixture réelle,
                             `claude --help`, aucun coût).
                             (b) `effort_flag_present_in_cmd` : la commande
                             RÉELLEMENT construite aujourd'hui par
                             `_claude_call_raw` porte-t-elle ce réglage ? PURE,
                             appliquée à un `cmd` observé par le seam de test
                             existant (monkeypatch de `subprocess.run`, même
                             patron que `tests/test_run_real_hardening.py`).
  4. effectivement utilisé — `classify_reasoning_evidence` : évidence
                             STRUCTURELLE (bloc `type: thinking`) dans une
                             sortie RÉELLE `claude -p --output-format
                             stream-json --verbose`. PURE, appliquée à des
                             fixtures capturées par 3 appels réels le
                             2026-07-30 (voir tests/fixtures/
                             reasoning_observability/, coût divulgué dans le
                             rapport de mission — jamais dans ce module).

claim_verdict: NO_CLAIM_ALLOWED — ce module mesure, il ne juge rien.
"""
from __future__ import annotations

import json
import re
import time
from dataclasses import asdict, dataclass
from pathlib import Path

from forge.contract import FORGE_ROLES, REPO_ROOT
from forge.verdict import CLAIM_VERDICT, _sign_mapping, _verify_mapping, current_git_head

SCHEMA = "forge.reasoning_observability.v1"

# --- Maillon 1 — déclaré, typé contre le vocabulaire RÉEL de l'exécutant -----------

# Mesuré le 2026-07-30 : `claude --help` -> "--effort <level>  Effort level for
# the current session (low, medium, high, xhigh, max)". C'est le SEUL réglage
# de raisonnement/effort documenté par le binaire invoqué par
# `forge.run_real._claude_call_raw`. Vocabulaire figé ICI (constante versionnée)
# plutôt que reparsé à chaque appel : une dérive de `claude --help` doit casser
# le test qui compare cette constante à la fixture réelle, jamais glisser en
# silence dans une classification.
EFFORT_CLI_VALUES = ("low", "medium", "high", "xhigh", "max")

DECLARED_KIND_CLI_COMPATIBLE = "cli_compatible"  # valeur ∈ EFFORT_CLI_VALUES
DECLARED_KIND_NOT_APPLICABLE = "not_applicable"  # False (Qwen, déterministe : pas de session claude -p)
DECLARED_KIND_UNKNOWN = "unknown"                # ni l'un ni l'autre (typo, valeur inventée)
DECLARED_KIND_ABSENT = "absent"                  # champ `reasoning` manquant du modèle


def classify_declared_reasoning(raw: object) -> str:
    """Kind TYPÉ d'une valeur `reasoning` brute de `roles.yaml`. Ne devine rien :
    seules les 5 chaînes de `EFFORT_CLI_VALUES` sont `cli_compatible` ; `False`
    (bool Python, pas la chaîne 'false') est `not_applicable` — c'est la forme
    réelle du YAML (`reasoning: false`, sans guillemets, pour Qwen et le runtime
    déterministe, aucun des deux n'étant une session `claude -p`)."""
    if raw is None:
        return DECLARED_KIND_ABSENT
    if raw is False:
        return DECLARED_KIND_NOT_APPLICABLE
    if isinstance(raw, str) and raw.strip().lower() in EFFORT_CLI_VALUES:
        return DECLARED_KIND_CLI_COMPATIBLE
    return DECLARED_KIND_UNKNOWN


@dataclass(frozen=True)
class DeclaredReasoning:
    model_id: str
    roles: "tuple[str, ...]"
    raw: object          # valeur brute telle que lue dans le YAML (str | False | None | autre)
    kind: str             # DECLARED_KIND_*


def read_declared_reasoning(roles_path: "Path | None" = None) -> "tuple[DeclaredReasoning, ...]":
    """Maillon 1 : `reasoning` de CHAQUE modèle déclaré dans `roles.yaml`
    (`FORGE_ROLES` par défaut — le fichier Forge-scopé, jamais openclaw/legacy).
    Un modèle sans clé `reasoning` rend `DECLARED_KIND_ABSENT`, jamais une
    exception ni un modèle silencieusement omis."""
    import yaml  # import tardif : même discipline que forge.contract (yaml absent hors venv)

    path = Path(roles_path) if roles_path else FORGE_ROLES
    data = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    out: list[DeclaredReasoning] = []
    for model in data.get("models") or []:
        if not isinstance(model, dict):
            continue
        raw = model.get("reasoning")
        out.append(DeclaredReasoning(
            model_id=str(model.get("id", "?")),
            roles=tuple(model.get("roles") or ()),
            raw=raw,
            kind=classify_declared_reasoning(raw),
        ))
    return tuple(out)


def declared_reasoning_for_role(role: str, roles_path: "Path | None" = None) -> "DeclaredReasoning | None":
    """La déclaration du modèle qui résout CE rôle (même sémantique de résolution
    que `control_plane.registry.get_model_for_role` : premier modèle qui déclare
    le rôle gagne). `None` si le rôle n'est résolu par aucun modèle — distinct
    d'un modèle résolu sans champ `reasoning` (ABSENT, pas None)."""
    for declared in read_declared_reasoning(roles_path):
        if role in declared.roles:
            return declared
    return None


# --- Maillon 2 — effectivement lu (recherche mécanique de lecteur) ----------------

# Modules Forge réellement traversés par un dispatch/exécution (jamais
# scripts/studioV2/, lane GELÉE et hors périmètre — c'est PRÉCISÉMENT la
# distinction que la doctrine §3 pose : "les seules occurrences vivent dans
# scripts/studioV2/", donc ce scan les EXCLUT par construction, il ne les
# re-découvre pas).
READER_SCAN_TARGETS = (
    "contract.py", "dispatch.py", "run_real.py", "driver.py",
    "context_manifest.py", "tool_observability.py", "verdict.py",
    "escalate.py", "panel.py", "pool.py", "runtime.py",
)

# Détecte un ACCÈS au champ `reasoning` d'un dict/objet modèle : `.get("reasoning"`,
# `["reasoning"]`, `.reasoning` (attribut). Volontairement plus large que strictement
# nécessaire (mieux vaut un faux positif qu'un lecteur raté) — voir le fixture positif
# du test pour la preuve que la détection fonctionne, et SKIPPED_VALIDATION du rapport
# de mission pour la limite assumée (regex, pas une analyse AST complète : un accès
# via getattr(model, "reason" + "ing") échapperait — jamais observé dans ce dépôt).
_READER_PATTERN = re.compile(
    r'\.get\(\s*["\']reasoning["\']|\[\s*["\']reasoning["\']\s*\]|\breasoning\s*='
)


def _scan_one_file(path: Path) -> dict:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return {"path": str(path), "exists": False, "reads_reasoning": False, "matches": ()}
    matches = tuple(m.group(0) for m in _READER_PATTERN.finditer(text))
    return {"path": str(path), "exists": True, "reads_reasoning": bool(matches), "matches": matches}


def scan_reasoning_readers(
    *, scripts_forge_dir: "Path | None" = None, registry_path: "Path | None" = None,
    targets: "tuple[str, ...] | None" = None,
) -> "tuple[dict, ...]":
    """Maillon 2 : un enregistrement PAR FICHIER SCANNÉ (trouvé ou non) — jamais
    seulement les positifs, pour que 'zéro lecteur' (mesuré) reste distinct de
    'zéro fichier regardé' (un scan vide serait un vert trompeur)."""
    base = Path(scripts_forge_dir) if scripts_forge_dir else Path(__file__).resolve().parent
    reg = Path(registry_path) if registry_path else (REPO_ROOT / "control_plane" / "registry.py")
    files = targets if targets is not None else READER_SCAN_TARGETS
    records = [_scan_one_file(base / name) for name in files]
    records.append(_scan_one_file(reg))
    return tuple(records)


# --- Maillon 3 — capacité de l'exécutant (a) puis câblage réel (b) ----------------

_EFFORT_HELP_RE = re.compile(r"--effort\s*<level>")


def effort_flag_documented(help_text: str) -> bool:
    """Maillon 3(a), fonction PURE : vrai ssi le texte d'aide du binaire (déjà
    capturé, jamais relancé ici) documente un réglage d'effort. Établi sur une
    capture réelle de `claude --help` (2026-07-30, 0 $ — commande locale, aucun
    appel modèle) : tests/fixtures/reasoning_observability/claude_help.txt."""
    return bool(_EFFORT_HELP_RE.search(help_text))


def effort_flag_present_in_cmd(cmd: "list[str] | tuple[str, ...]") -> bool:
    """Maillon 3(b), fonction PURE : vrai ssi `--effort` apparaît dans une
    commande DÉJÀ CONSTRUITE. Ne construit ni n'exécute rien elle-même —
    s'applique à un `cmd` observé par le seam de test existant (monkeypatch de
    `run_real.subprocess.run`, patron identique à `capture_cmd` dans
    `tests/test_run_real_hardening.py`), jamais un nouveau spawn."""
    return "--effort" in tuple(cmd)


# --- Maillon 4 — évidence structurelle d'utilisation réelle -----------------------

REASONING_EVIDENCE_NONE = "NO_EVIDENCE"                   # aucun bloc de raisonnement observé
REASONING_EVIDENCE_THINKING_BLOCK = "THINKING_BLOCK_PRESENT"  # >=1 bloc {"type":"thinking"}


def classify_reasoning_evidence(stream_jsonl_text: str) -> dict:
    """Maillon 4 : évidence STRUCTURELLE dans une sortie RÉELLE `claude -p
    --output-format stream-json --verbose` (jamais `--output-format json` seul —
    ce format ne rend qu'un objet résultat unique, aucun bloc de contenu n'y est
    observable ; même constat que `forge.tool_observability` pour les
    `tool_use`). PURE : aucune I/O, aucun réseau, aucun appel modèle. Une ligne
    corrompue est ignorée, jamais bloquante — un flux partiellement écrit ne
    doit jamais faire planter la lecture."""
    thinking_blocks = 0
    result: "dict | None" = None
    for raw in stream_jsonl_text.splitlines():
        raw = raw.strip()
        if not raw:
            continue
        try:
            rec = json.loads(raw)
        except ValueError:
            continue
        if not isinstance(rec, dict):
            continue
        if rec.get("type") == "assistant":
            content = (rec.get("message") or {}).get("content") or []
            for block in content:
                if isinstance(block, dict) and block.get("type") == "thinking":
                    thinking_blocks += 1
        elif rec.get("type") == "result":
            result = rec
    usage = (result or {}).get("usage") or {}
    status = (REASONING_EVIDENCE_THINKING_BLOCK if thinking_blocks
              else REASONING_EVIDENCE_NONE)
    return {
        "thinking_blocks": thinking_blocks,
        "status": status,
        "result_output_tokens": usage.get("output_tokens"),
        "result_cost_usd": (result or {}).get("total_cost_usd"),
        "result_duration_api_ms": (result or {}).get("duration_api_ms"),
    }


# --- trace par run (additive, dispatch-time — maillon 1 seul : c'est le seul  ----
# --- maillon connu AU MOMENT du dispatch, avant tout appel exécutant) -------------

def reasoning_observability_manifest_path(run_dir: "Path | str", etape: str) -> Path:
    """Fichier DISTINCT du Context Manifest et de tool_observability — même
    dossier `context/`, même convention de nommage (précédent exact :
    `tool_observability_manifest_path`)."""
    return Path(run_dir) / "context" / f"{etape}.reasoning_observability.jsonl"


def build_reasoning_observability_record(
    etape: str, run_id: str, contract: dict, *,
    roles_path: "Path | None" = None, ts: "float | None" = None,
) -> dict:
    """Corps NON SIGNÉ — maillon 1 SEUL, résolu pour le `capability_role` du
    contrat de cette étape (même rôle que celui que `forge.contract
    .resolve_runtime` résout en modèle). Les maillons 2/3/4 sont des mesures
    repo-wide ou nécessitant un appel réel : ils vivent dans leurs propres CLI
    (`scan-readers`, fixtures maillon 4), pas dans cette trace par-run."""
    role = contract.get("capability_role")
    declared = declared_reasoning_for_role(role, roles_path) if role else None
    return {
        "schema": SCHEMA,
        "run_id": run_id,
        "etape": etape,
        "ts": ts if ts is not None else time.time(),
        "git_head": current_git_head() or None,
        "capability_role": role,
        "declared": asdict(declared) if declared else None,
        "declared_status": "RESOLVED" if declared else "UNRESOLVED",
        "claim_verdict": CLAIM_VERDICT,
    }


def _append_line(path: Path, record: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")


def append_reasoning_observability_record(
    etape: str, run_id: str, contract: dict, *, run_dir: "Path | str",
    roles_path: "Path | None" = None, key_file: "Path | None" = None,
    ts: "float | None" = None,
) -> dict:
    """Construit, signe (même mécanisme HMAC que `forge.verdict`/
    `forge.context_manifest`/`forge.tool_observability`) et APPEND la ligne
    maillon-1 de cette étape/run. BEST-EFFORT : l'appelant (`dispatch.py`)
    encapsule en try/except — une exception ici ne doit jamais faire échouer un
    dispatch déjà validé."""
    record = build_reasoning_observability_record(etape, run_id, contract, roles_path=roles_path, ts=ts)
    record["hmac"] = _sign_mapping(record, key_file)
    _append_line(reasoning_observability_manifest_path(run_dir, etape), record)
    return record


def verify_reasoning_observability_record(record: dict, key_file: "Path | None" = None) -> bool:
    sig = record.get("hmac") if isinstance(record, dict) else None
    if not sig:
        return False
    body = {k: v for k, v in record.items() if k != "hmac"}
    return _verify_mapping(body, sig, key_file)


def read_reasoning_observability_records(run_dir: "Path | str", etape: str) -> "tuple[dict, ...]":
    """Le LECTEUR — sans lui, le fichier écrit par
    `append_reasoning_observability_record` serait un connecteur dormant de
    plus (leçon explicite, déjà nommée pour `tool_observability`). Une ligne
    tronquée/corrompue est ignorée, jamais bloquante."""
    path = reasoning_observability_manifest_path(run_dir, etape)
    if not path.exists():
        return ()
    out = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if isinstance(rec, dict):
            out.append(rec)
    return tuple(out)


# --- CLI (inspection humaine — patron `forge.tool_observability`/`forge.reference_guard`) --

def _cli_scan_declared() -> int:
    declared = read_declared_reasoning()
    counts: dict[str, int] = {}
    for d in declared:
        counts[d.kind] = counts.get(d.kind, 0) + 1
    print(json.dumps({
        "schema": SCHEMA, "models_scanned": len(declared),
        "kind_counts": counts,
        "declared": [asdict(d) for d in declared],
        "claim_verdict": CLAIM_VERDICT,
    }, ensure_ascii=False, indent=2))
    return 0


def _cli_scan_readers() -> int:
    records = scan_reasoning_readers()
    readers = [r for r in records if r["reads_reasoning"]]
    print(json.dumps({
        "schema": SCHEMA, "files_scanned": len(records),
        "reader_count": len(readers),
        "records": list(records),
        "claim_verdict": CLAIM_VERDICT,
    }, ensure_ascii=False, indent=2))
    return 0


def _cli_read(run_dir: str, etape: str, key_file: "str | None") -> int:
    kf = Path(key_file) if key_file else None
    recs = read_reasoning_observability_records(run_dir, etape)
    out = [{"record": r, "hmac_valid": verify_reasoning_observability_record(r, kf)} for r in recs]
    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0


def main(argv: "list[str] | None" = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(
        description="CLI forge.reasoning_observability : maillon 1 (déclaré, "
                     "production réelle), maillon 2 (recherche de lecteur), "
                     "maillon 5 (lecture de trace par run).")
    sub = parser.add_subparsers(dest="cmd")

    sub.add_parser("scan-declared", help="maillon 1 sur roles.yaml réel "
                    "(compte par kind, détail par modèle)")
    sub.add_parser("scan-readers", help="maillon 2 sur les modules Forge réels "
                    "+ control_plane/registry.py (compte de lecteurs trouvés)")

    p_read = sub.add_parser("read", help="relit la trace maillon 1 d'une étape/run")
    p_read.add_argument("--run-dir", required=True)
    p_read.add_argument("--etape", required=True)
    p_read.add_argument("--key-file", default=None)

    args = parser.parse_args(argv)
    if args.cmd == "scan-declared":
        return _cli_scan_declared()
    if args.cmd == "scan-readers":
        return _cli_scan_readers()
    if args.cmd == "read":
        return _cli_read(args.run_dir, args.etape, args.key_file)
    parser.print_usage()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
