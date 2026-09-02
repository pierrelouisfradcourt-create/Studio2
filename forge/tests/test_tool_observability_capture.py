"""Maillon 4 (appel réel) — forge.tool_observability.parse_tool_use_events /
extract_final_result / tool_names_used.

Question mécanique tranchée le 2026-07-30 : `claude -p --output-format json`
(utilisé par `forge.run_real._claude_call_raw` en production) rend un SEUL
objet résultat — AUCUN événement tool_use observable de ce format. Preuve :
`claude -p --help` documente "json (single result)". `--output-format
stream-json --verbose` rend un JSONL d'événements — PROUVÉ par un appel RÉEL
(pas simulé) :

  claude -p --model haiku --output-format stream-json --verbose \
    --add-dir <scratch> --strict-mcp-config --allowedTools "Bash(echo:*)" \
    --permission-mode acceptEdits --max-budget-usd 0.05 \
    "Use the Bash tool to run exactly this command: echo forge_probe_ok . ..."

capturé dans fixtures/tool_observability/probe_bash_echo_real_capture.jsonl
(stdout brut, non édité). Second appel RÉEL, `--tools ""` (aucun outil
disponible), capturé dans probe_no_tools_real_capture.jsonl : la mesure ZÉRO
tool_use est donc, elle aussi, une capture réelle — pas une valeur par défaut
non testée (« 0 est une mesure », pas une absence de mesure).

Ces deux fonctions sont PURES (aucune I/O, aucun subprocess) et ne sont PAS
câblées dans `forge.run_real._claude_call_raw` (fichier non modifié par ce
chantier) — voir le rapport de mission pour la limite assumée.
"""
from __future__ import annotations

from pathlib import Path

from forge import tool_observability as obs

FIXTURES = Path(__file__).resolve().parent / "fixtures" / "tool_observability"
BASH_ECHO = (FIXTURES / "probe_bash_echo_real_capture.jsonl").read_text(encoding="utf-8")
NO_TOOLS = (FIXTURES / "probe_no_tools_real_capture.jsonl").read_text(encoding="utf-8")


# --- capture RÉELLE avec un outil effectivement invoqué -------------------------

def test_parse_tool_use_events_sur_capture_reelle_bash():
    events = obs.parse_tool_use_events(BASH_ECHO)
    assert len(events) == 1
    assert events[0]["name"] == "Bash"
    assert events[0]["tool_use_id"].startswith("toolu_")
    assert "command" in events[0]["input_keys"]


def test_tool_names_used_sur_capture_reelle_bash():
    assert obs.tool_names_used(BASH_ECHO) == ("Bash",)


def test_extract_final_result_sur_capture_reelle_bash():
    result = obs.extract_final_result(BASH_ECHO)
    assert result is not None
    assert result["type"] == "result"
    # Valeurs RÉELLEMENT capturées (pas inventées) — cf. fixture.
    assert result["total_cost_usd"] > 0
    assert result["num_turns"] == 2


# --- capture RÉELLE SANS aucun outil disponible : preuve que 0 est une mesure ---

def test_parse_tool_use_events_sur_capture_reelle_sans_outils():
    """Négatif du maillon 4 : une vraie réponse SANS tool_use produit un tuple
    VIDE, pas une valeur devinée. Ce test échouerait si le parseur
    hallucinait un événement là où il n'y en a aucun."""
    events = obs.parse_tool_use_events(NO_TOOLS)
    assert events == ()
    assert obs.tool_names_used(NO_TOOLS) == ()


def test_extract_final_result_fonctionne_aussi_quand_zero_tool_use():
    result = obs.extract_final_result(NO_TOOLS)
    assert result is not None
    assert result["type"] == "result"
    assert result["num_turns"] == 1


# --- robustesse : jamais d'exception, jamais un événement inventé ---------------

def test_flux_vide_rend_tuple_vide_et_aucun_resultat():
    assert obs.parse_tool_use_events("") == ()
    assert obs.extract_final_result("") is None


def test_lignes_corrompues_ignorees_jamais_une_exception():
    corrompu = 'not json at all\n{"type":"assistant"\n' + BASH_ECHO
    # Ne lève pas ; retrouve quand même l'événement réel noyé dans du bruit.
    assert obs.tool_names_used(corrompu) == ("Bash",)


def test_type_assistant_sans_content_ignore_proprement():
    flux = '{"type":"assistant","message":{}}\n'
    assert obs.parse_tool_use_events(flux) == ()


def test_final_result_prend_la_derniere_ligne_result_pas_la_premiere():
    flux = (
        '{"type":"result","total_cost_usd":0.01}\n'
        '{"type":"assistant","message":{"content":[]}}\n'
        '{"type":"result","total_cost_usd":0.02}\n'
    )
    assert obs.extract_final_result(flux)["total_cost_usd"] == 0.02
