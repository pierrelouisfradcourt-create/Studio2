"""T3 (Lot F, plan `2026-08-23-forge-lot-f-boucle-completion-mutuelle.md` §T3) :
`design_state` (calculé après chaque étape de la boucle Art<->GM, id de base ∈
{s2.5-artbible, s2.7-gm-worldscan}, toute ronde). Patron `test_driver_loop_gate.py`
(`ForgeDriver.__new__` pour les méthodes pures) + `test_driver_lot_b_gates_heritage.py`
(run() réel, exécuteur stub) pour l'intégration. `_base_step` est une copie locale
PRIVÉE (T1, alias d'étape, tourne EN PARALLÈLE sur contract.py — non touché
ici) : elle sera dédoublonnée par l'orchestrateur une fois T1 mergé.

ADAPTÉ Lot C.4-code (2026-08-24, plan `2026-08-24-forge-lot-c4-code-boucles.md`) :
la gate `design_freeze` elle-même (9 boucles GM, COMPLETE/OPEN/PROPOSED/DEFERRED,
R1 étendu, R3-lite) est RÉÉCRITE et testée ici ; ses assertions sur l'ANCIEN
comportement (freeze basé sur `ready_for_freeze`/`blocking_gaps` global seuls, sans
notion de boucle) ont été remplacées par des fixtures gm 9-boucles. Les tests
NOUVEAUX et plus détaillés (statut par boucle, R3-lite, deferred_loops.json,
heritage au freeze) vivent dans `test_c4_design_state_freeze.py` — ce fichier garde
la couverture RUN() minimale (a)/(b)/(c convergée, blocking, ready) pour la
non-régression du câblage `run()` -> gate -> s1-prisme.
"""
import json
import sys
from pathlib import Path

import pytest

from forge.driver import ForgeDriver


def _driver_minimal(run_dir: Path, order=()) -> ForgeDriver:
    d = ForgeDriver.__new__(ForgeDriver)  # pas de __init__ : méthodes pures seulement
    d.run_id = "r1"
    d.project = "proj"
    d.profile = "full"
    d.run_dir = run_dir
    d.order = list(order)
    d.state_path = run_dir / "state.json"
    return d


# --- _base_step (copie locale privée, T1 hors périmètre) --------------------


def test_base_step_strip_round_suffix():
    assert ForgeDriver._base_step("s2.5-artbible-r2") == "s2.5-artbible"
    assert ForgeDriver._base_step("s2.7-gm-worldscan-r2") == "s2.7-gm-worldscan"


def test_base_step_identite_sans_suffixe():
    assert ForgeDriver._base_step("s2.5-artbible") == "s2.5-artbible"
    assert ForgeDriver._base_step("s1-prisme") == "s1-prisme"


# --- _design_loop_active -----------------------------------------------------


def test_design_loop_active_vrai_si_s27_dans_order(tmp_path):
    d = _driver_minimal(tmp_path, order=["s2.5-artbible", "s2.7-gm-worldscan", "s1-prisme"])
    assert d._design_loop_active() is True


def test_design_loop_active_vrai_avec_alias_r2(tmp_path):
    d = _driver_minimal(tmp_path, order=["s2.7-gm-worldscan-r2", "s1-prisme"])
    assert d._design_loop_active() is True


def test_design_loop_active_faux_profil_sans_boucle(tmp_path):
    d = _driver_minimal(tmp_path, order=["s9-build", "s10a-oracle-code", "s12-verdict"])
    assert d._design_loop_active() is False


# --- _compute_design_state, pure, jamais d'exception -------------------------


def _write_questions(run_dir: Path, payload: dict) -> None:
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "design_questions.json").write_text(
        json.dumps(payload, ensure_ascii=False), encoding="utf-8")


# 9 boucles GM figées (vocabulaire du plan C.4) — fixture LOCALE (Agent B, jamais
# le format réel produit par `game_master_schema.mjs`, hors périmètre ici).
_LOOPS_9 = (
    "core_loop", "gameplay_loop", "progression_loop", "content_loop",
    "economy_loop", "skill_loop", "world_loop", "quest_loop", "meta_loop",
)


def _valid_gm_nine_loops() -> dict:
    """Anneau de 9 boucles où chaque `produces` est consommé par la suivante,
    chaque `unlocks` pointe vers une boucle réelle, `transformation_perceptible`
    et `metric_propre` complets et exclusifs -> les 9 boucles sont COMPLETE."""
    n = len(_LOOPS_9)
    loops = {}
    for i, name in enumerate(_LOOPS_9):
        prev_name = _LOOPS_9[(i - 1) % n]
        next_name = _LOOPS_9[(i + 1) % n]
        loops[name] = {
            "steps": [],
            "produces": f"p_{name}",
            "consumes": [prev_name],  # noms de boucles (semantique mjs)
            "unlocks": [next_name],
            "transformation_perceptible": {
                "text": f"transformation perceptible de {name}",
                "proof_ref": f"proof_{name}",
            },
            "metric_propre": f"m_{name}",
        }
    return {"game_master": {"loops": loops}}


def _write_gm(run_dir: Path, payload: dict) -> None:
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "gm_worldscan.json").write_text(
        json.dumps(payload, ensure_ascii=False), encoding="utf-8")


def test_compute_design_state_absent_jamais_une_exception(tmp_path):
    d = _driver_minimal(tmp_path)
    ds = d._compute_design_state()
    assert ds["round"] is None
    assert ds["ready_for_freeze"] == {"ART": False, "GM": False}
    assert ds["shared_design_pct"] is None
    assert ds["note"] == "design_questions.json absent"


def test_compute_design_state_json_invalide_jamais_une_exception(tmp_path):
    d = _driver_minimal(tmp_path)
    tmp_path.mkdir(parents=True, exist_ok=True)
    (tmp_path / "design_questions.json").write_text("{ not json", encoding="utf-8")
    ds = d._compute_design_state()
    assert ds["ready_for_freeze"] == {"ART": False, "GM": False}
    assert "note" in ds


def test_compute_design_state_convergee_2_questions_2_reponses(tmp_path):
    d = _driver_minimal(tmp_path)
    _write_questions(tmp_path, {
        "schema_version": 1, "round": 2,
        "questions": [
            {"id": "q_art_001", "from": "ART", "to": "GM", "round": 1,
             "about": "x", "missing": [], "why": "y", "blocking": True,
             "answer": {"round": 2, "by": "GM", "ref": "gm_worldscan:x", "text": "..."}},
            {"id": "q_gm_001", "from": "GM", "to": "ART", "round": 1,
             "about": "grey_blocks.garden", "missing": [], "why": "z", "blocking": True,
             "answer": {"round": 2, "by": "ART", "ref": "art_bible:x", "text": "..."}},
        ],
        "declarations": {
            "ART": {"round": 2, "ready_for_freeze": True, "open_to_gm": 0},
            "GM": {"round": 2, "ready_for_freeze": True, "open_to_art": 0},
        },
    })
    ds = d._compute_design_state()
    assert ds["round"] == 2
    assert ds["asked"] == 2
    assert ds["answered"] == 2
    assert ds["blocking_gaps"] == 0
    assert ds["open_questions"] == {"ART_to_GM": 0, "GM_to_ART": 0}
    assert ds["ready_for_freeze"] == {"ART": True, "GM": True}
    assert ds["status"] == {"ART": "READY", "GM": "READY"}
    assert ds["shared_design_pct"] == 100
    assert "note" not in ds


def test_compute_design_state_une_blocking_sans_reponse(tmp_path):
    d = _driver_minimal(tmp_path)
    _write_questions(tmp_path, {
        "schema_version": 1, "round": 1,
        "questions": [
            {"id": "q_gm_001", "from": "GM", "to": "ART", "round": 1,
             "about": "grey_blocks.garden", "missing": [], "why": "z", "blocking": True,
             "answer": None},
        ],
        "declarations": {
            "ART": {"round": 1, "ready_for_freeze": False, "open_to_gm": 0},
            "GM": {"round": 1, "ready_for_freeze": True, "open_to_art": 1},
        },
    })
    ds = d._compute_design_state()
    assert ds["blocking_gaps"] == 1
    assert ds["open_questions"] == {"ART_to_GM": 0, "GM_to_ART": 1}
    assert ds["answered"] == 0
    assert ds["asked"] == 1
    assert ds["shared_design_pct"] == 0


def test_compute_design_state_zero_question_pct_null(tmp_path):
    d = _driver_minimal(tmp_path)
    _write_questions(tmp_path, {
        "schema_version": 1, "round": 1, "questions": [],
        "declarations": {
            "ART": {"round": 1, "ready_for_freeze": True, "open_to_gm": 0},
            "GM": {"round": 1, "ready_for_freeze": True, "open_to_art": 0},
        },
    })
    ds = d._compute_design_state()
    assert ds["asked"] == 0
    assert ds["shared_design_pct"] is None
    assert ds["ready_for_freeze"] == {"ART": True, "GM": True}


# --- _record_design_state_best_effort : id de base + alias -r<N> ------------


def test_record_design_state_seulement_pour_bases_de_la_boucle(tmp_path):
    run_dir = tmp_path / "run"
    d = _driver_minimal(run_dir)
    state = {"steps": {"s0-contrat": {"status": "OK", "detail": {}}}}
    d._record_design_state_best_effort(state, "s0-contrat")
    assert "design_state" not in state["steps"]["s0-contrat"]["detail"]
    assert not (run_dir / "design_state.json").exists()


def test_record_design_state_apres_s25_artbible_r2_alias(tmp_path):
    """(f) : `design_state.json` écrit après une étape `s2.5-artbible-r2`
    (alias) — la reconnaissance passe par `_base_step`, pas une égalité de
    chaîne exacte."""
    run_dir = tmp_path / "run"
    d = _driver_minimal(run_dir)
    _write_questions(run_dir, {
        "schema_version": 1, "round": 2,
        "questions": [{"id": "q1", "from": "ART", "to": "GM", "round": 1,
                        "about": "x", "missing": [], "why": "y", "blocking": False,
                        "answer": {"round": 2, "by": "GM", "ref": "r", "text": "t"}}],
        "declarations": {
            "ART": {"round": 2, "ready_for_freeze": True, "open_to_gm": 0},
            "GM": {"round": 2, "ready_for_freeze": True, "open_to_art": 0},
        },
    })
    state = {"steps": {"s2.5-artbible-r2": {"status": "OK", "detail": {}}}}
    d._record_design_state_best_effort(state, "s2.5-artbible-r2")
    assert state["steps"]["s2.5-artbible-r2"]["detail"]["design_state"]["asked"] == 1
    assert state["design_state"]["asked"] == 1
    on_disk = json.loads((run_dir / "design_state.json").read_text(encoding="utf-8"))
    assert on_disk["asked"] == 1
    # LF préservé (jamais de CRLF introduit par l'écriture du driver)
    raw = (run_dir / "design_state.json").read_bytes()
    assert b"\r\n" not in raw


# --- _design_freeze_gate, pure (state mutable, pas de vrai run()) -----------


def _driver_for_gate(tmp_path, order):
    run_dir = tmp_path / "run"
    d = _driver_minimal(run_dir, order=order)
    return d


def test_design_freeze_gate_none_si_profil_sans_s27(tmp_path):
    d = _driver_for_gate(tmp_path, ["s1-prisme"])
    state = {"steps": {"s1-prisme": {"status": "PENDING"}}}
    assert d._design_freeze_gate(state) is None
    assert "design_freeze" not in state


def test_design_freeze_gate_passed_true_convergee(tmp_path):
    """9 boucles COMPLETE (fixture en anneau) + 0 question ouverte + deferred
    absent -> la gate passe, `heritage/` est écrit AU FREEZE (avant s1)."""
    d = _driver_for_gate(tmp_path, ["s2.7-gm-worldscan", "s1-prisme"])
    d.run_dir.mkdir(parents=True, exist_ok=True)
    d.state_path = d.run_dir / "state.json"
    d.game_dir = tmp_path / "game"  # non consulté par le freeze (pas de project.godot requis)
    _write_gm(d.run_dir, _valid_gm_nine_loops())
    _write_questions(d.run_dir, {
        "schema_version": 1, "round": 1, "questions": [],
        "declarations": {
            "ART": {"round": 1, "ready_for_freeze": True, "open_to_gm": 0},
            "GM": {"round": 1, "ready_for_freeze": True, "open_to_art": 0},
        },
    })
    state = {"steps": {"s1-prisme": {"status": "PENDING"}}}
    assert d._design_freeze_gate(state) is None
    assert state["design_freeze"]["passed"] is True
    assert state["design_freeze"]["shared_design_pct"] == 100
    for name in _LOOPS_9:
        assert state["design_freeze"]["loops"][name]["status"] == "COMPLETE"
    assert (d.run_dir / "heritage" / "gm_worldscan.json").is_file()


def test_design_freeze_gate_halted_boucle_open(tmp_path):
    """Une question bloquante portant `loop_id=world_loop` sans réponse ->
    world_loop OPEN(1), gate HALTED, la boucle est nommée dans la raison."""
    d = _driver_for_gate(tmp_path, ["s2.7-gm-worldscan", "s1-prisme"])
    d.run_dir.mkdir(parents=True, exist_ok=True)
    d.state_path = d.run_dir / "state.json"
    _write_gm(d.run_dir, _valid_gm_nine_loops())
    _write_questions(d.run_dir, {
        "schema_version": 1, "round": 2,
        "questions": [
            {"id": "q_gm_042", "from": "GM", "to": "ART", "round": 2, "about": "x",
             "loop_id": "world_loop",
             "missing": [], "why": "y", "blocking": True, "answer": None},
        ],
        "declarations": {
            "ART": {"round": 2, "ready_for_freeze": False, "open_to_gm": 0},
            "GM": {"round": 2, "ready_for_freeze": True, "open_to_art": 1},
        },
    })
    state = {"steps": {"s1-prisme": {"status": "PENDING"}}}
    report = d._design_freeze_gate(state)
    assert report is not None
    assert report["status"] == "HALTED"
    assert "design non convergé" in report["reason"]
    assert "world_loop: OPEN(1)" in report["reason"]
    assert state["design_freeze"]["passed"] is False
    assert state["run_status"] == "HALTED"


def test_design_freeze_gate_halted_ready_false_dun_cote(tmp_path):
    """R1 étendu : ART ne se déclare pas ready -> HALTED nommant ART parmi les
    piliers en défaut, même si les 9 boucles sont par ailleurs COMPLETE."""
    d = _driver_for_gate(tmp_path, ["s2.7-gm-worldscan", "s1-prisme"])
    d.run_dir.mkdir(parents=True, exist_ok=True)
    d.state_path = d.run_dir / "state.json"
    _write_gm(d.run_dir, _valid_gm_nine_loops())
    _write_questions(d.run_dir, {
        "schema_version": 1, "round": 2,
        "questions": [],
        "declarations": {
            "ART": {"round": 2, "ready_for_freeze": False, "open_to_gm": 0},
            "GM": {"round": 2, "ready_for_freeze": True, "open_to_art": 0},
        },
    })
    state = {"steps": {"s1-prisme": {"status": "PENDING"}}}
    report = d._design_freeze_gate(state)
    assert report is not None
    assert "R1 étendu" in report["reason"]
    assert "ART" in report["reason"]


def test_design_freeze_gate_halted_fichier_absent(tmp_path):
    d = _driver_for_gate(tmp_path, ["s2.7-gm-worldscan-r2", "s1-prisme"])
    d.run_dir.mkdir(parents=True, exist_ok=True)
    d.state_path = d.run_dir / "state.json"
    state = {"steps": {"s1-prisme": {"status": "PENDING"}}}
    report = d._design_freeze_gate(state)
    assert report is not None
    assert report["status"] == "HALTED"
    assert "design non convergé" in report["reason"]
    assert state["design_freeze"]["passed"] is False


# --- intégration run() réel : (a) convergée -> s1 tourne, (b)/(c) HALTED -----
# Patron `test_driver_loop_gate.py` (fixture offline + _kwargs + executor stub).


@pytest.fixture
def offline(monkeypatch):
    monkeypatch.setattr("forge.runtime.qwen_available", lambda *a, **k: False)


def _oracle_config(tmp_path, project="proj", exit_code=0):
    script = f"import sys; sys.exit({exit_code})"
    cfg = tmp_path / "oracles.json"
    cfg.write_text(
        json.dumps({project: {"cwd": str(tmp_path),
                              "command": [sys.executable, "-c", script]}}),
        encoding="utf-8")
    return cfg


def _kwargs(tmp_path, run_dir):
    return dict(
        run_dir=run_dir,
        oracle_config=_oracle_config(tmp_path),
        key_file=tmp_path / "forge_test.key",
        audit_path=tmp_path / "audit.jsonl",
        telemetry_path=tmp_path / "telemetry.jsonl",
        builder_runs_path=tmp_path / "builder_runs.jsonl",
        run_index_path=tmp_path / "RUN_INDEX.md",
    )


class _StubExecutor:
    """Exécuteur factice : ne matérialise rien, rend juste un `ok: True` — les
    tests de ce fichier écrivent `design_questions.json` DIRECTEMENT dans
    run_dir (rôle du matérialiseur, hors périmètre T3 : le driver COMPTE, il
    ne PRODUIT ni ne VALIDE la forme)."""

    def __init__(self):
        self.calls: list[str] = []

    def __call__(self, payload, decision, context):
        self.calls.append(payload.etape)
        return {"ok": True, "output": f"artefact {payload.etape}"}


def _register_synthetic_profile(monkeypatch, name, order):
    """Enregistre un profil de TEST dans `forge.dispatch.PROFILES` (monkeypatch
    RUNTIME, aucune écriture sur dispatch.py — restauré automatiquement en fin
    de test). Nécessaire pour que `prepare_dispatch`
    (`profile_allowed_for_contract` -> `order_for_profile(profile)`) accepte
    les étapes de la boucle synthétique SANS `allow_unprofiled=True` — le
    driver appelle `prepare_dispatch` sans ce flag (comportement PRODUCTION
    inchangé), donc le profil déclaré doit réellement correspondre à
    `self.order` pour que le dispatch les accepte."""
    import forge.dispatch as dispatch_mod
    monkeypatch.setitem(dispatch_mod.PROFILES, name, tuple(order))


def _run_synthetic_loop(tmp_path, questions_payload, monkeypatch,
                         order=("s2.5-artbible", "s2.7-gm-worldscan", "s1-prisme"),
                         gm_payload=None):
    """Construit un driver réel sur un profil de TEST dont l'ordre est
    EXACTEMENT la boucle synthétique (contrats réels s2.5-artbible /
    s2.7-gm-worldscan / s1-prisme — tous dispatchables individuellement via
    leurs profils dédiés `artbible`/`gm_worldscan`/`full`) — run() RÉEL,
    exécuteur stub, aucun sous-processus, aucun builder Godot requis (le run
    HALTE ou s'arrête juste après s1-prisme dans ces tests). `gm_payload`
    (Lot C.4-code) : écrit `gm_worldscan.json` AVANT `run()` si fourni — le
    driver COMPTE, il ne PRODUIT ni ne VALIDE la forme (rôle du matérialiseur)."""
    run_dir = tmp_path / "run"
    executor = _StubExecutor()
    profile = "test_design_loop"
    _register_synthetic_profile(monkeypatch, profile, order)
    d = ForgeDriver("proj", "proj-1", profile=profile, executor=executor,
                     **_kwargs(tmp_path, run_dir))
    if questions_payload is not None:
        _write_questions(run_dir, questions_payload)
    if gm_payload is not None:
        _write_gm(run_dir, gm_payload)
    return d, executor


def _converged_questions(round_=2):
    return {
        "schema_version": 1, "round": round_,
        "questions": [
            {"id": "q1", "from": "ART", "to": "GM", "round": 1, "about": "x",
             "loop_id": "core_loop",
             "missing": [], "why": "y", "blocking": True,
             "answer": {"round": round_, "by": "GM", "ref": "r", "text": "t"}},
            {"id": "q2", "from": "GM", "to": "ART", "round": 1, "about": "z",
             "loop_id": "gameplay_loop",
             "missing": [], "why": "y", "blocking": False,
             "answer": {"round": round_, "by": "ART", "ref": "r2", "text": "t2"}},
        ],
        "declarations": {
            "ART": {"round": round_, "ready_for_freeze": True, "open_to_gm": 0},
            "GM": {"round": round_, "ready_for_freeze": True, "open_to_art": 0},
        },
    }


def test_a_run_converge_s1_tourne_design_freeze_passed(tmp_path, offline, monkeypatch):
    d, executor = _run_synthetic_loop(
        tmp_path, _converged_questions(), monkeypatch, gm_payload=_valid_gm_nine_loops())
    report = d.run()
    assert "s1-prisme" in executor.calls  # s1 A tourné
    assert report["design_freeze"]["passed"] is True
    assert report["design_freeze"]["shared_design_pct"] == 100
    state = json.loads((d.run_dir / "state.json").read_text(encoding="utf-8"))
    assert state["steps"]["s2.7-gm-worldscan"]["detail"]["design_state"]["asked"] == 2
    assert state["steps"]["s1-prisme"]["status"] == "OK"


def test_b_run_blocking_sans_reponse_halted_avant_s1(tmp_path, offline, monkeypatch):
    questions = {
        "schema_version": 1, "round": 1,
        "questions": [
            {"id": "q_gm_001", "from": "GM", "to": "ART", "round": 1,
             "about": "grey_blocks.garden", "loop_id": "world_loop",
             "missing": ["états visuels"], "why": "y",
             "blocking": True, "answer": None},
        ],
        "declarations": {
            "ART": {"round": 1, "ready_for_freeze": False, "open_to_gm": 0},
            "GM": {"round": 1, "ready_for_freeze": True, "open_to_art": 1},
        },
    }
    d, executor = _run_synthetic_loop(
        tmp_path, questions, monkeypatch, gm_payload=_valid_gm_nine_loops())
    report = d.run()
    assert report["status"] == "HALTED"
    assert "design non convergé" in report["reason"]
    assert "world_loop: OPEN(1)" in report["reason"]
    assert "s1-prisme" not in executor.calls  # s1 JAMAIS exécutée
    state = json.loads((d.run_dir / "state.json").read_text(encoding="utf-8"))
    assert state["steps"]["s1-prisme"]["status"] == "PENDING"


def test_c_run_ready_false_dun_cote_halted(tmp_path, offline, monkeypatch):
    questions = {
        "schema_version": 1, "round": 2,
        "questions": [],
        "declarations": {
            "ART": {"round": 2, "ready_for_freeze": True, "open_to_gm": 0},
            "GM": {"round": 2, "ready_for_freeze": False, "open_to_art": 0},
        },
    }
    d, executor = _run_synthetic_loop(
        tmp_path, questions, monkeypatch, gm_payload=_valid_gm_nine_loops())
    report = d.run()
    assert report["status"] == "HALTED"
    assert "R1 étendu" in report["reason"]
    assert "GM" in report["reason"]
    assert "s1-prisme" not in executor.calls


def test_d_run_fichier_absent_halted(tmp_path, offline, monkeypatch):
    d, executor = _run_synthetic_loop(tmp_path, None, monkeypatch)  # design_questions.json jamais écrit
    report = d.run()
    assert report["status"] == "HALTED"
    assert "design non convergé" in report["reason"]
    assert "s1-prisme" not in executor.calls


def test_e_run_profil_sans_s27_aucune_gate_s1_tourne(tmp_path, offline, monkeypatch):
    """(e) : un profil qui ne contient PAS d'étape de base s2.7-gm-worldscan
    (ex. patch / un ordre synthétique sans boucle) n'est jamais gaté — s1
    tourne sans qu'aucun `design_questions.json` n'existe."""
    run_dir = tmp_path / "run"
    executor = _StubExecutor()
    profile = "test_no_loop"
    _register_synthetic_profile(monkeypatch, profile, ("s1-prisme",))
    d = ForgeDriver("proj", "proj-1", profile=profile, executor=executor,
                     **_kwargs(tmp_path, run_dir))
    report = d.run()
    assert "s1-prisme" in executor.calls
    assert "design_freeze" not in report
    state = json.loads((run_dir / "state.json").read_text(encoding="utf-8"))
    assert "design_freeze" not in state
