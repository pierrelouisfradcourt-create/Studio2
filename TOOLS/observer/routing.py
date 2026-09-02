"""Routage des artefacts Observer — loi verrouillee par Pierre (mission P2,
2026-08-08).

    donnee explicite existante -> regle citant son champ source -> destination
    absence de regle fondee    -> REVIEW_REQUIRED
    JAMAIS : fichier inconnu -> inference sur le nom/contenu -> classement

Ce module est PUR : aucune lecture de fichier, aucune ecriture. Il ne consomme
que ce que les adaptateurs ont deja transforme en `Event` (voir
`observer.adapters.forge_run`) et le `dict` de reconstruction produit par
`observer.correlate.reconstruct`. Une regle qui ne peut pas citer le champ
source qui la fonde n'existe pas : chaque entree retournee porte `rule` (texte
humain) ET `field` (chemin du champ dans la source), jamais l'un sans l'autre.

Destinations autorisees — liste FERMEE, ne jamais en ajouter une sans decision
Pierre :

    PRODUCT · EVIDENCE · LESSON · DECISION_INPUT · KNOWLEDGE_INPUT ·
    NEXT_RUN_INPUT · ARCHIVE · REVIEW_REQUIRED

Deux categories de regles, avec une frontiere volontaire :

  * `route_run_files` classe CHAQUE FICHIER du run_dir d'un run reconstruit —
    c'est la fonction validee par la mission ("100% des fichiers routes").
  * `open_flags_of`, `archive_candidates` alimentent les AUTRES sous-sections
    de `session_transition` (next_run_input, archive_proposals) qui ne sont
    PAS un routage de fichier mais une lecture directe de champs deja
    reconstruits.
"""

from __future__ import annotations

import re
from collections import defaultdict
from typing import Any, Iterable, Optional

from observer.events import PROOF_SIGNED

# --------------------------------------------------------------------------- #
# Destinations — liste fermee
# --------------------------------------------------------------------------- #

PRODUCT = "PRODUCT"
EVIDENCE = "EVIDENCE"
LESSON = "LESSON"
DECISION_INPUT = "DECISION_INPUT"
KNOWLEDGE_INPUT = "KNOWLEDGE_INPUT"
NEXT_RUN_INPUT = "NEXT_RUN_INPUT"
ARCHIVE = "ARCHIVE"
REVIEW_REQUIRED = "REVIEW_REQUIRED"

DESTINATIONS: frozenset[str] = frozenset(
    {
        PRODUCT,
        EVIDENCE,
        LESSON,
        DECISION_INPUT,
        KNOWLEDGE_INPUT,
        NEXT_RUN_INPUT,
        ARCHIVE,
        REVIEW_REQUIRED,
    }
)

_WIREMAP_FROZEN_RE = re.compile(r"(^|/)wiremap[^/]*_frozen\.json$")


def _norm(path: Optional[str]) -> Optional[str]:
    if path is None:
        return None
    return path.replace("\\", "/")


def _to_repo_relative(raw: Optional[str], repo_root: str) -> Optional[str]:
    """Un `evidence_path`/`cwd` observe est souvent un chemin ABSOLU (Windows,
    backslashes) — jamais un chemin relatif comme `Source.path`. Normalise sur
    le meme format pour que les comparaisons de routage ne se cassent pas
    silencieusement sur un separateur ou une racine differents."""
    if not raw:
        return None
    norm_raw = _norm(raw)
    norm_root = _norm(repo_root)
    if norm_root and norm_raw.lower().startswith(norm_root.lower()):
        rest = norm_raw[len(norm_root):].lstrip("/")
        return rest
    return norm_raw


# --------------------------------------------------------------------------- #
# Regle par fichier — coeur du routeur
# --------------------------------------------------------------------------- #


def route_file(
    path: str,
    *,
    evidence_paths: set[str],
    signed_manifest_paths: set[str],
    reference_guard_paths: set[str],
    lesson_paths: set[str],
    humangate_flag_paths: set[str],
    product_roots: Iterable[str] = (),
) -> dict[str, Any]:
    """Route UN fichier deja normalise (`/`, relatif au repo). Premiere regle
    qui matche gagne ; l'ordre suit la table de la mission. Aucune regle ->
    REVIEW_REQUIRED, jamais une inference sur le nom/contenu du fichier."""
    p = _norm(path) or ""

    if p in evidence_paths:
        return {
            "destination": EVIDENCE,
            "rule": "cite en verdict.oracles.*.evidence_path",
            "field": "oracles.<id>.evidence_path",
        }
    if p in signed_manifest_paths:
        return {
            "destination": EVIDENCE,
            "rule": "manifeste context/*.manifest.jsonl dont le HMAC est verifie",
            "field": "proof=SIGNED (observer.signature.verify_envelope)",
        }
    if p in reference_guard_paths:
        return {
            "destination": EVIDENCE,
            "rule": "reference_guard.jsonl",
            "field": "schema=forge.reference_guard.report.v1",
        }
    if p in lesson_paths:
        return {
            "destination": LESSON,
            "rule": "manifest.reason.problem / manifest.reason.root_cause non vide",
            "field": "reason.problem|reason.root_cause",
        }
    if p in humangate_flag_paths:
        return {
            "destination": DECISION_INPUT,
            "rule": "verdict.humangate_flags non vide",
            "field": "humangate_flags",
        }
    if _WIREMAP_FROZEN_RE.search(p):
        return {
            "destination": NEXT_RUN_INPUT,
            "rule": "wiremap*_frozen.json",
            "field": "nom de fichier",
        }
    if p.endswith("reference_protected.yaml"):
        return {
            "destination": NEXT_RUN_INPUT,
            "rule": "reference_protected.yaml",
            "field": "nom de fichier",
        }
    for root in product_roots:
        root_n = _norm(root)
        if not root_n:
            continue
        if p == root_n or p.startswith(root_n.rstrip("/") + "/"):
            return {
                "destination": PRODUCT,
                "rule": "sous le src_root observe du run",
                "field": "test.result.payload.cwd (evidence/oracle_*.log, en-tete "
                         "`(cwd=...)` d'un run node --test)",
            }

    return {
        "destination": REVIEW_REQUIRED,
        "rule": "aucune regle fondee ne cite ce fichier",
        "field": None,
    }


# --------------------------------------------------------------------------- #
# Assemblage des ensembles de reference a partir des evenements reconstruits
# --------------------------------------------------------------------------- #


def _run_events(events: list[dict[str, Any]], run_id: Optional[str]) -> list[dict[str, Any]]:
    return [e for e in events if e.get("run_id") == run_id]


def build_reference_sets(
    events: list[dict[str, Any]], run_id: Optional[str], repo_root: str
) -> dict[str, set[str]]:
    """Construit, pour UN run_id, les ensembles de chemins que `route_file`
    consulte. Prend des `dict` d'evenements deja serialises (`Event.to_dict()`)
    pour rester utilisable aussi bien depuis `cli.py` (evenements reels) que
    depuis un test unitaire (evenements synthetiques minimalistes)."""
    evs = _run_events(events, run_id)

    evidence_paths: set[str] = set()
    for e in evs:
        if e.get("kind") != "oracle.result":
            continue
        raw = (e.get("payload") or {}).get("evidence_path")
        rel = _to_repo_relative(raw, repo_root)
        if rel:
            evidence_paths.add(rel)

    signed_manifest_paths: set[str] = set()
    for e in evs:
        if e.get("kind") == "dispatch.context_manifest" and e.get("proof") == PROOF_SIGNED:
            p = (e.get("source") or {}).get("path")
            if p:
                signed_manifest_paths.add(_norm(p))

    reference_guard_paths: set[str] = set()
    for e in evs:
        if e.get("kind") == "guard.reference":
            p = (e.get("source") or {}).get("path")
            if p:
                reference_guard_paths.add(_norm(p))

    lesson_paths: set[str] = set()
    for e in evs:
        if e.get("kind") != "dispatch.context_manifest":
            continue
        reason = (e.get("payload") or {}).get("reason")
        if isinstance(reason, dict) and (
            (reason.get("problem") or "").strip() or (reason.get("root_cause") or "").strip()
        ):
            p = (e.get("source") or {}).get("path")
            if p:
                lesson_paths.add(_norm(p))

    humangate_flag_paths: set[str] = set()
    for e in evs:
        if e.get("kind") != "verdict.signed":
            continue
        flags = (e.get("payload") or {}).get("humangate_flags")
        if isinstance(flags, list) and flags:
            p = (e.get("source") or {}).get("path")
            if p:
                humangate_flag_paths.add(_norm(p))

    product_roots: set[str] = set()
    for e in evs:
        if e.get("kind") != "test.result":
            continue
        cwd = (e.get("payload") or {}).get("cwd")
        if cwd:
            product_roots.add(_norm(cwd))

    return {
        "evidence_paths": evidence_paths,
        "signed_manifest_paths": signed_manifest_paths,
        "reference_guard_paths": reference_guard_paths,
        "lesson_paths": lesson_paths,
        "humangate_flag_paths": humangate_flag_paths,
        "product_roots": product_roots,
    }


def route_run_files(
    events: list[dict[str, Any]], run_id: Optional[str], repo_root: str
) -> list[dict[str, Any]]:
    """Route tous les fichiers observes pour UN run_id (tous les `source.path`
    distincts portes par les evenements de ce run, `run.artifact_present`
    compris — c'est lui qui garantit qu'aucun fichier du run_dir ne reste sans
    evenement, donc sans entree ici)."""
    refs = build_reference_sets(events, run_id, repo_root)
    evs = _run_events(events, run_id)

    paths: set[str] = set()
    for e in evs:
        p = (e.get("source") or {}).get("path")
        if p and not p.startswith("git:"):
            paths.add(_norm(p))

    out: list[dict[str, Any]] = []
    for p in sorted(paths):
        decision = route_file(
            p,
            evidence_paths=refs["evidence_paths"],
            signed_manifest_paths=refs["signed_manifest_paths"],
            reference_guard_paths=refs["reference_guard_paths"],
            lesson_paths=refs["lesson_paths"],
            humangate_flag_paths=refs["humangate_flag_paths"],
            product_roots=refs["product_roots"],
        )
        out.append({"path": p, **decision})
    return out


# --------------------------------------------------------------------------- #
# Sections annexes de `session_transition` — pas un routage de fichier
# --------------------------------------------------------------------------- #


def open_flags_of(run: dict[str, Any]) -> list[str]:
    """`open` de `session_transition` = humangate_flags du DERNIER verdict signe
    du run — lecture directe du champ, aucune inference."""
    verdict = run.get("verdict")
    if not isinstance(verdict, dict):
        return []
    flags = verdict.get("humangate_flags")
    return list(flags) if isinstance(flags, list) else []


def archive_candidate(
    run: dict[str, Any], *, has_reader: bool, age_days: Optional[float]
) -> Optional[dict[str, Any]]:
    """ARCHIVE reste une PROPOSITION : un run terminal (`run_status` fini),
    sans lecteur declare, avec un age mesurable. Aucun des trois manquants ->
    pas de proposition (silence, pas une fausse negative deguisee en positive).
    """
    status = run.get("run_status")
    terminal = status in ("DONE", "FAILED", "BLOCKED", "HALTED", "ABANDONED")
    if not terminal or has_reader or age_days is None:
        return None
    return {
        "run_id": run.get("run_id"),
        "destination_proposee": "C:\\STUDIO_ARCHIVE",
        "justification": f"run terminal (run_status={status}), aucun lecteur declare, "
                         f"age {age_days:.1f} jours",
        "preuve": {
            "run_status": status,
            "has_reader": has_reader,
            "age_days": round(age_days, 1),
        },
    }
