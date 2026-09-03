"""Vues COMMANDE de la console Observer — 4 vues de pilotage haut niveau.

Ce module ne lit rien lui-meme : toute lecture passe par `ObserverContext`
(`ctx.read_text` / `ctx.read_jsonl` / `ctx.iter_files`), qui leve
`BlindnessViolation` si une racine non declaree est touchee. Cette exception
n'est JAMAIS rattrapee ici : une source hors perimetre doit faire planter
l'appelant, pas disparaitre silencieusement.

Quatre vues :

    c4_humangate  — ce qui attend une decision Pierre vs ce qui est enregistre
                    dans le registre canonique, et l'ECART entre les deux.
    c5_docloop    — la chaine campagne -> Observer -> lecons -> doc -> planning,
                    et les lecons elles-memes (candidate/validated, routage).
    c6_aicontrol  — honnete sur trois rythmes (demarrage/avant/apres action) :
                    ce qui est mesurable ici, ce qui ne l'est structurellement
                    pas, et le score d'observabilite qui en resulte.
    c7_forgemap   — la chaine Projet -> Campagne -> Mission -> Agents ->
                    Artifacts -> Tests -> Preuves -> Decisions, assemblee
                    depuis les donnees, jamais saisie a la main.

Regle non negociable, identique a `cockpit.py` : un manque de mesure ne
devient jamais un OK. Une cellule sans preuve porte `NOT_OBSERVABLE` et sa
raison — jamais 0 par defaut, jamais vide.
"""

from __future__ import annotations

import logging
import re
import statistics
import time
from collections import Counter
from datetime import datetime
from pathlib import Path
from typing import Any, Optional

LOG = logging.getLogger("observer.command")

NOT_OBSERVABLE = "NOT_OBSERVABLE"

# --------------------------------------------------------------------------- #
# Aides communes — meme contrat de cellule que cockpit.py : {v, src?, why?}
# --------------------------------------------------------------------------- #


def _cell(
    value: Any,
    src: Optional[dict[str, Any]] = None,
    why: Optional[str] = None,
    owner: Optional[str] = None,
    because: Optional[str] = None,
    next_: Optional[str] = None,
) -> dict[str, Any]:
    """Une cellule : valeur, provenance, raison si non observable."""
    out: dict[str, Any] = {"v": value}
    if src:
        out["src"] = src
    if value == NOT_OBSERVABLE and why:
        out["why"] = why
    if owner:
        out["owner"] = owner
    if because:
        out["because"] = because
    if next_:
        out["next"] = next_
    return out


def _kinds(events: list[dict[str, Any]], kinds: tuple[str, ...],
           run_id: Optional[str] = None) -> list[dict[str, Any]]:
    out = [e for e in events if e.get("kind") in kinds]
    if run_id:
        out = [e for e in out if e.get("run_id") == run_id]
    return out


def _src_ev(ev: Optional[dict[str, Any]], field: Optional[str] = None) -> Optional[dict[str, Any]]:
    if not ev:
        return None
    s = ev.get("source", {}) or {}
    out: dict[str, Any] = {"path": s.get("path", "")}
    if s.get("line") is not None:
        out["line"] = s["line"]
    if field or s.get("field"):
        out["field"] = field or s.get("field")
    return out


def _first(events: list[dict[str, Any]], kind: str, run_id: Optional[str] = None) -> Optional[dict[str, Any]]:
    for ev in events:
        if ev.get("kind") != kind:
            continue
        if run_id and ev.get("run_id") != run_id:
            continue
        return ev
    return None


# --------------------------------------------------------------------------- #
# Parsing best-effort de registres en prose (decision-log.md / DEFERRED.md)
# --------------------------------------------------------------------------- #

# "## 2026-07-23 — Titre" ou "## 2026-07-05/06 — Titre" (dates a cheval)
_DECISION_HEADER_RE = re.compile(r"^##\s+(\d{4}-\d{2}-\d{2}(?:/\d{2})?)\s+—\s+(.+?)\s*$")
# "## DR-01 — Titre"
_DEFERRED_HEADER_RE = re.compile(r"^##\s+(DR-\d+)\s+—\s+(.+?)\s*$")
# Detection best-effort d'un tag/champ DESTINATION dans une ligne de lecon libre.
_DESTINATION_RE = re.compile(r"destination\s*[:=]\s*([^\s,;.]+)", re.IGNORECASE)


def _parse_headed_sections(text: str, header_re: re.Pattern) -> list[dict[str, Any]]:
    """Segmente un document prose en sections '## <id> — <titre>'.

    Best-effort assume : ce n'est PAS un parseur markdown, seulement une
    reconnaissance ligne par ligne de l'entete demandee. Retourne, pour
    chaque section trouvee, son identifiant/date, son titre, le numero de
    ligne de l'entete et la premiere ligne de contenu non vide qui suit.
    """
    lines = text.splitlines()
    sections: list[dict[str, Any]] = []
    for i, line in enumerate(lines, start=1):
        match = header_re.match(line)
        if not match:
            continue
        premiere_ligne: Optional[str] = None
        for j in range(i, len(lines)):
            candidate = lines[j].strip()
            if candidate and not candidate.startswith("##"):
                premiere_ligne = candidate
                break
        sections.append({
            "id": match.group(1),
            "titre": match.group(2).strip(),
            "ligne": i,
            "premiere_ligne": premiere_ligne,
        })
    return sections


# --------------------------------------------------------------------------- #
# c4 — HUMAN GATE
# --------------------------------------------------------------------------- #


def view_humangate(ctx: Any, result: dict[str, Any], events: list[dict[str, Any]]) -> dict[str, Any]:
    runs = result.get("runs", [])
    project = result.get("project")

    decision_log_path = ctx.repo_root / "studio_brain" / "decisions" / "decision-log.md"
    deferred_path = ctx.repo_root / "studio_brain" / "decisions" / "DEFERRED.md"

    decision_log_text = ctx.read_text(decision_log_path)
    deferred_text = ctx.read_text(deferred_path)

    # 1. en_attente — runs prets pour la gate, avec la preuve attendue.
    en_attente: list[dict[str, Any]] = []
    for run in runs:
        if run.get("decision") != "HUMANGATE_READY":
            continue
        verdict = run.get("verdict") or {}
        flags = verdict.get("humangate_flags")
        v_ev = _first(events, "verdict.signed", run.get("run_id"))
        en_attente.append({
            "run_id": _cell(run.get("run_id")),
            "project": _cell(project),
            "preuve_attendue": _cell(
                flags if flags else NOT_OBSERVABLE,
                _src_ev(v_ev, "humangate_flags"),
                "le verdict signe ne porte aucun humangate_flags pour ce run",
            ),
        })

    # 2. enregistrees — parse minimal du registre en prose.
    if decision_log_text is not None:
        enregistrees = [
            {
                "date": _cell(section["id"]),
                "titre": _cell(
                    section["titre"],
                    {"path": ctx.rel(decision_log_path), "line": section["ligne"]},
                ),
                "proof": _cell(
                    "SELF_DECLARED",
                    None,
                    "registre en prose — parsing best-effort, pas une source structuree",
                ),
            }
            for section in _parse_headed_sections(decision_log_text, _DECISION_HEADER_RE)
        ]
    else:
        LOG.warning("decision-log.md illisible ou absent : %s", decision_log_path)
        enregistrees = [{
            "date": _cell(NOT_OBSERVABLE, why="decision-log.md illisible ou absent"),
        }]

    # 3. ecart — LA ligne de valeur : verdict HUMANGATE_READY sans trace du
    #    projet dans le registre canonique.
    ecart: list[dict[str, Any]] = []
    if decision_log_text is not None:
        par_projet: dict[str, list[str]] = {}
        for run in runs:
            if run.get("decision") != "HUMANGATE_READY":
                continue
            par_projet.setdefault(project, []).append(run.get("run_id"))
        for proj, run_ids in sorted(par_projet.items()):
            occurrences = len(re.findall(re.escape(proj), decision_log_text, flags=re.IGNORECASE))
            if occurrences == 0:
                v_ev = _first(events, "verdict.signed", run_ids[0]) if run_ids else None
                ecart.append({
                    "projet": _cell(proj),
                    "verdicts_concernes": _cell(sorted(run_ids), _src_ev(v_ev, "decision")),
                    "occurrences_registre": _cell(
                        0, {"path": ctx.rel(decision_log_path)},
                    ),
                    "constat": _cell(
                        "decision ratifiee hors registre canonique ou non ratifiee — "
                        "le registre ne permet pas de trancher",
                    ),
                })
    else:
        ecart = [{
            "constat": _cell(NOT_OBSERVABLE, why="decision-log.md illisible ou absent — "
                              "l'ecart ne peut pas etre calcule"),
        }]

    # 4. deferred — registre DEFERRED.md, meme regime best-effort.
    if deferred_text is not None:
        deferred = [
            {
                "id": _cell(section["id"]),
                "premiere_ligne": _cell(
                    section["premiere_ligne"] if section["premiere_ligne"] else NOT_OBSERVABLE,
                    {"path": ctx.rel(deferred_path), "line": section["ligne"]},
                    None if section["premiere_ligne"] else "aucune ligne de contenu sous ce titre",
                ),
                "proof": _cell(
                    "SELF_DECLARED",
                    None,
                    "registre en prose — parsing best-effort, pas une source structuree",
                ),
            }
            for section in _parse_headed_sections(deferred_text, _DEFERRED_HEADER_RE)
        ]
    else:
        LOG.warning("DEFERRED.md illisible ou absent : %s", deferred_path)
        deferred = [{
            "id": _cell(NOT_OBSERVABLE, why="DEFERRED.md illisible ou absent"),
        }]

    return {
        "en_attente": en_attente,
        "enregistrees": enregistrees,
        "ecart": ecart,
        "deferred": deferred,
    }


# --------------------------------------------------------------------------- #
# c5 — DOCUMENTATION LOOP
# --------------------------------------------------------------------------- #


def _latest_lesson_states(lesson_lines: list[tuple[int, dict[str, Any]]]) -> dict[str, tuple[int, dict[str, Any]]]:
    """Dernier etat connu par lesson_id (le plus grand ts observe)."""
    latest: dict[str, tuple[int, dict[str, Any]]] = {}
    for lineno, obj in lesson_lines:
        lid = obj.get("lesson_id")
        if not lid:
            continue
        prev = latest.get(lid)
        if prev is None or (obj.get("ts") or 0.0) >= (prev[1].get("ts") or 0.0):
            latest[lid] = (lineno, obj)
    return latest


def _extract_destination(statement: str, obj: dict[str, Any]) -> Optional[str]:
    if isinstance(obj.get("destination"), str) and obj["destination"].strip():
        return obj["destination"].strip()
    match = _DESTINATION_RE.search(statement)
    return match.group(1) if match else None


# --------------------------------------------------------------------------- #
# Consommateur mecanique d'une lecon (chantier "preflight_oracle_registration")
#
# knowledge_base/search_log.jsonl (racine lisible declaree, cf. sources.py
# ALLOWED_ROOTS) est l'auto-journalisation de knowledge_base/search.mjs : chaque
# appel CLI ecrit une ligne {query, matchCount, ts}. Ce fichier ne porte NI
# lesson_id NI brick_id -- aucune correlation exacte n'y est disponible. Le lien
# le plus honnete qu'on puisse construire est LITTERAL : un consommateur qui veut
# etre reconnu comme tel doit faire figurer, MOT POUR MOT, l'identifiant de la
# lecon (le segment apres le dernier '.' de son lesson_id) dans l'intention de
# recherche qu'il passe a search.mjs -- c'est exactement ce que fait
# scripts/forge/preflight.py (LESSON_SLUG). Ne PAS inventer de correlation plus
# fine (ex. deviner un mapping query->lesson_id) : ce serait bricoler une preuve
# qui n'existe pas dans les donnees.
# --------------------------------------------------------------------------- #

_SEARCH_LOG_REL = ("knowledge_base", "search_log.jsonl")


def _lesson_identifier_slug(lesson_id: str) -> str:
    """Identifiant reconnaissable derive de `lesson_id` : le segment apres le
    dernier '.' (ex. 'forge.preflight_oracle_registration' ->
    'preflight_oracle_registration'), ou `lesson_id` entier s'il n'y a pas de
    point. C'est EXACTEMENT le slug que scripts/forge/preflight.py incorpore,
    litteralement, dans l'intention qu'il passe a knowledge_base/search.mjs."""
    return lesson_id.rsplit(".", 1)[-1] if "." in lesson_id else lesson_id


def _parse_iso_ts(raw: Any) -> Optional[float]:
    """Timestamp epoch (secondes) depuis une chaine ISO 8601 'Z' (format ecrit par
    search.mjs, `new Date().toISOString()`). None si absent/invalide -- jamais
    d'exception qui remonterait a l'appelant."""
    if not isinstance(raw, str) or not raw.strip():
        return None
    try:
        return datetime.fromisoformat(raw.strip().replace("Z", "+00:00")).timestamp()
    except ValueError:
        return None


def _find_consumer_in_run_artifacts(
    ctx: Any, lesson_id: str,
) -> Optional[dict[str, Any]]:
    """Canal nº2 (R1) — un ARTEFACT D'EXECUTION cite la lecon.

    Complement necessaire de `_find_consumer_in_search_log` : une lecon de type
    VALIDATOR_RULE / ORACLE_RULE / CONTRACT_SCHEMA est appliquee par un composant
    qui n'a AUCUNE raison d'interroger la KB pendant qu'il valide. Son unique
    trace honnete est la sortie qu'il PRODUIT en s'executant.

    On ne cherche donc PAS dans le code source (qui prouverait une intention, pas
    une execution) mais dans les artefacts produits par un run : verdict signe,
    logs d'oracle, reçus d'evidence, rapports d'etape. Un fichier de ce dossier
    n'existe que si le composant a tourne — la citation vaut alors preuve
    d'execution, pas de conformite declaree.

    Limite DECLAREE, identique au canal nº1 : le lien slug<->lecon est LITTERAL.
    Un composant qui appliquerait la regle sans citer la lecon reste invisible —
    c'est voulu : conformite n'est pas causalite.
    """
    slug = _lesson_identifier_slug(lesson_id).strip().lower()
    if not slug:
        return None
    racines = (ctx.run_dir, ctx.evidence_dir)
    for racine in racines:
        for path in ctx.iter_files(racine, "*"):
            if not path.is_file() or path.suffix.lower() not in _ARTEFACT_SUFFIXES:
                continue
            texte = ctx.read_text(path)
            if not texte or slug not in texte.lower():
                continue
            ligne = next(
                (n for n, l in enumerate(texte.splitlines(), 1) if slug in l.lower()),
                None,
            )
            return {
                "canal": "artefact_execution",
                "citation": f"slug '{slug}' cite dans un artefact produit par un run",
                "source": {"path": ctx.rel(path), "line": ligne},
            }
    return None


_ARTEFACT_SUFFIXES = frozenset({".json", ".jsonl", ".log", ".txt", ".md", ".yaml"})


def _find_mechanical_consumer(
    ctx: Any, lesson_id: str, validated_ts: Any,
) -> Optional[dict[str, Any]]:
    """Consommateur mecanique d'une lecon, sur DEUX canaux (R1, 2026-08-03).

    1. `knowledge_base/search_log.jsonl` — le consommateur interroge la KB au
       runtime (cas PREFLIGHT_GUARD : `scripts/forge/preflight.py`).
    2. artefacts d'execution d'un run — le consommateur cite la lecon dans ce
       qu'il PRODUIT (cas VALIDATOR_RULE / ORACLE_RULE / CONTRACT_SCHEMA, dont le
       composant n'interroge jamais la KB).

    Le canal nº1 garde sa contrainte d'horodatage (posterieur a la validation) ;
    le canal nº2 n'en a pas besoin — un artefact de run est par construction
    posterieur au code qui l'a produit.
    """
    trace = _find_consumer_in_search_log(ctx, lesson_id, validated_ts)
    if trace is not None:
        return trace
    return _find_consumer_in_run_artifacts(ctx, lesson_id)


def _find_consumer_in_search_log(
    ctx: Any, lesson_id: str, validated_ts: Any,
) -> Optional[dict[str, Any]]:
    """Canal nº1 — cherche, dans knowledge_base/search_log.jsonl, une trace MECANIQUE de
    consommation de `lesson_id` : une ligne dont `query` contient LITTERALEMENT
    (insensible a la casse) le slug identifiant de la lecon, horodatee APRES sa
    validation (`validated_ts`, le `ts` de la ligne 'validated' de lessons.jsonl),
    avec au moins un resultat trouve (`matchCount >= 1` -- une recherche a zero
    resultat prouve qu'on a cherche, pas qu'on a consomme la brique).

    Retourne la 1re trace trouvee (source citable : chemin + numero de ligne) ou
    None. Limite DECLAREE (ne pas la lire comme un bug) : le lien slug<->lesson
    est LITTERAL, pas semantique -- c'est le minimum honnete que les donnees
    disponibles permettent (search_log.jsonl ne porte ni lesson_id ni brick_id)."""
    epoch = validated_ts if isinstance(validated_ts, (int, float)) else None
    if epoch is None:
        return None
    slug = _lesson_identifier_slug(lesson_id).strip().lower()
    if not slug:
        return None
    search_log_path = ctx.repo_root.joinpath(*_SEARCH_LOG_REL)
    for lineno, obj in ctx.read_jsonl(search_log_path):
        query = str(obj.get("query") or "")
        if slug not in query.lower():
            continue
        try:
            match_count = int(obj.get("matchCount") or 0)
        except (TypeError, ValueError):
            match_count = 0
        if match_count < 1:
            continue
        entry_epoch = _parse_iso_ts(obj.get("ts"))
        if entry_epoch is None or entry_epoch < epoch:
            continue
        return {
            "canal": "search_log",
            "query": query,
            "matchCount": match_count,
            "ts": obj.get("ts"),
            "source": {"path": ctx.rel(search_log_path), "line": lineno},
        }
    return None


def view_docloop(ctx: Any, result: dict[str, Any], events: list[dict[str, Any]]) -> dict[str, Any]:
    lessons_path = ctx.repo_root / "lab" / "reports" / "lessons.jsonl"
    lesson_lines = list(ctx.read_jsonl(lessons_path))

    # RUN_INDEX.md vit sous lab/forge_runs/RUN_INDEX.md — la racine autorisee
    # est lab/forge_runs/<project>, PAS lab/forge_runs entier. On ne tente
    # meme pas la lecture (ce serait une BlindnessViolation) : la cellule
    # honnete est produite directement.
    run_index_cell = _cell(
        NOT_OBSERVABLE,
        why="RUN_INDEX.md hors des racines lisibles declarees — elargissement non ratifie",
    )

    attempts = [r for r in result.get("runs", []) if r.get("role") == "attempt"]

    chaine = [
        {
            "maillon": _cell("campagne"),
            "etat": _cell("EXISTANT" if attempts else NOT_OBSERVABLE,
                          None, None if attempts else "aucun run de type attempt observe"),
            "preuve": _cell(
                f"{len(attempts)} run(s) attempt observes" if attempts else NOT_OBSERVABLE,
                why=None if attempts else "aucun run de type attempt observe",
            ),
        },
        {
            "maillon": _cell("Observer"),
            "etat": _cell("EXISTANT"),
            "preuve": _cell(
                "cette reconstruction elle-meme (observer_run.json + events.jsonl lus)",
            ),
        },
        {
            "maillon": _cell("lessons"),
            "etat": _cell("EXISTANT" if lesson_lines else NOT_OBSERVABLE,
                          None, None if lesson_lines else "lessons.jsonl vide ou absent"),
            "preuve": _cell(
                f"{len(lesson_lines)} ligne(s) lue(s) ici meme" if lesson_lines else NOT_OBSERVABLE,
                {"path": ctx.rel(lessons_path)},
                None if lesson_lines else "lessons.jsonl vide ou absent",
            ),
        },
        {
            "maillon": _cell("doc"),
            "etat": _cell(
                NOT_OBSERVABLE,
                why="docs/forge/ est hors des racines lisibles declarees : aucune preuve "
                    "mecanique qu'une lecon validee produise un document n'est accessible ici",
            ),
            "preuve": _cell(NOT_OBSERVABLE, why="racine non lisible"),
        },
        {
            "maillon": _cell("planning"),
            "etat": _cell(
                NOT_OBSERVABLE,
                why="le pipeline de contrats/campagnes suivants est hors des racines lisibles "
                    "declarees : aucun consommateur mecanique des lecons n'est observable ici",
            ),
            "preuve": _cell(NOT_OBSERVABLE, why="racine non lisible"),
        },
    ]

    lecons = [
        {
            "lesson_id": _cell(obj.get("lesson_id", NOT_OBSERVABLE)),
            "status": _cell(obj.get("status", NOT_OBSERVABLE)),
            "statement": _cell(_truncate(str(obj.get("statement") or ""), 200)),
            "supporting_runs": _cell(obj.get("supporting_runs") or []),
            "src": {"path": ctx.rel(lessons_path), "line": lineno},
        }
        for lineno, obj in lesson_lines
    ]

    latest = _latest_lesson_states(lesson_lines)

    # Consommateur mecanique connu par lecon validee : recherche dans
    # knowledge_base/search_log.jsonl (cf. _find_mechanical_consumer ci-dessus).
    # Calcule UNE fois, reutilise par routage ET drift_items ci-dessous (jamais
    # deux jugements differents pour la meme lecon dans la meme vue).
    consumers: dict[str, Optional[dict[str, Any]]] = {
        lid: _find_mechanical_consumer(ctx, lid, obj.get("ts"))
        for lid, (_, obj) in latest.items()
        if obj.get("status") == "validated"
    }

    routage: list[dict[str, Any]] = []
    for lid, (lineno, obj) in sorted(latest.items()):
        if obj.get("status") != "validated":
            continue
        statement = str(obj.get("statement") or "")
        destination = _extract_destination(statement, obj)
        consumer = consumers.get(lid)
        if consumer:
            # Deux canaux (cf. _find_mechanical_consumer), deux FORMES de dict :
            # `search_log` porte query/matchCount/ts ; `artefact_execution` porte
            # citation. Rendre l'un avec les clés de l'autre lève un KeyError — c'est
            # ce qui est arrivé au run `tetris-fullgodot-20260803-084719`, premier run
            # a declencher le canal nº2 (les 5 lecons Breakout venaient d'etre promues
            # le matin meme, donc citees dans des artefacts). On branche sur le canal
            # declare, jamais sur un .get() permissif qui masquerait la provenance.
            if consumer.get("canal") == "artefact_execution":
                statut = _cell(
                    "CONSOMME — citation dans un artefact d'execution",
                    consumer["source"],
                )
                consommateur_cell = _cell(
                    str(consumer.get("citation") or NOT_OBSERVABLE),
                    consumer["source"],
                )
            else:
                statut = _cell(
                    "CONSOMME — trace mecanique dans search_log.jsonl",
                    consumer["source"],
                )
                consommateur_cell = _cell(
                    f"query={consumer['query']!r} matchCount={consumer['matchCount']} "
                    f"ts={consumer['ts']}",
                    consumer["source"],
                )
        else:
            statut = _cell("PROPOSE — aucun consommateur mecanique")
            consommateur_cell = _cell(
                NOT_OBSERVABLE,
                why="aucune ligne search_log.jsonl posterieure a la validation ne "
                    f"contient l'identifiant '{_lesson_identifier_slug(lid)}' avec "
                    "au moins un resultat trouve",
            )
        routage.append({
            "lesson_id": _cell(lid),
            "destination": _cell(
                destination if destination else NOT_OBSERVABLE,
                {"path": ctx.rel(lessons_path), "line": lineno},
                None if destination else "aucun champ ou tag DESTINATION trouve dans la ligne source",
            ),
            "statut": statut,
            "consommateur": consommateur_cell,
            "note": "les lecons proposent, n'ecrivent jamais ; application = gate Pierre",
        })

    drift_items: list[dict[str, Any]] = []
    for lid, (lineno, obj) in sorted(latest.items()):
        if obj.get("status") == "validated" and not consumers.get(lid):
            drift_items.append({
                "type": "lecon_routee_sans_consommateur",
                "severity": "medium",
                "owner": "DOCTRINE",
                "action": "CORRIGER",
                "detail": f"lecon '{lid}' validee sans consommateur mecanique connu dans les "
                          f"racines lisibles d'Observer",
                "source": {"path": ctx.rel(lessons_path), "line": lineno},
            })

    now = time.time()
    candidates_agees = [
        (lid, lineno) for lid, (lineno, obj) in latest.items()
        if obj.get("status") == "candidate" and obj.get("ts") is not None
        and (now - float(obj["ts"])) > 7 * 86400
    ]
    validated_count = sum(1 for _, obj in latest.values() if obj.get("status") == "validated")
    if len(candidates_agees) > validated_count:
        drift_items.append({
            "type": "lecon_candidate_non_arbitree",
            "severity": "info",
            "owner": "HUMANGATE",
            "action": "RATIFIER",
            "detail": f"{len(candidates_agees)} lecon(s) candidate(s) de plus de 7 jours pour "
                      f"{validated_count} lecon(s) validee(s) : arbitrage HumanGate en retard",
            "source": [{"path": ctx.rel(lessons_path), "line": ln} for _, ln in candidates_agees],
        })

    return {
        "chaine": chaine,
        "lecons": lecons,
        "routage": routage,
        "drift_items": drift_items,
        "run_index": run_index_cell,
    }


def _truncate(text: str, limit: int) -> str:
    return text if len(text) <= limit else text[:limit].rstrip() + "…"


# --------------------------------------------------------------------------- #
# c6 — AI CONTROL — trois rythmes, honnetete d'abord
# --------------------------------------------------------------------------- #


def view_aicontrol(ctx: Any, result: dict[str, Any], events: list[dict[str, Any]]) -> dict[str, Any]:
    items: list[tuple[str, dict[str, Any]]] = []

    def item(label: str, cell: dict[str, Any]) -> dict[str, Any]:
        items.append((label, cell))
        return cell

    lessons_path = ctx.repo_root / "lab" / "reports" / "lessons.jsonl"
    lesson_lines = list(ctx.read_jsonl(lessons_path))
    latest = _latest_lesson_states(lesson_lines)
    statuses = Counter(obj.get("status") for _, obj in latest.values())

    au_demarrage = {
        "invariants_zones_protegees": item("au_demarrage.invariants_zones_protegees", _cell(
            NOT_OBSERVABLE,
            why="reference_protected.yaml et .claude/settings.json hors racines lisibles — "
                "elargissement non ratifie",
        )),
        "contraintes_ratifiees": item("au_demarrage.contraintes_ratifiees", _cell(
            NOT_OBSERVABLE,
            why="FORGE_SYSTEM_CONTRACT hors racines lisibles — elargissement non ratifie",
        )),
        "memoire_lecons": item("au_demarrage.memoire_lecons", _cell(
            f"{statuses.get('validated', 0)} validated / {statuses.get('candidate', 0)} candidate"
            if lesson_lines else NOT_OBSERVABLE,
            {"path": ctx.rel(lessons_path)},
            None if lesson_lines else "lessons.jsonl vide ou absent",
        )),
        "decisions_faisant_foi": item("au_demarrage.decisions_faisant_foi", _cell(
            "voir vue HUMAN GATE (c4_humangate)",
            because="registre prose, ecart affiche en HUMAN GATE",
        )),
        "table_confiance": item("au_demarrage.table_confiance", _cell(
            NOT_OBSERVABLE,
            why="table §4.2 jamais serialisee — M2, gate en attente",
        )),
    }

    # etat_courant : run_status par run, source state.json.
    etat_par_run: dict[str, Any] = {}
    src_etat = None
    for run in result.get("runs", []):
        run_id = run.get("run_id")
        etat_par_run[run_id] = run.get("run_status") or NOT_OBSERVABLE
        if src_etat is None:
            ev = _first(events, "run.status", run_id) or _first(events, "run.declared", run_id)
            src_etat = _src_ev(ev)
    etat_courant = item("avant_action.etat_courant", _cell(
        etat_par_run if etat_par_run else NOT_OBSERVABLE,
        src_etat,
        "aucun run observe" if not etat_par_run else None,
    ))
    if etat_par_run:
        etat_courant["note"] = "state.json ment sur tout cumul (detail ecrase)"

    actions_possibles = item("avant_action.actions_possibles", _cell(
        NOT_OBSERVABLE,
        why="machine a etats du driver non exposee — M4, gate",
    ))

    # cout_attendu : M5, calculable par Observer seul depuis telemetry.step.
    tel_by_etape: dict[str, list[dict[str, Any]]] = {}
    for ev in _kinds(events, ("telemetry.step",)):
        etape = ev.get("etape") or NOT_OBSERVABLE
        tel_by_etape.setdefault(etape, []).append(ev["payload"])

    usage_by_etape: dict[str, list[int]] = {}
    for ev in _kinds(events, ("llm.usage",)):
        etape = ev.get("etape") or NOT_OBSERVABLE
        payload = ev["payload"]
        total = (int(payload.get("input_tokens") or 0) + int(payload.get("output_tokens") or 0)
                 + int(payload.get("cache_read_input_tokens") or 0)
                 + int(payload.get("cache_creation_input_tokens") or 0))
        usage_by_etape.setdefault(etape, []).append(total)

    cout_par_etape: dict[str, dict[str, Any]] = {}
    for etape in sorted(set(tel_by_etape) | set(usage_by_etape)):
        payloads = tel_by_etape.get(etape, [])
        tokens = usage_by_etape.get(etape, [])
        durations = [p.get("duration_s") for p in payloads if isinstance(p.get("duration_s"), (int, float))]
        costs = [p.get("cost_usd") for p in payloads if isinstance(p.get("cost_usd"), (int, float))]
        cout_par_etape[etape] = {
            "n": len(payloads) if payloads else NOT_OBSERVABLE,
            "mediane_duration_s": round(statistics.median(durations), 2) if durations else NOT_OBSERVABLE,
            "mediane_cost_usd": round(statistics.median(costs), 4) if costs else NOT_OBSERVABLE,
            "tokens_mesures_median": round(statistics.median(tokens), 1) if tokens else NOT_OBSERVABLE,
            "note": "couts DECLARES — sous-evalues x6.7-12.3 vs transcripts (drift prouve)" if payloads else
                    "aucune telemetrie de cout pour cette etape (seuls des tokens mesures existent)",
        }

    cout_attendu = item("avant_action.cout_attendu", _cell(
        cout_par_etape if cout_par_etape else NOT_OBSERVABLE,
        why="aucune telemetrie ni usage LLM observe" if not cout_par_etape else None,
    ))

    risque_action = item("avant_action.risque_action", _cell(
        NOT_OBSERVABLE,
        why="gel STUDIO absent des listes machine, git_guard non active — M6",
    ))

    # chaine_etapes : sequence observee du run attempt le plus recent (profil courant).
    attempts = [r for r in result.get("runs", []) if r.get("role") == "attempt"]
    profil_courant = max(
        (r for r in attempts if (r.get("window") or {}).get("start")),
        key=lambda r: r["window"]["start"],
        default=None,
    )
    if profil_courant:
        seq = [step.get("etape") for step in profil_courant.get("steps", [])]
        src_seq = _src_ev(_first(events, "run.declared", profil_courant.get("run_id")))
        chaine_etapes = item("avant_action.chaine_etapes", _cell(seq, src_seq))
        chaine_etapes["note"] = "sequence OBSERVEE, la source canonique PROFILES est hors racines lisibles"
    else:
        chaine_etapes = item("avant_action.chaine_etapes", _cell(
            NOT_OBSERVABLE, why="aucun run attempt date observe",
        ))

    avant_action = {
        "etat_courant": etat_courant,
        "actions_possibles": actions_possibles,
        "cout_attendu": cout_attendu,
        "risque_action": risque_action,
        "chaine_etapes": chaine_etapes,
    }

    # apres_action
    n_prepared = len(_kinds(events, ("dispatch.prepared",)))
    n_executed = len(_kinds(events, ("dispatch.executed",)))
    preuve_execution = item("apres_action.preuve_execution", _cell(
        {"prepared": n_prepared, "executed": n_executed}
        if (n_prepared or n_executed) else NOT_OBSERVABLE,
        why="aucun evenement de dispatch observe" if not (n_prepared or n_executed) else None,
    ))

    prompts = result.get("prompts") or []
    verifs = Counter(p.get("verification") for p in prompts)
    prompt_conforme = item("apres_action.prompt_conforme", _cell(
        dict(verifs) if prompts else NOT_OBSERVABLE,
        why="aucune activation de prompt observee" if not prompts else None,
    ))

    drift = result.get("drift") or []
    drift_produit = item("apres_action.drift_produit", _cell(
        dict(Counter(d.get("severity") for d in drift)) if drift else NOT_OBSERVABLE,
        why="aucune deviation detectee" if not drift else None,
    ))

    failures = _kinds(events, ("failure.event",))
    historique_corrections = item("apres_action.historique_corrections", _cell(
        len(failures) if failures else 0,
        why=None,
    ))
    historique_corrections["note"] = "signatures mecaniques, jamais causes"

    apres_action = {
        "preuve_execution": preuve_execution,
        "prompt_conforme": prompt_conforme,
        "drift_produit": drift_produit,
        "historique_corrections": historique_corrections,
    }

    not_observable_items = [(label, cell) for label, cell in items if cell.get("v") == NOT_OBSERVABLE]
    score_observabilite = {
        "observables": len(items) - len(not_observable_items),
        "not_observable": len(not_observable_items),
        "liste": [
            {"item": label, "why": cell.get("why", NOT_OBSERVABLE)}
            for label, cell in not_observable_items
        ],
    }

    return {
        "au_demarrage": au_demarrage,
        "avant_action": avant_action,
        "apres_action": apres_action,
        "score_observabilite": score_observabilite,
    }


# --------------------------------------------------------------------------- #
# c7 — FORGE MAP
# --------------------------------------------------------------------------- #


def view_forgemap(ctx: Any, result: dict[str, Any], events: list[dict[str, Any]]) -> dict[str, Any]:
    project = result.get("project")
    runs = result.get("runs", [])
    attempts = [r for r in runs if r.get("role") == "attempt"]

    starts = [r["window"]["start"] for r in attempts if (r.get("window") or {}).get("start")]
    ends = [r["window"]["end"] for r in attempts if (r.get("window") or {}).get("end")]
    campagne = {
        "nombre_runs": _cell(len(attempts)),
        "fenetre_globale": _cell(
            {"debut": min(starts), "fin": max(ends)} if starts and ends else NOT_OBSERVABLE,
            why=None if starts and ends else "aucun run attempt date",
        ),
    }

    missions: list[dict[str, Any]] = []
    for run in attempts:
        v_ev = _first(events, "verdict.signed", run.get("run_id"))
        missions.append({
            "run_id": _cell(run.get("run_id")),
            "decision": _cell(
                run.get("decision") or NOT_OBSERVABLE,
                _src_ev(v_ev, "decision"),
                "aucun verdict signe pour ce run" if not run.get("decision") else None,
            ),
            "fenetre": _cell(run.get("window")),
        })

    agents_par_etape: Counter = Counter()
    for ev in _kinds(events, ("agent.session",)):
        if ev.get("payload", {}).get("activity_attributed") and ev.get("etape"):
            agents_par_etape[ev["etape"]] += 1
    agents = {
        "sessions_attribuees_par_etape": _cell(
            dict(agents_par_etape) if agents_par_etape else NOT_OBSERVABLE,
            why="aucune session d'agent avec activite attribuee n'est rattachee a une etape"
            if not agents_par_etape else None,
        ),
    }

    fichiers_ecrits: set[str] = set()
    for ev in _kinds(events, ("file.write", "file.edit")):
        path = ev.get("payload", {}).get("path")
        if path:
            fichiers_ecrits.add(path)
    rapports_etape = _kinds(events, ("artifact.self_declared",))
    captures = _kinds(events, ("capture.visual",))
    artifacts = {
        "fichiers_ecrits": _cell(len(fichiers_ecrits)),
        "rapports_etape": _cell(len(rapports_etape)),
        "captures": _cell(
            len(captures) if captures else NOT_OBSERVABLE,
            why="aucune capture visuelle observee" if not captures else None,
        ),
    }

    tests_ev = _kinds(events, ("test.result",))
    mutation_ev = _kinds(events, ("mutation.result",))
    solva_ev = _kinds(events, ("solvability.result",))
    verdict_ev = _kinds(events, ("verdict.signed",))
    tests_preuves = {
        "tests": _cell(
            [{"run_id": e.get("run_id"), "passed": e["payload"].get("passed"),
              "failed": e["payload"].get("failed")} for e in tests_ev]
            if tests_ev else NOT_OBSERVABLE,
            why="aucun resultat de test observe" if not tests_ev else None,
        ),
        "mutation": _cell(
            [{"run_id": e.get("run_id"), "killed": e["payload"].get("killed"),
              "total": e["payload"].get("total")} for e in mutation_ev]
            if mutation_ev else NOT_OBSERVABLE,
            why="aucun recu de mutation observe" if not mutation_ev else None,
        ),
        "solvabilite": _cell(
            [{"run_id": e.get("run_id"), "won": e["payload"].get("won"),
              "trials": e["payload"].get("trials")} for e in solva_ev]
            if solva_ev else NOT_OBSERVABLE,
            why="solvabilite non mesuree" if not solva_ev else None,
        ),
        "verdict_hmac": _cell(
            [{"run_id": e.get("run_id"), "hmac": e["payload"].get("hmac"),
              "decision": e["payload"].get("decision")} for e in verdict_ev]
            if verdict_ev else NOT_OBSERVABLE,
            why="aucun verdict signe observe" if not verdict_ev else None,
        ),
    }

    decisions = {
        "renvoi": _cell("c4_humangate"),
        "note": "l'ecart decisions prises vs enregistrees vit dans la vue HUMAN GATE, "
                "il n'est pas duplique ici",
    }

    return {
        "projet": _cell(project),
        "campagne": campagne,
        "missions": missions,
        "agents": agents,
        "artifacts": artifacts,
        "tests_preuves": tests_preuves,
        "decisions": decisions,
    }


# --------------------------------------------------------------------------- #
# Assemblage
# --------------------------------------------------------------------------- #


def build_command_views(ctx: Any, result: dict[str, Any], events: list[dict[str, Any]]) -> dict[str, Any]:
    return {
        "c4_humangate": view_humangate(ctx, result, events),
        "c5_docloop": view_docloop(ctx, result, events),
        "c6_aicontrol": view_aicontrol(ctx, result, events),
        "c7_forgemap": view_forgemap(ctx, result, events),
    }


# --------------------------------------------------------------------------- #
# Preuve d'execution
# --------------------------------------------------------------------------- #

if __name__ == "__main__":
    import json
    import sys

    _HERE = Path(__file__).resolve().parent
    if str(_HERE.parent) not in sys.path:  # rend `import observer` possible sans install
        sys.path.insert(0, str(_HERE.parent))

    from observer.sources import ObserverContext, default_repo_root, default_transcripts_root  # noqa: E402

    logging.basicConfig(level=logging.WARNING)

    repo_root = default_repo_root()
    transcripts_root = default_transcripts_root(repo_root)
    ctx = ObserverContext.build(repo_root, "breakout_v2", transcripts_root)

    report_dir = repo_root / "EVIDENCE" / "reports" / "observer" / "breakout_v2"
    with (report_dir / "observer_run.json").open("r", encoding="utf-8-sig") as fh:
        result = json.load(fh)

    events: list[dict[str, Any]] = []
    with (report_dir / "events.jsonl").open("r", encoding="utf-8-sig") as fh:
        for line in fh:
            line = line.strip()
            if line:
                events.append(json.loads(line))

    views = build_command_views(ctx, result, events)

    print(f"cles produites : {sorted(views.keys())}")

    hg = views["c4_humangate"]
    print(
        f"c4_humangate   : en_attente={len(hg['en_attente'])} "
        f"enregistrees={len(hg['enregistrees'])} ecart={len(hg['ecart'])} "
        f"deferred={len(hg['deferred'])}"
    )

    dl = views["c5_docloop"]
    print(
        f"c5_docloop     : lecons={len(dl['lecons'])} drift_items={len(dl['drift_items'])} "
        f"routage={len(dl['routage'])}"
    )

    ac = views["c6_aicontrol"]
    print(
        f"c6_aicontrol   : score_observabilite={ac['score_observabilite']['observables']}"
        f"/{ac['score_observabilite']['observables'] + ac['score_observabilite']['not_observable']}"
        f" (not_observable={ac['score_observabilite']['not_observable']})"
    )

    fm = views["c7_forgemap"]
    print(
        f"c7_forgemap    : projet={fm['projet']['v']} missions={len(fm['missions'])} "
        f"nodes=[campagne,agents,artifacts,tests_preuves,decisions]"
    )

    print("--- ecart humangate (detail) ---")
    print(json.dumps(hg["ecart"], indent=2, ensure_ascii=False))

    print("--- score_observabilite (detail) ---")
    print(json.dumps(ac["score_observabilite"], indent=2, ensure_ascii=False))
