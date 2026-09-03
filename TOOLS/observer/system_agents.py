"""Vues SYSTÈME de Forge Observer V0 — « la vraie fiche, pas le YAML ».

Directive ratifiée (Pierre, build cockpit 2026-08-01) : le cockpit doit montrer
le SYSTÈME (les agents, leur contrat, ce qu'ils reçoivent vraiment), pas
seulement l'exécution d'un run. Ce module lit les contrats d'agent Forge
(`scripts/forge/contracts/*.yaml`), `roles.yaml` (résolution de modèle) et les
prompts réellement reçus (`observer.prompt.collect_prompts`) pour produire
trois vues :

  * `view_agents`    (s3_agents)   — une FICHE complète par contrat, les 18
    colonnes du tableau ratifié, enrichie de faits vivants (dernière
    activation, modèle mesuré vs déclaré, outils observés).
  * `view_injection` (s6_injection) — le pipeline d'assemblage du prompt :
    pour chaque activation, confronte DECLARE (le champ existe-t-il dans le
    contrat) à OBSERVE (la section correspondante est-elle vraiment dans le
    texte reçu par l'agent), maillon par maillon.
  * `view_prompt`    (s4_prompt)   — le texte réellement reçu, réorganisé par
    activation : en-tête, séquence des sections réelles, texte intégral en
    dernier recours.

Fait vérifié en lisant `scripts/forge/contract.py::_render_prompt` avant
d'écrire ce module (jamais importé — indépendance d'Observer vis-à-vis du
module `forge`, même règle que `observer/prompt.py`) : le contrat ne rend en
section QUE {RÔLE, EXIGENCES COGNITIVES, MÉMOIRE DE TRAVAIL, OBJECTIF, DANS/
HORS PÉRIMÈTRE, PERMISSIONS, GARDE-FOU, CRITÈRES DE RÉUSSITE, ORACLES/TESTS,
CONTRAT DE SORTIE, RAPPORT FINAL, À LIRE OBLIGATOIREMENT, RÈGLE DE
RESTITUTION, MARQUEUR DE DISPATCH}. `skill`/`plugin` ne sont JAMAIS rendus en
section (ils ne servent qu'à borner `allowed_tools`) et `delegation_context`
n'est JAMAIS rendu non plus, bien qu'il soit un champ RECOMMENDED validé. Les
sections « TÂCHE CONCRÈTE », « PRÉ-MORTEM » et « ARTEFACTS AMONT » observées
dans les transcripts réels viennent donc d'une couche D'ASSEMBLAGE en aval du
contrat (le driver de run), jamais du contrat lui-même — ce module le mesure,
il ne le suppose pas.

Lecture UNIQUEMENT via `ObserverContext` (garde de cécité) pour les contrats
et les transcripts. Aucune écriture. Aucun `open()` direct dans les fonctions
de vue. `BlindnessViolation` n'est JAMAIS rattrapée.
"""

from __future__ import annotations

import argparse
import json
import logging
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Any, Optional

import yaml

_HERE = Path(__file__).resolve().parent
if str(_HERE.parent) not in sys.path:  # rend `import observer` possible sans install
    sys.path.insert(0, str(_HERE.parent))

from observer.fleet import human_name_etape, human_name_session  # noqa: E402
from observer.prompt import _LIRE_RE, _MEMOIRE_RE, _find_section, collect_prompts  # noqa: E402
from observer.sources import (  # noqa: E402
    ObserverContext,
    default_repo_root,
    default_transcripts_root,
)

LOG = logging.getLogger("observer.system_agents")

NOT_OBSERVABLE = "NOT_OBSERVABLE"

# Fichiers de scripts/forge/contracts/ qui ne sont PAS des contrats d'agent
# (registre de résolution de modèle) — exclus de la vue AGENTS.
_NON_CONTRACT_FILES = frozenset({"roles.yaml"})

_CONTRACTS_SUBPATH = ("scripts", "forge", "contracts")


def _contracts_dir(ctx: ObserverContext) -> Path:
    return ctx.repo_root.joinpath(*_CONTRACTS_SUBPATH)


# --------------------------------------------------------------------------- #
# Cellule {v, src, why} — même contrat que cockpit.py/fleet.py.
# --------------------------------------------------------------------------- #


def _cell(value: Any, src: Optional[dict[str, Any]] = None, why: Optional[str] = None) -> dict[str, Any]:
    out: dict[str, Any] = {"v": value}
    if src:
        out["src"] = src
    if value == NOT_OBSERVABLE and why:
        out["why"] = why
    return out


# --------------------------------------------------------------------------- #
# Modèle à 3 états d'un champ de contrat (SCHEMA.md) — reproduit, pas importé.
#
# `scripts/forge/contract.py::field_state` fait exactement ceci, mais Observer
# ne doit JAMAIS dépendre du module `forge` (même règle d'indépendance que
# `observer/prompt.py`, cf. sa docstring de module ~l.60). Reproduit ici pour
# la même raison : un champ est DÉCLARÉ s'il est rempli OU s'il porte la
# sentinelle `aucun` (décision assumée) — il est ABSENT seulement si la clé
# manque ou si sa valeur est vide.
# --------------------------------------------------------------------------- #


def _field_declared(value: Any) -> bool:
    if value is None:
        return False
    if isinstance(value, str):
        return bool(value.strip())
    if isinstance(value, (list, tuple, dict)):
        return len(value) > 0
    return True


def _delegation_value_and_field(contract: dict[str, Any]) -> tuple[Any, str]:
    """`delegation_context` fait foi ; `parent_agent` (mentionné par la
    mission de fabrication) n'existe dans AUCUN contrat réel observé —
    `scripts/forge/contract.py::RECOMMENDED = ("delegation_context",)`
    confirme qu'il n'est pas un champ canonique. Le repli existe quand même,
    au cas où un contrat futur l'utilise."""
    value = contract.get("delegation_context")
    field = "delegation_context"
    if not _field_declared(value) and _field_declared(contract.get("parent_agent")):
        value = contract.get("parent_agent")
        field = "parent_agent"
    return value, field


def _contract_field_cell(contract: dict[str, Any], field: str, path_str: str) -> dict[str, Any]:
    value = contract.get(field)
    if not _field_declared(value):
        return _cell(NOT_OBSERVABLE, None, "champ absent du contrat")
    return _cell(value, {"path": path_str, "field": field})


# --------------------------------------------------------------------------- #
# roles.yaml — résolution capability_role -> modèle/reasoning.
# --------------------------------------------------------------------------- #


def _load_roles_models(ctx: ObserverContext) -> list[dict[str, Any]]:
    path = _contracts_dir(ctx) / "roles.yaml"
    text = ctx.read_text(path)
    if text is None:
        return []
    try:
        data = yaml.safe_load(text)
    except yaml.YAMLError as exc:
        LOG.warning("roles.yaml illisible: %s", exc)
        return []
    models = data.get("models") if isinstance(data, dict) else None
    if not isinstance(models, list):
        return []
    return [m for m in models if isinstance(m, dict)]


def _resolve_role(models: list[dict[str, Any]], capability_role: Optional[str]) -> Optional[dict[str, Any]]:
    """Premier modèle qui déclare le rôle gagne — même règle que
    `control_plane/registry.py:39`, reproduite ici en lecture seule."""
    if not capability_role:
        return None
    for model in models:
        roles = model.get("roles") or []
        if capability_role in roles:
            return model
    return None


def _modele_cell(
    models: list[dict[str, Any]], capability_role: Optional[str], roles_path_str: str
) -> dict[str, Any]:
    if not capability_role:
        return _cell(NOT_OBSERVABLE, None, "capability_role absent du contrat : aucune resolution possible")
    model = _resolve_role(models, capability_role)
    if model is None:
        return _cell(
            NOT_OBSERVABLE,
            {"path": roles_path_str, "field": "models[].roles"},
            f"aucun modele de roles.yaml ne declare le role {capability_role!r} (RoleUnresolved)",
        )
    return _cell(
        model.get("id") or model.get("name") or NOT_OBSERVABLE,
        {"path": roles_path_str, "field": f"models[roles contient {capability_role!r}].id"},
    )


def _reasoning_cell(
    contract: dict[str, Any],
    models: list[dict[str, Any]],
    capability_role: Optional[str],
    contract_path_str: str,
    roles_path_str: str,
) -> dict[str, Any]:
    # Aucun contrat reel n'a de champ `reasoning_effort` (absent des 17 champs
    # canoniques de SCHEMA.md) — verifie sur les contrats lus pour ce module.
    # Le repli existe quand meme si un contrat futur le declare.
    explicit = contract.get("reasoning_effort")
    if _field_declared(explicit):
        return _cell(explicit, {"path": contract_path_str, "field": "reasoning_effort"})
    model = _resolve_role(models, capability_role) if capability_role else None
    if model is None:
        return _cell(
            NOT_OBSERVABLE, None,
            "aucun champ reasoning_effort dans le contrat et role non resolu dans roles.yaml",
        )
    reasoning = model.get("reasoning")
    if reasoning is None:
        return _cell(
            NOT_OBSERVABLE, {"path": roles_path_str},
            "le modele resolu ne porte pas de champ 'reasoning' dans roles.yaml",
        )
    return _cell(reasoning, {"path": roles_path_str, "field": "models[].reasoning"})


# --------------------------------------------------------------------------- #
# Enrichissement vivant — croisement contrat x traces du projet observe.
# --------------------------------------------------------------------------- #


def _derniere_activation(events: list[dict[str, Any]], stem: str) -> dict[str, Any]:
    evs = [e for e in events if e.get("kind") == "dispatch.prepared" and e.get("etape") == stem]
    if not evs:
        return _cell(NOT_OBSERVABLE, None, "aucune activation dans le projet observe")
    dernier = max(evs, key=lambda e: e.get("ts") or 0)
    s = dernier.get("source", {}) or {}
    src: dict[str, Any] = {"path": s.get("path", "")}
    if s.get("line") is not None:
        src["line"] = s["line"]
    cell = _cell(dernier.get("ts_iso") or dernier.get("ts") or NOT_OBSERVABLE, src)
    cell["run_id"] = dernier.get("run_id")
    return cell


def _modele_declare_vs_mesure(events: list[dict[str, Any]], stem: str) -> dict[str, Any]:
    """Meme comparaison que `correlate.py::reconstruct` (drift
    `model_audit_differs_from_transcript`), recalculee ici directement depuis
    les evenements pour porter un badge PAR CONTRAT meme quand aucun drift
    n'a ete emis (cas ou modele declare == modele mesure : le badge doit
    quand meme afficher COHERENT, pas rester silencieux)."""
    declared: set[str] = set()
    for e in events:
        if e.get("etape") != stem:
            continue
        if e.get("kind") not in ("dispatch.prepared", "dispatch.executed", "dispatch.context_manifest"):
            continue
        payload = e.get("payload", {}) or {}
        actor = e.get("actor", {}) or {}
        for candidate in (payload.get("model"), actor.get("model")):
            if candidate and candidate not in ("", "non-llm"):
                declared.add(str(candidate))

    observed: Counter[str] = Counter()
    for e in events:
        if e.get("etape") != stem or e.get("kind") != "llm.usage":
            continue
        payload = e.get("payload", {}) or {}
        actor = e.get("actor", {}) or {}
        model = payload.get("model") or actor.get("model")
        if model and model != "<synthetic>":
            observed[str(model)] += 1

    if not declared or not observed:
        raisons = []
        if not declared:
            raisons.append("aucun modele declare (dispatch.prepared/executed/context_manifest) pour cette etape")
        if not observed:
            raisons.append("aucun usage LLM mesure (llm.usage) pour cette etape")
        return _cell(NOT_OBSERVABLE, None, " ; ".join(raisons))

    ecart = not (declared & set(observed))
    return _cell({
        "badge": "ECART" if ecart else "COHERENT",
        "modele_declare": sorted(declared),
        "modele_mesure": dict(observed.most_common()),
    })


def _outils_observes(events: list[dict[str, Any]], stem: str) -> dict[str, Any]:
    appels: Counter[str] = Counter()
    src: Optional[dict[str, Any]] = None
    for e in events:
        if e.get("etape") != stem or e.get("kind") != "tool.call":
            continue
        payload = e.get("payload", {}) or {}
        name = payload.get("tool_name")
        if not name:
            continue
        appels[name] += 1
        if src is None:
            s = e.get("source", {}) or {}
            src = {"path": s.get("path", "")}
            if s.get("line") is not None:
                src["line"] = s["line"]
    if not appels:
        return _cell(NOT_OBSERVABLE, None, "aucun appel d'outil observe pour cette etape dans ce projet")
    return _cell(dict(appels.most_common()), src)


# --------------------------------------------------------------------------- #
# s3_agents — une fiche complete par contrat
# --------------------------------------------------------------------------- #

# Colonnes du tableau ratifie, dans l'ordre d'affichage (18 champs : 15 champs
# de contrat + nom_humain + modele resolu + reasoning_effort resolu).
AGENT_COLONNES: tuple[tuple[str, str], ...] = (
    ("nom_humain", "nom humain"),
    ("posture", "posture (role)"),
    ("capability", "capability (capability_role)"),
    ("modele", "modele (resolu via roles.yaml)"),
    ("reasoning_effort", "reasoning effort"),
    ("exigences_cognitives", "exigences cognitives"),
    ("memoire", "memoire"),
    ("mandatory_read", "mandatory read"),
    ("objectif", "objectif"),
    ("in_scope", "in scope"),
    ("out_of_scope", "out of scope"),
    ("permissions", "permissions"),
    ("guard_rails", "guard rails (gardeFou)"),
    ("tests", "tests (tests_oracles)"),
    ("success", "success (success_criteria)"),
    ("output_contract", "output contract"),
    ("skill", "skill"),
    ("plugin", "plugin"),
    ("delegation", "delegation (parent_agent/delegation_context)"),
)


def view_agents(ctx: ObserverContext, result: dict[str, Any], events: list[dict[str, Any]]) -> dict[str, Any]:
    """Une FICHE complete par contrat de `scripts/forge/contracts/*.yaml`.

    `result` n'est pas consomme directement ici (les faits vivants viennent
    des `events` deja rattaches par run_id/etape) — conserve dans la
    signature pour respecter l'interface imposee et parce que d'autres
    enrichissements futurs (ex. verdicts signes par etape) en auront besoin.
    """
    del result  # reserve pour enrichissements futurs — voir docstring

    contracts_dir = _contracts_dir(ctx)
    roles_path_str = ctx.rel(contracts_dir / "roles.yaml")
    models = _load_roles_models(ctx)

    fiches: list[dict[str, Any]] = []
    for path in ctx.iter_files(contracts_dir, "*.yaml"):
        if path.name in _NON_CONTRACT_FILES:
            continue
        text = ctx.read_text(path)
        if text is None:
            continue
        try:
            contract = yaml.safe_load(text)
        except yaml.YAMLError as exc:
            LOG.warning("contrat illisible %s: %s", ctx.rel(path), exc)
            continue
        if not isinstance(contract, dict):
            LOG.warning("contrat %s n'est pas un mapping YAML, ignore", ctx.rel(path))
            continue

        stem = path.stem
        path_str = ctx.rel(path)
        capability_role = contract.get("capability_role")
        delegation_value, delegation_field = _delegation_value_and_field(contract)

        fiche: dict[str, Any] = {
            "fichier": stem,
            "nom_humain": _cell(human_name_etape(stem)),
            "posture": _contract_field_cell(contract, "role", path_str),
            "capability": _contract_field_cell(contract, "capability_role", path_str),
            "modele": _modele_cell(models, capability_role, roles_path_str),
            "reasoning_effort": _reasoning_cell(contract, models, capability_role, path_str, roles_path_str),
            "exigences_cognitives": _contract_field_cell(contract, "exigences_cognitives", path_str),
            "memoire": _contract_field_cell(contract, "memoire", path_str),
            "mandatory_read": _contract_field_cell(contract, "mandatory_read", path_str),
            "objectif": _contract_field_cell(contract, "objectif", path_str),
            "in_scope": _contract_field_cell(contract, "in_scope", path_str),
            "out_of_scope": _contract_field_cell(contract, "out_of_scope", path_str),
            "permissions": _contract_field_cell(contract, "permissions", path_str),
            "guard_rails": _contract_field_cell(contract, "gardeFou", path_str),
            "tests": _contract_field_cell(contract, "tests_oracles", path_str),
            "success": _contract_field_cell(contract, "success_criteria", path_str),
            "output_contract": _contract_field_cell(contract, "output_contract", path_str),
            "skill": _contract_field_cell(contract, "skill", path_str),
            "plugin": _contract_field_cell(contract, "plugin", path_str),
            "delegation": (
                _cell(delegation_value, {"path": path_str, "field": delegation_field})
                if _field_declared(delegation_value)
                else _cell(
                    NOT_OBSERVABLE, None,
                    "champ absent du contrat (ni delegation_context ni parent_agent)",
                )
            ),
            "enrichissement": {
                "derniere_activation": _derniere_activation(events, stem),
                "modele_declare_vs_mesure": _modele_declare_vs_mesure(events, stem),
                "outils_observes": _outils_observes(events, stem),
            },
        }
        fiches.append(fiche)

    fiches.sort(key=lambda f: f["fichier"])
    return {
        "colonnes": [{"cle": k, "titre": t} for k, t in AGENT_COLONNES],
        "lignes": fiches,
        "note_enrichissement": "derniere_activation/modele_declare_vs_mesure/outils_observes croisent "
                                "le contrat avec les traces du PROJET COURANT UNIQUEMENT — un contrat "
                                "jamais active dans ce projet reste affiche, avec NOT_OBSERVABLE et sa "
                                "raison sur les trois champs d'enrichissement.",
    }


# --------------------------------------------------------------------------- #
# s6_injection — chaine d'assemblage DECLARE x OBSERVE, maillon par maillon
# --------------------------------------------------------------------------- #

# La chaine ratifiee : Prompt utilisateur + Mandatory Read + Memoire + Lessons
# + Exigences cognitives + Reasoning effort + Permissions + Plugins + Skills +
# Delegation = Prompt envoye. Pour chaque maillon : le champ de contrat qui le
# DECLARE (None si aucun des 17 champs canoniques ne le porte — verifie contre
# `contract.py::_render_prompt`, voir docstring de module) et le motif d'
# en-tete qui permet de l'OBSERVER dans le texte reellement recu (reutilise
# `observer.prompt._find_section` sur les `sections` deja decoupees par
# `collect_prompts` — aucune resegmentation ici).
_TACHE_RE = re.compile(r"T.CHE CONCR.TE", re.IGNORECASE)
_PREMORTEM_RE = re.compile(r"PR.-MORTEM", re.IGNORECASE)
_EXIGENCES_RE = re.compile(r"EXIGENCES COGNITIVES", re.IGNORECASE)
_REASONING_RE = re.compile(r"RAISONNEMENT|REASONING", re.IGNORECASE)
_PERMISSIONS_RE = re.compile(r"PERMISSIONS", re.IGNORECASE)
_PLUGIN_RE = re.compile(r"\bPLUGINS?\b", re.IGNORECASE)
_SKILL_RE = re.compile(r"\bSKILLS?\b", re.IGNORECASE)
_DELEGATION_RE = re.compile(r"D.L.GATION|PARENT.AGENT", re.IGNORECASE)

MAILLONS: tuple[tuple[str, str, Optional[str], re.Pattern[str]], ...] = (
    ("prompt_utilisateur", "Prompt utilisateur (tache concrete)", None, _TACHE_RE),
    ("mandatory_read", "Mandatory Read", "mandatory_read", _LIRE_RE),
    ("memoire", "Memoire", "memoire", _MEMOIRE_RE),
    ("lessons", "Lessons (pre-mortem)", None, _PREMORTEM_RE),
    ("exigences_cognitives", "Exigences cognitives", "exigences_cognitives", _EXIGENCES_RE),
    ("reasoning_effort", "Reasoning effort", None, _REASONING_RE),
    ("permissions", "Permissions", "permissions", _PERMISSIONS_RE),
    ("plugins", "Plugins", "plugin", _PLUGIN_RE),
    ("skills", "Skills", "skill", _SKILL_RE),
    ("delegation", "Delegation", "delegation_context", _DELEGATION_RE),
)

_NO_FIELD_WHY = (
    "aucun des 17 champs canoniques du contrat (SCHEMA.md) ne porte ce nom, "
    "et scripts/forge/contract.py::_render_prompt ne rend aucune section de ce "
    "type — si ce maillon apparait quand meme dans le texte recu, il vient "
    "d'une couche d'assemblage en aval du contrat (le driver de run)"
)


def _statut_maillon(declare: bool, observe: bool) -> str:
    if declare and observe:
        return "DECLARE_ET_INJECTE"
    if declare and not observe:
        return "DECLARE_NON_RETROUVE"
    if observe:
        return "INJECTE_NON_DECLARE"
    return "ABSENT_DES_DEUX"


# --------------------------------------------------------------------------- #
# Consommation par maillon — la dimension manquante de la chaine
# Declare -> Rendu prompt -> Recu agent -> OBSERVE EXECUTION.
#
# `statut` (ci-dessus) repond « le champ est-il dans le prompt ? ».
# `consommation` repond « l'agent a-t-il UTILISE ce qui etait injecte ? »,
# mesuree MECANIQUEMENT depuis les events (file.read / tool.call), match par
# run_id + etape (les events ne portent pas l'attempt : tous les attempts
# d'une meme etape partagent la mesure — dit dans le `why`).
#
# Taxonomie finale ratifiee (statut_v2), EXACTE :
#   PRESENT_AND_USED      declare + injecte + consommation prouvee (>=1 trace)
#                          OU sans objet-mais-injecte
#   DECLARED_NOT_INJECTED  declare, jamais retrouve dans le texte recu
#   INJECTED_NOT_DECLARED  dans le texte recu, porte par aucun champ du contrat
#   UNKNOWN                injecte mais consommation non mesurable (prompt lu en
#                          bloc), OU mesurable-mais-zero-trace (NON_OBSERVEE :
#                          la taxonomie n'a pas de case « injecte non consomme »,
#                          le detail vit dans `consommation`), OU absent des deux.
# --------------------------------------------------------------------------- #

CONSO_PROUVEE = "PROUVEE"
CONSO_PARTIELLE = "PARTIELLE"
CONSO_NON_OBSERVEE = "NON_OBSERVEE"
CONSO_UNKNOWN = "UNKNOWN"
CONSO_SANS_OBJET = "SANS_OBJET"

STATUTS_V2: tuple[str, ...] = (
    "PRESENT_AND_USED", "DECLARED_NOT_INJECTED", "INJECTED_NOT_DECLARED", "UNKNOWN",
)

# Chemin de fichier dans une entree mandatory_read : `scripts/forge/.../X.md`
# ou entre parentheses dans une entree en prose (« la wiremap gelee du jeu
# courant (lab/forge_runs/<jeu>/wiremap.json) »). Les placeholders <jeu>/<game>/
# <projet> sont substitues par le projet observe.
_PATH_TOKEN_RE = re.compile(r"[A-Za-z0-9_<>\-]+(?:/[A-Za-z0-9_<>\-.]+)+\.[A-Za-z0-9]+")

# Maillons rendus en prose dans le prompt : lus en bloc par l'agent, aucun
# evenement dedie n'existe pour prouver ou infirmer leur consommation.
_MAILLONS_PROSE = frozenset({"prompt_utilisateur", "memoire", "lessons", "exigences_cognitives"})

# Maillons que `contract.py::_render_prompt` ne rend JAMAIS en section (verifie,
# cf. docstring de module) : rien n'est injecte, la consommation est sans objet.
_MAILLONS_JAMAIS_INJECTES = frozenset({"reasoning_effort", "plugins", "skills", "delegation"})

_WHY_PROSE = (
    "le prompt est lu en bloc par l'agent — aucun evenement dedie ne prouve ni "
    "n'infirme la consommation de cette section ; non mesurable mecaniquement"
)


def _ev_src(e: dict[str, Any]) -> dict[str, Any]:
    s = e.get("source", {}) or {}
    src: dict[str, Any] = {"path": s.get("path", "")}
    if s.get("line") is not None:
        src["line"] = s["line"]
    return src


def _norm_repo_path(repo_root: Path, raw: Any) -> Optional[str]:
    """Chemin normalise (minuscule, /, relatif au repo si possible) pour
    comparer `payload.path` (absolu Windows) aux entrees de contrat (relatives
    POSIX). Recalcule localement — Observer ne depend d'aucun autre module."""
    if not raw:
        return None
    p = str(raw).replace("\\", "/")
    root = str(repo_root).replace("\\", "/").rstrip("/")
    if p.lower().startswith(root.lower() + "/"):
        p = p[len(root) + 1:]
    p = p.strip("/").lower()
    return p or None


def _mandatory_read_targets(
    contract: dict[str, Any], project: str
) -> tuple[list[dict[str, Any]], list[str]]:
    """Entrees mandatory_read du CONTRAT resolues en chemins comparables.
    Retourne (resolues [{entree, chemins}], non_resolues [entrees sans chemin
    extractible]) — une entree est LUE si AU MOINS UN de ses chemins matche."""
    raw = contract.get("mandatory_read")
    if isinstance(raw, str):
        entries = [raw]
    elif isinstance(raw, (list, tuple)):
        entries = [str(e) for e in raw if e]
    else:
        entries = []
    resolues: list[dict[str, Any]] = []
    non_resolues: list[str] = []
    for entry in entries:
        chemins: list[str] = []
        for tok in _PATH_TOKEN_RE.findall(entry):
            tok = (tok.replace("<jeu>", project)
                       .replace("<game>", project)
                       .replace("<projet>", project))
            if "<" in tok:  # placeholder non substituable -> incomparable
                continue
            chemins.append(tok.strip("/").lower())
        if chemins:
            resolues.append({"entree": entry, "chemins": chemins})
        else:
            non_resolues.append(entry)
    return resolues, non_resolues


def _activation_reads(
    events: list[dict[str, Any]], run_id: Optional[str], etape: str, repo_root: Path
) -> tuple[set[str], Optional[dict[str, Any]]]:
    """Chemins normalises des file.read de la meme activation (run_id+etape)."""
    paths: set[str] = set()
    src: Optional[dict[str, Any]] = None
    for e in events:
        if e.get("kind") != "file.read" or e.get("run_id") != run_id or e.get("etape") != etape:
            continue
        norm = _norm_repo_path(repo_root, (e.get("payload") or {}).get("path"))
        if norm:
            paths.add(norm)
            if src is None:
                src = _ev_src(e)
    return paths, src


def _read_match(chemin: str, reads: set[str]) -> bool:
    """Match exact ou par suffixe (les reads peuvent viser une copie worktree)."""
    if chemin in reads:
        return True
    suffix = "/" + chemin
    return any(r.endswith(suffix) for r in reads)


def _conso_mandatory_read(
    contract: dict[str, Any], project: str,
    reads: set[str], reads_src: Optional[dict[str, Any]],
) -> dict[str, Any]:
    resolues, non_resolues = _mandatory_read_targets(contract, project)
    if not resolues:
        return {
            "v": CONSO_UNKNOWN,
            "why": "aucune entree mandatory_read resolvable en chemin de fichier"
                   if non_resolues else "champ mandatory_read absent du contrat — rien a consommer",
        }
    lus = [r["entree"] for r in resolues if any(_read_match(c, reads) for c in r["chemins"])]
    non_lus = [r["entree"] for r in resolues if r["entree"] not in lus]
    if lus and not non_lus:
        etat = CONSO_PROUVEE
    elif lus:
        etat = CONSO_PARTIELLE
    else:
        etat = CONSO_NON_OBSERVEE
    out: dict[str, Any] = {
        "v": {
            "etat": etat,
            "lus": len(lus),
            "declares": len(resolues),
            "ratio": f"{len(lus)}/{len(resolues)}",
            "fichiers_lus": lus,
            "fichiers_non_lus": non_lus,
            "entrees_non_resolues": non_resolues,
        },
        "why": "entrees du champ mandatory_read du CONTRAT confrontees aux events "
               "file.read de la meme activation (match run_id+etape, tous attempts "
               "confondus ; match de chemin exact ou par suffixe)",
    }
    if reads_src:
        out["src"] = reads_src
    return out


def _activation_tools(
    events: list[dict[str, Any]], run_id: Optional[str], etape: str
) -> tuple[Counter[str], Optional[list[str]], Optional[dict[str, Any]]]:
    """tool.call observes + outils charges (dispatch.tools payload.loaded.tools)
    de la meme activation. Recalcule localement, ne depend d'aucun autre module."""
    appels: Counter[str] = Counter()
    src: Optional[dict[str, Any]] = None
    charges: Optional[list[str]] = None
    for e in events:
        if e.get("run_id") != run_id or e.get("etape") != etape:
            continue
        kind = e.get("kind")
        if kind == "tool.call":
            name = (e.get("payload") or {}).get("tool_name")
            if name:
                appels[str(name)] += 1
                if src is None:
                    src = _ev_src(e)
        elif kind == "dispatch.tools" and charges is None:
            loaded = ((e.get("payload") or {}).get("loaded") or {}).get("tools")
            if isinstance(loaded, list):
                charges = [str(t) for t in loaded]
    return appels, charges, src


def _conso_permissions(
    appels: Counter[str], charges: Optional[list[str]], src: Optional[dict[str, Any]]
) -> dict[str, Any]:
    v: dict[str, Any] = {
        "etat": CONSO_PROUVEE if appels else CONSO_NON_OBSERVEE,
        "appels": sum(appels.values()),
        "outils_appeles": dict(appels.most_common()),
    }
    if charges is not None:
        v["outils_charges"] = charges
        bases = {t.split("(", 1)[0] for t in charges}
        v["appels_hors_charge"] = sorted(n for n in appels if n not in bases)
    out: dict[str, Any] = {
        "v": v,
        "why": "outils du contrat (permissions/dispatch.tools) confrontes aux events "
               "tool.call de la meme activation (match run_id+etape, tous attempts "
               "confondus)",
    }
    if src:
        out["src"] = src
    return out


def _consommation_maillon(
    key: str, observe: bool, contract: dict[str, Any], project: str,
    reads: set[str], reads_src: Optional[dict[str, Any]],
    appels: Counter[str], charges: Optional[list[str]], tools_src: Optional[dict[str, Any]],
) -> dict[str, Any]:
    if key == "mandatory_read":
        return _conso_mandatory_read(contract, project, reads, reads_src)
    if key == "permissions":
        return _conso_permissions(appels, charges, tools_src)
    if key in _MAILLONS_PROSE:
        if observe:
            return {"v": CONSO_UNKNOWN, "why": _WHY_PROSE}
        return {"v": CONSO_SANS_OBJET, "why": "section absente du texte recu — rien a consommer"}
    if key in _MAILLONS_JAMAIS_INJECTES:
        if observe:
            # cas theorique (une couche aval l'aurait injecte) : lu en bloc
            return {"v": CONSO_UNKNOWN, "why": _WHY_PROSE}
        return {
            "v": CONSO_SANS_OBJET,
            "why": "jamais rendu en section par contract.py::_render_prompt — rien "
                   "n'est injecte, consommation sans objet",
        }
    return {"v": CONSO_UNKNOWN, "why": "maillon sans regle de mesure de consommation"}


def _statut_v2(declare: bool, observe: bool, conso_v: Any) -> str:
    """Taxonomie finale EXACTE (ratifiee). `conso_v` = valeur `v` de la cellule
    consommation (str d'etat, ou dict {etat: ...} pour les mesures riches)."""
    if declare and not observe:
        return "DECLARED_NOT_INJECTED"
    if not declare and observe:
        return "INJECTED_NOT_DECLARED"
    if not declare and not observe:
        return "UNKNOWN"
    etat = conso_v.get("etat") if isinstance(conso_v, dict) else conso_v
    if etat in (CONSO_PROUVEE, CONSO_PARTIELLE, CONSO_SANS_OBJET):
        return "PRESENT_AND_USED"
    return "UNKNOWN"


# --------------------------------------------------------------------------- #
# Matrice ELEMENT (Declare / Injecte / Consomme / Prouve) — taxonomie V2
# ratifiee de la MATRICE (distincte de `statut_v2`, qui est conserve tel quel) :
#
#   COMPLETE                declare + injecte + consommation prouvee (>=1 trace).
#   DECLARED_NOT_INJECTED   declare, absent du prompt — la declaration PRIME :
#                           c'est le drift « contrat sans effet reel » que la
#                           matrice existe pour exposer (corrige 2026-08-02, la
#                           branche sans-objet->COMPLETE masquait delegation).
#                           RESERVE (amendement layer, meme date) aux vrais
#                           champs de couche `prompt` manquants — skill/plugin/
#                           delegation_context ont leur propre statut, ci-dessous.
#   CONFORME_DISPATCH       maillons `skills`/`plugins` (couche `dispatch`,
#                           SCHEMA.md) declares mais jamais rendus en section :
#                           NORMAL, pas un drift — leur canal de preuve est
#                           allowed_tools/l'audit outillage, jamais le texte du
#                           prompt (contract.py::_declared_tools). Statut FERME
#                           ajoute par l'amendement layer, ratifie Pierre
#                           2026-08-02 : « un champ sans consommateur declare ne
#                           doit pas etre presente comme une capacite injectee ».
#   CONFORME_DOCUMENTAIRE   maillon `delegation` (couche `documentation`,
#                           SCHEMA.md : delegation_context/parent_agent) declare
#                           mais jamais rendu en section : NORMAL — tracabilite
#                           humaine sans consommateur d'execution, hors matrice
#                           d'execution par construction. Meme amendement.
#   INJECTED_NOT_CONSUMED   injecte, consommation MESURABLE et mesuree a zero
#                           (etat NON_OBSERVEE) — l'ecart le plus actionnable.
#                           La case que `statut_v2` pliait dans UNKNOWN.
#   UNKNOWN                 consommation non mesurable (prompt lu en bloc), ou
#                           element hors des cases ci-dessus.
#
# Granularite mandatory_read (decision de fabrication) : le maillon entier est
# COMPLETE des qu'AU MOINS UNE entree est prouvee lue (etat PARTIELLE), MAIS
# l'element expose alors `elements_non_consommes` (les entrees jamais lues) ;
# un maillon avec 0/n entrees lues = INJECTED_NOT_CONSUMED.
#
# `prouve` = la verification LA PLUS FORTE disponible, niveau nomme :
#   execution.file.read / execution.tool.call  (events de la meme activation)
#   > attestation.dispatch / attestation.documentation (couches `dispatch`/
#                                               `documentation`, SCHEMA.md — COURT-
#                                               CIRCUITE le SHA pour skill/plugin/
#                                               delegation_context : leur canal de
#                                               preuve n'est structurellement JAMAIS
#                                               le texte du prompt, un SHA n'y
#                                               constaterait qu'une absence normale,
#                                               pas un manque de preuve — cf. CONFORME_*)
#   > prompt.sha256_normalized                 (SHA du texte reellement recu —
#                                               champs de couche `prompt` uniquement)
#   > attestation.contrat                      (le contrat declare — attestation
#                                               manifeste, pas une preuve d'execution)
# --------------------------------------------------------------------------- #

STATUTS_MATRICE: tuple[str, ...] = (
    "COMPLETE", "DECLARED_NOT_INJECTED", "INJECTED_NOT_CONSUMED",
    "CONFORME_DISPATCH", "CONFORME_DOCUMENTAIRE", "UNKNOWN",
)

# Maillons de couche non-`prompt` (SCHEMA.md, "Amendement layer" ratifie Pierre
# 2026-08-02) : cles de `MAILLONS` ci-dessus, PAS noms de champ de contrat (le
# maillon `plugins` porte le champ `plugin`, `skills` porte `skill`, `delegation`
# porte `delegation_context`). Distinct de `_MAILLONS_JAMAIS_INJECTES` (ci-dessus,
# utilise par `_consommation_maillon`/`statut_v2` — INCHANGE par cet amendement) :
# ici on classe le STATUT MATRICE d'un maillon declare-mais-non-injecte, pas sa
# consommation.
_MAILLONS_LAYER_DISPATCH = frozenset({"plugins", "skills"})
_MAILLONS_LAYER_DOCUMENTATION = frozenset({"delegation"})

PREUVE_EXECUTION_READ = "execution.file.read"
PREUVE_EXECUTION_TOOL = "execution.tool.call"
PREUVE_SHA_PROMPT = "prompt.sha256_normalized"
PREUVE_ATTESTATION = "attestation.contrat"
PREUVE_ATTESTATION_DISPATCH = "attestation.dispatch"
PREUVE_ATTESTATION_DOCUMENTATION = "attestation.documentation"


def _conso_etat(conso: dict[str, Any]) -> Any:
    v = conso.get("v")
    return v.get("etat") if isinstance(v, dict) else v


def _statut_matrice(key: str, declare: bool, observe: bool, etat: Any, sha_disponible: bool) -> str:
    """Taxonomie V2 de la MATRICE (voir bloc de commentaire ci-dessus).
    Un element injecte SANS declaration ne peut pas etre COMPLETE (la
    definition exige les trois : declare + injecte + consomme) — la dimension
    declaration manquante reste visible dans `declare`/`statut_v2`.

    `key` (la cle du maillon, ex. "skills"/"plugins"/"delegation") route vers
    les statuts FERMES de couche non-prompt (amendement layer, SCHEMA.md,
    ratifie Pierre 2026-08-02) AVANT la branche generique DECLARED_NOT_INJECTED."""
    if observe:
        if etat in (CONSO_PROUVEE, CONSO_PARTIELLE):
            return "COMPLETE" if declare else "UNKNOWN"
        if etat == CONSO_NON_OBSERVEE:
            return "INJECTED_NOT_CONSUMED"
        return "UNKNOWN"  # consommation non mesurable (prompt lu en bloc)
    # non injecte — couche non-prompt EN PREMIER (SCHEMA.md, amendement layer) :
    # pour skill/plugin/delegation_context, le texte du prompt n'est structurel-
    # lement PAS le canal de preuve — ne pas y apparaitre est la NORME de la
    # couche, pas un drift. DECLARED_NOT_INJECTED reste reserve aux vrais champs
    # de couche `prompt` (SCHEMA.md::LAYER_PROMPT, contract.py) jamais rendus.
    if declare and key in _MAILLONS_LAYER_DISPATCH:
        return "CONFORME_DISPATCH"
    if declare and key in _MAILLONS_LAYER_DOCUMENTATION:
        return "CONFORME_DOCUMENTAIRE"
    # sinon — la DECLARATION prime : un champ declare avec contenu et jamais
    # rendu dans le prompt est exactement le drift « contrat sans effet reel »
    # que cette matrice existe pour exposer. L'ancienne branche (SANS_OBJET +
    # SHA -> COMPLETE) masquait ce drift : le SHA prouve que le PROMPT a ete
    # livre, pas que l'ELEMENT y a ete rendu. Corrige 2026-08-02 apres
    # verification orchestrateur (delegation_context, contenu reel jamais
    # rendu, ressortait COMPLETE — contradiction directe avec recap_v2 x30).
    # Limite connue, partagee avec recap_v2 : `declare` mesure la PRESENCE du
    # champ ; un champ rempli de « aucun » (declare-vide) compte comme declare.
    if declare:
        return "DECLARED_NOT_INJECTED"
    return "UNKNOWN"


def _prouve_cell(
    key: str, declare: bool, observe: bool,
    conso: dict[str, Any], entry: dict[str, Any],
    declare_src: Optional[dict[str, Any]],
) -> dict[str, Any]:
    """La verification LA PLUS FORTE disponible pour cet element, niveau nomme."""
    etat = _conso_etat(conso)
    v_conso = conso.get("v")
    # Niveau 1 — preuve d'execution (events file.read / tool.call de la meme activation)
    if etat in (CONSO_PROUVEE, CONSO_PARTIELLE):
        v: dict[str, Any]
        if key == "mandatory_read":
            v = {"niveau": PREUVE_EXECUTION_READ}
            if isinstance(v_conso, dict) and v_conso.get("ratio"):
                v["ratio"] = v_conso["ratio"]
        else:
            v = {"niveau": PREUVE_EXECUTION_TOOL}
            if isinstance(v_conso, dict) and v_conso.get("appels") is not None:
                v["appels"] = v_conso["appels"]
        out: dict[str, Any] = {
            "v": v,
            "why": "niveau le plus fort : evenements d'execution de la meme activation "
                   "(match run_id+etape)",
        }
        if conso.get("src"):
            out["src"] = conso["src"]
        return out
    # Niveau 2 — couches non-prompt (SCHEMA.md, amendement layer ratifie Pierre
    # 2026-08-02) : COURT-CIRCUITE le SHA. Un SHA du prompt reellement recu ne
    # prouverait ici que l'ABSENCE normale de la section — jamais le canal reel
    # de skill/plugin (dispatch) ou delegation_context (documentation). Nommer
    # directement le bon canal plutot que se rabattre sur une preuve qui ne
    # porte pas sur la couche consommee.
    if declare and not observe and key in _MAILLONS_LAYER_DISPATCH:
        out = {
            "v": {"niveau": PREUVE_ATTESTATION_DISPATCH},
            "why": "couche dispatch (SCHEMA.md) : la preuve reelle est allowed_tools / "
                   "l'audit outillage (contract.py::_declared_tools), jamais le texte du "
                   "prompt. NOTE HONNETE : consommateur faible mesure -- la plupart des "
                   "contrats declarent skill/plugin a 'aucun', l'audit outillage signe "
                   "alors souvent allowed_tools=() ; sous-declaration connue, non "
                   "blanchie ici.",
        }
        if declare_src:
            out["src"] = declare_src
        return out
    if declare and not observe and key in _MAILLONS_LAYER_DOCUMENTATION:
        out = {
            "v": {"niveau": PREUVE_ATTESTATION_DOCUMENTATION},
            "why": "couche documentation (SCHEMA.md) : tracabilite humaine (qui a "
                   "mandate l'agent, pourquoi) -- aucun consommateur d'execution, hors "
                   "matrice d'execution par construction.",
        }
        if declare_src:
            out["src"] = declare_src
        return out
    # Niveau 3 — SHA du prompt normalise reellement recu
    sha = entry.get("sha256_normalized")
    if sha:
        s = entry.get("source", {}) or {}
        src: dict[str, Any] = {"path": s.get("path", "")}
        if s.get("line") is not None:
            src["line"] = s["line"]
        return {
            "v": {
                "niveau": PREUVE_SHA_PROMPT,
                "sha256": sha,
                "verification": entry.get("verification"),
                "porte_sur": ("presence de la section dans le prompt recu" if observe
                              else "absence de la section dans le prompt recu"),
            },
            "src": src,
            "why": "aucune preuve d'execution pour cet element — la plus forte "
                   "disponible est le SHA du texte reellement recu par l'agent",
        }
    # Niveau 4 — attestation manifeste (le contrat declare, rien de plus fort)
    if declare and declare_src:
        return {
            "v": {"niveau": PREUVE_ATTESTATION},
            "src": declare_src,
            "why": "ni preuve d'execution ni SHA de prompt disponible — seule reste "
                   "la declaration du contrat (attestation manifeste, pas une preuve "
                   "d'execution)",
        }
    return _cell(
        NOT_OBSERVABLE, None,
        "aucune preuve disponible a aucun niveau (execution, SHA prompt, contrat)",
    )


def _element_matrice(
    key: str, label: str,
    declare: bool, declare_src: Optional[dict[str, Any]], declare_why: Optional[str],
    observe: bool, observe_src: Optional[dict[str, Any]],
    conso: dict[str, Any], entry: dict[str, Any],
) -> dict[str, Any]:
    """Une ligne ELEMENT de la matrice Declare/Injecte/Consomme/Prouve."""
    sha_disponible = bool(entry.get("sha256_normalized"))
    etat = _conso_etat(conso)

    declare_cell: dict[str, Any] = {"v": declare}
    if declare_src:
        declare_cell["src"] = declare_src
    elif declare_why:
        declare_cell["why"] = declare_why

    injecte_cell: dict[str, Any] = {"v": observe}
    if observe and observe_src:
        injecte_cell["src"] = observe_src
    elif not observe:
        injecte_cell["why"] = (
            "section jamais retrouvee dans le texte recu (verifie sur le prompt "
            "SHA-verifie)" if sha_disponible else "section absente du texte recu"
        )

    element: dict[str, Any] = {
        "element": key,
        "label": label,
        "declare": declare_cell,
        "injecte": injecte_cell,
        "consomme": conso,
        "prouve": _prouve_cell(key, declare, observe, conso, entry, declare_src),
        "statut": _statut_matrice(key, declare, observe, etat, sha_disponible),
    }
    # Granularite mandatory_read : maillon COMPLETE des qu'>=1 entree prouvee lue,
    # mais les entrees jamais lues restent exposees ici (l'ecart actionnable).
    if key == "mandatory_read" and isinstance(conso.get("v"), dict):
        non_lus = list(conso["v"].get("fichiers_non_lus") or [])
        element["elements_non_consommes"] = non_lus
        element["nb_elements_non_consommes"] = len(non_lus)
    return element


def _load_contract_cached(
    ctx: ObserverContext, contracts_dir: Path, stem: str, cache: dict[str, Optional[dict[str, Any]]]
) -> Optional[dict[str, Any]]:
    if stem in cache:
        return cache[stem]
    path = contracts_dir / f"{stem}.yaml"
    text = ctx.read_text(path)
    if text is None:
        cache[stem] = None
        return None
    try:
        data = yaml.safe_load(text)
    except yaml.YAMLError as exc:
        LOG.warning("contrat illisible %s: %s", ctx.rel(path), exc)
        cache[stem] = None
        return None
    cache[stem] = data if isinstance(data, dict) else None
    return cache[stem]


def view_injection(
    ctx: ObserverContext,
    result: dict[str, Any],
    events: list[dict[str, Any]],
    prompts: list[dict[str, Any]],
) -> dict[str, Any]:
    """DECLARE (le contrat porte-t-il le champ) x OBSERVE (la section
    correspondante existe-t-elle dans le texte reellement recu) x CONSOMME
    (l'agent a-t-il utilise ce qui etait injecte — mesure depuis `events`),
    maillon par maillon, pour chaque activation reelle de `collect_prompts`."""
    del result  # la vue consomme les activations de prompt + les events

    contracts_dir = _contracts_dir(ctx)
    contract_cache: dict[str, Optional[dict[str, Any]]] = {}
    # caches par activation (run_id, etape) — les events ne portent pas l'attempt
    reads_cache: dict[tuple[Optional[str], str], tuple[set[str], Optional[dict[str, Any]]]] = {}
    tools_cache: dict[
        tuple[Optional[str], str],
        tuple[Counter[str], Optional[list[str]], Optional[dict[str, Any]]],
    ] = {}

    activations: list[dict[str, Any]] = []
    for entry in sorted(
        prompts,
        key=lambda e: (e.get("run_id") or "", e.get("etape") or "",
                        e.get("attempt") if e.get("attempt") is not None else -1),
    ):
        stem = entry.get("etape") or ""
        contract = _load_contract_cached(ctx, contracts_dir, stem, contract_cache) or {}
        contract_path_str = ctx.rel(contracts_dir / f"{stem}.yaml")
        sections = entry.get("sections") or []

        act_key = (entry.get("run_id"), stem)
        if act_key not in reads_cache:
            reads_cache[act_key] = _activation_reads(events, act_key[0], stem, ctx.repo_root)
        if act_key not in tools_cache:
            tools_cache[act_key] = _activation_tools(events, act_key[0], stem)
        reads, reads_src = reads_cache[act_key]
        appels, charges, tools_src = tools_cache[act_key]

        maillons_out: list[dict[str, Any]] = []
        matrice_out: list[dict[str, Any]] = []
        for key, label, field, pattern in MAILLONS:
            if field == "delegation_context":
                value, used_field = _delegation_value_and_field(contract)
                declare = _field_declared(value)
                declare_src = {"path": contract_path_str, "field": used_field} if declare else None
                declare_why = None if declare else "champ absent du contrat (ni delegation_context ni parent_agent)"
            elif field is not None:
                value = contract.get(field)
                declare = _field_declared(value)
                declare_src = {"path": contract_path_str, "field": field} if declare else None
                declare_why = None if declare else "champ absent du contrat"
            else:
                declare = False
                declare_src = None
                declare_why = _NO_FIELD_WHY

            section = _find_section(sections, pattern)
            observe = section is not None
            observe_src = None
            if observe:
                s = entry.get("source", {}) or {}
                observe_src = {
                    "path": s.get("path", ""),
                    "field": section["nom"] if section else None,
                }
                if s.get("line") is not None:
                    observe_src["line"] = s["line"]

            consommation = _consommation_maillon(
                key, observe, contract, ctx.project,
                reads, reads_src, appels, charges, tools_src,
            )

            maillon: dict[str, Any] = {
                "cle": key,
                "label": label,
                "declare": declare,
                "observe": observe,
                "statut": _statut_maillon(declare, observe),
            }
            if declare_src:
                maillon["declare_src"] = declare_src
            if not declare and declare_why:
                maillon["declare_why"] = declare_why
            if observe:
                maillon["observe_section"] = section["nom"] if section else None
                maillon["observe_src"] = observe_src
            # champs AJOUTES (compat console : les cles historiques ci-dessus
            # gardent leur forme, `statut` reste l'ancienne taxonomie)
            maillon["statut_v2"] = _statut_v2(declare, observe, consommation["v"])
            maillon["consommation"] = consommation
            maillons_out.append(maillon)

            matrice_out.append(_element_matrice(
                key, label,
                declare, declare_src, declare_why,
                observe, observe_src,
                consommation, entry,
            ))

        activations.append({
            "run_id": entry.get("run_id"),
            "etape": entry.get("etape"),
            "attempt": entry.get("attempt"),
            "source": entry.get("source"),
            "maillons": maillons_out,
            "matrice": matrice_out,
            "prompt_envoye": _cell(
                {
                    "chars": entry.get("chars_normalized"),
                    "verification": entry.get("verification"),
                    "sha256_normalized": entry.get("sha256_normalized"),
                },
                {
                    "path": (entry.get("source") or {}).get("path", ""),
                    "line": (entry.get("source") or {}).get("line"),
                },
            ),
        })

    if not activations:
        return {
            "lignes": [],
            "v": NOT_OBSERVABLE,
            "why": "aucune activation de prompt trouvee (collect_prompts n'a rien retourne pour ce projet)",
        }

    # recap_v2 — compte par statut_v2 sur tous les maillons de toutes les
    # activations + liste des champs DECLARED_NOT_INJECTED (champ AJOUTE).
    par_statut: Counter[str] = Counter()
    dni: dict[str, dict[str, Any]] = {}
    for act in activations:
        for m in act["maillons"]:
            par_statut[m["statut_v2"]] += 1
            if m["statut_v2"] == "DECLARED_NOT_INJECTED":
                rec = dni.setdefault(m["cle"], {"cle": m["cle"], "label": m["label"], "activations": 0})
                rec["activations"] += 1

    # recap_matrice — compte par statut MATRICE (taxonomie V2 ELEMENT, distincte
    # de statut_v2/recap_v2 ci-dessus) sur tous les ELEMENTs de toutes les
    # activations + liste des INJECTED_NOT_CONSUMED (champ AJOUTE, aucune cle
    # existante touchee).
    par_statut_matrice: Counter[str] = Counter()
    inc: dict[str, dict[str, Any]] = {}
    for act in activations:
        for el in act["matrice"]:
            par_statut_matrice[el["statut"]] += 1
            if el["statut"] == "INJECTED_NOT_CONSUMED":
                rec = inc.setdefault(
                    el["element"], {"cle": el["element"], "label": el["label"], "activations": 0}
                )
                rec["activations"] += 1

    return {
        "chaine": "Prompt utilisateur + Mandatory Read + Memoire + Lessons + Exigences cognitives "
                  "+ Reasoning effort + Permissions + Plugins + Skills + Delegation = Prompt envoye",
        "statuts": ("DECLARE_ET_INJECTE", "DECLARE_NON_RETROUVE", "INJECTE_NON_DECLARE", "ABSENT_DES_DEUX"),
        "lignes": activations,
        "statuts_v2": STATUTS_V2,
        "recap_v2": {
            "par_statut": {s: par_statut.get(s, 0) for s in STATUTS_V2},
            "champs_declared_not_injected": sorted(dni.values(), key=lambda r: r["cle"]),
            "regle": "statut_v2 = chaine Declare -> Rendu prompt -> Recu agent -> Observe execution. "
                     "PRESENT_AND_USED exige une preuve de consommation (file.read/tool.call de la "
                     "meme activation) ou une consommation sans objet ; UNKNOWN couvre l'injecte "
                     "non mesurable (prompt lu en bloc), le mesurable-sans-trace (etat NON_OBSERVEE "
                     "dans `consommation`) et l'absent des deux. Les anciens statuts (`statut`) sont "
                     "conserves inchanges.",
        },
        "statuts_matrice": STATUTS_MATRICE,
        "recap_matrice": {
            "par_statut": {s: par_statut_matrice.get(s, 0) for s in STATUTS_MATRICE},
            "elements_injected_not_consumed": sorted(inc.values(), key=lambda r: r["cle"]),
            "regle": "matrice ELEMENT (Declare/Injecte/Consomme/Prouve) par activation, taxonomie V2 "
                     "ratifiee : COMPLETE (declare+injecte+consommation prouvee) / "
                     "DECLARED_NOT_INJECTED (declare, jamais rendu dans le prompt — le drift "
                     "« contrat sans effet reel », RESERVE aux vrais champs de couche `prompt` "
                     "manquants depuis l'amendement layer du 2026-08-02, SCHEMA.md) / "
                     "CONFORME_DISPATCH (maillons skills/plugins, couche `dispatch` : jamais rendus "
                     "en section = NORMAL, leur preuve vit dans allowed_tools/l'audit outillage, pas "
                     "le prompt) / CONFORME_DOCUMENTAIRE (maillon delegation, couche `documentation` : "
                     "jamais rendu en section = NORMAL, tracabilite humaine sans consommateur "
                     "d'execution) / INJECTED_NOT_CONSUMED (consommation "
                     "MESURABLE mesuree a zero — l'ecart le plus actionnable, que statut_v2/recap_v2 "
                     "pliaient dans UNKNOWN) / UNKNOWN (consommation non mesurable, prompt lu en bloc). "
                     "Granularite mandatory_read : un maillon avec >=1 entree prouvee lue est COMPLETE "
                     "mais expose `elements_non_consommes` (les entrees jamais lues) sur son ELEMENT. "
                     "RIEN d'existant supprime : statuts historiques et statut_v2/recap_v2 conserves "
                     "inchanges, CONFORME_DISPATCH/CONFORME_DOCUMENTAIRE sont des cles additives.",
        },
    }


# --------------------------------------------------------------------------- #
# s4_prompt — le texte reel, reorganise par activation
# --------------------------------------------------------------------------- #


def view_prompt(
    ctx: ObserverContext,
    result: dict[str, Any],
    events: list[dict[str, Any]],
    prompts: list[dict[str, Any]],
) -> dict[str, Any]:
    """Reorganisation lisible des activations deja extraites par
    `collect_prompts` : en-tete, sequence des sections REELLES dans l'ordre
    du texte (avec leur texte complet, pas seulement l'extrait de 300
    caracteres), texte integral en dernier recours."""
    del result, events  # cette vue ne fait que reorganiser `prompts` (+ ctx.project)

    if not prompts:
        return {
            "activations": [],
            "v": NOT_OBSERVABLE,
            "why": "aucune activation de prompt trouvee (collect_prompts n'a rien retourne pour ce projet)",
        }

    activations: list[dict[str, Any]] = []
    for entry in sorted(
        prompts,
        key=lambda e: (e.get("run_id") or "", e.get("etape") or "",
                        e.get("attempt") if e.get("attempt") is not None else -1),
    ):
        texte = entry.get("texte") or ""
        sections_out: list[dict[str, Any]] = []
        for section in entry.get("sections") or []:
            debut = section.get("debut", 0)
            longueur = section.get("longueur", 0)
            sections_out.append({
                "nom": section.get("nom"),
                "longueur": longueur,
                "extrait": section.get("extrait"),
                "texte_complet": texte[debut: debut + longueur],
            })

        run_id = entry.get("run_id") or ""
        etape = entry.get("etape") or ""
        activations.append({
            "agent_humain": human_name_session(ctx.project, etape, run_id),
            "run_id": run_id,
            "etape": etape,
            "attempt": entry.get("attempt"),
            "verification": entry.get("verification"),
            "sha256_normalized": entry.get("sha256_normalized"),
            "chars_normalized": entry.get("chars_normalized"),
            "sections": sections_out,
            "texte_integral": texte,
            "source": entry.get("source"),
            "note": entry.get("note"),
        })

    return {"activations": activations}


# --------------------------------------------------------------------------- #
# Assemblage
# --------------------------------------------------------------------------- #


def build_agent_views(
    ctx: ObserverContext,
    result: dict[str, Any],
    events: list[dict[str, Any]],
    prompts: list[dict[str, Any]],
) -> dict[str, Any]:
    return {
        "s3_agents": view_agents(ctx, result, events),
        "s4_prompt": view_prompt(ctx, result, events, prompts),
        "s6_injection": view_injection(ctx, result, events, prompts),
    }


# --------------------------------------------------------------------------- #
# Preuve d'execution
# --------------------------------------------------------------------------- #


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Vues SYSTEME (AGENTS/INJECTION/PROMPT) de Forge Observer V0 (lecture seule)"
    )
    parser.add_argument("--project", default="breakout_v2")
    parser.add_argument("--repo", type=Path, default=default_repo_root())
    parser.add_argument(
        "--transcripts",
        type=Path,
        default=default_transcripts_root(),
    )
    parser.add_argument("--verbose", "-v", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.INFO if args.verbose else logging.WARNING,
        format="%(levelname)s %(name)s: %(message)s",
    )

    ctx = ObserverContext.build(args.repo, args.project, args.transcripts)

    report_dir = args.repo / "EVIDENCE" / "reports" / "observer" / args.project
    result_path = report_dir / "observer_run.json"
    events_path = report_dir / "events.jsonl"

    # Lecture DIRECTE (pas via ctx) : ce sont des artefacts DEJA reconstruits
    # par cli.py, hors du perimetre de cecite d'Observer — meme convention que
    # `observer.fleet.__main__` et `observer.prompt.main`, qui ne relisent
    # jamais leur propre sortie via ObserverContext.
    with result_path.open("r", encoding="utf-8-sig") as fh:
        result: dict[str, Any] = json.load(fh)

    events: list[dict[str, Any]] = []
    with events_path.open("r", encoding="utf-8-sig") as fh:
        for line in fh:
            line = line.strip()
            if line:
                events.append(json.loads(line))

    prompts = collect_prompts(ctx)
    views = build_agent_views(ctx, result, events, prompts)

    s3 = views["s3_agents"]
    s4 = views["s4_prompt"]
    s6 = views["s6_injection"]

    print(f"contrats trouves (s3_agents)        : {len(s3['lignes'])}")

    not_observable_counter: Counter[str] = Counter()
    for fiche in s3["lignes"]:
        for cle, cell in fiche.items():
            if cle in ("fichier", "enrichissement"):
                continue
            if isinstance(cell, dict) and cell.get("v") == NOT_OBSERVABLE:
                not_observable_counter[cle] += 1
        for cle, cell in fiche.get("enrichissement", {}).items():
            if isinstance(cell, dict) and cell.get("v") == NOT_OBSERVABLE:
                not_observable_counter[f"enrichissement.{cle}"] += 1

    print("champs NOT_OBSERVABLE les plus frequents :")
    for cle, n in not_observable_counter.most_common(12):
        print(f"  {cle:<35} {n}")

    print()
    print(f"activations de prompt (s4_prompt)      : {len(s4.get('activations', []))}")
    print(f"activations d'injection (s6_injection)  : {len(s6.get('lignes', []))}")

    print()
    print("resume injection, maillon par maillon, pour s9-build-godot-standard et s11-redteam-code :")
    for ligne in s6.get("lignes", []):
        if ligne.get("etape") not in ("s9-build-godot-standard", "s11-redteam-code"):
            continue
        statuts = Counter(m["statut"] for m in ligne["maillons"])
        print(f"  {ligne['run_id']} / {ligne['etape']} attempt={ligne['attempt']}")
        for cle, n in statuts.items():
            print(f"      {cle:<22} x{n}")

    print()
    print("detail v2 (statut_v2 + consommation) pour s9-build-godot-standard, run3 :")
    for ligne in s6.get("lignes", []):
        if ligne.get("etape") != "s9-build-godot-standard" or "run3" not in (ligne.get("run_id") or ""):
            continue
        print(f"  {ligne['run_id']} / {ligne['etape']} attempt={ligne['attempt']}")
        for m in ligne["maillons"]:
            conso = m["consommation"]
            v = conso["v"]
            if isinstance(v, dict):
                extra = ""
                if "ratio" in v:
                    extra = f" {v['ratio']} lus"
                    if v.get("fichiers_non_lus"):
                        extra += f" ; non lus: {v['fichiers_non_lus']}"
                elif "appels" in v:
                    extra = f" {v['appels']} appels {v.get('outils_appeles')}"
                    if v.get("appels_hors_charge"):
                        extra += f" ; hors charge: {v['appels_hors_charge']}"
                conso_txt = f"{v.get('etat')}{extra}"
            else:
                conso_txt = str(v)
            print(f"      {m['cle']:<22} {m['statut_v2']:<22} conso={conso_txt}")

    recap = s6.get("recap_v2") or {}
    print()
    print("recap_v2 (toutes activations confondues) :")
    for statut, n in (recap.get("par_statut") or {}).items():
        print(f"  {statut:<22} x{n}")
    print(f"  champs DECLARED_NOT_INJECTED : "
          f"{[c['cle'] for c in recap.get('champs_declared_not_injected', [])]}")

    print()
    print("matrice ELEMENT (Declare/Injecte/Consomme/Prouve) pour s9-build-godot-standard, run3 :")
    for ligne in s6.get("lignes", []):
        if ligne.get("etape") != "s9-build-godot-standard" or "run3" not in (ligne.get("run_id") or ""):
            continue
        print(f"  {ligne['run_id']} / {ligne['etape']} attempt={ligne['attempt']}")
        for el in ligne.get("matrice", []):
            preuve = el["prouve"]["v"]
            niveau = preuve.get("niveau") if isinstance(preuve, dict) else preuve
            print(f"      {el['element']:<22} {el['statut']:<22} prouve={niveau}")
            if el.get("nb_elements_non_consommes"):
                print(f"          elements_non_consommes ({el['nb_elements_non_consommes']}): "
                      f"{el['elements_non_consommes']}")

    recap_matrice = s6.get("recap_matrice") or {}
    print()
    print("recap_matrice (toutes activations confondues) :")
    for statut, n in (recap_matrice.get("par_statut") or {}).items():
        print(f"  {statut:<22} x{n}")
    print(f"  elements INJECTED_NOT_CONSUMED : "
          f"{[e['cle'] for e in recap_matrice.get('elements_injected_not_consumed', [])]}")

    print()
    print("2 fiches completes en resume :")
    for fiche in s3["lignes"][:2]:
        print(f"- {fiche['fichier']}  ({fiche['nom_humain']['v']})")
        print(f"    posture                : {fiche['posture']['v']}")
        print(f"    capability_role        : {fiche['capability']['v']}")
        print(f"    modele resolu          : {fiche['modele']['v']}")
        print(f"    reasoning_effort       : {fiche['reasoning_effort']['v']}")
        print(f"    skill / plugin         : {fiche['skill']['v']} / {fiche['plugin']['v']}")
        print(f"    delegation             : {fiche['delegation']['v']}")
        enrich = fiche["enrichissement"]
        print(f"    derniere_activation    : {enrich['derniere_activation']['v']}")
        print(f"    modele_declare_vs_mesure: {enrich['modele_declare_vs_mesure']['v']}")
        print(f"    outils_observes        : {enrich['outils_observes']['v']}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
