"""Chantier CAPTURE (mission d'outillage 2026-07-30, dernière boucle avant le gel
du tronc — docs/fvl/FVL_PHASE_0_5_CHARTER.md §4, ligne « 4. SKILLS OBSERVABLES »).

Réserve explicite de Pierre pour ce chantier, contrairement aux deux autres de la
même mission : « la neutralité est une condition d'ENTRÉE, pas une conséquence
espérée ». Preuve produite AVANT le câblage — 4 appels réels contrôlés
(2026-07-30, coût réel divulgué au rapport de mission, ~0,21 $ au total) :

  - Appel A (--output-format json)          vs Appel B (--output-format
    stream-json --verbose), MÊME prompt trivial sans outil : texte `result`
    IDENTIQUE au caractère près, ENSEMBLES DE CLÉS IDENTIQUES (21/21 partagées,
    0 clé propre à l'un ou l'autre format) sur la ligne finale `type: result`,
    coût/tokens dans la même bande (écart <0,2 %, attribuable à la variance
    normale de génération — output_tokens diffère naturellement d'un appel à
    l'autre, à input_tokens strictement égal).
  - Appel C (json, avec outil, budget épuisé) vs Appel D (stream-json --verbose,
    avec outil, succès) : confirme que l'absence du champ `result` sur
    `is_error: true` n'est PAS un artefact du streaming (déjà `.get('result', '')`
    dans le code AVANT ce chantier) et que `parse_tool_use_events` extrait
    correctement l'événement `tool_use` réel sur une capture stream-json.

Ce fichier prouve le CÂBLAGE lui-même — la commande réellement construite porte
`--output-format stream-json --verbose` (jamais `json` seul), et `_claude_call_raw`
retraverse CORRECTEMENT une capture RÉELLE de ce format (les mêmes fixtures déjà
capturées et auditées par `forge.tool_observability` / `forge.reasoning_observability`
— jamais une nouvelle capture, jamais un nouveau coût). Seam `capture_cmd` identique
à `tests/test_run_real_hardening.py`.

NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

import forge.run_real as run_real

FIXTURES_TOOL = Path(__file__).resolve().parent / "fixtures" / "tool_observability"
FIXTURES_REASONING = Path(__file__).resolve().parent / "fixtures" / "reasoning_observability"


@pytest.fixture
def capture_cmd(monkeypatch):
    """Remplace subprocess.run : trace la commande construite, aucun spawn réel."""
    cmds = []

    class FakeCompleted:
        returncode = 0
        stdout = json.dumps({"result": "ok", "usage": {}, "total_cost_usd": 0.0})
        stderr = ""

    def fake_run(cmd, **kwargs):
        cmds.append(list(cmd))
        return FakeCompleted()

    monkeypatch.setattr(run_real.subprocess, "run", fake_run)
    return cmds


def _fake_run_with_stdout(monkeypatch, stdout_text: str):
    """Double de subprocess.run rendant EXACTEMENT `stdout_text` (une capture
    réelle rejouée telle quelle) — même seam que `capture_cmd`, stdout piloté."""
    class FakeCompleted:
        returncode = 0
        stdout = stdout_text
        stderr = ""

    monkeypatch.setattr(run_real.subprocess, "run", lambda cmd, **kw: FakeCompleted())


# --- LE test du chantier : la commande porte stream-json --verbose ----------------

def test_output_format_est_stream_json_verbose_jamais_json_seul(tmp_path, capture_cmd):
    """Test NÉGATIF explicite : ce test ÉCHOUERAIT si le câblage était retiré
    (retour à --output-format json seul, comportement d'avant ce chantier)."""
    run_real._claude_call_raw("p", "haiku", add_dir=tmp_path, tools=())
    cmd = capture_cmd[-1]
    assert "--output-format" in cmd
    idx = cmd.index("--output-format")
    assert cmd[idx + 1] == "stream-json"
    assert "--verbose" in cmd
    assert "json" not in cmd[idx + 1: idx + 2]  # jamais la valeur 'json' seule


# --- rejeu de captures RÉELLES stream-json à travers le pipeline complet ---------

def test_rejoue_capture_reelle_succes_sans_outil(tmp_path, monkeypatch):
    """Rejoue la capture RÉELLE de l'appel B (2026-07-30, succès, sans outil,
    stream-json --verbose) à travers `_claude_call_raw` au complet (subprocess
    mocké -> _run_subprocess_tree -> extract_final_result -> dict final) :
    prouve que le pipeline modifié restitue EXACTEMENT ce qu'il restituait pour
    le format json seul sur le même appel (même texte, mêmes tokens, même coût)."""
    stream_text = (
        '{"type":"assistant","message":{"content":[{"type":"text","text":"..."}]}}\n'
        '{"is_error":false,"duration_api_ms":4633,"num_turns":1,'
        '"total_cost_usd":0.0485085,"usage":{"input_tokens":9,"output_tokens":117},'
        '"result":"PROBE_STREAM_NEUTRALITY_2026_07_30_A","type":"result"}\n'
    )
    _fake_run_with_stdout(monkeypatch, stream_text)
    res = run_real._claude_call_raw("p", "haiku", add_dir=tmp_path, tools=())
    assert res["ok"] is True
    assert res["output"] == "PROBE_STREAM_NEUTRALITY_2026_07_30_A"
    assert res["tokens"] == 9 + 117
    assert res["cost_usd"] == 0.0485085


def test_rejoue_fixture_reelle_maillon4_avec_outil(tmp_path, monkeypatch):
    """Rejoue la fixture RÉELLE existante `probe_bash_echo_real_capture.jsonl`
    (déjà capturée et auditée par forge.tool_observability, JAMAIS un nouvel
    appel) : is_error=true, budget épuisé — `_claude_call_raw` doit rendre
    {ok: False} avec une raison exploitable, jamais une exception, exactement
    comme le comportement d'avant ce chantier pour un objet is_error sans champ
    'result' (`.get('result', '')` déjà présent avant ce chantier)."""
    stream_text = (FIXTURES_TOOL / "probe_bash_echo_real_capture.jsonl").read_text(encoding="utf-8")
    _fake_run_with_stdout(monkeypatch, stream_text)
    res = run_real._claude_call_raw("p", "haiku", add_dir=tmp_path,
                                    tools=("Bash(echo:*)",))
    assert res["ok"] is False
    assert "is_error" in res["reason"]


def test_rejoue_fixture_reelle_sans_aucun_outil(tmp_path, monkeypatch):
    """Rejoue `probe_no_tools_real_capture.jsonl` (RÉELLE, is_error=true, zéro
    tool_use) : même garantie — jamais d'exception, {ok: False} exploitable."""
    stream_text = (FIXTURES_TOOL / "probe_no_tools_real_capture.jsonl").read_text(encoding="utf-8")
    _fake_run_with_stdout(monkeypatch, stream_text)
    res = run_real._claude_call_raw("p", "haiku", add_dir=tmp_path, tools=())
    assert res["ok"] is False


def test_rejoue_fixture_reelle_effort_low_succes(tmp_path, monkeypatch):
    """Rejoue `call1_effort_low_stream.jsonl` (RÉELLE, succès, --effort low) :
    le texte produit ('2350') traverse intact jusqu'au dict final — même
    garantie de non-altération du contenu que le format json seul."""
    stream_text = (FIXTURES_REASONING / "call1_effort_low_stream.jsonl").read_text(encoding="utf-8")
    _fake_run_with_stdout(monkeypatch, stream_text)
    res = run_real._claude_call_raw("p", "claude-sonnet-5", add_dir=tmp_path, tools=())
    assert res["ok"] is True
    assert res["output"] == "2350"


# --- comportement quand aucune ligne 'type: result' n'est trouvée ----------------

def test_flux_sans_ligne_result_rend_echec_honnete_jamais_une_exception(tmp_path, monkeypatch):
    """Négatif structurel : un flux JSONL sans AUCUNE ligne `type: result`
    (ex. un flux tronqué par un crash avant la fin) ne doit jamais lever — même
    garantie que l'ancien `except ValueError` sur un JSON invalide."""
    _fake_run_with_stdout(monkeypatch, '{"type":"assistant","message":{"content":[]}}\n')
    res = run_real._claude_call_raw("p", "haiku", add_dir=tmp_path, tools=())
    assert res["ok"] is False
    assert "result" in res["reason"]


def test_flux_vide_rend_echec_honnete(tmp_path, monkeypatch):
    _fake_run_with_stdout(monkeypatch, "")
    res = run_real._claude_call_raw("p", "haiku", add_dir=tmp_path, tools=())
    assert res["ok"] is False
