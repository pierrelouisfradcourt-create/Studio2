"""Pool de builders reactif (Concept A, Tier 2 #5) — best-of-N au MEME tier.

Zero surcout sur le chemin heureux ; retente le meme tier sur un FAIL d'oracle
avant d'escalader de modele (plus couteux). Departage = 1er candidat dont
l'oracle REEL passe gagne (deterministe, aucun LLM-arbitre).
"""
from forge.pool import DEFAULT_POOL_SIZE, PoolDecision, pool_decision


def test_no_retry_when_oracle_ok():
    d = pool_decision(oracle_ok=True, attempts_at_current_tier=1)
    assert isinstance(d, PoolDecision)
    assert d.retry_same_tier is False
    assert "necessaire" in d.reason or "OK" in d.reason


def test_retry_same_tier_on_first_failure():
    d = pool_decision(oracle_ok=False, attempts_at_current_tier=1, pool_size=2)
    assert d.retry_same_tier is True
    assert "2/2" in d.reason


def test_pool_exhausted_at_pool_size():
    d = pool_decision(oracle_ok=False, attempts_at_current_tier=2, pool_size=2)
    assert d.retry_same_tier is False
    assert "epuise" in d.reason.lower() or "épuisé" in d.reason.lower()


def test_pool_size_one_disables_pool():
    # pool_size<=1 : chaque FAIL escalade directement (comportement pre-Tier-2).
    d = pool_decision(oracle_ok=False, attempts_at_current_tier=1, pool_size=1)
    assert d.retry_same_tier is False


def test_default_pool_size_is_two():
    assert DEFAULT_POOL_SIZE == 2
