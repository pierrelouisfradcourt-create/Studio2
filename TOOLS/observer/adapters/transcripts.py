"""Adaptateur `transcripts` — active reelle de l'agent, lue dans les transcripts
Claude Code du projet (`ctx.transcripts_root`).

Ce module reconstruit, a partir des fichiers `.jsonl` de transcripts (sessions de
premier niveau, sous-agents, agents de workflow), les evenements MECHANICAL de
l'activite reelle : sessions, messages, appels d'outils, lectures/ecritures de
fichiers, commandes shell, resultats d'outils, usage LLM.

Correlation a un run Forge — le point le plus important de ce fichier :

Les agents d'etape Forge recoivent en tete de prompt un marqueur
``FORGE_DISPATCH:<etape>:<run_id>[:<attempt>]`` (meme forme que le garde de
spawn, `scripts/forge/hook_guard.py` ~l.29 — reproduite ici sans dependre du
module `forge`, cf. contrainte d'independance d'Observer). Le `run_id` n'existe
QUE sur la ligne qui porte le marqueur : rattacher les AUTRES lignes du meme
fichier a ce run est une inference au niveau du fichier, jamais une lecture
directe. Tous les evenements extraits d'un fichier candidat portent donc
`link = LINK_FILE_SCOPE`, jamais `LINK_DIRECT`.

Strategie a deux passes (imposee par la volumetrie — certains fichiers
depassent 6 Mo, le dossier entier depasse 400 Mo) :

1. Detection rapide : au plus les 50 premieres lignes de CHAQUE fichier, juste
   pour decider si le fichier est candidat (contient un marqueur dont le
   `run_id` commence par ``<ctx.project>-``). Un fichier non candidat n'est
   jamais relu.
2. Pour un fichier candidat seulement : une premiere lecture complete recense
   TOUS les marqueurs (et les metadonnees de fichier), une seconde lecture
   complete construit les evenements avec le marqueur resolu.

Si plusieurs marqueurs distincts (etape, run_id, attempt) coexistent dans un
meme fichier candidat, aucun choix silencieux n'est fait : un `agent.session`
est emis PAR marqueur trouve, la liste complete vit dans `markers`,
`ambiguous_scope: true` est pose, et les evenements d'outils du fichier sont
rattaches au marqueur le plus frequent — avec une `note` qui le dit.
"""

from __future__ import annotations

import json
import logging
import re
from collections import Counter
from pathlib import Path
from typing import Any, Iterator, Optional

from observer.events import (
    PROOF_MECHANICAL,
    LINK_FILE_SCOPE,
    Actor,
    Event,
    Source,
    iso,
    normalize_ts,
)
from observer.sources import BlindnessViolation, ObserverContext

LOG = logging.getLogger("observer.adapters.transcripts")

NAME = "transcripts"

# Meme forme que `scripts/forge/hook_guard.py` ~l.29 (MARKER) : etape et
# run_id en [\w.\-]+, attempt optionnel en suffixe numerique. Reproduite ici
# (pas importee) pour qu'Observer ne depende jamais du module `forge`.
_MARKER_RE = re.compile(r"FORGE_DISPATCH:([\w.\-]+):([\w.\-]+)(?::(\d+))?")

_HEAD_SCAN_LINES = 50

# Outils qui recoivent leur propre evenement dedie (file.read/write/edit,
# shell.exec). Un tool_use sur l'un de ces noms n'a PAS d'`input_excerpt` dans
# son `tool.call` : le detail vit dans l'evenement specialise.
_READ_TOOLS = ("Read", "NotebookRead")
_WRITE_TOOLS = ("Write",)
_EDIT_TOOLS = ("Edit", "NotebookEdit")
_SHELL_TOOLS = ("Bash", "PowerShell")
_SPECIALIZED_TOOLS = frozenset(_READ_TOOLS + _WRITE_TOOLS + _EDIT_TOOLS + _SHELL_TOOLS)

_EXCERPT_CHARS = 300
_COMMAND_CHARS = 1000

MarkerKey = tuple[str, str, Optional[int]]


def collect(ctx: ObserverContext) -> list[Event]:
    """Balaye `ctx.transcripts_root` et retourne les evenements de transcripts
    correles au projet de `ctx`.

    Une tentative de run n'a pas forcement les memes fichiers qu'une autre :
    un fichier illisible ou une erreur inattendue sur UN fichier candidat est
    journalisee et sautee, elle n'interrompt jamais le balayage global.
    """
    events: list[Event] = []
    project_prefix = f"{ctx.project}-"

    for path in ctx.iter_files(ctx.transcripts_root, "*.jsonl"):
        try:
            if not _is_candidate(ctx, path, project_prefix):
                continue
        except BlindnessViolation:
            raise
        except Exception:
            LOG.warning("detection de marqueur echouee sur %s", path, exc_info=True)
            continue

        try:
            events.extend(_process_candidate(ctx, path, project_prefix))
        except BlindnessViolation:
            raise
        except Exception:
            LOG.warning("traitement du candidat echoue sur %s", path, exc_info=True)
            continue

    return events


# --------------------------------------------------------------------------- #
# Passe 1 : detection rapide (au plus 50 lignes, arret tot)
# --------------------------------------------------------------------------- #


def _dispatch_text(obj: dict[str, Any]) -> str:
    """Texte d'une ligne susceptible de porter une INSTRUCTION de dispatch.

    Distinction decisive : recevoir un marqueur comme consigne n'est pas la meme
    chose que le mentionner. Une session d'exploration dont une sortie d'outil
    affiche un marqueur (un `grep` sur les traces, par exemple) n'est pas un
    agent d'etape Forge — et lui attribuer les fichiers qu'elle a ecrits
    fabriquerait un run qui n'a jamais eu lieu.

    On ne regarde donc que les positions ou un ordre est DONNE a l'agent :
      * `queue-operation.content` — prompt injecte en tete de session ;
      * un message `user` dont le contenu est du texte (pas un `tool_result`).

    Tout le reste — sorties d'outils, texte du modele, pieces jointes — est
    ignore pour la detection, quitte a manquer un cas plutot qu'a en inventer un.
    """
    kind = obj.get("type")
    if kind == "queue-operation":
        content = obj.get("content")
        return content if isinstance(content, str) else ""
    if kind == "user":
        message = obj.get("message")
        if not isinstance(message, dict):
            return ""
        content = message.get("content")
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            return " ".join(
                block.get("text", "")
                for block in content
                if isinstance(block, dict) and block.get("type") == "text"
            )
    return ""


def _is_candidate(ctx: ObserverContext, path: Path, project_prefix: str) -> bool:
    gen = ctx.read_jsonl(path)
    try:
        for i, (_lineno, obj) in enumerate(gen):
            if i >= _HEAD_SCAN_LINES:
                break
            for _etape, run_id, _attempt in _iter_markers(_dispatch_text(obj)):
                if run_id.startswith(project_prefix):
                    return True
    finally:
        gen.close()
    return False


# --------------------------------------------------------------------------- #
# Passe 2a : metadonnees + recensement complet des marqueurs
# --------------------------------------------------------------------------- #


class _FileMeta:
    __slots__ = (
        "line_count",
        "models",
        "prompt_ids",
        "mcp_tool_calls",
        "has_custom_title",
        "is_sidechain",
        "entrypoint",
        "cwd",
        "git_branch",
        "cli_version",
        "session_id",
        "first_ts_epoch",
        "first_ts_raw",
        "first_ts_format",
        "last_ts_epoch",
        "marker_counts",
        "marker_order",
        "mention_marker_count",
    )

    def __init__(self) -> None:
        self.line_count = 0
        self.models: set[str] = set()
        self.prompt_ids: set[str] = set()
        self.mcp_tool_calls = 0
        self.has_custom_title = False
        self.is_sidechain: Optional[bool] = None
        self.entrypoint: Optional[str] = None
        self.cwd: Optional[str] = None
        self.git_branch: Optional[str] = None
        self.cli_version: Optional[str] = None
        self.session_id: Optional[str] = None
        self.first_ts_epoch: Optional[float] = None
        self.first_ts_raw: Optional[str] = None
        self.first_ts_format: str = "absent"
        self.last_ts_epoch: Optional[float] = None
        self.marker_counts: Counter[MarkerKey] = Counter()
        self.marker_order: list[MarkerKey] = []
        self.mention_marker_count = 0


def _gather_metadata(ctx: ObserverContext, path: Path, project_prefix: str) -> _FileMeta:
    meta = _FileMeta()
    for lineno, obj in ctx.read_jsonl(path):
        meta.line_count = lineno

        if meta.is_sidechain is None and isinstance(obj.get("isSidechain"), bool):
            meta.is_sidechain = obj["isSidechain"]
        if meta.entrypoint is None and isinstance(obj.get("entrypoint"), str):
            meta.entrypoint = obj["entrypoint"]
        if meta.cwd is None and isinstance(obj.get("cwd"), str):
            meta.cwd = obj["cwd"]
        if meta.git_branch is None and isinstance(obj.get("gitBranch"), str):
            meta.git_branch = obj["gitBranch"]
        if meta.cli_version is None and isinstance(obj.get("version"), str):
            meta.cli_version = obj["version"]
        if meta.session_id is None and isinstance(obj.get("sessionId"), str):
            meta.session_id = obj["sessionId"]
        if obj.get("customTitle"):
            meta.has_custom_title = True

        prompt_id = obj.get("promptId")
        if isinstance(prompt_id, str) and prompt_id:
            meta.prompt_ids.add(prompt_id)

        epoch, raw, fmt = normalize_ts(obj.get("timestamp"))
        if epoch is not None:
            if meta.first_ts_epoch is None or epoch < meta.first_ts_epoch:
                meta.first_ts_epoch, meta.first_ts_raw, meta.first_ts_format = epoch, raw, fmt
            if meta.last_ts_epoch is None or epoch > meta.last_ts_epoch:
                meta.last_ts_epoch = epoch

        message = obj.get("message")
        if isinstance(message, dict):
            model = message.get("model")
            if isinstance(model, str) and model:
                meta.models.add(model)
            content = message.get("content")
            if isinstance(content, list):
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "tool_use":
                        name = block.get("name")
                        if isinstance(name, str) and name.startswith("mcp__"):
                            meta.mcp_tool_calls += 1

        for etape, run_id, attempt in _iter_markers(_dispatch_text(obj)):
            if not run_id.startswith(project_prefix):
                continue
            key = (etape, run_id, attempt)
            meta.marker_counts[key] += 1
            if key not in meta.marker_order:
                meta.marker_order.append(key)

        # Marqueurs vus ailleurs que dans une position d'instruction (sortie
        # d'outil, texte du modele). Comptes pour la transparence, jamais
        # utilises pour rattacher quoi que ce soit a un run.
        instruction_text = _dispatch_text(obj)
        for _etape, run_id, _attempt in _iter_markers(_dump(obj)):
            if run_id.startswith(project_prefix) and run_id not in instruction_text:
                meta.mention_marker_count += 1

    return meta


# --------------------------------------------------------------------------- #
# Orchestration par fichier candidat
# --------------------------------------------------------------------------- #


def _process_candidate(ctx: ObserverContext, path: Path, project_prefix: str) -> list[Event]:
    meta = _gather_metadata(ctx, path, project_prefix)
    if not meta.marker_order:
        # Ne devrait pas arriver (le fichier a ete juge candidat en passe 1)
        # mais une source n'a pas a etre fiable deux fois de suite.
        LOG.warning("candidat sans marqueur au relecture complete: %s", path)
        return []

    ambiguous = len(meta.marker_order) > 1
    chosen_key, chosen_count = meta.marker_counts.most_common(1)[0]

    # Second filet, apres la position de dispatch : une session interactive se
    # reconnait mecaniquement a deux signatures (plusieurs promptId distincts,
    # ou un titre personnalise). Un agent d'etape n'a ni l'un ni l'autre : il
    # recoit un prompt, travaille, s'arrete. Une session qui echoue a ce test
    # est enregistree comme fait — elle a bien parle de ce run — mais son
    # activite n'est PAS attribuee au run : on ne fabrique pas un run avec le
    # travail de quelqu'un d'autre.
    is_step_agent = len(meta.prompt_ids) <= 1 and not meta.has_custom_title
    session_role = "forge_step_agent" if is_step_agent else "orchestrator_or_interactive"

    rel_path = ctx.rel(path)
    bytes_size = ctx.stat_size(path)
    agent_meta = _read_agent_meta(ctx, path)

    shared_payload: dict[str, Any] = {
        "session_file": str(path),
        "session_id": meta.session_id,
        "markers": [
            {"etape": e, "run_id": r, "attempt": a} for (e, r, a) in meta.marker_order
        ],
        "is_sidechain": meta.is_sidechain,
        "entrypoint": meta.entrypoint,
        "cwd": meta.cwd,
        "git_branch": meta.git_branch,
        "cli_version": meta.cli_version,
        "prompt_ids": len(meta.prompt_ids),
        "has_custom_title": meta.has_custom_title,
        "line_count": meta.line_count,
        "bytes": bytes_size,
        "first_ts": iso(meta.first_ts_epoch),
        "last_ts": iso(meta.last_ts_epoch),
        "models": sorted(meta.models),
        "mcp_tool_calls": meta.mcp_tool_calls,
        "session_role": session_role,
        "activity_attributed": is_step_agent,
        "marker_mentions_outside_instruction": meta.mention_marker_count,
    }
    if agent_meta is not None:
        shared_payload["agent_meta"] = agent_meta
    if ambiguous:
        shared_payload["ambiguous_scope"] = True

    session_source = Source(path=rel_path, fmt="jsonl", line=1)

    events: list[Event] = []
    for key in meta.marker_order:
        etape, run_id, attempt = key
        note = None
        if ambiguous:
            if key == chosen_key:
                note = (
                    f"marqueur le plus frequent ({chosen_count} occurrences) "
                    f"— evenements d'outils du fichier rattaches ici"
                )
            else:
                note = (
                    "marqueur present mais non retenu pour le rattachement des "
                    f"evenements d'outils (voir {chosen_key[0]}/{chosen_key[1]})"
                )
        events.append(
            Event(
                kind="agent.session",
                source=session_source,
                proof=PROOF_MECHANICAL,
                link=LINK_FILE_SCOPE,
                ts=meta.first_ts_epoch,
                ts_raw=meta.first_ts_raw,
                ts_format=meta.first_ts_format,
                run_id=run_id,
                project=ctx.project,
                etape=etape,
                attempt=attempt,
                attempt_field="marker" if attempt is not None else None,
                actor=Actor(kind="llm_agent", session_id=meta.session_id),
                payload=dict(shared_payload),
                note=note,
            )
        )

    scope_note = None
    if ambiguous:
        scope_note = (
            f"fichier multi-marqueurs ({len(meta.marker_order)} distincts) — "
            f"rattache au plus frequent {chosen_key[0]}/{chosen_key[1]}"
        )

    if not is_step_agent:
        LOG.info(
            "session %s non attribuee au run (%d promptId, titre=%s)",
            rel_path,
            len(meta.prompt_ids),
            meta.has_custom_title,
        )
        return events

    events.extend(
        _build_activity_events(
            ctx=ctx,
            path=path,
            rel_path=rel_path,
            run_id=chosen_key[1],
            etape=chosen_key[0],
            attempt=chosen_key[2],
            note=scope_note,
        )
    )
    return events


def _read_agent_meta(ctx: ObserverContext, path: Path) -> Optional[Any]:
    meta_path = path.with_name(path.stem + ".meta.json")
    return ctx.read_json(meta_path)


# --------------------------------------------------------------------------- #
# Passe 2b : evenements d'activite (tool.call / file.* / shell.exec / ...)
# --------------------------------------------------------------------------- #


def _build_activity_events(
    ctx: ObserverContext,
    path: Path,
    rel_path: str,
    run_id: str,
    etape: str,
    attempt: Optional[int],
    note: Optional[str],
) -> list[Event]:
    events: list[Event] = []
    attempt_field = "marker" if attempt is not None else None

    def emit(kind: str, lineno: int, ts_tuple: tuple, actor: Actor, payload: dict[str, Any]) -> None:
        ts_epoch, ts_raw, ts_fmt = ts_tuple
        events.append(
            Event(
                kind=kind,
                source=Source(path=rel_path, fmt="jsonl", line=lineno),
                proof=PROOF_MECHANICAL,
                link=LINK_FILE_SCOPE,
                ts=ts_epoch,
                ts_raw=ts_raw,
                ts_format=ts_fmt,
                run_id=run_id,
                project=ctx.project,
                etape=etape,
                attempt=attempt,
                attempt_field=attempt_field,
                actor=actor,
                payload=payload,
                note=note,
            )
        )

    for lineno, obj in ctx.read_jsonl(path):
        ts_tuple = normalize_ts(obj.get("timestamp"))
        obj_type = obj.get("type")
        message = obj.get("message")
        if not isinstance(message, dict):
            continue

        session_id = obj.get("sessionId") if isinstance(obj.get("sessionId"), str) else None
        model = message.get("model") if isinstance(message.get("model"), str) else None
        content = message.get("content")

        if obj_type == "assistant":
            actor = Actor(kind="llm_agent", model=model, session_id=session_id)

            content_types: list[str] = []
            text_chars = 0
            blocks: list[dict[str, Any]] = []
            if isinstance(content, list):
                blocks = [b for b in content if isinstance(b, dict)]
                for block in blocks:
                    btype = block.get("type")
                    if isinstance(btype, str):
                        content_types.append(btype)
                    if btype == "text" and isinstance(block.get("text"), str):
                        text_chars += len(block["text"])
            elif isinstance(content, str):
                content_types = ["text"]
                text_chars = len(content)

            emit(
                "agent.message",
                lineno,
                ts_tuple,
                actor,
                {
                    "role": message.get("role"),
                    "model": model,
                    "content_types": content_types,
                    "text_chars": text_chars,
                },
            )

            usage = message.get("usage")
            if isinstance(usage, dict):
                emit(
                    "llm.usage",
                    lineno,
                    ts_tuple,
                    actor,
                    _drop_none(
                        {
                            "input_tokens": usage.get("input_tokens"),
                            "output_tokens": usage.get("output_tokens"),
                            "cache_creation_input_tokens": usage.get(
                                "cache_creation_input_tokens"
                            ),
                            "cache_read_input_tokens": usage.get("cache_read_input_tokens"),
                            "model": model,
                            "stop_reason": message.get("stop_reason"),
                            "request_id": obj.get("requestId"),
                        }
                    ),
                )

            for block in blocks:
                if block.get("type") != "tool_use":
                    continue
                events.extend(
                    _tool_use_events(
                        ctx=ctx,
                        rel_path=rel_path,
                        lineno=lineno,
                        ts_tuple=ts_tuple,
                        actor=actor,
                        block=block,
                        run_id=run_id,
                        etape=etape,
                        attempt=attempt,
                        attempt_field=attempt_field,
                        note=note,
                    )
                )

        elif obj_type == "user":
            actor = Actor(kind="llm_agent", model=model, session_id=session_id)
            if isinstance(content, list):
                for block in content:
                    if not isinstance(block, dict) or block.get("type") != "tool_result":
                        continue
                    is_error = block.get("is_error")
                    if is_error is None:
                        is_error = obj.get("is_error", False)
                    result_text = _stringify_result(block.get("content"))
                    emit(
                        "tool.result",
                        lineno,
                        ts_tuple,
                        actor,
                        {
                            "tool_use_id": block.get("tool_use_id"),
                            "is_error": bool(is_error),
                            "result_chars": len(result_text),
                            "result_excerpt": result_text[:_EXCERPT_CHARS],
                        },
                    )

    return events


def _tool_use_events(
    ctx: ObserverContext,
    rel_path: str,
    lineno: int,
    ts_tuple: tuple,
    actor: Actor,
    block: dict[str, Any],
    run_id: str,
    etape: str,
    attempt: Optional[int],
    attempt_field: Optional[str],
    note: Optional[str],
) -> list[Event]:
    """Construit tool.call plus, le cas echeant, file.read/write/edit/shell.exec
    pour UN bloc tool_use. `ctx` n'est utilise ici que pour `ctx.project`
    (tout le reste vient deja de la ligne parsee, aucune I/O supplementaire)."""
    tool_name = block.get("name")
    tool_use_id = block.get("tool_use_id") or block.get("id")
    raw_input = block.get("input")
    input_obj = raw_input if isinstance(raw_input, dict) else {}
    ts_epoch, ts_raw, ts_fmt = ts_tuple

    def mk(kind: str, payload: dict[str, Any]) -> Event:
        return Event(
            kind=kind,
            source=Source(path=rel_path, fmt="jsonl", line=lineno),
            proof=PROOF_MECHANICAL,
            link=LINK_FILE_SCOPE,
            ts=ts_epoch,
            ts_raw=ts_raw,
            ts_format=ts_fmt,
            run_id=run_id,
            project=ctx.project,
            etape=etape,
            attempt=attempt,
            attempt_field=attempt_field,
            actor=actor,
            payload=payload,
            note=note,
        )

    events: list[Event] = []

    call_payload: dict[str, Any] = {
        "tool_name": tool_name,
        "tool_use_id": tool_use_id,
        "input_keys": sorted(input_obj.keys()),
    }
    if tool_name not in _SPECIALIZED_TOOLS:
        call_payload["input_excerpt"] = _dump(raw_input if raw_input is not None else {})[
            :_EXCERPT_CHARS
        ]
    events.append(mk("tool.call", call_payload))

    if tool_name in _READ_TOOLS:
        file_path = input_obj.get("file_path")
        if isinstance(file_path, str) and file_path:
            events.append(
                mk("file.read", {"path": file_path, "tool_use_id": tool_use_id})
            )

    elif tool_name in _WRITE_TOOLS:
        file_path = input_obj.get("file_path")
        if isinstance(file_path, str) and file_path:
            payload = {"path": file_path, "tool_use_id": tool_use_id}
            file_content = input_obj.get("content")
            if isinstance(file_content, str):
                payload["bytes_written"] = len(file_content)
            events.append(mk("file.write", payload))

    elif tool_name in _EDIT_TOOLS:
        file_path = input_obj.get("file_path")
        if isinstance(file_path, str) and file_path:
            old_string = input_obj.get("old_string")
            new_string = input_obj.get("new_string")
            payload = {
                "path": file_path,
                "replace_all": bool(input_obj.get("replace_all", False)),
                "tool_use_id": tool_use_id,
            }
            if isinstance(old_string, str):
                payload["old_len"] = len(old_string)
            if isinstance(new_string, str):
                payload["new_len"] = len(new_string)
            events.append(mk("file.edit", payload))

    elif tool_name in _SHELL_TOOLS:
        command = input_obj.get("command")
        if isinstance(command, str) and command:
            payload = {
                "command": command[:_COMMAND_CHARS],
                "tool_use_id": tool_use_id,
            }
            description = input_obj.get("description")
            if isinstance(description, str) and description:
                payload["description"] = description
            events.append(mk("shell.exec", payload))

    return events


# --------------------------------------------------------------------------- #
# Utilitaires
# --------------------------------------------------------------------------- #


def _iter_markers(text: str) -> Iterator[tuple[str, str, Optional[int]]]:
    for match in _MARKER_RE.finditer(text):
        etape, run_id, attempt_raw = match.group(1), match.group(2), match.group(3)
        attempt = int(attempt_raw) if attempt_raw is not None else None
        yield etape, run_id, attempt


def _dump(obj: Any) -> str:
    try:
        return json.dumps(obj, ensure_ascii=False, default=str)
    except (TypeError, ValueError):
        return str(obj)


def _stringify_result(content: Any) -> str:
    if content is None:
        return ""
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts = []
        for block in content:
            if isinstance(block, dict) and isinstance(block.get("text"), str):
                parts.append(block["text"])
        if parts:
            return "\n".join(parts)
        return _dump(content)
    return _dump(content)


def _drop_none(payload: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in payload.items() if v is not None}
