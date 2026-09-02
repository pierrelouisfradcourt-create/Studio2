"""Aiguilleur runtime des étapes LLM de la chaîne Forge (A2).

Le contrat déclare un rôle, le registry résout `provider` + `model`. À
l'EXÉCUTION, cet aiguilleur honore ce provider :

  - `lmstudio`   : si LM Studio :1234 est UP -> Qwen 14B réel (reviewer
                   indépendant, ADR-002 gate 4). Si down -> fallback Claude en
                   contexte vierge, tracé (jamais de wedge sur un service local
                   absent). Décision A2 « Qwen réel + fallback ».
  - `claude-local` : Claude (l'orchestrateur /forge spawn via l'outil Agent).
  - `forge`      : étape déterministe (oracle) — NE doit pas passer par un LLM.

`route_step` est une DÉCISION pure (l'unique effet de bord possible est la sonde
d'availability Qwen, elle-même monkeypatchable). `run_qwen_step` exécute
réellement l'appel et encode l'échec en `ok=False` pour que l'orchestrateur
bascule proprement en fallback. Le `reviewer` réel est toujours restitué : il est
plié dans le verdict signé (A3). claim_verdict: NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import logging
import sys
from dataclasses import dataclass
from pathlib import Path

from forge.contract import DispatchPayload

logger = logging.getLogger(__name__)

# forge/runtime.py -> parent.parent == scripts/ (pour importer council.py).
SCRIPTS_DIR = Path(__file__).resolve().parent.parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

# Providers (valeurs telles que déclarées dans contracts/roles.yaml).
PROVIDER_LMSTUDIO = "lmstudio"
PROVIDER_CLAUDE = "claude-local"
PROVIDER_FORGE = "forge"

# Runners (qui exécute réellement l'étape).
RUNNER_QWEN = "qwen"
RUNNER_CLAUDE = "claude"
RUNNER_CLAUDE_BLIND = "claude-blind"
RUNNER_ORACLE = "oracle"

_QWEN_FALLBACK_MODEL = "qwen2.5-14b-instruct"
# Identité RÉELLE du reviewer quand Qwen n'a pas (ou plus) répondu. Un échec Qwen
# ne doit jamais s'étiqueter du nom du modèle qui n'a pas tourné (HIGH-3).
CLAUDE_BLIND_REVIEWER = "claude-blind (fallback)"


@dataclass(frozen=True)
class RouteDecision:
    """Décision d'aiguillage d'une étape. `reviewer` = identité réelle à signer."""

    runner: str
    reviewer: str
    reason: str = ""


def _make_qwen_adapter():
    """Construit le QwenAdapter réel (scripts/council.py). Import paresseux : garde
    runtime.py importable même si council/governor/requests manquent."""
    from council import QwenAdapter  # scripts/ est sur sys.path (voir ci-dessus)

    return QwenAdapter()


def qwen_available(adapter=None) -> bool:
    """LM Studio :1234 joignable ? Toute erreur (import/réseau) => indisponible."""
    try:
        ad = adapter if adapter is not None else _make_qwen_adapter()
        return bool(ad.is_available())
    except Exception:  # noqa: BLE001 — indisponible = tout échec de sonde
        return False


def route_step(payload: DispatchPayload) -> RouteDecision:
    """Décide qui exécute l'étape LLM, en honorant payload.provider.

    Ne lève jamais : un provider inconnu ou un service down dégrade vers un
    fallback Claude en contexte vierge, avec une `reason` explicite (visibilité
    de la dégradation, jamais silencieuse).
    """
    provider = (payload.provider or "").strip()

    if provider == PROVIDER_FORGE:
        # Garde : une étape déterministe ne doit pas être routée comme un LLM.
        return RouteDecision(runner=RUNNER_ORACLE, reviewer="deterministic")

    if provider == PROVIDER_CLAUDE:
        return RouteDecision(runner=RUNNER_CLAUDE, reviewer=payload.model)

    if provider == PROVIDER_LMSTUDIO:
        if qwen_available():
            return RouteDecision(
                runner=RUNNER_QWEN,
                reviewer=payload.model or _QWEN_FALLBACK_MODEL,
            )
        return RouteDecision(
            runner=RUNNER_CLAUDE_BLIND,
            reviewer=CLAUDE_BLIND_REVIEWER,
            reason="lmstudio :1234 down — reviewer indépendant indisponible",
        )

    # Provider absent/inconnu : ne pas wedge, mais rendre la dégradation visible.
    return RouteDecision(
        runner=RUNNER_CLAUDE_BLIND,
        reviewer=CLAUDE_BLIND_REVIEWER,
        reason=f"provider inconnu {provider!r} — fallback Claude contexte vierge",
    )


def run_qwen_step(payload: DispatchPayload, adapter=None) -> dict:
    """Exécute RÉELLEMENT l'étape via Qwen local. N'élève jamais.

    Succès -> {ok:True, reviewer, output}. Échec (réseau/quota/import) ->
    {ok:False, reviewer, reason} : l'orchestrateur bascule alors en claude-blind.
    """
    attempted = payload.model or _QWEN_FALLBACK_MODEL
    try:
        ad = adapter if adapter is not None else _make_qwen_adapter()
        text = ad.complete(payload.prompt)
    except Exception:  # noqa: BLE001 — échec encodé, jamais propagé (CouncilCallError inclus)
        logger.warning("run_qwen_step: appel Qwen KO pour %s -> fallback attendu", payload.etape)
        # HIGH-3 : sur échec, le reviewer RÉEL est le fallback, jamais le nom Qwen.
        # `attempted` conserve quel modèle a été tenté (traçabilité, sans mentir).
        return {"ok": False, "reviewer": CLAUDE_BLIND_REVIEWER, "attempted": attempted,
                "reason": "call_failed"}
    return {"ok": True, "reviewer": attempted, "output": text}
