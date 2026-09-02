"""Oracle du correctif `spawn_authorized` (lot A, réparation 3).

Post-mortem pacman (studio_brain/journal/2026-08-07_postmortem_pacman_forge.md §2) :
`forge/audit.py` déclare TROIS événements (spawn_prepared / spawn_authorized /
spawn_executed) mais `spawn_authorized` n'était JAMAIS écrit — mesuré 0/1418. Deux
causes distinctes, corrigées séparément :

  (a) chemin A (interactif, outil Task) — `forge.hook_guard.record_authorization`
      existait, testée, mais SON SEUL APPELANT LÉGITIME documenté dans sa propre
      docstring (`.claude/hooks/pretool_forge_guard.py`) ne l'appelait pas.
  (b) chemin B (headless / driver) — `ForgeDriver._record_spawn_executed` écrivait
      `spawn_executed` sans jamais écrire `spawn_authorized` d'abord : ce chemin n'a
      pas de garde PreToolUse séparé, il EST sa propre autorité d'autorisation.

Ce fichier prouve les deux chemins réparés, PLUS l'invariant de lecture
`forge.audit.check_spawn_invariant` (nouveau, lecture seule) qui aurait détecté le
défaut s'il avait existé — et qui reste la garde de non-régression.

Fichier NOUVEAU : ne touche à aucun test existant. Tous les fichiers d'audit sont
sous tmp_path (jamais EVIDENCE/bundles/dispatch_audit.jsonl réel). claim_verdict:
NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import importlib.util
import io
import json
import sys
import tempfile
import time
from pathlib import Path

import pytest

from forge import audit as audit_mod
from forge import dispatch as dispatch_mod
from forge import hook_guard as hook_guard_mod
from forge.audit import (
    EVENT_AUTHORIZED,
    EVENT_EXECUTED,
    EVENT_PREPARED,
    append_spawn_event,
    check_spawn_invariant,
    sign_audit_record,
    spawn_proof,
)
from forge.driver import ForgeDriver

KEY = Path(tempfile.mkdtemp()) / "audit_key"

_HOOK_PATH = (
    Path(__file__).resolve().parents[2] / ".claude" / "hooks" / "pretool_forge_guard.py"
)


def _prepared_line(etape: str, run_id: str, attempt: int) -> str:
    # Signée avec la clé de PRODUCTION par défaut (aucun `key_file`) : le hook sous
    # test (chemin A) appelle `hook_decision`/`record_authorization` SANS `key_file`
    # explicite, exactement comme en production — la fixture doit donc être
    # vérifiable par la MÊME clé que celle que le hook utilisera réellement.
    rec = {
        "run_id": run_id, "etape": etape, "capability_role": "", "model": "",
        "provider": "", "allowed_tools": [], "ts": time.time(),
        "event": EVENT_PREPARED, "attempt": attempt, "unprofiled": False,
    }
    return json.dumps(sign_audit_record(rec)) + "\n"


def _rows(path: Path) -> list[dict]:
    return [json.loads(l) for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]


# --- forge.audit.check_spawn_invariant : le lecteur qui aurait vu le défaut -------

def test_invariant_measured_false_on_absent_audit(tmp_path):
    out = check_spawn_invariant(audit_path=tmp_path / "absent.jsonl", key_file=KEY)
    assert out["measured"] is False


def test_invariant_detects_the_measured_pacman_defect(tmp_path):
    """Reproduit EXACTEMENT le défaut mesuré (0/1418) : une ligne spawn_executed
    SANS spawn_authorized correspondante -> violation détectée."""
    audit = tmp_path / "a.jsonl"
    append_spawn_event(EVENT_EXECUTED, "s9-build", "r1", 1, audit_path=audit, key_file=KEY)
    out = check_spawn_invariant("r1", audit_path=audit, key_file=KEY)
    assert out["measured"] is True
    assert out["executed"] == 1
    assert out["authorized"] == 0
    assert out["violations"] == [{"run_id": "r1", "etape": "s9-build", "attempt": 1}]


def test_invariant_holds_when_authorized_precedes_executed(tmp_path):
    audit = tmp_path / "a.jsonl"
    append_spawn_event(EVENT_AUTHORIZED, "s9-build", "r1", 1, audit_path=audit, key_file=KEY)
    append_spawn_event(EVENT_EXECUTED, "s9-build", "r1", 1, audit_path=audit, key_file=KEY)
    out = check_spawn_invariant("r1", audit_path=audit, key_file=KEY)
    assert out["measured"] is True
    assert out["violations"] == []


def test_invariant_scoped_to_run_id_when_provided(tmp_path):
    audit = tmp_path / "a.jsonl"
    append_spawn_event(EVENT_EXECUTED, "s9-build", "other-run", 1, audit_path=audit, key_file=KEY)
    out = check_spawn_invariant("r1", audit_path=audit, key_file=KEY)
    assert out["measured"] is True
    assert out["executed"] == 0  # filtré par run_id, l'autre run n'apparaît pas
    assert out["violations"] == []


# --- (b) chemin B (headless/driver) : _record_spawn_executed écrit authorized -----

def test_driver_record_spawn_executed_writes_authorized_before_executed(tmp_path):
    audit_path = tmp_path / "a.jsonl"
    d = ForgeDriver(
        "proj", "proj-1", run_dir=tmp_path / "run", profile="patch",
        audit_path=audit_path,
    )
    d._record_spawn_executed("s9-build", 1)
    rows = _rows(audit_path)
    events = [r["event"] for r in rows]
    assert events == [EVENT_AUTHORIZED, EVENT_EXECUTED]
    for r in rows:
        assert r["etape"] == "s9-build" and r["run_id"] == "proj-1" and r["attempt"] == 1

    # et l'invariant de lecture confirme : 0 violation sur ce triplet.
    out = check_spawn_invariant("proj-1", audit_path=audit_path)
    assert out["violations"] == []
    # spawn_proof (lecteur existant) voit bien authorized ET executed désormais.
    proof = spawn_proof("proj-1", audit_path=audit_path)
    assert proof["authorized"] == 1
    assert proof["executed"] == 1


# --- (a) chemin A (interactif) : le hook PreToolUse écrit authorized --------------

def _load_hook_module():
    """Charge .claude/hooks/pretool_forge_guard.py comme un module frais (pas un
    package) — même patron que le patron documenté pour tester un script mince,
    ici poussé jusqu'au bout parce que la LIGNE MANQUANTE vivait justement dans ce
    fichier (contrairement à test_git_guard.py, où le hook mince n'a aucune
    branche propre — celui-ci en a désormais une : l'appel record_authorization)."""
    spec = importlib.util.spec_from_file_location("pretool_forge_guard_under_test", _HOOK_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


@pytest.fixture
def isolated_audit(tmp_path, monkeypatch):
    """Redirige TOUTES les résolutions de chemin d'audit par défaut (audit.py,
    dispatch.py, hook_guard.py — trois noms liés séparément, cf. leurs docstrings)
    vers un fichier tmp : le hook sous test est invoqué SANS `audit_path` explicite
    (exactement comme en production), donc rien ne doit toucher le fichier réel
    EVIDENCE/bundles/dispatch_audit.jsonl."""
    audit_path = tmp_path / "a.jsonl"
    monkeypatch.setattr(audit_mod, "DEFAULT_AUDIT", audit_path)
    monkeypatch.setattr(dispatch_mod, "DEFAULT_AUDIT", audit_path)
    monkeypatch.setattr(hook_guard_mod, "DEFAULT_AUDIT", audit_path)
    return audit_path


def _run_hook(monkeypatch, tool: str, prompt: str) -> int:
    """Payload conforme au contrat RÉEL du hook, mesuré par sonde le 2026-08-09 :
    {session_id, transcript_path, cwd, prompt_id, permission_mode, effort,
    hook_event_name, tool_name, tool_input, tool_use_id}.

    L'ancien payload à deux champs décrivait une entrée QUI N'EXISTE PAS en
    production. La couche 2 du hook (héritage d'autorité, ajoutée le 2026-08-09)
    exige `transcript_path` pour résoudre le parent : son absence produisait
    PARENT_NOT_FOUND ⇒ DENY dès que le témoin d'activation était armé. Le défaut
    était dans la FIXTURE, pas dans le hook — un test qui construit lui-même son
    entrée peut mesurer une fiction sans que rien ne le signale.

    Aucune assertion n'est modifiée : seule l'entrée cesse d'être fictive. La
    lignée est un parent `general-purpose` de profondeur 1 sous tmp jetable —
    jamais un transcript réel."""
    with tempfile.TemporaryDirectory(prefix="fx_lineage_") as tmp:
        sub = Path(tmp) / "sess" / "subagents"
        sub.mkdir(parents=True)
        pid = "a" * 17
        (sub / f"agent-{pid}.jsonl").write_text("{}\n", encoding="utf-8")
        (sub / f"agent-{pid}.meta.json").write_text(
            json.dumps({"agentType": "general-purpose",
                        "toolUseId": "toolu_FX", "spawnDepth": 1}),
            encoding="utf-8")
        payload = {
            "tool_name": tool,
            "transcript_path": str(sub / f"agent-{pid}.jsonl"),
            "tool_use_id": "toolu_FX",
            "tool_input": {"prompt": prompt, "subagent_type": "Explore"},
        }
        monkeypatch.setattr(sys, "stdin", io.StringIO(json.dumps(payload)))
        mod = _load_hook_module()
        return mod.main()


def test_hook_authorizes_and_writes_spawn_authorized(tmp_path, monkeypatch, isolated_audit):
    """Bout en bout : un dispatch préparé + le hook l'AUTORISE -> le fichier
    d'audit gagne une ligne spawn_authorized pour le MÊME triplet. C'est la preuve
    que la ligne ajoutée dans pretool_forge_guard.py est bien câblée, pas
    seulement présente dans le source."""
    isolated_audit.write_text(_prepared_line("s9-build", "r1", 1), encoding="utf-8")
    code = _run_hook(monkeypatch, "Task", "... FORGE_DISPATCH:s9-build:r1:1 ...")
    assert code == 0

    rows = _rows(isolated_audit)
    events = [r.get("event") for r in rows]
    assert events == [EVENT_PREPARED, EVENT_AUTHORIZED]
    assert rows[1]["etape"] == "s9-build" and rows[1]["run_id"] == "r1" and rows[1]["attempt"] == 1


def test_hook_refused_spawn_does_not_write_authorized(tmp_path, monkeypatch, isolated_audit):
    """Un spawn REFUSÉ (aucun dispatch préparé pour ce triplet) ne doit jamais
    écrire spawn_authorized — l'écriture suit strictement la décision, jamais
    l'inverse."""
    code = _run_hook(monkeypatch, "Task", "... FORGE_DISPATCH:s9-build:r1:1 ...")
    assert code == 2
    assert not isolated_audit.exists() or _rows(isolated_audit) == []


def test_hook_non_forge_spawn_does_not_write_authorized(tmp_path, monkeypatch, isolated_audit):
    """Hors périmètre Forge (pas de marqueur) : fail-open, ET aucune écriture
    d'audit (rien à autoriser — il n'y a pas de dispatch Forge)."""
    code = _run_hook(monkeypatch, "Task", "prompt quelconque sans marqueur")
    assert code == 0
    assert not isolated_audit.exists() or _rows(isolated_audit) == []
