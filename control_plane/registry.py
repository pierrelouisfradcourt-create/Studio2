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


def _load_yaml(path: Path) -> dict:
    try:
        import yaml  # PyYAML — disponible dans .venv312
        with open(path, encoding="utf-8") as f:
            return yaml.safe_load(f) or {}
    except Exception as exc:
        log.warning("registry: cannot load %s — %s", path, exc)
        return {}


def load_capabilities(path: Path) -> dict:
    return _load_yaml(path)


def load_providers(path: Path) -> dict:
    return _load_yaml(path)


def get_model_for_role(role: str, caps_path: Path) -> Optional[str]:
    """Return the short model name (last path component) for a given role, or None."""
    for model in load_capabilities(caps_path).get("models", []):
        if role in model.get("roles", []):
            return model["id"].split("/")[-1]
    return None


def get_provider_for_role(role: str, caps_path: Path) -> Optional[str]:
    """Return the provider field for a role's resolved model, or None.

    Mirror read-only de get_model_for_role : le contrat déclare un rôle, le
    registry résout le provider (lmstudio / claude-local / forge). Utilisé par
    l'aiguilleur runtime Forge pour honorer payload.provider sans deviner depuis
    le nom court du modèle.
    """
    for model in load_capabilities(caps_path).get("models", []):
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
    for model in load_capabilities(caps_path).get("models", []):
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
