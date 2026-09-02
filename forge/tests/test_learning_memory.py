"""Oracle de `forge.learning_memory` — mémoire d'apprentissage Forge (FVL Phase 0.5,
étape 3 : failure_event append-only, statut de lesson, filtrage déterministe du
pré-mortem). Voir docs/forge/FORGE_EVOLUTION_DOCTRINE_V0.md §2.1-2.3.

Fichier NOUVEAU : ne touche à aucun test existant. Toute écriture est isolée sous
`tmp_path` (jamais dans `EVIDENCE/reports/failure_events.jsonl`/`lessons.jsonl` réels) —
SAUF les tests explicitement marqués « corpus RÉEL, lecture seule », qui lisent
`EVIDENCE/reports/forge_error_journal.jsonl`/`error_journal/_global_.jsonl` SANS jamais
écrire dedans (assertion de non-modification incluse). NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

import hashlib
import json

import pytest

from forge import learning_memory as lm


# =====================================================================================
# A. failure_event — append-only, clé par failure_id, replié à la lecture
# =====================================================================================

def test_record_failure_event_declares_absent_producers_as_explicitly_empty(tmp_path):
    """Un failure_event neuf sans expérience/verdict/leçon les porte VIDES, jamais
    absents (règle des trois états, mission §compatibilité)."""
    path = tmp_path / "fe.jsonl"
    record = lm.record_failure_event(
        "fail-1", "run-1", "proj",
        erreur_observee="oracle rouge", etape_detection="s10a-oracle-code",
        path=path,
    )
    assert record["schema"] == lm.FAILURE_EVENT_SCHEMA
    assert record["causes_suspectees"] == []
    assert record["niveaux_mutation_proposes"] == []
    assert record["experience_associee"] == ""
    assert record["verdict_oracle"] == ""
    assert record["lesson"] == {"texte": "", "statut": ""}


def test_failure_event_cause_is_never_derived_from_etape_detection(tmp_path):
    """PROPRIÉTÉ NÉGATIVE (doctrine §4.0) : `etape_detection` ne doit JAMAIS être
    utilisée pour deviner `causes_suspectees`. Même une étape au nom évocateur
    ('s9-build' -> tentation 'execution') laisse causes_suspectees VIDE si
    l'appelant n'en fournit aucune — la classification est un acte séparé, jamais
    une inférence automatique de ce module."""
    path = tmp_path / "fe.jsonl"
    record = lm.record_failure_event(
        "fail-2", "run-1", "proj",
        erreur_observee="build cassé", etape_detection="s9-build",
        path=path,
    )
    assert record["causes_suspectees"] == []
    # Et l'inverse tient : une cause EXPLICITE peut contredire l'étape de détection
    # (précédent réel : chesscolor, détecté à s11-redteam-code, cause = connaissance).
    record2 = lm.record_failure_event(
        "fail-3", "run-1", "proj",
        erreur_observee="couleur case fausse", etape_detection="s11-redteam-code",
        causes_suspectees=[{"level": lm.CAUSE_CONNAISSANCE, "status": "confirmed"}],
        path=path,
    )
    assert record2["causes_suspectees"] == [
        {"level": "connaissance", "status": "confirmed"}
    ]


def test_failure_event_rejects_unknown_cause_level(tmp_path):
    """PROPRIÉTÉ NÉGATIVE : un niveau de cause hors taxonomie lève, jamais un
    enregistrement silencieusement incohérent."""
    with pytest.raises(ValueError):
        lm.record_failure_event(
            "fail-x", "run-1", "proj", erreur_observee="e", etape_detection="s9",
            causes_suspectees=[{"level": "hasard", "status": "hypothesis"}],
            path=tmp_path / "fe.jsonl",
        )


def test_failure_event_rejects_unknown_cause_attribution_status(tmp_path):
    with pytest.raises(ValueError):
        lm.record_failure_event(
            "fail-x", "run-1", "proj", erreur_observee="e", etape_detection="s9",
            causes_suspectees=[{"level": lm.CAUSE_EXECUTION, "status": "vrai_de_vrai"}],
            path=tmp_path / "fe.jsonl",
        )


def test_failure_event_rejects_invalid_embedded_lesson_statut(tmp_path):
    with pytest.raises(ValueError):
        lm.record_failure_event(
            "fail-x", "run-1", "proj", erreur_observee="e", etape_detection="s9",
            lesson_statut="peut-etre", path=tmp_path / "fe.jsonl",
        )


def test_failure_event_append_only_preserves_both_writes(tmp_path):
    """PREUVE #7 : deux écritures successives sur le MÊME failure_id conservent les
    DEUX (append-only), et le repli à la lecture rend l'état courant SANS effacer
    l'historique."""
    path = tmp_path / "fe.jsonl"
    lm.record_failure_event(
        "fail-42", "run-1", "proj",
        erreur_observee="joueur IA faible", etape_detection="s10a-oracle-code",
        causes_suspectees=[{"level": lm.CAUSE_EXECUTION, "status": "hypothesis"}],
        path=path, ts=1.0,
    )
    lm.record_failure_event(
        "fail-42", "run-2", "proj",
        erreur_observee="joueur IA faible", etape_detection="s10a-oracle-code",
        causes_suspectees=[{"level": lm.CAUSE_CONNAISSANCE, "status": "confirmed"}],
        experience_associee="exp-worldscan-1",
        path=path, ts=2.0,
    )

    history = lm.read_failure_event_history("fail-42", path=path)
    assert len(history) == 2, "les DEUX événements doivent rester lisibles"
    assert history[0]["causes_suspectees"][0]["level"] == "execution"
    assert history[1]["causes_suspectees"][0]["level"] == "connaissance"

    folded = lm.fold_failure_events(path=path)
    assert folded["fail-42"] == history[1], "le repli rend l'état COURANT (le dernier écrit)"
    assert folded["fail-42"]["experience_associee"] == "exp-worldscan-1"
    # L'ancienne hypothèse n'a pas disparu du fichier (elle est juste 1re dans l'ordre).
    raw = lm.read_all_failure_events_raw(path=path)
    assert len(raw) == 2


def test_make_failure_id_is_stable_and_content_derived():
    id1 = lm.make_failure_id("proj", "s9-build", "erreur X")
    id2 = lm.make_failure_id("proj", "s9-build", "erreur X")
    id3 = lm.make_failure_id("proj", "s9-build", "erreur Y")
    assert id1 == id2
    assert id1 != id3


# =====================================================================================
# B. lesson — objet distinct, statut révisable par preuve, jamais le passé
# =====================================================================================

def test_lesson_new_must_start_candidate(tmp_path):
    """PROPRIÉTÉ NÉGATIVE : une leçon ne peut pas apparaître déjà 'validated' sans
    être passée par 'candidate' — sinon une leçon se déclarerait vraie d'emblée."""
    with pytest.raises(ValueError):
        lm.record_lesson_event(
            "lesson-1", status=lm.LESSON_STATUS_VALIDATED, statement="une leçon",
            path=tmp_path / "lessons.jsonl",
        )


def test_lesson_new_requires_statement(tmp_path):
    with pytest.raises(ValueError):
        lm.record_lesson_event(
            "lesson-1", status=lm.LESSON_STATUS_CANDIDATE, statement=None,
            path=tmp_path / "lessons.jsonl",
        )


def test_lesson_valid_transition_candidate_to_validated(tmp_path):
    path = tmp_path / "lessons.jsonl"
    lm.record_lesson_event("lesson-1", status=lm.LESSON_STATUS_CANDIDATE,
                            statement="oracle doit tester la solvabilité",
                            generation=2, path=path)
    record = lm.record_lesson_event(
        "lesson-1", status=lm.LESSON_STATUS_VALIDATED,
        caused_by_experience="exp-solvability-1", path=path,
    )
    assert record["status"] == "validated"
    assert record["statement"] == "oracle doit tester la solvabilité"
    assert record["generation"] == 2  # hérité du prior, jamais perdu
    assert record["caused_by"]["experience"] == "exp-solvability-1"


def test_lesson_invalid_transition_rejected(tmp_path):
    """PROPRIÉTÉ NÉGATIVE : candidate -> weakened directement est hors table
    (doctrine §2.2) — doit lever, pas s'enregistrer silencieusement."""
    path = tmp_path / "lessons.jsonl"
    lm.record_lesson_event("lesson-1", status=lm.LESSON_STATUS_CANDIDATE,
                            statement="s", path=path)
    with pytest.raises(ValueError):
        lm.record_lesson_event("lesson-1", status=lm.LESSON_STATUS_WEAKENED, path=path)


def test_lesson_deprecated_is_terminal(tmp_path):
    """PROPRIÉTÉ NÉGATIVE : une fois 'deprecated', aucune transition mécanique
    n'est prévue par la doctrine — doit lever."""
    path = tmp_path / "lessons.jsonl"
    lm.record_lesson_event("lesson-1", status=lm.LESSON_STATUS_CANDIDATE,
                            statement="s", path=path)
    lm.record_lesson_event("lesson-1", status=lm.LESSON_STATUS_DEPRECATED, path=path)
    with pytest.raises(ValueError):
        lm.record_lesson_event("lesson-1", status=lm.LESSON_STATUS_CANDIDATE, path=path)


def test_lesson_full_lifecycle_validated_weakened_rejected(tmp_path):
    path = tmp_path / "lessons.jsonl"
    lm.record_lesson_event("lesson-2", status=lm.LESSON_STATUS_CANDIDATE,
                            statement="s", path=path)
    lm.record_lesson_event("lesson-2", status=lm.LESSON_STATUS_VALIDATED, path=path)
    lm.record_lesson_event("lesson-2", status=lm.LESSON_STATUS_WEAKENED,
                            caused_by_failure_id="fail-9", path=path)
    final = lm.record_lesson_event("lesson-2", status=lm.LESSON_STATUS_REJECTED, path=path)
    assert final["status"] == "rejected"


def test_lesson_evidence_is_cumulative_never_shrinks(tmp_path):
    path = tmp_path / "lessons.jsonl"
    lm.record_lesson_event("lesson-3", status=lm.LESSON_STATUS_CANDIDATE,
                            statement="s", path=path)
    lm.record_lesson_event("lesson-3", status=lm.LESSON_STATUS_CANDIDATE,
                            add_supporting_run="run-a", path=path)
    r2 = lm.record_lesson_event("lesson-3", status=lm.LESSON_STATUS_CANDIDATE,
                                 add_supporting_run="run-b", path=path)
    assert r2["supporting_runs"] == ["run-a", "run-b"]
    assert r2["evidence_count"] == 2
    r3 = lm.record_lesson_event("lesson-3", status=lm.LESSON_STATUS_VALIDATED,
                                 add_counter_example="run-c-contredit", path=path)
    assert r3["supporting_runs"] == ["run-a", "run-b"]  # jamais perdu à la transition
    assert r3["counter_examples"] == ["run-c-contredit"]


def test_lesson_append_only_history_preserved(tmp_path):
    """Même preuve que pour failure_event, côté leçon : le fold ne perd rien."""
    path = tmp_path / "lessons.jsonl"
    lm.record_lesson_event("lesson-4", status=lm.LESSON_STATUS_CANDIDATE,
                            statement="s", path=path, ts=1.0)
    lm.record_lesson_event("lesson-4", status=lm.LESSON_STATUS_VALIDATED, path=path, ts=2.0)
    history = lm.read_lesson_history("lesson-4", path=path)
    assert [h["status"] for h in history] == ["candidate", "validated"]
    assert lm.fold_lessons(path=path)["lesson-4"]["status"] == "validated"


def test_lesson_rejects_unknown_status(tmp_path):
    with pytest.raises(ValueError):
        lm.record_lesson_event("lesson-5", status="tres_valide", statement="s",
                                path=tmp_path / "lessons.jsonl")


# =====================================================================================
# Compatibilité : anciennes leçons de méthode (pré-schéma)
# =====================================================================================

def test_legacy_global_lessons_reads_real_corpus():
    """Corpus RÉEL, lecture seule (mission, preuve #6) : les 3 leçons de méthode
    connues (`project=_global_`, `run_id=_method_`) du monolithe historique restent
    lisibles, ni perdues ni promues (statut LEGACY_STATUS, pas 'validated')."""
    legacy = lm.legacy_global_lessons()
    statements = [l["statement"] for l in legacy]
    assert any("SOLVABILITÉ" in s for s in statements), (
        "la leçon de méthode 'solvabilité' du corpus réel doit rester lisible")
    assert any("tautologique" in s for s in statements)
    assert any("evidence_path" in s for s in statements)
    for l in legacy:
        assert l["status"] == lm.LEGACY_STATUS, "jamais promue en 'validated' silencieusement"
        assert l["generation"] is None
        assert l["schema"] is None


def test_legacy_global_lessons_never_writes_to_source_files():
    """La lecture ne modifie JAMAIS les fichiers sources (monolithe/journal domaine)."""
    def _hash(path):
        return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None

    monolith_before = _hash(lm.DEFAULT_ERROR_JOURNAL)
    domain_path = lm.DOMAIN_JOURNAL_DIR / f"{lm.GLOBAL_SCOPE}.jsonl"
    domain_before = _hash(domain_path)

    lm.legacy_global_lessons()
    lm.legacy_global_lessons()  # deux lectures, au cas où une lecture aurait un effet de bord

    assert _hash(lm.DEFAULT_ERROR_JOURNAL) == monolith_before
    assert _hash(domain_path) == domain_before


def test_legacy_global_lessons_ids_are_stable_across_reads():
    ids_1 = sorted(l["lesson_id"] for l in lm.legacy_global_lessons())
    ids_2 = sorted(l["lesson_id"] for l in lm.legacy_global_lessons())
    assert ids_1 == ids_2
    assert len(ids_1) == len(set(ids_1)), "pas de doublon"


# =====================================================================================
# C. premortem_lessons — récupérer / filtrer / afficher
# =====================================================================================

def test_premortem_rejected_lesson_never_injected(tmp_path):
    """PREUVE #4 : une leçon 'rejected' n'est PAS injectée comme contrainte."""
    path = tmp_path / "lessons.jsonl"
    lm.record_lesson_event("lesson-r", status=lm.LESSON_STATUS_CANDIDATE,
                            statement="TEXTE_UNIQUE_REJETE", generation=1, path=path)
    lm.record_lesson_event("lesson-r", status=lm.LESSON_STATUS_VALIDATED, path=path)
    lm.record_lesson_event("lesson-r", status=lm.LESSON_STATUS_WEAKENED, path=path)
    lm.record_lesson_event("lesson-r", status=lm.LESSON_STATUS_REJECTED, path=path)

    out = lm.premortem_lessons(current_generation=1, lessons_path=path, include_legacy=False)
    assert not any("TEXTE_UNIQUE_REJETE" in line for line in out)


def test_premortem_different_generation_injected_and_marked(tmp_path):
    """PREUVE #5 : une leçon d'une autre génération EST injectée ET marquée à
    réexaminer (pas silencieusement traitée comme une règle courante)."""
    path = tmp_path / "lessons.jsonl"
    lm.record_lesson_event("lesson-g", status=lm.LESSON_STATUS_CANDIDATE,
                            statement="TEXTE_AUTRE_GENERATION", generation=1, path=path,
                            cause="le seuil etait code en dur dans le builder au lieu"
                                  " d'etre lu du charter")
    out = lm.premortem_lessons(current_generation=2, lessons_path=path, include_legacy=False)
    line = next(l for l in out if "TEXTE_AUTRE_GENERATION" in l)
    assert lm.MARKER_GENERATION_MISMATCH in line


def test_premortem_same_generation_no_marker(tmp_path):
    path = tmp_path / "lessons.jsonl"
    lm.record_lesson_event("lesson-s", status=lm.LESSON_STATUS_CANDIDATE,
                            statement="TEXTE_MEME_GENERATION", generation=3, path=path,
                            cause="l'oracle lisait le wiremap du run_dir alors que la"
                                  " topologie STANDARD le place dans 09_WIREMAP/")
    out = lm.premortem_lessons(current_generation=3, lessons_path=path, include_legacy=False)
    line = next(l for l in out if "TEXTE_MEME_GENERATION" in l)
    assert lm.MARKER_GENERATION_MISMATCH not in line
    assert lm.MARKER_DEPRECATED not in line


def test_premortem_deprecated_marked_historical_even_if_generation_matches(tmp_path):
    """Le statut 'deprecated' prime sur la comparaison de génération : marquée
    historique, jamais confondue avec une injection normale même si la génération
    déclarée coïncide."""
    path = tmp_path / "lessons.jsonl"
    lm.record_lesson_event("lesson-d", status=lm.LESSON_STATUS_CANDIDATE,
                            statement="TEXTE_DEPRECIEE", generation=5, path=path,
                            cause="le harnais e2e transformait une exception d'import"
                                  " manquant en passed:true (faux vert)")
    lm.record_lesson_event("lesson-d", status=lm.LESSON_STATUS_DEPRECATED,
                            generation=5, path=path)
    out = lm.premortem_lessons(current_generation=5, lessons_path=path, include_legacy=False)
    line = next(l for l in out if "TEXTE_DEPRECIEE" in l)
    assert lm.MARKER_DEPRECATED in line
    assert lm.MARKER_GENERATION_MISMATCH not in line


def test_premortem_unknown_current_generation_flags_everything(tmp_path):
    """Deux inconnues (génération de la leçon connue, génération courante inconnue)
    ne doivent JAMAIS se lire comme une correspondance silencieuse."""
    path = tmp_path / "lessons.jsonl"
    lm.record_lesson_event("lesson-u", status=lm.LESSON_STATUS_CANDIDATE,
                            statement="TEXTE_GENERATION_INCONNUE", generation=1, path=path,
                            cause="la regex de derivation de projet n'anticipait pas le"
                                  " suffixe horaire -HHMM du run_id")
    out = lm.premortem_lessons(current_generation=None, lessons_path=path, include_legacy=False)
    line = next(l for l in out if "TEXTE_GENERATION_INCONNUE" in l)
    assert lm.MARKER_GENERATION_MISMATCH in line


def test_premortem_legacy_lessons_are_marked_generation_mismatch(tmp_path):
    """Les leçons legacy (corpus réel) apparaissent, TOUJOURS marquées à réexaminer
    — jamais silencieusement traitées comme 'même génération'."""
    empty = tmp_path / "empty_lessons.jsonl"
    out = lm.premortem_lessons(current_generation=1, lessons_path=empty,
                                include_legacy=True, limit=50)
    assert out, "les leçons legacy du corpus réel doivent apparaître"
    assert all(lm.MARKER_GENERATION_MISMATCH in line for line in out)


def test_premortem_lessons_is_deterministic(tmp_path):
    """PREUVE #3 (la plus importante de la mission) : deux appels successifs sur le
    MÊME corpus rendent une sortie STRICTEMENT IDENTIQUE."""
    path = tmp_path / "lessons.jsonl"
    lm.record_lesson_event("lesson-z", status=lm.LESSON_STATUS_CANDIDATE,
                            statement="A", generation=1, path=path)
    lm.record_lesson_event("lesson-a", status=lm.LESSON_STATUS_CANDIDATE,
                            statement="B", generation=2, path=path)
    lm.record_lesson_event("lesson-m", status=lm.LESSON_STATUS_CANDIDATE,
                            statement="C", generation=1, path=path)

    out1 = lm.premortem_lessons(current_generation=1, lessons_path=path)
    out2 = lm.premortem_lessons(current_generation=1, lessons_path=path)
    out3 = lm.premortem_lessons(current_generation=1, lessons_path=path)
    assert out1 == out2 == out3


def test_premortem_lessons_sort_is_structural_not_read_order(tmp_path):
    """Le tri est un critère STRUCTUREL : peu importe l'ordre d'ÉCRITURE, la
    sortie reste la même pour le même ENSEMBLE de leçons (mêmes champs écrits).

    MAJ lot 1 ADR-003 (P0-5, GO Pierre 2026-08-15) : le tri est passé de
    `lesson_id` seul à (récence `ts` décroissante, puis `lesson_id`). `ts` est un
    champ ÉCRIT avec la leçon — il fait donc partie de la structure : ce test
    fixe désormais des `ts` explicites IDENTIQUES entre les deux corpus pour
    continuer de prouver la même propriété (l'ordre d'écriture/lecture ne décide
    rien, seuls les champs écrits décident)."""
    path_a = tmp_path / "order_a.jsonl"
    # Les DEUX corpus portent les MÊMES champs (statement, generation, ts, cause) :
    # seul l'ordre d'ÉCRITURE diffère. `cause` entre dans la structure comparée depuis
    # v2 — une fixture sans cause serait exclue par Gate 1 et ne prouverait plus rien.
    CAUSE_BB = "le builder documentait plusieurs fonctions par feature au lieu d'une"
    CAUSE_AA = "le timeout de dispatch etait calibre sur un squelette, pas sur un greenfield"
    lm.record_lesson_event("lesson-bb", status=lm.LESSON_STATUS_CANDIDATE,
                            statement="BB", generation=1, path=path_a, ts=100.0,
                            cause=CAUSE_BB)
    lm.record_lesson_event("lesson-aa", status=lm.LESSON_STATUS_CANDIDATE,
                            statement="AA", generation=1, path=path_a, ts=200.0,
                            cause=CAUSE_AA)

    path_b = tmp_path / "order_b.jsonl"
    lm.record_lesson_event("lesson-aa", status=lm.LESSON_STATUS_CANDIDATE,
                            statement="AA", generation=1, path=path_b, ts=200.0,
                            cause=CAUSE_AA)
    lm.record_lesson_event("lesson-bb", status=lm.LESSON_STATUS_CANDIDATE,
                            statement="BB", generation=1, path=path_b, ts=100.0,
                            cause=CAUSE_BB)

    out_a = lm.premortem_lessons(current_generation=1, lessons_path=path_a, include_legacy=False)
    out_b = lm.premortem_lessons(current_generation=1, lessons_path=path_b, include_legacy=False)
    assert out_a == out_b
    # La plus récente (ts=200) passe en tête — le nouveau critère, prouvé ici aussi.
    assert out_a[0].startswith("[lesson-aa]")


def test_premortem_lessons_limit_excludes_rejected_from_budget(tmp_path):
    """La limite s'applique APRÈS le filtre 'rejected' — une leçon rejetée ne doit
    pas consommer une place au détriment d'une leçon active."""
    path = tmp_path / "lessons.jsonl"
    # 2 leçons rejetées (id alphabétiquement avant), 1 leçon active.
    for suffix in ("a", "b"):
        lid = f"lesson-{suffix}"
        lm.record_lesson_event(lid, status=lm.LESSON_STATUS_CANDIDATE, statement="x",
                                generation=1, path=path,
                                cause="volet d'oracle rouge sur un mode d'execution ou la"
                                      " mesure etait impossible")
        lm.record_lesson_event(lid, status=lm.LESSON_STATUS_VALIDATED, path=path)
        lm.record_lesson_event(lid, status=lm.LESSON_STATUS_WEAKENED, path=path)
        lm.record_lesson_event(lid, status=lm.LESSON_STATUS_REJECTED, path=path)
    lm.record_lesson_event("lesson-c", status=lm.LESSON_STATUS_CANDIDATE,
                            statement="TEXTE_ACTIF_UNIQUE", generation=1, path=path,
                            cause="le projet n'etait pas enregistre dans oracles.json avant"
                                  " le premier dispatch LLM")

    out = lm.premortem_lessons(current_generation=1, lessons_path=path,
                                include_legacy=False, limit=1)
    assert any("TEXTE_ACTIF_UNIQUE" in line for line in out)


# =====================================================================================
# CLI
# =====================================================================================

def test_cli_failure_writes_record(tmp_path, monkeypatch):
    target = tmp_path / "fe.jsonl"
    monkeypatch.setattr(lm, "DEFAULT_FAILURE_EVENTS_PATH", target)
    code = lm.main([
        "failure", "--failure-id", "fail-cli", "--run-id", "r1", "--project", "p",
        "--erreur-observee", "e", "--etape-detection", "s9-build",
    ])
    assert code == 0
    rows = [json.loads(l) for l in target.read_text(encoding="utf-8").splitlines() if l.strip()]
    assert rows[0]["failure_id"] == "fail-cli"


def test_cli_lesson_writes_record(tmp_path, monkeypatch):
    target = tmp_path / "lessons.jsonl"
    monkeypatch.setattr(lm, "DEFAULT_LESSONS_PATH", target)
    code = lm.main([
        "lesson", "--lesson-id", "lesson-cli", "--status", "candidate",
        "--statement", "une leçon via CLI",
    ])
    assert code == 0
    rows = [json.loads(l) for l in target.read_text(encoding="utf-8").splitlines() if l.strip()]
    assert rows[0]["lesson_id"] == "lesson-cli"


def test_cli_lesson_invalid_transition_exits_nonzero(tmp_path, monkeypatch):
    target = tmp_path / "lessons.jsonl"
    monkeypatch.setattr(lm, "DEFAULT_LESSONS_PATH", target)
    lm.main(["lesson", "--lesson-id", "lesson-bad", "--status", "candidate",
             "--statement", "s"])
    code = lm.main(["lesson", "--lesson-id", "lesson-bad", "--status", "weakened"])
    assert code == 2


def test_cli_no_subcommand_prints_usage_and_exits_nonzero():
    assert lm.main([]) == 2


# ---------------------------------------------------------------------------
# GATE 1 — regle des trois etats sur `cause` (ratifiee Pierre 2026-09-01).
# Ces deux tests sont les SEULS gardiens de la politique : les sept tests
# d'injection preexistants portent desormais une cause reelle, donc aucun
# d'eux ne verifie plus la frontiere elle-meme.
# ---------------------------------------------------------------------------

def test_gate1_cause_vide_est_exclue_du_premortem(tmp_path):
    """Cause PRESENTE et VIDE = absence DECLAREE => evenement d'execution, jamais
    injecte. C'est le cas des 21 lecons « echec de la tentative 0 a <etape> » :
    leur manifeste ne portait aucun `root_cause`."""
    path = tmp_path / "lessons.jsonl"
    lm.record_lesson_event("lesson-sans-cause", status=lm.LESSON_STATUS_CANDIDATE,
                            statement="TEXTE_EVENEMENT_EXECUTION", generation=1,
                            path=path, cause="")
    lm.record_lesson_event("lesson-avec-cause", status=lm.LESSON_STATUS_CANDIDATE,
                            statement="TEXTE_CONNAISSANCE", generation=1, path=path,
                            cause="l'entree declaree n'existait pas dans le wrapper")

    out = lm.premortem_lessons(current_generation=1, lessons_path=path,
                                include_legacy=False)
    assert any("TEXTE_CONNAISSANCE" in l for l in out)
    assert not any("TEXTE_EVENEMENT_EXECUTION" in l for l in out)

    # Exclue du CONTEXTE, jamais du JOURNAL : l'historique reste complet.
    assert "lesson-sans-cause" in lm.fold_lessons(path)


def test_gate1_cause_absente_reste_toleree_pour_les_lecons_v1(tmp_path):
    """Cause ABSENTE = cause INCONNUE, pas niee. Sans cette tolerance, les 326
    lecons v1 du journal sortiraient DEFINITIVEMENT du contexte agent :
    `promote_manifest_lessons` est idempotente (`if lesson_id in existing:
    continue`), elles ne seraient jamais re-emises avec le champ.

    Ecriture DIRECTE d'un enregistrement v1 (sans le champ) : passer par
    `record_lesson_event` ecrirait toujours `cause`, donc ne pourrait pas
    reproduire l'historique reel."""
    path = tmp_path / "lessons.jsonl"
    v1 = {"schema": "forge.lesson.v1", "lesson_id": "lesson-v1",
          "statement": "TEXTE_HISTORIQUE_V1", "status": lm.LESSON_STATUS_CANDIDATE,
          "evidence_count": 1, "supporting_runs": ["r1"], "counter_examples": [],
          "generation": 1, "caused_by": {"failure_id": "", "experience": ""},
          "ts": 100.0}
    assert "cause" not in v1
    path.write_text(json.dumps(v1, ensure_ascii=False) + "\n", encoding="utf-8")

    out = lm.premortem_lessons(current_generation=1, lessons_path=path,
                                include_legacy=False)
    assert any("TEXTE_HISTORIQUE_V1" in l for l in out)
