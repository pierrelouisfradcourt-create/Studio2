"""Câblage additif de `forge.reasoning_observability` dans `forge.dispatch
.prepare_dispatch` — ferme le risque de dormance (le maillon 1 aurait sinon un
module testé mais AUCUN consommateur de production ; un vrai dispatch écrit
maintenant la trace, sans y dépendre pour rien). Patron identique à
`test_dispatch_tool_observability_wiring.py` (précédent immédiat, même corps de
fonction, même garantie).

Neutralité exigée (doctrine §6.2) : rejouer le même dispatch doit rendre le
MÊME `DispatchPayload` et la MÊME ligne d'audit — avec un fichier de trace en
plus, rien d'autre. Best-effort strict.
"""
from __future__ import annotations

import json

import pytest

from forge import reasoning_observability as ro
from forge.dispatch import prepare_dispatch


def test_prepare_dispatch_ecrit_la_trace_reasoning_observability(tmp_path):
    audit = tmp_path / "audit.jsonl"
    run_dir = tmp_path / "run"
    prepare_dispatch("s4-archi", run_id="run-reasoning-1", audit_path=audit, run_dir=run_dir)

    recs = ro.read_reasoning_observability_records(run_dir, "s4-archi")
    assert len(recs) == 1
    rec = recs[0]
    assert rec["run_id"] == "run-reasoning-1"
    assert rec["etape"] == "s4-archi"
    # s4-archi -> capability_role 'architect' -> Opus, reasoning: high (roles.yaml réel).
    assert rec["capability_role"] == "architect"
    assert rec["declared_status"] == "RESOLVED"
    assert rec["declared"]["kind"] == ro.DECLARED_KIND_CLI_COMPATIBLE
    assert rec["declared"]["raw"] == "high"
    assert ro.verify_reasoning_observability_record(rec) is True  # clé par défaut (.forge_key)


def test_neutralite_payload_et_audit_inchanges(tmp_path):
    """Preuve de neutralité (doctrine §6.2) : le payload retourné et la ligne
    d'audit signée sont EXACTEMENT ce qu'ils étaient avant ce chantier — le
    nouveau bloc n'ajoute qu'un fichier, jamais un effet sur la décision."""
    audit = tmp_path / "audit.jsonl"
    run_dir = tmp_path / "run"
    payload = prepare_dispatch("s4-archi", run_id="run-neutral-r", audit_path=audit, run_dir=run_dir)

    assert payload.model  # runtime résolu comme avant (Opus, indépendant de ce chantier)
    audit_rec = json.loads(audit.read_text(encoding="utf-8").strip())
    assert audit_rec["etape"] == "s4-archi"
    assert audit_rec["run_id"] == "run-neutral-r"
    assert audit_rec["model"] == payload.model
    assert audit_rec["allowed_tools"] == list(payload.allowed_tools)


def test_panne_du_bloc_reasoning_observability_ne_casse_pas_le_dispatch(tmp_path, monkeypatch):
    """Best-effort : si `append_reasoning_observability_record` lève,
    `prepare_dispatch` doit quand même retourner un payload valide et avoir
    écrit son audit — un dispatch déjà validé n'est jamais cassé par une mesure
    advisory."""
    def _boom(*args, **kwargs):
        raise RuntimeError("panne simulée du bloc advisory")

    monkeypatch.setattr(ro, "append_reasoning_observability_record", _boom)

    audit = tmp_path / "audit.jsonl"
    run_dir = tmp_path / "run"
    payload = prepare_dispatch("s4-archi", run_id="run-panne-r", audit_path=audit, run_dir=run_dir)
    assert payload.model
    assert audit.exists()
    assert ro.read_reasoning_observability_records(run_dir, "s4-archi") == ()


def test_deux_dispatches_de_la_meme_etape_accumulent_deux_lignes(tmp_path):
    audit = tmp_path / "audit.jsonl"
    run_dir = tmp_path / "run"
    prepare_dispatch("s9-build", run_id="run-a", audit_path=audit, run_dir=run_dir)
    prepare_dispatch("s9-build", run_id="run-b", audit_path=audit, run_dir=run_dir)
    recs = ro.read_reasoning_observability_records(run_dir, "s9-build")
    assert {r["run_id"] for r in recs} == {"run-a", "run-b"}


def test_unknown_step_raises_avant_toute_ecriture_de_trace(tmp_path):
    run_dir = tmp_path / "run"
    with pytest.raises(FileNotFoundError):
        prepare_dispatch("s99-inexistant", run_id="x", audit_path=tmp_path / "a.jsonl",
                         run_dir=run_dir)
    assert ro.read_reasoning_observability_records(run_dir, "s99-inexistant") == ()


def test_etape_deterministe_capability_role_deterministic_not_applicable(tmp_path):
    """Câblage sur une étape NON-LLM (s12-verdict, capability_role
    'deterministic') : la trace s'écrit quand même, avec `declared.kind ==
    not_applicable` — le modèle déterministe n'a pas de session `claude -p`,
    ce n'est PAS une absence de mesure (NOT_MEASURED serait faux ici : on A
    mesuré, la réponse est 'pas applicable')."""
    audit = tmp_path / "audit.jsonl"
    run_dir = tmp_path / "run"
    prepare_dispatch("s12-verdict", run_id="run-det", audit_path=audit, run_dir=run_dir)
    recs = ro.read_reasoning_observability_records(run_dir, "s12-verdict")
    assert len(recs) == 1
    assert recs[0]["declared"]["kind"] == ro.DECLARED_KIND_NOT_APPLICABLE
