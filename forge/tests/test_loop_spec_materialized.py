"""Matérialisation de `loop.json` (Gameplay Contract V2, GO Pierre 2026-08-22).

VERROU ABSOLU : `loop.json` est une PROJECTION DÉTERMINISTE de `prisme.json`,
écrite par l'EXÉCUTEUR (`run_real._materialize_loop_spec`) APRÈS que
`prisme.json` soit déjà sur disque — jamais par un LLM. Ce test vérifie que
cette matérialisation fonctionne sur un run_dir tmp synthétique (boucle
complète -> OK) ET sur la fixture RÉELLE du run 7 (kitten_clicker-20260821g,
commit 3843d7b : 8 exigences portent `loop_role`, boucle A..I atteinte, H et J
n'existent pas encore comme maillons -> steps non vides, verdict FAIL nommé,
JAMAIS une exception). Chemin non archivé (dernière run non déplacée sous
`_runN_...`) — la fixture a évolué depuis le run 6 d'origine (0 exigence
`loop_role`) ; ce test date du 2026-08-22 (lot Gameplay Contract T1) et mesure
l'état réel de ce fichier, pas un état figé.

    PYTHONPATH=scripts .venv312/Scripts/python.exe -m pytest \
        forge/tests/test_loop_spec_materialized.py -v
"""
from __future__ import annotations

import json
import pytest
from pathlib import Path

import forge.run_real as run_real

REPO_ROOT = Path(__file__).resolve().parents[2]
RUN7_PRISME = REPO_ROOT / "EVIDENCE" / "runs" / "kitten_clicker" / "_run8_20260821h2" / "prisme.json"  # archive run 8b (12 exigences de boucle, A..J, sans DECISION) ; le run_dir courant est purge entre deux runs


def _exigence(id_, role, **extra):
    return {
        "id": id_,
        "source": "ADDITIONS",
        "source_role": "prisme",
        "reference": None,
        "observation": f"observation {id_}",
        "claim": f"claim {id_}",
        "enonce": f"enonce {id_} distinct",
        "expected_proof": {"kind": "bot_action", "statement": f"preuve {id_}"},
        "destination": "s9-build",
        "loop_role": role,
        **extra,
    }


def _prisme_synthetique_complet() -> dict:
    # Gameplay Contract V2 (GO Pierre 2026-08-22) : 10 maillons A..J (C porte
    # par B) — G porte >= 2 exigences new_distinct sur le meme hud, H (REPEAT)
    # rejoue des refs B..F, J (ADVANTAGE) reference une ref B avec un predicat
    # increases_more_than: coherent, F porte observe.appears.
    return {
        "game_id": "kitten_clicker",
        "exigences": [
            _exigence("PG1", "PLAYER_GOAL", observe={"hud": "objectif", "predicate": "nonempty"}),
            _exigence("PA1", "PLAYER_ACTION", acteur="PLAYER", affordance="pelote", repeat=15,
                       observe={"hud": "ronrons", "predicate": "increases"}),
            _exigence("PA2", "PLAYER_ACTION", acteur="PLAYER", affordance="acheter_chaton",
                       observe={"hud": "collection", "predicate": "increases"}),
            _exigence("GR1", "GAME_RESPONSE", observe={"hud": "taux", "predicate": "increases", "wait_frames": 120}),
            _exigence("RW1", "REWARD", observe={"hud": "ronrons", "predicate": "increases", "wait_frames": 120}),
            _exigence("UN1", "UNLOCK", acteur="PLAYER", affordance="acheter_amelioration",
                       observe={"hud": "taux", "predicate": "increases", "appears": "affordance"}),
            _exigence("NG1", "NEXT_GOAL", observe={"hud": "objectif", "predicate": "new_distinct"}),
            _exigence("NG2", "NEXT_GOAL", observe={"hud": "objectif", "predicate": "new_distinct"}),
            _exigence("RP1", "REPEAT", replay=["PA1", "UN1"],
                       observe={"hud": "ronrons", "predicate": "increases"}),
            _exigence("ML1", "META_LOOP", acteur="PLAYER", affordance="prestige",
                       observe={"hud": "prestige", "predicate": "increases"}),
            _exigence("AD1", "ADVANTAGE", replay_ref="PA1",
                       observe={"hud": "ronrons", "predicate": "increases_more_than:PA1"}),
        ],
    }


def _prisme_synthetique_avec_decision() -> dict:
    # T1 (2026-08-23, extension DECISION — point de decision significative) :
    # meme fixture que _prisme_synthetique_complet, plus une exigence DECISION
    # entre REWARD et UNLOCK. options = PA1 (PLAYER_ACTION, affordance pelote)
    # et UN1 (UNLOCK, affordance acheter_amelioration), toutes deux existantes
    # ci-dessus ; metric='ronrons' est deja observe par PA1/RW1/RP1/AD1.
    prisme = _prisme_synthetique_complet()
    prisme["exigences"].append(_exigence(
        "DC1", "DECISION",
        options=["PA1", "UN1"],
        metric="ronrons",
        horizon_frames=300,
        policies=[
            {"name": "idle", "click": None, "every_frames": 0},
            {"name": "actif", "click": "pelote", "every_frames": 3},
        ],
        observe={"hud": "objectif", "predicate": "changes"},
    ))
    return prisme


def _ecrit_prisme(run_dir: Path, data: dict) -> None:
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "prisme.json").write_text(
        json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")


# --- (a) run_dir tmp synthétique : boucle complète -> loop.json OK -----------------
# T1 (2026-08-23, extension DECISION) : DECISION est desormais un maillon
# obligatoire de checkLoopSpec (loop_spec.mjs) — _prisme_synthetique_complet()
# (sans DECISION) n'atteint donc plus le verdict OK ; seul ce probleme apparait,
# le reste de la boucle A..J reste valide. Cf. _prisme_synthetique_avec_decision
# pour le cas pleinement complet (verdict OK).

def test_prisme_synthetique_complet_sans_decision_materialise_loop_json_fail_uniquement_sur_decision(tmp_path):
    run_dir = tmp_path / "run"
    _ecrit_prisme(run_dir, _prisme_synthetique_complet())

    recu = run_real._materialize_loop_spec("s1-prisme", run_dir)

    assert recu is not None
    assert recu["written"] is True, recu
    loop_path = run_dir / "loop.json"
    assert loop_path.exists()
    data = json.loads(loop_path.read_text(encoding="utf-8"))
    assert isinstance(data, dict)
    assert isinstance(data.get("steps"), list)
    assert len(data["steps"]) == 11
    assert recu["check"]["verdict"] == "FAIL"
    assert recu["check"]["problems"] == [
        "maillon DECISION : au moins 1 exigence attendue (0 trouvee)"
    ]


def test_ordre_des_etapes_respecte_la_sequence_imposee(tmp_path):
    run_dir = tmp_path / "run"
    _ecrit_prisme(run_dir, _prisme_synthetique_complet())
    run_real._materialize_loop_spec("s1-prisme", run_dir)
    data = json.loads((run_dir / "loop.json").read_text(encoding="utf-8"))
    roles = [s["role"] for s in data["steps"]]
    assert roles == [
        "PLAYER_GOAL", "PLAYER_ACTION", "PLAYER_ACTION", "GAME_RESPONSE",
        "REWARD", "UNLOCK", "NEXT_GOAL", "NEXT_GOAL", "REPEAT", "META_LOOP",
        "ADVANTAGE",
    ]


# --- (a bis) run_dir tmp synthétique + DECISION : boucle pleinement complète -> OK --

def test_prisme_synthetique_avec_decision_materialise_loop_json_ok(tmp_path):
    run_dir = tmp_path / "run"
    _ecrit_prisme(run_dir, _prisme_synthetique_avec_decision())

    recu = run_real._materialize_loop_spec("s1-prisme", run_dir)

    assert recu is not None
    assert recu["written"] is True, recu
    loop_path = run_dir / "loop.json"
    data = json.loads(loop_path.read_text(encoding="utf-8"))
    assert len(data["steps"]) == 12
    assert recu["check"]["verdict"] == "OK"
    assert recu["check"]["problems"] == []

    decision_step = next((s for s in data["steps"] if s["role"] == "DECISION"), None)
    assert decision_step is not None, "le step DECISION doit etre materialise dans loop.json"
    assert decision_step["ref"] == "DC1"
    assert decision_step["options"] == ["PA1", "UN1"]
    assert decision_step["metric"] == "ronrons"
    assert decision_step["horizon_frames"] == 300
    assert decision_step["policies"] == [
        {"name": "idle", "click": None, "every_frames": 0},
        {"name": "actif", "click": "pelote", "every_frames": 3},
    ]
    assert decision_step["observe"]["hud"] == "objectif"

    # position : entre REWARD et UNLOCK dans la sequence imposee.
    roles = [s["role"] for s in data["steps"]]
    assert roles.index("REWARD") < roles.index("DECISION") < roles.index("UNLOCK")


# --- (b) fixture RÉELLE run 7 : boucle incomplete -> steps non vides, FAIL, jamais une exception --
# Mesure du 2026-08-23 (lot T1, extension DECISION) : le fichier a EVOLUE depuis
# la mesure d'origine (8 exigences, boucle A..I) — il porte maintenant 12
# exigences de boucle et satisfait deja A..J. Seul le maillon DECISION
# (2026-08-23, absent de ce run anterieur a son introduction) manque desormais.
# Ce test mesure l'etat REEL du fichier, pas un etat fige (cf. docstring de tete).

def test_run7_reel_materialise_loop_json_fail_sans_exception(tmp_path):
    if not RUN7_PRISME.exists():
        pytest.skip(f"archive run 8b absente : {RUN7_PRISME}")
    run_dir = tmp_path / "run"
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "prisme.json").write_bytes(RUN7_PRISME.read_bytes())

    recu = run_real._materialize_loop_spec("s1-prisme", run_dir)  # ne doit JAMAIS lever

    assert recu is not None
    assert recu["written"] is True, recu
    loop_path = run_dir / "loop.json"
    assert loop_path.exists()
    data = json.loads(loop_path.read_text(encoding="utf-8"))
    assert len(data["steps"]) == 12
    assert recu["check"]["verdict"] == "FAIL"
    assert recu["check"]["problems"] == [
        "maillon DECISION : au moins 1 exigence attendue (0 trouvee)"
    ]


# --- (c) garde-fous ------------------------------------------------------------------

def test_etape_non_s1_prisme_ne_produit_aucun_recu(tmp_path):
    run_dir = tmp_path / "run"
    _ecrit_prisme(run_dir, _prisme_synthetique_complet())
    assert run_real._materialize_loop_spec("s3-decompo", run_dir) is None
    assert not (run_dir / "loop.json").exists()


def test_prisme_absent_recu_honnete_sans_ecriture(tmp_path):
    run_dir = tmp_path / "run"
    run_dir.mkdir(parents=True, exist_ok=True)
    recu = run_real._materialize_loop_spec("s1-prisme", run_dir)
    assert recu is not None
    assert recu["written"] is False
    assert not (run_dir / "loop.json").exists()
