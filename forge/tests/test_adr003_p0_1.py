# -*- coding: utf-8 -*-
"""ADR-003 lot 1 — tests des 5 P0, un bloc par sous-lot, causalement attribués.

Source : docs/adr/ADR-003-forge-workflow-coherence-audit.md (GO Pierre 2026-08-15).
Nouveau fichier : n'altère aucun test existant (zone protégée respectée).
"""
from __future__ import annotations

from pathlib import Path

from forge.dispatch import prepare_dispatch
from forge.hook_guard import check_spawn, marker_key

ETAPE = "s4-archi"


# ---------------------------------------------------------------------------
# P0-1 — le marqueur rendu par la porte porte l'attempt (triplet D4 complet).
# Avant : contract._render_prompt émettait FORGE_DISPATCH:<etape>:<run_id> (2
# champs) en PREMIÈRE position dans le prompt ; MARKER.search s'arrêtant à la
# première occurrence, la clé retombait sur le couple → dès 2 spawn_prepared
# pour la même étape, ambiguïté/replay → toute re-tentative était refusée.
# ---------------------------------------------------------------------------

def test_p0_1_marqueur_de_la_porte_porte_le_triplet(tmp_path: Path):
    audit = tmp_path / "audit.jsonl"
    payload = prepare_dispatch(ETAPE, "run-adr003", audit_path=audit,
                               run_dir=tmp_path, attempt=1)
    assert marker_key(payload.prompt) == (ETAPE, "run-adr003", 1), (
        "le marqueur rendu par la porte doit porter l'attempt transmis"
    )


def test_p0_1_la_retentative_redevient_spawnable(tmp_path: Path):
    """Scénario exact du P0 : deux préparations successives (attempt 1 puis 2)
    de la MÊME étape du MÊME run. Avant le correctif, le 2e prompt portait un
    marqueur 2 champs matchant les DEUX lignes d'audit → refus ambiguïté/replay.
    Après : chaque prompt porte son triplet, chaque triplet compte exactement
    UNE ligne d'audit → les deux spawns sont autorisés."""
    audit = tmp_path / "audit.jsonl"
    p1 = prepare_dispatch(ETAPE, "run-adr003", audit_path=audit,
                          run_dir=tmp_path, attempt=1)
    p2 = prepare_dispatch(ETAPE, "run-adr003", audit_path=audit,
                          run_dir=tmp_path, attempt=2)

    allow1, reason1 = check_spawn(p1.prompt, audit_path=audit)
    allow2, reason2 = check_spawn(p2.prompt, audit_path=audit)
    assert allow1, f"tentative 1 refusée : {reason1}"
    assert allow2, f"tentative 2 refusée : {reason2}"


def test_p0_1_defaut_attempt_zero_retrocompatible(tmp_path: Path):
    """Sans attempt explicite (appels historiques, dry-run) : marqueur :0, même
    convention que DispatchRecord.attempt — le spawn unique reste autorisé."""
    audit = tmp_path / "audit.jsonl"
    payload = prepare_dispatch(ETAPE, "run-adr003-z", audit_path=audit,
                               run_dir=tmp_path)
    assert marker_key(payload.prompt) == (ETAPE, "run-adr003-z", 0)
    allow, reason = check_spawn(payload.prompt, audit_path=audit)
    assert allow, reason


