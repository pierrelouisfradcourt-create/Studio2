"""Vue ROADMAP STUDIO de la console Observer — jeux / chantiers Forge / infrastructure.

Reprend la partie « Détail H · LE CURRICULUM » de `STUDIO_MASTER_SCHEMA.html` (l'arbre
de jeux, chacun avec un statut ● FAIT / ◐ EN COURS / ◇ CIBLE) et la complète avec :

  1. les TRACES mesurées (vue Fleet, `observer.fleet.view_fleet`) croisées par nom de
     projet — la doctrine affichée COMME doctrine (`SELF_DECLARED`, datée par le mtime
     du document) plutôt que comme un fait ;
  2. cinq « chantiers Forge » (Observer, Knowledge Runtime, World Scan, Asset Forge,
     Game Discovery) : ce que la doctrine en dit (recherche best-effort, exacte ou par
     terme proche) × un indice mécanique quand il existe ;
  3. six lignes d'infrastructure (LM Studio, Workers, Qwen, Claude, Playwright, GitHub) :
     doctrine seule — Observer lit des fichiers, il ne sonde jamais un port ni un
     service, donc la mesure y est NOT_OBSERVABLE par construction, jamais par oubli.

Les deux documents HTML sont de la doctrine manuelle (SVG écrits à la main), pas un
format stable : ce module les parse par regex/découpage de sections, best-effort assumé.
Toute cellule qui en résulte porte `"proof": "SELF_DECLARED"` et une `"note"` qui dit
comment elle a été obtenue. Un désaccord entre la doctrine et une mesure réelle devient
un `drift_item` de famille `documentation` (propriétaire DOCTRINE, action CORRIGER) —
jamais une correction silencieuse : Observer signale, HumanGate tranche.

Règle héritée de `cockpit.py`/`command.py`, non négociable ici aussi : une donnée qui
n'existe pas dans les traces ou dans la doctrine porte `NOT_OBSERVABLE` et sa raison —
jamais 0, jamais vide, jamais deviné.

Interface imposée :
    view_roadmap(ctx, result, events) -> dict          # la vue s2_roadmap elle-même
    build_roadmap_views(ctx, result, events) -> dict    # {"s2_roadmap": ...}
"""

from __future__ import annotations

import logging
import re
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

_HERE = Path(__file__).resolve().parent
if str(_HERE.parent) not in sys.path:  # rend `import observer` possible sans install
    sys.path.insert(0, str(_HERE.parent))

from observer.sources import BlindnessViolation  # noqa: E402

LOG = logging.getLogger("observer.system_roadmap")

NOT_OBSERVABLE = "NOT_OBSERVABLE"
SELF_DECLARED = "SELF_DECLARED"

SCHEMA_RELPATH = ("docs", "forge", "STUDIO_MASTER_SCHEMA.html")
PILOTAGE_RELPATH = ("docs", "forge", "FORGE_V2_PILOTAGE.html")

DRIFT_TYPE = "roadmap_doctrine_vs_mesure"


# --------------------------------------------------------------------------- #
# Cellule — meme contrat que cockpit.py/command.py : {v, src?, why?}
# --------------------------------------------------------------------------- #


def _cell(value: Any, src: Optional[dict[str, Any]] = None, why: Optional[str] = None) -> dict[str, Any]:
    out: dict[str, Any] = {"v": value}
    if src:
        out["src"] = src
    if value == NOT_OBSERVABLE and why:
        out["why"] = why
    return out


def _drift(detail: str, source: Any, severity: str = "medium") -> dict[str, Any]:
    """Item de drift au format attendu par la vue Drift unique (§ cockpit.py) —
    fusionné par l'orchestrateur, jamais consommé seul par ce module."""
    return {
        "type": DRIFT_TYPE,
        "severity": severity,
        "famille": "documentation",
        "owner": "DOCTRINE",
        "action": "CORRIGER",
        "detail": detail,
        "source": source,
    }


def _iso(epoch: float) -> str:
    return datetime.fromtimestamp(epoch, tz=timezone.utc).isoformat()


def _mtime_iso(ctx: Any, path: Path) -> Any:
    """Horodatage de modification, sous la MEME garde de cecite que le reste d'Observer.

    `ObserverContext` n'expose pas de lecteur de mtime dedie (seulement `stat_size`,
    borne aux octets) ; on reutilise sa garde privee `_check` pour ne jamais appeler
    `.stat()` sur un chemin que le contexte n'a pas lui-meme valide comme lisible.
    `BlindnessViolation` n'est jamais rattrapee ici.
    """
    resolved = ctx._check(path)  # noqa: SLF001 - meme garde que sources.py, pas de contournement
    if not resolved.is_file():
        return NOT_OBSERVABLE
    try:
        return _iso(resolved.stat().st_mtime)
    except OSError as exc:
        LOG.warning("mtime illisible pour %s: %s", resolved, exc)
        return NOT_OBSERVABLE


_TAG_RE = re.compile(r"<[^>]+>")


def _strip_tags(text: str) -> str:
    return _TAG_RE.sub(" ", text).strip()


# --------------------------------------------------------------------------- #
# Lecture des deux documents doctrine — jamais rattraper BlindnessViolation
# --------------------------------------------------------------------------- #


def _read_doc(ctx: Any, parts: tuple[str, ...]) -> Optional[dict[str, Any]]:
    path = ctx.repo_root.joinpath(*parts)
    text = ctx.read_text(path)
    if text is None:
        LOG.warning("document doctrine illisible ou absent: %s", path)
        return None
    return {
        "text": text,
        "lines": text.splitlines(),
        "path": ctx.rel(path),
        "mtime": _mtime_iso(ctx, path),
    }


# --------------------------------------------------------------------------- #
# Parsing best-effort — « Détail H · LE CURRICULUM » (STUDIO_MASTER_SCHEMA.html)
#
# Chaque nœud du curriculum est un <rect> suivi de <text> : le 1er texte est le nom
# du jeu, le 2e son système, un texte libre optionnel, et un marqueur de statut
# (● FAIT / ◐ EN COURS / ◇ CIBLE) quelque part dans le bloc. C'est un SVG écrit a la
# main, pas un format stable — ce parseur est volontairement tolerant et ne suppose
# aucun ordre fixe au-dela des deux premiers textes.
# --------------------------------------------------------------------------- #

_RECT_START_RE = re.compile(r"<rect\b")
_TEXT_CONTENT_RE = re.compile(r"<text\b[^>]*>([^<]*)</text>")
_STATUS_RE = re.compile(r"(\u25cf|\u25d0|\u25c7)\s*(FAIT|EN COURS|CIBLE)")


def _extract_curriculum(doc: dict[str, Any]) -> list[dict[str, Any]]:
    """Un noeud par jeu du Detail H, dans l'ordre d'apparition du SVG."""
    text = doc["text"]
    start = text.find("D\u00e9tail H \u00b7")
    if start == -1:
        return []
    end = text.find("D\u00e9tail H-bis")
    if end == -1:
        end = len(text)
    section = text[start:end]
    base_line = text.count("\n", 0, start)

    nodes: list[dict[str, Any]] = []
    positions = [m.start() for m in _RECT_START_RE.finditer(section)]
    for i, pos in enumerate(positions):
        chunk_end = positions[i + 1] if i + 1 < len(positions) else len(section)
        chunk = section[pos:chunk_end]
        texts = [t.strip() for t in _TEXT_CONTENT_RE.findall(chunk) if t.strip()]
        if not texts:
            continue
        status_match = _STATUS_RE.search(chunk)
        status_text = status_match.group(0) if status_match else None
        name = texts[0]
        systeme = texts[1] if len(texts) > 1 else None
        note_libre = [t for t in texts[2:] if not _STATUS_RE.fullmatch(t)]
        lineno = base_line + section.count("\n", 0, pos) + 1
        nodes.append({
            "nom": name,
            "systeme": systeme,
            "statut_doctrine": status_text or NOT_OBSERVABLE,
            "note_libre": note_libre,
            "ligne": lineno,
        })
    return nodes


# --------------------------------------------------------------------------- #
# Parsing best-effort — « lecture B : jeux et connaissance » (FORGE_V2_PILOTAGE.html)
# Boîtes PONG / SNAKE / BREAKOUT, plus riches (preuve, rôle d'apprentissage) que le
# curriculum mais couvrant seulement les jeux réellement forgés — source secondaire,
# fusionnée sous une clé distincte pour que tout désaccord entre les deux documents
# reste visible plutôt que d'être écrasé par un merge silencieux.
# --------------------------------------------------------------------------- #


def _extract_pilotage_boxes(doc: dict[str, Any]) -> dict[str, dict[str, Any]]:
    text = doc["text"]
    start = text.find("QUEL JEU PRODUIT QUELLE CONNAISSANCE")
    if start == -1:
        return {}
    end = text.find("LE BUDGET M\u00c9CANIQUE")
    if end == -1:
        end = len(text)
    section = text[start:end]
    base_line = text.count("\n", 0, start)

    boxes: dict[str, dict[str, Any]] = {}
    positions = [m.start() for m in _RECT_START_RE.finditer(section)]
    for i, pos in enumerate(positions):
        chunk_end = positions[i + 1] if i + 1 < len(positions) else len(section)
        chunk = section[pos:chunk_end]
        texts = [t.strip() for t in _TEXT_CONTENT_RE.findall(chunk) if t.strip()]
        if not texts:
            continue
        name = texts[0]
        lineno = base_line + section.count("\n", 0, pos) + 1
        boxes[name] = {
            "statut_pilotage": texts[1] if len(texts) > 1 else NOT_OBSERVABLE,
            "notes": texts[2:],
            "ligne": lineno,
        }
    return boxes


# --------------------------------------------------------------------------- #
# Croisement doctrine <-> traces (vue Fleet), par nom de projet
# --------------------------------------------------------------------------- #


def _normalize_key(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", "_", name.strip().lower()).strip("_")


def _match_fleet_projects(doctrine_name: str, projects: list[str]) -> list[str]:
    key = _normalize_key(doctrine_name)
    if not key:
        return []
    out = []
    for projet in projects:
        pkey = _normalize_key(projet)
        if pkey == key or pkey.startswith(key + "_") or key.startswith(pkey + "_"):
            out.append(projet)
    return out


def _lines_by_project(fleet: dict[str, Any]) -> dict[str, list[dict[str, Any]]]:
    grouped: dict[str, list[dict[str, Any]]] = {}
    for ligne in fleet.get("lignes", []):
        if ligne.get("v") == "ERREUR":
            continue
        projet = (ligne.get("projet") or {}).get("v")
        if not projet:
            continue
        grouped.setdefault(projet, []).append(ligne)
    return grouped


def _trace_summary(ligne: dict[str, Any]) -> dict[str, Any]:
    return {
        "run_id": (ligne.get("run_id") or {}).get("v"),
        "decision": (ligne.get("decision") or {}).get("v"),
        "mutation": (ligne.get("mutation") or {}).get("v"),
        "tests": (ligne.get("tests") or {}).get("v"),
    }


def _progression_cell(lines_for_project: list[dict[str, Any]]) -> dict[str, Any]:
    """Barre de progression UNIQUEMENT si dérivable d'une mesure réelle — jamais de
    la doctrine, jamais devinée. `lines_for_project` doit être trié plus-récent-en-tête
    (c'est l'ordre que rend déjà `view_fleet`)."""
    if not lines_for_project:
        return _cell(NOT_OBSERVABLE, why="aucune mesure de progression n'existe, la "
                     "barre de la doctrine est déclarative")

    latest = lines_for_project[0]
    mutation_cell = latest.get("mutation") or {}
    mutation = mutation_cell.get("v")
    if isinstance(mutation, str) and mutation != NOT_OBSERVABLE and "/" in mutation:
        parts = mutation.split("/", 1)
        try:
            killed, total = float(parts[0]), float(parts[1])
        except (ValueError, IndexError):
            killed = total = None
        if total:
            pct = round(100.0 * killed / total, 1)
            cell = _cell(pct, mutation_cell.get("src"))
            cell["derive_de"] = "mutation kill rate (dernier run)"
            return cell

    decision_cell = latest.get("decision") or {}
    decision = decision_cell.get("v")
    if decision == "HUMANGATE_READY":
        cell = _cell("avance", decision_cell.get("src"))
        cell["derive_de"] = "decision HUMANGATE_READY -> interpretee comme 'avance' (pas un pourcentage)"
        return cell
    if isinstance(decision, str) and "BLOCK" in decision.upper():
        cell = _cell("bloque", decision_cell.get("src"))
        cell["derive_de"] = f"decision '{decision}' -> interpretee comme 'bloque'"
        return cell

    return _cell(NOT_OBSERVABLE, why="run(s) tracé(s) observé(s) mais ni mutation ni "
                 "décision HUMANGATE_READY/BLOCKED n'est disponible pour en dériver "
                 "une progression")


# --------------------------------------------------------------------------- #
# Section 1 — JEUX
# --------------------------------------------------------------------------- #


def _build_games_section(
    fleet: dict[str, Any],
    schema_doc: Optional[dict[str, Any]],
    pilotage_doc: Optional[dict[str, Any]],
) -> dict[str, Any]:
    lignes: list[dict[str, Any]] = []
    drift_items: list[dict[str, Any]] = []

    if schema_doc is None:
        return {
            "lignes": [{
                "jeu": _cell(NOT_OBSERVABLE, why="STUDIO_MASTER_SCHEMA.html illisible ou absent"),
            }],
            "drift_items": [],
        }

    curriculum = _extract_curriculum(schema_doc)
    pilotage_boxes = _extract_pilotage_boxes(pilotage_doc) if pilotage_doc else {}
    grouped = _lines_by_project(fleet)
    projects = sorted(grouped.keys())
    covered: set[str] = set()

    if not curriculum:
        drift_items.append(_drift(
            "le marqueur 'D\u00e9tail H \u00b7' est introuvable dans STUDIO_MASTER_SCHEMA.html : "
            "la section curriculum a peut-\u00eatre \u00e9t\u00e9 renomm\u00e9e ou d\u00e9plac\u00e9e",
            {"path": schema_doc["path"]},
            severity="high",
        ))

    for node in curriculum:
        name = node["nom"]
        matches = _match_fleet_projects(name, projects)
        covered.update(matches)
        lines_for_project: list[dict[str, Any]] = []
        for m in matches:
            lines_for_project.extend(grouped.get(m, []))

        doctrine_cell = _cell(
            {
                "systeme": node["systeme"] or NOT_OBSERVABLE,
                "statut_doctrine": node["statut_doctrine"],
                "note_libre": node["note_libre"],
            },
            {"path": schema_doc["path"], "line": node["ligne"]},
        )
        doctrine_cell["proof"] = SELF_DECLARED
        doctrine_cell["note"] = (
            "extrait best-effort du SVG 'D\u00e9tail H' (d\u00e9coupage <rect>/<text>, pas un "
            f"format stable) ; document dat\u00e9 {schema_doc['mtime']}"
        )

        pilotage_entry = pilotage_boxes.get(name)
        if pilotage_entry:
            pilotage_cell = _cell(
                {"statut_pilotage": pilotage_entry["statut_pilotage"], "notes": pilotage_entry["notes"]},
                {"path": pilotage_doc["path"], "line": pilotage_entry["ligne"]},
            )
            pilotage_cell["proof"] = SELF_DECLARED
            pilotage_cell["note"] = f"document dat\u00e9 {pilotage_doc['mtime']}"
        else:
            pilotage_cell = _cell(
                NOT_OBSERVABLE,
                why="pas de case d\u00e9di\u00e9e dans 'lecture B : jeux et connaissance' de "
                    "FORGE_V2_PILOTAGE.html pour ce nom",
            )

        if lines_for_project:
            traces_cell = _cell(
                [_trace_summary(l) for l in lines_for_project],
                {"path": "c8_fleet", "field": "lignes[].projet"},
            )
        else:
            traces_cell = _cell(
                NOT_OBSERVABLE,
                why="aucun run Forge \u00e0 \u00e9tats pour ce projet (vue Fleet vide sur ce nom)",
            )

        lignes.append({
            "jeu": _cell(name),
            "doctrine_curriculum": doctrine_cell,
            "doctrine_pilotage": pilotage_cell,
            "traces": traces_cell,
            "progression": _progression_cell(lines_for_project),
        })

        if node["statut_doctrine"] in ("\u25cf FAIT", "\u25d0 EN COURS") and not lines_for_project:
            drift_items.append(_drift(
                f"la doctrine D\u00e9tail H d\u00e9clare '{name}' au statut "
                f"'{node['statut_doctrine']}' mais aucun run Forge trac\u00e9 (lab/forge_runs/) "
                "ne correspond \u00e0 ce nom",
                {"path": schema_doc["path"], "line": node["ligne"]},
            ))

    for projet in projects:
        if projet in covered:
            continue
        lines_for_project = grouped[projet]
        lignes.append({
            "jeu": _cell(projet),
            "doctrine_curriculum": _cell(
                NOT_OBSERVABLE,
                why="aucun n\u0153ud de la doctrine D\u00e9tail H ne correspond \u00e0 ce nom de projet",
            ),
            "doctrine_pilotage": _cell(
                NOT_OBSERVABLE,
                why="aucune case de 'lecture B' ne correspond \u00e0 ce nom de projet",
            ),
            "traces": _cell([_trace_summary(l) for l in lines_for_project],
                             {"path": "c8_fleet", "field": "lignes[].projet"}),
            "progression": _progression_cell(lines_for_project),
        })
        drift_items.append(_drift(
            f"le projet '{projet}' porte {len(lines_for_project)} run(s) Forge trac\u00e9(s) "
            "mais n'appara\u00eet dans aucun n\u0153ud de la doctrine D\u00e9tail H "
            "(STUDIO_MASTER_SCHEMA.html)",
            [{"path": schema_doc["path"]}, {"path": f"lab/forge_runs/{projet}"}],
        ))

    return {"lignes": lignes, "drift_items": drift_items}


# --------------------------------------------------------------------------- #
# Section 2 — FORGE (chantiers)
# --------------------------------------------------------------------------- #

CHANTIER_TERMS: dict[str, list[str]] = {
    "Observer": ["Observer"],
    "Knowledge Runtime": ["Knowledge Runtime", "knowledge_base", "BIBLIOTH\u00c8QUE"],
    "World Scan": ["World Scan", "worldscan"],
    "Asset Forge": ["Asset Forge", "art bible", "artbible", "assets"],
    "Game Discovery": ["Game Discovery"],
}


def _search_terms(docs: list[dict[str, Any]], terms: list[str], max_hits: int = 4) -> list[dict[str, Any]]:
    hits: list[dict[str, Any]] = []
    for doc in docs:
        for term in terms:
            for m in re.finditer(re.escape(term), doc["text"], flags=re.IGNORECASE):
                lineno = doc["text"].count("\n", 0, m.start()) + 1
                line_text = doc["lines"][lineno - 1] if lineno - 1 < len(doc["lines"]) else ""
                hits.append({
                    "terme": term,
                    "doc": doc["path"],
                    "line": lineno,
                    "extrait": _strip_tags(line_text)[:220],
                })
                if len(hits) >= max_hits:
                    return hits
    return hits


def _doctrine_mentions_cell(label: str, terms: list[str], docs: list[dict[str, Any]]) -> dict[str, Any]:
    hits = _search_terms(docs, terms)
    if not hits:
        proches = ", ".join(f"'{t}'" for t in terms[1:]) or "aucun"
        return _cell(NOT_OBSERVABLE, why=(
            f"ni le nom exact '{label}' ni les termes proches test\u00e9s ({proches}) "
            "n'apparaissent dans les 2 documents doctrine"
        ))
    exact = any(h["terme"].lower() == label.lower() for h in hits)
    cell = _cell(hits, {"path": hits[0]["doc"], "line": hits[0]["line"]})
    cell["proof"] = SELF_DECLARED
    cell["note"] = (
        f"nom exact '{label}' trouv\u00e9 dans la doctrine" if exact else
        f"nom exact '{label}' absent des 2 documents ; rapprochement best-effort sur "
        "un terme proche (voir 'terme' par occurrence)"
    )
    return cell


def _mesure_observer(ctx: Any, result: dict[str, Any], events: list[dict[str, Any]]) -> dict[str, Any]:
    lessons_path = ctx.repo_root / "lab" / "reports" / "lessons.jsonl"
    value = {
        "result_recu": bool(result),
        "runs_reconstruits": len((result or {}).get("runs") or []),
        "evenements_recus": len(events or []),
        "lessons_jsonl_existe": ctx.exists(lessons_path),
    }
    return _cell(value, {
        "path": "result/events (arguments en m\u00e9moire de build_roadmap_views, pas un "
                "fichier lu par ctx)",
        "field": "n/a",
    })


def _mesure_knowledge_runtime(ctx: Any) -> dict[str, Any]:
    kb_root = ctx.repo_root / "knowledge_base"
    files = [p for p in ctx.iter_files(kb_root) if p.is_file()]
    if not files:
        return _cell(NOT_OBSERVABLE, why="knowledge_base/ est vide ou absent des racines lisibles")
    mtimes: list[float] = []
    for f in files:
        try:
            mtimes.append(f.stat().st_mtime)
        except OSError:
            continue
    catalog = ctx.read_json(kb_root / "catalog.json")
    entries = catalog.get("entries") if isinstance(catalog, dict) else None
    search_log_lines = list(ctx.read_jsonl(kb_root / "search_log.jsonl"))
    value = {
        "fichiers_knowledge_base": len(files),
        "derniere_ecriture_utc": _iso(max(mtimes)) if mtimes else NOT_OBSERVABLE,
        "catalog_entrees": len(entries) if isinstance(entries, list) else NOT_OBSERVABLE,
        "search_log_lignes": len(search_log_lines),
    }
    return _cell(value, {"path": ctx.rel(kb_root)})


def _mesure_world_scan(ctx: Any) -> dict[str, Any]:
    contract_path = ctx.repo_root / "scripts" / "forge" / "contracts" / "s2-worldscan.yaml"
    if not ctx.exists(contract_path):
        return _cell(NOT_OBSERVABLE, why="scripts/forge/contracts/s2-worldscan.yaml absent")
    contract_text = ctx.read_text(contract_path) or ""
    value = {
        "contrat_existe": True,
        "contrat_mtime_utc": _mtime_iso(ctx, contract_path),
        "contrat_lignes": len(contract_text.splitlines()),
    }
    return _cell(value, {"path": ctx.rel(contract_path)})


def _mesure_asset_forge(ctx: Any) -> dict[str, Any]:
    assets_root = ctx.repo_root / "knowledge_base" / "assets"
    files = [p for p in ctx.iter_files(assets_root) if p.is_file()]
    contract_path = ctx.repo_root / "scripts" / "forge" / "contracts" / "s2.5-artbible.yaml"
    contract_exists = ctx.exists(contract_path)
    if not files and not contract_exists:
        return _cell(NOT_OBSERVABLE, why=(
            "knowledge_base/assets/ est vide et scripts/forge/contracts/s2.5-artbible.yaml "
            "est absent"
        ))
    mtimes: list[float] = []
    for f in files:
        try:
            mtimes.append(f.stat().st_mtime)
        except OSError:
            continue
    value = {
        "fichiers_assets": len(files),
        "derniere_ecriture_utc": _iso(max(mtimes)) if mtimes else NOT_OBSERVABLE,
        "contrat_artbible_existe": contract_exists,
    }
    return _cell(value, {"path": ctx.rel(assets_root)})


def _mesure_game_discovery(_ctx: Any) -> dict[str, Any]:
    return _cell(NOT_OBSERVABLE, why=(
        "aucun contrat, script ou dossier du p\u00e9rim\u00e8tre lecture d'Observer ne porte le "
        "nom 'Game Discovery' ou un terme proche connu : aucun indice m\u00e9canique \u00e0 mesurer"
    ))


def _build_forge_section(
    ctx: Any,
    result: dict[str, Any],
    events: list[dict[str, Any]],
    docs: list[dict[str, Any]],
) -> dict[str, Any]:
    lignes: list[dict[str, Any]] = []
    drift_items: list[dict[str, Any]] = []

    mesures = {
        "Observer": lambda: _mesure_observer(ctx, result, events),
        "Knowledge Runtime": lambda: _mesure_knowledge_runtime(ctx),
        "World Scan": lambda: _mesure_world_scan(ctx),
        "Asset Forge": lambda: _mesure_asset_forge(ctx),
        "Game Discovery": lambda: _mesure_game_discovery(ctx),
    }

    for label, terms in CHANTIER_TERMS.items():
        doctrine_cell = _doctrine_mentions_cell(label, terms, docs)
        mesure_cell = mesures[label]()
        lignes.append({
            "chantier": _cell(label),
            "doctrine": doctrine_cell,
            "mesure": mesure_cell,
        })
        if doctrine_cell["v"] == NOT_OBSERVABLE and mesure_cell["v"] != NOT_OBSERVABLE:
            drift_items.append(_drift(
                f"le chantier '{label}' porte un indice m\u00e9canique mesurable mais son nom "
                "n'appara\u00eet dans aucun des deux documents doctrine",
                mesure_cell.get("src"),
            ))

    return {"lignes": lignes, "drift_items": drift_items}


# --------------------------------------------------------------------------- #
# Section 3 — INFRASTRUCTURE (doctrine seule, jamais de sonde reseau)
# --------------------------------------------------------------------------- #

INFRA_TERMS: dict[str, list[str]] = {
    "LM Studio": ["LM Studio", "LM_MODEL"],
    "Workers": ["worker"],
    "Qwen": ["Qwen"],
    "Claude": ["Claude"],
    "Playwright": ["Playwright"],
    "GitHub": ["GitHub"],
}

_INFRA_MESURE_WHY = (
    "aucune sonde d'infrastructure dans le p\u00e9rim\u00e8tre lecture d'Observer — les "
    "ports/services ne sont pas des fichiers"
)


def _build_infra_section(docs: list[dict[str, Any]]) -> dict[str, Any]:
    lignes: list[dict[str, Any]] = []
    for label, terms in INFRA_TERMS.items():
        doctrine_cell = _doctrine_mentions_cell(label, [label, *terms], docs)
        mesure_cell = _cell(NOT_OBSERVABLE, why=_INFRA_MESURE_WHY)
        lignes.append({
            "composant": _cell(label),
            "doctrine": doctrine_cell,
            "mesure": mesure_cell,
        })
    return {"lignes": lignes}


# --------------------------------------------------------------------------- #
# Section 4 — CABLAGE 7 AXES (decision Pierre FORGE_AUTONOMY_V2 n°3, axe
# `bloque` ajoute le 2026-08-03 — cf. correction ci-dessous)
#
# Confronte, pour chaque connecteur nomme par la doctrine (Detail K « Nomenclature
# C (flux memoire) » + case POOL DE BUILDERS), l'ARCHITECTURE ATTENDUE a la
# REALITE MESUREE sur 7 axes : `prevu` / `construit` / `cable` / `actif` /
# `bloque` / `consomme` / `preuve_disponible`, plus le drapeau
# `humangate_en_attente`. `bloque` distingue explicitement une capacite
# BLOQUEE (appelee, predicat de depot connu et non rempli, raison portee) d'une
# capacite simplement absente ou jamais appelee — cf. `CONNECTOR_PROBES`
# ci-dessous : c'est le correctif du faux negatif `propose_brick` cable=NON
# (mission de reparation 2026-08-03, Pierre). Etend le meme
# mecanisme de drift que la section 1 (jeux) et 2 (chantiers Forge) ci-dessus —
# meme `_cell`, meme `_drift`, meme fusion dans `result["drift"]` par
# `views.py`. Aucun nouveau format de sortie, aucun nouveau pipeline.
#
# Regle stricte (identique a la consigne Pierre) : un axe ne vaut OUI que si
# les axes precedents valent OUI. Un axe non mesurable ici (code source hors
# des racines lisibles d'Observer, ex. scripts/forge/*.py) porte NOT_OBSERVABLE
# et sa raison — jamais devine, jamais force a NON par defaut. Piege connu et
# evite ici : NE JAMAIS confondre un identifiant proche par coincidence
# lexicale (ex. le champ `strategy: "pool_retry"` de l'escalade de builders,
# observe dans forge_builder_runs.jsonl, N'EST PAS une preuve d'activite de
# `scripts/forge/pool.py` — recherche par IDENTIFIANT EXACT, jamais par
# sous-chaine large).
# --------------------------------------------------------------------------- #

DRIFT_TYPE_CABLAGE = "architecture_declaree_vs_realite_mesuree"

# Chemins d'artefact CONNUS (dans les racines lisibles d'Observer) pour les
# connecteurs qui en ont un. `None` = aucune correspondance de fichier connue
# depuis ce module -> l'axe `construit` restera NOT_OBSERVABLE ou sera mesure
# par recherche de nom de fichier (cf. `_mesure_construit`).
CONNECTOR_ARTIFACTS: dict[str, Optional[tuple[str, ...]]] = {
    "learning_curve": ("knowledge_base", "learning_curve.jsonl"),
    # Chemins EXACTS, ouverts a Observer depuis l'elargissement declare nº4
    # (sources.py, 2026-08-03 — deux fichiers exacts, jamais le dossier
    # lab/reports). Sans eux ces noeuds retombaient sur la recherche par nom
    # dans knowledge_base/ + lab/forge_evidence/, qui ne les contiennent pas :
    # d'ou un FAUX NON, et surtout deux lignes de la meme vue (le noeud
    # artefact et le noeud writer propose_bible_entry) jugeant le MEME fichier
    # differemment. Verifie par falsification : artefact absent -> NON,
    # artefact present -> OUI.
    "forge_bible_proposals": ("lab", "reports", "forge_bible_proposals.jsonl"),
    "forge_brick_proposals": ("lab", "reports", "forge_brick_proposals.jsonl"),
}

# Pour les connecteurs "writer" (cf. `CONNECTOR_KIND` ci-dessous) : le nom de
# l'artefact de SORTIE que la fonction est censee produire (declare par
# l'architecture — Detail K + studio_link.py DEFAULT_*_PROPOSALS), PAS le nom
# de la fonction elle-meme (aucun fichier ne s'appellera jamais
# "propose_brick.*"). Le chemin complet declare (lab/reports/forge_*_proposals.jsonl)
# vit hors des racines actuellement ouvertes a Observer (ALLOWED_ROOTS n'ouvre
# que lab/reports/error_journal/ et lab/reports/lessons.jsonl) : on ne peut
# donc pas le lire directement sans elargir ALLOWED_ROOTS (hors perimetre de
# cette correction). Seul le NOM de fichier sert de repere de recherche, dans
# les memes racines que tout autre connecteur "artefact" (knowledge_base/,
# lab/forge_evidence/) — meme mecanisme que `_search_filename`, aucune
# nouvelle racine de lecture.
CONNECTOR_OUTPUT_ARTIFACT_NAME: dict[str, str] = {
    "propose_brick": "forge_brick_proposals",
    "propose_bible_entry": "forge_bible_proposals",
}

# Nature du connecteur : "artefact" (fichier attendu — une recherche de nom de
# fichier absent EST une mesure valide de NON) vs "writer" (fonction/mecanisme
# nomme par la doctrine, dont le CODE vit dans scripts/forge/*.py — hors des
# racines lisibles d'Observer. Confondre les deux surclasse un "je ne sais pas"
# en faux NON : `propose_brick` et `propose_bible_entry` sont des fonctions,
# pas des fichiers ; chercher un FICHIER nomme ainsi et ne pas en trouver ne
# prouve RIEN sur leur existence en tant que code. Par defaut (absent de ce
# dict) : "artefact", le regime le plus proche de ce que Detail K decrit
# (fichiers de flux memoire).
CONNECTOR_KIND: dict[str, str] = {
    "propose_brick": "writer",
    "propose_bible_entry": "writer",
}

# Racines de recherche pour cable/actif/consomme — jamais les documents
# doctrine eux-memes (ce serait circulaire), jamais tests/ (hors racines
# lisibles d'Observer par construction : cf. sources.py ALLOWED_ROOTS).
_CABLAGE_SEARCH_ROOTS: tuple[tuple[str, ...], ...] = (
    ("knowledge_base",),
    ("lab", "forge_evidence"),
    ("scripts", "forge", "contracts"),
)
_CABLAGE_SEARCH_SUFFIXES = frozenset({".json", ".jsonl", ".yaml", ".yml", ".md", ".txt"})


def _drift_cablage(detail: str, source: Any, severity: str = "medium") -> dict[str, Any]:
    """Item de drift architecture-declaree-vs-mesuree — meme forme que `_drift`
    (fusionne par `views.py` dans la vue Drift unique, famille documentation,
    proprietaire DOCTRINE, action CORRIGER)."""
    return {
        "type": DRIFT_TYPE_CABLAGE,
        "severity": severity,
        "famille": "documentation",
        "owner": "DOCTRINE",
        "action": "CORRIGER",
        "detail": detail,
        "source": source,
    }


def _extract_nomenclature_c(doc: dict[str, Any]) -> list[dict[str, Any]]:
    """Extrait les connecteurs nommes <code>...</code> de la bulle « Nomenclature C
    (flux memoire) » de Detail K, avec leur statut doctrine textuel (best-effort :
    decoupage sur le <code> suivant, jamais un format stable)."""
    text = doc["text"]
    start = text.find("Nomenclature C (flux")
    if start == -1:
        return []
    end = text.find("<br>", start)
    if end == -1:
        end = min(len(text), start + 900)
    block = text[start:end]
    base_line = text.count("\n", 0, start)

    items: list[dict[str, Any]] = []
    matches = list(_CODE_RE.finditer(block))
    for i, m in enumerate(matches):
        name = m.group(1).strip()
        seg_end = matches[i + 1].start() if i + 1 < len(matches) else len(block)
        segment = block[m.end():seg_end]
        segment = segment.strip().strip("·").strip()
        statut = _strip_tags(segment).strip() or NOT_OBSERVABLE
        lineno = base_line + block.count("\n", 0, m.start()) + 1
        items.append({"nom": name, "statut_doctrine": statut, "ligne": lineno})
    return items


_CODE_RE = re.compile(r"<code>([^<]+)</code>")


def _extract_pool_doctrine(doc: dict[str, Any]) -> Optional[dict[str, Any]]:
    """Extrait les deux annotations doctrine de la case « POOL DE BUILDERS »
    (Detail F) : 'pool.py construit (...)' et, si presente a proximite,
    'jamais declenche — condition jamais vraie'. Best-effort, meme regime que
    le reste de ce module : decoupage de <text>...</text> SVG, pas un format
    stable."""
    text = doc["text"]
    idx = text.find("pool.py construit")
    if idx == -1:
        return None

    def _enclosing_text(pos: int) -> tuple[str, int]:
        line_start = text.rfind("<text", 0, pos)
        if line_start == -1:
            return NOT_OBSERVABLE, text.count("\n", 0, pos) + 1
        m = _TEXT_CONTENT_RE.match(text, line_start)
        content = _strip_tags(m.group(1)) if m else NOT_OBSERVABLE
        return content, text.count("\n", 0, line_start) + 1

    construit_texte, construit_ligne = _enclosing_text(idx)

    idx2 = text.find("jamais déclenché", idx)
    actif_texte, actif_ligne = NOT_OBSERVABLE, None
    if idx2 != -1 and idx2 - idx < 500:
        actif_texte, actif_ligne = _enclosing_text(idx2)

    return {
        "nom": "pool.py",
        "construit_doctrine": construit_texte,
        "construit_ligne": construit_ligne,
        "actif_doctrine": actif_texte,
        "actif_ligne": actif_ligne,
    }


def _search_identifier(ctx: Any, nom: str) -> Optional[dict[str, Any]]:
    """Recherche un identifiant EXACT (frontieres de mot) dans les racines de
    cablage, hors documents doctrine et hors tests/ (structurellement hors des
    racines lisibles d'Observer). Retourne la 1re citation trouvee ou None —
    jamais une correlation devinee."""
    pattern = re.compile(r"\b" + re.escape(nom) + r"\b")
    for parts in _CABLAGE_SEARCH_ROOTS:
        root = ctx.repo_root.joinpath(*parts)
        for path in ctx.iter_files(root, "*"):
            if not path.is_file() or path.suffix.lower() not in _CABLAGE_SEARCH_SUFFIXES:
                continue
            text = ctx.read_text(path)
            if not text or not pattern.search(text):
                continue
            lineno = next(
                (n for n, l in enumerate(text.splitlines(), 1) if pattern.search(l)),
                None,
            )
            return {"path": ctx.rel(path), "line": lineno}
    return None


def _search_filename(ctx: Any, nom: str) -> Optional[dict[str, Any]]:
    """Cherche un FICHIER dont le nom contient l'identifiant, dans knowledge_base/
    et lab/forge_evidence/ (racines lisibles). Sert a mesurer `construit` pour un
    connecteur dont on ne connait pas le chemin exact a l'avance."""
    for parts in (("knowledge_base",), ("lab", "forge_evidence")):
        root = ctx.repo_root.joinpath(*parts)
        for path in ctx.iter_files(root, "*"):
            if path.is_file() and nom.lower() in path.name.lower():
                return {"path": ctx.rel(path)}
    return None


def _humangate_en_attente(ctx: Any, nom: str) -> dict[str, Any]:
    """`humangate_en_attente` : l'identifiant est-il mentionne dans le registre
    de decisions (studio_brain/decisions/decision-log.md ou DEFERRED.md) —
    racines deja declarees dans sources.py. Absence de mention = NON mesure
    (pas NOT_OBSERVABLE : le registre EST lisible, l'absence est une mesure)."""
    for rel in (("studio_brain", "decisions", "decision-log.md"),
                ("studio_brain", "decisions", "DEFERRED.md")):
        path = ctx.repo_root.joinpath(*rel)
        text = ctx.read_text(path)
        if text is None:
            continue
        idx = text.find(nom)
        if idx != -1:
            lineno = text.count("\n", 0, idx) + 1
            return _cell("OUI", {"path": ctx.rel(path), "line": lineno})
    return _cell("NON")


# --------------------------------------------------------------------------- #
# Axe BLOQUE (decision Pierre 2026-08-03) — un connecteur "writer" dont le CODE
# vit hors des racines lisibles d'Observer (scripts/forge/*.py) peut neanmoins
# etre juge APPELE (le pas driver qui le contient a tourne, cf. `state.json`)
# et son PREDICAT DE DEPOT peut etre mesure depuis des artefacts d'EXECUTION
# deja lisibles (verdict.json signe, wiremap fige du run) — jamais en lisant le
# code. Distingue 4 situations au lieu d'ecraser tout en NON/NOT_OBSERVABLE :
#
#   JAMAIS_APPELE       — le pas driver qui contient l'appel n'a pas ete
#                          atteint (absent de state.json) OU un retour anticipe
#                          DOCUMENTE precede l'appel dans ce meme pas.
#   BLOQUE              — le pas a ete atteint ET l'appel a bien ete traverse,
#                          mais son PREDICAT DE DEPOT (condition connue et
#                          documentee dans driver.py) n'est pas rempli — la
#                          raison est portee, jamais une supposition.
#   PREDICAT_SATISFAIT  — le predicat est rempli : un artefact est attendu. Si
#                          `_search_filename`/le chemin exact ne le trouve pas
#                          malgre tout, c'est alors APPELE_SANS_SORTIE (cf.
#                          `_six_axes_artefact`), pas BLOQUE.
#
# Piege evite : NE JAMAIS confondre "aucun artefact trouve" avec "jamais
# appele" — c'est exactement le faux negatif corrige ici (propose_brick,
# cf. driver.py:1984 `self._propose_bricks(record)` + driver.py:2023-2026
# `if code_status != "OK": return`).
# --------------------------------------------------------------------------- #

ETAT_JAMAIS_APPELE = "JAMAIS_APPELE"
ETAT_BLOQUE = "BLOQUE"
ETAT_PREDICAT_SATISFAIT = "PREDICAT_SATISFAIT"


def _read_run_state(ctx: Any) -> Optional[dict[str, Any]]:
    """`lab/forge_runs/<project>/state.json` — deja dans les racines lisibles
    d'Observer (`run_dir`), aucune racine nouvelle."""
    return ctx.read_json(ctx.run_dir / "state.json")


def _read_run_verdict(ctx: Any) -> Optional[dict[str, Any]]:
    """`lab/forge_runs/<project>/verdict.json` — le reçu SIGNÉ (deja dans
    `run_dir`), pas le code qui l'a produit. Porte `oracles.code.status`,
    authentique par construction (ecrit par `_run_verdict` puis re-verifie par
    `verify_run` AVANT l'appel a `propose_brick` — cf. driver.py:1943-1991)."""
    return ctx.read_json(ctx.run_dir / "verdict.json")


def _read_run_wiremap(ctx: Any) -> Optional[dict[str, Any]]:
    """Wiremap du run — prefere l'instantane fige sous `run_dir` (ecrit par le
    meme pas qui appelle `propose_bible_entry`), replie sur la copie vivante
    sous `games/<project>/09_WIREMAP/` (deja dans `allowed_roots`, cf.
    `ctx.game_dir`) si l'instantane n'existe pas."""
    doc = ctx.read_json(ctx.run_dir / "wiremap.json")
    if isinstance(doc, dict):
        return doc
    return ctx.read_json(ctx.game_dir / "09_WIREMAP" / "wiremap.json")


def _probe_propose_brick(ctx: Any) -> dict[str, Any]:
    """Etat d'execution de `studio_link.propose_brick`, appele par
    `driver.py._propose_bricks` UNIQUEMENT depuis `_run_verdict`, apres
    l'ecriture + re-verification (`verify_run`) du verdict signe (driver.py
    l.1943-1991) — le pas `s12-verdict` ne finit `status="OK"` qu'APRES cet
    appel (un `verify_run` bloquant renvoie `BLOCKED` et sort AVANT l'appel,
    driver.py l.1978-1984). PREDICAT DE DEPOT (driver.py l.2023-2026) :
    `record["oracles"]["code"]["status"] == "OK"`."""
    state = _read_run_state(ctx)
    steps = (state or {}).get("steps") if isinstance(state, dict) else None
    step = steps.get("s12-verdict") if isinstance(steps, dict) else None
    state_src = {"path": ctx.rel(ctx.run_dir / "state.json"), "field": "steps.s12-verdict"}

    if not isinstance(step, dict) or "status" not in step:
        return {
            "etat": ETAT_JAMAIS_APPELE,
            "raison": "aucune entree 's12-verdict' dans state.json de ce run — "
                      "le pas qui contient l'appel n'a jamais tourne",
            "src": state_src,
        }

    status = step.get("status")
    if status != "OK":
        detail = step.get("detail") if isinstance(step.get("detail"), dict) else {}
        motif = detail.get("reason")
        return {
            "etat": ETAT_JAMAIS_APPELE,
            "raison": (
                f"pas 's12-verdict' termine status={status!r} : le seul chemin de "
                "driver.py._run_verdict qui appelle propose_brick est celui qui "
                "finit status=='OK' (un verify_run bloquant renvoie BLOCKED et "
                "retourne AVANT l'appel, driver.py l.1978-1984)"
                + (f" ; motif du pas : {motif}" if motif else "")
            ),
            "src": state_src,
        }

    verdict = _read_run_verdict(ctx)
    verdict_src = {"path": ctx.rel(ctx.run_dir / "verdict.json"), "field": "oracles.code.status"}
    if not isinstance(verdict, dict):
        return {
            "etat": NOT_OBSERVABLE,
            "raison": "pas 's12-verdict' status=='OK' (l'appel a donc eu lieu) mais "
                      "verdict.json est illisible ou absent — predicat de depot non "
                      "mesurable depuis ce fichier",
            "src": state_src,
        }
    code_status = ((verdict.get("oracles") or {}).get("code") or {}).get("status")
    if code_status != "OK":
        return {
            "etat": ETAT_BLOQUE,
            "raison": (
                f"predicat de depot (driver.py._propose_bricks, l.2024-2026) exige "
                f"oracles.code.status=='OK' ; mesure sur ce run = {code_status!r}"
            ),
            "src": verdict_src,
        }
    return {
        "etat": ETAT_PREDICAT_SATISFAIT,
        "raison": f"oracles.code.status=='OK' mesure sur ce run : le predicat de depot est rempli",
        "src": verdict_src,
    }


def _probe_propose_bible_entry(ctx: Any) -> dict[str, Any]:
    """Etat d'execution de `studio_link.propose_bible_entry`, appele par
    `driver.py._propose_bible_entries` depuis `_run_standard_oracle`
    (pas `s10s-oracle-standard`), INCONDITIONNELLEMENT sauf si une entree
    requise (contrat/wiremap/standard) est absente — auquel cas le pas finit
    `BLOCKED` avec un detail `missing` AVANT d'atteindre l'appel (driver.py
    l.1688-1703, appel l.1759). PREDICAT DE DEPOT (driver.py l.1893-1912) :
    au moins un item de `wiremap["discarded"]` avec un `discard_reason` texte
    non vide."""
    state = _read_run_state(ctx)
    steps = (state or {}).get("steps") if isinstance(state, dict) else None
    step = steps.get("s10s-oracle-standard") if isinstance(steps, dict) else None
    state_src = {"path": ctx.rel(ctx.run_dir / "state.json"), "field": "steps.s10s-oracle-standard"}

    if not isinstance(step, dict) or "status" not in step:
        return {
            "etat": ETAT_JAMAIS_APPELE,
            "raison": "aucune entree 's10s-oracle-standard' dans state.json de ce "
                      "run — le pas qui contient l'appel n'a jamais tourne",
            "src": state_src,
        }

    detail = step.get("detail") if isinstance(step.get("detail"), dict) else {}
    if "missing" in detail:
        return {
            "etat": ETAT_JAMAIS_APPELE,
            "raison": (
                "pas 's10s-oracle-standard' bloque AVANT l'appel : entree(s) "
                f"requise(s) absente(s) ({detail.get('missing')}) — driver.py "
                "l.1688-1703 retourne BLOCKED avant d'atteindre "
                "_propose_bible_entries (l.1759)"
            ),
            "src": state_src,
        }

    wiremap = _read_run_wiremap(ctx)
    wiremap_src = {
        "path": ctx.rel(ctx.run_dir / "wiremap.json") if ctx.exists(ctx.run_dir / "wiremap.json")
        else ctx.rel(ctx.game_dir / "09_WIREMAP" / "wiremap.json"),
        "field": "discarded",
    }
    if not isinstance(wiremap, dict):
        return {
            "etat": NOT_OBSERVABLE,
            "raison": "pas 's10s-oracle-standard' atteint (l'appel a donc eu lieu) "
                      "mais aucun wiremap lisible pour ce run — predicat de depot "
                      "non mesurable",
            "src": state_src,
        }
    discarded = wiremap.get("discarded")
    valides = [
        item for item in discarded
        if isinstance(item, dict) and isinstance(item.get("discard_reason"), str)
        and item.get("discard_reason").strip()
    ] if isinstance(discarded, list) else []
    if not valides:
        return {
            "etat": ETAT_BLOQUE,
            "raison": (
                "predicat de depot (driver.py._propose_bible_entries, l.1893-1904) "
                "exige au moins un item de wiremap['discarded'] avec discard_reason "
                "non vide ; mesure sur ce run = "
                + ("absent" if discarded is None else f"present mais 0/{len(discarded)} valide(s)")
            ),
            "src": wiremap_src,
        }
    return {
        "etat": ETAT_PREDICAT_SATISFAIT,
        "raison": f"{len(valides)} item(s) discarded valide(s) (discard_reason non vide) mesure(s)",
        "src": wiremap_src,
    }


CONNECTOR_PROBES: dict[str, Any] = {
    "propose_brick": _probe_propose_brick,
    "propose_bible_entry": _probe_propose_bible_entry,
}


def _bloque_cell(probe: Optional[dict[str, Any]]) -> dict[str, Any]:
    """Cellule de l'axe `bloque` (7e axe, decision Pierre 2026-08-03) — jamais
    devinee : `NOT_OBSERVABLE` explicite quand aucune sonde n'existe pour ce
    connecteur, `OUI` avec sa raison quand la sonde mesure un predicat non
    rempli, `NON` sinon (jamais appele, predicat rempli, ou artefact deja la)."""
    if probe is None:
        return _cell(NOT_OBSERVABLE, why=(
            "aucune sonde de predicat connue pour ce connecteur — cf. "
            "CONNECTOR_PROBES ; ne pas deviner un blocage"
        ))
    if probe["etat"] == ETAT_BLOQUE:
        cell = _cell("OUI", probe.get("src"))
        cell["note"] = probe["raison"]
        return cell
    cell = _cell("NON", probe.get("src"))
    cell["note"] = probe["raison"]
    return cell


def _six_axes_artefact(
    ctx: Any, nom: str, doctrine_status: str, doctrine_src: dict[str, Any],
) -> dict[str, Any]:
    """Calcule les 7 axes (prevu/construit/cable/actif/bloque/consomme/preuve)
    pour un connecteur mesurable par existence de fichier (construit) puis par
    recherche d'identifiant exact (cable/actif/consomme). Monotone : un axe
    negatif ou NOT_OBSERVABLE en amont ne produit jamais un OUI en aval."""
    doctrine_cell = _cell(doctrine_status, doctrine_src)
    doctrine_cell["proof"] = SELF_DECLARED

    if CONNECTOR_KIND.get(nom, "artefact") == "writer":
        # Fonction/mecanisme nomme par la doctrine : son CODE vit dans
        # scripts/forge/*.py, hors des racines lisibles d'Observer — mais
        # l'ABSENCE de son code ici n'est pas l'absence de la FONCTION. Regle
        # (directive Pierre 2026-08-03) : `construit` est juge par ce que
        # l'architecture DECLARE (Detail K la nomme explicitement), pas par
        # une lecture de fichier impossible ici. Un axe non mesurable ne doit
        # jamais faire retomber TOUTE la ligne en NOT_OBSERVABLE : cable/actif/
        # consomme sont mesures via la trace d'execution observable — la
        # presence ou l'absence de l'artefact de SORTIE declare, cherche par
        # NOM DE FICHIER exact dans les racines de cablage deja ouvertes.
        construit = _cell("OUI", doctrine_src)
        construit["proof"] = SELF_DECLARED
        construit["note"] = (
            f"'{nom}' est une fonction nommee et declaree par l'architecture "
            "(Detail K, Nomenclature C) — son code vit dans scripts/forge/*.py, "
            "hors des racines lisibles d'Observer, mais l'absence du code "
            "source ici n'est pas l'absence de la fonction : jugee construite "
            "par declaration, jamais par lecture de fichier"
        )

        artefact_name = CONNECTOR_OUTPUT_ARTIFACT_NAME.get(nom)
        if artefact_name is None:
            why = (
                f"aucun nom d'artefact de sortie connu pour '{nom}' — rien a "
                "chercher sans deviner"
            )
            cable = _cell(NOT_OBSERVABLE, why=why)
            actif = _cell(NOT_OBSERVABLE, why="axe precedent (cable) non observable")
            consomme = _cell(NOT_OBSERVABLE, why="axe precedent (actif) non observable")
        else:
            # Chemin EXACT declare par l'architecture. Ouvert a Observer depuis
            # l'elargissement declare nº4 (sources.py, 2026-08-03) : deux fichiers
            # exacts, jamais le dossier lab/reports. Ce sont des artefacts
            # d'EXECUTION (files de propositions ecrites par un run), pas du code
            # source — la cecite sur scripts/forge/*.py et sur docs/ est intacte.
            # Avant cet elargissement, la recherche se faisait par nom de fichier
            # dans knowledge_base/ + lab/forge_evidence/, qui ne contiennent PAS
            # ces artefacts : la reponse etait juste par coincidence (ils
            # n'existaient nulle part) et serait devenue un FAUX NON des qu'un run
            # reel en aurait ecrit un.
            exact = ctx.repo_root / "lab" / "reports" / f"{artefact_name}.jsonl"
            hit = ({"path": ctx.rel(exact)} if ctx.exists(exact)
                   else _search_filename(ctx, artefact_name))
            probe = CONNECTOR_PROBES.get(nom, lambda _ctx: None)(ctx)
            if hit is None:
                # AVANT : "aucun artefact => cable=NON", que la capacite ait ete
                # appelee ou non — le faux negatif corrige ici (propose_brick
                # bloque par son predicat de depot ressortait identique a un
                # connecteur jamais appele). La sonde d'execution (state.json +
                # verdict.json/wiremap du run, jamais scripts/forge/*.py)
                # distingue les 3 etats reels : JAMAIS_APPELE / BLOQUE /
                # PREDICAT_SATISFAIT-mais-artefact-absent (anomalie honnete).
                etat = probe["etat"] if probe else None
                if etat == ETAT_BLOQUE:
                    cable = _cell(ETAT_BLOQUE, probe.get("src"))
                    cable["note"] = probe["raison"]
                    actif = _cell(ETAT_BLOQUE, probe.get("src"))
                    actif["note"] = "axe precedent (cable) BLOQUE : " + probe["raison"]
                    consomme = _cell("NON")
                    consomme["note"] = "axe precedent (actif) BLOQUE : rien a consommer"
                elif etat == ETAT_PREDICAT_SATISFAIT:
                    cable = _cell("APPELE_SANS_SORTIE", probe.get("src"))
                    cable["note"] = (
                        "anomalie mesuree : le predicat de depot est rempli "
                        f"({probe['raison']}) mais {ctx.rel(exact)} reste absent du "
                        "disque et aucun fichier de ce nom n'existe dans "
                        "knowledge_base/ ni lab/forge_evidence/ — appele, predicat "
                        "rempli, aucune sortie produite"
                    )
                    actif = _cell("NON")
                    actif["note"] = "axe precedent (cable) APPELE_SANS_SORTIE : aucun artefact a activer"
                    consomme = _cell("NON")
                    consomme["note"] = "axe precedent (actif) negatif : rien a consommer"
                elif etat == ETAT_JAMAIS_APPELE:
                    cable = _cell(ETAT_JAMAIS_APPELE, probe.get("src"))
                    cable["note"] = probe["raison"]
                    actif = _cell(ETAT_JAMAIS_APPELE, probe.get("src"))
                    actif["note"] = "axe precedent (cable) JAMAIS_APPELE : " + probe["raison"]
                    consomme = _cell("NON")
                    consomme["note"] = "axe precedent (actif) JAMAIS_APPELE : rien a consommer"
                else:
                    # Aucune sonde connue pour ce connecteur (ou sonde
                    # NOT_OBSERVABLE) : comportement inchange, jamais devine.
                    cable = _cell("NON")
                    cable["note"] = (
                        f"jamais peuple par un run reel : {ctx.rel(exact)} absent du "
                        "disque (chemin exact declare par l'architecture, verifie "
                        "directement), et aucun fichier de ce nom dans knowledge_base/ "
                        "ni lab/forge_evidence/ — absence mesuree, pas une supposition"
                    )
                    if probe is not None:
                        cable["note"] += f" ; sonde d'execution : {probe['raison']}"
                    actif = _cell("NON")
                    actif["note"] = "axe precedent (cable) negatif : jamais peuple par un run reel"
                    consomme = _cell("NON")
                    consomme["note"] = "axe precedent (actif) negatif : rien a consommer"
            else:
                cable = _cell("OUI", hit)
                artefact_path = ctx.repo_root.joinpath(*hit["path"].split("/"))
                if artefact_path.suffix == ".jsonl":
                    n_lignes = sum(1 for _ in ctx.read_jsonl(artefact_path))
                    if n_lignes >= 1:
                        actif = _cell("OUI", hit)
                        actif["note"] = f"{n_lignes} entree(s) reelle(s) dans l'artefact"
                    else:
                        actif = _cell("NON")
                        actif["note"] = "artefact trouve mais vide — jamais peuple par un run reel"
                else:
                    actif = _cell(NOT_OBSERVABLE, why=(
                        "artefact present, non-jsonl : aucune mesure de contenu "
                        "implementee ici"
                    ))

                if actif["v"] == "OUI":
                    consomme = _cell(NOT_OBSERVABLE, why=(
                        f"aucun lecteur distinct de '{artefact_name}' trouve dans "
                        "les racines de cablage (knowledge_base/, "
                        "lab/forge_evidence/, scripts/forge/contracts/) au-dela "
                        "de sa propre presence"
                    ))
                else:
                    consomme = _cell("NON")
                    consomme["note"] = "axe precedent (actif) non confirme"

        return {
            "connecteur": _cell(nom),
            "prevu": _cell("OUI", doctrine_src),
            "doctrine": doctrine_cell,
            "construit": construit,
            "cable": cable,
            "actif": actif,
            "bloque": _bloque_cell(probe if artefact_name is not None else None),
            "consomme": consomme,
            "preuve_disponible": _cell(NOT_OBSERVABLE, why=(
                "aucun recu d'oracle ne couvre le cablage de ce connecteur specifiquement"
            )),
            "humangate_en_attente": _humangate_en_attente(ctx, nom),
        }

    fixed_path = CONNECTOR_ARTIFACTS.get(nom)
    if fixed_path is not None:
        path = ctx.repo_root.joinpath(*fixed_path)
        if ctx.exists(path):
            construit = _cell("OUI", {"path": ctx.rel(path)})
        else:
            construit = _cell("NON", {"path": ctx.rel(path)})
    else:
        hit = _search_filename(ctx, nom)
        if hit:
            construit = _cell("OUI", hit)
        else:
            construit = _cell(
                "NON", {"path": "knowledge_base/, lab/forge_evidence/"},
            )
            construit["note"] = (
                f"aucun fichier dont le nom contient '{nom}' dans knowledge_base/ "
                "ni lab/forge_evidence/ (racines lisibles) — absence mesuree, "
                "pas une supposition"
            )

    if construit["v"] != "OUI":
        cable = _cell("NON", why=(
            "axe precedent (construit) negatif : aucun appel ne peut produire "
            "un artefact absent"
        ))
        actif = _cell("NON", why="axe precedent (cable) negatif")
        consomme = _cell("NON", why="axe precedent (actif) negatif : rien a consommer")
    else:
        hit = _search_identifier(ctx, nom)
        if hit:
            cable = _cell("OUI", hit)
        else:
            cable = _cell(NOT_OBSERVABLE, why=(
                f"identifiant '{nom}' introuvable (hors documents doctrine) dans "
                "knowledge_base/, lab/forge_evidence/, scripts/forge/contracts/ "
                "— le code appelant (scripts/forge/*.py) est hors des racines "
                "lisibles d'Observer"
            ))

        if fixed_path is not None:
            path = ctx.repo_root.joinpath(*fixed_path)
            n_lignes = sum(1 for _ in ctx.read_jsonl(path)) if path.suffix == ".jsonl" else None
            if n_lignes is not None and n_lignes >= 2:
                actif = _cell("OUI", {"path": ctx.rel(path)}, )
                actif["note"] = f"{n_lignes} entrees reelles horodatees dans l'artefact"
            elif n_lignes is not None:
                actif = _cell(NOT_OBSERVABLE, why=(
                    f"artefact present mais {n_lignes} entree(s) seulement — "
                    "insuffisant pour distinguer un usage reel repete d'un seed manuel"
                ))
            else:
                actif = _cell(NOT_OBSERVABLE, why="artefact present, non-jsonl : "
                              "aucune mesure de repetition d'usage implementee ici")
        else:
            actif = _cell(NOT_OBSERVABLE, why=(
                "artefact trouve par nom mais aucune mesure de repetition "
                "d'usage implementee pour ce connecteur"
            ))

        if actif["v"] == "OUI":
            # `cable` a deja consomme la 1re occurrence (le producteur lui-meme,
            # generalement le README/doctrine du connecteur) : un lecteur DISTINCT
            # exigerait une 2e citation dans un fichier different. On ne pretend
            # pas ici distinguer producteur/consommateur au-dela de cette
            # premiere citation — limite dite explicitement.
            consomme = _cell(NOT_OBSERVABLE, why=(
                f"aucun lecteur distinct de '{nom}' trouve dans les racines de "
                "cablage (knowledge_base/, lab/forge_evidence/, "
                "scripts/forge/contracts/) au-dela de sa propre documentation"
            ))
        else:
            consomme = _cell("NON", why="axe precedent (actif) non confirme")

    preuve = _cell(NOT_OBSERVABLE, why=(
        "aucun recu d'oracle (test.result/mutation.result/verdict.signed) ne "
        "couvre le cablage de ce connecteur specifiquement"
    ))

    return {
        "connecteur": _cell(nom),
        "prevu": _cell("OUI", doctrine_src),
        "doctrine": doctrine_cell,
        "construit": construit,
        "cable": cable,
        "actif": actif,
        "bloque": _cell(NOT_OBSERVABLE, why=(
            "aucune sonde de predicat de depot connue pour ce connecteur de type "
            "'artefact' (CONNECTOR_PROBES ne couvre que les connecteurs 'writer' "
            "propose_brick/propose_bible_entry) — ne pas deviner un blocage"
        )),
        "consomme": consomme,
        "preuve_disponible": preuve,
        "humangate_en_attente": _humangate_en_attente(ctx, nom),
    }


def _six_axes_pool(ctx: Any, pool_doc: dict[str, Any]) -> dict[str, Any]:
    """Cas particulier `pool.py` : code source hors des racines lisibles
    d'Observer (scripts/forge/ n'est ouvert qu'a contracts/) — `construit` et
    `actif` sont donc rendus tels que la doctrine elle-meme les DECLARE
    (SELF_DECLARED, cites), jamais mesures mecaniquement. Piege evite : ne
    JAMAIS chercher 'pool_retry' comme preuve d'activite — c'est le nom de la
    strategie d'ESCALADE de builders (`forge_builder_runs.jsonl`), un
    homonyme sans rapport avec `scripts/forge/pool.py`."""
    construit = _cell("OUI", {
        "path": pool_doc["src_path"], "line": pool_doc["construit_ligne"],
    })
    construit["proof"] = SELF_DECLARED
    construit["note"] = (
        f"doctrine uniquement ({pool_doc['construit_doctrine']!r}) — "
        "scripts/forge/pool.py hors des racines lisibles d'Observer : "
        "l'existence du fichier n'est pas verifiee mecaniquement ici"
    )

    if pool_doc["actif_ligne"] is not None:
        actif = _cell("NON", {"path": pool_doc["src_path"], "line": pool_doc["actif_ligne"]})
        actif["proof"] = SELF_DECLARED
        actif["note"] = f"doctrine : {pool_doc['actif_doctrine']!r}"
    else:
        actif = _cell(NOT_OBSERVABLE, why="aucune annotation d'activite trouvee a proximite dans la doctrine")

    cable = _cell(NOT_OBSERVABLE, why=(
        "le code appelant (scripts/forge/driver.py ou equivalent) est hors des "
        "racines lisibles d'Observer ; aucune mention distincte du cablage de "
        "pool.py, separee de son activation, n'existe dans les deux documents "
        "doctrine"
    ))
    consomme = _cell("NON", why="axe precedent (actif) negatif : rien a consommer") \
        if actif["v"] == "NON" else _cell(NOT_OBSERVABLE, why="axe precedent (actif) non confirme")
    preuve = _cell(NOT_OBSERVABLE, why="aucun recu d'oracle ne couvre le cablage de pool.py")

    # `bloque` (7e axe) : la doctrine ELLE-MEME nomme une condition de blocage
    # ("jamais declenche — condition jamais vraie", pool_doc["actif_doctrine"])
    # quand `actif_ligne` a ete trouve a proximite du marqueur "pool.py
    # construit" — SELF_DECLARED, jamais mesure mecaniquement (meme limite que
    # `construit`/`actif` ci-dessus, code hors des racines lisibles d'Observer).
    if pool_doc["actif_ligne"] is not None:
        bloque = _cell("OUI", {"path": pool_doc["src_path"], "line": pool_doc["actif_ligne"]})
        bloque["proof"] = SELF_DECLARED
        bloque["note"] = f"doctrine : {pool_doc['actif_doctrine']!r}"
    else:
        bloque = _cell(NOT_OBSERVABLE, why="aucune annotation de blocage trouvee a proximite dans la doctrine")

    return {
        "connecteur": _cell("pool.py"),
        "prevu": _cell("OUI", {"path": pool_doc["src_path"], "line": pool_doc["construit_ligne"]}),
        "doctrine": _cell(pool_doc["construit_doctrine"] + " / " + str(pool_doc["actif_doctrine"])),
        "construit": construit,
        "cable": cable,
        "actif": actif,
        "bloque": bloque,
        "consomme": consomme,
        "preuve_disponible": preuve,
        "humangate_en_attente": _humangate_en_attente(ctx, "pool.py"),
    }


def _build_cablage_section(
    ctx: Any, schema_doc: Optional[dict[str, Any]],
) -> dict[str, Any]:
    """Section 4 : `s2_roadmap.cablage` — 7 axes par connecteur declare par
    Detail K. Retourne {"lignes": [...], "drift_items": [...]}."""
    if schema_doc is None:
        return {
            "lignes": [{
                "connecteur": _cell(NOT_OBSERVABLE, why="STUDIO_MASTER_SCHEMA.html illisible ou absent"),
            }],
            "drift_items": [],
        }

    lignes: list[dict[str, Any]] = []
    drift_items: list[dict[str, Any]] = []

    nomenclature = _extract_nomenclature_c(schema_doc)
    if not nomenclature:
        drift_items.append(_drift_cablage(
            "le marqueur 'Nomenclature C (flux memoire)' est introuvable dans "
            "STUDIO_MASTER_SCHEMA.html : la section a peut-etre ete renommee ou deplacee",
            {"path": schema_doc["path"]},
            severity="high",
        ))

    for node in nomenclature:
        src = {"path": schema_doc["path"], "line": node["ligne"]}
        ligne = _six_axes_artefact(ctx, node["nom"], node["statut_doctrine"], src)
        lignes.append(ligne)
        axes = ("construit", "cable", "actif", "consomme")
        # Etats negatifs : "NON" (mesure directe) et les 3 valeurs de l'axe
        # BLOQUE/JAMAIS_APPELE/APPELE_SANS_SORTIE (cf. CONNECTOR_PROBES) —
        # toutes signalent une capacite qui NE PRODUIT PAS ce qu'elle promet,
        # meme quand ce n'est plus le litteral "NON" depuis la correction du
        # faux negatif propose_brick (2026-08-03).
        _AXE_NEGATIF = {"NON", ETAT_BLOQUE, ETAT_JAMAIS_APPELE, "APPELE_SANS_SORTIE"}
        non_axes = [a for a in axes if ligne[a]["v"] in _AXE_NEGATIF]
        if non_axes:
            drift_items.append(_drift_cablage(
                f"connecteur '{node['nom']}' (doctrine : {node['statut_doctrine']!r}, "
                f"Detail K) — axes negatifs mesures : {', '.join(non_axes)}",
                src,
                severity="high" if len(non_axes) >= 3 else "medium",
            ))

    pool_doc = _extract_pool_doctrine(schema_doc)
    if pool_doc is not None:
        pool_doc["src_path"] = schema_doc["path"]
        ligne = _six_axes_pool(ctx, pool_doc)
        lignes.append(ligne)
        if ligne["actif"]["v"] == "NON":
            drift_items.append(_drift_cablage(
                "connecteur 'pool.py' declare construit (doctrine, Detail F) mais "
                f"jamais actif : {pool_doc['actif_doctrine']!r}",
                {"path": schema_doc["path"], "line": pool_doc["construit_ligne"]},
                severity="medium",
            ))
    else:
        drift_items.append(_drift_cablage(
            "le marqueur 'pool.py construit' est introuvable dans "
            "STUDIO_MASTER_SCHEMA.html : la case POOL DE BUILDERS a peut-etre "
            "ete renommee ou deplacee",
            {"path": schema_doc["path"]},
            severity="high",
        ))

    return {"lignes": lignes, "drift_items": drift_items}


# --------------------------------------------------------------------------- #
# Fraicheur doctrine
# --------------------------------------------------------------------------- #


def _fraicheur_doctrine(schema_doc: Optional[dict[str, Any]],
                        pilotage_doc: Optional[dict[str, Any]]) -> dict[str, Any]:
    return {
        "studio_master_schema_html": {
            "path": schema_doc["path"] if schema_doc else "/".join(SCHEMA_RELPATH),
            "mtime_utc": schema_doc["mtime"] if schema_doc else NOT_OBSERVABLE,
        },
        "forge_v2_pilotage_html": {
            "path": pilotage_doc["path"] if pilotage_doc else "/".join(PILOTAGE_RELPATH),
            "mtime_utc": pilotage_doc["mtime"] if pilotage_doc else NOT_OBSERVABLE,
        },
        "avertissement": (
            "document manuel qui vieillit en silence — l'historique du Master Schema "
            "documente des d\u00e9rives r\u00e9currentes entre ce qui est \u00e9crit et ce qui est "
            "r\u00e9ellement c\u00e2bl\u00e9"
        ),
    }


# --------------------------------------------------------------------------- #
# Assemblage
# --------------------------------------------------------------------------- #


def view_roadmap(ctx: Any, result: dict[str, Any], events: list[dict[str, Any]]) -> dict[str, Any]:
    """La vue `s2_roadmap` : jeux (doctrine x traces), chantiers Forge, infrastructure,
    drift doctrine<->mesure, fraicheur des deux documents. Lecture uniquement via ctx ;
    `BlindnessViolation` n'est jamais rattrap\u00e9e."""
    schema_doc = _read_doc(ctx, SCHEMA_RELPATH)
    pilotage_doc = _read_doc(ctx, PILOTAGE_RELPATH)
    docs = [d for d in (schema_doc, pilotage_doc) if d is not None]

    from observer.fleet import view_fleet

    fleet = view_fleet(ctx.repo_root, ctx.transcripts_root, ctx.project, result)

    jeux = _build_games_section(fleet, schema_doc, pilotage_doc)
    forge = _build_forge_section(ctx, result, events, docs)
    infra = _build_infra_section(docs)
    cablage = _build_cablage_section(ctx, schema_doc)

    drift_items = [*jeux["drift_items"], *forge["drift_items"], *cablage["drift_items"]]

    return {
        "jeux": {"lignes": jeux["lignes"]},
        "forge": {"lignes": forge["lignes"]},
        "infrastructure": {"lignes": infra["lignes"]},
        "cablage": {
            "lignes": cablage["lignes"],
            "note": "architecture attendue (Detail K, Nomenclature C + POOL DE BUILDERS) "
                    "vs realite mesuree, 7 axes : prevu/construit/cable/actif/bloque/"
                    "consomme/preuve_disponible + humangate_en_attente (decision Pierre "
                    "FORGE_AUTONOMY_V2 n°3 ; axe bloque ajoute 2026-08-03, correction "
                    "du faux negatif propose_brick cable=NON)",
        },
        "drift_items": drift_items,
        "fraicheur_doctrine": _fraicheur_doctrine(schema_doc, pilotage_doc),
    }


def build_roadmap_views(ctx: Any, result: dict[str, Any], events: list[dict[str, Any]]) -> dict[str, Any]:
    return {"s2_roadmap": view_roadmap(ctx, result, events)}


# --------------------------------------------------------------------------- #
# Preuve d'execution
# --------------------------------------------------------------------------- #

if __name__ == "__main__":
    import json

    from observer.sources import ObserverContext, default_repo_root, default_transcripts_root  # noqa: E402

    logging.basicConfig(level=logging.WARNING, format="%(levelname)s %(name)s: %(message)s")

    _repo_root = default_repo_root()
    _transcripts_root = default_transcripts_root(_repo_root)
    _project = "breakout_v2"
    _ctx = ObserverContext.build(_repo_root, _project, _transcripts_root)

    _report_dir = _repo_root / "EVIDENCE" / "reports" / "observer" / _project
    with (_report_dir / "observer_run.json").open("r", encoding="utf-8-sig") as _fh:
        _result = json.load(_fh)

    _events: list[dict[str, Any]] = []
    with (_report_dir / "events.jsonl").open("r", encoding="utf-8-sig") as _fh:
        for _line in _fh:
            _line = _line.strip()
            if _line:
                _events.append(json.loads(_line))

    _views = build_roadmap_views(_ctx, _result, _events)
    _roadmap = _views["s2_roadmap"]

    print(f"cles produites        : {sorted(_views.keys())}")

    _jeux = _roadmap["jeux"]["lignes"]
    _doctrine_names = [
        l["jeu"]["v"] for l in _jeux
        if "doctrine_curriculum" in l and l["doctrine_curriculum"]["v"] != NOT_OBSERVABLE
    ]
    _mesures_names = [
        l["jeu"]["v"] for l in _jeux
        if "traces" in l and l["traces"]["v"] != NOT_OBSERVABLE
    ]
    print(f"jeux (lignes totales)  : {len(_jeux)}")
    print(f"jeux dans la doctrine  : {len(_doctrine_names)} -> {_doctrine_names}")
    print(f"jeux mesures (traces)  : {len(_mesures_names)} -> {_mesures_names}")

    print(f"drift_items            : {len(_roadmap['drift_items'])}")
    for _d in _roadmap["drift_items"]:
        print(f"  - [{_d['severity']}] {_d['detail']}")

    print("chantiers Forge :")
    for _l in _roadmap["forge"]["lignes"]:
        print(
            f"  - {_l['chantier']['v']:<20} doctrine={_l['doctrine']['v'] if _l['doctrine']['v'] == NOT_OBSERVABLE else 'trouve'} "
            f"mesure={_l['mesure']['v'] if _l['mesure']['v'] == NOT_OBSERVABLE else 'trouve'}"
        )

    print("infrastructure (doctrine seule) :")
    for _l in _roadmap["infrastructure"]["lignes"]:
        print(f"  - {_l['composant']['v']:<12} doctrine={_l['doctrine']['v'] if _l['doctrine']['v'] == NOT_OBSERVABLE else 'trouve'}")

    _fr = _roadmap["fraicheur_doctrine"]
    print(f"mtime STUDIO_MASTER_SCHEMA.html : {_fr['studio_master_schema_html']['mtime_utc']}")
    print(f"mtime FORGE_V2_PILOTAGE.html    : {_fr['forge_v2_pilotage_html']['mtime_utc']}")
