"""Oracle du pont Context Manifest -> lesson (lot A, réparation 2).

Post-mortem pacman (studio_brain/journal/2026-08-07_postmortem_pacman_forge.md
§1/§2/§6.2) : les manifests `EVIDENCE/runs/pacman-v{3,4,5,6}/context/*.manifest.
jsonl` portent `reason.problem`/`reason.root_cause` (root causes P1-P6, signées
HMAC) jamais promues en leçons — la boucle Run -> FailureEvent -> Lesson ->
Doctrine s'arrêtait au 2e maillon (0 promotion, registres intacts). Ce fichier
prouve `forge.learning_memory.promote_manifest_lessons` sur des fixtures
synthétiques PUIS sur le corpus RÉEL pacman-v3 (lecture seule).

Fichier NOUVEAU : ne touche à aucun test existant. Toute ÉCRITURE est isolée sous
`tmp_path` (jamais `EVIDENCE/reports/lessons.jsonl` réel). Les lectures du corpus réel
pacman sont EN LECTURE SEULE, avec assertion de non-modification. NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import json
import logging
from pathlib import Path

import pytest

from forge import learning_memory as lm
from forge.driver import ForgeDriver

_REPO_ROOT = Path(__file__).resolve().parents[2]


def _write_manifest(run_dir: Path, etape: str, rows: list[dict]) -> Path:
    ctx = run_dir / "context"
    ctx.mkdir(parents=True, exist_ok=True)
    path = ctx / f"{etape}.manifest.jsonl"
    with open(path, "a", encoding="utf-8") as fh:
        for row in rows:
            fh.write(json.dumps(row, ensure_ascii=False) + "\n")
    return path


def _dispatch_row(etape: str, run_id: str, reason: dict) -> dict:
    return {
        "schema": "forge.context_manifest.v1", "kind": "dispatch", "etape": etape,
        "run_id": run_id, "activation": 1, "reason": reason, "ts": 0.0,
    }


# --- promote_manifest_lessons : fixtures synthétiques ------------------------------

def test_promotes_a_lesson_from_problem_and_root_cause(tmp_path):
    run_dir = tmp_path / "run"
    _write_manifest(run_dir, "s9-build-godot-standard", [
        _dispatch_row("s9-build-godot-standard", "pacman-v3-20260806", {
            "action": "s9-build-godot-standard",
            "problem": "6 ecarts produit mesures",
            "root_cause": "P1 keycode brut non traduit",
        }),
    ])
    lessons_path = tmp_path / "lessons.jsonl"
    written = lm.promote_manifest_lessons(run_dir, lessons_path=lessons_path)

    assert len(written) == 1
    rec = written[0]
    assert rec["schema"] == lm.LESSON_SCHEMA
    assert rec["status"] == lm.LESSON_STATUS_CANDIDATE
    assert "6 ecarts produit mesures" in rec["statement"]
    assert "P1 keycode brut non traduit" in rec["statement"]
    assert rec["supporting_runs"] == ["pacman-v3-20260806"]

    on_disk = lm.fold_lessons(lessons_path)
    assert rec["lesson_id"] in on_disk


def test_rows_without_problem_or_root_cause_are_ignored(tmp_path):
    """La majorité des lignes de Context Manifest (`reason` sans problem/root_cause,
    ex. NOT_TRANSMITTED d'un enchaînement mécanique) ne produisent AUCUNE leçon —
    ce n'est pas une erreur, c'est le cas normal."""
    run_dir = tmp_path / "run"
    _write_manifest(run_dir, "s3-decompo", [
        _dispatch_row("s3-decompo", "r1", {"status": "NOT_TRANSMITTED", "action": "s3-decompo"}),
        _dispatch_row("s3-decompo", "r1", {"action": "s3-decompo"}),  # ni problem ni root_cause
    ])
    written = lm.promote_manifest_lessons(run_dir, lessons_path=tmp_path / "lessons.jsonl")
    assert written == []


def test_idempotent_second_call_writes_nothing_new(tmp_path):
    run_dir = tmp_path / "run"
    _write_manifest(run_dir, "s9-build-godot-standard", [
        _dispatch_row("s9-build-godot-standard", "pacman-v4-20260806", {
            "problem": "4 ecarts au playtest", "root_cause": "P1 aucun emetteur audio",
        }),
    ])
    lessons_path = tmp_path / "lessons.jsonl"
    first = lm.promote_manifest_lessons(run_dir, lessons_path=lessons_path)
    second = lm.promote_manifest_lessons(run_dir, lessons_path=lessons_path)

    assert len(first) == 1
    assert second == []  # rien de nouveau : idempotence
    lines = [l for l in lessons_path.read_text(encoding="utf-8").splitlines() if l.strip()]
    assert len(lines) == 1  # aucune ligne dupliquée sur disque


def test_idempotent_across_two_runs_sharing_the_same_content(tmp_path):
    """Deux MANIFESTS DISTINCTS (deux runs) portant le MÊME couple problem/root_cause
    convergent sur le même lesson_id (make_manifest_lesson_id est dérivé du
    CONTENU) — 2e run : la leçon gagne un supporting_run de PLUS, pas un doublon."""
    lessons_path = tmp_path / "lessons.jsonl"
    reason = {"problem": "meme probleme", "root_cause": "meme cause"}
    run_a = tmp_path / "run-a"
    run_b = tmp_path / "run-b"
    _write_manifest(run_a, "s9-build", [_dispatch_row("s9-build", "run-a-id", reason)])
    _write_manifest(run_b, "s9-build", [_dispatch_row("s9-build", "run-b-id", reason)])

    written_a = lm.promote_manifest_lessons(run_a, lessons_path=lessons_path)
    written_b = lm.promote_manifest_lessons(run_b, lessons_path=lessons_path)
    assert len(written_a) == 1
    assert written_b == []  # même lesson_id déjà connu -> pas de ré-émission

    on_disk = lm.fold_lessons(lessons_path)
    assert len(on_disk) == 1
    assert written_a[0]["supporting_runs"] == ["run-a-id"]


def test_multiple_distinct_causes_promote_multiple_lessons(tmp_path):
    run_dir = tmp_path / "run"
    _write_manifest(run_dir, "s9-build-godot-standard", [
        _dispatch_row("s9-build-godot-standard", "r1", {
            "problem": "probleme A", "root_cause": "cause A"}),
    ])
    _write_manifest(run_dir, "s6-redteam-plan", [
        _dispatch_row("s6-redteam-plan", "r1", {
            "problem": "probleme B", "root_cause": "cause B"}),
    ])
    written = lm.promote_manifest_lessons(run_dir, lessons_path=tmp_path / "lessons.jsonl")
    assert {w["lesson_id"] for w in written}.__len__() == 2
    statements = " | ".join(w["statement"] for w in written)
    assert "probleme A" in statements and "probleme B" in statements


def test_missing_run_dir_or_context_dir_yields_no_lessons_not_a_crash(tmp_path):
    written = lm.promote_manifest_lessons(tmp_path / "absent", lessons_path=tmp_path / "l.jsonl")
    assert written == []


def test_make_manifest_lesson_id_is_deterministic_and_content_derived():
    a = lm.make_manifest_lesson_id("s9-build", "p", "c")
    b = lm.make_manifest_lesson_id("s9-build", "p", "c")
    c = lm.make_manifest_lesson_id("s9-build", "p", "different")
    assert a == b
    assert a != c


# --- preuve : la leçon promue est bien restituée par premortem_lessons -------------

def test_promoted_lesson_is_surfaced_by_premortem_lessons(tmp_path):
    """La preuve exigée par la mission : une leçon promue par ce pont est bien
    RELUE par `premortem_lessons` (même fichier) — la boucle apprentissage se
    referme réellement, pas seulement « une ligne de plus dans un fichier »."""
    run_dir = tmp_path / "run"
    _write_manifest(run_dir, "s9-build-godot-standard", [
        _dispatch_row("s9-build-godot-standard", "pacman-v6-20260806", {
            "problem": "mode de jeu mesure INERTE",
            "root_cause": "producteur sans consommateur",
        }),
    ])
    lessons_path = tmp_path / "lessons.jsonl"
    lm.promote_manifest_lessons(run_dir, lessons_path=lessons_path)

    lines = lm.premortem_lessons(lessons_path=lessons_path, include_legacy=False, limit=10)
    assert any("producteur sans consommateur" in l for l in lines)


# --- corpus RÉEL pacman-v3 : lecture seule ------------------------------------------

def test_real_pacman_v3_manifest_promotes_at_least_one_lesson(tmp_path):
    """Lecture seule du corpus RÉEL (EVIDENCE/runs/pacman-v3/context/) — la fixture
    exacte citée par le post-mortem. Écrit UNIQUEMENT sous tmp_path."""
    # HumanGate HG2/HG3 (Pierre, 2026-09-05, A+A) : corpus HISTORIQUE V1 (lab/forge_runs/pacman-v3,
    # HEAD V1 3a9ef2d3, commit b22a9804), ré-ancré sous EVIDENCE/_V1_FIXTURES/ avec PROVENANCE_V1.md.
    # Ce n'est PAS une preuve V2 : témoin de traçabilité de la leçon « keycode brut », pas de capacité
    # V2 (celle-ci est démontrée par runm_breakout / v2_breakout_slice_r1). Jamais sous EVIDENCE/runs/.
    run_dir = _REPO_ROOT / "EVIDENCE" / "_V1_FIXTURES" / "runs" / "pacman-v3"
    context_dir = run_dir / "context"
    before = sorted(context_dir.glob("*.jsonl"))
    before_sizes = {p: p.stat().st_size for p in before}

    lessons_path = tmp_path / "lessons_pacman_v3.jsonl"
    written = lm.promote_manifest_lessons(run_dir, lessons_path=lessons_path)

    assert len(written) >= 1
    assert any("keycode brut" in w["statement"] for w in written)

    # non-modification du corpus réel
    after = sorted(context_dir.glob("*.jsonl"))
    assert after == before
    for p in after:
        assert p.stat().st_size == before_sizes[p]


# --- driver : appel best-effort NON silencieux en fin de run -----------------------

def test_driver_promotes_manifest_lessons_at_end_of_run(tmp_path):
    """`ForgeDriver._promote_manifest_lessons_best_effort` promeut réellement une
    leçon depuis `run_dir/context/` quand elle est appelée (même chemin que la fin
    d'un run réel, cf. `run()`)."""
    run_dir = tmp_path / "run"
    lessons_path = tmp_path / "lessons.jsonl"
    d = ForgeDriver(
        "proj", "proj-1", run_dir=run_dir, profile="micro", lessons_path=lessons_path,
    )
    _write_manifest(run_dir, "s9-build", [
        _dispatch_row("s9-build", "proj-1", {
            "problem": "probleme driver", "root_cause": "cause driver"}),
    ])
    d._promote_manifest_lessons_best_effort()

    on_disk = lm.fold_lessons(lessons_path)
    assert len(on_disk) == 1
    assert any("probleme driver" in v["statement"] for v in on_disk.values())


def test_driver_promotion_failure_is_logged_not_silent(tmp_path, monkeypatch, caplog):
    """Exigence explicite du lot : un échec de promotion est JOURNALISÉ (jamais
    avalé sans trace), contrairement au reste des connecteurs best-effort de cette
    classe qui restent silencieux par conception."""
    import forge.driver as driver_mod

    def boom(_run_dir, lessons_path=None, **kw):
        raise RuntimeError("manifest illisible (simulé)")

    monkeypatch.setattr(driver_mod, "promote_manifest_lessons", boom)
    d = ForgeDriver("proj", "proj-1", run_dir=tmp_path / "run", profile="micro")
    with caplog.at_level(logging.WARNING, logger="forge.driver"):
        d._promote_manifest_lessons_best_effort()  # ne lève jamais
    assert any("promotion manifest" in r.message for r in caplog.records)


def test_driver_promotion_success_is_a_noop_when_nothing_to_promote(tmp_path):
    """Aucun manifest qualifiant (run_dir vide) : la méthode ne lève pas, n'écrit
    rien — comportement silencieux normal (pas un échec)."""
    lessons_path = tmp_path / "lessons.jsonl"
    d = ForgeDriver(
        "proj", "proj-1", run_dir=tmp_path / "run", profile="micro",
        lessons_path=lessons_path,
    )
    d._promote_manifest_lessons_best_effort()
    assert not lessons_path.exists() or lm.fold_lessons(lessons_path) == {}
