"""Identité d'une section du GAME_BLUEPRINT (Lot 6, spec 2026-09-04, GO Pierre).

DEUX questions, deux réponses déterministes :
  * `identity_of(section)` — la clé d'identité canonique déclarée au registre, ou None si la section
    n'en a pas de mesurée (`UNKNOWN` : aucune règle ne s'applique, jamais une clé devinée) ;
  * `compare(...)` — ce qui a été gardé, ajouté, retiré, et ce qui a DISPARU alors que l'aval le cite.

Pourquoi : trois convocations réelles de `decompose` sur le même projet ont produit trois schémas d'ids
(`R1c1_*`, `R1..R10`, `CAP_*`) alors que la wiremap cite ces ids dans `features[].couvre[]` — un
renommage transforme une jointure JOINED en VOID sans qu'aucun mécanisme ne l'empêche ni ne désigne le
responsable.

RÉSOLVEUR (`key: "@<nom>"`) : quand l'identité d'une section est DÉJÀ calculée par une fonction de
production, le registre nomme cette fonction au lieu de recopier un chemin. Mesuré sur `wiremap` :
`static_oracles.frozen_features_from_wiremap` résout `lines[].id` (v2) ou `features[].feature` (v1), et
c'est cette identité que le gel des règles oppose au jeu courant (`check_feature_set_frozen`, STOP dur
en s10c). Recopier ces deux chemins ici créerait une seconde vérité qui divergerait au premier schéma
nouveau — voir EVIDENCE/reports/lot6_reconvocation/identity_measurement.md.

Ce module ne lit ni ne modifie un verdict, n'appelle aucun modèle, n'écrit aucun fichier. Il ne décide
pas non plus de refuser : il MESURE, et `forge.capability` applique la règle au point d'écriture.
NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

from pathlib import Path

import yaml

REGISTRY_PATH = Path(__file__).resolve().parent / "capability_registry.yaml"
UNKNOWN = "UNKNOWN"
ID_REFERENCED_DROPPED = "ID_REFERENCED_DROPPED"
RETIRED_KEY = "identity"          # <artefact>.identity.retired = [{id, reason}]


def load_identity(path: Path | None = None) -> dict:
    doc = yaml.safe_load(Path(path or REGISTRY_PATH).read_text(encoding="utf-8")) or {}
    return doc.get("identity") or {}


def identity_of(section: str, doc: dict | None = None) -> dict | None:
    """Déclaration d'identité d'une section, ou None si absente ou non mesurée (UNKNOWN)."""
    decl = (doc if doc is not None else load_identity()).get(section)
    if not isinstance(decl, dict) or decl.get("key") in (None, "", UNKNOWN):
        return None
    return decl


# --- résolveurs nommés : l'identité EST déjà calculée par la production ----------------------------

def _resolve_frozen_features(content) -> list[str]:
    """Délègue à l'unique autorité de production (static_oracles), jamais une copie de ses chemins."""
    from forge.static_oracles import frozen_features_from_wiremap
    if not isinstance(content, dict):
        return []
    return [str(v) for v in frozen_features_from_wiremap(content) if str(v)]


_RESOLVERS = {"@frozen_features_from_wiremap": _resolve_frozen_features}


# --- navigation par chemin ------------------------------------------------------------------------

def _walk(node, steps: list[str]) -> list:
    """Navigation déterministe : 'a[].b[].c' — '[]' descend dans une liste, un nom dans un dict."""
    if not steps:
        return [node] if node is not None else []
    step, rest = steps[0], steps[1:]
    if step == "[]":
        return [] if not isinstance(node, list) else [v for item in node for v in _walk(item, rest)]
    if not isinstance(node, dict) or step not in node:
        return []
    return _walk(node[step], rest)


def _parse(key: str) -> list[str]:
    steps: list[str] = []
    for part in str(key).split("."):
        name, _, brackets = part.partition("[")
        if name:
            steps.append(name)
        steps += ["[]"] * brackets.count("]")
    return steps


def extract_ids(content, key: str) -> list[str]:
    """Identifiants présents, dans l'ordre de lecture. Jamais d'exception : une structure inattendue
    rend une liste vide (l'absence de mesure ne se déguise pas en absence d'identifiants)."""
    resolver = _RESOLVERS.get(str(key))
    if resolver is not None:
        try:
            return resolver(content)
        except Exception:  # noqa: BLE001 — un résolveur en échec ne fabrique jamais d'identités
            return []
    return [str(v) for v in _walk(content, _parse(key)) if isinstance(v, (str, int)) and str(v)]


def declared_retired(content) -> list[dict]:
    """Retraits déclarés par la production elle-même : <artefact>.identity.retired."""
    block = content.get(RETIRED_KEY) if isinstance(content, dict) else None
    items = block.get("retired") if isinstance(block, dict) else None
    return [i for i in (items or []) if isinstance(i, dict) and i.get("id")]


def downstream_ids(blueprint: dict, refs: list[dict]) -> set[str]:
    """Identifiants réellement cités en aval, d'après les chemins déclarés au registre."""
    out: set[str] = set()
    for ref in refs or []:
        section, _, entry = str(ref.get("section", "")).partition(".")
        meta = (blueprint.get("sections") or {}).get(section) or {}
        content = meta.get("content")
        if entry:
            sub = content.get(entry) if isinstance(content, dict) else None
            content = sub.get("content") if isinstance(sub, dict) else None
        out.update(extract_ids(content, ref.get("path", "")))
    return out


def compare(before, after, *, key: str, downstream: set[str], retired: list[dict]) -> dict:
    """Rapport d'identité entre deux versions d'une section. MESURE — le refus est appliqué par
    l'appelant (`forge.capability`), qui seul est au point d'écriture.

    Règle (spec §3.4, correction 1 de Pierre) : un identifiant absent de `after` n'est accepté que
    s'il n'est PLUS cité en aval. Un retrait déclaré mais encore référencé est refusé au même titre
    qu'un renommage implicite — sinon on transformerait un renommage silencieux en suppression
    déclarée."""
    b = list(dict.fromkeys(extract_ids(before, key)))
    a = list(dict.fromkeys(extract_ids(after, key)))
    declared = {str(r["id"]) for r in (retired or [])}
    kept = [i for i in b if i in a]
    added = [i for i in a if i not in b]
    absents = [i for i in b if i not in a]
    referenced_dropped = [i for i in absents if i in (downstream or set())]
    retired_declared = [i for i in absents if i in declared and i not in referenced_dropped]
    dropped = [i for i in absents if i not in declared and i not in referenced_dropped]
    # Informatif : autant d'absents que d'ajouts => un renommage est PROBABLE. Jamais un verdict.
    renamed = list(zip(absents, added)) if absents and len(absents) == len(added) else []
    return {"key": key, "kept": kept, "added": added, "retired_declared": retired_declared,
            "dropped": dropped, "renamed_suspected": renamed,
            "referenced_dropped": referenced_dropped, "ok": not referenced_dropped}
