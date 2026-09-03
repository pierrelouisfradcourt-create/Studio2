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

# Lot B (GO Pierre 2026-09-02) : l'adaptateur LM vit DANS le paquet (`forge.lm_adapter`),
# extrait verbatim de `scripts/council.py`. Le bricolage de `sys.path` qui existait ici pour
# atteindre `scripts/` est SUPPRIMÉ : la Forge ne dépend plus du fichier d'une lane, et plus
# aucun chemin V1 n'est inséré dans `sys.path` au chargement de ce module.

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
    """Construit le QwenAdapter réel (`forge.lm_adapter`, extrait verbatim de council.py).

    Import PARESSEUX conservé tel quel : il garde `runtime.py` importable même si `requests`
    manque. Mais la dépendance qu'il porte est désormais INTERNE au paquet — c'est tout l'objet
    du lot B. Un import paresseux vers l'extérieur du paquet est précisément ce qui a fait
    tomber RUN M à s6 sans que rien ne le dise (cf. en-tête de `forge/lm_adapter.py`).
    """
    from forge.lm_adapter import QwenAdapter

    return QwenAdapter()


def qwen_probe(adapter=None) -> tuple[bool, str]:
    """(disponible, raison) — C-2, GO Pierre 2026-09-02, après RUN M.

    DÉFAUT CORRIGÉ : `qwen_available` rendait le MÊME `False` pour un `ModuleNotFoundError`
    (adaptateur introuvable) et pour un port fermé, et `route_step` annonçait alors
    « lmstudio :1234 down ». Le 2026-09-02 à 18:01 ce motif a été produit sur un port OUVERT,
    pendant que Qwen répondait en node 3 secondes plus tôt : un oracle correct rendant un motif
    faux. La cause est désormais DISTINGUÉE et transportée, jamais réécrite en aval.
    """
    try:
        ad = adapter if adapter is not None else _make_qwen_adapter()
    except Exception as exc:  # noqa: BLE001
        return False, (f"adaptateur LM indisponible ({type(exc).__name__}: {exc}) — "
                       "cause d'IMPORT, PAS un service down")
    try:
        return (True, "") if ad.is_available() else (
            False, "LM Studio ne répond pas sur son endpoint de santé — service injoignable")
    except Exception as exc:  # noqa: BLE001
        return False, (f"sonde LM en échec ({type(exc).__name__}) — cause RÉSEAU/SONDE, "
                       "distincte d'un défaut d'import")


def qwen_available(adapter=None) -> bool:
    """LM Studio joignable ? Conservé pour compatibilité — la CAUSE vit dans `qwen_probe`."""
    return qwen_probe(adapter)[0]


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
        # La DÉCISION reste prise par `qwen_available` : c'est le joint que 42 fichiers de test
        # substituent (`monkeypatch.setattr("forge.runtime.qwen_available", ...)`). Déplacer le
        # point de décision aurait rendu ces substitutions silencieusement inopérantes — un joint
        # de test qu'on croit actif et qui ne l'est plus est exactement le mode de panne que ce
        # lot corrige ailleurs. Seule la CAUSE vient de la sonde détaillée.
        if qwen_available():
            return RouteDecision(
                runner=RUNNER_QWEN,
                reviewer=payload.model or _QWEN_FALLBACK_MODEL,
            )
        # C-2 : la cause MESURÉE est transportée telle quelle. Ne jamais la remplacer par un
        # motif générique : c'est ce qui a fait passer un défaut d'import pour un service down.
        cause = qwen_probe()[1] or "indisponibilité signalée par la sonde, sans cause détaillée"
        return RouteDecision(
            runner=RUNNER_CLAUDE_BLIND,
            reviewer=CLAUDE_BLIND_REVIEWER,
            reason=f"reviewer indépendant indisponible — {cause}",
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
