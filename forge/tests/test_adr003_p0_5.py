# -*- coding: utf-8 -*-
"""ADR-003 lot 1 — tests des 5 P0, un bloc par sous-lot, causalement attribués.

Source : docs/adr/ADR-003-forge-workflow-coherence-audit.md (GO Pierre 2026-08-15).
Nouveau fichier : n'altère aucun test existant (zone protégée respectée).
"""
from __future__ import annotations

from pathlib import Path
# ---------------------------------------------------------------------------
# P0-5 — les leçons sont triées par RÉCENCE (ts écrit, jamais une horloge de
# lecture) puis par id. Avant : tri alphabétique seul + limit=5 → les leçons
# `manifest-*` du post-mortem pacman (les plus récentes, index 21-26/27)
# n'étaient JAMAIS injectées dans un run. Test de consommation : une leçon
# récente DOIT apparaître dans la sortie premortem.
# ---------------------------------------------------------------------------

def _corpus_style_reel(tmp_path: Path):
    """26 leçons anciennes `forge.*` + 1 récente `manifest-*` — la forme exacte
    du corpus réel mesuré (EVIDENCE/reports/lessons.jsonl, 2026-08-15)."""
    from forge import learning_memory as lm
    corpus = tmp_path / "lessons.jsonl"
    # v2 (Gate 1, ratifiée Pierre 2026-09-01) : `cause` fait DÉSORMAIS partie de la forme
    # d'une leçon qui prétend être injectée. Ce corpus reproduit une FORME (26 anciennes +
    # 1 récente) pour éprouver le TRI par récence — pas un contenu de connaissance ; sa
    # cause est donc un énoncé causal réel mais générique, jamais une prétention de savoir.
    # Sans elle, `premortem_lessons` rendrait une liste VIDE et les deux tests de ce
    # fichier passeraient À VIDE (deux sorties vides sont trivialement déterministes).
    for i in range(26):
        lm.record_lesson_event(f"forge.ancienne_{i:02d}", status="candidate",
                               statement=f"leçon ancienne {i}", generation=2,
                               path=corpus, ts=1000.0 + i,
                               cause=f"le volet {i} rendait FAIL là où la mesure était"
                                     " impossible dans le mode d'exécution courant")
    lm.record_lesson_event("manifest-pacman-recent", status="candidate",
                           statement="leçon récente du post-mortem",
                           generation=2, path=corpus, ts=999_999.0,
                           cause="la boucle d'apprentissage promouvait une observation"
                                 " sans jamais vérifier qu'un consommateur la relisait")
    return corpus


def test_p0_5_consommation_une_lecon_recente_est_injectee(tmp_path: Path):
    from forge import learning_memory as lm
    corpus = _corpus_style_reel(tmp_path)
    out = lm.premortem_lessons(current_generation=2, lessons_path=corpus,
                               include_legacy=False,
                               legacy_domain_path=tmp_path / "vide_dom.jsonl",
                               legacy_monolith_path=tmp_path / "vide_mono.jsonl")
    assert len(out) == 5, "limit par défaut inchangée (5)"
    assert any("manifest-pacman-recent" in line for line in out), (
        "la leçon la plus récente doit être injectée — avant le correctif, le tri "
        "alphabétique la plaçait en dernière position, invisible de tout run"
    )
    assert "manifest-pacman-recent" in out[0], "la plus récente arrive en tête"


def test_p0_5_determinisme_conserve(tmp_path: Path):
    """Le tri par récence lit `ts` ÉCRIT avec la leçon — deux lectures du même
    corpus rendent une sortie strictement identique (aucune horloge de lecture)."""
    from forge import learning_memory as lm
    corpus = _corpus_style_reel(tmp_path)
    kwargs = dict(current_generation=2, lessons_path=corpus, include_legacy=False,
                  legacy_domain_path=tmp_path / "d.jsonl",
                  legacy_monolith_path=tmp_path / "m.jsonl")
    assert lm.premortem_lessons(**kwargs) == lm.premortem_lessons(**kwargs)


def test_p0_5_egalite_de_ts_departagee_par_id_stable(tmp_path: Path):
    from forge.learning_memory import format_premortem_lessons
    annotated = [
        {"lesson_id": "b", "statement": "x", "marker": None, "ts": 7.0},
        {"lesson_id": "a", "statement": "y", "marker": None, "ts": 7.0},
    ]
    lines = format_premortem_lessons(annotated, limit=5)
    assert lines[0].startswith("[a]") and lines[1].startswith("[b]")


def test_p0_5_lecon_sans_ts_jamais_prioritaire(tmp_path: Path):
    """Une leçon sans `ts` (legacy) retombe en fin d'ordre (ts traité 0) — elle
    reste visible avec un grand limit, mais ne masque jamais une leçon datée."""
    from forge.learning_memory import format_premortem_lessons
    annotated = [
        {"lesson_id": "legacy-sans-ts", "statement": "x", "marker": None},
        {"lesson_id": "datee", "statement": "y", "marker": None, "ts": 1.0},
    ]
    lines = format_premortem_lessons(annotated, limit=5)
    assert lines[0].startswith("[datee]")
