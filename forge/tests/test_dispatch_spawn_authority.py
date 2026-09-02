"""Oracle Phase 2a — DISPATCH_SPAWN_AUTHORITY_V1 : ferme D1 (appartenance profil)
et D4 (unicité du spawn), sans toucher D2 (spawn_executed / PostToolUse, Phase 2b).

D1 : `prepare_dispatch(..., profile=...)` refuse un contrat hors de son profil
(`ContractIncomplete`), sauf dérogation tracée `allow_unprofiled=True` (`unprofiled: true`
dans le corps SIGNÉ). `profile=None` => comportement historique inchangé.

D4 : le marqueur devient `FORGE_DISPATCH:<etape>:<run_id>:<attempt>` ; le hook COMPTE
les lignes d'audit valides-HMAC au triplet — count 1 allow, 0 refus, >=2 refus. Les
retries légitimes (attempts distincts d'un même couple) restent chacun un count 1.
"""
import json
import tempfile
from pathlib import Path

import pytest

from forge.contract import ContractIncomplete
from forge.dispatch import (
    prepare_dispatch,
    profile_allowed_for_contract,
    sign_audit_record,
)
from forge.hook_guard import check_spawn, hook_decision

KEY = Path(tempfile.mkdtemp()) / "audit_key"


def _signed_line(rec: dict) -> str:
    return json.dumps(sign_audit_record(rec, key_file=KEY)) + "\n"


# --- D1 : appartenance profil -------------------------------------------------

def test_profile_allowed_pure_function():
    """Fonction pure adossée à l'unique source (order_for_profile)."""
    assert profile_allowed_for_contract("s9-build-standard", "standard") is True
    assert profile_allowed_for_contract("s9-build-godot", "standard") is False
    assert profile_allowed_for_contract("s4-archi", "full") is True
    assert profile_allowed_for_contract("s9-build-godot", "full") is False


def test_d1_hors_profil_leve(tmp_path):
    """s9-build-godot n'est dans AUCUN profil -> profile='full' refuse le dispatch."""
    with pytest.raises(ContractIncomplete) as exc:
        prepare_dispatch("s9-build-godot", "t", profile="full",
                         audit_path=tmp_path / "a.jsonl")
    assert "s9-build-godot" in str(exc.value) and "full" in str(exc.value)


def test_d1_allow_unprofiled_passe_et_trace_dans_le_corps_signe(tmp_path):
    """La dérogation passe ET écrit `unprofiled: true` dans le corps SIGNÉ (infalsifiable)."""
    audit = tmp_path / "a.jsonl"
    prepare_dispatch("s9-build-godot", "t", profile="full",
                     allow_unprofiled=True, audit_path=audit)
    rec = json.loads(audit.read_text(encoding="utf-8").strip())
    assert rec["unprofiled"] is True
    # `unprofiled` fait partie du corps couvert par le HMAC : la ligne est vérifiable.
    from forge.dispatch import verify_audit_line
    assert verify_audit_line(rec) is True


def test_d1_contrat_dans_le_profil_passe(tmp_path):
    """Un contrat MEMBRE de son profil passe sans dérogation, unprofiled reste false."""
    audit = tmp_path / "a.jsonl"
    prepare_dispatch("s9-build-standard", "t", profile="standard", audit_path=audit)
    rec = json.loads(audit.read_text(encoding="utf-8").strip())
    assert rec["unprofiled"] is False


def test_d1_profile_none_est_retrocompatible(tmp_path):
    """profile=None => AUCUN contrôle : même une étape hors-profil passe (comportement
    historique strictement inchangé pour tout appelant qui ne passe pas `profile`)."""
    audit = tmp_path / "a.jsonl"
    payload = prepare_dispatch("s9-build-godot", "t", audit_path=audit)
    assert payload.model
    rec = json.loads(audit.read_text(encoding="utf-8").strip())
    assert rec["unprofiled"] is False


# --- D4 : unicité du spawn (triplet etape/run_id/attempt) ---------------------

def test_d4_retries_preserves_chaque_attempt_est_count_1(tmp_path):
    """LE test qui compte : 3 tentatives (attempt 1,2,3) du MÊME couple
    (s9-build-standard, pong-01) => 3 lignes DISTINCTES ; le hook rend `allow` pour
    chacune (chaque triplet = count 1). Reproduit le cas réel des 7 lignes SANS le casser."""
    audit = tmp_path / "a.jsonl"
    for att in (1, 2, 3):
        prepare_dispatch("s9-build-standard", "pong-01", profile="standard",
                         attempt=att, audit_path=audit)
    lignes = audit.read_text(encoding="utf-8").strip().splitlines()
    assert len(lignes) == 3
    # Chaque marqueur triplet est accepté (count 1), key par défaut du repo.
    for att in (1, 2, 3):
        marker = f"FORGE_DISPATCH:s9-build-standard:pong-01:{att}"
        allow, reason = check_spawn(marker, audit_path=audit)
        assert allow is True, f"attempt {att} refusé: {reason}"


def test_d4_triplet_unique_allow(tmp_path):
    audit = tmp_path / "a.jsonl"
    audit.write_text(_signed_line({"etape": "s9-build", "run_id": "r", "attempt": 2}),
                     encoding="utf-8")
    allow, _ = check_spawn("FORGE_DISPATCH:s9-build:r:2", audit_path=audit, key_file=KEY)
    assert allow is True


def test_d4_zero_ligne_refuse(tmp_path):
    """0 dispatch pour ce triplet -> refus."""
    audit = tmp_path / "a.jsonl"
    audit.write_text(_signed_line({"etape": "s9-build", "run_id": "r", "attempt": 1}),
                     encoding="utf-8")
    allow, reason = check_spawn("FORGE_DISPATCH:s9-build:r:2", audit_path=audit, key_file=KEY)
    assert allow is False
    assert "aucun dispatch" in reason


def test_d4_deux_lignes_meme_triplet_refuse_replay(tmp_path):
    """2 lignes valides au MÊME triplet -> ambiguïté/replay, refus (count 2)."""
    audit = tmp_path / "a.jsonl"
    audit.write_text(
        _signed_line({"etape": "s9-build", "run_id": "r", "attempt": 1})
        + _signed_line({"etape": "s9-build", "run_id": "r", "attempt": 1}),
        encoding="utf-8",
    )
    allow, reason = check_spawn("FORGE_DISPATCH:s9-build:r:1", audit_path=audit, key_file=KEY)
    assert allow is False
    assert "ambigu" in reason.lower() or "replay" in reason.lower()


def test_d4_ne_matche_pas_sur_couple_seul_quand_attempt_fourni(tmp_path):
    """Deux attempts distincts d'un même couple ne doivent PAS se compter ensemble :
    un marqueur triplet attempt=1 ne voit QUE la ligne attempt=1 (sinon les retries
    casseraient). Ici 2 attempts distincts -> chaque triplet reste count 1 -> allow."""
    audit = tmp_path / "a.jsonl"
    audit.write_text(
        _signed_line({"etape": "s9-build", "run_id": "r", "attempt": 1})
        + _signed_line({"etape": "s9-build", "run_id": "r", "attempt": 2}),
        encoding="utf-8",
    )
    for att in (1, 2):
        allow, _ = check_spawn(f"FORGE_DISPATCH:s9-build:r:{att}", audit_path=audit, key_file=KEY)
        assert allow is True


def test_d4_ancien_marqueur_2_champs_toujours_reconnu(tmp_path):
    """Rétro-compat : un marqueur 2-champs (sans attempt) + 1 ligne historique -> allow."""
    audit = tmp_path / "a.jsonl"
    audit.write_text(_signed_line({"etape": "s4-archi", "run_id": "run1"}), encoding="utf-8")
    allow, _ = check_spawn("FORGE_DISPATCH:s4-archi:run1", audit_path=audit, key_file=KEY)
    assert allow is True


# --- fail-open PRÉSERVÉ (critique) --------------------------------------------

def test_fail_open_task_sans_marqueur():
    code, _ = hook_decision("Task", "prompt sans marqueur")
    assert code == 0


def test_fail_open_outil_non_task():
    code, _ = hook_decision("Read", "FORGE_DISPATCH:s4-archi:run1:1")
    assert code == 0


# --- intégration driver -> hook (marqueur 3-champs produit par le driver) -----

def test_integration_marqueur_driver_3_champs_accepte_par_le_hook(tmp_path):
    """Le driver écrit son audit via prepare_dispatch(attempt=N) ET pose le marqueur
    `FORGE_DISPATCH:{etape}:{run_id}:{N}`. On prouve que le marqueur du driver, appliqué
    au hook_decision (chemin de production), rend `allow` (0) pour la même clé.
    Reproduit la corrélation attempt driver<->hook de bout en bout."""
    audit = tmp_path / "a.jsonl"
    etape, run_id, attempt = "s9-build-standard", "pong-42", 1
    # étape driver : prepare_dispatch avec l'attempt du compteur `entry["attempts"]`.
    prepare_dispatch(etape, run_id, profile="standard", attempt=attempt, audit_path=audit)
    # marqueur exactement comme le construit driver.py (_run_llm, dispatch_marker).
    marker = f"FORGE_DISPATCH:{etape}:{run_id}:{attempt}"
    code, reason = hook_decision("Task", f"... {marker} ...", audit_path=audit)
    assert code == 0, reason
    # et un attempt jamais dispatché est refusé (preuve que la clé porte bien l'attempt).
    code2, _ = hook_decision("Task", f"FORGE_DISPATCH:{etape}:{run_id}:2", audit_path=audit)
    assert code2 == 2
