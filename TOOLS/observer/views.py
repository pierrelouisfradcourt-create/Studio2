"""Modele des dix vues de la console d'observation.

Ce module ne rend rien : il produit les donnees que la console affichera. Chaque
donnee affichable porte sa citation (`src`), pour que tout element soit cliquable
jusqu'a sa source. Une rubrique sans trace vaut litteralement `NOT_OBSERVABLE`
et n'est jamais comblee.

Les dix vues :
  1  pipeline vivant        6  graphe d'artefacts
  2  carte des agents       7  etat Forge
  3  prompt reel            8  temps reel (flux)
  4  outils reels           9  drift
  5  flux des fichiers     10  sante globale
"""

from __future__ import annotations

from collections import Counter, defaultdict
from typing import Any, Iterable, Optional

NOT_OBSERVABLE = "NOT_OBSERVABLE"

# Chaine canonique demandee, du geste humain au geste humain.
PIPELINE_STAGES: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("Human", ("run.charter", "run.task_prompt")),
    ("Forge", ("run.declared", "run.status")),
    ("Step", ("step.status",)),
    ("Agent", ("dispatch.prepared", "dispatch.executed", "agent.session")),
    ("Prompt", ("dispatch.context_manifest", "dispatch.reasoning")),
    ("Outils", ("dispatch.tools", "tool.call", "shell.exec")),
    ("Execution", ("file.read", "file.write", "file.edit", "llm.usage")),
    ("Artefacts", ("artifact.self_declared", "wiremap.line", "capture.visual")),
    ("Verdict", ("test.result", "mutation.result", "solvability.result",
                 "oracle.result", "verdict.signed")),
    ("Human", ("git.commit",)),
)

# Etats demandes pour la vue 7.
STATE_SUCCESS = "Success"
STATE_FAILED = "Failed"
STATE_BLOCKED = "Blocked"
STATE_RETRY = "Retry"
STATE_RUNNING = "Running"
STATE_WAITING = "Waiting"
STATE_HUMANGATE = "HumanGate"
# Gel par decision humaine — ni en cours, ni reussi, ni echoue. Distinct de
# STATE_BLOCKED (bloque par un oracle) et de STATE_WAITING (attend une entree).
STATE_FROZEN = "FrozenHuman"


def cite(ev: dict[str, Any], field: str | None = None) -> dict[str, Any]:
    """Citation compacte : de quoi rouvrir la source a la main."""
    src = ev.get("source", {}) or {}
    out: dict[str, Any] = {"path": src.get("path", "")}
    if src.get("line") is not None:
        out["line"] = src["line"]
    if field or src.get("field"):
        out["field"] = field or src.get("field")
    if "line" not in out and "field" not in out:
        out["scope"] = "document entier"
    out["event_id"] = ev.get("event_id")
    return out


def _kinds(events: Iterable[dict], kinds: tuple[str, ...],
           run_id: str | None = None) -> list[dict]:
    out = [e for e in events if e["kind"] in kinds]
    if run_id:
        out = [e for e in out if e.get("run_id") == run_id]
    return out


def _span(events: list[dict]) -> dict[str, Any]:
    dated = [e for e in events if e.get("ts")]
    if not dated:
        return {"debut": None, "fin": None, "duree_s": None}
    first = min(dated, key=lambda e: e["ts"])
    last = max(dated, key=lambda e: e["ts"])
    return {
        "debut": first.get("ts_iso"),
        "fin": last.get("ts_iso"),
        "duree_s": round(last["ts"] - first["ts"], 1),
    }


# --------------------------------------------------------------------------- #
# Vue 1 — pipeline vivant
# --------------------------------------------------------------------------- #


def view_pipeline(events: list[dict], runs: list[dict]) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for run in runs:
        run_id = run["run_id"]
        stages: list[dict[str, Any]] = []
        for label, kinds in PIPELINE_STAGES:
            evs = _kinds(events, kinds, run_id)
            if not evs:
                stages.append({
                    "etage": label, "statut": NOT_OBSERVABLE, "n": 0,
                    "pourquoi": "aucun evenement de ce type n'est rattache a ce run",
                })
                continue
            span = _span(evs)
            stages.append({
                "etage": label,
                "statut": "OBSERVE",
                "n": len(evs),
                **span,
                "kinds": dict(Counter(e["kind"] for e in evs).most_common()),
                "src": [cite(e) for e in evs[:3]],
            })
        out.append({
            "run_id": run_id,
            "role": run.get("role"),
            "decision": run.get("decision"),
            "run_status": run.get("run_status"),
            "fenetre": run.get("window"),
            "etages": stages,
        })
    return out


# --------------------------------------------------------------------------- #
# Vue 2 — carte des agents
# --------------------------------------------------------------------------- #


def view_agents(events: list[dict]) -> list[dict[str, Any]]:
    """Un agent = une session de travail rattachee a une etape.

    Parent et enfants : observables uniquement pour les sous-agents, dont le
    chemin de transcript porte la session parente (`<parent>/subagents/...`).
    Pour une session lancee en sous-processus par le driver, le lien de
    parente n'est porte par aucune trace : il vaut NOT_OBSERVABLE.
    """
    agents: list[dict[str, Any]] = []
    sessions = _kinds(events, ("agent.session",))
    by_file: dict[str, list[dict]] = defaultdict(list)
    for ev in sessions:
        by_file[ev["payload"].get("session_file", "")].append(ev)

    # index : fichier de session -> parent (chemin) et enfants
    children: dict[str, list[str]] = defaultdict(list)
    for path in by_file:
        norm = path.replace("\\", "/")
        if "/subagents/" in norm:
            parent = norm.split("/subagents/")[0] + ".jsonl"
            children[parent].append(path)

    for path, evs in sorted(by_file.items()):
        head = evs[0]
        payload = head["payload"]
        norm = path.replace("\\", "/")
        is_sub = "/subagents/" in norm
        parent = (norm.split("/subagents/")[0] + ".jsonl") if is_sub else None

        run_ids = sorted({e.get("run_id") for e in evs if e.get("run_id")})
        etapes = sorted({e.get("etape") for e in evs if e.get("etape")})
        attributed = bool(payload.get("activity_attributed"))

        usage = [e for e in events
                 if e["kind"] == "llm.usage"
                 and e.get("actor", {}).get("session_id") == payload.get("session_id")]
        tokens = {
            "input": sum(int(e["payload"].get("input_tokens") or 0) for e in usage),
            "output": sum(int(e["payload"].get("output_tokens") or 0) for e in usage),
            "cache_read": sum(int(e["payload"].get("cache_read_input_tokens") or 0)
                              for e in usage),
            "cache_creation": sum(int(e["payload"].get("cache_creation_input_tokens") or 0)
                                  for e in usage),
        }

        # cout : declare par etape dans la telemetrie, jamais par session
        cout = NOT_OBSERVABLE
        cout_src = None
        for ev in events:
            if (ev["kind"] == "telemetry.step" and ev.get("run_id") in run_ids
                    and ev.get("etape") in etapes):
                value = ev["payload"].get("cost_usd")
                if isinstance(value, (int, float)):
                    cout = round(float(value), 4)
                    cout_src = cite(ev, "cost_usd")
                    break

        # raison d'activation
        raison = NOT_OBSERVABLE
        raison_src = None
        for ev in events:
            if (ev["kind"] in ("dispatch.prepared", "dispatch.context_manifest")
                    and ev.get("run_id") in run_ids and ev.get("etape") in etapes):
                value = ev["payload"].get("reason") or ev["payload"].get("capability_role")
                if value:
                    raison = value
                    raison_src = cite(ev, "reason")
                    break

        agents.append({
            "nom": norm.rsplit("/", 1)[-1],
            "session_id": payload.get("session_id"),
            "session_file": path,
            "type": "sous-agent" if is_sub else "session d'etape",
            "parent": parent or NOT_OBSERVABLE,
            "parent_pourquoi": None if parent else
            "session lancee en sous-processus par le driver : aucune trace ne "
            "porte le lien vers la session appelante",
            "enfants": children.get(path, []),
            "run_ids": run_ids,
            "etapes": etapes,
            "modeles": payload.get("models") or [],
            "duree_s": _duree(payload),
            "tokens": tokens if usage else NOT_OBSERVABLE,
            "cout_usd": cout,
            "statut": "activite attribuee" if attributed else "mention seule",
            "raison_activation": raison,
            "marqueurs": payload.get("markers") or [],
            "src": cite(head),
            "src_cout": cout_src,
            "src_raison": raison_src,
        })
    return agents


def _duree(payload: dict[str, Any]) -> Any:
    first, last = payload.get("first_ts"), payload.get("last_ts")
    if not first or not last:
        return NOT_OBSERVABLE
    try:
        from datetime import datetime
        return round(
            (datetime.fromisoformat(last) - datetime.fromisoformat(first)).total_seconds(), 1
        )
    except (ValueError, TypeError):
        return NOT_OBSERVABLE


# --------------------------------------------------------------------------- #
# Vue 4 — outils reels
# --------------------------------------------------------------------------- #


def view_tools(events: list[dict]) -> list[dict[str, Any]]:
    """Contrat -> Runtime -> Execution, cote a cote.

    « Runtime » est la liste que l'audit de dispatch signe comme autorisee. On
    sait par ailleurs qu'elle est vide par construction : c'est un constat, pas
    une reparation.
    """
    rows: dict[tuple, dict[str, Any]] = {}
    for ev in _kinds(events, ("dispatch.context_manifest",)):
        key = (ev.get("run_id"), ev.get("etape"))
        row = rows.setdefault(key, _empty_tool_row(key))
        tools = ev["payload"].get("tools_effective")
        if isinstance(tools, list):
            row["contrat"].update(str(t) for t in tools)
            row["src_contrat"] = cite(ev, "tools_effective")
    for ev in _kinds(events, ("dispatch.prepared",)):
        key = (ev.get("run_id"), ev.get("etape"))
        row = rows.setdefault(key, _empty_tool_row(key))
        allowed = ev["payload"].get("allowed_tools")
        if isinstance(allowed, list):
            row["runtime"].update(str(t) for t in allowed)
            row["src_runtime"] = cite(ev, "allowed_tools")
    for ev in _kinds(events, ("dispatch.tools",)):
        key = (ev.get("run_id"), ev.get("etape"))
        row = rows.setdefault(key, _empty_tool_row(key))
        loaded = ev["payload"].get("loaded")
        if isinstance(loaded, dict):
            row["statut_mesure"] = loaded.get("status")
            row["src_mesure"] = cite(ev, "loaded.status")
    for ev in _kinds(events, ("tool.call",)):
        key = (ev.get("run_id"), ev.get("etape"))
        row = rows.setdefault(key, _empty_tool_row(key))
        name = ev["payload"].get("tool_name")
        if name:
            row["execution"][name] += 1
            if not row["src_execution"]:
                row["src_execution"] = cite(ev, "tool_name")

    out: list[dict[str, Any]] = []
    for (run_id, etape), row in sorted(rows.items(), key=lambda kv: str(kv[0])):
        contrat, runtime = row["contrat"], row["runtime"]
        execution = row["execution"]
        hors = sorted(set(execution) - contrat) if contrat else sorted(execution)
        out.append({
            "run_id": run_id, "etape": etape,
            "contrat": sorted(contrat) or NOT_OBSERVABLE,
            "runtime": sorted(runtime) or NOT_OBSERVABLE,
            "runtime_pourquoi": None if runtime else
            "l'audit de dispatch signe une liste d'outils vide : la borne reelle "
            "n'est pas portee par cette trace",
            "statut_mesure_forge": row["statut_mesure"] or NOT_OBSERVABLE,
            "execution": dict(execution.most_common()),
            "hors_contrat": hors,
            "derive": bool(hors),
            "src_contrat": row["src_contrat"], "src_runtime": row["src_runtime"],
            "src_mesure": row["src_mesure"], "src_execution": row["src_execution"],
        })
    return out


def _empty_tool_row(key: tuple) -> dict[str, Any]:
    return {
        "contrat": set(), "runtime": set(), "execution": Counter(),
        "statut_mesure": None, "src_contrat": None, "src_runtime": None,
        "src_mesure": None, "src_execution": None,
    }


# --------------------------------------------------------------------------- #
# Vue 5 — flux des fichiers
# --------------------------------------------------------------------------- #


def view_file_flow(events: list[dict]) -> dict[str, Any]:
    par_agent: dict[str, dict[str, Any]] = {}
    for kind, bucket in (("file.read", "lecture"), ("file.write", "ecriture"),
                         ("file.edit", "edition")):
        for ev in _kinds(events, (kind,)):
            session = ev.get("actor", {}).get("session_id") or ev.get("etape") or "?"
            entry = par_agent.setdefault(session, {
                "session_id": session,
                "etapes": set(), "run_ids": set(),
                "lecture": Counter(), "ecriture": Counter(), "edition": Counter(),
                "src": cite(ev, "path"),
            })
            if ev.get("etape"):
                entry["etapes"].add(ev["etape"])
            if ev.get("run_id"):
                entry["run_ids"].add(ev["run_id"])
            path = ev["payload"].get("path")
            if path:
                entry[bucket][path] += 1

    flux = []
    for session, entry in sorted(par_agent.items()):
        ecrits = set(entry["ecriture"]) | set(entry["edition"])
        flux.append({
            "session_id": session,
            "etapes": sorted(entry["etapes"]),
            "run_ids": sorted(entry["run_ids"]),
            "lecture": dict(entry["lecture"].most_common(40)),
            "ecriture": dict(entry["ecriture"].most_common(40)),
            "edition": dict(entry["edition"].most_common(40)),
            "n_lus": len(entry["lecture"]), "n_ecrits": len(ecrits),
            "src": entry["src"],
        })
    return {
        "par_agent": flux,
        "creation": "confondue avec l'ecriture : l'outil Write cree ou ecrase sans "
                    "distinguer les deux dans la trace",
        "suppression": NOT_OBSERVABLE,
        "suppression_pourquoi": "aucun outil de suppression n'apparait dans les "
                                "transcripts observes ; une suppression faite par "
                                "une commande shell serait noyee dans le texte de "
                                "la commande, non structuree",
    }


# --------------------------------------------------------------------------- #
# Vue 6 — graphe d'artefacts
# --------------------------------------------------------------------------- #


def view_artifact_graph(events: list[dict]) -> dict[str, Any]:
    """Qui a produit quel fichier, et qui l'a ensuite lu.

    Une arete « consomme » n'est tracee que si la lecture est POSTERIEURE a
    l'ecriture : sans cet ordre, on relierait un lecteur a un producteur qui
    n'existait pas encore.
    """
    producers: dict[str, list[dict]] = defaultdict(list)
    for ev in _kinds(events, ("file.write", "file.edit")):
        path = ev["payload"].get("path")
        if path:
            producers[path].append(ev)

    noeuds: dict[str, dict[str, Any]] = {}
    aretes: list[dict[str, Any]] = []

    def node(nid: str, kind: str, **kw: Any) -> None:
        noeuds.setdefault(nid, {"id": nid, "type": kind, **kw})

    for path, evs in producers.items():
        first = min(evs, key=lambda e: e.get("ts") or 0)
        agent = first.get("actor", {}).get("session_id") or first.get("etape") or "?"
        node(agent, "agent", etape=first.get("etape"), run_id=first.get("run_id"))
        node(path, "artefact")
        aretes.append({
            "de": agent, "vers": path, "relation": "produit",
            "n": len(evs), "ts": first.get("ts_iso"), "src": cite(first, "path"),
        })

    for ev in _kinds(events, ("file.read",)):
        path = ev["payload"].get("path")
        if path not in producers:
            continue
        lecteur = ev.get("actor", {}).get("session_id") or ev.get("etape") or "?"
        ecriture_ts = min((e.get("ts") or 0) for e in producers[path])
        if (ev.get("ts") or 0) <= ecriture_ts:
            continue  # lecture anterieure a toute ecriture : pas une consommation
        producteurs = {e.get("actor", {}).get("session_id") or e.get("etape")
                       for e in producers[path]}
        if lecteur in producteurs:
            continue  # se relire soi-meme n'est pas une consommation inter-agents
        node(lecteur, "agent", etape=ev.get("etape"), run_id=ev.get("run_id"))
        aretes.append({
            "de": path, "vers": lecteur, "relation": "consomme",
            "ts": ev.get("ts_iso"), "src": cite(ev, "path"),
        })

    return {"noeuds": list(noeuds.values()), "aretes": aretes,
            "note": "les aretes de consommation exigent que la lecture suive "
                    "l'ecriture ; le rattachement agent<->run reste une inference "
                    "de portee de session"}


# --------------------------------------------------------------------------- #
# Vue 7 — etat Forge
# --------------------------------------------------------------------------- #


def view_forge_state(events: list[dict], runs: list[dict],
                     now_ts: float | None = None) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for run in runs:
        run_id = run["run_id"]
        etapes: dict[str, dict[str, Any]] = {}
        for ev in _kinds(events, ("step.status",), run_id):
            etape = ev.get("etape")
            if not etape:
                continue
            entry = etapes.setdefault(etape, {
                "etape": etape, "statuts": [], "attempts": set(), "src": cite(ev),
            })
            status = ev["payload"].get("status")
            if status:
                entry["statuts"].append(status)
            if ev.get("attempt") is not None:
                entry["attempts"].add(ev["attempt"])

        failures = Counter(e.get("etape") for e in _kinds(events, ("failure.event",), run_id))
        executed = Counter(e.get("etape")
                           for e in _kinds(events, ("dispatch.executed",), run_id))
        prepared = Counter(e.get("etape")
                           for e in _kinds(events, ("dispatch.prepared",), run_id))

        lignes = []
        for etape, entry in sorted(etapes.items()):
            dernier = entry["statuts"][-1] if entry["statuts"] else None
            lignes.append({
                "etape": etape,
                "etat": _state_of(dernier, failures.get(etape, 0),
                                  prepared.get(etape, 0), executed.get(etape, 0)),
                "statut_brut": dernier or NOT_OBSERVABLE,
                "activations": executed.get(etape, 0),
                "dispatches_prepares": prepared.get(etape, 0),
                "incidents": failures.get(etape, 0),
                "src": entry["src"],
            })

        out.append({
            "run_id": run_id,
            "etat_run": _run_state(run),
            "decision": run.get("decision") or NOT_OBSERVABLE,
            "etapes": lignes,
        })
    return out


def _state_of(statut: str | None, incidents: int, prepared: int, executed: int) -> str:
    if statut:
        upper = statut.upper()
        if "BLOCK" in upper:
            return STATE_BLOCKED
        if "FAIL" in upper or "HALT" in upper:
            return STATE_FAILED
        if upper in ("OK", "DONE", "PASSED", "SUCCESS"):
            return STATE_SUCCESS
        if "RUN" in upper:
            return STATE_RUNNING
    if executed and executed > 1:
        return STATE_RETRY
    if incidents:
        return STATE_FAILED
    if prepared and not executed:
        return STATE_WAITING
    return NOT_OBSERVABLE


def _run_state(run: dict[str, Any]) -> str:
    status = (run.get("run_status") or "").upper()
    # FROZEN_HUMAN AVANT tout le reste : c'est un etat de DECISION, pas
    # d'execution. Il prime sur `decision` et sur le statut d'execution — un run
    # gele par Pierre n'est ni en cours, ni reussi, ni echoue. Sans cette branche,
    # la chaine `if status: return STATE_RUNNING` ci-dessous affichait Pong comme
    # « Running » alors que plus aucun processus ne tourne depuis le 2026-07-27 :
    # on aurait retire le mensonge des donnees (state.json) en le laissant dans
    # l'affichage. Vocabulaire ratifie Pierre 2026-08-03 (FORGE_CAPITALISATION_V1) :
    # RUNNING / FROZEN_HUMAN / CLOSED / FAILED.
    if status == "FROZEN_HUMAN":
        return STATE_FROZEN
    decision = (run.get("decision") or "").upper()
    if "HUMANGATE" in decision:
        return STATE_HUMANGATE
    if "BLOCK" in decision:
        return STATE_BLOCKED
    if status in ("DONE", "CLOSED"):
        return STATE_SUCCESS
    if status == "FAILED":
        return STATE_FAILED
    if status:
        return STATE_RUNNING
    return NOT_OBSERVABLE


# --------------------------------------------------------------------------- #
# Vue 9 — drift  /  Vue 10 — sante
# --------------------------------------------------------------------------- #


def view_drift(result: dict[str, Any]) -> dict[str, Any]:
    drift = result.get("drift", [])
    return {
        "total": len(drift),
        "par_severite": dict(Counter(d["severity"] for d in drift)),
        "par_type": dict(Counter(d["type"] for d in drift)),
        "chaine": ["declare (contrat)", "injecte (prompt)", "autorise (audit)",
                   "reel (executeur)", "observe (transcript)"],
        "items": sorted(drift, key=lambda d: {"high": 0, "medium": 1, "info": 2}
                        .get(d["severity"], 3)),
    }


def view_health(events: list[dict], runs: list[dict],
                result: dict[str, Any]) -> dict[str, Any]:
    usage = _kinds(events, ("llm.usage",))
    telemetry = _kinds(events, ("telemetry.step",))
    builders = _kinds(events, ("builder.attempt",))
    sessions = [e for e in _kinds(events, ("agent.session",))
                if e["payload"].get("activity_attributed")]

    cout = sum(float(e["payload"].get("cost_usd") or 0) for e in telemetry)
    cout += sum(float(e["payload"].get("cost_estimated") or 0) for e in builders)

    tentatives = [r for r in runs if r.get("role") == "attempt"]
    durees = [r["window"]["duree_s"] if "duree_s" in r["window"]
              else r["window"].get("duration_s") for r in tentatives]
    durees = [d for d in durees if isinstance(d, (int, float))]

    return {
        "sessions_attribuees": len(sessions),
        "runs": {"total": len(runs), "tentatives": len(tentatives)},
        "tokens_mesures": {
            "input": sum(int(e["payload"].get("input_tokens") or 0) for e in usage),
            "output": sum(int(e["payload"].get("output_tokens") or 0) for e in usage),
            "cache_read": sum(int(e["payload"].get("cache_read_input_tokens") or 0)
                              for e in usage),
            "cache_creation": sum(int(e["payload"].get("cache_creation_input_tokens") or 0)
                                  for e in usage),
        },
        "cout_declare_usd": round(cout, 4) if (telemetry or builders) else NOT_OBSERVABLE,
        "cout_reel_usd": NOT_OBSERVABLE,
        "cout_reel_pourquoi": "aucune grille tarifaire n'accompagne les traces : le "
                              "cout ne peut etre ni recalcule ni verifie",
        "duree_totale_s": round(sum(durees), 1) if durees else NOT_OBSERVABLE,
        "echecs": len(_kinds(events, ("failure.event",))),
        "retries": sum(1 for e in builders
                       if e["payload"].get("strategy") == "pool_retry"),
        "human_gates": sum(1 for r in runs
                           if "HUMANGATE" in (r.get("decision") or "").upper()),
        "human_gates_ratifies": NOT_OBSERVABLE,
        "human_gates_pourquoi": "HUMANGATE_READY signifie pret pour la gate, pas "
                                "ratifie par elle ; la decision humaine vit hors "
                                "des racines lisibles",
        "drift": {"total": len(result.get("drift", [])),
                  "high": sum(1 for d in result.get("drift", [])
                              if d["severity"] == "high")},
        "faits": result.get("facts_summary", {}).get("par_statut", {}),
    }


def _add_human_names(campagnes: Optional[dict[str, Any]],
                     result: dict[str, Any]) -> None:
    """Ajoute un nom lisible a chaque ligne Campagnes.

    Transformation deterministe (fleet.human_name_session) — aucune table
    manuelle. L'identifiant brut reste la cle : le nom est un confort.
    """
    if not campagnes or "lignes" not in campagnes:
        return
    from observer.fleet import human_name_session

    for ligne in campagnes["lignes"]:
        run_id = (ligne.get("run_id") or {}).get("v")
        if not run_id:
            continue
        # Nom de RUN : sans etape — a cette granularite, afficher la derniere
        # etape laisserait croire que le run s'y resume.
        ligne["nom"] = {
            "v": human_name_session(result.get("project", ""), "", run_id),
            "note": "nom derive mecaniquement de l'identifiant — l'identifiant "
                    "brut reste l'identite",
        }
    if not any(c.get("cle") == "nom" for c in campagnes.get("colonnes", [])):
        campagnes["colonnes"].insert(1, {"cle": "nom", "titre": "nom"})


# --------------------------------------------------------------------------- #
# Assemblage
# --------------------------------------------------------------------------- #


def build_views(result: dict[str, Any], events: list[dict],
                prompts: Optional[list[dict]] = None,
                ctx: Any = None) -> dict[str, Any]:
    from observer.cockpit import build_cockpit

    runs = result.get("runs", [])

    # --- Vues de commande (HUMAN GATE, DOC LOOP, AI CONTROL, FORGE MAP) ------
    # Elles exigent un ctx (lectures declarees : studio_brain/decisions,
    # lessons.jsonl). Sans ctx, elles s'affichent NOT_OBSERVABLE — jamais
    # omises en silence.
    command_views: dict[str, Any] = {}
    if ctx is not None:
        from observer.command import build_command_views

        command_views = build_command_views(ctx, result, events)
        # Le bandeau croise les verdicts avec le registre de decisions : on lui
        # passe la vue humangate via result (contrat prevu par cockpit).
        result["humangate"] = command_views.get("c4_humangate", {})
        # Les ecarts famille documentation rejoignent la vue Drift UNIQUE
        # (decision ratifiee §04) avant sa construction.
        doc_drift = (command_views.get("c5_docloop") or {}).get("drift_items") or []
        existing = {d.get("type") for d in result.get("drift", [])}
        for d in doc_drift:
            if d.get("type") in existing:
                continue
            d.setdefault("famille", "documentation")
            result["drift"].append(d)
    else:
        why = "ctx absent : les lectures declarees (decisions, lessons) n'ont pas ete faites"
        command_views = {
            key: {"v": "NOT_OBSERVABLE", "why": why}
            for key in ("c4_humangate", "c5_docloop", "c6_aicontrol", "c7_forgemap")
        }

    # --- Flotte multi-projets — calculee AVANT les vues systeme : la vue
    # production en depend (bug d'ordre releve par le worker E, corrige ici).
    if ctx is not None:
        from observer.fleet import view_fleet as _view_fleet

        fleet_early = _view_fleet(ctx.repo_root, ctx.transcripts_root,
                                  ctx.project, result)
        result.setdefault("views", {})["c8_fleet"] = fleet_early
    else:
        fleet_early = None

    # --- Vues systeme (objets metier de la Forge — « Master Schema vivant ») --
    system_views: dict[str, Any] = {}
    if ctx is not None:
        from observer.system_agents import build_agent_views
        from observer.system_artefacts import build_artefact_views
        from observer.system_roadmap import build_roadmap_views

        system_views.update(build_agent_views(ctx, result, events, prompts or []))
        system_views.update(build_artefact_views(ctx, result, events))
        system_views.update(build_roadmap_views(ctx, result, events))

        from observer.system_planning import build_planning_views

        planning_out = (ctx.repo_root / "EVIDENCE" / "reports" / "observer"
                        / ctx.project)
        system_views.update(
            build_planning_views(ctx, result, events, out_dir=planning_out)
        )

        # Chantiers C et D (mode parallele) : graphe de production et registre
        # normalise des decisions — derives, aucune ecriture de store.
        from observer.evidence import view_evidence
        from observer.system_production import build_production_views

        system_views.update(build_production_views(ctx, result, events))
        system_views.update(view_evidence(ctx, result, events))

        # Wiremap vivante (chantier 4, V2) : overlay derive prescription ×
        # construction observee × validation — jamais une reecriture du run.
        from observer.wiremap_living import view_wiremap_living

        system_views.update(view_wiremap_living(ctx, result, events))

        # Les desaccords doctrine<->mesure de la roadmap rejoignent la vue
        # Drift unique, famille documentation.
        for d in (system_views.get("s2_roadmap") or {}).get("drift_items") or []:
            d.setdefault("famille", "documentation")
            result["drift"].append(d)
    else:
        why = "ctx absent : les vues systeme exigent les lectures declarees"
        system_views = {
            key: {"v": "NOT_OBSERVABLE", "why": why}
            for key in ("s1_workflow", "s2_roadmap", "s3_agents", "s4_prompt",
                        "s5_artefacts", "s6_injection", "s7_flow", "s8_planning")
        }

    # --- Flotte multi-projets : deja calculee en amont (fleet_early) ---------
    fleet = fleet_early if fleet_early is not None else {
        "v": "NOT_OBSERVABLE",
        "why": "ctx absent : la flotte exige un contexte par projet",
    }

    # Le bandeau lit le registre de planning (prochaine action) : on lui passe
    # la vue s8_planning construite juste au-dessus.
    cockpit = build_cockpit(result, events,
                            planning_view=system_views.get("s8_planning"))

    # Noms humains sur la vue Campagnes (confort ; l'identifiant reste l'identite).
    _add_human_names(cockpit.get("c1_campagnes"), result)

    # La piece Accueil et les cartes pedagogiques se construisent en DERNIER :
    # elles recomposent les vues deja faites (bandeau, drift, humangate,
    # workflow, planning), sans rien recalculer.
    if ctx is not None:
        from observer.pedagogy import build_home_views

        views_partial = {**cockpit, **command_views, **system_views}
        system_views.update(build_home_views(ctx, result, events, views_partial))
    else:
        system_views["s0_accueil"] = {
            "v": "NOT_OBSERVABLE",
            "why": "ctx absent : la piece Accueil recompose des vues qui "
                   "exigent les lectures declarees",
        }

    return {
        **cockpit,
        **command_views,
        **system_views,
        "c8_fleet": fleet,
        "v1_pipeline": view_pipeline(events, runs),
        "v2_agents": view_agents(events),
        "v3_prompts": prompts if prompts is not None else {
            "statut": NOT_OBSERVABLE,
            "pourquoi": "le module de prompt n'a pas ete execute",
        },
        "v4_tools": view_tools(events),
        "v5_file_flow": view_file_flow(events),
        "v6_artifacts": view_artifact_graph(events),
        "v7_forge_state": view_forge_state(events, runs),
        # v9_drift supprime (decision ratifiee §04) : une seule vue Drift,
        # c2_drift — les memes ecarts, familles/proprietaires/actions inclus.
        "v10_health": view_health(events, runs, result),
    }
