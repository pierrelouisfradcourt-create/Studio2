"""Rupture 11 (2026-08-23) -- « le canal de dialogue Art <-> GM est sensible a la
forme » (kitten_clicker run 10c, kitten_clicker-20260823e).

MESURE au run 10c (sortie brute, pas d'hypothese) :
  1. Art R1 a ecrit un fence ```design_questions``` contenant de la PROSE markdown
     (titres, puces, `ready_for_freeze: true` en queue au format YAML) --
     `_extract_design_questions_block` ne rendait `None` sans aucun diagnostic
     (il n'acceptait QUE du JSON) -> `written: False` tolere en round 1.
  2. GM R1 n'a EMIS AUCUN fence ("will not emit a design_questions block") et le
     contrat le tolerait -- le canal se taisait sans jamais le declarer.
  3. Art R2 a refait de la prose -> refus avec un message qui ne nommait PAS la
     vraie cause (bloc present mais mal FORME, pas absent).
  4. Le rejeu Lot G (`driver._is_materialize_refusal_reason`) ne reconnaissait
     que « non materialisable » -- le message de round>=2 ("obligatoire en
     round >=2") ne le contenait pas -> halt immediat sans 2e tentative.
  5. Meme rejoue, l'agent aurait recu le MEME prompt (aucun retour du
     materialiseur dans le contexte).
  6. `res["design_questions_check"]` n'etait jamais recopie dans `state.json`.

Ce fichier couvre le correctif des 6 points :
  - T1 : `_extract_design_questions_block` rend (dict|None, diagnostic) --
    JSON, YAML structure, prose (diagnostic precis), aucun fence.
  - T2 : `_materialize_design_questions` refuse (jamais ne tolere plus) un
    fence absent DES LE ROUND 1, avec un message contenant « non
    materialisable » -- rejouable par Lot G.
  - T3 : `_has_valid_design_questions_fence` (tolerance PARTIAL round 1 du
    `game_master`) ne depend plus d'une question bloquante, seulement de la
    presence d'un fence valide.
  - T4 : `ForgeDriver._run_llm` transmet `materialize_feedback` au contexte de
    la tentative suivante ; `run_real.claude_executor` l'injecte dans le prompt.
  - T5 : `design_questions_check`/`economy_check` recopies dans
    `entry["detail"]` (meme patron que `loop_check`).

    PYTHONPATH=scripts .venv312/Scripts/python.exe -m pytest \
        forge/tests/test_lot_g2_design_questions_channel.py -v
"""
from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

import pytest

from forge import run_real
from forge.driver import ForgeDriver, _is_materialize_refusal_reason

REPO_ROOT = Path(__file__).resolve().parents[2]
GM_VALID_FIXTURE = Path(__file__).resolve().parent / "fixtures" / "gm_game_master_valid.json"


def _valid_game_master() -> dict:
    return json.loads(GM_VALID_FIXTURE.read_text(encoding="utf-8"))


_SYNTH_ART_BIBLE = """---
styles: ["cozy", "flat"]
mood_keywords: ["mignon", "chaleureux"]
---

## character_states
Idle / happy / sad, silhouettes lisibles.
"""


def _write_fixtures(run_dir: Path, game_master: dict) -> None:
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "art_bible.md").write_text(_SYNTH_ART_BIBLE, encoding="utf-8")
    (run_dir / "gm_worldscan.json").write_text(
        json.dumps({"game_master": game_master}), encoding="utf-8")


def _dq_round1(*, questions=None, blocking=True) -> dict:
    if questions is None:
        questions = [
            {"id": "q_gm_001", "from": "GM", "to": "ART", "round": 1,
             "about": "grey_blocks.garden", "loop_id": "world_loop",
             "missing": ["etats visuels LOCKED/AVAILABLE/ACTIVE/FULL"],
             "why": "le joueur doit comprendre pourquoi il ne peut pas encore entrer",
             "blocking": blocking, "answer": None},
        ]
    open_to_art = sum(1 for q in questions if q["from"] == "GM")
    return {
        "schema_version": 1, "round": 1,
        "questions": questions,
        "declarations": {
            "ART": {"round": 1, "ready_for_freeze": False, "open_to_gm": 0},
            "GM": {"round": 1, "ready_for_freeze": False, "open_to_art": open_to_art},
        },
    }


# Copie du VRAI fence observe au run 10c (prose markdown -- titres, puces, la
# cle YAML `ready_for_freeze` en queue) -- jamais un exemple invente.
_RUN10C_PROSE_FENCE = (
    "# Design Questions - Art Bible\n\n"
    "## Ce que je sais\n"
    "- Palette pastel confirmee, mood cozy/flat\n\n"
    "## Ce qui manque\n"
    "- Etats visuels du jardin (LOCKED/AVAILABLE/ACTIVE/FULL)\n"
    "- Representation de la progression du joueur\n\n"
    "ready_for_freeze: true\n"
)


# =======================================================================================
# T1 -- _extract_design_questions_block : (dict | None, diagnostic)
# =======================================================================================

def test_extract_fence_json_valide():
    dq = _dq_round1()
    output = "```design_questions\n" + json.dumps(dq) + "\n```"
    got, diagnostic = run_real._extract_design_questions_block(output)
    assert diagnostic == ""
    assert got == dq


def test_extract_fence_yaml_structure_valide():
    output = (
        "```design_questions\n"
        "schema_version: 1\n"
        "round: 1\n"
        "questions: []\n"
        "declarations:\n"
        "  ART:\n"
        "    round: 1\n"
        "    ready_for_freeze: false\n"
        "    open_to_gm: 0\n"
        "  GM:\n"
        "    round: 1\n"
        "    ready_for_freeze: false\n"
        "    open_to_art: 0\n"
        "```"
    )
    got, diagnostic = run_real._extract_design_questions_block(output)
    assert diagnostic == ""
    assert isinstance(got, dict)
    assert got["questions"] == []
    assert got["declarations"]["ART"]["open_to_gm"] == 0


def test_extract_fence_prose_diagnostic_precis_run10c():
    """Le VRAI defaut mesure au run 10c : un fence PRESENT mais rempli de prose
    markdown -- ni JSON ni YAML structure -- rendait auparavant None SANS
    diagnostic. Doit desormais nommer precisement la cause."""
    output = "```design_questions\n" + _RUN10C_PROSE_FENCE + "```"
    got, diagnostic = run_real._extract_design_questions_block(output)
    assert got is None
    assert "ni JSON ni YAML structure" in diagnostic
    assert "Design Questions" in diagnostic  # 40 premiers caracteres du bloc


def test_extract_aucun_fence():
    got, diagnostic = run_real._extract_design_questions_block("rien ici, pas de fence")
    assert got is None
    assert diagnostic == "aucun fence ```design_questions"


# =======================================================================================
# T2 -- _materialize_design_questions : le fence est OBLIGATOIRE des le round 1
# =======================================================================================

def test_materialize_aucun_fence_en_round1_refuse():
    """Rupture 11 : l'ancienne tolerance round 1 ('written: False') disparait --
    un GM/ART qui ne s'exprime jamais via le canal structure (run 10c, GM R1)
    doit desormais REJOUER, pas passer inapercu."""
    r = run_real._materialize_design_questions(
        "s2.7-gm-worldscan", Path("."), "prose sans aucun fence")
    assert r is not None
    assert r.get("ok") is False
    assert "non materialisable" in r["reason"]
    assert "aucun fence" in r["reason"]
    assert "ATTENDU" in r["reason"]


def test_materialize_fence_prose_refuse_avec_diagnostic_precis(tmp_path):
    _write_fixtures(tmp_path, _valid_game_master())
    output = "```design_questions\n" + _RUN10C_PROSE_FENCE + "```"
    r = run_real._materialize_design_questions("s2.7-gm-worldscan", tmp_path, output)
    assert r is not None and r.get("ok") is False
    assert "non materialisable" in r["reason"]
    assert "ni JSON ni YAML structure" in r["reason"]
    assert "ATTENDU" in r["reason"]
    assert not (tmp_path / "design_questions.json").exists()


def test_materialize_questions_vides_avec_declarations_acceptee(tmp_path):
    """R1 sans aucune question : `questions: []` + `declarations` presentes ->
    ACCEPTE (le canal doit etre utilise pour DIRE 'rien a signaler', pas
    silencieux)."""
    _write_fixtures(tmp_path, _valid_game_master())
    dq = _dq_round1(questions=[])
    output = "```design_questions\n" + json.dumps(dq) + "\n```"
    r = run_real._materialize_design_questions("s2.7-gm-worldscan", tmp_path, output)
    assert r == {"written": True, "path": str(tmp_path / "design_questions.json"),
                 "round": 1, "questions": 0}


def test_materialize_fence_json_valide_toujours_ecrit(tmp_path):
    _write_fixtures(tmp_path, _valid_game_master())
    dq = _dq_round1()
    output = "```design_questions\n" + json.dumps(dq) + "\n```"
    r = run_real._materialize_design_questions("s2.7-gm-worldscan", tmp_path, output)
    assert r == {"written": True, "path": str(tmp_path / "design_questions.json"),
                 "round": 1, "questions": 1}
    assert json.loads((tmp_path / "design_questions.json").read_text(encoding="utf-8")) == dq


# =======================================================================================
# T3 -- tolerance PARTIAL round 1 : fence valide, pas question bloquante
# =======================================================================================

def test_tolerance_partial_ne_depend_plus_d_une_question_bloquante(tmp_path):
    gm = dict(_valid_game_master())
    gm["world_interpretation"] = gm["world_interpretation"][:1]  # casse le schema (>=3 exiges)
    _write_fixtures(tmp_path, gm)
    data = {"game_master": gm}

    # fence valide SANS aucune question (declarations seules) -> tolere
    dq = _dq_round1(questions=[])
    output = "```design_questions\n" + json.dumps(dq) + "\n```"
    reason = run_real._validate_game_master_block(
        data, tmp_path, output=output, etape="s2.7-gm-worldscan")
    assert reason == "", reason

    # aucun fence -> plus tolere du tout
    reason_sans_fence = run_real._validate_game_master_block(
        data, tmp_path, output="prose seule, aucun fence", etape="s2.7-gm-worldscan")
    assert reason_sans_fence != ""

    # round 2 (alias) : jamais tolere, meme avec un fence valide
    reason_r2 = run_real._validate_game_master_block(
        data, tmp_path, output=output, etape="s2.7-gm-worldscan-r2")
    assert reason_r2 != ""


# =======================================================================================
# T4 -- driver : retour du materialiseur transmis a la tentative suivante
# =======================================================================================

def _driver(tmp_path, *, executor=None, materialize_attempts_max=2):
    return ForgeDriver(
        "proj-r11", "r1", run_dir=tmp_path / "run", profile="micro",
        key_file=tmp_path / "k.key", audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        journal_path=tmp_path / "journal.jsonl",
        failure_events_path=tmp_path / "failure_events.jsonl",
        executor=executor,
        materialize_attempts_max=materialize_attempts_max,
    )


def _state(d):
    return {"steps": {e: {"status": "PENDING", "attempts": 0, "detail": {}}
                      for e in d.order}}


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


def test_refus_transmet_materialize_feedback_puis_succes(tmp_path, offline):
    calls = []

    def executor(payload, decision, context):
        calls.append(context)
        if len(calls) == 1:
            # la 1re tentative ne porte jamais de retour du materialiseur
            assert context.get("materialize_feedback") is None
            return {
                "ok": False,
                "reason": "s2.7-gm-worldscan: design_questions.json non "
                          "materialisable -- bloc present mais ni JSON ni YAML "
                          "structure (contenu commence par : # Design Questions) "
                          "-- ATTENDU : un unique fence ```design_questions```",
                "output": "```design_questions\n" + _RUN10C_PROSE_FENCE + "```",
            }
        # 2e tentative : le contexte porte le retour du materialiseur precedent
        mf = context.get("materialize_feedback")
        assert mf is not None
        assert mf["attempt"] == 1
        assert "non materialisable" in mf["reason"]
        return {
            "ok": True, "output": "SORTIE VALIDE", "tokens": 100,
            "duration_s": 1.0, "cost_usd": 0.02,
            "design_questions_check": {"written": True, "path": "x/design_questions.json",
                                       "round": 1, "questions": 0},
            "economy_check": {"ok": True},
        }

    d = _driver(tmp_path, executor=executor)
    etape = d.order[0]
    state = _state(d)
    ok = d._run_llm(state, etape)

    assert ok is True
    entry = state["steps"][etape]
    assert entry["status"] == "OK"
    assert len(calls) == 2
    assert len(entry["detail"]["materialize_retries"]) == 1
    assert entry["detail"]["design_questions_check"]["written"] is True
    assert entry["detail"]["economy_check"] == {"ok": True}


def test_detecteur_reconnait_le_motif_design_questions():
    assert _is_materialize_refusal_reason(
        "design_questions.json obligatoire mais absent -- refus") is True


# =======================================================================================
# T4b -- run_real.claude_executor : le prompt porte la section RETOUR DU MATERIALISEUR
# =======================================================================================

@dataclass
class FakePayload:
    etape: str
    model: str = "haiku"
    prompt: str = "PROMPT CONTRAT"


def _context(run_dir, **extra):
    ctx = {
        "run_id": "run-1",
        "project": "proj",
        "run_dir": str(run_dir),
        "model_override": None,
        "dispatch_marker": "FORGE_DISPATCH:x:run-1",
        "attempt": 2,
        "premortem": [],
    }
    ctx.update(extra)
    return ctx


def test_executor_injecte_le_retour_du_materialiseur_dans_le_prompt(tmp_path, monkeypatch):
    captured = {}

    def fake_claude_call(prompt, model, **kwargs):
        captured["prompt"] = prompt
        return {"ok": True, "output": "SORTIE LLM", "tokens": 10,
                "duration_s": 0.1, "cost_usd": 0.001}

    monkeypatch.setattr(run_real, "_claude_call_raw", fake_claude_call)
    monkeypatch.setattr(
        run_real, "_materialize_artifact",
        lambda etape, output, run_dir: None,
    )

    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={})
    ex(FakePayload("s2-worldscan"), None, _context(
        tmp_path / "run",
        materialize_feedback={"attempt": 1, "reason": "s2-worldscan: worldscan.json "
                              "non materialisable -- virgule manquante",
                              "failed_artifact_path": None},
    ))

    prompt = captured["prompt"]
    assert "## RETOUR DU MATÉRIALISEUR" in prompt
    assert "tentative 1" in prompt
    assert "virgule manquante" in prompt
    assert "REFUSÉE" in prompt


def test_executor_sans_materialize_feedback_necrit_aucune_section(tmp_path, monkeypatch):
    captured = {}

    def fake_claude_call(prompt, model, **kwargs):
        captured["prompt"] = prompt
        return {"ok": True, "output": "SORTIE LLM", "tokens": 10,
                "duration_s": 0.1, "cost_usd": 0.001}

    monkeypatch.setattr(run_real, "_claude_call_raw", fake_claude_call)
    monkeypatch.setattr(
        run_real, "_materialize_artifact",
        lambda etape, output, run_dir: None,
    )

    ex = run_real.claude_executor(add_dir=tmp_path, task_by_step={})
    ex(FakePayload("s2-worldscan"), None, _context(tmp_path / "run"))

    assert "## RETOUR DU MATÉRIALISEUR" not in captured["prompt"]


def test_driver_ne_spawn_pas_directement():
    """Garde-fou : ce correctif n'introduit aucun spawn direct dans driver.py."""
    src = Path(__file__).resolve().parents[1].joinpath("driver.py").read_text(
        encoding="utf-8")
    for mot in ("subprocess", "Popen", "os.system", "anthropic"):
        assert mot not in src, f"mot interdit trouve dans driver.py : {mot}"


# --- Run 11 (2026-08-24, kitten_clicker-20260824e) : mention inline qui eclipse le vrai fence ---

RUN11_SHADOWED = Path(__file__).resolve().parent / "fixtures" / "run11_art_r2_valid_fence_shadowed.txt"


@pytest.mark.skipif(not RUN11_SHADOWED.exists(), reason="fixture run 11 absente")
def test_mention_inline_du_fence_dans_la_prose_n_eclipse_pas_le_vrai_fence():
    """MESURE run 11 (s2.5-artbible-r2, tentative 3) : la sortie portait UN vrai
    fence ```design_questions``` en debut de ligne avec le JSON complet, mais la
    prose obligatoire (RETURN_REASON, lignee causale) citait ```design_questions```
    INLINE apres lui -- la regex non ancree prenait la DERNIERE mention (vide) et
    refusait un producteur conforme. Un fence ne commence qu'en debut de ligne."""
    output = RUN11_SHADOWED.read_text(encoding="utf-8")
    data, diagnostic = run_real._extract_design_questions_block(output)
    assert diagnostic == ""
    assert isinstance(data, dict)
    assert len(data["questions"]) == 5
    assert data["declarations"]["ART"]["ready_for_freeze"] is True


def test_fence_reel_en_debut_de_ligne_reste_le_dernier_retenu():
    """Deux vrais fences ligne-ancres : le DERNIER gagne toujours (regle rupture 11
    inchangee) ; une mention inline apres eux ne compte jamais."""
    output = (
        "```design_questions\n{\"schema_version\": 1, \"round\": 1, \"questions\": []}\n```\n"
        "du texte\n"
        "```design_questions\n{\"schema_version\": 1, \"round\": 2, \"questions\": []}\n```\n"
        "prose finale citant ```design_questions``` inline.\n")
    data, diagnostic = run_real._extract_design_questions_block(output)
    assert diagnostic == ""
    assert data["round"] == 2
