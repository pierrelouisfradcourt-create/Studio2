"""Oracle de l'escalade de modèle Forge.

Un tier faible (builder Haiku) peut DEMANDER, ou déclencher par échec d'oracle, une
montée en puissance : ré-exécuter LE MÊME contrat sur le tier supérieur. Bornée,
tracée. Prolonge l'aiguilleur A2.
"""
from forge.escalate import (
    LADDER,
    MAX_ESCALATIONS,
    EscalationDecision,
    escalation_decision,
    next_tier,
    parse_agent_escalation,
    tier_of,
)


def test_tier_of_normalizes_ids_and_names():
    assert tier_of("claude-haiku-4-5-20251001") == "haiku"
    assert tier_of("claude-sonnet-5") == "sonnet"
    assert tier_of("claude-opus-4-8") == "opus"
    assert tier_of("haiku") == "haiku"
    assert tier_of("qwen2.5-14b-instruct") is None   # hors échelle (reviewer indépendant)
    assert tier_of("non-llm") is None


def test_next_tier_climbs_then_stops():
    assert next_tier("haiku") == "sonnet"
    assert next_tier("claude-sonnet-5") == "opus"
    assert next_tier("opus") is None       # déjà au sommet
    assert next_tier("non-llm") is None


def test_parse_agent_escalation_marker():
    ok, reason = parse_agent_escalation("build partiel... ESCALATE_REQUEST: physique trop complexe pour ce tier")
    assert ok is True
    assert "trop complexe" in reason


def test_parse_agent_escalation_json():
    ok, _ = parse_agent_escalation('rapport {"escalate": true, "reason": "x"}')
    assert ok is True


def test_parse_agent_escalation_absent():
    ok, reason = parse_agent_escalation("build terminé, oracle vert")
    assert ok is False
    assert reason == ""


def test_escalate_on_oracle_fail():
    d = escalation_decision("haiku", oracle_ok=False, agent_requested=False)
    assert isinstance(d, EscalationDecision)
    assert d.escalate is True
    assert d.next_model == "sonnet"


def test_no_escalate_when_oracle_ok_and_no_request():
    d = escalation_decision("haiku", oracle_ok=True, agent_requested=False)
    assert d.escalate is False


def test_escalate_on_agent_request_even_if_oracle_ok():
    d = escalation_decision("haiku", oracle_ok=True, agent_requested=True, agent_reason="tâche trop grosse")
    assert d.escalate is True
    assert d.next_model == "sonnet"
    assert "trop grosse" in d.reason


def test_no_escalate_beyond_cap():
    d = escalation_decision("haiku", oracle_ok=False, agent_requested=False, escalations_so_far=MAX_ESCALATIONS)
    assert d.escalate is False
    assert "cap" in d.reason.lower()


def test_top_tier_failure_routes_to_humangate_not_loop():
    d = escalation_decision("opus", oracle_ok=False, agent_requested=False)
    assert d.escalate is False
    assert "humangate" in d.reason.lower()


def test_ladder_is_weak_to_strong():
    assert LADDER == ("haiku", "sonnet", "opus")
