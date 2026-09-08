"""Câblage join_check → humangate_flags (GO Pierre 2026-09-08).

Diagnostic (micro-audit lecture seule) : `forge.run_real.check_wiremap_join` mesure
déjà si la WireMap couvre réellement le plan (5 régimes) et le reçu est stocké dans
`state.json` (`s5-wiremap.detail.join_check`), mais rien ne le pliait en
`extra_advisory` — mesuré : il avait détecté R12/R15 (`lignes_sans_couvre: 2`) dès le
premier run `chaton_clicker`, sans qu'aucun humain ne le voie sans lire state.json à
la main.

Même patron que `test_driver_amont_traversal_advisory.py` /
`test_driver_player_loop_wiring.py` : `ForgeDriver.__new__` sans `__init__`, on ne
teste que la méthode ajoutée."""
from forge.driver import ForgeDriver


def _driver_minimal():
    return ForgeDriver.__new__(ForgeDriver)


def _state(detail):
    return {"steps": {"s5-wiremap": {"detail": detail}}}


def test_regime_joined_forme_satisfaite_ne_declenche_rien():
    d = _driver_minimal()
    detail = {"join_check": {"regime": "JOINED", "forme_satisfaite": True,
                             "capacites_couvertes": 15, "capacites": 15}}
    assert d._join_facts(_state(detail)) == ()


def test_regime_not_applicable_ne_declenche_rien():
    d = _driver_minimal()
    detail = {"join_check": {"regime": "NOT_APPLICABLE", "forme_satisfaite": True}}
    assert d._join_facts(_state(detail)) == ()


def test_not_measured_ne_declenche_rien():
    d = _driver_minimal()
    detail = {"join_check": {"status": "NOT_MEASURED", "regime": "NOT_MEASURED"}}
    assert d._join_facts(_state(detail)) == ()


def test_absence_de_join_check_ne_declenche_rien():
    """Run antérieur au 2026-09-02, ou étape absente du profil — pas de rétro-pénalité."""
    d = _driver_minimal()
    assert d._join_facts(_state({})) == ()
    assert d._join_facts({"steps": {}}) == ()


def test_reproduit_le_cas_reel_r12_r15_forme_non_satisfaite():
    """Cas EXACT mesuré sur chaton_clicker : regime JOINED (15/15 capacités) mais
    forme_satisfaite=False (lignes_sans_couvre=2, R12/R15). Doit être signalé nommément
    malgré le régime JOINED."""
    d = _driver_minimal()
    detail = {"join_check": {
        "regime": "JOINED", "forme_satisfaite": False,
        "capacites_couvertes": 15, "capacites": 15,
        "lignes_sans_couvre": 2, "couverture_fantome": 0,
    }}
    facts = d._join_facts(_state(detail))
    assert len(facts) == 1
    assert "lignes_sans_couvre=2" in facts[0]
    assert "join_check" in facts[0]


def test_regime_partial_est_signale():
    d = _driver_minimal()
    detail = {"join_check": {"regime": "PARTIAL", "forme_satisfaite": True,
                             "capacites_couvertes": 3, "capacites": 5,
                             "lignes_sans_couvre": 0, "couverture_fantome": 1}}
    facts = d._join_facts(_state(detail))
    assert len(facts) == 1
    assert "PARTIAL" in facts[0]


def test_regime_void_et_empty_form_sont_signales():
    d = _driver_minimal()
    for regime in ("VOID", "EMPTY_FORM"):
        detail = {"join_check": {"regime": regime, "forme_satisfaite": regime != "EMPTY_FORM"}}
        assert d._join_facts(_state(detail)) != (), f"regime {regime} aurait dû être signalé"


def test_prefere_le_recu_apres_reparation():
    """join_check_apres_reparation, s'il existe, prime sur join_check (état le plus
    à jour que le driver connaisse)."""
    d = _driver_minimal()
    detail = {
        "join_check": {"regime": "VOID", "forme_satisfaite": True},
        "join_check_apres_reparation": {"regime": "JOINED", "forme_satisfaite": True},
    }
    assert d._join_facts(_state(detail)) == ()


def test_le_flag_ne_change_jamais_software_verdict():
    """Vérification structurelle : _join_facts ne retourne QUE des chaînes, jamais
    une clé qui influencerait software_verdict — même garantie que _player_loop_facts
    (extra_advisory, jamais dans le calcul du verdict)."""
    d = _driver_minimal()
    detail = {"join_check": {"regime": "PARTIAL", "forme_satisfaite": False}}
    facts = d._join_facts(_state(detail))
    assert isinstance(facts, tuple)
    assert all(isinstance(f, str) for f in facts)
