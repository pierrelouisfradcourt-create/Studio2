"""Oracle du router runtime Forge (A2).

`route_step` décide QUI exécute une étape LLM : Qwen local (contrat honoré) quand
LM Studio :1234 est UP, sinon fallback Claude en contexte vierge. `run_qwen_step`
exécute réellement l'appel Qwen (QwenAdapter de forge/lm_adapter.py, extrait verbatim) et
encode l'échec en `ok=False` pour que l'orchestrateur bascule en fallback.

Le `reviewer` réel (qwen2.5-14b vs claude-blind) est toujours restitué — il sera
plié dans le verdict signé (A3).
"""
from forge import runtime
from forge.contract import DispatchPayload, build_dispatch_payload, load_contract
from forge.runtime import RouteDecision, route_step, run_qwen_step


def _payload(model: str, provider: str) -> DispatchPayload:
    return DispatchPayload(
        etape="s6-redteam-plan",
        role="red-team",
        model=model,
        prompt="attaque le plan",
        allowed_tools=(),
        mandatory_read=(),
        provider=provider,
    )


# --- route_step : la décision d'aiguillage (pure, sans effet de bord) ----------

def test_route_lmstudio_up_goes_to_qwen(monkeypatch):
    monkeypatch.setattr(runtime, "qwen_available", lambda adapter=None: True)
    d = route_step(_payload("qwen2.5-14b-instruct", "lmstudio"))
    assert isinstance(d, RouteDecision)
    assert d.runner == "qwen"
    assert "qwen" in d.reviewer


def test_route_lmstudio_down_falls_back_to_claude_blind(monkeypatch):
    """C-2 (2026-09-02) : le seuil de decision est passe de `qwen_available` a `qwen_probe`,
    qui transporte la CAUSE. Ce test patche donc la sonde, et verifie en plus que la cause
    mesuree arrive telle quelle dans la `reason` — c'est tout l'objet du lot : sur RUN M, un
    defaut d'IMPORT avait ete annonce comme un « :1234 down » sur un port ouvert."""
    monkeypatch.setattr(runtime, "qwen_available", lambda adapter=None: False)
    monkeypatch.setattr(runtime, "qwen_probe",
                        lambda adapter=None: (False, "cause mesuree de test"))
    d = route_step(_payload("qwen2.5-14b-instruct", "lmstudio"))
    assert d.runner == "claude-blind"
    assert "fallback" in d.reviewer
    assert d.reason  # raison explicite (visibilité de la dégradation)
    assert "cause mesuree de test" in d.reason,         "la cause mesuree doit etre transportee, jamais remplacee par un motif generique"


def test_qwen_probe_distingue_import_et_reseau(monkeypatch):
    """C-2 : un defaut d'IMPORT et un service injoignable ne doivent plus rendre le meme motif."""
    monkeypatch.setattr(runtime, "_make_qwen_adapter",
                        lambda: (_ for _ in ()).throw(ModuleNotFoundError("council")))
    ok, cause = runtime.qwen_probe()
    assert ok is False and "IMPORT" in cause

    class _Injoignable:
        def is_available(self):
            return False
    ok2, cause2 = runtime.qwen_probe(_Injoignable())
    assert ok2 is False and "injoignable" in cause2
    assert cause != cause2, "les deux causes doivent etre distinctes"


def test_route_claude_local_goes_to_claude():
    d = route_step(_payload("claude-opus-4-8", "claude-local"))
    assert d.runner == "claude"
    assert d.reviewer == "claude-opus-4-8"


def test_route_forge_provider_is_oracle_guard():
    d = route_step(_payload("non-llm", "forge"))
    assert d.runner == "oracle"


def test_route_unknown_provider_defaults_to_claude_blind_with_reason():
    d = route_step(_payload("mystere", "provider-inconnu"))
    assert d.runner == "claude-blind"
    assert d.reason


# --- run_qwen_step : l'exécution réelle (échec encodé, jamais levé) ------------

def test_run_qwen_step_success():
    class FakeAdapter:
        def complete(self, prompt, **kw):
            return '{"stance":"APPROUVE","rationale":"ok"}'

    out = run_qwen_step(_payload("qwen2.5-14b-instruct", "lmstudio"), adapter=FakeAdapter())
    assert out["ok"] is True
    assert out["output"] == '{"stance":"APPROUVE","rationale":"ok"}'
    assert "qwen" in out["reviewer"]


def test_run_qwen_step_failure_returns_not_ok():
    class BoomAdapter:
        def complete(self, prompt, **kw):
            raise RuntimeError("call_failed")

    out = run_qwen_step(_payload("qwen2.5-14b-instruct", "lmstudio"), adapter=BoomAdapter())
    assert out["ok"] is False
    assert out["reason"]


def test_run_qwen_step_failure_never_claims_qwen_reviewer():
    """HIGH-3 : un appel Qwen raté ne doit JAMAIS s'étiqueter comme reviewé par Qwen.

    Le champ reviewer d'un échec porte l'identité RÉELLE (claude-blind fallback),
    le nom du modèle qui n'a pas répondu est conservé séparément dans `attempted`.
    """
    class BoomAdapter:
        def complete(self, prompt, **kw):
            raise RuntimeError("down")

    out = run_qwen_step(_payload("qwen2.5-14b-instruct", "lmstudio"), adapter=BoomAdapter())
    assert not out["reviewer"].lower().startswith("qwen")
    assert "claude-blind" in out["reviewer"]
    assert out["attempted"] == "qwen2.5-14b-instruct"


# --- le payload porte désormais le provider (résolu par le registry) ----------

def test_payload_carries_provider_for_s6_redteam():
    p = build_dispatch_payload(load_contract("s6-redteam-plan"), etape="s6-redteam-plan")
    assert p.provider == "lmstudio"  # gate 4 : reviewer indépendant Qwen


def test_payload_carries_provider_for_s4_archi():
    p = build_dispatch_payload(load_contract("s4-archi"), etape="s4-archi")
    assert p.provider == "claude-local"
