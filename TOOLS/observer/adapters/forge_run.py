"""Adaptateur Observer — reconstruction du run Forge d'un projet (breakout_v2 et
au-dela) depuis `lab/forge_runs/<project>/`.

Perimetre couvert (voir la mission de fabrication pour le detail exact) :

  * `state.json`      (racine + chaque sous-dossier de tentative archivee)
  * `verdict.json`     idem
  * `context/<etape>.manifest.jsonl` / `.reasoning_observability.jsonl` /
    `.tool_observability.jsonl`
  * `reference_guard.jsonl`
  * `evidence/mutation_*.raw.json`, `evidence/oracle_*.log`
  * `playtest/playtest_capture_report.json`
  * `artifacts/<etape>.txt`
  * `tasks_run<N>.json`
  * `charter.yaml` (jamais parse : seulement path/bytes/sha256)
  * `wiremap.json`
  * `salvage_*.json`
  * `run.log`, `run<N>_console.log`

Le run_dir courant contient la tentative EN COURS a sa racine, plus des
tentatives archivees dans des sous-dossiers `_run*_YYYYMMDD` / `_blocked*` /
`_halted*`. Ces dossiers sont decouverts par motif (jamais code en dur) et
traites tous de la meme facon par `_collect_attempt_dir` : les fichiers qui
n'existent que dans un seul dossier (contexte, wiremap, charter, reference
guard, tasks_run*.json) sont simplement absents ailleurs et donc ignores sans
erreur, ce qui rend le traitement uniforme correct par construction.

Aucune ecriture. Aucune lecture hors de `ctx` (garde de cecite). Une source
absente est sautee, jamais une exception levee (sauf `BlindnessViolation`,
jamais rattrapee).
"""

from __future__ import annotations

import hashlib
import json
import logging
import re
from pathlib import Path
from typing import Any, Optional

from observer.events import (
    Actor,
    Event,
    LINK_DIRECT,
    LINK_FILENAME,
    LINK_NONE,
    LINK_PATH,
    PROOF_MECHANICAL,
    PROOF_SELF_DECLARED,
    PROOF_SIGNED,
    PROOF_SIGNED_INVALID,
    PROOF_SIGNED_UNVERIFIABLE,
    Source,
    extract_attempt,
    normalize_ts,
)
from observer.signature import INVALID as _SIG_INVALID
from observer.signature import UNVERIFIABLE as _SIG_UNVERIFIABLE
from observer.signature import VERIFIED as _SIG_VERIFIED
from observer.signature import verify_envelope
from observer.sources import ObserverContext

LOG = logging.getLogger("observer.forge_run")

NAME = "forge_run"

# P4 INV-2 : SIGNED = signature HMAC verifiee, pas seulement presente. Cette
# table traduit le verdict de `observer.signature.verify_envelope` en `proof`
# d'evenement — vocabulaire d'events.py, jamais un vocabulaire parallele.
_PROOF_BY_SIG_STATUS = {
    _SIG_VERIFIED: PROOF_SIGNED,
    _SIG_INVALID: PROOF_SIGNED_INVALID,
    _SIG_UNVERIFIABLE: PROOF_SIGNED_UNVERIFIABLE,
}


def _signed_proof(envelope: dict, key_file: Path | None = None) -> tuple[str, str]:
    """Verifie l'enveloppe et retourne (proof, sig_status). ABSENT (pas de champ
    hmac) degrade en PROOF_SIGNED_UNVERIFIABLE : la source PRETEND etre une
    trace signee (elle passait deja par ce chemin de collecte) mais n'a rien a
    verifier — jamais assimile silencieusement a un SIGNED verifie."""
    status = verify_envelope(envelope, key_file)
    return _PROOF_BY_SIG_STATUS.get(status, PROOF_SIGNED_UNVERIFIABLE), status


def _drift_invalid_signature(
    *, kind_verifie: str, rel: str, run_id: Optional[str], project: Optional[str], detail: str
) -> Event:
    """Reçu à signature INVALIDE : DRIFT sévérité haute, jamais une exception levée
    (l'agrégat reste lisible ; c'est Pierre/HumanGate qui doit voir le signal)."""
    return Event(
        kind="drift.detected",
        source=Source(path=rel, fmt="json"),
        proof=PROOF_MECHANICAL,
        link=LINK_NONE,
        run_id=run_id,
        project=project,
        payload={
            "drift_kind": "signature_invalid",
            "severity": "high",
            "subject": kind_verifie,
            "detail": detail,
        },
        note="signature HMAC presente mais NE correspond PAS au corps de l'enregistrement "
             "(cle lisible) — falsification ou corruption probable",
    )

# --------------------------------------------------------------------------- #
# Motifs
# --------------------------------------------------------------------------- #

# Dossiers de tentative archivee : jamais code en dur, decouverts par prefixe.
_ATTEMPT_DIR_RE = re.compile(r"^_(run|blocked|halted)", re.IGNORECASE)

_MUTATION_FILENAME_RE = re.compile(r"^mutation_(.+)\.raw\.json$")
_TASKS_FILENAME_RE = re.compile(r"^tasks_run(\d+)\.json$")

_RESULT_LINE_RE = re.compile(
    r"===\s*RESULT:\s*(\d+)\s*passed,\s*(\d+)\s*failed\s*\(fichiers:\s*(\d+)\)\s*==="
)

# Format `node --test` (P2 routage, 2026-08-08) : jusqu'ici `evidence/oracle_*.log`
# n'etait parse que pour le format Godot ci-dessus (`=== RESULT: ... ===`) ; un run
# oracle `node --test` (profil patch, mesure sur driver_smoke_v3/v4) produisait donc
# ZERO evenement bien que le fichier soit lu. Diagnostic verifie sur driver_smoke_v4
# avant d'ecrire ces regex : le fichier commence par `$ node --test <fichier>` puis
# `(cwd=<chemin absolu>)`, et le resume `node:test` porte `tests N` / `pass N` /
# `fail N` sur des lignes separees (prefixees d'un symbole qui arrive corrompu dans
# le fichier source lui-meme — double encodage UTF-8 en amont, non corrige ici :
# les chiffres restent ASCII et le motif matche independamment du prefixe).
_NODE_TEST_CMD_RE = re.compile(r"^\$\s*(?P<cmd>.+)$", re.MULTILINE)
_NODE_TEST_CWD_RE = re.compile(r"\(cwd=(?P<cwd>[^)]+)\)")
_NODE_TEST_TESTS_RE = re.compile(r"\btests\s+(\d+)\b")
_NODE_TEST_PASS_RE = re.compile(r"\bpass\s+(\d+)\b")
_NODE_TEST_FAIL_RE = re.compile(r"\bfail\s+(\d+)\b")

# Ligne de run.log : "2026-07-31 11:11:49,660 INFO forge.driver: message"
_DRIVER_LOG_TS_RE = re.compile(
    r"^(?P<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d{3})\s+"
    r"(?P<level>[A-Z]+)\s+(?P<logger>[\w.]+):\s*(?P<message>.*)$"
)
# Ligne de run<N>_console.log : sans horodatage — "INFO forge.driver: message"
_DRIVER_LOG_NOTS_RE = re.compile(
    r"^(?P<level>[A-Z]+)\s+(?P<logger>[\w.]+):\s*(?P<message>.*)$"
)

_RUN_ID_IN_MSG_RE = re.compile(r"run=([^\s:]+)")
_ETAPE_IN_MSG_RE = re.compile(r"[eé]tape=([^\s:]+)")
_FAILURE_WORD_RE = re.compile(r"HALT|[ée]chec|timeout", re.IGNORECASE)

_CONTEXT_MANIFEST_FIELDS = (
    "activation",
    "kind",
    "contract_sha256",
    "final_prompt_sha256",
    "final_prompt_chars",
    "payload_prompt_sha256",
    "premortem_sha256",
    "prompt_budget",
    "sources",
    "tools_effective",
    "tools_disallowed_count",
    "git_head",
    "hmac",
    "reason",
    "ambient_context_note",
)
_REASONING_FIELDS = ("capability_role", "declared", "declared_status", "git_head", "hmac")
_TOOLS_FIELDS = ("declared", "loaded", "git_head", "hmac")
_GUARD_FIELDS = (
    "schema",
    "phase",
    "status",
    "baseline_combined_sha256",
    "current_combined_sha256",
    "current_file_count",
    "diffs",
    "derogation_present",
    "unreadable",
    "checked_at",
)
_MUTATION_EXECUTION_FIELDS = (
    "total",
    "killed",
    "survived",
    "survivors",
    "mutants_generes",
    "mutants_executes",
    "budget_exceeded",
    "baseline_ok",
    "fichiers_sans_mutant",
    "files",
    "command_declaree",
    "command_executee",
    "cwd_execute",
)
_CAPTURE_FIELDS = (
    "schema",
    "boot_png",
    "midgame_png",
    "boot_bytes",
    "midgame_bytes",
    "captures_different",
    "godot_exit_forced",
    "note",
)
_VERDICT_FIELDS = (
    "decision",
    "software_verdict",
    "evidence_verdict",
    "claim_verdict",
    "hmac",
    "nonce",
    "git_head",
    "provenance_ok",
    "redteam_ran",
    "redteam_advisory",
    "redteam_reviewer",
    "humangate_flags",
)
_WIREMAP_LINE_FIELDS = (
    "id",
    "source",
    "source_role",
    "state",
    "statut",
    "category",
    "fichiers",
    "owner",
    "decider",
    "preuve",
    "expected_proof",
    "observable_by_player",
    "reused_from",
)
_SALVAGE_FIELDS = (
    "etape",
    "timeout_reason",
    "salvageable",
    "harness_present",
    "produced_mjs",
    "src_root",
    "note",
)


def collect(ctx: ObserverContext) -> list[Event]:
    """Reconstruit les evenements du run Forge courant (racine + tentatives)."""
    events: list[Event] = []
    base = ctx.run_dir
    if not ctx.exists(base):
        LOG.info("run_dir absent pour project=%s", ctx.project)
        return events

    events.extend(_collect_attempt_dir(ctx, base))

    for child in _direct_children(ctx, base, "_*"):
        if child.is_dir() and _ATTEMPT_DIR_RE.match(child.name):
            events.extend(_collect_attempt_dir(ctx, child))

    return events


# --------------------------------------------------------------------------- #
# Un dossier de tentative (racine ou sous-dossier archive)
# --------------------------------------------------------------------------- #


def _collect_attempt_dir(ctx: ObserverContext, base: Path) -> list[Event]:
    events: list[Event] = []

    dir_run_id, dir_project = _collect_state(ctx, base, events)
    _collect_verdict(ctx, base, dir_run_id, events)
    _collect_context(ctx, base, events)
    _collect_reference_guard(ctx, base, dir_run_id, events)
    _collect_mutation_evidence(ctx, base, dir_run_id, events)
    _collect_mutation_receipt(ctx, base, dir_run_id, events)
    _collect_oracle_log(ctx, base, dir_run_id, events)
    _collect_playtest(ctx, base, dir_run_id, events)
    _collect_artifacts(ctx, base, dir_run_id, events)
    _collect_tasks(ctx, base, dir_run_id, events)
    _collect_charter(ctx, base, dir_run_id, events)
    _collect_wiremap(ctx, base, dir_run_id, events)
    _collect_salvage(ctx, base, dir_run_id, events)
    _collect_driver_logs(ctx, base, dir_run_id, events)
    _collect_generic_presence(ctx, base, dir_run_id, events)

    return events


# --------------------------------------------------------------------------- #
# Marche generique — presence de tout fichier qu'aucun collecteur specifique
# n'a reclame (P2 routage, 2026-08-08)
# --------------------------------------------------------------------------- #


def _collect_generic_presence(
    ctx: ObserverContext, base: Path, dir_run_id: Optional[str], events: list[Event]
) -> None:
    """Emet `run.artifact_present` pour tout fichier du dossier de tentative
    qu'aucun `_collect_*` ci-dessus n'a deja transforme en evenement.

    S'execute EN DERNIER, apres tous les collecteurs specifiques : `covered` est
    calcule sur les evenements deja produits par CE dossier de tentative, jamais
    sur une liste codee en dur de noms de fichiers. Objectif mesure (mission P2) :
    100% des fichiers du run_dir recoivent un evenement, meme les orphelins
    connus (`oracles_override.json`, `rapport_redteam_code.md`, `run.log`) —
    ceux-la restent volontairement REVIEW_REQUIRED au routage, ce module ne fait
    que les rendre VISIBLES, jamais ne les classe.

    Purement additif : un fichier deja source d'un evenement n'en recoit jamais
    un second par ce chemin (pas de double-comptage), et un dossier de tentative
    archive (sous-dossier de `base`, ex. `_run2_...`) est traite separement par
    son propre appel a `_collect_attempt_dir` — seuls les fichiers DIRECTEMENT
    sous `base` sont concernes ici (les sous-dossiers de tentative archivee ne
    sont pas des fichiers de CETTE tentative).
    """
    if not ctx.exists(base):
        return
    covered = {e.source.path for e in events}
    for path in ctx.iter_files(base, "*"):
        if not path.is_file():
            continue
        # Un sous-dossier de tentative archivee (`_run*`, `_blocked*`, `_halted*`)
        # est une tentative a part entiere, deja parcourue par son propre appel :
        # ses fichiers ne sont pas comptes ici, pour ne jamais les attribuer au
        # mauvais run_id.
        try:
            relative_to_base = path.relative_to(base)
        except ValueError:
            continue
        if len(relative_to_base.parts) > 1 and _ATTEMPT_DIR_RE.match(relative_to_base.parts[0]):
            continue
        rel = ctx.rel(path)
        if rel in covered:
            continue
        size = ctx.stat_size(path)
        sha256 = ctx.sha256_of(path)
        payload: dict[str, Any] = {"size_bytes": size}
        if sha256 is not None:
            payload["sha256"] = sha256
        events.append(
            Event(
                kind="run.artifact_present",
                source=Source(path=rel, fmt=path.suffix.lstrip(".") or "bin"),
                proof=PROOF_MECHANICAL,
                link=LINK_PATH,
                run_id=dir_run_id,
                payload=payload,
                note="fichier du run_dir sans collecteur specifique — presence "
                     "constatee par la marche generique, jamais classee ici",
            )
        )


# --------------------------------------------------------------------------- #
# state.json
# --------------------------------------------------------------------------- #


def _collect_state(
    ctx: ObserverContext, base: Path, events: list[Event]
) -> tuple[Optional[str], Optional[str]]:
    path = base / "state.json"
    state = ctx.read_json(path)
    if not isinstance(state, dict):
        return None, None

    run_id = state.get("run_id")
    project = state.get("project")
    rel = ctx.rel(path)

    ts_d, ts_raw_d, fmt_d = normalize_ts(state.get("created_ts"))
    payload_declared = {
        k: state.get(k)
        for k in (
            "project",
            "run_id",
            "profile",
            "is_game",
            "model_override",
            "created_ts",
            "updated_ts",
        )
        if k in state
    }
    events.append(
        Event(
            kind="run.declared",
            source=Source(path=rel, fmt="json"),
            proof=PROOF_MECHANICAL,
            link=LINK_DIRECT,
            ts=ts_d,
            ts_raw=ts_raw_d,
            ts_format=fmt_d,
            run_id=run_id,
            project=project,
            payload=payload_declared,
        )
    )

    ts_s, ts_raw_s, fmt_s = normalize_ts(state.get("updated_ts"))
    payload_status = {
        k: state.get(k) for k in ("run_status", "escalations", "humangate_notes") if k in state
    }
    events.append(
        Event(
            kind="run.status",
            source=Source(path=rel, fmt="json", field="run_status"),
            proof=PROOF_MECHANICAL,
            link=LINK_DIRECT,
            ts=ts_s,
            ts_raw=ts_raw_s,
            ts_format=fmt_s,
            run_id=run_id,
            project=project,
            payload=payload_status,
        )
    )

    steps = state.get("steps")
    if isinstance(steps, dict):
        for etape, info in steps.items():
            if not isinstance(info, dict):
                continue
            detail = info.get("detail")
            if isinstance(detail, str) and len(detail) > 2000:
                detail = detail[:2000] + "…[tronque]"
            payload_step = {
                "etape": etape,
                "status": info.get("status"),
                "attempts": info.get("attempts"),
                "detail": detail,
            }
            ts_e, ts_raw_e, fmt_e = normalize_ts(info.get("ts"))
            events.append(
                Event(
                    kind="step.status",
                    source=Source(path=rel, fmt="json", field=f"steps.{etape}"),
                    proof=PROOF_MECHANICAL,
                    link=LINK_DIRECT,
                    ts=ts_e,
                    ts_raw=ts_raw_e,
                    ts_format=fmt_e,
                    run_id=run_id,
                    project=project,
                    etape=etape,
                    payload=payload_step,
                )
            )

    return run_id, project


# --------------------------------------------------------------------------- #
# verdict.json
# --------------------------------------------------------------------------- #


def _collect_verdict(
    ctx: ObserverContext, base: Path, dir_run_id: Optional[str], events: list[Event]
) -> None:
    """Traite tous les `verdict*.json` a la racine du dossier de tentative.

    Un projet peut porter plusieurs verdicts versionnes cote a cote (mesure
    sur pacman : `verdict.json` et `verdict_v2.json`, memes champs, memes
    oracles, deux run_id distincts). Chacun est un recu SIGNE independant :
    on les traite tous, jamais un seul au hasard du nom de fichier.
    """
    for path in _direct_children(ctx, base, "verdict*.json"):
        _collect_one_verdict(ctx, path, dir_run_id, events)


def _collect_one_verdict(
    ctx: ObserverContext, path: Path, dir_run_id: Optional[str], events: list[Event]
) -> None:
    verdict = ctx.read_json(path)
    if not isinstance(verdict, dict):
        return

    rel = ctx.rel(path)
    v_run_id = verdict.get("run_id")
    note = None
    if v_run_id and dir_run_id and v_run_id != dir_run_id:
        note = (
            f"run_id de verdict.json ({v_run_id}) diverge du run_id de "
            f"state.json du meme dossier ({dir_run_id})"
        )

    # P4 INV-2 : la signature couvre TOUT le dict `verdict` (asdict(AggregateVerdict)
    # + hmac, cf. forge.verdict.signed_aggregate_record) — `oracles` est INCLUS dans
    # le corps signe. Un seul calcul ici ; le statut se propage a `verdict.signed`,
    # `oracle.result` et aux metriques de detail issues du MEME fichier : verifier
    # deux fois la meme enveloppe n'apprendrait rien de plus.
    verdict_proof, verdict_sig_status = _signed_proof(verdict)
    if verdict_sig_status == _SIG_INVALID:
        events.append(
            _drift_invalid_signature(
                kind_verifie="verdict.signed",
                rel=rel,
                run_id=v_run_id or dir_run_id,
                project=verdict.get("project"),
                detail=f"verdict.json ({rel}) : hmac present, cle lisible, signature "
                       "invalide sur le corps de l'agregat",
            )
        )

    ts_v, ts_raw_v, fmt_v = normalize_ts(verdict.get("ts"))
    payload_v = {k: verdict.get(k) for k in _VERDICT_FIELDS if k in verdict}
    events.append(
        Event(
            kind="verdict.signed",
            source=Source(path=rel, fmt="json"),
            proof=verdict_proof,
            link=LINK_DIRECT if v_run_id else LINK_PATH,
            ts=ts_v,
            ts_raw=ts_raw_v,
            ts_format=fmt_v,
            run_id=v_run_id or dir_run_id,
            project=verdict.get("project"),
            payload=payload_v,
            note=note,
        )
    )

    oracles = verdict.get("oracles")
    if not isinstance(oracles, dict):
        return
    for oracle_id, odata in oracles.items():
        if not isinstance(odata, dict):
            continue
        o_run_id = odata.get("run_id")
        o_note = None
        if o_run_id and v_run_id and o_run_id != v_run_id:
            o_note = (
                f"run_id de l'oracle {oracle_id} ({o_run_id}) diverge du "
                f"run_id de verdict.json ({v_run_id})"
            )
        ts_o, ts_raw_o, fmt_o = normalize_ts(odata.get("ts"))
        payload_o = {
            "oracle_id": odata.get("oracle_id", oracle_id),
            "status": odata.get("status"),
            "detail": _truncate_detail(odata.get("detail"), 1000),
            "evidence_path": odata.get("evidence_path"),
            "evidence_sha256": odata.get("evidence_sha256"),
        }
        events.append(
            Event(
                kind="oracle.result",
                source=Source(path=rel, fmt="json", field=f"oracles.{oracle_id}"),
                proof=verdict_proof,
                link=LINK_DIRECT if o_run_id else LINK_PATH,
                ts=ts_o,
                ts_raw=ts_raw_o,
                ts_format=fmt_o,
                run_id=o_run_id or v_run_id or dir_run_id,
                project=verdict.get("project"),
                payload=payload_o,
                note=o_note,
            )
        )

        detail = odata.get("detail")
        if isinstance(detail, dict):
            _emit_verdict_detail_metrics(
                detail=detail,
                oracle_id=oracle_id,
                rel=rel,
                run_id=o_run_id or v_run_id or dir_run_id,
                project=verdict.get("project"),
                ts=ts_o,
                ts_raw=ts_raw_o,
                ts_fmt=fmt_o,
                proof=verdict_proof,
                events=events,
            )


def _emit_verdict_detail_metrics(
    detail: dict[str, Any],
    oracle_id: str,
    rel: str,
    run_id: Optional[str],
    project: Optional[str],
    ts: Optional[float],
    ts_raw: Optional[str],
    ts_fmt: str,
    events: list[Event],
    proof: str = PROOF_SIGNED,
) -> None:
    """Extrait `tests_executes`/`solvabilite` quand ils sont ecrits en clair
    dans le `detail` signe d'un oracle de verdict*.json, plutot que dans
    `evidence/oracle_*.log` (deja couvert par `_collect_oracle_log`).

    Mesure sur pacman (`verdict.json`/`verdict_v2.json`, oracle `code`) :
    `detail.assertions` (entier) et `detail.solvabilite` (chaine libre,
    ex. "50/50 sur 2 cartes") existent alors qu'aucun `evidence/oracle_*.log`
    n'accompagne ce run. Purement additif : ne remplace jamais un evenement
    deja produit par `_collect_oracle_log`, n'invente aucun champ absent.
    """
    assertions = detail.get("assertions")
    if isinstance(assertions, int) and not isinstance(assertions, bool):
        events.append(
            Event(
                kind="test.result",
                source=Source(
                    path=rel, fmt="json", field=f"oracles.{oracle_id}.detail.assertions"
                ),
                proof=proof,
                link=LINK_DIRECT if run_id else LINK_PATH,
                ts=ts,
                ts_raw=ts_raw,
                ts_format=ts_fmt,
                run_id=run_id,
                project=project,
                payload={
                    "oracle_id": oracle_id,
                    "assertions": assertions,
                    "returncode": detail.get("returncode"),
                },
            )
        )

    solvabilite = detail.get("solvabilite")
    if isinstance(solvabilite, str) and solvabilite.strip():
        events.append(
            Event(
                kind="solvability.result",
                source=Source(
                    path=rel, fmt="json", field=f"oracles.{oracle_id}.detail.solvabilite"
                ),
                proof=proof,
                link=LINK_DIRECT if run_id else LINK_PATH,
                ts=ts,
                ts_raw=ts_raw,
                ts_format=ts_fmt,
                run_id=run_id,
                project=project,
                payload={"oracle_id": oracle_id, "solvabilite": solvabilite},
            )
        )


# --------------------------------------------------------------------------- #
# context/<etape>.{manifest,reasoning_observability,tool_observability}.jsonl
# --------------------------------------------------------------------------- #


def _collect_context(ctx: ObserverContext, base: Path, events: list[Event]) -> None:
    context_dir = base / "context"

    for path in ctx.iter_files(context_dir, "*.manifest.jsonl"):
        etape_guess = path.name.split(".", 1)[0]
        for lineno, obj in ctx.read_jsonl(path):
            _emit_context_manifest(ctx, path, lineno, obj, etape_guess, events)

    for path in ctx.iter_files(context_dir, "*.reasoning_observability.jsonl"):
        etape_guess = path.name.split(".", 1)[0]
        for lineno, obj in ctx.read_jsonl(path):
            _emit_reasoning(ctx, path, lineno, obj, etape_guess, events)

    for path in ctx.iter_files(context_dir, "*.tool_observability.jsonl"):
        etape_guess = path.name.split(".", 1)[0]
        for lineno, obj in ctx.read_jsonl(path):
            _emit_tools(ctx, path, lineno, obj, etape_guess, events)


def _emit_context_manifest(
    ctx: ObserverContext,
    path: Path,
    lineno: int,
    obj: dict[str, Any],
    etape_guess: str,
    events: list[Event],
) -> None:
    run_id = obj.get("run_id")
    etape = obj.get("etape", etape_guess)
    attempt, attempt_field = extract_attempt(obj)
    ts, ts_raw, ts_fmt = normalize_ts(obj.get("ts"))
    payload = {f: obj[f] for f in _CONTEXT_MANIFEST_FIELDS if f in obj}
    extra, note = _model_divergence(obj)
    payload.update(extra)
    rel = ctx.rel(path)
    proof, sig_status = _signed_proof(obj)
    if sig_status == _SIG_INVALID:
        events.append(
            _drift_invalid_signature(
                kind_verifie="dispatch.context_manifest",
                rel=rel,
                run_id=run_id,
                project=None,
                detail=f"{rel}:{lineno} : hmac present, cle lisible, signature "
                       "invalide sur ce manifeste de contexte",
            )
        )
    events.append(
        Event(
            kind="dispatch.context_manifest",
            source=Source(path=rel, fmt="jsonl", line=lineno),
            proof=proof,
            link=LINK_DIRECT if run_id else LINK_PATH,
            ts=ts,
            ts_raw=ts_raw,
            ts_format=ts_fmt,
            run_id=run_id,
            etape=etape,
            attempt=attempt,
            attempt_field=attempt_field,
            actor=_build_actor(obj),
            payload=payload,
            note=note,
        )
    )


def _emit_reasoning(
    ctx: ObserverContext,
    path: Path,
    lineno: int,
    obj: dict[str, Any],
    etape_guess: str,
    events: list[Event],
) -> None:
    run_id = obj.get("run_id")
    etape = obj.get("etape", etape_guess)
    attempt, attempt_field = extract_attempt(obj)
    ts, ts_raw, ts_fmt = normalize_ts(obj.get("ts"))
    payload = {f: obj[f] for f in _REASONING_FIELDS if f in obj}
    rel = ctx.rel(path)
    proof, sig_status = _signed_proof(obj)
    if sig_status == _SIG_INVALID:
        events.append(
            _drift_invalid_signature(
                kind_verifie="dispatch.reasoning",
                rel=rel,
                run_id=run_id,
                project=None,
                detail=f"{rel}:{lineno} : hmac present, cle lisible, signature "
                       "invalide sur cet enregistrement de reasoning_observability",
            )
        )
    events.append(
        Event(
            kind="dispatch.reasoning",
            source=Source(path=rel, fmt="jsonl", line=lineno),
            proof=proof,
            link=LINK_DIRECT if run_id else LINK_PATH,
            ts=ts,
            ts_raw=ts_raw,
            ts_format=ts_fmt,
            run_id=run_id,
            etape=etape,
            attempt=attempt,
            attempt_field=attempt_field,
            actor=_build_actor(obj),
            payload=payload,
        )
    )


def _emit_tools(
    ctx: ObserverContext,
    path: Path,
    lineno: int,
    obj: dict[str, Any],
    etape_guess: str,
    events: list[Event],
) -> None:
    run_id = obj.get("run_id")
    etape = obj.get("etape", etape_guess)
    attempt, attempt_field = extract_attempt(obj)
    ts, ts_raw, ts_fmt = normalize_ts(obj.get("ts"))
    payload = {f: obj[f] for f in _TOOLS_FIELDS if f in obj}
    rel = ctx.rel(path)
    proof, sig_status = _signed_proof(obj)
    if sig_status == _SIG_INVALID:
        events.append(
            _drift_invalid_signature(
                kind_verifie="dispatch.tools",
                rel=rel,
                run_id=run_id,
                project=None,
                detail=f"{rel}:{lineno} : hmac present, cle lisible, signature "
                       "invalide sur cet enregistrement de tool_observability",
            )
        )
    events.append(
        Event(
            kind="dispatch.tools",
            source=Source(path=rel, fmt="jsonl", line=lineno),
            proof=proof,
            link=LINK_DIRECT if run_id else LINK_PATH,
            ts=ts,
            ts_raw=ts_raw,
            ts_format=ts_fmt,
            run_id=run_id,
            etape=etape,
            attempt=attempt,
            attempt_field=attempt_field,
            actor=_build_actor(obj),
            payload=payload,
        )
    )


# --------------------------------------------------------------------------- #
# reference_guard.jsonl
# --------------------------------------------------------------------------- #


def _collect_reference_guard(
    ctx: ObserverContext, base: Path, dir_run_id: Optional[str], events: list[Event]
) -> None:
    path = base / "reference_guard.jsonl"
    for lineno, obj in ctx.read_jsonl(path):
        run_id = obj.get("run_id")
        ts, ts_raw, ts_fmt = normalize_ts(obj.get("checked_at"))
        payload = {f: obj.get(f) for f in _GUARD_FIELDS if f in obj}
        events.append(
            Event(
                kind="guard.reference",
                source=Source(path=ctx.rel(path), fmt="jsonl", line=lineno),
                proof=PROOF_MECHANICAL,
                link=LINK_DIRECT if run_id else LINK_PATH,
                ts=ts,
                ts_raw=ts_raw,
                ts_format=ts_fmt,
                run_id=run_id or dir_run_id,
                payload=payload,
            )
        )


# --------------------------------------------------------------------------- #
# evidence/mutation_*.raw.json
# --------------------------------------------------------------------------- #


def _collect_mutation_evidence(
    ctx: ObserverContext, base: Path, dir_run_id: Optional[str], events: list[Event]
) -> None:
    evidence_dir = base / "evidence"
    for path in ctx.iter_files(evidence_dir, "mutation_*.raw.json"):
        match = _MUTATION_FILENAME_RE.match(path.name)
        file_run_id = match.group(1) if match else None
        obj = ctx.read_json(path)
        if not isinstance(obj, dict):
            continue
        mutation_execution = obj.get("mutation_execution")
        if not isinstance(mutation_execution, dict):
            mutation_execution = {}
        payload = {k: mutation_execution.get(k) for k in _MUTATION_EXECUTION_FIELDS}
        payload["gate"] = obj.get("gate")
        payload["forme"] = obj.get("forme")
        note = None
        if file_run_id and dir_run_id and file_run_id != dir_run_id:
            note = (
                f"run_id lu dans le nom de fichier ({file_run_id}) diverge du "
                f"run_id du dossier de tentative ({dir_run_id})"
            )
        events.append(
            Event(
                kind="mutation.result",
                source=Source(path=ctx.rel(path), fmt="json"),
                proof=PROOF_MECHANICAL,
                link=LINK_FILENAME,
                run_id=file_run_id or dir_run_id,
                payload=payload,
                note=note,
            )
        )


# --------------------------------------------------------------------------- #
# mutation_receipt.json — a la racine du dossier de run, PAS sous evidence/
# --------------------------------------------------------------------------- #


def _collect_mutation_receipt(
    ctx: ObserverContext, base: Path, dir_run_id: Optional[str], events: list[Event]
) -> None:
    """Recu de mutation au format vu sur pacman : `mutation_receipt.json` a la
    racine du dossier de run (`{total, survivors, detail, duree_s}`), distinct
    du format `evidence/mutation_*.raw.json` couvert par
    `_collect_mutation_evidence`. Les deux sources sont additives, jamais
    fusionnees — un projet peut n'avoir que l'une des deux, ou aucune."""
    path = base / "mutation_receipt.json"
    obj = ctx.read_json(path)
    if not isinstance(obj, dict) or "total" not in obj:
        return
    survivors = obj.get("survivors")
    survivors_count = len(survivors) if isinstance(survivors, list) else None
    payload = {
        k: v
        for k, v in {
            "total": obj.get("total"),
            "survivors_count": survivors_count,
            "survivors": survivors if isinstance(survivors, list) else None,
            "duree_s": obj.get("duree_s"),
        }.items()
        if v is not None
    }
    events.append(
        Event(
            kind="mutation.result",
            source=Source(path=ctx.rel(path), fmt="json"),
            proof=PROOF_MECHANICAL,
            link=LINK_PATH,
            run_id=dir_run_id,
            payload=payload,
        )
    )


# --------------------------------------------------------------------------- #
# evidence/oracle_*.log
# --------------------------------------------------------------------------- #


def _collect_oracle_log(
    ctx: ObserverContext, base: Path, dir_run_id: Optional[str], events: list[Event]
) -> None:
    evidence_dir = base / "evidence"
    for path in ctx.iter_files(evidence_dir, "oracle_*.log"):
        text = ctx.read_text(path)
        if text is None:
            continue
        rel = ctx.rel(path)

        match = _RESULT_LINE_RE.search(text)
        if match:
            payload = {
                "passed": int(match.group(1)),
                "failed": int(match.group(2)),
                "files": int(match.group(3)),
                "raw_line": match.group(0),
            }
            events.append(
                Event(
                    kind="test.result",
                    source=Source(path=rel, fmt="log"),
                    proof=PROOF_MECHANICAL,
                    link=LINK_PATH,
                    run_id=dir_run_id,
                    payload=payload,
                )
            )

        solv_payload = _find_solvability_block(text)
        if solv_payload is not None:
            events.append(
                Event(
                    kind="solvability.result",
                    source=Source(path=rel, fmt="log"),
                    proof=PROOF_MECHANICAL,
                    link=LINK_PATH,
                    run_id=dir_run_id,
                    payload=solv_payload,
                )
            )

        node_payload = _find_node_test_summary(ctx, text)
        if node_payload is not None:
            events.append(
                Event(
                    kind="test.result",
                    source=Source(path=rel, fmt="log"),
                    proof=PROOF_MECHANICAL,
                    link=LINK_PATH,
                    run_id=dir_run_id,
                    payload=node_payload,
                )
            )


def _find_node_test_summary(ctx: ObserverContext, text: str) -> Optional[dict[str, Any]]:
    """Resume `node --test` : `tests N` / `pass N` / `fail N`, plus `cwd`/`command`
    quand l'en-tete `$ <commande>` / `(cwd=<chemin>)` est present. Tolerant : si le
    resume est absent, retourne None sans deviner (meme discipline que les autres
    extracteurs de ce fichier)."""
    tests_m = _NODE_TEST_TESTS_RE.search(text)
    pass_m = _NODE_TEST_PASS_RE.search(text)
    fail_m = _NODE_TEST_FAIL_RE.search(text)
    if not (tests_m and pass_m and fail_m):
        return None
    payload: dict[str, Any] = {
        "tests": int(tests_m.group(1)),
        "pass": int(pass_m.group(1)),
        "fail": int(fail_m.group(1)),
        "format": "node_test",
    }
    cwd_m = _NODE_TEST_CWD_RE.search(text)
    if cwd_m:
        raw_cwd = cwd_m.group("cwd").strip()
        payload["cwd_raw"] = raw_cwd
        payload["cwd"] = ctx.rel(Path(raw_cwd))
    cmd_m = _NODE_TEST_CMD_RE.search(text)
    if cmd_m:
        payload["command"] = cmd_m.group("cmd").strip()
    return payload


def _find_solvability_block(text: str) -> Optional[dict[str, Any]]:
    """Cherche un bloc JSON de solvabilite {trials, won, lost, verdict, ...}.

    Tolerant : si le motif est absent, retourne None sans deviner."""
    required = ('"trials"', '"won"', '"lost"', '"verdict"')
    for match in re.finditer(r"\{[^{}]*\}", text, re.DOTALL):
        chunk = match.group(0)
        if not all(token in chunk for token in required):
            continue
        try:
            obj = json.loads(chunk)
        except json.JSONDecodeError:
            continue
        if not isinstance(obj, dict):
            continue
        payload = {k: obj[k] for k in ("trials", "won", "lost", "verdict") if k in obj}
        for k in ("failed_seeds", "project"):
            if k in obj:
                payload[k] = obj[k]
        payload["raw_line"] = chunk
        return payload
    return None


# --------------------------------------------------------------------------- #
# playtest/playtest_capture_report.json
# --------------------------------------------------------------------------- #


def _collect_playtest(
    ctx: ObserverContext, base: Path, dir_run_id: Optional[str], events: list[Event]
) -> None:
    path = base / "playtest" / "playtest_capture_report.json"
    obj = ctx.read_json(path)
    if not isinstance(obj, dict):
        return
    payload = {k: obj.get(k) for k in _CAPTURE_FIELDS if k in obj}
    events.append(
        Event(
            kind="capture.visual",
            source=Source(path=ctx.rel(path), fmt="json"),
            proof=PROOF_MECHANICAL,
            link=LINK_PATH,
            run_id=dir_run_id,
            payload=payload,
        )
    )


# --------------------------------------------------------------------------- #
# artifacts/<etape>.txt
# --------------------------------------------------------------------------- #


def _collect_artifacts(
    ctx: ObserverContext, base: Path, dir_run_id: Optional[str], events: list[Event]
) -> None:
    artifacts_dir = base / "artifacts"
    for path in ctx.iter_files(artifacts_dir, "*.txt"):
        text = ctx.read_text(path)
        if text is None:
            continue
        etape = path.stem
        sha256 = hashlib.sha256(text.encode("utf-8")).hexdigest()
        payload: dict[str, Any] = {
            "etape": etape,
            "chars": len(text),
            "sha256": sha256,
            "excerpt": text[:2000],
        }
        findings = _extract_findings_block(text)
        if findings is not None:
            payload["findings"] = findings
        events.append(
            Event(
                kind="artifact.self_declared",
                source=Source(path=ctx.rel(path), fmt="txt"),
                proof=PROOF_SELF_DECLARED,
                link=LINK_PATH,
                run_id=dir_run_id,
                etape=etape,
                payload=payload,
            )
        )


def _extract_findings_block(text: str) -> Optional[list[Any]]:
    """Cherche un bloc JSON `{"findings": [...]}` en fin de fichier.

    Ne devine pas : si le motif est absent ou mal forme, retourne None."""
    tail_span = 6000
    tail = text[-tail_span:]
    matches = list(re.finditer(r'\{\s*"findings"\s*:', tail))
    if not matches:
        return None
    start = matches[-1].start()
    decoder = json.JSONDecoder()
    try:
        obj, _end = decoder.raw_decode(tail[start:])
    except json.JSONDecodeError:
        return None
    if isinstance(obj, dict) and isinstance(obj.get("findings"), list):
        return obj["findings"]
    return None


# --------------------------------------------------------------------------- #
# tasks_run<N>.json
# --------------------------------------------------------------------------- #


def _collect_tasks(
    ctx: ObserverContext, base: Path, dir_run_id: Optional[str], events: list[Event]
) -> None:
    for path in _direct_children(ctx, base, "tasks_run*.json"):
        obj = ctx.read_json(path)
        if not isinstance(obj, dict):
            continue
        match = _TASKS_FILENAME_RE.match(path.name)
        file_num = match.group(1) if match else None
        note = None
        if file_num and dir_run_id and f"-run{file_num}-" not in dir_run_id:
            note = (
                f"{path.name} porte le numero de run {file_num} qui ne "
                f"correspond pas au run_id du dossier courant ({dir_run_id}) — "
                "rattache par defaut au run_id du dossier faute de meilleur lien."
            )
        for etape_key, prompt_text in obj.items():
            if not isinstance(prompt_text, str):
                continue
            sha256 = hashlib.sha256(prompt_text.encode("utf-8")).hexdigest()
            payload = {
                "etape": etape_key,
                "chars": len(prompt_text),
                "sha256": sha256,
                "excerpt": prompt_text[:400],
            }
            events.append(
                Event(
                    kind="run.task_prompt",
                    source=Source(path=ctx.rel(path), fmt="json", field=etape_key),
                    proof=PROOF_MECHANICAL,
                    link=LINK_PATH,
                    run_id=dir_run_id,
                    etape=etape_key,
                    payload=payload,
                    note=note,
                )
            )


# --------------------------------------------------------------------------- #
# charter.yaml (jamais parse)
# --------------------------------------------------------------------------- #


def _collect_charter(
    ctx: ObserverContext, base: Path, dir_run_id: Optional[str], events: list[Event]
) -> None:
    path = base / "charter.yaml"
    text = ctx.read_text(path)
    if text is None:
        return
    size = ctx.stat_size(path)
    sha256 = hashlib.sha256(text.encode("utf-8")).hexdigest()
    payload = {"path": ctx.rel(path), "bytes": size, "sha256": sha256}
    events.append(
        Event(
            kind="run.charter",
            source=Source(path=ctx.rel(path), fmt="yaml"),
            proof=PROOF_SELF_DECLARED,
            link=LINK_PATH,
            run_id=dir_run_id,
            payload=payload,
        )
    )


# --------------------------------------------------------------------------- #
# wiremap.json
# --------------------------------------------------------------------------- #


def _collect_wiremap(
    ctx: ObserverContext, base: Path, dir_run_id: Optional[str], events: list[Event]
) -> None:
    path = base / "wiremap.json"
    obj = ctx.read_json(path)
    if not isinstance(obj, dict):
        return
    w_run_id = obj.get("run_id")
    note = None
    if w_run_id and dir_run_id and w_run_id != dir_run_id:
        note = (
            f"run_id de wiremap.json ({w_run_id}) diverge du run_id de "
            f"state.json du dossier ({dir_run_id}) — la wiremap n'est pas "
            "regeneree a chaque run."
        )
    lines = obj.get("lines")
    if not isinstance(lines, list):
        return
    rel = ctx.rel(path)
    for idx, line in enumerate(lines):
        if not isinstance(line, dict):
            continue
        payload = {f: line.get(f) for f in _WIREMAP_LINE_FIELDS if f in line}
        events.append(
            Event(
                kind="wiremap.line",
                source=Source(path=rel, fmt="json", field=f"lines[{idx}]"),
                proof=PROOF_SELF_DECLARED,
                link=LINK_DIRECT,
                run_id=w_run_id or dir_run_id,
                payload=payload,
                note=note,
            )
        )


# --------------------------------------------------------------------------- #
# salvage_*.json
# --------------------------------------------------------------------------- #


def _collect_salvage(
    ctx: ObserverContext, base: Path, dir_run_id: Optional[str], events: list[Event]
) -> None:
    for path in _direct_children(ctx, base, "salvage_*.json"):
        obj = ctx.read_json(path)
        if not isinstance(obj, dict):
            continue
        ts, ts_raw, ts_fmt = normalize_ts(obj.get("ts"))
        payload = {k: obj.get(k) for k in _SALVAGE_FIELDS if k in obj}
        events.append(
            Event(
                kind="failure.event",
                source=Source(path=ctx.rel(path), fmt="json"),
                proof=PROOF_MECHANICAL,
                link=LINK_PATH,
                ts=ts,
                ts_raw=ts_raw,
                ts_format=ts_fmt,
                run_id=dir_run_id,
                etape=obj.get("etape"),
                payload=payload,
            )
        )


# --------------------------------------------------------------------------- #
# run.log, run<N>_console.log
# --------------------------------------------------------------------------- #


def _collect_driver_logs(
    ctx: ObserverContext, base: Path, dir_run_id: Optional[str], events: list[Event]
) -> None:
    run_log = base / "run.log"
    events.extend(_parse_driver_log(ctx, run_log, dir_run_id, expect_ts=True))

    for path in _direct_children(ctx, base, "run*_console.log"):
        events.extend(_parse_driver_log(ctx, path, dir_run_id, expect_ts=False))


def _parse_driver_log(
    ctx: ObserverContext, path: Path, dir_run_id: Optional[str], expect_ts: bool
) -> list[Event]:
    text = ctx.read_text(path)
    if text is None:
        return []
    rel = ctx.rel(path)
    out: list[Event] = []

    for line in text.splitlines():
        if line.startswith("{"):
            # Bascule vers le dump JSON brut de fin de fichier : on arrete le
            # parsing ligne-a-ligne, ce n'est plus du log structure.
            break
        line = line.rstrip("\r\n")
        if not line.strip():
            continue
        parsed = _parse_log_line(line, expect_ts)
        if parsed is None:
            continue
        ts_raw, level, logger_name, message = parsed
        ts, ts_raw_norm, ts_fmt = normalize_ts(ts_raw)

        run_match = _RUN_ID_IN_MSG_RE.search(message)
        line_run_id = run_match.group(1) if run_match else None
        link = LINK_DIRECT if line_run_id else LINK_PATH

        etape_match = _ETAPE_IN_MSG_RE.search(message)
        etape = etape_match.group(1) if etape_match else None

        payload = {"level": level, "logger": logger_name, "message": message}
        is_failure = level == "ERROR" or bool(_FAILURE_WORD_RE.search(message))
        kind = "failure.event" if is_failure else "step.status"

        out.append(
            Event(
                kind=kind,
                source=Source(path=rel, fmt="log"),
                proof=PROOF_MECHANICAL,
                link=link,
                ts=ts,
                ts_raw=ts_raw_norm,
                ts_format=ts_fmt,
                run_id=line_run_id or dir_run_id,
                etape=etape,
                actor=Actor(kind="driver"),
                payload=payload,
            )
        )
    return out


def _parse_log_line(
    line: str, expect_ts: bool
) -> Optional[tuple[Optional[str], str, str, str]]:
    if expect_ts:
        match = _DRIVER_LOG_TS_RE.match(line)
        if not match:
            return None
        return match.group("ts"), match.group("level"), match.group("logger"), match.group(
            "message"
        )
    match = _DRIVER_LOG_NOTS_RE.match(line)
    if not match:
        return None
    return None, match.group("level"), match.group("logger"), match.group("message")


# --------------------------------------------------------------------------- #
# Aides generiques
# --------------------------------------------------------------------------- #


def _direct_children(ctx: ObserverContext, base: Path, pattern: str) -> list[Path]:
    """`iter_files` est recursif (rglob) ; ceci ne garde que les enfants
    directs de `base`, pour ne jamais compter deux fois un fichier d'un
    sous-dossier de tentative traite separement."""
    return [p for p in ctx.iter_files(base, pattern) if p.parent == base]


def _truncate_detail(value: Any, limit: int) -> Optional[str]:
    """Serialise `value` en JSON compact et le tronque a `limit` caracteres.

    Les details d'oracle sont de gros arbres imbriques (product_oracle_godot
    en particulier) : la troncature s'applique donc a la representation JSON,
    pas seulement aux chaines nues."""
    if value is None:
        return None
    if isinstance(value, str):
        text = value
    else:
        try:
            text = json.dumps(value, ensure_ascii=False, sort_keys=True, default=str)
        except (TypeError, ValueError):
            text = str(value)
    if len(text) > limit:
        return text[:limit] + "…[tronque]"
    return text


def _model_divergence(obj: dict[str, Any]) -> tuple[dict[str, Any], Optional[str]]:
    """Si `model` et `model_executed` different, les deux sont remontes dans
    le payload avec une note — jamais fusionnes silencieusement."""
    model = obj.get("model")
    model_executed = obj.get("model_executed")
    if model is not None and model_executed is not None and model != model_executed:
        return (
            {"model": model, "model_executed": model_executed},
            f"model ({model}) diverge de model_executed ({model_executed})",
        )
    return {}, None


def _build_actor(obj: dict[str, Any]) -> Actor:
    model = obj.get("model")
    if model is None:
        declared = obj.get("declared")
        if isinstance(declared, dict):
            model = declared.get("model_id")
    provider = obj.get("provider")
    capability_role = obj.get("capability_role")

    kind = "unknown"
    if model == "non-llm":
        kind = "non_llm"
    elif isinstance(model, str) and "claude" in model.lower():
        kind = "llm_agent"

    return Actor(kind=kind, model=model, provider=provider, capability_role=capability_role)
