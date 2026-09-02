"""Oracle du CÂBLAGE réel de `forge.learning_memory.premortem_lessons` — FVL Phase
0.5 étape 3, complément demandé par contre-vérification orchestrateur : le SEUL
changement de lecture exigé par le minimum (doctrine §2.3) n'a de valeur que s'il
atteint effectivement le prompt d'un agent, pas seulement une fonction testée en
isolation ("mode de panne n°1 : écrivain sans appelant / lecteur sans données").

Ce fichier prouve la CHAÎNE COMPLÈTE, sans appel réseau/claude réel (même patron
que `test_run_real_greenfield.py::test_premortem_injecte_sous_le_titre_attendu`,
`_claude_call_raw` monkeypatché) :

    ForgeDriver._premortem() -> context["premortem"] -> run_real.claude_executor
        -> prompt final assemblé -> context_manifest.premortem_sha256

Fichier NOUVEAU : ne touche à aucun test existant. Tout est isolé sous tmp_path
(`lessons_path` injecté au driver) SAUF `test_wiring_reaches_real_default_paths_read_only`
qui exerce délibérément la branche PRODUCTION (run_dir sous le repo -> defaults
réels de learning_memory) en LECTURE SEULE (aucune écriture, aucun `.run()`).
NO_CLAIM_ALLOWED.
"""
from __future__ import annotations

from dataclasses import dataclass

import pytest

import forge.run_real as run_real
from forge import learning_memory as lm
from forge.driver import _REPO_ROOT, ForgeDriver


@dataclass
class FakePayload:
    etape: str
    model: str = "haiku"
    prompt: str = "PROMPT CONTRAT"


def _context(run_dir, driver: ForgeDriver, etape: str):
    return {
        "run_id": driver.run_id, "project": driver.project, "run_dir": str(run_dir),
        "model_override": None, "dispatch_marker": f"FORGE_DISPATCH:{etape}:{driver.run_id}",
        "attempt": 1, "premortem": driver._premortem(),
    }


@pytest.fixture
def capture_calls(monkeypatch):
    """Remplace _claude_call_raw (jamais de vrai `claude -p`) : trace le prompt final."""
    calls = []

    def fake(prompt, model, **kwargs):
        calls.append({"prompt": prompt, "model": model, **kwargs})
        return {"ok": True, "output": "artefact", "tokens": 1, "duration_s": 0.1, "cost_usd": 0.0}

    monkeypatch.setattr(run_real, "_claude_call_raw", fake)
    return calls


def _populate_lessons(path):
    # v2 (Gate 1, ratifiee Pierre 2026-09-01) : une lecon qui PRETEND etre injectee dans
    # le contexte d'un agent doit declarer sa cause. Ces fixtures exercent exactement
    # cette pretention -- elles portent donc une cause REELLE, jamais un remplissage.
    lm.record_lesson_event("lesson-rejetee", status=lm.LESSON_STATUS_CANDIDATE,
                            statement="TEXTE_REJETE_NE_DOIT_JAMAIS_APPARAITRE",
                            generation=2, path=path,
                            cause="le mutant survivant avait ete trie equivalent par son"
                                  " propre producteur, sans verification independante")
    lm.record_lesson_event("lesson-rejetee", status=lm.LESSON_STATUS_VALIDATED, path=path)
    lm.record_lesson_event("lesson-rejetee", status=lm.LESSON_STATUS_WEAKENED, path=path)
    lm.record_lesson_event("lesson-rejetee", status=lm.LESSON_STATUS_REJECTED, path=path)

    lm.record_lesson_event("lesson-autre-gen", status=lm.LESSON_STATUS_CANDIDATE,
                            statement="TEXTE_AUTRE_GENERATION_A_REEXAMINER",
                            generation=1, path=path,
                            cause="un test ecrit pendant le run n'etait liste par aucune"
                                  " commande d'oracle du projet")

    lm.record_lesson_event("lesson-meme-gen", status=lm.LESSON_STATUS_CANDIDATE,
                            statement="TEXTE_MEME_GENERATION_NORMAL",
                            generation=2, path=path,
                            cause="run_status: RUNNING etait lu comme une preuve de vie"
                                  " alors qu'aucun process ne tournait")


def test_lesson_texte_atteint_le_prompt_final_reel(tmp_path, capture_calls, monkeypatch):
    """PREUVE DE COMPLÉTION (proof #2) : un pré-mortem RÉELLEMENT produit par
    ForgeDriver, contenant une leçon filtrée, arrive dans le prompt final assemblé
    par run_real.claude_executor — le chemin qui atteint effectivement un agent."""
    # Génération courante = 2 (genome_generation.yaml réel du dépôt) : pas de
    # monkeypatch ici, on exerce la VRAIE valeur déclarée.
    assert lm.load_current_generation() == 2

    lessons_path = tmp_path / "lessons.jsonl"
    _populate_lessons(lessons_path)

    run_dir = tmp_path / "run"
    driver = ForgeDriver("proj", "proj-1", profile="micro", run_dir=run_dir,
                         lessons_path=lessons_path)

    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={})
    ex(FakePayload("s9-build"), None, _context(run_dir, driver, "s9-build"))

    prompt = capture_calls[-1]["prompt"]
    assert "## PRÉ-MORTEM (erreurs des runs passés)" in prompt
    assert "TEXTE_MEME_GENERATION_NORMAL" in prompt
    assert "TEXTE_AUTRE_GENERATION_A_REEXAMINER" in prompt
    assert lm.MARKER_GENERATION_MISMATCH in prompt
    # PREUVE #4 : une leçon rejected n'apparaît pas dans le pré-mortem produit.
    assert "TEXTE_REJETE_NE_DOIT_JAMAIS_APPARAITRE" not in prompt
    # La ligne de la leçon même-génération ne porte PAS le marqueur.
    same_gen_line = next(l for l in prompt.splitlines() if "TEXTE_MEME_GENERATION_NORMAL" in l)
    assert lm.MARKER_GENERATION_MISMATCH not in same_gen_line


def test_determinisme_bout_en_bout_deux_productions_successives(tmp_path):
    """PREUVE #3 côté câblage réel : deux PRODUCTIONS SUCCESSIVES du même
    pré-mortem (deux instances driver distinctes sur le même corpus, comme deux
    tentatives d'étape) rendent une sortie STRICTEMENT IDENTIQUE."""
    lessons_path = tmp_path / "lessons.jsonl"
    _populate_lessons(lessons_path)
    run_dir = tmp_path / "run"

    d1 = ForgeDriver("proj", "proj-1", profile="micro", run_dir=run_dir, lessons_path=lessons_path)
    d2 = ForgeDriver("proj", "proj-1", profile="micro", run_dir=run_dir, lessons_path=lessons_path)
    assert d1._premortem() == d2._premortem()
    # Et re-appeler la MÊME instance (cache) ne change rien non plus.
    assert d1._premortem() == d1._premortem()


def test_wiring_reaches_real_default_paths_read_only():
    """Un run_dir SOUS le repo (production réelle, jamais .run() ici -> aucune
    écriture) fait retomber `_lessons_target`/`_legacy_lessons_targets` sur les
    défauts RÉELS de learning_memory.

    PROPRIÉTÉ DURABLE, pas un état de corpus (règle ratifiée : « un test qui fige
    une implémentation devient un faux signal »). La version initiale assertait
    `all(MARKER in l)` — vrai seulement tant que le corpus réel ne contenait QUE
    des leçons legacy (`generation=None`). L'assertion est devenue fausse dès que
    des leçons de la génération courante y ont été consignées (5 leçons Breakout V2,
    `generation=2`, commit bcde5cb) ALORS QUE le mécanisme de marquage, lui,
    fonctionnait correctement.

    Ce qui est vérifié désormais : le câblage retombe bien sur les défauts
    production (None/None), le corpus réel produit un pré-mortem non vide, et la
    correspondance marqueur <-> génération est exacte LIGNE PAR LIGNE, dans les
    DEUX sens, contre la source relue depuis ces mêmes défauts — quel que soit le
    contenu du corpus au moment du run."""
    run_dir = _REPO_ROOT / "EVIDENCE" / "runs" / "_wiring_proof_read_only"
    driver = ForgeDriver("proj", "proj-1", profile="micro", run_dir=run_dir,
                         journal_path=run_dir / "journal_isolated.jsonl")
    assert driver._lessons_target() is None
    assert driver._legacy_lessons_targets() == (None, None)
    lines = driver._premortem_lessons()
    assert lines, "le corpus réel doit produire un pré-mortem non vide pour un run 'production'"

    current = lm.load_current_generation()
    # Source relue depuis les défauts PRODUCTION (aucun chemin en dur ici) : c'est
    # exactement ce que le driver vient d'atteindre en retombant sur None/None.
    source = {lid: r.get("generation") for lid, r in lm.fold_lessons(None).items()}
    source.update({l["lesson_id"]: l.get("generation") for l in lm.legacy_global_lessons()})
    assert source, "les défauts production doivent exposer un corpus non vide"

    # Échantillon élargi : les lignes réellement rendues au driver (tronquées à
    # `limit=5`) ET le corpus complet non tronqué — sans quoi le sens « marqué » de
    # la règle cesserait d'être exercé sur le corpus réel dès que la fenêtre de
    # troncature ne contient qu'une seule classe de génération.
    sample = list(lines) + lm.premortem_lessons(current_generation=current, limit=0)
    for line in sample:
        lesson_id = line.split("]", 1)[0].lstrip("[")
        assert lesson_id in source, f"ligne rendue hors corpus source : {line!r}"
        gen = source[lesson_id]
        mismatch = gen is None or current is None or gen != current
        assert (lm.MARKER_GENERATION_MISMATCH in line) is mismatch, (
            f"marquage incohérent pour {lesson_id} (generation={gen!r}, "
            f"courante={current!r}) : {line!r}")
