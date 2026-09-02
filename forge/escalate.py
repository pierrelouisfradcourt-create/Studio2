"""Escalade de modèle — un tier faible demande (ou déclenche) une montée en puissance.

Prolonge l'aiguilleur runtime (A2) : au lieu de figer le modèle contracté, on peut
ré-exécuter LE MÊME contrat sur un tier supérieur quand
  (a) le sous-agent le DEMANDE (tâche trop grosse) — ``ESCALATE_REQUEST: <raison>``, ou
  (b) l'oracle échoue après le build.
Bornée par ``MAX_ESCALATIONS`` et par l'existence d'un tier supérieur. Au sommet avec
échec => pas d'escalade, on remonte un besoin HumanGate (ne jamais boucler). L'échelle
est une politique de FAMILLES de modèles (haiku/sonnet/opus), pas des versions en dur
(ADR-002 gate 1). Fable est l'ORCHESTRATEUR de la chaîne, pas un tier de build.
"""
from __future__ import annotations

import re
from dataclasses import dataclass

# Échelle d'escalade, en termes de l'outil Agent (ce que l'orchestrateur passe comme
# `model`), du plus faible au plus fort.
LADDER = ("haiku", "sonnet", "opus")
MAX_ESCALATIONS = 2

_ESC_MARKER = re.compile(r"ESCALATE_REQUEST[:\s]+(.+)", re.IGNORECASE)
_ESC_JSON = re.compile(r'"escalate"\s*:\s*true', re.IGNORECASE)


def tier_of(model: str, ladder: tuple[str, ...] = LADDER) -> str | None:
    """Normalise un id/nom de modèle vers sa famille de tier (haiku/sonnet/opus), ou None.

    None = hors échelle de build (ex. `qwen2.5-14b-instruct` reviewer, `non-llm` oracle,
    `fable` orchestrateur) : ces rôles ne s'escaladent pas.
    """
    if not model:
        return None
    low = model.lower()
    for tier in ladder:
        if tier in low:
            return tier
    return None


def next_tier(model: str, ladder: tuple[str, ...] = LADDER) -> str | None:
    """Le tier immédiatement supérieur, ou None si déjà au sommet / hors échelle."""
    t = tier_of(model, ladder)
    if t is None:
        return None
    i = ladder.index(t)
    return ladder[i + 1] if i + 1 < len(ladder) else None


def parse_agent_escalation(output: str) -> tuple[bool, str]:
    """Détecte une DEMANDE d'escalade dans la sortie d'un sous-agent.

    Formes acceptées : marqueur ``ESCALATE_REQUEST: <raison>`` ou ``"escalate": true``
    (JSON). Retourne (demandé, raison).
    """
    if not output:
        return (False, "")
    m = _ESC_MARKER.search(output)
    if m:
        return (True, m.group(1).strip()[:200])
    if _ESC_JSON.search(output):
        return (True, "escalate:true (sortie JSON)")
    return (False, "")


@dataclass(frozen=True)
class EscalationDecision:
    escalate: bool
    next_model: str | None   # tier cible (haiku/sonnet/opus) à passer à l'outil Agent
    reason: str


def escalation_decision(
    current_model: str,
    *,
    oracle_ok: bool,
    agent_requested: bool,
    agent_reason: str = "",
    escalations_so_far: int = 0,
    ladder: tuple[str, ...] = LADDER,
    max_escalations: int = MAX_ESCALATIONS,
) -> EscalationDecision:
    """Décide s'il faut ré-exécuter le contrat sur un tier supérieur.

    Déclencheurs : oracle rouge OU demande explicite. Bornée par le cap et le sommet
    de l'échelle. Au sommet avec échec => remonte HumanGate (pas d'escalade en boucle).
    """
    if escalations_so_far >= max_escalations:
        return EscalationDecision(False, None, f"cap d'escalade atteint ({max_escalations})")
    if not (oracle_ok is False or agent_requested):
        return EscalationDecision(False, None, "aucun déclencheur (oracle OK, pas de demande)")
    nxt = next_tier(current_model, ladder)
    if nxt is None:
        top = tier_of(current_model, ladder) or current_model
        return EscalationDecision(
            False, None,
            f"déjà au tier max ({top}) — escalade impossible, remonter HumanGate",
        )
    if agent_requested and agent_reason.strip():
        why = agent_reason.strip()
    elif not oracle_ok:
        why = "oracle FAIL"
    else:
        why = "demande agent"
    return EscalationDecision(True, nxt, f"{tier_of(current_model, ladder)} -> {nxt} ({why})")
