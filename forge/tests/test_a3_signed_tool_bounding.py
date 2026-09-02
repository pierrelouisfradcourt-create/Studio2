"""A3 (Paquet A, décision 3 — ratifiée Pierre 2026-08-28) — la ligne d'audit SIGNÉE
porte le bornage d'outils RÉELLEMENT appliqué, pas une prédiction vide.

Défaut mesuré : `spawn_prepared` (dispatch.py) signe `allowed_tools=payload.allowed_tools`
— les champs skill/plugin du contrat, donc `()` pour 17 contrats sur 19 — pendant que le
bornage réel appliqué à la CLI est `_effective_step_tools` / `_derive_disallowed`
(run_real), hors de toute signature. La ligne signée décrivait des outils qu'elle
n'appliquait pas.

CHOIX (option a) — on signe AU MOMENT OÙ LE MÉCANISME APPLIQUE : les événements
`spawn_authorized`/`spawn_executed`, écrits par le driver APRÈS le retour réel de
l'exécuteur, qui rapporte les valeurs qu'il a passées à `claude -p` (`res["spawn_link"]`,
R2-OBS P4). Signer au dispatch aurait signé une PRÉDICTION statique — et déplacé
`_STEP_TOOLS` dans un module partagé pour un gain de vérité nul.

Rétro-compatibilité DURE : `allowed_tools` ne disparaît pas et ne change pas de sens
(déclaration de contrat) ; le réel arrive dans des clés NOUVELLES
(`tools_effective_signed`, `tools_disallowed_count`) ; les lignes historiques restent
vérifiables (le HMAC porte sur le corps réellement présent).
"""
from __future__ import annotations

import json
import types
from pathlib import Path

import pytest

from forge import run_real
from forge.audit import sign_audit_record, verify_audit_line
from forge.driver import ForgeDriver

RUN_ID = "a3-1"
ETAPE_RATIFIEE = "s9-build"        # jeu d'outils RATIFIÉ (_STEP_TOOLS)
ETAPE_DERIVEE = "s2-worldscan"     # jeu d'outils DÉRIVÉ du contrat (permissions)


# --- harnais ------------------------------------------------------------------

def _driver(tmp_path, executor=None):
    return ForgeDriver(
        "proj-a3", RUN_ID, run_dir=tmp_path / "run", profile="micro",
        key_file=tmp_path / "k.key", audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
        executor=executor,
    )


def _payload(etape):
    return types.SimpleNamespace(etape=etape, model="haiku", provider="anthropic",
                                 allowed_tools=())


def _amont(tmp_path, etape):
    """L'amont RÉEL : produit par le mécanisme qui borne (run_real), jamais à la main."""
    return run_real._build_spawn_link_upstream(
        tmp_path / "run", etape, "PROMPT", None,
        model_declared="haiku", model_requested="haiku", res={})


def _lignes(tmp_path):
    path = tmp_path / "audit.jsonl"
    return [json.loads(l) for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


# --- (a) le bornage RÉEL entre dans le corps signé ----------------------------

@pytest.mark.parametrize("etape", [ETAPE_RATIFIEE, ETAPE_DERIVEE])
def test_les_outils_reellement_appliques_sont_signes(tmp_path, etape):
    """Vrai pour une étape RATIFIÉE (_STEP_TOOLS) comme pour une étape DÉRIVÉE
    (permissions du contrat) : la ligne porte les valeurs de l'appel."""
    d = _driver(tmp_path)
    res = {"ok": True, "spawn_link": _amont(tmp_path, etape)}
    d._record_spawn_executed(etape, 1, _payload(etape), res)

    attendus = list(run_real._effective_step_tools(etape))
    assert attendus, "étape témoin sans outil : le test ne prouverait rien"
    lignes = _lignes(tmp_path)
    assert [l["event"] for l in lignes] == ["spawn_authorized", "spawn_executed"]
    for ligne in lignes:
        assert ligne["tools_effective_signed"] == attendus
        assert ligne["tools_disallowed_count"] == len(
            run_real._derive_disallowed(tuple(attendus)))
        # `allowed_tools` (déclaration de contrat) INCHANGÉ — jamais écrasé.
        assert ligne["allowed_tools"] == []
        assert verify_audit_line(ligne) is True


def test_letape_derivee_prouve_quelle_ne_vient_pas_de_step_tools(tmp_path):
    """Garde d'indépendance : s2-worldscan n'a AUCUNE entrée `_STEP_TOOLS` et sort
    des outils non triviaux (dérivés de `permissions:`)."""
    assert ETAPE_DERIVEE not in run_real._STEP_TOOLS
    d = _driver(tmp_path)
    d._record_spawn_executed(ETAPE_DERIVEE, 1, _payload(ETAPE_DERIVEE),
                             {"ok": True, "spawn_link": _amont(tmp_path, ETAPE_DERIVEE)})
    signes = _lignes(tmp_path)[-1]["tools_effective_signed"]
    assert "WebSearch" in signes and "Read" in signes


def test_alteration_du_bornage_signe_invalide_la_signature(tmp_path):
    d = _driver(tmp_path)
    d._record_spawn_executed(ETAPE_RATIFIEE, 1, _payload(ETAPE_RATIFIEE),
                             {"ok": True, "spawn_link": _amont(tmp_path, ETAPE_RATIFIEE)})
    ligne = _lignes(tmp_path)[-1]
    assert verify_audit_line(ligne) is True
    ligne["tools_effective_signed"] = ligne["tools_effective_signed"] + ["Bash"]
    assert verify_audit_line(ligne) is False
    ligne["tools_effective_signed"] = ligne["tools_effective_signed"][:-1]
    ligne["tools_disallowed_count"] = 0
    assert verify_audit_line(ligne) is False


# --- (b) jamais d'invention, jamais de régression ------------------------------

def test_un_spawn_sans_amont_declare_null_jamais_un_bornage_invente(tmp_path):
    """Étape déterministe (oracle in-process) : aucun bornage CLI n'a été appliqué.
    `null` se lit « non mesuré » — un `[]` se lirait « aucun outil », ce serait faux."""
    d = _driver(tmp_path)
    d._record_spawn_executed("s10a-oracle-code", 1)
    ligne = _lignes(tmp_path)[-1]
    assert ligne["tools_effective_signed"] is None
    assert ligne["tools_disallowed_count"] is None
    assert verify_audit_line(ligne) is True


def test_les_lignes_historiques_restent_valides():
    """Une ligne d'audit écrite AVANT ce lot (sans les nouvelles clés) garde un HMAC
    valide : `verify_audit_line` re-signe le corps réellement présent."""
    ancienne = {
        "run_id": "vieux", "etape": "s9-build", "capability_role": "",
        "model": "haiku", "provider": "anthropic", "allowed_tools": [],
        "ts": 0.0, "event": "spawn_prepared", "attempt": 1, "unprofiled": False,
    }
    signee = sign_audit_record(ancienne)
    assert verify_audit_line(signee) is True
    assert "tools_effective_signed" not in signee


# --- (c) câblage RÉEL : le driver transmet ce que l'exécuteur a appliqué -------

def test_le_chemin_reel_du_driver_transmet_le_bornage(tmp_path, offline):
    """Preuve de branchement (pas seulement d'API) : `_run_llm` passe le `res` de
    l'exécuteur à la ligne signée."""
    amont = _amont(tmp_path, ETAPE_RATIFIEE)
    d = _driver(tmp_path, executor=lambda p, dec, ctx: {
        "ok": True, "output": "S", "tokens": 1, "duration_s": 1.0, "cost_usd": 0.0,
        "spawn_link": dict(amont)})
    state = {"steps": {e: {"status": "PENDING", "attempts": 0, "detail": {}}
                       for e in d.order}}
    assert d._run_llm(state, d.order[0]) is True

    executees = [l for l in _lignes(tmp_path) if l.get("event") == "spawn_executed"]
    assert executees
    assert executees[-1]["tools_effective_signed"] == amont["tools_effective"]
    assert executees[-1]["tools_disallowed_count"] == amont["tools_disallowed_count"]
