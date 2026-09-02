"""Vues operateur — le cockpit quotidien.

Trois tableaux, concus pour repondre vite a quatre questions :

    Qu'est-ce qui s'est passe ?          -> vue Campagnes
    Ou la Forge derive-t-elle ?          -> vue Drift
    Qu'est-ce qui s'ameliore ?           -> colonnes `delta` de la vue Campagnes
    Quelle anomalie merite une action ?  -> tri par gravite + colonne `action`

Regle non negociable de ce module : **un manque de mesure ne devient jamais un
OK**. Une cellule sans donnee porte `NOT_OBSERVABLE` et sa raison. Une cellule
a zero signifie « mesure faite, resultat nul » — jamais « pas mesure ».

Tableaux avant graphes : chaque vue rend des lignes et des colonnes nommees,
directement affichables, chacune portant sa provenance.
"""

from __future__ import annotations

import hashlib
from collections import Counter
from typing import Any, Optional

NOT_OBSERVABLE = "NOT_OBSERVABLE"

# Colonnes de la vue Campagnes, dans l'ordre d'affichage.
CAMPAGNE_COLONNES: tuple[tuple[str, str], ...] = (
    ("run_id", "run"),
    ("projet", "projet"),
    ("verdict", "verdict"),
    ("duree_s", "duree (s)"),
    ("tokens_mesures", "tokens mesures"),
    ("cout_declare_usd", "cout declare ($)"),
    ("cout_verifiable_usd", "cout verifiable ($)"),
    ("activations", "activations"),
    ("agents", "agents"),
    ("outils_utilises", "outils utilises"),
    ("outils_hors_contrat", "outils hors contrat"),
    ("fichiers_lus", "fichiers lus"),
    ("fichiers_ecrits", "fichiers ecrits"),
    ("tests", "tests"),
    ("mutation", "mutation"),
    ("solvabilite", "solvabilite"),
    ("failure_events", "failure_events"),
)

# Sens d'amelioration par colonne : +1 = plus c'est haut, mieux c'est ;
# -1 = plus c'est bas, mieux c'est ; 0 = pas d'ordre naturel.
SENS: dict[str, int] = {
    "duree_s": -1,
    "tokens_mesures": -1,
    "cout_declare_usd": -1,
    "activations": -1,
    "outils_hors_contrat": -1,
    "failure_events": -1,
    "mutation": +1,
    "tests": +1,
}


def _short(text: Any, limit: int = 200) -> str:
    """Meme utilitaire que system_planning._short / evidence._short — troncature
    lisible d'un champ prose, jamais un JSON brut dans une cellule bandeau."""
    text = " ".join(str(text).split())
    return text if len(text) <= limit else text[:limit].rstrip() + "…"


def _cell(value: Any, src: Optional[dict] = None,
          why: Optional[str] = None) -> dict[str, Any]:
    """Une cellule de tableau : valeur, provenance, et raison si non observable."""
    out: dict[str, Any] = {"v": value}
    if src:
        out["src"] = src
    if value == NOT_OBSERVABLE and why:
        out["why"] = why
    return out


def _src(events: list[dict], kind: str, run_id: str | None = None,
         field: str | None = None) -> Optional[dict]:
    for ev in events:
        if ev["kind"] != kind:
            continue
        if run_id and ev.get("run_id") != run_id:
            continue
        s = ev.get("source", {}) or {}
        out = {"path": s.get("path", "")}
        if s.get("line") is not None:
            out["line"] = s["line"]
        if field:
            out["field"] = field
        return out
    return None


def _evs(events: list[dict], kind: str, run_id: str | None = None) -> list[dict]:
    out = [e for e in events if e["kind"] == kind]
    if run_id:
        out = [e for e in out if e.get("run_id") == run_id]
    return out


# --------------------------------------------------------------------------- #
# Vue Campagnes
# --------------------------------------------------------------------------- #


def view_campagnes(result: dict[str, Any], events: list[dict]) -> dict[str, Any]:
    projet = result.get("project")
    lignes: list[dict[str, Any]] = []

    for run in result.get("runs", []):
        run_id = run["run_id"]
        totals = run.get("totals") or {}
        mesures = totals.get("tokens_measured_in_transcripts") or {}
        tokens = (mesures.get("input", 0) + mesures.get("output", 0)
                  + mesures.get("cache_creation", 0)) if mesures else None

        execs = _evs(events, "dispatch.executed", run_id)
        sessions = {e["payload"].get("session_id")
                    for e in _evs(events, "agent.session", run_id)
                    if e["payload"].get("activity_attributed")}

        appels = Counter(e["payload"].get("tool_name")
                         for e in _evs(events, "tool.call", run_id)
                         if e["payload"].get("tool_name"))
        declares: set[str] = set()
        for ev in _evs(events, "dispatch.context_manifest", run_id):
            t = ev["payload"].get("tools_effective")
            if isinstance(t, list):
                declares.update(str(x) for x in t)
        hors = sorted(set(appels) - declares) if declares else sorted(appels)

        lus = {e["payload"].get("path") for e in _evs(events, "file.read", run_id)} - {None}
        ecrits = ({e["payload"].get("path") for e in _evs(events, "file.write", run_id)}
                  | {e["payload"].get("path") for e in _evs(events, "file.edit", run_id)}
                  ) - {None}

        tests = next(iter(_evs(events, "test.result", run_id)), None)
        mutation = next(iter(_evs(events, "mutation.result", run_id)), None)
        solva = next(iter(_evs(events, "solvability.result", run_id)), None)
        failures = _evs(events, "failure.event", run_id)

        verdict = run.get("decision")
        duree = (run.get("window") or {}).get("duration_s")

        ligne = {
            "run_id": _cell(run_id, _src(events, "run.declared", run_id)),
            "projet": _cell(projet),
            "verdict": _cell(verdict or NOT_OBSERVABLE,
                             _src(events, "verdict.signed", run_id, "decision"),
                             "aucun verdict signe n'existe pour ce run"),
            "duree_s": _cell(duree if duree is not None else NOT_OBSERVABLE,
                             _src(events, "run.declared", run_id),
                             "aucun evenement date rattache a ce run"),
            "tokens_mesures": _cell(tokens if tokens else NOT_OBSERVABLE,
                                    _src(events, "llm.usage", run_id, "usage"),
                                    "aucun transcript rattache a ce run"),
            "cout_declare_usd": _cell(
                totals.get("cost_usd_declared")
                if totals.get("cost_usd_declared") is not None else NOT_OBSERVABLE,
                _src(events, "telemetry.step", run_id, "cost_usd"),
                "la telemetrie ne porte pas de cout pour ce run"),
            # Volontairement NON derive du cout declare : sans grille tarifaire
            # ni formule dans les traces, aucun montant n'est recalculable.
            # Recopier le declare ici reviendrait a maquiller une absence de
            # verification en verification.
            "cout_verifiable_usd": _cell(
                NOT_OBSERVABLE, None,
                "aucune grille tarifaire ni formule n'accompagne les traces : "
                "le montant declare ne peut etre ni recalcule ni contredit"),
            "activations": _cell(len(execs),
                                 _src(events, "dispatch.executed", run_id)),
            "agents": _cell(len(sessions),
                            _src(events, "agent.session", run_id)),
            "outils_utilises": _cell(sum(appels.values()),
                                     _src(events, "tool.call", run_id, "tool_name")),
            "outils_hors_contrat": _cell(
                len(hors) if declares else NOT_OBSERVABLE,
                _src(events, "dispatch.context_manifest", run_id, "tools_effective"),
                "aucune liste d'outils n'est declaree : l'ecart n'est pas calculable"),
            "fichiers_lus": _cell(len(lus), _src(events, "file.read", run_id, "path")),
            "fichiers_ecrits": _cell(len(ecrits),
                                     _src(events, "file.write", run_id, "path")),
            "tests": _cell(
                f"{tests['payload'].get('passed')}/{tests['payload'].get('failed')} (ok/ko)"
                if tests else NOT_OBSERVABLE,
                _src(events, "test.result", run_id, "passed"),
                "aucun oracle de test n'a produit de resultat pour ce run"),
            "mutation": _cell(
                f"{mutation['payload'].get('killed')}/{mutation['payload'].get('total')}"
                if mutation else NOT_OBSERVABLE,
                _src(events, "mutation.result", run_id, "killed"),
                "aucun recu de mutation pour ce run"),
            "solvabilite": _cell(
                f"{solva['payload'].get('won')}/{solva['payload'].get('trials')}"
                if solva else NOT_OBSERVABLE,
                _src(events, "solvability.result", run_id, "won"),
                "la solvabilite n'a pas ete mesuree sur ce run"),
            "failure_events": _cell(len(failures),
                                    _src(events, "failure.event", run_id, "error")),
            "_role": run.get("role"),
            "_detail_hors_contrat": hors,
        }
        lignes.append(ligne)

    lignes.sort(key=lambda l: str(l["run_id"]["v"]))
    tentatives = [l for l in lignes if l["_role"] == "attempt"]
    return {
        "colonnes": [{"cle": k, "titre": t} for k, t in CAMPAGNE_COLONNES],
        "lignes": lignes,
        "progression": _progression(tentatives),
        "note_cout": "« cout verifiable » reste NOT_OBSERVABLE par construction : "
                     "Observer refuse de presenter un montant qu'il ne peut pas "
                     "recalculer comme s'il l'avait verifie",
    }


def _progression(tentatives: list[dict]) -> list[dict[str, Any]]:
    """Ce qui s'ameliore, ce qui se degrade, d'une tentative a la suivante."""
    out: list[dict[str, Any]] = []
    for prev, curr in zip(tentatives, tentatives[1:]):
        deltas: list[dict[str, Any]] = []
        for cle, sens in SENS.items():
            a, b = prev.get(cle, {}).get("v"), curr.get(cle, {}).get("v")
            a_num, b_num = _num(a), _num(b)
            if a_num is None or b_num is None:
                deltas.append({
                    "colonne": cle, "avant": a, "apres": b,
                    "tendance": NOT_OBSERVABLE,
                    "why": "une des deux valeurs n'est pas mesuree : la comparaison "
                           "n'a pas de sens",
                })
                continue
            ecart = round(b_num - a_num, 4)
            if ecart == 0:
                tendance = "STABLE"
            elif (ecart > 0) == (sens > 0):
                tendance = "MIEUX"
            else:
                tendance = "MOINS_BIEN"
            deltas.append({"colonne": cle, "avant": a, "apres": b,
                           "delta": ecart, "tendance": tendance})
        out.append({
            "de": prev["run_id"]["v"], "vers": curr["run_id"]["v"], "deltas": deltas,
        })
    return out


def _num(value: Any) -> Optional[float]:
    if isinstance(value, bool) or value == NOT_OBSERVABLE or value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str) and "/" in value:
        head = value.split("/")[0].strip()
        try:
            return float(head)
        except ValueError:
            return None
    return None


# --------------------------------------------------------------------------- #
# Vue Drift — declaration vs execution, ligne par ligne
# --------------------------------------------------------------------------- #

# Les quatre confrontations demandees, plus celles que les traces permettent.
DRIFT_CATEGORIES: dict[str, tuple[str, str]] = {
    "model_audit_differs_from_transcript": ("modele", "modele declare / modele observe"),
    "tools_used_beyond_declared": ("outils", "outils autorises / outils utilises"),
    "tools_used_without_declaration": ("outils", "aucune declaration / outils utilises"),
    "tool_observability_not_measured": ("outils", "mesure des outils declaree absente"),
    "prompt_recu_differe_du_prompt_signe": ("prompt", "prompt signe / prompt recu"),
    "prompt_sans_empreinte_declaree": ("prompt", "prompt recu sans empreinte signee"),
    "token_accounting_below_measured": ("effort", "tokens declares / tokens mesures"),
    "reference_guard_drift": ("perimetre", "fichiers proteges / fichiers modifies"),
    "file_written_outside_game_and_lab": ("perimetre", "perimetre attendu / ecriture reelle"),
    "file_written_in_session_scratchpad": ("perimetre", "ecriture hors depot (jetable)"),
    "dispatch_prepared_never_executed": ("dispatch", "dispatch prepare / execution"),
}


# --------------------------------------------------------------------------- #
# Taxonomies de fusion — famille / proprietaire / impact / action.
#
# Regle dure (ratifiee) : AUCUN drift n'est force dans une categorie. Un type
# absent d'une table rend NOT_OBSERVABLE avec sa raison plutot qu'une valeur
# devinee. Les quatre tables sont des dictionnaires exacts, jamais de la
# logique floue (pas de "si severity == high alors...").
# --------------------------------------------------------------------------- #

FAMILLE_PAR_TYPE: dict[str, str] = {
    "model_audit_differs_from_transcript": "declaration",
    "tools_used_beyond_declared": "contrat",
    "tools_used_without_declaration": "declaration",
    "tool_observability_not_measured": "metrique",
    "prompt_sans_empreinte_declaree": "declaration",
    "prompt_recu_differe_du_prompt_signe": "declaration",
    "token_accounting_below_measured": "metrique",
    "reference_guard_drift": "comportement",
    "file_written_outside_game_and_lab": "comportement",
    "file_written_in_session_scratchpad": "comportement",
    "dispatch_prepared_never_executed": "declaration",
}
_FAMILLE_INCONNU_WHY = "type d'ecart non repertorie dans la table de familles"

OWNER_PAR_TYPE: dict[str, str] = {
    "token_accounting_below_measured": "HARNAIS",
    "tools_used_beyond_declared": "HARNAIS",
    "tool_observability_not_measured": "HARNAIS",
    "prompt_recu_differe_du_prompt_signe": "HARNAIS",
    "model_audit_differs_from_transcript": "REGISTRE",
    "reference_guard_drift": "HUMANGATE",
    "file_written_outside_game_and_lab": "CONTRAT",
}
_OWNER_NOT_OBSERVABLE_WHY: dict[str, str] = {
    "tools_used_without_declaration": (
        "activation dispatchee hors de l'executeur standard (outil Task) : "
        "aucune des cinq categories ne borne ce chemin aujourd'hui"),
    "prompt_sans_empreinte_declaree": (
        "le chemin de dispatch par outil Task ne signe pas d'empreinte : "
        "proprietaire a etablir a la gate du capteur"),
    "file_written_in_session_scratchpad": (
        "constat informatif — trace d'une verification reellement executee ; "
        "aucune reponse requise"),
    "dispatch_prepared_never_executed": (
        "artefact de dry-run ; aucune reponse requise"),
}
_OWNER_INCONNU_WHY = "type d'ecart non repertorie dans la table des proprietaires"

IMPACT_PAR_TYPE: dict[str, str] = {
    "token_accounting_below_measured":
        "toute decision de cout fondee sur la telemetrie est faussee",
    "model_audit_differs_from_transcript":
        "la signature ne garantit plus quel modele a reellement travaille",
    "tools_used_beyond_declared":
        "le perimetre d'outils promis par le contrat n'est pas garanti a l'execution",
    "tools_used_without_declaration":
        "aucune borne d'outils verifiable pour cette activation",
    "tool_observability_not_measured":
        "une mesure declaree absente alors que la donnee est observable",
    "prompt_sans_empreinte_declaree":
        "conformite du prompt ni prouvable ni refutable",
    "prompt_recu_differe_du_prompt_signe":
        "l'agent n'a pas recu le texte que la Forge a signe",
    "reference_guard_drift":
        "un fichier protege a change pendant le run sans derogation",
    "file_written_outside_game_and_lab":
        "ecriture dans le depot hors du perimetre attendu du run",
    "file_written_in_session_scratchpad":
        "verification reellement executee hors depot (informatif)",
    "dispatch_prepared_never_executed":
        "dispatch signe sans execution correspondante",
}
_IMPACT_INCONNU_WHY = "type d'ecart non repertorie dans la table d'impact"

# RATIFIER | CORRIGER | ACCEPTER | SURVEILLER — vocabulaire ferme.
# CORRIGER signifie chantier gated : Observer signale, il ne corrige rien.
ACTION_PAR_TYPE: dict[str, str] = {
    "reference_guard_drift": "RATIFIER",
    "file_written_outside_game_and_lab": "RATIFIER",
    "token_accounting_below_measured": "CORRIGER",
    "model_audit_differs_from_transcript": "CORRIGER",
    "tools_used_beyond_declared": "CORRIGER",
    "tools_used_without_declaration": "CORRIGER",
    "tool_observability_not_measured": "CORRIGER",
    "prompt_sans_empreinte_declaree": "CORRIGER",
    "prompt_recu_differe_du_prompt_signe": "CORRIGER",
    "dispatch_prepared_never_executed": "ACCEPTER",
    "file_written_in_session_scratchpad": "SURVEILLER",
}
_ACTION_INCONNU_WHY = "type d'ecart non repertorie dans la table d'action"


def _famille(kind: str) -> tuple[str, Optional[str]]:
    if kind in FAMILLE_PAR_TYPE:
        return FAMILLE_PAR_TYPE[kind], None
    return NOT_OBSERVABLE, _FAMILLE_INCONNU_WHY


def _owner(kind: str) -> tuple[str, Optional[str]]:
    if kind in OWNER_PAR_TYPE:
        return OWNER_PAR_TYPE[kind], None
    if kind in _OWNER_NOT_OBSERVABLE_WHY:
        return NOT_OBSERVABLE, _OWNER_NOT_OBSERVABLE_WHY[kind]
    return NOT_OBSERVABLE, _OWNER_INCONNU_WHY


def _impact(kind: str) -> tuple[str, Optional[str]]:
    if kind in IMPACT_PAR_TYPE:
        return IMPACT_PAR_TYPE[kind], None
    return NOT_OBSERVABLE, _IMPACT_INCONNU_WHY


def _action_typee(kind: str) -> tuple[str, Optional[str]]:
    if kind in ACTION_PAR_TYPE:
        return ACTION_PAR_TYPE[kind], None
    return NOT_OBSERVABLE, _ACTION_INCONNU_WHY


def _drift_id(kind: Any, run_id: Any, etape: Any, detail: Any) -> str:
    """Hash court deterministe : sert de cle stable a la console (nouveau /
    vu / arbitre), gere cote client, jamais persiste par Observer."""
    material = "|".join(str(x) for x in (kind, run_id, etape, detail))
    return hashlib.sha1(material.encode("utf-8")).hexdigest()[:10]


def view_drift_table(result: dict[str, Any]) -> dict[str, Any]:
    lignes: list[dict[str, Any]] = []
    for item in result.get("drift", []):
        kind = item["type"]
        categorie, libelle = DRIFT_CATEGORIES.get(kind, ("autre", kind))
        declaration, observation = _drift_pair(item)
        # Un detecteur peut porter lui-meme famille/owner/impact/action (cas :
        # ecarts famille documentation emis par la boucle documentaire). Ses
        # champs font foi ; les tables par type ne sont que le repli.
        famille, famille_why = ((item["famille"], None) if item.get("famille")
                                else _famille(kind))
        owner, owner_why = ((item["owner"], None) if item.get("owner")
                            else _owner(kind))
        impact, impact_why = ((item["impact"], None) if item.get("impact")
                              else _impact(kind))
        action, action_why = ((item["action"], None) if item.get("action")
                              else _action_typee(kind))

        ligne: dict[str, Any] = {
            "drift_id": _drift_id(kind, item.get("run_id"), item.get("etape"),
                                  item.get("detail")),
            "categorie": categorie,
            "confrontation": libelle,
            "declaration": declaration,
            "observation": observation,
            "statut": "ECART",
            "gravite": item.get("severity"),
            "run_id": item.get("run_id"),
            "etape": item.get("etape"),
            "detail": item.get("detail"),
            "provenance": item.get("source") or item.get("provenance"),
            "famille": famille,
            "impact": impact,
            "owner": owner,
            "action": action,
        }
        if famille_why:
            ligne["famille_why"] = famille_why
        if owner_why:
            ligne["owner_why"] = owner_why
        if impact_why:
            ligne["impact_why"] = impact_why
        if action_why:
            ligne["action_why"] = action_why
        lignes.append(ligne)

    ordre = {"high": 0, "medium": 1, "info": 2}
    lignes.sort(key=lambda l: (ordre.get(l["gravite"], 3), l["categorie"]))

    # Les confrontations demandees qui ne SONT PAS calculables doivent apparaitre
    # comme telles, sinon leur absence du tableau se lirait comme « pas d'ecart ».
    permissions_detail = (
        "le champ `permissions` du contrat est de la prose libre : rien "
        "n'en derive une liste de chemins comparable aux ecritures. "
        "L'absence de ligne d'ecart ne signifie donc PAS l'absence "
        "d'ecart.")
    lignes.append({
        "drift_id": _drift_id("permissions_declarees_vs_ecritures_reelles",
                              None, None, permissions_detail),
        "categorie": "permissions",
        "confrontation": "permissions declarees / ecritures reelles",
        "declaration": NOT_OBSERVABLE,
        "observation": "les ecritures reelles sont observables",
        "statut": NOT_OBSERVABLE,
        "gravite": "—",
        "run_id": None,
        "etape": None,
        "detail": permissions_detail,
        "provenance": None,
        "famille": "contrat",
        "impact": ("capteur manquant : aucune verification mecanique du "
                   "perimetre de permissions declare n'existe"),
        "owner": "CONTRAT",
        "action": "CORRIGER",
    })

    return {
        "regle_owner": "aucun drift n'est force dans une categorie : "
                       "proprietaire inconnu = NOT_OBSERVABLE avec raison",
        "colonnes": ["drift_id", "categorie", "confrontation", "declaration",
                     "observation", "statut", "gravite", "famille", "impact",
                     "owner", "action", "provenance"],
        "lignes": lignes,
        "par_gravite": dict(Counter(l["gravite"] for l in lignes)),
        "familles": dict(Counter(l["famille"] for l in lignes)),
        "chaine": "declare -> injecte -> autorise -> reel -> observe",
        "note_action_corriger": "CORRIGER signifie chantier gated : Observer "
                                 "ne corrige rien lui-meme, il signale et "
                                 "laisse HumanGate trancher",
    }


def _drift_pair(item: dict[str, Any]) -> tuple[Any, Any]:
    """Les deux cotes de la confrontation, par type d'ecart.

    L'appariement est explicite type par type : une regle generique produisait
    des cellules `null` ou `NOT_OBSERVABLE` des deux cotes, qui n'apprennent
    rien a l'operateur alors meme que l'ecart est reel et documente.
    """
    kind = item["type"]

    if kind == "model_audit_differs_from_transcript":
        return item.get("declared_by_forge"), item.get("observed_in_transcripts")

    if kind == "token_accounting_below_measured":
        declare = item.get("declared_by_forge")
        mesure = item.get("measured_billable")
        cache = item.get("measured_cache_read")
        return (f"{declare} tokens (telemetrie Forge)",
                f"{mesure} tokens facturables + {cache} de lecture de cache "
                f"non comptee — facteur x{item.get('ratio')}")

    if kind == "tools_used_beyond_declared":
        return item.get("declared"), item.get("observed_only")

    if kind == "tools_used_without_declaration":
        return "aucune liste d'outils declaree dans le dispatch", item.get("observed")

    if kind == "tool_observability_not_measured":
        return ("loaded.status = NOT_MEASURED",
                f"{item.get('observed_count')} appels d'outils observes "
                f"dans le transcript")

    if kind == "prompt_sans_empreinte_declaree":
        return ("aucune empreinte de prompt signee pour cette activation",
                "prompt integralement lisible dans le transcript, "
                "conformite ni prouvable ni refutable")

    if kind == "prompt_recu_differe_du_prompt_signe":
        return (f"{item.get('chars_declares')} caracteres signes",
                f"{item.get('chars_transcript')} caracteres recus — empreintes "
                f"differentes")

    if kind == "reference_guard_drift":
        diffs = item.get("diffs") or []
        chemins = [d.get("path") for d in diffs if isinstance(d, dict)]
        return "fichiers proteges, non modifiables pendant un run", chemins or diffs

    if kind == "dispatch_prepared_never_executed":
        return ("un dispatch prepare et signe",
                "aucun evenement d'execution correspondant")

    if kind in ("file_written_outside_game_and_lab", "file_written_in_session_scratchpad"):
        return "perimetre attendu : games/ ou lab/", item.get("path")

    # Repli generique, volontairement conservateur.
    return (item.get("declared", NOT_OBSERVABLE),
            item.get("observed") or item.get("observed_only") or NOT_OBSERVABLE)


# --------------------------------------------------------------------------- #
# Vue Sante Observer
# --------------------------------------------------------------------------- #


def view_sante(result: dict[str, Any]) -> dict[str, Any]:
    summary = result.get("facts_summary", {})
    par_categorie = summary.get("par_categorie", {})

    lignes: list[dict[str, Any]] = []
    for categorie, statuts in sorted(par_categorie.items()):
        prouve = statuts.get("RECONSTRUIT", 0)
        partiel = statuts.get("PARTIEL", 0)
        absent = statuts.get("NOT_OBSERVABLE", 0)
        lignes.append({
            "categorie": categorie,
            "prouve": prouve, "partiel": partiel, "not_observable": absent,
            "verdict": ("PROUVE" if prouve and not (partiel or absent)
                        else NOT_OBSERVABLE if absent and not prouve
                        else "PARTIEL"),
        })

    return {
        "colonnes": ["categorie", "prouve", "partiel", "not_observable", "verdict"],
        "lignes": lignes,
        "totaux": summary.get("par_statut", {}),
        "localisateurs": summary.get("localisateurs", {}),
        "faits_sans_provenance": summary.get("faits_sans_provenance", []),
        "angles_morts": summary.get("not_observable", []),
        "regle": "un manque de mesure n'est jamais rendu comme un OK : une "
                 "categorie sans trace porte NOT_OBSERVABLE et sa raison",
        "prompts": _sante_prompts(result),
    }


def _sante_prompts(result: dict[str, Any]) -> dict[str, Any]:
    prompts = result.get("prompts", []) or []
    verifs = Counter(p.get("verification") for p in prompts)
    return {
        "activations": len(prompts),
        "verification": dict(verifs),
        "lecture": "MATCH = le texte recu par l'agent reproduit l'empreinte signee "
                   "par la Forge. NO_DECLARATION = le texte est lisible mais aucune "
                   "empreinte n'a ete signee : ni prouvable, ni refutable.",
    }


# --------------------------------------------------------------------------- #
# Vue Bandeau — le matin, sept cellules, rien de plus
# --------------------------------------------------------------------------- #


def _bandeau_decisions_en_attente(result: dict[str, Any]) -> dict[str, Any]:
    humangate = result.get("humangate")
    if isinstance(humangate, dict) and "en_attente" in humangate:
        return _cell(humangate["en_attente"],
                     {"path": "result.humangate.en_attente"})

    runs = result.get("runs", []) or []
    run_ids = [r.get("run_id") for r in runs
               if r.get("decision") == "HUMANGATE_READY"]
    cell = _cell(len(run_ids))
    cell["run_ids"] = run_ids
    cell["note"] = ("compte brut des verdicts HUMANGATE_READY — le croisement "
                     "avec le registre de decisions est fourni par la vue "
                     "HUMAN GATE")
    return cell


def _bandeau_run_en_cours(events: list[dict]) -> dict[str, Any]:
    statuses = _evs(events, "run.status")

    def _statut(ev: dict) -> Any:
        p = ev.get("payload", {}) or {}
        return p.get("status") or p.get("run_status")

    en_cours = next((ev for ev in statuses if _statut(ev) == "RUNNING"), None)
    if en_cours is not None:
        s = en_cours.get("source", {}) or {}
        src = {"path": s.get("path", ""), "field": "status"}
        if s.get("line") is not None:
            src["line"] = s["line"]
        return _cell(en_cours.get("run_id"), src)

    if statuses:
        dernier = max(statuses, key=lambda e: e.get("ts") or 0)
        s = dernier.get("source", {}) or {}
        src = {"path": s.get("path", ""), "field": "status"}
        if s.get("line") is not None:
            src["line"] = s["line"]
        # « aucun » est une mesure, pas une absence : le dernier run.status lu
        # a bien ete lu, il ne porte simplement pas RUNNING.
        return _cell("aucun", src)

    return _cell(NOT_OBSERVABLE, None,
                 "aucun evenement run.status n'a ete observe dans les traces")


def _bandeau_dernier_verdict(events: list[dict]) -> dict[str, Any]:
    verdicts = _evs(events, "verdict.signed")
    if not verdicts:
        return _cell(NOT_OBSERVABLE, None,
                     "aucun verdict signe n'a ete observe dans les traces")

    dernier = max(verdicts, key=lambda e: e.get("ts") or 0)
    payload = dernier.get("payload", {}) or {}
    v = {
        "decision": payload.get("decision", NOT_OBSERVABLE),
        "project": dernier.get("project") or payload.get("project") or NOT_OBSERVABLE,
        "hmac_present": bool(payload.get("hmac")),
    }
    s = dernier.get("source", {}) or {}
    src = {"path": s.get("path", "")}
    if s.get("line") is not None:
        src["line"] = s["line"]
    return _cell(v, src)


def _bandeau_drift_high(result: dict[str, Any],
                         drift_table: dict[str, Any]) -> dict[str, Any]:
    highs = [l for l in drift_table["lignes"] if l.get("gravite") == "high"]
    v = {"total": len(highs), "ids": [l["drift_id"] for l in highs]}
    return _cell(v)


def _bandeau_incidents(events: list[dict]) -> dict[str, Any]:
    fails = _evs(events, "failure.event")
    ids = [e.get("event_id") for e in fails if e.get("event_id")]
    v = {"total": len(fails), "ids": ids}
    return _cell(v)


def _bandeau_cout_recent(result: dict[str, Any]) -> dict[str, Any]:
    tentatives = [r for r in result.get("runs", []) if r.get("role") == "attempt"]
    if not tentatives:
        return _cell(NOT_OBSERVABLE, None,
                     "aucune tentative (role=attempt) n'existe dans ce run")

    tentatives.sort(key=lambda r: (r.get("window") or {}).get("start") or "")
    derniere = tentatives[-1]
    totals = derniere.get("totals") or {}
    declare = totals.get("cost_usd_declared")
    mesures = totals.get("tokens_measured_in_transcripts") or {}
    tokens = (mesures.get("input", 0) + mesures.get("output", 0)
              + mesures.get("cache_creation", 0)) if mesures else None

    ratio = next(
        (item.get("ratio") for item in result.get("drift", [])
         if item.get("type") == "token_accounting_below_measured"
         and item.get("run_id") == derniere.get("run_id")),
        None,
    )
    avertissement = (
        f"la telemetrie sous-declare les tokens mesures (facteur x{ratio})"
        if ratio is not None else
        "aucun ecart de comptabilite token detecte pour cette tentative")

    v = {
        "declare_usd": declare if declare is not None else NOT_OBSERVABLE,
        "tokens_mesures": tokens if tokens is not None else NOT_OBSERVABLE,
        "avertissement": avertissement,
    }
    cell = _cell(v)
    cell["note"] = ("le cout n'est jamais presente seul : toujours accompagne "
                     "des tokens mesures, sous-declaration mesuree comprise")
    return cell


# --------------------------------------------------------------------------- #
# prochaine_action — 1re tache EN_ATTENTE non bloquee du registre de planning
# (studio_brain/planning/planning.yaml, expose par
# observer.system_planning.build_planning_views sous la cle `s8_planning`).
# Le registre existe depuis le 2026-08-02 (6 taches ratifiees) mais cette
# cellule etait encore ecrite AVANT sa creation : elle rendait NOT_OBSERVABLE
# inconditionnellement. Regle "non bloquee" : `etat == EN_ATTENTE` ET tous
# les `depends_on` pointent vers des taches `etat == TERMINE` (une dependance
# inconnue du registre compte comme bloquante — jamais suppose satisfaite).
# --------------------------------------------------------------------------- #


def _tache_bloquee(tache: dict[str, Any], par_id: dict[str, Any]) -> bool:
    deps = tache.get("depends_on")
    if not isinstance(deps, list):
        return False
    for dep_id in deps:
        dep = par_id.get(dep_id)
        if dep is None or dep.get("etat") != "TERMINE":
            return True
    return False


def _prochaine_tache(taches: list[dict[str, Any]]) -> Optional[dict[str, Any]]:
    par_id = {t.get("id"): t for t in taches if isinstance(t, dict) and t.get("id")}
    candidats = [t for t in taches
                 if t.get("etat") == "EN_ATTENTE" and not _tache_bloquee(t, par_id)]
    if not candidats:
        return None

    def _prio(t: dict[str, Any]) -> float:
        p = t.get("priorite")
        return float(p) if isinstance(p, (int, float)) and not isinstance(p, bool) else float("inf")

    candidats.sort(key=lambda t: (_prio(t), str(t.get("id"))))
    return candidats[0]


def _bandeau_prochaine_action(
    planning_view: Optional[dict[str, Any]] = None,
) -> dict[str, Any]:
    """Repli SERVEUR pour la cellule `prochaine_action`. N'est REELLEMENT
    exerce que si l'appelant passe `planning_view` (la vue `s8_planning`) a
    `build_cockpit` / `view_bandeau` — voir docstring de `build_cockpit` :
    l'appelant reel aujourd'hui (`views.py::build_views`) invoque
    `build_cockpit(result, events)` a DEUX arguments, donc cette fonction
    recoit `planning_view=None` en pratique et rend NOT_OBSERVABLE. Le
    chemin qui fonctionne reellement aujourd'hui pour l'operateur est le
    repli COTE CLIENT dans console.html (`prochaineActionFallback`, qui lit
    `state.views.s8_planning.registre.taches` directement) — documente aussi
    la-bas. Cette fonction reste prete, testee et idempotente pour le jour ou
    `views.py` (hors perimetre de ce chantier) sera branche."""
    if not isinstance(planning_view, dict):
        return _cell(NOT_OBSERVABLE, None,
                     "planning_view non fourni a build_cockpit : le registre "
                     "de planning n'est pas branche cote serveur pour cette "
                     "cellule (repli cote client actif dans console.html)")

    registre = planning_view.get("registre") or {}
    taches = registre.get("taches") or []
    if not taches:
        why = registre.get("why") or "le registre existe mais ne contient aucune tache valide"
        return _cell(NOT_OBSERVABLE, None, why)

    tache = _prochaine_tache(taches)
    if tache is None:
        return _cell(NOT_OBSERVABLE, None,
                     "aucune tache EN_ATTENTE non bloquee dans le registre "
                     "(tout est termine, en cours, bloque, ou aucune tache "
                     "n'est EN_ATTENTE)")

    v = {
        "id": tache.get("id"),
        "objectif": tache.get("objectif"),
        "raison": _short(tache.get("raison") or "", 200),
    }
    return _cell(v, {"path": "studio_brain/planning/planning.yaml", "field": "taches"})


def view_bandeau(result: dict[str, Any], events: list[dict],
                  planning_view: Optional[dict[str, Any]] = None) -> dict[str, Any]:
    drift_table = view_drift_table(result)
    return {
        "decisions_en_attente": _bandeau_decisions_en_attente(result),
        "run_en_cours": _bandeau_run_en_cours(events),
        "dernier_verdict": _bandeau_dernier_verdict(events),
        "drift_high": _bandeau_drift_high(result, drift_table),
        "incidents": _bandeau_incidents(events),
        "cout_recent": _bandeau_cout_recent(result),
        "prochaine_action": _bandeau_prochaine_action(planning_view),
    }


def build_cockpit(result: dict[str, Any], events: list[dict],
                   planning_view: Optional[dict[str, Any]] = None) -> dict[str, Any]:
    """`planning_view` (optionnel, defaut None) = la vue `s8_planning`
    produite par `observer.system_planning.build_planning_views`, pour
    alimenter la cellule bandeau `prochaine_action` (voir
    `_bandeau_prochaine_action`). Defaut None = compatibilite totale avec
    les DEUX appels reels existants, tous les deux a deux arguments :
    `views.py::build_views` (`cockpit = build_cockpit(result, events)`,
    ~L683) et tout appelant direct de `cli.py`/`live.py` (qui n'appellent
    jamais `build_cockpit` eux-memes — ils passent par `build_views`).
    `views.py` est un fichier hors perimetre pour ce chantier : le troisieme
    argument n'est donc PAS branche aujourd'hui, et `prochaine_action` reste
    NOT_OBSERVABLE cote serveur. Le repli qui fonctionne reellement pour
    l'operateur vit cote client (console.html lit directement
    `state.views.s8_planning.registre.taches`)."""
    return {
        "c0_bandeau": view_bandeau(result, events, planning_view),
        "c1_campagnes": view_campagnes(result, events),
        "c2_drift": view_drift_table(result),
        "c3_sante": view_sante(result),
    }
