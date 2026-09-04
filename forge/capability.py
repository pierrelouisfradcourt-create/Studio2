"""Capacités convocables sur le GAME_BLUEPRINT (Lot 2, plan V2 2026-09-03, GO Pierre) — K2 + K3 + K7.

DEUX CHOSES, PAS PLUS :
  * `spec(name)` — la fiche complète d'une capacité : ce que `capability_registry.yaml` DÉCLARE
    (reads/writes/validator/problem_codes/escalation/verrous) + ce que les sources de vérité
    existantes DISENT (contrat 17 champs, roles.yaml, tables de run_real). Extraction fidèle,
    aucune compétence inventée.
  * `invoke_capability(...)` — UNE convocation : porte (`prepare_dispatch` + `check_spawn`),
    prompt assemblé DEPUIS LES SECTIONS DU BLUEPRINT (plus depuis `_UPSTREAM_BY_STEP`), exécuteur
    (réel `claude -p` ou injecté), matérialisation + validateur de PRODUCTION
    (`run_real._materialize_artifact`), oracle déterministe déclaré, écriture de LA SEULE section
    possédée, reçus d'audit `spawn_authorized`/`spawn_executed` (chemin B, comme le driver).

CE QUE CE MODULE N'EST PAS : un Director (il ne choisit jamais quelle capacité appeler ni quand),
un ordre d'étapes, un juge de valeur. Il ne lit ni ne modifie un verdict. K7 : un problème n'a un
`code` que si son `producer` est un mécanisme (validateur, oracle, porte, exécuteur) ; ce que
l'agent DEMANDE (escalade) est rendu comme `requests`, jamais comme code. NO_CLAIM_ALLOWED.

Usage : python -m forge.capability invoke <capacité> --blueprint <json> --run-id <id> [--out <json>]
        python -m forge.capability spec <capacité>
"""
from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

import yaml

from forge import blueprint as bp
from forge import context_manifest   # Lot 5 : lignées execution / return
from forge import studio_link        # Lot 5 : pré-mortem, journal d'erreurs du run
from forge.audit import EVENT_AUTHORIZED, EVENT_EXECUTED, append_spawn_event
from forge.contract import FORGE_ROLES, load_contract, resolve_runtime, validate_contract
from dataclasses import replace as dataclass_replace

from forge.dispatch import prepare_dispatch
from forge.driver import ForgeDriver, SPAWN_LINK_SCHEMA   # Lot 5 : next_reason, schéma spawn_link
from forge.escalate import LADDER, parse_agent_escalation, tier_of
from forge.hook_guard import check_spawn
from forge.run_real import (  # mécanismes de PRODUCTION, réutilisés tels quels
    DEFAULT_STEP_TIMEOUT_S,
    UPSTREAM_MAX_CHARS,
    _ARTIFACT_BY_STEP,
    _ARTIFACT_VALIDATORS,
    _build_spawn_link_upstream,
    _claude_call_with_transient_retry,
    _derive_disallowed,
    _extract_return_reason,
    _effective_step_tools,
    _materialize_artifact,
    _persist_final_prompt,
    _truncate_preserve_terminal_json,
    default_task_by_step,
)

REPO_ROOT = Path(__file__).resolve().parents[1]
REGISTRY_PATH = Path(__file__).resolve().parent / "capability_registry.yaml"
REGISTRY_SCHEMA = "CAPABILITY_REGISTRY/v0"
# Lot 5 (2026-09-04, GO Pierre) : propriétaires du transport et politique de timeout par capacité.
TRANSPORT_OWNERS = ("invoke", "director", "driver", "pierre")
TRANSPORT_STATUSES = ("carried", "director", "deferred", "dropped")
DEFAULT_TIMEOUT_POLICY = {"timeout_s": DEFAULT_STEP_TIMEOUT_S, "launch": "attached"}
SPAWN_LINK_ATTESTATION_NOTE = ("auto-attesté (chemin B headless) : cette ligne est écrite par forge.capability "
                               "qui exécute la convocation, aucun observateur tiers ne l'a constatée")
_SPAWN_LINK_UPSTREAM_KEYS = ("contract_path", "contract_sha256", "prompt_file", "prompt_sha256",
                             "tools_effective", "tools_disallowed_count",
                             "model_declared", "model_requested", "model_used")

# Codes K7 produits par CE module (producteur nommé à chaque émission).
CAPABILITY_UNKNOWN = "CAPABILITY_UNKNOWN"
CAPABILITY_LOCKED = "CAPABILITY_LOCKED"
CAPABILITY_NOT_INVOKABLE_V0 = "CAPABILITY_NOT_INVOKABLE_V0"
BLUEPRINT_SECTION_ABSENT = "BLUEPRINT_SECTION_ABSENT"
SPAWN_REFUSED = "SPAWN_REFUSED"
EXECUTOR_FAILED = "EXECUTOR_FAILED"
ARTIFACT_NOT_MATERIALIZABLE = "ARTIFACT_NOT_MATERIALIZABLE"
ARTIFACT_INVALID = "ARTIFACT_INVALID"
VALIDATOR_NOT_MEASURED = "VALIDATOR_NOT_MEASURED"
SECTION_WRITE_REFUSED = "SECTION_WRITE_REFUSED"
EXECUTOR_TIMEOUT_SALVAGED = "EXECUTOR_TIMEOUT_SALVAGED"


class CapabilityError(Exception):
    """Refus explicite du module — jamais un silence."""


# ----------------------------------------------------------------------------- registre / spec

def _load_registry_document(path: Path | None = None) -> dict:
    data = yaml.safe_load(Path(path or REGISTRY_PATH).read_text(encoding="utf-8")) or {}
    if data.get("schema") != REGISTRY_SCHEMA:
        raise CapabilityError(f"registre : schema {data.get('schema')!r} != {REGISTRY_SCHEMA!r}")
    return data


def load_registry(path: Path | None = None) -> dict:
    caps = _load_registry_document(path).get("capabilities")
    if not isinstance(caps, dict) or not caps:
        raise CapabilityError("registre : `capabilities` absent ou vide")
    return caps


def load_transport(path: Path | None = None) -> dict:
    """Lot 5 — propriétaire de chaque mécanisme de production emporté ou non par la convocation."""
    transport = _load_registry_document(path).get("transport")
    if not isinstance(transport, dict) or not transport:
        raise CapabilityError("registre : `transport` absent ou vide (Lot 5)")
    for name, decl in transport.items():
        if not isinstance(decl, dict) or decl.get("owner") not in TRANSPORT_OWNERS \
                or decl.get("status") not in TRANSPORT_STATUSES:
            raise CapabilityError(f"registre : transport {name!r} mal déclaré (owner/status)")
    return transport


def _reasoning_for(model: str):
    try:
        from control_plane.registry import get_reasoning_for_model
        return get_reasoning_for_model(model, caps_path=FORGE_ROLES)
    except Exception:  # noqa: BLE001 — la fiche dit UNKNOWN, elle n'invente pas
        return "UNKNOWN"


def _provider_for(role: str) -> str:
    try:
        from control_plane.registry import get_provider_for_role
        return get_provider_for_role(role, caps_path=FORGE_ROLES) or ""
    except Exception:  # noqa: BLE001
        return ""


def spec(name: str, registry: dict | None = None) -> dict:
    """Fiche complète d'une capacité — déclaré (YAML) + dérivé (contrat, roles, run_real)."""
    caps = registry or load_registry()
    if name not in caps:
        raise CapabilityError(f"capacité inconnue {name!r} (registre : {', '.join(sorted(caps))})")
    decl = dict(caps[name])
    etape = decl["contract"]
    contract = load_contract(etape)
    validate_contract(contract)
    role = contract["capability_role"]
    model = resolve_runtime(contract)
    escalation = decl.get("escalation", "aucun")
    ladder = list(LADDER) if escalation == "builder_ladder" else None
    if ladder and tier_of(model) is None:
        raise CapabilityError(
            f"{name}: escalation `builder_ladder` déclarée mais le modèle {model!r} est hors échelle")
    return {
        "name": name,
        "etape": etape,
        "kind": decl.get("kind", "llm"),
        "capability_role": role,
        # --- dérivé du contrat : la compétence réelle, jamais réécrite ici
        "mission": contract.get("objectif"),
        "skill": {
            "role": contract.get("role"),
            "exigences_cognitives": contract.get("exigences_cognitives"),
            "gardeFou": contract.get("gardeFou"),
            "memoire": contract.get("memoire"),
            "in_scope": contract.get("in_scope"),
            "out_of_scope": contract.get("out_of_scope"),
            "declared_skill": contract.get("skill"),
            "plugin": contract.get("plugin"),
            "mandatory_read": list(contract.get("mandatory_read") or []),
            "success_criteria": contract.get("success_criteria"),
            "tests_oracles": contract.get("tests_oracles"),
        },
        # --- dérivé de roles.yaml
        "model_policy": {"model": model, "provider": _provider_for(role), "ladder": ladder},
        "reasoning_policy": _reasoning_for(model),
        # --- dérivé de run_real
        "artifact": _ARTIFACT_BY_STEP.get(etape),
        "artifact_validator": (_ARTIFACT_VALIDATORS.get(_ARTIFACT_BY_STEP.get(etape, ""), None) or
                               (lambda: None)).__name__ if _ARTIFACT_BY_STEP.get(etape) else None,
        "tools": list(_effective_step_tools(etape)),
        # --- déclaré ici seulement
        "timeout_policy": dict(decl.get("timeout_policy") or DEFAULT_TIMEOUT_POLICY),
        "reads": list(decl.get("reads") or []),
        "writes": decl.get("writes"),
        "validator": decl.get("validator"),
        "problem_codes": dict(decl.get("problem_codes") or {}),
        "escalation": escalation,
        "locked": decl.get("locked"),
        "post_artifact": decl.get("post_artifact"),
        "add_dir": decl.get("add_dir"),
        "invokable_v0": bool(decl.get("invokable_v0", False)),
        "invokable_reason": decl.get("invokable_reason"),
    }


# ----------------------------------------------------------------------------- lecture Blueprint

def _read_section(blueprint: dict, ref: str) -> tuple[dict | None, object]:
    """`section` ou `section.entree` -> (meta, content). content None si absent."""
    section, _, entry = ref.partition(".")
    meta = blueprint["sections"].get(section)
    if meta is None:
        return None, None
    content = meta.get("content")
    if entry:
        sub = (content or {}).get(entry) if isinstance(content, dict) else None
        return meta, (sub or {}).get("content") if isinstance(sub, dict) else None
    return meta, content


def _render_blueprint_inputs(blueprint: dict, reads: list[dict]) -> tuple[str, list[dict]]:
    """Section de prompt « GAME_BLUEPRINT — sections lues » + la liste des entrées (version, sha)."""
    blocks: list[str] = []
    inputs: list[dict] = []
    for r in reads:
        ref = r["section"]
        meta, content = _read_section(blueprint, ref)
        if content is None:
            continue
        if isinstance(content, str):
            body, lang = content, ""
        elif ref == "gameplay":
            body, lang = yaml.safe_dump(content, allow_unicode=True, sort_keys=False), "yaml"
        else:
            body, lang = json.dumps(content, ensure_ascii=False, indent=1), "json"
        if len(body) > UPSTREAM_MAX_CHARS:
            body = _truncate_preserve_terminal_json(body)
        inputs.append({"section": ref, "version": meta["version"],
                       "content_sha256": meta["content_sha256"],
                       # Lot 5 (L22) : le sha de la sous-entrée LUE, pas celui du composite parent
                       "entry_sha256": bp.content_sha256(content)})
        blocks.append(f"### {ref} (v{meta['version']} · content_sha256={meta['content_sha256']})\n"
                      f"```{lang}\n{body}\n```")
    if not blocks:
        return "", inputs
    header = ("## GAME_BLUEPRINT — sections lues (SOURCE UNIQUE de ton contexte projet ; les "
              "fichiers homonymes du run_dir n'en sont que des projections)")
    return header + "\n\n" + "\n\n".join(blocks), inputs


def _materialize_reads(blueprint: dict, reads: list[dict], run_dir: Path) -> list[str]:
    """Projette les sections lues en fichiers de run_dir (pour les oracles legacy et l'outil Read)."""
    written: list[str] = []
    for r in reads:
        target = r.get("materialize_as")
        if not target:
            continue
        _, content = _read_section(blueprint, r["section"])
        if content is None:
            continue
        run_dir.mkdir(parents=True, exist_ok=True)
        path = run_dir / target
        if isinstance(content, str):
            path.write_text(content, encoding="utf-8")
        elif target.endswith((".yaml", ".yml")):
            path.write_text(yaml.safe_dump(content, allow_unicode=True, sort_keys=False), encoding="utf-8")
        else:
            path.write_text(json.dumps(content, ensure_ascii=False, indent=1), encoding="utf-8")
        written.append(target)
    return written


# ----------------------------------------------------------------------------- oracle déclaré

def _run_validator(sp: dict, artifact_path: Path, run_dir: Path) -> tuple[dict | None, list[dict]]:
    """Exécute l'oracle déterministe déclaré. Rend (reçu, problèmes K7). node absent => NOT_MEASURED."""
    v = sp.get("validator")
    if not v:
        return None, []
    name = v.get("name", "validator")
    cmd = [str(c).replace("{artifact}", str(artifact_path)).replace("{run_dir}", str(run_dir))
           for c in v["command"]]
    if cmd and cmd[0] == "node":
        node = shutil.which("node")
        if node is None:
            return ({"status": "NOT_MEASURED", "reason": "node indisponible"},
                    [{"code": VALIDATOR_NOT_MEASURED, "producer": name, "path": None,
                      "message": "node indisponible", "suggested_action": "installer node"}])
        cmd[0] = node
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8",
                              cwd=str(REPO_ROOT), timeout=120)
    except (OSError, subprocess.SubprocessError) as exc:
        return ({"status": "NOT_MEASURED", "reason": str(exc)},
                [{"code": VALIDATOR_NOT_MEASURED, "producer": name, "path": None,
                  "message": str(exc), "suggested_action": "reconvoke"}])
    raw = proc.stdout or ""
    start = raw.find("{")
    if start < 0:
        return ({"status": "NOT_MEASURED", "reason": "sortie sans JSON", "exit_code": proc.returncode},
                [{"code": VALIDATOR_NOT_MEASURED, "producer": name, "path": None,
                  "message": (proc.stderr or raw)[:300], "suggested_action": "reconvoke"}])
    try:
        data = json.loads(raw[start:])
    except json.JSONDecodeError as exc:
        return ({"status": "NOT_MEASURED", "reason": f"JSON illisible : {exc}"},
                [{"code": VALIDATOR_NOT_MEASURED, "producer": name, "path": None,
                  "message": str(exc), "suggested_action": "reconvoke"}])
    receipt = {"name": name, "exit_code": proc.returncode, "ok": data.get("ok"),
               "stats": data.get("stats"), "advisory": True}
    problems: list[dict] = []
    for key, code in (sp.get("problem_codes") or {}).items():
        items = data.get(key) or []
        for item in items:
            problems.append({"code": code, "producer": name, "path": f"{sp['writes']}.{key}",
                             "message": item if isinstance(item, str) else json.dumps(item, ensure_ascii=False)[:300],
                             "suggested_action": "reconvoke"})
    receipt["problem_count"] = len(problems)
    return receipt, problems


def _problem(code: str, producer: str, message: str, *, path: str | None = None,
             action: str = "halt") -> dict:
    return {"code": code, "producer": producer, "path": path, "message": message,
            "suggested_action": action}


# ----------------------------------------------------------------------------- convocation

def default_premortem(project: str, run_dir: Path, limit: int = 8) -> list[str]:
    """Le pré-mortem d'une convocation (Lot 5, L1) : journal studio du projet (+ leçons globales)
    puis journal LOCAL du run (les échecs des convocations précédentes de CE run). Best-effort,
    jamais bloquant — même discipline que ForgeDriver._premortem."""
    lines: list[str] = []
    try:
        lines += studio_link.premortem(project, domain="html")
    except Exception:  # noqa: BLE001
        pass
    local = Path(run_dir) / "error_journal.jsonl"
    if local.exists():
        try:
            lines += studio_link.premortem(project, journal_path=local)
        except Exception:  # noqa: BLE001
            pass
    return list(dict.fromkeys(lines))[-limit:]


def _append_spawn_link(run_dir: Path, run_id: str, etape: str, attempt: int, status: str,
                       upstream: dict, artifact: Path | None) -> bool:
    """Le joint spawn_links.jsonl — MÊME schéma et MÊMES clés que ForgeDriver._append_spawn_link
    (Lot 5, L10). Capteur : ne lève jamais, rend False si la ligne n'a pas pu être écrite."""
    try:
        ligne = {
            "schema": SPAWN_LINK_SCHEMA, "run_id": run_id, "etape": etape, "attempt": attempt,
            "ts": time.time(), "status": status,
            "artifact_path": str(artifact) if artifact is not None else None,
            "artifact_sha256": bp.file_sha256(artifact) if artifact is not None else None,
            "verdict_ref": None,   # une convocation n'a pas de verdict : la QA du Director le rendra
            "attestation": "self", "attestation_note": SPAWN_LINK_ATTESTATION_NOTE,
            "claim_verdict": "NO_CLAIM_ALLOWED",
        }
        for cle in _SPAWN_LINK_UPSTREAM_KEYS:
            ligne[cle] = upstream.get(cle)
        path = Path(run_dir) / "context" / "spawn_links.jsonl"
        path.parent.mkdir(parents=True, exist_ok=True)
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(ligne, ensure_ascii=False, sort_keys=True) + "\n")
        return True
    except Exception:  # noqa: BLE001 — capteur, jamais un blocage
        return False


def _default_executor(prompt: str, sp: dict, payload, *, run_dir: Path, timeout_s: float) -> dict:
    return _claude_call_with_transient_retry(
        prompt, payload.model, add_dir=run_dir, tools=tuple(sp["tools"]),
        timeout_s=timeout_s, etape=sp["etape"])


def invoke_capability(name: str, blueprint: dict, run_dir: Path, *, run_id: str, attempt: int = 1,
                      executor=None, audit_path: Path | None = None, task: str | None = None,
                      timeout_s: float | None = None, project: str | None = None,
                      src_root_rel: str = ".", registry: dict | None = None,
                      add_dir: Path | None = None, model_override: str | None = None,
                      premortem: list[str] | None = None, feedback: dict | None = None) -> dict:
    """UNE convocation d'une capacité sur le Blueprint. Ne lève pas pour un refus : rend un résultat
    dont `ok` est faux et `problems` dit pourquoi (producteur nommé). Lève seulement sur un usage
    incorrect du module (capacité inconnue)."""
    run_dir = Path(run_dir)
    t0 = time.monotonic()
    result: dict = {
        "capability": name, "run_id": run_id, "attempt": attempt, "ok": False,
        "etape": None, "model": None, "section_written": None, "section_version": None,
        "artifact": None, "artifact_sha256": None, "validator_receipt": None, "output_file": None,
        "model_executed": None,
        # Lot 5 : mesuré ≠ déclaré (L11), diagnostic d'exécuteur (L17), next_reason (L13)
        "model_used": None, "model_measured": False, "executor_diagnostic": None, "next_reason": "",
        # Lot 5 : lignées de preuve (L7 execution, L9 return, L10 spawn_link)
        "return_reason": None,
        "lineage": {"execution_manifest": False, "return_manifest": False, "spawn_link": False},
        "_run_dir": str(run_dir),   # retiré par _finish
        "_project": project or blueprint.get("project", ""),   # retiré par _finish
        # Lot 5 : pré-mortem (L1) et retour du matérialiseur (L3) réellement injectés
        "premortem_lines": 0, "feedback_applied": False,
        "timeout_s": None,   # Lot 5 (L6) : timeout effectivement appliqué (registre ou intention)
        "problems": [], "requests": [], "questions": [], "blueprint_inputs": [],
        "prompt_file": None, "audit": {"prepared": False, "spawn_allowed": None,
                                       "authorized": False, "executed": False},
        "cost": {"tokens": 0, "duration_s": 0.0, "cost_usd": 0.0}, "duration_s": None,
    }
    sp = spec(name, registry)
    result["etape"] = sp["etape"]
    # Lot 5 (L6, réserve 2) : le timeout vient du registre par capacité ; l'intention explicite gagne
    effective_timeout = float(timeout_s if timeout_s is not None else sp["timeout_policy"]["timeout_s"])
    result["timeout_s"] = effective_timeout
    if sp.get("locked"):
        result["problems"].append(_problem(CAPABILITY_LOCKED, "capability_registry", sp["locked"],
                                           action="ask_pierre"))
        return _finish(result, t0)
    if not sp["invokable_v0"]:
        result["problems"].append(_problem(CAPABILITY_NOT_INVOKABLE_V0, "capability_registry",
                                           sp.get("invokable_reason") or "non invocable en v0"))
        return _finish(result, t0)
    # sections requises : refus AVANT toute dépense (fail-closed)
    for r in sp["reads"]:
        _, content = _read_section(blueprint, r["section"])
        if r.get("required") and content is None:
            result["problems"].append(_problem(BLUEPRINT_SECTION_ABSENT, "capability_registry",
                                               f"section requise {r['section']!r} absente du Blueprint",
                                               path=r["section"], action="convoke_owner"))
    if result["problems"]:
        return _finish(result, t0)

    # 1. le contexte, depuis le Blueprint — AVANT la porte, pour que le manifest le mesure (Lot 5, L8)
    projections = _materialize_reads(blueprint, sp["reads"], run_dir)
    bp_section, inputs = _render_blueprint_inputs(blueprint, sp["reads"])
    result["blueprint_inputs"] = inputs
    result["projections"] = projections
    sources_override = [{"path": f"blueprint:{i['section']}", "role": "blueprint_section", "exists": True,
                         "sha256": i["entry_sha256"], "version": i["version"]} for i in inputs]

    # 2. la porte — un dispatch signé, puis la même vérification que le hook
    payload = prepare_dispatch(
        sp["etape"], run_id, audit_path=audit_path, run_dir=run_dir, profile=None,
        attempt=attempt, reason={"signal": "convocation", "by": "forge.capability", "capability": name},
        model_executed=model_override, sources_override=sources_override,
    )
    result["audit"]["prepared"] = True
    result["model"] = payload.model
    result["model_executed"] = model_override or payload.model
    if model_override:   # escalade (portee : cette etape seule, ESC-1) : le payload porte le modele reel
        payload = dataclass_replace(payload, model=model_override)
    allowed, why = check_spawn(payload.prompt, audit_path=audit_path)
    result["audit"]["spawn_allowed"] = allowed
    if not allowed:
        result["problems"].append(_problem(SPAWN_REFUSED, "hook_guard.check_spawn", why))
        return _finish(result, t0)

    # 3. le prompt
    task_text = task if task is not None else default_task_by_step(
        project or blueprint.get("project", ""), src_root_rel, profile="full").get(sp["etape"], "")
    parts = [payload.prompt, f"## TÂCHE CONCRÈTE ({run_id} / {sp['etape']})\n{task_text}"]
    if bp_section:
        parts.append(bp_section)
    # Lot 5 (L1) : pré-mortem — MÊME titre de section que run_real.claude_executor
    pm = premortem if premortem is not None else default_premortem(project or blueprint.get("project", ""), run_dir)
    premortem_section = None
    if pm:
        premortem_section = "## PRÉ-MORTEM (erreurs des runs passés)\n" + "\n".join(f"- {p}" for p in pm)
        parts.append(premortem_section)
    result["premortem_lines"] = len(pm)
    # Lot 5 (L3) : retour du matérialiseur à la re-convocation — MÊME texte que run_real (rupture 11)
    if feedback:
        parts.append(f"## RETOUR DU MATÉRIALISEUR — tentative {feedback.get('attempt')} "
                     "(ta sortie précédente a été REFUSÉE)\n"
                     f"{feedback.get('reason')}\n"
                     "Corrige la FORME demandée ; le fond de ta sortie précédente reste valable.")
        result["feedback_applied"] = True
    prompt = "\n\n".join(parts)
    result["prompt_file"] = _persist_final_prompt(run_dir, sp["etape"], attempt, prompt)
    # Lot 5 (L7) : le manifest d'exécution — le prompt FINAL, ses outils effectifs, son pré-mortem —
    # écrit AVANT l'appel, comme run_real.claude_executor. Advisory, jamais bloquant.
    tools = tuple(sp["tools"])
    try:
        context_manifest.append_execution_manifest(
            run_id, sp["etape"], run_dir, prompt, model=payload.model, premortem_section=premortem_section,
            tools_effective=tools, tools_disallowed_count=len(_derive_disallowed(tools)))
        result["lineage"]["execution_manifest"] = True
    except Exception:  # noqa: BLE001 — advisory
        pass

    # 3. l'exécuteur — réel ou injecté ; reçus d'audit chemin B (comme ForgeDriver)
    work_dir = Path(add_dir) if add_dir is not None else run_dir
    ex = executor or (lambda p, s, pl: _default_executor(p, s, pl, run_dir=work_dir, timeout_s=effective_timeout))
    started_at = time.time()
    res = ex(prompt, sp, payload) or {}
    mesure = res.get("model_used")
    result["model_used"] = list(mesure) if isinstance(mesure, (list, tuple)) else (mesure or None)
    result["model_measured"] = bool(result["model_used"])
    result["executor_diagnostic"] = {k: res.get(k) for k in (
        "returncode", "process_state", "stderr_tail", "timeout", "transient_retries", "session_id", "tools_used")}
    # Lot 5 (L10) : l'amont du joint spawn_link — ce que SEUL l'exécuteur connaît (run_real, P4)
    result["_spawn_link_upstream"] = _build_spawn_link_upstream(
        run_dir, sp["etape"], prompt, result["prompt_file"],
        model_declared=result["model"], model_requested=payload.model, res=res)
    common = dict(capability_role=sp["capability_role"], model=payload.model, provider=payload.provider,
                  allowed_tools=tuple(payload.allowed_tools), tools_effective_signed=tuple(sp["tools"]),
                  audit_path=audit_path)
    result["audit"]["authorized"] = append_spawn_event(EVENT_AUTHORIZED, sp["etape"], run_id, attempt, **common)
    result["audit"]["executed"] = append_spawn_event(EVENT_EXECUTED, sp["etape"], run_id, attempt, **common)
    result["cost"] = {"tokens": int(res.get("tokens") or 0), "duration_s": float(res.get("duration_s") or 0.0),
                      "cost_usd": float(res.get("cost_usd") or 0.0)}
    if not res.get("ok"):
        reason = str(res.get("reason") or "échec sans raison")
        post = run_dir / sp["post_artifact"] if sp.get("post_artifact") else None
        salvageable = (post is not None and post.exists() and post.stat().st_mtime >= started_at
                       and "timeout" in reason.lower())
        if not salvageable:
            result["problems"].append(_problem(EXECUTOR_FAILED, "executor", reason, action="reconvoke"))
            return _finish(result, t0)
        # FIR-02 transposé (run_real._salvage_on_timeout) : un exécuteur tué par le timeout NE JETTE PAS
        # aveuglément ce qu'il a écrit sur disque. L'artefact déclaré a été modifié PENDANT la
        # convocation : il est repris et marqué « à RE-JUGER » (problème K7, producteur exécuteur),
        # jamais compté comme un succès — ce sont les oracles qui jugeront.
        result["problems"].append(_problem(EXECUTOR_TIMEOUT_SALVAGED, "executor",
                                           f"{reason} — {sp['post_artifact']} modifié pendant la convocation, "
                                           "repris pour re-jugement par les oracles", path=sp["writes"], action="qa"))
        result["salvaged"] = True
        res = dict(res, output="")
    output = str(res.get("output") or "")
    result["next_reason"] = ForgeDriver._parse_next_reason(output)   # transport, jamais décision
    if res.get("ok"):
        # Lot 5 (L9) : lignée RETURN — extraction déterministe, manifest jumeau, jamais bloquant
        reason = _extract_return_reason(output)
        result["return_reason"] = reason
        try:
            context_manifest.append_return_manifest(run_id, sp["etape"], run_dir, reason)
            result["lineage"]["return_manifest"] = True
        except Exception:  # noqa: BLE001
            pass
    art_dir = run_dir / "artifacts"
    art_dir.mkdir(parents=True, exist_ok=True)
    output_file = art_dir / f"{sp['etape']}.txt"          # meme forme que le driver (artifacts/<etape>.txt)
    output_file.write_text(output, encoding="utf-8")
    result["output_file"] = str(output_file)
    requested, esc_reason = parse_agent_escalation(output)
    if requested:  # demande de l'AGENT : jamais un code K7 (producteur LLM)
        result["requests"].append({"kind": "escalation", "reason": esc_reason, "producer": "agent"})

    # 4bis. capacite SANS artefact JSON materialise par l'executeur (builder) : l'agent a ecrit
    # lui-meme le jeu et tenu a jour le fichier declare `post_artifact` dans le run_dir
    if sp.get("post_artifact"):
        post = run_dir / sp["post_artifact"]
        if not post.exists():
            result["problems"].append(_problem(ARTIFACT_NOT_MATERIALIZABLE, "capability_registry",
                                               f"{sp['post_artifact']} absent du run_dir apres execution",
                                               path=sp["writes"], action="reconvoke"))
            return _finish(result, t0)
        try:
            data = json.loads(post.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            result["problems"].append(_problem(ARTIFACT_INVALID, "capability_registry",
                                               f"{sp['post_artifact']} illisible : {exc}", path=sp["writes"],
                                               action="reconvoke"))
            return _finish(result, t0)
        result["artifact"] = str(post)
        result["artifact_sha256"] = bp.file_sha256(post)
        try:
            _write_owned_section(blueprint, sp, data, post, run_id)
        except bp.BlueprintError as exc:
            result["problems"].append(_problem(SECTION_WRITE_REFUSED, "blueprint.write_section", str(exc),
                                               path=sp["writes"]))
            return _finish(result, t0)
        result["section_written"] = sp["writes"]
        result["section_version"] = blueprint["sections"][sp["writes"].split(".")[0]]["version"]
        result["ok"] = True
        return _finish(result, t0)

    # 4. matérialisation + validateur de schéma de PRODUCTION
    failure = _materialize_artifact(sp["etape"], output, run_dir)
    if failure is not None:
        reason = str(failure.get("reason", ""))
        code = ARTIFACT_INVALID if "invalide" in reason else ARTIFACT_NOT_MATERIALIZABLE
        result["problems"].append(_problem(code, f"run_real.{sp['artifact_validator']}", reason,
                                           path=sp["writes"], action="reconvoke"))
        return _finish(result, t0)
    artifact_path = run_dir / sp["artifact"]
    data = json.loads(artifact_path.read_text(encoding="utf-8"))
    result["artifact"] = str(artifact_path)
    result["artifact_sha256"] = bp.file_sha256(artifact_path)

    # 5. oracle déterministe déclaré (advisory, codes K7)
    receipt, problems = _run_validator(sp, artifact_path, run_dir)
    result["validator_receipt"] = receipt
    result["problems"].extend(problems)

    # 6. écriture de LA section possédée — le seul effet sur le Blueprint
    try:
        _write_owned_section(blueprint, sp, data, artifact_path, run_id)
    except bp.BlueprintError as exc:
        result["problems"].append(_problem(SECTION_WRITE_REFUSED, "blueprint.write_section", str(exc),
                                           path=sp["writes"]))
        return _finish(result, t0)
    section = sp["writes"].split(".")[0]
    result["section_written"] = sp["writes"]
    result["section_version"] = blueprint["sections"][section]["version"]
    result["ok"] = True
    return _finish(result, t0)


def _write_owned_section(blueprint: dict, sp: dict, data, artifact_path: Path, run_id: str) -> None:
    section, _, entry = sp["writes"].partition(".")
    try:
        rel = str(artifact_path.resolve().relative_to(REPO_ROOT)).replace("\\", "/")
    except ValueError:
        rel = str(artifact_path)
    source = {"path": rel, "sha256": bp.file_sha256(artifact_path), "status": "FILE", "run_id": run_id}
    if entry:
        current = blueprint["sections"][section].get("content")
        composite = dict(current) if isinstance(current, dict) else {}
        composite[entry] = {"source": source, "content": data}
        bp.write_section(blueprint, section, composite, writer=sp["capability_role"],
                         source={"path": None, "sha256": None, "status": "COMPOSITE", "run_id": run_id})
    else:
        bp.write_section(blueprint, section, data, writer=sp["capability_role"], source=source)


def _finish(result: dict, t0: float) -> dict:
    result["duration_s"] = round(time.monotonic() - t0, 3)
    upstream = result.pop("_spawn_link_upstream", None)
    if upstream is not None:   # un exécuteur a tourné : le joint est écrit, succès comme échec (L10)
        art = Path(result["artifact"]) if result.get("artifact") else None
        result["lineage"]["spawn_link"] = _append_spawn_link(
            Path(result["_run_dir"]), result["run_id"], result["etape"], result["attempt"],
            "OK" if result["ok"] else "HALTED", upstream, art)
    # Lot 5 (L14) : un échec de convocation (exécuteur, matérialisation, validateur, section) est
    # journalisé dans le run — le pré-mortem de la convocation suivante le relit. Les refus du
    # registre (verrou, non invocable, section absente) ne sont pas des erreurs d'exécution.
    if not result["ok"] and result.get("_run_dir"):
        first = next((p for p in result["problems"] if p.get("producer") != "capability_registry"), None)
        if first is not None:
            try:
                studio_link.record_error(result["run_id"], result["etape"] or "?",
                                         f"{first['code']}: {first['message']}", result.get("_project") or "",
                                         journal_path=Path(result["_run_dir"]) / "error_journal.jsonl")
            except Exception:  # noqa: BLE001 — capteur
                pass
    result.pop("_project", None)
    result.pop("_run_dir", None)
    return result


# ----------------------------------------------------------------------------- CLI

def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Capacités convocables sur le GAME_BLUEPRINT (v0)")
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("spec"); s.add_argument("name")
    i = sub.add_parser("invoke")
    i.add_argument("name"); i.add_argument("--blueprint", required=True); i.add_argument("--run-id", required=True)
    i.add_argument("--attempt", type=int, default=1); i.add_argument("--out", default=None)
    i.add_argument("--timeout", type=float, default=None,
                   help="Lot 5 : absent = timeout_policy du registre ; présent = intention de l'opérateur")
    a = p.parse_args(argv)
    if a.cmd == "spec":
        print(json.dumps(spec(a.name), ensure_ascii=False, indent=1, default=str))
        return 0
    b = bp.load(REPO_ROOT / a.blueprint)
    run_dir = REPO_ROOT / "EVIDENCE" / "runs" / a.run_id
    res = invoke_capability(a.name, b, run_dir, run_id=a.run_id, attempt=a.attempt, timeout_s=a.timeout)
    out = REPO_ROOT / (a.out or a.blueprint)
    bp.save(b, out)
    (run_dir / f"capability_result_{a.name}_a{a.attempt}.json").write_text(
        json.dumps(res, ensure_ascii=False, indent=1, default=str), encoding="utf-8")
    print(json.dumps({k: res[k] for k in ("capability", "ok", "section_written", "section_version",
                                          "model", "cost", "audit")}, ensure_ascii=False, indent=1))
    print(json.dumps({"problems": res["problems"], "requests": res["requests"],
                      "validator_receipt": res["validator_receipt"], "blueprint_saved": str(out)},
                     ensure_ascii=False, indent=1, default=str))
    return 0 if res["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
