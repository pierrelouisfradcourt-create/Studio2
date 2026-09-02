"""forge/tool_observability.py — Étape 4 du charter V2 (SKILLS
OBSERVABLES, docs/fvl/FVL_PHASE_0_5_CHARTER.md §4, ligne « 4. SKILLS OBSERVABLES »).

PÉRIMÈTRE STRICT — observer, jamais activer (charter §4.0) :
  - aucun agent ne reçoit d'outil ou de skill nouveau ici ;
  - `forge.contract._declared_tools` (trou I4 : retourne la PROSE des champs
    skill/plugin, pas des identifiants typés) n'est PAS corrigé — ce module
    l'observe depuis l'extérieur, avec sa propre lecture, sans y toucher ;
  - `forge.audit.DispatchRecord`, `_append_audit`, `payload.allowed_tools` ne
    sont PAS modifiés — toute donnée neuve est additive, dans SON PROPRE
    fichier (précédent exact : `model_executed` dans `forge.context_manifest`).
  - aucun changement de verdict/gate/oracle/décision. Advisory strict.

Cinq maillons, cinq lecteurs, AUCUN OK global :

  1. déclaration  — `read_declared_tools`      : identifiant TYPÉ vs prose, sur
                                                   le contenu réel des champs
                                                   skill/plugin d'un contrat.
  2. chargement   — `read_loaded_tools`         : ce que `forge.run_real
                                                   ._STEP_TOOLS` met RÉELLEMENT
                                                   à disposition d'une étape.
                                                   NOT_MEASURED distinct de
                                                   EMPTY (0 est une mesure).
  3. confinement  — `assert_tool_allowed`       : refus PAR LE CODE d'un nom
                                                   d'outil hors table chargée,
                                                   sans modèle, sans subprocess
                                                   (patron qwen-file-worker :
                                                   liste constante + défaut
                                                   refus, prouvé par appel
                                                   direct).
  4. appel réel   — `parse_tool_use_events` /
                    `extract_final_result`      : extraction déterministe des
                                                   événements `tool_use` d'une
                                                   sortie RÉELLE `claude -p
                                                   --output-format stream-json
                                                   --verbose` (JSONL). Fonctions
                                                   PURES, testées sur une
                                                   capture RÉELLE (jamais
                                                   simulée) — voir
                                                   `tests/fixtures/
                                                   tool_observability/`.
                                                   NON câblé dans
                                                   `forge.run_real
                                                   ._claude_call_raw` : ce
                                                   fichier n'est pas modifié
                                                   (voir rapport de mission).
  5. trace        — `append_tool_observability_record` /
                    `read_tool_observability_records` : consigne 1+2 en JSONL
                                                   HMAC-signé (même mécanisme
                                                   que `forge.verdict`/
                                                   `forge.context_manifest`),
                                                   dans SON PROPRE fichier,
                                                   exploitable par un lecteur
                                                   (CLI `python -m
                                                   forge.tool_observability`).

claim_verdict: NO_CLAIM_ALLOWED — ce module mesure, il ne juge rien.
"""
from __future__ import annotations

import json
import re
import time
from dataclasses import asdict, dataclass
from pathlib import Path

from forge.contract import CONTRACTS_DIR, IMPORTANT, REPO_ROOT, field_state
from forge.verdict import CLAIM_VERDICT, _sign_mapping, _verify_mapping, current_git_head

SCHEMA = "forge.tool_observability.v1"

# --- Maillon 1 — déclaration, typée -------------------------------------------

DECLARATION_KIND_EMPTY = "empty"            # absent ou sentinelle 'aucun'
DECLARATION_KIND_IDENTIFIER = "identifier"  # ressemble à un identifiant d'outil/skill
DECLARATION_KIND_PROSE = "prose"            # texte narratif : PAS un identifiant

# Identifiant plausible : un seul « mot » (lettres/chiffres/_/./:/- , AUCUN espace).
# Couvre les formes réellement observées dans le dépôt : 'forge', 'world-scan',
# 'architecture-review' (slugs de skill) et une forme 'plugin:skill' éventuelle.
# Un texte à espaces (une phrase) ne matche jamais — c'est tout le point : la
# même heuristique « pas d'espace = ressemble à un chemin/identifiant » que
# `forge.context_manifest._looks_like_path` (déjà éprouvée sur les 14 contrats
# réels du dépôt pour mandatory_read), appliquée ici aux champs skill/plugin.
_IDENTIFIER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.:\-]*$")


def classify_declared_value(raw: object) -> str:
    """Kind d'UNE valeur de champ (skill OU plugin), TYPÉ, jamais de la prose
    prise pour un identifiant. Réutilise `forge.contract.field_state` (lecture
    seule) pour distinguer absent/'aucun' (EMPTY) de rempli."""
    state = field_state(raw)
    if state != "filled":
        return DECLARATION_KIND_EMPTY
    text = str(raw).strip()
    return DECLARATION_KIND_IDENTIFIER if _IDENTIFIER_RE.match(text) else DECLARATION_KIND_PROSE


@dataclass(frozen=True)
class DeclaredField:
    field: str                # 'skill' | 'plugin'
    raw: "str | None"         # valeur brute (None si absente ou non-str)
    field_state: str          # 'filled' | 'declared_empty' | 'absent' (contract.field_state)
    kind: str                 # DECLARATION_KIND_*


def read_declared_tools(contract: dict) -> tuple[DeclaredField, ...]:
    """Maillon 1 : les champs `skill`/`plugin` du contrat, chacun TYPÉ. Ne
    modifie ni ne lit `contract._declared_tools` — lecture indépendante,
    directement sur le dict de contrat (même source, autre œil)."""
    out = []
    for f in IMPORTANT:  # ("skill", "plugin") — ordre stable du schéma
        raw = contract.get(f)
        out.append(DeclaredField(
            field=f,
            raw=raw if isinstance(raw, str) else None,
            field_state=field_state(raw),
            kind=classify_declared_value(raw),
        ))
    return tuple(out)


def scan_all_contracts(contracts_dir: "Path | None" = None) -> tuple[dict, ...]:
    """Mesure de PRODUCTION (preuve exigée #5) : `read_declared_tools` sur
    CHAQUE contrat réel du dépôt. Exclut les fichiers qui ne sont pas des
    contrats d'étape (SCHEMA.md, PLAYABLE_CONTRACT.md — pas du YAML ; roles.yaml
    — le registre, pas un contrat d'agent, sans champ skill/plugin CRITIQUE).
    Ne lève jamais sur un fichier illisible/mal formé : consigné avec
    kind='error', jamais une exception qui interromprait le scan."""
    import yaml

    d = Path(contracts_dir) if contracts_dir else CONTRACTS_DIR
    results = []
    for path in sorted(d.glob("*.yaml")):
        if path.name == "roles.yaml":
            continue
        etape = path.stem
        try:
            data = yaml.safe_load(path.read_text(encoding="utf-8"))
        except (OSError, yaml.YAMLError) as exc:
            results.append({"etape": etape, "error": str(exc)})
            continue
        if not isinstance(data, dict):
            results.append({"etape": etape, "error": "contrat non-mapping"})
            continue
        declared = read_declared_tools(data)
        results.append({
            "etape": etape,
            "fields": tuple(asdict(f) for f in declared),
        })
    return tuple(results)


# --- Maillon 2 — chargement -----------------------------------------------------

LOADING_STATUS_NOT_MEASURED = "NOT_MEASURED"  # étape absente de la table : RIEN observé
LOADING_STATUS_EMPTY = "EMPTY"                # entrée présente, tuple vide (0 outil chargé)
LOADING_STATUS_LOADED = "LOADED"              # entrée présente, >=1 outil


@dataclass(frozen=True)
class LoadedTools:
    etape: str
    tools: "tuple[str, ...]"
    status: str


def read_loaded_tools(etape: str) -> LoadedTools:
    """Maillon 2 : ce que `forge.run_real._STEP_TOOLS` met RÉELLEMENT à
    disposition d'une étape au moment de l'appel `claude -p` — PAS
    `payload.allowed_tools` (vide par construction, cf. contract.py I4).

    NOT_MEASURED (étape absente de la table) est DISTINCT de EMPTY (entrée
    présente, tuple vide) : invariant Pierre `NOT_MEASURED != OK` — une étape
    dont personne n'a rempli l'entrée n'est pas la même chose qu'une étape
    déclarée sans aucun outil.
    """
    from forge.run_real import _STEP_TOOLS  # import tardif : lecture seule, pas de cycle

    if etape not in _STEP_TOOLS:
        return LoadedTools(etape=etape, tools=(), status=LOADING_STATUS_NOT_MEASURED)
    tools = tuple(_STEP_TOOLS[etape])
    status = LOADING_STATUS_LOADED if tools else LOADING_STATUS_EMPTY
    return LoadedTools(etape=etape, tools=tools, status=status)


# --- Maillon 3 — confinement, prouvé SANS modèle --------------------------------

class ToolNotAllowed(Exception):
    """Levée par `assert_tool_allowed` — refus PAR LE CODE, jamais une
    supposition sur ce qu'un modèle choisirait de faire. Patron de référence :
    liste constante + défaut refus + preuve par appel direct (sans modèle,
    sans subprocess) — précédent hors dépôt `qwen-file-worker`."""


def _tool_name_matches(name: str, allowed: "tuple[str, ...]") -> bool:
    """Vrai ssi `name` est couvert par une entrée de `allowed`. Correspondance
    EXACTE, sauf le motif `Tool(prefix:*)` déjà en usage dans `_STEP_TOOLS`
    (ex. 'Bash(node:*)') : un nom concret 'Bash(node:ls)' matche ce motif par
    préfixe ('Bash(node:'), jamais un simple 'contains'."""
    for pattern in allowed:
        if pattern == name:
            return True
        if pattern.endswith(":*)") and "(" in pattern:
            prefix = pattern[: -len("*)")]
            if name.startswith(prefix):
                return True
    return False


def assert_tool_allowed(etape: str, tool_name: str) -> None:
    """Maillon 3 : lève `ToolNotAllowed` si `tool_name` n'est couvert par
    AUCUNE entrée de `read_loaded_tools(etape).tools`. DÉFAUT REFUS : une étape
    NOT_MEASURED (absente de `_STEP_TOOLS`) refuse TOUT nom — jamais un
    laissez-passer par omission. Fonction PURE : aucun réseau, aucun
    subprocess, aucun appel modèle — la preuve est l'exécution directe de
    cette fonction, pas un comportement observé d'un agent."""
    loaded = read_loaded_tools(etape)
    if _tool_name_matches(tool_name, loaded.tools):
        return
    raise ToolNotAllowed(
        f"outil {tool_name!r} refusé pour l'étape {etape!r} : hors de la table "
        f"chargée {loaded.tools!r} (statut={loaded.status})"
    )


# --- Maillon 4 — appel réel : extraction déterministe (fonctions PURES) --------
#
# `--output-format json` (utilisé par `forge.run_real._claude_call_raw` en
# production) rend un SEUL objet résultat — aucun événement intermédiaire,
# donc aucun tool_use observable de ce format (vérifié : `claude -p --help`,
# « json (single result) »). `--output-format stream-json --verbose` rend un
# JSONL d'événements, PROUVÉ mécaniquement le 2026-07-30 par un appel RÉEL
# (`claude -p --model haiku --output-format stream-json --verbose ...`, capturé
# dans tests/fixtures/tool_observability/) : un bloc `{"type":"assistant",
# "message":{"content":[{"type":"tool_use","name":"Bash",...}]}}` y apparaît,
# suivi d'une ligne finale `{"type":"result", "total_cost_usd":..., "usage":
# ...}` STRUCTURELLEMENT IDENTIQUE à ce que `--output-format json` rend seul.
#
# Ces deux fonctions savent lire ce flux. Elles ne sont PAS câblées dans
# `forge.run_real._claude_call_raw` (fichier non modifié par ce chantier) —
# voir le rapport de mission pour la raison de cette limite assumée.

def parse_tool_use_events(stream_jsonl_text: str) -> "tuple[dict, ...]":
    """Événements `tool_use` d'une sortie `--output-format stream-json
    --verbose`, dans l'ordre d'apparition. PURE : aucune I/O, ne lève jamais
    sur une ligne corrompue (ignorée — un flux partiellement écrit ne doit
    jamais faire planter la lecture). Une sortie SANS tool_use rend un tuple
    VIDE, distinct d'un tuple vide par échec de parse (0 est une mesure)."""
    events: list[dict] = []
    for raw in stream_jsonl_text.splitlines():
        raw = raw.strip()
        if not raw:
            continue
        try:
            rec = json.loads(raw)
        except ValueError:
            continue
        if not isinstance(rec, dict) or rec.get("type") != "assistant":
            continue
        message = rec.get("message")
        if not isinstance(message, dict):
            continue
        for block in message.get("content") or []:
            if isinstance(block, dict) and block.get("type") == "tool_use":
                events.append({
                    "name": block.get("name"),
                    "tool_use_id": block.get("id"),
                    "input_keys": sorted((block.get("input") or {}).keys()),
                })
    return tuple(events)


def extract_final_result(stream_jsonl_text: str) -> "dict | None":
    """Dernière ligne `type: result` d'un flux `stream-json` — mêmes champs
    que `--output-format json` seul (ok/cost/usage). `None` si absente/toutes
    les lignes illisibles (jamais une exception)."""
    last: "dict | None" = None
    for raw in stream_jsonl_text.splitlines():
        raw = raw.strip()
        if not raw:
            continue
        try:
            rec = json.loads(raw)
        except ValueError:
            continue
        if isinstance(rec, dict) and rec.get("type") == "result":
            last = rec
    return last


def tool_names_used(stream_jsonl_text: str) -> "tuple[str, ...]":
    """Noms d'outils utilisés (dédupliqués, ordre de première apparition) —
    forme condensée de `parse_tool_use_events`, pratique pour un manifest."""
    seen: list[str] = []
    for ev in parse_tool_use_events(stream_jsonl_text):
        name = ev.get("name")
        if isinstance(name, str) and name not in seen:
            seen.append(name)
    return tuple(seen)


# --- Maillon 5 — trace, consignée de façon exploitable --------------------------

def tool_observability_manifest_path(run_dir: "Path | str", etape: str) -> Path:
    """Fichier DISTINCT du Context Manifest (`forge.context_manifest` n'est ni
    lu ni modifié ici) — même dossier `context/`, même convention de nommage."""
    return Path(run_dir) / "context" / f"{etape}.tool_observability.jsonl"


def build_tool_observability_record(
    etape: str, run_id: str, contract: dict, *, ts: "float | None" = None,
) -> dict:
    """Corps NON SIGNÉ — combine maillon 1 (déclaré) et maillon 2 (chargé) pour
    une étape/run donnés. Utile aux tests qui veulent inspecter avant signature."""
    declared = read_declared_tools(contract)
    loaded = read_loaded_tools(etape)
    return {
        "schema": SCHEMA,
        "run_id": run_id,
        "etape": etape,
        "ts": ts if ts is not None else time.time(),
        "git_head": current_git_head() or None,
        "declared": [asdict(f) for f in declared],
        "loaded": {"tools": list(loaded.tools), "status": loaded.status},
        "claim_verdict": CLAIM_VERDICT,
    }


def _append_line(path: Path, record: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")


def append_tool_observability_record(
    etape: str, run_id: str, contract: dict, *, run_dir: "Path | str",
    key_file: "Path | None" = None, ts: "float | None" = None,
) -> dict:
    """Construit, signe (même mécanisme HMAC que `forge.verdict`/
    `forge.context_manifest`) et APPEND la ligne maillon 1+2 de cette
    étape/run. BEST-EFFORT : les appelants (dispatch.py) encapsulent en
    try/except, comme `context_manifest` — une exception ici ne doit jamais
    faire échouer un dispatch déjà validé."""
    record = build_tool_observability_record(etape, run_id, contract, ts=ts)
    record["hmac"] = _sign_mapping(record, key_file)
    _append_line(tool_observability_manifest_path(run_dir, etape), record)
    return record


def verify_tool_observability_record(record: dict, key_file: "Path | None" = None) -> bool:
    """Vrai ssi la ligne porte un HMAC valide sur son contenu (hors `hmac`)."""
    sig = record.get("hmac") if isinstance(record, dict) else None
    if not sig:
        return False
    body = {k: v for k, v in record.items() if k != "hmac"}
    return _verify_mapping(body, sig, key_file)


def read_tool_observability_records(run_dir: "Path | str", etape: str) -> "tuple[dict, ...]":
    """Maillon 5, le LECTEUR — sans lui, le fichier écrit par
    `append_tool_observability_record` serait un connecteur dormant de plus
    (leçon explicite de la mission). Une ligne tronquée/corrompue est ignorée,
    jamais bloquante. Ne filtre PAS sur la signature (un appelant qui veut la
    preuve HMAC utilise `verify_tool_observability_record` par-dessus)."""
    path = tool_observability_manifest_path(run_dir, etape)
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


# --- CLI (inspection humaine — patron `forge.reference_guard`) ------------------

def _cli_scan_contracts() -> int:
    results = scan_all_contracts()
    counts = {DECLARATION_KIND_EMPTY: 0, DECLARATION_KIND_IDENTIFIER: 0,
              DECLARATION_KIND_PROSE: 0}
    prose_examples = []
    for r in results:
        if "error" in r:
            continue
        for f in r["fields"]:
            counts[f["kind"]] = counts.get(f["kind"], 0) + 1
            if f["kind"] == DECLARATION_KIND_PROSE:
                prose_examples.append({"etape": r["etape"], "field": f["field"],
                                       "raw": f["raw"]})
    print(json.dumps({
        "schema": SCHEMA, "contracts_scanned": len(results),
        "field_kind_counts": counts, "prose_examples": prose_examples,
        "claim_verdict": CLAIM_VERDICT,
    }, ensure_ascii=False, indent=2))
    return 0


def _cli_read(run_dir: str, etape: str, key_file: "str | None") -> int:
    kf = Path(key_file) if key_file else None
    recs = read_tool_observability_records(run_dir, etape)
    out = [{"record": r, "hmac_valid": verify_tool_observability_record(r, kf)} for r in recs]
    print(json.dumps(out, ensure_ascii=False, indent=2))
    return 0


def main(argv: "list[str] | None" = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(
        description="CLI forge.tool_observability : mesure de production "
                     "(maillon 1) + lecture de trace (maillon 5).")
    sub = parser.add_subparsers(dest="cmd")

    sub.add_parser("scan-contracts", help="maillon 1 sur tous les contrats réels "
                    "(compte identifiant/prose/vide, exemples de prose)")

    p_read = sub.add_parser("read", help="relit la trace maillon 1+2 d'une étape/run")
    p_read.add_argument("--run-dir", required=True)
    p_read.add_argument("--etape", required=True)
    p_read.add_argument("--key-file", default=None)

    args = parser.parse_args(argv)
    if args.cmd == "scan-contracts":
        return _cli_scan_contracts()
    if args.cmd == "read":
        return _cli_read(args.run_dir, args.etape, args.key_file)
    parser.print_usage()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
