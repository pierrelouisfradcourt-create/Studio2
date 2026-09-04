"""GAME_BLUEPRINT v0 — l'objet central de conception (Lot 1, plan V2 2026-09-03, GO Pierre).

CE QUE C'EST : un seul document par projet, découpé en SECTIONS possédées. Chaque section porte
son propriétaire (une capacité, ou Pierre), la version, l'écrivain de la dernière écriture, le
sha256 de son contenu et la source dont elle provient (chemin + sha256 du fichier). Le Blueprint
ne remplace aucun artefact de run : il les RÉUNIT sous un seul objet dont l'état se lit d'un coup.

CE QUE CE MODULE N'EST PAS : aucun Director, aucune convocation, aucun LLM, aucune écriture hors
de l'objet en mémoire (la persistance est `save`/`load`, explicites). Aucun verdict n'est lu ni
modifié. NO_CLAIM_ALLOWED.

PROPRIÉTÉ (FORGE_TARGET_MODEL §2, corrigée par le plan §2.4) — mécanique, pas déclarative :
`write_section` refuse un écrivain hors de la table OWNERS. `feature_map` et `wiremap` sont des
sections DÉRIVÉES : aucun humain ne les saisit (même règle que « aucun LLM n'écrit loop.json »).
`questions` est append-only : une question ne disparaît jamais (doctrine de complétion mutuelle).
L'écrivain `importer` est autorisé partout, mais seulement avec une source datée d'un run — c'est
l'importeur déterministe de `forge.blueprint_import`, jamais un agent.
"""
from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

SCHEMA_ID = "GAME_BLUEPRINT/v0"
IMPORTER = "importer"

# Ordre = ordre de lecture humain. Les sections réservées par la cible (design_metrics, ux,
# game_flow, systems) NE SONT PAS ici : DOCUMENTED_ONLY, aucune n'a de producteur (plan §6).
SECTIONS: tuple[str, ...] = (
    "identity", "vision", "constraints",
    "gameplay", "understanding",
    "feature_map", "architecture_contract", "wiremap",
    "questions", "decisions", "provenance",
)

# Qui a le droit d'écrire quoi. Noms = `capability_role` de forge/contracts/roles.yaml, plus
# `pierre` (HumanGate) et `director` (Lot 3, réservé). `importer` est ajouté à l'exécution.
OWNERS: dict[str, frozenset[str]] = {
    "identity": frozenset({"pierre"}),
    "vision": frozenset({"pierre"}),
    "constraints": frozenset({"pierre"}),
    "gameplay": frozenset({"contract_author"}),
    "understanding": frozenset({"worldscan", "prisme", "game_master"}),
    "feature_map": frozenset({"decompose"}),            # DÉRIVÉE — jamais `pierre`
    "architecture_contract": frozenset({"architect"}),
    "wiremap": frozenset({"wiremap", "builder"}),       # DÉRIVÉE — design (s5) puis construite (s9)
    "questions": frozenset({"contract_author", "worldscan", "prisme", "game_master", "art_director",
                            "decompose", "architect", "wiremap", "builder", "redteam_plan",
                            "redteam_code", "director", "pierre"}),
    "decisions": frozenset({"director", "pierre"}),
    "provenance": frozenset({IMPORTER}),
}
DERIVED_SECTIONS = frozenset({"feature_map", "wiremap"})
APPEND_ONLY_SECTIONS = frozenset({"questions", "decisions"})


class BlueprintError(Exception):
    """Base des refus du Blueprint — jamais un silence."""


class OwnershipViolation(BlueprintError):
    """Écrivain hors de la table OWNERS de la section visée."""


class AppendOnlyViolation(BlueprintError):
    """Une section append-only a perdu une entrée."""


def content_sha256(content) -> str:
    """sha256 du contenu en JSON canonique (clés triées, séparateurs fixes)."""
    blob = json.dumps(content, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(blob.encode("utf-8")).hexdigest()


def file_sha256(path: Path) -> str:
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def _now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def empty_section(section: str) -> dict:
    """Section vide déclarée : version 0, aucune source, contenu None (liste vide si append-only)."""
    return {
        "owner": sorted(OWNERS[section]),
        "writer": None,
        "version": 0,
        "content_sha256": None,
        "source": {"path": None, "sha256": None, "status": "ABSENT"},
        "content": [] if section in APPEND_ONLY_SECTIONS else None,
    }


def new_blueprint(project: str) -> dict:
    return {
        "schema": SCHEMA_ID,
        "project": project,
        "imported_at": None,
        "sections": {s: empty_section(s) for s in SECTIONS},
    }


def _check_owner(section: str, writer: str) -> None:
    if section not in OWNERS:
        raise BlueprintError(f"section inconnue {section!r} (attendu : {', '.join(SECTIONS)})")
    if writer == IMPORTER:
        return
    if section in DERIVED_SECTIONS and writer == "pierre":
        raise OwnershipViolation(
            f"{section!r} est une section DÉRIVÉE : jamais saisie à la main (écrivain {writer!r})")
    if writer not in OWNERS[section]:
        raise OwnershipViolation(
            f"écrivain {writer!r} hors des propriétaires de {section!r} "
            f"({', '.join(sorted(OWNERS[section]))})")


def _check_append_only(section: str, before, after) -> None:
    if section not in APPEND_ONLY_SECTIONS:
        return
    if not isinstance(after, list):
        raise AppendOnlyViolation(f"{section!r} doit rester une liste (reçu {type(after).__name__})")
    prev = before if isinstance(before, list) else []
    if len(after) < len(prev) or after[: len(prev)] != prev:
        raise AppendOnlyViolation(
            f"{section!r} est append-only : {len(prev)} entrée(s) existante(s) doivent être "
            f"conservées à l'identique et en tête (reçu {len(after)} entrée(s))")


def write_section(blueprint: dict, section: str, content, *, writer: str, source: dict) -> dict:
    """Écrit `content` dans `section` au nom de `writer`. Refuse (lève) hors propriété ou hors
    append-only ; ne modifie RIEN en cas de refus. Retourne la section écrite."""
    _check_owner(section, writer)
    if writer == IMPORTER and not (isinstance(source, dict) and source.get("run_id")):
        raise OwnershipViolation("l'écrivain `importer` exige une source portant `run_id`")
    current = blueprint["sections"][section]
    _check_append_only(section, current.get("content"), content)
    src = {"path": None, "sha256": None, "status": "DECLARED"}
    src.update(source or {})
    if src.get("path") is None and src.get("status") == "DECLARED":
        src["status"] = "NO_FILE"
    updated = {
        "owner": sorted(OWNERS[section]),
        "writer": writer,
        "version": int(current.get("version", 0)) + 1,
        "content_sha256": content_sha256(content),
        "source": src,
        "content": content,
    }
    blueprint["sections"][section] = updated
    return updated


def restore_section(blueprint: dict, section: str, snapshot: dict, *, decision_id: str,
                    authorized_by: str) -> dict:
    """Restaure une version ANTÉRIEURE d'une section (Lot 3 : réaction à une régression).

    Ce n'est pas une écriture de propriétaire : c'est un acte d'autorité, et seul Pierre
    la détient (`authorized_by == "pierre"`, réponse structurée K8). Le Director propose,
    inscrit la décision, et applique — jamais de sa propre initiative. La version
    s'incrémente (l'historique ne recule jamais), l'écrivain est `director`, la source dit
    d'où vient le contenu et quelle décision l'a autorisé. Sections append-only exclues :
    une question ou une décision ne se « restaure » pas."""
    if authorized_by != "pierre":
        raise OwnershipViolation(
            f"restauration de {section!r} refusée : seule une réponse de Pierre l'autorise "
            f"(reçu {authorized_by!r})")
    if section in APPEND_ONLY_SECTIONS:
        raise AppendOnlyViolation(f"{section!r} est append-only : rien ne se restaure")
    if section not in OWNERS:
        raise BlueprintError(f"section inconnue {section!r}")
    if not isinstance(snapshot, dict) or "content" not in snapshot:
        raise BlueprintError("snapshot invalide : `content` attendu")
    current = blueprint["sections"][section]
    updated = {
        "owner": sorted(OWNERS[section]),
        "writer": "director",
        "version": int(current.get("version", 0)) + 1,
        "content_sha256": content_sha256(snapshot["content"]),
        "source": {"path": snapshot.get("path"), "sha256": None, "status": "RESTORED",
                   "from_version": snapshot.get("version"), "decision_id": decision_id,
                   "authorized_by": authorized_by},
        "content": snapshot["content"],
    }
    blueprint["sections"][section] = updated
    return updated


def validate(blueprint: dict) -> list[str]:
    """Liste de problèmes (vide = valide). Jamais d'exception sur entrée malformée."""
    problems: list[str] = []
    if not isinstance(blueprint, dict):
        return [f"blueprint n'est pas un mapping ({type(blueprint).__name__})"]
    if blueprint.get("schema") != SCHEMA_ID:
        problems.append(f"schema {blueprint.get('schema')!r} != {SCHEMA_ID!r}")
    if not isinstance(blueprint.get("project"), str) or not blueprint["project"].strip():
        problems.append("project absent ou vide")
    sections = blueprint.get("sections")
    if not isinstance(sections, dict):
        return problems + ["sections absent"]
    for s in SECTIONS:
        meta = sections.get(s)
        if not isinstance(meta, dict):
            problems.append(f"section {s!r} absente")
            continue
        for key in ("owner", "version", "source", "content"):
            if key not in meta:
                problems.append(f"section {s!r} sans champ {key!r}")
        if meta.get("version", 0) > 0:
            if meta.get("writer") is None:
                problems.append(f"section {s!r} v{meta['version']} sans écrivain")
            if meta.get("content_sha256") != content_sha256(meta.get("content")):
                problems.append(f"section {s!r} : content_sha256 ne correspond pas au contenu")
        if s in APPEND_ONLY_SECTIONS and not isinstance(meta.get("content"), list):
            problems.append(f"section {s!r} append-only doit être une liste")
    for s in sections:
        if s not in SECTIONS:
            problems.append(f"section inconnue {s!r}")
    return problems


def save(blueprint: dict, path: Path) -> Path:
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(blueprint, ensure_ascii=False, sort_keys=True, indent=1) + "\n",
                    encoding="utf-8")
    return path


def load(path: Path) -> dict:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    problems = validate(data)
    if problems:
        raise BlueprintError("blueprint invalide : " + " ; ".join(problems))
    return data


def stamp_imported(blueprint: dict) -> None:
    blueprint["imported_at"] = _now()
