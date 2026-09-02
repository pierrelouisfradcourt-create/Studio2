"""Oracle du garde de spawn Forge (hook dur, connecteur 2).

Un spawn de sous-agent portant le marqueur FORGE_DISPATCH:<etape>:<run_id> n'est
autorisé que si un dispatch validé correspondant existe dans l'audit. Sans
marqueur (spawn hors Forge) => toujours autorisé (le hook ne gêne pas le reste).
"""
import json
import tempfile
from pathlib import Path

import forge.hook_guard as hg
from forge.dispatch import sign_audit_record
from forge.hook_guard import check_spawn, hook_decision

KEY = Path(tempfile.mkdtemp()) / "audit_key"


def _signed_line(rec: dict) -> str:
    """Une ligne d'audit SIGNÉE avec la clé de test (comme le vrai _append_audit)."""
    return json.dumps(sign_audit_record(rec, key_file=KEY)) + "\n"


def test_non_forge_spawn_passe(tmp_path):
    allow, reason = check_spawn("Analyse ce fichier stp", audit_path=tmp_path / "a.jsonl")
    assert allow is True


def test_forge_spawn_sans_dispatch_bloque(tmp_path):
    audit = tmp_path / "a.jsonl"
    audit.write_text("", encoding="utf-8")
    allow, reason = check_spawn("... FORGE_DISPATCH:s4-archi:run1 ...", audit_path=audit)
    assert allow is False
    assert "s4-archi" in reason


def test_forge_spawn_avec_dispatch_signe_passe(tmp_path):
    audit = tmp_path / "a.jsonl"
    audit.write_text(_signed_line({"etape": "s4-archi", "run_id": "run1"}), encoding="utf-8")
    allow, reason = check_spawn("cadre... FORGE_DISPATCH:s4-archi:run1 ...fin",
                                audit_path=audit, key_file=KEY)
    assert allow is True


def test_forge_spawn_ligne_forgee_non_signee_bloque(tmp_path):
    """#1b : une ligne d'audit écrite à la main SANS signature valide est rejetée."""
    audit = tmp_path / "a.jsonl"
    audit.write_text(json.dumps({"etape": "s9-build", "run_id": "PWNED"}) + "\n", encoding="utf-8")
    allow, reason = check_spawn("FORGE_DISPATCH:s9-build:PWNED", audit_path=audit, key_file=KEY)
    assert allow is False
    assert "non signée" in reason or "altérée" in reason


def test_forge_spawn_signature_mauvaise_cle_bloque(tmp_path):
    audit = tmp_path / "a.jsonl"
    audit.write_text(_signed_line({"etape": "s4-archi", "run_id": "run1"}), encoding="utf-8")
    other = Path(tempfile.mkdtemp()) / "other"
    allow, _ = check_spawn("FORGE_DISPATCH:s4-archi:run1", audit_path=audit, key_file=other)
    assert allow is False


def test_forge_spawn_mauvais_run_bloque(tmp_path):
    audit = tmp_path / "a.jsonl"
    audit.write_text(_signed_line({"etape": "s4-archi", "run_id": "AUTRE"}), encoding="utf-8")
    allow, reason = check_spawn("FORGE_DISPATCH:s4-archi:run1", audit_path=audit, key_file=KEY)
    assert allow is False


# --- hook_decision : fail-OPEN hors périmètre, fail-CLOSED sur périmètre Forge ---

def test_hook_decision_outil_hors_perimetre_autorise():
    code, _ = hook_decision("Read", "FORGE_DISPATCH:s4-archi:run1")
    assert code == 0


def test_hook_decision_sans_marqueur_autorise(tmp_path):
    code, _ = hook_decision("Task", "analyse ce fichier", audit_path=tmp_path / "a.jsonl")
    assert code == 0


def test_hook_decision_marqueur_sans_dispatch_bloque(tmp_path):
    audit = tmp_path / "a.jsonl"
    audit.write_text("", encoding="utf-8")
    code, reason = hook_decision("Task", "x FORGE_DISPATCH:s4-archi:run1 y", audit_path=audit)
    assert code == 2


def test_hook_decision_marqueur_avec_dispatch_signe_autorise(tmp_path):
    audit = tmp_path / "a.jsonl"
    audit.write_text(_signed_line({"etape": "s4-archi", "run_id": "run1"}), encoding="utf-8")
    code, _ = hook_decision("Task", "FORGE_DISPATCH:s4-archi:run1", audit_path=audit, key_file=KEY)
    assert code == 0


def test_hook_decision_fail_closed_si_garde_plante_en_perimetre_forge(monkeypatch):
    """Marqueur Forge présent + garde qui lève => REFUS (2), pas fail-open silencieux."""
    def boom(*a, **k):
        raise RuntimeError("garde cassé")
    monkeypatch.setattr(hg, "check_spawn", boom)
    code, reason = hook_decision("Task", "FORGE_DISPATCH:s4-archi:run1")
    assert code == 2
    assert "fail-closed" in reason.lower()


def test_hook_decision_hors_perimetre_reste_fail_open_si_garde_plante(monkeypatch):
    """Sans marqueur, une erreur du garde ne doit PAS bloquer (fail-open hors scope)."""
    def boom(*a, **k):
        raise RuntimeError("garde cassé")
    monkeypatch.setattr(hg, "check_spawn", boom)
    code, _ = hook_decision("Task", "aucun marqueur ici")
    assert code == 0
