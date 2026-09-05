"""control_plane/registry.py — Capability & Provider Registry (IMP-125).

SOURCE EXPLICITE, JAMAIS DEVINÉE. Le chemin du catalogue est un argument
OBLIGATOIRE : ce module ne connaît aucun emplacement par défaut.

Les défauts `openclaw/capabilities.yaml` et `openclaw/providers.yaml` ont été
retirés le 2026-09-04 (gate Pierre, décision A). `openclaw/` n'existe pas en V2 :
un appel sans chemin traversait `_load_yaml` -> fichier absent -> warning -> `{}`
-> `None`, c'est-à-dire qu'une erreur de structure ressortait comme un résultat
de résolution ordinaire. Mesure AST du même jour : les 11 sites d'appel de
production passaient DÉJÀ un chemin explicite, aucun ne dépendait des défauts.

En V2 l'unique catalogue lu est `forge/contracts/roles.yaml`, passé par
l'appelant (`forge/contract.py`, `capability.py`, `run_real.py`,
`repair_dispatch.py`, `asset_producer/asset_dispatch.py`).

HORS PÉRIMÈTRE de cette décision, délibérément :
- `_load_yaml` garde son `except -> warning -> {}` (rendre la lecture levante est
  la décision A-bis : `contract.py:666` n'attrape pas, une levée y remonterait) ;
- la branche providers (`load_providers`, `get_provider_status`, `probe_*`) est
  conservée bien qu'elle n'ait AUCUN consommateur mesuré — supprimer une API
  publique demande sa propre gate ;
- l'emplacement du fichier (`control_plane/` vs `TOOLS/`, CP-1 d'ADJUDICATION.md)
  reste non tranché : ce patch corrige un contrat, pas une architecture.
"""
import logging
import urllib.request
import urllib.error
from pathlib import Path
from typing import Optional
from urllib.parse import urlparse

log = logging.getLogger(__name__)


# --- diagnostic du catalogue (gate 2, 2026-09-05) --------------------------------------
# CE QUI NE MARCHAIT PAS, mesuré : trois causes distinctes — fichier absent, YAML
# invalide, fichier vide — rendaient toutes le MÊME message en aval,
# `RoleUnresolved: capability_role 'X' non résolu par le registry`. Ce message accuse LE
# RÔLE : on va relire la liste des rôles, parfaitement saine, au lieu de soupçonner une
# accolade non fermée. Verdict correct, cause fausse.
#
# CE QUI EST CHANGÉ ICI : la cause est NOMMÉE, pas le comportement. `_load_yaml` rend
# toujours `{}` sur anomalie ; `probleme_catalogue()` dit POURQUOI, et
# `forge.contract.resolve_runtime` l'ajoute à son message quand la résolution échoue.
#
# DEUX FORMES CRASHAIENT HORS du `except`, incohérence mesurée le même jour : un YAML
# rendant une LISTE donnait `AttributeError: 'list' object has no attribute 'get'`, et
# `models: 42` donnait `TypeError: 'int' object is not iterable`. L'erreur de PARSING
# était avalée pendant que l'erreur de STRUCTURE passait brute. Elles rendent desormais
# `{}` avec une cause nommée, comme les autres.

CATALOGUE_ABSENT = "fichier absent"
CATALOGUE_ILLISIBLE = "YAML illisible"
CATALOGUE_VIDE = "fichier vide"
CATALOGUE_STRUCTURE = "structure invalide (objet YAML attendu)"
CATALOGUE_MODELS = "clé `models` présente mais non-liste"


def probleme_catalogue(path: Path) -> "str | None":
    """Cause LISIBLE de l'inexploitabilité du catalogue, ou None s'il est exploitable.

    Fonction de DIAGNOSTIC : elle ne décide rien, elle explique. Appelée seulement
    lorsqu'une résolution a déjà échoué — jamais sur le chemin nominal."""
    path = Path(path)
    if not path.exists():
        return f"{CATALOGUE_ABSENT} ({path})"
    try:
        import yaml
        contenu = yaml.safe_load(path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001 — on RAPPORTE l'erreur, on ne la relance pas
        return f"{CATALOGUE_ILLISIBLE} ({path}) : {exc}"
    if contenu is None:
        return f"{CATALOGUE_VIDE} ({path})"
    if not isinstance(contenu, dict):
        return f"{CATALOGUE_STRUCTURE} ({path}) : {type(contenu).__name__} lu"
    if "models" in contenu and not isinstance(contenu["models"], list):
        return f"{CATALOGUE_MODELS} ({path}) : {type(contenu['models']).__name__} lu"
    return None


def _load_yaml(path: Path) -> dict:
    """Lecture TOLÉRANTE : toute anomalie donne `{}` + un warning nommant la cause.

    Volontairement NON levante — le refus a lieu en aval (`resolve_runtime` lève
    `RoleUnresolved`), et trois appelants (`capability._provider_for`,
    `asset_dispatch`, `repair_dispatch`) enveloppent déjà l'appel dans un
    `except Exception` : rendre la lecture levante ne refermerait PAS leur chemin
    silencieux. C'est une gate à part."""
    try:
        import yaml  # PyYAML — disponible dans .venv312
        with open(path, encoding="utf-8") as f:
            contenu = yaml.safe_load(f) or {}
    except Exception as exc:
        log.warning("registry: catalogue illisible %s — %s", path, exc)
        return {}
    if not isinstance(contenu, dict):
        log.warning("registry: catalogue %s — %s, %s lu",
                    path, CATALOGUE_STRUCTURE, type(contenu).__name__)
        return {}
    return contenu


def _models(caps_path: Path) -> list:
    """Liste `models` du catalogue, ou [] si elle est absente ou mal typée.

    Sans cette garde, `models: 42` faisait lever un `TypeError` nu depuis la boucle
    de chaque lecteur — une erreur Python à la place d'un refus explicable."""
    models = _load_yaml(caps_path).get("models", [])
    if not isinstance(models, list):
        log.warning("registry: catalogue %s — %s", caps_path, CATALOGUE_MODELS)
        return []
    return [m for m in models if isinstance(m, dict)]


def load_capabilities(path: Path) -> dict:
    return _load_yaml(path)


def load_providers(path: Path) -> dict:
    return _load_yaml(path)


def get_model_for_role(role: str, caps_path: Path) -> Optional[str]:
    """Return the short model name (last path component) for a given role, or None."""
    for model in _models(caps_path):
        if role in model.get("roles", []):
            return model.get("id", "").split("/")[-1]
    return None


def get_provider_for_role(role: str, caps_path: Path) -> Optional[str]:
    """Return the provider field for a role's resolved model, or None.

    Mirror read-only de get_model_for_role : le contrat déclare un rôle, le
    registry résout le provider (lmstudio / claude-local / forge). Utilisé par
    l'aiguilleur runtime Forge pour honorer payload.provider sans deviner depuis
    le nom court du modèle.
    """
    for model in _models(caps_path):
        if role in model.get("roles", []):
            return model.get("provider")
    return None


def get_reasoning_for_model(model_short_name: str, caps_path: Path) -> object:
    """Return the RAW `reasoning` field declared for the model whose id's last
    path component equals `model_short_name` (the same short form
    `get_model_for_role` already returns), or None if no model matches.

    Companion function, MODEL-keyed rather than role-keyed : `get_model_for_role`
    / `get_provider_for_role` resolve role -> attribute of the model a role's
    contract declares. This one resolves the model a caller is ABOUT TO INVOKE
    -> that model's OWN declared `reasoning`. The distinction matters after an
    escalade (forge/escalate.py) : the model actually executing a call
    can differ from the model the originating role declares, and it is the
    EXECUTING model's own declaration that should ever apply — never the
    original role's. Raw passthrough (str | False | None, exactly as written in
    the YAML) : classification (CLI-compatible / not_applicable / unknown /
    absent) is left to the caller (see
    forge/reasoning_observability.classify_declared_reasoning) — this
    function only looks up, it never interprets or guesses.
    """
    for model in _models(caps_path):
        if model.get("id", "").split("/")[-1] == model_short_name:
            return model.get("reasoning")
    return None


def get_provider_status(provider_id: str, prov_path: Path) -> str:
    """Return the static status field from providers.yaml, or 'UNKNOWN'."""
    for p in load_providers(prov_path).get("providers", []):
        if p["id"] == provider_id:
            return p.get("status", "UNKNOWN")
    return "UNKNOWN"


def probe_provider(provider: dict) -> str:
    """Live-probe a single provider dict. Returns 'UP' | 'DOWN' | 'SKIP'."""
    hc = provider.get("healthcheck")
    if not hc or not hc.get("endpoint"):
        return "SKIP"
    try:
        parsed = urlparse(provider["base_url"])
        url = f"{parsed.scheme}://{parsed.netloc}{hc['endpoint']}"
        req = urllib.request.Request(url, method=hc.get("method", "GET"))
        with urllib.request.urlopen(req, timeout=int(hc.get("timeout_s", 3))) as r:
            return "UP" if r.status < 400 else "DOWN"
    except Exception:
        return "DOWN"


def probe_all_providers(prov_path: Path) -> dict:
    """Probe every provider that has a healthcheck. Returns {id: 'UP'|'DOWN'|'SKIP'}."""
    results: dict = {}
    for p in load_providers(prov_path).get("providers", []):
        pid = p["id"]
        if pid == "autopilot_7331":  # éviter self-probe
            results[pid] = "SKIP"
        else:
            results[pid] = probe_provider(p)
    return results
