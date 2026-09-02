"""Vue PRODUCTION de Forge Observer V0 — « Que produit-on, et où ça bloque ? »

Transforme le planning plat en GRAPHE DE PRODUCTION. Chaîne ratifiée par jeu :

    Jeu → Core loop → Systèmes → Artefacts → Tests → Validation

Chaque nœud porte : un état (cellule {v,src,why}), un propriétaire, ses
dépendances, la preuve attendue et les risques rattachés. TOUT est dérivé des
traces existantes, RIEN n'est saisi :

    * nœud Jeu        — flotte (`result.views.c8_fleet`) : dernier run piloté,
                        décision, rôle producteur dominant mesuré dans `runs[].actor` ;
    * Core loop       — dérivé MÉCANIQUEMENT de la wiremap : le système de
                        catégorie `system` qui compose le plus d'autres systèmes
                        (`allowed_deps` le plus long). Pour breakout_v2 c'est
                        `game_loop` — mais la règle est mécanique, pas nominative ;
    * Systèmes        — `wiremap.json systems[]` (id, category) + `lines[]`
                        (state → état du nœud, expected_proof/preuve → preuve,
                        fichiers[] → artefacts déclarés) ;
    * Artefacts       — croisement fichiers déclarés par les lignes wiremap ×
                        événements `file.write`/`file.edit` observés (comptes par
                        système quand le rattachement est dérivable, global sinon) ;
    * Tests           — reçus d'oracle du run (`test.result`, `mutation.result`,
                        `solvability.result`, `oracle.result`) ;
    * Validation      — verdict signé + état HumanGate (`result.humangate`) ;
    * nœuds AMONT     — tâches de `studio_brain/planning/planning.yaml` (LECTURE
                        seule, vue dérivée — le registre n'est JAMAIS écrit ici)
                        dont l'objectif/raison mentionne le jeu ou la Forge ;
    * risques         — drifts du run rattachés au nœud concerné (table
                        famille→niveau explicite) + tâches BLOQUE du registre
                        liées au jeu.

Les autres projets de la flotte n'ont pas de wiremap lisible dans ce contexte
(cécité : racines limitées au projet courant) : ils reçoivent un graphe RÉDUIT
Jeu → Tests → Validation depuis leurs cellules de flotte, chaînons intermédiaires
déclarés NOT_OBSERVABLE avec leur raison — jamais 0, jamais vide, jamais deviné.

Ce module ne lit rien hors d'`ObserverContext` (BlindnessViolation jamais
rattrapée ici) et n'écrit AUCUN fichier.
"""

from __future__ import annotations

import logging
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Optional

LOG = logging.getLogger("observer.system_production")

NOT_OBSERVABLE = "NOT_OBSERVABLE"

# Bootstrap identique a fleet.py / system_planning.py : rend `import observer.*`
# possible sans install, AVANT tout import croise inter-modules.
_HERE = Path(__file__).resolve().parent
if str(_HERE.parent) not in sys.path:
    sys.path.insert(0, str(_HERE.parent))

QUESTION = "Que produit-on, et où ça bloque ?"

# Vocabulaire ferme des niveaux de la chaine ratifiee.
NIVEAU_JEU = "jeu"
NIVEAU_CORE_LOOP = "core_loop"
NIVEAU_SYSTEME = "systeme"
NIVEAU_ARTEFACTS = "artefacts"
NIVEAU_TESTS = "tests"
NIVEAU_VALIDATION = "validation"
NIVEAU_AMONT = "amont"

# Proprietaires par role producteur (repli quand la wiremap ne porte pas de
# proprietaire nominal — son champ `owner` est un booleen de POSSESSION DE
# CAPACITE, pas une personne ; voir `_proprietaire_systeme`).
PROPRIETAIRE_BUILDER = "Builder (game_forger)"
PROPRIETAIRE_ORACLES = "oracles deterministes (code/mutation/solvabilite)"
PROPRIETAIRE_HUMANGATE = "HUMANGATE (Pierre)"

# Rattachement famille de drift -> niveau de la chaine. Table EXPLICITE : une
# famille absente est rattachee au noeud Jeu avec sa raison, jamais perdue.
_NIVEAU_PAR_DRIFT: dict[str, str] = {
    # ecarts d'ecriture de fichiers -> la production d'artefacts
    "file_written_in_session_scratchpad": NIVEAU_ARTEFACTS,
    "file_written_outside_game_and_lab": NIVEAU_ARTEFACTS,
    "reference_guard_drift": NIVEAU_ARTEFACTS,
    # ecarts de pilotage/declaration -> le noeud Jeu (production globale)
    "tools_used_beyond_declared": NIVEAU_JEU,
    "tools_used_without_declaration": NIVEAU_JEU,
    "tool_observability_not_measured": NIVEAU_JEU,
    "token_accounting_below_measured": NIVEAU_JEU,
    "model_audit_differs_from_transcript": NIVEAU_JEU,
    "prompt_sans_empreinte_declaree": NIVEAU_JEU,
    "dispatch_prepared_never_executed": NIVEAU_JEU,
    "roadmap_doctrine_vs_mesure": NIVEAU_JEU,
    # la boucle lecon->consommateur vit APRES le verdict -> validation
    "lecon_routee_sans_consommateur": NIVEAU_VALIDATION,
}


# --------------------------------------------------------------------------- #
# Aides communes
# --------------------------------------------------------------------------- #


def _cell(value: Any, src: Optional[dict] = None,
          why: Optional[str] = None) -> dict[str, Any]:
    """Une cellule : valeur, provenance, raison si non observable (cockpit._cell)."""
    out: dict[str, Any] = {"v": value}
    if src:
        out["src"] = src
    if value == NOT_OBSERVABLE and why:
        out["why"] = why
    return out


def _short(text: Any, limit: int = 160) -> str:
    text = " ".join(str(text).split())
    return text if len(text) <= limit else text[:limit].rstrip() + "…"


def _evs(events: list[dict], kind: str,
         run_id: Optional[str] = None) -> list[dict]:
    out = [e for e in events if e.get("kind") == kind]
    if run_id:
        out = [e for e in out if e.get("run_id") == run_id]
    return out


def _first_ev(events: list[dict], kind: str,
              run_id: Optional[str] = None) -> Optional[dict]:
    for e in _evs(events, kind, run_id):
        return e
    return None


def _norm_path(path: Any) -> str:
    return str(path).replace("\\", "/").lower()


# --------------------------------------------------------------------------- #
# Sources derivees : dernier run pilote, wiremap, registre planning
# --------------------------------------------------------------------------- #


def _runs_pilotes(result: dict[str, Any]) -> list[dict[str, Any]]:
    """Meme critere d'appartenance que fleet._reconstruire_projet : « le driver
    l'a pilote », jamais « son nom ressemble »."""
    out = []
    for run in result.get("runs", []):
        if run.get("role") == "dryrun":
            continue
        if (run.get("role") == "attempt" or run.get("run_status") is not None
                or run.get("decision") is not None):
            out.append(run)
    return out


def _dernier_run(result: dict[str, Any]) -> Optional[dict[str, Any]]:
    pilotes = _runs_pilotes(result)
    if not pilotes:
        return None
    return max(pilotes, key=lambda r: (r.get("window") or {}).get("start") or "")


def _load_wiremap(ctx: Any) -> Optional[dict[str, Any]]:
    return ctx.read_json(ctx.run_dir / "wiremap.json")


def _load_registre_planning(ctx: Any) -> tuple[Any, Optional[str]]:
    """Lecture SEULE de studio_brain/planning/planning.yaml — vue derivee, le
    registre n'est jamais ecrit ni modifie par ce module."""
    path = ctx.repo_root / "studio_brain" / "planning" / "planning.yaml"
    if not ctx.exists(path):
        return NOT_OBSERVABLE, "studio_brain/planning/planning.yaml n'existe pas"
    text = ctx.read_text(path)
    if text is None:
        return NOT_OBSERVABLE, "planning.yaml existe mais est illisible"
    try:
        import yaml
    except ImportError:
        return (NOT_OBSERVABLE,
                "PyYAML indisponible dans cet interpreteur : registre non parse")
    try:
        data = yaml.safe_load(text)
    except yaml.YAMLError as exc:
        return NOT_OBSERVABLE, f"planning.yaml n'est pas un YAML valide : {exc}"
    if isinstance(data, dict):
        data = data.get("taches") or data.get("tasks") or []
    if not isinstance(data, list):
        return (NOT_OBSERVABLE,
                "format non reconnu (attendu : liste de taches, ou dict 'taches')")
    taches = [t for t in data if isinstance(t, dict) and t.get("id")]
    if not taches:
        return NOT_OBSERVABLE, "le registre existe mais ne porte aucune tache exploitable"
    return taches, None


def _taches_liees(taches: Any, project: str) -> list[dict[str, Any]]:
    """Taches du registre dont objectif/raison mentionne le jeu ou la Forge.
    Correspondance par sous-chaine insensible a la casse — best-effort assume."""
    if not isinstance(taches, list):
        return []
    tokens = {project.lower(), project.lower().split("_")[0], "forge"}
    liees = []
    for t in taches:
        texte = f"{t.get('objectif', '')} {t.get('raison', '')}".lower()
        hits = sorted(tok for tok in tokens if tok and tok in texte)
        if hits:
            liees.append({"tache": t, "match": hits})
    return liees


# --------------------------------------------------------------------------- #
# Graphe riche (projet courant, wiremap disponible)
# --------------------------------------------------------------------------- #


def _core_loop_system(wiremap: dict[str, Any]) -> Optional[dict[str, Any]]:
    """Regle mecanique : le systeme de categorie `system` avec le plus long
    `allowed_deps` est celui qui COMPOSE les autres — c'est le core loop."""
    candidats = [s for s in wiremap.get("systems", []) if s.get("category") == "system"]
    if not candidats:
        return None
    best = max(candidats, key=lambda s: len(s.get("allowed_deps") or []))
    if not (best.get("allowed_deps") or []):
        return None  # aucun systeme n'en compose d'autres : pas de core loop derivable
    return best


def _lines_par_systeme(wiremap: dict[str, Any]) -> dict[str, list[dict[str, Any]]]:
    par_sys: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for line in wiremap.get("lines", []):
        parent = line.get("system_parent")
        if parent:
            par_sys[parent].append(line)
    return par_sys


def _etat_systeme(lignes: list[dict[str, Any]],
                  fichiers_ecrits: int, fichiers_declares: int) -> tuple[str, Optional[str]]:
    """Etat d'un noeud systeme derive des lignes wiremap + de l'ecriture observee.

    IMPORTANT : la wiremap de breakout_v2 ne porte AUCUNE ligne IMPLEMENTED —
    `state` vaut REQUIRED/DEFERRED et `preuve` est vide sur toutes les lignes
    (verifie 2026-08-02). L'implementation ne peut donc etre affirmee que par le
    croisement avec les evenements file.write, jamais par la wiremap seule."""
    if not lignes:
        return (NOT_OBSERVABLE,
                "aucune ligne wiremap ne porte ce systeme (system_parent absent)")
    etats = Counter(l.get("state") for l in lignes)
    implemented = etats.get("IMPLEMENTED", 0)
    deferred = etats.get("DEFERRED", 0)
    avec_preuve = sum(1 for l in lignes if l.get("preuve"))
    if implemented == len(lignes) and avec_preuve == len(lignes):
        return "IMPLEMENTE_PROUVE_WIREMAP", None
    if fichiers_declares and fichiers_ecrits >= fichiers_declares:
        return "SPECIFIE_ET_FICHIERS_TOUS_OBSERVES_ECRITS", None
    if fichiers_ecrits > 0:
        return "SPECIFIE_ET_PARTIELLEMENT_ECRIT_OBSERVE", None
    if deferred == len(lignes):
        return "DIFFERE", None
    return "SPECIFIE_SANS_ECRITURE_OBSERVEE", None


def _fichiers_ecrits_observes(events: list[dict], project: str) -> set[str]:
    """Chemins ecrits/edites observes, normalises, restreints a games/<projet>/."""
    marqueur = f"games/{project.lower()}/"
    out: set[str] = set()
    for kind in ("file.write", "file.edit"):
        for e in _evs(events, kind):
            p = _norm_path((e.get("payload") or {}).get("path") or "")
            if marqueur in p:
                out.add(p.split(marqueur, 1)[1])
    return out


def _preuve_attendue_systeme(lignes: list[dict[str, Any]]) -> dict[str, Any]:
    kinds = Counter((l.get("expected_proof") or {}).get("kind") for l in lignes)
    kinds.pop(None, None)
    exemple = None
    for l in lignes:
        st = (l.get("expected_proof") or {}).get("statement")
        if st:
            exemple = _short(st, 180)
            break
    if not kinds:
        return {"v": NOT_OBSERVABLE,
                "why": "aucune ligne de ce systeme ne declare d'expected_proof"}
    return {"v": dict(kinds), "exemple": exemple,
            "src": {"path": "lab/forge_runs/*/wiremap.json",
                    "field": "lines[].expected_proof"}}


def _proprietaire_systeme(lignes: list[dict[str, Any]]) -> dict[str, Any]:
    """Le champ wiremap `owner` est un BOOLEEN (possession de capacite), pas un
    proprietaire nominal : aucune taxonomie de personnes n'existe dans la
    wiremap. Repli sur le role producteur (Builder), la provenance source_role
    des lignes est conservee comme information."""
    roles = Counter(l.get("source_role") for l in lignes if l.get("source_role"))
    cell = _cell(PROPRIETAIRE_BUILDER,
                 {"path": "scripts/forge/contracts", "field": "roles producteurs"})
    cell["provenance_lignes_source_role"] = dict(roles) if roles else NOT_OBSERVABLE
    cell["note"] = ("wiremap lines[].owner est un booleen de capacite, pas un "
                    "proprietaire — repli role producteur")
    return cell


def _risques_pour(niveau: str, drifts_par_niveau: dict[str, list[dict[str, Any]]]
                  ) -> list[dict[str, Any]]:
    return drifts_par_niveau.get(niveau, [])


def _classer_drifts(result: dict[str, Any],
                    project: str) -> tuple[dict[str, list[dict]], list[str]]:
    """Rattache chaque drift de la reconstruction a un niveau de la chaine.
    Retourne aussi la liste des familles NON mappees (rattachees au Jeu)."""
    par_niveau: dict[str, list[dict[str, Any]]] = defaultdict(list)
    non_mappees: set[str] = set()
    for item in result.get("drift", []):
        kind = item.get("type") or "type_absent"
        niveau = _NIVEAU_PAR_DRIFT.get(kind)
        entry = {
            "type": kind,
            "severity": item.get("severity"),
            "run_id": item.get("run_id"),
            "detail": _short(item.get("detail") or "", 200),
            "source": item.get("source"),
        }
        if niveau is None:
            niveau = NIVEAU_JEU
            entry["rattachement"] = ("famille non mappee a un niveau plus precis "
                                     "— rattachee au noeud Jeu, jamais perdue")
            non_mappees.add(kind)
        par_niveau[niveau].append(entry)
    return par_niveau, sorted(non_mappees)


def _noeud(node_id: str, niveau: str, etat: dict[str, Any],
           proprietaire: dict[str, Any], preuve: dict[str, Any],
           dependances: list[str], risques: list[dict[str, Any]],
           **extra: Any) -> dict[str, Any]:
    out = {
        "id": node_id,
        "niveau": niveau,
        "etat": etat,
        "proprietaire": proprietaire,
        "preuve_attendue": preuve,
        "dependances": dependances,
        "risques": risques,
    }
    out.update(extra)
    return out


def _ligne_fleet_projet(result: dict[str, Any], projet: str) -> Optional[dict[str, Any]]:
    """Premiere ligne (= dernier run, fleet est trie plus-recent-en-haut) du
    projet dans views.c8_fleet."""
    fleet = (result.get("views") or {}).get("c8_fleet") or {}
    for ligne in fleet.get("lignes", []):
        if ligne.get("v") == "ERREUR":
            continue
        if (ligne.get("projet") or {}).get("v") == projet:
            return ligne
    return None


def _noeud_jeu(result: dict[str, Any], events: list[dict], project: str,
               dernier: Optional[dict[str, Any]],
               risques: list[dict[str, Any]]) -> dict[str, Any]:
    ligne = _ligne_fleet_projet(result, project)
    if ligne is None:
        etat = _cell(NOT_OBSERVABLE, None,
                     "le projet n'apparait pas dans views.c8_fleet (aucun run pilote)")
        run_cell = _cell(NOT_OBSERVABLE, None, "aucun run pilote dans la flotte")
    else:
        etat = dict(ligne["decision"])  # cellule fleet reprise telle quelle (v/src/why)
        run_cell = dict(ligne["nom_humain"])

    # Proprietaire mesure : role de capacite dominant du dernier run pilote.
    if dernier and (dernier.get("actor") or {}).get("capability_roles"):
        roles = dernier["actor"]["capability_roles"]
        dominant = max(roles.items(), key=lambda kv: kv[1])[0]
        proprio = _cell(dominant,
                        {"path": f"lab/reports/observer/{project}/observer_run.json",
                         "field": "runs[].actor.capability_roles"})
        proprio["roles_mesures"] = dict(roles)
    else:
        proprio = _cell(NOT_OBSERVABLE, None,
                        "aucun run pilote ne porte de roles de capacite mesures")

    verdict_ev = _first_ev(events, "verdict.signed",
                           dernier.get("run_id") if dernier else None)
    preuve = _cell(
        "verdict signe HMAC re-verifiable (forge.verify_run)",
        verdict_ev.get("source") if verdict_ev else None)

    return _noeud(f"{project}:jeu", NIVEAU_JEU, etat, proprio, preuve, [], risques,
                  dernier_run=run_cell)


def _noeud_validation(result: dict[str, Any], events: list[dict], project: str,
                      dernier: Optional[dict[str, Any]],
                      risques: list[dict[str, Any]],
                      dependances: list[str]) -> dict[str, Any]:
    run_id = dernier.get("run_id") if dernier else None
    verdict = (dernier or {}).get("verdict") or {}
    verdict_ev = _first_ev(events, "verdict.signed", run_id)
    if verdict.get("decision"):
        etat = _cell(verdict["decision"],
                     verdict_ev.get("source") if verdict_ev else None)
        etat["software_verdict"] = verdict.get("software_verdict", NOT_OBSERVABLE)
        etat["hmac_present"] = bool(verdict.get("hmac"))
    else:
        etat = _cell(NOT_OBSERVABLE, None,
                     "aucun verdict signe n'existe pour le dernier run pilote")

    # HumanGate : le run est-il dans la file d'attente reconstruite ?
    hg = result.get("humangate") or {}
    en_attente_ids = {((e.get("run_id") or {}).get("v"))
                      for e in hg.get("en_attente", []) if isinstance(e, dict)}
    if run_id and run_id in en_attente_ids:
        humangate = _cell("EN_ATTENTE_DE_PIERRE",
                          {"path": f"lab/reports/observer/{project}/observer_run.json",
                           "field": "humangate.en_attente"})
    elif run_id:
        humangate = _cell(NOT_OBSERVABLE, None,
                          "le run n'apparait pas dans humangate.en_attente et aucune "
                          "trace d'enregistrement ne le concerne dans cette reconstruction")
    else:
        humangate = _cell(NOT_OBSERVABLE, None, "aucun run pilote")

    preuve = _cell("decision Pierre consignee dans "
                   "studio_brain/decisions/decision-log.md (merge/reject/freeze)")
    return _noeud(f"{project}:validation", NIVEAU_VALIDATION, etat,
                  _cell(PROPRIETAIRE_HUMANGATE), preuve, dependances, risques,
                  humangate=humangate)


def _noeud_tests(events: list[dict], project: str,
                 dernier: Optional[dict[str, Any]],
                 dependances: list[str]) -> dict[str, Any]:
    run_id = dernier.get("run_id") if dernier else None

    def _recu(kind: str, fmt) -> dict[str, Any]:
        ev = _first_ev(events, kind, run_id)
        if ev is None:
            return _cell(NOT_OBSERVABLE, None,
                         f"aucun evenement {kind} pour le dernier run pilote")
        return _cell(fmt(ev.get("payload") or {}), ev.get("source"))

    tests = _recu("test.result",
                  lambda p: f"{p.get('passed')}/{p.get('failed')} (ok/ko)")
    mutation = _recu("mutation.result",
                     lambda p: f"{p.get('killed')}/{p.get('total')} tues")
    solvabilite = _recu("solvability.result",
                        lambda p: f"{p.get('won')}/{p.get('trials')} gagnes "
                                  f"({p.get('verdict')})")
    oracles = {}
    for ev in _evs(events, "oracle.result", run_id):
        p = ev.get("payload") or {}
        oid = p.get("oracle_id") or "?"
        oracles[oid] = _cell(p.get("status", NOT_OBSERVABLE), ev.get("source"))
    if not oracles:
        oracles = {"_": _cell(NOT_OBSERVABLE, None,
                              "aucun oracle.result pour le dernier run pilote")}

    statuts = [c["v"] for c in (tests, mutation, solvabilite)] + \
              [c["v"] for c in oracles.values()]
    if all(v == NOT_OBSERVABLE for v in statuts):
        etat = _cell(NOT_OBSERVABLE, None,
                     "aucun recu d'oracle (test/mutation/solvabilite) observe "
                     "pour ce projet dans cette reconstruction")
    elif any(v in ("FAIL", "BLOCKED") for v in statuts if isinstance(v, str)):
        etat = _cell("AU_MOINS_UN_ORACLE_ROUGE")
    else:
        etat = _cell("RECUS_D_ORACLE_PRESENTS")

    preuve = _cell("recus deterministes non-LLM : test.result + mutation.result "
                   "+ solvability.result + oracle.result, chacun source")
    return _noeud(f"{project}:tests", NIVEAU_TESTS, etat,
                  _cell(PROPRIETAIRE_ORACLES), preuve, dependances, [],
                  tests=tests, mutation=mutation, solvabilite=solvabilite,
                  oracles=oracles)


def _graphe_riche(ctx: Any, result: dict[str, Any], events: list[dict],
                  project: str, wiremap: dict[str, Any],
                  taches_liees: list[dict[str, Any]]) -> dict[str, Any]:
    dernier = _dernier_run(result)
    drifts_par_niveau, familles_non_mappees = _classer_drifts(result, project)

    lines_par_sys = _lines_par_systeme(wiremap)
    ecrits = _fichiers_ecrits_observes(events, project)
    core = _core_loop_system(wiremap)
    core_id = core["id"] if core else None

    wiremap_src = {"path": f"lab/forge_runs/{project}/wiremap.json"}

    noeuds: list[dict[str, Any]] = []
    aretes: list[dict[str, str]] = []

    # ---- Jeu ------------------------------------------------------------- #
    risques_jeu = list(_risques_pour(NIVEAU_JEU, drifts_par_niveau))
    # Taches BLOQUE du registre liees au jeu = risques sur le noeud Jeu.
    for lien in taches_liees:
        t = lien["tache"]
        if t.get("etat") == "BLOQUE":
            risques_jeu.append({
                "type": "tache_planning_bloquee",
                "severity": "registre",
                "detail": _short(f"{t['id']} : {t.get('objectif', '')}", 200),
                "source": {"path": "studio_brain/planning/planning.yaml"},
                "depends_on": t.get("depends_on") or [],
            })
    n_jeu = _noeud_jeu(result, events, project, dernier, risques_jeu)
    noeuds.append(n_jeu)

    # ---- Core loop ------------------------------------------------------- #
    if core:
        lignes_core = lines_par_sys.get(core_id, [])
        decl_core = [f["path"] for l in lignes_core for f in (l.get("fichiers") or [])]
        ecrits_core = sum(1 for p in decl_core if _norm_path(p) in ecrits)
        etat_v, etat_why = _etat_systeme(lignes_core, ecrits_core, len(decl_core))
        n_core = _noeud(
            f"{project}:core_loop:{core_id}", NIVEAU_CORE_LOOP,
            _cell(etat_v, wiremap_src, etat_why),
            _proprietaire_systeme(lignes_core),
            _preuve_attendue_systeme(lignes_core),
            [n_jeu["id"]], [],
            derivation=("core loop = systeme de categorie 'system' au plus long "
                        "allowed_deps de la wiremap (regle mecanique) : "
                        f"{core_id} compose {len(core.get('allowed_deps') or [])} systemes"),
            role=_short(core.get("role") or "", 200))
        noeuds.append(n_core)
        aretes.append({"from": n_jeu["id"], "to": n_core["id"], "type": "chaine"})
        parent_systemes = n_core["id"]
    else:
        n_core = _noeud(
            f"{project}:core_loop", NIVEAU_CORE_LOOP,
            _cell(NOT_OBSERVABLE, None,
                  "aucun systeme de la wiremap ne compose les autres "
                  "(allowed_deps vides partout) : core loop non derivable"),
            _cell(NOT_OBSERVABLE, None, "core loop non derivable"),
            _cell(NOT_OBSERVABLE, None, "core loop non derivable"),
            [n_jeu["id"]], [])
        noeuds.append(n_core)
        aretes.append({"from": n_jeu["id"], "to": n_core["id"], "type": "chaine"})
        parent_systemes = n_core["id"]

    # ---- Systemes -------------------------------------------------------- #
    sys_node_ids: dict[str, str] = {}
    artefacts_par_systeme: dict[str, dict[str, int]] = {}
    for s in wiremap.get("systems", []):
        sid = s["id"]
        if sid == core_id:
            sys_node_ids[sid] = f"{project}:core_loop:{sid}"
            continue
        lignes = lines_par_sys.get(sid, [])
        declares = [f["path"] for l in lignes for f in (l.get("fichiers") or [])]
        n_ecrits = sum(1 for p in declares if _norm_path(p) in ecrits)
        artefacts_par_systeme[sid] = {"declares": len(declares),
                                      "observes_ecrits": n_ecrits}
        etat_v, etat_why = _etat_systeme(lignes, n_ecrits, len(declares))
        node_id = f"{project}:systeme:{sid}"
        sys_node_ids[sid] = node_id
        noeuds.append(_noeud(
            node_id, NIVEAU_SYSTEME,
            _cell(etat_v, wiremap_src, etat_why),
            _proprietaire_systeme(lignes),
            _preuve_attendue_systeme(lignes),
            [parent_systemes], [],
            categorie=s.get("category"),
            lignes_wiremap={"n": len(lignes),
                            "par_state": dict(Counter(l.get("state") for l in lignes))}
            if lignes else {"n": 0, "why": "aucune ligne wiremap sur ce systeme"},
            fichiers={"declares": len(declares), "observes_ecrits": n_ecrits},
            role=_short(s.get("role") or "", 160)))
        aretes.append({"from": parent_systemes, "to": node_id, "type": "chaine"})

    # Dependances wiremap entre systemes (allowed_deps) — aretes typees.
    for s in wiremap.get("systems", []):
        src_node = sys_node_ids.get(s["id"])
        for dep in s.get("allowed_deps") or []:
            dst_node = sys_node_ids.get(dep)
            if src_node and dst_node and src_node != dst_node:
                aretes.append({"from": src_node, "to": dst_node,
                               "type": "dependance_wiremap"})

    # Dependances de capacite entre lignes (requires[] -> provides[] owner).
    provides_owner: dict[str, str] = {}
    for line in wiremap.get("lines", []):
        if line.get("owner"):
            for cap in line.get("provides") or []:
                provides_owner.setdefault(cap, line.get("system_parent") or "")
    vues: set[tuple[str, str]] = set()
    for line in wiremap.get("lines", []):
        src_sys = line.get("system_parent")
        for cap in line.get("requires") or []:
            dst_sys = provides_owner.get(cap)
            a, b = sys_node_ids.get(src_sys or ""), sys_node_ids.get(dst_sys or "")
            if a and b and a != b and (a, b) not in vues:
                vues.add((a, b))
                aretes.append({"from": a, "to": b, "type": "requires_capacite",
                               "capacite": cap})

    # ---- Artefacts ------------------------------------------------------- #
    total_declares = sum(v["declares"] for v in artefacts_par_systeme.values())
    total_ecrits_declares = sum(v["observes_ecrits"]
                                for v in artefacts_par_systeme.values())
    n_ecrits_global = len(ecrits)
    if n_ecrits_global == 0:
        etat_art = _cell(NOT_OBSERVABLE, None,
                         f"aucun evenement file.write/file.edit sous games/{project}/ "
                         "dans cette reconstruction")
    else:
        etat_art = _cell(
            f"{n_ecrits_global} fichier(s) observes ecrits sous games/{project}/",
            {"path": f"lab/reports/observer/{project}/events.jsonl",
             "field": "file.write/file.edit"})
    risques_art = _risques_pour(NIVEAU_ARTEFACTS, drifts_par_niveau)
    n_art = _noeud(
        f"{project}:artefacts", NIVEAU_ARTEFACTS, etat_art,
        _cell(PROPRIETAIRE_BUILDER),
        _cell("chaque fichier declare par une ligne wiremap doit etre observe "
              "ecrit sous games/<jeu>/ pendant un run pilote"),
        sorted(sys_node_ids.values()), risques_art,
        par_systeme=artefacts_par_systeme if artefacts_par_systeme else
        {"why": "aucun rattachement fichier->systeme derivable"},
        global_={"fichiers_declares_wiremap": total_declares,
                 "declares_observes_ecrits": total_ecrits_declares,
                 "observes_ecrits_total": n_ecrits_global
                 if n_ecrits_global else NOT_OBSERVABLE})
    noeuds.append(n_art)
    for nid in sorted(set(sys_node_ids.values())):
        aretes.append({"from": nid, "to": n_art["id"], "type": "chaine"})

    # ---- Tests ----------------------------------------------------------- #
    n_tests = _noeud_tests(events, project, dernier, [n_art["id"]])
    n_tests["risques"] = _risques_pour(NIVEAU_TESTS, drifts_par_niveau)
    noeuds.append(n_tests)
    aretes.append({"from": n_art["id"], "to": n_tests["id"], "type": "chaine"})

    # ---- Validation ------------------------------------------------------ #
    n_val = _noeud_validation(result, events, project, dernier,
                              _risques_pour(NIVEAU_VALIDATION, drifts_par_niveau),
                              [n_tests["id"]])
    noeuds.append(n_val)
    aretes.append({"from": n_tests["id"], "to": n_val["id"], "type": "chaine"})

    # ---- Noeuds AMONT (registre planning, lecture seule) ------------------ #
    for lien in taches_liees:
        t = lien["tache"]
        node_id = f"amont:{t['id']}"
        noeuds.append(_noeud(
            node_id, NIVEAU_AMONT,
            _cell(t.get("etat", NOT_OBSERVABLE),
                  {"path": "studio_brain/planning/planning.yaml"}),
            _cell(PROPRIETAIRE_HUMANGATE),
            _cell(_short(t.get("preuve_de_fin") or NOT_OBSERVABLE, 200)),
            [], [],
            objectif=_short(t.get("objectif") or "", 200),
            priorite=t.get("priorite", NOT_OBSERVABLE),
            depends_on=t.get("depends_on") or [],
            match=lien["match"]))
        aretes.append({"from": node_id, "to": n_jeu["id"],
                       "type": "registre_planning"})

    return {
        "type": "riche",
        "source_wiremap": f"lab/forge_runs/{project}/wiremap.json",
        "noeuds": noeuds,
        "aretes": aretes,
        "familles_drift_non_mappees": familles_non_mappees,
    }


# --------------------------------------------------------------------------- #
# Graphe reduit (autres projets de la flotte, wiremap non lisible ici)
# --------------------------------------------------------------------------- #

_WHY_REDUIT = ("wiremap non chargee pour ce projet : les racines de lecture de "
               "cette reconstruction sont limitees au projet courant (cecite "
               "structurelle sources.py) — chainon non derivable")


def _graphe_reduit(projet: str, ligne: dict[str, Any],
                   taches_liees: list[dict[str, Any]]) -> dict[str, Any]:
    def c(nom: str) -> dict[str, Any]:
        cell = ligne.get(nom)
        return dict(cell) if isinstance(cell, dict) else _cell(
            NOT_OBSERVABLE, None, f"colonne {nom} absente de la ligne de flotte")

    n_jeu = _noeud(f"{projet}:jeu", NIVEAU_JEU, c("decision"),
                   _cell(NOT_OBSERVABLE, None,
                         "roles de capacite non mesures dans le balayage de flotte"),
                   _cell("verdict signe HMAC re-verifiable"), [], [],
                   dernier_run=c("nom_humain"))

    tests_c, mutation_c = c("tests"), c("mutation")
    if tests_c["v"] == NOT_OBSERVABLE and mutation_c["v"] == NOT_OBSERVABLE:
        etat_tests = _cell(NOT_OBSERVABLE, None,
                           "aucun recu de test ni de mutation dans la ligne de flotte")
    else:
        etat_tests = _cell("RECUS_D_ORACLE_PRESENTS")
    n_tests = _noeud(f"{projet}:tests", NIVEAU_TESTS, etat_tests,
                     _cell(PROPRIETAIRE_ORACLES),
                     _cell("recus test.result / mutation.result de la flotte"),
                     [f"{projet}:jeu"], [],
                     tests=tests_c, mutation=mutation_c)

    n_val = _noeud(f"{projet}:validation", NIVEAU_VALIDATION, c("decision"),
                   _cell(PROPRIETAIRE_HUMANGATE),
                   _cell("decision Pierre consignee dans le decision-log"),
                   [f"{projet}:tests"], [])

    chainon_manquant = _cell(NOT_OBSERVABLE, None, _WHY_REDUIT)

    noeuds = [n_jeu, n_tests, n_val]
    aretes = [{"from": f"{projet}:jeu", "to": f"{projet}:tests", "type": "chaine"},
              {"from": f"{projet}:tests", "to": f"{projet}:validation",
               "type": "chaine"}]
    for lien in taches_liees:
        t = lien["tache"]
        node_id = f"amont:{t['id']}"
        noeuds.append(_noeud(
            node_id, NIVEAU_AMONT,
            _cell(t.get("etat", NOT_OBSERVABLE),
                  {"path": "studio_brain/planning/planning.yaml"}),
            _cell(PROPRIETAIRE_HUMANGATE),
            _cell(_short(t.get("preuve_de_fin") or NOT_OBSERVABLE, 200)),
            [], [], objectif=_short(t.get("objectif") or "", 200),
            match=lien["match"]))
        aretes.append({"from": node_id, "to": f"{projet}:jeu",
                       "type": "registre_planning"})

    return {
        "type": "reduit",
        "chainons_non_derivables": {
            "core_loop": chainon_manquant,
            "systemes": chainon_manquant,
            "artefacts": chainon_manquant,
        },
        "noeuds": noeuds,
        "aretes": aretes,
    }


# --------------------------------------------------------------------------- #
# Assemblage
# --------------------------------------------------------------------------- #


def _bloquants(graphe: dict[str, Any]) -> list[str]:
    out = []
    for n in graphe["noeuds"]:
        v = n["etat"].get("v")
        if isinstance(v, str) and ("BLOCKED" in v or "BLOQUE" in v or "ROUGE" in v):
            out.append(n["id"])
        if any(r.get("severity") == "high" for r in n.get("risques", [])):
            out.append(n["id"] + " (risque high)")
    return out


def view_production(ctx: Any, result: dict[str, Any],
                    events: list[dict[str, Any]]) -> dict[str, Any]:
    project = result.get("project") or ctx.project

    wiremap = _load_wiremap(ctx)
    taches, taches_why = _load_registre_planning(ctx)

    graphes: dict[str, dict[str, Any]] = {}

    # --- projet courant : graphe riche si la wiremap existe --------------- #
    liees_courant = _taches_liees(taches, project)
    if wiremap and wiremap.get("systems"):
        graphes[project] = _graphe_riche(ctx, result, events, project, wiremap,
                                         liees_courant)
    else:
        ligne = _ligne_fleet_projet(result, project)
        if ligne is not None:
            g = _graphe_reduit(project, ligne, liees_courant)
            g["why_reduit"] = (f"lab/forge_runs/{project}/wiremap.json absente ou "
                               "sans systems[] : graphe riche non derivable")
            graphes[project] = g
        else:
            graphes[project] = {
                "type": NOT_OBSERVABLE,
                "why": "ni wiremap ni ligne de flotte pour le projet courant",
                "noeuds": [], "aretes": [],
            }

    # --- autres projets de la flotte : version reduite --------------------- #
    fleet = (result.get("views") or {}).get("c8_fleet") or {}
    vus: set[str] = {project}
    for ligne in fleet.get("lignes", []):
        if ligne.get("v") == "ERREUR":
            continue
        projet = (ligne.get("projet") or {}).get("v")
        if not projet or projet in vus:
            continue  # fleet trie plus-recent-en-haut : 1re occurrence = dernier run
        vus.add(projet)
        graphes[projet] = _graphe_reduit(projet, ligne, _taches_liees(taches, projet))

    if not fleet.get("lignes"):
        graphes["_flotte"] = {
            "type": NOT_OBSERVABLE,
            "why": "views.c8_fleet absente de la reconstruction : les autres "
                   "projets ne peuvent pas etre derives",
            "noeuds": [], "aretes": [],
        }

    # --- resume ------------------------------------------------------------ #
    n_noeuds = sum(len(g.get("noeuds", [])) for g in graphes.values())
    n_aretes = sum(len(g.get("aretes", [])) for g in graphes.values())
    bloquants = {p: _bloquants(g) for p, g in graphes.items()
                 if g.get("noeuds") and _bloquants(g)}
    n_bloq = sum(len(v) for v in bloquants.values())
    resume = (f"{len([g for g in graphes.values() if g.get('noeuds')])} jeu(x) en "
              f"graphe ({n_noeuds} noeuds, {n_aretes} aretes). "
              f"{n_bloq} point(s) de blocage ou risque high localises."
              if n_bloq else
              f"{len([g for g in graphes.values() if g.get('noeuds')])} jeu(x) en "
              f"graphe ({n_noeuds} noeuds, {n_aretes} aretes). Aucun blocage "
              "localise dans les etats de noeud.")

    registre_cell = (_cell(f"{len(taches)} tache(s) lue(s) (lecture seule)",
                           {"path": "studio_brain/planning/planning.yaml"})
                     if isinstance(taches, list)
                     else _cell(NOT_OBSERVABLE, None, taches_why))

    return {
        "question": QUESTION,
        "resume": resume,
        "chaine_ratifiee": [NIVEAU_JEU, NIVEAU_CORE_LOOP, NIVEAU_SYSTEME,
                            NIVEAU_ARTEFACTS, NIVEAU_TESTS, NIVEAU_VALIDATION],
        "registre_planning": registre_cell,
        "graphes": graphes,
        "bloquants": bloquants if bloquants else
        {"_": "aucun noeud en etat bloquant ni risque high"},
        "note_derivation": (
            "Vue ENTIEREMENT derivee (wiremap + evenements + flotte + registre "
            "planning en LECTURE seule) — rien de saisi, aucune ecriture. "
            "Limite honnete : la wiremap breakout_v2 ne porte aucune ligne "
            "IMPLEMENTED (state=REQUIRED/DEFERRED, champ preuve vide partout) ; "
            "l'implementation n'est affirmee que via les ecritures de fichiers "
            "observees dans les evenements, jamais supposee."),
    }


def build_production_views(ctx: Any, result: dict[str, Any],
                           events: list[dict[str, Any]]) -> dict[str, Any]:
    return {"s9_production": view_production(ctx, result, events)}


# --------------------------------------------------------------------------- #
# Preuve d'execution
# --------------------------------------------------------------------------- #

if __name__ == "__main__":
    import json

    from observer.sources import ObserverContext, default_repo_root, default_transcripts_root  # noqa: E402

    logging.basicConfig(level=logging.WARNING)
    try:  # console Windows cp1252 : jamais un crash d'affichage pour un accent
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except AttributeError:
        pass

    repo_root = default_repo_root()
    transcripts_root = default_transcripts_root(repo_root)
    project = "breakout_v2"
    ctx = ObserverContext.build(repo_root, project, transcripts_root)

    report_dir = repo_root / "lab" / "reports" / "observer" / project
    with (report_dir / "observer_run.json").open("r", encoding="utf-8-sig") as fh:
        result = json.load(fh)

    events: list[dict[str, Any]] = []
    with (report_dir / "events.jsonl").open("r", encoding="utf-8-sig") as fh:
        for line in fh:
            line = line.strip()
            if line:
                events.append(json.loads(line))

    views = build_production_views(ctx, result, events)
    prod = views["s9_production"]

    print(f"question : {prod['question']}")
    print(f"resume   : {prod['resume']}")
    print(f"registre : {prod['registre_planning']['v']}")

    print("\n--- graphes par jeu ---")
    for projet, g in prod["graphes"].items():
        noeuds, aretes = g.get("noeuds", []), g.get("aretes", [])
        par_niveau = Counter(n["niveau"] for n in noeuds)
        print(f"  {projet:<22} type={g.get('type'):<8} "
              f"{len(noeuds):>3} noeuds / {len(aretes):>3} aretes  "
              f"{dict(par_niveau)}")

    riche = prod["graphes"].get(project, {})
    print(f"\n--- detail {project} (graphe riche) ---")
    for n in riche.get("noeuds", []):
        v = n["etat"].get("v")
        risq = f" risques={len(n['risques'])}" if n.get("risques") else ""
        print(f"  [{n['niveau']:<11}] {n['id']:<45} etat={_short(v, 60)}{risq}")

    types_aretes = Counter(a["type"] for a in riche.get("aretes", []))
    print(f"  aretes par type : {dict(types_aretes)}")

    print("\n--- bloquants ---")
    for projet, ids in (prod["bloquants"].items()
                        if isinstance(prod["bloquants"], dict) else []):
        print(f"  {projet}: {ids}")

    blob = json.dumps(views, ensure_ascii=False)
    json.loads(blob)  # round-trip : la vue est integralement serialisable
    print(f"\nserialisation JSON OK ({len(blob)} caracteres, round-trip verifie)")
