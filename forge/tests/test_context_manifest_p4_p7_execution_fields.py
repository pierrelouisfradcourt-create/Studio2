"""Oracle P4 + P7 (lot dégel 2, docs/forge/FORGE_CONTEXT_COMPACT_V1.md §07) sur
la ligne 'execution' du Context Manifest :

  P4 — `tools_effective`/`tools_disallowed_count` portent le plancher RÉEL
       d'outils accordés par l'exécuteur (`run_real._STEP_TOOLS`), jamais la
       ligne d'audit signée de dispatch.py (`allowed_tools=()`, INTOUCHÉE).
  P7 — `context_budget` (nom trompeur : ne mesurait que ~8% du contexte réel)
       est requalifié `prompt_budget` (même calcul), + `ambient_context_note`
       informatif. `context_budget` reste émis EN PLUS, à l'identique, en
       alias rétrocompat DÉLIBÉRÉ pour `forge/context_check.mjs`
       (script Node hors périmètre fichiers de ce lot).

P4 est exercé via le SEAM déjà prouvé par `test_driver_premortem_lessons_
wiring.py` : `run_real._claude_call_raw` monkeypatché, `claude_executor` réel
assemble le prompt et écrit la ligne 'execution' réelle sur disque.

Fichier NEUF (forge/tests/**, régime studio normal) — n'altère aucun
test existant. NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
from dataclasses import dataclass

import pytest

import forge.run_real as run_real
from forge import context_manifest as cm


@dataclass
class FakePayload:
    etape: str
    model: str = "haiku"
    prompt: str = "PROMPT CONTRAT"
    provider: str = ""


def _context(run_dir, etape):
    return {
        "run_id": "tools-eff-run", "project": "proj", "run_dir": str(run_dir),
        "model_override": None, "dispatch_marker": f"FORGE_DISPATCH:{etape}:run:1",
        "attempt": 1, "premortem": [],
    }


@pytest.fixture
def capture_calls(monkeypatch):
    calls = []

    def fake(prompt, model, **kwargs):
        calls.append({"prompt": prompt, "model": model, **kwargs})
        return {"ok": True, "output": "artefact", "tokens": 1, "duration_s": 0.1, "cost_usd": 0.0}

    monkeypatch.setattr(run_real, "_claude_call_raw", fake)
    return calls


def _last_execution_record(run_dir, etape):
    lines = cm.manifest_path(run_dir, etape).read_text(encoding="utf-8").strip().splitlines()
    return json.loads(lines[-1])


# --- P4 : outils effectifs ----------------------------------------------------------

def test_execution_manifest_carries_effective_tools_for_s9_build_godot_standard(
        tmp_path, capture_calls):
    run_dir = tmp_path / "run"
    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={})
    ex(FakePayload("s9-build-godot-standard"), None,
       _context(run_dir, "s9-build-godot-standard"))

    rec = _last_execution_record(run_dir, "s9-build-godot-standard")
    assert tuple(rec["tools_effective"]) == ("Write", "Edit", "Read", "Bash(node:*)")
    assert rec["tools_disallowed_count"] == len(run_real._STEP_DISALLOWED)


def test_execution_manifest_carries_effective_tools_for_s11_redteam_code(
        tmp_path, capture_calls):
    run_dir = tmp_path / "run"
    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={})
    ex(FakePayload("s11-redteam-code"), None, _context(run_dir, "s11-redteam-code"))

    rec = _last_execution_record(run_dir, "s11-redteam-code")
    assert tuple(rec["tools_effective"]) == ("Read",)


def test_execution_manifest_step_absent_from_table_gets_empty_tuple_field_present(
        tmp_path, capture_calls):
    """Une étape sans entrée dans `_STEP_TOOLS` (ex. s6-redteam-plan) rend les outils
    DÉRIVÉS DE SON CONTRAT (M1, GO Pierre 2026-08-13 ; amendement de l'attendu ratifié
    par gate Pierre le même jour) — le champ reste TOUJOURS présent, jamais absent.

    Sémantique d'origine (P4/P7) : absente de la table -> tuple vide. Sémantique M1 :
    absente de la table -> `_effective_step_tools` dérive du champ `permissions` du
    contrat (s6-redteam-plan.yaml : `read: repo entier` -> ['Read'] ; write/run: rien
    de dérivable). L'invariant conservé ici est celui qui comptait déjà : le champ est
    présent même sans entrée ratifiée, et il reflète la borne réellement appliquée."""
    run_dir = tmp_path / "run"
    assert "s6-redteam-plan" not in run_real._STEP_TOOLS
    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={})
    ex(FakePayload("s6-redteam-plan"), None, _context(run_dir, "s6-redteam-plan"))

    rec = _last_execution_record(run_dir, "s6-redteam-plan")
    assert "tools_effective" in rec
    assert rec["tools_effective"] == ["Read"]
    # Cohérence avec la source M1 : le manifeste porte exactement la dérivation.
    assert rec["tools_effective"] == list(
        run_real._effective_step_tools("s6-redteam-plan"))


def test_build_execution_manifest_record_direct_defaults_are_additive():
    """Appel direct de `build_execution_manifest_record` sans les nouveaux
    paramètres : comportement rétrocompatible, champs présents par défaut."""
    rec = cm.build_execution_manifest_record(
        "r", "s9-build", "prompt", model="claude-sonnet-5",
    )
    assert rec["tools_effective"] == []
    assert rec["tools_disallowed_count"] == 0


# --- P7 : prompt_budget + ambient_context_note — UN SEUL nom émis ------------------
# (L'alias transitoire `context_budget` a été retiré à la clôture du lot : la
# lecture LEGACY des manifestes historiques vit côté LECTEUR, dans
# context_check.mjs extractBudget — testée dans context_check.test.mjs.)

def test_execution_manifest_carries_prompt_budget_and_ambient_note(tmp_path):
    rec = cm.append_execution_manifest(
        "test-run", "s9-build", tmp_path, "petit prompt", model="claude-sonnet-5",
    )
    assert rec["prompt_budget"]["status"] == "OK"
    assert rec["prompt_budget"]["model_window_tokens"] == 200000
    assert rec["ambient_context_note"]["measured"] is False
    assert rec["ambient_context_note"]["estimate_tokens"] == 32775
    assert "note" in rec["ambient_context_note"]


def test_legacy_context_budget_name_is_not_emitted_anymore(tmp_path):
    """Propriété DURABLE (pas l'accident transitoire de l'alias) : une ligne
    d'exécution neuve porte UN SEUL nom de budget — `prompt_budget`. L'ancien
    nom `context_budget` n'est plus écrit ; il n'est accepté qu'en LECTURE sur
    les manifestes historiques (côté context_check.mjs, jamais réécrits)."""
    rec = cm.append_execution_manifest(
        "test-run", "s9-build", tmp_path, "petit prompt", model="claude-sonnet-5",
    )
    assert "context_budget" not in rec
    assert rec["prompt_budget"]["status"] == "OK"


def test_prompt_budget_overflow_and_unknown_window_unchanged_by_the_rename(tmp_path):
    huge_prompt = "x" * 900_000
    rec = cm.append_execution_manifest(
        "test-run", "s9-build", tmp_path, huge_prompt, model="claude-sonnet-5",
    )
    assert rec["prompt_budget"]["status"] == "OVERFLOW_RISK"
    assert "context_budget" not in rec

    rec2 = cm.append_execution_manifest(
        "test-run", "s9-build", tmp_path, "prompt", model="some-unlisted-model",
    )
    assert rec2["prompt_budget"]["status"] == "UNKNOWN_WINDOW"
