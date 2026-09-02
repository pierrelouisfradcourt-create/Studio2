"""Pool de builders réactif (Concept A, Tier 2 #5) — best-of-N au MÊME tier.

WFL-01 (labo) n'était pas un mécanisme réel : une discipline manuelle
control/variant, jamais invocable, jamais réconciliée. Ce module est la
première version RÉELLE, bornée en coût :

  - zéro surcoût sur le chemin heureux (1er essai vert = 1 seul appel, comme
    avant) ;
  - sur un FAIL d'oracle SEULEMENT (jamais sur une demande explicite de
    l'agent — ``ESCALATE_REQUEST`` veut dire « ce tier est trop faible »,
    retenter le même tier n'y changerait rien), retente jusqu'à
    ``pool_size - 1`` fois de plus AU MÊME tier avant d'escalader de modèle
    (haiku -> sonnet -> opus, plus coûteux et pas toujours nécessaire — un
    FAIL peut être un aléa du tirage, pas une preuve que le tier est trop
    faible) ;
  - départage = le premier candidat dont l'oracle RÉEL passe gagne :
    déterministe, aucun LLM-arbitre (NO_CLAIM_ALLOWED).

S'insère dans ``forge.driver.ForgeDriver._maybe_escalate`` AVANT l'appel à
``forge.escalate.escalation_decision`` : le pool épuisé retombe dans
l'escalade de modèle existante, inchangée.
"""
from __future__ import annotations

from dataclasses import dataclass

# 1er essai + 1 candidat supplémentaire au même tier avant d'escalader de modèle.
DEFAULT_POOL_SIZE = 2


@dataclass(frozen=True)
class PoolDecision:
    retry_same_tier: bool
    reason: str


def pool_decision(
    *,
    oracle_ok: bool,
    attempts_at_current_tier: int,
    pool_size: int = DEFAULT_POOL_SIZE,
) -> PoolDecision:
    """Faut-il retenter LE MÊME tier avant d'escalader de modèle ?

    ``attempts_at_current_tier`` compte les tentatives DÉJÀ jouées à ce tier,
    y compris celle qui vient d'échouer (>= 1). ``pool_size`` <= 1 désactive
    le pool (chaque FAIL escalade directement, comportement pré-Tier-2).
    """
    if oracle_ok:
        return PoolDecision(False, "oracle OK — aucun retry nécessaire")
    if attempts_at_current_tier >= pool_size:
        return PoolDecision(
            False, f"pool épuisé ({attempts_at_current_tier}/{pool_size} au tier courant)"
        )
    return PoolDecision(
        True, f"retry même tier ({attempts_at_current_tier + 1}/{pool_size})"
    )
