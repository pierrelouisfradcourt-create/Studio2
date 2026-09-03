"""Vue PLANNING de Forge Observer V0 — « Que construit-on ensuite ? »

Une seule vue, quatre sections :

    A. jeux_en_cours   — dérivé de la flotte (`fleet.view_fleet`) : le dernier run de
                         chaque projet, regroupé par état lisible (EN ATTENTE DE PIERRE /
                         BLOQUÉ / TERMINÉ-ARCHIVÉ). L'appartenance à TERMINÉ-ARCHIVÉ est
                         tranchée par la même mécanique que `command.view_humangate` : le
                         nom du projet apparaît-il dans `studio_brain/decisions/decision-log.md` ?
    B. registre        — lecture (jamais écriture) de `studio_brain/planning/planning.yaml`
                         s'il existe, avec validation du schéma §06 : une tâche sans
                         `raison` ou sans `preuve_de_fin` est rejetée, jamais ignorée en
                         silence (`rejets`). Le registre n'existe pas encore au moment où
                         ce module est écrit — c'est un fait attendu, pas une anomalie.
    C. backlog_derive  — chantiers candidats dérivés MÉCANIQUEMENT du `drift` (un par
                         type distinct dont l'action résolue vaut CORRIGER) et des leçons
                         `validated` de `lab/reports/lessons.jsonl`. Un lien `related`
                         best-effort (mots-clés simples) relie un chantier drift et un
                         chantier leçon qui semblent parler du même sujet.
    D. proposition_yaml — le backlog dérivé, mis en forme au schéma §06 et écrit dans
                         `lab/reports/observer/<projet>/planning_PROPOSED.yaml` (SEULE
                         écriture de ce module, gardée : refuse tout `out_dir` hors de
                         `lab/reports/observer/`). Propose-only — la promotion vers
                         `studio_brain/planning/` est un geste Pierre, jamais automatique.

Ce module ne lit rien lui-même en dehors de `ObserverContext` (`ctx.read_text` /
`ctx.read_jsonl` / `ctx.exists`), qui lève `BlindnessViolation` si une racine non
déclarée est touchée. Cette exception n'est JAMAIS rattrapée ici. Régime NOT_OBSERVABLE
identique aux autres vues Observer : un manque de mesure ne devient jamais un OK, une
cellule sans preuve porte `NOT_OBSERVABLE` et sa raison — jamais 0 par défaut, jamais
deviné.
"""

from __future__ import annotations

import logging
import re
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any, Optional

LOG = logging.getLogger("observer.system_planning")

NOT_OBSERVABLE = "NOT_OBSERVABLE"

# Bootstrap identique a fleet.py : rend `import observer.*` possible sans install,
# fait AVANT les imports croises inter-modules qui suivent (meme motif que fleet.py,
# a executer au chargement du module, pas seulement dans __main__).
_HERE = Path(__file__).resolve().parent
if str(_HERE.parent) not in sys.path:
    sys.path.insert(0, str(_HERE.parent))

from observer.cockpit import ACTION_PAR_TYPE, OWNER_PAR_TYPE  # noqa: E402
from observer.fleet import view_fleet  # noqa: E402

# Vocabulaire ferme des trois etats lisibles demandes (accents/espaces litteraux,
# ce sont des libelles affiches, pas des identifiants internes).
ETAT_EN_ATTENTE = "EN ATTENTE DE PIERRE"
ETAT_BLOQUE = "BLOQUÉ"
ETAT_TERMINE = "TERMINÉ-ARCHIVÉ"

_ETATS_HUMANGATE: tuple[str, ...] = ("HUMANGATE_READY", "HUMANGATE_READY_WITH_OBJECTION")


# --------------------------------------------------------------------------- #
# Aides communes
# --------------------------------------------------------------------------- #


def _short(text: str, limit: int = 160) -> str:
    text = " ".join(str(text).split())
    return text if len(text) <= limit else text[:limit].rstrip() + "…"


# --------------------------------------------------------------------------- #
# A. jeux_en_cours
# --------------------------------------------------------------------------- #

_TS_RE = re.compile(r"(\d{8}-\d{6})")


def _quand_from_run_id(run_id: Any) -> tuple[Any, Optional[str]]:
    """Horodatage extrait mecaniquement du run_id (motif AAAAMMJJ-HHMMSS, present sur
    la plupart des runs pilotes reels -- voir fleet.py `_RUN_NUM_RE`/`human_name_session`
    pour le meme genre d'extraction par motif). Pas de source canonique de date
    disponible a ce niveau (fleet.py ne rend pas `window.start`), donc extraction depuis
    le run_id est le seul chemin mecanique restant."""
    if not run_id or not isinstance(run_id, str):
        return NOT_OBSERVABLE, "aucun run_id exploitable pour en extraire un horodatage"
    m = _TS_RE.search(run_id)
    if not m:
        return (NOT_OBSERVABLE,
                f"aucun motif d'horodatage (AAAAMMJJ-HHMMSS) trouve dans run_id={run_id!r}")
    d, t = m.group(1).split("-")
    return f"{d[0:4]}-{d[4:6]}-{d[6:8]} {t[0:2]}:{t[2:4]}:{t[4:6]}", None


def _etat_lisible(decision: Any, projet: str,
                   decision_log_text: Optional[str]) -> tuple[str, Optional[str]]:
    if decision == "BLOCKED":
        return ETAT_BLOQUE, None
    if decision in _ETATS_HUMANGATE:
        if decision_log_text is None:
            return (NOT_OBSERVABLE,
                    "decision-log.md illisible ou absent -- impossible de determiner si "
                    "la decision est deja ratifiee et enregistree")
        if re.search(re.escape(projet), decision_log_text, re.IGNORECASE):
            return ETAT_TERMINE, None
        return ETAT_EN_ATTENTE, None
    return (NOT_OBSERVABLE,
            f"decision={decision!r} non classifiable dans les etats connus "
            f"(HUMANGATE_READY[_WITH_OBJECTION] / BLOCKED)")


def _view_jeux_en_cours(ctx: Any, fleet: dict[str, Any]) -> dict[str, Any]:
    decision_log_text = ctx.read_text(ctx.repo_root / "studio_brain" / "decisions" / "decision-log.md")

    dernier_par_projet: dict[str, dict[str, Any]] = {}
    for ligne in fleet.get("lignes", []):
        if ligne.get("v") == "ERREUR":
            continue
        projet = ligne["projet"]["v"]
        if projet in dernier_par_projet:
            continue  # fleet est deja trie plus-recent-en-haut : 1re occurrence = dernier run
        dernier_par_projet[projet] = ligne

    cartes: list[dict[str, Any]] = []
    par_etat: dict[str, list[str]] = defaultdict(list)
    for projet, ligne in sorted(dernier_par_projet.items()):
        decision = ligne["decision"]["v"]
        etat, why = _etat_lisible(decision, projet, decision_log_text)
        quand, quand_why = _quand_from_run_id(ligne["run_id"]["v"])
        carte: dict[str, Any] = {
            "projet": projet,
            "etat_lisible": etat,
            "dernier_run": ligne["nom_humain"]["v"],
            "decision": decision,
            "quand": quand,
            "src": ligne["run_id"].get("src"),
        }
        if why:
            carte["etat_lisible_why"] = why
        if quand_why:
            carte["quand_why"] = quand_why
        cartes.append(carte)
        par_etat[etat].append(projet)

    return {
        "cartes": cartes,
        "par_etat": {k: sorted(v) for k, v in par_etat.items()},
        "regle": "TERMINE-ARCHIVE = decision HUMANGATE_READY[_WITH_OBJECTION] ET le nom du "
                 "projet apparait dans decision-log.md (meme mecanique que "
                 "command.view_humangate) ; sinon EN ATTENTE DE PIERRE. BLOCKED = BLOQUE.",
    }


# --------------------------------------------------------------------------- #
# B. registre — lecture seule de studio_brain/planning/planning.yaml
# --------------------------------------------------------------------------- #

_REQUIRED_TASK_FIELDS: tuple[str, ...] = ("id", "objectif", "raison", "priorite", "etat",
                                           "preuve_de_fin")
_VALID_ETATS: frozenset[str] = frozenset({"EN_ATTENTE", "EN_COURS", "BLOQUE", "TERMINE"})


def _load_registre(ctx: Any) -> dict[str, Any]:
    path = ctx.repo_root / "studio_brain" / "planning" / "planning.yaml"
    if not ctx.exists(path):
        return {
            "v": NOT_OBSERVABLE,
            "why": "le registre n'existe pas encore — proposition generee ci-dessous, "
                   "promotion = geste Pierre",
            "taches": [],
            "rejets": [],
        }

    text = ctx.read_text(path)
    if text is None:
        return {
            "v": NOT_OBSERVABLE,
            "why": "studio_brain/planning/planning.yaml existe mais est illisible",
            "taches": [], "rejets": [],
        }

    try:
        import yaml
    except ImportError:
        LOG.warning("PyYAML indisponible : registre planning.yaml non parse")
        return {
            "v": NOT_OBSERVABLE,
            "why": "PyYAML indisponible dans cet interpreteur : registre non parse",
            "taches": [], "rejets": [],
        }

    try:
        data = yaml.safe_load(text)
    except yaml.YAMLError as exc:
        LOG.warning("planning.yaml illisible: %s", exc)
        return {
            "v": NOT_OBSERVABLE,
            "why": f"planning.yaml n'est pas un YAML valide : {exc}",
            "taches": [], "rejets": [],
        }

    if isinstance(data, list):
        raw_taches: Any = data
    elif isinstance(data, dict):
        raw_taches = data.get("taches") or data.get("tasks") or []
    else:
        raw_taches = None

    if not isinstance(raw_taches, list):
        return {
            "v": NOT_OBSERVABLE,
            "why": "format de planning.yaml non reconnu (attendu : une liste de taches, "
                   "ou un dict portant la cle 'taches')",
            "taches": [], "rejets": [],
        }

    taches: list[dict[str, Any]] = []
    rejets: list[dict[str, Any]] = []
    for i, item in enumerate(raw_taches):
        if not isinstance(item, dict):
            rejets.append({"index": i, "id": NOT_OBSERVABLE,
                            "motif": "entree qui n'est pas un objet (tache mal formee)"})
            continue
        manquants = [f for f in _REQUIRED_TASK_FIELDS if not item.get(f)]
        if manquants:
            rejets.append({
                "id": item.get("id", NOT_OBSERVABLE),
                "motif": f"champ(s) obligatoire(s) manquant(s) ou vide(s) : "
                         f"{', '.join(manquants)}",
            })
            continue
        if item["etat"] not in _VALID_ETATS:
            rejets.append({
                "id": item["id"],
                "motif": f"etat {item['etat']!r} hors du vocabulaire ferme "
                         f"{sorted(_VALID_ETATS)}",
            })
            continue
        taches.append(item)

    return {
        "v": taches if taches else NOT_OBSERVABLE,
        "why": None if taches else "le registre existe mais ne contient aucune tache valide",
        "taches": taches,
        "rejets": rejets,
    }


# --------------------------------------------------------------------------- #
# C. backlog_derive
# --------------------------------------------------------------------------- #

# Reformulation lisible de l'objectif par type de drift CORRIGER connu -- deterministe,
# pas de LLM. Un type CORRIGER absent de cette table (extension future de la Forge)
# reste couvert par le repli generique de `_objectif_drift` : jamais un chantier perdu.
_OBJECTIF_PAR_TYPE: dict[str, str] = {
    "token_accounting_below_measured": (
        "Aligner la comptabilite de tokens de la Forge sur les tokens reellement "
        "mesures dans les transcripts."),
    "model_audit_differs_from_transcript": (
        "Faire correspondre le modele declare par la Forge au modele reellement "
        "observe dans les transcripts."),
    "tools_used_beyond_declared": (
        "Mettre a jour la liste d'outils declaree pour couvrir les outils reellement "
        "utilises par l'agent."),
    "tools_used_without_declaration": (
        "Exiger une declaration d'outils pour toute activation dispatchee."),
    "tool_observability_not_measured": (
        "Corriger le statut de mesure des outils quand des appels sont observables "
        "dans les transcripts."),
    "prompt_sans_empreinte_declaree": (
        "Signer une empreinte de prompt pour chaque activation."),
    "prompt_recu_differe_du_prompt_signe": (
        "Garantir que le prompt recu par l'agent correspond au prompt signe par la "
        "Forge."),
    "lecon_routee_sans_consommateur": (
        "Relier chaque lecon validee a un consommateur mecanique reel."),
    "roadmap_doctrine_vs_mesure": (
        "Reconcilier la doctrine affichee (roadmap) avec l'etat mesure reel."),
    "file_written_outside_game_and_lab": (
        "Border l'ecriture de fichiers au perimetre attendu (games/ ou lab/)."),
}


def _drift_action(item: dict[str, Any]) -> Optional[str]:
    """Meme resolution que `cockpit.view_drift_table` : le champ embarque par le
    detecteur fait foi (cas famille documentation), sinon repli sur la table."""
    if item.get("action"):
        return item["action"]
    return ACTION_PAR_TYPE.get(item.get("type"))


def _objectif_drift(kind: str, occurrences: list[dict[str, Any]]) -> str:
    if kind in _OBJECTIF_PAR_TYPE:
        return _OBJECTIF_PAR_TYPE[kind]
    detail = occurrences[0].get("detail") or kind
    return f"Corriger l'ecart « {kind} » ({_short(str(detail), 120)})."


def _priorite_drift(occurrences: list[dict[str, Any]]) -> int:
    """1 si high, 2 si medium (regle demandee). 3 pour tout le reste (info/inconnu) --
    extension necessaire pour ne jamais faire disparaitre un chantier dont la
    gravite n'est ni high ni medium, jamais couverte silencieusement par 1 ou 2."""
    severites = {o.get("severity") for o in occurrences}
    if "high" in severites:
        return 1
    if "medium" in severites:
        return 2
    return 3


def _provenance_drift(occurrences: list[dict[str, Any]]) -> list[str]:
    out: set[str] = set()
    for o in occurrences:
        src = o.get("source")
        candidats = src if isinstance(src, list) else [src]
        for c in candidats:
            if isinstance(c, dict) and c.get("path"):
                out.add(c["path"])
    return sorted(out)


def _details_excerpt(occurrences: list[dict[str, Any]], limit: int = 2) -> str:
    """Extraits DISTINCTS de `detail` (jusqu'a `limit`) -- la raison doit porter le
    contenu reel de l'ecart, pas seulement son type : c'est aussi ce texte que le
    rapprochement `related` (mots-cles) interroge, un chantier sans extrait de detail
    ne peut jamais etre relie a une lecon qui parle du meme sujet."""
    seen: list[str] = []
    for o in occurrences:
        d = o.get("detail")
        if d and d not in seen:
            seen.append(str(d))
        if len(seen) >= limit:
            break
    return " / ".join(_short(d, 140) for d in seen)


def _owner_drift(kind: str, occurrences: list[dict[str, Any]]) -> Any:
    for o in occurrences:
        if o.get("owner"):
            return o["owner"]
    return OWNER_PAR_TYPE.get(kind, NOT_OBSERVABLE)


def _backlog_from_drift(result: dict[str, Any]) -> list[dict[str, Any]]:
    par_type: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for item in result.get("drift", []):
        kind = item.get("type")
        if not kind or _drift_action(item) != "CORRIGER":
            continue
        par_type[kind].append(item)

    chantiers: list[dict[str, Any]] = []
    for kind, occurrences in sorted(par_type.items()):
        provenance = _provenance_drift(occurrences)
        excerpt = _details_excerpt(occurrences)
        chantiers.append({
            "id": f"drift:{kind}",
            "source": "drift",
            "objectif": _objectif_drift(kind, occurrences),
            "raison": f"{kind} observe {len(occurrences)} fois"
                      f"{' : ' + excerpt if excerpt else ''} (provenance : "
                      f"{', '.join(provenance) if provenance else 'non tracee dans les evenements'})",
            "priorite_suggeree": _priorite_drift(occurrences),
            "preuve_de_fin": "le detecteur Observer ne remonte plus ce type d'ecart",
            "owner": _owner_drift(kind, occurrences),
            "n_occurrences": len(occurrences),
            "run_ids": sorted({o.get("run_id") for o in occurrences if o.get("run_id")}),
        })
    return chantiers


def _backlog_from_lessons(ctx: Any) -> list[dict[str, Any]]:
    lessons_path = ctx.repo_root / "lab" / "reports" / "lessons.jsonl"
    latest: dict[str, dict[str, Any]] = {}
    for _, obj in ctx.read_jsonl(lessons_path):
        lid = obj.get("lesson_id")
        if not lid:
            continue
        prev = latest.get(lid)
        if prev is None or (obj.get("ts") or 0.0) >= (prev.get("ts") or 0.0):
            latest[lid] = obj

    chantiers: list[dict[str, Any]] = []
    for lid, obj in sorted(latest.items()):
        if obj.get("status") != "validated":
            continue
        statement = str(obj.get("statement") or "")
        supporting = obj.get("supporting_runs") or []
        chantiers.append({
            "id": f"lesson:{lid}",
            "source": "lesson",
            "objectif": _short(statement, 200) or f"Appliquer la lecon validee {lid}.",
            "raison": f"lecon validee '{lid}' : {_short(statement, 160)} "
                      f"(supporting_runs: {supporting})",
            "priorite_suggeree": NOT_OBSERVABLE,
            "priorite_suggeree_why": "aucune regle de priorisation n'est definie pour les "
                                      "chantiers derives de lecons (seule la regle severite"
                                      "->priorite du drift est specifiee)",
            "preuve_de_fin": NOT_OBSERVABLE,
            "preuve_de_fin_why": "la lecon ne declare pas d'oracle de fin — a definir a la "
                                  "ratification",
            "owner": NOT_OBSERVABLE,
            "owner_why": "aucune lecon ne declare de champ owner/destination mecanique "
                         "exploitable ici",
            "n_occurrences": len(supporting),
            "run_ids": sorted(supporting),
        })
    return chantiers


def _dedupe_by_id(chantiers: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: dict[str, dict[str, Any]] = {}
    for c in chantiers:
        seen.setdefault(c["id"], c)
    return list(seen.values())


# Mots-cles simples pour le rapprochement drift x lecon -- best-effort assume, pas une
# recherche semantique. Sous-chaine, insensible a la casse.
_RELATED_KEYWORDS: tuple[str, ...] = (
    "timeout", "oracle", "token", "wiremap", "scratchpad", "modele", "model",
    "prompt", "outil", "tool", "reference", "permission", "doctrine", "roadmap",
    "consommateur", "empreinte",
)


def _searchable(chantier: dict[str, Any]) -> str:
    return f"{chantier.get('objectif', '')} {chantier.get('raison', '')}".lower()


def _link_related(chantiers: list[dict[str, Any]]) -> None:
    """Croisement drift x lecon UNIQUEMENT (litteral a la demande) : deux chantiers
    drift entre eux, ou deux lecons entre elles, ne sont jamais relies ici. Mutation en
    place (ajoute `related` sur les elements concernes)."""
    drifts = [c for c in chantiers if c["source"] == "drift"]
    lecons = [c for c in chantiers if c["source"] == "lesson"]
    textes = {c["id"]: _searchable(c) for c in chantiers}

    for d in drifts:
        for l in lecons:
            hits = [kw for kw in _RELATED_KEYWORDS
                    if kw in textes[d["id"]] and kw in textes[l["id"]]]
            if not hits:
                continue
            d.setdefault("related", []).append(
                {"id": l["id"], "match": "best_effort_keywords", "keywords": hits})
            l.setdefault("related", []).append(
                {"id": d["id"], "match": "best_effort_keywords", "keywords": hits})


def _view_backlog_derive(ctx: Any, result: dict[str, Any]) -> dict[str, Any]:
    drift_chantiers = _backlog_from_drift(result)
    lesson_chantiers = _backlog_from_lessons(ctx)
    chantiers = _dedupe_by_id(drift_chantiers + lesson_chantiers)
    _link_related(chantiers)
    n_related = sum(1 for c in chantiers if c.get("related"))

    return {
        "chantiers": chantiers,
        "n_depuis_drift": len(drift_chantiers),
        "n_depuis_lecons": len(lesson_chantiers),
        "n_avec_related": n_related,
        "note_related": "correspondance best-effort par mots-cles simples, croisement "
                         "drift x lecon uniquement — ne remplace pas une revue humaine",
    }


# --------------------------------------------------------------------------- #
# D. proposition_yaml — seule ecriture de ce module, strictement gardee
# --------------------------------------------------------------------------- #

_PLACEHOLDER = "A_DEFINIR_A_LA_RATIFICATION"


def _tache_yaml_dict(chantier: dict[str, Any]) -> dict[str, Any]:
    priorite = chantier.get("priorite_suggeree")
    preuve = chantier.get("preuve_de_fin")
    owner = chantier.get("owner")
    return {
        "id": chantier["id"],
        "objectif": chantier["objectif"],
        "raison": chantier["raison"],
        "priorite": priorite if priorite != NOT_OBSERVABLE else _PLACEHOLDER,
        "etat": "EN_ATTENTE",
        "depends_on": sorted({r["id"] for r in chantier.get("related", [])}),
        "decision_attendue": _PLACEHOLDER,
        "preuve_de_fin": preuve if preuve != NOT_OBSERVABLE else _PLACEHOLDER,
        "owner": owner if owner != NOT_OBSERVABLE else _PLACEHOLDER,
        "source": chantier["source"],
    }


def _build_proposition_yaml_text(chantiers: list[dict[str, Any]], project: str) -> str:
    header = (
        "# PROPOSITION generee par Observer (scripts/observer/system_planning.py).\n"
        "# propose-only : la promotion vers studio_brain/planning/planning.yaml est un\n"
        "# geste Pierre, jamais automatique.\n"
        f"# Projet source des donnees : {project}.\n"
        "# Schema attendu (§06) : id, objectif, raison, priorite, etat, depends_on,\n"
        "# decision_attendue, preuve_de_fin. Valeurs 'A_DEFINIR_A_LA_RATIFICATION' =\n"
        "# NOT_OBSERVABLE mecaniquement, jamais devinees par Observer.\n"
    )
    taches = [_tache_yaml_dict(c) for c in chantiers]
    try:
        import yaml
        body = yaml.safe_dump({"taches": taches}, allow_unicode=True, sort_keys=False,
                               default_flow_style=False)
    except ImportError:
        # Repli sans PyYAML : JSON est un sous-ensemble valide de YAML -- jamais un
        # plantage pour une dependance optionnelle absente de l'interpreteur courant.
        import json
        LOG.warning("PyYAML indisponible : proposition ecrite en JSON (sous-ensemble YAML valide)")
        body = json.dumps({"taches": taches}, indent=2, ensure_ascii=False)
    return header + body


def _write_proposition(ctx: Any, out_dir: Optional[Path],
                        text: str) -> tuple[Optional[str], Optional[str]]:
    """La SEULE ecriture de ce module. `out_dir=None` = pas d'ecriture (defaut). Garde
    dure : refuse d'ecrire hors de `lab/reports/observer/` -- jamais dans
    `studio_brain/`, meme si l'appelant se trompe de chemin."""
    if out_dir is None:
        return None, None

    out_path = Path(out_dir).resolve()
    guard_root = (ctx.repo_root / "EVIDENCE" / "reports" / "observer").resolve()
    try:
        out_path.relative_to(guard_root)
    except ValueError:
        why = (f"out_dir {out_path} n'est pas sous lab/reports/observer/ -- ecriture "
               "refusee (seule sortie autorisee pour Observer)")
        LOG.error(why)
        return None, why

    out_path.mkdir(parents=True, exist_ok=True)
    file_path = out_path / "planning_PROPOSED.yaml"
    file_path.write_text(text, encoding="utf-8")
    return str(file_path), None


def _view_proposition_yaml(ctx: Any, project: str, chantiers: list[dict[str, Any]],
                            out_dir: Optional[Path]) -> dict[str, Any]:
    text = _build_proposition_yaml_text(chantiers, project)
    written_path, write_why = _write_proposition(ctx, out_dir, text)

    out: dict[str, Any] = {
        "chemin": written_path if written_path else NOT_OBSERVABLE,
        "note": "proposition — la promotion vers studio_brain/planning/planning.yaml "
                "est un geste Pierre",
        "contenu_preview": "\n".join(text.splitlines()[:15]),
    }
    if written_path is None:
        out["why"] = write_why or "out_dir=None : aucune ecriture demandee par l'appelant"
    return out


# --------------------------------------------------------------------------- #
# Assemblage
# --------------------------------------------------------------------------- #


def view_planning(ctx: Any, result: dict[str, Any], events: list[dict[str, Any]],
                   out_dir: Optional[Path] = None) -> dict[str, Any]:
    project = result.get("project") or ctx.project

    fleet = view_fleet(ctx.repo_root, ctx.transcripts_root, project, result)
    jeux = _view_jeux_en_cours(ctx, fleet)
    registre = _load_registre(ctx)
    backlog = _view_backlog_derive(ctx, result)
    proposition = _view_proposition_yaml(ctx, project, backlog["chantiers"], out_dir)

    n_en_attente = sum(1 for c in jeux["cartes"] if c["etat_lisible"] == ETAT_EN_ATTENTE)
    n_backlog = len(backlog["chantiers"])
    if isinstance(registre["v"], list):
        registre_msg = f"{len(registre['v'])} tache(s) active(s) dans le registre ratifie"
    else:
        registre_msg = "aucun registre ratifie n'existe encore"
    resume = (
        f"{n_en_attente} jeu(x) attend(ent) une decision de Pierre. "
        f"{n_backlog} chantier(s) candidat(s) derive(s) des ecarts et lecons ; "
        f"{registre_msg}."
    )

    return {
        "question": "Que construit-on ensuite ?",
        "resume": resume,
        "jeux_en_cours": jeux,
        "registre": registre,
        "backlog_derive": backlog,
        "proposition_yaml": proposition,
    }


def build_planning_views(ctx: Any, result: dict[str, Any], events: list[dict[str, Any]],
                          out_dir: Optional[Path] = None) -> dict[str, Any]:
    return {"s8_planning": view_planning(ctx, result, events, out_dir=out_dir)}


# --------------------------------------------------------------------------- #
# Preuve d'execution
# --------------------------------------------------------------------------- #

if __name__ == "__main__":
    import json

    from observer.sources import ObserverContext, default_repo_root, default_transcripts_root  # noqa: E402
    from observer.system_artefacts import build_artefact_views  # noqa: E402

    logging.basicConfig(level=logging.WARNING)

    repo_root = default_repo_root()
    transcripts_root = default_transcripts_root(repo_root)
    project = "breakout_v2"
    ctx = ObserverContext.build(repo_root, project, transcripts_root)

    report_dir = repo_root / "EVIDENCE" / "reports" / "observer" / project
    with (report_dir / "observer_run.json").open("r", encoding="utf-8-sig") as fh:
        result = json.load(fh)

    events: list[dict[str, Any]] = []
    with (report_dir / "events.jsonl").open("r", encoding="utf-8-sig") as fh:
        for line in fh:
            line = line.strip()
            if line:
                events.append(json.loads(line))

    views = build_planning_views(ctx, result, events, out_dir=report_dir)
    planning = views["s8_planning"]

    print(f"question : {planning['question']}")
    print(f"resume   : {planning['resume']}")

    print("\n--- jeux_en_cours par etat ---")
    for etat, projets in sorted(planning["jeux_en_cours"]["par_etat"].items()):
        print(f"  {etat:<24} {len(projets)} projet(s) : {projets}")

    backlog = planning["backlog_derive"]
    print(f"\n--- backlog_derive : {len(backlog['chantiers'])} chantier(s) ---")
    print(f"  depuis drift  : {backlog['n_depuis_drift']}")
    print(f"  depuis lecons : {backlog['n_depuis_lecons']}")
    print(f"  avec related  : {backlog['n_avec_related']}")
    for c in backlog["chantiers"]:
        rel = f" related={[r['id'] for r in c['related']]}" if c.get("related") else ""
        print(f"  [{c['source']:<6}] {c['id']:<55} prio={c['priorite_suggeree']}{rel}")

    reg = planning["registre"]
    print("\n--- registre ---")
    print(f"  v={reg['v']!r}")
    print(f"  why={reg.get('why')!r}")
    print(f"  rejets={len(reg['rejets'])}")

    prop = planning["proposition_yaml"]
    print("\n--- proposition_yaml ---")
    print(f"  chemin: {prop['chemin']}")
    print("  15 premieres lignes :")
    for line in prop["contenu_preview"].splitlines():
        print(f"    {line}")

    print("\n--- s5_artefacts : un exemple avec ses 4 roles ---")
    art_views = build_artefact_views(ctx, result, events)
    art = art_views["s5_artefacts"]
    exemple = None
    for cat, data in art["categories"].items():
        for rec in data["artefacts"]:
            if rec["produit_par"]["v"] != NOT_OBSERVABLE:
                exemple = (cat, rec)
                break
        if exemple:
            break
    if exemple:
        cat, rec = exemple
        print(f"  categorie   : {cat}")
        print(f"  chemin      : {rec['chemin']}")
        print(f"  produit_par : {rec['produit_par']['v']}")
        print(f"  consomme_par.observes.n : {rec['consomme_par']['observes']['n']}")
        print(f"  valide_par  : {rec['valide_par']['v']}")
        print(f"  archive_par : {rec['archive_par']['v']}")
    else:
        print("  aucun artefact avec producteur observe dans ce run")
