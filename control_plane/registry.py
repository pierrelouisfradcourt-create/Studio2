"""control_plane/registry.py — Capability & Provider Registry (IMP-125).

Lit openclaw/capabilities.yaml et openclaw/providers.yaml.
Fallback silencieux si les fichiers sont absents.
"""
import logging
import urllib.request
import urllib.error
from pathlib import Path
from typing import Optional
from urllib.parse import urlparse

log = logging.getLogger(__name__)

_CAPS_PATH = Path(__file__).parent.parent / "openclaw" / "capabilities.yaml"
_PROV_PATH = Path(__file__).parent.parent / "openclaw" / "providers.yaml"


def _load_yaml(path: Path) -> dict:
    try:
        import yaml  # PyYAML — disponible dans .venv312
        with open(path, encoding="utf-8") as f:
            return yaml.safe_load(f) or {}
    except Exception as exc:
        log.warning("registry: cannot load %s — %s", path, exc)
        return {}


def load_capabilities(path: Optional[Path] = None) -> dict:
    return _load_yaml(path or _CAPS_PATH)


def load_providers(path: Optional[Path] = None) -> dict:
    return _load_yaml(path or _PROV_PATH)


def get_model_for_role(role: str, caps_path: Optional[Path] = None) -> Optional[str]:
    """Return the short model name (last path component) for a given role, or None."""
    for model in load_capabilities(caps_path).get("models", []):
        if role in model.get("roles", []):
            return model["id"].split("/")[-1]
    return None


def get_provider_for_role(role: str, caps_path: Optional[Path] = None) -> Optional[str]:
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


def get_reasoning_for_model(model_short_name: str, caps_path: Optional[Path] = None) -> object:
    """Return the RAW `reasoning` field declared for the model whose id's last
    path component equals `model_short_name` (the same short form
    `get_model_for_role` already returns), or None if no model matches.

    Companion function, MODEL-keyed rather than role-keyed : `get_model_for_role`
    / `get_provider_for_role` resolve role -> attribute of the model a role's
    contract declares. This one resolves the model a caller is ABOUT TO INVOKE
    -> that model's OWN declared `reasoning`. The distinction matters after an
    escalade (scripts/forge/escalate.py) : the model actually executing a call
    can differ from the model the originating role declares, and it is the
    EXECUTING model's own declaration that should ever apply — never the
    original role's. Raw passthrough (str | False | None, exactly as written in
    the YAML) : classification (CLI-compatible / not_applicable / unknown /
    absent) is left to the caller (see
    scripts/forge/reasoning_observability.classify_declared_reasoning) — this
    function only looks up, it never interprets or guesses.
    """
    for model in load_capabilities(caps_path).get("models", []):
        if model.get("id", "").split("/")[-1] == model_short_name:
            return model.get("reasoning")
    return None


def get_provider_status(provider_id: str, prov_path: Optional[Path] = None) -> str:
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


def probe_all_providers(prov_path: Optional[Path] = None) -> dict:
    """Probe every provider that has a healthcheck. Returns {id: 'UP'|'DOWN'|'SKIP'}."""
    results: dict = {}
    for p in load_providers(prov_path).get("providers", []):
        pid = p["id"]
        if pid == "autopilot_7331":  # éviter self-probe
            results[pid] = "SKIP"
        else:
            results[pid] = probe_provider(p)
    return results
